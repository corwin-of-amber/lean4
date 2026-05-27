
## Crazy shit

This is an attempt to reconstruct Lean's bootstrapping build.
The makefile (`crazy.makefile`) builds Stage 0 Lean and Lake executables.

The goal is to make a few adjustments:
 * Single-threaded mode
 * Sandbox build without libuv

Currenly, this sort-of works.
```
make -f crazy.makefile

export LEAN_PATH=$PWD/build/debug/stage1/lib/lean
echo def a := 90 | ./bin/lean --stdin
```

(CHEAT: the above tests using a pre-made Stage 1 build for Init.
It seems that Stage 0 `lake` built this way can also compile Init,
at least in `.olean` format.)
