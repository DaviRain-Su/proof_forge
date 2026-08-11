# Few-shot 02 — 修复环实录（D1 真实诊断）

> 这是 golden 模板定稿过程中**真实发生**的两轮门禁拒绝与修复，
> 直接可作为 Agent 修复环的参考样例。诊断逐字保留。

## Round 1 — Bool 参数被拒

**坏源片段**（初版 golden）：

```lean
entry setAllow(who : Principal, ok : Bool) : Bool do
```

**门禁诊断**（`check`，exit 非零）：

```text
PF-SRC-INVALID: S1 parameter 'ok' requires anonymous UInt/Int/Field/Principal/String,
named Struct/Enum, or Array/Map/Bytes/Option
```

**修复**：参数改 `ok : UInt64`，加 `assert ok <= 1`，Map 写 0/1。→ `check` 绿。

## Round 2 — Map Bool 值在 EVM Plan 被拒

**坏源片段**（check 已绿，build 才炸）：

```lean
state allowlist : Map Principal Bool
```

**门禁诊断**（`build --target evm`，exit 非零）：

```text
PF-PLAN-INVARIANT: invalid evm plan: unsupported EVM semantic shape:
Map index value must be UInt64
```

注意：报错文案写的是 "Map index value"，实际卡的是 **值类型**
（`Map Principal UInt64` 的 vault 在同版本能 build；`Map UInt64 UInt64` 的 MapMini 也能）。
**修复**：`allowlist : Map Principal UInt64`，读取处 `assert flag == 1`。→ build 绿。

## Round 0（来自调研 handoff 的已知坑，预防性写进禁止清单）

| 坑 | 症状 |
|---|---|
| 裸 `error X`（无括号） | PF-INTERNAL |
| event 字段用 Principal | S1 拒绝；仅 UInt/Int/String |
| 部署源里写 invariant/proof | EVM build `PF-PLAN-INVARIANT` fail closed |
| `-o` 传仓库相对路径 | 输出嵌套进 `<root>/<repo-path>`；用 `-o out-evm`（相对 root） |
| 输出目录已存在 | `PF-OUTPUT-COLLISION`；先删再建 |

## 教训（给 Agent 的元规则）

1. `check` 绿 ≠ `build` 绿：target Plan 还有一层 capability 门。**两轮都要跑**（gate.sh 已串好）。
2. 报错文案可能误导（Round 2）；用「同形态已知好使的对照例」定位真实原因。
3. 修 4 轮仍不过 → 回退 golden 全量，只改标识符和数值。
