---
id: SPEC-LANG-001
title: Program DSL 语言规格
status: proposed
owner: frontend
updated: 2026-07-18
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

当前 pre-acceptance alpha decoder 已把 closed `UInt8/16/32/64/128/256` 与
`Int8/16/32/64/128/256` 的 exact 单 token spelling 保存为 declaration type carrier；width-aware
literal typing/bounds、负数语义与 Int arithmetic 仍属于 D2。该扩展不得改变 `Field bn254_fr` 的
two-token same-line guard，也不得重编号既有 canonical type tags。

当前 alpha 也接受 exact unqualified single-token `Unit` declaration carrier。entry、view 与 fn 省略
返回类型时，frontend 必须在构造 `Source.Program` 前 materialize 为 `Unit`；显式 `: Unit` 与省略形式
必须产生相同的 result carrier 与 canonical binding。该切片不实现无值 `return`、`Unit` fallthrough
或 D2 return-path/type checking，`init` 仍没有返回类型。

当前 alpha 还接受 exact unqualified single-token `Principal` declaration carrier。该 type carrier 本身
不读取 caller，不推导 `callerContext`，也不定义 principal literal、`context.caller`、authority 或
D2 value semantics；这些运行时语义必须由后续显式 expression/op 与 capability 规则引入，不能根据
declaration type 猜测。

D1-PA-18 冻结的 pre-acceptance alpha Option 子集只接受同一行的 `Option PrimitiveAtom`，其中
`PrimitiveAtom` 是当前已实现的 exact single-token `Bool`、closed UInt/Int width、`Principal` 或
`Unit`；该子集暂不接受 `Field bn254_fr`、Named、nested Option、Array、Map 或 Bytes element。
Source/Semantic carrier 为 `option(element)`；alpha canonical encoding 必须 append tag `16` 后递归追加
`element` 的既有 canonical type bytes，既有 tags `0..15` 不变。Semantic requirement 必须精确传播
`element.requirements`，不能把 `Option Bool` 降为零 requirement，也不能凭 Option 本身发明 capability。
该切片只保存 declaration type structure，不实现 none/some expression、unwrap、runtime representation、
recursive legality或 D2 type/effect semantics；超出该闭集的 payload 必须 fail closed。

D1-PA-19 冻结的 pre-acceptance alpha Bytes 子集只接受同一行的 `Bytes N`，其中 `N` 的 lexical
spelling 必须等于其 Nat 值的 canonical ASCII 十进制表示，且值位于 `0..4096`；因此除单个 `0`
外禁止前导零，也禁止 `_`、`0x`/`0b`/`0o`、符号、identifier、缺失/额外 payload 或跨行 payload。
Source/Semantic carrier 为 `bytes(length : UInt32)`，frontend 在构造 carrier 前完成 lexical 与 bound
检查。alpha canonical encoding append tag `17` 后使用各 encoder 已有的 `appendNat(length.toNat)`：
Source 为 8-byte big-endian，Semantic 为 8-byte little-endian；既有 tags `0..16` 不变。这个
encoder-local alpha binding 明确不是 `SPEC-SOURCE-WIRE-001`/`SPEC-SEM-WIRE-001` 的正式 `u32le`
Type wire，后者仍由其独立 stable encoder/decoder 负责。Bytes declaration 推导零 requirement；本切片
不实现 bytes literal、index/slice/length op、runtime representation、Option/Array/Map nesting 或 D2
type/value legality。直接伪造的 in-memory over-bound carrier 不属于 frontend accepted source；本切片
不把 alpha total hash helper 冒充 stable wire validator。

D1-PA-20 冻结的 pre-acceptance alpha `let` 子集只接受 existing initializer/callable body 内同一行的
`let name := Expr` 与 `let name : Type := Expr`。Source carrier 固定为
`Statement.letDecl(name, typeAnn : Option ValueType, value)`；alpha source canonical encoder 在既有
statement tags `0..2` 后 append tag `3`，随后依次编码 name、`typeAnn` 的 `0/1` marker（`some`
时紧接既有 type bytes）与 value expression。frontend 只保存 Source statement structure；
`Typed.check` 必须以 exact `let statements are not yet supported by typed checking` fail closed，且本切片
不得新增 local scope、shadowing、type inference、SemanticIR、requirement 或 target behavior。
`let` 使用 DSL category 内的 contextual parser，不新增宿主 Lean keyword；现有 escaped identifier
`«let» := 1` 仍表示给 identifier `let` 赋值，而 bare `let := 1` 继续停在 parser boundary；
state/parameter identifier policy 也不在本切片改变。unknown annotated type 与
reserved binder 在 decoder fail closed；escaped/qualified introducer、缺失 name/type/value/`:=` 与跨行
形态停在 parser boundary。不得为追求统一诊断而加入 generic fallback parser 或扩大已接受语法。

D1-PA-21 冻结的 pre-acceptance alpha Bool literal 子集只把 exact bare token `true` 与 `false`
解码为 `Source.Expr.boolLiteral(value : Bool)`。Source alpha canonical encoder 在既有 Expr tags `0..3`
后 append tag `4`，再 append 单个 marker byte：`false = 0`、`true = 1`；不得复用 UInt64 literal
`0/1` 或修改既有 expression tags/goldens。parser 必须使用 `pfExpr` category 内的 contextual named
parser 并优先于 generic identifier arm，不新增宿主 Lean keyword或 generic fallback；decoder/quote 必须
按 named parser structure 往返，禁止扫描任意 Syntax 子树。exact escaped `«true»`/`«false»`、
qualified `Std.true`/`Std.false`、`trueValue`/`falseValue` 及大小写不同的 identifier 不是 Bool
literal，继续按普通 identifier 进入既有 name-resolution boundary；本切片不得改变 portable identifier
policy。literal 后存在额外独立 token 的形态停在 parser boundary。`Typed.check` 遇到 `boolLiteral`
必须以 exact
`boolean literals are not yet supported by typed checking` fail closed；本切片不得新增 Typed/Semantic
Bool expression、requirement、target behavior 或 runtime representation。

D1-PA-22 冻结的 pre-acceptance alpha checked subtraction 子集把 binary `lhs - rhs` 解码为
`Source.Expr.checkedSub(lhs, rhs)`。`-` 与既有 `+` 同属 precedence `65`，parser 形状固定为
`pfExpr:65 " - " pfExpr:66`；因此 `9 - 4 - 1`、`1 + 2 - 3` 与 `1 - 2 + 3` 必须按源码顺序
左结合，且 operator kind/operand order 必须进入 Source AST 与 sourceHash。Source alpha canonical
encoder 在既有 Expr tags `0..4` 后 append tag `5`，随后递归编码 lhs、rhs；不得重编号既有 tag、
交换 operand 或把 subtraction 伪装成 addition/unary negation。decoder/quote 必须结构化往返既有
`pfExpr` syntax；binary operand 可使用当前 alpha expression，variable operand 保持 name，不新增
parenthesized expression、unary minus、signed literal、multiplication 或其他 operator。缺失 lhs/rhs 与
unary-minus spelling 停在 parser boundary。`Typed.check` 遇到 `checkedSub` 必须以 exact
`checked subtraction is not yet supported by typed checking` fail closed；本切片不得新增 Typed/Semantic
subtraction、arithmetic requirement、underflow rule、target behavior 或 runtime representation；既有
`checkedAdd` Typed/Semantic 正常路径必须保持不变。

