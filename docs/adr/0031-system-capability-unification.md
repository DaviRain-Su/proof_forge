---
id: ADR-0031
title: 系统能力统一抽象波（L1 ContextRead 扩键 + L2 官方链上 program 能力 catalog）
status: proposed
owner: architecture
updated: 2026-08-06
normative: true
---

# ADR-0031：系统能力统一抽象波（SYS-CAP-UNIFY）

- 状态：`proposed`
- 日期：2026-08-06
- 前置：ADR-0029/ADR-0030（L1 portable 词汇层与绑定纪律已收口）；ADR-0025
  （EVM `context.caller` 编码冻结）；ADR-0028（Solana 显式账户/PDA/CPI）；
  RPT-020/RPT-021（[`20-host-function-survey.md`](../research/20-host-function-survey.md)、
  [`21-system-programs-survey.md`](../research/21-system-programs-survey.md)，
  产品 owner 调研落盘，2026-08-05）

## 背景

调研（SYS-CAP-SURVEY，done）确认两件事：

1. **平台分三类，抽象边界由类别决定**：状态类（EVM/Solana/NEAR/CW/TON/Soroban/ICP）
   合约直接读真实链上值；电路类（Noir/OpenVM/Psy）只能经 input/witness/oracle 注入
   且必须电路内约束（**可信输入问题**，不是 host function 问题）；Aleo 混合
   （proof ❌ / finalize ✅）。时间戳、区块高度、调用者、自身余额、附加价值、链 ID
   六维在状态类平台高度同构。
2. **系统能力有两种形态，对调用方等价**：L1 内建运行时能力（host function /
   syscall / opcode / stdlib）与 L2 官方链上 program（builtin program / system
   contract / precompile / management canister / 链级模块）。**同一能力在不同链以
   不同形态出现**（sha256 = EVM precompile `0x02` / Solana `sol_sha256` / NEAR host
   `sha256` / TON stdlib；原生转账 = System Program / BankMsg / promise action /
   send_raw_message / credits.aleo）。统一抽象的本质是**能力与形态解耦**。

项目先例已验证 L2 路径：ADR-0030 E1 绑定的 Solana System/Token/ATA program、
NEAR NEP-141、CW CW20 就是"官方链上 program 作为能力"的工程化；E2 的
`envRead` 双键则是 L1 内建能力的 catalog 扩键样板。本 ADR 把二者系统化为同一
catalog 纪律（backlog **SYS-CAP-UNIFY**）。

## 核心决策

1. **统一 catalog 机制**：L1 内建能力与 L2 官方 program 能力共用同一套 wire
   catalog + requirement 行 + per-target 物化 + **无对应物 fail closed** 纪律。
   不设第二套机制。
2. **L1 扩键 = E2 同款纪律**：每个新 `ContextRead` 键交付七件套——closed
   `SchemaId` 键、requirement 行、source surface admission、Normalize lowering、
   Reference 语义、structure-gate/禁表（invariant root/closure pureFn 禁止）、
   per-target accept/FC 矩阵与对应 runtime 门。首期键均为只读、effect-free、
   不进 EffectId 序列。
3. **两个新 catalog 轴**（记入每行/每键的 binding 文档）：
   - **view-safety**（L1）：某键在某 target 上 view-safe 还是 view-forbidden。
     动因：NEAR `predecessor_account_id`/`signer_account_id`/`attached_deposit`
     在 view 上下文被宿主禁止。view-forbidden 键出现在 view callable 时，该
     target 的 Plan 必须 fail closed（不得假装各链都 view-safe）。
   - **强制等级**（L2）：`protocol-builtin`（Solana System、EVM precompile、
     Aleo credits.aleo、ICP `aaaaa-aa`）/ `official-deployed`（Solana Token/ATA、
     NNS canisters）/ `ecosystem-reference`（NEAR staking pool、ARC-20、
     soroban-examples/token）。**ecosystem-reference 不得进入 L2 catalog**——
     它不是系统能力，只是生态惯例（同 ADR-0029 对 ERC-20 的处理：
     interface-standard，非 protocol）。
