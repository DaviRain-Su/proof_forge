import ProofForgeV2.Core.Typed
import Lean.Elab.Command
import Lean.Util.FoldConsts

namespace Tests.Compiler.TypedNameIndex

open ProofForgeV2
open Lean
open Lean.Elab.Command

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectInvalidMessage (result : CompileResult α) (expected : String) : IO Unit :=
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"expected invalid-program message '{expected}', got '{actual}'"
  | .error error =>
      throw <| IO.userError s!"expected invalid-program message '{expected}', got {error.render}"
  | .ok _ => throw <| IO.userError s!"expected invalid-program message '{expected}', got success"

private def sourceParam (name : String) : Source.Param := {
  name
  type := .u64
}

private def sourceState (name : String) : Source.StateDecl := {
  name
  type := .u64
}

private def sourceEntry (name : String) (params : Array Source.Param)
    (body : Array Source.Statement) (mode : Source.EntryMode := .mutate) : Source.Entry := {
  name
  params
  result := .u64
  mode
  body
}

private def sourceProgram (name : String) (state : Array Source.StateDecl)
    (entries : Array Source.Entry) (initializer : Option Source.Initializer := none) :
    Source.Program := {
  qualifiedName := s!"Tests.TypedNameIndex.{name}"
  name
  state
  initializer
  entries
}

private def wideCount : Nat := 2048

private def wideStates : Array Source.StateDecl :=
  (Array.range wideCount).map fun index => sourceState s!"state{index}"

private def wideParams : Array Source.Param :=
  (Array.range wideCount).map fun index => sourceParam s!"param{index}"