D1-PA-23 冻结的 pre-acceptance alpha checked multiplication 子集把 binary `lhs * rhs` 解码为
`Source.Expr.checkedMul(lhs, rhs)`。parser precedence 固定为 `70`，形状固定为
`pfExpr:70 " * " pfExpr:71`；它高于既有 precedence `65` 的 `+`/`-`，且同层左结合，因此
`2 * 3 * 4`、`2 + 3 * 4`、`2 * 3 + 4`、`2 - 3 * 4` 与 `2 * 3 - 4` 必须保留 EBNF
`MulExpr`/`AddExpr` 的源码分组。Source alpha canonical encoder 在既有 Expr tags `0..5` 后 append
tag `6`，随后递归编码 lhs、rhs；不得重编号既有 tag、交换 operand 或把 multiplication 伪装成
repeated addition。decoder/quote 必须结构化往返既有 `pfExpr` syntax；binary operand 可使用当前 alpha
expression，variable operand 保持 name。本切片不新增 parenthesized expression、unary operator、division、
modulo 或其他 operator；缺失 lhs/rhs、重复 operator 与额外 token 停在 parser boundary。
`Typed.check` 遇到 `checkedMul` 必须以 exact
`checked multiplication is not yet supported by typed checking` fail closed；本切片不得新增
Typed/Semantic multiplication、arithmetic requirement、overflow rule、target behavior 或 runtime
representation。既有 `checkedAdd` 正常路径与 `checkedSub` exact fail-closed path 必须保持不变。

D1-PA-24 冻结的 pre-acceptance alpha parenthesized grouping 子集只接受 `(` `Expr` `)` 作为
`PrimaryExpr` grouping sugar，parser 形状固定为 `syntax:max "(" pfExpr:0 ")" : pfExpr`：外层结果是
可作为 `*` operand 的 high-precedence primary，内部 min precedence `0` 必须允许完整 `+`/`-`/`*`
expression。decoder 必须以结构化 quotation 取得内部 `pfExpr` 并递归返回同一 `Source.Expr`；不得新增 Source Expr ctor、
canonical tag/field、generic syntax scan 或 quote arm。因此冗余 grouping（如 `(42)`、`((x))`、
`(2 + 3)`）与未分组的同一表达式产生相同 Source AST、canonical bytes 与 sourceHash；grouping 改变
运算树时则必须保留改变后的结构，例如 `(2 + 3) * 4`、`7 - (3 - 1)`、`2 * (3 * 4)` 与
`2 * (3 + 4)` 分别形成 addition-before-multiplication、right-nested subtraction、right-nested
multiplication 与 multiplication-of-addition，且不得 alias 对应
left-nested/default-precedence tree。empty/unit `()`、tuple `(1, 2)`、group 内额外 payload、缺失括号、
group 后额外 token 与 call-like `f(1)` 必须停在 parser boundary；本切片不新增 tuple、call、constructor、
unary 或其他 expression kind，type position 的 `(UInt64)` 也不得被误收为 `pfType`。`quoteExpr`、
`Source.lean`、Source canonical encoder、`Typed.lean`/`Typed.check`、SemanticIR、requirements 与 target
pipeline 必须保持不变；grouped checkedAdd 继续正常通过，grouped Bool/checkedSub/checkedMul
只表现其内部表达式既有的 exact Typed boundary。

D1-PA-25 冻结的 pre-acceptance alpha unary checked negation 子集新增
`Source.Expr.checkedNeg(operand)`，parser 形状固定为 `syntax:75 "-" pfExpr:75 : pfExpr`。前缀与
operand 使用相同 precedence `75`，因此一元负号右结合，并且其 binding power 高于 `*`、`+` 和
binary `-`：`-2 * 3` 必须解析为 `(-2) * 3`，`-(2 + 3)` 保留 grouped operand，`1 - -2`、
`1 + -2` 与 `1 * -2` 接受一元表达式作为 binary operand，`- - 2` 保留两个 checked-negation
node。`-2` 与 `- 2` 都是对 unsigned literal 的 checked negation，不得折叠成 signed literal。
Source canonical encoder 以 append-only Expr tag `7` 后接 operand；既有 tags `0..6` 与 goldens
不得改变。`quoteExpr` 必须保留该节点；`Typed.check` 对其逐字 fail closed 为
`checked negation is not yet supported by typed checking`。

本切片明确 supersede D1-PA-22 中 `- 3`、`-3`、`7 - - 3`、`1 + - 2` 的临时 parser-negative
pin，以及 D1-PA-24 中 grouped `(- 3)` 的临时 unary-negative pin；这些用例从 PA25 起迁移为精确
positive AST pin，旧 evidence 仍只描述当时实现。Lean lexer 中无空格的 `--` 是 line comment
起点，不是两个一元负号：`--2` 不得被描述为 nested negation；`1--2` 的当前宿主词法行为是
literal `1` 后接 comment，测试必须将其固定为 comment-boundary control。需要表达 binary subtraction
of a negative operand 时，canonical source spelling 是 `1 - -2`。本切片不新增 `!`/`~`、signed
literal、constant folding、Typed/Semantic negation、arithmetic requirement、overflow rule、target
behavior 或 runtime representation；bare/malformed operator 与额外 payload 仍须停在 parser boundary。

D1-PA-26 冻结的 pre-acceptance alpha assert statement 子集只接受 existing initializer/callable body
中的 bare `assert Expr`，parser 形状固定为 `syntax "assert " pfExpr : pfStmt`。Source carrier 固定为
`Statement.assertStmt(condition : Expr)`；alpha source canonical encoder 在既有 Statement tags `0..3`
后 append tag `4`，随后递归编码 condition。decoder 与 `quoteStatement` 必须结构化保留 condition，
不得通过自由文本或 generic syntax scan 恢复。EBNF 中 optional `else Ident` 明确 deferred：
`assert Expr else Ident` 在本切片仍停在 parser boundary，不能被写成已实现的 declared-error binding。

`assert` 是 DSL statement reserved word，沿用 `return`/`call` 的 keyword syntax；bare
`assert := Expr` 必须拒绝，escaped `«assert» := Expr` 仍是普通 assignment identifier，其他以
`assert` 为前缀的 identifier 不得被误收。`Typed.checkStatement` 必须在检查 condition 之前逐字 fail
closed 为 `assert statements are not yet supported by typed checking`，因此 `assert true` 不得先泄漏
Bool expression 的既有 Typed diagnostic。本切片不得新增 Typed Statement ctor、condition Bool checking、
assertion failure/revert code、SemanticIR、requirement、effect、target behavior 或 runtime representation；
bare/missing condition、extra payload、optional else 与 block-like 形态必须保持 fail closed。

D1-PA-27 冻结的 pre-acceptance alpha unary bitwise-not 子集新增
`Source.Expr.bitwiseNot(operand)`，parser 形状固定为 `syntax:75 "~" pfExpr:75 : pfExpr`。它与
checked negation 使用同一 prefix precedence `75` 并右结合，高于 `*`、`+` 与 binary `-`：
`~2 * 3` 必须解析为 `(~2) * 3`，`~(2 + 3)` 保留 grouped operand，`1 - ~2` 与
`1 * ~2` 接受 unary operand，`~ ~ 2` 保留两个 bitwise-not node。mixed unary 的次序也必须保留：
`- ~ 2` 是 checked-negation of bitwise-not，`~ - 2` 是 bitwise-not of checked-negation，不得
constant-fold、互换或擦除节点。

Source canonical encoder 以 append-only Expr tag `8` 后接递归 operand；既有 tags `0..7` 与 goldens
不得改变。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 对其逐字 fail closed 为
`bitwise not is not yet supported by typed checking`。本切片不新增 logical `!`、shift/bitwise binary、
signed literal、constant folding、Typed/Semantic bitwise operation、requirement、target behavior 或
runtime representation；bare/malformed `~` 与额外 payload 保持 parser reject。当前测试中没有 `~`
parser-negative pin，因此本切片不得修改既有测试来制造迁移。

D1-PA-28 冻结的 pre-acceptance alpha unary logical-not 子集新增
`Source.Expr.logicalNot(operand)`，parser 形状固定为 `syntax:75 "!" pfExpr:75 : pfExpr`。它与
checked negation/bitwise-not 使用同一 prefix precedence `75` 并右结合，高于 `*`、`+` 与 binary
`-`：`!2 * 3` 必须解析为 `(!2) * 3`，`!(2 + 3)` 保留 grouped operand，`1 - !2`
与 `1 * !2` 接受 unary operand，`! ! 2` 保留两个 logical-not node。mixed unary 次序必须保留：
`- ! 2`/`! - 2` 与 `~ ! 2`/`! ~ 2` 分别形成不同树，不得交换、折叠或擦除节点。

