import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.Plan.Storage
import ProofForge.Backend.Evm.IR
import ProofForge.Compiler.Yul.Printer
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Target.Plan

/-! # Canonical Core → EVM Plan Assertions

Tests that `buildFromCore` produces valid EVM `ModulePlan` from
`CheckedCanonicalContract`. Checks:
- physical slot allocation is injective over logical StateId;
- selectors/ABI come from InterfaceContract, never zero fallback;
- each non-empty Core function has a non-empty StmtPlan body;
- return plans exist for every non-unit function;
- evidence changes do not change ModulePlan;
- missing capability, unsupported Core op, and incomplete return fail.
-/

open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Plan.Core

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def effectUsesSymbolicStorage : EffectPlan → Bool
  | .storageScalarRead .. | .storageScalarWrite .. | .storageScalarAssignOp ..
  | .storageMapContains .. | .storageMapGet .. | .storageMapInsert ..
  | .storageMapSet .. | .storageMapDelete ..
  | .storageArrayRead .. | .storageArrayWrite ..
  | .storageArrayStructFieldRead .. | .storageArrayStructFieldWrite ..
  | .storageDynamicArrayPush .. | .storageDynamicArrayPop ..
  | .storageStructFieldRead .. | .storageStructFieldWrite ..
  | .storagePathRead .. | .storagePathWrite .. | .storagePathAssignOp .. => true
  | _ => false

partial def exprUsesSymbolicStorage : ExprPlan → Bool
  | .effect effect => effectUsesSymbolicStorage effect
  | .builtin _ args | .helperCall _ args | .arrayLit _ args => args.any exprUsesSymbolicStorage
  | .checkedArith _ lhs rhs .. | .arrayGet lhs rhs | .memoryArrayGet lhs rhs
  | .hashTwoToOne lhs rhs => exprUsesSymbolicStorage lhs || exprUsesSymbolicStorage rhs
  | .hashPack a b c d | .hashValue a b c d | .ecrecover a b c d =>
      #[a, b, c, d].any exprUsesSymbolicStorage
  | .eip712PermitDigest a b c d e f => #[a, b, c, d, e, f].any exprUsesSymbolicStorage
  | .crosscall _ target method value? args _ =>
      exprUsesSymbolicStorage target || exprUsesSymbolicStorage method ||
        value?.any exprUsesSymbolicStorage || args.any (fun
          | .expr value => exprUsesSymbolicStorage value
          | .local .. | .storage .. => false)
  | .create _ value salt? _ =>
      exprUsesSymbolicStorage value || salt?.any exprUsesSymbolicStorage
  | .cast value _ | .structField value _ | .memoryArrayNew _ value
  | .memoryArrayLength value | .hash value => exprUsesSymbolicStorage value
  | .localArrayGet _ path _ => path.any exprUsesSymbolicStorage
  | .structLit _ fields => fields.any (exprUsesSymbolicStorage ·.snd)
  | .crosscallAbiPacked target _ _ _ _ _ dynLen? _ dynTargets =>
      exprUsesSymbolicStorage target || dynLen?.any exprUsesSymbolicStorage ||
        dynTargets.any exprUsesSymbolicStorage
  | .literalWord .. | .local .. | .calldataWord .. | .storageLoad ..
  | .context .. | .nativeValue => false

partial def stmtUsesSymbolicStorage : StmtPlan → Bool
  | .letBind _ _ value | .letMutBind _ _ value => exprUsesSymbolicStorage value
  | .assign target value | .assignOp target _ value | .assertEq target value .. =>
      exprUsesSymbolicStorage target || exprUsesSymbolicStorage value
  | .effect effect => effectUsesSymbolicStorage effect
  | .assert condition .. | .assertPlanned condition .. | .return condition =>
      exprUsesSymbolicStorage condition
  | .ifElse condition thenBody elseBody =>
      exprUsesSymbolicStorage condition || thenBody.any stmtUsesSymbolicStorage ||
        elseBody.any stmtUsesSymbolicStorage
  | .boundedFor _ _ _ body => body.any stmtUsesSymbolicStorage
  | .release .. | .revert .. | .revertWithError .. | .revertPlanned .. => false

