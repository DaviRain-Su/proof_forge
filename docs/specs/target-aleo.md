---
id: SPEC-TARGET-ALEO-001
title: Aleo 目标规格（Leo 4.0.2 capability-gated slice）
status: proposed
owner: targets
updated: 2026-08-07
normative: true
---

# Aleo 目标规格（SPEC-TARGET-ALEO-001）

## 1. 范围

`proof-forge-next build --target aleo` 消费 retained `SemanticProgramV1`
（sole NormalizeV1 生产者），经 capability（`ResolvedEngineeringBuildV1`）进入
target-owned Plan/IR，发射 **Leo 4.0.2 source** 与
`{programId}.aleo-query-contract.json` network-state descriptor。与黑客松
V1-direct 平行路径无关。ALEO-I1 已以
`pf.aleo-plan.engineering.v1` 绑定 canonical Plan content digest。默认 profile
`aleo-leo-4.0.2-u64-v1` 保持 zero-tool；显式 profile
`aleo-leo-4.0.2-u64-compile-v1` 使用 locked Leo 4.0.2 执行 offline compile-only
Finalize，并新增 `{programId}.compiled.aleo`、`{programId}.abi.json`、
`{programId}.leo-program.json` 三个 `finalized-extra`。两条 profile 均
`deployable=false`；成熟度为 **source emission + engineering locked compile
finalization**，不包含 execute/proof/deploy/query。

## 2. 支持表面

| 类别 | 支持 |
|---|---|
| 状态 | public UInt8/16/32/64、Int64、exact BLS12-377 `field` 叶；named/Array/Bytes/`Option UInt64`/dense Map cap-2 按 target-owned flatten 进入 `mapping pf_state_N: u8 => T`（key `0u8`） |
| init | `fn initialize(...) -> Final` + one-shot `initialized` guard mapping |
| entry | state-touching → `fn ... -> Final { return final { ... } }`；纯计算 → 普通 `fn -> T`；bounded aggregate return 仅按已冻结 target ABI 子集 |
| view | bare state-read（无参）→ product query-contract 的 `network-state-descriptor`；实际 `leo query` 仍是网络态；纯计算 → 普通 fn |
| 表达式 | legal UInt/Int64/Bool/Field 子集、place、checked arithmetic、六比较、bitwise/logical/shift、pureCall、已开放的 aggregate/index/Option 操作 |
| 语句 | let（不可变）、assign→mapping set、assert、if/else、switch 链、bounded for、bare revert/trap → `assert(false)`；aggregate store 先读取全部叶再统一 set |
| fn | pureFn → Leo `fn`（无 mapping 访问；scalar 参数与结果；aggregate pureFn return 仍 fail closed） |

## 3. Fail-closed（诚实拒绝）

| 形状 | 原因 |
|---|---|
| `emit` | Leo 4.0.2 无链上事件日志 |
| 带参 `revert` | error payload 无法表示 |
| computed / multi-leaf state-reading view | query-contract 只承载 bare single-leaf mapping get；无可执行查询物化 |
| externalCall / schedule / emit / ContextRead | 当前 Aleo capability/Plan 明确拒绝；不得从 Leo 平台能力反推开放 |
| invariant / Principal / String / Int128/256 / nested or non-UInt64 Option / aggregate pureFn return | 当前 target ABI 或语义承载未冻结 |

## 4. Leo 4.0.2 编码

- state-touching：`fn <name>(public p0: u64, ...) -> Final { return final { ... } }`
- dropped 返回值：非 Unit entry 且 body 触碰 mapping → `resultDropped`（Plan
  显式元数据）；每个 return 表达式仍在 final block 内求值
  （`let pf_return: T = ...;`）以保留失败语义，但 Leo `Final` **不返回该值**。
  query-contract 只声明交易后可查询相关 public mappings，不能把映射状态冒充原返回值
- 映射读写：`<mapping>.get_or_use(0u8, 0u64)` / `<mapping>.set(0u8, v)`
- bounded for：`let pf_start = s; let pf_end = e; if (pf_start < pf_end) {
  assert((pf_end - pf_start) <= N); } for pf_c in 0u64..Nu64 { if (pf_c <
  (pf_end - pf_start)) { let pf_i = pf_start + pf_c; <body> } }` ——
  boundExceeded 在 body 前 halt（可观察等价于参考机的 N 次 body 后 revert）
- 字面量：`42u64` / `true` / `false`；let 需显式类型标注

## 5. 制品、解析器与资源边界

产品 materialize 有序输出两个 `materialized-base`：

1. `{programId}.aleo`（`text/plain`）
2. `{programId}.aleo-query-contract.json`（`application/json`，schema
   `proof-forge-aleo-query-contract/v1`）

query-contract 以固定键序绑定 profile、Leo version、source/semantic hash、
`pf_state_N` mappings、bare views 与 `resultDropped` observation；它不是 Leo
`build/abi.json`，也不执行 `leo query`。Finalize 不增加 extra file，保持
`deployable=false`。

- program id：小写 ASCII + 数字 + 下划线（artifact 名小写化）
- 标识符保留字集合（Leo 关键字）→ fail closed
- 表达式深度 ≤ 256、函数 ≤ 256、参数 ≤ 64、语句 ≤ 4096（Plan 校验）

## 6. 成熟度声明

两平台 Tool Lock 固定 Leo 4.0.2 executable digest，并将 source/compile 两个
profile exact 绑定到同一工具。`AleoAcceptance` 只允许显式
`PROOF_FORGE_TOOL_ROOT/leo` 或 package cache 中的 locked binary；无
PATH/cargo/brew fallback。工具存在时硬验证 version/digest/profile，并在隔离 HOME 与
secret/network env 下执行 `leo build --offline --disable-update-check`；缺少 locked tool
时 acceptance 只作 host-optional clean skip，不算 compile pass。

显式 compile profile 的产品 Finalize 则 fail closed：缺失/摘要不符/版本不符/构建失败或
三个输出任一缺失、非 regular、空文件时均不发布 destination。它只把 product `.aleo`
放入临时 Leo package；query-contract 不进入 compiler input。产品测试固定两次同机输出及
manifest/evidence exact bytes，并经 `inspect` 重验 content-bound disk closure。

RPT-024 已确认 `leo run` 只是本地解释，execute/deploy/query 需要网络，synthesize
需要未锁定 CRS，仓库也没有 pinned snarkOS/snarkVM。因此本切片仍未验证 VM、proof、
deploy、on-chain finalization 或 offline query；formal D4–D7 与 hermetic/Stage-0
完成态不因本切片改变。
