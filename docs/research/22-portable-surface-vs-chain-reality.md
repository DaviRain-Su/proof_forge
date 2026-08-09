---
id: RESEARCH-022
title: 可移植表面 vs 链上现实（跨合约 / 资产 / 原子性）
status: draft
owner: engineering
updated: 2026-08-07
normative: false
---

# 可移植表面 vs 链上现实

> **目的**：用一张「产品看得懂、工具链可钉」的清单说明——  
> **为什么同一份 `program` 不能诚实直出「各链行为与失败语义都相同」的制品**，  
> 以及 **每个 target 在跨合约调用、资产移动、原子性上的硬边界**。  
>
> **不是** wire Op 格子（那是 [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md)）。  
> **不是** host/syscall 全表（那是 [`20-host-function-survey.md`](20-host-function-survey.md) /  
> [`21-system-programs-survey.md`](21-system-programs-survey.md)）。  
> 本文只钉 **「一份代码多链」最容易被误解的那一层**：调用与钱何时算办完。

**工程状态**：draft / non-normative。产品决策债见 `B-CALL-SEM`；scope/formal lighthouse 见 ADR-0036；
资产词汇见 ADR-0029 / ADR-0030。

---

## 1. 一句话结论

| 问题 | 答案 |
|---|---|
| 为什么不能「一份代码直出多链且保证一样」？ | 因为各链对 **跨合约调用何时执行、失败是否拖垮整笔业务** 的定义不同。共享的是 **意图与类型化语义**；**物化形态与失败边界** 必须 per-target 诚实。 |
| 是 Wasm 的锅吗？ | **不是。** Wasm 只是字节码/本地 VM。NEAR 与 CosmWasm 都可是 Wasm，跨合约模型仍完全不同。 |
| 是 NEAR 设计导致的吗？ | **对跨合约资产移动而言，是。** NEAR 跨合约以 **Promise / 多 receipt** 为主；不能把 NEP-141 说成「当场同步 transfer 已完成」。 |
| 那还统一什么？ | 统一 **源语言、Semantic、扩展 catalog、fail-closed**；不统一 **假同步** 或 **假原子性**。 |

通俗比喻：

- **EVM / Solana（及 CW 上诚实的 sync 资产绑定）**：柜台当面结账——钱没扣成功，货也不算卖。  
- **NEAR 跨合约**：先开一张「稍后办理」的工单——你离开柜台后才真扣款，可能失败。  
- 源码若写成「改账本 → 立刻转账 → return 成功」，在 NEAR 上 **不能** 假装和 EVM 同一保证。

---

## 2. 读表约定

| 列 | 含义 |
|---|---|
| **跨合约模型** | 链上真实机制（CALL / CPI / Promise / SubMsg / out-message …） |
| **sync `call`（外调）** | 产品 `call QN(...)` 在该 target 是否可绑「当场完成」的语义 |
| **async `schedule`** | 产品 `schedule` / fire-and-forget 通道 |
| **`pf.assets.token.transfer`（sync）** | 是否可诚实绑「同事务/同调用语义内」的代币转出 |
| **`token.transferAsync`** | 是否绑异步出金 |
| **资产失败与本地 state** | 转账失败时，已改的业务 state 是否随同失败（原子性） |
| **MiniAmmAssets 式「改账+转币」** | 与 `Examples/MiniAmmAssets.lean` 同一业务写法是否可诚实多链 |

状态词：

- **YES** = 工程已绑且语义与文档一致（可有 PARTIAL/工程门上限）  
- **NO / FC** = fail closed 或永久不可绑  
- **ASYNC-ONLY** = 只能 async，不能 sync  
- **PARTIAL** = 机制在，但 callee 绑定/返回值/账户 ABI 等未闭合（见 B-CALL-SEM）  
- **N/A** = 该平台无此层（电路域等）

---

## 3. 总表：12-target registry（工程控制面）

> accepted PRD Phase 1 文案仍以 **EVM / Solana / NEAR / Noir** 为主；  
> Aleo / Psy / Quint / CosmWasm / TON 为 engineering implemented；  
> Soroban / ICP / OpenVM 为 design-only。accepted/engineering 边界见 ADR-0036。