logical-not 在业务语义上是 Bool operation，但 D1 Source frontend 只保存 intent，不在本切片检查 operand
类型；因此 literal/variable/Bool/其他当前 Expr 均可形成 Source node，Bool type legality 属于 D2。
Source canonical encoder 以 append-only Expr tag `9` 后接递归 operand；既有 tags `0..8` 与 goldens
不得改变。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 逐字 fail closed 为
`logical not is not yet supported by typed checking`，且不得先泄漏 operand 的 Bool/arithmetic diagnostic。
本切片不新增 `!=` comparison、`&&`/`||`、Bool typing、constant folding、Semantic/requirement、target
behavior 或 runtime representation；`1 != 2`、bare/malformed `!` 与额外 payload 保持 parser reject。
`! = 2` 也必须拒绝，不能把 deferred comparison token 拆成 logical-not 加残余 payload。
当前测试中没有 DSL `!` parser-negative pin，因此本切片不得修改既有测试来制造迁移。

D1-PA-29 冻结的 pre-acceptance alpha binary checked-division 子集新增
`Source.Expr.checkedDiv(lhs, rhs)`，parser 形状固定为
`syntax:70 pfExpr:70 " / " pfExpr:71 : pfExpr`。它与 multiplication 使用相同 precedence `70`
并左结合，高于 precedence `65` 的 `+`/binary `-`，低于 prefix precedence `75`：`6 / 3 / 2`
必须解析为 `(6 / 3) / 2`，`2 * 6 / 3` 为 `(2 * 6) / 3`，`8 / 4 * 2` 为
`(8 / 4) * 2`，`1 + 6 / 3` 与 `6 / 3 + 1` 保留 MulExpr/AddExpr 分组，`(1 + 2) / 3`
保留 grouped lhs；`6 / (3 / 2)` 与 `2 * (6 / 3)` 必须保留显式 right/grouped tree。
`8 / 4 - 2` 必须是 `(8 / 4) - 2`，`-8 / 4` 与 `8 / -4` 的 unary operand 均高于 division。
`8 / 0` 必须形成 Source node；除零 legality 属于 D2/target，不得在 Source/parser 提前拒绝。
不得交换 operand、把 division 改写成 multiplication，或提前执行除零/常量计算。

Source canonical encoder 以 append-only Expr tag `10` 后依次递归编码 lhs、rhs；既有 tags `0..9`
与 goldens 不得改变。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand
之前逐字 fail closed 为 `checked division is not yet supported by typed checking`。本切片只允许把
`CheckedMul` 中 `2 / 3` 与 `Grouping` 中 `(2 / 3)` 两条既有 parser negative 在同一个 tests-only RED
迁移为 division positives；`%` negatives 必须保留。不得新增 modulo、signed/zero-division semantics、
constant folding、Typed/Semantic division、requirement、target behavior 或 runtime representation；
bare/missing operand、`2 // 3`、repeated/mixed operator 与额外 payload 保持 parser reject。production
只允许修改 `Source.lean` 的 ctor/encoder、`Syntax.lean` 的 production/decode/quote 与 `Typed.lean` 的
direct fail-closed arm（共 3 文件/11 行）；Typed Expr、SemanticIR/Semantics、requirements、targets、
preflight 与 generic negative table 均不得修改。本切片只实现 `/`，不得把 `MulExpr` 写成已完整实现。

D1-PA-30 冻结的 pre-acceptance alpha binary checked-modulo 子集新增
`Source.Expr.checkedMod(lhs, rhs)`，parser 形状固定为
`syntax:70 pfExpr:70 " % " pfExpr:71 : pfExpr`。它与 multiplication/division 使用相同 precedence
`70` 并跨 operator 左结合，高于 additive precedence `65`，低于 prefix precedence `75`：
`7 % 3 % 2` 必须为 `(7 % 3) % 2`，`2 * 7 % 3` 为 `(2 * 7) % 3`，`7 % 3 * 2`
为 `(7 % 3) * 2`，`8 / 4 % 2` 为 `(8 / 4) % 2`，`8 % 4 / 2` 为 `(8 % 4) / 2`；
`1 + 7 % 3`、`7 % 3 - 1`、`(1 + 2) % 3`、`7 % (3 % 2)` 与 unary operands 必须保留
各自 grouping。`8 % 0` 必须形成 Source node；modulo-by-zero legality 属于 D2/target，不得提前拒绝。

Source canonical encoder 以 append-only Expr tag `11` 后依次递归编码 lhs、rhs；既有 tags `0..10`
与 goldens 不得改变。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand
之前逐字 fail closed 为 `checked modulo is not yet supported by typed checking`。同一个 tests-only RED
必须且只能迁移 3 个 suite 中 4 条 percent negative：`CheckedMul` 的 `2 % 3`、`Grouping` 的
`(2 % 3)`，以及 `CheckedDiv` 新增的 `2 % 3`/`(2 % 3)` retention controls。不得新增
modulo-by-zero、Int/signed/rounding/sign semantics、constant folding、Typed/Semantic modulo、requirement、
target behavior 或 runtime representation；bare/missing operand、`2 %% 3`、repeated/mixed operator 与
额外 payload 保持 parser reject。production 只允许 Source/Syntax/Typed 3 文件/11 行 exact seam，
不得修改 Typed Expr、SemanticIR/Semantics、requirements、targets、preflight 或 generic negative table。
本切片完成后只能称 `*`/`/`/`%` 的 Source surface 已覆盖，不得宣称 `MulExpr`、expression grammar 或
`TASK-D1-04` 正式完成。

D1-PA-31 冻结的 pre-acceptance alpha shift-left 子集新增 `Source.Expr.shiftLeft(lhs, rhs)`，parser
形状固定为 `syntax:60 pfExpr:60 " << " pfExpr:61 : pfExpr`。它严格低于 AddExpr precedence `65`
并左结合，高于未来 Compare 层：`1 + 2 << 3` 必须为 `(1 + 2) << 3`，`1 << 2 + 3` 必须为
`1 << (2 + 3)`，`8 << 2 * 3` 为 `8 << (2 * 3)`，`8 * 2 << 3` 为 `(8 * 2) << 3`，
`1 << 2 << 3` 为 `(1 << 2) << 3`；`1 << (2 << 3)` 保留显式 right-nested tree，unary operand
继续以 precedence `75` 绑定。不得把 shift 误放到 additive/multiplicative precedence 或重排 operands。

Source canonical encoder 以 append-only Expr tag `12` 后依次递归编码 lhs、rhs；既有 tags `0..11`
与 goldens 不得改变。`1 << 0` 与 `1 << 64` 必须形成 Source node；shift-count zero/over-width legality
属于 D2/target，不得提前拒绝。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一
operand 前逐字 fail closed 为 `shift left is not yet supported by typed checking`。当前仓库没有 DSL
`<<`/`>>` negative，因此本切片不得迁移既有 tests；`1 >> 2` 必须作为 deferred shift-right retention
control 停在 parser boundary。本切片不得新增 `>>`、signed/arithmetic shift、rotate、width/overflow
semantics、constant folding、Typed/Semantic shift、requirement、target behavior 或 runtime representation；
bare/missing operand、`1 < < 2`、`1 <<< 2` 与额外 payload 保持 parser reject。production 必须限于
Source/Syntax/Typed 3 文件/11 行 exact seam，其他层不得修改。本切片只实现 `<<`，不得宣称
`ShiftExpr`、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-32 冻结的 pre-acceptance alpha shift-right 子集新增 `Source.Expr.shiftRight(lhs, rhs)`，parser
形状固定为 `syntax:60 pfExpr:60 " >> " pfExpr:61 : pfExpr`。它与 shift-left 使用相同 ShiftExpr
precedence `60` 并跨 operator 左结合，严格低于 AddExpr/MulExpr：`1 + 2 >> 3` 必须为
`(1 + 2) >> 3`，`1 >> 2 + 3` 为 `1 >> (2 + 3)`，`8 >> 2 * 3` 为 `8 >> (2 * 3)`，
`8 * 2 >> 3` 为 `(8 * 2) >> 3`，`1 >> 2 >> 3` 为 `(1 >> 2) >> 3`；
`1 << 2 >> 3` 必须为 `(1 << 2) >> 3`，`1 >> 2 << 3` 为 `(1 >> 2) << 3`，
`1 >> (2 >> 3)` 保留显式 right-nested tree，unary operands 继续以 precedence `75` 绑定。

