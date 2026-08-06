---
id: ADR-0033
title: MiniAMM 真实资产事务模型冻结（pre-fund + vault credit）
status: proposed
owner: architecture
updated: 2026-08-07
normative: true
---

# ADR-0033：MiniAMM 真实资产事务模型冻结

- 状态：`proposed`（engineering freeze for M4/M5；非 formal）
- 日期：2026-08-07
- 前置：ADR-0030（`pf.assets` transfer / balanceOfSelf / no transferFrom）；
  ADR-0029（L1 assets vocabulary）；ADR-0025（Principal wire）；
  MiniAMM M0 数学向量（`Examples/MiniAmm.lean` + `MiniAmmVectorsV1`）；
  M2/M2b EVM Map 紧凑 IR（deploy size 已非阻塞）

## 背景

M0 冻结了 **vault-internal** constant-product 数学与 LP Map 记账，并在 EVM Anvil
（strict EIP limits）与 Solana Mollusk hybrid 上验证了内部向量。E4 北极星仍要求
**真实 token 进出 vault**，而不是把 `reserve*` 当用户资产的唯一真相。

ADR-0030 已明确：V2 热路径 **不用** `transferFrom` / allowance；用户先把 token
转入 pair/vault，pair 用自身余额与记账 reserve 的差作为 **credit**。M3 把该模式
写成 MiniAMM 可实施、可测、不可诚实撒谎的事务模型，供 M4（Solana 双 mint ATA）与
M5（EVM 双 ERC-20）按同一源码面物化。

## 决策（冻结）

### 1. 双程序分工

| 程序 | 角色 |
|---|---|
| `Examples/MiniAmm.lean` | **M0 数学 / LP Map 权威 demo**（不调用 `pf.assets`）。继续承载共享数值向量与无资产依赖的 Plan 门。 |
| `Examples/MiniAmmAssets.lean` | **E4 真实资产产品面**（`pf.assets@1.1.0` + 同款数学）。M4/M5 runtime 门只认此面或其字节等同演化。 |

两程序 **同一套 UInt64 floor 数学**（首次 LP、双侧 min、双向 swap+amountOutMin、
removeLiquidity）。资产面多出的约束仅为 vault credit 与 token 进出。

### 2. Vault 身份

- 程序 **self** 即 vault。
- EVM：合约地址上的 ERC-20 余额（`balanceOf(self)` / 出金 `transfer`）。
- Solana：program-derived vault 对 `mint0`/`mint1` 的 classic ATA（读 amount 叶 /
  `transferChecked` 以 vault PDA 为 authority）——细节属 M4，不在本 ADR 改 CPI 机器。
- 不引入第二套“逻辑 vault 账户”与 self 分叉。

### 3. 资金路径：pre-fund + credit（禁止 transferFrom）

1. **Pre-fund（独立顶层事务）**：用户或 router 将 `token0` / `token1` **转入 vault**。
   该事务 **不属于** 后续 AMM entry 的原子回滚域。
2. **Credit（AMM entry 内读）**：
   \[
   \mathrm{credit}(m) = \mathrm{balanceOfSelf}(m) - \mathrm{reserve}(m)
   \]
   要求 `balanceOfSelf(m) ≥ reserve(m)`（checked；否则 assert 回滚）。
3. **记账 reserve**：仅在成功 entry 内更新；始终不大于对应 mint 的 self 余额
   （成功路径后应满足 `balanceOfSelf(m) ≥ reserve(m)`；多余为 unaccounted credit）。

### 4. Entry 语义（资产面）

参数与 M0 对齐处保留；swap **不再**接收 `amountIn` 参数——`amountIn` 取
**当前该侧全部 credit**（Uniswap V2 pair `swap` 的 balance-delta 纪律：用户先转入
精确额度）。

| Entry | Credit / 资产动作 | 记账 |
|---|---|---|
| `addLiquidity(amount0, amount1)` | 要求 `credit0 ≥ amount0` ∧ `credit1 ≥ amount1`；**不**再 transfer 入金 | 同 M0 铸 LP；`reserve* += amount*` |
| `swap0to1(amountOutMin)` | `amountIn = credit0`（>0）；成功后 `transfer(mint1, caller, amountOut)` | `reserve0 += amountIn`；`reserve1 -= amountOut` |
| `swap1to0(amountOutMin)` | 对称 | 对称 |
| `removeLiquidity(lpAmount)` | 成功后 `transfer` 两侧 base units 给 `context.caller` | 同 M0 烧 LP、缩 reserve |