4. **平台 disposition 不变**：电路类（Noir/OpenVM/Psy）对链上锚定值统一 fail
   closed（Aztec PublicChecks 式 sequencer 公开执行闭环是独立设计波，不属于本
   ADR）；TON 维持 owner 决策冻结；Psy/Aleo 维持 ADR-0029 既有 disposition
   （零绑定），某键若对 Aleo finalize 诚实可绑须另行单键决策；Quint 模型层逐键
   诚实（可建模为模型输入/变量的键可绑，不可建模的 FC）。
5. **显式非目标**（RPT-020 §4.3）：
   - **随机数永不进 ContextRead**——各链要么没有、要么有偏/可预测/区块级确定，
     统一抽象会教出错误安全模型。
   - **质押/治理/IBC 不进 ContextRead**——它们是业务能力（且几乎 CW 独有），
     应走 `pf.*` extension catalog 的 per-target 独立绑定（同 `pf.assets` 纪律）。
   - **平台独有原语不统一**——PDA、CPI stack height、RawQuery、`commit()`、
     `config_param`、SEND_MODE 等各自留在 target Plan 层。

## L1 扩键波次（ContextRead catalog）

| 期 | 键 | 语义/类型 | 各 target 诚实对应物 | 状态 |
|---|---|---|---|---|
| **S1** | `context.caller : Principal` | 当前调用者身份（= ADR-0030 E3，MiniAMM 依赖） | EVM `CALLER`→`u32le(20)\|\|addr20`（ADR-0025 唯一 realization）；Solana exact CPI profile 的 `pf_caller` signer role→`u32le(32)\|\|pubkey32`（非 tx.origin；legacy profiles FC）；NEAR `predecessor_account_id`（init/entry；**view 禁**）；CW `MessageInfo.sender`（instantiate/execute；query/view 禁） | **done（engineering，2026-08-06）**：四条 target-owned Plan/IR/emitter lane 与 Anvil/Mollusk/near-sandbox/cw-vm 门均已交付；未扩展无对应物 target，非 formal/mainnet parity |
| **S2** | `context.blockHeight : UInt64` | 当前区块高度 | EVM `NUMBER`；Solana ordinary-elf `Clock.slot` via `sol_get_clock_sysvar`（≈400ms 物理槽，**非**逻辑块号——记入 catalog 语义差异；CPI product profile 仍 FC）；NEAR `block_index`；CW `Env.block.height`；TON/ICP 无直接对应物 FC；电路类/Quint FC | **in_progress**（shared + **四 target leaf** Plan/IR/emitter 已交付：EVM/NEAR/CW/Solana-ordinary；专门 Anvil/sandbox/Mollusk/cw-vm S2 runtime 门与 CPI-profile Clock 仍 residual） |
| **S3** | `context.chainId` | 链身份（重放保护/域分隔） | EVM `CHAINID`（UInt64）；CW `Env.block.chain_id`（**String**——Bytes/宽度纪律待 S3 冻结）；NEAR `chain_id`；Solana/TON/ICP 无→FC | pending（类型纪律 S3 冻结） |
| **S4** | `context.attachedValue : UInt64` | 本次调用携带的原生资产量 | EVM `CALLVALUE`；NEAR `attached_deposit`（**view 禁**）；CW `MessageInfo.funds`（单 denom 纪律沿用 C1 `stake`）；Solana 无直接对应物（SOL 经指令转账）FC | pending |

分期纪律同 ADR-0030：shared core（键/requirement/Reference/source admission）
串行于 main；per-target binding lane 文件不重叠可隔离 worktree 并行；每期以对应
runtime 门收尾。**S1 已闭合并解除 ADR-0030 E3；E4（MiniAMM）已进入 EVM-first/算术前置阶段，但双链 runtime 尚未闭合。**

