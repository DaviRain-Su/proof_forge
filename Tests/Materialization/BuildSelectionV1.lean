import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Registry
import Tests.Language.ParserSession

namespace Tests.Materialization.BuildSelectionV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

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

private def materializeSelected (target : TargetId) (compiled : CompiledProgramV1)
    (profile? : Option CodegenProfileId := none) : CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

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
  -- Well-known constants equal parse? of the same wire; invalid parse is none.
  expect (CodegenProfileId.evmYulSolc0834V1 == (← parseProfile "evm-yul-solc-0.8.34-v1"))
    "well-known evm profile constant"
  expect (CodegenProfileId.solanaSbpfPlanV1 == (← parseProfile "solana-sbpf-plan-v1"))
    "well-known solana profile constant"
  expect (CodegenProfileId.nearWasmRawU64V1 == (← parseProfile "near-wasm-raw-u64-v1"))
    "well-known near profile constant"
  expect (CodegenProfileId.noirSourceU64RelationsV1 == (← parseProfile "noir-source-u64-relations-v1"))
    "well-known noir profile constant"
  expect (CodegenProfileId.parse? "A--").isNone "invalid profile parse is none"
  expect (CodegenProfileId.parse? "evm-yul-solc-0.8.34-v1" ==
      some CodegenProfileId.evmYulSolc0834V1)
    "parse? of shipped wire equals constant (no EVM aliasing for other strings)"
  expect (TargetId.ofKind .evm == TargetId.evm) "ofKind closed map"
  expect (TargetId.ofKind .noir == TargetId.noir) "ofKind noir"

private def testIndexValidation : IO Unit := do
  let index ← liftResult initialStaticBuildSelectionIndexV1Result
  let regs := index.toArray
  expect (regs.size == 10) "initial index must contain 4 implemented + 6 design-only"
  match createStaticBuildSelectionIndexV1 initialRegistrations with
  | .ok rebuilt =>
      expect (rebuilt.toArray.size == 10) "rebuilt seed index size"
  | .error e => throw <| IO.userError s!"initialRegistrations must validate: {e.render}"
  let impl ← liftResult implementedRegistrations
  let design ← liftResult designOnlyRegistrations
  expect (impl.size == 4) "exactly four implemented targets"
  expect (design.size == 6) "exactly six design-only targets"
  let expectedIds :=
    #["aleo", "cosmwasm", "evm", "icp", "near", "noir", "openvm", "psy", "solana", "soroban"]
  let ids := regs.map (·.targetId.toString)
  expect (ids == expectedIds) s!"exact closed target id set, got {ids}"
  let expectedImpl := #["evm", "near", "noir", "solana"]
  expect (impl.map (·.targetId.toString) == expectedImpl)
    s!"exact implemented set, got {impl.map (·.targetId.toString)}"
  let expectedDesign := #["aleo", "cosmwasm", "icp", "openvm", "psy", "soroban"]
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
      expect (!reservedFutureProfiles.contains p.toString)
        s!"reserved profile {p} must not be registered"
  let sorted := ids.toList.mergeSort (· ≤ ·)
  expect (ids.toList == sorted) "index storage must be sorted by target id"
  let expectDefault (tid : TargetId) (profile : String) : IO Unit := do
    match ← liftResult (registration? tid) with
    | some reg =>
        match reg.defaultProfile with
        | some defP => expect (defP.toString == profile) s!"{tid} default profile"
        | none => throw <| IO.userError s!"{tid} has no default"
    | none => throw <| IO.userError s!"missing registration {tid}"
  expectDefault TargetId.evm "evm-yul-solc-0.8.34-v1"
  expectDefault TargetId.solana "solana-sbpf-plan-v1"
  expectDefault TargetId.near "near-wasm-raw-u64-v1"
  expectDefault TargetId.noir "noir-source-u64-relations-v1"
  -- Seed Result is .ok for shipped initial; empty seed cannot succeed.
  expectErrorCode (createStaticBuildSelectionIndexV1 #[])
    "PF-REGISTRY-INVALID" "empty seed never succeeds"
  -- Sentinel seed: every DI body propagates PF-REGISTRY-INVALID; none mint capability.
  let sentinel : CompileResult StaticBuildSelectionIndexV1 :=
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
  -- Seed-first: failed seed wins over malformed/case-invalid target strings.
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "EVM")
    "PF-REGISTRY-INVALID" "describe seed-first: case-invalid + failed seed"
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "1evm")
    "PF-REGISTRY-INVALID" "describe seed-first: malformed + failed seed"
  expectErrorCode
    (ProofForgeV2.CLI.describeTargetWithSeedV1 sentinel "not a target!!!")
    "PF-REGISTRY-INVALID" "describe seed-first: garbage + failed seed"
  -- Product success seed still maps malformed/case-invalid → PF-TARGET-UNKNOWN.
  expectErrorCode (ProofForgeV2.CLI.describeTargetText "EVM")
    "PF-TARGET-UNKNOWN" "product seed: case-invalid target"
  expectErrorCode (ProofForgeV2.CLI.describeTargetText "1evm")
    "PF-TARGET-UNKNOWN" "product seed: malformed target"
  -- Product wrappers on frozen seed still succeed.
  match initialStaticBuildSelectionIndexV1Result with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"shipped seed must be ok: {e.render}"
  let _ ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let _ ← liftResult <| registration? TargetId.evm
  let _ ← liftResult <| ProofForgeV2.CLI.listTargetLines false
  let _ ← liftResult <| ProofForgeV2.CLI.describeTargetText "evm"
  -- Forged catalog may inspect rows only — no public mint of ResolvedBuildSelectionV1
  -- from arbitrary index (resolveBuildSelectionInIndexV1 removed).

