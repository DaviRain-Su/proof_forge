---
id: SPEC-LANG-001
title: Program DSL 语言规格
status: proposed
owner: frontend
updated: 2026-07-19
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

D1-PA-54 冻结的 pre-acceptance alpha Array 子集只接受同一行的
`Array PrimitiveAtom N`。`PrimitiveAtom` 与 D1-PA-18 相同，只包含 exact single-token `Bool`、closed
UInt/Int width、`Principal` 或 `Unit`；`Field bn254_fr`、Named、Option、Bytes、Array 与 Map element
全部继续 fail closed。`N` 复用 `Bytes N` 的 canonical ASCII decimal lexical discipline，边界精确为
`0..4096`，并在 Source/Semantic carrier 中保存为各自的 `ArrayLength := Fin 4097`，使超界长度无法由
公开 AST 类型构造，不能依赖 parser 约定避免 canonical alias。

Source/Semantic carrier 固定为 `array(element, length)`。alpha canonical encoding 使用 append-only
type tag `18`，随后递归编码 element，再调用各 encoder 已有的 `appendNat(length.val)`；Source 保持
8-byte big-endian，Semantic 保持 8-byte little-endian，tags `0..17` 与全部旧 golden 不变。Array
本身不发明 capability，requirements 必须精确递归传播 element：`Array UInt64 4` 为零，
`Array Bool 0` 为 `boolValues`。frontend 使用 exact contextual `Array` 专用 parser，不得把通用
`pfType` 放宽为任意三 token，也不得改变 `Option UInt64 Principal` 等既有 malformed type 的 parser
boundary。Lean command 与 ParserSession 必须得到同一结构与 sourceHash。

tests-only RED 为 zero migration，只新增/注册 `Tests.Language.ArrayTypes`。positive 覆盖 state、struct
field、enum payload、const、initializer/entry/view/fn parameter 与 result，长度 `0`、普通值与 `4096`，
并固定 Source/Semantic tag、element、length、size/hash non-alias。unknown/Field element、缺失 element 或
length、`4097`、leading zero、hex、signed、underscore、额外/跨行 payload、nested Option/Bytes/Array/Map
必须按专用 grammar fail closed；named-ident type 不在本切片。四个 Phase 1 target 只验证 requirement
resolver 与既有 non-UInt64 Plan rejection，不新增数组 target support 或制品。

本切片不实现 array literal、constructor、index/length/slice、mutation、assignment、runtime layout、
ABI、recursive legality、D2 type/value semantics 或 target Plan/IR。production 仅限
`Core/Source.lean`、`Core/SemanticIR.lean`、`Language/Syntax.lean` 三文件，最多 64 行新增、6 行移除，
并在同一 GREEN 刷新 Lean package file-set。focused/aggregate/test binary 与 independent review 全绿后
只可记录 bounded Array declaration carrier；PA53 已完成 committed-tree batch `just ci`，本切片不重复
完整 gate，不得声明数组运行语义、完整 type grammar 或正式 D1 完成。

D1-PA-55 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic 类型构造的
`option(.field)` 开放 exact same-line spelling `Option Field bn254_fr`。这不是新 ValueType carrier：
Source/Semantic 的 recursive Option canonical encoder 已产生 tag `16` 后接 Field tag `2`，
`ValueType.requirements` 也已把 `.fieldBn254` 递归穿过 Option；不得新增 ctor/tag、修改 encoder、
Typed 或 target。frontend 只能新增 exact contextual named `optionFieldType` 与 struct-field 对应 parser，
不得把通用 `portableType` 放宽为任意三 atom，也不得接受其他 Field identifier、Named、nested Option、
Array、Map 或 Bytes element。

decoder 必须 exact 验证第三 atom 的 raw spelling 为 `bn254_fr` 后才构造 `.option .field`；alternate、
escaped 或 qualified identifier fail closed。Lean command 与 ParserSession 必须得到同一 Source tree/hash。
canonical tests 固定既有 tag `16→2` 的 Source/Semantic bytes/hash，并与 bare Field、Option Bool、
Option UInt64 non-alias；不重编号 tags `0..18`。semantic requirements 必须恰为 `fieldBn254`，不能被
Option 擦除或重复；四个 Phase 1 target 必须在 support resolution 以 named requirement 拒绝，不能进入
Plan 或产生 artifact。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
`("field option", "Option Field bn254_fr")` parser-negative 迁移为 positive；migration count 精确为一，
其他测试不得迁移。positive 覆盖 state、struct field、enum payload、const、initializer/entry/view/fn
parameter/result 与双入口 parity。`Option Field`、alternate/escaped/qualified id、escaped/qualified
constructor、extra/split payload 必须 fail closed；Option Bytes、nested Option、Option Array/Map 和既有
extra payload failure class 保持原边界。

本切片不实现 none/some expression、unwrap、field literal/arithmetic、recursive type legality、runtime
representation、ABI 或 target Field support。production 仅限 `Language/Syntax.lean` 一文件，最多 32 行
新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。focused/aggregate/test binary 与 independent
review 全绿后只可记录 existing-carrier spelling；PA53 batch `just ci` 已绿，本切片不重复完整 gate，
不得声明 Option/Field runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-56 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive Option 构造的
`option(.option element)` 开放 exact same-line、exact one-level spelling
`Option Option PrimitiveAtom`。inner `PrimitiveAtom` 闭集精确复用 D1-PA-18：exact single-token Bool、
closed UInt/Int widths、Unit、Principal，共 15 个；Field、Bytes、Array、Map、Named 或另一个 Option
都不属于该闭集。这不是新 ValueType carrier：Source/Semantic recursive encoder 已产生 tag `16`、
第二个 tag `16` 再接 element bytes，`ValueType.requirements` 也已递归两层传播 element requirements；
不得新增 ctor/tag、修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionOptionType` 与 struct-field 对应 parser；不得把通用
`portableType` 放宽为任意三 atom，也不得引入 recursive parser。decoder 只从专用 parser 接收一个
inner element atom，以既有 exact single-token type policy 解码后构造 `.option (.option element)`；因此
第三层 `Option Option Option Bool`、two-token Field/Bytes/Array、unknown/escaped/qualified element 都必须
fail closed。Lean command 与 ParserSession 必须得到同一 Source tree/hash。canonical tests 固定既有
tag `16→16→element` 的 Source/Semantic bytes/hash，并与 bare element、single Option 及不同 nested
element non-alias；不重编号 tags `0..18`。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
`("nested option", "Option Option UInt64")` parser-negative 迁移为 positive；migration count 精确为一，
其他测试不得迁移。positive 覆盖 nested Bool/UInt64 的 state、struct field、enum payload、const、
initializer/entry/view/fn parameter/result 与双入口 parity。nested UInt64 requirement 必须为空；nested Bool
必须递归传播恰一个 `boolValues`。四个 Phase 1 target 对 nested Bool 在 support resolution 以 named
requirement 拒绝；nested UInt64 通过 support 后，non-UInt64 state/result/parameter 仍由既有 target Plan
fail closed，任何路径均不得产出 artifact。Option Bytes、Option Array/Map、Option Field 及第三层 nested
Option 保持原边界。

本切片不实现 none/some expression、unwrap、任意递归 type grammar、recursive legality、runtime
representation、ABI 或 target nested-Option support。production 仅限 `Language/Syntax.lean` 一文件，最多
32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。focused/aggregate/test binary 与
independent review 全绿后只可记录 one-level existing-carrier spelling；按冻结不重复完整 `just ci`，
不得声明 nested Option runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-57 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`option(.array element length)` 开放 exact same-line spelling `Option Array PrimitiveAtom N`。element
闭集精确复用 D1-PA-18/PA54 的 15 个 exact single-token PrimitiveAtom；`N` 精确复用 Array 的 canonical
ASCII decimal `0..4096` discipline 与 `ArrayLength := Fin 4097`。Field、Option、Bytes、Array、Map、Named
element 继续排除。这不是新 ValueType carrier：Source/Semantic recursive encoders 已产生 Option tag `16`
后接 Array tag `18`、element bytes 与 encoder-local length payload，requirements 也已递归穿过两层 wrapper；
不得新增 ctor/tag、修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionArrayType` 与 struct-field 对应 parser；不得把通用
`portableType` 放宽为任意四 atom，也不得引入 recursive parser。decoder 只从专用 parser 接收 element 与
length atoms，必须复用既有 `decodeArrayValueTypeFromAtoms` 完成 element/lexical/bound 验证后再包一层
Option；不得复制或放宽 Array policy。Lean command 与 ParserSession 必须得到同一 Source tree/hash。
canonical tests 固定既有 tag `16→18→element→length` 的 Source/Semantic bytes/hash，并与 bare Array、
single/nested Option 及不同 element/length non-alias；不重编号 tags `0..18`。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
`("Array option", "Option Array UInt64 4")` parser-negative 迁移为 positive；migration count 精确为一，
其他测试不得迁移。positive 覆盖 Bool/UInt64、长度 0/普通值/4096、所有 declaration positions 与双入口
parity。UInt64 element requirement 必须为空；Bool element 必须递归传播恰一个 `boolValues`。四个 Phase 1
target 对 Bool 在 support resolution 以 named requirement 拒绝；UInt64 通过 support 后，non-UInt64
state/result/parameter 仍由既有 target Plan fail closed，任何路径均不得产出 artifact。Option Bytes、
Array Option、Array Field、third-layer nested Option 和 extra/split payload 保持原边界。

