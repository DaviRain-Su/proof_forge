/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Target preflight (IR-level gates before materialize)

Answers the product question: **do we validate on the IR before chain
materialization?** Yes — in **layers**. Preflight is the shared orchestrator
that runs *before* target-native packing (CPI / CALL / Promise /
`invoke_contract`):

```text
IR.Module
  ├─ L0  Portability (family-only constructors)     IR.Portability
  ├─ L1  Capability resolve                         Target.Adapter.resolveModule
  ├─ L2  Protocol-shaped IR checks (per backend)    Evm.Validate / Solana / EmitWat
  └─ L3  Materialize + native emit                  Materialize / CPI / CALL / Promise / Soroban invoke
```

| Layer | Question | Maps to materialize? |
|---|---|---|
| L0 Portability | Is this constructor legal for *any* portable path / this family? | No — reject early |
| L1 Capability | Does `--target X` advertise the needed capabilities? | Gates materialize |
| L2 Protocol IR | Target-specific well-formedness still on IR (types, returns, …) | Feeds plan |
| L3 Materialize | Account roles, CPI pack, CALL ABI, Promise strings | **Is** materialize |
| L4 Prologue / emit | Solana signer/owner traps; Yul/WAT specifics | After schema exists |

Solana Anchor/Pinocchio-style **account** checks are **L3→L4**: schema from
materialize, traps in entrypoint prologue — not portable IR nodes.

This module implements **L0+L1+L2 preflight** as one report (PF-P1-04). L2 runs
when `TargetBackend` registers validate/plan/package hooks; secondary targets
without hooks keep L0∧L1 readiness only.
-/
import ProofForge.IR.Contract
import ProofForge.IR.Portability
import ProofForge.Target.Adapter
import ProofForge.Target.Backend
import ProofForge.Target.BackendRegistry
import ProofForge.Target.Registry
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Target.PortableHonesty

namespace ProofForge.Target.Preflight

open ProofForge.IR
open ProofForge.IR.Portability
open ProofForge.Target
open ProofForge.Target.CrosscallMaterialize
open ProofForge.Target.PortableHonesty

structure Report where
  targetId : String
  /-- L1 capability plan resolved (empty when failed). -/
  capabilityOk : Bool
  capabilityError? : Option String
  /-- L0 hard: no *family-only constructors* illegal on this family
  (e.g. nearPromiseThen on Solana). Foreign *metadata* (e.g. nearCrosscallStrings
  on EVM) is recorded but does not block materialize — backends ignore it. -/
  portabilityOk : Bool
  portabilityViolations : Array String
  /-- Soft: foreign target metadata present (ignored by this family). -/
  metadataNotes : Array String
  /-- Declared native form for portable crosscall (if any). -/
  crosscallNativeForm : String
  /-- L2 backend fragment validation when TargetBackend registers hooks (PF-P1-04).
  `true` when no L2 hooks are registered, or when validate/plan/package pass. -/
  backendOk : Bool := true
  backendError? : Option String := none
  /-- `notRegistered` | `passed` | `failed` | `skippedL1` (L2 not run after L1 fail). -/
  backendStage : String := "notRegistered"
  /-- Ready for target materialize/emit: hard L0 ∧ L1 ∧ L2 (when L2 is registered). -/
  readyToMaterialize : Bool
  note : String
  deriving Repr

private def jsonStr (s : String) : String := "\"" ++ s ++ "\""

private def jsonStrOption : Option String → String
  | none => "null"
  | some s => jsonStr s

def Report.json (r : Report) : String :=
  "{" ++
  "\"targetId\":" ++ jsonStr r.targetId ++ "," ++
  "\"capabilityOk\":" ++ (if r.capabilityOk then "true" else "false") ++ "," ++
  "\"portabilityOk\":" ++ (if r.portabilityOk then "true" else "false") ++ "," ++
  "\"backendOk\":" ++ (if r.backendOk then "true" else "false") ++ "," ++
  "\"backendStage\":" ++ jsonStr r.backendStage ++ "," ++
  "\"backendError\":" ++ jsonStrOption r.backendError? ++ "," ++
  "\"readyToMaterialize\":" ++ (if r.readyToMaterialize then "true" else "false") ++ "," ++
  "\"crosscallNativeForm\":" ++ jsonStr r.crosscallNativeForm ++ "," ++
  "\"note\":" ++ jsonStr r.note ++
  "}"

/-- Hard L0: only `targetFamilyOnly` mismatches block materialize.
`targetMetadata` for another family is soft (backends ignore foreign metadata). -/
def hardPortabilityViolations (module : Module) (family : TargetFamily) :
    Array PortabilityFinding :=
  (classifyModule module).filter fun f =>
    match f.class_ with
    | .targetFamilyOnly other => other != family
    | _ => false

