---
id: ADR-0029
title: Portable 跨程序互通层（shared semantic extensions 与 per-target catalog 绑定）
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# ADR-0029：Portable 跨程序互通层

- 状态：`draft`
- 日期：2026-08-04
- 动机：产品 owner 决策（2026-08-04）——可被诚实映射的链差异必须在物化层消化，
  源码保持 target-neutral；PDA 是 Solana 对"程序控制地址/金库"的实现机制，不是业务语义。

## 背景

当前跨程序互通有两条 lane：

1. **L0 portable core**：generic `call QualifiedId(args)`。callee 是 opaque 静态身份，
   各 target 自行诚实物化（EVM static-QN `CALL`、TON async message、CW SubMsg、NEAR promise），
   无法保持语义即 fail closed。
2. **L2 platform extension**：`requires extension solana.cpi.accounts …`（ADR-0028）。
   源码显式 opt-in 链专属语义（account metas、PDA/bump、System/Token/ATA 程序）。

缺口：**可移植的业务互通意图没有 portable 表达**。原生币转账、代币转账、合约金库托管
这类各链共有的操作，今天只能写成 `solana.*` 链专属 API，导致同一业务逻辑在每个生态
各写一份源码，且诱使本应 portable 的程序过早绑定单链。若不加治理，每接入一个生态就会
复制一套 source 级 SDK（`near.*`、`evm.*`……），portable 核被架空。

关键观察：**ADR-0028 暴露给源码的 PDA 参数，其业务本体是"合约自己控制的地址"**——
这在每条链上都存在，只是实现不同。它可以且应当消入物化层。

## 决定

引入第三层 **L1 portable semantic extension**：链无关 extension（`pf.*` 命名空间）、
链无关 QN、冻结的链无关语义契约；每个 target 的 registry/catalog 把 QN 绑定到具体平台
程序，绑定不了就 fail closed。三层并存，职责互不越界：

| 层 | 身份 | callee/QN | 语义 | 现状 |
|---|---|---|---|---|
| L0 portable core | 无 extension | opaque static QualifiedName | generic `Op.ExternalCall` + rollback | 已有 |
| **L1 portable extension（本 ADR 新增）** | `pf.*` extension（exact triple） | 链无关 QN（如 `pf.assets.native.transfer`） | 冻结的链无关契约 + per-target catalog 绑定 | **新增** |
| L2 platform extension | target 命名空间 extension | 链专属 QN（如 `solana.system.transfer`） | 链原生语义 | ADR-0028，不改 |

### 准入规则（portable-first）

1. 新互通能力**必须先尝试表达为 L1**；只有证明不存在诚实 portable 语义（在文中列举
   至少两个 target 之间不可调和的语义冲突）才允许落 L2。
2. L1 的 QN 与 extension id 不得包含 target 名；版本/SemVer/digest 纪律与 ADR-0005 相同，
   requirement row 复用 ADR-0028 #116 的 exact triple 机制。
3. L2 继续存在且不被改写、不被降级为 fallback；`solana.companion.*` 保持 test-only。
4. TargetId 永不改写源码语义；L1 API 的 target 绑定写入 **target-owned catalog**
   （ADR-0028 callee catalog 模式从 Solana profile 推广为 per-target registry 资产）。

## 可移植性的词表判据

> **可移植性是"词表"的属性，不是程序的属性。**

程序 P 对 target 集合 T 可移植，当且仅当 P 引用的每个外部 QN 都属于 L0/L1 词表，
且对每个 t ∈ T，t 的 catalog 中存在该 QN 的 `admitted=true` 绑定。

- **推论 1**：调用已部署合约不破坏可移植性。System Program、SPL Token、ERC-20 全是
  已部署合约；破坏可移植性的是把被调方的**链原生接口形状**写进源码（L2 QN），
  而不是"调用"本身。
- **推论 2**：对没有 admitted 绑定的 target fail closed 是正确行为，不是缺陷；
  绑定集合的扩张是 catalog 版本演进，不需要触碰源码。
