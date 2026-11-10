<!--
Copyright (c) 2026 Emilio Jesus Gallego Arias. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-->
# WASIX allocator selection

The default is `MIMALLOC=1 OPT=Oz`. Set `MIMALLOC=0` for a libc comparison or
`OPT=O3` for a different optimization level:

```sh
WASI_KIT=native=false wasi-kit make -f crazy.makefile BACKEND=wasm OPT=O3 MIMALLOC=1 -j2
```

Object and archive names identify backend, bootstrap stage, optimization,
symbol lookup and allocator mode. Changing modes does not reuse incompatible
objects. Shared executable paths are relinked when selecting another mode.

Mimalloc comes from the native bootstrap at
`build/release/mimalloc/src/mimalloc`, or `MIMALLOC_DIR` when overridden. Its
unity source is compiled as C with pthread locks and local TLS; Lean uses the
header shim in `crazy/include/lean/mimalloc.h`. Libc retains its own allocator:
`MI_MALLOC_OVERRIDE` would reach mimalloc before WASIX thread-local startup.

The allocator probe links the same allocator object as Lean and Lake:

```sh
WASI_KIT=native=false wasi-kit make -f crazy.makefile BACKEND=wasm MIMALLOC=1 test-mimalloc
```

`tests/wasm/test_crazy_build.py` checks mode selection and incremental reuse;
`tests/wasm/mimalloc.c` checks allocation, alignment and cross-thread frees.

The measurements below are historical 4.34 observations, not measurements of
the 4.36 compiler or the current allocator implementation.

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
