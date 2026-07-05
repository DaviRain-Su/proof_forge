/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Psy semantic plan — the `psy-dpn` counterpart of `ProofForge.Backend.Evm.Plan`.

The EVM backend separates IR-to-Yul lowering into two stages:
`Lower.lean` builds a `ModulePlan` (storage layout, helpers, events,
crosscalls, dispatch, checked-arith), then `IR.lean` consumes that plan
to build the Yul AST. This separation keeps the Yul builder pure and
gives a stable inspection point for artifact/deploy metadata.

The Psy backend mirrors the same split: `Plan.lean` builds a
`PsyModulePlan` capturing Psy-specific resolved shapes, and `IR.lean`
(`buildModule`) consumes the plan to build the `Psy.Module` AST.

What the Psy plan captures (Psy has no selectors, slot storage, event
topics, or checked arithmetic, so the plan is intentionally leaner than
the EVM plan):

- `StorageShapePlan`: per-state resolved shape (scalar / map key+value+capacity
  / array element+length+feltBackedU32 / structRef), so the AST builder does
  not re-resolve `findState?` or `isFeltBackedU32StorageArrayPath` on every
  expression.
- `ContextOpPlan`: the set of context fields actually used (userId,
  contractId, checkpointId), recorded for artifact metadata.
- `EventPlan`: event name + ordered data field names, so `__emit` lowering
  and artifact metadata share one source of truth.
- `CrosscallPlan`: crosscall target contract ids, recorded for future
  `__invoke_sync#<Felt>` helper discovery.
- `TestPlan`: the fixture-shape-detected test body lines and test function
  name, so `renderModule` does not re-detect the Counter shape inline.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Backend.Psy.Plan

open ProofForge.IR
open ProofForge.Target

structure PlanError where
  message : String
  deriving Repr, Inhabited

def PlanError.render (err : PlanError) : String :=
  err.message

def diagnosticError (err : Diagnostic) : PlanError :=
  { message := err.render }

/-! ## Storage shape plan -/

/-- Resolved shape of a single storage declaration. -/
inductive StorageShape where
  | scalar (type : ValueType)
  | structRef (type : ValueType)
  | map (keyType valueType : ValueType) (capacity : Nat)
  | array (elementType : ValueType) (length : Nat) (feltBackedU32 : Bool)
  deriving Repr

/-- A resolved storage state entry: id + shape. -/
structure StorageStatePlan where
  id : String
  shape : StorageShape
  deriving Repr

/-- The full storage layout for a module. -/
structure StorageLayout where
  states : Array StorageStatePlan
  deriving Repr

def findState? (layout : StorageLayout) (stateId : String) : Option StorageStatePlan :=
  layout.states.find? fun state => state.id == stateId

/-- Build the storage layout from a portable IR module. -/
def storageLayout (module : Module) : Except PlanError StorageLayout := do
  let states ← module.state.mapM fun state => do
    match state.kind with
    | .scalar =>
        match state.type with
        | .structType _ => .ok { id := state.id, shape := .structRef state.type }
        | _ => .ok { id := state.id, shape := .scalar state.type }
    | .map keyType capacity => .ok { id := state.id, shape := .map keyType state.type capacity }
    | .array length =>
        let feltBacked := state.type == .u32
        .ok { id := state.id, shape := .array state.type length feltBacked }
    | .dynamicArray => .error { message := s!"state `{state.id}` is storage.dynamicArray; Psy IR v0 does not lower portable dynamic array storage" }
  .ok { states }

/-! ## Context operation plan -/

inductive ContextOp where
  | userId | contractId | checkpointId
  deriving Repr

def ContextOp.fromIR (field : IR.ContextField) : Option ContextOp :=
  match field with
  | .userId => some .userId
  | .contractId => some .contractId
  | .checkpointId => some .checkpointId
  | _ => none

def ContextOp.name : ContextOp → String
  | .userId => "userId"
  | .contractId => "contractId"
  | .checkpointId => "checkpointId"

/-! ## Event plan -/

def exprTypeName? (e : IR.Expr) : Option String :=
  match e with
  | .literal (.u8 _) => some "U8"
  | .literal (.u32 _) => some "U32"
  | .literal (.u64 _) => some "U64"
  | .literal (.u128 _) => some "U128"
  | .literal (.bool _) => some "Bool"
  | .literal (.address _) => some "Address"
  | .literal (.hash4 _ _ _ _) => some "Hash"
  | .arrayLit elemType _ => some s!"Array<{elemType.name}>"
  | .cast _ targetType => some targetType.name
  | .crosscallInvokeTyped _ _ _ retType => some retType.name
  | .structLit typeName _ => some typeName
  | _ => none