- **推论 3**："彻底不调用任何现有合约"是充分不必要条件——零调用仍受资源/隐私/
  时间模型差异约束（dense Map cap-8、Noir 私有见证），可移植性永远相对一个词表而言。
- **推论 4**：wrapper 必须住在编译器侧（catalog + lowering），不得住在用户源码里；
  per-target adapter 源码模块（expect/actual 模式）会破坏 sourceHash/semantic hash
  跨 target 一致性，本项目不采用（见否决方案）。

## Custody 的 portable 模型（PDA 消隐的核心）

跨链业务互通的高频概念只有三个身份：

1. **caller**：`context.caller`（已有；ADR-0025 冻结 EVM 编码，Plan 开放另议）。
2. **self vault**：合约自己控制的资产持有身份与余额。**这是 PDA 的业务语义本体**：

   | Target | "self vault" 的诚实实现 |
   |---|---|
   | Solana | program-owned **PDA**（frozen seeds，如 `proof-forge:vault:v1` + bump；无 keypair；`invoke_signed` 签名）；创建走 System CPI，幂等 |
   | EVM | `address(this)` 与合约自身 balance |
   | NEAR | current account id 与 contract balance |
   | CosmWasm | contract address 与 bank balance |
   | TON | contract address 与 balance |

   源码只出现 portable 的 vault 概念；seeds/bump/`invoke_signed`/ATA 全部留在
   Solana-owned Plan/IR。注意区分 **program identity** 与 **vault identity**：Solana 上
   program id ≠ 资产地址；EVM 上二者同一。portable 抽象只暴露 **vault**（"本合约资产的
   持有身份"），program id 不进业务面。
3. **外部身份**：callee program（L0 已有）与外部资产身份（SPL mint / ERC-20 合约 /
   CW20 地址或 denom / NEP-141 合约）。wire 上保持 opaque `Principal`/`Bytes` identity
   （沿用 T10/T12 wire-identity 与 PrincipalAddr pin：**不做全局同构**），具体平台对象由
   per-target catalog 精确绑定。

## L1 首个 extension：`pf.assets@1.0.0`

Frozen identity payload（ADR-0028 §2 同纪律：canonical JCS；docs-check 复算门禁；
acceptance 若修订必须 bump version/digest 并原子更新 payload/本表/checker）：

| 文件 | raw SHA-256 | domain-separated digest |
|---|---|---|
| [`pf-assets-extension-v1.json`](../specs/pf-assets-extension-v1.json) | `fe12c5667bc4e30541fe16d201a02afbf0a00da0333777369e38ddb74a02d4fc` | `sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed` |

Digest 公式：`SHA-256("pf.extension-semantics.v1" || NUL || extensionJcs)`。
source declaration 使用 extension domain digest。

每条 API 给出 portable 语义契约与各 target 的绑定/拒绝。**sync/async 不作为隐式差异**：
`transfer` 要求 sync-atomic（failure 随本交易传播），`transferAsync` 为 fire-and-forget
（不观测结果）；每个 target 只绑定能诚实满足的 variant，与既有 sync call vs `schedule`
纪律同构。

