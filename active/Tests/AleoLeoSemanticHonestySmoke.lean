import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter

/-! Regression tests for Aleo lowering semantic honesty. -/

namespace ProofForge.Tests.AleoLeoSemanticHonestySmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

/-- Leo 4.0.2 cannot surface a value read from a mapping-backed state getter.
The backend must reject the module instead of silently changing `U64` to `Final`. -/
def counterGetterFailsClosed : Bool :=
  match renderModule Examples.Counter.module with
  | .error e =>
      e.message.contains "get" &&
      e.message.contains "non-Unit return" &&
      e.message.contains "Leo 4.0.2"
  | .ok _ => false

theorem counter_getter_fails_closed : counterGetterFailsClosed = true := by
  native_decide

def arithmeticEntrypoint (overflowChecked : Bool) : Entrypoint :=
  { name := "arithmetic"
    params := #[("a", .u64), ("b", .u64)]
    returns := .u64
    body := #[.return (.add (.local "a") (.local "b") overflowChecked)] }

def arithmeticModule (name : String) (nodeChecked moduleChecked : Bool) : Module :=
  { name
    state := #[]
    entrypoints := #[arithmeticEntrypoint nodeChecked]
    overflowChecked := moduleChecked }

/-- Expression arithmetic follows the node flag in all four combinations;
`Module.overflowChecked` only governs AssignOp, whose IR node has no flag. -/
def expressionOverflowFourCombinations : Bool :=
  let check (nodeChecked moduleChecked : Bool) : Bool :=
    match renderModule (arithmeticModule s!"M{nodeChecked}{moduleChecked}" nodeChecked moduleChecked) with
    | .ok source =>
        if nodeChecked then
          source.contains "return (a + b);" && !source.contains "add_wrapped"
        else
          source.contains "return a.add_wrapped(b);" && !source.contains "return (a + b);"
    | .error _ => false
  check false false && check false true && check true false && check true true

theorem expression_overflow_four_combinations : expressionOverflowFourCombinations = true := by
  native_decide

def assignOpEntrypoint : Entrypoint :=
  { name := "assign_op"
    body := #[
      .letMutBind "x" .u64 (.literal (.u64 1)),
      .assignOp (.local "x") .add (.literal (.u64 1))
    ] }