本切片不实现 array value/constructor/index/length/slice/mutation、none/some/unwrap、任意递归 type grammar、
recursive legality、runtime representation、ABI 或 target Option-Array support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused/aggregate/test binary 与 independent review 全绿后只可记录 existing-carrier spelling；按冻结不重复
完整 `just ci`，不得声明 Option/Array runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-58 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`option(.bytes length)` 开放 exact same-line spelling `Option Bytes N`。`N` 精确复用 Bytes 的 canonical
ASCII decimal `0..4096` discipline；除单个 `0` 外禁止前导零，禁止 `_`、base prefix、符号、identifier、
缺失/额外 payload 或跨行 payload。这不是新 ValueType carrier：Source/Semantic recursive encoders 已产生
Option tag `16` 后接 Bytes tag `17` 与 encoder-local length payload，requirements 也已递归穿过 wrapper；
不得新增 ctor/tag、修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionBytesType` 与 struct-field 对应 parser；不得把通用
`portableType` 放宽为任意三 atom，也不得引入 recursive parser。decoder 只从专用 parser 接收 length atom，
必须复用既有 `decodeBytesLengthAtom` 完成 lexical/bound 验证后构造 `.option (.bytes length)`；不得复制或
放宽 Bytes policy。Lean command 与 ParserSession 必须得到同一 Source tree/hash。canonical tests 固定既有
tag `16→17→length` 的 Source/Semantic bytes/hash，并与 bare Bytes、single Option、Option Array 及不同
length non-alias；不重编号 tags `0..18`。

tests-only RED 只修改 `Tests.Language.OptionDeclarations` 与 `Tests.Language.BytesTypes`，将既有两条
`Option Bytes` parser-negative 迁移为 positive，migration count 精确为二，其他测试不得迁移。positive 覆盖
长度 `0`、普通值、`4096`、state、struct field、enum payload、const、initializer/entry/view/fn
parameter/result 与双入口 parity。`Option Bytes N` 必须推导零 requirement；四个 Phase 1 target 通过
support resolver 后仍由既有 non-UInt64 Plan invariant 拒绝，任何路径均不得产出 artifact。missing/invalid
length、escaped/qualified constructor、extra/split payload 必须 fail closed；Array Option、Array Field、
third-layer nested Option、Option Map 与既有 extra-payload failure class 保持原边界。

本切片不实现 bytes literal/index/slice/length、none/some、unwrap、任意递归 type grammar、recursive
legality、runtime representation、ABI 或 target Option-Bytes support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused/aggregate/test binary 与 independent review 全绿后只可记录 existing-carrier spelling；按冻结不重复
完整 `just ci`，不得声明 Option/Bytes runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-59 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`array(.option element, length)` 开放 exact same-line spelling `Array Option PrimitiveAtom N`。element
闭集精确复用 D1-PA-18/PA54/PA57 的 15 个 exact single-token PrimitiveAtom；`N` 精确复用 Array 的
canonical ASCII decimal `0..4096` discipline 与 `ArrayLength := Fin 4097`。Field、Bytes、Array、Option、
Map、Named element 继续排除。这不是新 ValueType carrier：Source/Semantic recursive encoders 已产生
Array tag `18`、Option tag `16`、element bytes 与 encoder-local length payload，requirements 也已递归穿过
两层 wrapper；不得新增 ctor/tag、修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `arrayOptionType` 与 struct-field 对应 parser；不得把通用
`arrayType` 或 `portableType` 放宽为任意多 atom，也不得引入 recursive parser。decoder 只从专用 parser
接收 element 与 length atoms，必须复用既有 PrimitiveAtom decode 与 `decodeBytesLengthAtom` 的 lexical/
bound 验证后构造 `.array (.option element) length`；不得复制或放宽 Array/Option policy。Lean command 与
ParserSession 必须得到同一 Source tree/hash。canonical tests 固定既有 tag `18→16→element→length` 的
Source/Semantic bytes/hash，并与 bare Array、Option Array、bare Option、不同 element/length non-alias；
不重编号 tags `0..18`。

tests-only RED 只修改 `Tests.Language.ArrayTypes` 与 `Tests.Language.OptionDeclarations`，将既有两条
`Array Option Bool 4` parser-negative 迁移为 positive，migration count 精确为二，其他测试不得迁移。
positive 覆盖 Bool/UInt64、长度 `0`、普通值、`4096`、所有 declaration positions 与双入口 parity。
`Array Option UInt64 N` requirement 必须为空；`Array Option Bool N` 必须递归传播恰一个 `boolValues`。
四个 Phase 1 target 对 Bool 在 support resolution 以 named requirement 拒绝；UInt64 通过 support 后，
non-UInt64 state/result/parameter 仍由既有 target Plan fail closed，任何路径均不得产出 artifact。missing/
unknown/Field/Bytes/Array/Option/Map element、invalid length、escaped/qualified constructor 或 element、
extra/split payload 必须 fail closed；Array Field、Array Bytes、Option Array compound、third-layer nested
Option、Map/Named 与既有 extra-payload failure class 保持原边界。

本切片不实现 array value/constructor/index/length/slice/mutation、none/some/unwrap、任意递归 type grammar、
recursive legality、runtime representation、ABI 或 target Array-Option support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused/aggregate/test binary 与 independent review 全绿后只可记录 existing-carrier spelling；按冻结不重复
完整 `just ci`，不得声明 Array/Option runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-60 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`array(.field, length)` 开放 exact same-line spelling `Array Field bn254_fr N`。Field identifier 必须是
raw exact `bn254_fr`；alternate、escaped、qualified、missing 或 extra id 均 fail closed。`N` 精确复用
Array 的 canonical ASCII decimal `0..4096` discipline 与 `ArrayLength := Fin 4097`。Bytes、Option、
Array、Map、Named element 继续排除。这不是新 ValueType carrier：Source/Semantic encoders 已产生
Array tag `18`、Field tag `2` 与 encoder-local length payload，requirements 也已递归穿过 Array wrapper；
不得新增 ctor/tag、修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `arrayFieldType` 与 struct-field 对应 parser；不得把通用
`arrayType` 或 `portableType` 放宽为任意多 atom，也不得引入 recursive parser。decoder 只从专用 parser
接收 field id 与 length atoms，必须 exact 检查 `bn254_fr` 并复用 `decodeBytesLengthAtom` 的 lexical/bound
验证后构造 `.array .field length`；不得复制或放宽 Field/Array policy。Lean command 与 ParserSession
必须得到同一 Source tree/hash。canonical tests 固定既有 tag `18→2→length` 的 Source/Semantic bytes/hash，
并与 bare Field、bare Array PrimitiveAtom、Option Field、Array Option 及不同 length non-alias；不重编号
tags `0..18`。

tests-only RED 只修改 `Tests.Language.ArrayTypes` 与 `Tests.Language.OptionDeclarations`，将既有两条
`Array Field bn254_fr 4` parser-negative 迁移为 positive，migration count 精确为二，其他测试不得迁移。
positive 覆盖长度 `0`、普通值、`4096`、state、struct field、enum payload、const、initializer/entry/view/fn
parameter/result 与双入口 parity。`Array Field bn254_fr N` 必须递归传播恰一个 `fieldBn254`；四个 Phase 1
target 必须在 support resolution 以 named requirement 拒绝，不得进入 Plan 或产出 artifact。missing/
alternate/escaped/qualified Field id、invalid length、extra/split payload 必须 fail closed；Array Bytes、
Array Option compound、Option Array compound、nested Option、Map/Named 与既有 extra-payload failure class
保持原边界。

本切片不实现 array value/constructor/index/length/slice/mutation、field arithmetic、none/some/unwrap、
任意递归 type grammar、recursive legality、runtime representation、ABI 或 target Array-Field support。
production 仅限 `Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean
package file-set。focused/aggregate/test binary 与 independent review 全绿后只可记录 existing-carrier
spelling；按冻结不重复完整 `just ci`，不得声明 Array/Field runtime semantics、完整 type grammar 或正式
D1 完成。

D1-PA-61 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`array(.bytes innerLength, outerLength)` 开放 exact same-line spelling `Array Bytes N M`。`N` 是 inner
Bytes length，`M` 是 outer Array length；二者都精确复用 canonical ASCII decimal `0..4096` discipline，
其中 `M` 物化为 `ArrayLength := Fin 4097`。Field、Option、Array、Map、Named element 继续排除。
这不是新 ValueType carrier：Source/Semantic encoders 已产生 Array tag `18`、Bytes tag `17`、inner
length 与 outer length payload，requirements 递归结果为空；不得新增 ctor/tag、修改 encoder、Typed
或 target。

frontend 只能新增 exact contextual named `arrayBytesType` 与 struct-field 对应 parser；不得把通用
`arrayType` 或 `portableType` 放宽为任意多 atom，也不得引入 recursive parser。decoder 只从专用 parser
接收 inner length 与 outer length atoms，且两个 length 都必须复用 `decodeBytesLengthAtom` 的 lexical/
bound 验证后构造 `.array (.bytes innerLength) outerLength`；不得复制或放宽 Bytes/Array policy。
Lean command 与 ParserSession 必须得到同一 Source tree/hash。canonical tests 固定既有 tag
`18→17→N→M` 的 Source/Semantic bytes/hash，并与 bare Bytes、bare Array PrimitiveAtom、Option Bytes、
Array Field 及不同 inner/outer length non-alias；不重编号 tags `0..18`。

tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条 `Array Bytes 32 4`
parser-negative 迁移为 positive，migration count 精确为一；`Array Bytes 4` 继续保留为 unsupported
bare Bytes-array negative，其他测试不得迁移。positive 覆盖 inner/outer 长度 `0`、普通值、边界值、
state、struct field、enum payload、const、initializer/entry/view/fn parameter/result 与双入口 parity。
`Array Bytes N M` 必须推导零 requirement；四个 Phase 1 target 通过 support resolution 后仍由既有
non-UInt64 Plan invariant 拒绝，不得产出 artifact。missing/invalid inner 或 outer length、escaped/
qualified constructor 或 Bytes element、extra/split payload 必须 fail closed；Array Field、
Array Option compound、Option Array compound、nested Option、Map/Named 与既有 extra-payload failure
class 保持原边界。

本切片不实现 bytes value/constructor/index/slice/length、array value/constructor/index/length/slice/
mutation、任意递归 type grammar、recursive legality、runtime representation、ABI 或 target Array-Bytes
support。production 仅限 `Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN
刷新 Lean package file-set。focused/aggregate/test binary 与 independent review 全绿后只可记录
existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 Array/Bytes runtime semantics、完整
type grammar 或正式 D1 完成。

D1-PA-62 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`option(option(field))` 开放 exact same-line spelling `Option Option Field bn254_fr`。Field identifier
必须是 raw exact `bn254_fr`；alternate、escaped、qualified、missing 或 extra id 均 fail closed。
PrimitiveAtom nested Option、nested Bytes、nested Array、third-layer Option、Map 与 Named 继续按各自
边界处理，不能因本切片放宽。这不是新 ValueType carrier：Source/Semantic encoders 已产生两层 Option
tag `16→16` 与 Field tag `2`，requirements 也已递归穿过两层 Option wrapper；不得新增 ctor/tag、
修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionOptionFieldType` 与 struct-field 对应 parser；不得把既有
`optionOptionType` 从 PrimitiveAtom 放宽到 Field/Bytes/Array，也不得放宽 `portableType` 或引入 recursive
parser。decoder 只从专用 parser 接收 field id atom，必须 exact 检查 raw `bn254_fr` 后构造
`.option (.option .field)`；不得复制或放宽 Field/nested Option policy。Lean command 与 ParserSession
必须得到同一 Source tree/hash。canonical tests 固定既有 tag `16→16→2` 的 Source/Semantic bytes/hash，
并与 bare Field、Option Field、Option Option PrimitiveAtom 及不同 element non-alias；不重编号 tags
`0..18`。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
`Option Option Field bn254_fr` parser-negative 迁移为 positive，migration count 精确为一；
`Option Option Field` 继续保留为 unsupported incomplete nested-field negative，其他测试不得迁移。
positive 覆盖 state、struct field、enum payload、const、initializer/entry/view/fn parameter/result 与
双入口 parity。`Option Option Field bn254_fr` 必须递归传播恰一个 `fieldBn254`；四个 Phase 1 target
必须在 support resolver 以 named requirement 拒绝，不得进入 Plan 或产出 artifact。missing/alternate/
escaped/qualified Field id、escaped/qualified Option 或 Field constructor、extra/split payload 必须 fail
closed；Option Option Bytes、Option Option Array、third-layer Option、Option Array compounds、Array
Option compounds、Array Array、Map/Named 与既有 extra-payload failure class 保持原边界。

本切片不实现 none/some/unwrap、field arithmetic、任意 recursive type grammar、recursive legality、
runtime representation、ABI 或 target nested-Option-Field support。production 仅限 `Language/Syntax.lean`
一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。focused/aggregate/test
binary 与 independent review 全绿后只可记录 existing-carrier spelling；按冻结不重复完整 `just ci`，
不得声明 nested Option/Field runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-63 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`option(option(bytes(length)))` 开放 exact same-line spelling `Option Option Bytes N`。`N` 精确复用
Bytes 的 canonical ASCII decimal `0..4096` discipline；除单个 `0` 外禁止前导零，禁止 `_`、base
prefix、符号、identifier、缺失/额外 payload 或跨行 payload。这项决定显式 supersede D1-PA-56 与
D1-PA-62 对 `Option Option Bytes` 的临时拒绝边界；为保持两层 Option wrapper 深度并先补齐既有 leaf
family，third-layer Option 继续 deferred。这不是新 ValueType carrier：Source/Semantic encoders 已产生
两层 Option tag `16→16`、Bytes tag `17` 与 length payload，requirements 递归结果为空；不得新增
ctor/tag、修改 encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionOptionBytesType` 与 struct-field 对应 parser；不得把既有
`optionOptionType`、`optionBytesType` 或 `portableType` 放宽，也不得引入 recursive parser。新增的 nested
decoder 必须复用 `decodeOptionBytesValueTypeFromAtoms` 的完整 lexical/bound policy，再只包一层 Option；
不得复制或放宽 Bytes/nested Option policy。专用 parser/dispatch 必须先于 generic `optionOptionType`。
Lean command 与 ParserSession 必须得到同一 Source tree/hash。canonical tests 固定既有 tag
`16→16→17→length` 的 Source/Semantic bytes/hash，并与 bare Bytes、Option Bytes、Option Option
PrimitiveAtom、Option Option Field 及不同 length non-alias；不重编号 tags `0..18`。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
`("full Bytes nested option", "Option Option Bytes 8")` parser-negative 迁移为 positive，migration count
精确为一；`Option Option Bytes` 继续保留为 unsupported incomplete nested-Bytes negative，其他测试不得
迁移。positive 覆盖 length `0`、普通值、`4096`、state、struct field、enum payload、const、event/error
parameter、initializer/entry/view/fn parameter/result 与双入口 parity。requirements 必须为空；四个 Phase 1
target 通过 support resolver 后，non-UInt64 state/result/parameter 仍由既有 Plan invariant 拒绝，不得产出
artifact。length `4097`/`01`/hex/underscore/signed/identifier、escaped/qualified Option 或 Bytes
constructor、extra/split payload 必须 fail closed；Option Option Array、third-layer Option、Map/Named 与
既有 compound 边界不变。

本切片不实现 bytes value/index/slice/length、none/some/unwrap、任意 recursive type grammar、recursive
legality、runtime representation、ABI 或 target nested-Option-Bytes support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused/aggregate/test binary 与 independent review 全绿后只可记录 existing-carrier spelling；按冻结不
重复完整 `just ci`，不得声明 nested Option/Bytes runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-64 冻结的 pre-acceptance alpha 子集只为已经可由 Source/Semantic recursive carriers 构造的
`option(option(array(element,length)))` 开放 exact same-line spelling `Option Option Array PrimitiveAtom N`。
`PrimitiveAtom` 沿既有 15-atom Array policy 解码，`N` 精确复用 Array 的 canonical ASCII decimal `0..4096`
discipline；不得开放 Field/Bytes/Option/Array/Map/Named element。既有 encoder 定义两层 Option tag
`16→16`、Array tag `18`、element tag 与 length payload，requirements 递归传播；不得新增 ctor/tag、修改
encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionOptionArrayType` 与 struct-field 对应 parser；不得放宽既有
`optionOptionType`、`optionArrayType`、`arrayType` 或 `portableType`，不得引入 recursive parser。新增 decoder
必须复用既有 Option/Array/PrimitiveAtom 与 length policy，再只包一层 Option；专用 dispatch 必须先于 generic
`optionOptionType`。tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
`Option Option Array UInt64 4` parser-negative 迁移为 positive，migration count 精确为一；不完整
`Option Option Array` 与所有 compound/third-layer boundaries 继续 fail closed。positive 覆盖 length
`0`/普通值/`4096`、all declaration positions including event/error parameters、双入口 parity、canonical
tag `16→16→18→element→length`、requirements、四 target support-vs-Plan boundary 与 no-artifact controls。