| API | portable 语义契约 | Solana | EVM | NEAR | CW | TON |
|---|---|---|---|---|---|---|
| `pf.assets.native.deposit(amount)` | entry 内从 caller 向 self vault 转入 `amount`；成功后 caller 减、vault 增；failure 传播 | System CPI：outer-signer caller 账户 → vault PDA（复用 account-bound Principal 机制，ABI 细节留 Plan） | `msg.value` 精确校验（== 或 ≥ 于 acceptance 钉死）；无 deposit 的 entry 生成 `msg.value==0` 检查 | attached_deposit 校验 | message funds 校验 | inbound value 校验 |
| `pf.assets.native.transfer(dst, amount)` | 从 self vault 扣 `amount` 记入 `dst`；sync、随交易原子、failure 传播；对接收方是否执行代码**不作承诺**（opaque external effect） | System transfer：vault PDA → dst，`invoke_signed` | value `CALL`（合约 balance；接收方 fallback 可能执行——见下文"诚实注记"） | **fail closed**（Promise 为 async；可绑 `transferAsync`） | `BankMsg::Send`（需 reply_on_error 语义；当前 CW 纪律为 reply_on=never，须另立 versioned contract） | **fail closed**（async message；可绑 `transferAsync`） |
| `pf.assets.token.transfer(mint, dst, amount)` | self vault 的 `mint` 代币转 `amount`（base units）给 `dst`；sync 原子 | classic Token `transferChecked`（vault ATA → dst ATA；dst ATA 缺失时先行 `createIdempotent`——幂等 ensure 是实现细节） | ERC-20 `transfer`（返回值/无返回值兼容策略入 catalog predicate） | **fail closed**（NEP-141 async；可绑 `transferAsync`） | CW20 `Transfer` / `BankMsg::Send`（denom 绑定入 catalog） | **fail closed**（jetton async；可绑 `transferAsync`） |
| `pf.assets.*.transferAsync(...)` | fire-and-forget；不观测结果、不传播异步失败 | —（Solana sync 天然满足更强保证，**不**提供弱语义 variant，避免假异步） | —（同理） | native `Promise` / NEP-141 | SubMsg reply_on=never（现纪律） | out-message（现纪律） |

余额查询类 API（如 `balanceOfSelf`）需要新的 env-read 表面，**本 ADR 不覆盖**，另立切片。

### 诚实注记（不作过度承诺）

- **EVM 接收方代码执行**：EVM value `CALL` 可能执行接收方 fallback；Solana/NEAR/CW 的
  原生转账不执行接收方代码。L1 契约因此把 transfer 定义为 **opaque external effect**
  （复用 Reference `responses` cursor 模型）：对"接收方可能执行任意代码"正确的程序，在
  提供更强保证的链上依然正确。Reference 语义保持唯一，target 只许提供更强运行时保证，
  不得提供更弱。
- **NEAR/TON 的 sync 缺口**是 fail-closed 哲学的预期行为，不是缺陷；它们绑定
  `transferAsync` 或拒绝，不得把 async 包装成 sync。
- **资产身份**不做跨链同构：mint/ERC-20/denom 的对应关系是 per-target catalog 的
  versioned 绑定（含 decimals join、Token-2022 排除等谓词），不进 source。
- **Solana deposit 的 ABI 后果**：caller 账户成为 outer signer role——这正是 ADR-0028
  account-bound Principal 机制的复用，账户枚举出现在 Solana-facing ABI/Plan，不进源码语义。

## PDA 消隐规则

ADR-0028 暴露的 PDA 用法按下表分流：

| ADR-0028 现状 | 业务本体 | 去向 |
|---|---|---|
| `solana.system.transfer(payer, …)`（payer 为 outer signer） | caller 出资 | L1 `pf.assets.native.deposit` |
| `solana.system.createPdaAccount(…)` 建金库/托管账户 | self vault 的创建 | L1 vault 生命周期（init/幂等 ensure），Solana lowering 内部 |
| `solana.token.transferCheckedPda(…, authorityPda, seedAuthority, seedTag, bump, …)` | 从 self vault 出币 | L1 `pf.assets.token.transfer`（PDA 签名细节消隐） |
| `solana.ata.createIdempotent(…)` | 确保收款方能收币 | L1 token transfer 的 Solana lowering 内部步骤 |
| `solana.companion.*` | 测试伴侣程序 | 保持 test-only；业务等价物是 L0 generic call |
| 任意 account metas / 自定义 seeds 数据账户 / remaining accounts | Solana 执行模型调用约定 | **留 L2**，无 portable 语义 |

## 包装层 catalog 设计

L1 的包装由**四类资产**承载（ADR-0009 三层身份模型的延伸；字段名为示意，
acceptance 时以 frozen payload 为准）：

