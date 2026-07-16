---
id: SPEC-TYPE-001
title: 类型、Effect 与信息披露规格
status: proposed
owner: semantics
updated: 2026-07-16
normative: true
---

# 类型、Effect 与信息披露规格

## 类型

整数宽度固定 `{8,16,32,64,128,256}`，two's complement signed，默认运算 checked；
overflow、underflow、除零、非法 shift 产生 semantic revert。不同宽度无隐式转换，
`cast<T>(x)` 仅在运行值可表示时成功。`Field id` 是 registry 中 exact modulus identity，
运算按该素数域；不同 field 不可混合。

`Principal` 是不透明逻辑身份，不假定 20/32 bytes；target Plan 定义编码，不能无损编码
则拒绝。`Bytes N` 固定长度；`Array T N` 固定长度；`Map K V` 是有限映射，K 仅允许
Bool、整数、Principal、Bytes 和由这些组成的 tuple/struct，缺失 lookup 返回 `Option V`。
Struct/enum 递归必须经 `Option` 且 Phase 1 禁止运行时递归值。

## 类型规则

- arithmetic operands/result 同类型；comparison 返回 Bool。
- logical operators 只接受 Bool；shift rhs 为 UInt32，必须小于 lhs width。
- state/place assignment 要求 exact type；没有 implicit truncation。
- callable 参数和返回必须可 canonical serialize；pure `fn` 可使用内部 struct/enum。
- Map iteration 不提供；Array loop 必须有静态 bound。
- const expression 不读 state/context，不调用函数，必须在 elaboration 时求值。

错误：`PF-TYPE-001` mismatch，`PF-TYPE-002` unknown/ambiguous name，
`PF-TYPE-003` invalid cast，`PF-TYPE-004` non-serializable interface。

### Alpha 名称索引契约

当前 `Typed.check` 的 alpha 子集仍以 `CompileResult`/`CompileError.invalidProgram` 报错；
本切片不提前宣称完整 `PF-TYPE-*` Diagnostic v1 已实现。accepted-width
`Source.Program` 必须按以下方式完成名称解析：

- state 在 `Typed.check` 中按源码顺序只构建一次 `HashMap String StateDecl`；initializer
  与所有 entry 共用该索引。entry 名称按源码顺序用 `HashSet String` 检查重复。
- 每个 initializer/entry 按参数声明顺序构建一次 `HashMap String Param`；参数 ID、state ID、
  typed state/parameter/entry 数组仍严格来自声明顺序。HashMap/HashSet 只是临时环境，禁止
  通过迭代哈希容器生成可观察输出、序列化或 semantic hash。
- `.variable name` 先查当前 callable 参数，再查 state；同名参数遮蔽隐式 state 引用。
  `.state name` 与 assignment target 只查 state。非空 synchronous callee 在当前 alpha
  仍不做 entry resolution。
- 重复检查和 lookup 使用 `Std.HashMap`/`Std.HashSet` 的预期/摊销常数时间操作，因此对
  declaration/reference 数量和名称字节总量为预期/摊销线性；不得把该性质表述为抵抗
  adversarial hash collision 的严格最坏情况线性保证。

错误选择顺序也是可观察契约：空 qualified identity → 空 display name → 第一个重复 state
→ 第一个重复 entry → 零 entry → initializer 参数重复/initializer body → 各 entry 按声明
顺序的参数重复/body。body 内保持 left-to-right；view assignment 在 target/RHS lookup 前失败，
mutate assignment 先查 target 再查 RHS，`checkedAdd` 先检查 lhs 再检查 rhs。

## Effect

```text
Effect ::= state.read | state.write | event.emit | external.call.sync
         | workflow.schedule | context.read.<name> | disclosure.commit
         | failure.revert | extension.<id>
```

effect 从表达式和 statement 自底向上取集合；call graph 求最小不动点，禁止递归环。
`fn` 只允许空 effect；`view` 只允许 `state.read/context.read/failure.revert`；`init/entry`
允许除未声明 extension 外的 effect。调用方 effect 包含被调 pure helper effect。

错误：`PF-EFFECT-001` callable 不允许 effect；`PF-EFFECT-002` effect 未声明支持；
`PF-BOUND-001` 无法证明终止/资源 bound。

## Disclosure

label 为 `public | commitment | private`。默认参数、state、return 为 public；显式 private
值只可流入 private sink；`commit(x)` 是唯一从 private 到 commitment 的降级操作并推导
`disclosure.commitment` requirement；没有隐式 declassification。public 值可用于 private
计算。分支条件、index、错误 variant、event、call data 和返回值都参与隐式流检查：
private condition 下对 public state/effect 的可观察差异为 `PF-VIS-001`。

chain artifacts 的 calldata/accounts/KV 均按 public 处理；因此 private requirement 在
EVM/Solana/NEAR Phase 1 必须拒绝。Noir Plan 把 private 参数映射 witness，把 public/
commitment 参数映射 public inputs/commitment checks。

## Authority 与 State Custody

authority 从 `context.caller/authorizers` 的读取及 guard 数据流推导；它不是 visibility。
state custody 从 logical state 的 owner key、program global state 或 extension annotation
推导；它也不是 authority。Requirement 分别使用 `authority.*`、`stateCustody.*`。

## 终止与资源

只允许无递归 call graph 和显式 `for ... bounded N`。编译器证明实际迭代次数不超过 N；
否则运行时 revert。每个 callable 的静态 upper bound 是 statement/effect/memory size 的
结构递推；超过 profile limit 在 resolution 阶段 `PF-REQ-PRECONDITION`。

## 边界与验收

覆盖每个整数 min/max、overflow/underflow、除零、shift 0/width-1/width、合法/非法 cast、
不同 Field、Bytes/Array 0/4096、Map missing key、enum exhaustiveness、recursive type、
view 间接写 state、private 显式/隐式流、private error/log/index、commitment、authority
与 custody 混淆、call graph cycle、bound 0/max/over-limit。验收关联 `FR-003/012`、
`TST-TYPE-*`、`TST-EFFECT-*`、`TST-BOUND-*`、`TST-VIS-*`。
