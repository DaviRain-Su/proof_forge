---
id: SPEC-SOURCE-WIRE-001
title: Source.ProgramV1 Canonical AST 与 Wire 规格
status: proposed
owner: frontend
updated: 2026-07-19
normative: true
---

# Source.ProgramV1 Canonical AST 与 Wire 规格

## 范围与权威边界

本规格冻结 `Source.ProgramV1` 的目标中立 canonical AST、binary wire、`sourceHash` 输入和
NodeId 分配测试接口。`SPEC-LANG-001` 继续唯一拥有 surface grammar、默认值和 source
elaboration；`SPEC-COMMON-001` 继续拥有 common `QualifiedName`、`NodeId`、`Digest`、NFC 和资源
primitive，**不**把 common `QualifiedName` 当作 source wire Ident 或 source identity 数组权威。
本规格只把已经由 Phase 1 parser 接受并完成 declaration-shape validation 的 source AST 编码为
唯一 bytes，不定义 type/effect/termination/disclosure 结论，也不包含 `TargetId`、profile、VM、ABI、
storage、account、Wasm、circuit 或 deploy 语义。

schema 名为 `proof-forge.source-program.v1`，hash domain 固定为 `pf.source.v1`。schema 由调用
API 或 persistent environment extension out-of-band 选择；canonical bytes 自身不重复写 schema
字符串。任何 constructor、ordered field、默认值 materialization 或 encoding 改变都必须发布新
schema/domain，不能在 v1 中宽松读取。

当前 `ProofForgeV2.Core.Source` 是 alpha 子集，不是本规格的字段或 tag authority。完整 D1
实现必须迁移到本规格；不得为了兼容 alpha 的内存 constructor 而改变 v1 wire。

## Source name carrier（Ident）

Source wire 的 `Ident` 是 **raw Lean `Name.str` payload carrier**（`SourceNameComponentV1`），与
`Name.toString` rendered spelling（可含 `«…»`）以及 `SPEC-COMMON-001` `QualifiedName` component
三者互不等价。

- **Wire 身份字节**只编码 raw UTF-8；不得写入 guillemet render、pretty-printer 或 `Name.toString`。
- raw 必须已是 pinned NFC；UTF-8 长度 `1..240`；拒绝 Unicode Cc 与 closing guillemet `U+00BB`。
  这是 deliberate wire-local fail-closed narrowing：Lean 把 `»` 视为 identifier 字符，但
  `Name.toString` 无法为含 `»` 的 component 生成可恢复 escape；禁掉 closing guillemet 后，plain render
  或外围 `«raw»` 都能唯一回到同一 raw。opening `U+00AB` 本身不破坏该注入性。
- raw **允许** exact `_`、opening guillemet `U+00AB`、digit-leading、hyphen、embedded dot、space、
  NFC Unicode letter-like 与 language reserved word **bodies**（语法层仍可按 `SPEC-LANG-001` 保留词
  拒绝；本 wire carrier 不实现 keyword deny-list）。
- raw **不**要求 `Lean.isIdFirst`/`isIdRest`；common `QualifiedName` 的 isId\* 规则保持不变，
  不得被本规格削弱。
- 从 `Lean.Name` 投影时只接受最终 constructor 为 `.str` 的 component；`.num`/anonymous 失败。
- render helper 仅供 Lean 侧诊断/导出对照：`(Name.str .anonymous raw).toString`；render **永不**进入
  sourceHash / canonical bytes。非 Lean 实现不得重写该 renderer 后把结果当身份；跨实现只实现并比较
  raw validation 与 raw wire bytes。

Source identity 数组（`moduleName`、`programIdentity` 与其他 source-only qualified paths）是
`Array<SourceNameComponentV1>`（实现名可称 source-qualified array），**不是** common
`QualifiedName`。count 规则：`moduleName` ≥1；`programIdentity` ≥2 且为 module∥namespace∥decl
join；上限 256 components。common `QualifiedName` 继续服务 non-source JCS/export 场景。

## Canonical root

canonical root 是以下三段的无间隔串接：

