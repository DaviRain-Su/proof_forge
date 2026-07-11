import ProofForge.IR.Contract
import ProofForge.Contract.Spec

namespace ProofForge.IR.Legacy

/--! Disposition of a legacy IR node in the canonical-core migration.

A `LegacyDisposition` records what the migration plan intends to do with a
specific `Expr`, `Effect`, `Statement`, or `ContractSpec` field.  It is part of
the Wave 0 "freeze and classify" contract: before the adapter can accept a
legacy node, that node must have an explicit decision and an owner. -/
inductive LegacyDisposition
  | preserve
  | normalize
  | materialization
  | evidence
  | reject
  deriving BEq, Repr

def LegacyDisposition.toString : LegacyDisposition → String
  | .preserve => "preserve"
  | .normalize => "normalize"
  | .materialization => "materialization"
  | .evidence => "evidence"
  | .reject => "reject"

/--! Decision for one legacy IR constructor.

`nodeTag` is a stable constructor identifier (e.g. `"Expr.literal"`).  The
`owner` is the team/task responsible for making the disposition true.  The
`reason` is a short, human-readable justification. -/
structure LegacyDecision where
  nodeTag : String
  disposition : LegacyDisposition
  owner : String
  reason : String
  deriving BEq, Repr

/--! Decision for one `ContractSpec` field. -/
structure LegacySpecFieldDecision where
  field : String
  disposition : LegacyDisposition
  owner : String
  reason : String
  deriving BEq, Repr

/--! Classify a legacy `Effect` constructor.