Source canonical encoder 以 append-only Expr tag `13` 后依次递归编码 lhs、rhs；既有 tags `0..12`
与 goldens 不得改变。`1 >> 0` 与 `1 >> 64` 必须形成 Source node；count legality 属于 D2/target，
不得提前拒绝。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字
fail closed 为 `shift right is not yet supported by typed checking`。同一个 tests-only RED 必须且只能把
`ShiftLeft.lean` 的 deferred `1 >> 2` 一条 negative 迁移为 exact positive，并保持其他 tests 不变。
本切片不得决定 arithmetic-vs-logical/signed shift-right、rotate、width/overflow、constant folding、
Typed/Semantic shift、requirement、target behavior 或 runtime representation；bare/missing operand、
`1 > > 2`、`1 >>> 2` 与额外 payload 保持 parser reject。production 必须限于 Source/Syntax/Typed
3 文件/11 行 exact seam，其他层不得修改。本切片完成后只能称 `<<`/`>>` Source surface 已覆盖，
不得宣称 `ShiftExpr`、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-33 冻结的 pre-acceptance alpha equality 子集新增 `Source.Expr.equal(lhs, rhs)`，parser 形状固定为
`syntax:50 pfExpr:51 " == " pfExpr:51 : pfExpr`。precedence `50` 严格低于 ShiftExpr `60`；两个 operand
slot 都使用 `51`，从语法结构落实 EBNF 中 CompareExpr 的 optional comparison 和 non-associativity：
`1 == 2 == 3` 必须 parser reject。`1 << 2 == 3` 必须为 `(1 << 2) == 3`，
`1 == 2 >> 3` 为 `1 == (2 >> 3)`，additive/multiplicative/unary 在两侧同理；parenthesized equality
仍作为 PrimaryExpr 允许嵌入更高层表达式。未来 BitAndExpr 必须使用低于 `50` 的 precedence，不得反转
EBNF 层级。

Source canonical encoder 以 append-only Expr tag `14` 后依次递归编码 lhs、rhs；既有 tags `0..13`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，operand legality 与 Bool result
typing 属于 D2，不得提前拒绝。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一
operand 前逐字 fail closed 为 `equality is not yet supported by typed checking`。当前仓库没有 DSL `==`
negative，本切片不得迁移既有 tests；`LogicalNot.lean` 的 `1 != 2` retention negative 必须保持。
本切片不得新增 `!=`、`<`、`<=`、`>`、`>=`、bitwise/logical binary operator、Bool legality、constant
folding、Typed/Semantic comparison、requirement、target behavior 或 runtime representation；bare/missing
operand、single/spaced/triple equals、chained equality、未实现的 ordering siblings 与额外 payload 保持
parser reject。production 必须限于 Source/Syntax/Typed 3 文件/11 行 exact seam，其他层不得修改。
本切片完成后只能称 `==` Source surface 已覆盖，不得宣称 `CompareExpr`、expression grammar 或
`TASK-D1-04` 正式完成。

D1-PA-34 冻结的 pre-acceptance alpha not-equal 子集新增 `Source.Expr.notEqual(lhs, rhs)`，parser 形状
固定为 `syntax:50 pfExpr:51 " != " pfExpr:51 : pfExpr`。它与 `equal` 共用 Compare precedence `50`，
两个 operand slot 都使用 `51`；同类 `1 != 2 != 3` 以及 mixed `1 == 2 != 3`、
`1 != 2 == 3` 都必须 parser reject，落实 EBNF 中至多一个 comparison 的约束。Shift/Add/Mul/Unary
在两侧继续以更高 precedence 绑定；parenthesized comparison 仍可作为 PrimaryExpr。

Source canonical encoder 以 append-only Expr tag `15` 后依次递归编码 lhs、rhs；既有 tags `0..14`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，operand legality 与 Bool result
typing 属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字
fail closed 为 `not-equal comparison is not yet supported by typed checking`。同一个 tests-only RED 必须且
只能把 `LogicalNot.lean` 的 deferred `1 != 2` 一条 negative 迁移为 exact positive；相邻的 spaced
`! = 2` 必须保持 parser reject，证明 `!=` 是完整 binary token 而非 unary `!` 加残余 `=`。
`1 ! = 2`、`1 !== 2`、`1 ! == 2`、same/mixed chained comparison 与额外 payload 同样必须拒绝。
本切片不得新增 `<`、`<=`、`>`、`>=`、bitwise/logical binary operator、Bool legality、constant folding、
Typed/Semantic comparison、requirement、target behavior 或 runtime representation；production 必须限于
Source/Syntax/Typed 3 文件/11 行 exact seam，其他层不得修改。本切片完成后只能称 `==`/`!=` equality
pair 的 Source surface 已覆盖，不得宣称 `CompareExpr`、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-35 冻结的 pre-acceptance alpha less-than 子集新增 `Source.Expr.lessThan(lhs, rhs)`，parser 形状固定为
`syntax:50 pfExpr:51 " < " pfExpr:51 : pfExpr`。它与 `equal`/`notEqual` 共用 Compare precedence `50`，
两个 operand slot 都使用 `51`；同类 `1 < 2 < 3` 以及与 `==`/`!=` 组成的任意 mixed comparison chain
都必须 parser reject，继续落实 EBNF 中至多一个 comparison 的约束。Shift/Add/Mul/Unary 在两侧以更高
precedence 绑定；`1 << 2 < 3` 必须为 `(1 << 2) < 3`，`1 < 2 << 3` 必须为
`1 < (2 << 3)`，parenthesized comparison 仍可作为 PrimaryExpr。

Source canonical encoder 以 append-only Expr tag `16` 后依次递归编码 lhs、rhs；既有 tags `0..15`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，operand legality 与 Bool result
typing 属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字
fail closed 为 `less-than comparison is not yet supported by typed checking`。同一个 tests-only RED 必须且
只能把 `Equal.lean` 的 deferred `1 < 2` 一条 negative 迁移为 exact positive；相邻的 `<=`、`>`、`>=`
ordering siblings 必须继续 parser reject。`1 << 2` 必须继续形成 shift-left，`ShiftLeft.lean` 的
`1 < < 2` 与 `1 <<< 2` 必须继续拒绝，证明单字符 `<` 未破坏最长 token 与 parser boundary。
本切片不得新增 `<=`、`>`、`>=`、bitwise/logical binary operator、Bool legality、constant folding、
Typed/Semantic comparison、requirement、target behavior 或 runtime representation；production 必须限于
Source/Syntax/Typed 3 文件/11 行 exact seam，其他层不得修改。本切片完成后只能称 `<` Source surface
已覆盖，不得宣称 `CompareExpr`、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-36 冻结的 pre-acceptance alpha less-or-equal 子集新增 `Source.Expr.lessEqual(lhs, rhs)`，parser
形状固定为 `syntax:50 pfExpr:51 " <= " pfExpr:51 : pfExpr`。它与 `equal`/`notEqual`/`lessThan`
共用 Compare precedence `50`，两个 operand slot 都使用 `51`；`1 <= 2 <= 3` 以及 `<=` 与三个既有
comparison 组成的双向 mixed chains 都必须 parser reject。Shift/Add/Mul/Unary 在两侧以更高 precedence
绑定；`1 << 2 <= 3` 必须为 `(1 << 2) <= 3`，`1 <= 2 << 3` 必须为
`1 <= (2 << 3)`，parenthesized comparison 仍可作为 PrimaryExpr。

