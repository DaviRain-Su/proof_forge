/-
  Tests.Compiler.CheckV1ProductGate — product-path fail-closed gate for
  independent multi-pass CheckV1 inside NormalizeV1 / Typed.checkV1 /
  compileValidatedSourceV1.

  Pins Counter happy path (Normalize structure gate + residual alpha),
  type / effect / bound / disclosure product wires, Normalize-gate residual
  control-flow (missing/after-return) and private unused state fail closed at
  S1 Normalize (no alpha-only compile path). Bound-only coverage is a
  well-typed triple-nested `for bounded 4096` (UInt32 product overflow).
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Typed.CheckV1
import Tests.Language.ParserSession
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Compiler.CheckV1ProductGate

open ProofForgeV2
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Typed.CheckV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def n (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def q (parts : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified name" (parseSourceQualifiedNameV1 parts)

private def block (statements : Array StmtV1) : BlockV1 := { statements }
private def ret (value : ExprV1) : BlockV1 := block #[.return_ (some value)]
private def u (value : Nat) : ExprV1 := .literal (.integer value)
private def var (name : SourceNameComponentV1) : ExprV1 := .place (.name name)
private def param (name : SourceNameComponentV1) (ty : TypeV1 := .uint 64)
    (visibility : VisibilityV1 := .public_) : ParamV1 :=
  { visibility := visibility, name := name, type_ := ty }
private def mkEntry (name : SourceNameComponentV1) (body : BlockV1)
    (params : Array ParamV1 := #[]) (result : TypeV1 := .uint 64) : EntryDeclV1 :=
  { name := name, params := params, result := result, body := body }
private def mkView (name : SourceNameComponentV1) (body : BlockV1)
    (params : Array ParamV1 := #[]) (result : TypeV1 := .uint 64) : ViewDeclV1 :=
  { name := name, params := params, result := result, body := body }
private def mkState (name : SourceNameComponentV1) (ty : TypeV1 := .uint 64)
    (visibility : VisibilityV1 := .public_) : StateDeclV1 :=
  { visibility := visibility, name := name, type_ := ty }

private def validated (module identity : SourceQualifiedNameV1)
    (name : SourceNameComponentV1) (items : Array ProgramItemV1) : IO ValidatedSourceV1 :=
  lift "validate" (validateSourceV1 module identity { name, items })

private def expectOk (label : String) (r : CompileResult α) : IO α :=
  match r with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectRender (label want : String) (r : CompileResult α) : IO Unit :=
  match r with
  | .error e =>
      expect (e.render == want)
        s!"{label}: expected render {want}, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error {want}"

private def expectRenderPrefix (label wantPrefix : String) (r : CompileResult α) : IO Unit :=
  match r with
  | .error e =>
      expect (e.render.startsWith wantPrefix)
        s!"{label}: expected render prefix {wantPrefix}, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error prefix {wantPrefix}"

private def expectRenderContains (label wantPrefix needle : String) (r : CompileResult α) :
    IO Unit := do
  match r with
  | .error e =>
      expect (e.render.startsWith wantPrefix)
        s!"{label}: expected prefix {wantPrefix}, got {e.render}"
      expect (e.render.contains needle)
        s!"{label}: expected needle {needle}, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def expectNormalizeOk (label : String) (source : ValidatedSourceV1) : IO Unit := do
  let c1 ← match normalizeProgramV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{label}: normalize #1: {repr e}"
  let c2 ← match normalizeProgramV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{label}: normalize #2: {repr e}"
  match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1 c1 with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: validate: {repr e}"
  expect (c1.canonicalBytes == c2.canonicalBytes)
    s!"{label}: canonicalBytes deterministic"
  let h1 ← match ProofForgeV2.Semantic.WireV1.semanticHashV1 c1 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"{label}: hash1: {repr e}"
  let h2 ← match ProofForgeV2.Semantic.WireV1.semanticHashV1 c2 with
    | .ok h => pure h
    | .error e => throw <| IO.userError s!"{label}: hash2: {repr e}"
  expect (h1 == h2) s!"{label}: semanticHashV1 deterministic"

private def moduleName : String := "Tests.CheckV1ProductGate"

private unsafe def counterSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program CounterGate where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private unsafe def privateStateUnusedSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program PrivateUnusedGate where\n" ++
  "  state private secret : UInt64\n" ++
  "  entry ping(seed : UInt64) : UInt64 do\n" ++
  "    return seed\n"

private unsafe def accumulatorSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program AccumulatorGate where\n" ++
  "  state total : UInt64\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n"

/-- Direct AST / compileValidatedSourceV1 coverage of the product Typed + Normalize gate. -/
def runAst : IO Unit := do
  let demo ← n "Demo"; let count ← n "count"; let delta ← n "delta"
  let seed ← n "seed"; let inc ← n "increment"; let getN ← n "get"
  let runN ← n "run"; let x ← n "x"; let peer ← q #["Peer", "go"]
  let moduleQ ← q #["Tests", "Gate"]; let identity ← q #["Tests", "Gate", "Demo"]

  -- Counter-shaped ValidatedSourceV1 succeeds through product compile + Normalize.
  let counter ← validated moduleQ identity demo #[
    .state (mkState count),
    .init { params := #[param seed], body := block #[.assign (.name count) (var seed)] },
    .entry (mkEntry inc (block #[
      .assign (.name count) (.binary .add (var count) (var delta)),
      .return_ (some (var count))]) #[param delta]),
    .view (mkView getN (ret (var count)))]
  let _ ← expectOk "counter-ast" (Compiler.compileValidatedSourceV1 counter)
  let _ ← expectOk "counter-checkV1" (Typed.checkV1 counter)
  expectNormalizeOk "counter-ast-normalize" counter

  -- Accumulator-shaped S1 AST succeeds through product compile + Normalize.
  let total ← n "total"; let amount ← n "amount"; let addN ← n "add"; let cur ← n "current"
  let acc ← validated moduleQ (← q #["Tests", "Gate", "Accumulator"]) (← n "Accumulator") #[
    .state (mkState total),
    .init { params := #[param seed], body := block #[.assign (.name total) (var seed)] },
    .entry (mkEntry addN (block #[
      .assign (.name total) (.binary .add (var total) (var amount)),
      .return_ (some (var total))]) #[param amount]),
    .view (mkView cur (ret (var total)))]
  let _ ← expectOk "accumulator-ast" (Compiler.compileValidatedSourceV1 acc)
  expectNormalizeOk "accumulator-ast-normalize" acc

  -- Type-only: Bool return from UInt64 entry → PF-SRC-INVALID type mismatch.
  -- Full multi-error product bundle path is covered by DiagnosticPipelineV1;
  -- non-product compileValidatedSourceV1 remains a fixture convenience.
  let typeOnly ← validated moduleQ identity demo #[
    .entry (mkEntry runN (ret (.literal (.bool true))))]
  expectRender "type-only"
    "PF-SRC-INVALID: type mismatch: expected UInt64, got Bool"
    (Compiler.compileValidatedSourceV1 typeOnly)
  expectRenderPrefix "type-only-checkV1" "PF-SRC-INVALID:"
    (Typed.checkV1 typeOnly)

  -- Effect-only: view write/call → CompileError.effectDisallowed / PF-EFFECT-001
  -- via EffectCheckV1 (sole product allowlist authority). Never the retired alpha
  -- strings "cannot write state" / "cannot perform synchronous call".
  let viewWrite ← validated moduleQ identity demo #[
    .state (mkState count),
    .view (mkView getN (block #[.assign (.name count) (u 1), .return_ (some (var count))]))]
  let wantWrite := "PF-EFFECT-001: view 'get' does not allow effect 'state.write'"
  expectRender "effect-view-write" wantWrite (Compiler.compileValidatedSourceV1 viewWrite)
  expectRender "effect-view-write-checkV1" wantWrite (Typed.checkV1 viewWrite)
  match Typed.checkV1 viewWrite with
  | .error (.effectDisallowed msg) =>
      expect (msg == "view 'get' does not allow effect 'state.write'")
        s!"effect-view-write-ctor detail: {msg}"
  | .error e => throw <| IO.userError s!"effect-view-write-ctor: expected effectDisallowed, got {e.render}"
  | .ok _ => throw <| IO.userError "effect-view-write-ctor: expected error"
  match Compiler.compileValidatedSourceV1 viewWrite with
  | .error e =>
      expect (not (e.render.contains "cannot write state"))
        s!"effect-view-write must not use alpha residual string, got {e.render}"
  | .ok _ => throw <| IO.userError "effect-view-write must fail"

  let viewCall ← validated moduleQ identity demo #[
    .view (mkView getN (block #[.call { callee := peer, args := #[] }, .return_ (some (u 0))]))]
  let wantCall := "PF-EFFECT-001: view 'get' does not allow effect 'external.call.sync'"
  expectRender "effect-view-call" wantCall (Compiler.compileValidatedSourceV1 viewCall)
  expectRender "effect-view-call-checkV1" wantCall (Typed.checkV1 viewCall)
  match Typed.checkV1 viewCall with
  | .error (.effectDisallowed msg) =>
      expect (msg == "view 'get' does not allow effect 'external.call.sync'")
        s!"effect-view-call-ctor detail: {msg}"
  | .error e => throw <| IO.userError s!"effect-view-call-ctor: expected effectDisallowed, got {e.render}"
  | .ok _ => throw <| IO.userError "effect-view-call-ctor: expected error"
  match Compiler.compileValidatedSourceV1 viewCall with
  | .error e =>
      expect (not (e.render.contains "cannot perform synchronous call"))
        s!"effect-view-call must not use alpha residual string, got {e.render}"
  | .ok _ => throw <| IO.userError "effect-view-call must fail"

  -- Disclosure-only: private param returned publicly → PF-VIS-001.
  let disc ← validated moduleQ identity demo #[
    .entry (mkEntry runN (ret (var x)) #[param x (.uint 64) .private_])]
  expectRenderContains "disclosure-return" "PF-VIS-001:"
    "disclosure violation: cannot flow 'private' into 'public'"
    (Compiler.compileValidatedSourceV1 disc)

  -- Bound-only: well-typed triple-nested for bounded 4096 → PF-BOUND-001.
  let totalB ← n "totalB"; let start ← n "start"; let stop ← n "stop"
  let i ← n "i"; let j ← n "j"; let k ← n "k"
  let tripleNest : BlockV1 := block #[
    .for_ i (var start) (var stop) 4096 (block #[
      .for_ j (var start) (var stop) 4096 (block #[
        .for_ k (var start) (var stop) 4096 (block #[
          .assign (.name totalB) (var i)])])])]
  let boundOnly ← validated moduleQ identity demo #[
    .state (mkState totalB),
    .state (mkState start),
    .state (mkState stop),
    .entry (mkEntry runN tripleNest #[] .unit)]
  expectRender "bound-loop-product"
    "PF-BOUND-001: loop bound product overflows UInt32 in entry 'run' (bound 4096)"
    (Compiler.compileValidatedSourceV1 boundOnly)
  expectRender "bound-loop-product-checkV1"
    "PF-BOUND-001: loop bound product overflows UInt32 in entry 'run' (bound 4096)"
    (Typed.checkV1 boundOnly)

  -- Residual control-flow now fails at Normalize S1 (gate before alpha residual).
  -- Nonempty block without return (unit entry + state assign); empty blocks are
  -- rejected by ValidatedSourceV1 before the compiler.
  let missing ← validated moduleQ identity demo #[
    .state (mkState count),
    .entry (mkEntry runN (block #[.assign (.name count) (var seed)]) #[param seed] .unit)]
  expectRender "normalize-missing-return"
    "PF-SRC-INVALID: S1 normalizer requires explicit return for entry/view"
    (Compiler.compileValidatedSourceV1 missing)

  let after ← validated moduleQ identity demo #[
    .state (mkState count),
    .entry (mkEntry runN (block #[
      .return_ (some (var seed)),
      .assign (.name count) (var seed)]) #[param seed])]
  expectRender "normalize-after-return"
    "PF-SRC-INVALID: S1 normalizer does not support statements after return"
    (Compiler.compileValidatedSourceV1 after)

  -- Private state unused: CheckV1 may succeed; product compile fails at Normalize.
  let priv ← validated moduleQ identity demo #[
    .state (mkState count (.uint 64) .private_),
    .entry (mkEntry runN (ret (var seed)) #[param seed])]
  let _ ← expectOk "private-unused-checkV1" (Typed.checkV1 priv)
  expectRender "private-unused-normalize-gate"
    "PF-SRC-INVALID: S1 normalizer supports only public state, got non-public 'count'"
    (Compiler.compileValidatedSourceV1 priv)

  -- UInt64 literal-only entry succeeds through the sole Normalize-first product
  -- path; retained SemanticProgramV1 contains the exact Op.Literal bytes.
  let litOnly ← validated moduleQ identity demo #[
    .entry (mkEntry runN (ret (u 72623859790382856)))]
  let _ ← expectOk "literal-only-checkV1" (Typed.checkV1 litOnly)
  let litCompiled ← expectOk "literal-only-compile"
    (Compiler.compileValidatedSourceV1 litOnly)
  expectNormalizeOk "literal-only-normalize" litOnly
  let litData ← match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
      (Compiler.CompiledProgramV1.semanticV1Of litCompiled) with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"literal-only retained carrier: {repr e}"
  let some litCallable := litData.callables[0]? |
    throw <| IO.userError "literal-only: missing retained callable"
  let some litBlock := litCallable.blocks[0]? |
    throw <| IO.userError "literal-only: missing retained block"
  let some litInstr := litBlock.instructions[0]? |
    throw <| IO.userError "literal-only: missing retained literal instruction"
  match litInstr.op with
  | ProofForgeV2.Semantic.WireV1.SemanticOpV1.literal tid bytes =>
      expect (tid == 0 && bytes == ByteArray.mk #[(0x08 : UInt8), 0x07, 0x06,
          0x05, 0x04, 0x03, 0x02, 0x01])
        "literal-only: exact retained UInt64 little-endian bytes"
  | _ => throw <| IO.userError "literal-only: expected retained Op.Literal"

  -- Unit bare return: multi-pass CheckV1 ok (Unit empty return); residual
  -- Typed.checkV1 still rejects Stmt.Return. S3 fails at Normalize first with
  -- a stable S1 message so product never surfaces residual-only Stmt.Return.
  let bareRet ← validated moduleQ identity demo #[
    .entry (mkEntry runN (block #[.return_ none]) #[] .unit)]
  let bareMp := checkProgramTypedResultV1 bareRet
  expect (bareMp.ok && bareMp.analysisComplete)
    "unit-bare-return multipass CheckV1 must be ok"
  expectRender "unit-bare-return-normalize-gate"
    "PF-SRC-INVALID: S1 normalizer does not support bare return"
    (Compiler.compileValidatedSourceV1 bareRet)

  -- schedule-only: multipass CheckV1 ok; residual alpha rejects Stmt.Schedule.
  -- Product compile fails at Normalize S1 (sibling of call gate).
  let sched ← validated moduleQ identity demo #[
    .entry (mkEntry runN (block #[
      .schedule { callee := peer, args := #[] },
      .return_ (some (var seed))]) #[param seed])]
  let schedMp := checkProgramTypedResultV1 sched
  expect (schedMp.ok && schedMp.analysisComplete)
    "schedule-only multipass CheckV1 must be ok"
  expectRender "schedule-only-normalize-gate"
    "PF-SRC-INVALID: S1 normalizer does not support schedule"
    (Compiler.compileValidatedSourceV1 sched)

private unsafe def runSource
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1 counterSource
      "<checkv1-product-counter>" moduleName none with
  | .ok source =>
      let _ ← expectOk "counter-source" (Compiler.compileValidatedSourceV1 source)
      expectNormalizeOk "counter-source-normalize" source
  | .error error => throw <| IO.userError s!"counter-source load: {error.render}"

  match ← session.selectProgramV1 accumulatorSource
      "<checkv1-product-accumulator>" moduleName none with
  | .ok source =>
      let _ ← expectOk "accumulator-source" (Compiler.compileValidatedSourceV1 source)
      expectNormalizeOk "accumulator-source-normalize" source
  | .error error => throw <| IO.userError s!"accumulator-source load: {error.render}"

  match ← session.selectProgramV1 privateStateUnusedSource
      "<checkv1-product-private>" moduleName none with
  | .ok source =>
      let _ ← expectOk "private-unused-source-checkV1" (Typed.checkV1 source)
      expectRender "private-unused-source"
        "PF-SRC-INVALID: S1 normalizer supports only public state, got non-public 'secret'"
        (Compiler.compileValidatedSourceV1 source)
  | .error error => throw <| IO.userError s!"private-unused-source load: {error.render}"

  let typeOnlySource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TypeOnlyGate where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return true\n"
  match ← session.selectProgramV1 typeOnlySource
      "<checkv1-product-type>" moduleName none with
  | .ok source =>
      expectRender "type-only-source"
        "PF-SRC-INVALID: type mismatch: expected UInt64, got Bool"
        (Compiler.compileValidatedSourceV1 source)
  | .error error => throw <| IO.userError s!"type-only-source load: {error.render}"

  let discSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscOnlyGate where\n" ++
    "  entry run(private x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  match ← session.selectProgramV1 discSource
      "<checkv1-product-disc>" moduleName none with
  | .ok source =>
      expectRenderContains "disclosure-source" "PF-VIS-001:"
        "disclosure violation: cannot flow 'private' into 'public'"
        (Compiler.compileValidatedSourceV1 source)
  | .error error => throw <| IO.userError s!"disclosure-source load: {error.render}"

  -- D2-04b implicit PC: private if then public return → PF-VIS-001 via checkV1/compile.
  let discImplicitSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscImplicitGate where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    if flag then\n" ++
    "      return 1\n" ++
    "    else\n" ++
    "      return 0\n"
  match ← session.selectProgramV1 discImplicitSource
      "<checkv1-product-disc-implicit>" moduleName none with
  | .ok source =>
      expectRenderContains "disclosure-implicit-source" "PF-VIS-001:"
        "disclosure violation: cannot flow 'private' into 'public'"
        (Compiler.compileValidatedSourceV1 source)
      expectRenderContains "disclosure-implicit-checkV1" "PF-VIS-001:"
        "disclosure violation: cannot flow 'private' into 'public'"
        (Typed.checkV1 source)
  | .error error => throw <| IO.userError s!"disclosure-implicit-source load: {error.render}"

  -- D2-04b assert condition is a public sink (assert ⇒ failure.revert).
  let discAssertSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program DiscAssertGate where\n" ++
    "  entry run(private flag : Bool) : UInt64 do\n" ++
    "    assert flag\n" ++
    "    return 0\n"
  match ← session.selectProgramV1 discAssertSource
      "<checkv1-product-disc-assert>" moduleName none with
  | .ok source =>
      expectRenderContains "disclosure-assert-source" "PF-VIS-001:"
        "disclosure violation: cannot flow 'private' into 'public'"
        (Compiler.compileValidatedSourceV1 source)
      expectRenderContains "disclosure-assert-checkV1" "PF-VIS-001:"
        "disclosure violation: cannot flow 'private' into 'public'"
        (Typed.checkV1 source)
  | .error error => throw <| IO.userError s!"disclosure-assert-source load: {error.render}"

  -- Bound-only source path: same triple-nested product overflow as AST case.
  let boundSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoundOnlyGate where\n" ++
    "  state total : UInt64\n" ++
    "  state start : UInt64\n" ++
    "  state stop : UInt64\n" ++
    "  entry run() do\n" ++
    "    for i in start ..< stop bounded 4096 do\n" ++
    "      for j in start ..< stop bounded 4096 do\n" ++
    "        for k in start ..< stop bounded 4096 do\n" ++
    "          total := i\n"
  match ← session.selectProgramV1 boundSource
      "<checkv1-product-bound>" moduleName none with
  | .ok source =>
      expectRender "bound-loop-product-source"
        "PF-BOUND-001: loop bound product overflows UInt32 in entry 'run' (bound 4096)"
        (Compiler.compileValidatedSourceV1 source)
      expectRender "bound-loop-product-source-checkV1"
        "PF-BOUND-001: loop bound product overflows UInt32 in entry 'run' (bound 4096)"
        (Typed.checkV1 source)
  | .error error => throw <| IO.userError s!"bound-source load: {error.render}"

  -- Literal-only source succeeds through CheckV1 → Normalize → retained
  -- SemanticProgramV1 → residual alpha dual-carrier mint.
  let literalSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LiteralOnlyGate where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 18446744073709551615\n"
  match ← session.selectProgramV1 literalSource
      "<checkv1-product-literal>" moduleName none with
  | .ok source =>
      let _ ← expectOk "literal-source-checkV1" (Typed.checkV1 source)
      let _ ← expectOk "literal-source-compile"
        (Compiler.compileValidatedSourceV1 source)
      expectNormalizeOk "literal-source-normalize" source
  | .error error => throw <| IO.userError s!"literal-source load: {error.render}"

unsafe def run : IO Unit := do
  runAst
  let session ← Tests.Language.ParserSession.shared
  runSource session

end Tests.Compiler.CheckV1ProductGate
