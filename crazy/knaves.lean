-- https://github.com/JadAbouHawili/KnightsAndKnaves-Lean4Game

module

infixr:35 " and " => And
infixr:30 " or  "  => Or

set_option linter.unusedVariables false
abbrev ℕ := Nat

example : 2 = 2 := by
  rfl

example {x : ℕ} (h : x=2) : x=2 := by
  exact h

example {x y z : ℕ} (h : x = 3) (g: y = 6) (i : z=10) : x + x = y := by
  rw [h, g]

example (P Q R : Prop) (hP: P) (hQ: Q) (hR : R) : P := by
  exact hP

example (P Q : Prop) (hP : P) (hQ : Q) : P ∧ Q := by
  exact And.intro hP hQ

example (P Q : Prop) (hP : P ∧ Q) : P := by
  exact And.left hP

example {P Q: Prop} (hP : P) : P ∨ Q := by
  left; exact hP

example {P Q : Prop} (hP : P) (PtoQ: P → Q) : Q := by
  exact PtoQ hP

example {P :Prop} : P → P := by
  intro h; exact h

example {P Q R : Prop} (h : P ∨ Q) (hPR : P → R) (hQR : Q → R) : R := by
  rcases h with h_1|h_1
  · exact hPR h_1
  · exact hQR h_1
