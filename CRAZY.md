
## Crazy shit

This is an attempt to reconstruct Lean's bootstrapping build.
The makefile (`crazy.makefile`) builds Stage 0 Lean and Lake executables.

The goal is to make a few adjustments:
 * Single-threaded mode
 * Sandbox build without libuv

Currenly, this sort-of works.
```
make -f crazy.makefile -j12

export LEAN_PATH=$PWD/build/debug/stage1/lib/lean
echo def a := 90 | ./bin/lean --stdin
```

CHEAT: the above tests using a pre-made Stage 1 build for Init.
It seems that Stage 0 `lake` built this way can also compile Init,
at least in `.olean` format.

### Builting Init

```
make -f crazy.makefile lib-init-fresh
```

This creates `tmp/init` with the sources of Init and runs `lake build`.

### WebAssembly Port!!

Building `lean.wasm` and `lake.wasm` is simplest using `wasi-kit` (from wasi-kernel).
```
rm -rf obj  # clean native build files
wasi-kit make -f crazy.makefile -j12
```

If you are interested, the flags that are relevant for the compilation can be
found in `wasi-kit.json`. In particular:
 * `-mtail-call` is crucial for compiling `stage0/stdlib/Lean/Language/Lean.c`.
   This repository contains a patch
 * `@crazy/export-symbols.txt` is needed to expose a minimal set of native
   symbols defined in the main executable as WASM exports, which the
   interpreter requires be present at runtime.
 * `@lib/export-symbols.txt` can be used instead to expose all the symbols defined
   in the main executable, mainly for testing purposes. This creates a much larger
   file and increases loading times due to the size of the export table.
   This requires running `make -f crazy.makefile lib/export-symbols.txt` before
   the final linking; the main target `bin/lean` takes care of that.

### Lean 4.36.0-rc2

The port targets Lean 4.36.0-rc2. Configure the native bootstrap with
`cmake --preset release -DLEAN_SPECIAL_VERSION_DESC=rc2` before building
Stage 1. The Wasm version headers identify the same upstream release.

Lake now imports `LeanExport`; the bootstrap configuration builds its library
modules and the library packaging produces `lib/LeanExport.tar`. The
`LeanExport.c` executable entry point is excluded from the compiler archive.
The Wasmer library runner uses a 16 MB host call stack for the new symbolic
simplifier code; override `WASMER_STACK_SIZE` if needed. This is separate from
Lean's `-s4000` option.
