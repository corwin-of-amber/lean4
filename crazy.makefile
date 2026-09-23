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

OBJ_DIR = obj

SRC_CPP = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLCPP)} crazy/stubs.cpp
SRC_C = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLC)}

MODIFIERS = -DLEAN_MULTI_THREAD -DLEAN_MULTI_THREAD_FRUGAL
MODIFIERS += -DLEAN_EMSCRIPTEN
MODIFIERS += -DAMBER -DLEAN_USE_POSIX_SPAWN -DLEAN_DEFAULT_INTERPRETER_PREFER_NATIVE=false
ifeq ($(STAGE),0)
MODIFIERS += -DLEAN_IS_STAGE0
endif

#MODIFIERS += -DLEAN_USE_GMP

# This is a special build mode that uses a C array as a table for
# native symbol lookup (see `ir_interpreter.cpp`).
ifeq ($(DLSYM),dyn)
SRC_C += crazy/dyn.c crazy/dyntable/crc.c
SRC_CPP += crazy/dyntable/dlsym_dyn.cpp
MODIFIERS += -DAMBER_DL_DYNTABLE
endif


OBJ = $(addprefix $(OBJ_DIR)/,$(SRC_CPP:.cpp=.o) $(SRC_C:.c=.o))

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
CFLAGS += -Oz -DLEAN_BUILD_TYPE="Release" -DNDEBUG

# For comparison: these are the full flags used by the cmake build
#CFLAGS = -I/opt/homebrew/Cellar/libuv/1.52.1/include -I/Users/corwin/var/ext/lean4/build/debug/stage0/include -I/Users/corwin/var/ext/lean4/stage0/src -I/Users/corwin/var/ext/lean4/build/debug/stage0 -D LEAN_USE_GMP   -D LEAN_MMAP -D LEAN_MULTI_THREAD -DLEAN_BUILD_TYPE="Release" -DLEAN_EXPORTING -D__CLANG__ -ftls-model=initial-exec -fvisibility=hidden -fvisibility-inlines-hidden -O3 -DNDEBUG -arch arm64

make-rec = $(MAKE) -f $(firstword $(MAKEFILE_LIST))


both: bin/lean bin/lake
.PHONY: both

bin/lean: $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o)) lib/liblean.a
	-@$(make-rec) lib/export-symbols.txt
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $+ $(LDFLAGS)

bin/lake: $(addprefix $(OBJ_DIR)/,$(SRC_LAKE_C:.c=.o)) lib/liblean.a
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $< -Llib -llean $(LDFLAGS)

lib/liblean.a: $(OBJ)
	@mkdir -p $(dir $@)
	ar r $@ $+

crazy/dyn.c:
	npx tsx crazy/extract-native-exports.ts dyn > $@
lib/export-symbols.txt:
	$(if $(filter dyn,$(DLSYM)),echo,\
	npx tsx crazy/extract-native-exports.ts link) > $@
lib/export-symbols-all.txt: lib/liblean.wa
	nm --defined-only -A $< | awk '$$NF ~ /^(runtime_|meta_)?initialize_|.*__boxed$$/ { print "-Wl,--export=" $$NF }' > $@
lib/liblean.wa:

$(OBJ_DIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	clang++ --std=c++20 -c $< -o $@ $(CFLAGS)
$(OBJ_DIR)/%.o: %.c
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

.PHONY: lib-init lib-init-%



define newline


endef
