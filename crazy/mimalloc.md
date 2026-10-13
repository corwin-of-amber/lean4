<!--
Copyright (c) 2026 Emilio Jesus Gallego Arias. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-->
# Optional mimalloc support

After the native bootstrap, build Lean and Lake with Lean's existing mimalloc
API path:

```sh
wasi-kit make -f crazy.makefile DLSYM=dyn MIMALLOC=1 -j2
```

The default remains `MIMALLOC=0 OPT=Oz`. Use `OPT=O3` to compare both allocator
modes at that optimization level. Objects and archives have separate paths for
each combination; switching modes relinks the shared `bin/lean` and `bin/lake`.
Set `MIMALLOC_DIR` to use a different source checkout, and use a fresh object
directory when changing allocator versions.

The build uses the mimalloc source fetched by the native bootstrap at
`build/release/mimalloc/src/mimalloc`. It copies the public header into the
variant's include directory and defines `LEAN_MIMALLOC` for all Lean objects.
This mode also selects Lean's mimalloc STL allocator and small-object handling.

The unity source is compiled as C++, with pthread locks and local TLS. Libc
retains its allocator: defining `MI_MALLOC_OVERRIDE` would call mimalloc from
WASIX's `__wasi_init_tp` before thread-local storage is initialized.

Run the build-selection regression checks with:

```sh
python3 tests/wasm/test_crazy_build.py
```

Run the allocator API and cross-thread-free probe under Wasmer with:

```sh
wasi-kit make -f crazy.makefile DLSYM=dyn MIMALLOC=1 test-mimalloc -j2
```

Its source is `tests/wasm/mimalloc.c`.

## RawLemmas profiling observation

On a Ryzen AI 9 HX 370, a local reproduction of `crazy-4.34.0` at `f231d8d0`
compiled the complete `Std/Data/DHashMap/Internal/RawLemmas.lean` with Wasmer
7.5.0 Cranelift, WASI SDK 33, WASIX libc 2026-10-02.1, and mimalloc 3.4.4.
Both variants used `OPT=O3`, CPU 0 affinity, warmed caches, and Lean flags
`-j1 -s4000 -Dinterpreter.prefer_native=false -Dbackward.do.legacy=false`.

| Alternating pair | libc seconds | mimalloc seconds |
| --- | ---: | ---: |
| 1 | 157.74 | 61.33 |
| 2 | 162.91 | 61.90 |
| 3 | 192.60 | 60.43 |
| 4 | 151.66 | 65.28 |

Median complete-command time was 160.325 versus 61.615 seconds (2.60x).
Median peak process RSS, including the host/JIT, was 1.691 versus 1.572 GiB.
Host load varied; these are descriptive measurements, not a confidence interval
or a pure Wasm/native overhead ratio. They do not measure the default `OPT=Oz`
combination or browser performance.

The source, frozen import files, and name/symbol lookup code were held fixed.
The reproduction included matching local version-header and CLI exit-code fixes
in both variants; those fixes are separate from this allocator patch.
Generated C was identical across every run, SHA-256
`c225a3048c15427220374702fdd05a22c72c757d353da9a2e9c11832639d7fea`.
Some serialized Lean artifacts differed, but all four producer/consumer import
combinations passed with four Lean workers.