```text
canonicalSourceAstBytesV1 =
  encodeSourceNameArray(moduleName) ||
  encodeSourceNameArray(programIdentity) ||
  encodeTagged(program)
```

- `moduleName` / `programIdentity` 为 source-specific raw component arrays（见上节）。
- `program.name` 必须等于 `programIdentity` 最后一个 **raw** component（非 rendered）。
- root 没有 outer tag、field count、magic、source path 或 trailing bytes。调用者必须已经选择
  `proof-forge.source-program.v1`。

`Program` 的 item array 保持 source declaration order。所有其他 array 也保持语法/业务顺序；
v1 不按 identifier 排序 AST。parser 在构造 ProgramV1 前将省略的 state/parameter visibility
materialize 为 `Visibility.Public`，将省略的 callable return type materialize 为 `Type.Unit`。
显式与默认写法因此产生相同 AST。`let` 的显式 type annotation、缺失 `else`、无值 `return` 等
会改变 source-level validation，必须按下文 option 字段保留。

## Primitive binary encoding

所有整数使用 little-endian。decoder 必须在分配 payload 前检查声明长度、剩余 bytes、全局
16 MiB source/profile limit、100000-node limit 和 256 nesting limit；不得用整数 wraparound 或
unbounded recursion 读取攻击输入。

| Value | Exact encoding |
|---|---|
| `u8` | 1 byte |
| `u16le` | 2 bytes |
| `u32le` | 4 bytes |
| `u256le` | exactly 32 bytes, unsigned magnitude |
| `Bool` | `0x00=false`, `0x01=true`; other byte rejected |
| `Option<T>` | `0x00` for none, or `0x01 || encode(T)`; other marker rejected |
| `Array<T>` | `u32le count || encode(element[0]) ...`; order preserved |
| `Ident` / `SourceNameComponentV1` | `u32le UTF8-byte-length || raw NFC UTF-8`（raw Lean `Name.str` payload；见上节） |
| `String` | `u32le UTF8-byte-length || NFC Unicode-scalar UTF-8` |
| `SourceNameArray` | `Array<Ident>`；source identity/path 专用；count 依上下文（module ≥1；programIdentity ≥2；≤256） |
| `QualifiedName`（common only） | 仍由 `SPEC-COMMON-001` 定义；**不得**用作 source wire Ident 或 source identity 数组 |
| `QualifiedId` | source 上为 `SourceNameArray` 且 count `2..256`；common QN 规则不自动适用 |
| Phase 1 length/bound | `u32le`, value restricted to `0..4096` |

`ProofDecl.theorem`、constructor/pattern callee paths 与 `ExternalCallExpr.callee` 在 source wire 上
使用 source `QualifiedId`（≥2 raw components）；root `programIdentity` 使用上节 join。
String escape spelling 不进入 AST，decoded Unicode scalar
sequence 才编码。Integer literal 的 decimal/hex spelling 不进入 AST；magnitude 必须在
`0..2^256-1`，编码为固定 `u256le`。源码负号是 `Expr.Unary(UnaryOp.Neg, ...)`，不是 signed literal。

每个 tagged constructor 使用：

```text
encodeTagged(value) =
  u32le(tag ASCII byte length) || tag ASCII bytes ||
  u16le(fieldCount) ||
  encode(field[0]) || ... || encode(field[fieldCount-1])
```

tag 大小写敏感。field name 不写入 binary；下表顺序是唯一解释。`fieldCount` 固定为 `u16le`，
必须与 tag 的表列值 exact 相等，即使某字段是 `none` 或 empty array 也不能省略。所有 nullary
constructor 仍编码 tag 加 `u16le(0)`。

下表 `Tag` 列是 `SPEC-LANG-001` 所称 EBNF production/alternative name 的 v1 exact expansion：
已有命名 production 保持该名，EBNF 中未命名的 sum alternative 使用下表冻结的 qualified tag。
wire tag、NodeId `parentTag` 与 golden inventory 必须逐 byte 使用同一 ASCII string；Lean/C/Rust 等
实现的内存 type/constructor 名不能替代它。`Ordered fields` 中冒号前的名字同样冻结 NodeId
`fieldTag`，不能使用字段 ordinal、pretty-printer label 或 parser syntax kind。