Source canonical encoder 以 append-only Expr tag `17` 后依次递归编码 lhs、rhs；既有 tags `0..16`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，operand legality 与 Bool result
typing 属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字
fail closed 为 `less-equal comparison is not yet supported by typed checking`。同一个 tests-only RED 必须且
只能把 `Equal.lean` 的 deferred `1 <= 2` 一条 negative 迁移为 exact positive；`>`、`>=` siblings
必须继续 parser reject。`1 < = 2`、`1 <<= 2` 与 `1 <= = 2` 必须拒绝，既有 `1 < 2`、
`1 << 2`、`1 < < 2` 与 `1 <<< 2` 的含义/边界不得改变，证明 `<=` 是完整 binary token 且未破坏
`<`/`<<` 的最长 token 行为。
本切片不得新增 `>`、`>=`、bitwise/logical binary operator、Bool legality、constant folding、
Typed/Semantic comparison、requirement、target behavior 或 runtime representation；production 必须限于
Source/Syntax/Typed 3 文件/11 行 exact seam，其他层不得修改。本切片完成后只能称 `<`/`<=` Source
surface 已覆盖，不得宣称 `CompareExpr`、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-37 冻结的 pre-acceptance alpha greater-than 子集新增 `Source.Expr.greaterThan(lhs, rhs)`，parser
形状固定为 `syntax:50 pfExpr:51 " > " pfExpr:51 : pfExpr`。它与四个既有 comparison 共用
precedence `50`，两个 operand slot 都使用 `51`；`1 > 2 > 3` 以及 `>` 与既有 comparisons 组成的
双向 mixed chains 都必须 parser reject。Shift/Add/Mul/Unary 在两侧以更高 precedence 绑定；
`1 >> 2 > 3` 必须为 `(1 >> 2) > 3`，`1 > 2 >> 3` 必须为 `1 > (2 >> 3)`。

Source canonical encoder 以 append-only Expr tag `18` 后依次递归编码 lhs、rhs；既有 tags `0..17`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，operand legality 与 Bool result
typing 属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字
fail closed 为 `greater-than comparison is not yet supported by typed checking`。同一个 tests-only RED
必须且只能把 `Equal.lean` 的 deferred `1 > 2` 一条 negative 迁移为 exact positive；`>=` sibling
必须继续 parser reject。`1 > > 2`、`1 >>> 2`、`1 >>= 2` 与 `1 > = 2` 必须拒绝，既有
`1 >> 2` 及 ShiftRight 的 spaced/triple boundary 不得改变，证明单字符 `>` 未破坏 `>>` 最长 token。
本切片不得新增 `>=`、bitwise/logical binary operator、Bool legality、constant folding、Typed/Semantic
comparison、requirement、target behavior 或 runtime representation；production 必须限于 Source/Syntax/
Typed 3 文件/11 行 exact seam，其他层不得修改。本切片完成后只能称 `>` Source surface 已覆盖，
不得宣称 `CompareExpr`、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-38 冻结的 pre-acceptance alpha greater-or-equal 子集新增 `Source.Expr.greaterEqual(lhs, rhs)`，
parser 形状固定为 `syntax:50 pfExpr:51 " >= " pfExpr:51 : pfExpr`。它与五个既有 comparison
共用 precedence `50`，两个 operand slot 都使用 `51`；same chain 与针对所有 siblings 的十种双向
mixed chains 都必须 parser reject。Shift/Add/Mul/Unary 在两侧以更高 precedence 绑定；
`1 >> 2 >= 3` 必须为 `(1 >> 2) >= 3`，`1 >= 2 >> 3` 必须为 `1 >= (2 >> 3)`。

Source canonical encoder 以 append-only Expr tag `19` 后依次递归编码 lhs、rhs；既有 tags `0..18`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，operand legality 与 Bool result
typing 属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字
fail closed 为 `greater-equal comparison is not yet supported by typed checking`。同一个 tests-only RED
必须且只能把 `Equal.lean` 最后一条 deferred `1 >= 2` negative 迁移为 exact positive，并证明移除后
reject list 仍有效。`1 > = 2`、`1 >>= 2` 与 `1 >= = 2` 必须拒绝，既有 `1 > 2`、`1 >> 2`
以及 ShiftRight spaced/triple boundary 不得改变。
本切片不得新增 bitwise/logical binary operator、Bool legality、constant folding、Typed/Semantic
comparison、requirement、target behavior 或 runtime representation；production 必须限于 Source/Syntax/
Typed 3 文件/11 行 exact seam。GREEN 后必须在 committed tree 上通过 CompareExpr 批量 `just ci`。
完成后可称六个 comparison 的 CompareExpr Source surface 已覆盖，但仍不得宣称 expression grammar、
Typed/Semantic comparison 或 `TASK-D1-04` 正式完成。

D1-PA-39 冻结的 pre-acceptance alpha binary bitwise-and 子集新增 `Source.Expr.bitwiseAnd(lhs, rhs)`，
parser 形状固定为 `syntax:45 pfExpr:45 " & " pfExpr:46 : pfExpr`。它严格低于 CompareExpr `50`，
并按 BitAndExpr 的 Kleene-star 形状左结合：`1 & 2 & 3` 必须为 `(1 & 2) & 3`；explicit
`1 & (2 & 3)` 保留 right-nested tree。`1 & 2 == 3` 必须为 `1 & (2 == 3)`，
`1 == 2 & 3` 必须为 `(1 == 2) & 3`。future BitXor/BitOr/LogicAnd/LogicOr 必须使用低于 `45`
的 precedence，不得反转 EBNF 层级。

Source canonical encoder 以 append-only Expr tag `20` 后依次递归编码 lhs、rhs；既有 tags `0..19`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，legality/result typing 属于 D2。
decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字 fail closed 为
`bitwise and is not yet supported by typed checking`。当前没有 DSL `&` retention negative，本切片 zero
migration；`1 && 2` 必须继续 parser reject，证明逻辑与 token 未被拆为两个 bitwise-and；bare/missing、
`1 & & 2` 与 extra payload 同样拒绝。本切片不得新增 `^`、`|`、`&&`、`||`、Bool legality、
constant folding、Typed/Semantic bitwise、requirement、target behavior 或 runtime representation；production
必须限于 Source/Syntax/Typed 3 文件/11 行。本切片完成后只能称 `&` Source surface 已覆盖，
不得宣称 bitwise tier、expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-40 冻结的 pre-acceptance alpha binary bitwise-xor 子集新增 `Source.Expr.bitwiseXor(lhs, rhs)`，
parser 形状固定为 `syntax:40 pfExpr:40 " ^ " pfExpr:41 : pfExpr`。它严格低于 BitAndExpr `45`，
并按 BitXorExpr 的 Kleene-star 形状左结合：`1 ^ 2 ^ 3` 必须为 `(1 ^ 2) ^ 3`；explicit
`1 ^ (2 ^ 3)` 保留 right-nested tree。`1 & 2 ^ 3` 必须为 `(1 & 2) ^ 3`，
`1 ^ 2 & 3` 必须为 `1 ^ (2 & 3)`；`1 ^ 2 == 3` 必须为 `1 ^ (2 == 3)`，
`1 == 2 ^ 3` 必须为 `(1 == 2) ^ 3`。future BitOr/LogicAnd/LogicOr 必须使用低于 `40`
的 precedence，不得反转 EBNF 层级。

Source canonical encoder 以 append-only Expr tag `21` 后依次递归编码 lhs、rhs；既有 tags `0..20`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，legality/result typing 属于 D2。
decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字 fail closed 为
`bitwise xor is not yet supported by typed checking`。当前没有 DSL `^` retention negative，本切片 zero
migration；bare/missing、`1 ^ ^ 2`、`1 ^^ 2` 与 extra payload 必须 parser reject，future `1 | 2`
必须继续拒绝。本切片不得新增 `|`、`&&`、`||`、Bool legality、constant folding、Typed/Semantic
bitwise、requirement、target behavior 或 runtime representation；production 必须限于 Source/Syntax/Typed
3 文件/11 行。本切片完成后只能称 `^` Source surface 已覆盖，不得宣称 bitwise tier、expression
grammar 或 `TASK-D1-04` 正式完成。

