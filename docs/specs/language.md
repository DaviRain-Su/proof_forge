---
id: SPEC-LANG-001
title: Program DSL 语言规格
status: proposed
owner: frontend
updated: 2026-07-16
normative: true
---

# Program DSL 语言规格

## 目标与非目标

定义唯一、可定位、可确定性 elaboration 的 Lean 自定义 command DSL。作者写业务语义，
不写目标、VM、部署类别或机器指令。DSL 不接受任意 Lean term；Lean 证明只能通过
显式 `proof ... using Qualified.Name` 引用。

## 文件与命名

源码是 UTF-8 Lean 文件，必须 `import ProofForgeV2` 并 `open ProofForgeV2.Language`。
一个文件可声明多个 program；其 identity 是 Lean module namespace 加声明名组成的
fully-qualified `Name`。名字采用 NFC，关键字 ASCII、大小写敏感。

```lean
program Counter where
  state count : UInt64
  init(initial : UInt64) do
    count := initial
  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count
  view get() : UInt64 do
    return count
```

## 词法

identifier 遵循 Lean identifier；decimal/hex 整数禁止符号内嵌，负号是一元操作；
string 使用 Lean 转义但规范值为 Unicode scalar sequence；`//` 与 `/- -/` 注释不进入
source hash。保留词：`program where state struct enum const event error init entry view fn
invariant requires extension version digest proof using do let if then else match with for in
bounded assert revert emit return call schedule public private commitment true false`。

## EBNF

```text
Program       ::= "program" Ident "where" ProgramItem+
ProgramItem   ::= StateDecl | StructDecl | EnumDecl | ConstDecl | EventDecl
                | ErrorDecl | InitDecl | EntryDecl | ViewDecl | FnDecl
                | InvariantDecl | ExtensionReq | ProofDecl
Visibility    ::= "public" | "private" | "commitment"
StateDecl     ::= "state" Visibility? Ident ":" Type
StructDecl    ::= "struct" Ident "where" FieldDecl+
FieldDecl     ::= Ident ":" Type
EnumDecl      ::= "enum" Ident "where" ("|" Ident ("(" TypeList ")")?)+
ConstDecl     ::= "const" Ident ":" Type ":=" Expr
EventDecl     ::= "event" Ident "(" ParamList? ")"
ErrorDecl     ::= "error" Ident ("(" ParamList? ")")?
InitDecl      ::= "init" "(" ParamList? ")" "do" Block
EntryDecl     ::= "entry" Ident "(" ParamList? ")" ReturnType? "do" Block
ViewDecl      ::= "view" Ident "(" ParamList? ")" ReturnType? "do" Block
FnDecl        ::= "fn" Ident "(" ParamList? ")" ReturnType? "do" Block
InvariantDecl ::= "invariant" Ident ":" Expr
ExtensionReq  ::= "requires" "extension" QualifiedId "version" String
                  "digest" String
ProofDecl     ::= "proof" Ident "using" QualifiedName
Param         ::= Visibility? Ident ":" Type
ParamList     ::= Param ("," Param)*
TypeList      ::= Type ("," Type)*
ExprList      ::= Expr ("," Expr)*
PatternList   ::= Pattern ("," Pattern)*
ReturnType    ::= ":" Type
TypeAnn       ::= ":" Type
Type          ::= Primitive | Ident | "Array" Type Nat | "Map" Type Type
                | "Option" Type | "Bytes" Nat | "Field" Ident
Block         ::= Stmt+
Stmt          ::= "let" Ident TypeAnn? ":=" Expr
                | Place ":=" Expr
                | "if" Expr "then" Block ("else" Block)?
                | "match" Expr "with" StmtMatchArm+
                | "for" Ident "in" Expr "..<" Expr "bounded" Nat "do" Block
                | "assert" Expr ("else" Ident)?
                | "revert" Ident ("(" ExprList? ")")?
                | "emit" Ident "(" ExprList? ")"
                | "return" Expr?
                | "call" ExternalCallExpr
                | "schedule" ExternalCallExpr
StmtMatchArm  ::= "|" Pattern "=>" "do" Block
ExprMatchArm  ::= "|" Pattern "=>" Expr
LocalFnCall   ::= Ident "(" ExprList? ")"
ExternalCallExpr ::= QualifiedId "(" ExprList? ")"
ConstructorExpr ::= QualifiedId "(" ExprList? ")"
MatchExpr     ::= "match" Expr "with" ExprMatchArm+
Place         ::= Ident PlaceSuffix*
PlaceSuffix   ::= "." Ident | "[" Expr "]"
Pattern       ::= "_" | Ident | Literal | ConstructorPattern
ConstructorPattern ::= QualifiedId "(" PatternList? ")"

Expr          ::= MatchExpr | LogicOrExpr
LogicOrExpr   ::= LogicAndExpr ("||" LogicAndExpr)*
LogicAndExpr  ::= BitOrExpr ("&&" BitOrExpr)*
BitOrExpr     ::= BitXorExpr ("|" BitXorExpr)*
BitXorExpr    ::= BitAndExpr ("^" BitAndExpr)*
BitAndExpr    ::= CompareExpr ("&" CompareExpr)*
CompareExpr   ::= ShiftExpr (("==" | "!=" | "<" | "<=" | ">" | ">=") ShiftExpr)?
ShiftExpr     ::= AddExpr (("<<" | ">>") AddExpr)*
AddExpr       ::= MulExpr (("+" | "-") MulExpr)*
MulExpr       ::= UnaryExpr (("*" | "/" | "%") UnaryExpr)*
UnaryExpr     ::= ("-" | "!" | "~") UnaryExpr | PrimaryExpr
PrimaryExpr   ::= Literal | ConstructorExpr | LocalFnCall | Place | "(" Expr ")"
Literal       ::= "true" | "false" | IntegerLiteral | StringLiteral
QualifiedId   ::= Ident "." Ident ("." Ident)*
QualifiedName ::= Ident ("." Ident)+
```

