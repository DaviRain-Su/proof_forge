---
id: TARGET-TON
title: TON / TVM target dossier
status: draft
owner: architecture
updated: 2026-08-03
normative: true
---

# Target Dossier：TON / TVM

状态：`draft`
Target ID：`ton`
Phase 1：研究期候选；不实现
Static dossier ceiling：`research`

> **研究期边界（ADR-0017）**：本 dossier 只有资料与 family 归类。没有 decision-complete
> descriptor、没有 `TargetDescriptor`/capability/extension、没有 Plan/IR 实现、没有制品或
> 运行证据。不得写成 specified/prototype 或更高 maturity，不得驱动 `TASK-*`。
> `TargetId` 枚举与 `Registry.lean` 本期不变；编译器对 `ton` 继续不可寻址、fail closed。
> 来源以官方文档 URL 引用；本期**不**登记 `SRC-*`/`CLM-*`（见 ADR-0017 §6）。

## 1. 身份与来源

TON 智能合约在 **TVM（Threaded Virtual Machine）** 上执行：栈式、account-based，既非
EVM 也非 SVM 也非 Wasm host。合约持久状态是 account 的 **c4 data cell**（cell DAG +
dict/hashmap）；合约间交互只有 **异步消息**，没有同步跨合约返回值。

Family：[`family-tvm-stack-account.md`](family-tvm-stack-account.md)
（`FAMILY-TVM-STACK-ACCOUNT`）。不得塞进 EVM / SVM / Wasm host family，也不得共享其
Plan/IR 类型。

### 研究期可引用官方来源（plain link；非 SRC 登记）