| 资产 | 归属 | 内容 | digest domain |
|---|---|---|---|
| L1 extension payload | 链无关，registry 一份 | QN 集、参数/结果类型、portable 语义契约（sync/async、原子性、failure、ordering）、precondition 谓词 | `pf.extension-semantics.v1`（复用 ADR-0028） |
| **Target binding catalog** | 每 target 一份，versioned | QN→平台对象绑定、lowering 契约、artifact/interface 绑定、准入状态 | catalog 自带 domain（如 `pf.catalog.solana.v1`） |
| Asset registry | **NetworkProfile 维** | 资产实例身份（mainnet USDC mint、Sepolia 某 ERC-20 地址……）与 decimals 等谓词 | 独立 domain |
| L2 callee catalog | 每 target 一份 | ADR-0028 形态 | 已有（如 `pf.solana.callee-catalog.v1`） |

**程序/标准身份进 target catalog，资产实例身份进 NetworkProfile asset registry。**
Solana 的 System/Token program id 跨 cluster 一致，可直接进 catalog；EVM 的 ERC-20
代币地址是 per-chain 的，只能进 NetworkProfile。同一 L1 程序 + 同一 target catalog，
切换 NetworkProfile 即切换部署环境，源码与 catalog 均不动。

### Catalog 条目结构（推广 ADR-0028 callee catalog）

```jsonc
{
  "schema": "proof-forge.catalog.solana.v1",     // 示意
  "digestDomain": "pf.catalog.solana.v1",
  "version": "1.0.0",
  "bindings": [
    {
      "qn": "pf.assets.native.transfer",          // 链无关 QN
      "layer": "L1",                               // L1/L2 条目可共存于一份 catalog
      "extensionRef": { "id": "pf.assets", "version": "1.0.0",
                        "digest": "sha256:…" },    // exact triple 回指链无关 payload
      "packageId": "system-v1",                    // 平台对象（可复用 L2 包身份）
      "executionClass": "native-system",
      "artifactBinding": { "kind": "runtime-native" },
      "loweringContract": {                        // 包装的核心：该 QN 在此 target 的物化策略
        "kind": "vault-pda-system-transfer",
        "vaultSeeds": "proof-forge:vault:v1",
        "signer": "vault-pda-invoke-signed",
        "failure": "propagate"
      },
      "admissionRequirements": [ "…" ],
      "admittedForMaterialization": true,
      "productRole": "approved-product-closure"
    }
  ]
}
```

`artifactBinding` 由 ADR-0028 两形态推广为三形态：

| 形态 | 适用 | 示例 |
|---|---|---|
| `runtime-native` | 链原生程序/模块 | Solana System program、CW bank 模块 |
| `package-owned-bytes` | package 自持 exact 字节码 | classic Token/ATA loader-v3 ELF（现有） |
| **`interface-standard`（新增）** | 接口统一、实例无数的对象，不绑定字节码，绑定标准 + 谓词 | ERC-20（返回值纪律/decimals join/排除 fee-on-transfer 等谓词）、CW20、NEP-141 |

`loweringContract` 声明物化策略：vault PDA seeds recipe、ATA ensure 步骤、EVM value
`CALL` 编码与重入注记、ERC-20 返回值处理、SubMsg reply 模式等。策略变更必须 bump
catalog version/digest；源码与链无关 extension payload 不动。

### 同一 QN 的多 target 绑定（并排示例）

| QN | Solana | EVM | CosmWasm |
|---|---|---|---|
| `pf.assets.native.transfer` | `system-v1` + vault-pda-transfer | native-value 包 + value-CALL（opaque-effect 注记） | bank 模块 + `BankMsg::Send`（reply_on_error 待新 CW contract） |
| `pf.assets.token.transfer` | `token-classic-v1` + vault-ATA `transferChecked` + ATA ensure | `erc20` 包（`interface-standard`）+ `transfer` 编码 | `cw20` 包 + `Transfer` execute |
| `pf.assets.native.deposit` | `system-v1` + outer-signer→vault-PDA | msg.value 校验 | funds 校验 |

### 准入治理（curation 纪律）

1. 新增 L1 QN：只改链无关 extension payload（version/digest bump）。源码 declaration
   对旧 digest fail closed，必须显式更新——这是**有意的重新 opt-in**。
