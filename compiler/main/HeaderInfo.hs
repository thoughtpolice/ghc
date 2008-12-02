-----------------------------------------------------------------------------
--
-- | Parsing the top of a Haskell source file to get its module name,
-- imports and options.
--
-- (c) Simon Marlow 2005
-- (c) Lemmih 2006
--
-----------------------------------------------------------------------------

module HeaderInfo ( getImports
                  , getOptionsFromFile, getOptions
                  , optionsErrorMsgs,
                    checkProcessArgsResult ) where

#include "HsVersions.h"

import RdrName
import HscTypes
import Parser		( parseHeader )
import Lexer
import FastString
import HsSyn		( ImportDecl(..), HsModule(..) )
import Module		( ModuleName, moduleName )
import PrelNames        ( gHC_PRIM, mAIN_NAME )
import StringBuffer	( StringBuffer(..), hGetStringBufferBlock
                        , appendStringBuffers )
import SrcLoc
import DynFlags
import ErrUtils
import Util
import Outputable
import Pretty           ()
import Maybes
import Bag		( emptyBag, listToBag, unitBag )

import MonadUtils       ( MonadIO )
import Exception
import Control.Monad
import System.IO
import Data.List

------------------------------------------------------------------------------

-- | Parse the imports of a source file.
--
-- Throws a 'SourceError' if parsing fails.
getImports :: GhcMonad m =>
              DynFlags
           -> StringBuffer -- ^ Parse this.
           -> FilePath     -- ^ Filename the buffer came from.  Used for
                           --   reporting parse error locations.
           -> FilePath     -- ^ The original source filename (used for locations
                           --   in the function result)
           -> m ([Located (ImportDecl RdrName)], [Located (ImportDecl RdrName)], Located ModuleName)
              -- ^ The source imports, normal imports, and the module name.
getImports dflags buf filename source_filename = do
  let loc  = mkSrcLoc (mkFastString filename) 1 0
  case unP parseHeader (mkPState buf loc dflags) of
    PFailed span err -> parseError span err
    POk pst rdr_module -> do
      let ms@(warns, errs) = getMessages pst
      logWarnings warns
      if errorsFound dflags ms
        then liftIO $ throwIO $ mkSrcErr errs
        else
	  case rdr_module of
	    L _ (HsModule mb_mod _ imps _ _ _ _) ->
	      let
                main_loc = mkSrcLoc (mkFastString source_filename) 1 0
		mod = mb_mod `orElse` L (srcLocSpan main_loc) mAIN_NAME
	        (src_idecls, ord_idecls) = partition (ideclSource.unLoc) imps
		ordinary_imps = filter ((/= moduleName gHC_PRIM) . unLoc . ideclName . unLoc) 
					ord_idecls
		     -- GHC.Prim doesn't exist physically, so don't go looking for it.
	      in
	      return (src_idecls, ordinary_imps, mod)
  
parseError :: GhcMonad m => SrcSpan -> Message -> m a
parseError span err = throwOneError $ mkPlainErrMsg span err

--------------------------------------------------------------
-- Get options
--------------------------------------------------------------

-- | Parse OPTIONS and LANGUAGE pragmas of the source file.
--
-- Throws a 'SourceError' if flag parsing fails (including unsupported flags.)
getOptionsFromFile :: DynFlags
                   -> FilePath            -- ^ Input file
                   -> IO [Located String] -- ^ Parsed options, if any.
