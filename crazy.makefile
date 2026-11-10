.DEFAULT_GOAL := both
include crazy/platform.mk

crazy/platform.mk crazy/include/lean/version.h crazy/include/githash.h: crazy/platform.json crazy/configure.py
	python3 crazy/configure.py

#
# This makefile can be used to compile either Stage 0 or Stage 1.
# Building Stage 1 depends on having a bootstrapped build directory
# (`build/release/stage1`).
#
ifeq ($(STAGE),0)
CPP_ROOT = stage0/src
C_ROOT = stage0/stdlib
ALLCPP := ${shell find $(CPP_ROOT) -name "*.cpp"}
ALLC := ${shell find $(C_ROOT) -name "*.c"}
SRC_LEAN_CPP = stage0/src/shell/lean.cpp
SRC_LAKE_C = stage0/stdlib/LakeMain.c
INC = -Istage0/src -Istage0/src/include
else
STAGE := 1
CPP_ROOT = src
C_ROOT = build/release/stage1/lib/temp
ALLCPP := ${shell find $(CPP_ROOT) -name "*.cpp"}
ALLC := ${shell find $(C_ROOT) -name "*.c"}
SRC_LEAN_CPP = src/shell/lean.cpp
SRC_LAKE_C = build/release/stage1/lib/temp/LakeMain.c
INC = -Isrc -Isrc/include
endif

INC += -Icrazy -Icrazy/include

MAINS = LeanIR.c LeanChecker.c LeanExport.c LakeMain.c Leanc.c shell/lean.cpp
EXCEPT = lean_js.cpp $(MAINS)

OPT ?= Oz
DLSYM ?= dyn
MIMALLOC ?= 1
MIMALLOC_DIR ?= build/release/mimalloc/src/mimalloc
BACKEND ?= native
BUILD_SUFFIX = -$(BACKEND)-stage$(STAGE)-$(OPT)-$(DLSYM)$(if $(filter 1,$(MIMALLOC)),-mimalloc,)
OBJ_DIR = obj$(BUILD_SUFFIX)
LEAN_ARCHIVE = lib/liblean$(BUILD_SUFFIX).a
BUILD_MODE = obj/.crazy-build-mode
SOURCE_LIST = obj/.crazy-source-list
LEAN_BIN = bin/lean$(if $(filter wasm,$(BACKEND)),.wasm,)
LAKE_BIN = bin/lake$(if $(filter wasm,$(BACKEND)),.wasm,)
PROBE_BIN = bin/mimalloc-probe$(if $(filter wasm,$(BACKEND)),.wasm,)

SRC_CPP = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLCPP)} crazy/stubs.cpp
SRC_C = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLC)}

MODIFIERS = -DLEAN_MULTI_THREAD -DLEAN_MULTI_THREAD_FRUGAL
MODIFIERS += -DLEAN_EMSCRIPTEN
MODIFIERS += -DAMBER -DLEAN_USE_POSIX_SPAWN -DLEAN_DEFAULT_INTERPRETER_PREFER_NATIVE=false
ifeq ($(STAGE),0)
MODIFIERS += -DLEAN_IS_STAGE0
endif

#MODIFIERS += -DLEAN_USE_GMP

ifeq ($(MIMALLOC),1)
MODIFIERS += -DLEAN_MIMALLOC
MIMALLOC_OBJECT = $(OBJ_DIR)/crazy/mimalloc.o
INC += -I$(MIMALLOC_DIR)/include -I$(MIMALLOC_DIR)/src
MIMALLOC_DEPS := $(shell find $(MIMALLOC_DIR)/src $(MIMALLOC_DIR)/include -type f 2>/dev/null)

$(MIMALLOC_OBJECT): $(MIMALLOC_DIR)/src/static.c $(MIMALLOC_DEPS)
	@mkdir -p $(dir $@)
	clang -c $< -o $@ $(CFLAGS) -MMD -MP -MT$@ -MF $@.d -include pthread.h -DMI_DEBUG=0 -DMI_SECURE=0 -DMI_USE_PTHREADS=1 -DMI_TLS_MODEL_LOCAL=1
	@touch $@
