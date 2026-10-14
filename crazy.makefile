#
# This makefile can be used to compile either Stage 0 or Stage 1.
# Building Stage 1 depends on having a bootstrapped build directory
# (`build/release/stage1`).
#
ifeq ($(STAGE),0)
ALLCPP := ${shell find stage0/src -name "*.cpp"}
ALLC := ${shell find stage0/stdlib -name "*.c"}
SRC_LEAN_CPP = stage0/src/shell/lean.cpp
SRC_LAKE_C = stage0/stdlib/LakeMain.c
INC = -Istage0/src -Istage0/src/include
else
STAGE := 1
ALLCPP := ${shell find src -name "*.cpp"}
ALLC := ${shell find build/release/stage1/lib/temp -name "*.c"}
SRC_LEAN_CPP = src/shell/lean.cpp
SRC_LAKE_C = build/release/stage1/lib/temp/LakeMain.c
INC = -Isrc -Isrc/include
endif

INC += -Icrazy -Icrazy/include

MAINS = LeanIR.c LeanChecker.c LakeMain.c Leanc.c shell/lean.cpp
EXCEPT = lean_js.cpp $(MAINS)

OPT ?= Oz
DLSYM ?= dyn
MIMALLOC ?= 1
MIMALLOC_DIR ?= build/release/mimalloc/src/mimalloc
BUILD_SUFFIX = $(if $(filter Oz,$(OPT)),,-$(OPT))$(if $(filter 1,$(MIMALLOC)),-mimalloc,)
LEAN_ARCHIVE = lib/liblean$(BUILD_SUFFIX).a
BUILD_MODE = obj/.crazy-build-mode

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
SRC_C += build/release/mimalloc/src/mimalloc/src/static.c
INC += -I$(MIMALLOC_DIR)/include -I$(MIMALLOC_DIR)/src
MIMALLOC_DEPS := $(shell find $(MIMALLOC_DIR)/src $(MIMALLOC_DIR)/include -type f 2>/dev/null)

obj/%/mimalloc/src/static.o: $(MIMALLOC_DEPS)
obj/%/mimalloc/src/static.o: CFLAGS += -include pthread.h -DMI_DEBUG=0 -DMI_SECURE=0 -DMI_USE_PTHREADS=1 -DMI_TLS_MODEL_LOCAL=1
endif

# This is a special build mode that uses a C array as a table for
# native symbol lookup (see `ir_interpreter.cpp`).
ifeq ($(DLSYM),dyn)
SRC_C += lib/dyn.c crazy/dyntable/crc.c
SRC_CPP += crazy/dyntable/dlsym_dyn.cpp
MODIFIERS += -DAMBER_DL_DYNTABLE
endif


OBJ = $(addprefix obj/,$(SRC_CPP:.cpp=.o) $(SRC_C:.c=.o))

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


both: bin/lean bin/lake
.PHONY: both

bin/lean: $(addprefix obj/,$(SRC_LEAN_CPP:.cpp=.o)) $(LEAN_ARCHIVE) $(BUILD_MODE)
	-@$(make-rec) lib/export-symbols.txt
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $(addprefix obj/,$(SRC_LEAN_CPP:.cpp=.o)) $(LEAN_ARCHIVE) $(LDFLAGS)

	@if [ -e bin/lean.wasm ] && [ -e build-wasmer-fs/usr/bin/lean ] ; then \
	  cp bin/lean.wasm build-wasmer-fs/usr/bin/lean ; fi    # this is easy to forget and it bites

bin/lake: $(addprefix obj/,$(SRC_LAKE_C:.c=.o)) $(LEAN_ARCHIVE) $(BUILD_MODE)
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $< $(LEAN_ARCHIVE) $(LDFLAGS)

$(LEAN_ARCHIVE): $(OBJ)
	@mkdir -p $(dir $@)
	ar r $@ $+

# The executable paths are shared, while objects and archives are per variant.
$(BUILD_MODE): FORCE
	@mkdir -p $(dir $@)
	@printf '%s\n' '$(BUILD_SUFFIX):$(MIMALLOC_DIR)' > $@.tmp
	@cmp -s $@.tmp $@ || mv $@.tmp $@
	@rm -f $@.tmp
.PHONY: FORCE
FORCE:

ifeq ($(MIMALLOC),1)
bin/mimalloc-probe: obj/tests/wasm/mimalloc.o obj/crazy/mimalloc.o $(BUILD_MODE)
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $(filter %.o,$^) $(LDFLAGS)

test-mimalloc: bin/mimalloc-probe
	wasmer run --stack-size=4000000 bin/mimalloc-probe.wasm
