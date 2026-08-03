---
id: SPEC-SEM-WIRE-001
title: SemanticProgramV1 Canonical Model、Wire 与 Proof Subject
status: proposed
owner: semantics
updated: 2026-07-16
normative: true
---

# SemanticProgramV1 Canonical Model、Wire 与 Proof Subject

## 1. 范围、authority 与版本边界

本规格是 `SemanticProgramV1`、`LogicalStateV1`、`pf.semantic.v1` binary wire、严格 decoder、
proof subject 和 invariant proof ABI executable boundary 的唯一字段与 byte authority。
`SPEC-SEM-001` 继续拥有通用 reference semantics、transaction/effect/rollback 语义；
`SPEC-TYPE-001` 拥有 source type/effect/disclosure rules；`SPEC-CAP-001` 拥有 requirement key、
predicate merge 和 support resolution；`SPEC-COMMON-001` 拥有公共 scalar 的值域。本文件把这些
结果冻结为一个可以由 Lean、独立 reference encoder 和 proof-bundle builder 逐 byte 重建的 v1
closed value。source/provenance 另由本文件的 `SemanticProvenanceV1` companion envelope 携带，不进入
业务 semantic bytes。

schema ID 固定为 `proof-forge.semantic-program.v1`，binary domain/magic 固定为 ASCII
`pf.semantic.v1`。companion schema ID 固定为 `proof-forge.semantic-provenance.v1`，binary
domain/magic 固定为 ASCII `pf.semantic-provenance.v1`。任何 constructor、ordered field、tag、
canonical order、value encoding、decoder
acceptance 或 evaluator observable behavior 的变化都必须发布新的 schema/domain；v1 decoder 不得
通过 unknown-field skip、best effort、默认补字段或 implicit migration 接受它。

`SemanticProgramV1` 不包含 `sourceHash`、`SourceOrigin`、origin map、source path/span，也不包含
`TargetId`、`CodegenProfileId`、`NetworkProfileId`、ABI selector、storage slot、
account meta、Wasm import、circuit opcode、deploy address 或 proof result。proof reference/bundle identity
也不进入本模型。`ProgramRequirementsV1` 的业务 request key/predicate 是 normalization 的最终输出
之一，在 v1 中作为 `SemanticProgramDataV1.requirements` 的必需字段进入 canonical bytes；requirement
inference、predicate merge 和 canonical sort 必须在 semantic serialization、`semanticHash` 以及 proof
validation 之前完成，之后不得追加、删除或改写 requirement。requirement 的 source origins 与其他
origin 一样只进入 `SemanticProvenanceV1`，由 requirement index exact join。

## 2. 完整 Lean data model

`SemanticProgramV1`、`SemanticProgramDataV1`、provenance、所有 table/wire type、strict codec 与
validator 的 owning module 固定为 `ProofForgeV2.Semantic.WireV1`。`InvariantOrdinalV1`、
`LogicalStateV1`、`InvariantEvalResultV1`、`StateConformsV1`、`evalInvariantV1` 和
`InvariantTheoremV1` 的唯一 public owning module/namespace固定为
`ProofForgeV2.Semantic.InvariantABI`。为保持formal evaluator到reference machine的acyclic依赖，
`InvariantOrdinalV1`、`LogicalStateV1`、`InvariantEvalResultV1`与StateConforms所需codec/defaults可由
lower `ProofForgeV2.Semantic.InvariantFoundationV1`在exact
`ProofForgeV2.Semantic.InvariantABI` namespace下物理定义；public `InvariantABI` façade必须import该
foundation并直接定义后续`evalInvariantV1`/`InvariantTheoremV1`，不得建立alias/wrapper或第二份
definition。ProofBundle manifest的module/theorem identity与public ABI `.olean` digest仍绑定
`InvariantABI`；trusted `.olean` closure必须exact包含其全部transitive依赖——当前含
`InvariantFoundationV1`，在formal evaluator引入后也必须含`ReferenceMachineV1`。

下列定义中的 `Digest`、`SemVer`、`SchemaId`、
`QualifiedName`、`ProjectRelativePath`、`NodeId` 和 `SourceOrigin` 精确使用
`ProofForgeV2.Common`/`SPEC-COMMON-001`；`ByteArray`、`Array`、`Option`、`Bool`、`UInt8`、
`UInt16`、`UInt32`、`UInt64` 是 Lean 4 类型。除这些列明的 common primitive 外，不存在未定义的
外部 carrier。provenance validator 的 `Source.ProgramV1` 精确使用
`SPEC-SOURCE-WIRE-001`/`ProofForgeV2.Source.WireV1` 的 production decoder 结果。