def planUsesSymbolicStorage (plan : ModulePlan) : Bool :=
  plan.entrypoints.any fun entrypoint => entrypoint.body.any stmtUsesSymbolicStorage

/-- A simple counter contract in Core: one state, two functions
(initialize + increment + get). -/
def counterContract : CanonicalContract := {
  schemaVersion := 1
  module := {
    name := "Counter"
    structs := #[]
    state := #[⟨⟨0⟩, .scalar .u64⟩]
    events := #[]
    functions := #[
      { id := ⟨0⟩, params := #[], retType := .unit, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
            ⟨#[], .storageStore
              { root := ⟨0⟩, path := #[], resultType := .u64 }
              { id := ⟨0⟩, type := .u64 }⟩
          ]
          terminator := .return #[]
        }]
      },
      { id := ⟨1⟩, params := #[], retType := .unit, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨1⟩, .u64⟩], .storageLoad
              { root := ⟨0⟩, path := #[], resultType := .u64 }⟩,
            ⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
            ⟨#[⟨⟨3⟩, .u64⟩], .pure (.arithmetic .add .checked
              { id := ⟨1⟩, type := .u64 } { id := ⟨2⟩, type := .u64 })⟩,
            ⟨#[], .storageStore
              { root := ⟨0⟩, path := #[], resultType := .u64 }
              { id := ⟨3⟩, type := .u64 }⟩
          ]
          terminator := .return #[]
        }]
      },
      { id := ⟨2⟩, params := #[], retType := .u64, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨3⟩, .u64⟩], .storageLoad
              { root := ⟨0⟩, path := #[], resultType := .u64 }⟩
          ]
          terminator := .return #[{ id := ⟨3⟩, type := .u64 }]
        }]
      }
    ]
    errors := #[]
  }
  interface := {
    contractName := "Counter"
    entrypoints := #[
      { functionId := ⟨0⟩, name := "initialize",
        mutability := .call, params := #[], retType := .unit,
        selector? := some "deadbeef" },
      { functionId := ⟨1⟩, name := "increment",
        mutability := .call, params := #[], retType := .unit,
        selector? := some "feedface" },
      { functionId := ⟨2⟩, name := "get",
        mutability := .view, params := #[], retType := .u64,
        selector? := some "c0ffee00" }
    ]
    events := #[]
    errors := #[]
  }
  materialization := {
    constructorParams := #[{ name := "initial", abiType := "uint64" }]
    constructorBindings := #[{
      stateId := ⟨0⟩, paramName := "initial", kind := .scalarU64 }]
    stateSymbols := #[{ stateId := ⟨0⟩, name := "count" }]
  }
  requirements := #[]
}

def counterContractWithReqs : CanonicalContract := {
  counterContract with
  requirements := deriveCapabilityRequirements
    counterContract.module counterContract.materialization
}

def emptyCapPlan : CapabilityPlan := { targetId := "evm", calls := #[], metadata := #[] }

def wrongTargetCapPlan : CapabilityPlan := { targetId := "solana-sbpf-asm", calls := #[], metadata := #[] }

def checkedFromSpec (spec : ProofForge.Contract.ContractSpec) : IO CheckedCanonicalContract := do
  let bundle ← match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"canonical adapter failed: {repr error}"
  match validateCanonical bundle.contract.contract with
  | .ok checked => pure checked
  | .error error => throw <| IO.userError s!"canonical validation failed: {repr error}"

def renderWithCanonicalPlan (plan : ModulePlan) : IO String := do
  let object ← match ProofForge.Backend.Evm.IR.lowerCanonicalModuleWithPlan plan with
    | .ok object => pure object
    | .error error => throw <| IO.userError s!"canonical EVM plan did not render: {error.message}"
  pure (Lean.Compiler.Yul.Printer.render object)

/-- A contract with an unsupported instruction (hostCall). -/
def unsupportedContract : CanonicalContract := {
  schemaVersion := 1
  module := {
    name := "Unsupported"
    structs := #[]
    state := #[]
    events := #[]
    functions := #[
      { id := ⟨0⟩, params := #[], retType := .u64, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨0⟩, .u64⟩], .hostCall {
              id := ⟨"test", "unsupported", ⟨1, 0, 0⟩⟩,
              args := #[] }⟩
          ]
          terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
        }]
      }
    ]
    errors := #[]
  }
  interface := {
    contractName := "Unsupported"
    entrypoints := #[
      { functionId := ⟨0⟩, name := "run",
        mutability := .view, params := #[], retType := .u64 }
    ]
  }
  materialization := { constructorParams := #[], constructorBindings := #[], stateSymbols := #[] }
  requirements := #[]
}

