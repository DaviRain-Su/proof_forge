import ProofForgeV2.Language.ProgramPayload
import ProofForgeV2.Language.ProgramExport
import Lean
open Lean Elab.Command ProofForgeV2.Language.ProgramPayload

private def expectedShort : Name → Except String String
  | .str _ raw => pure (Name.str .anonymous raw).toString
  | _ => throw "declaration final component is not Name.str"

structure ShortNameRow where
  declaration : String
  payloadName : String
  deriving BEq, Repr, Inhabited

private def exactShortErr :=
  "PF-EXPORT-001: exported program short name does not match declaration"

private def assertShort (decl : Name) (p : ProofForgeV2.Source.Program) : CommandElabM Unit := do
  unless decl.toString == p.qualifiedName do
    throwError s!"PA84 qname drift {decl} vs {p.qualifiedName}"
  match expectedShort decl with
  | .error e => throwError e
  | .ok exp => unless p.name == exp do
      throwError s!"short-name drift decl={decl} exp={exp} got={p.name}"

private def defStr (id : Ident) (s : String) : CommandElabM Unit := do
  elabCommand (← `(def $(mkIdent id.getId) : String := $(Syntax.mkStrLit s)))

elab "#snapshot_short_table " id:ident : command => do
  match programPayloads (← getEnv) with
  | .error m => throwError m
  | .ok rows => do
      for (ex, p) in rows do assertShort ex.declaration p
      let elems ← rows.mapM fun (ex, p) =>
        `(ShortNameRow.mk $(Syntax.mkStrLit ex.declaration.toString) $(Syntax.mkStrLit p.name))
      elabCommand (← `(def $(mkIdent id.getId) : Array ShortNameRow := #[$elems,*]))

elab "#snapshot_short_payload " n:ident "as" id:ident : command => do
  let name ← resolveGlobalConstNoOverload n
  match programPayload (← getEnv) name with
  | .error m => throwError m
  | .ok p => do
      assertShort name p
      elabCommand (← `(def $(mkIdent id.getId) : ShortNameRow :=
        ShortNameRow.mk $(Syntax.mkStrLit name.toString) $(Syntax.mkStrLit p.name)))

/-- One isolated liar: evaluate single+table APIs together so RED is non-vacuous for both. -/
elab "#expect_short_error_apis " n:ident "as" sId:ident "and" tId:ident : command => do
  let env ← getEnv
  let name ← resolveGlobalConstNoOverload n
  let mut problems : Array String := #[]
  let mut singleMsg : Option String := none
  let mut tableMsg : Option String := none
  match programPayload env name with
  | .ok _ => problems := problems.push "expected short-name failure from programPayload"
  | .error m =>
      if m == exactShortErr then singleMsg := some m
      else problems := problems.push s!"single: expected `{exactShortErr}`, got `{m}`"
  match programPayloads env with
  | .ok _ => problems := problems.push "expected short-name failure from programPayloads"
  | .error m =>
      if m == exactShortErr then tableMsg := some m
      else problems := problems.push s!"table: expected `{exactShortErr}`, got `{m}`"
  if problems.size > 0 then
    throwError (String.intercalate "\n" problems.toList)
  match singleMsg, tableMsg with
  | some s, some t => defStr sId s; defStr tId t
  | _, _ => throwError "internal: short-error apis missing messages"

elab "#expect_payloads_prefix" pref:str "as" id:ident : command => do
  match programPayloads (← getEnv) with
  | .ok _ => throwError "expected programPayloads failure"
  | .error m =>
      unless m.startsWith pref.getString do
        throwError s!"expected prefix `{pref.getString}`, got `{m}`"
      defStr id m