```lean
abbrev TypeIdV1      := UInt32
abbrev ConstantIdV1  := UInt32
abbrev StateIdV1     := UInt32
abbrev EventIdV1     := UInt32
abbrev ErrorIdV1     := UInt32
abbrev CallableIdV1  := UInt32
abbrev BlockIdV1     := UInt32
abbrev ValueIdV1     := UInt32
abbrev EffectIdV1    := UInt32
abbrev InvariantIdV1 := UInt32

structure EffectOccurrenceV1 where
  effectId   : EffectIdV1
  occurrence : UInt32

-- Transient trusted frontend validation context; it is not semantic/provenance wire.
structure SourceNodeInventoryV1 where
  sourceHash : Digest
  nodes      : Array SourceOrigin

inductive VisibilityV1
  | public | private_ | commitment

structure FieldSpecV1 where
  id        : SchemaId
  modulusBE : ByteArray

structure StructFieldV1 where
  name   : String
  typeId : TypeIdV1

structure EnumVariantV1 where
  name         : String
  payloadTypes : Array TypeIdV1

inductive TypeShapeV1
  | bool
  | uint      (width : UInt16)
  | int       (width : UInt16)
  | principal
  | unit
  | bytes     (length : UInt32)
  | array     (element : TypeIdV1) (length : UInt32)
  | map       (key : TypeIdV1) (value : TypeIdV1)
  | option    (element : TypeIdV1)
  | field     (spec : FieldSpecV1)
  | struct    (fields : Array StructFieldV1)
  | enum      (variants : Array EnumVariantV1)

structure TypeDeclV1 where
  id    : TypeIdV1
  name  : Option String
  shape : TypeShapeV1

structure ConstantV1 where
  id         : ConstantIdV1
  name       : String
  typeId     : TypeIdV1
  valueBytes : ByteArray

structure StateDeclV1 where
  id         : StateIdV1
  name       : String
  typeId     : TypeIdV1
  visibility : VisibilityV1

structure InterfaceFieldV1 where
  name       : String
  typeId     : TypeIdV1
  visibility : VisibilityV1

structure EventDeclV1 where
  id     : EventIdV1
  name   : String
  fields : Array InterfaceFieldV1

structure ErrorDeclV1 where
  id     : ErrorIdV1
  name   : String
  fields : Array InterfaceFieldV1

inductive CallableKindV1
  | initializer | entry | view | pureFn | invariant

structure ParameterV1 where
  valueId    : ValueIdV1
  name       : String
  typeId     : TypeIdV1
  visibility : VisibilityV1

structure CallableResultV1 where
  typeId     : TypeIdV1
  visibility : VisibilityV1

structure ValueDefV1 where
  valueId : ValueIdV1
  typeId  : TypeIdV1

structure BlockParameterV1 where
  valueId : ValueIdV1
  typeId  : TypeIdV1

inductive UnaryOpV1
  | neg | not | bitNot

inductive BinaryOpV1
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or | bitAnd | bitOr | bitXor | shl | shr

inductive SemanticOpV1
  | literal      (typeId : TypeIdV1) (valueBytes : ByteArray)
  | constant     (constantId : ConstantIdV1)
  | stateLoad    (stateId : StateIdV1)
  | stateStore   (stateId : StateIdV1) (value : ValueIdV1)
  | construct    (typeId : TypeIdV1) (constructorIndex : UInt32)
                   (args : Array ValueIdV1)
  | fieldGet     (base : ValueIdV1) (fieldIndex : UInt32)
  | fieldSet     (base : ValueIdV1) (fieldIndex : UInt32) (value : ValueIdV1)
  | variantTag   (base : ValueIdV1)
  | variantPayload (base : ValueIdV1) (variantIndex payloadIndex : UInt32)
  | indexGet     (base : ValueIdV1) (index : ValueIdV1)
  | indexSet     (base : ValueIdV1) (index : ValueIdV1) (value : ValueIdV1)
  | checkedCast  (value : ValueIdV1) (toType : TypeIdV1)
  | unary        (op : UnaryOpV1) (operand : ValueIdV1)
  | binary       (op : BinaryOpV1) (lhs : ValueIdV1) (rhs : ValueIdV1)
  | pureCall     (callableId : CallableIdV1) (args : Array ValueIdV1)
  | contextRead  (key : SchemaId)
  | commit       (value : ValueIdV1)
  | assert_      (condition : ValueIdV1) (errorId : Option ErrorIdV1)
                   (args : Array ValueIdV1)
  | emit         (effectId : EffectIdV1) (eventId : EventIdV1)
                   (args : Array ValueIdV1)
  | externalCall (effectId : EffectIdV1) (callee : QualifiedName)
                   (args : Array ValueIdV1)
  | schedule     (effectId : EffectIdV1) (callee : QualifiedName)
                   (args : Array ValueIdV1)

structure InstructionV1 where
  result : Option ValueDefV1
  op     : SemanticOpV1

structure JumpTargetV1 where
  blockId : BlockIdV1
  args    : Array ValueIdV1

structure SwitchCaseV1 where
  typeId     : TypeIdV1
  valueBytes : ByteArray
  target     : JumpTargetV1

inductive SemanticTrapCodeV1
  | unreachable | invalidExternalResponse | resourceExhausted | internalInvariant

inductive TerminatorV1
  | jump   (target : JumpTargetV1)
  | branch (condition : ValueIdV1) (thenTarget elseTarget : JumpTargetV1)
  | switch (scrutinee : ValueIdV1) (cases : Array SwitchCaseV1)
             (defaultTarget : Option JumpTargetV1)
  | return_ (value : Option ValueIdV1)
  | revert  (errorId : ErrorIdV1) (args : Array ValueIdV1)
  | trap    (code : SemanticTrapCodeV1)

structure BlockV1 where
  id           : BlockIdV1
  params       : Array BlockParameterV1
  instructions : Array InstructionV1
  terminator   : TerminatorV1

structure LoopBoundV1 where
  header        : BlockIdV1
  backEdgeFrom  : BlockIdV1
  maxIterations : UInt32

structure CallableV1 where
  id              : CallableIdV1
  kind            : CallableKindV1
  name            : Option String
  params          : Array ParameterV1
  result          : CallableResultV1
  entryBlock      : BlockIdV1
  blocks          : Array BlockV1
  loopBounds      : Array LoopBoundV1
  invariantSteps  : Option UInt64

structure InvariantDeclV1 where
  id         : InvariantIdV1
  name       : String
  callableId : CallableIdV1

inductive RequirementPredicateV1
  | uintAtLeast  (name : String) (value : UInt64)
  | uintAtMost   (name : String) (value : UInt64)
  | boolEquals   (name : String) (value : Bool)
  | enumContains (name : String) (values : Array String)
  | digestEquals (name : String) (value : Digest)

structure RequirementRequestV1 where
  id         : String
  version    : SemVer
  digest     : Digest
  predicates : Array RequirementPredicateV1

structure ProgramRequirementsV1 where
  items : Array RequirementRequestV1

inductive SemanticEntityRefV1
  | type       (id : TypeIdV1)
  | constant   (id : ConstantIdV1)
  | state      (id : StateIdV1)
  | event      (id : EventIdV1)
  | error      (id : ErrorIdV1)
  | callable   (id : CallableIdV1)
  | block      (callableId : CallableIdV1) (blockId : BlockIdV1)
  | instruction (callableId : CallableIdV1) (blockId : BlockIdV1)
                  (instructionIndex : UInt32)
  | terminator (callableId : CallableIdV1) (blockId : BlockIdV1)
  | value      (callableId : CallableIdV1) (valueId : ValueIdV1)
  | effect     (callableId : CallableIdV1) (effectId : EffectIdV1)
  | invariant  (id : InvariantIdV1)
  | requirement (index : UInt32)

structure OriginBindingV1 where
  entity  : SemanticEntityRefV1
  origins : Array SourceOrigin

structure SemanticProgramDataV1 where
  qualifiedName : QualifiedName
  types        : Array TypeDeclV1
  constants    : Array ConstantV1
  logicalState : Array StateDeclV1
  events       : Array EventDeclV1
  errors       : Array ErrorDeclV1
  callables    : Array CallableV1
  invariants   : Array InvariantDeclV1
  requirements : ProgramRequirementsV1

structure SemanticProvenanceV1 where
  schema        : SchemaId
  qualifiedName : QualifiedName
  sourceHash    : Digest
  semanticHash  : Digest
  originMap     : Array OriginBindingV1

inductive SemanticWireErrorV1
  | truncated | limitExceeded | badMagic | badTag | badFieldCount
  | badScalar | nonCanonical | duplicate | badReference | badType
  | badCfg | badRequirement | badProvenance | trailingBytes

structure SemanticProgramV1 where
  canonicalBytes : ByteArray

-- The declarations from this point through InvariantEvalResultV1 are owned by
-- ProofForgeV2.Semantic.InvariantABI; all preceding declarations are WireV1.
abbrev InvariantOrdinalV1 := UInt32

structure LogicalStateV1 where
  initialized     : Bool
  canonicalValues : ByteArray

inductive InvariantEvalResultV1
  | returnedTrue | returnedFalse | reverted | trapped
```

`SemanticProgramV1` 故意是单字段 byte carrier：compiler 与独立 proof builder 只要嵌入相同
canonical bytes，就构造 definitionally equal 的 closed Lean value；不依赖 serializer theorem、hash
相等、propositional cast 或运行时文件。该 public constructor 不是绕过 validation 的入口：所有
compiler/loader API 只接受 `decodeSemanticProgramV1` 成功的 carrier，invalid carrier 的 projection
为空且 `StateConformsV1` 为 false、`evalInvariantV1` 为 `.trapped`。

实现必须提供以下 total API；不得使用 `partial`、`unsafe`、`IO`、environment lookup 或 target
dispatch：

```lean
def encodeSemanticProgramDataV1
    (p : SemanticProgramDataV1) : Except SemanticWireErrorV1 ByteArray
def decodeSemanticProgramDataV1
    (bytes : ByteArray) : Except SemanticWireErrorV1 SemanticProgramDataV1
def decodeSemanticProgramV1
    (bytes : ByteArray) : Except SemanticWireErrorV1 SemanticProgramV1
def validateSemanticProgramV1
    (p : SemanticProgramV1) : Except SemanticWireErrorV1 SemanticProgramDataV1
def semanticHashV1
    (p : SemanticProgramV1) : Except SemanticWireErrorV1 Digest
def SemanticProgramV1.invariants (p : SemanticProgramV1) : Array InvariantDeclV1
def encodeSemanticProvenanceV1
    (sourceModule : QualifiedName)
    (sourceIdentity : QualifiedName)
    (source : Source.ProgramV1)
    (nodeInventory : SourceNodeInventoryV1)
    (program : SemanticProgramV1)
    (p : SemanticProvenanceV1) : Except SemanticWireErrorV1 ByteArray
def decodeSemanticProvenanceV1
    (bytes : ByteArray) : Except SemanticWireErrorV1 SemanticProvenanceV1
def semanticProvenanceDigestV1
    (sourceModule : QualifiedName)
    (sourceIdentity : QualifiedName)
    (source : Source.ProgramV1)
    (nodeInventory : SourceNodeInventoryV1)
    (program : SemanticProgramV1)
    (p : SemanticProvenanceV1) : Except SemanticWireErrorV1 Digest
def validateSemanticProvenanceV1
    (sourceModule : QualifiedName)
    (sourceIdentity : QualifiedName)
    (source : Source.ProgramV1)
    (nodeInventory : SourceNodeInventoryV1)
    (program : SemanticProgramV1)
    (provenance : SemanticProvenanceV1) : Except SemanticWireErrorV1 Unit
```