## Program 与 item constructors

`ProgramItem` 没有额外 wrapper tag；item 直接使用其 alternative tag。

| Tag | Count | Ordered fields |
|---|---:|---|
| `Program` | 2 | `name : Ident`, `items : Array<ProgramItem>` |
| `StateDecl` | 3 | `visibility : Visibility`, `name : Ident`, `type : Type` |
| `StructDecl` | 2 | `name : Ident`, `fields : Array<FieldDecl>` |
| `EnumDecl` | 2 | `name : Ident`, `variants : Array<EnumVariant>` |
| `ConstDecl` | 3 | `name : Ident`, `type : Type`, `value : Expr` |
| `EventDecl` | 2 | `name : Ident`, `params : Array<Param>` |
| `ErrorDecl` | 2 | `name : Ident`, `params : Array<Param>` |
| `InitDecl` | 2 | `params : Array<Param>`, `body : Block` |
| `EntryDecl` | 4 | `name : Ident`, `params : Array<Param>`, `result : Type`, `body : Block` |
| `ViewDecl` | 4 | `name : Ident`, `params : Array<Param>`, `result : Type`, `body : Block` |
| `FnDecl` | 4 | `name : Ident`, `params : Array<Param>`, `result : Type`, `body : Block` |
| `InvariantDecl` | 2 | `name : Ident`, `predicate : Expr` |
| `ExtensionReq` | 3 | `id : QualifiedId`, `version : String`, `digest : String` |
| `ProofDecl` | 2 | `invariant : Ident`, `theorem : QualifiedId` |

`Program.items`、`StructDecl.fields`、`EnumDecl.variants` 和 every `Block.statements` 必须 nonempty。
`ExtensionReq.version` 必须是 canonical exact SemVer string；`digest` 必须是
`sha256:<64 lowercase hex>`。这些 strings 仍按 String primitive 编码。duplicate declarations、
zero entry/view、multiple init 与 proof/invariant binding 继续由 `SPEC-LANG-001` 按稳定 source
order 拒绝，不通过 serializer 修复。

## Supporting records 与 visibility

| Tag | Count | Ordered fields |
|---|---:|---|
| `Param` | 3 | `visibility : Visibility`, `name : Ident`, `type : Type` |
| `FieldDecl` | 2 | `name : Ident`, `type : Type` |
| `EnumVariant` | 2 | `name : Ident`, `payloadTypes : Array<Type>` |
| `Block` | 1 | `statements : Array<Stmt>` |
| `StmtMatchArm` | 2 | `pattern : Pattern`, `body : Block` |
| `ExprMatchArm` | 2 | `pattern : Pattern`, `value : Expr` |
| `ExternalCallExpr` | 2 | `callee : QualifiedId`, `args : Array<Expr>` |

Visibility 是 tagged nullary value：

| Tag | Count |
|---|---:|
| `Visibility.Public` | 0 |
| `Visibility.Private` | 0 |
| `Visibility.Commitment` | 0 |

Visibility 只保留用户声明的 disclosure label；它不是 authority、state custody 或 target ABI。

## Type constructors

| Tag | Count | Ordered fields |
|---|---:|---|
| `Type.Bool` | 0 | — |
| `Type.UInt` | 1 | `width : u16le` |
| `Type.Int` | 1 | `width : u16le` |
| `Type.Principal` | 0 | — |
| `Type.Unit` | 0 | — |
| `Type.Named` | 1 | `name : Ident` |
| `Type.Array` | 2 | `element : Type`, `length : u32le` |
| `Type.Map` | 2 | `key : Type`, `value : Type` |
| `Type.Option` | 1 | `element : Type` |
| `Type.Bytes` | 1 | `length : u32le` |
| `Type.Field` | 1 | `id : Ident` |

`Type.UInt.width` 和 `Type.Int.width` 只允许 `8,16,32,64,128,256`。Array/Bytes length 只允许
`0..4096`。Phase 1 `Type.Field.id` 的唯一 accepted source identifier 是 `bn254_fr`；D2 将它 exact
映射到 `proof-forge.field.bn254-fr.v1`，其他 identifier 失败，且 target/profile 不参与 lookup。
Map key legality、recursive type legality、named resolution 和 serializability 是 D2 type rules；wire 只
保留 source type structure，并拒绝非法 width/length。

