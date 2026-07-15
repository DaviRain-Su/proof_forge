---
id: RPT-003
title: Lean program DSL 语义研究
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Lean `program` DSL 语义研究

状态：`draft`
研究日期：2026-07-15

## 核心问题

怎样只让用户写一份业务代码，同时避免重新发明“合约 DSL、circuit DSL、guest DSL”三套语言？

## 结论摘要

唯一顶层形式是：

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

源码不声明执行类别。`--target` 选择物化方式；编译器从源码推导 `ProgramRequirements` 并检查目标是否能等价实现。Lean 官方语法系统提供自定义 category、source span、command elaborator 和 hygiene 基础，因此无需把业务 DSL 伪装成不受约束的普通 Lean term（`CLM-LANG-001`）。

## 建议的语法边界

首版声明：`state`、`struct`、`enum`、`const`、`event`、`error`、`init`、`entry`、`view`、`invariant`、`requires`。

首版语句：`let`、赋值、`if/else`、`match`、有静态上界的 `for`、`assert`、`revert`、`emit`、`return`、同步 `call`、异步 `schedule`。

DSL 使用专属 `programItem`、`programExpr`、`programType` grammar。除明确的 theorem/invariant reference 位置外，不接受任意 Lean term，以免不可控元编程绕过 effect、termination 和 determinism 检查。

## 语义模型

```text
step : State × Invocation × ExternalResponses → Outcome

Outcome =
  returned(postState, returnValue, orderedEffects)
  | reverted(error, unchangedState)
  | trapped(fault, unchangedState)
```

这里的 `State` 是逻辑状态，不预设 storage/account/KV/record；`ExternalResponses` 是显式、可重放输入，不允许编译器从宿主环境暗取不确定值。

## Requirements 不是源码类别

推导维度至少包括：

- `value.*`：整数宽度、overflow、Field、Bytes、Principal。
- `control.*`：循环上界、递归、动态分配。
- `state.*`：Cell/Map/Vector、原子提交、升级连续性。
- `effect.*`：event、同步调用、异步工作流、协议调用。
- `context.*`：caller、authorizers、time、randomness。
- `disclosure.*`：`verifierVisible | proverWitness | commitmentOnly`。
- `authority.*`：谁能授权。
- `stateCustody.*`：contract/user/account/record ownership。
- `failure.*`：revert、trap、external failure、commit boundary。
- `extension.*`：namespace、name、exactSemVer、semanticsDigest。

披露、授权、状态托管必须相互独立。例如 `private` 只描述信息披露，不表示只有 owner 可以写，也不表示数据存放在用户 record。

## 名称、导出与诊断

每个 program 解码为带稳定完全限定名的 `Source.Program`，直接 Lean 编译入口可通过专用
persistent attribute 注册；CLI 的 non-elaborating loader 则直接收集同一 decoder 的结果。
一个源文件允许多个 program；CLI 歧义时要求 `--program Fully.Qualified.Name`。SourceHash
排除绝对路径、注释和展示 span，但诊断保留 node id/span/origin。

诊断必须稳定携带 `code`、`phase`、`span`、`program`、`entry`、`requirement`、`extension`、`target` 和 `suggestion`。至少覆盖 parse、name、type、effect、bound、visibility、extension、target support 和 export ambiguity。

## 冲突与取舍

- 仅靠 target 区分执行形态，不等于业务源码可以省略隐私。公开输入与 witness 的区别会改变可观察语义，必须显式写在参数/状态上。
- “同一源码都能编译”是条件承诺：只有目标支持全部 requirements 时成立。
- target extension 仍是同一 DSL，但使用 extension 会缩小可用 target 集合；这不是多 DSL。

## 验收影响

- Counter 同源编译到 EVM、Solana、NEAR、Noir。
- PrivateSum4 验证披露语义，而非顶层类别。
- 同一语义哈希在路径变化、注释变化后保持稳定。
- 任意 Lean escape、无界循环、隐式随机数和未声明 external effect 必须失败。

## 限制

本报告定义语言方向，不替代 normative language/type/effect specs。custom command、persistent attribute 和跨模块导出仍需 Lean 4.31 的最小原型及编译测试确认。