endif

# This is a special build mode that uses a C array as a table for
# native symbol lookup (see `ir_interpreter.cpp`).
ifeq ($(DLSYM),dyn)
SRC_C += lib/dyn.c crazy/dyntable/crc.c
SRC_CPP += crazy/dyntable/dlsym_dyn.cpp
MODIFIERS += -DAMBER_DL_DYNTABLE
endif


OBJ = $(addprefix $(OBJ_DIR)/,$(SRC_CPP:.cpp=.o) $(SRC_C:.c=.o)) $(MIMALLOC_OBJECT)
ifeq ($(MIMALLOC),1)
$(OBJ) $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o) $(SRC_LAKE_C:.c=.o)): $(MIMALLOC_DIR)/include/mimalloc.h crazy/include/lean/mimalloc.h
endif

CFLAGS = $(MODIFIERS) $(INC)
LDFLAGS = # -L/opt/homebrew/lib -luv -lgmp

# - platform-dependent flags
OS := $(shell uname -s)
ifeq ($(OS), Linux)
    LDFLAGS += -rdynamic
endif

# dbg
#CFLAGS += -g -DLEAN_DEBUG
# opt
CFLAGS += -$(OPT) -DLEAN_BUILD_TYPE="Release" -DNDEBUG

# For comparison: these are the full flags used by the cmake build
#CFLAGS = -I/opt/homebrew/Cellar/libuv/1.52.1/include -I/Users/corwin/var/ext/lean4/build/debug/stage0/include -I/Users/corwin/var/ext/lean4/stage0/src -I/Users/corwin/var/ext/lean4/build/debug/stage0 -D LEAN_USE_GMP   -D LEAN_MMAP -D LEAN_MULTI_THREAD -DLEAN_BUILD_TYPE="Release" -DLEAN_EXPORTING -D__CLANG__ -ftls-model=initial-exec -fvisibility=hidden -fvisibility-inlines-hidden -O3 -DNDEBUG -arch arm64

TSX = crazy/node_modules/.bin/tsx

make-rec = $(MAKE) -f $(firstword $(MAKEFILE_LIST))


both: $(LEAN_BIN) $(LAKE_BIN)
.PHONY: both

$(LEAN_BIN): $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o)) $(LEAN_ARCHIVE) $(BUILD_MODE)
	-@$(make-rec) lib/export-symbols.txt
	@mkdir -p $(dir $@)
	clang++ -o bin/lean --std=c++20 $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o)) $(LEAN_ARCHIVE) $(LDFLAGS)

	@if [ -e bin/lean.wasm ] && [ -e build-wasmer-fs/usr/bin/lean ] ; then \
	  cp bin/lean.wasm build-wasmer-fs/usr/bin/lean ; fi    # this is easy to forget and it bites

$(LAKE_BIN): $(addprefix $(OBJ_DIR)/,$(SRC_LAKE_C:.c=.o)) $(LEAN_ARCHIVE) $(BUILD_MODE)
	@mkdir -p $(dir $@)
	clang++ -o bin/lake --std=c++20 $< $(LEAN_ARCHIVE) $(LDFLAGS)

$(LEAN_ARCHIVE): $(OBJ) $(SOURCE_LIST)
	@mkdir -p $(dir $@)
	rm -f $@ $(@:.a=.wa)
	ar r $@ $(filter %.o,$+)
	@touch $@

# Executables are shared; object and archive paths identify the configuration.
# Bypass wasi-kit’s mv wrapper for host-side bookkeeping files.
$(OBJ) $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o) $(SRC_LAKE_C:.c=.o)) $(OBJ_DIR)/tests/wasm/mimalloc.o: $(OBJ_DIR)/.build-flags
$(OBJ_DIR)/.build-flags: FORCE
	@mkdir -p $(dir $@)
	@printf '%s\n' '$(abspath $(MIMALLOC_DIR)):$(CFLAGS)' > $@.tmp
	@cmp -s $@.tmp $@ || /bin/mv $@.tmp $@
	@rm -f $@.tmp

