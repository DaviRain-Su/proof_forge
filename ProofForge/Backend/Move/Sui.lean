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
    "#[allow(duplicate_alias)]",
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
    "    public fun destroy(counter: " ++ mod.name ++ ") {",
    "        let " ++ mod.name ++ " { id, " ++ field ++ ": _ } = counter;",
    "        object::delete(id);",
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
    "        let mut scenario = test_scenario::begin(@0xCAFE);",
    "        let ctx = test_scenario::ctx(&mut scenario);",
    "        let mut counter = " ++ n ++ "::initialize(ctx);",
    "        assert!(" ++ n ++ "::value(&counter) == 0, 0);",
    "        " ++ n ++ "::increment(&mut counter);",
    "        assert!(" ++ n ++ "::get(&counter) == 1, 1);",
    "        " ++ n ++ "::increment(&mut counter);",
    "        assert!(" ++ n ++ "::value(&counter) == 2, 2);",
    "        " ++ n ++ "::destroy(counter);",
    "        test_scenario::end(scenario);",
    "    }",
    "}"
  ]

def renderMoveToml (modName : String) : String :=
  String.intercalate "\n" [
    "[package]",
    "name = \"" ++ modName.toLower ++ "\"",
    "version = \"0.0.1\"",
    "edition = \"2024\"",
    "",
    "[addresses]",
    "proof_forge = \"0x0\"",
    "",
    "[dependencies]",
    "# Sui framework dependencies are resolved automatically by local `sui move build/test`.",
    ""
  ]

structure PackageFile where
  path : String
  content : String

def renderClient (mod : Module) : String :=
  let packageName := mod.name.toLower
  String.intercalate "\n" [
    "/* ProofForge generated Sui Counter client sketch. */",
    "export const TARGET = \"move-sui\";",
    "export const PACKAGE_NAME = \"" ++ packageName ++ "\";",
    "export const MODULE_NAME = \"" ++ packageName ++ "\";",
    "export const MODULE_ADDRESS = \"proof_forge\";",
    "export const PACKAGE_ID = \"0x0\";",
    "export const COUNTER_TYPE = \"" ++ mod.name ++ "\";",
    "",
    "export type ObjectId = string;",
    "export type CounterObjectRef = { objectId: ObjectId; version?: string | number; digest?: string };",
    "export type CounterObjectInput = ObjectId | CounterObjectRef;",
    "export type SuiTransactionLike = {",
    "  object?: (id: ObjectId) => unknown;",
    "  moveCall: (input: { target: string; arguments?: unknown[] }) => unknown;",
    "};",
    "",
    "export function counterType(packageId: string = PACKAGE_ID): string {",
    "  return `${packageId}::${MODULE_NAME}::${COUNTER_TYPE}`;",
    "}",
    "",
    "export function entrypointTarget(name: \"create\" | \"initialize\" | \"increment\" | \"value\" | \"get\", packageId: string = PACKAGE_ID): string {",
    "  return `${packageId}::${MODULE_NAME}::${name}`;",
    "}",
    "",
    "export function counterObjectId(counter: CounterObjectInput): ObjectId {",
    "  return typeof counter === \"string\" ? counter : counter.objectId;",
    "}",
    "",
    "export function counterObjectArg(tx: SuiTransactionLike, counter: CounterObjectInput): unknown {",
    "  const objectId = counterObjectId(counter);",
    "  return tx.object ? tx.object(objectId) : objectId;",
    "}",
    "",
    "export function createCounter(tx: SuiTransactionLike, packageId: string = PACKAGE_ID): unknown {",
    "  return tx.moveCall({ target: entrypointTarget(\"create\", packageId), arguments: [] });",
    "}",
    "",
    "export function initializeCounter(tx: SuiTransactionLike, packageId: string = PACKAGE_ID): unknown {",
    "  return tx.moveCall({ target: entrypointTarget(\"initialize\", packageId), arguments: [] });",
    "}",
    "",
    "export function incrementCounter(tx: SuiTransactionLike, counter: CounterObjectInput, packageId: string = PACKAGE_ID): unknown {",
    "  return tx.moveCall({ target: entrypointTarget(\"increment\", packageId), arguments: [counterObjectArg(tx, counter)] });",
    "}",
    "",
    "export function valueCounter(tx: SuiTransactionLike, counter: CounterObjectInput, packageId: string = PACKAGE_ID): unknown {",
    "  return tx.moveCall({ target: entrypointTarget(\"value\", packageId), arguments: [counterObjectArg(tx, counter)] });",
    "}",
    "",
    "export function getCounterValue(tx: SuiTransactionLike, counter: CounterObjectInput, packageId: string = PACKAGE_ID): unknown {",
    "  return tx.moveCall({ target: entrypointTarget(\"get\", packageId), arguments: [counterObjectArg(tx, counter)] });",
    "}",
    "",
    "export const entrypoints = {",
    "  create: { txContext: \"&mut TxContext\", returns: COUNTER_TYPE, helper: createCounter },",
    "  initialize: { txContext: \"&mut TxContext\", returns: COUNTER_TYPE, helper: initializeCounter },",
    "  increment: { object: \"mutable Counter\", helper: incrementCounter },",
    "  value: { object: \"immutable Counter\", returns: \"u64\", helper: valueCounter },",
    "  get: { object: \"immutable Counter\", returns: \"u64\", helper: getCounterValue },",
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
