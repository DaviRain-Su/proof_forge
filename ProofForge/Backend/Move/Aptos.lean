/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Aptos Move source generation POC (Workstream 8).

Generates a minimal Aptos Move package from the portable IR Counter shape:
- one `has key` resource for scalar U64 contract state
- `init(&signer)` to publish the resource
- `increment(&signer)` to mutate it
- `value(address): u64` to read it
- Move unit tests

This is intentionally a Counter-specific spike. Generalization to other IR
shapes is deferred until the Aptos resource model is proven end to end.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Capability

namespace ProofForge.Backend.Move.Aptos

open ProofForge.IR

structure EmitError where
  message : String
  deriving Repr, Inhabited

def err (msg : String) : Except EmitError α := .error { message := msg }

/-- Capabilities supported by the Aptos Counter spike. -/
def supportedCapabilities : ProofForge.Target.CapabilitySet := #[
  .storageScalar,
  .assertions
]

def checkCapabilities (mod : ProofForge.IR.Module) : Except EmitError Unit :=
  mod.capabilities.foldlM (fun _ c =>
    if supportedCapabilities.contains c then .ok ()
    else .error { message := "Aptos Counter spike: capability `" ++ c.id ++ "` is not supported" }) ()

/-- Validate that the module has exactly one scalar U64 state and return its id.
The POC only supports a single scalar U64 state; the state id becomes the Move
resource field name so the generated source faithfully reflects the IR. -/
def requireScalarState (mod : ProofForge.IR.Module) : Except EmitError String := do
  let state := mod.state
  if state.size != 1 then
    err "Aptos Counter spike: exactly one scalar state is required"
  else match state[0]? with
    | none => err "Aptos Counter spike: unreachable empty state"
    | some s =>
      if s.kind != .scalar then
        err ("Aptos Counter spike: state `" ++ s.id ++ "` must be scalar")
      else if s.type != .u64 then
        err ("Aptos Counter spike: state `" ++ s.id ++ "` must be u64")
      else pure s.id

/-- Render a scalar storage resource declaration. The field name is the IR state
id, so the generated Move reflects the portable IR rather than a hardcoded name. -/
def renderResource (mod : ProofForge.IR.Module) : Except EmitError String := do
  let field ← requireScalarState mod
  pure ("struct " ++ mod.name ++ " has key {\n        " ++ field ++ ": u64\n    }")

/-- Render an entrypoint body. The POC recognizes the Counter initialize/increment/get
pattern and lowers the scalar state field by its IR id. Unsupported shapes fail fast. -/
def renderEntrypoint (modName : String) (field : String) (ep : Entrypoint) : Except EmitError String :=
  match ep.name with
  | "initialize" =>
    if ep.returns != .unit then
      err "Aptos `initialize` must return unit"
    else
      pure ("public entry fun initialize(account: &signer) {\n" ++
            "        move_to(account, " ++ modName ++ " { " ++ field ++ ": 0 })\n" ++
            "    }")
  | "increment" =>
    if ep.returns != .unit then
      err "Aptos `increment` must return unit"
    else
      pure ("public entry fun increment(account: &signer) acquires " ++ modName ++ " {\n" ++
            "        let counter = borrow_global_mut<" ++ modName ++ ">(signer::address_of(account));\n" ++
            "        counter." ++ field ++ " = counter." ++ field ++ " + 1;\n" ++
            "    }")
  | "get" =>
    if ep.returns != .u64 then
      err "Aptos `get` must return u64"
    else
      pure ("#[view]\n" ++
            "    public fun value(addr: address): u64 acquires " ++ modName ++ " {\n" ++
            "        borrow_global<" ++ modName ++ ">(addr)." ++ field ++ "\n" ++
            "    }")
  | name => err ("Aptos Counter spike: unsupported entrypoint `" ++ name ++ "`")

/-- Render the module source for the Counter shape. -/
def renderSource (mod : ProofForge.IR.Module) : Except EmitError String := do
  let resource ← renderResource mod
  let field ← requireScalarState mod
  let eps ← mod.entrypoints.mapM (renderEntrypoint mod.name field)
  let epLines := String.intercalate "\n\n    " eps.toList
  pure ("module proof_forge::" ++ mod.name.toLower ++ " {\n" ++
        "    use std::signer;\n\n" ++
        "    " ++ resource ++ "\n\n    " ++ epLines ++ "\n}\n")

/-- Render Move unit tests for the Counter lifecycle. -/
def renderTests (modName : String) : String :=
  let n := modName.toLower
  "#[test_only]\n" ++
  "module proof_forge::" ++ n ++ "_tests {\n" ++
  "    use proof_forge::" ++ n ++ ";\n" ++
  "    use std::signer;\n\n" ++
  "    #[test(account = @0xCAFE)]\n" ++
  "    fun test_lifecycle(account: &signer) {\n" ++
  "        let addr = signer::address_of(account);\n" ++
  "        " ++ n ++ "::initialize(account);\n" ++
  "        assert!(" ++ n ++ "::value(addr) == 0, 0);\n" ++
  "        " ++ n ++ "::increment(account);\n" ++
  "        assert!(" ++ n ++ "::value(addr) == 1, 1);\n" ++
  "        " ++ n ++ "::increment(account);\n" ++
  "        assert!(" ++ n ++ "::value(addr) == 2, 2);\n" ++
  "    }\n" ++
  "}\n"

/-- Render Move.toml for the generated package. -/
def renderMoveToml (modName : String) : String :=
  "[package]\n" ++
  "name = \"" ++ modName.toLower ++ "\"\n" ++
  "version = \"0.0.1\"\n\n" ++
  "[addresses]\n" ++
  "proof_forge = \"_\"\n\n" ++
  "[dependencies]\n" ++
  "MoveStdlib = { git = \"https://github.com/aptos-labs/aptos-core.git\", subdir = \"aptos-move/framework/move-stdlib\", rev = \"main\" }\n"

structure PackageFile where
  path : String
  content : String

def renderPackage (mod : ProofForge.IR.Module) : Except EmitError (Array PackageFile) := do
  checkCapabilities mod
  let source ← renderSource mod
  let tests := renderTests mod.name
  let moveToml := renderMoveToml mod.name
  pure #[
    { path := "Move.toml", content := moveToml },
    { path := ("sources/" ++ mod.name.toLower ++ ".move"), content := source },
    { path := ("tests/" ++ mod.name.toLower ++ "_tests.move"), content := tests }
  ]

def renderModule (mod : ProofForge.IR.Module) : Except EmitError String := do
  let pkg ← renderPackage mod
  pure (String.intercalate "\n\n" (pkg.map (fun f => "--- " ++ f.path ++ " ---\n" ++ f.content)).toList)

end ProofForge.Backend.Move.Aptos
