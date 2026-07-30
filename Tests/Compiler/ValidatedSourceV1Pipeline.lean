import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1

-- Large decisive-matrix + S3/S5 gate suite; raise elaboration fuel for nested AST fixtures.
set_option maxRecDepth 4096

namespace Tests.Compiler.ValidatedSourceV1Pipeline

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private abbrev SemanticProgramV1 := ProofForgeV2.Semantic.WireV1.SemanticProgramV1
private def validateSemanticProgramV1 :=
  ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
private def semanticHashV1 := ProofForgeV2.Semantic.WireV1.semanticHashV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

/-- Detail string from any product CompileError (CheckV1 gate may surface
    invalidProgram / effectDisallowed / visibilityViolation / resourceBound). -/
private def errorDetail : CompileResult α → Option String
  | .error e => some e.message
  | _ => none

private def expectInvalid (label want : String) (r : CompileResult α) : IO Unit :=
  expect (errorDetail r == some want)
    s!"{label}: expected {want}, got {errorDetail r}"

private def expectRender (label want : String) (r : CompileResult α) : IO Unit :=
  match r with
  | .error e =>
      expect (e.render == want) s!"{label}: expected render {want}, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error render {want}"

private def n (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def q (parts : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified name" (parseSourceQualifiedNameV1 parts)

private def block (statements : Array StmtV1) : BlockV1 := { statements }
private def ret (value : ExprV1) : BlockV1 := block #[.return_ (some value)]
private def u (value : Nat) : ExprV1 := .literal (.integer value)
private def var (name : SourceNameComponentV1) : ExprV1 := .place (.name name)
private def param (name : SourceNameComponentV1) (type_ : TypeV1 := .uint 64)
    (visibility : VisibilityV1 := .public_) : ParamV1 := { visibility, name, type_ }
private def entry (name : SourceNameComponentV1) (body : BlockV1)
    (params : Array ParamV1 := #[]) (result : TypeV1 := .uint 64) : EntryDeclV1 :=
  { name, params, result, body }
private def view (name : SourceNameComponentV1) (body : BlockV1)
    (params : Array ParamV1 := #[]) (result : TypeV1 := .uint 64) : ViewDeclV1 :=
  { name, params, result, body }
private def state (name : SourceNameComponentV1) (type_ : TypeV1 := .uint 64)
    (visibility : VisibilityV1 := .public_) : StateDeclV1 := { visibility, name, type_ }

private def validated (module identity : SourceQualifiedNameV1)
    (name : SourceNameComponentV1) (items : Array ProgramItemV1) : IO ValidatedSourceV1 :=
  lift "validate" (validateSourceV1 module identity { name, items })

private def compileOk (label : String) (source : ValidatedSourceV1) : IO CompiledSemanticV1 :=
  match Compiler.compileValidatedSourceV1 source with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

/-- Assert direct Normalize produces structure-valid carrier with deterministic hash. -/
private def expectNormalizeDeterministic (label : String) (source : ValidatedSourceV1) :
    IO Unit := do
  let c1 ← match normalizeProgramV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{label}: normalize #1 failed: {repr e}"
  let c2 ← match normalizeProgramV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{label}: normalize #2 failed: {repr e}"
  match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1 c1 with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: validate failed: {repr e}"
  expect (c1.canonicalBytes == c2.canonicalBytes)
    s!"{label}: canonicalBytes must be deterministic"
  let h1 ← match ProofForgeV2.Semantic.WireV1.semanticHashV1 c1 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"{label}: hash #1: {repr e}"
  let h2 ← match ProofForgeV2.Semantic.WireV1.semanticHashV1 c2 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"{label}: hash #2: {repr e}"
  expect (h1 == h2) s!"{label}: semanticHashV1 must be deterministic"

/-- Product path: NormalizeV1 structure gate → single CompiledSemanticV1;
    Counter + Accumulator S1 positives, canonical source/semantic identity,
    CheckV1 wires, and out-of-S1 fail-closed behavior. -/
def run : IO Unit := do
  let demo ← n "Demo"; let x ← n "x"; let y ← n "y"; let seed ← n "seed"
  let runN ← n "run"; let getN ← n "get"; let total ← n "total"
  let amount ← n "amount"; let peer ← q #["Peer", "go"]
  let moduleName ← q #["Tests", "Pipeline"]; let identity ← q #["Tests", "Pipeline", "Demo"]
  let quotedModule ← q #["Root"]
  let quotedIdentity ← q #["Root", "A.B", "C"]  -- Source-legal dotted component; Normalize rejects

  -- Counter-shaped S1: public UInt64 state, init/entry/view, bare place, binary +.
  let counterItems : Array ProgramItemV1 := #[
    .state (state x),
    .init { params := #[param seed], body := block #[.assign (.name x) (var seed)] },
    .entry (entry runN (block #[
      .assign (.name x) (.binary .add (var x) (var y)),
      .return_ (some (var x))]) #[param y]),
    .view (view getN (ret (var x)))]
  let counter ← validated moduleName identity demo counterItems
  let counterCompiled ← compileOk "counter S1" counter
  let retained := CompiledSemanticV1.semanticV1Of counterCompiled
  let counterData ← match validateSemanticProgramV1 retained with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"retained carrier structure invalid: {repr error}"
  expect (counterData.qualifiedName.components.toArray == #["Tests", "Pipeline", "Demo"] &&
      CompiledSemanticV1.artifactProgramNameOf counterCompiled == "Demo")
    "compiled program name must be the retained qualified-name final component"
  expect (counterData.logicalState.map (·.name) == #["x"])
    "S1 counter state bucket"
  expect (counterData.callables.filterMap (·.name) == #["run", "get"])
    "entry and view must share relative source order"
  let digest ← lift "source hash" (sourceHashV1 counter)
  expect (CompiledSemanticV1.sourceDigestOf counterCompiled == digest)
    "compiled source digest must equal canonical sourceHashV1"
  let sourceHex ← match CompiledSemanticV1.artifactSourceHashHexOf counterCompiled with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"compiled source hex: {error.render}"
  let rendered ← lift "render digest" (renderDigest digest)
  expect (rendered == "sha256:" ++ sourceHex)
    "derived artifact source hex must be the sourceHashV1 suffix"
  expectNormalizeDeterministic "counter normalize" counter

  -- Retained SemanticProgramV1 structure and sole ProgramRequirementsV1 freeze.
  expect (counterData.requirements.items.size == 3)
    s!"retained carrier must freeze three S2 requirements, got {counterData.requirements.items.size}"
  let expectReq (i : Nat) (id : String) : IO Unit := do
    let some item := counterData.requirements.items[i]? |
      throw <| IO.userError s!"retained missing requirement[{i}]"
    expect (item.id == id) s!"retained req[{i}] id, got {item.id}"
    expect (item.version == s2RequirementVersionV1)
      s!"retained req[{i}] version 1.0.0"
    expect item.predicates.isEmpty s!"retained req[{i}] empty predicates"
    let dig ← lift s!"digest {id}" (engineeringRequirementDigestV1 id)
    expect (item.digest == dig) s!"retained req[{i}] engineering digest"
  expectReq 0 "failure.atomic-rollback"
  expectReq 1 "state.persistent"
  expectReq 2 "value.checked-arithmetic"
  let directNorm ← match normalizeProgramV1 counter with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"direct normalize for retention: {repr e}"
  expect (retained.canonicalBytes == directNorm.canonicalBytes)
    "compileValidatedSourceV1 must retain NormalizeV1 canonicalBytes"
  let retainedHash ← match semanticHashV1 retained with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"retained hash: {repr e}"
  let directHash ← match semanticHashV1 directNorm with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"direct hash: {repr e}"
  expect (retainedHash == directHash &&
      CompiledSemanticV1.semanticDigestOf counterCompiled == retainedHash)
    "compiled semantic digest must equal direct Normalize semanticHashV1"
  let semanticHex ← match CompiledSemanticV1.artifactSemanticHashHexOf counterCompiled with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"compiled semantic hex: {error.render}"
  let semanticWire ← lift "semantic digest render" (renderDigest retainedHash)
  expect (semanticWire == "sha256:" ++ semanticHex)
    "derived artifact semantic hex must be the semanticHashV1 suffix"

  -- Accumulator-shaped S1 (distinct names from Counter).
  let accName ← n "Accumulator"
  let accIdentity ← q #["Tests", "Pipeline", "Accumulator"]
  let acc ← validated moduleName accIdentity accName #[
    .state (state total),
    .init { params := #[param seed], body := block #[.assign (.name total) (var seed)] },
    .entry (entry (← n "add") (block #[
      .assign (.name total) (.binary .add (var total) (var amount)),
      .return_ (some (var total))]) #[param amount]),
    .view (view (← n "current") (ret (var total)))]
  let accCompiled ← compileOk "accumulator S1" acc
  let accData ← match validateSemanticProgramV1 (CompiledSemanticV1.semanticV1Of accCompiled) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"accumulator semantic: {repr error}"
  expect (CompiledSemanticV1.artifactProgramNameOf accCompiled == "Accumulator" &&
      accData.logicalState.map (·.name) == #["total"] &&
      accData.callables.filterMap (·.name) == #["add", "current"])
    "accumulator retained semantic names"
  expectNormalizeDeterministic "accumulator normalize" acc

  -- Program identity for product compile must use Common.QualifiedName-legal
  -- components (Normalize structure gate). Distinct multi-component boundaries
  -- and short names remain; embedded-dot components fail closed at Normalize.
  let cName ← n "C"
  let pathABC ← validated quotedModule (← q #["Root", "A", "B", "C"]) cName
    #[.entry (entry runN (ret (var seed)) #[param seed])]
  let pathABCCompiled ← compileOk "multi-component identity" pathABC
  let pathABCData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of pathABCCompiled) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"path ABC semantic: {repr error}"
  expect (pathABCData.qualifiedName.components.toArray == #["Root", "A", "B", "C"])
    "multi-component identity must lower through Normalize"
  let pathAXC ← validated quotedModule (← q #["Root", "AX", "C"]) (← n "C")
    #[.entry (entry runN (ret (var seed)) #[param seed])]
  let pathAXCCompiled ← compileOk "identity boundary twin" pathAXC
  let pathAXCData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of pathAXCCompiled) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"path AXC semantic: {repr error}"
  expect (pathABCData.qualifiedName != pathAXCData.qualifiedName &&
      CompiledSemanticV1.artifactProgramNameOf pathAXCCompiled == "C")
    "distinct component boundaries must remain distinct after Normalize"
  let minimal ← validated quotedModule (← q #["Root", "C"]) cName
    #[.entry (entry runN (ret (var seed)) #[param seed])]
  let minimalCompiled ← compileOk "minimum identity" minimal
  let minimalData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of minimalCompiled) with
    | .ok data => pure data
    | .error error => throw <| IO.userError s!"minimum identity semantic: {repr error}"
  expect (minimalData.qualifiedName.components.toArray == #["Root", "C"])
    "minimum two-component identity must lower"
  -- Embedded-dot program-identity component is Source-legal but Normalize identity
  -- rejects it (Common.QualifiedName Lean-identifier rule) — fail closed.
  let dottedId ← validated quotedModule quotedIdentity cName
    #[.entry (entry runN (ret (var seed)) #[param seed])]
  match Compiler.compileValidatedSourceV1 dottedId with
  | .error (.invalidProgram msg) =>
      expect (msg.contains "qualified-name component" || msg.contains "identifier")
        s!"dotted identity must fail Normalize identity, got {msg}"
  | .error e => throw <| IO.userError s!"dotted identity wrong error: {e.render}"
  | .ok _ => throw <| IO.userError "dotted identity component must not full-compile"
  let dottedState ← n "state.value"; let dottedParam ← n "arg.value"
  let dottedEntry ← n "run.call"
  let rawNames ← validated moduleName identity demo #[
    .state (state dottedState),
    .entry (entry dottedEntry (ret (var dottedParam)) #[param dottedParam])]
  expectInvalid "raw unqualified name grammar gate"
    "semantic structure gate: badScalar"
    (Compiler.compileValidatedSourceV1 rawNames)

  -- Cross-kind reorder: S1 public state + param-echo entry/view (no literals).
  let reordered ← validated moduleName identity demo #[
    .entry (entry runN (ret (var seed)) #[param seed]), .state (state x),
    .view (view getN (ret (var x)))]
  let original ← validated moduleName identity demo #[
    .state (state x), .entry (entry runN (ret (var seed)) #[param seed]),
    .view (view getN (ret (var x)))]
  let a ← compileOk "order original" original
  let b ← compileOk "order twin" reordered
  expect (CompiledSemanticV1.sourceDigestOf a != CompiledSemanticV1.sourceDigestOf b)
    "cross-kind source reorder must change sourceHashV1"
  expect ((CompiledSemanticV1.semanticV1Of a).canonicalBytes ==
      (CompiledSemanticV1.semanticV1Of b).canonicalBytes &&
      CompiledSemanticV1.semanticDigestOf a == CompiledSemanticV1.semanticDigestOf b)
    "Semantic canonical bytes and hash must ignore source-order provenance"

  -- The dual-carrier parity seam is deleted: Normalize requirements and
  -- CompiledSemanticV1 digests are now the only product identities.

  -- Decisive Normalize-gate negatives (CheckV1 ok, Normalize rejects, no alpha path).
  let privateUnused ← validated moduleName identity demo #[
    .state (state x (.uint 64) .private_),
    .entry (entry runN (ret (var seed)) #[param seed])]
  expectInvalid "private state normalize gate"
    "S1 normalizer supports only public state, got non-public 'x'"
    (Compiler.compileValidatedSourceV1 privateUnused)
  let commitmentUnused ← validated moduleName identity demo #[
    .state (state x (.uint 64) .commitment),
    .entry (entry runN (ret (var seed)) #[param seed])]
  expectInvalid "commitment state normalize gate"
    "S1 normalizer supports only public state, got non-public 'x'"
    (Compiler.compileValidatedSourceV1 commitmentUnused)
  let fnLocalClean ← validated moduleName identity demo #[
    ProgramItemV1.fn {
      name := x
      params := #[param seed]
      result := .uint 64
      body := ret (var seed)
    },
    .entry (entry runN (ret (.localCall x #[var seed])) #[param seed])]
  expectInvalid "fn/localCall normalize gate"
    "S1 normalizer does not support fn"
    (Compiler.compileValidatedSourceV1 fnLocalClean)
  -- UInt64 literal-only programs pass Normalize and retain exact value bytes in
  -- the single compiled SemanticProgramV1 carrier.
  let literalOnly ← validated moduleName identity demo #[
    .entry (entry runN (ret (u 72623859790382856)))]
  let literalCompiled ← compileOk "literal-only product compile" literalOnly
  expectNormalizeDeterministic "literal-only normalize" literalOnly
  let literalRetained := CompiledSemanticV1.semanticV1Of literalCompiled
  let literalData ← match validateSemanticProgramV1 literalRetained with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"literal-only retained carrier: {repr e}"
  let some literalInstr := literalData.callables[0]?.bind (·.blocks[0]?) |>.bind
      (·.instructions[0]?) |
    throw <| IO.userError "literal-only: missing retained instruction"
  match literalInstr.op with
  | .literal tid bytes =>
      expect (tid == 0 && bytes == ByteArray.mk #[(0x08 : UInt8), 0x07, 0x06,
          0x05, 0x04, 0x03, 0x02, 0x01])
        "literal-only: retained Op.Literal exact little-endian bytes"
  | _ => throw <| IO.userError "literal-only: expected retained Op.Literal"
  let literalHash ← match semanticHashV1 literalRetained with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError s!"literal-only semantic hash: {repr error}"
  expect (CompiledSemanticV1.semanticDigestOf literalCompiled == literalHash)
    "literal-only compiled digest must bind retained semantic bytes"
  let callOnly ← validated moduleName identity demo #[
    .entry (entry runN (block #[
      .call { callee := peer, args := #[] },
      .return_ (some (var seed))]) #[param seed])]
  expectInvalid "call normalize gate"
    "S1 normalizer does not support call"
    (Compiler.compileValidatedSourceV1 callOnly)
  -- schedule is the alpha-shape sibling of call: CheckV1-ok, Normalize reject.
  let scheduleOnly ← validated moduleName identity demo #[
    .entry (entry runN (block #[
      .schedule { callee := peer, args := #[] },
      .return_ (some (var seed))]) #[param seed])]
  expectInvalid "schedule normalize gate"
    "S1 normalizer does not support schedule"
    (Compiler.compileValidatedSourceV1 scheduleOnly)
  -- Unit bare `return` (return_ none): CheckV1 allows empty return when result
  -- is Unit; S1 rejects at Normalize so product never hits residual Stmt.Return.
  let bareReturn ← validated moduleName identity demo #[
    .entry (entry runN (block #[.return_ none]) #[] .unit)]
  expectInvalid "unit bare-return normalize gate"
    "S1 normalizer does not support bare return"
    (Compiler.compileValidatedSourceV1 bareReturn)
  -- Init with explicit bare return after assign also fails at Normalize (implicit
  -- terminator-none when source omits return remains the only Unit path).
  let initBareReturn ← validated moduleName identity demo #[
    .state (state x),
    .init { params := #[param seed], body := block #[
      .assign (.name x) (var seed),
      .return_ none] },
    .entry (entry runN (ret (var seed)) #[param seed])]
  expectInvalid "init bare-return normalize gate"
    "S1 normalizer does not support bare return"
    (Compiler.compileValidatedSourceV1 initBareReturn)

  -- Product wire-error message contract: structure-gate failures map to a fixed
  -- prefix + closed SemanticWireErrorV1 summary (never Lean repr). Empty
  -- SemanticProgramDataV1 fails encode with a stable wire tag.
  let emptyQn ← lift "empty qn" (parseQualifiedName #["Tests", "EmptyWire"])
  let emptyData : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1 := {
    qualifiedName := emptyQn
    types := #[]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables := #[]
    invariants := #[]
    requirements := { items := #[] }
  }
  match encodeCarrierV1 emptyData with
  | .error (.wire e) =>
      -- Pin exact closed product text used by compileErrorFromNormalizeV1 (.wire).
      expect (Compiler.productMessageFromWireErrorV1 e ==
          "semantic structure gate: badCfg")
        s!"empty SemanticProgramDataV1 encode must surface badCfg product text, got {Compiler.productMessageFromWireErrorV1 e}"
  | .error other =>
      throw <| IO.userError s!"empty encode expected .wire, got {repr other}"
  | .ok _ =>
      throw <| IO.userError "empty SemanticProgramDataV1 must fail structure gate"

  -- Closed productMessageFromWireErrorV1 contract over every SemanticWireErrorV1
  -- constructor. Expected strings are independent hand-written product literals
  -- (never built via productMessageFromWireErrorV1 / production match copy).
  let wireMsgTable :
      Array (ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1 × String) := #[
    (.truncated, "semantic structure gate: truncated"),
    (.limitExceeded, "semantic structure gate: limitExceeded"),
    (.badMagic, "semantic structure gate: badMagic"),
    (.badTag, "semantic structure gate: badTag"),
    (.badFieldCount, "semantic structure gate: badFieldCount"),
    (.badScalar, "semantic structure gate: badScalar"),
    (.nonCanonical, "semantic structure gate: nonCanonical"),
    (.duplicate, "semantic structure gate: duplicate"),
    (.badReference, "semantic structure gate: badReference"),
    (.badType, "semantic structure gate: badType"),
    (.badCfg, "semantic structure gate: badCfg"),
    (.badRequirement, "semantic structure gate: badRequirement"),
    (.badProvenance, "semantic structure gate: badProvenance"),
    (.trailingBytes, "semantic structure gate: trailingBytes")
  ]
  expect (wireMsgTable.size == 14)
    s!"SemanticWireErrorV1 product-message table size must be 14, got {wireMsgTable.size}"
  -- Exhaustive test-local constructor→table membership guard (no wildcard /
  -- catch-all). A new SemanticWireErrorV1 constructor makes this match
  -- non-exhaustive at compile time until the independent table and this guard
  -- are updated. Incomplete table fails at runtime when the missing ctor is
  -- exercised below.
  let tableWant
      (e : ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1) : Option String :=
    match e with
    | .truncated =>
        (wireMsgTable.find? (fun p => p.1 == .truncated)).map (·.2)
    | .limitExceeded =>
        (wireMsgTable.find? (fun p => p.1 == .limitExceeded)).map (·.2)
    | .badMagic =>
        (wireMsgTable.find? (fun p => p.1 == .badMagic)).map (·.2)
    | .badTag =>
        (wireMsgTable.find? (fun p => p.1 == .badTag)).map (·.2)
    | .badFieldCount =>
        (wireMsgTable.find? (fun p => p.1 == .badFieldCount)).map (·.2)
    | .badScalar =>
        (wireMsgTable.find? (fun p => p.1 == .badScalar)).map (·.2)
    | .nonCanonical =>
        (wireMsgTable.find? (fun p => p.1 == .nonCanonical)).map (·.2)
    | .duplicate =>
        (wireMsgTable.find? (fun p => p.1 == .duplicate)).map (·.2)
    | .badReference =>
        (wireMsgTable.find? (fun p => p.1 == .badReference)).map (·.2)
    | .badType =>
        (wireMsgTable.find? (fun p => p.1 == .badType)).map (·.2)
    | .badCfg =>
        (wireMsgTable.find? (fun p => p.1 == .badCfg)).map (·.2)
    | .badRequirement =>
        (wireMsgTable.find? (fun p => p.1 == .badRequirement)).map (·.2)
    | .badProvenance =>
        (wireMsgTable.find? (fun p => p.1 == .badProvenance)).map (·.2)
    | .trailingBytes =>
        (wireMsgTable.find? (fun p => p.1 == .trailingBytes)).map (·.2)
  -- Drive every current constructor through the exhaustive guard (not only
  -- rows already present in the table).
  let allWireCtors : Array ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1 := #[
    .truncated, .limitExceeded, .badMagic, .badTag, .badFieldCount,
    .badScalar, .nonCanonical, .duplicate, .badReference, .badType,
    .badCfg, .badRequirement, .badProvenance, .trailingBytes
  ]
  expect (allWireCtors.size == 14)
    s!"exhaustive SemanticWireErrorV1 constructor drive size must be 14, got {allWireCtors.size}"
  for e in allWireCtors do
    match tableWant e with
    | some want =>
        expect (Compiler.productMessageFromWireErrorV1 e == want)
          s!"exhaustive tableWant {repr e}: productMessageFromWireErrorV1 expected {want}, got {Compiler.productMessageFromWireErrorV1 e}"
    | none =>
        throw <| IO.userError
          s!"wireMsgTable missing independent row for constructor {repr e}"
  for i in [0:wireMsgTable.size] do
    for j in [i+1:wireMsgTable.size] do
      match wireMsgTable[i]?, wireMsgTable[j]? with
      | some (ei, wanti), some (ej, wantj) =>
          expect (ei != ej)
            s!"wire-message table constructors at {i} and {j} must be unique"
          expect (wanti != wantj)
            s!"wire-message table expected strings at {i} and {j} must be unique"
      | _, _ =>
          throw <| IO.userError
            s!"wire-message table index OOB while checking uniqueness ({i},{j})"
  for (e, want) in wireMsgTable do
    let got := Compiler.productMessageFromWireErrorV1 e
    expect (got == want)
      s!"productMessageFromWireErrorV1 {repr e}: expected {want}, got {got}"
    -- Anti-repr guard: product text must not dump Lean Repr of the enum.
    expect (!((got.splitOn "SemanticWireErrorV1.").length > 1))
      s!"productMessageFromWireErrorV1 must not embed Repr enum path, got {got}"
    expect (got != toString (repr e))
      s!"productMessageFromWireErrorV1 must not equal bare Repr, got {got}"

  -- Top-level alternatives: CheckV1 runs first (via Normalize typedNotOk).
  -- Well-typed constructors fail at Normalize S1 unsupported detail.
  let hostile := .literal (.string "HOSTILE")
  let digest0 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let topCases : Array (String × Array ProgramItemV1 × String) := #[
    ("StructDecl", #[.struct { name := x, fields := #[{ name := y, type_ := .map .bool .bool }] }],
      "S1 normalizer does not support struct"),
    ("EnumDecl", #[.enum { name := x, variants := #[{ name := y, payloadTypes := #[.map .bool .bool] }] }],
      "S1 normalizer does not support enum"),
    ("ConstDecl", #[.const { name := x, type_ := .map .bool .bool, value := hostile }],
      "type mismatch: expected Map (Bool) (Bool), got string literal"),
    ("EventDecl", #[.event { name := x, params := #[param y (.map .bool .bool)] }],
      "S1 normalizer does not support event"),
    ("ErrorDecl", #[.error { name := x, params := #[param y (.map .bool .bool)] }],
      "S1 normalizer does not support error"),
    ("FnDecl",
      #[ProgramItemV1.fn {
          name := x
          params := #[param y (.map .bool .bool)]
          result := .map .bool .bool
          body := ret hostile
        }],
      "type mismatch: expected Map (Bool) (Bool), got string literal"),
    ("InvariantDecl", #[.invariant { name := x, predicate := hostile }],
      "type mismatch: expected Bool, got string literal"),
    ("ExtensionReq", #[.extensionReq { id := peer, version := "1.0.0", digest := digest0 }],
      "S1 normalizer does not support extension"),
    ("ProofDecl", #[.proof { invariant := x, theorem_ := peer },
      .invariant { name := x, predicate := hostile }],
      "type mismatch: expected Bool, got string literal")]
  for (tag, itemPrefix, want) in topCases do
    -- Entry uses param-echo so CheckV1-clean constructors hit Normalize unsupported,
    -- not the isolated legacy alpha "validated ProgramV1 lowering does not support …" path.
    let bad ← validated moduleName identity demo
      (itemPrefix.push (.entry (entry runN (ret (var seed)) #[param seed])))
    expectInvalid s!"top {tag}" want (Compiler.compileValidatedSourceV1 bad)

  -- Named types fail CheckV1 resolution; Map-shaped types reach Normalize S1.
  let typeCases : Array (String × TypeV1 × String) := #[
    ("Type.Named", .named x, "name 'x' resolved to state but expected type"),
    ("Type.Map", .map .bool .bool, "S1 normalizer does not support Map"),
    ("Type.Named nested", .option (.array (.named x) 1),
      "name 'x' resolved to state but expected type"),
    ("Type.Map nested", .array (.option (.map .bool .bool)) 1, "S1 normalizer does not support Array")]
  for (tag, type_, want) in typeCases do
    let bad ← validated moduleName identity demo
      #[.state (state x type_), .entry (entry runN (ret (var seed)) #[param seed])]
    expectInvalid s!"type {tag}" want (Compiler.compileValidatedSourceV1 bad)

  let patterns : Array PatternV1 := #[.wildcard, .bind x, .literal (.bool true), .constructor peer #[]]
  let exprArms := patterns.map fun p => { pattern := p, value := hostile }
  let mut exprCases : Array (String × ExprV1 × String) := #[
    ("Literal.Bool", .literal (.bool true), "type mismatch: expected UInt64, got Bool"),
    ("Literal.String", hostile, "type mismatch: expected UInt64, got string literal"),
    ("Place.Field", .place (.field (.name x) y), "unknown name 'x' (expected value)"),
    ("Place.Index", .place (.index (.name x) hostile), "unknown name 'x' (expected value)"),
    ("Expr.Constructor", .constructor peer #[hostile],
      "unknown name 'Peer' (expected constructor enum)"),
    ("Expr.Unary.neg", .unary .neg hostile,
      "type mismatch: expected expected type, got string literal"),
    ("Expr.Unary.not", .unary .not hostile, "type mismatch: expected Bool, got string literal"),
    ("Expr.Unary.bitNot", .unary .bitNot hostile,
      "type mismatch: expected expected type, got string literal"),
    ("Expr.LocalCall", .localCall x #[hostile], "unknown name 'x' (expected function)"),
    ("Expr.Match", .match_ hostile exprArms, "unknown name 'Peer' (expected constructor enum)")]
  let arithBinary : Array (String × BinaryOpV1) := #[
    ("BinaryOp.Sub", .sub), ("BinaryOp.Mul", .mul), ("BinaryOp.Div", .div),
    ("BinaryOp.Mod", .mod), ("BinaryOp.BitAnd", .bitAnd), ("BinaryOp.BitOr", .bitOr),
    ("BinaryOp.BitXor", .bitXor)]
  for (tag, op) in arithBinary do
    exprCases := exprCases.push (tag, .binary op hostile hostile,
      "type mismatch: expected UInt64, got string literal")
  exprCases := exprCases.push ("BinaryOp.Eq", .binary .eq hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Ne", .binary .ne hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Lt", .binary .lt hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Le", .binary .le hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Gt", .binary .gt hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Ge", .binary .ge hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.And", .binary .logicalAnd hostile hostile,
    "type mismatch: expected Bool, got string literal")
  exprCases := exprCases.push ("BinaryOp.Or", .binary .logicalOr hostile hostile,
    "type mismatch: expected Bool, got string literal")
  exprCases := exprCases.push ("BinaryOp.Shl", .binary .shl hostile hostile,
    "type mismatch: expected UInt64, got string literal")
  exprCases := exprCases.push ("BinaryOp.Shr", .binary .shr hostile hostile,
    "type mismatch: expected UInt64, got string literal")
  for (tag, expression, want) in exprCases do
    let bad ← validated moduleName identity demo #[.entry (entry runN (ret expression))]
    expectInvalid s!"expression {tag}" want (Compiler.compileValidatedSourceV1 bad)
  let huge ← validated moduleName identity demo #[.entry (entry runN (ret (u (2^64))))]
  expectInvalid "integer range"
    "type mismatch: expected UInt64, got integer literal 18446744073709551616 out of range"
    (Compiler.compileValidatedSourceV1 huge)

  -- Statement families: CheckV1 resolution/type before Normalize unsupported.
  let stmtArms := patterns.map fun p => { pattern := p, body := ret hostile }
  let stmtCases : Array (String × StmtV1 × String) := #[
    ("Stmt.Let", .let_ x (some (.map .bool .bool)) hostile,
      "type mismatch: expected Map (Bool) (Bool), got string literal"),
    ("Stmt.Assign.field", .assign (.field (.name x) y) hostile, "unknown name 'x' (expected value)"),
    ("Stmt.Assign.index", .assign (.index (.name x) hostile) hostile, "unknown name 'x' (expected value)"),
    ("Stmt.If", .if_ hostile (ret hostile) (some (ret hostile)),
      "type mismatch: expected Bool, got string literal"),
    ("Stmt.Match", .match_ hostile stmtArms, "unknown name 'Peer' (expected constructor enum)"),
    ("Stmt.For", .for_ x hostile hostile 1 (ret hostile),
      "type mismatch: expected expected type, got string literal"),
    ("Stmt.Assert", .assert_ hostile none, "type mismatch: expected Bool, got string literal"),
    ("Stmt.Assert.error", .assert_ hostile (some x), "unknown name 'x' (expected error)"),
    ("Stmt.Revert", .revert x #[hostile], "unknown name 'x' (expected error)"),
    ("Stmt.Emit", .emit x #[hostile], "unknown name 'x' (expected event)"),
    ("Stmt.Return", .return_ none, "type mismatch: expected UInt64, got empty return"),
    ("Stmt.Schedule", .schedule { callee := peer, args := #[hostile] },
      "type mismatch: expected expected type, got string literal")]
  for (tag, statement, want) in stmtCases do
    let bad ← validated moduleName identity demo
      #[.entry (entry runN (block #[statement, .return_ (some (var seed))]) #[param seed])]
    expectInvalid s!"statement {tag}" want (Compiler.compileValidatedSourceV1 bad)
  let callArgs ← validated moduleName identity demo #[.entry (entry runN
    (block #[.call { callee := peer, args := #[hostile] }, .return_ (some (var seed))])
      #[param seed])]
  expectInvalid "call arguments" "type mismatch: expected expected type, got string literal"
    (Compiler.compileValidatedSourceV1 callArgs)

  -- Phase-order priority under CheckV1-first product gate (via Normalize typedNotOk).
  let priority : Array (String × Array ProgramItemV1 × String) := #[
    ("item order", #[.entry (entry runN (ret hostile)),
      .struct { name := x, fields := #[{ name := y, type_ := .bool }] }],
      "type mismatch: expected UInt64, got string literal"),
    ("add lhs", #[.entry (entry runN (ret (.binary .add hostile (.literal (.bool true)))))],
      "type mismatch: expected UInt64, got string literal"),
    ("assign target", #[.state (state x), .entry (entry runN (block #[
      .assign (.field (.name x) y) hostile, .return_ (some (var seed))]) #[param seed])],
      "type mismatch: expected struct type, got UInt64"),
    ("resolution before type", #[.entry (entry runN (block #[
      .return_ (some (var y)), .return_ (some hostile)]))],
      "unknown name 'y' (expected value)")]
  for (label, items, want) in priority do
    let bad ← validated moduleName identity demo items
    expectInvalid label want (Compiler.compileValidatedSourceV1 bad)

  -- Product Typed gate: CheckV1 (incl. EffectCheckV1) wins when it fires.
  -- After-return / missing-return now surface via Normalize S1 detail; the
  -- isolated legacy alpha checker is not a product post-gate.
  let typedCases : Array (String × Array ProgramItemV1 × String) := #[
    ("unknown", #[.entry (entry runN (ret (var y)))], "unknown name 'y' (expected value)"),
    ("assign", #[.entry (entry runN (block #[.assign (.name y) (u 1), .return_ (some (u 1))]))],
      "unknown name 'y' (expected value)"),
    ("view write", #[.state (state x), .view (view getN (block #[
      .assign (.name x) (u 1), .return_ (some (var x))]))],
      "view 'get' does not allow effect 'state.write'"),
    ("view call", #[.view (view getN (block #[
      .call { callee := peer, args := #[] }, .return_ (some (u 0))]))],
      "view 'get' does not allow effect 'external.call.sync'"),
    ("non-u64 add", #[.state (state x .bool), .entry (entry runN (ret (.binary .add (var x) (u 1))))],
      "type mismatch: expected UInt64, got Bool"),
    ("init return", #[.init { params := #[], body := block #[.return_ (some (u 0))] },
      .entry (entry runN (ret (var seed)) #[param seed])],
      "type mismatch: expected Unit, got integer literal"),
    ("missing return", #[.state (state x),
      .entry (entry runN (block #[.assign (.name x) (var seed)]) #[param seed] .unit)],
      "S1 normalizer requires explicit return for entry/view"),
    ("after return", #[.entry (entry runN (block #[
      .return_ (some (var seed)), .assign (.name x) (var seed)]) #[param seed]),
      .state (state x)],
      "S1 normalizer does not support statements after return"),
    ("return mismatch", #[.entry (entry runN (ret (u 0)) #[] .bool)],
      "type mismatch: expected Bool, got integer literal")]
  for (label, items, want) in typedCases do
    let bad ← validated moduleName identity demo items
    expectInvalid label want (Compiler.compileValidatedSourceV1 bad)

  -- Wire codes for effect-only product failures (CheckV1 via Normalize typedNotOk).
  expectRender "view write wire"
    "PF-EFFECT-001: view 'get' does not allow effect 'state.write'"
    (Compiler.compileValidatedSourceV1 (← validated moduleName identity demo
      #[.state (state x), .view (view getN (block #[.assign (.name x) (u 1), .return_ (some (var x))]))]))
  expectRender "view call wire"
    "PF-EFFECT-001: view 'get' does not allow effect 'external.call.sync'"
    (Compiler.compileValidatedSourceV1 (← validated moduleName identity demo
      #[.view (view getN (block #[.call { callee := peer, args := #[] }, .return_ (some (u 0))]))]))

  -- Bound-only product wire: well-typed triple-nested for product overflow maps
  -- DiagnosticCodeV1.resourceBound → CompileError.resourceBound (PF-BOUND-001).
  let totalB ← n "totalB"; let startN ← n "start"; let stopN ← n "stop"
  let i ← n "i"; let j ← n "j"; let k ← n "k"
  let tripleNest : BlockV1 := block #[
    .for_ i (var startN) (var stopN) 4096 (block #[
      .for_ j (var startN) (var stopN) 4096 (block #[
        .for_ k (var startN) (var stopN) 4096 (block #[
          .assign (.name totalB) (var i)])])])]
  expectRender "bound loop product wire"
    "PF-BOUND-001: loop bound product overflows UInt32 in entry 'run' (bound 4096)"
    (Compiler.compileValidatedSourceV1 (← validated moduleName identity demo
      #[.state (state totalB), .state (state startN), .state (state stopN),
        .entry (entry runN tripleNest #[] .unit)]))

end Tests.Compiler.ValidatedSourceV1Pipeline