`Primitive` 为 `Bool`、`UInt8/16/32/64/128/256`、`Int8/16/32/64/128/256`、
`Principal`、`Unit`。数组长度、Bytes 长度和 loop bound 必须是 0..4096 的十进制常量。
Phase 1 的 `Field Ident` 只接受 exact identifier `bn254_fr`；它在 D2 target-neutral normalization
中映射到 `proof-forge.field.bn254-fr.v1`。其他 field identifier 必须拒绝，不能由 target/profile 或
ambient registry 解释。

上述 EBNF 使用 Lean layout/offside：`where`/`do`/`then`/`else` 后的 `Block` item 必须比引入 token
更深缩进；回到引入列结束 block。match arm 的 `|` 必须位于同一 arm column，新的 arm 结束前一
`StmtMatchArm` 的 `do` block。逗号只允许在上述 list production 内，不允许 trailing comma。
`IntegerLiteral` 只允许无符号 decimal 或 `0x` lowercase-prefix hex token；`StringLiteral` 使用词法节的
Lean escape 子集。parser 必须按上表 precedence 自低到高解析；除 comparison 为 non-associative 外，
同层 binary operator 左结合，unary 右结合。`&&`/`||` 左到右 short-circuit，其他 binary operand
均左到右求值。

unqualified `Ident(...)` 在 Source AST 中只能是 `LocalFnCall`；constructor 必须使用至少两个 component
的 `QualifiedId(...)`。Phase 1 canonical constructor identity 固定为 `StructName.new`、
`EnumName.Variant`、`Option.some` 或 `Option.none`，即使零 payload 也必须写 `()`；pattern 使用相同
qualified identity，因此 bare `Ident` 始终是 binding。`call`/`schedule` 关键字提供上下文，使相同
QualifiedId call syntax 只构造 `ExternalCallExpr`。这些分类在 D1 即确定，D2 只做 exact declaration/
type/arity lookup，不得根据 target 或运行时重新分类。

## 语义约束

- program 至少有一个 `entry` 或 `view`；`init` 最多一个。
- program item、field、variant、callable 和 parameter 在各自 scope 唯一。
- 默认 parameter/state visibility 为 `public`；省略返回类型等价 `Unit`。
- `fn` 只能是 pure local helper；不读取/写入 state/context，不产生 host、state、workflow、
  disclosure effect，只允许 checked arithmetic/assert/显式 revert 的确定性 `failure.revert`。表达式中的
  `LocalFnCall` 只解析同一 program 的 `fn`，不会解析 entry/view/init 或外部目标；被调函数可在
  调用点之后声明，但整个 local-fn call graph 必须无环。