`decodeSemanticProgramV1 bytes` 仅在 data decoder 成功且重新编码逐 byte 等于原 bytes 时返回
`⟨bytes⟩`。`validateSemanticProgramV1` 做同一检查。`semanticHashV1` 只允许用于已验证 carrier，值为
`SHA-256(p.canonicalBytes)`；invalid carrier 返回 error，不得获得 typed hash。dot projection `invariants` 在
validation 成功时返回 decoded array，失败返回 `#[]`，从而现有 ABI 中
`program.invariants.size` 仍是 total expression。

`validateSemanticProvenanceV1` 用给定 source module/identity/program 重算 canonical sourceHash，要求
provenance schema、qualifiedName、sourceHash、重新计算的 semanticHash、entity coverage/order 和
requirement-index join 全部 exact；随后把每个 SourceOrigin 的 path/span/NodeId 与同一次 production
NodeId assignment 与 frontend span capture 得到的 `nodeInventory` 做 exact membership。它不把
provenance 合并回 program；
proof builder 不把 provenance origin 当作 theorem premise。
`nodeInventory.sourceHash` 必须等于本次 source snapshot 的重算 hash；inventory producer 在进入该
total API 前已经完成 no-follow safe-open、path-set casefold uniqueness 和每个 origin
`endByte <= immutable file byte length`。本 API 只验证 inventory/source/provenance 的 closed joins，
不重复打开 path，也不把 filesystem 状态伪装成 `ProjectRelativePath` scalar 属性。
`decodeSemanticProvenanceV1` 先验证 magic/scalar/order并要求内部 canonical re-encode 逐 byte相等；
entity range/coverage
只能在给定 source/program 后由 `validateSemanticProvenanceV1` 检查。`semanticProvenanceDigestV1` 内部先
执行该 join validation，只对通过两级检查的 canonical bytes 返回 SHA-256。

## 3. Scalar binary encoding 与资源限制

所有整数 little-endian。decoder 必须在分配前验证长度和剩余 bytes，使用 checked `UInt64` 累加，
不得整数 wraparound、unbounded recursion 或先分配后检查。compiler-core effective resource profile
可以进一步降低但不能提高以下 hard limit：canonical program 64 MiB、array 1,000,000 elements、
types/state/constants/events/errors/callables/invariants 各 100,000、blocks/instructions/values/effects
每 callable 各 1,000,000、nesting 256、NFC string 1 MiB、canonical value 16 MiB、Map entries
1,000,000。canonical provenance 同样 64 MiB、origin bindings 1,000,000、单 binding origins 100,000。
下表 `concat(sequence)` 表示括号内按列出顺序组成的有限 byte sequence 无间隔串接。

| Value | Exact binary encoding |
|---|---|
| `UInt8` | one byte |
| `UInt16` | 2-byte little-endian |
| `UInt32` / every `*IdV1` | 4-byte little-endian |
| `UInt64` | 8-byte little-endian |
| `Bool` | `00=false`, `01=true`; other byte rejected |
| `Option<T>` | `00` or `concat(01,encode(T))`; other marker rejected |
| `Array<T>` | `concat(u32le count,encode(elements in order))` |
| `ByteArray` | `concat(u32le byteLength,raw bytes)` |
| `String` | `concat(u32le byteLength,NFC UTF-8)`; invalid UTF-8/non-NFC rejected |
| `QualifiedName` | nonempty `Array<String>`，每项还通过 common identifier rule |
| `SchemaId` | `String` 后通过 common lowercase dotted grammar |
| `SemVer` | canonical SemVer ASCII 作为 `String`；alternate spelling rejected |
| `Digest` | 32 raw SHA-256 bytes；不编码 algorithm/string prefix |
| `ProjectRelativePath` | `String` 后通过 common path rule |
| `NodeId` | exactly 16 raw bytes |
| `SourceOrigin` | `ProjectRelativePath,startByte:UInt64,endByte:UInt64,NodeId`，无 outer tag |

每个 tagged value 编码为：

```text
u32le(tag ASCII byte length) || tag ASCII || u16le(fieldCount) ||
concat(i from 0 through fieldCount-1, encode(field[i]))
```

tag 大小写敏感；field name 不写入 bytes。`fieldCount` 必须与下表 exact 相等，nullary tag 仍写
`u16le(0)`。unknown tag/count、缺失/额外字段和 root trailing byte 一律拒绝。

## 4. Record、sum 与 ordered-field wire table

### 4.1 Root 与 records

canonical root 唯一为：

```text
canonicalSemanticProgramBytesV1 =
  ASCII("pf.semantic.v1") || 0x00 || encodeTagged(SemanticProgram.Data)
```

companion provenance root 唯一为：

```text
canonicalSemanticProvenanceBytesV1 =
  ASCII("pf.semantic-provenance.v1") || 0x00 ||
  encodeTagged(SemanticProvenance.Data)

semanticProvenanceDigestV1 = SHA-256(canonicalSemanticProvenanceBytesV1)
```

| Tag | Count | Ordered fields |
|---|---:|---|
| `SemanticProgram.Data` | 9 | `qualifiedName,types,constants,logicalState,events,errors,callables,invariants,requirements` |
| `SemanticProvenance.Data` | 5 | `schema,qualifiedName,sourceHash,semanticHash,originMap` |
| `FieldSpec` | 2 | `id,modulusBE` |
| `StructField` | 2 | `name,typeId` |
| `EnumVariant` | 2 | `name,payloadTypes` |
| `TypeDecl` | 3 | `id,name,shape` |
| `Constant` | 4 | `id,name,typeId,valueBytes` |
| `StateDecl` | 4 | `id,name,typeId,visibility` |
| `InterfaceField` | 3 | `name,typeId,visibility` |
| `EventDecl` | 3 | `id,name,fields` |
| `ErrorDecl` | 3 | `id,name,fields` |
| `Parameter` | 4 | `valueId,name,typeId,visibility` |
| `CallableResult` | 2 | `typeId,visibility` |
| `ValueDef` | 2 | `valueId,typeId` |
| `BlockParameter` | 2 | `valueId,typeId` |
| `Instruction` | 2 | `result,op` |
| `JumpTarget` | 2 | `blockId,args` |
| `SwitchCase` | 3 | `typeId,valueBytes,target` |
| `Block` | 4 | `id,params,instructions,terminator` |
| `LoopBound` | 3 | `header,backEdgeFrom,maxIterations` |
| `Callable` | 9 | `id,kind,name,params,result,entryBlock,blocks,loopBounds,invariantSteps` |
| `InvariantDecl` | 3 | `id,name,callableId` |
| `RequirementRequest` | 4 | `id,version,digest,predicates` |
| `ProgramRequirements` | 1 | `items` |
| `OriginBinding` | 2 | `entity,origins` |

### 4.2 Type、visibility、callable 与 operator tags

| Tag | Count | Ordered fields |
|---|---:|---|
| `Visibility.Public` | 0 | — |
| `Visibility.Private` | 0 | — |
| `Visibility.Commitment` | 0 | — |
| `Type.Bool` | 0 | — |
| `Type.UInt` | 1 | `width` |
| `Type.Int` | 1 | `width` |
| `Type.Principal` | 0 | — |
| `Type.Unit` | 0 | — |
| `Type.Bytes` | 1 | `length` |
| `Type.Array` | 2 | `element,length` |
| `Type.Map` | 2 | `key,value` |
| `Type.Option` | 1 | `element` |
| `Type.Field` | 1 | `spec` |
| `Type.Struct` | 1 | `fields` |
| `Type.Enum` | 1 | `variants` |
| `Callable.Initializer` | 0 | — |
| `Callable.Entry` | 0 | — |
| `Callable.View` | 0 | — |
| `Callable.PureFn` | 0 | — |
| `Callable.Invariant` | 0 | — |
| `Unary.Neg` | 0 | — |
| `Unary.Not` | 0 | — |
| `Unary.BitNot` | 0 | — |
| `Binary.Add` | 0 | — |
| `Binary.Sub` | 0 | — |
| `Binary.Mul` | 0 | — |
| `Binary.Div` | 0 | — |
| `Binary.Mod` | 0 | — |
| `Binary.Eq` | 0 | — |
| `Binary.Ne` | 0 | — |
| `Binary.Lt` | 0 | — |
| `Binary.Le` | 0 | — |
| `Binary.Gt` | 0 | — |
| `Binary.Ge` | 0 | — |
| `Binary.And` | 0 | — |
| `Binary.Or` | 0 | — |
| `Binary.BitAnd` | 0 | — |
| `Binary.BitOr` | 0 | — |
| `Binary.BitXor` | 0 | — |
| `Binary.Shl` | 0 | — |
| `Binary.Shr` | 0 | — |