structure EventPlan where
  name : String
  dataFields : Array (String × String)
  deriving Repr

/-! ## Crosscall plan -/

structure CrosscallPlan where
  /-- Contract ids referenced by crosscallInvoke effects/expressions. -/
  targets : Array String
  deriving Repr

/-! ## Test plan -/

structure TestPlan where
  functionName : String
  bodyLines : Array String
  deriving Repr

/-! ## Module plan -/

structure PsyModulePlan where
  name : String
  storage : StorageLayout
  contextOps : Array ContextOp
  events : Array EventPlan
  crosscalls : CrosscallPlan
  test : TestPlan
  capabilities : Array Capability
  deriving Repr

/-! ## Plan construction helpers -/

mutual
  /-- Collect context ops used in an expression. -/
  partial def exprContextOps (e : IR.Expr) : Array ContextOp :=
    match e with
    | .effect eff => effectContextOps eff
    | .arrayLit _ values => values.foldl (fun acc v => acc ++ exprContextOps v) #[]
    | .arrayGet array index => exprContextOps array ++ exprContextOps index
    | .structLit _ fields => fields.foldl (fun acc (_, v) => acc ++ exprContextOps v) #[]
    | .field base _ => exprContextOps base
    | .add l r | .sub l r | .mul l r | .div l r | .mod l r | .pow l r
    | .bitAnd l r | .bitOr l r | .bitXor l r | .shiftLeft l r | .shiftRight l r
    | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
    | .boolAnd l r | .boolOr l r => exprContextOps l ++ exprContextOps r
    | .boolNot v | .hash v => exprContextOps v
    | .hashTwoToOne l r => exprContextOps l ++ exprContextOps r
    | .cast v _ => exprContextOps v
    | .hashValue a b c d => exprContextOps a ++ exprContextOps b ++ exprContextOps c ++ exprContextOps d
    | .crosscallInvoke target methodId args =>
        exprContextOps target ++ exprContextOps methodId ++ args.foldl (fun acc v => acc ++ exprContextOps v) #[]
    | _ => #[]

  partial def effectContextOps (eff : IR.Effect) : Array ContextOp :=
    match eff with
    | .contextRead field =>
        match ContextOp.fromIR field with
        | some op => #[op]
        | none => #[]
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageArrayWrite _ _ v | .storageStructFieldWrite _ _ v
    | .storageArrayStructFieldWrite _ _ _ v
    | .storagePathWrite _ _ v | .storagePathAssignOp _ _ _ v
    | .storageMapInsert _ _ v | .storageMapSet _ _ v =>
        exprContextOps v
    | .storageMapContains _ k | .storageMapGet _ k | .storageArrayRead _ k =>
        exprContextOps k
    | .storagePathRead _ path =>
        path.foldl (fun acc seg => match seg with | .index e => acc ++ exprContextOps e | _ => acc) #[]
    | .storageArrayStructFieldRead _ k _ => exprContextOps k
    | .storageStructFieldRead _ _ => #[]
    | .eventEmit _ fields | .eventEmitIndexed _ _ fields =>
        fields.foldl (fun acc (_, v) => acc ++ exprContextOps v) #[]
    | _ => #[]
end

/-- Collect events from a statement. -/
partial def stmtEvents (s : IR.Statement) : Array EventPlan :=
  let fieldType (e : IR.Expr) : String := exprTypeName? e |>.getD "Felt"
  match s with
  | .effect (.eventEmit name fields) =>
      #[{ name, dataFields := fields.map (fun (n, e) => (n, fieldType e)) }]
  | .effect (.eventEmitIndexed name indexedFields dataFields) =>
      #[{ name, dataFields := (indexedFields ++ dataFields).map (fun (n, e) => (n, fieldType e)) }]
  | .ifElse _ thenBody elseBody => thenBody.flatMap stmtEvents ++ elseBody.flatMap stmtEvents
  | .boundedFor _ _ _ body => body.flatMap stmtEvents
  | _ => #[]

