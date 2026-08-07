import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.TargetRegistryV1
import Tests.Language.ParserSession

namespace Tests.Materialization.BuildSelectionV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectErrorCode (result : CompileResult α) (code : String) (message : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code) s!"{message}: got {error.code}: {error.message}"
  | .ok _ => throw <| IO.userError s!"{message}: expected error {code}"

private def expectParseTarget (input : String) (ok : Bool) : IO Unit :=
  match TargetId.parse? input, ok with
  | some _, true => pure ()
  | none, false => pure ()
  | some id, false => throw <| IO.userError s!"TargetId.parse? accepted '{input}' → {id}"
  | none, true => throw <| IO.userError s!"TargetId.parse? rejected '{input}'"

private def expectParseProfile (input : String) (ok : Bool) : IO Unit :=
  match CodegenProfileId.parse? input, ok with
  | some _, true => pure ()
  | none, false => pure ()
  | some id, false => throw <| IO.userError s!"CodegenProfileId.parse? accepted '{input}' → {id}"
  | none, true => throw <| IO.userError s!"CodegenProfileId.parse? rejected '{input}'"

private def expectParseNetwork (input : String) (ok : Bool) : IO Unit :=
  match NetworkProfileId.parse? input, ok with
  | some _, true => pure ()
  | none, false => pure ()
  | some id, false => throw <| IO.userError s!"NetworkProfileId.parse? accepted '{input}' → {id}"
  | none, true => throw <| IO.userError s!"NetworkProfileId.parse? rejected '{input}'"

/-- Test-local profile parse: IO/Except only — never substitutes a shipped
identity on grammar failure. -/
private def parseProfile (s : String) : IO CodegenProfileId :=
  match CodegenProfileId.parse? s with
  | some id => pure id
  | none => throw <| IO.userError s!"test fixture profile failed grammar: '{s}'"

private def materializeSelected (target : TargetId) (compiled : CompiledSemanticV1)
    (profile? : Option CodegenProfileId := none) : CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

/-- Closed-policy EVM registration fixture (exact kind policy fields). -/
private def evmAxes : TargetSemanticsAxesV1 := {
  targetId := TargetId.evm
  executionHost := .evm
  commitModel := .transactionAtomic
  stateBinding := .contractStorage
  callModel := .synchronousMessage
  proofModel := .noProof
  settlementModel := .evmChain
}

private def mkEvmReg
    (profiles : Array CodegenProfileId) (defaultProfile : Option CodegenProfileId) :
    TargetRegistrationDataV1 := {
  targetId := TargetId.evm
  kind := .evm
  implemented := true
  displayName := "EVM"
  acceptanceProfileId := "phase1.evm-u64.v1"
  maturityLabel := "runtime-validated-alpha"
  semantics := evmAxes
  profiles
  defaultProfile
}

private def mkNearReg
    (profiles : Array CodegenProfileId) (defaultProfile : Option CodegenProfileId) :
    TargetRegistrationDataV1 := {
  targetId := TargetId.near
  kind := .near
  implemented := true
  displayName := "NEAR"
  acceptanceProfileId := "phase1.near-u64.v1"
  maturityLabel := "wasm-validated-alpha"
  semantics := {
    targetId := TargetId.near
    executionHost := .nearWasm
    commitModel := .receiptLocal
    stateBinding := .contractKeyValue
    callModel := .promiseDag
    proofModel := .noProof
    settlementModel := .nearChain
  }
  profiles
  defaultProfile
}

private def mkAleoReg
    (profiles : Array CodegenProfileId) (defaultProfile : Option CodegenProfileId) :
    TargetRegistrationDataV1 := {
  targetId := TargetId.aleo
  kind := .aleo
  implemented := false
  displayName := "Aleo"
  acceptanceProfileId := "research.aleo.v1"
  maturityLabel := "research-only"
  semantics := {
    targetId := TargetId.aleo
    executionHost := .aleoVm
    commitModel := .proofFinalDual
    stateBinding := .recordsMappings
    callModel := .programProofFinal
    proofModel := .applicationChainProof
    settlementModel := .aleoChain
  }
  profiles
  defaultProfile
}

private def mkSolanaReg
    (profiles : Array CodegenProfileId) (defaultProfile : Option CodegenProfileId) :
    TargetRegistrationDataV1 := {
  targetId := TargetId.solana
  kind := .solana
  implemented := true
  displayName := "Solana"
  acceptanceProfileId := "phase1.solana-u64.v1"
  maturityLabel := "plan-only"
  semantics := {
    targetId := TargetId.solana
    executionHost := .svm
    commitModel := .instructionAtomic
    stateBinding := .explicitAccounts
    callModel := .synchronousCpi
    proofModel := .noProof
    settlementModel := .solanaChain
  }
  profiles
  defaultProfile
}

