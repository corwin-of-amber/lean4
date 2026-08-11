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
INC = -Istage0/src{,/include}
else
STAGE := 1
ALLCPP := ${shell find src -name "*.cpp"}
ALLC := ${shell find build/release/stage1/lib/temp -name "*.c"}
SRC_LEAN_CPP = src/shell/lean.cpp
SRC_LAKE_C = build/release/stage1/lib/temp/LakeMain.c
INC = -Isrc{,/include}
endif

MAINS = LeanIR.c LeanChecker.c LakeMain.c shell/lean.cpp
EXCEPT = lean_js.cpp $(MAINS)

OBJ_DIR = obj

SRC_CPP = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLCPP)} crazy/stubs.cpp
SRC_C = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLC)}

OBJ = $(addprefix $(OBJ_DIR)/,$(SRC_CPP:.cpp=.o) $(SRC_C:.c=.o))

MODIFIERS = -DLEAN_MULTI_THREAD -DLEAN_MULTI_THREAD_FRUGAL
MODIFIERS += -DLEAN_EMSCRIPTEN
MODIFIERS += -DAMBER -DLEAN_USE_POSIX_SPAWN
ifeq ($(STAGE),0)
MODIFIERS += -DLEAN_IS_STAGE0
endif

#MODIFIERS += -DLEAN_USE_GMP

CFLAGS = $(MODIFIERS) -Icrazy/include $(INC)
LDFLAGS = # -L/opt/homebrew/lib -luv -lgmp

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
	clang++ -o $@ --std=c++20 $< -Llib -llean $(LDFLAGS) -Wl,-dead_strip

lib/liblean.a: $(OBJ)
	@mkdir -p $(dir $@)
	ar r $@ $+

lib/export-symbols.txt: lib/liblean.wa
	nm --defined-only -A $< | awk '$$NF ~ /^(runtime|meta)_initialize_|.*__boxed$$/ { print "-Wl,--export=" $$NF }' > $@
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
	mkdir -p $@/home/init/src $@/usr/bin $@/dev
	cp crazy/init/lakefile.toml    $@/home/init
	cp -r src/Init.lean src/Init   $@/home/init/src
	dd if=/dev/urandom of=$@/dev/urandom bs=1K count=1

.PHONY: build-wasmer-fs

lib-init:
	rm -rf tmp/init/build
	( cd tmp/init && ../../bin/lake build --no-ansi -v Init:leanArts ) | tee tmp/lake-build-init.log

lib-init-fresh:
	rm -rf tmp/init; mkdir -p tmp/init/src
	cp crazy/init/lakefile.toml    tmp/init
	cp -r src/Init.lean src/Init   tmp/init/src
	$(make-rec) lib-init

lib-init-wasm: build-wasmer-fs
	node crazy/replay-lake-trace.js
	@$(make-rec) lib-init-wasm-tar

lib-init-wasm-tar:
	mkdir -p lib
	( cd build-wasmer-fs/home/init/build/lib/lean && \
	  tar cf ${PWD}/lib/Init32.tar `find * -name '*.olean' -o -name '*.ir' -o -name '*.ilean' -o -name '*.olean.*'` )

.PHONY: lib-init lib-init-%