private def expectWideLateLookup : IO Unit := do
  let last := wideCount - 1
  let lastState := s!"state{last}"
  let lastParam := s!"param{last}"
  let source := sourceProgram "WideLateLookup" wideStates #[
    sourceEntry "before" #[] #[.returnValue (.literal 0)],
    sourceEntry "run" wideParams #[
      .assign lastState (.variable lastParam),
      .returnValue (.state lastState)
    ],
    sourceEntry "after" #[] #[.returnValue (.literal 0)]
  ] (some {
    params := wideParams
    body := #[.assign lastState (.variable lastParam)]
  })
  let checked ← match Typed.check source with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError s!"wide late lookup failed: {error.render}"
  expect (checked.state.map (·.id.value) == Array.range wideCount)
    "wide state IDs must remain in declaration order"
  expect (checked.state.map (·.name) == wideStates.map (·.name))
    "wide state output must remain in declaration order"
  match checked.initializer with
  | none => throw <| IO.userError "wide initializer was lost"
  | some initializer =>
      expect (initializer.params.map (·.id.value) == Array.range wideCount)
        "wide initializer parameter IDs must remain in declaration order"
      expect (initializer.params.map (·.name) == wideParams.map (·.name))
        "wide initializer parameters must remain in declaration order"
      match initializer.body with
      | #[.assign target (.ref (.param rhs _))] =>
          expect (target.value == last && rhs.value == last)
            "wide initializer must reuse state lookup and resolve its final parameter"
      | body => throw <| IO.userError s!"unexpected wide initializer body: {repr body}"
  expect (checked.entries.map (·.name) == #["before", "run", "after"])
    "entry output must remain in declaration order"
  match checked.entries[1]? with
  | none => throw <| IO.userError "wide entry was lost"
  | some entry =>
      expect (entry.params.map (·.id.value) == Array.range wideCount)
        "wide parameter IDs must remain in declaration order"
      expect (entry.params.map (·.name) == wideParams.map (·.name))
        "wide parameter output must remain in declaration order"
      match entry.body with
      | #[.assign target (.ref (.param rhs _)), .returnValue (.ref (.state returned _))] =>
          expect (target.value == last && rhs.value == last && returned.value == last)
            "late references must resolve to the final declaration-order IDs"
      | body => throw <| IO.userError s!"unexpected wide typed body: {repr body}"

private def expectDuplicateAndErrorPriority : IO Unit := do
  let emptyIdentity := {
    sourceProgram "Ignored" #[sourceState "x", sourceState "x"] #[
      sourceEntry "run" #[] #[.returnValue (.literal 0)]
    ] with
    qualifiedName := ""
    name := ""
  }
  expectInvalidMessage (Typed.check emptyIdentity) "program qualified identity cannot be empty"

  let emptyName := {
    sourceProgram "EmptyName" #[sourceState "x", sourceState "x"] #[
      sourceEntry "run" #[] #[.returnValue (.literal 0)]
    ] with
    name := ""
  }
  expectInvalidMessage (Typed.check emptyName) "program name cannot be empty"

  let duplicateStates := sourceProgram "DuplicateStatePriority"
    #[sourceState "a", sourceState "b", sourceState "b", sourceState "a"] #[
      sourceEntry "run" #[] #[.returnValue (.variable "unknown")],
      sourceEntry "run" #[] #[.returnValue (.literal 0)]
    ]
  expectInvalidMessage (Typed.check duplicateStates)
    "duplicate state declaration 'b' in program 'Tests.TypedNameIndex.DuplicateStatePriority'"

  let duplicateEntries := sourceProgram "DuplicateEntryPriority" #[] #[
      sourceEntry "a" #[] #[.returnValue (.literal 0)],
      sourceEntry "b" #[] #[.returnValue (.literal 0)],
      sourceEntry "b" #[] #[.returnValue (.literal 0)],
      sourceEntry "a" #[] #[.returnValue (.literal 0)]
    ] (some {
      params := #[sourceParam "i", sourceParam "j", sourceParam "j", sourceParam "i"]
      body := #[]
    })
  expectInvalidMessage (Typed.check duplicateEntries)
    "duplicate entry declaration 'b' in program 'Tests.TypedNameIndex.DuplicateEntryPriority'"

  let initializerFirst := sourceProgram "InitializerPriority" #[] #[
      sourceEntry "run" #[sourceParam "e", sourceParam "f", sourceParam "f", sourceParam "e"]
        #[.returnValue (.variable "unknown")]
    ] (some {
      params := #[sourceParam "a", sourceParam "b", sourceParam "b", sourceParam "a"]
      body := #[.returnValue (.literal 0)]
    })
  expectInvalidMessage (Typed.check initializerFirst)
    "duplicate parameter 'b' in initializer"

  let entryParameterDuplicate := sourceProgram "EntryParameterDuplicate" #[] #[
    sourceEntry "run"
      #[sourceParam "a", sourceParam "b", sourceParam "b", sourceParam "a"]
      #[.returnValue (.variable "missingBodyValue")]
  ]
  expectInvalidMessage (Typed.check entryParameterDuplicate)
    "duplicate parameter 'b' in entry 'run'"

  let zeroEntries := sourceProgram "ZeroEntries" #[] #[] (some {
    params := #[sourceParam "a", sourceParam "a"]
    body := #[]
  })
  expectInvalidMessage (Typed.check zeroEntries)
    "program 'Tests.TypedNameIndex.ZeroEntries' must declare at least one entry or view"

  let initializerBodyFirst := sourceProgram "InitializerBodyPriority" #[] #[
      sourceEntry "run" #[sourceParam "e", sourceParam "e"]
        #[.returnValue (.variable "unknown")]
    ] (some {
      params := #[]
      body := #[.returnValue (.literal 0)]
    })
  expectInvalidMessage (Typed.check initializerBodyFirst) "initializer cannot return a value"

  let earlierEntryBodyFirst := sourceProgram "EntryBodyPriority" #[] #[
    sourceEntry "first" #[] #[.returnValue (.variable "missingFirst")],
    sourceEntry "second" #[sourceParam "x", sourceParam "x"] #[.returnValue (.literal 0)]
  ]
  expectInvalidMessage (Typed.check earlierEntryBodyFirst) "unknown value 'missingFirst' in first"

  let assignmentTargetFirst := sourceProgram "AssignmentPriority" #[] #[
    sourceEntry "run" #[] #[
      .assign "missingTarget" (.variable "missingRhs"),
      .returnValue (.literal 0)
    ]
  ]
  expectInvalidMessage (Typed.check assignmentTargetFirst)
    "assignment target 'missingTarget' in run is not declared state"

  let viewAssignmentFirst := sourceProgram "ViewAssignmentPriority" #[] #[
    sourceEntry "read" #[] #[
      .assign "missingTarget" (.variable "missingRhs"),
      .returnValue (.literal 0)
    ] .view
  ]
  expectInvalidMessage (Typed.check viewAssignmentFirst)
    "view 'read' cannot write state 'missingTarget'"

  let additionLeftFirst := sourceProgram "AdditionPriority" #[] #[
    sourceEntry "run" #[] #[
      .returnValue (.checkedAdd (.variable "missingLhs") (.variable "missingRhs"))
    ]
  ]
  expectInvalidMessage (Typed.check additionLeftFirst)
    "unknown value 'missingLhs' in run"

private def expectLookupSemantics : IO Unit := do
  let shadowing := sourceProgram "Shadowing" #[sourceState "shared"] #[
    sourceEntry "run" #[sourceParam "shared"] #[
      .assign "shared" (.variable "shared"),
      .returnValue (.state "shared")
    ]
  ]
  let checked ← match Typed.check shadowing with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError s!"shadowing vector failed: {error.render}"
  match checked.entries[0]? with
  | some entry =>
      match entry.body with
      | #[.assign target (.ref (.param rhs _)), .returnValue (.ref (.state returned _))] =>
          expect (target.value == 0 && rhs.value == 0 && returned.value == 0)
            "variable lookup must prefer parameters while explicit state lookup remains available"
      | body => throw <| IO.userError s!"unexpected shadowing body: {repr body}"
  | none => throw <| IO.userError "shadowing entry was lost"

  let missingVariable := sourceProgram "WideMissingVariable" wideStates #[
    sourceEntry "run" wideParams #[.returnValue (.variable "missing")]
  ]
  expectInvalidMessage (Typed.check missingVariable) "unknown value 'missing' in run"

  let missingState := sourceProgram "WideMissingState" wideStates #[
    sourceEntry "run" wideParams #[.returnValue (.state "missing")]
  ]
  expectInvalidMessage (Typed.check missingState) "unknown state 'missing' in run"

  let unresolvedCallee := sourceProgram "UnresolvedCallee" #[] #[
    sourceEntry "run" #[] #[
      .synchronousCall "not-yet-resolved",
      .returnValue (.literal 0)
    ]
  ]
  match Typed.check unresolvedCallee with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"nonempty synchronous callee changed semantics: {error.render}"