D1-PA-41 冻结的 pre-acceptance alpha binary bitwise-or 子集新增 `Source.Expr.bitwiseOr(lhs, rhs)`，
parser 形状固定为 `syntax:35 pfExpr:35 " | " pfExpr:36 : pfExpr`。它严格低于 BitXorExpr `40`，
并按 BitOrExpr 的 Kleene-star 形状左结合：`1 | 2 | 3` 必须为 `(1 | 2) | 3`；explicit
`1 | (2 | 3)` 保留 right-nested tree。`1 ^ 2 | 3` 必须为 `(1 ^ 2) | 3`，
`1 | 2 ^ 3` 必须为 `1 | (2 ^ 3)`；`1 & 2 | 3`/`1 | 2 & 3` 与
`1 | 2 == 3`/`1 == 2 | 3` 同理按 `&`/Compare 优先。future LogicAnd/LogicOr 必须使用低于 `35`
的 precedence，不得反转 EBNF 层级。

Source canonical encoder 以 append-only Expr tag `22` 后依次递归编码 lhs、rhs；既有 tags `0..21`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node，legality/result typing 属于 D2。
decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在检查任一 operand 前逐字 fail closed 为
`bitwise or is not yet supported by typed checking`。tests-only RED 必须且只能迁移
`BitwiseXor.lean` 的 `1 | 2` retention negative，并在新 suite 固定为 positive AST；不得修改其他既有
suite。当前 enum variant introducer 属于独立 `pfAggregateMember` category，RED 必须用同一个 program
中的 enum variants 与 bitwise-or expression 做双入口 coexistence proof，禁止因 token 复用误分类。
`StmtMatchArm` 尚未实现；未来 match parser 必须拥有 arm introducer 的 block/line disambiguation，本切片
不得提前实现 match。bare/missing operand、`1 | | 2`、extra payload 与 future `1 || 2` 必须 parser
reject，逻辑或 token 不得拆成两个 bitwise-or。本切片不得新增 `&&`、`||`、match expression、Bool legality、constant
folding、Typed/Semantic bitwise、requirement、target behavior 或 runtime representation；production 必须
限于 Source/Syntax/Typed 3 文件/11 行。GREEN、focused/aggregate/test binary 与独立审查全绿后必须在
committed tree 上运行一次 bitwise-tier 批量 `just ci` checkpoint；只有该 gate 全绿才能记录
`&`/`^`/`|` 的完整 bitwise Source surface，仍不得宣称 expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-42 冻结的 pre-acceptance alpha binary logical-and 子集新增 `Source.Expr.logicalAnd(lhs, rhs)`，
parser 形状固定为 `syntax:30 pfExpr:30 " && " pfExpr:31 : pfExpr`。它严格低于 BitOrExpr `35`，
并按 LogicAndExpr 的 Kleene-star 形状左结合：`1 && 2 && 3` 必须为 `(1 && 2) && 3`；explicit
`1 && (2 && 3)` 保留 right-nested tree。`1 | 2 && 3` 必须为 `(1 | 2) && 3`，
`1 && 2 | 3` 必须为 `1 && (2 | 3)`；`1 == 2 && 3` 必须为 `(1 == 2) && 3`，
`1 && 2 == 3` 必须为 `1 && (2 == 3)`。future LogicOr 必须使用低于 `30` 的 precedence，
不得反转 EBNF 层级。

Source canonical encoder 以 append-only Expr tag `23` 后依次递归编码 lhs、rhs；既有 tags `0..22`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node；operand/result legality 与
short-circuit Typed/Semantic 实现属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在
检查任一 operand 前逐字 fail closed 为 `logical and is not yet supported by typed checking`。
tests-only RED 必须且只能迁移 `BitwiseAnd.lean` 的 `1 && 2` retention negative，并在新 suite 固定为
positive AST；同 suite 的 `1 & & 2` survival pin 与其他既有 suite 不得修改。bare/missing operand、
`1 && && 2`、`1 &&& 2`、`1 & && 2` 与 extra payload 必须 parser reject；`BitwiseOr.lean` 的 future
`1 || 2` retention negative 必须保持不动。本切片不得新增 `||`、short-circuit lowering、Bool legality、
constant folding、Typed/Semantic logical operation、requirement、target behavior 或 runtime representation；
production 必须限于 Source/Syntax/Typed 3 文件/11 行。GREEN、focused/aggregate/test binary 与独立审查
全绿后只能记录 logical-and Source surface；logical tier 的 committed-tree 批量 `just ci` 延后到
logical-or 收口，不得宣称 expression grammar 或 `TASK-D1-04` 正式完成。

D1-PA-43 冻结的 pre-acceptance alpha binary logical-or 子集新增 `Source.Expr.logicalOr(lhs, rhs)`，
parser 形状固定为 `syntax:25 pfExpr:25 " || " pfExpr:26 : pfExpr`。它严格低于 LogicAndExpr `30`，
并按 LogicOrExpr 的 Kleene-star 形状左结合：`1 || 2 || 3` 必须为 `(1 || 2) || 3`；explicit
`1 || (2 || 3)` 保留 right-nested tree。`1 && 2 || 3` 必须为 `(1 && 2) || 3`，
`1 || 2 && 3` 必须为 `1 || (2 && 3)`；`1 | 2 || 3`/`1 || 2 | 3` 与
`1 == 2 || 3`/`1 || 2 == 3` 同理按 bitwise-or/Compare 优先。

Source canonical encoder 以 append-only Expr tag `24` 后依次递归编码 lhs、rhs；既有 tags `0..23`
与 goldens 不得改变。integer 与 Bool operands 都必须形成 Source node；operand/result legality 与
short-circuit Typed/Semantic 实现属于 D2。decoder/`quoteExpr` 必须结构化保留节点；`Typed.check` 必须在
检查任一 operand 前逐字 fail closed 为 `logical or is not yet supported by typed checking`。
tests-only RED 必须且只能迁移 `BitwiseOr.lean` 的 `1 || 2` retention negative，并在新 suite 固定为
positive AST；同 suite 的 spaced `1 | | 2` survival pin 与其他既有 suite 不得修改。bare/missing operand、
`1 || || 2`、`1 ||| 2`、`1 | || 2` 与 extra payload 必须 parser reject。本切片不得新增 match、
short-circuit lowering、Bool legality、constant folding、Typed/Semantic logical operation、requirement、
target behavior 或 runtime representation；production 必须限于 Source/Syntax/Typed 3 文件/11 行。
GREEN、focused/aggregate/test binary 与独立审查全绿后必须在 committed tree 上运行 logical-tier 批量
`just ci` checkpoint；只有该 gate 全绿才能记录 bitwise 与 logical 的 Source operator precedence tower，
但不得把它扩张为 MatchExpr、完整 expression/statement grammar 或 `TASK-D1-04` 正式完成。

D1-PA-44 冻结的 pre-acceptance alpha StringLiteral 子集新增
`Source.Expr.stringLiteral(value : String)` 与 primary rule `syntax str : pfExpr`。Source value 必须取
Lean lexer 已解码的 `str.getString`；`quoteExpr` 必须用 `Syntax.mkStrLit` 重新构造合法 token。因此空串、
引号、反斜杠、tab 与 Unicode scalar 必须按值往返，不得把原始 token 拼写或 escape spelling 写入
Source identity。两种 Lean escape 拼写若解码为同一 String，必须形成相同 Source.Program、canonical
bytes 与 sourceHash；string literal 和相同 payload 的 identifier 必须为不同 Source node。