**S1 工程事实（2026-08-06）**：EVM 以 `CALLER` 物化 20-byte Principal，并由
CallerCheck/Ownable Anvil corpus 验证；Solana 仅在 `solana-sbpf-cpi-elf-v1` 以单一
`pf_caller` outer signer 的 32-byte pubkey 物化 Principal，普通 Principal 参数继续走
T12 ix data 且强制 `len∈1..64`/高尾清零，两个 legacy profile 纵深 FC；NEAR 以
`predecessor_account_id` 绑定 init/entry，并把 register id 收归 `RegisterLayout`，view
保持 FC；CosmWasm 仅在实际使用 caller 的 instantiate/execute branch 读取
`MessageInfo.sender`，复用 lowercase `[a-z0-9]`/len/tail 门，query/view 保持 FC。
这些均为工程 local-runtime 门，不是 formal、hermetic 或主网等价声明。

**S2 工程事实（2026-08-06）**：四条状态类 leaf 均已 target-owned Plan/IR/emitter
钉测——EVM `NUMBER`；NEAR view-safe `block_index()`；CW Env JSON bare-u64 `"height"`；
Solana ordinary legacy profiles 经 `sol_get_clock_sysvar` 读 `Clock.slot`（Plan tag 51 /
`Expr.clockSlot`，保持单 state 账户 ABI，**不**引入 Clock account meta；CPI product
profile 明确 residual FC）。诚实差异：Solana 为物理 slot 而非逻辑块号。尚无这四条
高度叶的 Anvil/near-sandbox/Mollusk/cw-vm 专门 runtime 门。因此 S2 保持
`in_progress`（leaf 4/4 ordinary paths，runtime residual），不得写成 formal/跨链
语义等价闭合。

## L2 官方 program 能力 catalog

结构：每行 = （能力 QN， 强制等级， per-target 形态绑定 | FC）。候选波次：

| 期 | 行 | 内容 | 状态 |
|---|---|---|---|
| **S5** | `pf.crypto` v1 | 密码学逐能力 catalog，首行 `sha256`：EVM precompile `0x02`（STATICCALL）/ Solana `sol_sha256` / NEAR host `sha256` / Noir 电路内 `sha256_compression`（**纯函数、无可信输入问题**，电路类可诚实绑定的例外候选——S5 冻结时决策）/ CW 无内建 FC / Aleo 无 SHA-2 FC / TON 冻结 / Quint FC | pending（独立 payload/扩展波） |
| **S6+** | per-chain 官方 program | EVM 系统合约（EIP-4788/2935/7002/7251）、Solana Stake/ComputeBudget、Aleo `credits.aleo`、CW staking/gov、ICP management（design-only target） | deferred（每行独立设计波；质押/治理属业务能力走 `pf.*` extension 纪律） |

## 验证

- 每期：Reference 钉测 + per-target Plan/IR/emitter 钉测 + 产品纵切 + 对应
  runtime 门（Anvil / Mollusk / near-sandbox / cw-vm mock）+ `just dev-check`
  （含 docs-check）+ SBOM pin 刷新。
- 成熟度声明纪律不变：均为工程 local_runtime 门，**非** formal/mainnet parity；
  找不到诚实对应物的 target 按行 fail closed，禁止 best-effort 或隐式 fallback。

## 否决方案

- **把 caller/blockHeight 并入 `envRead` 家族**：`envRead` 是 self-vault 账户状态
  观察（E2）；`context.*` 是交易/区块上下文。家族边界不动，二者共用纪律即可。
- **L1/L2 分两套 catalog 机制**：违背统一抽象目标；extension/requirement 机制
  已证明可同时承载两者（ADR-0030 E1 是 L2、E2 是 L1，机制同一）。
- **随机数进 catalog**：安全模型错误（PREVRANDAO 1-bit 偏置 + 提议者可操纵，
  OWASP SCWE-153；NEAR random_seed 区块级确定；TON rand 可预测）。
- **ecosystem-reference 进 L2 catalog**：NEAR staking pool / ARC-20 /
  soroban-examples/token 是生态惯例而非系统能力，进入即冒充。
- **电路类在本波开链上锚定键**：需要 Aztec PublicChecks 式 sequencer 闭环或
  oracle+Merkle 约束设计，独立设计波；裸电路保持 FC。
