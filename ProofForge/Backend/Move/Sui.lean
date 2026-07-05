import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Capability

namespace ProofForge.Backend.Move.Sui

open ProofForge.IR

structure EmitError where
  message : String
  deriving Repr, Inhabited

def err (msg : String) : Except EmitError α := .error { message := msg }

def supportedCapabilities : ProofForge.Target.CapabilitySet := #[
  .storageScalar,
  .assertions,
  .accountExplicit
]

def checkCapabilities (mod : Module) : Except EmitError Unit :=
  mod.capabilities.foldlM (fun _ capability =>
    if supportedCapabilities.contains capability then .ok ()
    else err ("Sui Counter MVP: capability `" ++ capability.id ++ "` is not supported")) ()

def requireScalarState (mod : Module) : Except EmitError String := do
  if mod.state.size != 1 then
    err "Sui Counter MVP: exactly one scalar u64 state is required"
  else
    match mod.state[0]? with
    | none => err "Sui Counter MVP: unreachable empty state"
    | some state =>
        if state.kind != .scalar then
          err ("Sui Counter MVP: state `" ++ state.id ++ "` must be scalar")
        else if state.type != .u64 then
          err ("Sui Counter MVP: state `" ++ state.id ++ "` must be u64")
        else
          pure state.id

def renderSource (mod : Module) : Except EmitError String := do
  checkCapabilities mod
  let field ← requireScalarState mod
  pure <| String.intercalate "\n" [
    "module proof_forge::" ++ mod.name.toLower ++ " {",
    "    use sui::object::{Self, UID};",
    "    use sui::tx_context::TxContext;",
    "",
    "    public struct " ++ mod.name ++ " has key {",
    "        id: UID,",
    "        " ++ field ++ ": u64,",
    "    }",
    "",
    "    public fun create(ctx: &mut TxContext): " ++ mod.name ++ " {",
    "        " ++ mod.name ++ " { id: object::new(ctx), " ++ field ++ ": 0 }",
    "    }",
    "",
    "    public fun initialize(ctx: &mut TxContext): " ++ mod.name ++ " {",
    "        create(ctx)",
    "    }",
    "",
    "    public fun increment(counter: &mut " ++ mod.name ++ ") {",
    "        counter." ++ field ++ " = counter." ++ field ++ " + 1;",
    "    }",
    "",
    "    public fun value(counter: &" ++ mod.name ++ "): u64 {",
    "        counter." ++ field,
    "    }",
    "",
    "    public fun get(counter: &" ++ mod.name ++ "): u64 {",
    "        value(counter)",
    "    }",
    "}"
  ]

def renderTests (modName : String) : String :=
  let n := modName.toLower
  String.intercalate "\n" [
    "#[test_only]",
    "module proof_forge::" ++ n ++ "_tests {",
    "    use proof_forge::" ++ n ++ ";",
    "    use sui::test_scenario;",
    "",
    "    #[test]",
    "    fun counter_lifecycle() {",
    "        let scenario = test_scenario::begin(@0xCAFE);",
    "        let ctx = test_scenario::ctx(&mut scenario);",
    "        let counter = " ++ n ++ "::initialize(ctx);",
    "        assert!(" ++ n ++ "::value(&counter) == 0, 0);",
    "        " ++ n ++ "::increment(&mut counter);",
    "        assert!(" ++ n ++ "::get(&counter) == 1, 1);",
    "        " ++ n ++ "::increment(&mut counter);",
    "        assert!(" ++ n ++ "::value(&counter) == 2, 2);",
    "        test_scenario::end(scenario);",
    "    }",
    "}"
  ]

def renderMoveToml (modName : String) : String :=
  String.intercalate "\n" [
    "[package]",
    "name = \"" ++ modName.toLower ++ "\"",
    "version = \"0.0.1\"",
    "",
    "[addresses]",
    "proof_forge = \"0x0\"",
    "",
    "[dependencies]",
    "Sui = { local = \"${SUI_FRAMEWORK_PATH}\" }",
    ""
  ]

structure PackageFile where
  path : String
  content : String

def renderClient (mod : Module) : String :=
  String.intercalate "\n" [
    "/* ProofForge generated Sui Counter client metadata. */",
    "export const TARGET = \"move-sui\";",
    "export const PACKAGE_NAME = \"" ++ mod.name.toLower ++ "\";",
    "export const MODULE_NAME = \"proof_forge::" ++ mod.name.toLower ++ "\";",
    "export const COUNTER_TYPE = \"" ++ mod.name ++ "\";",
    "",
    "export type ObjectId = string;",
    "export type CounterObjectRef = { objectId: ObjectId; version?: string; digest?: string };",
    "",
    "export const entrypoints = {",
    "  create: { txContext: \"required\", returns: COUNTER_TYPE },",
    "  initialize: { txContext: \"required\", returns: COUNTER_TYPE },",
    "  increment: { object: \"mutable Counter\" },",
    "  value: { object: \"immutable Counter\", returns: \"u64\" },",
    "  get: { object: \"immutable Counter\", returns: \"u64\" },",
    "} as const;",
    ""
  ]

def renderPackage (mod : Module) : Except EmitError (Array PackageFile) := do
  let source ← renderSource mod
  pure #[
    { path := "Move.toml", content := renderMoveToml mod.name },
    { path := "sources/" ++ mod.name.toLower ++ ".move", content := source },
    { path := "tests/" ++ mod.name.toLower ++ "_tests.move", content := renderTests mod.name },
    { path := "proof-forge-client.ts", content := renderClient mod }
  ]

end ProofForge.Backend.Move.Sui