else
test-mimalloc:
	@echo 'Set MIMALLOC=1 to run the allocator probe.' >&2
	@exit 2
endif
.PHONY: test-mimalloc

lib/dyn.c:
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

obj/%.o: %.cpp
	@mkdir -p $(dir $@)
	clang++ --std=c++20 -c $< -o $@ $(CFLAGS)
obj/%.o: %.c
	@mkdir -p $(dir $@)
	clang -c $< -o $@ $(CFLAGS)

wasm-opt:
	wasm-opt bin/lean.wasm -Oz -o bin/lean.wasm
.PHONY: wasm-opt

build-wasmer-fs:
	rm -rf $@
	mkdir -p $@/home/init/src $@/usr/bin $@/etc $@/dev
	cp bin/lean.wasm              $@/usr/bin/lean
	cp crazy/init/lakefile.toml   $@/home/init
	cp /etc/localtime             $@/etc
	dd if=/dev/urandom of=$@/dev/urandom bs=1K count=1

lib-init:
	rm -rf tmp/init/build
	cd tmp/init && ../../bin/lake build Init
	cd lib && ln -s ../tmp/init/build/lib/lean .

lib-others:
	cd tmp/init && ../../bin/lake build Std Lean Lake

lib-init-fresh:
	rm -rf tmp/init; mkdir -p tmp/init/src
	cp crazy/init/lakefile.toml    tmp/init
	cp -r src/Init.lean src/Init   tmp/init/src
	cp -r src/Std.lean  src/Std    tmp/init/src
	cp -r src/Lean.lean src/Lean   tmp/init/src
	cp -r src/lake                 tmp/init/src
	$(make-rec) lib-init

WASMER_FLAGS = --stack-size=4000000
ifneq ($(J),)
WASMER_FLAGS += --env LEAN_NUM_THREADS=$(J)
endif
WASMER_FLAGS += ${foreach d, home usr dev,\$(newline) --volume build-wasmer-fs/$(d):/$(d)}

lib-init-wasm: build-wasmer-fs
	cp -r src/Init.lean src/Init build-wasmer-fs/home/init/src
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- build Init
	@$(make-rec) lib-init-wasm-tar

lib-std-wasm: build-wasmer-fs
	cp -r src/Std.lean src/Std build-wasmer-fs/home/init/src
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- build Std

lib-lean-wasm: build-wasmer-fs
	cp -r src/Lean.lean src/Lean build-wasmer-fs/home/init/src
	# splitting to two phases helps avoid crashes during CI...
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- build +Lean.Meta
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- build Lean

lib-lake-wasm: build-wasmer-fs
	cp -r src/lake build-wasmer-fs/home/init/src
	wasmer run $(WASMER_FLAGS) --cwd /home/init bin/lake.wasm -- build Lake

# Location of lib build artifacts (either `/home/init` or `/usr/lib`)
LIB_LEAN = $(wildcard \
	build-wasmer-fs/home/init/build/lib/lean build-wasmer-fs/usr/lib/lean)

LIB_LEAN_EXTS = .olean .ir .ir.sig
pats = $(addprefix *, ${LIB_LEAN_EXTS})
find_flags = $(subst $(E) -o @@,,$(foreach pat,$(pats),-name '$(pat)' -o) @@)

lib-init-wasm-tar:
	mkdir -p lib
	( cd ${LIB_LEAN} && \
	  tar cf ${PWD}/lib/Init.tar ${pats} `find Init ${find_flags}` )

lib-wasm-tars:
	$(make-rec) lib-init-wasm-tar
	( cd ${LIB_LEAN}/Std && \
	  tar cf ${PWD}/lib/Std.tar `find * ${find_flags}`)
	( cd ${LIB_LEAN}/Lean && \
	  tar cf ${PWD}/lib/Lean.tar `find * ${find_flags}`)
	( cd ${LIB_LEAN}/Lake && \
	  tar cf ${PWD}/lib/Lake.tar `find * ${find_flags}`)

lib-wasm-tar:  # huge file
	mkdir -p lib
	( cd ${LIB_LEAN} && \
	  tar cf ${PWD}/lib/lib32.tar `find * ${find_flags}` )

lib-wasm-extra-tar:  # extra huge file
	mkdir -p lib
	( cd ${LIB_LEAN} && \
	  tar cf ${PWD}/lib/lib+extra32.tar `find * -name '*.olean.*'` )

lib-wasm-install:
	mkdir -p build-wasmer-fs/usr/lib
	cp -r build-wasmer-fs/home/init/build/lib/lean build-wasmer-fs/usr/lib

.PHONY: lib-init lib-init-%



define newline


endef