private def testGrammar : IO Unit := do
  expectParseTarget "e" true
  expectParseTarget "evm" true
  expectParseTarget "a-b" true
  expectParseTarget "a--" true
  expectParseTarget "ab-" true
  expectParseTarget (String.ofList (List.replicate 32 'a')) true
  expectParseTarget "" false
  expectParseTarget "Evm" false
  expectParseTarget "1evm" false
  expectParseTarget "ev.m" false
  expectParseTarget "ev_m" false
  expectParseTarget (String.ofList (List.replicate 33 'a')) false
  expectParseTarget "év" false
  expectParseTarget "a b" false
  expectParseProfile "a" true
  expectParseProfile "evm-yul-solc-0.8.34-v1" true
  expectParseProfile "a.b" true
  expectParseProfile "a-b.c0" true
  expectParseProfile "a-" false
  expectParseProfile "a." false
  expectParseProfile "a--b" false
  expectParseProfile "a..b" false
  expectParseProfile "a-.b" false
  expectParseProfile "A" false
  expectParseProfile "" false
  expectParseProfile (String.ofList (List.replicate 128 'a')) false
  expectParseProfile (String.ofList (List.replicate 127 'a')) true
  expectParseProfile "év" false
  expectParseNetwork "mainnet" true
  expectParseNetwork "a--" false
  expectParseNetwork "Main" false
  expect (CodegenProfileId.evmYulSolc0834V1 == (← parseProfile "evm-yul-solc-0.8.34-v1"))
    "well-known evm profile constant"
  expect (CodegenProfileId.evmYulSolc0834CancunV1 ==
      (← parseProfile "evm-yul-solc-0.8.34-cancun-v1"))
    "well-known evm cancun profile constant"
  expect (CodegenProfileId.solanaSbpfPlanV1 == (← parseProfile "solana-sbpf-plan-v1"))
    "well-known solana plan profile constant"
  expect (CodegenProfileId.solanaSbpfCpiElfV1 ==
      (← parseProfile "solana-sbpf-cpi-elf-v1"))
    "well-known inert solana cpi profile constant"
  expect (CodegenProfileId.solanaSbpfElfV1 == (← parseProfile "solana-sbpf-elf-v1"))
    "well-known solana elf profile constant"
  expect (CodegenProfileId.nearWasmRawU64V1 == (← parseProfile "near-wasm-raw-u64-v1"))
    "well-known near profile constant"
  expect (CodegenProfileId.noirSourceU64RelationsV1 == (← parseProfile "noir-source-u64-relations-v1"))
    "well-known noir profile constant"
  expect (CodegenProfileId.quintSourceU64ModelV1 == (← parseProfile "quint-source-u64-model-v1"))
    "well-known Quint profile constant"
  expect (TargetId.parse? "quint" == some TargetId.quint)
    "well-known Quint target constant"
  expect (TargetId.ofKind .quint == TargetId.quint) "ofKind Quint"
  expect (CodegenProfileId.parse? "A--").isNone "invalid profile parse is none"
  expect (CodegenProfileId.parse? "evm-yul-solc-0.8.34-v1" ==
      some CodegenProfileId.evmYulSolc0834V1)
    "parse? of shipped wire equals constant (no EVM aliasing for other strings)"
  expect (TargetId.ofKind .evm == TargetId.evm) "ofKind closed map"
  expect (TargetId.ofKind .noir == TargetId.noir) "ofKind noir"