### 4.3 Semantic operation tags

| Tag | Count | Ordered fields |
|---|---:|---|
| `Op.Literal` | 2 | `typeId,valueBytes` |
| `Op.Constant` | 1 | `constantId` |
| `Op.StateLoad` | 1 | `stateId` |
| `Op.StateStore` | 2 | `stateId,value` |
| `Op.Construct` | 3 | `typeId,constructorIndex,args` |
| `Op.FieldGet` | 2 | `base,fieldIndex` |
| `Op.FieldSet` | 3 | `base,fieldIndex,value` |
| `Op.VariantTag` | 1 | `base` |
| `Op.VariantPayload` | 3 | `base,variantIndex,payloadIndex` |
| `Op.IndexGet` | 2 | `base,index` |
| `Op.IndexSet` | 3 | `base,index,value` |
| `Op.CheckedCast` | 2 | `value,toType` |
| `Op.Unary` | 2 | `op,operand` |
| `Op.Binary` | 3 | `op,lhs,rhs` |
| `Op.PureCall` | 2 | `callableId,args` |
| `Op.ContextRead` | 1 | `key` |
| `Op.Commit` | 1 | `value` |
| `Op.Assert` | 3 | `condition,errorId,args` |
| `Op.Emit` | 3 | `effectId,eventId,args` |
| `Op.ExternalCall` | 3 | `effectId,callee,args` |
| `Op.Schedule` | 3 | `effectId,callee,args` |

`Instruction.result` 必须为：产生 value 的 `Literal/Constant/StateLoad/Construct/FieldGet/FieldSet/`
`VariantTag/VariantPayload/IndexGet/IndexSet/CheckedCast/Unary/Binary/PureCall/ContextRead/Commit` 恰有一个 result；
`StateStore/Assert/Emit/ExternalCall/Schedule` 必须为 `none`。v1 external call 是 statement effect，
没有隐式 return value；将来增加 typed return 是 schema 变化。

### 4.4 Terminator、trap 与 entity tags

| Tag | Count | Ordered fields |
|---|---:|---|
| `Term.Jump` | 1 | `target` |
| `Term.Branch` | 3 | `condition,thenTarget,elseTarget` |
| `Term.Switch` | 3 | `scrutinee,cases,defaultTarget` |
| `Term.Return` | 1 | `value` |
| `Term.Revert` | 2 | `errorId,args` |
| `Term.Trap` | 1 | `code` |
| `Trap.Unreachable` | 0 | — |
| `Trap.InvalidExternalResponse` | 0 | — |
| `Trap.ResourceExhausted` | 0 | — |
| `Trap.InternalInvariant` | 0 | — |
| `Entity.Type` | 1 | `id` |
| `Entity.Constant` | 1 | `id` |
| `Entity.State` | 1 | `id` |
| `Entity.Event` | 1 | `id` |
| `Entity.Error` | 1 | `id` |
| `Entity.Callable` | 1 | `id` |
| `Entity.Block` | 2 | `callableId,blockId` |
| `Entity.Instruction` | 3 | `callableId,blockId,instructionIndex` |
| `Entity.Terminator` | 2 | `callableId,blockId` |
| `Entity.Value` | 2 | `callableId,valueId` |
| `Entity.Effect` | 2 | `callableId,effectId` |
| `Entity.Invariant` | 1 | `id` |
| `Entity.Requirement` | 1 | `index` |

### 4.5 Requirement predicate tags

| Tag | Count | Ordered fields |
|---|---:|---|
| `Req.UintAtLeast` | 2 | `name,value` |
| `Req.UintAtMost` | 2 | `name,value` |
| `Req.BoolEquals` | 2 | `name,value` |
| `Req.EnumContains` | 2 | `name,values` |
| `Req.DigestEquals` | 2 | `name,value` |

Requirement ID/version/digest、predicate merge 和 comparison 精确遵守 `SPEC-CAP-001`。ID 第一段只
允许 `value`、`control`、`state`、`effect`、`context`、`disclosure`、`authority`、
`state-custody`、`failure`、`extension`。`predicates` 按
`(name UTF-8, variant rank, full tagged bytes)` 唯一升序；rank 依次为上表 0..4，
`EnumContains.values` nonempty，按 NFC UTF-8 唯一升序。`ProgramRequirements.items` 按
`(id UTF-8, canonical SemVer UTF-8, digest raw bytes)` 唯一升序；相同 key 必须先完成 predicate/origin
merge，其中 predicate merge 的业务结果进入 program，origin merge 的结果进入 companion provenance；
不能在任一 wire 中出现第二项。zero requirements 合法。

`RequirementRequestV1` 只是 `SPEC-CAP-001 RequirementRef` 的 binary carrier，不是第二套 requirement
schema：`id,version,digest,predicates` 的值域、variant rank、merge、conflict 和 equality 一一相同，且
两者都没有 origins。`RequirementPredicateV1` 五个 constructor 与 `SupportPredicate` 五个 constructor
逐项同构；decoder 必须无损构造 `RequirementRef`，resolver 直接消费该值，禁止 rename、default、
predicate drop/reorder 或再次 inference。origin 只能按相同 requirement index在 provenance 中供
diagnostic/audit 使用。

## 5. Canonical type/value encoding

`TypeDeclV1.id` 必须等于其 `types` array index。named Struct fields 与 Enum variants 都必须 nonempty，
与 Source.Program 的 `FieldDecl+`/variant `+` exact 对应。TypeId 不使用 host map iteration 或
“第一次碰到”分配；v1 使用以下完整 type-closure algorithm：

1. 按 canonical Source.Program 的 named struct/enum declaration order 先保留连续 ID
   `0 .. namedCount-1`。所有 named reference 的 symbolic key 是 `named(reservedId)`，因此递归 body
   在解析前已经有稳定 anchor。
2. normalizer 在分配其余 ID 前先构造完整 symbolic Semantic Core；每个 type slot 保存下述
   `TypeKeyV1`，包括 declaration/state/event/error/callable/block/value/constant/switch type，以及按
   第 5.1 节 op contract 合成的 Bool、UInt8、UInt32、`Option V` 与其他 result type。不存在分配 ID 后
   才推导的 hidden type。
3. closure root 是每个 named body 的 field/payload type 和 symbolic Core 中每个 type slot；递归加入
   所有 anonymous child key，按 exact key bytes 去重。anonymous cycle 非法；递归 cycle 必须同时
   穿过 `Option` 和一个 reserved named key，从而 key expansion total。
4. 将全部 anonymous key 按 unsigned lexicographic raw bytes 唯一升序，rank `i` 的 ID 固定为
   `namedCount + i`；child 可引用排序后位于其前或后的 ID。最后才把 symbolic key 替换为 TypeId，
   materialize `types = named declarations ++ sorted anonymous declarations`。
5. decoder 必须从 named prefix、全部 type usage 和 anonymous declarations 重建同一 closure/key order；
   missing、duplicate、wrong-rank 或未被 named body/Core/另一 required anonymous type 传递引用的匿名
   declaration 都是 `nonCanonical`。同 shape 只能有一个匿名 ID；两个同 shape 的 named declarations
   仍保持不同 reserved identity。

`TypeKeyV1` 的 byte form 独立于最终 TypeId：

```text
typeKey(tag, fields) =
  u16le(ASCII(tag).size) || ASCII(tag) || u32le(fields.size) ||
  concat(for field in fields: u32le(field.size) || field)
nameBytes(name) = u32le(NFC_UTF8(name).size) || NFC_UTF8(name)
```

closure/top-level tag 只允许 `named|bool|uint|int|principal|unit|bytes|array|map|option|field|struct|enum`；
nested record helper 另只允许 `struct-field|enum-variant`。
`named` field 是 reserved ID 的 u32le；width 使用 u16le，length 使用 u32le；array/map/option 的
child field 是完整 nested typeKey。field fields 是 `(SchemaId encoded String, modulusBE)`；struct 的
单项 field 是 `typeKey("struct-field",[nameBytes,childKey])`，enum 的单项 variant 是
`typeKey("enum-variant",[nameBytes,concat(u32le(count),length-prefixed payloadKeys)])`，随后分别作为
struct/enum 的 ordered fields。`struct-field`/`enum-variant` 只能出现在父 key 内，不能成为 closure
declaration tag。以上 framing、source field/variant order 与 exact nested keys 共同构成 structural
equality；禁止用 pretty type name、hash、locale sort 或 final TypeId 作为 anonymous sort key。