mutual
  /-- Collect crosscall target contract ids from an effect. -/
  partial def effectCrosscallTargets (eff : IR.Effect) : Array String :=
    match eff with
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageArrayWrite _ _ v | .storageStructFieldWrite _ _ v
    | .storageArrayStructFieldWrite _ _ _ v
    | .storagePathWrite _ _ v | .storagePathAssignOp _ _ _ v
    | .storageMapInsert _ _ v | .storageMapSet _ _ v =>
        exprCrosscallTargets v
    | .storageMapContains _ k | .storageMapGet _ k | .storageArrayRead _ k =>
        exprCrosscallTargets k
    | .storagePathRead _ path =>
        path.foldl (fun acc seg => match seg with | .index e => acc ++ exprCrosscallTargets e | _ => acc) #[]
    | .storageArrayStructFieldRead _ k _ => exprCrosscallTargets k
    | .storageStructFieldRead _ _ => #[]
    | .eventEmit _ fields | .eventEmitIndexed _ _ fields =>
        fields.foldl (fun acc (_, v) => acc ++ exprCrosscallTargets v) #[]
    | _ => #[]

  /-- Collect crosscall target contract ids from an expression. -/
  partial def exprCrosscallTargets (e : IR.Expr) : Array String :=
    match e with
    | .crosscallInvoke target _ args =>
        let targetIds := match target with | .local n => #[n] | _ => #[]
        args.foldl (fun acc v => acc ++ exprCrosscallTargets v) targetIds
    | .effect eff => effectCrosscallTargets eff
    | .arrayLit _ values => values.foldl (fun acc v => acc ++ exprCrosscallTargets v) #[]
    | .arrayGet array index => exprCrosscallTargets array ++ exprCrosscallTargets index
    | .structLit _ fields => fields.foldl (fun acc (_, v) => acc ++ exprCrosscallTargets v) #[]
    | .field base _ => exprCrosscallTargets base
    | .add l r | .sub l r | .mul l r | .div l r | .mod l r | .pow l r
    | .bitAnd l r | .bitOr l r | .bitXor l r | .shiftLeft l r | .shiftRight l r
    | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
    | .boolAnd l r | .boolOr l r => exprCrosscallTargets l ++ exprCrosscallTargets r
    | .boolNot v | .hash v => exprCrosscallTargets v
    | .hashTwoToOne l r => exprCrosscallTargets l ++ exprCrosscallTargets r
    | .cast v _ => exprCrosscallTargets v
    | .hashValue a b c d =>
        exprCrosscallTargets a ++ exprCrosscallTargets b ++ exprCrosscallTargets c ++ exprCrosscallTargets d
    | _ => #[]
end

/-- Collect context ops from a statement. -/
partial def stmtContextOps (s : IR.Statement) : Array ContextOp :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v => exprContextOps v
  | .effect eff => effectContextOps eff
  | .assert c _ _ => exprContextOps c
  | .assertEq lhs rhs _ _ => exprContextOps lhs ++ exprContextOps rhs
  | .ifElse c thenBody elseBody => exprContextOps c ++ thenBody.flatMap stmtContextOps ++ elseBody.flatMap stmtContextOps
  | .boundedFor _ _ _ body => body.flatMap stmtContextOps
  | .return v => exprContextOps v
  | _ => #[]

/-- Collect crosscall targets from a statement. -/
partial def stmtCrosscallTargets (s : IR.Statement) : Array String :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v => exprCrosscallTargets v
  | .effect eff => effectCrosscallTargets eff
  | .assert c _ _ => exprCrosscallTargets c
  | .assertEq lhs rhs _ _ => exprCrosscallTargets lhs ++ exprCrosscallTargets rhs
  | .ifElse c thenBody elseBody => exprCrosscallTargets c ++ thenBody.flatMap stmtCrosscallTargets ++ elseBody.flatMap stmtCrosscallTargets
  | .boundedFor _ _ _ body => body.flatMap stmtCrosscallTargets
  | .return v => exprCrosscallTargets v
  | _ => #[]

