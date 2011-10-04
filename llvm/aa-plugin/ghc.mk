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

llvm/aa-plugin_dist_LLVM_PLUGIN_SRC = GHCAliasAnalysis.cpp
$(eval $(call llvm-plugin,llvm/aa-plugin,dist))