Source canonical encoder 使用 append-only Expr tag `25` 后接现有 length-prefixed UTF-8 `appendString`；
既有 tags `0..24` 与 goldens 不得改变。tests-only RED 为 zero migration，只新增并注册
`Tests.Language.StringLiterals`；positive 必须覆盖 initializer、entry、view、fn 的 return/let value 与
Lean command/ParserSession 双入口 parity，并固定空串、ASCII、escaped quote/backslash/tab、Unicode、
decoded-value canonical equality 和 string-vs-variable tag non-alias。相邻 literals、interpolated string
syntax 与 unterminated string 必须停在 parser boundary。`Typed.check` 必须逐字 fail closed 为
`string literals are not yet supported by typed checking`。本切片不得新增 String ValueType、concatenation、
interpolation、constant folding、Typed/Semantic string legality、ABI/runtime representation、call/constructor/
place 或 match；production 必须限于 Source/Syntax/Typed 3 文件/9 行。GREEN、focused/aggregate/test binary
与独立审查全绿后只可记录 EBNF Literal 的 Source carrier 已覆盖；本切片不重复全量 `just ci`，下一批
primary-expression checkpoint 再运行，且不得宣称 PrimaryExpr、完整 expression/statement grammar 或
`TASK-D1-04` 正式完成。

D1-PA-45 冻结的 pre-acceptance alpha LocalFnCall 子集一次实现完整
`LocalFnCall ::= Ident "(" ExprList? ")"` 与 `ExprList ::= Expr ("," Expr)*`，新增
`Source.Expr.localFnCall(callee : String, args : Array Expr)`。parser rule 固定为
`syntax:max ident "(" pfExpr,* ")" : pfExpr`：call result 是 high-precedence PrimaryExpr，每个 argument
使用完整低 precedence `pfExpr`，零、单、多参数和递归 nested call 都必须接受，trailing comma 禁止。
bare `f` 继续是 variable，`f()`/`f ()` 必须形成同一 localFnCall；grouping 与 call 不得混淆。

Lean `ident` 会把 `A.B` 词法化为一个 qualified identifier，因此 decoder 必须先要求
`callee.getId.components.length == 1`，不满足时逐字拒绝 `local function call callee must be unqualified`，
不得把 future ConstructorExpr 的 `QualifiedId(...)` 错收成 LocalFnCall。escaped 单组件 identifier 仍按
既有 `decodeIdentifier` policy 处理；callee 必须先于 arguments 解码，以固定错误优先级。Source canonical
encoder 使用 append-only Expr tag `26`，随后依次编码 callee string 与 length-prefixed argument array；
既有 tags `0..25`/goldens 不得改变。argument order、count 与 nested tree 必须进入 source identity。

tests-only RED 必须且只能迁移 `Grouping.lean` 的 `("call-like", f(1))` negative，并新增/注册
`Tests.Language.LocalFnCalls`。positive 覆盖 initializer、entry、view、fn 的 return/let value、双入口 parity、
zero/one/multiple args、operator/group/string args、nested calls、call-as-operator-operand 与 escaped callee；
canonical controls 固定 callee/argument order、count/nesting、grouping desugar，以及 localFnCall `f()` 对
variable `f` 的 tag non-alias。missing callee/paren、leading/trailing/double comma、adjacent payload、unescaped
reserved token 与 qualified call-like forms 必须 fail closed；`A.B(...)` 命中上述 exact unqualified diagnostic，
不得实现 constructor。`Typed.check` 必须在检查任一 argument 或做 fn lookup 前逐字 fail closed 为
`local function calls are not yet supported by typed checking`。本切片不得新增 callable resolution、arity/type/
return checking、recursion analysis、ConstructorExpr、ExternalCallExpr、Place、MatchExpr、Typed/Semantic call、
requirement 或 target behavior；production 必须限于 Source/Syntax/Typed 3 文件/13 行。GREEN 与 focused/
aggregate/test binary/独立审查全绿后只可记录完整 LocalFnCall Source carrier；本切片不运行全量 `just ci`，
call-like primary batch checkpoint 延后到后续单一 slice，且不得宣称 PrimaryExpr、完整 grammar 或正式 D1 完成。

D1-PA-46 冻结的 pre-acceptance alpha ConstructorExpr 子集复用 PA45 已有的
`syntax:max ident "(" pfExpr,* ")" : pfExpr`，不新增另一条 call-like syntax rule。decoder 必须以
`callee.getId.components.length` 做 target-neutral 分类：单组件仍形成 LocalFnCall，两个或更多
组件形成 `Source.Expr.constructorExpr(path : Array String, args : Array Expr)`；禁止把 qualified
identity 压平为 dotted string。path 必须逐组件经既有 portable-identifier reserved policy，再经
`Core.Common.parseQualifiedName`/canonical component rendering，并在解码任何 argument 前完成；不合法
组件、numeric Name 组件，以及 constructor-path helper 收到少于两个组件时必须 fail closed，
不影响单组件 callee 继续分类为 LocalFnCall。
分类依据是 Lean `Name.components`，不是 rendered string 中是否出现点：`A.B()` 是两组件
ConstructorExpr，whole-escaped `«A.B»()` 是单组件并按既有 policy 继续形成 LocalFnCall；
没有 call suffix 的 bare `A.B` 仍是既有 variable carrier。普通/等价 escaped 的合法独立 path
component 不得改变 canonical component value。这只是对已冻结 component-count 规则的消歧，
不新增可写类别标记或扩大完成面。

Source canonical encoder 使用 append-only Expr tag `27`，随后依次编码 length-prefixed path component
array 和 length-prefixed argument expression array；既有 tags `0..26`/goldens 不得改变。tests-only RED
必须且只能迁移 `LocalFnCalls.lean` 中 `A.B()`/`A.B(1)` 两条 qualified-call negatives，
并新增/注册 `Tests.Language.ConstructorExprs`。positive 覆盖 initializer、entry、view、fn
return/let 及双入口 parity，zero/one/multiple/operator/group/string/nested constructor arguments，
two/multi-component paths 和 escaped portable components；canonical controls 固定 component count/order/value、
argument count/order/nesting 及 constructor-vs-local-call-vs-variable tag non-alias。bare/local `f(...)` 必须
继续形成 LocalFnCall，missing/malformed list、reserved/invalid qualified components 与 dotted-token boundaries
必须拒绝。`Typed.check` 必须在 argument checking 或 constructor/type lookup 前逐字 fail closed 为
`constructor expressions are not yet supported by typed checking`。

本切片不得实现 struct/enum/Option constructor resolution、arity/type/result 检查、Place、MatchExpr、
ExternalCallExpr、Typed/Semantic constructor、requirement 或 target behavior；production 仅限
Source/Syntax/Typed 3 文件、最多 24 行新增，且不得新增 syntax production。GREEN、focused/
aggregate/test binary 与独立审查全绿后，必须在 clean committed tree 运行一次 call-like
primary batch `just ci`；只可记录 ConstructorExpr Source carrier 和 LocalFnCall/ConstructorExpr 分类
已固定，不得宣称 PrimaryExpr、完整 grammar 或正式 D1 完成。

D1-PA-47 冻结的 pre-acceptance alpha index-access 子集只物化 EBNF `PlaceSuffix` 的一个只读
bracket suffix，parser 形状固定为 `syntax:max ident "[" pfExpr "]" : pfExpr`，Source 节点固定为
`Source.Expr.indexAccess(base : String, index : Expr)`。base 必须是恰好一个 Lean `Name` component 的
bare `Ident`；decoder 必须先检查 component count，再经既有 `decodeIdentifier` policy 解码 base，最后
才递归解码完整 `index` expression。qualified `A.B[expr]` 必须在 index 前逐字拒绝
`index access base must be unqualified`。`x[expr]` 与 `x [expr]`、普通/等价 escaped portable base 必须
产生同一 Source value；index expression 可包含既有 operator、group、local call 或 constructor carrier。

本切片不引入独立 `Place`/suffix-array 类型，也不把任意 expression 扩成 postfix base：`(x)[0]`、
`f()[0]`、`A.B[0]`、chained `x[0][1]` 与 indexed assignment `x[0] := 1` 必须 fail closed；既有 bare
dotted variable 与 statement 的 bare-ident assignment LHS 语义不得改变。Source canonical encoder 使用
append-only Expr tag `28`，随后依次编码 base string 和 index expression；既有 tags `0..27`/goldens
不得改变。tests-only RED 为 zero migration，只新增/注册 `Tests.Language.IndexAccesses`；canonical controls
固定 base value、index value/tree 与 indexAccess-vs-variable tag non-alias。`Typed.check` 必须在 base
resolution 或 index checking 前逐字 fail closed 为
`index access is not yet supported by typed checking`。