2. 新增/修改某 target 绑定：只改该 target catalog（version/digest bump）；其他 target
   与全部源码不受影响。
3. 每个 binding 必须有：Reference 语义等价说明、per-target accept 测试、负例
   （谓词失败 / failure 传播 / rollback）。
4. 禁止 runtime 网络 lookup、QN hash 冒充身份、版本近似匹配（#111 honesty 纪律推广）。
5. 无"半绑定"：QN 存在但 `admitted=false` 时，该 target 对使用此 QN 的程序
   fail closed，诊断精确到 QN 与 catalog digest。
6. profile payload 以 exact digest 引用 selected catalog（ADR-0028 §2 profile↔catalog
   三角关系推广到全部 implemented target）；BuildIdentity/Plan/evidence/manifest
   绑定同一 catalog digest。

## 重写示例（展示"抹除链相关 extension"后的形态）

**托管转账（现状 L2，仅 Solana 可构建）**：

```lean
requires extension solana.cpi.accounts version "1.0.0" digest "sha256:df7d…"
entry transfer(payer : Principal, recipient : Principal, lamports : UInt64) : UInt64 do
  call solana.system.transfer(payer, recipient, lamports)
  ...
```

**同一业务意图（L1，所有绑定该 API 的 target 均可构建）**：

```lean
requires extension pf.assets version "1.0.0" digest "sha256:97dfde7f…"
entry tip(recipient : Principal, amount : UInt64) : Unit do
  call pf.assets.native.deposit(amount)
  call pf.assets.native.transfer(recipient, amount)
```

**Escrow 放币（现状 L2：`createPdaAccount` + `createIdempotent` + `transferCheckedPda`）**：

```lean
-- L1：金库 ATA 的创建、bump、invoke_signed、decimals join 全部在 target lowering 内
entry release(mint : Principal, buyer : Principal, amount : UInt64) : Unit do
  call pf.assets.token.transfer(mint, buyer, amount)
```

同一源码在 EVM 物化为合约 balance 的 ERC-20 `transfer`，在 Solana 物化为 vault PDA 的
`transferChecked`；业务语义（原子、failure 传播、source order）不变。

## 不可映射清单（必须留 L2 或 fail closed）

任意 account-metas CPI、remaining accounts、自定义 seeds 的**数据**账户、Token-2022、
multisig、sysvar、rent/compute budget 管理、EVM `delegatecall`/proxy、NEAR 跨合约
callback 状态机、TON message mode/flag。这些暴露的是目标链执行模型的调用约定，
没有业务级 portable 语义；强行抽象只能发明语义，违反 INV/FR-005。

## 与现有合同的关系

- **不改** ADR-0002/0003/0005/0028；本 ADR 是 additive 新层。现有 `solana.cpi.accounts`
  程序继续合法；新产品推荐 L1。
- **B-CALL-SEM**：本 ADR 是其 portable 分支的解决方案候选；链原生分支仍由 L2 承担。
- **EXT-\* backlog**：`pf.assets` 为其首个实例；`EXT-CRYPTO` 等后续 L1 候选沿用本模式。
- **state 物化**（2026-08-04 讨论）：自有 state 已在物化层映射（state account / storage
  slot / KV）；未来 "PDA-per-entry `Map`" 是 Solana 新 `CodegenProfileId` 的 target-owned
  lowering 决策，源码不变——与本 ADR 的 custody 模型正交，可复用 vault seeds 纪律。
- callee 部署地址绑定（L0 generic call 的 deployment-address binding）属
  NetworkProfile/registry 议题，不在本 ADR。

## 否决方案

- **只做 L2 per-target 扩展**（每链一套 `xxx.cpi.*`）：源码碎片化，portable 核架空——拒绝。
- **让 target 在物化时猜测链专属语义**（如自动把 generic call 映射到 System program）：
  隐式 fallback / 发明语义——拒绝（ADR-0003 否决项）。
