import Std.Data.HashSet
import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.AstProgramValidateV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

private def fail (detail : String) : Except String α := .error detail
private def multiInitErr := "program must declare at most one init"
private def zeroEVErr := "program must declare at least one entry or view"
private def dupStateErr := "program contains duplicate state declarations"
private def dupEVErr := "program contains duplicate entry/view declarations"
private def dupEventErr := "program contains duplicate event declarations"
private def dupErrorErr := "program contains duplicate error declarations"
private def dupStructErr := "program contains duplicate struct declarations"
private def dupEnumErr := "program contains duplicate enum declarations"
private def dupConstErr := "program contains duplicate const declarations"
private def dupFnErr := "program contains duplicate fn declarations"
private def dupCallableErr := "program contains duplicate callable declarations"
private def dupInvErr := "program contains duplicate invariant declarations"
private def dupExtErr := "program contains duplicate extension requirements"
private def dupProofErr := "program contains duplicate proof references"
private def initParamErr := "initializer contains duplicate parameters"
private def raw (n : SourceNameComponentV1) : String := n.raw
private def extKey (id : SourceQualifiedNameV1) : String :=
  String.intercalate "\u0000" ((NonEmptyArray.toArray id.components).map raw |>.toList)

private def checkDupKeys (keys : Array String) (err : String) : Except String Unit := do
  let mut seen : Std.HashSet String := Std.HashSet.emptyWithCapacity keys.size
  for k in keys do
    let (hit, seen') := seen.containsThenInsert k
    if hit then return ← fail err
    seen := seen'

private def checkParams (ps : Array ParamV1) (err : String) : Except String Unit :=
  checkDupKeys (ps.map (fun p => raw p.name)) err

private def checkItemNameDups (items : Array ProgramItemV1)
    (pick : ProgramItemV1 → Option String) (err : String) : Except String Unit := do
  let mut seen : Std.HashSet String := Std.HashSet.emptyWithCapacity items.size
  for it in items do
    match pick it with
    | none => pure ()
    | some k =>
        let (hit, seen') := seen.containsThenInsert k
        if hit then return ← fail err
        seen := seen'

private def pickState : ProgramItemV1 → Option String
  | .state s => some (raw s.name) | _ => none
private def pickEV : ProgramItemV1 → Option String
  | .entry e => some (raw e.name) | .view v => some (raw v.name) | _ => none
private def pickEvent : ProgramItemV1 → Option String
  | .event e => some (raw e.name) | _ => none
private def pickError : ProgramItemV1 → Option String
  | .error e => some (raw e.name) | _ => none
private def pickStruct : ProgramItemV1 → Option String
  | .struct s => some (raw s.name) | _ => none
private def pickEnum : ProgramItemV1 → Option String
  | .enum e => some (raw e.name) | _ => none
private def pickConst : ProgramItemV1 → Option String
  | .const c => some (raw c.name) | _ => none
private def pickFn : ProgramItemV1 → Option String
  | .fn f => some (raw f.name) | _ => none
private def pickCallable : ProgramItemV1 → Option String
  | .entry e => some (raw e.name) | .view v => some (raw v.name)
  | .fn f => some (raw f.name) | _ => none
private def pickInv : ProgramItemV1 → Option String
  | .invariant i => some (raw i.name) | _ => none
private def pickExt : ProgramItemV1 → Option String
  | .extensionReq e => some (extKey e.id) | _ => none

def validateProgramDeclSetV1 (program : ProgramV1) : Except String Unit := do
  let items := program.items
  let mut inits : Nat := 0
  for it in items do
    match it with
    | .init _ =>
        inits := inits + 1
        if inits ≥ 2 then return ← fail multiInitErr
    | _ => pure ()
  let mut hasEV : Bool := false
  for it in items do
    match it with
    | .entry _ | .view _ => hasEV := true
    | _ => pure ()
  unless hasEV do return ← fail zeroEVErr
  let _ ← checkItemNameDups items pickState dupStateErr
  let _ ← checkItemNameDups items pickEV dupEVErr
  let _ ← checkItemNameDups items pickEvent dupEventErr
  let _ ← checkItemNameDups items pickError dupErrorErr
  let _ ← checkItemNameDups items pickStruct dupStructErr
  let _ ← checkItemNameDups items pickEnum dupEnumErr
  let _ ← checkItemNameDups items pickConst dupConstErr
  let _ ← checkItemNameDups items pickFn dupFnErr
  let _ ← checkItemNameDups items pickCallable dupCallableErr
  let _ ← checkItemNameDups items pickInv dupInvErr
  let _ ← checkItemNameDups items pickExt dupExtErr
  let mut invSet : Std.HashSet String := Std.HashSet.emptyWithCapacity items.size
  for it in items do
    match it with
    | .invariant i => invSet := invSet.insert (raw i.name)
    | _ => pure ()
  let mut proofSet : Std.HashSet String := Std.HashSet.emptyWithCapacity items.size
  for it in items do
    match it with
    | .proof p =>
        let k := raw p.invariant
        let (hit, proofSet') := proofSet.containsThenInsert k
        if hit then return ← fail dupProofErr
        proofSet := proofSet'
    | _ => pure ()
  for it in items do
    match it with
    | .proof p =>
        let k := raw p.invariant
        unless invSet.contains k do
          return ← fail s!"proof reference names unknown invariant '{k}'"
    | _ => pure ()
  for it in items do
    match it with
    | .init d => checkParams d.params initParamErr
    | _ => pure ()
  for it in items do
    match it with
    | .struct s =>
        let _ ← checkDupKeys (s.fields.map (fun f => raw f.name))
          s!"struct '{raw s.name}' contains duplicate fields"
    | _ => pure ()
  for it in items do
    match it with
    | .enum e =>
        let _ ← checkDupKeys (e.variants.map (fun v => raw v.name))
          s!"enum '{raw e.name}' contains duplicate variants"
    | _ => pure ()
  for it in items do
    match it with
    | .event e => checkParams e.params s!"event '{raw e.name}' contains duplicate parameters"
    | _ => pure ()
  for it in items do
    match it with
    | .error e => checkParams e.params s!"error '{raw e.name}' contains duplicate parameters"
    | _ => pure ()
  for it in items do
    match it with
    | .entry e => checkParams e.params s!"entry '{raw e.name}' contains duplicate parameters"
    | .view v => checkParams v.params s!"view '{raw v.name}' contains duplicate parameters"
    | _ => pure ()
  for it in items do
    match it with
    | .fn f => checkParams f.params s!"fn '{raw f.name}' contains duplicate parameters"
    | _ => pure ()

end ProofForgeV2.Source.AstProgramValidateV1