| Target | 执行家族 | 跨合约模型（现实） | sync 外调 `call` | async `schedule` | token.transfer (sync) | token.transferAsync | 资产失败 vs 本地 state | MiniAmmAssets 式写法 |
|---|---|---|---|---|---|---|---|---|
| **EVM** | 账户 + EVM | 同 tx 内 `CALL` | YES（static QN；地址绑定 PARTIAL） | YES（same-tx fire-and-forget；**非**跨 tx） | YES（ERC-20；E1a + Anvil） | FC | 整笔 revert → 原子 | **YES**（M5 Anvil） |
| **Solana** | 账户 + SBPF | 同 ix 内 CPI | YES（仅 exact CPI profile；legacy FC） | FC（product async） | YES（classic Token CPI；Mollusk + Surfpool business） | FC | 整笔 ix 失败 → 原子 | **YES**（E4 双链门） |
| **NEAR** | 账户 + Wasm | **Promise / 多 receipt** | FC（sync 跨合约） | YES（promise schedule） | **FC 永久** | YES（NEP-141 Promise） | Promise 晚失败 **不**自动回滚已提交 receipt 内 state | **NO**（须 async 产品或 vault-internal） |
| **Noir** | 电路 | 无链上执行调用 | PARTIAL（relation / witness；**不** attest 链上发生） | PARTIAL（同左） | FC | FC | N/A（无链上资产移动） | **NO**（电路域） |
| **CosmWasm** | Cosmos + Wasm | **同顶层 tx 内 SubMsg 队列** | 通用 sync 外调受限；**pf.assets sync 已开** | YES（SubMsg `reply_on=never` 子集；PARTIAL） | YES（CW20 SubMsg error-propagating；E1-CW） | FC | 子消息失败可拖垮整笔 tx（sync-atomic 纪律） | **语义可**；应用级 dual-mint 门仍 engineering residual |
| **TON** | Actor 消息 | out-message；**无 sync 跨合约** | FC | YES（createMessage 子集 PARTIAL） | FC（TON pf.assets 冻结决策） | FC | 异步消息；非同栈返回 | **NO**（async actor） |
| **Quint** | 模型 / 规格 | 无部署型跨合约 | FC | FC | 模型 vault 子集；非链上 token CPI | FC | 模型 stutter / 显式 outcome | **NO**（非 deployable AMM 资产） |
| **Aleo** | ZK 应用 | finalize / 系统程序边界 | FC（双键） | FC | FC | FC | N/A 产品路径 | **NO** |
| **Psy** | 电路/Felt | 源码面 `__invoke_sync` 等 | PARTIAL（源码发射；无 VM 门） | FC | FC | FC | N/A | **NO** |
| **Soroban** | 合约 + auth | `invoke` 等（design-only） | design-only | design-only | design-only | design-only | design-only | design-only |
| **ICP** | Canister | inter-canister async | design-only | design-only | design-only | design-only | 跨 canister 异步为主 | design-only |
| **OpenVM** | zkVM guest | 无链上 CPI | design-only / N/A | N/A | N/A | N/A | N/A | **NO** |

### 3.1 「四条常讨论链」对照（用户讨论焦点）

| | EVM | Solana | CosmWasm | NEAR |
|---|---|---|---|---|
| 都是 Wasm？ | 否 | 否（SBPF） | **常是** | **常是** |
| 跨合约「当场办完」？ | 是 | 是 | **同 tx 内可原子** | **否（Promise）** |
| 产品 token 出金键 | sync | sync | sync | **async only** |
| 一份 MiniAmmAssets 源 | 已 runtime 门 | 已 runtime 门 | 语义可、应用门未齐 | **不能同保证直出** |

**关键句**：CosmWasm 与 NEAR 都可能是 Wasm，**差的是消息是否在同一笔链上交易里原子完成**，不是「用没用 Wasm」。

---

## 4. 按家族简述（工具注释用）

### 4.1 状态类 · 同步跨合约友好

- **EVM**：`CALL` 嵌套；失败整笔 revert。资产 = ERC-20 CALL + 返回值谓词。  
- **Solana**：CPI；失败整笔 ix 失败。资产 = Token/ATA + 显式 accounts（CPI profile）。  

→ 适合「改 state → transfer → return」的 **同步北极星**（E4 MiniAmmAssets）。

