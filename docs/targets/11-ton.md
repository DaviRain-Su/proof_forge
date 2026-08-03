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
Phase 1：**MVP 已实现**（2026-08-03，见 §0）

## 0. 工程状态（2026-08-03）

**已实现（TON-1/TON-2，branch `integrate/ton-2`）**：ADR-0024 提升为 implemented
（8 implemented + 3 design-only；profile `ton-tolk-boc-v1`；六轴 `tvm`/`transactionAtomic`/
`cellHashmap`/`asynchronousActor`/`noProof`/`tonChain`）；`Targets/Ton/**` target-owned
Plan/IR/Tolk emitter——c4 扁平 struct cell 状态（无 dict）、`onInternalMessage` op 分发
（32-bit op + 64-bit query_id + loadUint(64)）、init/mutate/view → op/get methods、
TVM int257 上 UInt64 显式范围检查（error code 表 100–105/200+）、if/match/bounded for/
pureFn、emit → external out-message（SEND_MODE_PAY_FEES_SEPARATELY）、revert → throw；
Finalize 经 locked `tolk 1.4.2` 产 `.fif` + `abi.json` + `symbolTypes.json`，再经 companion
`fift`（Tool Lock 外 env `PROOF_FORGE_TON_TOOLS`/`PROOF_FORGE_TOLK_STDLIB`/`PROOF_FORGE_FIFT`/
`PROOF_FORGE_FIFTLIB`——**不得**放进 tool-root）产 **真实 BoC**；Counter e2e
`deployable=true` + `inspect` exact closure 通过。
**capability**：sync call 显式 fail closed（纯异步 actor，不伪装）；async/event 开
（**schedule 的 Plan 发射仍 FC**——destination/send-mode 未接线，属后续切片）。
**仍 fail closed**：multi-width UInt8..256、named Struct/Enum、Array/Map/Bytes/Option、
Field/Principal/String、ContextRead/Commit、nonempty invariants/constants、
masterchain/library/extra currencies。
**maturity**：`source-only`（registry 标签不变）；BoC 已产且 **engineering sandbox
differential 已接线**（TON-3：`runtime-tests/ton` `@ton/sandbox@0.44.0` lockfile pin +
`scripts/ton_runtime_test.sh`——Counter/EventFlowTon 7/7：init/mutate/get、overflow
exit 100 + state 不变（bounceable 与 non-bounceable）、emit external out 解码、Cap
revert exit 200、compute/action/bounce 五相位分离；非主网/formal/runtime 完成）。
callback/promise_then 走编排层（用户第二 entry），不升 Reference schema。
Static dossier ceiling：`research`（formal 静态上限不变；工程 MVP ≠ formal maturity 升格）。

> **Historical / superseded research boundary（ADR-0017 研究期原文）**：下列句子描述的是
> 实现前的研究边界，**已被 2026-08-03 TON-1/2/3 工程 MVP 取代**，仅保留作历史对照——
> 「本 dossier 只有资料与 family 归类；没有 `TargetDescriptor`/capability；没有 Plan/IR；
> 编译器对 `ton` 不可寻址」。**当前事实以本节 §0 正文为准**：`ton` 已登记、可寻址、
> 有 Plan/IR/Tolk/BoC/sandbox；registry maturity 仍为 `source-only`，不得写成 formal/
> hermetic/主网完成。

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

### Portable 候选与当前工程映射

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

### 扩展（后续 CodegenProfile / extension）

消息 op 表、send mode 位图、bounce 格式选择、storage cell schema 版本、get-method 表、
jetton/NFT 等生态消息惯例、GlobalVersion-gated 指令、Acton/Blueprint 脚手架约定。每种
schema 必须 exact 版本化；NetworkProfile 只声明兼容，不定义 schema。MVP 未打开 schedule
destination/send-mode Plan 发射。

## 4. `TonPlan` schema（工程 MVP 已接线）

```text
TonPlan {
  profile,                 -- CodegenProfileId ton-tolk-boc-v1（tolk 1.4.2 工程 pin）
  receivers,               -- op → handler：internal message 分发（32-bit op + query_id）
  storageLayout,           -- c4 扁平 struct cell（MVP 无 dict）
  getMethods,              -- 链下只读方法表
  outActions,              -- emit → external out；schedule destination/send-mode **Plan 仍 FC**
  errorCodes,              -- 稳定 exit / 业务错误码表（100–105/200+）
  events,                  -- external out 日志形状
  bouncePolicy,            -- sandbox 已分阶段观察；产品 Plan 完整 bounce 策略仍后续
  resourceAssumptions      -- gas + cell + max actions(255) 上界（部分工程钉测）
}
```

约束：

