import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramCodecV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstProgramValidateV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace Tests.Language.SourceAstProgramValidateV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramCodecV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstProgramValidateV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def expectOk (label : String) (r : Except String Unit) : IO Unit :=
  match r with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def expectErr (label want : String) (r : Except String Unit) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{label}: got {e}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly ok"

private def name (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def qn (ps : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 ps)

private def blk : BlockV1 := { statements := #[.return_ none] }
private def litT : ExprV1 := .literal (.bool true)
private def p (n : SourceNameComponentV1) : ParamV1 :=
  { visibility := .public_, name := n, type_ := .bool }
private def st (n : SourceNameComponentV1) : StateDeclV1 :=
  { visibility := .public_, name := n, type_ := .bool }
private def ent (n : SourceNameComponentV1) (ps : Array ParamV1 := #[]) : EntryDeclV1 :=
  { name := n, params := ps, result := .unit, body := blk }
private def vw (n : SourceNameComponentV1) (ps : Array ParamV1 := #[]) : ViewDeclV1 :=
  { name := n, params := ps, result := .unit, body := blk }
private def fnD (n : SourceNameComponentV1) (ps : Array ParamV1 := #[]) : FnDeclV1 :=
  { name := n, params := ps, result := .unit, body := blk }
private def initD (ps : Array ParamV1 := #[]) : InitDeclV1 := { params := ps, body := blk }
private def inv (n : SourceNameComponentV1) : InvariantDeclV1 :=
  { name := n, predicate := litT }
private def ev (n : SourceNameComponentV1) (ps : Array ParamV1 := #[]) : EventDeclV1 :=
  { name := n, params := ps }
private def er (n : SourceNameComponentV1) (ps : Array ParamV1 := #[]) : ErrorDeclV1 :=
  { name := n, params := ps }
private def su (n : SourceNameComponentV1) (fs : Array FieldDeclV1) : StructDeclV1 :=
  { name := n, fields := fs }
private def enu (n : SourceNameComponentV1) (vs : Array EnumVariantV1) : EnumDeclV1 :=
  { name := n, variants := vs }
private def co (n : SourceNameComponentV1) : ConstDeclV1 :=
  { name := n, type_ := .bool, value := litT }
private def fd (n : SourceNameComponentV1) : FieldDeclV1 := { name := n, type_ := .bool }
private def vr (n : SourceNameComponentV1) : EnumVariantV1 := { name := n, payloadTypes := #[] }
private def prog (demo : SourceNameComponentV1) (items : Array ProgramItemV1) : ProgramV1 :=
  { name := demo, items := items }

/-- D1-PA-105: declaration-set validator matrix (not alpha bucket order). -/
def run : IO Unit := do
  let demo ← name "Demo"; let a ← name "a"
  let runN ← name "run"; let get ← name "get"; let h ← name "h"
  let invN ← name "inv"; let x ← name "x"; let y ← name "y"
  let e1 ← name "E1"; let r1 ← name "R1"; let s1 ← name "S1"
  let u1 ← name "U1"; let c1 ← name "C1"
  let th ← qn #["T", "thm"]
  let extId ← qn #["ext", "id"]
  let dig00 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let dig11 := "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  let ext1 : ExtensionReqV1 := { id := extId, version := "1.0.0", digest := dig00 }
  let ext2 : ExtensionReqV1 := { id := extId, version := "2.0.0", digest := dig11 }
  let pr : ProofDeclV1 := { invariant := invN, kind := .holds, theorem_ := th }
  let prPreserving : ProofDeclV1 := { pr with kind := .preserving }
  let prA : ProofDeclV1 := { invariant := a, kind := .holds, theorem_ := th }
  -- positives
  expectOk "pos_all_unique" (validateProgramDeclSetV1 (prog demo #[
    .state (st a), .struct (su s1 #[fd x]), .enum (enu u1 #[vr y]), .const (co c1),
    .event (ev e1), .error (er r1), .init (initD #[p x]), .entry (ent runN),
    .view (vw get), .fn (fnD h), .invariant (inv invN),
    .extensionReq ext1, .proof pr]))
  expectOk "pos_proof_fwd" (validateProgramDeclSetV1 (prog demo #[
    .proof pr, .invariant (inv invN), .entry (ent runN)]))
  expectOk "pos_proof_dual_kind" (validateProgramDeclSetV1 (prog demo #[
    .invariant (inv invN), .proof pr, .proof prPreserving, .entry (ent runN)]))
  expectOk "pos_view_only" (validateProgramDeclSetV1 (prog demo #[.view (vw get)]))
  -- 23 per-slot negatives
  expectErr "n_multi_init" "program must declare at most one init"
    (validateProgramDeclSetV1 (prog demo #[.init (initD #[]), .init (initD #[]), .entry (ent runN)]))
  expectErr "n_zero_ev" "program must declare at least one entry or view"
    (validateProgramDeclSetV1 (prog demo #[.state (st a)]))
  expectErr "n_dup_state" "program contains duplicate state declarations"
    (validateProgramDeclSetV1 (prog demo #[.state (st a), .state (st a), .entry (ent runN)]))
  expectErr "n_dup_ev" "program contains duplicate entry/view declarations"
    (validateProgramDeclSetV1 (prog demo #[.entry (ent a), .view (vw a)]))
  expectErr "n_dup_event" "program contains duplicate event declarations"
    (validateProgramDeclSetV1 (prog demo #[.event (ev e1), .event (ev e1), .entry (ent runN)]))
  expectErr "n_dup_error" "program contains duplicate error declarations"
    (validateProgramDeclSetV1 (prog demo #[.error (er r1), .error (er r1), .entry (ent runN)]))
  expectErr "n_dup_struct" "program contains duplicate struct declarations"
    (validateProgramDeclSetV1 (prog demo #[.struct (su s1 #[fd x]), .struct (su s1 #[fd y]),
      .entry (ent runN)]))
  expectErr "n_dup_enum" "program contains duplicate enum declarations"
    (validateProgramDeclSetV1 (prog demo #[.enum (enu u1 #[vr x]), .enum (enu u1 #[vr y]),
      .entry (ent runN)]))
  expectErr "n_dup_const" "program contains duplicate const declarations"
    (validateProgramDeclSetV1 (prog demo #[.const (co c1), .const (co c1), .entry (ent runN)]))
  expectErr "n_dup_fn" "program contains duplicate fn declarations"
    (validateProgramDeclSetV1 (prog demo #[.fn (fnD h), .fn (fnD h), .entry (ent runN)]))
  expectErr "n_dup_callable" "program contains duplicate callable declarations"
    (validateProgramDeclSetV1 (prog demo #[.entry (ent runN), .fn (fnD runN)]))
  expectErr "n_dup_inv" "program contains duplicate invariant declarations"
    (validateProgramDeclSetV1 (prog demo #[.invariant (inv invN), .invariant (inv invN),
      .entry (ent runN)]))
  expectErr "n_dup_ext" "program contains duplicate extension requirements"
    (validateProgramDeclSetV1 (prog demo #[.extensionReq ext1, .extensionReq ext2, .entry (ent runN)]))
  expectErr "n_dup_proof" "program contains duplicate proof references"
    (validateProgramDeclSetV1 (prog demo #[.invariant (inv invN), .proof pr, .proof pr,
      .entry (ent runN)]))
  expectErr "n_unknown_proof" "proof reference names unknown invariant 'a'"
    (validateProgramDeclSetV1 (prog demo #[.proof prA, .entry (ent runN)]))
  expectErr "n_init_params" "initializer contains duplicate parameters"
    (validateProgramDeclSetV1 (prog demo #[.init (initD #[p x, p x]), .entry (ent runN)]))
  expectErr "n_struct_fields" "struct 'S1' contains duplicate fields"
    (validateProgramDeclSetV1 (prog demo #[.struct (su s1 #[fd x, fd x]), .entry (ent runN)]))
  expectErr "n_enum_vars" "enum 'U1' contains duplicate variants"
    (validateProgramDeclSetV1 (prog demo #[.enum (enu u1 #[vr x, vr x]), .entry (ent runN)]))
  expectErr "n_event_params" "event 'E1' contains duplicate parameters"
    (validateProgramDeclSetV1 (prog demo #[.event (ev e1 #[p x, p x]), .entry (ent runN)]))
  expectErr "n_error_params" "error 'R1' contains duplicate parameters"
    (validateProgramDeclSetV1 (prog demo #[.error (er r1 #[p x, p x]), .entry (ent runN)]))
  expectErr "n_entry_params" "entry 'run' contains duplicate parameters"
    (validateProgramDeclSetV1 (prog demo #[.entry (ent runN #[p x, p x])]))
  expectErr "n_view_params" "view 'get' contains duplicate parameters"
    (validateProgramDeclSetV1 (prog demo #[.view (vw get #[p x, p x])]))
  expectErr "n_fn_params" "fn 'h' contains duplicate parameters"
    (validateProgramDeclSetV1 (prog demo #[.fn (fnD h #[p x, p x]), .entry (ent runN)]))
  -- 7 cross-rule priorities
  expectErr "p_init_before_zero" "program must declare at most one init"
    (validateProgramDeclSetV1 (prog demo #[.init (initD #[]), .init (initD #[])]))
  expectErr "p_zero_before_state" "program must declare at least one entry or view"
    (validateProgramDeclSetV1 (prog demo #[.state (st a), .state (st a)]))
  expectErr "p_state_before_ev" "program contains duplicate state declarations"
    (validateProgramDeclSetV1 (prog demo #[.state (st a), .state (st a), .entry (ent a), .view (vw a)]))
  expectErr "p_event_before_struct" "program contains duplicate event declarations"
    (validateProgramDeclSetV1 (prog demo #[.event (ev e1), .event (ev e1),
      .struct (su s1 #[fd x]), .struct (su s1 #[fd y]), .entry (ent runN)]))
  expectErr "p_fn_before_callable" "program contains duplicate fn declarations"
    (validateProgramDeclSetV1 (prog demo #[.fn (fnD runN), .fn (fnD runN), .entry (ent runN)]))
  expectErr "p_state_before_unknown" "program contains duplicate state declarations"
    (validateProgramDeclSetV1 (prog demo #[.state (st a), .state (st a), .proof prA, .entry (ent runN)]))
  expectErr "p_dup_proof_before_unknown" "program contains duplicate proof references"
    (validateProgramDeclSetV1 (prog demo #[.proof prA, .proof prA, .entry (ent runN)]))
  -- encoder/validator neutrality: dup state still encodes
  let badState := prog demo #[.state (st a), .state (st a), .entry (ent runN)]
  expectErr "neut_validate" "program contains duplicate state declarations"
    (validateProgramDeclSetV1 badState)
  match encodeProgramV1 badState with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"neut_encode: {e}"

end Tests.Language.SourceAstProgramValidateV1