private def testIndexNegatives : IO Unit := do
  expectErrorCode (createStaticBuildSelectionIndexV1 #[])
    "PF-REGISTRY-INVALID" "empty index"
  let dupTarget :=
    match initialRegistrations[0]? with
    | some first => createStaticBuildSelectionIndexV1 (initialRegistrations.push first)
    | none => .error (.registryInvalid "empty initialRegistrations")
  expectErrorCode dupTarget "PF-REGISTRY-DUPLICATE" "duplicate target id"
  let dupWithin : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1, CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
    maturityLabel := "bad"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[dupWithin])
    "PF-REGISTRY-DUPLICATE" "duplicate profile within target"
  let evmV2 ← parseProfile "evm-yul-solc-0.8.34-v2"
  let reversedProfiles : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[evmV2, CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
    maturityLabel := "bad"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[reversedProfiles])
    "PF-REGISTRY-INVALID" "reversed multi-profile must fail closed"
  let ascendingProfiles : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1, evmV2]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
    maturityLabel := "ok"
  }
  match createStaticBuildSelectionIndexV1 #[ascendingProfiles] with
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
  let sharedProfileAcross : Array StaticBuildRegistrationV1 := #[
    {
      targetId := TargetId.evm
      kind := .evm
      implemented := true
      profiles := #[sharedP]
      defaultProfile := some sharedP
      maturityLabel := "bad"
    },
    {
      targetId := TargetId.near
      kind := .near
      implemented := true
      profiles := #[sharedP]
      defaultProfile := some sharedP
      maturityLabel := "bad"
    }
  ]
  expectErrorCode (createStaticBuildSelectionIndexV1 sharedProfileAcross)
    "PF-REGISTRY-DUPLICATE" "duplicate profile across targets"
  let foreignDefault : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.nearWasmRawU64V1
    maturityLabel := "bad"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[foreignDefault])
    "PF-REGISTRY-INVALID" "foreign default profile"
  let implNoDefault : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := none
    maturityLabel := "bad"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[implNoDefault])
    "PF-REGISTRY-INVALID" "implemented missing default"
  let aleoFake ← parseProfile "aleo-fake-v1"
  let designWithProfile : StaticBuildRegistrationV1 := {
    targetId := TargetId.aleo
    kind := .aleo
    implemented := false
    profiles := #[aleoFake]
    defaultProfile := none
    maturityLabel := "research-only"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[designWithProfile])
    "PF-REGISTRY-INVALID" "design-only with profiles"
  let designWithDefault : StaticBuildRegistrationV1 := {
    targetId := TargetId.aleo
    kind := .aleo
    implemented := false
    profiles := #[]
    defaultProfile := some aleoFake
    maturityLabel := "research-only"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[designWithDefault])
    "PF-REGISTRY-INVALID" "design-only with default"
  let kindMismatch : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .near
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
    maturityLabel := "bad"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[kindMismatch])
    "PF-REGISTRY-INVALID" "targetId/kind mismatch"
  let reservedElf ← parseProfile "solana-sbpf-elf-v1"
  let reserved : StaticBuildRegistrationV1 := {
    targetId := TargetId.solana
    kind := .solana
    implemented := true
    profiles := #[reservedElf]
    defaultProfile := some reservedElf
    maturityLabel := "bad"
  }
  expectErrorCode (createStaticBuildSelectionIndexV1 #[reserved])
    "PF-REGISTRY-INVALID" "reserved future profile"

private def testResolve : IO ResolvedBuildSelectionV1 := do
  let evmDefault ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  expect (evmDefault.targetId == TargetId.evm) "default selection target"
  expect (evmDefault.codegenProfile == CodegenProfileId.evmYulSolc0834V1) "default profile"
  expect (evmDefault.kind == .evm) "default kind"
  let evmExplicit ← liftResult <| resolveBuildSelectionV1 TargetId.evm
    (some CodegenProfileId.evmYulSolc0834V1)
  expect (evmExplicit.codegenProfile == evmDefault.codegenProfile) "explicit default member"
  expect (TargetId.parse? "EVM").isNone "target lookup is case-sensitive at parse"
  let ghost ← match TargetId.parse? "ghost-target" with
    | some id => pure id
    | none => throw <| IO.userError "ghost-target must parse"
  expectErrorCode (resolveBuildSelectionV1 ghost none) "PF-TARGET-UNKNOWN" "unknown target"
  expectErrorCode (resolveBuildSelectionV1 TargetId.cosmwasm none)
    "PF-TARGET-NOT-IMPLEMENTED" "design-only target"
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
  let sentinel : CompileResult StaticBuildSelectionIndexV1 :=
    .error (.registryInvalid "sentinel")
  -- Failed seed wins over any usage/target/profile parse.
  let expectSeedFirst (label : String) (args : List String) : IO Unit := do
    match ProofForgeV2.CLI.parseCliCommandWithSeedV1 sentinel args with
    | Except.error msg =>
        expect (msg == (CompileError.registryInvalid "sentinel").render)
          s!"{label}: got {msg}"
    | Except.ok _ => throw <| IO.userError s!"{label}: sentinel seed must fail before parse"
  expectSeedFirst "build-counter EVM" ["build-counter", "--target", "EVM"]
  expectSeedFirst "build-counter bad profile"
    ["build-counter", "--target", "evm", "--profile", "!!!bad"]
  expectSeedFirst "build-counter dup target"
    ["build-counter", "--target", "evm", "--target", "near"]
  expectSeedFirst "list-targets" ["list-targets"]
  expectSeedFirst "describe 1evm" ["describe-target", "1evm"]
  -- Success seed keeps original usage/parse diagnostics.
  match ProofForgeV2.CLI.parseProductCliCommandV1
      ["build-counter", "--target", "evm", "--network", "local"] with
  | Except.error msg =>
      expect (hasSubstr msg "unknown option '--network'")
        "success seed preserves --network usage"
  | Except.ok _ => throw <| IO.userError "product preflight must reject --network"
  match ProofForgeV2.CLI.parseProductCliCommandV1
      ["build-counter", "--target", "evm", "--target", "near"] with
  | Except.error msg =>
      expect (msg == "duplicate --target") "success seed duplicate --target"
  | Except.ok _ => throw <| IO.userError "product preflight must reject duplicate --target"
  -- list-targets default / --all via product listTargetLines (seed Result)
  let defaultList ← liftResult <| ProofForgeV2.CLI.listTargetLines false
  expect (defaultList.size == 4) "default list-targets is implemented-only"
  expect (defaultList == #["evm\truntime-validated-alpha", "near\twasm-validated-alpha",
      "noir\tsource-only", "solana\tplan-only"])
    s!"default list-targets exact lines, got {defaultList}"
  let allList ← liftResult <| ProofForgeV2.CLI.listTargetLines true
  expect (allList == #[
      "aleo\tresearch-only",
      "cosmwasm\tresearch-only",
      "evm\truntime-validated-alpha",
      "icp\tresearch-only",
      "near\twasm-validated-alpha",
      "noir\tsource-only",
      "openvm\tresearch-only",
      "psy\tresearch-only",
      "solana\tplan-only",
      "soroban\tresearch-only"])
    s!"list-targets --all canonical TargetId order, got {allList}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets"] with
  | .ok (.listTargets false) => pure ()
  | other => throw <| IO.userError s!"parse list-targets default: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets", "--all"] with
  | .ok (.listTargets true) => pure ()
  | other => throw <| IO.userError s!"parse list-targets --all: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1 ["list-targets", "--json"] with
  | .error msg =>
      expect (hasSubstr msg "unknown list-targets argument") "bad list-targets args"
  | .ok _ => throw <| IO.userError "list-targets --json must fail"
  match ProofForgeV2.CLI.parseCliCommandV1 ["describe-target", "evm"] with
  | .ok (.describeTarget "evm") => pure ()
  | other => throw <| IO.userError s!"parse describe: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build-counter", "--target", "evm"] with
  | .ok (.buildCounter opts) =>
      expect (opts.target == some TargetId.evm) "dispatcher build-counter target"
      expect opts.profile.isNone "dispatcher build-counter default profile"
  | other => throw <| IO.userError s!"parse build-counter default: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build-counter", "--target", "evm", "--profile", "evm-yul-solc-0.8.34-v1"] with
  | .ok (.buildCounter opts) =>
      expect (opts.profile == some CodegenProfileId.evmYulSolc0834V1)
        "dispatcher explicit profile"
  | other => throw <| IO.userError s!"parse build-counter explicit: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build-counter", "--target", "evm", "--profile", "near-wasm-raw-u64-v1"] with
  | .ok (.buildCounter opts) =>
      match opts.target with
      | some tid =>
          expectErrorCode (resolveBuildSelectionV1 tid opts.profile)
            "PF-PROFILE-UNKNOWN" "dispatcher cross-profile resolve"
      | none => throw <| IO.userError "cross profile missing target"
  | other => throw <| IO.userError s!"parse cross profile: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build-counter", "--target", "openvm"] with
  | .ok (.buildCounter opts) =>
      match opts.target with
      | some tid =>
          expectErrorCode (resolveBuildSelectionV1 tid opts.profile)
            "PF-TARGET-NOT-IMPLEMENTED" "dispatcher design-only resolve"
      | none => throw <| IO.userError "design-only missing target"
  | other => throw <| IO.userError s!"parse design-only: {repr other}"
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build-counter", "--target", "evm", "--network", "local"] with
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
  match ProofForgeV2.CLI.parseCliCommandV1
      ["build-counter", "--target", "evm", "--target", "near"] with
  | .error msg => expect (msg == "duplicate --target") "dispatcher duplicate --target"
  | .ok _ => throw <| IO.userError "dispatcher must reject duplicate --target"
  match ProofForgeV2.CLI.parseCliCommandV1 [] with
  | .ok .usage => pure ()
  | other => throw <| IO.userError s!"empty args → usage: {repr other}"
  -- Inspection vs capability: forged catalog validates as rows; product resolve
  -- still frozen. BuildSelectionInspectionV1 cannot feed materialize (type distinct).
  let insp ← liftResult <|
    inspectBuildSelectionWithSeedV1 initialStaticBuildSelectionIndexV1Result
      TargetId.evm none
  expect (insp.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "inspection of frozen seed"
  expect (insp.targetId == TargetId.evm) "inspection target"
  -- Product resolve still ignores forged catalogs.
  let ghostP ← parseProfile "ghost-evm-profile-v1"
  let ghostCatalog : Array StaticBuildRegistrationV1 := #[
    {
      targetId := TargetId.evm
      kind := .evm
      implemented := true
      profiles := #[ghostP]
      defaultProfile := some ghostP
      maturityLabel := "forged"
    }
  ]
  match createStaticBuildSelectionIndexV1 ghostCatalog with
  | .ok forged =>
      match forged.toArray[0]?, forged.toArray[0]? with
      | some row, _ =>
          match row.profiles[0]? with
          | some p0 =>
              expect (p0.toString == "ghost-evm-profile-v1")
                "forged catalog validates as carrier"
          | none => throw <| IO.userError "forged catalog missing profile"
      | none, _ => throw <| IO.userError "forged catalog empty"
      let product ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
      expect (product.codegenProfile == evmDefault.codegenProfile)
        "forged catalog cannot influence product frozen resolver"
  | .error e => throw <| IO.userError s!"forged catalog should validate: {e.render}"
  -- describe join positives/negatives
  match ProofForgeV2.CLI.describeTargetText "evm" with
  | .ok text =>
      expect (text.startsWith "target=evm\nprofile=evm-yul-solc-0.8.34-v1\n")
        s!"describe implemented evm, got {text}"
      expect (hasSubstr text "requirements=") "describe implemented includes requirements"
      expect (hasSubstr text "failure.atomic-rollback")
        "describe S2 ids from engineering support index"
      expect (hasSubstr text "state.persistent") "describe includes state.persistent"
      expect (hasSubstr text "value.checked-arithmetic")
        "describe includes value.checked-arithmetic"
      expect (!hasSubstr text "privateWitness")
        "describe must not surface residual alpha privateWitness"
      expect (!hasSubstr text "ProgramRequirement")
        "describe uses S2 request identities, not alpha Repr"
  | .error e => throw <| IO.userError s!"describe evm: {e.render}"
  match ProofForgeV2.CLI.describeTargetText "aleo" with
  | .ok text =>
      expect (text == "target=aleo\nstatus=research-only")
        s!"describe design-only, got {text}"
  | .error e => throw <| IO.userError s!"describe aleo: {e.render}"
  expectErrorCode (ProofForgeV2.CLI.describeTargetText "ghost-target")
    "PF-TARGET-UNKNOWN" "describe unknown grammar-valid target"
  expectErrorCode (ProofForgeV2.CLI.describeTargetText "EVM")
    "PF-TARGET-UNKNOWN" "describe rejects case-mismatched target"
  -- Synthetic describeImplementedJoin mismatches
  let implReg : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
    maturityLabel := "ok"
  }
  let wrongTargetDesc := { Targets.Evm.descriptor with targetId := TargetId.near }
  expectErrorCode
    (ProofForgeV2.CLI.describeImplementedJoin implReg wrongTargetDesc)
    "PF-REGISTRY-INVALID" "describe join targetId mismatch"
  let wrongProfileDesc :=
    { Targets.Evm.descriptor with codegenProfile := CodegenProfileId.nearWasmRawU64V1 }
  expectErrorCode
    (ProofForgeV2.CLI.describeImplementedJoin implReg wrongProfileDesc)
    "PF-REGISTRY-INVALID" "describe join profile mismatch"
  -- Positive join on real descriptor
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
  let residual := CompiledProgramV1.alphaResidualOf compiled
  for tid in #[TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let selection ← liftResult <| resolveBuildSelectionV1 tid none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    let output ← liftResult <| Targets.materializeResult capability
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty) s!"{tid} must emit artifacts"
    expect (MaterializedArtifactsV1.targetIdOf output == tid)
      s!"carrier target identity for {tid}"
    expect (MaterializedArtifactsV1.residualSourceHashOf output == residual.sourceHash)
      s!"carrier residual sourceHash identity for {tid}"
    expect (MaterializedArtifactsV1.residualSemanticHashOf output == residual.semanticHash)
      s!"carrier residual semanticHash identity for {tid}"
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
  expect (receipt.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)
    "emitProgram profile identity"
  let evmSel ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let evmCap ← liftResult <| Targets.resolveEngineeringRequirementsV1 evmSel compiled
  let evmOut ← liftResult <| Targets.materializeResult evmCap
  expect ((MaterializedArtifactsV1.targetIdOf evmOut).toString == "evm")
    "EVM carrier target wire"
  expect (MaterializedArtifactsV1.codegenProfileIdOf evmOut ==
      CodegenProfileId.evmYulSolc0834V1)
    "EVM carrier profile wire"
  -- On-disk v2alpha1 (private CLI renderer) after real emit for EVM wire bytes.
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
  testIndexValidation
  testIndexNegatives
  let evmDefault ← testResolve
  testCliDispatcher evmDefault
  testMaterializeIdentity

end Tests.Materialization.BuildSelectionV1

/-! ## Compile-time proof: identity types have no `Inhabited`

These `#guard_msgs` blocks are evaluated when the suite file is typechecked
(`lake env lean` / ordinary CI). They fail closed if an `Inhabited` instance is
reintroduced for opaque TargetId / CodegenProfileId / NetworkProfileId.
-/

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
