ALLCPP := ${shell find stage0/src -name "*.cpp"} crazy/stubs.cpp
ALLC := ${shell find stage0/stdlib -name "*.c"}
#ALLC := ${shell find tmp/stage0/stdlib -name "*.c"}

MAINS = LeanIR.c LeanChecker.c LakeMain.c shell/lean.cpp
EXCEPT = lean_js.cpp $(MAINS)

OBJ_DIR = obj

SRC_CPP = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLCPP)}
SRC_C = ${filter-out ${addprefix %/,$(EXCEPT)}, $(ALLC)}

SRC_LEAN_CPP = stage0/src/shell/lean.cpp
SRC_LAKE_C = stage0/stdlib/LakeMain.c

OBJ = $(addprefix $(OBJ_DIR)/,$(SRC_CPP:.cpp=.o) $(SRC_C:.c=.o))

# $(patsubst %.cpp,%.o,$(SRC)))

MODIFIERS = -DLEAN_MULTI_THREAD
MODIFIERS += -DLEAN_EMSCRIPTEN
MODIFIERS += -DAMBER

#MODIFIERS += -DLEAN_USE_GMP

CFLAGS = $(MODIFIERS) -Icrazy/include -Istage0/src{,/include}
LDFLAGS = # -L/opt/homebrew/lib -luv -lgmp

# dbg
#CFLAGS += -g -DLEAN_DEBUG
# opt
CFLAGS += -O3 -DLEAN_BUILD_TYPE="Release" -DNDEBUG

# For comparison: these are the full flags used by the cmake build
#CFLAGS = -I/opt/homebrew/Cellar/libuv/1.52.1/include -I/Users/corwin/var/ext/lean4/build/debug/stage0/include -I/Users/corwin/var/ext/lean4/stage0/src -I/Users/corwin/var/ext/lean4/build/debug/stage0 -D LEAN_USE_GMP   -D LEAN_MMAP -D LEAN_MULTI_THREAD -DLEAN_BUILD_TYPE="Release" -DLEAN_EXPORTING -D__CLANG__ -ftls-model=initial-exec -fvisibility=hidden -fvisibility-inlines-hidden -O3 -DNDEBUG -arch arm64



both: bin/lean bin/lake
.PHONY: both

bin/lean: $(addprefix $(OBJ_DIR)/,$(SRC_LEAN_CPP:.cpp=.o)) lib/liblean.a
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $+ $(LDFLAGS)

bin/lake: $(addprefix $(OBJ_DIR)/,$(SRC_LAKE_C:.c=.o)) lib/liblean.a
	@mkdir -p $(dir $@)
	clang++ -o $@ --std=c++20 $< -Llib -llean $(LDFLAGS) -Wl,-dead_strip

lib/liblean.a: $(OBJ)
	@mkdir -p $(dir $@)
	ar r $@ $+


$(OBJ_DIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	clang++ --std=c++20 -c $< -o $@ $(CFLAGS)
$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	clang -c $< -o $@ $(CFLAGS)


lib:
	rm -rf tmp/build
	( cd tmp && ../bin/lake build Init:leanArts )
.PHONY: lib