private def testRegistrySeedMembership : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  let regs := TargetRegistryV1.registrationsOf registry
  expect (regs.size == 12) "initial registry must contain 9 implemented + 3 design-only"
  match createTargetRegistryV1 initialRegistrationRowsV1 with
  | .ok rebuilt =>
      expect (rebuilt.toArray.size == 12) "rebuilt seed registry size"
  | .error e => throw <| IO.userError s!"initialRegistrationRowsV1 must validate: {e.render}"
  let impl ← liftResult implementedRegistrations
  let design ← liftResult designOnlyRegistrations
  expect (impl.size == 9) "exactly nine implemented targets"
  expect (design.size == 3) "exactly three design-only targets"
  let expectedIds :=
    #["aleo", "cosmwasm", "evm", "icp", "near", "noir", "openvm", "psy", "quint", "solana", "soroban", "ton"]
  let ids := regs.map (·.targetId.toString)
  expect (ids == expectedIds) s!"exact closed target id set, got {ids}"
  let expectedImpl := #["aleo", "cosmwasm", "evm", "near", "noir", "psy", "quint", "solana", "ton"]
  expect (impl.map (·.targetId.toString) == expectedImpl)
    s!"exact implemented set, got {impl.map (·.targetId.toString)}"
  let expectedDesign := #["icp", "openvm", "soroban"]
  expect (design.map (·.targetId.toString) == expectedDesign)
    s!"exact design-only set, got {design.map (·.targetId.toString)}"
  for reg in impl do
    expect reg.implemented s!"{reg.targetId} must be implemented"
    expect (!reg.profiles.isEmpty) s!"{reg.targetId} must have profiles"
    match reg.defaultProfile with
    | some defP =>
        expect (reg.profiles.any (· == defP)) s!"{reg.targetId} default must be a member"
    | none => throw <| IO.userError s!"{reg.targetId} missing default"
    let sel ← liftResult <| resolveBuildSelectionV1 reg.targetId none
    match reg.defaultProfile with
    | some defP =>
        expect (sel.codegenProfile == defP) s!"{reg.targetId} default resolve"
    | none => throw <| IO.userError s!"{reg.targetId} missing default after check"
  for reg in design do
    expect (!reg.implemented) s!"{reg.targetId} must be design-only"
    expect reg.profiles.isEmpty s!"{reg.targetId} must have empty profiles"
    expect reg.defaultProfile.isNone s!"{reg.targetId} must have no default"
    expectErrorCode (resolveBuildSelectionV1 reg.targetId none)
      "PF-TARGET-NOT-IMPLEMENTED" s!"design-only {reg.targetId}"
  expect (ids.toList.eraseDups.length == ids.size) "target IDs must be unique"
  for reg in regs do
    for p in reg.profiles do
      expect (!(ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains p.toString))
        s!"reserved profile {p} must not be registered"
  let sorted := ids.toList.mergeSort (· ≤ ·)
  expect (ids.toList == sorted) "registry storage must be sorted by target id"
  let expectDefault (tid : TargetId) (profile : String) : IO Unit := do
    match ← liftResult (registration? tid) with
    | some reg =>
        match reg.defaultProfile with
        | some defP => expect (defP.toString == profile) s!"{tid} default profile"
        | none => throw <| IO.userError s!"{tid} has no default"
    | none => throw <| IO.userError s!"missing registration {tid}"
  expectDefault TargetId.evm "evm-yul-solc-0.8.34-v1"
  expectDefault TargetId.solana "solana-sbpf-cpi-elf-v1"
  match ← liftResult (registration? TargetId.solana) with
  | some reg =>
      expect (reg.profiles == #[CodegenProfileId.solanaSbpfCpiElfV1])
        s!"Solana profiles must be sole rail cpi-elf, got {reg.profiles.map (·.toString)}"
  | none => throw <| IO.userError "missing Solana registration"
  expectDefault TargetId.aleo "aleo-leo-4.0.2-u64-v1"
  match ← liftResult (registration? TargetId.aleo) with
  | some reg =>
      expect (reg.profiles ==
          #[CodegenProfileId.aleoLeoU64CompileV1, CodegenProfileId.aleoLeoU64V1])
        s!"Aleo profiles must be ASCII ascending compile then u64, got {reg.profiles.map (·.toString)}"
      expect (reg.defaultProfile == some CodegenProfileId.aleoLeoU64V1)
        "Aleo default remains source u64-v1"
  | none => throw <| IO.userError "missing Aleo registration"
  -- Explicit compile resolve; unknown Aleo profile fails closed.
  let aleoDefault ← liftResult <| resolveBuildSelectionV1 TargetId.aleo none
  expect (aleoDefault.codegenProfile == CodegenProfileId.aleoLeoU64V1)
    "Aleo resolve none → source default"
  let aleoCompile ← liftResult <|
    resolveBuildSelectionV1 TargetId.aleo (some CodegenProfileId.aleoLeoU64CompileV1)
  expect (aleoCompile.codegenProfile == CodegenProfileId.aleoLeoU64CompileV1)
    "Aleo resolve explicit compile"
  match CodegenProfileId.parse? "aleo-leo-4.0.2-u64-unknown-v1" with
  | some ghost =>
      expectErrorCode (resolveBuildSelectionV1 TargetId.aleo (some ghost))
        "PF-PROFILE-UNKNOWN" "unknown Aleo profile rejected"
  | none => throw <| IO.userError "ghost Aleo profile must be grammar-valid"
  expectDefault TargetId.near "near-wasm-raw-u64-v1"
  expectDefault TargetId.noir "noir-source-u64-relations-v1"
  expectDefault TargetId.quint "quint-source-u64-model-v1"
  expectErrorCode (createTargetRegistryV1 #[])
    "PF-REGISTRY-INVALID" "empty seed never succeeds"
  let sentinel : CompileResult TargetRegistryV1 :=
    .error (.registryInvalid "sentinel")
  expectErrorCode
    (inspectBuildSelectionWithSeedV1 sentinel TargetId.evm none)
    "PF-REGISTRY-INVALID" "inspect DI propagates sentinel seed"
  expectErrorCode
    (registrationWithSeedV1 sentinel TargetId.evm)
    "PF-REGISTRY-INVALID" "registration DI propagates sentinel seed"
  expectErrorCode
    (registrationsWithSeedV1 sentinel)
    "PF-REGISTRY-INVALID" "registrations DI propagates sentinel seed"
  expectErrorCode
    (implementedRegistrationsWithSeedV1 sentinel)
    "PF-REGISTRY-INVALID" "implemented DI propagates sentinel seed"
  expectErrorCode
    (designOnlyRegistrationsWithSeedV1 sentinel)
    "PF-REGISTRY-INVALID" "design-only DI propagates sentinel seed"
  expectErrorCode
    (ProofForgeV2.CLI.listTargetLinesWithSeedV1 sentinel false)
    "PF-REGISTRY-INVALID" "list DI propagates sentinel seed"
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "evm")
    "PF-REGISTRY-INVALID" "describe DI propagates sentinel seed"
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "EVM")
    "PF-REGISTRY-INVALID" "describe seed-first: case-invalid + failed seed"
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "1evm")
    "PF-REGISTRY-INVALID" "describe seed-first: malformed + failed seed"
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "not a target!!!")
    "PF-REGISTRY-INVALID" "describe seed-first: garbage + failed seed"
  expectErrorCode (ProofForgeV2.CLI.describeTargetText "EVM")
    "PF-TARGET-UNKNOWN" "product seed: case-invalid target"
  expectErrorCode (ProofForgeV2.CLI.describeTargetText "1evm")
    "PF-TARGET-UNKNOWN" "product seed: malformed target"
  match initialTargetRegistryV1Result with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"shipped seed must be ok: {e.render}"
  let _ ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let _ ← liftResult <| registration? TargetId.evm
  let _ ← liftResult <| ProofForgeV2.CLI.listTargetLines false
  let _ ← liftResult <| ProofForgeV2.CLI.describeTargetText "evm"