getOptionsFromFile dflags filename
    = Exception.bracket
	      (openBinaryFile filename ReadMode)
              (hClose)
              (\handle ->
                   do buf <- hGetStringBufferBlock handle blockSize
                      loop handle buf)
    where blockSize = 1024
          loop handle buf
              | len buf == 0 = return []
              | otherwise
              = case getOptions' dflags buf filename of
                  (Nothing, opts) -> return opts
                  (Just buf', opts) -> do nextBlock <- hGetStringBufferBlock handle blockSize
                                          newBuf <- appendStringBuffers buf' nextBlock
                                          if len newBuf == len buf
                                             then return opts
                                             else do opts' <- loop handle newBuf
                                                     return (opts++opts')

-- | Parse OPTIONS and LANGUAGE pragmas of the source file.
--
-- Throws a 'SourceError' if flag parsing fails (including unsupported flags.)
getOptions :: DynFlags
           -> StringBuffer -- ^ Input Buffer
           -> FilePath     -- ^ Source filename.  Used for location info.
           -> [Located String] -- ^ Parsed options.
getOptions dflags buf filename
    = case getOptions' dflags buf filename of
        (_,opts) -> opts

-- The token parser is written manually because Happy can't
-- return a partial result when it encounters a lexer error.
-- We want to extract options before the buffer is passed through
-- CPP, so we can't use the same trick as 'getImports'.
getOptions' :: DynFlags
            -> StringBuffer         -- Input buffer
            -> FilePath             -- Source file. Used for msgs only.
            -> ( Maybe StringBuffer -- Just => we can use more input
               , [Located String]   -- Options.
               )
getOptions' dflags buf filename
    = parseToks (lexAll (pragState dflags buf loc))
    where loc  = mkSrcLoc (mkFastString filename) 1 0

          getToken (_buf,L _loc tok) = tok
          getLoc (_buf,L loc _tok) = loc
          getBuf (buf,_tok) = buf
          combine opts (flag, opts') = (flag, opts++opts')
          add opt (flag, opts) = (flag, opt:opts)

          parseToks (open:close:xs)
              | IToptions_prag str <- getToken open
              , ITclose_prag       <- getToken close
              = map (L (getLoc open)) (words str) `combine`
                parseToks xs
          parseToks (open:close:xs)
              | ITinclude_prag str <- getToken open
              , ITclose_prag       <- getToken close
              = map (L (getLoc open)) ["-#include",removeSpaces str] `combine`
                parseToks xs
          parseToks (open:close:xs)
              | ITdocOptions str <- getToken open
              , ITclose_prag     <- getToken close
              = map (L (getLoc open)) ["-haddock-opts", removeSpaces str]
                `combine` parseToks xs
          parseToks (open:xs)
              | ITdocOptionsOld str <- getToken open
              = map (L (getLoc open)) ["-haddock-opts", removeSpaces str]
                `combine` parseToks xs
          parseToks (open:xs)
              | ITlanguage_prag <- getToken open
              = parseLanguage xs
          -- The last token before EOF could have been truncated.
          -- We ignore it to be on the safe side.
          parseToks [tok,eof]
              | ITeof <- getToken eof
              = (Just (getBuf tok),[])
          parseToks (eof:_)
              | ITeof <- getToken eof
              = (Just (getBuf eof),[])
          parseToks _ = (Nothing,[])
          parseLanguage ((_buf,L loc (ITconid fs)):rest)
              = checkExtension (L loc fs) `add`
                case rest of
                  (_,L _loc ITcomma):more -> parseLanguage more
                  (_,L _loc ITclose_prag):more -> parseToks more
                  (_,L loc _):_ -> languagePragParseError loc
                  [] -> panic "getOptions'.parseLanguage(1) went past eof token"
          parseLanguage (tok:_)
              = languagePragParseError (getLoc tok)
          parseLanguage []
              = panic "getOptions'.parseLanguage(2) went past eof token"
          lexToken t = return t
          lexAll state = case unP (lexer lexToken) state of
                           POk _      t@(L _ ITeof) -> [(buffer state,t)]
                           POk state' t -> (buffer state,t):lexAll state'
                           _ -> [(buffer state,L (last_loc state) ITeof)]

-----------------------------------------------------------------------------

-- | Complain about non-dynamic flags in OPTIONS pragmas.
--
-- Throws a 'SourceError' if the input list is non-empty claiming that the
-- input flags are unknown.
checkProcessArgsResult :: MonadIO m => [Located String] -> m ()
checkProcessArgsResult flags
  = when (notNull flags) $
      liftIO $ throwIO $ mkSrcErr $ listToBag $ map mkMsg flags
    where mkMsg (L loc flag)
              = mkPlainErrMsg loc $
                  (text "unknown flag in  {-# OPTIONS #-} pragma:" <+>
                   text flag)

-----------------------------------------------------------------------------

checkExtension :: Located FastString -> Located String
checkExtension (L l ext)
-- Checks if a given extension is valid, and if so returns
-- its corresponding flag. Otherwise it throws an exception.
 =  let ext' = unpackFS ext in
    if ext' `elem` supportedLanguages
       || ext' `elem` (map ("No"++) supportedLanguages)
    then L l ("-X"++ext')
    else unsupportedExtnError l ext'

languagePragParseError :: SrcSpan -> a
languagePragParseError loc =
  throw $ mkSrcErr $ unitBag $
     (mkPlainErrMsg loc $
       text "cannot parse LANGUAGE pragma: comma-separated list expected")

unsupportedExtnError :: SrcSpan -> String -> a
unsupportedExtnError loc unsup =
  throw $ mkSrcErr $ unitBag $
    mkPlainErrMsg loc $
        text "unsupported extension: " <> text unsup


optionsErrorMsgs :: [String] -> [Located String] -> FilePath -> Messages
optionsErrorMsgs unhandled_flags flags_lines _filename
  = (emptyBag, listToBag (map mkMsg unhandled_flags_lines))
  where	unhandled_flags_lines = [ L l f | f <- unhandled_flags, 
					  L l f' <- flags_lines, f == f' ]
        mkMsg (L flagSpan flag) = 
            ErrUtils.mkPlainErrMsg flagSpan $
                    text "unknown flag in  {-# OPTIONS #-} pragma:" <+> text flag