named type 的 `name=some`，其 shape 只能是 struct/enum；其他 type 的 `name=none`。所有 type
reference 必须存在；integer width 只允许 `8,16,32,64,128,256`；Bytes/Array length `<=4096`。
Map key type 只允许 Bool、UInt、Int、Principal、Bytes 和递归只含这些合法 key 的 Struct。decoder/value
reader 的 nesting fuel 固定为 256。

v1 Field catalog 只有一个 exact entry；decoder 不访问 ambient registry：

```text
id        = proof-forge.field.bn254-fr.v1
modulusBE = 30 64 4e 72 e1 31 a0 29 b8 50 45 b6 81 81 58 5d
            28 33 e8 48 79 b9 70 91 43 e1 f5 93 f0 00 00 01
```

SPEC-LANG-001 的唯一 Phase 1 source spelling `Field bn254_fr` 必须在 target-neutral D2
normalization 中映射到该 entry；该 alias 本身不进入 SemanticProgram bytes，target/profile/extension
不得替换 modulus 或选择另一 entry。

`FieldSpecV1` 必须逐 byte 等于该 entry，同一 program 内重复 field shape 由 type structural interning
消除。unknown ID、alternate modulus、leading zero、short/long encoding 都拒绝。增加其他 prime field
需要新 semantic schema/domain，不能在 v1 动态查 target/extension registry。

`valueBytes` 不是 arbitrary payload。给定 resolved `TypeIdV1`，canonical value 编码唯一为：

| Shape | Exact value bytes |
|---|---|
| Bool | one byte `00` or `01` |
| UInt N | exactly `N/8` little-endian unsigned bytes |
| Int N | exactly `N/8` little-endian two's-complement bytes |
| Principal | `concat(u32le length,opaque bytes)`，length `1..4096` |
| Unit | empty bytes |
| Bytes N | exactly N raw bytes |
| Array T N | N canonical T values concatenated in index order |
| Map K V | `u32le count`，随后每项 `concat(u32le keyLen,keyBytes,u32le valueLen,valueBytes)` |
| Option T | `00` for none；`concat(01,canonical T)` for some |
| Field p | exactly `ceil(bitLength(p)/8)` little-endian unsigned bytes，decoded value `<p` |
| Struct | field canonical values concatenated in declared order |
| Enum | `concat(u32le variantIndex,payload canonical values)` in declared order |

Map entries 按 `keyBytes` unsigned lexicographic unique ascending，duplicate logical/canonical key 拒绝；
每个 key/value length 必须等于 type-driven decoder 恰好消费的长度。decoder 必须完整消费调用者给定
的 slice，并且 `encode(decode(bytes)) == bytes`，否则为 `nonCanonical`。Constant/Literal bytes、Switch
case value、state、call argument/result 和 instruction result 都复用这一套 decoder，不能各自发明 wire。

`Op.Construct.constructorIndex` 的解释也是唯一的：Struct/Array/Map/Unit 使用 0；Enum 使用
实际 zero-based variant index；Option 使用 0 表示 none、1 表示 some。Struct args 是全部 fields，
Array args 恰为 N 个 elements，Map args 是扁平 key/value 对序列（偶数个，key 在偶数位、value 在
奇数位，positional 类型必须精确等于 K/V；空序列即 empty Map；语义为空 Map 后按 arg 顺序逐对
upsert，duplicate key 以最后一次写入为准，与 IndexSet 一致，因此允许运行期计算的 key，wire 不
要求静态排序），Unit/Option-none 没有 args，Option-some 恰有一个 arg，Enum args 恰为 selected
variant payload。primitive/Bytes/Principal/Field/整数不能用 Construct。
`VariantTag` 只接受 Enum/Option，分别产生 UInt32 variant index 与 0/1；`VariantPayload` 只接受
Enum 的 exact runtime variant 或 Option-some `(variantIndex=1,payloadIndex=0)`，mismatch 为 invalid
Core trap。`FieldGet/FieldSet` 只接受 Struct；`IndexGet/IndexSet` 只接受 Array、Bytes 或 Map，Map
lookup 的 result type 必须为 `Option V`。

### 5.1 Per-operation type/result contract

令 `type(v)` 为 ValueId definition 的 TypeId，`resultType` 为 `Instruction.result.some.typeId`；structural
interning 保证 Bool、UInt8、UInt32 和 `Option V` 各有唯一 TypeId。每个 op 的 exact contract 是：

| Op | Input/type requirement | Exact result type |
|---|---|---|
| Literal | valueBytes canonical for declared typeId | typeId |
| Constant | constantId exists | referenced constant.typeId |
| StateLoad | stateId exists | referenced state.typeId |
| StateStore | type(value) = state.typeId | no result |
| Construct | 第 5 节 constructor rule、all args exact | declared typeId |
| FieldGet | base Struct，fieldIndex in range | selected field.typeId |
| FieldSet | base Struct，fieldIndex in range，value exact field type | type(base) |
| VariantTag | base Enum/Option | unique UInt32 TypeId |
| VariantPayload | exact variant/payload index；Option 只允许 `(1,0)` | selected payload/element TypeId |
| IndexGet Array | index UInt32 | element TypeId |
| IndexGet Bytes | index UInt32 | unique UInt8 TypeId |
| IndexGet Map | index exact key type | unique `Option valueType` TypeId |
| IndexSet Array | index UInt32，value element type | type(base) |
| IndexSet Bytes | index UInt32，value UInt8 | type(base) |
| IndexSet Map | index key type，value map value type | type(base) |
| CheckedCast | input/output 均为 UInt/Int | toType |
| Unary Neg | Int/Field | type(operand) |
| Unary Not | Bool | Bool |
| Unary BitNot | UInt/Int | type(operand) |
| Binary arithmetic | lhs/rhs exact same UInt/Int；Field 只允许 add/sub/mul/div | operand type |
| Binary Eq/Ne | lhs/rhs exact same serializable type | Bool |
| Binary Lt/Le/Gt/Ge | lhs/rhs exact same UInt/Int | Bool |
| Binary And/Or | lhs/rhs Bool | Bool |
| Binary bitwise | lhs/rhs exact same UInt/Int | operand type |
| Binary Shl/Shr | lhs UInt/Int，rhs UInt32 | type(lhs) |
| PureCall | callee kind pureFn；args逐项匹配 params | callee.result.typeId |
| ContextRead | key合法且 requirement 绑定该 exact result type | declared resultType |
| Commit | input serializable且 disclosure rule/requirement通过 | type(value) |
| Assert | condition Bool；error/args按 ErrorDecl exact | no result |
| Emit | args逐项匹配 EventDecl fields | no result |
| ExternalCall/Schedule | args 全部 canonical serializable；callee 至少两个 components | no result |

表中 “declared resultType” 仍必须是 `Instruction.result` 的实际 TypeId；不存在由 host 推断的 hidden type。
同一 program 内所有 `Op.ContextRead` 的相同 key 必须使用同一 result TypeId；不同 callable/branch 对
同 key 声明不同 type 是 invalid Core，不能由 Invocation 或 target adapter 任选其一。
提议中的 v1 wire-owned closed catalog 仅接纳 key
`proof-forge.context.unix-time-seconds.v1`，其结果语义形状必须是程序中唯一匿名
`TypeShapeV1.uint 64`。使用该 key 时 requirements 必须包含且只能包含一个 id 为
`context.unix-time-seconds` 的 exact row：SemVer `1.0.0`、空 predicates、digest 为
`domainSeparatedSha256("pf.context-read-requirement.v1", UTF-8(id))`。Reference runtime按
SPEC-SEM-CORE-001 exact invocation context执行；target support catalog仍未接纳ContextRead。
`Op.Commit` 是 target-neutral 的 label-only disclosure boundary：其逻辑结果保持 operand 的
exact TypeId 与 canonical value bytes，不在 Semantic 层执行hash、加盐或改变值表示。每个含
Commit 的program必须包含且只能包含一个id为`disclosure.commitment`的exact row：SemVer
`1.0.0`、空predicates、digest为
`domainSeparatedSha256("pf.commit-requirement.v1", UTF-8(id))`。识别该row不表示任何target
支持commitment；target必须另行发布并解析同一exact capability claim。
任何 result presence/type、input arity/type 或 referenced declaration不符都是 invalid Core trap，而
Array/Bytes runtime index越界、checked arithmetic/cast/assert failure 才是 `.reverted`。