## Statement constructors

| Tag | Count | Ordered fields |
|---|---:|---|
| `Stmt.Let` | 3 | `name : Ident`, `typeAnn : Option<Type>`, `value : Expr` |
| `Stmt.Assign` | 2 | `target : Place`, `value : Expr` |
| `Stmt.If` | 3 | `condition : Expr`, `thenBlock : Block`, `elseBlock : Option<Block>` |
| `Stmt.Match` | 2 | `scrutinee : Expr`, `arms : Array<StmtMatchArm>` |
| `Stmt.For` | 5 | `binder : Ident`, `start : Expr`, `endExclusive : Expr`, `bound : u32le`, `body : Block` |
| `Stmt.Assert` | 2 | `condition : Expr`, `error : Option<Ident>` |
| `Stmt.Revert` | 2 | `error : Ident`, `args : Array<Expr>` |
| `Stmt.Emit` | 2 | `event : Ident`, `args : Array<Expr>` |
| `Stmt.Return` | 1 | `value : Option<Expr>` |
| `Stmt.Call` | 1 | `call : ExternalCallExpr` |
| `Stmt.Schedule` | 1 | `call : ExternalCallExpr` |

`Stmt.Match.arms` 必须 nonempty；`Stmt.For.bound` 为 `0..4096`。call/schedule 只保存 source
qualified callee 与 argument order；同步/异步 effect 和 target support 在后续阶段推导。

## Expression、literal 与 operator constructors

| Tag | Count | Ordered fields |
|---|---:|---|
| `Expr.Literal` | 1 | `literal : Literal` |
| `Expr.Place` | 1 | `place : Place` |
| `Expr.Constructor` | 2 | `constructor : QualifiedId`, `args : Array<Expr>` |
| `Expr.Unary` | 2 | `op : UnaryOp`, `operand : Expr` |
| `Expr.Binary` | 3 | `op : BinaryOp`, `lhs : Expr`, `rhs : Expr` |
| `Expr.LocalCall` | 2 | `callee : Ident`, `args : Array<Expr>` |
| `Expr.Match` | 2 | `scrutinee : Expr`, `arms : Array<ExprMatchArm>` |

`Expr.Match.arms` 必须 nonempty。`Expr.Constructor` 与 pattern constructor 只表示 Phase 1
struct/enum/Option 的 positional source shape；它不选择 target representation。named constructor
fields、guards、or-patterns、ranges、closures 和任意 Lean term 不属于 v1；若 surface grammar 将来
增加它们，必须新增 schema/domain，不能塞入 generic string。`Expr.LocalCall` 只保存 EBNF
`LocalFnCall`；D2 仍必须 exact resolve 到同一 program 的 `fn`。constructor identity 只允许
SPEC-LANG-001 的 `StructName.new`、`EnumName.Variant`、`Option.some`、`Option.none`；unqualified
call 永远编码 `Expr.LocalCall`，不能在 D2 或 target stage 改写 alternative。

Literal 是 tagged value：

| Tag | Count | Ordered fields |
|---|---:|---|
| `Literal.Bool` | 1 | `value : Bool` |
| `Literal.Integer` | 1 | `magnitude : u256le` |
| `Literal.String` | 1 | `value : String` |

`Literal.String` 仅保留 `SPEC-LANG-001` 词法允许的 string literal；它不会凭 wire constructor
引入新的 Phase 1 runtime `String` type。若所在 expression 没有合法 source type，D2 必须拒绝。

UnaryOp 是 tagged nullary value：

| Tag | Count |
|---|---:|
| `UnaryOp.Neg` | 0 |
| `UnaryOp.Not` | 0 |
| `UnaryOp.BitNot` | 0 |

BinaryOp 是 tagged nullary value：

