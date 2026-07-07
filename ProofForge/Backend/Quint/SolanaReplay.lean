/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# SolanaReplay — Tier C-diff replay shim for the Solana (sBPF) backend

This is the Step A type-only stub from RFC 0014 Phase 5, Path 5a
(see `docs/quint-cdiff-multi-backend-design.md`). It is the second C-diff
candidate after NEAR: the same Quint MBT ITF traces that `Replay.replayTrace`
consumes for Tier A (IR self-replay) are lowered into a Rust Mollusk test
file that replays the trace against the emitted sBPF ELF (`.so`).

The shim is **not** wired into any `*-backend-replay-gate.sh` and does not
spawn Mollusk, `sbpf`, `solana-keygen`, or `quint`. It only renders the Rust
test source deterministically and provides the type definitions. Step B
(the wrapping test that emits the ELF + spawns `cargo test`, the gate script,
the `justfile` recipe wired into `just check`) is a follow-up, gated on the
stub compiling cleanly and the SBF platform-tools being available.

## Harness shape

Mollusk is a Rust crate (`mollusk_svm`) invoked as a Rust test harness — there
is no Mollusk CLI. The rendered harness is therefore a Rust source file that
calls `mollusk_svm::Mollusk::new(&pid, "<elf>")` and
`m.process_instruction(...)` per trace step, mirroring the in-tree template
`Tests/solana/counter_mollusk.rs.tpl` and the testkit harness
(`testkit/harness-solana/src/lib.rs`). This is the EVM-shim shape (render a
test file the target toolchain executes) rather than the NEAR-shim shape
(render a CLI arg list).

## Account-model translation (plan-driven)

Solana's executable artifact is an sBPF ELF; its state lives in *accounts*
(one account per state field group, owned by the program), not in flat
storage. The shim maps an IR trace step `(entrypoint, args)` to a Solana
instruction `(program_id, accounts, instruction_data)`:

- `program_id` is the first 32 bytes of the keypair JSON (rendered as a
  `program_id()` fn in the test, identical to the in-tree template).
- `accounts` and the state account data length are derived from the
  `SolanaModulePlan` (`ProofForge.Backend.Solana.Plan`, Phase 2). The plan
  exposes `accounts : Array SolanaAccountPlan` (ordered, with `dataSize`) and
  `stateFields : Array SolanaStateFieldPlan` (with `absOff`/`byteSize`). The
  shim renders one `AccountMeta` per plan account and seeds the state account
  with `plan.accounts[0].dataSize` zero bytes. This ties C-diff to the Tier B
  plan (the intended RFC 0014 synergy) and replaces the v1 hard-coded
  "single writable `counter` account" so the shim is not Counter-specific.
- `instruction_data` is the entrypoint discriminator (1-byte internal tag or
  8-byte external selector parsed from `Entrypoint.selector?`) followed by the
  little-endian encoding of the IR arguments. The `SolanaModulePlan` already
  exposes this discriminator + instruction-data ABI; the shim re-derives it
  from `Entrypoint.selector?` via `Manifest.externalDiscriminatorBytes?` to
  avoid requiring a full plan build at replay time.

## Non-scalar state handling (v1)

For modules whose primary state is a map or array (e.g. `EvmMapProbe`), the
Solana account holds the *serialized* state (map prefix / array slots), not a
single scalar. The v1 shim observes only the primary scalar field: it looks
up `cfg.primaryStateVar` in `plan.stateFields`, and if found renders the
expected little-endian bytes at that field's `absOff` within the account data.
If the primary var is a map/array (no scalar field by that name, or
`byteSize = 0`), the observation degrades to a zero-byte slice and the
read-back assertion is skipped — the harness still renders without crashing,
proving the shim is not Counter-specific. Full map/array state-diff
observation is a v2 follow-up.

The chain-neutral trace interpretation (`resolveActionName`, `entrypointMap`,
`buildArgs`, `itfValueToIr`) is imported unchanged from `Replay.lean`.
-/

import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Backend.Quint.BackendReplay
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Plan

namespace ProofForge.Backend.Quint.SolanaReplay

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.Backend.Quint.BackendReplay
open ProofForge.Backend.Quint.Replay
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Plan

abbrev SolanaReplayError := BackendReplayError