## 6. Canonical IDs、table order 与 structural validation

- constants、logicalState、events、errors、callables、invariants 的 ID 必须分别等于 array index；
  每类 declaration 按 Source.Program 中该类 declaration 的 source traversal order。
- callable-like declaration（init/entry/view/fn/invariant）按统一 source item order 分配 CallableId；
  invariant predicate 物化为 `kind=invariant` 的 callable，并由同序 `InvariantDecl.callableId` 引用。
- 每个 callable 的 entry block ID 为 0。block 使用从 entry 开始的 preorder DFS：Jump target；Branch
  then/else；Switch cases array order/default；已访问 block 不重复分配。所有 block reachable，ID 等于
  callable.blocks index。
- ValueId 先按 callable parameter order，再按 BlockId order 的 block params，再按 BlockId/instruction
  order 的 result 分配；每个恰好定义一次，use 必须被 dominance relation 覆盖。EffectId 按同一
  BlockId/instruction order 对 effect op 分配且唯一；runtime effect order仍是实际 instruction execution
  order，不以 ID 排序执行。每个 static EffectId 的动态执行从 occurrence 0 开始递增，以
  `EffectOccurrenceV1(effectId,occurrence)` 唯一标识；termination analysis 必须证明每个计数不超过
  `UInt32.max`。committed effect buffer 和 synchronous ExternalResponses 都使用该 pair，response 必须
  与实际执行 sequence exact 对应；missing/duplicate/extra pair trap。这样 effectful bounded loop 不会
  复用同一 response/effect identity。
- jump/block parameter arity/type exact；branch condition Bool；switch case type 与 scrutinee exact，case
  valueBytes 是该 type 的 canonical value且唯一；return/revert/event/error/call arity/type exact；all
  references in range。
- `loopBounds` 按 `(header,backEdgeFrom)` 唯一升序，恰好覆盖 CFG 的每条 back edge；maxIterations
  `<=4096`。view 不含 write/effect；pureFn 只含 deterministic value op 和 checked failure；invariant
  只含下节允许的 closure。
所有 declaration/field/parameter/invariant name 必须是 NFC、nonempty、通过 `SPEC-LANG-001` identifier
规则，并在其所属 namespace/table 中唯一。initializer 恰为零或一个、`name=none`、Unit/public result；
其他 callable `name=some`。invariant callable 的 name、ID 和 `InvariantDecl` exact 对应，Bool/public
result；event/error/parameter field order保留 source order。`Assert(errorId=none)` 要求 args empty；
`some errorId` 要求 error存在且 args arity/type exact。

program qualifiedName 必须是从 source module identity + declaration name 得到的至少两个 component；
`Op.ExternalCall/Op.Schedule.callee` 同样至少两个 component。callables 中至少一个 `entry` 或 `view`。
logical state、constants、events、errors、views、pure functions、invariants、requirements 均可为空；
types 只能在没有任何 reference 时
为空。Switch cases nonempty、保持 normalized source arm order且 constant value唯一；没有 case 的控制流
必须规范化为 Jump，不能保留第二种等价编码。

任一规则失败，external bytes 返回 `PF-SEMANTIC-INVALID` 对应的 `SemanticWireErrorV1`；compiler
自己产生失败值返回 `PF-SEMANTIC-INTERNAL`，不得发布 bytes/hash/partial program。

### 6.1 Provenance companion validation

`SemanticProvenanceV1.schema` 必须 exact 为 `proof-forge.semantic-provenance.v1`；qualifiedName 与
decoded program/sourceIdentity exact 相等；sourceHash 与调用者从
`(sourceModule,sourceIdentity,Source.ProgramV1)` 重算的 hash exact 相等；
semanticHash 与 `semanticHashV1 program` exact 相等。`originMap` 按 `encodeTagged(entity)` unsigned
lexicographic unique ascending；每项 origins nonempty且按 common SourceOrigin key 唯一升序。

`SourceNodeInventoryV1` 只能由 contained production frontend 在同一次 source safe-read/parse/decode 后
构造：sourceHash 必须等于上述重算值；`nodes` 对 `SPEC-SOURCE-WIRE-001` 列出的每个 node-bearing
Source value 恰有一个 SourceOrigin，NodeId 来自 production assigner，path/span 来自同一 immutable
source snapshot。nodes 按 NodeId raw bytes唯一升序；NodeId collision、duplicate visit、missing/extra
node、path/span 不在 snapshot bounds 或 sourceHash 不符时不得构造 inventory。该 transient inventory
不持久化、不进入 program/provenance hash，也不能从 `.pfprov` 或 proof source反序列化。

每个 type/constant/state/event/error/callable/block/instruction/terminator/value/effect/invariant/requirement
都恰有一个 binding，
且不得有 program 中不存在的 entity。`Entity.Requirement(i)` exact 指向
`program.requirements.items[i]`；其 merged origins 只为该 business request 提供 diagnostic/audit trace，
不属于 `SPEC-CAP-001 RequirementRef`。compiler 用 index join 生成 diagnostics/trace，但 support resolver
只接收 program 中的 business request，不能读取 provenance 或让 origin 改写 key/predicate。
synthetic block/value 使用产生它的最近 source node origin，不能写 empty/host span。
每个 listed SourceOrigin 必须在同一 source program 的 production `SourceNodeInventoryV1` 中按
`(path,startByte,endByte,nodeId)` exact 命中；只匹配 NodeId、只检查 span bounds、从其他 sourceHash/
program 复用 inventory 或 builder 自造 inventory 都拒绝。provenance 不要求每个 source syntax node 都
物化为 semantic entity，但所有 semantic bindings 必须来自该唯一 inventory。

Provenance path/span/NodeId/sourceHash 的任意变化会改变 provenance bytes/digest，但只要业务 program
不变就不得改变 semantic bytes/hash。provenance 只供 diagnostics、audit、proof manifest source join；
support resolver 与 target materializer 均不接收 origin map，也不得据此分支或改写语义。

### 6.2 Stable validation order

program decoder/encoder 的首错误顺序固定为：hard byte/nesting/count limit；magic；tag/fieldCount；
length/truncation；UTF-8/NFC/common scalar；option/bool marker；root trailing byte；re-encode equality；
qualifiedName/name/duplicate；table ID/order与 reference range；type graph/Field spec；canonical constant/
literal/switch values；callable kind/signature；CFG reachability/block args/dominance；effect/loop order；
operation/terminator typing；invariant closure/fuel；requirement key/predicate/order。每组内部按 root field
order、array index、record field order；同 instruction 先 result 后 op fields。encoder 在输出任何 byte 前
执行同一 validation，不能 encode 后再发现 invalid。

provenance decoder 先按上述 transport/scalar/re-encode顺序，再检查 schema、qualifiedName、sourceHash、
semanticHash、origin array order/duplicate；join validator 随后按 program entity category 与 ID order检查
range、missing/extra、requirement index，最后按 origin array order与 production SourceNodeInventory exact join。
因此同一多错输入在所有实现上产生相同 `SemanticWireErrorV1` class 与 stable context。

## 7. LogicalStateV1 与 StateConformsV1

`LogicalStateV1.canonicalValues` 按 `program.logicalState` array order，恰为每项
`u32le valueByteLength || canonical value bytes` 的连续串接，不含 name/path/origin/target layout。
`canonicalLogicalStateBytesV1` 若需要持久化，唯一为：

```text
ASCII("pf.logical-state.v1") || 0x00 ||
encode(Bool initialized) || u32le(canonicalValues.size) || canonicalValues
```

实现必须提供：

```lean
def stateConformsBoolV1
    (program : SemanticProgramV1) (state : LogicalStateV1) : Bool

def StateConformsV1
    (program : SemanticProgramV1) (state : LogicalStateV1) : Prop :=
  stateConformsBoolV1 program state = true
```