Views：`getReserve*` / `getTotalSupply` / `balanceOf(who)` / 可选
`tokenBalance0/1` → `balanceOfSelf(mint*)`（只读）。

`init()` 为零参（避免 EVM ctor 双 Principal = 18 ABI 词 solc StackTooDeep）；
随后一次性 `configure(mint0, mint1)` 写入两个 Principal mint 身份（wire identity
原样存储，**非** 20B/32B 网络地址重解释；与 T10/ADR-0025 一致）。仅允许
`totalSupply == 0 ∧ reserve* == 0` 时配置。

### 5. 失败与诚实边界（不可写穿）

| 场景 | 诚实结果 |
|---|---|
| AMM entry assert / 算术 / Map 满 / transfer 失败 | **AMM 状态**（reserve、LP Map、totalSupply）整笔回滚 |
| Pre-fund 已在**先前**顶层事务完成，随后 AMM 回滚 | Pre-funded token **留在 vault**，成为 unaccounted credit；**不得**宣传“用户资产随滑点失败自动退回” |
| 同块 router multicall（若宿主支持） | 仍是多个顶层消息/调用的组合；本模型不定义跨消息原子性 |
| `amountOutMin` 不足 | assert 回滚记账；已 pre-fund 的 input token 仍在 vault |

禁止：

- 把 pre-fund 与 AMM call 拆开却声称“单一用户资产原子回滚”。
- `transferFrom` / allowance / NEP-141 `ft_transfer_call` 回调扣款作为 MVP 路径。
- 可转让 LP ERC-20/SPL mint（LP 仍为内部 `Map Principal UInt64` cap-4）。

### 6. Unaccounted credit 与可选 skim

成功路径不强制清空 credit。多余 pre-fund 可：

- 被后续 `addLiquidity` / swap 消耗；或
- 由后续 **可选** `skim(to)` entry（把 `credit*` 转出给 `to`）处理——**非** M3 必做，
  M4/M5 前可不实现；若实现必须只动 credit、不改 reserve/LP。

### 7. 与 Reference / formal

- Reference 已有 pf.assets self-vault 解释器（ADR-0030 E2）：deposit/transfer 与
  balanceOfSelf 可对齐 credit 记账；**不**声称 formal TST 或 Reference↔Anvil/Mollusk
  closure。
- M3 不新增 formal TASK/TST。

## 后果

### 正面

- M4/M5 只实现物化，不再争论“谁先转账 / 是否 allowance”。
- Anvil/Mollusk 脚本可写成固定序列：mint/fund → AMM entry → 断言余额与 reserve。
- 与 TokenJar/EnvReadJar 已验证的 `pf.assets` 绑定一致。

### 负面 / residual

- Pre-fund 失败不自动退款：产品文案与 UX 必须诚实。
- Solana 双 ATA 账户图与 EVM 双 ERC-20 部署仍是 M4/M5 工作量。
- cap-4 LP Map 与 UInt64 乘积上界仍是工程 pilot，不是通用 DEX 生产能力。

## 完成信号（M3）

1. 本 ADR 落盘且 `document-status` / plan 指针更新。
2. `Examples/MiniAmmAssets.lean` 存在并声明 `pf.assets@1.1.0`，entry 面符合 §4。
3. 至少 **EVM** `plan`/`build` 产品路径绿（Plan pin）；Solana sole-rail plan 能编则钉，
   不能编则明确 FC 原因留给 M4（不得 silent 假绿）。
4. **不**要求 M3 完成 Anvil 双 ERC-20 或 Mollusk 双 mint 资产流（那是 M5/M4）。

## 参考

- [`0030-pf-assets-vocabulary-wave.md`](0030-pf-assets-vocabulary-wave.md)
- [`Examples/MiniAmm.lean`](../../Examples/MiniAmm.lean)（M0）
- [`Examples/MiniAmmAssets.lean`](../../Examples/MiniAmmAssets.lean)（本切片产品面）
- [`Examples/TokenJar.lean`](../../Examples/TokenJar.lean) / [`EnvReadJar.lean`](../../Examples/EnvReadJar.lean)
- [`Tests/Semantic/MiniAmmVectorsV1.lean`](../../Tests/Semantic/MiniAmmVectorsV1.lean)
