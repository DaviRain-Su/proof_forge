---
id: ADR-0030
title: pf.assets 词汇扩展波（token 绑定 + balanceOfSelf env-read + AMM 北极星）
status: proposed
owner: architecture
updated: 2026-08-05
normative: true
---

# ADR-0030：pf.assets 词汇扩展波

- 状态：`proposed`
- 日期：2026-08-05
- 前置：ADR-0029（L1 portable extension 层 + catalog 包装 + A→D 分期已收口）

## 背景

ADR-0029 建立了 L1 词汇层并完成 `pf.assets@1.0.0` 的 native 两 API 在五条 target
的绑定（Quint 模型 / EVM / Solana / CosmWasm / NEAR；Psy/Aleo 零绑定；Noir 永久 FC；
TON 冻结）。但 v1 只有 native deposit/transfer，**复杂应用（DEX/借贷/治理）做不了**。
本 ADR 以 **Uniswap V2 式 AMM** 为北极星，冻结下一波词汇扩展的范围与纪律。

关键事实：`pf.assets.token.transfer` / `token.transferAsync` **已在 v1.0.0 frozen
payload 中**（5 QN 之二），当前全 target fail closed 于 Plan——token 家族的开通
**不需要 payload 改版**，是纯 per-target binding 工作。只有全新能力（余额读取、
授权扣款、发行）才需要 payload bump 与有意的重新 opt-in（ADR-0029 准入治理第 1 条）。

## Uniswap V2 能力分解（北极星依据）

| AMM 需求 | portable 对应 | 本波处置 |
|---|---|---|
| 代币转入/转出池子 | `pf.assets.token.transfer`（已在 payload） | **E1：四条部署链绑定** |
| 读自身代币余额（reserves 模式） | `pf.assets.*.balanceOfSelf`（新 env-read） | **E2：payload v1.1.0** |
| 恒定乘积 x*y≥k | UInt128/256 宽算术 | 已有，不动 |
| LP 份额 | v1 内部记账（`Map Principal UInt64` state） | 已有；发行真资产（mint）**defer 至 custody/issuance v2** |
| LP 归属/权限 | `context.caller`（编码已冻结于 ADR-0025） | **E3：Plan 层开放（B-CTX-OPEN）** |
| TWAP | `context.unixTimeSeconds` + 累积器 | 已有，不动 |
| 授权扣款 transferFrom | 模型不通用（NEP-141 无 allowance） | **本波不做**（V2 reserves 模式已绕开） |
| flash swap（先发货+回调） | 动态 callee + 回调 | **本波不做**（破 static-QN 根基，见否决） |

**V2 的热路径刻意不用 transferFrom**（用户先转账、pair 读自身余额），所以 MVP AMM
只需要 transfer + balanceOfSelf + caller——不需要发明 allowance 抽象。

## E1：`pf.assets.token.transfer` per-target 绑定（payload 不变）

| Target | 绑定 | 关键设计点 |
|---|---|---|
| EVM | ERC-20 `transfer(address,uint256)` | **动态 callee**：token 合约地址来自 `mint` Principal 参数（exact wire shape `u32le(20)||addr20`，B2 dst 同纪律）；这是受控的动态地址 CALL，**仅允许 catalog token 家族**（非任意 dynamic callee）；返回值 quirks（无返回值/USDT 类）入 catalog predicate；失败（revert/false）传播 |
| Solana | classic SPL `transferChecked`（vault ATA → dst ATA） | 复用 ADR-0028 机器：fixed Token program id + 动态账户（无动态 callee 问题）；dst ATA 缺失先行 `createIdempotent`；decimals join 入 catalog |
| CosmWasm | CW20 `Transfer` execute（WasmMsg SubMsg 给 token 合约） | 动态 token 合约地址（bech32 编码契约同 C1 dst）；error-propagating SubMsg 同 C1 sync 纪律 |
| NEAR | NEP-141 `ft_transfer`（async） | **仅 `transferAsync` 可绑**（跨合约为 Promise）；sync `token.transfer` 永久 FC |
| Quint | 模型层 token vault（mint-keyed Map） | 可选；Q0 若能诚实建模 mint-keyed 余额则绑，否则保持 FC |
| Psy/Aleo/Noir/TON | 全 FC | 与 v1 结论一致 |

