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

private def proofKey (proof : ProofDeclV1) : String :=
  raw proof.invariant ++ "\u0000" ++ toString proof.kind

/-- Kernel-reducible equality membership for source strings. Lean's fallback
    `BEq String` is implemented through the opaque `DecidableEq String`; source
    identity is already defined over exact UTF-8 bytes. -/
private def containsString (key : String) : List String → Bool
  | [] => false
  | candidate :: rest =>
      candidate.toUTF8 == key.toUTF8 || containsString key rest

private def checkDupKeyList (keys : List String) (err : String) : Except String Unit :=
  let rec visit (remaining seen : List String) : Except String Unit :=
    match remaining with
    | [] => .ok ()
    | key :: rest =>
        if containsString key seen then fail err else visit rest (key :: seen)
  visit keys []

private def checkParams (ps : Array ParamV1) (err : String) : Except String Unit :=
  checkDupKeyList (ps.toList.map (fun p => raw p.name)) err

private def checkItemNameDups (items : Array ProgramItemV1)
    (pick : ProgramItemV1 → Option String) (err : String) : Except String Unit :=
  checkDupKeyList (items.toList.filterMap pick) err

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

/-- Number of initializers in source order. -/
private def initCount : List ProgramItemV1 → Nat
  | [] => 0
  | .init _ :: rest => initCount rest + 1
  | _ :: rest => initCount rest

private def hasEntryOrView : List ProgramItemV1 → Bool
  | [] => false
  | .entry _ :: _ | .view _ :: _ => true
  | _ :: rest => hasEntryOrView rest

private def invariantNames : List ProgramItemV1 → List String
  | [] => []
  | .invariant invariant :: rest => raw invariant.name :: invariantNames rest
  | _ :: rest => invariantNames rest

private def proofKeys : List ProgramItemV1 → List String
  | [] => []
  | .proof proof :: rest => proofKey proof :: proofKeys rest
  | _ :: rest => proofKeys rest

private def checkProofReferences
    (invariants : List String) : List ProgramItemV1 → Except String Unit
  | [] => .ok ()
  | .proof proof :: rest =>
      let key := raw proof.invariant
      if containsString key invariants then
        checkProofReferences invariants rest
      else
        fail s!"proof reference names unknown invariant '{key}'"
  | _ :: rest => checkProofReferences invariants rest

private def checkItems
    (check : ProgramItemV1 → Except String Unit) :
    List ProgramItemV1 → Except String Unit
  | [] => .ok ()
  | item :: rest => do
      check item
      checkItems check rest

def validateProgramDeclSetV1 (program : ProgramV1) : Except String Unit := do
  let items := program.items
  let itemList := items.toList
  unless initCount itemList ≤ 1 do return ← fail multiInitErr
  unless hasEntryOrView itemList do return ← fail zeroEVErr
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
  let invSet := invariantNames itemList
  checkDupKeyList (proofKeys itemList) dupProofErr
  checkProofReferences invSet itemList
  checkItems (fun it => match it with
    | .init d => checkParams d.params initParamErr
    | _ => pure ()) itemList
  checkItems (fun it => match it with
    | .struct s =>
        checkDupKeyList (s.fields.toList.map (fun f => raw f.name))
          s!"struct '{raw s.name}' contains duplicate fields"
    | _ => pure ()) itemList
  checkItems (fun it => match it with
    | .enum e =>
        checkDupKeyList (e.variants.toList.map (fun v => raw v.name))
          s!"enum '{raw e.name}' contains duplicate variants"
    | _ => pure ()) itemList
  checkItems (fun it => match it with
    | .event e => checkParams e.params s!"event '{raw e.name}' contains duplicate parameters"
    | _ => pure ()) itemList
  checkItems (fun it => match it with
    | .error e => checkParams e.params s!"error '{raw e.name}' contains duplicate parameters"
    | _ => pure ()) itemList
  checkItems (fun it => match it with
    | .entry e => checkParams e.params s!"entry '{raw e.name}' contains duplicate parameters"
    | .view v => checkParams v.params s!"view '{raw v.name}' contains duplicate parameters"
    | _ => pure ()) itemList
  checkItems (fun it => match it with
    | .fn f => checkParams f.params s!"fn '{raw f.name}' contains duplicate parameters"
    | _ => pure ()) itemList

end ProofForgeV2.Source.AstProgramValidateV1