- `view` 可读 state，不可写 state、emit、call 或 schedule。
- `entry/init` 可写 state；`init` 不可被普通 invocation 调用。
- 表达式从左到右求值；不支持 operator overloading 或隐式 numeric coercion。
- statement `call` 是同步外部调用，`schedule` 是异步 workflow intent；其
  `ExternalCallExpr` 不参与 local-fn 名称解析，两者均产生 requirements。
- `proof x using N` 中 `x` 精确绑定同一 program 内名为 `x` 的 invariant；`x` 不是新的 proof
  名称。每个 invariant 最多一个 proof reference，未知 invariant、重复 reference 或短名/别名
  匹配均失败。D1 只把 `(invariantName, theoremQualifiedName, origin)` 保存到 `Source.Program`；
  invariant Bool typing 属于 type/effect 检查；theorem lookup/signature validation 必须等 canonical
  `SemanticProgramV1` 生成、validate 与 hash 完成后执行。

## Pure fn 与 proof reference 契约

`LocalFnCall` 按同一 program 的 callable table 做 exact、case-sensitive lookup。callee 必须是
`fn`，实参数量和每个参数类型必须 exact，返回类型就是表达式类型；没有默认参数、隐式 cast、
overload 或 entry fallback。非 `Unit` `fn` 的每条可达路径必须返回一个 exact return type 的值；
`Unit` 才允许无值 `return` 或末尾 fallthrough。参数按声明顺序求值，callee body 随后按普通
left-to-right 语义执行；callee 的确定性 failure 原样传播且不提交 caller state/effect。直接或间接
递归以 `PF-BOUND-001` 拒绝。

type/effect 检查先确认 invariant 为 Bool、pure-fn closure 无环且只有允许的 pure failure；随后
normalization 在不读取 proof bundle 的情况下产生并 validate 唯一 canonical
`program : SemanticProgramV1`。compiler 按 canonical invariant array 的 exact NFC name 找到 `x`
的 ordinal `i`，expected theorem type 唯一为：

```lean
ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1 program i
```

其 state conformance、predicate evaluation、revert/trap 和 closed-program binding 由
[`SPEC-SEM-001`](semantic-core.md) 与
[`SPEC-SEM-WIRE-001`](semantic-program-wire.md) 唯一定义；不得再次从 Source/Typed AST 拼装另一份 theorem
statement，也不得只把 `semanticHash` 当成 proposition。`N` 必须与 CLI digest-pinned
`ProofBundleV1` 的 exact export 对应；manifest 的 invariant name/ordinal/theorem name、bundle
sourceHash/semanticHash/semanticProvenanceDigest 与 compiler 当前 canonical source/program/provenance
必须全部匹配，且 theorem type 与上述 closed
expected type definitionally equal。proof bundle trust policy、locked `.olean` closure 与 safe loader
规则同样由 SPEC-SEM-001 拥有。

同文件稍后声明、ambient Lean environment、project/parent `.lake`、`LEAN_PATH` 或任意 term
elaboration 都不能满足 `N`。unknown theorem、bundle 缺失/过期、signature/ordinal/program
mismatch、axiom/`sorryAx`/`unsafe`/`partial`/extern/initializer/plugin dependency 均 fail closed。
proof reference 是 `Source.ProgramV1` 的 source-level certification metadata，因此新增、删除或修改
`ProofDecl` 必须改变 canonical source bytes 与 `sourceHash`。successful validation record 不再改写
Source.Program 或 `sourceHash`；proof reference 与 validation record 都不得改变 Typed/Semantic 业务执行、
requirements、`semanticHash` 或 target 选择。失败不得进入 target resolution/Plan。

## Elaboration 与导出

当前 alpha parser/decoder 产生 `Source.Program`；完整 D1 parser 将为节点补齐 `NodeId`、
byte span、line/column。`Source.ProgramV1` 的完整 constructor/ordered-field schema、node-bearing
集合、binary wire 与 path traversal 由
[`SPEC-SOURCE-WIRE-001`](source-program-wire.md) 唯一拥有。`normalizedSyntacticPath` 是从 program
root 到该节点的序列，每段恰为 `{parentTag,fieldTag,index}`；tag/field 必须是该 wire 规格中的
exact ASCII constructor/ordered-field 名，index 是该 field 内从 0 开始的无符号位置。
module/program 名以 QualifiedName component array 表示，全部字符串先 NFC。NodeId 的 128-bit
candidate 为：