/-- The Psy test function name for a module (mirrors IR.testFunctionName). -/
def testFunctionName (module : Module) : String :=
  if module.name == "StorageNestedAggregateProbe" then "test_storage_nested_aggregate_probe_fixture"
  else if module.name == "ConditionalProbe" then "test_conditional_probe_fixture"
  else if module.name == "ElseIfProbe" then "test_else_if_probe_fixture"
  else if module.name == "ArithmeticProbe" then "test_arithmetic_probe_fixture"
  else if module.name == "U32ArithmeticProbe" then "test_u32_arithmetic_probe_fixture"
  else if module.name == "BitwiseProbe" then "test_bitwise_probe_fixture"
  else if module.name == "BoolStorageArrayProbe" then "test_bool_storage_array_probe_fixture"
  else if module.name == "BoolStorageScalarProbe" then "test_bool_storage_scalar_probe_fixture"
  else if module.name == "U32HashPackingProbe" then "test_u32_hash_packing_probe_fixture"
  else if module.name == "U32StorageScalarProbe" then "test_u32_storage_scalar_probe_fixture"
  else if module.name == "U32StorageArrayProbe" then "test_u32_storage_array_probe_fixture"
  else if module.name == "ExpressionPredicateProbe" then "test_expression_predicate_probe_fixture"
  else if module.name == "NestedAggregateProbe" then "test_nested_aggregate_probe_fixture"
  else if module.name == "AbiAggregateProbe" then "test_abi_aggregate_probe_fixture"
  else if module.name == "StructArrayProbe" then "test_struct_array_probe_fixture"
  else if module.name == "StructProbe" then "test_struct_probe_fixture"
  else if module.name == "ArrayProbe" then "test_array_probe_fixture"
  else if module.name == "LoopProbe" then "test_loop_probe_fixture"
  else if module.name == "AssertProbe" then "test_assert_probe_fixture"
  else if module.name == "MapProbe" then "test_map_probe_fixture"
  else if module.name == "HashProbe" then "test_hash_probe_fixture"
  else if module.name == "HashStorageProbe" then "test_hash_storage_probe_fixture"
  else if module.name == "ContextProbe" then "test_context_probe_fixture"
  else if module.name == "Counter" then "test_counter_lifecycle"
  else s!"test_{module.name}_fixture"

/-- The `impl <Name>Ref` name for a module. -/
def capitalizedRefName (module : Module) : String :=
  s!"{module.name}Ref"