| Tag | Count | Class |
|---|---:|---|
| `BinaryOp.Add` | 0 | arithmetic |
| `BinaryOp.Sub` | 0 | arithmetic |
| `BinaryOp.Mul` | 0 | arithmetic |
| `BinaryOp.Div` | 0 | arithmetic |
| `BinaryOp.Mod` | 0 | arithmetic |
| `BinaryOp.Eq` | 0 | comparison |
| `BinaryOp.Ne` | 0 | comparison |
| `BinaryOp.Lt` | 0 | comparison |
| `BinaryOp.Le` | 0 | comparison |
| `BinaryOp.Gt` | 0 | comparison |
| `BinaryOp.Ge` | 0 | comparison |
| `BinaryOp.And` | 0 | logical |
| `BinaryOp.Or` | 0 | logical |
| `BinaryOp.BitAnd` | 0 | bitwise |
| `BinaryOp.BitOr` | 0 | bitwise |
| `BinaryOp.BitXor` | 0 | bitwise |
| `BinaryOp.Shl` | 0 | shift |
| `BinaryOp.Shr` | 0 | shift |

Concrete token spelling/precedence remains `SPEC-LANG-001` parser authority；wire tags only record the
resulting AST. Operand type, checked failure、short-circuit behavior and left-to-right evaluation remain
type/semantic rules, not binary decoder decisions. Builtins that lack a current `SPEC-LANG-001` EBNF
alternative cannot be smuggled in as `Expr.LocalCall`；adding a distinct builtin expression requires a
coordinated language and wire schema revision。

## Place constructors

当前 EBNF 将 `Place` 留作未展开 production。Phase 1 canonical AST 只允许以下目标中立结构：

| Tag | Count | Ordered fields |
|---|---:|---|
| `Place.Name` | 1 | `name : Ident` |
| `Place.Field` | 2 | `base : Place`, `field : Ident` |
| `Place.Index` | 2 | `base : Place`, `index : Expr` |

`Place.Name` 不在 Source 阶段标记 local/parameter/state/context；exact resolution、shadowing、read/write
legality 和 Array/Map index typing 属于 D2。`Place.Field` 只保存 source selection，`Place.Index`
只保存 source index expression；二者不含 storage offset、account key、ABI path 或 target layout。

## Pattern constructors

当前 EBNF 只通过 `MatchArm` 引用 pattern，未展开 pattern production。Phase 1 canonical AST 只允许：

| Tag | Count | Ordered fields |
|---|---:|---|
| `Pattern.Wildcard` | 0 | — |
| `Pattern.Bind` | 1 | `name : Ident` |
| `Pattern.Literal` | 1 | `literal : Literal` |
| `Pattern.Constructor` | 2 | `constructor : QualifiedId`, `args : Array<Pattern>` |

Pattern 只描述 source destructuring。binding uniqueness、constructor resolution、payload arity/type、
exhaustiveness 和 unreachable arm 属于 D2；wire 不根据 target 或 runtime representation 改写。

## Canonical validation 与 unknown rejection

`decodeCanonicalSourceAstBytesV1` 必须 exact consume whole input，并在返回任何 ProgramV1 前完成：

1. root 两个 qualified names 和 `Program` tag validation；
2. 每个 tag 为上表 exact ASCII tag；unknown tag 立即拒绝；
3. 每个 `u16le fieldCount` 与 tag 的固定 count exact 相等；missing/extra field 均拒绝；
4. Bool/option marker、UTF-8、Unicode scalar、NFC、Ident/QualifiedName/QualifiedId component count、
   SemVer/digest、width/bound
   和 nonempty-array invariant validation；
5. declared length/count 不超过 remaining bytes、profile maxima 或 allocation budget；
6. Program name/identity join、AST depth/node count 和 no trailing byte validation；
7. `SPEC-LANG-001` 的 declaration-shape validation，按 source order 返回首诊断。

v1 没有 unknown-field preservation、optional extension area、best effort、default-on-error 或
forward-compatible skip。malformed/noncanonical/unknown wire 使用 `PF-SRC-020`，stable context 至少
区分 `unknown-constructor`、`field-count`、`noncanonical-scalar`、`identity-mismatch`、
`trailing-bytes`；资源上限使用 `PF-BOUND-001`。失败不得返回 partial Program、登记 environment
extension、计算可用 sourceHash 或进入 D2。