```text
first-16-bytes(SHA-256("pf.source-node.v1" || NUL ||
  JCS({module:[...], program:[...], path:[{parentTag,fieldTag,index}, ...]})))
```

root 的 path 为空 array。wire form 按 SPEC-COMMON-001 为 `nodeid:<32 lowercase hex>`；
不含绝对/项目相对路径、span、line/column、注释或内存分配顺序。
128-bit 截断值不是数学唯一性声明。D1 必须按 SPEC-SOURCE-WIRE-001 保存
`NodeId -> exact canonical preimage`：不同 preimage 得到同一 candidate 时稳定返回
`PF-SRC-NODEID-COLLISION` 并拒绝整个 program/attribute/output；相同 preimage 被二次访问是
`PF-INTERNAL`/`duplicate-node-visit`。禁止 first/last winner、重新加盐、扩宽后静默继续或由 CLI/
target 替换 production SHA-256。
每个 command 生成：

```lean
@[proof_forge_program]
def Counter : ProofForgeV2.Source.Program := ...
```

persistent environment extension 只登记 fully-qualified name 与 schema version；payload
由常量求值获得。导入顺序不影响排序，loader 按 UTF-8 qualified name 排序。重复 identity
为 `PF-EXPORT-001`；多候选且缺少 `--program` 为 `PF-EXPORT-002`。

## Syntax 资源预检

当前 alpha 把预算域冻结为**单个 portable `program` command 的 Lean `Syntax` 子树**，
不是整个 `.lean` module 的累计 AST。`preflightSyntax` 使用显式 Array 工作栈，不递归；root
depth 从 1 开始，沿 `Syntax.getArgs` 可达的 node、atom、identifier 与 missing 值都计入节点数。
每个 command 最多 100000 nodes、root-inclusive nesting 最多 256；fully-qualified program
identity 和单个 identifier 也最多 256 个 `Name` components。恰好 100000/256 接受，
100001/257 以 `PF-BOUND-001` 拒绝。

namespace scope 的瞬时深度不是 program identity。CLI Loader 允许 scope 临时超过 256
components，并以不构造超限聚合 `Name` 的可恢复状态跟踪；若随后退回 255 components 再声明
单 component program，最终 256-component identity 必须与 Lean command 路径一致地接受。
若 program 仍位于超限 scope 则拒绝。program Syntax 与 identity 同时超限时，两个入口都先
返回 Syntax preflight 的诊断，再判断 identity。

两条生产路径共享 `decodeProgramCommandChecked`：CLI parent 先执行 bounded 16 MiB read，并在
`proof-forge.resource.frontend.v1` containment 中启动 parser worker；worker 在 Lean parser 产出每个
program command 后预检，再 whitelist/decode。Lean command elaborator 调用同一 checked
decoder，再 quote 其返回值，但整个 Lean process 必须由同等或更严格的 outer build runner
contain。文件上限返回 `PF-SRC-INVALID`；有效源码恰好 16 MiB 接受，16 MiB+1 拒绝。未受控的
直接 `lake env lean`/library 调用不属于 untrusted-source 或 formal-evidence surface。

### 双前端单一 decode/validation 契约

`decodeProgramCommandChecked` 返回的 validated `Source.Program` 是 CLI Loader 与 Lean
command elaborator 的唯一业务 AST。共享 validation 在 decode 后按固定顺序检查：至少一个
entry/view、state 名唯一、entry 名唯一、event 名唯一、error 名唯一、struct 名唯一、enum 名唯一、
initializer 参数名唯一、每个 struct field 按 struct 声明顺序非空且名称唯一、每个 enum variant
按 enum 声明顺序非空且名称唯一、每个 event 参数名按 event 声明顺序唯一、每个 error 参数名按
error 声明顺序唯一、每个 entry 参数名唯一；
duplicate initializer 仍在构造 `Source.Program` 前拒绝。Loader 只拥有 module header/
command whitelist、namespace stack、module 内 program identity 去重和 selection，不得另有
per-program declaration validator。

