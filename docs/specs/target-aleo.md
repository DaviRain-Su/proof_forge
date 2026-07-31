---
id: SPEC-TARGET-ALEO-001
title: Aleo 目标规格（Leo 4.0.2 capability-gated slice）
status: proposed
owner: targets
updated: 2026-07-31
normative: true
---

# Aleo 目标规格（SPEC-TARGET-ALEO-001）

## 1. 范围

`proof-forge-next build --target aleo` 消费 retained `SemanticProgramV1`
（sole NormalizeV1 生产者），经 capability（`ResolvedEngineeringBuildV1`）进入
target-owned Plan/IR，发射 **Leo 4.0.2 source**。与黑客松 V1-direct 平行路径
无关。成熟度：**source-only**（无 digest-pinned `leo` 工具，零工具 finalization，
同 Noir 先例）。

## 2. 支持表面

| 类别 | 支持 |
|---|---|
| 状态 | public UInt64，每字段一个 `mapping <pf_state_N>: u8 => u64`（key `0u8`） |
| init | `fn initialize(...) -> Final` + one-shot `initialized` guard mapping |
| entry | state-touching → `fn ... -> Final { return final { ... } }`；纯计算 → 普通 `fn -> T` |
| view | bare state-read（无参）→ 离链 `leo query` 描述符；纯计算 → 普通 fn |
| 表达式 | UInt64/Bool 字面量、place、checked add/sub/mul（Leo 原生 halt-on-overflow）、div/mod（显式非零 assert）、六比较、bitwise、严格 logical（两侧求值）、shift（显式 `count < 64` assert）、`~`/`!`、pureCall |
| 语句 | let（不可变）、assign→mapping set、assert、if/else、switch 链、bounded for、bare revert/trap → `assert(false)` |
| fn | pureFn → Leo `fn`（无 mapping 访问；UInt64/Bool 参数与结果） |

## 3. Fail-closed（诚实拒绝）

| 形状 | 原因 |
|---|---|
| `emit` | Leo 4.0.2 无链上事件日志 |
| 带参 `revert` | error payload 无法表示 |
| computed state-reading view | 无链上或查询物化 |
| externalCall / schedule | 无地址承载类型 / 无 workflow 模型（resolver 行已排除对应 requirements） |
| invariant / aggregates / Int/Field/Principal | 共享 Normalize 包络之外 |

## 4. Leo 4.0.2 编码

- state-touching：`fn <name>(public p0: u64, ...) -> Final { return final { ... } }`
- dropped 返回值：非 Unit entry 且 body 触碰 mapping → `resultDropped`（Plan
  显式元数据）；每个 return 表达式仍在 final block 内求值
  （`let pf_return: T = ...;`）以保留失败语义；值经交易后 `leo query` 观察
- 映射读写：`<mapping>.get_or_use(0u8, 0u64)` / `<mapping>.set(0u8, v)`
- bounded for：`let pf_start = s; let pf_end = e; if (pf_start < pf_end) {
  assert((pf_end - pf_start) <= N); } for pf_c in 0u64..Nu64 { if (pf_c <
  (pf_end - pf_start)) { let pf_i = pf_start + pf_c; <body> } }` ——
  boundExceeded 在 body 前 halt（可观察等价于参考机的 N 次 body 后 revert）
- 字面量：`42u64` / `true` / `false`；let 需显式类型标注

## 5. 解析器/资源边界

- program id：小写 ASCII + 数字 + 下划线（artifact 名小写化）
- 标识符保留字集合（Leo 关键字）→ fail closed
- 表达式深度 ≤ 256、函数 ≤ 256、参数 ≤ 64、语句 ≤ 4096（Plan 校验）

## 6. 成熟度声明

生成 Leo source 未经 `leo build`/`execute`/proof/deploy 验证；devnet 证据链
来自黑客松（Vault/Escrow/Registry/RangeCalc），不作为本切片的 formal 证据。
formal D4–D7 完成态不因本切片改变。