- `TonPlan` **不得**复用 `EvmPlan` / `SolanaPlan` / `NearPlan` / 任何 Wasm host Plan。
- 不得把异步消息编码成“伪同步 call + 忽略返回值”。
- renderer 不得回读 `SemanticProgram` 重推业务逻辑；Plan 必须自包含 receiver、layout、
  out-action 与错误表。
- Lean `Targets/Ton/**` 已声明 Plan/IR/emitter；**resolver 开 async ≠ Plan schedule 已 lower**。

## 5. Target IR 与制品

工程路径（已实现）：

```text
TonPlan → Tolk 源码发射 → .tolk → (tolk 1.4.2) → .fif + abi.json + symbolTypes.json
  → companion fift（env 侧，非 tool-root）→ real BoC
  → @ton/sandbox@0.44.0 engineering differential
```

- **Tolk 源码发射**为产品路径；不把手写 TVM 汇编或 FunC 作为默认 IR。
- 制品：`*.tolk`、`.fif`/BoC、`abi.json`、manifest/evidence；Counter e2e
  `deployable=true` + inspect exact closure。
- sandbox 差分是工程门，**不是** 主网/formal/hermetic 完成。

## 6. 工具链

| 工具 | 工程状态（2026-08-03） |
|---|---|
| `tolk` binary | locked **1.4.2**（Tool Lock / Finalize 路径） |
| companion `fift` + libs | env：`PROOF_FORGE_TON_TOOLS` / `PROOF_FORGE_TOLK_STDLIB` / `PROOF_FORGE_FIFT` / `PROOF_FORGE_FIFTLIB`——**不得**放进 tool-root |
| 本地仿真 | `@ton/sandbox@0.44.0` lockfile pin（`runtime-tests/ton` + `scripts/ton_runtime_test.sh`） |
| 脚手架 | Acton 仍为可选生态；未进入 CodegenProfile 强制默认 |

纪律：missing/version mismatch fail closed。sandbox/compile 成功 **不得** 写成 formal
Reference 差分或 Stage-0 证据。

## 7. 部署流程

工程验收（已有部分）与后续：

1. Tolk 编译产物结构门（BoC / ABI 形状）— **已接线**。
2. `@ton/sandbox` 五阶段断言（Counter/EventFlowTon 7/7 工程差分）— **已接线**；**非** formal。
3. Counter：init data cell、内部消息 inc、get-method 读回 — **已接线**。
4. 消息序列 + callback/`query_id` 往返 — **未** 作为完整产品 schedule Plan。
5. bounce / action-fail / exit-code 负例 — sandbox 子集已观察。
6. 可选 testnet 部署 — 未做（network gate；非 Phase 1 工程声明）。

禁止把“Tolk 编译成功”或“sandbox 通过”写成部署、主网或 formal 完成。

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
Tolk compile (结构/ABI)                    ✅ 工程
  → sandbox Counter (c4 + 单消息 + get-method)  ✅ 工程（TON-3）
  → 消息序列 / callback + query_id             ⏳ Plan schedule 仍 FC
  → bounce / exit-code / action 上限负例      ⚠️ sandbox 子集
  → 可选 testnet evidence                     ❌
```

每一级独立 fail closed；上级通过不蕴含下级。sandbox/compile **不是** formal Reference
差分或 hermetic Stage-0。

## 10. 不支持、风险与成熟度退出

### 当前明确不支持 / fail closed

- 同步跨合约 `call`（resolver + Plan 双 FC）。
- **Plan-level `schedule` 发射**（resolver 开 async，destination/send-mode 未接线 → Plan FC）。
- multi-width UInt8..256、named Struct/Enum、Array/Map/Bytes/Option、Field/Principal/String、
  ContextRead/Commit、nonempty invariants/constants、masterchain/library/extra currencies。
- FunC/Tact 默认发射、手写 TVM 汇编产品路径。
- formal Reference 差分、主网 deploy 证据。

### 风险

- GlobalVersion / codepage 演进导致指令面漂移。
- resolver async open 与 Plan schedule FC 的 **capability mismatch** 必须诚实写清，禁止
  写成“跨合约 async 已完成”。
- Cell/dict 布局一旦在生态中“约定俗成”却未写入 Plan，会造成 layout confusion。
- Sandbox 与主网 GlobalVersion 不一致导致假绿。

### 成熟度边界

- 工程 MVP **已** 使 `ton` 可寻址并产出 BoC + sandbox 差分；registry maturity 标签仍为
  **`source-only`**（不在本切片改 wire label）。
- Static dossier ceiling 保持 **`research`**；工程 sandbox/compile **不得** 升 formal
  `specified`/`prototype` 或冒充 Stage-0。
- formal maturity 升格仍要求独立 evaluator / gate catalog 路径（不在本用户侧文档切片）。