$(BUILD_MODE): FORCE
	@mkdir -p $(dir $@)
	@printf '%s\n' '$(BUILD_SUFFIX):$(abspath $(MIMALLOC_DIR)):$(LDFLAGS)' > $@.tmp
	@cmp -s $@.tmp $@ || /bin/mv $@.tmp $@
	@rm -f $@.tmp
.PHONY: FORCE
FORCE:

ifeq ($(MIMALLOC),1)
$(PROBE_BIN): $(OBJ_DIR)/tests/wasm/mimalloc.o $(MIMALLOC_OBJECT) $(BUILD_MODE)
	@mkdir -p $(dir $@)
	clang++ -o bin/mimalloc-probe --std=c++20 $(filter %.o,$^) $(LDFLAGS)

test-mimalloc: $(PROBE_BIN)
	$(if $(filter wasm,$(BACKEND)),wasmer run --stack-size=$(WASMER_STACK_SIZE) bin/mimalloc-probe.wasm,./bin/mimalloc-probe)
else
test-mimalloc:
	@echo 'Set MIMALLOC=1 to run the allocator probe.' >&2
	@exit 2
endif
.PHONY: test-mimalloc

$(SOURCE_LIST): FORCE
	@mkdir -p $(dir $@)
	@find $(CPP_ROOT) $(C_ROOT) -type f \( -name '*.c' -o -name '*.cpp' \) | LC_ALL=C sort > $@.tmp
	@cmp -s $@.tmp $@ || /bin/mv $@.tmp $@
	@rm -f $@.tmp

lib/dyn.c: $(SOURCE_LIST) $(ALLC) crazy/extract-native-exports.ts crazy/dyntable/crc.ts
	@mkdir -p $(dir $@)
	$(TSX) crazy/extract-native-exports.ts dyn > $@
lib/export-symbols.txt:
	@mkdir -p $(dir $@)
	$(if $(filter dyn,$(DLSYM)),echo,\
	$(TSX) crazy/extract-native-exports.ts link) > $@
lib/export-symbols-all.txt: $(LEAN_ARCHIVE:.a=.wa)
	@mkdir -p $(dir $@)
	nm --defined-only -A $< | awk '$$NF ~ /^(runtime_|meta_)?initialize_|.*__boxed$$/ { print "-Wl,--export=" $$NF }' > $@
$(LEAN_ARCHIVE:.a=.wa):

