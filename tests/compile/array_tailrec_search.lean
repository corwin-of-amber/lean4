/-! Check the fork's non-monadic array search implementations, including bounds and long scans. -/

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def main : IO Unit := do
  for size in [:9] do
    let xs := (List.range size).map (· % 3) |>.toArray
    for needle in [:5] do
      let p := (· == needle)
      for start in [:size + 3] do
        for stop in [:size + 3] do
          let expected := (xs.toList.drop start |>.take (stop - start)).any p
          check (xs.any p start stop == expected)
            s!"Array.any mismatch: size={size}, needle={needle}, start={start}, stop={stop}"
      check (xs.find? p == xs.toList.find? p)
        s!"Array.find? mismatch: size={size}, needle={needle}"
  let large := Array.range 100000
  check (large.any (· == 99999)) "Array.any failed at the last element of a long scan"
  check (!(large.any (· == 100000))) "Array.any found an absent element"
  check (large.find? (· == 99999) == some 99999) "Array.find? failed at the last element"
  check (large.find? (· == 100000) == none) "Array.find? found an absent element"