def softMetadataNotes (module : Module) (family : TargetFamily) : Array PortabilityFinding :=
  (classifyModule module).filter fun f =>
    match f.class_ with
    | .targetMetadata (some other) => other != family
    | _ => false

/-- Run L2 **supported-fragment** validation via TargetBackend hooks (PF-P1-04).

Returns `(ok, stage, error?)` where stage is `notRegistered` | `passed` | `failed`.

L2 readiness uses `validateModule` (the fragment/well-formedness gate). Plan and
package dry-runs remain available on TargetBackend for `check`/emit paths, but
are **not** folded into `readyToMaterialize` here: some backends still diverge
between plan surface and production lower (e.g. NEAR nested mapKey paths).
-/
def runBackendL2 (profile : TargetProfile) (module : Module) (_plan? : Option CapabilityPlan) :
    Bool × String × Option String :=
  match findBackend? profile.id with
  | none => (true, "notRegistered", none)
  | some backend =>
      if !backend.hasValidate then
        (true, "notRegistered", none)
      else
        match backend.validateModule module with
        | .error err => (false, "failed", some err.message)
        | .ok () => (true, "passed", none)

/-- Run L0 portability + L1 capability + L2 backend fragment preflight for one target.

Portable honesty (HostEnv/Identity/sync-crosscall) is enforced inside
`resolveModule` → `defaultResolve`; this report surfaces that as capabilityOk
failure with the PortableHonesty diagnostic text. When TargetBackend registers
validate/plan/package hooks, `readyToMaterialize` requires those L2 stages too
(PF-P1-04).
-/
def run (profile : TargetProfile) (module : Module) : Report :=
  let capResult := resolveModule profile module
  let (capabilityOk, capabilityError?, plan?) :=
    match capResult with
    | .ok plan => (true, none, some plan)
    | .error e => (false, some e.render, none)
  let hard := hardPortabilityViolations module profile.family
  let soft := softMetadataNotes module profile.family
  let portabilityOk := hard.isEmpty
  let violStrs := hard.map renderFinding
  let metaStrs := soft.map renderFinding
  let xform := (forProfile profile).nativeForm.id
  -- Explicit sync-subset note for report consumers (also enforced in resolve).
  let syncNote :=
    if moduleUsesPortableSyncCrosscall module && moduleUsesNearAsyncExtension module then
      " [portable sync-subset forbids mixing crosscallInvoke with promise_then/result]"
    else if moduleUsesPortableSyncCrosscall module then
      " [portable sync-subset remote]"
    else ""
  -- L2 only after L0+L1 hard gates (avoid noisy backend errors on illegal modules).
  let (backendOk, backendStage, backendError?) :=
    if capabilityOk && portabilityOk then
      runBackendL2 profile module plan?
    else
      (true, "skippedL1", none)
  let ready := capabilityOk && portabilityOk && backendOk
  let note :=
    if ready then
      let softNote :=
        if metaStrs.isEmpty then ""
        else s!" (soft metadata ignored: {String.intercalate "; " metaStrs.toList})"
      let l2Note :=
        if backendStage == "notRegistered" then
          " (L2 hooks not registered on TargetBackend)"
        else
          " (L0+L1+L2 ok)"
      s!"preflight ok → materialize as {xform}{l2Note}{softNote}{syncNote}"
    else if !capabilityOk then
      s!"capability/honesty reject: {capabilityError?.getD "?"}"
    else if !portabilityOk then
      s!"portability reject: {String.intercalate "; " violStrs.toList}"
    else
      s!"backend L2 reject: {backendError?.getD "?"}"
  { targetId := profile.id
    capabilityOk := capabilityOk
    capabilityError? := capabilityError?
    portabilityOk := portabilityOk
    portabilityViolations := violStrs
    metadataNotes := metaStrs
    crosscallNativeForm := xform
    backendOk := backendOk
    backendError? := backendError?
    backendStage := backendStage
    readyToMaterialize := ready
    note := note }

/-- Preflight primary three targets used by portable multi-target demos. -/
def runPrimary (module : Module) : Array Report :=
  #[run evm module, run solanaSbpfAsm module, run wasmNear module]

/-- Primary triad + Soroban host-adapter profile (not in `Registry.all`). -/
def runPrimaryWithSoroban (module : Module) : Array Report :=
  runPrimary module |>.push (run wasmStellarSoroban module)

def allReady (reports : Array Report) : Bool :=
  reports.all (fun r => r.readyToMaterialize)

end ProofForge.Target.Preflight