encoder 只能接受已通过同一 invariant validator 的 ProgramV1。`decode(encode(p)) = p` 且
`encode(decode(bytes)) = bytes`；第二个等式意味着 decoder 必须拒绝任何可以被重新编码成不同
bytes 的输入。

## SourceHash

```text
sourceHash = SHA-256(
  ASCII("pf.source.v1") || 0x00 || canonicalSourceAstBytesV1
)
```

API 返回 SPEC-COMMON-001 `Digest` wire form `sha256:<64 lowercase hex>`。hash 输入包含两个
qualified identities、全部 exact constructor tags、field counts、ordered fields、materialized
defaults、array/option markers 和 AST values。它排除 schema 字符串、sourceHash 自身、注释、空白、
token spelling、绝对/项目相对路径、span、line/column、NodeId、origin table、内存地址、hash-map
iteration order 和非语义括号；operator precedence 形成的 AST 结构仍包含在内。

以下 API 是唯一 production boundary：

```text
canonicalSourceAstBytesV1(
  moduleName : SourceQualifiedNameV1,
  programIdentity : SourceQualifiedNameV1,
  program : ProgramV1
) -> Except Diagnostic ByteArray

decodeCanonicalSourceAstBytesV1(bytes)
  -> Except Diagnostic (SourceQualifiedNameV1 × SourceQualifiedNameV1 × ProgramV1)

sourceHashV1(moduleName, programIdentity, program)
  -> Except Diagnostic Digest
```

command elaborator、CLI Loader、persistent export 与 independent tooling 必须调用同一 contract；
不得各自维护 tag number、field order 或默认值逻辑。

## NodeId path 与 collision-injection interface

NodeId 不进入 canonical bytes/sourceHash。D1 在 ProgramV1 validation 后，以
`SPEC-LANG-001` 的 preimage 公式为每个 node-bearing value 分配 NodeId：`Program`、所有 item、
`Param`、`FieldDecl`、`EnumVariant`、`Block`、两种 match arm、`ExternalCallExpr`、`Type`、`Stmt`、
`Expr`、`Place` 和 `Pattern` 是 node-bearing；Visibility、Literal、UnaryOp、BinaryOp 和 scalar
不是独立 NodeId node。

root `Program` path 是 empty array。canonical preorder 按 constructor 的 ordered fields 遍历；
direct child 或 present option child 的 `index=0`，array child 使用 source-order index。每个 path
segment 恰为：

```text
{parentTag: exact constructor tag, fieldTag: exact ordered-field name, index: u32}
```

只有 node-bearing child 追加 segment；scalar/tagged scalar 不产生 path。NodeId preimage 与结果为：

```text
nodeIdPreimageV1 =
  ASCII("pf.source-node.v1") || 0x00 ||
  JCS({module:[...], program:[...], path:[...]})

nodeId = first-16-bytes(SHA-256(nodeIdPreimageV1))
```

以下 collision 与 duplicate-visit 拒绝规则是 normative D1 contract，不是测试建议。实现必须提供
以下 production API 与 test-build-only seam；名称可按实现语言调整，参数/结果语义不能改变：

```text
nodeIdPreimageV1(moduleName, programIdentity, path) -> ByteArray

assignNodeIdsV1(
  moduleName,
  programIdentity,
  program
) -> Except Diagnostic NodeOriginTableV1

NodeIdCandidate16V1 :=
  (canonicalPreimage : ByteArray) -> Except Diagnostic ByteArray[16]

assignNodeIdsV1ForTestWithCandidate(
  candidate16 : NodeIdCandidate16V1,
  moduleName,
  programIdentity,
  program
) -> Except Diagnostic NodeOriginTableV1
```

production `assignNodeIdsV1` 内部固定计算 `first-16-bytes(SHA-256(preimage))`；它没有 digest/candidate
参数，且不能从 CLI、source、extension、environment 或 target 替换。test-only entry 只接收已经由
`nodeIdPreimageV1` 构造的 canonical preimage，并返回最终 16-byte candidate；调用方不能借该 seam
改变 preimage。该 symbol 只存在于测试构建，release binary 和 production library API 不得导出。