No wildcard arms: adding a new `Effect` constructor makes this function fail to
compile until it receives an explicit decision. -/
def classifyEffect : Effect → LegacyDecision
  | .storageScalarRead _ =>
      { nodeTag := "Effect.storageScalarRead"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar storage read is in the initial accepted runtime fragment" }
  | .storageScalarWrite _ _ =>
      { nodeTag := "Effect.storageScalarWrite"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar storage write is in the initial accepted runtime fragment" }
  | .storageScalarAssignOp _ _ _ =>
      { nodeTag := "Effect.storageScalarAssignOp"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar storage assign-op is in the initial accepted runtime fragment" }
  | .storageMapContains _ _ =>
      { nodeTag := "Effect.storageMapContains"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage rejected until core validator and semantics tasks land" }
  | .storageMapGet _ _ =>
      { nodeTag := "Effect.storageMapGet"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage read rejected until core validator and semantics tasks land" }
  | .storageMapInsert _ _ _ =>
      { nodeTag := "Effect.storageMapInsert"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage insert rejected until core validator and semantics tasks land" }
  | .storageMapSet _ _ _ =>
      { nodeTag := "Effect.storageMapSet"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage set rejected until core validator and semantics tasks land" }
  | .storageArrayRead _ _ =>
      { nodeTag := "Effect.storageArrayRead"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array read rejected until core validator and semantics tasks land" }
  | .storageArrayWrite _ _ _ =>
      { nodeTag := "Effect.storageArrayWrite"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array write rejected until core validator and semantics tasks land" }
  | .storageArrayStructFieldRead _ _ _ =>
      { nodeTag := "Effect.storageArrayStructFieldRead"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array struct-field read rejected until core validator and semantics tasks land" }
  | .storageArrayStructFieldWrite _ _ _ _ =>
      { nodeTag := "Effect.storageArrayStructFieldWrite"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array struct-field write rejected until core validator and semantics tasks land" }
  | .storageDynamicArrayPush _ _ =>
      { nodeTag := "Effect.storageDynamicArrayPush"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "dynamic array push rejected until core validator and semantics tasks land" }
  | .storageDynamicArrayPop _ =>
      { nodeTag := "Effect.storageDynamicArrayPop"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "dynamic array pop rejected until core validator and semantics tasks land" }
  | .memoryArraySet _ _ _ =>
      { nodeTag := "Effect.memoryArraySet"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array set rejected until core validator and semantics tasks land" }
  | .storageStructFieldRead _ _ =>
      { nodeTag := "Effect.storageStructFieldRead"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "storage struct field read rejected until core validator and semantics tasks land" }
  | .storageStructFieldWrite _ _ _ =>
      { nodeTag := "Effect.storageStructFieldWrite"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "storage struct field write rejected until core validator and semantics tasks land" }
  | .storagePathRead _ _ =>
      { nodeTag := "Effect.storagePathRead"
        disposition := .reject
        owner := "canonical-core-storage-paths"
        reason := "storage path read rejected until core validator and semantics tasks land" }
  | .storagePathWrite _ _ _ =>
      { nodeTag := "Effect.storagePathWrite"
        disposition := .reject
        owner := "canonical-core-storage-paths"
        reason := "storage path write rejected until core validator and semantics tasks land" }
  | .storagePathAssignOp _ _ _ _ =>
      { nodeTag := "Effect.storagePathAssignOp"
        disposition := .reject
        owner := "canonical-core-storage-paths"
        reason := "storage path assign-op rejected until core validator and semantics tasks land" }
  | .contextRead _ =>
      { nodeTag := "Effect.contextRead"
        disposition := .normalize
        owner := "canonical-core"
        reason := "context read is in the initial accepted runtime fragment" }
  | .eventEmit _ _ =>
      { nodeTag := "Effect.eventEmit"
        disposition := .normalize
        owner := "canonical-core"
        reason := "event emit is in the initial accepted runtime fragment" }
  | .eventEmitIndexed _ _ _ =>
      { nodeTag := "Effect.eventEmitIndexed"
        disposition := .materialization
        owner := "target-plan-events"
        reason := "indexed/data event field split materialized to target plan" }
  | .checkErc721Received _ _ _ _ =>
      { nodeTag := "Effect.checkErc721Received"
        disposition := .reject
        owner := "evm-adapter"
        reason := "ERC-721 receiver check is target-only until a typed portable primitive or HostOp handler exists" }
  | .checkErc1155Received _ _ _ _ _ =>
      { nodeTag := "Effect.checkErc1155Received"
        disposition := .reject
        owner := "evm-adapter"
        reason := "ERC-1155 receiver check is target-only until a typed portable primitive or HostOp handler exists" }
  | .checkErc1155BatchReceived _ _ _ _ _ _ _ =>
      { nodeTag := "Effect.checkErc1155BatchReceived"
        disposition := .reject
        owner := "evm-adapter"
        reason := "ERC-1155 batch receiver check is target-only until a typed portable primitive or HostOp handler exists" }

/--! Classify a legacy `Statement` constructor.

No wildcard arms: adding a new `Statement` constructor makes this function fail
to compile until it receives an explicit decision. -/
def classifyStatement : Statement → LegacyDecision
  | .letBind _ _ _ =>
      { nodeTag := "Statement.letBind"
        disposition := .normalize
        owner := "canonical-core"
        reason := "immutable let binding is in the initial accepted runtime fragment" }
  | .letMutBind _ _ _ =>
      { nodeTag := "Statement.letMutBind"
        disposition := .normalize
        owner := "canonical-core"
        reason := "mutable let binding is in the initial accepted runtime fragment" }
  | .assign _ _ =>
      { nodeTag := "Statement.assign"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assignment is in the initial accepted runtime fragment" }
  | .assignOp _ _ _ =>
      { nodeTag := "Statement.assignOp"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assign-op is in the initial accepted runtime fragment" }
  | .effect _ =>
      { nodeTag := "Statement.effect"
        disposition := .normalize
        owner := "canonical-core"
        reason := "effect statement is in the initial accepted runtime fragment" }
  | .assert _ _ _ =>
      { nodeTag := "Statement.assert"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assert is in the initial accepted runtime fragment" }
  | .assertEq _ _ _ _ =>
      { nodeTag := "Statement.assertEq"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assert-eq is in the initial accepted runtime fragment" }
  | .revert _ =>
      { nodeTag := "Statement.revert"
        disposition := .normalize
        owner := "canonical-core"
        reason := "revert is in the initial accepted runtime fragment" }
  | .revertWithError _ =>
      { nodeTag := "Statement.revertWithError"
        disposition := .normalize
        owner := "canonical-core"
        reason := "revert with structured error is in the initial accepted runtime fragment" }
  | .release _ =>
      { nodeTag := "Statement.release"
        disposition := .normalize
        owner := "canonical-core"
        reason := "local release is in the initial accepted runtime fragment" }
  | .ifElse _ _ _ =>
      { nodeTag := "Statement.ifElse"
        disposition := .normalize
        owner := "canonical-core"
        reason := "conditional is in the initial accepted runtime fragment" }
  | .boundedFor _ _ _ _ =>
      { nodeTag := "Statement.boundedFor"
        disposition := .normalize
        owner := "canonical-core"
        reason := "bounded for loop is in the initial accepted runtime fragment" }
  | .whileLoop _ _ =>
      { nodeTag := "Statement.whileLoop"
        disposition := .reject
        owner := "canonical-core-loops"
        reason := "unbounded while loop rejected until core validator and semantics tasks land" }
  | .return _ =>
      { nodeTag := "Statement.return"
        disposition := .normalize
        owner := "canonical-core"
        reason := "return is in the initial accepted runtime fragment" }

/--! Classify a legacy `Expr` constructor.

No wildcard arms: adding a new `Expr` constructor makes this function fail to
compile until it receives an explicit decision. -/
def classifyExpr : Expr → LegacyDecision
  | .literal _ =>
      { nodeTag := "Expr.literal"
        disposition := .preserve
        owner := "canonical-core"
        reason := "fixed-width literal is in the initial accepted runtime fragment" }
  | .local _ =>
      { nodeTag := "Expr.local"
        disposition := .preserve
        owner := "canonical-core"
        reason := "local variable reference is in the initial accepted runtime fragment" }
  | .arrayLit _ _ =>
      { nodeTag := "Expr.arrayLit"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "fixed array literal rejected until core validator and semantics tasks land" }
  | .arrayGet _ _ =>
      { nodeTag := "Expr.arrayGet"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "fixed array get rejected until core validator and semantics tasks land" }
  | .memoryArrayNew _ _ =>
      { nodeTag := "Expr.memoryArrayNew"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array allocation rejected until core validator and semantics tasks land" }
  | .memoryArrayLength _ =>
      { nodeTag := "Expr.memoryArrayLength"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array length rejected until core validator and semantics tasks land" }
  | .memoryArrayGet _ _ =>
      { nodeTag := "Expr.memoryArrayGet"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array get rejected until core validator and semantics tasks land" }
  | .structLit _ _ =>
      { nodeTag := "Expr.structLit"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "struct literal rejected until core validator and semantics tasks land" }
  | .field _ _ =>
      { nodeTag := "Expr.field"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "struct field projection rejected until core validator and semantics tasks land" }
  | .add _ _ _ =>
      { nodeTag := "Expr.add"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar addition is in the initial accepted runtime fragment" }
  | .sub _ _ _ =>
      { nodeTag := "Expr.sub"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar subtraction is in the initial accepted runtime fragment" }
  | .mul _ _ _ =>
      { nodeTag := "Expr.mul"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar multiplication is in the initial accepted runtime fragment" }
  | .div _ _ =>
      { nodeTag := "Expr.div"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar division is in the initial accepted runtime fragment" }
  | .mod _ _ =>
      { nodeTag := "Expr.mod"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar modulo is in the initial accepted runtime fragment" }
  | .pow _ _ =>
      { nodeTag := "Expr.pow"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar power is in the initial accepted runtime fragment" }
  | .bitAnd _ _ =>
      { nodeTag := "Expr.bitAnd"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar bitwise and is in the initial accepted runtime fragment" }
  | .bitOr _ _ =>
      { nodeTag := "Expr.bitOr"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar bitwise or is in the initial accepted runtime fragment" }
  | .bitXor _ _ =>
      { nodeTag := "Expr.bitXor"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar bitwise xor is in the initial accepted runtime fragment" }
  | .shiftLeft _ _ =>
      { nodeTag := "Expr.shiftLeft"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar left shift is in the initial accepted runtime fragment" }
  | .shiftRight _ _ =>
      { nodeTag := "Expr.shiftRight"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar right shift is in the initial accepted runtime fragment" }
  | .cast _ _ =>
      { nodeTag := "Expr.cast"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar cast is in the initial accepted runtime fragment" }
  | .eq _ _ =>
      { nodeTag := "Expr.eq"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar equality is in the initial accepted runtime fragment" }
  | .ne _ _ =>
      { nodeTag := "Expr.ne"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar inequality is in the initial accepted runtime fragment" }
  | .lt _ _ =>
      { nodeTag := "Expr.lt"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar less-than is in the initial accepted runtime fragment" }
  | .le _ _ =>
      { nodeTag := "Expr.le"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar less-or-equal is in the initial accepted runtime fragment" }
  | .gt _ _ =>
      { nodeTag := "Expr.gt"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar greater-than is in the initial accepted runtime fragment" }
  | .ge _ _ =>
      { nodeTag := "Expr.ge"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar greater-or-equal is in the initial accepted runtime fragment" }
  | .boolAnd _ _ =>
      { nodeTag := "Expr.boolAnd"
        disposition := .normalize
        owner := "canonical-core"
        reason := "boolean and is in the initial accepted runtime fragment" }
  | .boolOr _ _ =>
      { nodeTag := "Expr.boolOr"
        disposition := .normalize
        owner := "canonical-core"
        reason := "boolean or is in the initial accepted runtime fragment" }
  | .boolNot _ =>
      { nodeTag := "Expr.boolNot"
        disposition := .normalize
        owner := "canonical-core"
        reason := "boolean not is in the initial accepted runtime fragment" }
  | .hashValue _ _ _ _ =>
      { nodeTag := "Expr.hashValue"
        disposition := .materialization
        owner := "target-plan-abi"
        reason := "four-word hash packing materialized to target plan" }
  | .hash _ =>
      { nodeTag := "Expr.hash"
        disposition := .materialization
        owner := "target-plan-abi"
        reason := " cryptographic hash materialized to target plan" }
  | .hashTwoToOne _ _ =>
      { nodeTag := "Expr.hashTwoToOne"
        disposition := .materialization
        owner := "target-plan-abi"
        reason := "two-to-one hash combiner materialized to target plan" }
  | .ecrecover _ _ _ _ =>
      { nodeTag := "Expr.ecrecover"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "EVM secp256k1 ecrecover precompile materialized by EVM adapter" }
  | .eip712PermitDigest _ _ _ _ _ _ =>
      { nodeTag := "Expr.eip712PermitDigest"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "EIP-712 permit digest materialized by EVM adapter" }
  | .nativeValue =>
      { nodeTag := "Expr.nativeValue"
        disposition := .preserve
        owner := "canonical-core"
        reason := "native value reference is in the initial accepted runtime fragment" }
  | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
      { nodeTag := "Expr.crosscallAbiPacked"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "ABI-packed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvoke _ _ _ =>
      { nodeTag := "Expr.crosscallInvoke"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "dynamic crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeTyped _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "typed dynamic crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeValueTyped _ _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeValueTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "value-bearing typed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeStaticTyped _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeStaticTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "static typed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeDelegateTyped _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeDelegateTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "delegate typed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallCreate _ _ =>
      { nodeTag := "Expr.crosscallCreate"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "contract creation rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallCreate2 _ _ _ =>
      { nodeTag := "Expr.crosscallCreate2"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "CREATE2 deployment rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallNamed _ _ _ _ =>
      { nodeTag := "Expr.crosscallNamed"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "named-callee cross-program call rejected until a typed portable primitive or HostOp handler exists" }
  | .nearCrosscallInvokePool _ _ _ _ =>
      { nodeTag := "Expr.nearCrosscallInvokePool"
        disposition := .reject
        owner := "near-adapter"
        reason := "NEAR promise_create crosscall rejected until Task 17" }
  | .nearPromiseThen _ _ _ _ =>
      { nodeTag := "Expr.nearPromiseThen"
        disposition := .reject
        owner := "near-adapter"
        reason := "NEAR promise_then callback rejected until Task 17" }
  | .nearPromiseResultsCount =>
      { nodeTag := "Expr.nearPromiseResultsCount"
        disposition := .reject
        owner := "near-adapter"
        reason := "NEAR promise results count rejected until Task 17" }
  | .nearPromiseResultStatus _ =>
      { nodeTag := "Expr.nearPromiseResultStatus"
        disposition := .reject
        owner := "near-adapter"
        reason := "NEAR promise result status rejected until Task 17" }
  | .nearPromiseResultU64 _ =>
      { nodeTag := "Expr.nearPromiseResultU64"
        disposition := .reject
        owner := "near-adapter"
        reason := "NEAR promise result payload rejected until Task 17" }
  | .effect _ =>
      { nodeTag := "Expr.effect"
        disposition := .normalize
        owner := "canonical-core"
        reason := "effect expression wrapper is in the initial accepted runtime fragment" }

/--! Representative expression for every `Expr` constructor.

Used to build `allDecisions`; the actual sub-expressions/types do not affect the
classification because `classifyExpr` dispatches only on the constructor. -/
def exprInventory : Array Expr := #[
  .literal (Literal.bool false),
  .local "x",
  .arrayLit .u8 #[],
  .arrayGet (.local "a") (.literal (Literal.u32 0)),
  .memoryArrayNew .u8 (.literal (Literal.u32 0)),
  .memoryArrayLength (.local "a"),
  .memoryArrayGet (.local "a") (.literal (Literal.u32 0)),
  .structLit "S" #[],
  .field (.local "s") "f",
  .add (.local "x") (.local "y"),
  .sub (.local "x") (.local "y"),
  .mul (.local "x") (.local "y"),
  .div (.local "x") (.local "y"),
  .mod (.local "x") (.local "y"),
  .pow (.local "x") (.local "y"),
  .bitAnd (.local "x") (.local "y"),
  .bitOr (.local "x") (.local "y"),
  .bitXor (.local "x") (.local "y"),
  .shiftLeft (.local "x") (.local "y"),
  .shiftRight (.local "x") (.local "y"),
  .cast (.local "x") .u64,
  .eq (.local "x") (.local "y"),
  .ne (.local "x") (.local "y"),
  .lt (.local "x") (.local "y"),
  .le (.local "x") (.local "y"),
  .gt (.local "x") (.local "y"),
  .ge (.local "x") (.local "y"),
  .boolAnd (.local "x") (.local "y"),
  .boolOr (.local "x") (.local "y"),
  .boolNot (.local "x"),
  .hashValue (.local "a") (.local "b") (.local "c") (.local "d"),
  .hash (.local "x"),
  .hashTwoToOne (.local "x") (.local "y"),
  .ecrecover (.local "d") (.local "v") (.local "r") (.local "s"),
  .eip712PermitDigest (.local "o") (.local "s") (.local "v") (.local "n") (.local "d") (.local "ds"),
  .nativeValue,
  .crosscallAbiPacked (.local "t") 0 #[] 0 0 none none #[] #[],
  .crosscallInvoke (.local "t") (.local "m") #[],
  .crosscallInvokeTyped (.local "t") (.local "m") #[] .unit,
  .crosscallInvokeValueTyped (.local "t") (.local "m") (.local "v") #[] .unit,
  .crosscallInvokeStaticTyped (.local "t") (.local "m") #[] .unit,
  .crosscallInvokeDelegateTyped (.local "t") (.local "m") #[] .unit,
  .crosscallCreate (.local "v") "",
  .crosscallCreate2 (.local "v") (.local "s") "",
  .crosscallNamed "p" "m" #[] .unit,
  .nearCrosscallInvokePool (.local "i") (.local "m") #[] (.local "d"),
  .nearPromiseThen (.local "p") (.local "c") #[] (.local "d"),
  .nearPromiseResultsCount,
  .nearPromiseResultStatus (.local "i"),
  .nearPromiseResultU64 (.local "i"),
  .effect (Effect.contextRead .userId)
]

/--! Representative effect for every `Effect` constructor. -/
def effectInventory : Array Effect := #[
  .storageScalarRead "s",
  .storageScalarWrite "s" (.local "v"),
  .storageScalarAssignOp "s" .add (.local "v"),
  .storageMapContains "m" (.local "k"),
  .storageMapGet "m" (.local "k"),
  .storageMapInsert "m" (.local "k") (.local "v"),
  .storageMapSet "m" (.local "k") (.local "v"),
  .storageArrayRead "a" (.local "i"),
  .storageArrayWrite "a" (.local "i") (.local "v"),
  .storageArrayStructFieldRead "a" (.local "i") "f",
  .storageArrayStructFieldWrite "a" (.local "i") "f" (.local "v"),
  .storageDynamicArrayPush "a" (.local "v"),
  .storageDynamicArrayPop "a",
  .memoryArraySet (.local "a") (.local "i") (.local "v"),
  .storageStructFieldRead "s" "f",
  .storageStructFieldWrite "s" "f" (.local "v"),
  .storagePathRead "s" #[],
  .storagePathWrite "s" #[] (.local "v"),
  .storagePathAssignOp "s" #[] .add (.local "v"),
  .contextRead .userId,
  .eventEmit "E" #[],
  .eventEmitIndexed "E" #[] #[],
  .checkErc721Received (.local "o") (.local "f") (.local "t") (.local "i"),
  .checkErc1155Received (.local "o") (.local "f") (.local "t") (.local "i") (.local "a"),
  .checkErc1155BatchReceived (.local "o") (.local "f") (.local "t") (.local "i0") (.local "a0") (.local "i1") (.local "a1")
]

/--! Representative statement for every `Statement` constructor. -/
def statementInventory : Array Statement := #[
  .letBind "x" .u64 (.local "v"),
  .letMutBind "x" .u64 (.local "v"),
  .assign (.local "x") (.local "v"),
  .assignOp (.local "x") .add (.local "v"),
  .effect (Effect.contextRead .userId),
  .assert (.local "c") "msg",
  .assertEq (.local "x") (.local "y") "msg",
  .revert,
  .revertWithError { assertionId := 0 },
  .release "x",
  .ifElse (.local "c") #[] #[],
  .boundedFor "i" 0 1 #[],
  .whileLoop (.local "c") #[],
  .return (.local "x")
]

/--! All constructor decisions.

Every current `Expr`, `Effect`, and `Statement` constructor appears exactly once. -/
def allDecisions : Array LegacyDecision :=
  exprInventory.map classifyExpr ++
  effectInventory.map classifyEffect ++
  statementInventory.map classifyStatement

/--! All node tags extracted from `allDecisions`. -/
def allNodeTags : Array String :=
  allDecisions.map (·.nodeTag)

/--! Decisions for every `ContractSpec` field. -/
def contractSpecFieldDecisions : Array LegacySpecFieldDecision := #[
  { field := "name"
    disposition := .preserve
    owner := "canonical-core"
    reason := "contract name metadata preserved by canonical core" },
  { field := "module"
    disposition := .preserve
    owner := "canonical-core"
    reason := "IR module preserved by canonical core" },
  { field := "intents"
    disposition := .materialization
    owner := "target-plan"
    reason := "intents materialized to target plan" },
  { field := "upgradePolicy?"
    disposition := .materialization
    owner := "evm-adapter"
    reason := "upgrade policy materialized by EVM adapter" },
  { field := "proxyPattern?"
    disposition := .materialization
    owner := "evm-adapter"
    reason := "proxy pattern materialized by EVM adapter" },
  { field := "constructorParams"
    disposition := .materialization
    owner := "evm-adapter"
    reason := "constructor parameters materialized by EVM adapter" },
  { field := "constructorInitBindings"
    disposition := .materialization
    owner := "evm-adapter"
    reason := "constructor init bindings materialized by EVM adapter" },
  { field := "quintInvariants"
    disposition := .evidence
    owner := "fv-quint"
    reason := "Quint invariants are verification evidence" },
  { field := "quintLiveness"
    disposition := .evidence
    owner := "fv-quint"
    reason := "Quint liveness properties are verification evidence" },
  { field := "leanInvariants"
    disposition := .evidence
    owner := "fv-lean"
    reason := "Lean invariants are verification evidence" }
]

/--! Classify the fields of a `ContractSpec`.

The classification depends only on the field schema, not on the concrete spec
values, so the argument is ignored. -/
def classifySpecFields (_spec : ProofForge.Contract.ContractSpec) : Array LegacySpecFieldDecision :=
  contractSpecFieldDecisions

end ProofForge.IR.Legacy