当前 D1 pre-acceptance alpha 将 event/error 的 exact name 与 parameter order 保存在
`Source.Program` 并纳入 `pf.source.v1` development binding；`error E` 与 `error E()` 物化为同一
空参数 carrier。Typed/Semantic 的 declaration tables 完成前，任一非空 event/error table 必须在
`Typed.check` fail closed，不得被静默删除后进入 requirement resolution 或 target Plan。该 alpha
projection 还不是 `SPEC-SOURCE-WIRE-001` 的完整 ordered `Program.items` 实现，不能作为正式
`Source.ProgramV1` wire evidence。

当前 D1 pre-acceptance alpha 同样把 struct/enum 的 exact declaration name、field name/type、variant
name/payload type order 保存在独立 Source projection 并纳入 development source binding；完整
`Program.items` 落地前只保证 struct 与 enum 各自的 declaration order，不声称跨 kind source order。
`StructDecl.fields` 与 `EnumDecl.variants` 必须 nonempty；bare variant 是 nullary，带括号时 TypeList
必须 nonempty，因此 `| V()` 失败。Typed/Semantic named-type tables 完成前，任一非空 struct/enum
table 必须在 `Typed.check` fail closed。

为避免 ProofForge import 把 Lean 宿主中的 `struct`/`enum`/`event`/`error` 变成全局 parser keyword，
这些词只在 `pfItem` 首位按 raw token exact 识别；escaped keyword 或其他 leading identifier 失败。
其 semantic identifier 同时属于 DSL 保留词：program、declaration、parameter、expression 与
assignment 的 identifier decoder 对普通或 escaped 后值为上述名称统一返回 `PF-SRC-INVALID`，
但 DSL 外的 Lean declaration 仍可合法使用这些名称。

Lean command elaborator 必须从 decoded value quote 出 `@[proof_forge_program]` 常量；不得丢弃
decoded value 后再沿原始 `Syntax` 运行第二套 `expandType/expandParam/expandExpr/expandStatement/
expandItem` AST construction。quote 是 `Source.Program → Lean term` 的穷举编码，不重新解释
grammar、名称、visibility、类型或 statement。当前 alpha 的两入口相同错误继续使用
`PF-SRC-INVALID`；本切片不提前实现 Diagnostic v1。

Syntax preflight 本身不保护 Lean parser；规范保护来自 parser 之前已经生效的
`proof-forge.resource.frontend.v1` containment。该 node 边界不是多 program module 的累计上限，也不
约束直接构造 `Source.Program` 后调用 compiler API 的代码。当前 alpha 尚未实现 parser worker/
outer build containment，只能产生 development evidence；parser fuzz、完整 NodeId/span 和
module aggregate policy 仍由后续 D1/security 任务实现。

## SourceHash

`canonicalSourceAstBytesV1` 只用于已经通过 declaration-shape validation 的
`Source.ProgramV1`；它的 root、全部 constructor tag、`u16le` field count、ordered field、scalar/
array/option encoding、default materialization、decoder unknown rejection 和 cross-implementation golden
完全由 [`SPEC-SOURCE-WIRE-001`](source-program-wire.md) 定义。本文件不再维护第二份摘要编码表。

```text
sourceHash = SHA-256("pf.source.v1" || NUL || canonicalSourceAstBytesV1)
```

排除注释、空白、绝对/项目相对文件路径、span、line/column、NodeId 和非语义括号；
运算符优先级产生的 AST 结构不排除。schema/domain 改变必须发布新 source hash
version，不得重用 `pf.source.v1`。

## 错误与边界

`PF-SRC-001` 非法 token/grammar；`PF-SRC-010` 重复声明；`PF-SRC-020` 非法 item；
`PF-EXPORT-001/002` 导出冲突/选择歧义。必须覆盖：空 program、零 callable、重复 init、
重复 field/variant、NFC 冲突、跨 module 同短名、嵌套注释、非法转义、literal 超宽、
长度 0/4096/4097、loop bound 0/4096/4097、portable Syntax 深度 >256、单 command 节点
>100000、import
diamond、attribute schema mismatch、proof name 缺失、绝对路径改变但 hash 不变。

## 安全与验收

CLI source 限制 16 MiB；每个 portable program Syntax 子树限制 100000 nodes、nesting 256；
diagnostic 不回显 private literal。
验收关联 `FR-001/002/010`、`TST-SRC-001..008`、`TST-DIAG-001`，并要求 parser
fuzz 在 100 万 case 内无 crash/超限资源、跨 module identity 与 source hash 决定性通过。