算法固定为：validate/decode program；要求 `initialized=true`；从 offset 0 依次读取每个 state slot
的 u32 length 和 exact type-driven canonical value；要求 decoder 完整消费该 slice、re-encode 相等；
最后要求 offset 恰等于 `canonicalValues.size`。program invalid、length overflow、slot 缺失/额外、
noncanonical Map、bad enum/payload、wrong Bytes/Array/Field/integer value 或 trailing byte 都返回 false，
不抛 exception、不读取 target state、不容错补零。

## 8. evalInvariantV1 total executable boundary

proof evaluator 是纯、total、target-neutral interpreter。每个 invariant callable 必须：零参数、Bool
public result、entry block 0、`loopBounds=[]`；其 reachable pureFn call graph 必须为 DAG，且所有 closure
CFG 无 back edge。normalizer 必须在进入 SemanticProgramV1 前把 bounded pure loop按 proven bound
展开为 acyclic CFG；超过 effective core limit 则拒绝，不能把 loop 留给 proof evaluator猜测。

对 closure 中每个 callable，按 reverse topological call order计算：

```text
computedInvariantSteps(c) =
  1
  + sum over c.blocks of (c.instructions.size + 1)
  + sum over every Op.PureCall instruction in c of
      computedInvariantSteps(callee)
```

全部使用 checked UInt64；v1 intrinsic hard ceiling 固定为 `10_000_000` steps，overflow 或超过该值为
invalid。ResourceProfile 只能在外层限制实际 worker wall/memory，不能改变同一 canonical bytes 的
valid/invalid 结论；需要更低 product limit 时在 normalization 前拒绝，不能传入 decoder/hash API。
closure 每个 callable 的
`invariantSteps` 必须是 `some(computedInvariantSteps(c))`；不属于任何 invariant closure 的 callable
必须为 `none`。一个 callable 被多个 closure 使用时 computed value必须相同。运行时 fuel 在 frame
entry、每条 instruction、每个 terminator 各减 1；callee 与 caller 共用 fuel，因此上述值是所有
acyclic execution path 的保守上界。合法 program 不会 fuel exhaustion。

允许的 invariant root op 恰为 `Literal,Constant,StateLoad,Construct,FieldGet,FieldSet,VariantTag,`
`VariantPayload,IndexGet,`
`IndexSet,CheckedCast,Unary,Binary,PureCall,Assert`；pureFn closure 进一步禁止 `StateLoad`。所有
`StateStore,ContextRead,Commit,Emit,ExternalCall,Schedule` 都使 semantic validation 失败；若 invalid
carrier 绕过调用则 interpreter 返回 `.trapped`。值环境是由 ValueId 唯一索引的
`(TypeIdV1, canonical value bytes)`；每次读取、构造和运算均重新执行 exact type/range validation。

执行语义固定为：

- entry 参数/Block 参数按 ValueId/type exact bind；instruction、argument 和 target 从左到右。
- Literal 从 op bytes、Constant 从 constant table、StateLoad 从已由 `StateConformsV1` 切分的 slot 取得
  exact `(TypeId,canonical bytes)`，并在写入 value environment 前再次核对 Instruction result type。
- checked integer/Field 运算按 `SPEC-TYPE-001`；overflow、underflow、div/mod zero、bad shift、
  failed cast 与 `Assert(false)` 返回 `.reverted`。Bool/bit/comparison、aggregate get/set、Map lookup
  和 Option result 使用第 5 节 canonical values；invalid reference/type/index/Core 返回 `.trapped`。
- `PureCall` 只能指向 `kind=pureFn`，arity/type exact，共用 fuel；callee revert/trap 原样传播。
- Branch 只接受 Bool；Switch 按 exact typed canonical value equality 选择第一个且唯一 case，缺 match
  走 default，缺 default 为 `.trapped`。Jump arguments exact bind。
- `Term.Revert` 返回 `.reverted`；`Term.Trap` 返回 `.trapped`；Invariant return 必须是一个 Bool，true/
  false 分别返回 `.returnedTrue/.returnedFalse`。Unit/missing/wrong-type return 为 `.trapped`。
- evaluator 不读 context、clock、random、file、network、environment 或 external responses，不提交
  logical state/effect；任何 host exception/resource fault 都通过 total result 映射 `.trapped`。

运算的 executable 细节不留给 host：UInt division/mod 是 Euclidean quotient/remainder；Int division
向零截断、remainder 与 dividend 同号，`minInt / -1` revert。add/sub/mul 和 UInt left shift要求数学
结果仍在目标宽度，Int right shift 为 sign-extending、UInt right shift 为 zero-fill；shift rhs 必须是
UInt32 且 `< width`。bit operation 在固定宽度 two's-complement bits 上执行。`Neg` 只接受 Int/Field，
Int min negation revert，Field negation为 `(-x) mod p`；`Not` 只接受 Bool，`BitNot` 只接受整数。
Field add/sub/mul/neg/div 全部 modulo p，division 使用唯一 multiplicative inverse且 zero revert；Field
不接受 mod/order/bit/shift。Eq/Ne 接受两个 exact 同 type canonical values；Lt/Le/Gt/Ge 只接受同宽
UInt/Int并按各自 unsigned/signed order。And/Or 只接受 Bool；它们的 operands 已由 CFG 左到右求值，
source short-circuit 必须在 normalization 中显式为 Branch。CheckedCast v1 只允许 UInt/Int 之间转换，
数学值不可表示时 revert。Array/Bytes index越界 revert；Map missing返回 canonical Option-none，Map
set返回新 canonical sorted map；static bad field/variant/type reference是 trap。

API 与 theorem proposition 固定为：

```lean
def evalInvariantV1
    (program : SemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (state : LogicalStateV1) : InvariantEvalResultV1

def InvariantTheoremV1
    (program : SemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1) : Prop :=
  invariantOrdinal.toNat < program.invariants.size ∧
  ∀ state : LogicalStateV1,
    StateConformsV1 program state →
    evalInvariantV1 program invariantOrdinal state = .returnedTrue
```

`evalInvariantV1` 依次 validate program、ordinal、state、invariant/callable closure，再以
`computedInvariantSteps(root)` 执行；任一步失败或 ordinal 越界均 `.trapped`。它不能调用通用
`step` 并注入伪 external response，也不能把 revert/trap 当 true。

## 9. Checked-in canonical proof subject 与 definitional equality

独立 proof builder 用于构造 closed program 的 subject identity input 只能是一对 regular、single-link、
project-relative file；证明源文件、锁定 Lean toolchain、同一 canonical Source.Program 输入与其
contained frontend 产生的 `SourceNodeInventoryV1` 是另外的 required build input，不能替换这对 subject：

```text
proof-subject.pfsem
proof-subject.pfprov
```

`.pfsem` 的全部文件 bytes 必须就是 `canonicalSemanticProgramBytesV1`；`.pfprov` 的全部 bytes 必须
就是 `canonicalSemanticProvenanceBytesV1`。builder strict decode 两者，用同一
`sourceModule,sourceIdentity,Source.ProgramV1` 重新计算 sourceHash、运行 production NodeId assigner，并
从当前 immutable source snapshot 构造 `SourceNodeInventoryV1`，再调用
`validateSemanticProvenanceV1` 对 `.pfprov` 的每一个 path/span/NodeId binding 做 exact inventory
join。验证成功后重算 `semanticProvenanceDigestV1`。ProofBundle manifest 的
`sourceHash,semanticHash,semanticProvenanceDigest` 必须分别 exact 等于 provenance sourceHash、
program semanticHash 和刚重算的 provenance digest；formal builder 不能只相信命令行、`.pfprov` 或
manifest 自报值。