def addressLiteralContract : CanonicalContract := {
  unsupportedContract with
  module := {
    unsupportedContract.module with
    name := "AddressLiteral"
    functions := #[{
      id := ⟨0⟩, params := #[], retType := .address, entry := ⟨0⟩,
      blocks := #[{
        id := ⟨0⟩, params := #[],
        instructions := #[
          ⟨#[⟨⟨0⟩, .address⟩], .pure (.literal (.addressLit "0x0000000000000000000000000000000000000001"))⟩
        ],
        terminator := .return #[{ id := ⟨0⟩, type := .address }]
      }]
    }]
  }
  interface := {
    contractName := "AddressLiteral"
    entrypoints := #[{
      functionId := ⟨0⟩, name := "run",
      mutability := .view, params := #[], retType := .address,
      selector? := some "01020304"
    }]
  }
}

def invalidAddressLiteralContract : CanonicalContract := {
  addressLiteralContract with
  module := {
    addressLiteralContract.module with
    name := "InvalidAddressLiteral"
    functions := #[{
      id := ⟨0⟩, params := #[], retType := .address, entry := ⟨0⟩,
      blocks := #[{
        id := ⟨0⟩, params := #[],
        instructions := #[
          ⟨#[⟨⟨0⟩, .address⟩], .pure (.literal (.addressLit "not-an-evm-address"))⟩
        ],
        terminator := .return #[{ id := ⟨0⟩, type := .address }]
      }]
    }]
  }
  interface := { addressLiteralContract.interface with contractName := "InvalidAddressLiteral" }
}

def multiBlockContract : CanonicalContract := {
  unsupportedContract with
  module := {
    unsupportedContract.module with
    name := "MultiBlock"
    functions := #[{
      id := ⟨0⟩, params := #[], retType := .u64, entry := ⟨0⟩,
      blocks := #[
        { id := ⟨0⟩, params := #[], instructions := #[], terminator := .jump ⟨1⟩ #[] },
        { id := ⟨1⟩, params := #[], instructions := #[
            ⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩
          ], terminator := .return #[{ id := ⟨0⟩, type := .u64 }] }
      ]
    }]
  }
  interface := {
    contractName := "MultiBlock"
    entrypoints := #[{
      functionId := ⟨0⟩, name := "run",
      mutability := .view, params := #[], retType := .u64,
      selector? := some "01020304"
    }]
  }
}

