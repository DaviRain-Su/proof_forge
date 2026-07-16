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
ReturnType    ::= ":" Type
Type          ::= Primitive | Ident | "Array" Type Nat | "Map" Type Type
                | "Option" Type | "Bytes" Nat | "Field" Ident
Block         ::= Stmt+
Stmt          ::= "let" Ident TypeAnn? ":=" Expr
                | Place ":=" Expr
                | "if" Expr "then" Block ("else" Block)?
                | "match" Expr "with" MatchArm+
                | "for" Ident "in" Expr "..<" Expr "bounded" Nat "do" Block
                | "assert" Expr ("else" Ident)?
                | "revert" Ident ("(" ExprList? ")")?
                | "emit" Ident "(" ExprList? ")"
                | "return" Expr?
                | "call" CallExpr
                | "schedule" CallExpr
Expr          ::= literal | Place | constructor | unary | binary | call | match
```

`Primitive` 为 `Bool`、`UInt8/16/32/64/128/256`、`Int8/16/32/64/128/256`、
`Principal`、`Unit`。数组长度、Bytes 长度和 loop bound 必须是 0..4096 的十进制常量。

## 语义约束

- program 至少有一个 `entry` 或 `view`；`init` 最多一个。
- program item、field、variant、callable 和 parameter 在各自 scope 唯一。
- 默认 parameter/state visibility 为 `public`；省略返回类型等价 `Unit`。
- `fn` 只能是 pure local helper；不读取/写入 state，不发 effect。
- `view` 可读 state，不可写 state、emit、call 或 schedule。
- `entry/init` 可写 state；`init` 不可被普通 invocation 调用。
- 表达式从左到右求值；不支持 operator overloading 或隐式 numeric coercion。
- `call` 是同步外部调用，`schedule` 是异步 workflow intent；两者均产生 requirements。
- `proof x using N` 中 N 必须解析为符合生成 theorem signature 的 Lean 常量；不展开
  任意语法到业务 IR。

## Elaboration 与导出

当前 alpha parser/decoder 产生 `Source.Program`；完整 D1 parser 将为节点补齐 `NodeId`、
byte span、line/column。NodeId 是
`SHA-256(moduleName, programName, normalized syntactic path)` 前 128 bit，不含绝对路径。
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

两条生产路径共享 `decodeProgramCommandChecked`：CLI 在 Lean parser 产出每个 program
command 后预检，再 whitelist/decode；Lean command elaborator 在递归 decode 和
`expandItem/expandExpr` 前预检。CLI 另在调用 Lean parser 前执行 16 MiB source-byte 上限，
该上限当前返回 `PF-SRC-INVALID`；有效源码恰好 16 MiB 接受，16 MiB+1 拒绝。直接
`lake env lean` 的 command 路径没有这项 CLI 文件上限。

这个边界不保护 Lean parser 本身，不是多 program module 的累计 node 上限，也不约束直接
构造 `Source.Program` 后调用 compiler API 的代码。parser fuzz、parser 进程 time/memory
containment、完整 NodeId/span 和 module aggregate policy 仍属于后续 D1/security 工作。

## SourceHash

hash 输入为 schema tag、qualified identity、NFC identifier/string、规范 literal 和 AST
结构的 length-prefixed canonical bytes。排除注释、空白、绝对/相对文件路径、line/column
和非语义括号；运算符优先级产生的 AST 不排除。算法固定 SHA-256。

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