本切片不实现 array value/index/slice/length/mutation、none/some/unwrap、任意 recursive type grammar、
recursive legality、runtime representation、ABI 或 target nested-Option-Array support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set；按
冻结不重复完整 `just ci`，不得声明 nested Option/Array runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-65 冻结的 pre-acceptance alpha 子集只为已有 `option(array(field,length))` carrier 开放 exact
same-line spelling `Option Array Field bn254_fr N`。`N` 复用 Array 的 canonical ASCII decimal `0..4096`
policy，Field id 只接受 raw `bn254_fr`；tag 固定 `16→18→2→length`，requirements 精确传播单个
`fieldBn254`。frontend 只能新增 named `optionArrayFieldType` 与 struct-field parser，decoder 复用既有
Array length/raw Field policy；不得放宽 `optionArrayType`、`arrayType` 或 `portableType`，不得修改 ctor/tag、
encoder、Typed 或 target。tests-only RED 只迁移既有一条 full Field Option Array negative，positive 覆盖
all declaration positions including event/error 与双入口，四 target support 后 named requirement 拒绝且无
artifact；invalid length/id、escaped/qualified constructors、extra/split payload 与 compounds 保持 fail closed。
production 仅限 `Language/Syntax.lean` ≤32 additions/2 removals，GREEN 同步 package file-set；按冻结不重复
完整 `just ci`，不得声明 Option/Array/Field runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-66 冻结的 pre-acceptance alpha 子集只为已有
`array(array(element,innerLength),outerLength)` carrier 开放 exact same-line spelling
`Array Array PrimitiveAtom N M`。`PrimitiveAtom` 复用 Array 的 15 个 exact single-token atom，`N` 是
inner length、`M` 是 outer length，均为 canonical ASCII decimal `0..4096`；tag 固定
`18→18→element→N→M`，requirements 精确透传 element requirements。frontend 只能新增 named
`arrayArrayType` 与 struct-field parser；decoder 必须复用既有 PrimitiveAtom 与 length policy，且专用
dispatch 必须先于 generic `arrayType`。不得放宽 `arrayType`/`portableType`，不得修改 ctor/tag、encoder、
Typed 或 target。tests-only RED 只迁移既有一条 `Array Array UInt64 4 4` negative，migration count
精确为一；incomplete Array Array、Field/Bytes/Option/Array/Map/Named compounds、escaped/qualified
constructors 与 split/extra payload 继续 fail closed。production 仅限 Syntax 一文件 ≤32 additions/2 removals，
GREEN 同步 package file-set；不得声明 nested Array runtime semantics、完整 recursive type grammar 或正式
D1 完成。

D1-PA-67 冻结的 pre-acceptance alpha 子集只为已有
`option(array(option(element),length))` carrier 开放 exact same-line spelling
`Option Array Option PrimitiveAtom N`。`PrimitiveAtom` 复用 15 个 exact atom，`N` 复用 canonical ASCII
decimal `0..4096`；tag 固定 `16→18→16→element→length`，requirements 精确透传 inner Option element。
frontend 只能新增 named `optionArrayOptionType` 与 struct-field parser，decoder 必须复用既有 Option/Array/
PrimitiveAtom/length policy，并在 generic `optionArrayType` 前 dispatch。不得放宽 `optionArrayType`、
`arrayType`、`optionOptionType` 或 `portableType`，不得修改 ctor/tag、encoder、Typed 或 target。tests-only
RED 只迁移既有一条 `Option Array Option Bool 4` negative；third-layer Option、Option Array Bytes/Array、
Map/Named 与 invalid/extra/split/escaped/qualified boundaries 继续 fail closed。production 仅限 Syntax 一文件
≤32 additions/2 removals，GREEN 同步 package file-set；不得声明 nested Option/Array runtime semantics、完整
recursive grammar 或正式 D1 完成。

D1-PA-68 冻结的 pre-acceptance alpha 子集只为已有
`option(array(bytes(innerLength),outerLength))` carrier 开放 exact same-line spelling
`Option Array Bytes N M`。`N` 是 inner Bytes length、`M` 是 outer Array length，均复用 canonical ASCII
decimal `0..4096`；tag 固定 `16→18→17→N→M`，requirements 精确为空。frontend 只能新增 named
`optionArrayBytesType` 与 struct-field parser，decoder 必须复用 `decodeArrayBytesValueTypeFromAtoms` 后只包
一层 Option，并在 generic `optionArrayType` 前 dispatch。不得放宽 `optionArrayType`、`arrayBytesType`、
`arrayType` 或 `portableType`，不得修改 ctor/tag、encoder、Typed 或 target。tests-only RED 只迁移既有一条
`Option Array Bytes 8 4` negative；Option Array Array、Array Option compounds、third-layer Option、Map/Named 与
invalid/extra/split/escaped/qualified boundaries 继续 fail closed。production 仅限 Syntax 一文件 ≤32 additions/
2 removals，GREEN 同步 package file-set；不得声明 Option/Array/Bytes runtime semantics、完整 recursive grammar
或正式 D1 完成。

D1-PA-69 冻结的 pre-acceptance alpha 子集只为已有
`option(array(array(element,innerLength),outerLength))` carrier 开放 exact same-line spelling
`Option Array Array PrimitiveAtom N M`。`PrimitiveAtom` 复用 15 个 exact atom，`N` 是 inner Array length、
`M` 是 outer Array length，均复用 canonical ASCII decimal `0..4096`；tag 固定
`16→18→18→element→N→M`，requirements 精确透传 element。frontend 只能新增 named
`optionArrayArrayType` 与 struct-field parser，decoder 必须复用 `decodeArrayArrayValueTypeFromAtoms` 后只包
一层 Option，并在 generic `optionArrayType` 前 dispatch。不得放宽 `optionArrayType`、`arrayArrayType`、
`arrayType` 或 `portableType`，不得修改 ctor/tag、encoder、Typed 或 target。tests-only RED 只迁移既有一条
`Option Array Array UInt64 4 4` negative；non-Primitive compounds、Array Option compounds、third-layer Option、
Map/Named 与 invalid/extra/split/escaped/qualified boundaries 继续 fail closed。production 仅限 Syntax 一文件
≤32 additions/2 removals，GREEN 同步 package file-set；不得声明 nested Array runtime semantics、完整 recursive
grammar 或正式 D1 完成。

D1-PA-70 冻结的 pre-acceptance alpha 子集只为已有
`option(option(option(element)))` carrier 开放 exact same-line spelling
`Option Option Option PrimitiveAtom`。`PrimitiveAtom` 仍是 15 个 exact single-token atom，tag 固定
`16→16→16→element`，requirements 经三层 Option 精确透传 element。frontend 只能新增 named
`optionOptionOptionType` 与 struct-field parser；decoder 必须复用既有 closed
`decodeNestedOptionValueTypeFromAtoms` 后只包一层 Option，并在 generic `optionOptionType` 前 dispatch。
不得放宽 `optionOptionType` 或 `portableType`，不得修改 ctor/tag、encoder、Typed 或 target。
本冻结只对 exact 三层 Option + PrimitiveAtom spelling 显式 supersede 此前各切片中的 “third-layer Option
deferred/继续 fail closed/保持两层 Option wrapper 深度” 边界；它不建立任意递归 Option grammar。tests-only
RED 只迁移既有一条 `Option Option Option Bool` negative；Field/Bytes/Array/Option/Map/Named element、第四层
Option、invalid/extra/split/escaped/qualified boundaries 继续 fail closed。production 仅限 Syntax 一文件
≤32 additions/2 removals，GREEN 同步 package file-set；不得声明 none/some/unwrap、runtime/ABI、target
three-layer Option support、完整 recursive grammar 或正式 D1 完成。

D1-PA-71 冻结的 pre-acceptance alpha 子集只为已有
`array(option(option(element)),length)` carrier 开放 exact same-line spelling
`Array Option Option PrimitiveAtom N`。`PrimitiveAtom` 精确复用 15 个 exact single-token atom；`N` 精确
复用 Array 的 canonical ASCII decimal `0..4096` discipline，tag 固定
`18→16→16→element→N`，requirements 经两层 Option 与外层 Array 精确透传 element。本冻结只为此 exact
spelling supersede D1-PA-59 的 “Option element excluded/fail closed” 边界，以及 D1-PA-60/61/62/68/69 的
“Array Option compounds 继续 fail closed” residual；只开放第二层 Option 的 leaf 为 PrimitiveAtom 的这一
形状。Array Option Bytes/Array、第三层 inner Option、Array Array non-Primitive、Map/Named 仍不开放，也不
建立任意递归 grammar；这些保留项只保持既有 negatives，不新增 PA71 migration 或无关测试完成条件。

frontend 只能新增 exact contextual named `arrayOptionOptionType` 与 struct-field 对应 parser；不得放宽既有
`arrayOptionType`、`arrayType`、`optionOptionType` 或 `portableType`，不得引入 recursive parser。新增 decoder
必须复用 `decodeArrayValueTypeFromAtoms` 的完整 15-atom/length policy，再构造
`.array (.option (.option element)) length`；专用 type 与 aggregate dispatch 必须先于 generic
`arrayOptionType`/`arrayOptionAggregateField`。不得新增 ctor/tag、修改 encoder、Typed 或 target。

tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
`("nested Array Option element", "Array Option Option Bool 4")` parser-negative 迁移为 positive，migration
count 精确为一，其他测试不得迁移。positive 覆盖全部 15 个 PrimitiveAtom、长度 `0`/普通值/`4096`、所有
declaration positions 与 Lean command/ParserSession parity；canonical tests 固定 UInt64 长度 `0/4/4096`、
Bool 长度 `0`、Principal 长度 `4096` 五组 Source/Semantic vectors。candidate
`Array Option Option UInt64 4` 必须分别与相同 payload 的 `Array Option UInt64 4`、
`Option Array Option UInt64 4` 和 `Option Option UInt64` non-alias；五组 candidate 内部必须固定
UInt64 `0≠4≠4096`、UInt64 0≠Bool 0、UInt64 4096≠Principal 4096。UInt64 requirements 必须为空，Bool
必须传播恰一个 `boolValues`。四个 Phase 1 target 对 Bool 必须在 support resolver 以 named
`boolValues` 拒绝且不得进入 Plan；UInt64 surface 通过 support 后，state/result/parameter 三个 dedicated
fixtures 必须分别在四 target 触发既有 `is not UInt64`/`does not return UInt64` Plan invariant，且所有路径
均不得产出 artifact。missing/invalid length、Field/Bytes/Array/Option/Map/Named inner、escaped/qualified
constructors 或 element、extra/split payload 必须 fail closed。

本切片不实现 array/option value operations、none/some/unwrap、任意 recursive type grammar、recursive
legality、runtime representation、ABI 或 target Array-nested-Option support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可记录
existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type grammar 或
正式 D1 完成。

D1-PA-72 冻结的 pre-acceptance alpha 子集只为已有
`array(option(bytes(innerLength)),outerLength)` carrier 开放 exact same-line spelling
`Array Option Bytes N M`。`N` 是 inner Bytes length，`M` 是 outer Array length；两者都精确复用 canonical
ASCII decimal `0..4096` discipline，tag 固定 `18→16→17→N→M`，requirements 精确为空。本冻结只为此
exact spelling supersede D1-PA-59 的 “Bytes element excluded/fail closed” 边界、D1-PA-60/61/62/68/69 的
broad “Array Option compounds 继续 fail closed” residual 及 D1-PA-71 明示保留的 Array Option Bytes
negative；只开放 Option leaf 为 Bytes 的双长度形状。Array Option Array、Array Array non-Primitive、第三层
inner Option、Map/Named 仍不开放且只保持既有 negatives，不新增 PA72 migrations 或无关完成条件。

frontend 只能新增 exact contextual named `arrayOptionBytesType` 与 struct-field 对应 parser；不得放宽既有
`arrayOptionType`、`arrayBytesType`、`arrayType` 或 `portableType`，不得引入 recursive parser。新增 decoder
必须复用 `decodeArrayBytesValueTypeFromAtoms` 的完整 dual-length lexical/bound policy，并且只把其
`.array (.bytes innerLength) outerLength` 结果改构造为
`.array (.option (.bytes innerLength)) outerLength`；专用 type 与 aggregate dispatch 必须先于 generic
`arrayOptionType`/`arrayOptionAggregateField`。不得新增 ctor/tag、修改 encoder、Typed 或 target。

tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
`("nested Bytes Array Option element", "Array Option Bytes 8 4")` parser-negative 迁移为 positive，migration
count 精确为一，其他测试不得迁移。positive 覆盖 inner/outer length `0/0`、`8/4`、`4096/1`、所有
declaration positions（含 event/error）与 Lean command/ParserSession parity。Source/Semantic canonical
tests 固定上述三组 vectors；candidate `Array Option Bytes 8 4` 必须分别与相同 payload 的
`Array Bytes 8 4`、`Option Array Bytes 8 4` non-alias，并与 `Array Option UInt64 4`、`Option Bytes 8`
固定 leaf/wrapper 差异；三组 candidates 必须 pairwise non-alias；`Array Option Bytes 8 4` 必须分别与
`Array Option Bytes 0 4`（只改变 inner length）、`Array Option Bytes 8 0`（只改变 outer length）以及交换
双长度后的 `Array Option Bytes 4 8` non-alias。requirements 必须为空，四个 Phase 1 target 必须通过
support；state/result/parameter dedicated fixtures 必须分别在四 target 触发既有
`is not UInt64`/`does not return UInt64` Plan invariant，且所有路径均不得产出 artifact。

missing inner/outer length、两长度各自的 invalid lexical/bound forms、Field/Array/Option/Map/Named inner、
escaped/qualified Array/Option/Bytes constructor、extra/split payload 必须 fail closed。本切片不实现
bytes/array/option value operations、none/some/unwrap、任意 recursive type grammar、recursive legality、
runtime representation、ABI 或 target Array-Option-Bytes support。production 仅限 `Language/Syntax.lean`
一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。focused 23-job、192-job
aggregate/test binary、`just sbom` 与 independent review 全绿后只可记录 existing-carrier spelling；按冻结
不重复完整 `just ci`，不得声明 runtime semantics、完整 type grammar 或正式 D1 完成。

D1-PA-73 冻结的 pre-acceptance alpha 子集只为已有
`option(option(option(field)))` carrier 开放 exact same-line spelling
`Option Option Option Field bn254_fr`。Field identifier 必须是 raw exact `bn254_fr`，tag 固定
`16→16→16→2`，requirements 经三层 Option 精确透传为单个 `fieldBn254`。本冻结只对这一 exact
spelling supersede D1-PA-62 的 third-layer Field deferred 与 D1-PA-70 的 Field-element fail-closed 项；
PA55/PA62 已完成的一层/两层 Field spelling
保持不变，Bytes/Array/Option/Map/Named leaf、第四层 Option 与任意 recursive Option grammar 继续 fail
closed。不得新增 ctor/tag、修改 Source/Semantic encoder、Typed 或 target。

frontend 只能新增 exact contextual named `optionOptionOptionFieldType` 与 struct-field 对应 parser；不得
放宽既有 `optionOptionOptionType`、`optionOptionFieldType`、`optionOptionType` 或 `portableType`，不得引入
recursive parser。新增 decoder 必须复用 closed `decodeNestedOptionFieldValueTypeFromAtoms` 的 raw
`bn254_fr` exact policy，再只包一层 Option；专用 type 与 aggregate dispatch 必须先于 generic
`optionOptionOptionType`/aggregate parser。Lean command 与 ParserSession 必须得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
`("full Field Triple Option element", "Option Option Option Field bn254_fr")` parser-negative 迁移为
positive，migration count 精确为一；incomplete `Option Option Option Field` 继续保留为 negative，其他
测试不得迁移。positive 覆盖所有 declaration positions（含 event/error）与双入口 parity。Source/Semantic
canonical tests 各固定一个 exact vector，并在两侧分别与 bare Field、一层/两层 Option Field、同深度
UInt64/Bool 做 canonical bytes/hash non-alias，证明第三 wrapper 与 Field leaf 都进入 preimage。requirements
必须恰为单个 `fieldBn254`；四个 Phase 1 target 的 `Targets.checkSupport` 与
`Targets.materializeResult` 必须都返回 exact `.unsupportedRequirement .fieldBn254 actualTarget` 且
`actualTarget == target`，证明不能进入 Plan、`OutputSet` 或产出 artifact。