private def testRegistryNegatives : IO Unit := do
  expectErrorCode (createTargetRegistryV1 #[])
    "PF-REGISTRY-INVALID" "empty registry"
  let rows := initialRegistrationRowsV1
  let dupTarget :=
    match rows[0]? with
    | some first => createTargetRegistryV1 (rows.push first)
    | none => .error (.registryInvalid "empty initialRegistrationRowsV1")
  expectErrorCode dupTarget "PF-REGISTRY-DUPLICATE" "duplicate target id"
  let dupWithin := mkEvmReg
    #[CodegenProfileId.evmYulSolc0834V1, CodegenProfileId.evmYulSolc0834V1]
    (some CodegenProfileId.evmYulSolc0834V1)
  expectErrorCode (createTargetRegistryV1 #[dupWithin])
    "PF-REGISTRY-DUPLICATE" "duplicate profile within target"
  let evmV2 ← parseProfile "evm-yul-solc-0.8.34-v2"
  let reversedProfiles := mkEvmReg
    #[evmV2, CodegenProfileId.evmYulSolc0834V1]
    (some CodegenProfileId.evmYulSolc0834V1)
  expectErrorCode (createTargetRegistryV1 #[reversedProfiles])
    "PF-REGISTRY-INVALID" "reversed multi-profile must fail closed"
  let ascendingProfiles := mkEvmReg
    #[CodegenProfileId.evmYulSolc0834V1, evmV2]
    (some CodegenProfileId.evmYulSolc0834V1)
  match createTargetRegistryV1 #[ascendingProfiles] with
  | .ok multi =>
      let rows := multi.toArray
      expect (rows.size == 1) "multi-profile carrier size"
      match rows[0]? with
      | some reg =>
          expect (reg.profiles.size == 2) "multi-profile field count"
          match reg.profiles[0]?, reg.profiles[1]? with
          | some p0, some p1 =>
              expect (p0.toString == "evm-yul-solc-0.8.34-v1")
                "multi-profile ascending first"
              expect (p1.toString == "evm-yul-solc-0.8.34-v2")
                "multi-profile ascending second"
          | _, _ => throw <| IO.userError "multi-profile missing profile slots"
          expect (reg.defaultProfile == some CodegenProfileId.evmYulSolc0834V1)
            "multi-profile default membership on carrier"
          let product ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
          expect (product.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
            "product resolve stays on frozen catalog despite multi-profile carrier"
          expectErrorCode
            (resolveBuildSelectionV1 TargetId.evm (some evmV2))
            "PF-PROFILE-UNKNOWN"
            "non-shipped multi-profile id cannot resolve via product path"
      | none => throw <| IO.userError "multi-profile empty rows"
  | .error e => throw <| IO.userError s!"ascending multi-profile must validate: {e.render}"
  let sharedP ← parseProfile "shared-profile-v1"
  let sharedProfileAcross : Array TargetRegistrationDataV1 := #[
    mkEvmReg #[sharedP] (some sharedP),
    mkNearReg #[sharedP] (some sharedP)
  ]
  expectErrorCode (createTargetRegistryV1 sharedProfileAcross)
    "PF-REGISTRY-DUPLICATE" "duplicate profile across targets"
  let foreignDefault := mkEvmReg
    #[CodegenProfileId.evmYulSolc0834V1]
    (some CodegenProfileId.nearWasmRawU64V1)
  expectErrorCode (createTargetRegistryV1 #[foreignDefault])
    "PF-REGISTRY-INVALID" "foreign default profile"
  let implNoDefault := mkEvmReg
    #[CodegenProfileId.evmYulSolc0834V1] none
  expectErrorCode (createTargetRegistryV1 #[implNoDefault])
    "PF-REGISTRY-INVALID" "implemented missing default"
  let aleoFake ← parseProfile "aleo-fake-v1"
  let designWithProfile := mkAleoReg #[aleoFake] none
  expectErrorCode (createTargetRegistryV1 #[designWithProfile])
    "PF-REGISTRY-INVALID" "design-only with profiles"
  let designWithDefault := mkAleoReg #[] (some aleoFake)
  expectErrorCode (createTargetRegistryV1 #[designWithDefault])
    "PF-REGISTRY-INVALID" "design-only with default"
  let kindMismatch := { mkEvmReg #[CodegenProfileId.evmYulSolc0834V1]
      (some CodegenProfileId.evmYulSolc0834V1) with kind := .near }
  expectErrorCode (createTargetRegistryV1 #[kindMismatch])
    "PF-REGISTRY-INVALID" "targetId/kind mismatch"
  -- solana-sbpf-elf-v1 is a shipped Solana profile; reserved gate keeps noir-acir.
  let reservedNoir ← parseProfile "noir-acir-proof-v1"
  let reserved := mkEvmReg #[reservedNoir] (some reservedNoir)
  expectErrorCode (createTargetRegistryV1 #[reserved])
    "PF-REGISTRY-INVALID" "reserved future profile"
  -- Closed registration policy: no product-facing field can drift from kind.
  let badImplemented := { mkEvmReg #[] none with implemented := false }
  expectErrorCode (createTargetRegistryV1 #[badImplemented])
    "PF-REGISTRY-INVALID" "implemented closed policy"
  let badMaturity := { mkEvmReg #[CodegenProfileId.evmYulSolc0834V1]
      (some CodegenProfileId.evmYulSolc0834V1) with maturityLabel := "forged" }
  expectErrorCode (createTargetRegistryV1 #[badMaturity])
    "PF-REGISTRY-INVALID" "maturityLabel closed policy"
  let badDisplayName := { mkEvmReg #[CodegenProfileId.evmYulSolc0834V1]
      (some CodegenProfileId.evmYulSolc0834V1) with displayName := "Forged" }
  expectErrorCode (createTargetRegistryV1 #[badDisplayName])
    "PF-REGISTRY-INVALID" "displayName closed policy"
  let badAcceptance := { mkEvmReg #[CodegenProfileId.evmYulSolc0834V1]
      (some CodegenProfileId.evmYulSolc0834V1) with
        acceptanceProfileId := "forged.evm.v1" }
  expectErrorCode (createTargetRegistryV1 #[badAcceptance])
    "PF-REGISTRY-INVALID" "acceptanceProfileId closed policy"

private def testResolve : IO ResolvedBuildSelectionV1 := do
  let evmDefault ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  expect (evmDefault.targetId == TargetId.evm) "default selection target"
  expect (evmDefault.codegenProfile == CodegenProfileId.evmYulSolc0834V1) "default profile"
  expect (evmDefault.kind == .evm) "default kind"
  let evmExplicit ← liftResult <| resolveBuildSelectionV1 TargetId.evm
    (some CodegenProfileId.evmYulSolc0834V1)
  expect (evmExplicit.codegenProfile == evmDefault.codegenProfile) "explicit default member"
  let evmCancun ← liftResult <| resolveBuildSelectionV1 TargetId.evm
    (some CodegenProfileId.evmYulSolc0834CancunV1)
  expect (evmCancun.codegenProfile == CodegenProfileId.evmYulSolc0834CancunV1)
    "explicit cancun profile resolves"
  expect (evmCancun.codegenProfile != evmDefault.codegenProfile)
    "cancun profile is not the default"
  expect (TargetId.parse? "EVM").isNone "target lookup is case-sensitive at parse"
  let ghost ← match TargetId.parse? "ghost-target" with
    | some id => pure id
    | none => throw <| IO.userError "ghost-target must parse"
  expectErrorCode (resolveBuildSelectionV1 ghost none) "PF-TARGET-UNKNOWN" "unknown target"
  expectErrorCode (resolveBuildSelectionV1 TargetId.soroban none)
    "PF-TARGET-NOT-IMPLEMENTED" "design-only target"
  let cosmwasmDefault ← liftResult <| resolveBuildSelectionV1 TargetId.cosmwasm none
  expect (cosmwasmDefault.codegenProfile == CodegenProfileId.cosmwasmWasmU64V1)
    "cosmwasm default profile after promotion"
  let solanaCpi ← liftResult <| resolveBuildSelectionV1 TargetId.solana
    (some CodegenProfileId.solanaSbpfCpiElfV1)
  expect (solanaCpi.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1 &&
      solanaCpi.kind == .solana)
    "opt-in Solana CPI product profile resolves as a registered selection"
  expectErrorCode
    (resolveBuildSelectionV1 TargetId.evm
      (some CodegenProfileId.nearWasmRawU64V1))
    "PF-PROFILE-UNKNOWN" "cross-target profile"
  let unknownProf ← parseProfile "not-a-real-profile-v1"
  expectErrorCode
    (resolveBuildSelectionV1 TargetId.evm (some unknownProf))
    "PF-PROFILE-UNKNOWN" "unknown profile"
  return evmDefault

/-- Seed-first product dispatcher (`parseCliCommandWithSeedV1` / `parseProductCliCommandV1`). -/
private def testCliDispatcher (evmDefault : ResolvedBuildSelectionV1) : IO Unit := do
  let sentinel : CompileResult TargetRegistryV1 :=
    .error (.registryInvalid "sentinel")
  let expectSeedFirst (label : String) (args : List String) : IO Unit := do
    match ProofForgeV2.CLI.parseCliCommandWithSeedV1 sentinel args with
    | Except.error msg =>
        expect (msg == (CompileError.registryInvalid "sentinel").render)
          s!"{label}: got {msg}"
    | Except.ok _ => throw <| IO.userError s!"{label}: sentinel seed must fail before parse"
  expectSeedFirst "build EVM" ["build", "Examples/Counter.lean", "--module", "Examples.Counter", "--target", "EVM"]
  expectSeedFirst "build bad profile"
    ["build", "Examples/Counter.lean", "--module", "Examples.Counter", "--target", "evm", "--profile", "!!!bad"]
  expectSeedFirst "build dup target"
    ["build", "Examples/Counter.lean", "--module", "Examples.Counter", "--target", "evm", "--target", "near"]
  expectSeedFirst "list-targets" ["list-targets"]
  expectSeedFirst "inspect 1evm" ["inspect", "1evm"]
  match ProofForgeV2.CLI.parseProductCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--network", "local"] with
  | Except.error msg =>
      expect (hasSubstr msg "unknown option '--network'")
        "success seed preserves --network usage"
  | Except.ok _ => throw <| IO.userError "product preflight must reject --network"
  match ProofForgeV2.CLI.parseProductCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--target", "near"] with
  | Except.error msg =>
      expect (msg == "duplicate --target") "success seed duplicate --target"
  | Except.ok _ => throw <| IO.userError "product preflight must reject duplicate --target"
  let defaultList ← liftResult <| ProofForgeV2.CLI.listTargetLines false
  expect (defaultList.size == 9) "default list-targets is implemented-only"
  expect (defaultList == #["aleo\tsource-only", "cosmwasm\twasm-validated-alpha",
      "evm\truntime-validated-alpha", "near\twasm-validated-alpha", "noir\tsource-only",
      "psy\tsource-only", "quint\tsource-only", "solana\tplan-only", "ton\tsource-only"])
    s!"default list-targets exact lines, got {defaultList}"
  let allList ← liftResult <| ProofForgeV2.CLI.listTargetLines true
  expect (allList == #[
      "aleo\tsource-only",
      "cosmwasm\twasm-validated-alpha",
      "evm\truntime-validated-alpha",
      "icp\tresearch-only",
      "near\twasm-validated-alpha",
      "noir\tsource-only",
      "openvm\tresearch-only",
      "psy\tsource-only",
      "quint\tsource-only",
      "solana\tplan-only",
      "soroban\tresearch-only",
      "ton\tsource-only"])
    s!"list-targets --all canonical TargetId order, got {allList}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets"] with
  | .ok (.listTargets opts) =>
      expect (!opts.includeDesignOnly && !opts.json) "parse list-targets default"
  | other => throw <| IO.userError s!"parse list-targets default: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets", "--all"] with
  | .ok (.listTargets opts) =>
      expect (opts.includeDesignOnly && !opts.json) "parse list-targets --all"
  | other => throw <| IO.userError s!"parse list-targets --all: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets", "--json"] with
  | .ok (.listTargets opts) =>
      expect (!opts.includeDesignOnly && opts.json) "parse list-targets --json"
  | other => throw <| IO.userError s!"parse list-targets --json: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets", "--all", "--json"] with
  | .ok (.listTargets opts) =>
      expect (opts.includeDesignOnly && opts.json) "parse list-targets --all --json"
  | other => throw <| IO.userError s!"parse list-targets combo: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets", "--bogus"] with
  | .error msg =>
      expect (hasSubstr msg "unknown list-targets argument") "bad list-targets args"
  | .ok _ => throw <| IO.userError "list-targets --bogus must fail"
  match ProofForgeV2.CLI.parseCliCommandV1 ["inspect", "evm"] with
  | .ok (.inspect "evm" false) => pure ()
  | other => throw <| IO.userError s!"parse inspect: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["inspect", "evm", "--json"] with
  | .ok (.inspect "evm" true) => pure ()
  | other => throw <| IO.userError s!"parse inspect --json: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm"] with
  | .ok (.build opts) =>
      expect (opts.target == some TargetId.evm) "dispatcher build target"
      expect opts.profile.isNone "dispatcher build default profile"
      expect opts.languageVersion.isNone "dispatcher omitted language version"
      expect (!opts.json) "dispatcher build default json off"
  | other => throw <| IO.userError s!"parse build default: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--language-version", "1.0.0"] with
  | .ok (.build opts) =>
      expect (opts.languageVersion == some "1.0.0")
        "dispatcher explicit language version"
  | other => throw <| IO.userError s!"parse explicit language version: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--profile", "evm-yul-solc-0.8.34-v1"] with
  | .ok (.build opts) =>
      expect (opts.profile == some CodegenProfileId.evmYulSolc0834V1)
        "dispatcher explicit profile"
  | other => throw <| IO.userError s!"parse build explicit profile: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--profile", "near-wasm-raw-u64-v1"] with
  | .ok (.build opts) =>
      match opts.target with
      | some tid =>
          expectErrorCode (resolveBuildSelectionV1 tid opts.profile)
            "PF-PROFILE-UNKNOWN" "dispatcher cross-profile resolve"
      | none => throw <| IO.userError "cross profile missing target"
  | other => throw <| IO.userError s!"parse cross profile: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "openvm"] with
  | .ok (.build opts) =>
      match opts.target with
      | some tid =>
          expectErrorCode (resolveBuildSelectionV1 tid opts.profile)
            "PF-TARGET-NOT-IMPLEMENTED" "dispatcher design-only resolve"
      | none => throw <| IO.userError "design-only missing target"
  | other => throw <| IO.userError s!"parse design-only: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--network", "local"] with
  | .error msg =>
      expect (hasSubstr msg "unknown option '--network'") "dispatcher --network usage"
  | .ok _ => throw <| IO.userError "--network must be usage error"
  match ProofForgeV2.CLI.parseBuildArgsExcept
      ["--target", "evm", "--target", "near"] with
  | .error msg => expect (msg == "duplicate --target") "duplicate --target message"
  | .ok _ => throw <| IO.userError "duplicate --target must fail"
  match ProofForgeV2.CLI.parseBuildArgsExcept
      ["--target", "evm", "--profile", "evm-yul-solc-0.8.34-v1",
        "--profile", "near-wasm-raw-u64-v1"] with
  | .error msg => expect (msg == "duplicate --profile") "duplicate --profile message"
  | .ok _ => throw <| IO.userError "duplicate --profile must fail"
  match ProofForgeV2.CLI.parseBuildArgsExcept
      ["--language-version", "1.0.0", "--language-version", "1.0.1"] with
  | .error msg =>
      expect (msg == "duplicate --language-version") "duplicate --language-version message"
  | .ok _ => throw <| IO.userError "duplicate --language-version must fail"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm", "--target", "near"] with
  | .error msg => expect (msg == "duplicate --target") "dispatcher duplicate --target"
  | .ok _ => throw <| IO.userError "dispatcher must reject duplicate --target"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter", "--json"] with
  | .ok (.check opts) =>
      expect opts.json "dispatcher check --json"
      expect (opts.source == some "Examples/Counter.lean") "dispatcher check source"
  | other => throw <| IO.userError s!"parse check: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 [] with
  | .ok .usage => pure ()
  | other => throw <| IO.userError s!"empty args → usage: {repr other}"
  let insp ← liftResult <|
    inspectBuildSelectionWithSeedV1 initialTargetRegistryV1Result
      TargetId.evm none
  expect (insp.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "inspection of frozen seed"
  expect (insp.targetId == TargetId.evm) "inspection target"
  -- Forged catalog with closed policy labels but alternate profile cannot
  -- influence product frozen resolver.
  let ghostP ← parseProfile "ghost-evm-profile-v1"
  let ghostCatalog : Array TargetRegistrationDataV1 := #[
    mkEvmReg #[ghostP] (some ghostP)
  ]
  match createTargetRegistryV1 ghostCatalog with
  | .ok forged =>
      match forged.toArray[0]? with
      | some row =>
          match row.profiles[0]? with
          | some p0 =>
              expect (p0.toString == "ghost-evm-profile-v1")
                "forged catalog validates as carrier"
          | none => throw <| IO.userError "forged catalog missing profile"
      | none => throw <| IO.userError "forged catalog empty"
      let product ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
      expect (product.codegenProfile == evmDefault.codegenProfile)
        "forged catalog cannot influence product frozen resolver"
  | .error e => throw <| IO.userError s!"forged catalog should validate: {e.render}"
  match ProofForgeV2.CLI.inspectTargetText "evm" with
  | .ok text =>
      expect (text.startsWith "target=evm\nprofile=evm-yul-solc-0.8.34-v1\n")
        s!"inspect implemented evm, got {text}"
      expect (hasSubstr text "requirements=") "inspect implemented includes requirements"
      expect (hasSubstr text "failure.atomic-rollback")
        "inspect S2 ids from engineering support index"
      expect (hasSubstr text "state.persistent") "inspect includes state.persistent"
      expect (hasSubstr text "value.checked-arithmetic")
        "inspect includes value.checked-arithmetic"
      expect (hasSubstr text "registryRootDigest=sha256:")
        "inspect includes registry root digest"
      expect (hasSubstr text "supportClaimDigest=sha256:")
        "inspect includes support claim digest"
      expect (hasSubstr text "buildIdentityDomain=pf.build-identity.engineering.v1")
        "inspect includes build identity domain"
      expect (!hasSubstr text "privateWitness")
        "inspect must not surface residual alpha privateWitness"
      expect (!hasSubstr text "ProgramRequirement")
        "inspect uses S2 request identities, not alpha Repr"
  | .error e => throw <| IO.userError s!"inspect evm: {e.render}"
  match ProofForgeV2.CLI.inspectTargetText "aleo" with
  | .ok text =>
      expect (hasSubstr text "target=aleo\nprofile=aleo-leo-4.0.2-u64-v1\n")
        s!"inspect aleo prefix, got {text}"
      expect (hasSubstr text
          "requirements=#[failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic]")
        s!"inspect aleo requirements, got {text}"
      expect (hasSubstr text "status=implemented") "aleo is implemented source-only"
  | .error e => throw <| IO.userError s!"inspect aleo: {e.render}"
  -- Legacy three-line helper remains for S2 exact-string join tests.
  match ProofForgeV2.CLI.describeTargetText "aleo" with
  | .ok text =>
      expect (text ==
          "target=aleo\nprofile=aleo-leo-4.0.2-u64-v1\nrequirements=#[failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic]")
        s!"describe helper exact, got {text}"
  | .error e => throw <| IO.userError s!"describe helper aleo: {e.render}"
  expectErrorCode (ProofForgeV2.CLI.inspectTargetText "ghost-target")
    "PF-TARGET-UNKNOWN" "inspect unknown grammar-valid target"
  expectErrorCode (ProofForgeV2.CLI.inspectTargetText "EVM")
    "PF-TARGET-UNKNOWN" "inspect rejects case-mismatched target"
  let implReg := mkEvmReg
    #[CodegenProfileId.evmYulSolc0834V1]
    (some CodegenProfileId.evmYulSolc0834V1)
  let wrongTargetDesc := { Targets.Evm.descriptor with targetId := TargetId.near }
  expectErrorCode
    (ProofForgeV2.CLI.describeImplementedJoin implReg wrongTargetDesc)
    "PF-REGISTRY-INVALID" "describe join targetId mismatch"
  let wrongProfileDesc :=
    { Targets.Evm.descriptor with codegenProfile := CodegenProfileId.nearWasmRawU64V1 }
  expectErrorCode
    (ProofForgeV2.CLI.describeImplementedJoin implReg wrongProfileDesc)
    "PF-REGISTRY-INVALID" "describe join profile mismatch"
  match ProofForgeV2.CLI.describeImplementedJoin implReg Targets.Evm.descriptor with
  | .ok text =>
      expect (hasSubstr text "target=evm") "describe join positive"
  | .error e => throw <| IO.userError s!"describe join positive: {e.render}"
  let viaDefault ← ProofForgeV2.CLI.resolveSelectionFromFlags
    { target := some TargetId.evm, profile := none }
  expect (viaDefault.codegenProfile == evmDefault.codegenProfile)
    "resolveSelectionFromFlags default profile"

private unsafe def testMaterializeIdentity : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<build-selection-counter>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  for tid in #[TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let selection ← liftResult <| resolveBuildSelectionV1 tid none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    let output ← liftResult <| Targets.materializeResult capability
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty) s!"{tid} must emit artifacts"
    expect (MaterializedArtifactsV1.targetIdOf output == tid)
      s!"carrier target identity for {tid}"
    expect (MaterializedArtifactsV1.sourceDigestOf output == sourceDigest)
      s!"carrier canonical source digest identity for {tid}"
    expect (MaterializedArtifactsV1.semanticDigestOf output == semanticDigest)
      s!"carrier canonical semantic digest identity for {tid}"
    match ← liftResult (registration? tid) with
    | some reg =>
        match reg.defaultProfile with
        | some defP =>
            expect (MaterializedArtifactsV1.codegenProfileIdOf output == defP)
              s!"carrier profile identity for {tid}"
        | none => throw <| IO.userError "implemented without default"
    | none => throw <| IO.userError "missing reg"
  match resolveBuildSelectionV1 TargetId.openvm none with
  | .error (.targetNotImplemented .openvm) => pure ()
  | .error e => throw <| IO.userError s!"expected NOT-IMPLEMENTED, got {e.render}"
  | .ok _ => throw <| IO.userError "design-only must not resolve"
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let outputDir := System.FilePath.mk "build/v2/build-selection-emit"
  if ← outputDir.pathExists then IO.FS.removeDirAll outputDir
  let receipt ← ProofForgeV2.CLI.emitProgram capability outputDir
  expect (receipt.target == TargetId.solana) "emitProgram target identity"
  expect (receipt.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "emitProgram profile identity (sole rail)"
  let evmSel ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let evmCap ← liftResult <| Targets.resolveEngineeringRequirementsV1 evmSel compiled
  let evmOut ← liftResult <| Targets.materializeResult evmCap
  expect ((MaterializedArtifactsV1.targetIdOf evmOut).toString == "evm")
    "EVM carrier target wire"
  expect (MaterializedArtifactsV1.codegenProfileIdOf evmOut ==
      CodegenProfileId.evmYulSolc0834V1)
    "EVM carrier profile wire"
  let evmDir := System.FilePath.mk "build/v2/build-selection-emit-evm"
  if ← evmDir.pathExists then IO.FS.removeDirAll evmDir
  let _ ← ProofForgeV2.CLI.emitProgram evmCap evmDir
  let json ← IO.FS.readFile (evmDir / "manifest.json")
  expect (hasSubstr json "\"target\": \"evm\"") "manifest JSON target"
  expect (hasSubstr json "\"codegenProfile\": \"evm-yul-solc-0.8.34-v1\"")
    "manifest JSON profile"
  let viaSelected ← liftResult <| materializeSelected TargetId.near compiled
  expect (MaterializedArtifactsV1.targetIdOf viaSelected == TargetId.near)
    "selection-only materialize path"

unsafe def run : IO Unit := do
  testGrammar
  testRegistrySeedMembership
  testRegistryNegatives
  let evmDefault ← testResolve
  testCliDispatcher evmDefault
  testMaterializeIdentity

end Tests.Materialization.BuildSelectionV1

/-! ## Compile-time proof: identity types have no `Inhabited` -/

open ProofForgeV2

/--
error: failed to synthesize
  Inhabited TargetId

Hint: Additional diagnostic information may be available using the `set_option diagnostics true` command.
-/
#guard_msgs in
#synth Inhabited TargetId

/--
error: failed to synthesize
  Inhabited CodegenProfileId

Hint: Additional diagnostic information may be available using the `set_option diagnostics true` command.
-/
#guard_msgs in
#synth Inhabited CodegenProfileId

/--
error: failed to synthesize
  Inhabited NetworkProfileId

Hint: Additional diagnostic information may be available using the `set_option diagnostics true` command.
-/
#guard_msgs in
#synth Inhabited NetworkProfileId