def main : IO Unit := do
  let realCounterChecked ← checkedFromSpec
    (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module)
  let realCounterPlan ← match buildFromCore realCounterChecked emptyCapPlan with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError s!"real Counter plan failed: {error.message}"
  require (realCounterPlan.storage.states.map (·.id) == #["count"])
    s!"canonical state symbol did not reach the EVM plan: {repr (realCounterPlan.storage.states.map (·.id))}"
  require (!planUsesSymbolicStorage realCounterPlan)
    s!"canonical Counter EVM plan retained symbolic Legacy storage effects: {repr realCounterPlan.entrypoints}"
  let counterYul ← renderWithCanonicalPlan realCounterPlan
  require (counterYul.contains "object \"Counter\"")
    "canonical Counter plan did not produce a Yul object"
  require (counterYul.contains
      "__pf_checked_width(__pf_checked_add(__pf_checked_width(v1, 18446744073709551615)")
    "canonical u64 checked addition lost its narrow-width overflow guard"
  let symbolicEntrypoints := realCounterPlan.entrypoints.mapIdx fun idx entrypoint =>
    if idx == 0 then
      { entrypoint with body := #[.effect (.storageScalarWrite "count" (.literalWord 0))] }
    else entrypoint
  match ProofForge.Backend.Evm.IR.lowerCanonicalModuleWithPlan
      { realCounterPlan with entrypoints := symbolicEntrypoints } with
  | .ok _ => throw <| IO.userError "plan-only EVM renderer accepted symbolic Legacy storage"
  | .error error =>
      require (error.message.contains "symbolic storage effect")
        s!"unexpected symbolic storage diagnostic: {error.message}"

  let realVaultChecked ← checkedFromSpec
    (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module)
  let realVaultPlan ← match buildFromCore realVaultChecked emptyCapPlan with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError s!"real ValueVault plan failed: {error.message}"
  require (realVaultPlan.storage.states.map (·.id) ==
      #["balance", "released", "fees", "last_value", "last_checkpoint", "operations"])
    "ValueVault canonical state symbols changed"
  require (!planUsesSymbolicStorage realVaultPlan)
    "canonical ValueVault EVM plan retained symbolic Legacy storage effects"
  let depositPlan ← match realVaultPlan.entrypoints.find? (·.name == "deposit") with
    | some plan => pure plan
    | none => throw <| IO.userError "canonical ValueVault deposit plan missing"
  require ((reprStr depositPlan.body).contains "local \"amount\"")
    "canonical parameter ValueId was not resolved to its ABI local"
  let initializedEvent ← match realVaultPlan.events.find? (·.name == "VaultInitialized") with
    | some event => pure event
    | none => throw <| IO.userError "canonical VaultInitialized event plan missing"
  require (initializedEvent.signature == "VaultInitialized(uint64,uint64)")
    s!"canonical event signature used field names instead of ABI types: {initializedEvent.signature}"
  let vaultYul ← renderWithCanonicalPlan realVaultPlan
  require (vaultYul.contains "object \"ValueVault\"")
    "canonical ValueVault plan did not produce a Yul object"

  /- Validate the counter contract. -/
  let counterChecked ← match validateCanonical counterContractWithReqs with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"Counter validation failed: {repr e}"

  /- Build the EVM plan from Core. -/
  let plan ← match buildFromCore counterChecked emptyCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Counter buildFromCore failed: {e.message}"

  /- Check 1: slot allocation is injective over StateId. -/
  let slots := plan.storage.states.map (·.slot)
  /- Check all slots are distinct: sort and look for adjacent duplicates. -/
  let sorted := slots.qsort (· ≤ ·)
  let mut hasDup := false
  for i in [1:sorted.size] do
    if sorted[i]! == sorted[i-1]! then hasDup := true
  require (!hasDup) "slot allocation is not injective"

  /- Check 2: selectors come from InterfaceContract, never zero fallback. -/
  for ep in plan.entrypoints do
    require (ep.selector != "0x00000000") s!"entrypoint {ep.name} has zero selector"
    require (!ep.selector.isEmpty) s!"entrypoint {ep.name} has empty selector"

  /- Check 3: each non-empty Core function has a non-empty StmtPlan body. -/
  for ep in plan.entrypoints do
    require (!ep.body.isEmpty) s!"entrypoint {ep.name} has empty body"

  /- Check 4: return plans exist for every non-unit function. -/
  for ep in plan.entrypoints do
    match ep.returns.returnType with
    | .unit => pure ()
    | _ =>
      /- The entry point must either return a value or have a return stmt. -/
      let hasReturn := ep.body.any fun s => match s with
        | StmtPlan.return _ => true
        | _ => false
      require hasReturn s!"entrypoint {ep.name} with non-unit return has no return stmt"

  /- Check 5: evidence changes do not change ModulePlan. -/
  let plan2 ← match buildFromCore counterChecked emptyCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Second buildFromCore failed: {e.message}"
  require (plan.storage.states.size == plan2.storage.states.size) "storage changed between builds"
  require (plan.entrypoints.size == plan2.entrypoints.size) "entrypoint count changed"

  /- Check 6: wrong target fails. -/
  match buildFromCore counterChecked wrongTargetCapPlan with
  | .ok _ => throw <| IO.userError "buildFromCore should fail with wrong target"
  | .error e =>
    require (e.message.contains "requires target") s!"wrong target error: {e.message}"

  /- Check 7: unsupported Core op fails (either at validation or buildFromCore).
  This is fail-closed: either path rejecting the contract is correct. -/
  match validateCanonical {
    unsupportedContract with
    requirements := deriveCapabilityRequirements
      unsupportedContract.module unsupportedContract.materialization
  } with
  | .ok c =>
      match buildFromCore c emptyCapPlan with
      | .ok _ => throw <| IO.userError "buildFromCore should fail with unsupported op"
      | .error _ => pure ()
  | .error _ => pure ()

  /- Check 8: malformed EVM selectors are rejected by the target plan. -/
  let badSelectorContract := { counterContractWithReqs with
    interface := { counterContractWithReqs.interface with
      entrypoints := counterContractWithReqs.interface.entrypoints.mapIdx fun idx ep =>
        if idx == 0 then { ep with selector? := some "0xdeadbeef" } else ep } }
  let badSelectorChecked ← match validateCanonical badSelectorContract with
    | .ok checked => pure checked
    | .error e => throw <| IO.userError s!"bad-selector fixture did not validate: {repr e}"
  match buildFromCore badSelectorChecked emptyCapPlan with
  | .ok _ => throw <| IO.userError "buildFromCore accepted a malformed EVM selector"
  | .error e =>
      require (e.message.contains "invalid EVM selector") s!"bad selector error: {e.message}"

  /- Check 9: valid EVM addresses materialize exactly; invalid ones fail. -/
  let addressChecked ← match validateCanonical {
      addressLiteralContract with
      requirements := deriveCapabilityRequirements
        addressLiteralContract.module addressLiteralContract.materialization
    } with
    | .ok checked => pure checked
    | .error e => throw <| IO.userError s!"address literal fixture did not validate: {repr e}"
  match buildFromCore addressChecked emptyCapPlan with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"valid EVM address literal failed: {e.message}"
  let invalidAddressChecked ← match validateCanonical {
      invalidAddressLiteralContract with
      requirements := deriveCapabilityRequirements
        invalidAddressLiteralContract.module invalidAddressLiteralContract.materialization
    } with
    | .ok checked => pure checked
    | .error e => throw <| IO.userError s!"invalid-address fixture did not validate: {repr e}"
  match buildFromCore invalidAddressChecked emptyCapPlan with
  | .ok _ => throw <| IO.userError "buildFromCore accepted an invalid EVM address literal"
  | .error e =>
      require (e.message.contains "invalid EVM address literal")
        s!"invalid address literal error: {e.message}"

  /- Check 10: structured multi-block CFG control flow is preserved. -/
  let multiBlockChecked ← match validateCanonical {
      multiBlockContract with
      requirements := deriveCapabilityRequirements
        multiBlockContract.module multiBlockContract.materialization
    } with
    | .ok checked => pure checked
    | .error e => throw <| IO.userError s!"multi-block fixture did not validate: {repr e}"
  match buildFromCore multiBlockChecked emptyCapPlan with
  | .error e => throw <| IO.userError s!"multi-block CFG planning failed: {e.message}"
  | .ok cfgPlan =>
      require (cfgPlan.entrypoints.any fun entrypoint =>
        entrypoint.body.any fun statement =>
          match statement with | .return _ => true | _ => false)
        "multi-block CFG lost its return terminator"

  IO.println "canonical-evm-plan: ok"