**动态 callee 纪律（新冻结）**：token 家族把 callee 从 static-QN 扩为「参数携带、
catalog 限定、exact wire shape 校验」的动态地址。这不是任意 dynamic call——EVM 的
generic dynamic callee 仍 FC；只有 catalog 声明的 token 接口形态允许参数化地址。

## E2：`balanceOfSelf` env-read（payload v1.1.0）

新增 QN（payload bump → 新 digest → 源码显式重新 opt-in）：

| QN | 语义 | 各 target 诚实性 |
|---|---|---|
| `pf.assets.native.balanceOfSelf() : UInt64` | 读 self vault 原生余额（view 可用；只读） | EVM `selfbalance` / Solana vault PDA lamports / CW `query_balance`（env）/ NEAR `account_balance` host——均 sync 可读 |
| `pf.assets.token.balanceOfSelf(mint : Principal) : UInt64` | 读 self 的 token 余额 | EVM 需 staticcall ERC-20 `balanceOf`（动态 callee + 只读）；Solana 读 vault ATA data（账户须传入）；CW smart query（WasmQuery——mock 可查）；**NEAR 跨合约 view 是 async → FC** |

env-read 是新的 op 家族（不同于 ExternalCall）：只读、view 可用、不产生 effect。
Reference 语义与 ABI 影响在切片时冻结。

## E3：`context.caller` Plan 层开放（B-CTX-OPEN 的 pf.assets 承接）

LP 份额/权限需要 caller。编码已冻结（ADR-0025：`u32le(20)||addr20` EVM；各 target
按各自 identity 长度另决策）。本波只承接 AMM 所需的 entry 内 caller 读取，
per-target 原子 cutover 纪律不变。

## E4：MiniAMM 北极星里程碑

`Examples/MiniAmm.lean`（工作名）：add-liquidity（内部 LP 份额记账）+ swap
（reserves 模式：transfer + balanceOfSelf + 恒定乘积）+ remove-liquidity；
目标在 **EVM + Solana**（至少两条部署链）上经各自 runtime 门（Anvil/Mollusk）
验证成功/失败/回滚路径。这是词汇层正确性的应用级证据。

## 分期

| 期 | 内容 | 依赖 | 状态 |
|---|---|---|---|
| **E1** | token.transfer 四链绑定（EVM/Solana/CW/NEAR-async） | 无（payload 已含 QN） | **E1a EVM / E1b Solana done（2026-08-05）**；CW/NEAR-async 为第二波（见下） |
| **E2** | payload v1.1.0：balanceOfSelf env-read + Reference/Normalize 接线 | E1 可先并行 | pending |
| **E3** | context.caller Plan 开放（per-target 原子 cutover） | 独立（B-CTX-OPEN） | pending |
| **E4** | MiniAMM 北极星（EVM+Solana 双链 runtime 门） | E1+E2+E3 | pending |

并行纪律同 ADR-0029：shared payload/Normalize 变更串行于 main；per-target binding
lane 文件不重叠可隔离 worktree 并行；每期以对应 runtime 门收尾。