本切片不得实现 field suffix、suffix chaining、indexed assignment、general postfix expression、Place
resolution/lvalue legality、container/index type、bounds、read semantics、MatchExpr、ExternalCallExpr、
Typed/Semantic index、requirement 或 target behavior；production 仅限 Source/Syntax/Typed 3 文件、最多
14 行新增。GREEN、focused/aggregate/test binary 与两份独立审查全绿后只可记录 bare-base rvalue
indexAccess Source carrier；本切片不重复全量 `just ci`，下一批 primary-expression checkpoint 再运行，
且不得宣称完整 Place、PrimaryExpr、expression/statement grammar 或正式 D1 完成。

D1-PA-48 冻结的 pre-acceptance alpha revert statement 子集一次实现完整
`RevertStmt ::= "revert" Ident ("(" ExprList? ")")?`，Source carrier 固定为
`Source.Statement.revertStmt(errorName : String, args : Array Expr)`，不得拆成 bare-only 与 payload 两套
constructor。parser rules 固定为 `syntax "revert " ident : pfStmt` 与
`syntax "revert " ident "(" pfExpr,* ")" : pfStmt`，必须接受 bare `revert Err`、empty-paren
`revert Err()` 与完整 `revert Err(exprs)`。parenthesized rule 必须优先于 strict-prefix bare fallback
完成 longest match；禁止 bare rule 先吞掉 `revert Err` 后把括号遗留在 statement parser；
bare/empty-paren 两种 surface 均物化为空 args array 并产生相同 Source AST/canonical bytes/sourceHash。
每个 argument 复用 PA45 已完成的完整 `pfExpr`/ExprList grammar 并保持声明次序。

errorName 必须是恰好一个 Lean `Name` component 的 `Ident`；decoder 先做 component-count guard，再经
既有 `decodeIdentifier` policy 解码 name，最后才递归解码 arguments。qualified `A.B(...)` 必须在
arguments 前逐字拒绝 `revert error name must be unqualified`。Source canonical encoder 使用 append-only
Statement tag `5`，随后依次编码 errorName string 与 length-prefixed argument expression array；既有
statement tags `0..4`/goldens 不得改变。tests-only RED 为 zero migration，只新增/注册
`Tests.Language.RevertStatements`；canonical controls 固定 name、argument value/count/order/nesting、
bare/empty equivalence 与 revert-vs-call/其他 statement kind non-alias。

missing name/paren、leading/trailing/double comma、missing/adjacent argument、extra payload 与 unescaped
keyword lookalikes 必须 fail closed；escaped assignment identifier 必须保持既有分类。`Typed.check` 必须在
error declaration lookup、arity/type 或 argument checking 前逐字 fail closed 为
`revert statements are not yet supported by typed checking`。本切片不得实现 error-table resolution、
payload arity/type、failure code/rollback semantics、Typed/Semantic revert、ABI/runtime、requirement 或 target
behavior；production 仅限 Source/Syntax/Typed 3 文件、最多 20 行新增。GREEN、focused/aggregate/test
binary 与两份独立审查全绿后只可记录完整 revert statement Source carrier；本切片不重复全量
`just ci`，下一批 statement checkpoint 再运行，且不得宣称完整 error semantics、statement grammar
或正式 D1 完成。

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
entry/view、state 名唯一、entry/view declaration 名唯一、event 名唯一、error 名唯一、struct 名唯一、
enum 名唯一、const 名唯一、fn 名唯一、entry/view/fn callable 名唯一、invariant 名唯一、extension ID
唯一、每个 invariant 最多一个 proof reference、每个 proof reference 精确绑定已声明 invariant、
initializer 参数名唯一、每个 struct field 按 struct 声明顺序非空且名称唯一、每个 enum variant 按
enum 声明顺序非空且名称唯一、每个 event 参数名按 event 声明顺序唯一、每个 error 参数名按 error
声明顺序唯一、每个 entry 参数名唯一、每个 fn 参数名唯一且 body nonempty；
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

当前 D1 pre-acceptance alpha 把 const 的 exact declaration name、declared type 与当前 alpha
expression constructors 保存在独立 Source projection，并把 declaration/type/value/count/order 纳入
development source binding。完整 `Program.items` 落地前只保证 const 同类 declaration order，不声称
跨 kind source order。该切片不执行 D2 const type/name resolution；任一非空 const table 必须在
`Typed.check` fail closed，不能以未解析 expression 进入 requirement resolution 或 target Plan。

当前 D1 pre-acceptance alpha 把 pure fn 的 exact name、parameter、result 与当前 alpha statement/body
保存在独立 Source projection，并把 signature/body/count/order 纳入 development source binding。完整
`Program.items` 落地前只保证 fn 同类 declaration order，不声称跨 kind callable source order；
entry、view 与 fn 共用 callable 名称空间，跨 kind 同名由 shared validation fail closed。
fn body 作为 `Block` 必须 nonempty。该切片不执行 D2 local-call lookup、type/effect/return/acyclicity
检查；当前 alpha 已把省略返回类型在 parse time materialize 为 `Unit`，但不据此声称无值 `return`、
`Unit` fallthrough 或完整 return-path 语义已实现。
任一非空 fn table 必须在
`Typed.check` fail closed，不能以未检查 body 进入 Semantic、resolver 或 target Plan。

当前 D1 pre-acceptance alpha 把 invariant 的 exact name 与当前 alpha expression predicate 保存在
独立 Source projection，并把 name/predicate/count/order 纳入 development source binding。完整
`Program.items` 落地前只保证 invariant 同类 declaration order，不声称跨 kind 名称唯一性。
该切片不执行 D2 predicate Bool type checking、name resolution、pure-fn lookup 或 proof binding；
任一非空 invariant table 必须在 `Typed.check` fail closed，不能以未检查 predicate 进入 Semantic、
resolver 或 target Plan。

当前 D1 pre-acceptance alpha 把 extension requirement 的 exact lowercase dotted ID、完整 canonical
SemVer 字符串（包括 prerelease/build identity）与 `sha256:<64 lowercase hex>` digest 保存在独立
Source projection，并把 id/version/digest/count/order 纳入 development source binding。同一 ID 即使
version/digest 不同也按 duplicate 拒绝；decode 顺序固定为 id→version→digest。完整 `Program.items`
落地前只保证 extension requirement 同类源码顺序。D2 typed extension registry、operation/effect/
requirement inference、semantic registry digest 与 target support resolution 尚未实现，因此任一非空
extension table 必须在 `Typed.check` fail closed，不能把 Source 声明直接伪装成可信
`ProgramRequirements` 或进入 target Plan。

当前 D1 pre-acceptance alpha 把 proof reference 的 exact invariant name 与 theorem QualifiedName
component array 保存在独立 Source projection，并把 invariant/theorem component count/value/order、
reference count/order 纳入 development source binding。每个 invariant 最多一个 reference；duplicate
先于 unknown invariant 拒绝，unknown 检查按 proof 源码顺序 exact、case-sensitive lookup，允许
forward-declared invariant，不做 short-name、namespace 或 ambient environment fallback。theorem 的
每个 QualifiedName component 必须先通过同一 DSL reserved-identifier policy，再进入 Common 的
QualifiedName NFC/字符/长度校验；Common carrier 不拥有或复制 DSL 保留词策略。该切片不读取
`.olean`/proof bundle，不查 theorem、不构造 expected theorem type，也不改变业务执行、requirements、
semanticHash 或 target 选择。完整 origin、invariant ordinal、closed SemanticProgram binding 与 proof
validation record 尚未实现；任一非空 proof table 必须在 `Typed.check` fail closed。

为避免 ProofForge import 把 Lean 宿主中的 `struct`/`enum`/`const`/`event`/`error`/`fn`/`invariant`/
`requires`/`extension`/`version`/`digest`/`proof`/`using` 变成全局 parser keyword，
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
