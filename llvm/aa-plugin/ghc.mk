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

llvm/aa-plugin_dist_SRC = llvm/aa-plugin/GHCAliasAnalysis.cpp

# Determine the OS
ifeq "$(findstring darwin,$(HOSTPLATFORM))" "darwin"
llvm/aa-plugin_dist_LIBDEP = llvm/aa-plugin/GHCAliasAnalysis.dylib
else ifeq "$(findstring mingw,$(HOSTPLATFORM))" "mingw"
llvm/aa-plugin_dist_LIBDEP = llvm/aa-plugin/GHCAliasAnalysis.dll
else ifeq "$(findstring linux,$(HOSTPLATFORM))" "linux"
llvm/aa-plugin_dist_LIBDEP = llvm/aa-plugin/GHCAliasAnalysis.so
endif

# If we can't find LLVM config then we can't find the necessary
# library dirs etc to link with.
ifeq "$(WithLlvmConfig)" "NONE"
llvm/aa-plugin_dist_LIBDEP =
endif

all_llvm/aa-plugin : $(llvm/aa-plugin_dist_LIBDEP)

# -----------------------------------------------------------------------------
# Build rules for plugin
# 

llvm/aa-plugin_dist_LLVM_LIBDIR=$(shell $(WithLlvmConfig) --libdir)
llvm/aa-plugin_dist_LLVM_INCDIR=$(shell $(WithLlvmConfig) --includedir)
llvm/aa-plugin_dist_LLVM_LIBS=$(shell $(WithLlvmConfig) --libs)

llvm/aa-plugin_dist_PLUGIN_BLD_OPTS=-D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS \
	-fno-exceptions -fno-rtti -fno-common -Wall \
	-L$(llvm/aa-plugin_dist_LLVM_LIBDIR) \
	-I$(llvm/aa-plugin_dist_LLVM_INCDIR) \
	$(llvm/aa-plugin_dist_LLVM_LIBS)

llvm/aa-plugin/GHCAliasAnalysis.dylib: $(llvm/aa-plugin_dist_SRC)
	g++ -dynamiclib $(llvm/aa-plugin_dist_PLUGIN_BLD_OPTS) $< -o $@
llvm/aa-plugin/GHCAliasAnalysis.dll: $(llvm/aa-plugin_dist_SRC)
	g++ -fPIC -shared $(llvm/aa-plugin_dist_PLUGIN_BLD_OPTS) $< -o $@
llvm/aa-plugin/GHCAliasAnalysis.so: $(llvm/aa-plugin_dist_SRC)
	g++ -fPIC -shared $(llvm/aa-plugin_dist_PLUGIN_BLD_OPTS) $< -o $@

clean_llvm/aa-plugin:
	rm -f llvm/aa-plugin/*.dll  llvm/aa-plugin/*.so  llvm/aa-plugin/*.dylib