def run : IO Unit := do
  expectWideLateLookup
  expectDuplicateAndErrorPriority
  expectLookupSemantics

private def forbiddenArraySearches : NameSet :=
  NameSet.ofList [
    ``Array.contains,
    ``Array.elem,
    ``Array.find?,
    ``Array.findM?,
    ``Array.findSome?,
    ``Array.findSomeM?,
    ``Array.findSome!,
    ``Array.findRev?,
    ``Array.findRevM?,
    ``Array.findSomeRev?,
    ``Array.findSomeRevM?,
    ``Array.findIdx?,
    ``Array.findIdxM?,
    ``Array.findIdx,
    ``Array.findFinIdx?
  ]

private def requiredIndexOperations : Array Name := #[
  ``Std.HashMap.getThenInsertIfNew?,
  ``Std.HashMap.get?,
  ``Std.HashSet.containsThenInsert
]

private def renderDependencyPath (path : Array Name) : String :=
  String.intercalate " -> " (path.toList.map Name.toString)

private partial def countConstantUses (needle : Name) : Expr → Nat
  | .const name _ => if name == needle then 1 else 0
  | .app function argument =>
      countConstantUses needle function + countConstantUses needle argument
  | .lam _ type body _ | .forallE _ type body _ =>
      countConstantUses needle type + countConstantUses needle body
  | .letE _ type value body _ =>
      countConstantUses needle type + countConstantUses needle value +
        countConstantUses needle body
  | .mdata _ body | .proj _ _ body => countConstantUses needle body
  | _ => 0

private structure DependencyAudit where
  visited : NameSet
  used : NameSet
  stateBuilderUses : Nat

private partial def visitCheckerDependency
    (env : Environment) (owner : ModuleIdx) (decl : Name) (path : Array Name) :
    StateT DependencyAudit (Except String) Unit := do
  if NameSet.contains (← get).visited decl then
    return
  modify fun audit => { audit with visited := NameSet.insert audit.visited decl }
  let some info := Environment.find? env decl
    | throw s!"missing declaration while auditing {Name.toString decl}"
  let some value := ConstantInfo.value? info (allowOpaque := true)
    | return
  modify fun audit => {
    audit with
    stateBuilderUses := audit.stateBuilderUses +
      countConstantUses ``ProofForgeV2.Typed.NameIndex.resolveState value
  }
  let dependencies := Expr.getUsedConstantsAsSet value
  for dependency in dependencies do
    modify fun audit => { audit with used := NameSet.insert audit.used dependency }
    if NameSet.contains forbiddenArraySearches dependency then
      throw s!"checker-owned Array search is reachable: {renderDependencyPath (path.push dependency)}"
    if Environment.getModuleIdxFor? env dependency == some owner then
      visitCheckerDependency env owner dependency (path.push dependency)

private def auditTypedCheck (env : Environment) : Except String Unit := do
  let root := ``ProofForgeV2.Typed.check
  let some owner := Environment.getModuleIdxFor? env root
    | throw s!"cannot determine module owner for {Name.toString root}"
  let some rootInfo := Environment.find? env root
    | throw s!"cannot find {Name.toString root}"
  let some rootValue := ConstantInfo.value? rootInfo (allowOpaque := true)
    | throw s!"cannot inspect {Name.toString root}"
  let directStateBuilderUses :=
    countConstantUses ``ProofForgeV2.Typed.NameIndex.resolveState rootValue
  unless directStateBuilderUses == 1 do
    throw s!"Typed.check must directly contain exactly one state index builder occurrence; found {directStateBuilderUses}"
  let (_, audit) ← (visitCheckerDependency env owner root #[root]).run {
    visited := {}
    used := {}
    stateBuilderUses := 0
  }
  for operation in requiredIndexOperations do
    unless NameSet.contains audit.used operation do
      throw s!"required name-index operation is not reachable: {Name.toString operation}"
  unless audit.stateBuilderUses == 1 do
    throw s!"state index builder must occur exactly once in the checker-owned dependency graph; found {audit.stateBuilderUses}"
  return ()

run_cmd do
  match auditTypedCheck (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

end Tests.Compiler.TypedNameIndex