def assignOpUsesModuleMode : Bool :=
  let wrapping : Module := { name := "AssignWrap", state := #[], entrypoints := #[assignOpEntrypoint] }
  let checked : Module := { wrapping with name := "AssignChecked", overflowChecked := true }
  match renderModule wrapping, renderModule checked with
  | .ok wrappingSource, .ok checkedSource =>
      wrappingSource.contains "x = x.add_wrapped(1u64);" &&
      checkedSource.contains "x = (x + 1u64);"
  | _, _ => false

theorem assign_op_uses_module_mode : assignOpUsesModuleMode = true := by
  native_decide

def hashPair (name lhs rhs : String) : Entrypoint :=
  { name
    params := #[("a", .u64), ("b", .u64)]
    returns := .hash
    body := #[.return (.hashTwoToOne (.local lhs) (.local rhs))] }

def orderedHashModule : Module :=
  { name := "OrderedHash"
    state := #[]
    entrypoints := #[hashPair "hash_ab" "a" "b", hashPair "hash_ba" "b" "a"] }

/-- Pair hashing must encode position and a pair-domain tag. The two generated
expressions therefore differ when the operands are reversed. -/
def orderedHashHasDomainSeparatedShapes : Bool :=
  match renderModule orderedHashModule with
  | .ok source =>
      source.contains "1315423911field" &&
      source.contains "2field" &&
      source.contains "(Poseidon2::hash_to_field(a) * 1315423911field)" &&
      source.contains "(Poseidon2::hash_to_field(b) * 1315423911field)"
  | .error _ => false

theorem ordered_hash_has_domain_separated_shapes : orderedHashHasDomainSeparatedShapes = true := by
  native_decide

def balanceState : StateDecl :=
  { id := "balance", kind := .scalar, type := .u64 }

def taintedReturn : Entrypoint :=
  { name := "tainted_return"
    returns := .u64
    body := #[
      .letBind "current" .u64 (.effect (.storageScalarRead "balance")),
      .letBind "next" .u64 (.add (.local "current") (.literal (.u64 1))),
      .effect (.storageScalarWrite "balance" (.local "next")),
      .return (.local "next")
    ] }

def taintedReturnModule : Module :=
  { name := "Tainted", state := #[balanceState], entrypoints := #[taintedReturn] }

/-- A local derived from a mapping read exists only inside `final`; it cannot be
reordered into the off-chain value-return path. -/
def taintedMixedReturnFailsClosed : Bool :=
  match renderModule taintedReturnModule with
  | .error e => e.message.contains "tainted_return" && e.message.contains "state-derived local"
  | .ok _ => false

theorem tainted_mixed_return_fails_closed : taintedMixedReturnFailsClosed = true := by
  native_decide

def postFinalPure : Entrypoint :=
  { name := "post_final_pure"
    params := #[("amount", .u64)]
    returns := .u64
    body := #[
      .effect (.storageScalarWrite "balance" (.local "amount")),
      .letBind "late" .u64 (.literal (.u64 7)),
      .return (.local "amount")
    ] }

def mutableAcrossBoundary : Entrypoint :=
  { name := "mutable_across_boundary"
    returns := .u64
    body := #[
      .letMutBind "x" .u64 (.literal (.u64 1)),
      .effect (.storageScalarWrite "balance" (.local "x")),
      .return (.literal (.u64 1))
    ] }

def controlFlowMixed : Entrypoint :=
  { name := "control_flow_mixed"
    params := #[("flag", .bool)]
    returns := .u64
    body := #[
      .ifElse (.local "flag")
        #[.effect (.storageScalarWrite "balance" (.literal (.u64 1)))]
        #[.effect (.storageScalarWrite "balance" (.literal (.u64 2)))],
      .return (.literal (.u64 1))
    ] }

def namedCrosscallMixed : Entrypoint :=
  { name := "named_crosscall_mixed"
    returns := .u64
    body := #[
      .letBind "remote" .u64 (.crosscallNamed "credits.aleo" "mint" #[] .u64),
      .effect (.storageScalarWrite "balance" (.literal (.u64 1))),
      .return (.local "remote")
    ] }

def namedCrosscallFinalOnly : Entrypoint :=
  { name := "named_crosscall_final_only"
    body := #[
      .letBind "remote" .u64 (.crosscallNamed "credits.aleo" "mint" #[] .u64),
      .effect (.storageScalarWrite "balance" (.local "remote"))
    ] }