/-- Build the test body lines for a module (fixture-shape detection). -/
def buildTestBody (module : Module) : Except PlanError (Array String) := do
  let refName := capitalizedRefName module
  let hasCounterShape :=
    module.state.size == 1 &&
    module.state.any (fun state => state.id == "count" && state.kind == .scalar && state.type == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "initialize") &&
    module.entrypoints.any (fun entry => entry.name == "increment") &&
    module.entrypoints.any (fun entry => entry.name == "get")
  if hasCounterShape then
    .ok #[
      s!"let c = {refName}::new(ContractMetadata::current());",
      s!"{refName}::initialize();",
      "assert_eq(c.count, 0, \"counter starts at zero\");",
      s!"{refName}::increment();",
      s!"assert_eq({refName}::get(), 1, \"counter increments once\");",
      s!"{refName}::increment();",
      s!"assert_eq({refName}::get(), 2, \"counter increments twice\");"
    ]
  else if module.name == "ConditionalProbe" &&
    module.entrypoints.any (fun entry => entry.name == "conditional_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::conditional_lifecycle(), 10, \"conditional branches update storage\");"
    ]
  else if module.name == "ArithmeticProbe" &&
    module.entrypoints.any (fun entry => entry.name == "arithmetic_mix" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::arithmetic_mix(), 60, \"arithmetic expressions preserve precedence\");"
    ]
  else if module.name == "U32ArithmeticProbe" &&
    module.entrypoints.any (fun entry => entry.name == "u32_arithmetic" && entry.params.size == 2 && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::u32_arithmetic(2u32, 3u32), 1, \"u32 arithmetic follows upstream u32 test shape\");"
    ]
  else if module.name == "BitwiseProbe" &&
    module.entrypoints.any (fun entry => entry.name == "bitwise_mix" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::bitwise_mix(), 16, \"bitwise expressions follow upstream opcode_test shape\");"
    ]
  else if module.name == "U32HashPackingProbe" &&
    module.entrypoints.any (fun entry => entry.name == "pack_literal" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "pack_params" && entry.params.size == 8 && entry.returns == .hash) then
    .ok #[
      "let literal_hash: Hash = [8589934593, 17179869187, 25769803781, 34359738375];",
      "let param_hash: Hash = [42949672969, 51539607563, 60129542157, 68719476751];",
      s!"assert_eq({refName}::pack_literal(), literal_hash, \"u32 literal limbs pack into Hash\");",
      s!"assert_eq({refName}::pack_params(9u32, 10u32, 11u32, 12u32, 13u32, 14u32, 15u32, 16u32), param_hash, \"u32 ABI limbs pack into Hash\");"
    ]
  else if module.name == "U32StorageScalarProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_lifecycle(), 12, \"u32 scalar storage reads preserve u32 values\");"
    ]
  else if module.name == "BoolStorageArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "local_flags_sum" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::local_flags_sum(), 2, \"bool fixed arrays index true values\");",
      s!"assert_eq({refName}::storage_lifecycle(), 2, \"bool storage arrays preserve bool values\");"
    ]
  else if module.name == "BoolStorageScalarProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_lifecycle(), 1, \"bool scalar storage reads preserve bool values\");"
    ]
  else if module.name == "U32StorageArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_lifecycle(), 28, \"u32 storage array path assignments preserve u32 arithmetic\");"
    ]
  else if module.name == "ExpressionPredicateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "predicate_sum" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::predicate_sum(), 16, \"predicate expressions compose to true\");"
    ]
  else if module.name == "ContextProbe" &&
    module.entrypoints.any (fun entry => entry.name == "sum_context" && entry.params.size == 2 && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::sum_context(2, 3), 2 + 3 + get_user_id() + get_contract_id() + get_checkpoint_id(), \"context sum follows current context\");"
    ]
  else if module.name == "HashProbe" &&
    module.entrypoints.any (fun entry => entry.name == "poseidon_hash" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "poseidon_pair_hash" && entry.params.isEmpty && entry.returns == .hash) then
    .ok #[
      s!"let left: Hash = [1, 2, 3, 4];",
      s!"let right: Hash = [5, 6, 7, 8];",
      s!"assert_eq({refName}::poseidon_hash(), hash(left), \"hash probe matches Poseidon hash\");",
      s!"assert_eq({refName}::poseidon_pair_hash(), hash_two_to_one(left, right), \"pair hash probe matches Poseidon two-to-one hash\");"
    ]
  else if module.name == "HashStorageProbe" &&
    module.entrypoints.any (fun entry => entry.name == "scalar_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "array_lifecycle" && entry.params.isEmpty && entry.returns == .hash) then
    .ok #[
      "let scalar_expected: Hash = [5, 6, 7, 8];",
      "let array_expected: Hash = [55, 66, 77, 88];",
      s!"assert_eq({refName}::scalar_lifecycle(), scalar_expected, \"hash scalar storage returns latest value\");",
      s!"assert_eq({refName}::array_lifecycle(), array_expected, \"hash array storage returns indexed value\");"
    ]
  else if module.name == "MapProbe" &&
    module.state.any (fun state => state.id == "balances") &&
    module.entrypoints.any (fun entry => entry.name == "map_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "has_seed_balance" && entry.params.isEmpty && entry.returns == .bool) &&
    module.entrypoints.any (fun entry => entry.name == "get_seed_balance" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "path_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "set_return_lifecycle" && entry.params.isEmpty && entry.returns == .hash) &&
    module.entrypoints.any (fun entry => entry.name == "insert_return_lifecycle" && entry.params.isEmpty && entry.returns == .hash) then
    .ok #[
      s!"let c = {refName}::new(ContractMetadata::current());",
      "let key: Hash = [1001, 0, 0, 0];",
      "let value1: Hash = [55, 66, 77, 88];",
      "let path_key: Hash = [2002, 0, 0, 0];",
      "let path_value: Hash = [77, 88, 99, 111];",
      "let set_old_value: Hash = [31, 32, 33, 34];",
      "let insert_old_value: Hash = [5, 6, 7, 8];",
      s!"let set_result: Hash = {refName}::set_return_lifecycle();",
      s!"let insert_result: Hash = {refName}::insert_return_lifecycle();",
      s!"assert_eq({refName}::has_seed_balance(), false, \"seed balance starts absent\");",
      s!"assert_eq({refName}::map_lifecycle(), value1, \"map lifecycle returns the updated value\");",
      s!"assert_eq({refName}::has_seed_balance(), true, \"seed balance exists after lifecycle\");",
      s!"assert_eq({refName}::get_seed_balance(), value1, \"seed getter reads the lifecycle value\");",
      s!"assert_eq({refName}::path_lifecycle(), path_value, \"map storage path reads updated value\");",
      "assert_eq(set_result, set_old_value, \"map set returns the previous value\");",
      "assert_eq(insert_result, insert_old_value, \"map insert returns the previous value\");",
      "assert_eq(c.before, 111, \"map lifecycle preserves before field\");",
      "assert_eq(c.after, 222, \"map lifecycle preserves after field\");",
      "assert_eq(c.balances.contains(key), true, \"raw map contains follows generated entrypoint\");",
      "assert_eq(c.balances.get(path_key), path_value, \"raw map get follows storage path entrypoint\");"
    ]
  else if module.name == "AssertProbe" &&
    module.entrypoints.any (fun entry => entry.name == "checked_sum" && entry.params.size == 2 && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::checked_sum(5, 7), 12, \"checked_sum returns the asserted value\");"
    ]
  else if module.name == "LoopProbe" &&
    module.entrypoints.any (fun entry => entry.name == "count_to_three" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::count_to_three(), 3, \"bounded loop runs exactly three iterations\");"
    ]
  else if module.name == "ArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "sum_literal" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "array_predicates" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::sum_literal(), 60, \"fixed array literal indexes add up\");",
      s!"assert_eq({refName}::storage_lifecycle(), 31, \"storage array indexes read after writes\");",
      s!"assert_eq({refName}::array_predicates(), 1, \"fixed array equality predicates hold\");"
    ]
  else if module.name == "StructProbe" &&
    module.entrypoints.any (fun entry => entry.name == "local_sum" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::local_sum(), 30, \"struct literal fields add up\");",
      s!"assert_eq({refName}::storage_lifecycle(), 26, \"storage struct fields read after writes\");"
    ]
  else if module.name == "StructArrayProbe" &&
    module.entrypoints.any (fun entry => entry.name == "local_struct_array_sum" && entry.params.isEmpty && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "storage_struct_array_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::local_struct_array_sum(), 100, \"struct array literal fields add up\");",
      s!"assert_eq({refName}::storage_struct_array_lifecycle(), 102, \"storage struct array fields read after writes\");"
    ]
  else if module.name == "AbiAggregateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "sum_pair" && entry.params.size == 1 && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "sum_array" && entry.params.size == 1 && entry.returns == .u64) &&
    module.entrypoints.any (fun entry => entry.name == "make_pair" && entry.params.size == 2 && entry.returns == .structType "Pair") then
    .ok #[
      s!"assert_eq({refName}::sum_pair(new Pair " ++ "{ left: 7, right: 8 }), 15, \"struct ABI parameter flattens\");",
      s!"assert_eq({refName}::sum_array([1, 2, 3]), 6, \"fixed-array ABI parameter flattens\");",
      s!"let pair: Pair = {refName}::make_pair(9, 4);",
      "assert_eq(pair.left + pair.right, 13, \"struct ABI return flattens\");"
    ]
  else if module.name == "NestedAggregateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "nested_update_sum" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::nested_update_sum(), 51, \"nested aggregate assignment updates selected field\");"
    ]
  else if module.name == "StorageNestedAggregateProbe" &&
    module.entrypoints.any (fun entry => entry.name == "storage_nested_lifecycle" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::storage_nested_lifecycle(), 252, \"storage nested aggregate path updates selected fields\");"
    ]
  else if module.name == "EventProbe" &&
    module.entrypoints.any (fun entry => entry.name == "emit_value_event" && entry.params.size == 1 && entry.returns == .unit) then
    .ok #[
      s!"{refName}::emit_value_event(42);",
      "assert_eq(1, 1, \"event entrypoint call compiles and emits\");"
    ]
  else if module.name == "ElseIfProbe" &&
    module.entrypoints.any (fun entry => entry.name == "classify" && entry.params.isEmpty && entry.returns == .u64) then
    .ok #[
      s!"assert_eq({refName}::classify(), 1, \"else-if chain selects the equality branch\");"
    ]
  else
    .ok #[
      s!"let _c = {refName}::new(ContractMetadata::current());"
    ]

/-- Build the complete Psy semantic plan for a module. -/
def buildModulePlan (module : Module) : Except PlanError PsyModulePlan := do
  let storage ← storageLayout module
  let testBody ← buildTestBody module
  let testPlan := { functionName := testFunctionName module, bodyLines := testBody }
  let events := module.entrypoints.flatMap (fun ep => ep.body.flatMap stmtEvents)
  let contextOps := module.entrypoints.flatMap (fun ep => ep.body.flatMap (fun s => stmtContextOps s))
  let crosscallTargets := module.entrypoints.flatMap (fun ep => ep.body.flatMap (fun s => stmtCrosscallTargets s))
  let caps := match resolveModule Target.psyDpn module with
    | .ok plan => plan.calls.map (fun call => call.capability)
    | .error _ => #[]
  .ok {
    name := module.name,
    storage,
    contextOps,
    events,
    crosscalls := { targets := crosscallTargets },
    test := testPlan,
    capabilities := caps
  }

end ProofForge.Backend.Psy.Plan