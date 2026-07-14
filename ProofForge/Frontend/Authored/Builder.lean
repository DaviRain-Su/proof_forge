import Init.Control.State
import ProofForge.Frontend.Authored.Syntax

/-! # Direct Authored builder

The compiler-owned builder used by `contract_source`. It constructs only the
target-neutral `AuthoredContract`; checked Canonical Core is produced by the
separate canonicalizer. This module must not depend on the retired
`Contract.Builder`/`IR.Contract` authoring route.
-/

namespace ProofForge.Frontend.Authored.Builder

open ProofForge.Frontend.Authored

structure ModuleBuilder where
  name : String
  structs : Array AuthoredStructDecl := #[]
  state : Array AuthoredStateDecl := #[]
  events : Array AuthoredEventDecl := #[]
  errors : Array AuthoredErrorDecl := #[]
  entrypoints : Array AuthoredEntrypoint := #[]
  constructorParams : Array AuthoredConstructorParam := #[]
  constructorBindings : Array AuthoredConstructorBinding := #[]
  intents : Array AuthoredIntent := #[]
  quintInvariants : Array AuthoredVerificationAnnotation := #[]
  quintLiveness : Array AuthoredVerificationAnnotation := #[]
  leanInvariants : Array AuthoredVerificationAnnotation := #[]
  deriving Repr

structure EntryBuilder where
  body : Array AuthoredStmt := #[]
  intents : Array AuthoredIntent := #[]
  deriving Repr

abbrev ModuleM := StateM ModuleBuilder
abbrev EntryM := StateM EntryBuilder

def ModuleBuilder.toContract (builder : ModuleBuilder) : AuthoredContract := {
  name := builder.name
  structs := builder.structs
  state := builder.state
  events := builder.events
  errors := builder.errors
  entrypoints := builder.entrypoints
  constructorParams := builder.constructorParams
  constructorBindings := builder.constructorBindings
  intents := builder.intents
  quintInvariants := builder.quintInvariants
  quintLiveness := builder.quintLiveness
  leanInvariants := builder.leanInvariants
}

def build (name : String) (body : ModuleM Unit) : AuthoredContract :=
  let (_, builder) := body.run { name }
  builder.toContract

def struct (declaration : AuthoredStructDecl) : ModuleM Unit :=
  modify fun builder => { builder with structs := builder.structs.push declaration }

def state (name : String) (kind : AuthoredStateKind) : ModuleM Unit :=
  modify fun builder => { builder with state := builder.state.push { name, kind } }

def scalarState (name : String) (type : AuthoredType) : ModuleM Unit :=
  state name (.scalar type)

def mapState (name : String) (keyType valueType : AuthoredType)
    (capacity : Option Nat := none) : ModuleM Unit :=
  state name (.map keyType valueType capacity)

def event (declaration : AuthoredEventDecl) : ModuleM Unit :=
  modify fun builder => { builder with events := builder.events.push declaration }

def error (declaration : AuthoredErrorDecl) : ModuleM Unit :=
  modify fun builder => { builder with errors := builder.errors.push declaration }

def intent (authoredIntent : AuthoredIntent) : ModuleM Unit :=
  modify fun builder => { builder with intents := builder.intents.push authoredIntent }

def quintInvariant (name body : String) : ModuleM Unit :=
  modify fun builder => { builder with
    quintInvariants := builder.quintInvariants.push { name, body } }

def quintLiveness (name body : String) : ModuleM Unit :=
  modify fun builder => { builder with
    quintLiveness := builder.quintLiveness.push { name, body } }

def leanInvariant (name body : String) : ModuleM Unit :=
  modify fun builder => { builder with
    leanInvariants := builder.leanInvariants.push { name, body } }

def pushStmt (statement : AuthoredStmt) : EntryM Unit :=
  modify fun builder => { builder with body := builder.body.push statement }

def bind (name : String) (type : AuthoredType) (value : AuthoredExpr) : EntryM Unit :=
  pushStmt (.bind name type value)

def assign (target : AuthoredLValue) (value : AuthoredExpr) : EntryM Unit :=
  pushStmt (.assign target value)

def stateWrite (name : String) (value : AuthoredExpr) : EntryM Unit :=
  pushStmt (.stateWrite name value)

def emit (name : String) (args : Array AuthoredExpr) : EntryM Unit :=
  pushStmt (.emit name args)

def assert (condition : AuthoredExpr) (message : String) : EntryM Unit :=
  pushStmt (.assert condition message)

def ret (value : AuthoredExpr) : EntryM Unit :=
  pushStmt (.returnExpr value)

def retUnit : EntryM Unit :=
  pushStmt .returnUnit

def entryFull (name : String) (params : Array AuthoredParam) (retType : AuthoredType)
    (body : EntryM Unit) (mutability : AuthoredMutability := .call)
    (kind : AuthoredEntrypointKind := .function) (selector? : Option String := none)
    (returnAbiWord? : Option String := none) : ModuleM Unit := do
  let (_, entryBuilder) := body.run {}
  let entrypoint : AuthoredEntrypoint := {
    name
    kind
    mutability
    selector?
    params
    retType
    returnAbiWord?
    body := entryBuilder.body
  }
  modify fun builder => { builder with
    entrypoints := builder.entrypoints.push entrypoint
    intents := builder.intents ++ entryBuilder.intents }

def entry (name : String) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name #[] .unit body

def entryReturns (name : String) (retType : AuthoredType) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name #[] retType body

def queryReturns (name : String) (retType : AuthoredType) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name #[] retType body .view

end ProofForge.Frontend.Authored.Builder