/-- Named cross-program calls execute in the Leo function, never inside its
`final` block. A Unit-returning storage writer must therefore fail closed too,
not only the mixed `(value, Final)` shape. -/
def namedCrosscallFinalOnlyFailsClosed : Bool :=
  let module : Module :=
    { name := "NamedCrosscallFinalOnly"
      state := #[balanceState]
      entrypoints := #[namedCrosscallFinalOnly] }
  match renderModule module with
  | .error error =>
      error.message.contains "named_crosscall_final_only" &&
      error.message.contains "named crosscall" &&
      error.message.contains "final"
  | .ok _ => false

theorem named_crosscall_final_only_fails_closed : namedCrosscallFinalOnlyFailsClosed = true := by
  native_decide

def mixedShapeRejects (entrypoint : Entrypoint) (marker : String) : Bool :=
  let module : Module := { name := "MixedShape", state := #[balanceState], entrypoints := #[entrypoint] }
  match renderModule module with
  | .error error => error.message.contains marker
  | .ok _ => false

def nonCanonicalMixedShapesFailClosed : Bool :=
  mixedShapeRejects postFinalPure "after final" &&
  mixedShapeRejects mutableAcrossBoundary "mutable" &&
  mixedShapeRejects controlFlowMixed "control flow" &&
  mixedShapeRejects namedCrosscallMixed "named crosscall"

theorem non_canonical_mixed_shapes_fail_closed : nonCanonicalMixedShapesFailClosed = true := by
  native_decide

def nestedCrosscall : Entrypoint :=
  { name := "nested_crosscall"
    params := #[("amount", .u64)]
    returns := .u64
    body := #[.return (.add
      (.crosscallNamed "credits.aleo" "mint" #[.local "amount"] .u64)
      (.literal (.u64 1)))] }

def nestedCrosscallModule : Module :=
  { name := "NestedCaller", state := #[], entrypoints := #[nestedCrosscall] }

def nestedCrosscallImportIsCollected : Bool :=
  match renderModule nestedCrosscallModule with
  | .ok source => source.contains "import credits.aleo;"
  | .error _ => false

theorem nested_crosscall_import_is_collected : nestedCrosscallImportIsCollected = true := by
  native_decide

def invalidProgramCrosscall : Entrypoint :=
  { name := "invalid_program"
    returns := .u64
    body := #[.return (.crosscallNamed "credits" "mint" #[] .u64)] }

def invalidMethodCrosscall : Entrypoint :=
  { name := "invalid_method"
    returns := .u64
    body := #[.return (.crosscallNamed "credits.aleo" "bad-name" #[] .u64)] }

def invalidCrosscallIdentifiersFailClosed : Bool :=
  let programModule : Module := { name := "InvalidProgram", state := #[], entrypoints := #[invalidProgramCrosscall] }
  let methodModule : Module := { name := "InvalidMethod", state := #[], entrypoints := #[invalidMethodCrosscall] }
  match renderModule programModule, renderModule methodModule with
  | .error programError, .error methodError =>
      programError.message.contains "program id" && methodError.message.contains "method"
  | _, _ => false

theorem invalid_crosscall_identifiers_fail_closed : invalidCrosscallIdentifiersFailClosed = true := by
  native_decide

def nestedArgumentCrosscall : Entrypoint :=
  { name := "nested_argument_crosscall"
    returns := .u64
    body := #[.return (.crosscallNamed "router.aleo" "forward"
      #[.crosscallNamed "credits.aleo" "mint" #[] .u64] .u64)] }

def nestedArgumentImportsAreCollected : Bool :=
  let module : Module := { name := "NestedArgument", state := #[], entrypoints := #[nestedArgumentCrosscall] }
  match renderModule module with
  | .ok source => source.contains "import router.aleo;" && source.contains "import credits.aleo;"
  | .error _ => false

theorem nested_argument_imports_are_collected : nestedArgumentImportsAreCollected = true := by
  native_decide

def statefulCrosscallArg : Entrypoint :=
  { name := "stateful_crosscall_arg"
    returns := .u64
    body := #[.return (.crosscallNamed "credits.aleo" "mint"
      #[.effect (.storageScalarRead "balance")] .u64)] }

def statefulCrosscallArgModule : Module :=
  { name := "StatefulCaller", state := #[balanceState], entrypoints := #[statefulCrosscallArg] }

/-- Storage effects nested in named-call arguments participate in function
planning; they cannot escape into a pure caller-visible return. -/
def statefulCrosscallArgFailsClosed : Bool :=
  match renderModule statefulCrosscallArgModule with
  | .error e =>
      e.message.contains "stateful_crosscall_arg" &&
      e.message.contains "named crosscall" &&
      e.message.contains "final"
  | .ok _ => false

theorem stateful_crosscall_arg_fails_closed : statefulCrosscallArgFailsClosed = true := by
  native_decide

example : True := by
  have _ := @counter_getter_fails_closed
  have _ := @expression_overflow_four_combinations
  have _ := @assign_op_uses_module_mode
  have _ := @ordered_hash_has_domain_separated_shapes
  have _ := @tainted_mixed_return_fails_closed
  have _ := @non_canonical_mixed_shapes_fail_closed
  have _ := @named_crosscall_final_only_fails_closed
  have _ := @nested_crosscall_import_is_collected
  have _ := @invalid_crosscall_identifiers_fail_closed
  have _ := @nested_argument_imports_are_collected
  have _ := @stateful_crosscall_arg_fails_closed
  exact True.intro

end ProofForge.Tests.AleoLeoSemanticHonestySmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-semantic-honesty-smoke: getter/hash/arithmetic checked"
  return 0
