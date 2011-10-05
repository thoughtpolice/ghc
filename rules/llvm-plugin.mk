# -----------------------------------------------------------------------------
#
# (c) 2011 The University of Glasgow
#
# This file is part of the GHC build system.
#
# To understand how the build system works and how to modify it, see
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Architecture
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Modifying
#
# -----------------------------------------------------------------------------

define llvm-plugin # args: $1 = dir, $2 = distdir

# Options
$1_$2_PLUGIN_BLD_OPTS=-D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS \
	-fno-exceptions -fno-rtti -fno-common -Wall \
	-L$$(LlvmLibDir) \
	-I$$(LlvmIncDir) \
	$$(LlvmLibOpts)

$1_$2_CPP_FILES    = $$(patsubst %,$1/%,$$($1_$2_LLVM_PLUGIN_SRC))
$1_$2_CPP_BASENAME = $$(basename $$($1_$2_CPP_FILES))

# Target platform
ifeq "$$(findstring darwin,$$(HOSTPLATFORM))" "darwin"
$1_$2_BLDDEP = $$($1_$2_CPP_BASENAME).dylib
$1_$2_EXTRA_BLD_OPTS = -dynamiclib
else ifeq "$$(findstring mingw,$$(HOSTPLATFORM))" "mingw"
$1_$2_BLDDEP = $$($1_$2_CPP_BASENAME).dll
$1_$2_EXTRA_BLD_OPTS = -shared
else ifeq "$$(findstring linux,$$(HOSTPLATFORM))" "linux"
$1_$2_BLDDEP = $$($1_$2_CPP_BASENAME).so
$1_$2_EXTRA_BLD_OPTS = -fPIC -shared
endif

# We set OUT to BLDDEP and define OUT as the rule invoking the CXX
# compiler, because if there is no llvm-config, then we don't want
# 'all' to do anything, so...
$1_$2_OUT = $$($1_$2_BLDDEP)

# Don't do anything if no llvm-config
ifeq "$$(WithLlvmConfig)" "NONE"
$1_$2_BLDDEP = 
endif

INSTALL_LIBS += $$($1_$2_BLDDEP)

all_$1 : $$($1_$2_BLDDEP)

$$($1_$2_OUT) : $$($1_$2_CPP_FILES)
	g++ $$($1_$2_PLUGIN_BLD_OPTS) $$($1_$2_EXTRA_BLD_OPTS) $$< -o $$@

clean_$1:
	rm -f $1/*.so $1/*.dll $1/*.dylib

endef