- **把 vault/PDA 概念直接写进 portable 类型系统**（如 `Pda` 类型）：链概念渗入共享层——拒绝；
  vault 只经 extension API 表达。
- **`payable` 入口修饰符替代显式 `deposit`**：增加 grammar 表面且把资金流隐式化；
  显式 `deposit` 让资金流向在 source order 中可见。若 acceptance 阶段证明修饰符更优，
  可在冻结 API 前替换。

## 验证（acceptance 前的工程门槛）

1. 每个 L1 API：Reference `ExternalCall` 语义 case（debit/credit/failure propagation/
   source order/rollback），含 opaque-effect 接收方纪律。
2. per-target accept/FC 矩阵测试：绑定表、sync/async variant 分离、catalog digest 纪律。
3. extension exact triple（id/version/digest）正负例，复用 #116 机制；provenance 绑定
   declaration + 每个 L1 call 的 origin。
4. catalog 门禁：payload canonical JCS 重算、raw/domain digest 复算、profile↔catalog
   exact 引用三角、`admitted=false`/unknown QN/半绑定 fail-closed 负例、
   L1/L2 条目共存但 layer 不可混用，全部接入 `scripts/docs_check.py` 同构检查。
5. 至少一个 target 的先导纵切（建议 EVM 或 Solana），产品 `build`/`inspect` 全链。
6. `TransferSol`/Escrow 的 L1 重写示例与 L2 版本的行为等价性说明（非 parity 冒充）。

后续切片见下节分期；`pf.custody`（self vault 身份暴露）与 `pf.assets` vNext 视结果另立。

## 分期与并行策略

| 期 | 内容 | 性质 |
|---|---|---|
| **A** | L1 registry 机制（exact triple/provenance）+ `pf.assets` payload 冻结 + Reference 语义 + **Quint 绑定** | **shared core，串行 cutover**；Quint 是不可部署的 executable-model target，作为最便宜的语义验证场（vault 扣账/入账、failure 传播、rollback 先钉死在模型里） |
| **B** | **Solana 先导 → EVM** | target leaf lane：Solana 复用 ADR-0028 既有机器重新绑定到链无关 QN（vault PDA≈`createPdaAccount`/`invoke_signed`、出币≈`transferCheckedPda`、ATA ensure≈`createIdempotent`）；EVM 新增 `interface-standard` artifactBinding、deposit/msg.value 校验与 value `CALL` lowering |
| **C** | **CosmWasm + NEAR** | CW 争取完整 sync 绑定（`BankMsg::Send`/CW20 SubMsg 同交易原子，需 reply 语义新 versioned contract）；NEAR 结构上仅 `deposit` + `transferAsync`（Promise 为 async，sync 永久不可绑） |
| **D** | TON、Psy、**Aleo 单独立项** | TON async-only（`deposit` + `transferAsync`）；Psy source-only 无 VM 门，最后；**Aleo 资产为 record 而非账户余额，custody 模型不同，vault 概念需 v2 单独设计，不与 Psy 并列** |
| — | **Noir 对 `pf.assets` 永久 fail closed** | 电路不搬资产，sync/async 均无意义；这是诚实边界，不是欠债 |

**并行纪律**（遵循 Recovery Execution Protocol）：

1. Phase A 为 shared-core **串行**工作，`main` 是 sole integration authority；shared
   docs/registrations/SBOM/commit 由主代理串行维护。
2. Phase B 起，接口（extension payload/digest、resolver row、Reference 契约）冻结后，
   各 target lane 可在**临时隔离 worktree** 并行，文件必须完全不重叠
   （`Targets/<target>*` 与各自测试/脚本）；lane 合并后立即移除 worktree。
3. 禁止 9 target 同时推进：每个 binding 必须带各自的运行时验收门，逐期收尾——
   Quint 模型（A）→ Mollusk（Solana）→ Anvil（EVM）→ wasmd/mock（CW）→
   near-sandbox（NEAR）→ TON sandbox（TON）。
4. 每期完成只更新本 ADR 分期表状态与对应 target dossier；不提前声称后续期的能力。