| 主题 | URL |
|---|---|
| 节点 monorepo / releases | [github.com/ton-blockchain/ton/releases](https://github.com/ton-blockchain/ton/releases)（研究快照：`v2026.06`，2026-07-15；月度节奏；附多平台 binary + sha256） |
| Tolk 编译器 | [tolk-1.4.2](https://github.com/ton-blockchain/ton/releases/tag/tolk-1.4.2)（2026-06-21；独立 tag + 与节点 release 同捆 binary：`tolk-mac-arm64` / `tolk-linux-x86_64` 等）；[docs.ton.org/tolk/overview](https://docs.ton.org/tolk/overview) |
| TVM 总览 | [docs.ton.org/tvm/overview](https://docs.ton.org/tvm/overview) |
| 配置 / GlobalVersion | [docs.ton.org/foundations/config](https://docs.ton.org/foundations/config) |
| 交易五阶段 | [docs.ton.org/foundations/phases](https://docs.ton.org/foundations/phases) |
| 消息 | [docs.ton.org/foundations/messages](https://docs.ton.org/foundations/messages) |
| Cells | [docs.ton.org/foundations/cells](https://docs.ton.org/foundations/cells) |
| 地址 | [docs.ton.org/foundations/addresses](https://docs.ton.org/foundations/addresses) |
| 本地仿真 | [@ton/sandbox](https://www.npmjs.com/package/@ton/sandbox)（研究快照 `0.44.0`）；[github.com/ton-org/sandbox](https://github.com/ton-org/sandbox) |
| 脚手架 | [ton-blockchain.github.io/acton](https://ton-blockchain.github.io/acton)（Acton 为新项目推荐脚手架） |

研究期语言面结论：**Tolk 为官方推荐**；FunC legacy 停维护（最后节点侧标记约 v2025.07）；
Tact deprecated。实现若发生，默认发射路径应优先 **Tolk 源码**，不手写 TVM 汇编、不复活
FunC/Tact 作为产品默认。

## 2. 执行、状态、调用、失败与资源

### 执行

- TVM 为 **栈式 VM**；主整数类型为 **257-bit 有符号整数**（常称 `int` / int257）。
- **无独立“TVM 版本号”产品面**：指令面由 **codepage `cp0`** 与链上 **ConfigParam 8
  GlobalVersion** 共同解锁（主网研究快照：Global version **15**）。CodegenProfile /
  NetworkProfile 未来必须钉死可接受的 GlobalVersion 与 codepage，禁止 best-effort 指令集。
- 合约代码以 cell/BoC 形态驻留 account；入口由 **内部消息 / 外部消息 / get-method** 触发，
  不是 EVM 式同步 `CALL` 返回栈。

### 状态

- 持久逻辑状态：account **c4** 上的 **data cell**（可含 dict/hashmap）。
- **Cell 极限**：每个 cell ≤ **1023 bits** + ≤ **4 refs**；存储规模另受 ~**65k cells**
  量级账户/gas 经济约束（研究期以官方 foundations 为准，实现前须用 pin 工具复测）。
- **Dict / hashmap**：固定 key 长度的有序 KV；**空 dict = null**（不是空 cell 容器的
  通用“空 map”直觉）。小状态 KV 可映射为 dict；大/嵌套结构必须显式 cell layout，禁止
  隐式“任意 Map → dict”。

### 调用

- 合约间 **只有异步消息，无同步调用**。Portable `call`（同步）在 TON 上 **必须 fail
  closed**；唯一诚实的跨合约模式是 **callback + 64-bit `query_id`**。
- 内部消息 ABI 习惯：`32-bit op` + `64-bit query_id` + payload（TL-B 信封之上）。
- **Get methods**：链下只读入口，不改变 c4；不得假装成 on-chain view transaction。
- **Send modes**（研究期必须进入 Plan，不得折叠成单一 “emit message”）：
  `PAY_FEES_SEPARATELY`、`IGNORE_ERRORS`、`BOUNCE_ON_ACTION_FAIL`、`CARRY_*` 等。
- **Bounce**：失败回弹前缀历史上 `0xffffffff`；新格式 `0xfffffffe`。误处理 bounce 是
  一等安全坑。
- **External out message**：日志/观测面（对标 portable `emit` 的候选），不是跨合约
  request/response。

### 失败

- 单笔交易 **五阶段**：`storage → credit → compute → action → bounce`。
  **compute 成功 ≠ 业务成功**：action 阶段仍可能失败；bounce 可能回弹资金与通知。
- Exit code / 阶段结果必须在 sandbox 断言中按阶段区分；禁止把“整笔 tx ok”等同于
  “语义 entry 成功且状态已提交”。
- 单 tx **action 上限 255**；超限是资源/建模失败，不是业务 `false`。

### 资源

- **双账本**：gas（含 compute / dict 操作等）与 **cell / storage** 经济。
- 研究期已知热点：dict / builder **finalize ≈ 500 gas** 量级；cell 极限与 action 上限
  必须进入 Plan 的 resource assumptions，禁止“无限消息队列”幻想。

## 3. Portable fragment 与扩展

### Portable 候选（研究期，非 capability 声明）

| Portable / Semantic 面 | TON 诚实映射（候选） |
|---|---|
| `UInt` / `Int`（有界宽） | TVM int257 + **显式宽度检查**（overflow / range → 固定 exit / revert 策略）；禁止默认真 257-bit 业务语义 |
| 小 KV / dense Map（有界） | c4 dict（固定 key 长、有序）；空 dict = null |
| `emit` | external out message（日志面） |
| `schedule` / 异步工作流 | `SENDRAWMSG` 等 out-action **一等公民**；callback + `query_id` |
| bare assert / error | compute 失败 / 固定 exit code 表（须与 bounce 语义区分） |
| entry（消息接收） | internal/external message receiver（op 分发） |
| view | get-method（链下只读）或只读消息模式（实现前冻结，二者不得混称） |

### 必须 fail closed / 非 portable

- **同步 `call`**：无栈返回值；不得降级为“发消息并忽略结果”的隐式 best effort。
- **IBC 式跨链协议原语**：TON 有自身跨链/bridge 故事，但不等于 CosmWasm IBC；不得复用
  `CosmWasmPlan` packet/ack 模型。
- **Field / Principal 直接映射**：无 bn254 Field 或 EVM address / Solana pubkey 同构；
  地址是 workchain + hash 的 raw/friendly 双形态，须独立 identity 模型。
- **非确定性 `RAND` 等**：不得进入可重放 Semantic 子集。
- FunC/Tact 默认路径、手写 TVM 汇编作为产品 emitter：研究期明确不采用。

### 扩展（未来 CodegenProfile / extension，本期不注册）

消息 op 表、send mode 位图、bounce 格式选择、storage cell schema 版本、get-method 表、
jetton/NFT 等生态消息惯例、GlobalVersion-gated 指令、Acton/Blueprint 脚手架约定。每种
schema 必须 exact 版本化；NetworkProfile 只声明兼容，不定义 schema。

## 4. `TonPlan` schema（研究期草稿）

```text
TonPlan {
  profile,                 -- CodegenProfileId（未来 pin：tolk 版本 / GlobalVersion 假设）
  receivers,               -- op → handler：internal/external 分发表
  storageLayout,           -- c4 cell / dict key 布局与初始化策略
  getMethods,              -- 链下只读方法表（名、参数、结果形状）
  outActions,              -- SENDRAWMSG 等：destination、value、body、sendMode
  errorCodes,              -- 稳定 exit / 业务错误码表
  events,                  -- external out 日志形状
  bouncePolicy,            -- 旧/新 bounce 前缀与处理责任
  resourceAssumptions      -- gas + cell + max actions(255) 上界
}
```

约束（研究期即写死，避免实现时偷换）：

- `TonPlan` **不得**复用 `EvmPlan` / `SolanaPlan` / `NearPlan` / 任何 Wasm host Plan。
- 不得把异步消息编码成“伪同步 call + 忽略返回值”。
- renderer 不得回读 `SemanticProgram` 重推业务逻辑；Plan 必须自包含 receiver、layout、
  out-action 与错误表。
- 本期 **不** 在 Lean 中声明该类型；本节仅为未来独立实现 ADR 的输入草稿。

## 5. Target IR 与制品

推荐路径（研究结论）：

```text
TonPlan → Tolk 源码发射 → .tolk → (tolk) → .fif + BoC + abi.json (+ manifest/evidence)
```

- **Tolk 源码发射**为推荐产品路径；不把手写 TVM 汇编或 FunC 作为默认 IR。
- 预期制品：`*.tolk`（审计）、编译产物（`.fif` / BoC）、`abi.json`（op / get-method）、
  storage layout 说明、capability/manifest 侧车。
- 当前 **不创建** emitter、不产出任何二进制、不注册 Tool Lock 条目。

## 6. 工具链

实现前必须冻结（研究期清单，非现网 pin）：

| 工具 | 研究快照 / 方向 |
|---|---|
| `tolk` binary | `tolk-1.4.2`（2026-06-21）；平台 binary + sha256；与节点 monorepo release 对齐策略待定 |
| 节点 / smartcont 库 | `ton-blockchain/ton` `v2026.06`（2026-07-15）及同捆 stdlib / smartcont |
| 本地仿真 | `@ton/sandbox@0.44.0`（底层 `@ton/emulator`）；Blueprint 0.45.0 为存量支持，非强制产品默认 |
| 脚手架 | Acton（官方新项目推荐）；是否进入 CodegenProfile 由后续 ADR 决定 |

纪律：content-addressed pin + lockfile（对齐 ADR-0013/0015）；missing/version/hash
mismatch fail closed。研究期 **不** 写入 Tool Lock 或 SBOM。

## 7. 部署流程

研究期验收构想（实现后才有证据；本期无运行）：

1. Tolk 编译产物结构门（BoC / ABI 形状）。
2. `@ton/sandbox` 五阶段断言：storage/credit/compute/action/bounce 分阶段可观察。
3. Counter 类最小合约：init data cell、内部消息 inc、get-method 读回。
4. 消息序列 + callback/`query_id` 往返（证明无同步 call）。
5. bounce / action-fail / exit-code 负例。
6. 可选 testnet 部署（network gate；非 Phase 1）。

禁止把“Tolk 编译成功”写成部署或运行完成。

## 8. 安全

重点（必须进入未来验证计划）：

- **Bounce 误处理**（旧 `0xffffffff` vs 新 `0xfffffffe`；资金回弹与重入叙事）。
- **地址格式**：raw vs friendly；user-facing 字符串与链上 256-bit/workchain 表示混淆。
- **消息 value 经济**：attached TON、fees、`PAY_FEES_SEPARATELY` / `CARRY_*` 误配导致
  静默丢消息或意外自毁余额。
- **Cell 极限**（1023 bits / 4 refs）与存储放大；dict finalize gas。
- **255 actions/tx** 上限与“循环发消息”放大。
- **compute 成功但 action/bounce 失败** 的半成功叙事。
- **Get-method 与 on-chain 状态** 一致性（链下读不可替代共识执行）。
- 无同步返回值时的 **callback 假冒 / query_id 重放**（须在消息认证模型中显式处理）。

## 9. 验证阶梯

```text
Tolk compile (结构/ABI)
  → sandbox Counter (c4 + 单消息 + get-method)
  → 消息序列 / callback + query_id
  → bounce / exit-code / action 上限负例
  → 可选 testnet evidence
```

每一级独立 fail closed；上级通过不蕴含下级。研究期只定义阶梯，不声称任何一级已执行。

## 10. 不支持、风险与成熟度退出

### 当前明确不支持

- 任何代码生成、Plan/IR、registry 构造子、CLI `--target ton`。
- 同步跨合约 `call`、IBC 式跨链 Plan 复用、Field/Principal 同构、非确定性 RAND。
- FunC/Tact 作为默认发射、手写 TVM 汇编产品路径。
- formal Reference 差分、Tool Lock、deploy/runtime 证据。

### 风险

- GlobalVersion / codepage 演进导致指令面漂移。
- 异步-only 与 ProofForge portable `call` 矩阵冲突（必须保持 fail closed，参见工程
  backlog 对跨平台 call 过度声明的纪律）。
- Cell/dict 布局一旦在生态中“约定俗成”却未写入 Plan，会造成 layout confusion。
- Sandbox 与主网 GlobalVersion 不一致导致假绿。

### 成熟度退出（离开 `research` 之前）

1. 独立实现 ADR：冻结 `TargetDescriptor`、capability/extension、`TonPlan`/`Ton IR` schema。
2. 将 `ton` 构造子加入 `TargetId` 与 `Registry.lean` 的 researched/descriptor/materialize 轴。
3. 按 ADR-0013 补齐 `SRC-*`/`CLM-*` 与工具 digest pin。
4. 按 `GOV-TASK-FREEZE-001` 立项后才能 in_progress；不得从本 dossier 直接跳到实现。

在上述完成前，static ceiling 保持 **`research`**；本文件不得作为 specified 输入。