### 4.2 状态类 · 同 tx 消息队列（仍可绑 sync 资产）

- **CosmWasm**：返回 `SubMsg`；pf.assets 用 **error-propagating** SubMsg 绑 sync transfer。  
  通用 `call`/`schedule` 矩阵仍有 PARTIAL/子集限制；**不等于**「一切都是 async」。

### 4.3 状态类 · 真异步跨合约

- **NEAR**：跨合约 = Promise；token = **`transferAsync` only**。  
  view 上诚实 caller / token balanceOfSelf 等亦有 FC。  
- **TON**：纯异步 out-message；sync call **显式拒绝**（ADR-0024 同级诚实）。  

→ 「一份代码」只能共享逻辑；**资产完成时刻与失败语义必须换产品面或降级保证**。

### 4.4 电路 / 模型 · 无链上资产 CPI

- **Noir / Psy / OpenVM**：无「链上发生了 transfer」的 attestation；外调最多是 witness/relation。  
- **Quint**：规格/模型；Q0 子集，非 deployable token AMM。  
- **Aleo**：产品路径对 call/assets 纵深 FC 为主。  

→ 不参与「双链 runtime 资产门」叙事。

### 4.5 Design-only

- **Soroban / ICP**：可进本表作为「未来行」；未实现 materializer 前不写 YES。

---

## 5. 对产品与工具的直接含义

1. **CLI / 文档 / inspect** 应能指向：  
   - 该 target 对 `effect.synchronous-call` / schedule / `pf.assets.*` 的 **support 与诚实 caveat**（已有 resolver + target dossier；本文补「为什么」）。  
2. **禁止**：resolver 显示 support 就被写成「跨平台 call 已完成」（`B-CALL-SEM`）。  
3. **E4 选 EVM+Solana**：不是偏好，是 **两边都能诚实做 sync token 出金**。  
4. **NEAR 要类似 AMM**：  
   - 要么 vault-internal（无链上 token CPI）；  
   - 要么显式 async 产品（`transferAsync` + 接受非原子）；  
   - **不要** 同步 API 名 + Promise 实现。  
5. **覆盖矩阵分工**：  
   - **本文** = 可移植性 / 原子性 / 资产完成时刻；  
   - **12** = 每个 wire op 是否 LOWERED；  
   - **20/21** = host 与系统程序能力清单。

---

## 6. 与现有文档的关系

| 文档 | 关系 |
|---|---|
| [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md) | Op×target 工程格子；本文不重复逐 op |
| [`20-host-function-survey.md`](20-host-function-survey.md) | 能力全景；本文抽「跨合约一行」做成产品语言 |
| [`21-system-programs-survey.md`](21-system-programs-survey.md) | Token/System 等 L2 形态 |
| ADR-0029 / ADR-0030 | pf.assets 词汇与 E1–E4 分期 |
| ADR-0024（TON） | sync call 永久诚实拒绝 |
| ADR-0028 / #125（Solana） | exact CPI profile 与 async FC |
| `engineering-backlog.md` `B-CALL-SEM` | call/schedule 与平台语义对齐债 |

---

## 7. 维护规则

- 某 target 打开/关闭 sync·async·assets 绑定时：**先改代码与 ADR/dossier，再改本表**。  
- 不得把 PARTIAL 写成 YES 而不带 caveat。  
- 不得把 Wasm 写成跨合约异步的原因。  
- 新增 implemented target 时：本表加一行 + 链接 12 矩阵与 materializer catalog。

---

## 8. 给「工具上写明每个链特性」的建议文案（短）

可嵌在 `inspect <target>` / 文档门户：

```text
Portable source does not imply identical cross-contract guarantees.
- EVM/Solana: sync call + sync token.transfer possible (same-tx/ix atomicity).
- CosmWasm: sync token.transfer via same-tx SubMsg (error-propagating); generic call matrix PARTIAL.
- NEAR: cross-contract is Promise; token.transfer FC; use token.transferAsync only.
- TON: no sync cross-contract; schedule/out-message only.
- Noir/Psy/OpenVM/Quint/Aleo: no portable on-chain asset CPI story (circuit/model/FC).
See docs/research/22-portable-surface-vs-chain-reality.md
```

（具体 CLI 接线属工程切片，不在本 draft 强制实施。）
