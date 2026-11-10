module

import Init

/-! Exercise WASIX process options and recovery through the public Lean API. -/

public def main (args : List String) : IO UInt32 := do
  if args == ["child"] then
    IO.println s!"{(← IO.getEnv "LEAN_SPAWN_TEST").getD "missing"}:{← IO.currentDir}"
    return 7
  let config : IO.Process.SpawnArgs := {
    cmd := "/usr/bin/lean"
    args := #["--run", "/tests/ProcessSpawn.lean", "child"]
    cwd := some "/home/init"
    env := #[("LEAN_SPAWN_TEST", some "present")]
  }
  let check := do
    let result ← IO.Process.output config
    unless result.exitCode == 7 && result.stdout == "present:/home/init\n" && result.stderr == "" do
      throw <| IO.userError s!"unexpected child result: {result.exitCode}, {result.stdout}, {result.stderr}"
  check
  for _ in [:5] do
    let failed ← try
      let _ ← IO.Process.output {config with cmd := "/no-such-lean-spawn-test"}
      pure false
    catch _ => pure true
    unless failed do throw <| IO.userError "missing executable unexpectedly succeeded"
  check
  let child ← IO.Process.spawn {config with stdin := .null, stdout := .null, stderr := .null}
  unless (← child.wait) == 7 do throw <| IO.userError "null stream child failed"
  let rejected ← try
    let child ← IO.Process.spawn {config with setsid := true}
    let _ ← child.wait
    pure false
  catch _ => pure true
  unless rejected do throw <| IO.userError "WASI session request should be rejected"
  IO.println "WASIX process options and recovery checks passed"
  return 0