error channel 经 GREEN 前 focused runtime probe 校正如下：incomplete/alternate/escaped/qualified Field id、
第三个 Option constructor 的 escaped/qualified form及第三个 Option 后换行必须 exact
`unsupported portable type`；extra payload、第一/第二个 Option 后或 Field/id 之间换行、第一/第二个
Option constructor 任一位置与 Field constructor 的 escaped/qualified form 必须 parser-rejected。这项
empirical channel correction 不改变 Output、Tests 集合、migration count 或 Done 语义。
Bytes/Array/Option/Map/Named leaf 与
第四层 Option 只保持既有 negatives，不新增完成条件。本切片不实现 none/some/unwrap、field literal/
arithmetic、任意 recursive type grammar、recursive legality、runtime representation、ABI 或 target
triple-Option-Field support。production 仅限 `Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，
并在同一 GREEN 刷新 Lean package file-set。focused 23-job、192-job aggregate/test binary、`just sbom` 与
independent review 全绿后只可记录 existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明
runtime semantics、完整 type grammar 或正式 D1 完成。post-PA-72 bounded arbitration 因本 spelling 只有
单一 Field leaf/golden、无双长度与 15-atom matrix，选择它而非更大的
`Array Option Array PrimitiveAtom N M`；该选择不是 checkpoint 自动递增。

D1-PA-74 冻结的 pre-acceptance alpha 子集只为已有
`option(option(option(bytes(length))))` carrier 开放 exact same-line spelling
`Option Option Option Bytes N`。`N` 精确复用 Bytes 的 canonical ASCII decimal `0..4096` discipline，
tag 固定 `16→16→16→17→N`，requirements 经三层 Option 精确透传为空。本冻结只对这一 exact
spelling supersede D1-PA-63 的 third-layer deferred、D1-PA-70 的 Bytes-element fail-closed 项与 D1-PA-73
明示保留的 Bytes leaf；PA63 已完成的两层 Option Bytes 与 PA73 已完成的三层 Option Field 保持不变，
Array/Option/Map/Named leaf、第四层 Option 与任意 recursive Option grammar 继续 fail closed。post-PA-73
bounded arbitration 因本候选只有单一 length 轴、无需 15-atom/dual-length matrix，选择它而非更大的
`Array Option Array PrimitiveAtom N M`；该选择不是 checkpoint 自动递增。

frontend 只能新增 exact contextual named `optionOptionOptionBytesType` 与 struct-field 对应 parser；不得
放宽既有 `optionOptionOptionType`、`optionOptionBytesType`、`optionOptionType` 或 `portableType`，不得引入
recursive parser。新增 decoder 必须复用 closed `decodeNestedOptionBytesValueTypeFromAtoms` 的完整 Bytes
lexical/bound policy，再只包一层 Option；专用 type 与 aggregate dispatch 必须先于 generic
`optionOptionOptionType`/aggregate parser。不得新增 ctor/tag、修改 Source/Semantic encoder、Typed 或 target；
Lean command 与 ParserSession 必须得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
`("Bytes Triple Option element", "Option Option Option Bytes 8")` parser-negative 迁移为 positive，
migration count 精确为一；incomplete `Option Option Option Bytes` 继续保留为 unsupported，其他测试不得
迁移。positive 覆盖 length `0`、`8`、`4096`、所有 declaration positions（含 event/error）与双入口 parity。
Source/Semantic canonical tests 各固定三组 length vectors；`N=8` candidate 必须在两侧分别与 bare Bytes、
一层/两层 Option Bytes、同深度 UInt64 与同深度 Field 做 canonical bytes/hash non-alias，三组 lengths 也必须
pairwise non-alias，证明第三 wrapper、Bytes leaf 与完整 length payload 都进入 preimage。requirements 必须
精确为空；四个 Phase 1 target 必须通过 `Targets.checkSupport`，随后 state/result/parameter 三个 dedicated
fixtures 必须分别由 `Targets.materializeResult` 的既有 non-UInt64 Plan invariant 拒绝，且不得产生
`OutputSet` 或 artifact。

pre-freeze minimal parser probe 已固定 error channel：incomplete spelling、`4097`/leading-zero/hex/underscore
length、full/bare Map 与 unknown leaf 必须 exact `unsupported portable type`；negative/identifier length、extra
payload、任一 Option/Bytes-length seam 换行、三个 Option constructor 或 Bytes constructor 的 escaped/
qualified form、full Array leaf 与第四层 Option 必须 parser-rejected。Field triple spelling 保持 PA73 positive，
只作为 canonical non-alias control，不得迁回 negative。其他 Array/Option/Map/Named compound cases只保持既有
fail-closed 边界，不新增完成条件。

本切片不实现 bytes value/index/slice/length、none/some/unwrap、任意 recursive type grammar、recursive
legality、runtime representation、ABI 或 target triple-Option-Bytes support。production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可记录
existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type grammar 或
正式 D1 完成。

D1-PA-75 冻结的 pre-acceptance alpha 子集只为已有
`option(option(array(field,length)))` carrier 开放 exact same-line spelling
`Option Option Array Field bn254_fr N`。Field identifier 必须是 raw exact `bn254_fr`；`N` 精确复用
Array 的 canonical ASCII decimal `0..4096` discipline，tag 固定 `16→16→18→2→N`，requirements 经两层
Option 与 Array 精确透传为单个 `fieldBn254`。本冻结只对这一 exact spelling supersede D1-PA-64 的
`optionOptionArray` Field-leaf fail-closed residual，并在 D1-PA-65 已完成的
`Option Array Field bn254_fr N` carrier spelling 外再包一层 Option；PA64 的
`Option Option Array PrimitiveAtom N`、PA65 的直接前驱 spelling 与 PA73/74 的三层 Option spelling
保持不变。Bytes/Option/Array/Map/Named leaf 于该 compound 之下、更深 unanchored Option 与任意
recursive grammar 继续 fail closed。

post-PA-74 bounded residual audit 与 challenge correction 明确记录：expression 侧当前没有可合法冻结的
parser-only residual candidate；type 侧固定 Field leaf + 单 length 的
`Option Option Array Field bn254_fr N` 客观小于 `Option Option Option Array PrimitiveAtom N`（后者需要
15-atom matrix 与 Bool/UInt64 混合 support/Plan 控制）。该选择不是 checkpoint 自动递增，也不是为凑 PA
序号。

frontend 只能新增 exact contextual named `optionOptionArrayFieldType` 与 struct-field 对应 parser；不得
放宽既有 `optionOptionArrayType`、`optionArrayFieldType`、`optionOptionType` 或 `portableType`，不得引入
recursive parser。新增 decoder 必须复用 closed `decodeOptionArrayFieldValueTypeFromAtoms` 的 raw
`bn254_fr` 与完整 Array length lexical/bound policy，再只包一层 Option；专用 type 与 aggregate dispatch
必须先于 generic `optionOptionArrayType`/aggregate parser。不得新增 ctor/tag、修改 Source/Semantic
encoder、Typed 或 target；Lean command 与 ParserSession 必须得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
`("full Field nested Array element", "Option Option Array Field bn254_fr 4")` parser-negative 迁移为
positive，migration count 精确为一；incomplete `Option Option Array Field 4` 继续保留为 exact
unsupported，其他测试不得迁移。positive 覆盖 length `0`、`4`、`4096`、所有 declaration positions（含
event/error）与双入口 parity。Source/Semantic canonical tests 各固定三组 length vectors；`N=4`
candidate 必须在两侧分别与 `Option Array Field bn254_fr 4`、`Option Option Array UInt64 4`、
`Option Option Field bn254_fr`、以及 twin 构造的 `Array Option Option Field bn254_fr 4`
（`.array (.option (.option .field)) 4`）做 canonical bytes/hash non-alias，三组 lengths 也必须 pairwise
non-alias。requirements 必须恰为单个 `fieldBn254`；四个 Phase 1 target 的 `Targets.checkSupport` 与
`Targets.materializeResult` 必须都返回 exact `.unsupportedRequirement .fieldBn254 actualTarget` 且
`actualTarget == target`，证明不能进入 Plan、`OutputSet` 或产出 artifact。

empirical GREEN 后 error channel 固定如下：incomplete spelling、alternate/escaped/qualified Field id、
length `4097`/leading-zero/`0x10`/`4_096`、bare Bytes/Option/Array/Map 与 `Widget 4` Named/unknown leaf
必须 exact `unsupported portable type`；missing/negative/identifier length、extra payload、五个
Option/Array/Field/id/length same-line seam 换行、四个 constructor（两层 Option、Array、Field）的
escaped/qualified form、full Bytes/Option/Array/Map compounds 必须 parser-rejected。不得使用虚假
Named constructor 作为 unsupported 主控（`Widget 4` 仅作 unknown/Named-like control）；不得把更深
unanchored Option 或 triple Option Array 迁入本切片。

本切片不实现 field arithmetic、array/option value operations、none/some/unwrap、任意 recursive type
grammar、recursive legality、runtime representation、ABI 或 target nested-Option-Array-Field support。
production 仅限 `Language/Syntax.lean` 一文件，最多 30 行新增、2 行移除，并在同一 GREEN 刷新 Lean
package file-set。focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后
只可记录 existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type
grammar 或正式 D1 完成。

D1-PA-76 冻结的 pre-acceptance alpha 子集只为已有
`array(option(option(field)),length)` carrier 开放 exact same-line spelling
`Array Option Option Field bn254_fr N`。Field identifier 必须是 raw exact `bn254_fr`；`N` 精确复用
Array 的 canonical ASCII decimal `0..4096` discipline，tag 固定 `18→16→16→2→N`，requirements 经
Array 与两层 Option 精确透传为单个 `fieldBn254`。本冻结只对 D1-PA-71 明示保留的 exact Field leaf
residual supersede fail-closed boundary；PA60 的 `Array Field`、PA71 的 `Array Option Option PrimitiveAtom`、
PA75 的 wrapper-order twin 均保持不变。Bytes/Option/Array/Map/Named leaf、更深 Option、dual-length 与任意
recursive grammar 继续 fail closed。

post-PA-75 residual audit 的四路 challenge 以总验收面而非 production 行数仲裁：本候选只有 fixed Field
与 single length，且在 support resolver 提前拒绝；`Option Option Array Bytes N M` 需要 dual-length
canonical 轴并在 support-pass 后覆盖 state/result/parameter target-owned Plan rejection，
`Option Option Option Array PrimitiveAtom N` 增加 PrimitiveAtom element 轴与 zero/`boolValues`
requirement/support 分支。因此选择本候选不是 checkpoint 自动递增，也不是按 type family 补齐。

frontend 只能新增 exact contextual named `arrayOptionOptionFieldType` 与 struct-field 对应 parser；不得
放宽既有 `arrayOptionOptionType`、`arrayFieldType`、`arrayOptionType` 或 `portableType`，不得引入 recursive
parser。新增 decoder 必须复用 closed `decodeArrayFieldValueTypeFromAtoms` 的 raw `bn254_fr` 与完整 Array
length lexical/bound policy，再只把 element 包两层 Option；专用 type 与 aggregate dispatch 必须先于
generic `arrayOptionOptionType`/aggregate parser。不得新增 ctor/tag、修改 Source/Semantic encoder、Typed
或 target；Lean command 与 ParserSession 必须得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
`("full Field Array Option Option element", "Array Option Option Field bn254_fr 4")` parser-negative
迁移为 positive，migration count 精确为一；incomplete `Array Option Option Field 4` 继续保留为 exact
unsupported，其他测试不得迁移。positive 覆盖 length `0`、`4`、`4096`、所有 declaration positions
（含 event/error）与双入口 parity。Source/Semantic canonical tests 各固定三组 length vectors；`N=4`
candidate 必须在两侧分别与 `Array Option Field bn254_fr 4`、`Array Option Option UInt64 4`、
`Option Option Array Field bn254_fr 4`、`Option Option Field bn254_fr` 做 canonical bytes/hash non-alias，
三组 lengths 也必须 pairwise non-alias。非 surface-positive control 用既有 carrier 手工构造，不得借测试
开放额外 spelling。requirements 必须恰为单个 `fieldBn254`；四个 Phase 1 target 的
`Targets.checkSupport` 与 `Targets.materializeResult` 必须都返回 exact
`.unsupportedRequirement .fieldBn254 actualTarget` 且 `actualTarget == target`，证明不能进入 Plan、
`OutputSet` 或产出 artifact。

冻结 error channel 如下：incomplete spelling、alternate/escaped/qualified Field id、length `4097`/
leading-zero/`0x10`/`4_096`、bare Bytes/Option/Array/Map 与 `Widget 4` unknown/Named-like leaf 必须 exact
`unsupported portable type`；missing/negative/identifier length、extra payload、五个 Array/Option/Field/id/
length same-line seam 换行、四个 constructor（Array、两层 Option、Field）的 escaped/qualified form、
full Bytes/Option/Array/Map compounds 必须 parser-rejected。若 GREEN empirical probe 与冻结 channel
不一致，必须在 GREEN 前以独立规格修正提交闭合，不得静默改断言或扩大 positive。

本切片不实现 field arithmetic、array/option value operations、none/some/unwrap、任意 recursive type
grammar、recursive legality、runtime representation、ABI 或 target Array-Option-Option-Field support。
tests-only RED 仅限 `Tests/Language/ArrayTypes.lean`，最多 320 行新增、2 行移除；production 仅限
`Language/Syntax.lean` 一文件，最多 30 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可记录
existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type grammar 或
正式 D1 完成。

D1-PA-77 冻结的 pre-acceptance alpha 子集只为已有
`array(array(field,innerLength),outerLength)` carrier 开放 exact same-line spelling
`Array Array Field bn254_fr N M`。Field identifier 必须是 raw exact `bn254_fr`；`N`/`M` 分别表示 inner/
outer Array length，并各自精确复用 canonical ASCII decimal `0..4096` discipline；tag 固定
`18→18→2→N→M`，requirements 经两层 Array 精确透传为单个 `fieldBn254`。本冻结只对 D1-PA-66
明示保留的 exact Field leaf residual supersede fail-closed boundary；PA60 的 `Array Field`、PA66 的
`Array Array PrimitiveAtom` 与 PA76 的 Array/Option/Option wrapper 均保持不变。Bytes/Option/Array/Map/
Named leaf、第三层 Array 与任意 recursive grammar 继续 fail closed。

post-PA-76 三路独立 residual audit 均按总验收面选择本候选：它与
`Option Option Array Bytes N M` 同为 fixed leaf + dual length，但 Field 在 support resolver 前置拒绝，
不需要 zero-requirement 候选的 state/result/parameter target-owned Plan fixtures；PrimitiveAtom 候选还
增加 element 轴与 zero/`boolValues` requirement 分支。该选择不是 checkpoint 自动递增或 type family
补齐。

frontend 只能新增 exact contextual named `arrayArrayFieldType` 与 struct-field 对应 parser；不得放宽
既有 `arrayArrayType`、`arrayFieldType`、`arrayType` 或 `portableType`，不得引入 recursive parser。
新增 decoder 必须对 inner `[fieldId,N]` 复用 closed `decodeArrayFieldValueTypeFromAtoms` 的 raw
`bn254_fr`/length policy，对 outer `M` 复用 `decodeBytesLengthAtom` 与既有 Array `0..4096` bound，再只包
一层 outer Array；专用 type 与 aggregate dispatch 必须先于 generic `arrayArrayType`/aggregate parser。
不得新增 ctor/tag、修改 Source/Semantic encoder、Typed 或 target；Lean command 与 ParserSession 必须
得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
`("full Field Array Array element", "Array Array Field bn254_fr 4 4")` parser-negative 迁移为 positive，
migration count 精确为一；incomplete `Array Array Field 4 4` 继续保留为 exact unsupported，其他测试
不得迁移。positive 覆盖 `(inner,outer)=(0,0)/(4,4)/(4096,1)`、所有 declaration positions（含 event/
error）与双入口 parity。Source/Semantic canonical tests 各固定三组 vectors；ordinary candidate 必须在
两侧分别与 `Array Array UInt64 4 4`、`Array Field bn254_fr 4`、`Option Array Field bn254_fr 4` 做
canonical bytes/hash non-alias，并用手工 carrier controls 在 Source/Semantic 两侧固定 `8/4` 对 `0/4`
（inner-only）、`8/4` 对 `8/0`（outer-only）与 `8/4` 对 `4/8`（swapped-order）non-alias；
非 surface-positive control 不得借测试开放额外 spelling。requirements 必须
恰为单个 `fieldBn254`；四个 Phase 1 target 的 `Targets.checkSupport` 与
`Targets.materializeResult` 必须都返回 exact `.unsupportedRequirement .fieldBn254 actualTarget` 且
`actualTarget == target`，证明不能进入 Plan、`OutputSet` 或产出 artifact。

冻结 error channel 如下：incomplete spelling、alternate/escaped/qualified Field id、inner/outer 任一
length 的 `4097`/leading-zero/`0x10`/`4_096`、bare Bytes/Option/Array/Map 与 `Widget 4 4`
unknown/Named-like leaf 必须 exact `unsupported portable type`；missing/negative/identifier inner/outer
length、extra payload、五个 Array/Array/Field/id/length same-line seam 换行、三个 constructor（两层
Array、Field）的 escaped/qualified form、full Bytes/Option/Array/Map compounds 必须 parser-rejected。
若 GREEN empirical probe 与冻结 channel 不一致，必须在 GREEN 前以独立规格修正提交闭合，不得静默
改断言或扩大 positive。

本切片不实现 field arithmetic、array value operations、任意 recursive type grammar/legality、runtime
representation、ABI 或 target nested-Array-Field support。tests-only RED 仅限
`Tests/Language/ArrayTypes.lean`，最多 330 行新增、2 行移除；production 仅限
`Language/Syntax.lean` 一文件，最多 36 行新增、2 行移除，并在同一 GREEN 刷新 Lean package file-set。
focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可记录
existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type grammar 或
正式 D1 完成。

D1-PA-78 冻结的 pre-acceptance alpha 子集只为已有
`option(array(array(field,innerLength),outerLength))` carrier 开放 exact same-line spelling
`Option Array Array Field bn254_fr N M`。Field identifier 必须是 raw exact `bn254_fr`；`N`/`M`
分别表示 inner/outer Array length，并各自精确复用 canonical ASCII decimal `0..4096` discipline；
tag 固定 `16→18→18→2→N→M`，requirements 经 Option 与两层 Array 精确透传为单个
`fieldBn254`。本冻结只 supersede D1-PA-69 明示保留的 exact Field leaf boundary；PA65 的
`Option Array Field`、PA69 的 `Option Array Array PrimitiveAtom`、PA75 的
`Option Option Array Field` 与 PA77 的 `Array Array Field` 均保持不变。Bytes/Option/Array/Map/
Named leaf、第三层 Array 与任意 recursive grammar 继续 fail closed。

post-PA-77 初始 audit 曾分别按 production helper 行数与总验收面把
`Option Option Array Bytes N M` 和本候选排在第一；随后 bounded challenge 把完整测试/target 调用计入
同一分母。本候选的 `fieldBn254` 在 support resolver 前置拒绝，只需四 target 各一次
`checkSupport` 与 `materializeResult`，而 zero-requirement Bytes 候选还需 state/result/parameter 三类
target-owned Plan rejection fixtures，因此本候选是唯一最小 slice。该选择不是 checkpoint 自动递增或
type family 补齐。

frontend 只能新增 exact contextual named `optionArrayArrayFieldType` 与 struct-field 对应 parser；不得
放宽既有 `optionArrayArrayType`、`arrayArrayFieldType`、`optionArrayType` 或 `portableType`，不得引入
recursive parser。新增 decoder 必须完整复用 closed `decodeArrayArrayFieldValueTypeFromAtoms` 的 raw
`bn254_fr`、双 length lexical/bound policy与 inner/outer 顺序，随后只包一层 outer Option；专用 type
与 aggregate dispatch 必须先于 generic `optionArrayArrayType`/aggregate parser。不得新增 ctor/tag、
修改 Source/Semantic encoder、Typed 或 target；Lean command 与 ParserSession 必须得到同一 Source
tree/hash。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
`("full Field Option Array Array element", "Option Array Array Field bn254_fr 4 4")`
parser-negative 迁移为 positive，migration count 精确为一。当前没有既存 incomplete pin，因此 RED
必须新增 `Option Array Array Field 4 4` 的 exact unsupported control；该新增不是第二条 migration。
其他测试不得迁移。positive 覆盖 `(inner,outer)=(0,0)/(4,4)/(4096,1)`、所有 declaration
positions（含 event/error）与双入口 parity。Source/Semantic canonical tests 各固定三组 vectors；
ordinary candidate 必须在两侧分别与 `Array Array Field bn254_fr 4 4`、
`Option Array Field bn254_fr 4`、`Option Option Array Field bn254_fr 4`、
`Option Array Array UInt64 4 4` 做 canonical bytes/hash non-alias，并用手工 carrier controls 在
Source/Semantic 两侧固定 `8/4` 对 `0/4`（inner-only）、`8/4` 对 `8/0`（outer-only）与
`8/4` 对 `4/8`（swapped-length-order）non-alias；非 surface-positive control 不得借测试开放额外
spelling。requirements 必须恰为单个 `fieldBn254`；四个 Phase 1 target 的
`Targets.checkSupport` 与 `Targets.materializeResult` 必须都返回 exact
`.unsupportedRequirement .fieldBn254 actualTarget` 且 `actualTarget == target`，证明不能进入 Plan、
`OutputSet` 或产出 artifact。

冻结 error channel 如下：新增 incomplete spelling、alternate/escaped/qualified Field id、inner/outer
任一 length 的 `4097`/leading-zero/`0x10`/`4_096`、bare Bytes/Option/Array/Map 与
`Widget 4 4` unknown/Named-like leaf 必须 exact `unsupported portable type`；missing outer/both
lengths、negative/identifier inner/outer length、extra payload、六个 Option/Array/Array/Field/id/
inner-length same-line seam 换行、四个 constructor（Option、两层 Array、Field）的 escaped/qualified
form、full Bytes/Option/Array/Map compounds 必须 parser-rejected。若 GREEN empirical probe 与冻结
channel 不一致，必须在 GREEN 前以独立规格修正提交闭合，不得静默改断言或扩大 positive。

本切片不实现 field arithmetic、array/option value operations、none/some/unwrap、任意 recursive type
grammar/legality、runtime representation、ABI 或 target Option-nested-Array-Field support。tests-only
RED 仅限 `Tests/Language/OptionDeclarations.lean`，最多 330 行新增、2 行移除；production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package
file-set。focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可
记录 existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type
grammar 或正式 D1 完成。

D1-PA-79 冻结的 pre-acceptance alpha 子集只为已有
`option(option(array(bytes(innerLength),outerLength)))` carrier 开放 exact same-line spelling
`Option Option Array Bytes N M`。`N`/`M` 分别表示 Bytes 长度与 outer Array length，并各自精确复用
canonical ASCII decimal `0..4096` discipline；tag 固定 `16→16→18→17→N→M`，requirements 经两层 Option
与 Array 精确透传为空集。本冻结只 supersede D1-PA-64/PA-68 明示保留的 nested Option Array Bytes
fail-closed residual；PA64 的 `Option Option Array PrimitiveAtom`、PA68 的 `Option Array Bytes`、
PA74 的 triple Option Bytes 与 PA78 的 Option Array Array Field 均保持不变。Field/Option/Array/Map/
Named leaf、第三层 Option 与任意 recursive grammar 继续 fail closed。

post-PA-78 residual 在 PA77 challenge 之后把 dual-length Field reject 与 dual-length Bytes Plan 重新排序：
PA78 已关闭 Option Array Array Field；剩余候选 `Option Option Array Bytes N M` 是当前最小 dual-length
zero-requirement Plan-class residual——固定 Bytes leaf + dual length，decoder 复用 closed
`decodeOptionArrayBytesValueTypeFromAtoms` 后再包一层 Option，无需 Field-id 矩阵，但仍需
state/result/parameter 三类 Plan fixture。该选择不是 checkpoint 自动递增或 type family 补齐。

frontend 只能新增 exact contextual named `optionOptionArrayBytesType` 与 struct-field 对应 parser；不得
放宽既有 `optionOptionArrayType`、`optionArrayBytesType`、`optionOptionType` 或 `portableType`，不得引入
recursive parser。新增 decoder 必须完整复用 closed `decodeOptionArrayBytesValueTypeFromAtoms` 的
Bytes/dual-length lexical/bound policy 与 inner/outer 顺序，随后只包一层 outer Option（fail-closed
shape match）；专用 type 与 aggregate dispatch 必须先于 generic `optionOptionArrayType`/aggregate
parser。不得新增 ctor/tag、修改 Source/Semantic encoder、Typed 或 target；Lean command 与
ParserSession 必须得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
`("nested Bytes nested Array element", "Option Option Array Bytes 8 4")` parser-negative 迁移为
positive，migration count 精确为一。既有 incomplete bare
`("bare Bytes nested Option Array Field prefix", "Option Option Array Bytes 4")` 必须继续保留为 exact
unsupported，其他测试不得迁移。positive 覆盖 `(inner,outer)=(0,0)/(8,4)/(4096,1)`、所有 declaration
positions（含 event/error）与双入口 parity。Source/Semantic canonical tests 各固定三组 deliberately
UNBOUND golden vectors；ordinary candidate 必须在两侧分别与 `Option Option Array UInt64 4`、
`Option Array Bytes 8 4`、`Option Option Bytes 8`、`Array Bytes 8 4` 做 canonical bytes/hash
non-alias，并用手工 carrier controls 在 Source/Semantic 两侧固定 `8/4` 对 `0/4`（inner-only）、
`8/4` 对 `8/0`（outer-only）与 `8/4` 对 `4/8`（swapped-length-order）non-alias；非 surface-positive
control 不得借测试开放额外 spelling。requirements 必须为空；四个 Phase 1 target 的
`Targets.checkSupport` 必须全部 `.ok`；callable boundary 之外，state/result/parameter 三类 fixture 的
`Targets.materializeResult` 必须 exact `.planInvariant` 且 detail 分别包含 `is not UInt64` /
`does not return UInt64` / `is not UInt64`，证明不能进入 Plan/`OutputSet` 或产出 artifact。

冻结 error channel 经 GREEN 前 empirical probe 修正如下：incomplete bare spelling、inner/outer
任一 length 的 `4097`/leading-zero/`0x10`/`4_096`，以及仅缺 outer length 的
`Option Option Array Bytes 8` 必须 exact `unsupported portable type`；bare Field/Option/Array/Map 与
`Widget 8 4` unknown/Named-like dual-length leaf、missing both lengths、negative/identifier
inner/outer length、extra payload、
五个 outer-Option/middle-Option/Array/Bytes/inner-length 后的 same-line seam 换行、四个 constructor
（两层 Option、Array、Bytes）的 escaped/qualified form、full Field/Option/Array/Map compounds 必须
parser-rejected。该修正只校准既有负例的实际拒绝层，不迁移或扩大 positive。

本切片不实现 bytes/array/option value operations、none/some/unwrap、任意 recursive type grammar/
legality、runtime representation、ABI 或 target nested-Option-Array-Bytes support。tests-only RED 仅限
`Tests/Language/OptionDeclarations.lean`，最多 330 行新增、2 行移除；production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package
file-set。focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可
记录 existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type
grammar 或正式 D1 完成。

D1-PA-80 冻结的 pre-acceptance alpha 子集只为已有
`array(option(option(bytes(innerLength))),outerLength)` carrier 开放 exact same-line spelling
`Array Option Option Bytes N M`。`N`/`M` 分别表示 Bytes 长度与 outer Array length，并各自精确复用
canonical ASCII decimal `0..4096` discipline；tag 固定 `18→16→16→17→N→M`，requirements 经 Array
与两层 Option 精确透传为空集。本冻结只 supersede D1-PA-71 明示保留的 Array Option Option Bytes
fail-closed residual；PA71 的 PrimitiveAtom、PA72 的 Array Option Bytes、PA76 的 Field 与 PA79 的
Option Option Array Bytes positive 均保持不变。该选择补齐 `Array→Option→Option` 下 fixed portable
leaf 的 PrimitiveAtom/Field/Bytes 三元组；Array/Option/Map/Named compounds 与任意 recursive grammar
继续 fail closed。它来自 post-PA79 双路 bounded arbitration，不是 checkpoint 自动递增。

frontend 只能新增 exact contextual named `arrayOptionOptionBytesType` 与 struct-field 对应 parser；不得
放宽既有 `arrayOptionOptionType`、`arrayOptionOptionFieldType`、`arrayOptionBytesType` 或
`portableType`，不得引入 recursive parser。新增 decoder 必须完整复用 closed
`decodeArrayOptionBytesValueTypeFromAtoms` 的 Bytes/dual-length lexical/bound policy 与 inner/outer
顺序，只在既有 Array element 的 Option 外再包一层 Option（fail-closed shape match）；专用 type 与
aggregate dispatch 必须位于 `arrayOptionOptionFieldType` 之后、generic
`arrayOptionOptionType`/aggregate parser 之前。不得新增 ctor/tag、修改 Source/Semantic encoder、Typed
或 target；Lean command 与 ParserSession 必须得到同一 Source tree/hash。

tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有唯一
`("full Bytes Array Option Option element", "Array Option Option Bytes 8 4")` parser-negative 迁移为
positive，migration count 精确为一。既有 incomplete
`("bare Bytes Array Option Option element", "Array Option Option Bytes 4")` 必须继续 exact
unsupported，其他测试不得迁移。positive 覆盖 `(inner,outer)=(0,0)/(8,4)/(4096,1)`、所有 declaration
positions（含 event/error）与双入口 parity。Source/Semantic canonical tests 各固定三组 deliberately
UNBOUND golden vectors；ordinary candidate 必须在两侧分别与 `Array Option Bytes 8 4`、
`Array Option Option UInt64 4`、`Array Option Option Field bn254_fr 4`、`Option Option Bytes 8`、
`Array Bytes 8 4` 做 canonical bytes/hash non-alias，并用手工 carrier controls 固定 `8/4` 对 `0/4`
（inner-only）、`8/4` 对 `8/0`（outer-only）与 `8/4` 对 `4/8`（swapped-length-order）non-alias。
requirements 必须为空；四个 Phase 1 target 的 `Targets.checkSupport` 必须全部 `.ok`；
state/result/parameter 三类 fixture 的 `Targets.materializeResult` 必须 exact `.planInvariant` 且 detail
分别包含 `is not UInt64` / `does not return UInt64` / `is not UInt64`，证明不能进入 Plan/`OutputSet`
或产出 artifact。

冻结 error channel 如下：incomplete bare spelling、inner/outer 任一 length 的 `4097`/leading-zero/
`0x10`/`4_096`，以及仅缺 outer length 的 `Array Option Option Bytes 8` 必须 exact
`unsupported portable type`；bare Field/Option/Array/Map 与 `Widget 8 4` dual-length leaf、missing both
lengths、negative/identifier inner/outer length、extra payload、五个 same-line seams、Array/两层 Option/
Bytes constructors 的 escaped/qualified form、full Field/Option/Array/Map compounds 必须
parser-rejected。若 GREEN empirical probe 与冻结 channel 不一致，必须在 GREEN 前以独立规格修正
提交闭合，不得静默改断言或扩大 positive。

本切片不实现 Bytes/Array/Option value operations、none/some/unwrap、任意 recursive type grammar、
runtime representation、ABI 或 target Array-Option-Option-Bytes support。tests-only RED 仅限
`Tests/Language/ArrayTypes.lean`，最多 320 行新增、2 行移除；production 仅限
`Language/Syntax.lean` 一文件，最多 32 行新增、2 行移除，并在同一 GREEN 刷新 Lean package
file-set。focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后只可
记录 existing-carrier spelling；按冻结不重复完整 `just ci`，不得声明 runtime semantics、完整 type
grammar 或正式 D1 完成。

D1-PA-81 冻结的 pre-acceptance alpha 子集把当前 no-op `proof_forge_program` attribute 收紧为
persistent environment export registry。该选择来自 post-PA80 declaration residual audit 与
`TASK-D1-04` external-call carrier audit：前者已进入无界 wrapper 组合，后者需要 Source/Semantic wire
演进；因此本切片转向 `TASK-D1-05` 已有的独立 export seam，不是 checkpoint 自动递增。正式
`TASK-D1-05` 及 `TST-SRC-006/007` 仍为 pending。

environment entry 固定为 `ProgramExportV1{schema,declaration}`，其中 `schema` exact 为
`proof-forge.program-export.v1`，`declaration` 是 attributed constant 的 fully-qualified Lean `Name`；
extension 只持久化这两个字段，不持久化或复制 `Source.Program` payload。公开 query
`programExports : Environment → Except String (Array ProgramExportV1)` 必须合并 imported 与 local entries，
按 `declaration.toString` 的 valid-Unicode lexicographic order（等价于 UTF-8 byte order）唯一排序，并在
返回任何部分结果前以 `PF-EXPORT-001` 拒绝 unknown schema、重复 structural `Name` 或同名冲突。

`proof_forge_program` 只接受无参数、global、当前 module declaration；application time 固定在 type
checking 之后，并要求 declaration type exact 为 `ProofForgeV2.Source.Program`。现有 `program ... where`
elaborator 仍生成 `@[proof_forge_program] def ... : Source.Program`，不得新增第二套 raw-Syntax AST、改变
program identity/sourceHash，或让 import order 进入 export order。测试 helper 可调用与 query 相同的
closed normalization 验证 schema-mismatch/duplicate negatives；不得仅靠 set 静默去重。

tests-only RED 固定新增 Shared/A/B diamond fixture、A→B 与 B→A 两个 snapshot module 及单一
`Tests.Language.ProgramExports` suite：两种 import order 必须得到完全相同的三项 schema/FQN table，
diamond 中 Shared 只出现一次，未加 attribute 的 manual `Source.Program` alias 不得出现；wrong schema、
duplicate declaration 与 reordered raw entries 必须分别证明 fail-closed 或 canonical normalization。
RED 只允许这些 test fixture、`Tests.lean` 与 `lakefile.lean` 的单行注册，总新增不超过 240 行。

GREEN 只允许新增 `ProofForgeV2/Language/ProgramExport.lean`（最多 150 行）、在
`ProofForgeV2/Language/Syntax.lean` 增加 import 并删除旧 no-op attribute（最多 3 行新增、8 行移除），
以及刷新 `supply-chain/lean-package-files.v1.json`。focused `lake build
Tests.Language.ProgramExports`、aggregate test build/binary、`git diff --check`、单次 `just sbom` 与独立
review 全绿后才能收口；按冻结不重复完整 `just ci`。

本切片明确不实现 constant evaluation、跨 module payload identity duplicate 判定、NodeId/source-origin
export、`PF-EXPORT-002`、CLI/Loader `--program` selection、wire/JSON publication、target/materializer 或
contained frontend worker；不得据此宣称正式 D1、完整 `TST-SRC-006/007` 或可部署能力完成。

D1-PA-82 冻结的 pre-acceptance alpha 子集只关闭 PA81 schema/FQN registry 到 exported
`Source.Program` value 的安全重建缝隙。该选择来自两路 post-PA81 security audit，不是 checkpoint
自动递增：Lean 4.31 的 `Environment.evalConst`、`evalConstCheck` 与 `Meta.evalExpr` 都会编译或执行
constant-reachable IR，不能用于未 contained 的产品路径；本切片因此把上文笼统的“常量求值”收紧为
读取 `ConstantInfo.value` 后的 closed structural reconstruction，禁止执行 attributed declaration。
正式 `TASK-D1-05` 与 `TST-SRC-006/007` 仍为 pending。

新增模块 `ProofForgeV2.Language.ProgramPayload`。公开 API 固定为：

```lean
decodeQuotedProgramV1 : Lean.Expr → Except String ProofForgeV2.Source.Program
programPayload : Lean.Environment → Lean.Name → Except String ProofForgeV2.Source.Program
programPayloads : Lean.Environment →
  Except String (Array (ProgramExportV1 × ProofForgeV2.Source.Program))