**E1 工程事实（2026-08-05）**：`pf.assets.token.transfer`（v1.0.0 payload 既有 QN，
无 payload 变更）已绑定两条部署型 target。**EVM**（E1a，commits `77ff279f7` +
`cf64bf14e`）：ERC-20 `transfer(address,uint256)` CALL，mint Principal 参数经
exact wire shape `u32le(20)||addr20`（高肢清零）解码为 20 字节 token 合约地址——
受控动态 callee，仅 catalog token 家族准入，generic dynamic callee 仍 FC；calldata
exact（selector `0xa9059cbb` + 32B address + 32B amount）；返回值三分支 catalog
predicate（returndatasize 0 → USDT 式成功、32 → 首 word 非零、其余 revert），CALL
失败传播 revert；合约自身 ERC-20 余额即 vault，entry 保持 nonpayable。产品纵切
`TokenJarEvmV1`（solc 0.8.34 bytecode + exact closure）；Anvil 工程门真跑
（`scripts/evm_tokenjar_anvil_smoke.sh` 作为 `evm_anvil_differential.sh` companion
leg：mint 2000 → `tipToken(mint,dst,1000)` 精确 ±1000 余额差值、超额 revert 状态
保持、returnFalse 负例、USDT 无返回成功、mint/dst wire-shape 负例全过）。
**Solana**（E1b，commits `611d350da` + `c5d832d4b` + 本收口）：frozen composite
六步序——vault PDA find → vault ATA find+`createIdempotent` ensure → dst ATA
find+ensure → classic Token `transferChecked`（authority=vault PDA，单 signer group
`invoke_signed`）；ATA program 账户经 derive/Plan 补为 outer role（否则
NotEnoughAccountKeys）；**ADR-0028 §4.2 site-time 纪律修正**：两 ATA 的 165B/
initialized/mintEq/ownerEq/delegateNone 谓词从 pre-invoke siteChecks 过滤，改在每次
ensure 之后由 `emitPfAssetsAtaPostEnsure` 重查（fresh ATA 由 ensure 自身初始化，
pre-invoke 检查必假）；**ROLE_DATA_LEN 刷新**：fresh createIdempotent 把账户
realloc 为 165B，role slot 的 data_len 标量仍是 entry 快照 0（lamports/owner/data
为指向 live 输入区的指针，由 runtime `update_caller_account` 自动同步，唯
data_len 是值拷贝），不刷新则下一个 CPI 的 `update_callee_account` 比较 0 vs 165
以 `AccountDataSizeChanged` fail closed——ensure 后显式写回 165（幂等路径无害）。
产品纵切 `runtime-tests/solana/fixtures/TokenJarAssets.lean` 经真实 CLI
`build --profile solana-sbpf-cpi-elf-v1` → `TokenJarAssets.so`（37528 B）+
`inspect` exact closure；Mollusk 工程门真跑（`runtime-tests/solana` **16**
binaries / **338** active，`tipjar_token` **14/14**：pin 矩阵、init/get、既有双 ATA
精确 ±1000 余额差值、fresh dst ATA 创建+转账、underfunded 完整 snapshot rollback、
wrong-mint join、non-canonical dst ATA、多/零 signer 负例）。CW20（CosmWasm）与
NEP-141 `ft_transfer`（NEAR，仅 transferAsync 可绑）为 E1 第二波，未开。
**非** formal TASK/TST、**非** 主网/mainnet parity；Anvil/Mollusk 为工程
local_runtime 门，Reference 仍 opaque void（无 vault 解释器）。

## 否决方案

- **transferFrom/allowance 抽象**：NEP-141 无 allowance（transfer_call 回调模型），
  强抽象则 NEAR 必假；V2 reserves 模式不需要它。后续若做借贷再单独立项。
- **flash swap / 动态回调**：callee 来自运行时输入 + 回调入口，打破 static-QN 与
  Reference 的 response-cursor 模型；非简单 lane 工作，需专门 ADR。
- **现在就发行 LP 真资产（mint/burn）**：EVM 内置记账 vs Solana create-mint+PDA
  authority vs CW20 instantiate vs NEP-141 独立部署——发行语义分歧大，defer 至
  custody/issuance v2（与 Aleo record custody v2 同一设计波）。
- **把 token transfer 留在 static-QN**：token 合约地址必须来自业务参数，static-QN
  无法表达；受控动态 callee（catalog 限定）是诚实的最小扩面。

## 验证

1. E1：每链 Plan/IR/emitter 钉测 + 产品纵切 + 对应 runtime 门（Anvil ERC-20 mock /
   Mollusk Token fixture / cw-vm CW20 mock / near-sandbox NEP-141）。
2. E2：payload digest 重 pin（docs-check 同构门）、旧 digest FC、env-read Reference
   钉测、per-target accept/FC 矩阵。
3. E4：MiniAMM 双链 runtime 门（成功/滑点失败/流动性回滚）。
4. 全波：Quint 模型层优先验证语义（若绑）；不声称 formal/mainnet。