assigner 使用显式 preorder worklist，并维护 `NodeId -> exact preimage/path` map。两个不同 preimage
得到相同 candidate 时，必须以 `PF-SRC-NODEID-COLLISION` 拒绝整个 program；不得覆盖 origin、保留
first/last winner、登记 attribute、导出 `Source.Program`、写 CLI staging 或发布 partial table。
相同 preimage 被第二次访问表示 traversal compiler bug，必须以 `PF-INTERNAL` / stable context
`duplicate-node-visit` 拒绝，不能当作合法 alias，也不能降级成 collision 诊断。

collision test 至少注入 constant 16-byte candidate，使第二个不同 preimage deterministic collision；
duplicate-visit test 必须以受控 traversal fixture 重放同一 canonical preimage。test-only seam 不改变
canonicalSourceAstBytesV1 或 sourceHashV1。

## Cross-implementation golden contract

golden corpus 的每个 case 必须提供以下逻辑值；fixture container 可用仓库锁定格式，但任何实现都
必须比较相同 bytes，而不是重新 pretty-print AST：

```text
GoldenSourceProgramV1 {
  caseId,
  sourceUtf8,
  moduleName,
  programIdentity,
  expectedCanonicalBytes,
  expectedSourceHash,
  expectedNodePathsAndIds
}
```

每个 accepted vector 必须执行：

1. Lean command decoder 与 non-elaborating Loader 从同一 source 得到相等 ProgramV1；
2. reference Lean encoder 与至少一个不共享 encoder implementation 的 independent implementation
   产生 byte-for-byte 相同 `expectedCanonicalBytes` 和 `expectedSourceHash`；
3. 每个实现 decode golden bytes 后重新 encode，bytes 不变；
4. production NodeId 与 `expectedNodePathsAndIds` 相等；absolute/project-relative path 改变不影响
   bytes/hash/NodeId；module/program identity 改变必须改变 hash 与 NodeId；
5. unknown tag、wrong field count、bad option/Bool、non-NFC、length truncation/overflow、trailing byte、
   one-component QualifiedId/theorem、invalid width/bound、identity mismatch、node collision 和
   duplicate-node-visit vectors fail closed。

accepted golden 集合必须覆盖本规格每个 tag 至少一次，并覆盖 empty array、none/some、Unicode NFC、
decimal/hex 等值 integer、`u256` max、每个 UInt/Int fixed width 的 source literal 边界（负值通过
`Expr.Unary/UnaryOp.Neg` 表示）、length/bound `0` 与 `4096`、nested field/index Place、四种 Pattern、
statement/expression match、operator precedence、all program item kinds，以及 direct/array/option child
NodeId paths。tag/field coverage 由生成的 closed inventory 与本规格 tag list exact 比较；缺 tag 或
fixture 中出现 unknown tag 都失败。

至少一组 negative golden 必须针对每个 positive-field-count constructor 将 field count 改为 `n-1`
与 `n+1`，并针对每个 nullary constructor 将 `0` 改为 `1`；decoder 必须在构造该 node 前拒绝。
跨实现只比较最终 hash 而不保存 expected canonical bytes 不满足验收。

## 非目标与版本纪律

- 本规格不定义 concrete target materialization、runtime layout 或 proof system。
- 本规格不允许 arbitrary Lean term、macro callback、plugin payload 或 target-owned AST 混入 Source。
- span/origin 持久化若需要独立 wire，必须另立 schema；不得把它加入 sourceHash payload。
- 新 type/operator/place/pattern/statement/expression/item alternative 是 schema-breaking change。
- pure-fn call graph、pattern exhaustiveness、place resolution、visibility flow 和 proof theorem lookup
  都属于 D2；serializer 只做结构/canonical validation。

主验收是 `TST-SRC-001`；同时关联 `SPEC-LANG-001`、`MOD-SOURCE-001`、`FR-001/002/010` 与
`TST-SRC-005/006/007`。本规范仍为 `proposed`，且没有实现/正式 EV；完整 trace 即使存在也不能
单独关闭任何 task/test。