```

`programPayload` 必须先取得 `programExports env` 的完整 normalized table，并要求 exact structural `Name`
存在；禁止把未 attributed declaration 当作候选。`programPayloads` 只遍历该 table，并在全部 row 成功后
一次返回；任一 row 失败不得返回 partial prefix。两者只接受 `ConstantInfo.defnInfo`、definition safety
为 safe、type exact 为 `ProofForgeV2.Source.Program`、没有 top-level `implemented_by`/extern 替代且
`Environment.hasUnsafe value = false` 的 declaration；opaque/axiom/theorem、unsafe、missing value、
type mismatch、constant alias 与最终呈现 non-direct value 的 partial alias 全部以 `PF-EXPORT-004` fail closed。
Lean 4.31 对非递归 direct-value `partial def` 不保留可由 `Environment` 或其 closed value `Expr` 观察的
source-modifier provenance；若其最终为 safe direct `Program.mk`，decoder 按结构与普通 safe def 等同处理。
不得为了区分该不可观察修饰符而执行 declaration；若未来必须保留 provenance，应由 registry schema
显式承载并另行冻结，不得回填本切片。

`decodeQuotedProgramV1` 是纯 `Expr → Except` decoder，不查文件、网络、环境变量或 plugin，不调用
`whnf`/simp/reduce、compiler、`evalConst`/`evalExpr`、`unsafe` API 或 `IO`。root 必须是 exact
`ProofForgeV2.Source.Program.mk` 的 14-field application。递归 payload 只接受当前 `quoteProgram` 产生的
exact constructor vocabulary：`ProofForgeV2.Source.*` constructors、string/Nat literals、
`List.toArray` 的 `List.nil`/`List.cons` spine、`Option.none/some`、Bool，以及 literal/length wrapper 中的
`UInt64.ofNat`、`UInt32.ofNat`、`OfNat.ofNat`/`Fin.instOfNat` 形状。type/proof implicit arguments只能在
这些 exact wrapper position 被忽略；任何其他 data-position constant、lambda/let/projection/free/meta
variable 或 wrapper/arity drift 均拒绝。UInt32/UInt64 与 `Fin 4097` 在构造 host value 前按 raw Nat literal
检查范围，禁止 wrap/truncate 或相信 proof term。

decoder 先用显式工作栈对 raw `Expr` 做最多 100000 nodes 的总量预检；Source Expr/Statement/ValueType
的逻辑递归深度最多 256，list spine 不计作业务递归深度。node/depth 恰等于上限可进入结构判定，超过
上限固定为 `PF-EXPORT-004: program payload structural bound exceeded`。`programExports env`
成功返回 normalized table 后，其他 payload 失败固定以前缀 `PF-EXPORT-004` 返回 `not registered`、
`declaration unavailable or unsafe` 或 `unsupported quoted Source.Program form`，不得抛出 raw Lean
exception；若上游 registry normalization 因 schema/identity 冲突失败，则保留 PA81 已冻结的
`PF-EXPORT-001`，不得误标为 payload failure。

tests-only RED 固定新增 single rich DSL payload fixture、alias/opaque/unsafe/implemented-by negative
fixtures、snapshot helper 与单一 `Tests.Language.ProgramPayloads` suite，并只修改 `Tests.lean`/
`lakefile.lean` 注册，总新增不超过 360 行。positive rich fixture 必须比较 reconstructed Program 的全部
BEq value、qualified name 与 sourceHash；rich 与 test-owned exact direct quoted control 联合覆盖完整
constructor family。当前 DSL 的 bare state read 产生 `Expr.variable`，所以 `Expr.state` 由 direct quoted
control 覆盖，禁止为了 fixture 改 grammar。negative 必须证明 unregistered、constant alias、opaque、unsafe、可观察的
partial alias、
`implemented_by` replacement 均不执行且以 `PF-EXPORT-004` 拒绝，valid+invalid table 不返回 partial。
test-owned synthetic raw Expr 另固定 100000/100001 node 与 256/257 logical-depth boundary channel。

GREEN 只允许新增 `ProofForgeV2/Language/ProgramPayload.lean`（最多 520 行）并刷新
`supply-chain/lean-package-files.v1.json`；不得修改 Syntax、ProgramExport registry、Core Source、Loader、
CLI、Typed/Semantic 或 target。focused suite、aggregate test build/binary、`git diff --check`、单次
`just sbom` 与 independent review 全绿后只能记录 development evidence；不得声明运行了用户代码、
identity-level duplicate 已闭合、正式 constant-evaluation sandbox、CLI selection 或 D1 完成。

本切片明确不实现 cross-row `qualifiedName`/sourceHash identity duplicate、NodeId/origin、
`PF-EXPORT-002/003` selection、CLI/Loader、wire publication、target/materializer、frontend containment 或
任意 Lean term evaluator。若 closed structural decoder 无法覆盖 `quoteProgram` 当前完整 constructor
surface，必须 blocked/split，禁止回退到 `evalConst`/`evalExpr`。

D1-PA-83 冻结的 pre-acceptance alpha 子集只关闭 PA82 成功重建全部 registry row 之后的
cross-row exported Source identity duplicate/split-brain 缝隙。该选择来自两路 post-PA82
residual/authority audit，因 PA81 只保证 declaration `Name` 唯一，PA82 明确未检查 payload
identity，且该缝隙可在不引入 CLI/Loader、wire、NodeId/origin、target 或 contained worker 的情况下
独立测试；不是 checkpoint 自动递增。正式 `TASK-D1-05` 与 `TST-SRC-006/007` 仍为
pending。

本切片不新增公开 API，只收紧既有 `programPayloads`。算法顺序固定为：

1. 先取得 PA81 normalized/sorted `programExports env`；registry schema/identity 失败保留
   `PF-EXPORT-001`。
2. 按该 row order 调用 PA82 closed structural decoder 重建**全部** payload；任一 row 失败保留
   `PF-EXPORT-004`，不执行 identity scan，不暴露 partial prefix。
3. 全部重建成功后，仍按 PA81 declaration FQN order 扫描 rows。唯一主键是 payload
   `Source.Program.qualifiedName` 的 exact `String` equality，不做 casefold、path normalization 或重排序。
   第一次出现记录 `qualifiedName → Source.Program.sourceHash`。
4. 后续 row 使用相同 qualifiedName 时，若 sourceHash 与已记录值相同，稳定失败为
   `PF-EXPORT-001: duplicate exported program identity`；若 sourceHash 不同，稳定失败为
   `PF-EXPORT-001: conflicting exported program identity`。首个 collision 决定诊断，不返回 partial table。
5. qualifiedName 不同的 rows 通过本检查。`sourceHash` 不是可独立碰撞的第二主键：当前
   `Source.Program.canonicalBytes` 已把 qualifiedName 放入 hash preimage，因此本切片不伪造
   different-qualifiedName/same-hash 负例，也不以不可构造的 SHA-256 碰撞作为验收前置。

tests-only RED 固定新增 isolated ProgramIdentity fixtures/snapshot 与单一
`Tests.Language.ProgramIdentities` suite，并只修改 `Tests.lean`/`lakefile.lean` 注册，总新增不超过
220 行。positive 用两个 distinct qualifiedName、相同业务 shape 的 attributed direct
`Program.mk` 值固定 table/order 与不同 hash；duplicate fixture 用不同 declaration FQN 承载同
qualifiedName+同 payload；split-brain fixture 承载同 qualifiedName+不同 payload/hash。另一 isolated
priority fixture 同时含 identity collision 与后续 PA82-invalid payload，必须稳定返回 `PF-EXPORT-004`，证明
全量 decode 先于 identity scan。

GREEN 只允许修改 `ProofForgeV2/Language/ProgramPayload.lean`，不新增 public API，文件总行数不超过
480，并刷新 `supply-chain/lean-package-files.v1.json`。禁止修改 ProgramExport registry、Core Source、
Syntax、Loader、CLI、Typed/Semantic 或 target。focused suite、aggregate test build/binary、
`git diff --check`、单次 `just sbom` 与 independent review 全绿后只能记录 development evidence，按冻结
不重复完整 `just ci`。

本切片明确不实现 single-row `ProgramExportV1.declaration.toString` 与 payload qualifiedName 绑定、
independent sourceHash collision oracle、NodeId/origin、`PF-EXPORT-002/003` selection、CLI/Loader、wire
publication、target/materializer、frontend containment 或正式 `TST-SRC-006/007` closure。这些新缺口
只能经新的 bounded audit/freeze 处理，不得回填本切片。

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

D1-PA-49 冻结的 pre-acceptance alpha value-less return 子集只补齐 EBNF
`"return" Expr?` 中缺失的无 Expr 分支，Source carrier 固定为 nullary
`Source.Statement.returnUnit`。它只解除 `EV-20260718-0002` 中“无无值 return”的 Source-carrier
延期；Unit fallthrough、return-path/termination、result-type legality、initializer/entry/fn return rules、
Typed/Semantic return 与 target materialization 仍明确留给 D2/后续，不得据此改写旧 evidence 的其他限制。
既有 `Source.Statement.returnValue(value)`、Statement tag `1`、syntax、goldens 与 Typed success path
全部保持不变；禁止改为 `Option Expr` 或重编号既有 tag。

parser 使用 named `returnValueStmt` 的 `leading_parser` + `withPosition`，value-bearing 分支在 `return`
后必须满足 `checkLineEq` 或 `checkColGt` 才进入 `pfExpr`；随后 bare `syntax "return" : pfStmt` 作为
fallback。即 `return 1`/`return true` 与严格增加缩进的多行 `return` newline `  1` 物化为
`returnValue`，同 statement column 的 newline 开始下一条 statement，bare 物化为 `returnUnit`。
这项 parser correction 由 tests-only RED 后的首次 GREEN 聚焦构建触发：原冻结的 unrestricted
跨行规则会把下一 item 的 contextual `fn` 或下一条 `x := 1` 的 identifier 贪婪识别为 Expr，无法同时
满足 bare-at-block-end 与 bare-followed-statement；禁止用 fixture 重排或枚举未来 statement introducer
规避该歧义。原冻结的同缩进 `return` newline `1` retention 因而改为 parser rejection，严格缩进版本
保留明确的 multiline continuation；现有 suites 无 migration，只纠正本切片新 RED 的一条预期。

Source canonical encoder 使用 append-only Statement tag `6` 且无 payload；tag `0..5`/既有 goldens
不变。tests-only RED 为 zero migration，只新增/注册 `Tests.Language.ValueLessReturns`，固定 Lean command/
ParserSession 在 initializer、entry、view、fn 以及 explicit/omitted Unit 与 non-Unit declaration 上的
Source parity，并固定 returnUnit 对 returnValue 及其他 statement kind 的 tag non-alias。

`return()`、bare 后括号/逗号/额外 payload、unescaped keyword assignment 等 malformed shapes 必须 fail
closed；escaped `«return» := 1` 保持 assignment。`Typed.check` 必须在 result type、Unit materialization、
initializer legality、return-path/statement-after-return 分析前逐字 fail closed 为
`value-less return is not yet supported by typed checking`；尤其 omitted-result fn 中的 bare return 仍必须
得到同一 diagnostic，不得借 Unit 自动接受。首次 aggregate test-binary 验证确认既有 generic fn gate
先于 statement checker，因此该 gate 只可增加 returnUnit exact-priority 检查，普通 fn 仍保持原 fail-closed。
本切片不得实现 fallthrough、implicit Unit value、return-path、
type/effect、Semantic/requirement、ABI/runtime 或 target behavior；production 仅限 Source/Syntax/Typed
3 文件、最多 12 行新增/2 行移除。GREEN、focused/aggregate/test binary 与两份独立审查全绿后，在 clean committed
tree 运行一次 statement checkpoint `just ci`；只可记录 value-less return Source carrier，不得宣称
return semantics、完整 statement grammar 或正式 D1 完成。

D1-PA-50 冻结的 pre-acceptance alpha emit statement 子集一次实现完整 EBNF
`"emit" Ident "(" ExprList? ")"` Source surface，carrier 固定为
`Source.Statement.emitStmt(eventName : String, args : Array Expr)`。parentheses 必须存在；`emit Tick()`
物化 empty args，`emit Tick` 不得成为 optional-paren fallback。event declarations 已有 Source carrier，
但 event lookup、payload arity/type、view legality、effect 与 target materialization 仍属于 D2/后续。

parser 只新增 `syntax "emit " ident "(" pfExpr,* ")" : pfStmt`；decoder 必须先验证 event name
恰好一个 `Name` component，再应用既有 portable identifier policy，最后才按源顺序解码完整 ExprList。
Source canonical encoder 使用 append-only Statement tag `7`，随后编码 eventName string 与
length-prefixed argument expression array；tag `0..6` 与既有 goldens 不变。tests-only RED 为 zero
migration，只新增/注册 `Tests.Language.EmitStatements`，固定 Lean command/ParserSession 在 initializer、
entry、view、fn 上的 Source parity，以及 event name、argument value/count/order/nesting 与 statement kind
的 canonical non-alias。

missing name/parenthesis、bare name、leading/trailing/double comma、adjacent argument、extra payload 与
unescaped keyword assignment 必须停在 parser boundary；escaped `«emit» := 1` 保持 assignment。
qualified event name 必须在 argument decode 前逐字拒绝 `emit event name must be unqualified`，reserved
name 继续走既有 portable policy。`Typed.checkStatement` 必须在 event-table lookup、argument checking、
view/effect analysis 前逐字 fail closed 为 `emit statements are not yet supported by typed checking`；
含 event declarations 的完整 surface 仍可被既有 generic event gate 拒绝，不得伪称 Typed emit support。
本切片不得实现 event resolution、payload legality、emission/effect、Semantic/requirement、ABI/runtime 或
target behavior；production 仅限 Source/Syntax/Typed 3 文件、最多 16 行新增且不移除既有 production。
GREEN、focused/aggregate/test binary 与两份独立审查全绿后只可记录完整 emit statement Source carrier；
PA49 已运行 statement checkpoint，本切片不重复全量 `just ci`，且不得宣称完整 event semantics、
statement grammar 或正式 D1 完成。

D1-PA-51 冻结的 pre-acceptance alpha assert-error 子集补齐 EBNF
`"assert" Expr ("else" Ident)?` 的 optional-error Source 分支。既有 bare
`Source.Statement.assertStmt(condition)` 与 Statement tag `4`、surface、canonical bytes/hash 全部不变；
新增 append-only syntax-variant carrier
`Source.Statement.assertErrorStmt(condition : Expr, errorName : String)`。Source 层保留 bare/error 两个
surface variant，后续 target-neutral normalization 才统一映射到 Semantic Assert 的 optional ErrorId；
不得为追求单一 Source constructor 修改已接受的 bare carrier 或重算旧 golden。

parser 在既有 bare rule 前新增 longer rule
`syntax "assert " pfExpr " else " ident : pfStmt`，必须完整消费 `else Ident`，禁止 bare rule 先吞
condition 后遗留 payload。decoder 先要求 error name 恰好一个 `Name` component，再应用既有 portable
identifier policy，最后解码 condition；qualified/reserved error name 的 exact diagnostic 优先于 condition
decode。Source canonical encoder 使用 append-only Statement tag `8`，随后按 semantic field order 编码
condition expression 和 errorName string；tag `0..7` 与全部既有 goldens 不变。quotation 必须结构化保留
两字段，不得退化为文本。

tests-only RED 只扩展 `Tests.Language.AssertStatements`，并且必须且只能移除其中
`assert true else Failure` 的一条 deferred negative；不新增测试模块或迁移其他 suite。positive 固定
initializer、entry、view、fn 的 Lean command/ParserSession parity，literal/Bool/variable/operator/group
condition、普通/等价 escaped error name，以及 condition/name/kind 的 canonical binding。missing name、
qualified/reserved name、call-like error payload、duplicate `else`、extra payload 与 block-like 形态必须
fail closed；bare assert、`assert := 1` rejection、escaped assignment 与 `assertValue` assignment 保持。
`Typed.checkStatement` 必须在 condition checking、error-table lookup、Bool/effect analysis前逐字 fail closed
为既有 `assert statements are not yet supported by typed checking`；含 error declaration 的 control 仍由
既有 generic error-table diagnostic 拒绝。本切片不得实现 error resolution、condition Bool typing、
assertion failure/revert、Semantic/requirement/effect、ABI/runtime 或 target behavior；production 仅限
Source/Syntax/Typed 3 文件、最多 14 行新增且不移除既有 production。focused/aggregate/test binary 与
两份独立审查全绿后只可记录完整 assert optional-error Source carrier；PA49 已运行 statement checkpoint，
本切片不重复 `just ci`，不得宣称完整 assert semantics、statement grammar 或正式 D1 完成。

D1-PA-52 冻结的 pre-acceptance alpha conditional 子集一次实现 EBNF
`"if" Expr "then" Block ("else" Block)?` 的 Source surface。carrier 固定为
`Source.Statement.ifStmt(condition : Expr, thenBody : Array Statement,
elseBody : Option (Array Statement))`；作者不写 target/kind，frontend 不根据 target 重写条件或分支。
parser 只新增一条 optional-else surface。tests-only RED 的首次 GREEN 证明 `ppLine`
只是 formatter hint，不会拒绝 same-line branch；因此实现必须使用唯一的
`@[pfStmt_parser default+1] ifStmt` parser，以 `withPosition` + `checkLinebreakBefore` +
`checkColGt` 固定 branch 换行/深缩进，以 `checkColEq` 固定 `else` 回到 owning `if`
列，then/else 内部均由 `many1Indent(pfStmt)` 承载。`thenBody` 与存在的
`elseBody` 均至少一条 statement；结构化 layout 决定 dangling-else 归属，不得另增
same-line/textual fallback。

decoder 顺序固定为 condition→then statements→optional else statements，并且递归 decoder 只能为
承载 nested Source block 改为 `partial`。上述位置感知 custom parser 产生固定五段 syntax
node；decoder 必须 fail-closed 检查 exact `ifStmt` kind/五段 shape 与 optional-else group，不得
将 malformed node 落入普通 statement。quotation 必须递归构造 statement arrays 与 exact
`Option.none`/`Option.some`，不得退化为文本。Source canonical encoder 使用 append-only Statement
tag `9`，随后依次编码 condition expression、length-prefixed then-body statement array、else marker
byte `0`/`1`；marker `1` 后再编码 length-prefixed else-body statement array。递归 encoder 只能为
nested block 改为 `partial`；tag `0..8` 与全部旧 golden 不变。

tests-only RED 为 zero migration，只新增/注册 `Tests.Language.IfStatements`。positive 固定
initializer、entry、view、fn 中 if-then/if-then-else 的 Lean command/ParserSession Source parity，
literal/Bool/variable/operator/group condition，then/else statement count/order 与 nested if 结构。canonical
golden/non-alias 必须绑定 condition value/tree、then-body count/order、else marker、else-body content、
nested statement kind 与 tag `9`；旧 statement tags/goldens 不得重算。missing condition/`then`、
same-line 或 empty then-body、dangling/wrong-column/duplicate `else`、empty else-body、extra payload 必须
fail closed；unescaped `then := 1`/`else := 1` 必须拒绝，escaped `«then» := 1`/
`«else» := 1` 保持 assignment。

`Typed.checkStatement` 必须在 condition checking、branch checking、return/effect/path analysis 前逐字
fail closed 为 `if statements are not yet supported by typed checking`；旧 statement controls 保持 exact outcome。
本切片不实现 Bool typing、branch join、return-path/effect、Semantic/requirement、target Plan/IR、runtime 或
materialization；production 仅限 Source/Syntax/Typed 3 文件，最多 38 行新增与 3 行移除。
两行移除用于把既有 recursive encoder/decoder declaration 替换为 `partial`，第三行仅用于把
原 generic decoder catch-all 替换为 exact `ifStmt` kind/shape 验证后的 fail-closed catch-all。focused/aggregate/test
binary 与 independent review 全绿后只可记录 conditional Source carrier；本切片不运行
`just ci`，不得宣称 Typed conditional semantics、完整 statement grammar 或正式 D1 完成。

D1-PA-53 冻结的 pre-acceptance alpha bounded-for 子集一次实现既有 EBNF
`"for" Ident "in" Expr "..<" Expr "bounded" Nat "do" Block` 的 Source surface。carrier 固定为
`Source.IterationBound := Fin 4097` 与
`Source.Statement.forStmt(iterator : String, start : Expr, stopExclusive : Expr,
maxIterations : IterationBound, body : Array Statement)`；它只记录作者源码，不执行迭代、求值或 target
特化。parser 只新增一条 position-sensitive `forStmt` production：header 的 `for`、iterator、`in`、
start、exact `..<` token、stopExclusive、`bounded`、bound 与 `do` 必须全部同一行；`do` 后必须真实
换行，body item 必须更深缩进，并由 `many1Indent(pfStmt)` 保证 non-empty。`0 ..< 10` 与
`0..<10` 使用同一个 exact range token 并形成同一 Source tree；不得接受内部拆开的 `.. <`、闭区间或
textual/same-line fallback。

`maxIterations` 只接受 exact ASCII decimal spelling `0..4096`；除单独 `0` 外禁止 leading zero，
并拒绝 signed、hex、underscore、空或超界 spelling。decoder 必须复用 `Bytes N` 已有的 bounded
decimal lexical discipline，不得调用 unchecked host literal/`getNat` 转换，而要先验证长度/leading-zero，
再逐字符验证 digit、手工累积并即时检查上界；不得另建宽松 numeral 路径。custom parser node 必须按 iterator→start→stopExclusive→maxIterations→body 顺序 exact
kind/token/null-group/non-empty shape 验证，quotation 必须递归保留 body array，不得退化为文本。

Source canonical encoder 使用 append-only Statement tag `10`，随后依次编码 iterator string、start
expression、stopExclusive expression、`appendNat maxIterations.val` 与 length-prefixed body statement array；
tag `0..9` 与全部旧 golden 不变。tests-only RED 为 zero migration，只新增/注册
`Tests.Language.ForStatements`。positive 固定 initializer、entry、view、fn 的 Lean
command/ParserSession parity，bound `0`/`4096`、spaced/compact exact range token、literal/variable/operator/
group endpoints、multi-statement body 与 nested if/for。canonical golden/non-alias 必须绑定 iterator、两个 endpoint value/tree、bound、
body count/order/nesting、tag `10`，RED 中 golden 保持显式未绑定，后续独立 probe 单独提交绑定。

missing iterator/`in`/`..<`/stop/`bounded`/bound/`do`、header split、same-line/same-column/empty body、
内部拆开的 `.. <`、bound `4097`/`01`/`0x10`/signed/underscore、extra payload 必须 fail closed；
unescaped `for := 1`/`in := 1`/`bounded := 1` 必须拒绝，escaped `«for»`/`«in»`/`«bounded»`
保持 assignment。`Typed.checkStatement` 必须在 iterator lookup、endpoint checking、bound/body/return/effect
analysis 前逐字 fail closed 为 `for statements are not yet supported by typed checking`；旧 statement controls
保持 exact outcome。本切片不实现 iterator scope/type、range evaluation、bounded-loop proof、induction、
return/effect/path、Semantic/requirement、target Plan/IR、runtime 或 materialization；production 仅限
Source/Syntax/Typed 3 文件、最多 34 行新增且不移除既有 production，并在同一 GREEN 刷新 Lean package
file-set。focused/aggregate/test binary、independent review 与 PA50–PA53 committed-tree batch `just ci` 全绿后
只可记录 bounded-for Source carrier；不得宣称 loop semantics、完整 statement grammar 或正式 D1 完成。

RED 后的 canonical security probe 证明裸 `Nat` 不是合法 carrier：`appendNat` 经 `UInt64.ofNat` 会让
`0` 与 `2^64` 产生相同 bytes/sourceHash。上述 `IterationBound` 收紧是冻结范围内的安全修正：surface
仍只接受原定 `0..4096` decimal，合法值的 bytes/goldens 不变，但 public Source AST 中越界 bound 变为
不可表示；不得以“parser 不会产生”为理由保留 canonical alias。

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
