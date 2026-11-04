# Lean 4.36.0-rc2 with WASIX

This port builds Lean and Lake for WASIX, using the native Stage 1 build as its
bootstrap. The supported path below uses Stage 1; `STAGE=0` remains an
experimental source selection and needs separate validation.

## Native bootstrap

Install CMake, Make, a C/C++ compiler, Node/npm, and Lean's normal native build
dependencies. Configure the release-candidate description explicitly:

```sh
cmake --preset release -DLEAN_SPECIAL_VERSION_DESC=$(python3 crazy/configure.py --special-version)
make -j2 -C build/release
```

The WASIX tools also need wasi-kernel's `wasi-kit`, WASI SDK 33, the WASIX libc
2026-10-02.1 exnref-ehpic sysroot, and Wasmer. Set `WASI_SDK` and `WASIX_LIBC`
when those are installed outside the default locations used by wasi-kit.

## Wasm compiler and libraries

```sh
python3 crazy/configure.py
(cd crazy && npm ci)
WASI_KIT=native=false wasi-kit make -f crazy.makefile BACKEND=wasm -j2
for target in lib-init-wasm lib-std-wasm lib-lean-wasm lib-lake-wasm lib-wasm-tars lib-wasm-install; do
  make -f crazy.makefile BACKEND=wasm "$target"
done
```

`bin/lean.wasm` and `bin/lake.wasm` are the compilers. The five library archives
are `lib/{Init,Std,Lean,LeanExport,Lake}.tar`; installed libraries live under
`build-wasmer-fs/usr/lib/lean`. Archives include public, server, and private
`.olean` files, plus IR. Missing or corrupt module metadata is an import error.

Lake imports LeanExport, so its library modules are included while the
`LeanExport.c` executable entry point is excluded from the compiler archive.
The native-symbol table is regenerated when the generated C source set changes.

Run library phases sequentially because they share a guest filesystem. Keep Wasmer’s built-in `/dev` devices visible; a host directory mounted over `/dev` hides `/dev/null` and breaks null stream redirection.
`WASMER_STACK_SIZE` defaults to 16000000 bytes for the symbolic simplifier;
this host call-stack limit is separate from Lean's `-s4000` setting.

## Configuration and provenance

`crazy/platform.json` records the upstream release, upstream commit, Wasm
target, and default host stack size. `crazy/configure.py` generates the version
headers and Make settings. Check them with `python3 crazy/configure.py --check`.
`lib/build-info.json` separately records the port commit and modified-tree state;
the version header's Git hash identifies the upstream release.

`BACKEND`, `STAGE`, `OPT`, `DLSYM`, and `MIMALLOC` identify object/archive paths.
Defaults are `BACKEND=native`, `STAGE=1`, `OPT=Oz`, `DLSYM=dyn`, `MIMALLOC=1`.
Use `BACKEND=wasm` through wasi-kit. Host bookkeeping bypasses wasi-kit’s artifact-renaming wrapper. Compiler flags and allocator source-location
changes also invalidate affected objects. Header dependencies are tracked by
Clang. Executable paths are shared, so configuration changes relink them.
`WASI_KIT=native=false` skips unnecessary native companion compilation.

## Checks

```sh
python3 tests/wasm/test_crazy_build.py
crazy/node_modules/.bin/tsx --test tests/wasm/builder.test.ts
python3 tests/wasm/module_metadata.py --lean "$PWD/build/release/stage1/bin/lean"
c++ -std=c++20 -D_GNU_SOURCE -Isrc tests/wasm/posix_spawn.cpp -o /tmp/lean-posix-spawn-test
/tmp/lean-posix-spawn-test
WASI_KIT=native=false wasi-kit make -f crazy.makefile BACKEND=wasm test-mimalloc
```

After building and installing the libraries, run the guest API regression:

```sh
wasmer run --stack-size=16000000 --volume build-wasmer-fs/usr:/usr --volume build-wasmer-fs/home:/home --volume tests/wasm:/tests bin/lean.wasm -- --run /tests/ProcessSpawn.lean
```

The host POSIX-spawn test uses Linux `/proc/self/fd` to check failure-path
ownership. The Wasm backend preserves arguments, environment inheritance and
updates, working directories, stream redirections, and effective `PATH` lookup. Separate sessions are
explicitly unsupported on WASI; unsupported session/directory operations return
an IO error. Resource owners
clean up file actions, descriptors, and failed child handoffs. Spawn failures
return to Lean rather than terminating the parent process.

The builder converts dependency manifests to local paths, fails on missing
dependencies, and packages metadata using a unique staging directory. Output
archives are replaced only after successful packaging, and staging cleanup is
awaited on both success and failure.