$(OBJ_DIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	clang++ --std=c++20 -c $< -o $@ $(CFLAGS) -MMD -MP -MT$@ -MF $@.d
	@touch $@
$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	clang -c $< -o $@ $(CFLAGS) -MMD -MP -MT$@ -MF $@.d
	@touch $@

# These units embed the version or commit from the port's checked-in headers.
$(addprefix $(OBJ_DIR)/,src/util/shell.o src/library/util.o src/library/module.o src/runtime/platform.o src/runtime/exception.o build/release/stage1/lib/temp/Init/Meta/Defs.o): crazy/include/lean/version.h crazy/include/githash.h

wasm-opt:
	wasm-opt bin/lean.wasm -Oz -o bin/lean.wasm
.PHONY: wasm-opt

build-wasmer-fs:
	rm -rf $@
	mkdir -p $@/home/init/src $@/usr/bin $@/etc
	cp bin/lean.wasm              $@/usr/bin/lean
	cp crazy/init/lakefile.toml   $@/home/init
	cp /etc/localtime             $@/etc

# Refresh the bootstrap configuration without discarding completed libraries.
build-wasmer-fs/home/init/lakefile.toml: crazy/init/lakefile.toml | build-wasmer-fs
	cp $< $@

lib-init-wasm lib-std-wasm lib-lean-wasm lib-lake-wasm: build-wasmer-fs/home/init/lakefile.toml

lib-init:
	rm -rf tmp/init/build
	cd tmp/init && ../../bin/lake build Init
	cd lib && ln -s ../tmp/init/build/lib/lean .

lib-others:
	cd tmp/init && ../../bin/lake build Std Lean LeanExport Lake

lib-init-fresh:
	rm -rf tmp/init; mkdir -p tmp/init/src
	cp crazy/init/lakefile.toml    tmp/init
	cp -r src/Init.lean src/Init   tmp/init/src
	cp -r src/Std.lean  src/Std    tmp/init/src
	cp -r src/Lean.lean src/Lean   tmp/init/src
	cp -r src/lake src/LeanExport  tmp/init/src
	$(make-rec) lib-init

WASMER_FLAGS = --stack-size=$(WASMER_STACK_SIZE)
ifneq ($(J),)
WASMER_FLAGS += --env LEAN_NUM_THREADS=$(J)
endif
WASMER_FLAGS += ${foreach d, home usr,\$(newline) --volume build-wasmer-fs/$(d):/$(d)}

lib-init-wasm: build-wasmer-fs
	cp -r src/Init.lean src/Init build-wasmer-fs/home/init/src
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- --no-ansi build Init
	@$(make-rec) lib-init-wasm-tar

lib-std-wasm: build-wasmer-fs
	cp -r src/Std.lean src/Std build-wasmer-fs/home/init/src
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- --no-ansi build Std

lib-lean-wasm: build-wasmer-fs
	cp -r src/Lean.lean src/Lean build-wasmer-fs/home/init/src
	# splitting to two phases helps avoid crashes during CI...
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- --no-ansi build +Lean.Meta
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- --no-ansi build Lean

lib-lake-wasm: build-wasmer-fs
	cp -r src/lake src/LeanExport build-wasmer-fs/home/init/src
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- --no-ansi build Lake

# Location of lib build artifacts (either `/home/init` or `/usr/lib`)
LIB_LEAN = $(firstword $(wildcard \
	build-wasmer-fs/home/init/build/lib/lean build-wasmer-fs/usr/lib/lean))

LIB_LEAN_EXTS = .olean .olean.server .olean.private .ir .ir.sig
pats = $(addprefix *, ${LIB_LEAN_EXTS})
find_flags = $(subst $(E) -o @@,,$(foreach pat,$(pats),-name '$(pat)' -o) @@)

lib-init-wasm-tar:
	mkdir -p lib
	( cd ${LIB_LEAN} && \
	  tar cf $(CURDIR)/lib/Init.tar ${pats} `find Init ${find_flags}` )

lib-wasm-tars:
	$(make-rec) lib-init-wasm-tar
	( cd ${LIB_LEAN}/Std && \
	  tar cf $(CURDIR)/lib/Std.tar `find * ${find_flags}`)
	( cd ${LIB_LEAN}/Lean && \
	  tar cf $(CURDIR)/lib/Lean.tar `find * ${find_flags}`)
	( cd ${LIB_LEAN}/LeanExport && \
	  tar cf $(CURDIR)/lib/LeanExport.tar `find * ${find_flags}`)
	( cd ${LIB_LEAN}/Lake && \
	  tar cf $(CURDIR)/lib/Lake.tar `find * ${find_flags}`)

lib-wasm-tar:  # huge file
	mkdir -p lib
	( cd ${LIB_LEAN} && \
	  tar cf $(CURDIR)/lib/lib32.tar `find * ${find_flags}` )

lib-wasm-extra-tar:  # extra huge file
	mkdir -p lib
	( cd ${LIB_LEAN} && \
	  tar cf $(CURDIR)/lib/lib+extra32.tar `find * -name '*.olean.*'` )

lib-wasm-install:
	mkdir -p build-wasmer-fs/usr/lib
	cp -r build-wasmer-fs/home/init/build/lib/lean build-wasmer-fs/usr/lib

.PHONY: lib-init lib-init-%



define newline


endef

-include $(OBJ:%=%.d) $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o.d) $(SRC_LAKE_C:.c=.o.d))