builder safe-read 两文件，执行 full strict decoder、re-encode equality 和全部 structural validation，
再生成 reducible closed Lean abbreviation；bytes 必须逐项写成包含 `.pfsem` 每一个 byte 的固定
`UInt8` literal，不读取运行时文件。令 safe-read 得到的文件 bytes 为 `A : Array UInt8`；生成器用
`"ByteArray.mk #[" ++ String.intercalate ", " (A.toList.map (fun b => toString b.toNat)) ++ "]"`
构造 literal 的完整 token sequence；`ByteArray.mk` 的 expected constructor argument type使每个 numeral
elaborate 为 `UInt8`。每个 `b_i` 均实际出现，不允许省略号、chunk digest、runtime read 或 opaque
constant。生成模块把该
literal 定义为 reducible `subjectBytes : ByteArray`，再定义 reducible
`subjectProgram : SemanticProgramV1 := ⟨subjectBytes⟩`。
生成 source/`.olean` 仍受 compiler-core 与 ProofBundle 的 byte/time/memory hard maxima；超过时该 proof
bundle build fail closed，不能改用 digest theorem、分块 opaque constant 或 runtime loader 绕过 full
closed value。

compiler expected-type builder 对自身已验证 bytes执行相同 byte-to-literal 算法，直接构造 closed
`InvariantTheoremV1 (⟨ByteArray.mk A⟩ : SemanticProgramV1) ordinal` expression；这里 `A` 表示实际
内联的完整 `Array UInt8` literal，不是变量或 bundle lookup。loader 不引用 bundle 自报
的同名 `subjectBytes` 来构造
expected type。

bundle export 只在展开 ABI abbrev 与 bundle 显式 reducible abbreviation 后做 definitional equality。
同 bytes 的两个独立 builder 因单字段 carrier definitionally equal；任一 byte 或 ordinal 不同就不
definitionally equal。`semanticHashV1 program = manifest.semanticHash`、任意 digest equality theorem、
existential program、propositional equality/cast、metavariable、axiom 或自报 decoded fields 都不能
代替完整 closed value进入 theorem proposition。

`.pfprov` 与 provenance 不进入 theorem proposition；改变 path/span/NodeId/sourceHash 而保持 `.pfsem`
不变时，closed program/theorem type保持 definitionally equal，但 source inventory validation 和
ProofBundle manifest 的 sourceHash/semanticProvenanceDigest join 会拒绝错误 provenance。`.pfprov`
因此是 authenticated build input，不是装饰 metadata。`proof-subject.*` 是 bundle 构建输入/evidence，
不是运行时 `ProofBundleV1` directory member；最终
bundle layout 仍严格遵守 `SPEC-SEM-001`。bundle loader 除 manifest sourceHash/semanticHash/
semanticProvenanceDigest 检查外，必须对 exported theorem type执行上述 exact expected-type definitional
equality；两层检查缺一不可。

## 10. Golden、roundtrip 与 mutation acceptance

`TST-SEM-001` 以本文件为唯一 wire oracle，`TST-PROOF-001` 复用同一 checked-in subject。验收 corpus
必须把 `.pfsem` bytes/semanticHash、`.pfprov` bytes/provenanceDigest、sourceHash 以及两个 decoded field
dump 全部 checked in；测试运行时重新生成但不得更新 golden。至少由 production Lean encoder 与一个
不 import ProofForge 的独立 reference encoder 生成，两个实现彼此相等但没有固定 bytes/hash 不算通过。

Golden inventory 必须覆盖：

1. optional empty tables/minimal valid program、Counter、Map、event/error、external call/schedule、bounded loop、
   struct/enum/Option、每个 integer width/Field/Bytes/Array/Principal extrema；
2. 本文件每个 wire record、Type、Visibility、Callable、Unary、Binary、Op、Term、Trap、Entity 和 Req tag
   至少一次，以及每个 `none/some`、empty/single/multiple array 和 NFC non-ASCII string；
3. canonical logical state 的 uninitialized/initialized、zero/maximum value、Map order、enum payload；
4. invariant returned true/false、checked revert、explicit revert、invalid trap、pure-call composition 和
   exact computed fuel；
5. zero/one/multiple merged requirements，所有五种 predicate 和所有十个 requirement domain。
6. provenance 的每个 Entity tag、single/multiple origin、multi-file path/span/NodeId、requirement origin join；
   同 business program 的两个不同 sourceHash/originMap 必须生成不同 provenance digest、相同 semanticHash。
7. effectful bounded loop 的 static EffectId 与 occurrence 0/1/maximum sequence，以及 response missing/
   duplicate/extra/reordered pair trap；matched reverted 后有 trailing extra、程序自行 revert/trap 时仍有
   unconsumed response 都必须命中同一个 precedence golden。
8. source 未显式写 Bool/UInt8/UInt32/Option、但 comparison、Bytes index、VariantTag、Map lookup
   normalization 分别合成这些类型的 fixture；两个 encoder 必须产生相同 complete type-closure key dump、
   TypeId、`.pfsem` bytes 与 semanticHash，删除/换序/加入未引用匿名 type 的 mutation 全部拒绝。

对每个 valid fixture 必须断言：

```text
decode(bytes) succeeds
encode(decoded) == bytes
decode(encode(decoded)) == decoded
SHA-256(bytes) == checked-in semanticHash
StateConforms/evalInvariant == checked-in executable observations
decode(provenanceBytes) succeeds
encodeSemanticProvenance(sourceModule, sourceIdentity, source, nodeInventory,
                         program, decodedProvenance) == provenanceBytes
validateSemanticProvenance(sourceModule, sourceIdentity, source, nodeInventory,
                           program, provenance) succeeds
SHA-256(provenanceBytes) == checked-in provenanceDigest
ProofBundleManifest.semanticProvenanceDigest == checked-in provenanceDigest
```

property roundtrip 只能生成满足全部 structural invariants 的 bounded typed program；另外生成 arbitrary
bytes 断言 decoder total、never crash/hang，并且任何 success 都满足 re-encode identity。production 与
reference encoder/decoder 的 bytes、error class 和 first-error order 必须一致。

每个 golden 分别只做一个 mutation并断言 stable rejection、零 proof acceptance、零 requirement
resolution、零 target Plan/OutputSet：magic/domain byte、tag byte/case、fieldCount、length equal/over/
truncate、bool/option marker、invalid UTF-8/NFC/SemVer/SchemaId/path/Digest、unknown/trailing byte、array
order、duplicate/out-of-range ID、missing reference、non-dominating ValueId、bad block arg/type、CFG
unreachable/back-edge/loop bound、effect order、literal/constant/state noncanonical value、Map key order/
duplicate、enum tag/payload、Field modulus/value、requirement key/predicate order/duplicate/conflict、
wrong `invariantSteps`、effectful/recursive/cyclic invariant closure、fuel exhaustion。requirement origin、
origin entity/order/duplicate/missing/extra、wrong provenance schema/name/sourceHash/semanticHash 只 mutation
`.pfprov`；测试必须同时断言 `.pfsem` 与 semanticHash 未变化。

Proof-subject/bundle mutation additionally covers `.pfsem`/`.pfprov` one-byte change、ProofBundle manifest
duplicate/unknown/missing field、wrong sourceHash/semanticHash/provenance entity/origin join、same digest assertion
over different full program、foreign/spoofed SourceNodeInventory、wrong semanticProvenanceDigest、same
invariant name with wrong ordinal、digest-only theorem、propositional cast、metavariable 和 non-reducible/
opaque subject value。positive 必须证明两个独立 builder 从同一 `.pfsem` 产生 definitionally equal
`subjectProgram` 与 theorem type，并编译包含全部 UInt8 元素的实际 `ByteArray.mk` 生成模块；negative
必须证明即使伪造 manifest digest equality，任一完整 program byte mutation仍使 expected type mismatch。

## 11. 错误与完成条件

binary/value/structural input failure 对外统一 `PF-SEMANTIC-INVALID`，内部 compiler generation failure
为 `PF-SEMANTIC-INTERNAL`，proof subject/expected type不符按 SPEC-CLI-001/diagnostic registry 统一为
`PF-TYPE-001`；资源超限按
compiler-core ResourceProfile 映射。所有失败 fail closed：不缓存 invalid carrier/hash，不降级到 digest
theorem，不调用 target，不产生 partial certification 或 artifact。

本规格只有在完整 Lean types、strict encoder/decoder、独立 reference implementation、固定 golden、
roundtrip/property/mutation corpus、`StateConformsV1`、total invariant interpreter、proof-subject builder
和 exact definitional-equality loader test 同时通过时才能 accepted。关联 `FR-004`、`FR-005`、
`TST-SEM-001`、`TST-SEM-002`、`TST-SEM-003`、`TST-REQ-001`、`TST-REQ-002`、
`TST-PROOF-001`。