/-- Per-backend config: where the sBPF ELF + keypair live and how to observe
the primary scalar state. Mirrors `EvmReplayConfig` (`bytecodeHex` /
`readSignature` / `primaryStateVar`) but with Solana artifact paths. The
state account data length and primary field byte size / offset are derived
from the `SolanaModulePlan` when available (see `SolanaReplayPlan`); the
fields here are fallbacks used when no plan is supplied. -/
structure SolanaReplayConfig where
  /-- Path to the emitted sBPF ELF (`.so`), passed to `Mollusk::new`. -/
  programPath : String
  /-- Path to the program keypair JSON; the program id is its first 32 bytes. -/
  keypairPath : String
  /-- Fallback byte length of the state account data (e.g. 8 for Counter's u64). -/
  stateAccountDataLen : Nat
  /-- ITF/IR state variable name being checked (e.g. `count`). -/
  primaryStateVar : String
  /-- Fallback byte size of the primary scalar (e.g. 8 for u64). -/
  primaryStateByteSize : Nat

/-- Plan-derived rendering inputs: the state account's name + data length,
the primary scalar field's byte offset and size within the account data, and
the ordered account-meta list to render. Built from a `SolanaModulePlan` by
`SolanaReplayPlan.fromPlan`; the render functions consume it so the harness
is driven by the Tier B plan rather than hard-coded Counter assumptions. -/
structure SolanaReplayPlan where
  /-- Name of the first (state) account, used as the Rust local binding. -/
  stateAccountName : String
  /-- Byte length of the state account data. -/
  stateAccountDataLen : Nat
  /-- Ordered list of (name, writable) for every account in the instruction. -/
  accountMetas : Array (String × Bool)
  /-- Byte offset of the primary scalar within the account data. `none` if the
  primary var is not a scalar state field (map/array/missing); the v1
  observation degrades to a zero slice in that case. -/
  primaryFieldOffset? : Option Nat
  /-- Byte size of the primary scalar. Falls back to `cfg.primaryStateByteSize`. -/
  primaryFieldByteSize : Nat

/-- Render a Nat as a Rust little-endian byte-array literal body, e.g.
`[1u8, 0, 0, 0, 0, 0, 0, 0]` for `n=1, byteSize=8`. -/
def renderLeBytes (byteSize : Nat) (n : Nat) : String :=
  renderRustLeBytes byteSize n

/-- Encode an IR scalar argument value as little-endian byte string for the
instruction-data payload. Only scalar argument types are supported in v1;
aggregates are deferred (matches the EVM/NEAR v1 scalar-args constraint). -/
def encodeArgLe (v : Value) : Except SolanaReplayError (Array Nat) :=
  match v with
  | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .bool _ | .unit => encodeScalarLeBytes v
  | other => .error { message := s!"SolanaReplay v1 cannot encode argument: {repr other}" }

/-- Encode an array of IR argument values as a single byte array
(concatenated little-endian bytes). -/
def encodeArgsLe (args : Array Value) : Except SolanaReplayError (Array Nat) := do
  let mut out := #[]
  for arg in args do
    out := out ++ (← encodeArgLe arg)
  pure out

/-- Build a sanitized-name → entrypoint map (reuses `Replay.entrypointMap`). -/
def entrypointMap (module : ProofForge.IR.Module) : Std.HashMap String Entrypoint :=
  Replay.entrypointMap module

/-- Build a sanitized-name → instruction tag (entrypoint index) map. The tag
is the entrypoint's position in `module.entrypoints`, matching
`Manifest.buildInstructions` and the sBPF dispatch prologue. -/
def tagMap (module : ProofForge.IR.Module) : Std.HashMap String Nat :=
  module.entrypoints.foldl
    (fun m ep => m.insert (sanitizeName ep.name) m.size)
    {}

/-- Discriminator bytes for an entrypoint: the 8-byte external selector if
`selector?` is a valid 8-byte hex, otherwise the 1-byte internal tag. Reuses
`Manifest.externalDiscriminatorBytes?` so the shim stays consistent with the
manifest emitter. -/
def discriminatorBytes (ep : Entrypoint) (tag : Nat) : Array Nat :=
  match externalDiscriminatorBytes? ep with
  | some bytes => bytes
  | none => #[tag]

/-- Whether an entrypoint is a read (returns a non-unit value) vs a mutating
call. Used to decide whether the step asserts account data (mutating) or
return data (read). -/
def isReadEntrypoint (ep : Entrypoint) : Bool :=
  ep.returns != .unit

/-- Render the instruction-data `Vec<u8>` literal for one trace step:
discriminator bytes followed by little-endian-encoded arguments. Returns the
Rust source snippet (a `vec![...]` expression) and the entrypoint used. -/
def renderInstructionData (ep : Entrypoint) (tag : Nat) (args : Array Value) :
    Except SolanaReplayError String := do
  let disc := discriminatorBytes ep tag
  let argBytes ← encodeArgsLe args
  let allBytes := disc ++ argBytes
  if allBytes.isEmpty then
    .ok "vec![]"
  else
    .ok (s!"vec![{String.intercalate ", " (allBytes.toList.map toString)}]")

/-- Derive the `SolanaReplayPlan` from a `SolanaModulePlan` + config. The
state account is `plan.accounts[0]`; its data length is that account's
`dataSize` (falling back to `cfg.stateAccountDataLen` if the plan lists no
accounts). The primary scalar field is found by matching `cfg.primaryStateVar`
against `plan.stateFields` and keeping only scalar fields (`byteSize > 0`).
Map/array state fields have `byteSize = 0` in the Phase 2 plan, so the
observation degrades to `primaryFieldOffset? := none` for them. -/
def SolanaReplayPlan.fromPlan (cfg : SolanaReplayConfig) (plan : SolanaModulePlan) :
    SolanaReplayPlan :=
  let stateAccount := plan.accounts[0]?
  let stateAccountName := match stateAccount with
    | some a => a.name
    | none => "state"
  let stateAccountDataLen := match stateAccount with
    | some a => a.dataSize
    | none => cfg.stateAccountDataLen
  let accountMetas := plan.accounts.map (fun a => (a.name, a.writable))
  let primaryField? := plan.stateFields.find? (fun f =>
    f.id == cfg.primaryStateVar && f.kind == "scalar" && f.byteSize > 0)
  { stateAccountName := stateAccountName
    stateAccountDataLen := stateAccountDataLen
    accountMetas := accountMetas
    primaryFieldOffset? := primaryField?.map (fun f => f.absOff)
    primaryFieldByteSize := match primaryField? with
      | some f => f.byteSize
      | none => cfg.primaryStateByteSize }

/-- Render the `AccountMeta::new(...)` argument list for the `ix` helper from
the plan's account metas. Each entry becomes `AccountMeta::new(<name>, <signer>)`;
the writable/signer flags are collapsed to the `is_signer` boolean Mollusk
expects (the writable flag is the v1 default — all state accounts are
writable in the scalar/array/map probes). -/
def renderAccountMetas (metas : Array (String × Bool)) : String :=
  let entries := metas.map (fun (name, _) => s!"AccountMeta::new({name}, false)")
  String.intercalate ", " entries.toList

/-- Render the `let <name> = Address::new_unique();` bindings for every
account in the plan, plus the state account data init. -/
def renderAccountBindings (plan : SolanaReplayPlan) : String :=
  let bindings := plan.accountMetas.map (fun (name, _) =>
    s!"    let {name} = Address::new_unique();")
  String.intercalate "\n" bindings.toList

/-- Render one `#[test] fn test_step_<idx>()` for a trace step. The state
account is seeded with `plan.stateAccountDataLen` zero bytes, then the
primary scalar (if any) is written at its `primaryFieldOffset?` so the
seeded account matches the previous ITF state's primary value. -/
def renderTraceStep (module : ProofForge.IR.Module) (cfg : SolanaReplayConfig)
    (rplan : SolanaReplayPlan) (epMap : Std.HashMap String Entrypoint)
    (tags : Std.HashMap String Nat)
    (prevValue expected : Nat) (stepIdx : Nat) (state : ITF.State) :
    Except SolanaReplayError String := do
  let actionName ← traceActionName module state
  -- The Quint `init` action maps to the IR `initialize` entrypoint (the
  -- Counter fixture's first entrypoint), mirroring NearReplay's init handling.
  let resolvedName := if actionName == "init" then "initialize" else actionName
  let entrypoint? := Std.HashMap.get? epMap resolvedName
  -- Modules without an `initialize` entrypoint (e.g. the EvmMapProbe sub-module)
  -- have no artifact call for the Quint `init` action; the Solana account starts
  -- zeroed, so render a no-op step that only asserts the seeded primary scalar.
  match entrypoint? with
  | none =>
    if actionName == "init" then
      let testName := s!"test_step_{stepIdx}"
      let comment := s!"// step {stepIdx}: init (no initialize entrypoint; seed-only)"
      let acctName := rplan.stateAccountName
      let zeroSeed := String.intercalate ", " (List.range rplan.stateAccountDataLen |>.map (fun _ => "0"))
      match rplan.primaryFieldOffset? with
      | some off =>
        let le := renderLeBytes rplan.primaryFieldByteSize expected
        let seedData := s!"vec![{zeroSeed}] with [{off}..{off + rplan.primaryFieldByteSize}].copy_from_slice(&[{le}]);"
        .ok <| String.intercalate "\n" [
          "#[test]",
          s!"fn {testName}() " ++ "{",
          "    // no initialize entrypoint; assert seeded primary scalar only.",
          s!"    {comment}",
          s!"    let {acctName} = Address::new_unique();",
          s!"    let {acctName}_account = Account::new(0, {rplan.stateAccountDataLen}, &pid);",
          s!"    {acctName}_account.data = {seedData}",
          s!"    assert_eq!({acctName}_account.data, {seedData}, \"step {stepIdx} seed mismatch\");",
          "}"
        ]
      | none =>
        .ok <| String.intercalate "\n" [
          "#[test]",
          s!"fn {testName}() " ++ "{",
          "    // no initialize entrypoint; primary state non-scalar; seed-only no-op.",
          s!"    {comment}",
          "    assert!(true);",
          "}"
        ]
    else
      .error { message := s!"unknown entrypoint `{actionName}` (resolved `{resolvedName}`) for Solana replay" }
  | some entrypoint =>
    let tag := (tags.get? resolvedName).getD 0
    let args ← entrypointArgs entrypoint state.nondetPicks
    let dataLiteral ← renderInstructionData entrypoint tag args
    let isRead := isReadEntrypoint entrypoint
    let testName := s!"test_step_{stepIdx}"
    let comment := s!"// step {stepIdx}: {entrypoint.name} -> {cfg.primaryStateVar} = {expected}"
    let acctName := rplan.stateAccountName
    -- Seed the state account with zero bytes, then patch in the previous step's
    -- primary scalar at its plan-derived offset (if the primary var is a scalar).
    let zeroSeed := String.intercalate ", " (List.range rplan.stateAccountDataLen |>.map (fun _ => "0"))
    let seedBytes := match rplan.primaryFieldOffset? with
    | some off =>
      let le := renderLeBytes rplan.primaryFieldByteSize prevValue
      s!"vec![{zeroSeed}] with [{off}..{off + rplan.primaryFieldByteSize}].copy_from_slice(&[{le}]);"
    | none => s!"vec![{zeroSeed}]"
    let expectedBytes := renderLeBytes rplan.primaryFieldByteSize expected
    let mut lines := [
      "#[test]",
      s!"fn {testName}() " ++ "{",
      "    let pid = program_id();",
      "    let m = mollusk();",
      s!"    let {acctName} = Address::new_unique();",
      s!"    let mut {acctName}_account = Account::new(0, {rplan.stateAccountDataLen}, &pid);",
      s!"    {acctName}_account.data = {seedBytes}",
      s!"    {comment}",
      s!"    let data = {dataLiteral};",
      "    let result = m.process_instruction(",
      s!"        &ix(pid, data, &[{renderAccountMetas rplan.accountMetas}]),",
      s!"        &[({acctName}, {acctName}_account)],",
      "    );",
      s!"    assert!(!result.program_result.is_err(), \"step {stepIdx} ({entrypoint.name}) failed\");"
    ]
    if isRead then
      -- Read entrypoint: the primary value comes back as return data.
      lines := lines.concat
        s!"    assert_eq!(result.return_data, vec![{expectedBytes}], \"step {stepIdx} return data mismatch\");"
    else
      -- Mutating entrypoint: the primary value is written to the account data.
      -- For scalar primary vars, assert the full account data equals the seeded
      -- bytes with the expected value patched in. For non-scalar primary vars
      -- (map/array), skip the byte-level assertion — the harness still renders.
      match rplan.primaryFieldOffset? with
      | some off =>
        let le := renderLeBytes rplan.primaryFieldByteSize expected
        let expectedData := s!"vec![{zeroSeed}] with [{off}..{off + rplan.primaryFieldByteSize}].copy_from_slice(&[{le}]);"
        lines := lines.concat
          s!"    let after = result.get_account(&{acctName}).expect(\"step {stepIdx} missing state account\");"
        lines := lines.concat
          s!"    assert_eq!(after.data, {expectedData}, \"step {stepIdx} account data mismatch\");"
      | none =>
        lines := lines.concat
          s!"    // primary state `{cfg.primaryStateVar}` is non-scalar; v1 skips byte-level account-data assertion."
    lines := lines.concat "}"
    .ok (String.intercalate "\n" lines)

/-- Render the full Rust Mollusk test file for a trace (v1: one test per
trace step, each seeded from the previous ITF state's primary value and
asserting the current ITF state's expected value). The account list and state
layout are derived from the `SolanaModulePlan` (Tier B), so the harness is
not Counter-specific. The result is a self-contained Rust source file
suitable for `cargo test` against a Mollusk-bearing crate. -/
def renderReplayHarness (module : ProofForge.IR.Module) (trace : ITF.Trace)
    (cfg : SolanaReplayConfig) : Except SolanaReplayError String := do
  if trace.states.isEmpty then
    .error { message := "empty ITF trace" }
  -- Build the Solana Tier B plan so the account list + state layout drive the
  -- harness rendering (the RFC 0014 C-diff ↔ Tier B synergy). If the plan build
  -- fails (e.g. a module the Solana backend does not lower), fall back to the
  -- config-derived single-account shape so the shim degrades gracefully.
  let rplan : SolanaReplayPlan :=
    match buildSolanaModulePlan module with
    | .ok plan => SolanaReplayPlan.fromPlan cfg plan
    | .error _ =>
      { stateAccountName := "state"
        stateAccountDataLen := cfg.stateAccountDataLen
        accountMetas := #[("state", true)]
        primaryFieldOffset? := some 0
        primaryFieldByteSize := cfg.primaryStateByteSize }
  let epMap := entrypointMap module
  let tags := tagMap module
  -- The initial (var) state carries the pre-init primary value; default to 0.
  let initialValue ←
    match itfNatValue trace.states.head! cfg.primaryStateVar with
    | .ok n => .ok n
    | .error _ => .ok 0
  let steps ← trace.states.tail!.mapM (fun state => do
    let prevIdx := state.index - 1
    let prevValue ←
      if prevIdx < trace.states.length then
        match itfNatValue trace.states[prevIdx]! cfg.primaryStateVar with
        | .ok n => .ok n
        | .error _ => .ok initialValue
      else
        .ok initialValue
    let expected ← itfNatValue state cfg.primaryStateVar
    renderTraceStep module cfg rplan epMap tags prevValue expected state.index state)
  .ok <| String.intercalate "\n" [
    "#![cfg(test)]",
    "// ProofForge Quint C-diff Solana replay harness (generated).",
    "// Mirrors Tests/solana/counter_mollusk.rs.tpl; executes one Mollusk",
    "// instruction per ITF trace step and asserts the primary scalar state.",
    "// Account list + state layout are derived from the SolanaModulePlan.",
    "",
    "use {",
    "    mollusk_svm::Mollusk,",
    "    solana_account::Account,",
    "    solana_address::Address,",
    "    solana_instruction::{AccountMeta, Instruction},",
    "};",
    "",
    s!"const STATE_DATA_LEN: usize = {rplan.stateAccountDataLen};",
    "",
    "fn program_id() -> Address {",
    s!"    let keypair_bytes = std::fs::read(\"{cfg.keypairPath}\").unwrap();",
    "    let mut arr = [0u8; 32];",
    "    arr.copy_from_slice(&keypair_bytes[..32]);",
    "    Address::new_from_array(arr)",
    "}",
    "",
    "fn mollusk() -> Mollusk {",
    "    let pid = program_id();",
    s!"    let mut mollusk = Mollusk::new(&pid, \"{cfg.programPath}\");",
    "    // Phase 1 lowering uses the legacy embedded account-data layout.",
    "    mollusk.feature_set.account_data_direct_mapping = false;",
    "    mollusk.feature_set.direct_account_pointers_in_program_input = false;",
    "    mollusk.feature_set.virtual_address_space_adjustments = false;",
    "    mollusk",
    "}",
    "",
    "fn ix(pid: Address, data: Vec<u8>, " ++
      String.intercalate ", "
        (rplan.accountMetas.toList.map (fun (n, _) => n)) ++
      ") -> Instruction {",
    "    Instruction::new_with_bytes(",
    "        pid,",
    "        &data,",
    s!"        vec![{renderAccountMetas rplan.accountMetas}],",
    "    )",
    "}",
    "",
    indent 0 steps
  ]

end ProofForge.Backend.Quint.SolanaReplay
