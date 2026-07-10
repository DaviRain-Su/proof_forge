# 链无关(chain-agnostic)缺口分析 —— 从现在到"完全不考虑链"还差什么

> 目标:开发者写合约时**完全不碰任何链概念**(NEAR 跨合约、Solana CPI、EVM call、各链 host
> runtime、token 标准……全被抽象掉)。本文按组件层盘点 **已完成 / 部分 / 缺失**,并把缺口分成
> **两堆**:①**机械缺口**(枚举 + 物化 + 诚实拒绝,有现成机器能磨)②**根本性语义冲突**(链之间
> 真的不一致,必须做设计决策,papering 不过去)。**②才是风险所在——Move 当年就是在这些点上分裂的。**
>
> 非权威原生中文分析(见 [README](README.md))。配套:[产品内核 north-star](product-north-star.md)。

## 判断准则:一个概念要么"抽象+物化",要么"诚实拒绝"

"完全链无关"= 每一处链概念泄漏,都必须被:**(a) 抽象成便携词汇 + 各链物化**,或 **(b) 诚实拒绝**
(preflight reject,而不是静默生成错代码)。项目已有这套机器(capability + Preflight + HostRuntime
honesty reject);缺的是把还没抽象的概念灌进去,以及解决几个抽象不了、只能设计取舍的硬骨头。

## 一、核心计算 & 状态 —— 基本 DONE

| 组件 | 状态 | 说明 |
|---|---|---|
| 算术/位运算/比较/布尔/cast/控制流/类型 | ✅ | IR 已覆盖(含 checked overflow node 字段) |
| 存储 scalar / map / array / struct / dynamic | ✅ | capability `storageScalar/Map/Array/…` |
| **可迭代集合**(有序 map、set、分页遍历) | ❌ **缺** | 各链差异极大(EVM 无原生迭代;Solana 账户;NEAR trie);DeFi/NFT 常用 |
| **定点数 / decimals**(fixed-point) | ✅ **已落地** | `Contract/FixedPoint.lean`(scale / rescale / mulScaled; decimals 0–18) |

## 二、你点名的三块

### (A) 跨合约调用 —— PARTIAL→策略已锁(step 3)

- **已有**:便携面 `declareRemote` / `remoteCall` / `remoteCallRef`(逻辑 peer,不碰 host 池索引)→
  物化到 EVM call / Solana CPI / NEAR promise;Solana CPI 账户打包、PDA signer seeds、SPL-token
  `initialize_account3/mint` 都真跑通;honesty reject 已制度化。
- **✅ 同步子集策略已锁定**:`CrosscallMaterialize.portableCrosscallPolicy = syncRequestResponseOnly`;
  `requireSyncSubset` 拒绝 `nearPromiseThen` / `promise_result*`(逃生口仍可用但**非** portable 产品路径)。
  NEAR portable remote → `promise_create` only(同 receipt 无返回值)。**不做**便携 continuation 模型
  (plan non-goal)。
- **✅ Solana 账户推断(portable remotes)**:`inferSolanaAccounts` + `materializeSyncRemote`——作者
  **不传** account metas;从 peer + module.state 推断(含 SPL peer 的 token 程序/ATA 占位)。
  动态/未知 peer 空 id → 诚实拒绝。更细的 CPI packing 仍在 Backend.Solana。
- **机械缺口(仍)**:类型化返回值 decode、多目标返回 ABI 统一;NEAR 同 receipt 同步返回值。

### (B) Host runtime 环境方法 —— PARTIAL,词汇是 EVM 味的(这块你要的 plan 设计)

- **已有**:`ContextField`(15 个:userId/timestamp/epochHeight/chainId/gasPrice/gasLeft/baseFee/
  prevRandao/coinbase/origin/blockHash…)+ `Target/HostRuntime.lean` 统一 catalog(opcode/syscall/
  host-import 一张表,带 n/a honesty reject)。
- **问题**:`ContextField` **是 EVM 味的**——`gasPrice/baseFee/prevRandao/coinbase/origin` 全是 EVM
  概念,不是链无关词汇。
- **建议的 plan 设计(在 `HostRuntime.lean` 上,把 `ContextField` 重表达成便携 `HostEnv`,分三桶):**

  | 桶 | 语义 | 便携词汇 | 各链物化 |
  |---|---|---|---|
  | **1 通用**(每链都有) | 直接映射 | `blockTime` / `blockHeight` / `chainId` / `caller` / `selfAddress` / `attachedValue` | EVM `block.timestamp/number`·`msg.sender`;NEAR `block_timestamp/block_index`·`predecessor`;Solana `Clock.unix_timestamp/slot`·signer |
  | **2 近似**(语义相近、单位/名不同) | 映射 + 语义注记 | `epoch` / `gasOrComputeBudgetLeft` / `blockHash` / `randomness` | EVM `gasleft`↔Solana compute-units↔NEAR prepaid_gas;EVM `prevRandao`↔Solana slot-hash↔NEAR `random_seed` |
  | **3 链专属** | 诚实拒绝 / opt-in 扩展 | `coinbase`·`baseFee`·`tx.origin`(EVM);Solana rent/sysvar;NEAR signer≠predecessor | 缺该概念的链上 **reject**(或像 `Source.Solana` opt-in) |

  即:一个便携 `HostEnv` 枚举 + `materializeEnv : Target → HostEnv → Except Reject Lowering` 表。
  `HostRuntime.lean` 是它的家;`ContextField` 应改写成建在它之上。
- **✅ 已落地(step 1)**:`ProofForge.Target.HostRuntime.HostEnv` + 三桶 +
  `materializeEnv` / `requireHostEnv`。**诚实规则**:只有该 target 已有真实 lower/host
  路径才 `.ok`(例如 NEAR `chainId` / `gasLeft` **拒绝**,不别名 `block_index` / 不发明
  `sol_get_cluster`)。IR `ContextField.toHostEnv` 桥接;测试覆盖 triad 矩阵。
  文档:[host-runtime.md](../host-runtime.md) §8 HostEnv。后续:把更多 lower 路径强制走
  `materializeEnv`;补 Solana timestamp/self 与 NEAR chainId 等 lower。
- **✅ 身份冲突(step 2)**:`Target/Identity.lean` `materializeIdentity`——EVM-20 / Sol-32 /
  NEAR 命名账户;作者面统一 `ValueType.address` / `Address`。

### (C) Token —— FORMING→auth feature 已锁(step 4)

- **已有**:`Contract/Token.lean` `TokenStandard` + `TokenFeature`;示例与各链客户端。
- **✅ 授权模型 feature flag**:`Contract/TokenAuth.lean`——`allowance`(EVM) /
  `authority`(SPL) / `storageDeposit`+`transferCall`(NEP-141);跨 host **诚实拒绝**(无假
  allowance 上 NEP-141)。Core `transfer`/`balanceOf` 常开;`mint`/`burn` **capability-gated**
  (`TokenFeature.mintable` / `burnable`)。
- **✅ 定点**:`Contract/FixedPoint.lean`。
- **仍缺**:NFT/多 token 全家桶;Token/ 路径仍偏 EVM codegen。

## 三、你问的"还差哪些组件"(其余轴)

| 组件 | 状态 | 缺口 / 冲突 |
|---|---|---|
| ④ 访问控制 / auth | PARTIAL | Ownable/AccessControl/roles 在长;需统一角色模型 + 链原生 auth + 多签 |
| ⑤ **身份 / 地址** | ✅ **catalog 已落地** | `Target/Identity.lean` materialize-or-reject;Solana `self` 仍 reject 至 program-id lower |
| ⑥ 升级 / 生命周期 | ✅ **intent 已落地** | `UpgradePolicy.materializeUpgrade`：EVM v0 的 product authority/governance 均诚实拒绝（UUPS 仅 backend transport spike，尚未绑定 `keyRef`）；Solana upgrade-authority；NEAR redeploy+migrate |
| ⑦ value / 原生币 | PARTIAL | `valueNative` / HostEnv.attachedValue;余额查询仍粗 |
| ⑧ crypto | ✅ **首批 catalog** | `PortableMechanics`:keccak/sha256 triad;ecrecover EVM-only;ed25519 Sol/NEAR |
| ⑨ 错误模型 | ✅ **首批 catalog** | `mech.error.code` / `message` triad materialize |
| ⑩ 序列化 / ABI | ✅ **首批 catalog** | abi EVM / borsh Sol(+NEAR) / json NEAR;跨 host 拒绝 |
| ⑪ 事件 / 日志 | 基本 DONE | `eventsEmit` 有;indexed/topic 语义各链不同,需注记 |
| ⑫ 时间 / 随机 | PARTIAL | HostEnv `randomness` untrusted 注记;VRF 未做 |
| ⑬ 资源计量 / gas | PARTIAL | HostEnv `gasOrComputeBudgetLeft` EVM-only materialize;其余 reject |

## 四、最有用的结论:把缺口分两堆

### 堆 1 —— 机械缺口(纯 plumbing,有现成机器,是"工作量"不是"风险")

大多数 host-env 方法、存储、事件、错误、序列化、crypto hash、部署、gas 计量。**用你已有的
`HostRuntime catalog + capability + Preflight reject` 这台机器,逐个枚举 + 物化 + 诚实拒绝即可。**
这是剩余组件的大头,可并行、可交给 agent 批量磨。

### 堆 2 —— 根本性语义冲突(必须做设计决策,plumbing 绕不过去)

**这五个是愿景成败的关键点(Move 正是在这些点上分裂的):**

1. **同步 vs 异步调用(NEAR)** —— #1 难。定策略:同步子集 only(拒绝异步)还是便携 continuation 模型。
2. **Solana 账户模型** —— 必须预声明账户;编译器要从逻辑推断账户集(已部分)。
3. **地址 / 身份模型** —— 20 字节 / 32 字节 / 命名账户;需便携 `Address` 类型。
4. **Token 授权/权限模型** —— 无公共分母;用 feature flag 建模分歧。
5. **升级模型** —— proxy vs upgrade-authority vs 重部署。

**这五个每一个都不是"多写代码",而是"选一个语义契约,并让不满足的链诚实拒绝"。**

## 五、到"真正完成"的建议路线

1. **✅ HostEnv 去 EVM 化 + 管线** — `materializeEnv` 由 `PortableHonesty` 在
   `resolveSpec` 对 primary triad 强制;无真实 lower → 拒。
2. **✅ Identity 管线** — `materializeIdentity` 挂 resolve;Solana `self` 拒;EVM/NEAR ok。
3. **✅ 跨调同步子集 + 账户推断进 schema** — portable 禁混 promise_then;Solana **空 peer 拒**;
   `inferSolanaAccounts` 合并进 `Manifest.ensurePortableCrosscallAccounts`（进 AccountEntry,
   非仅 note）;`materializationNote` 列出 `inferredAccounts=[…]`。
4. **✅ Token planForTarget** — FixedPoint;mint/burn 门控;`TokenSpec.authFeatures` 走
   `materializeAuth`（NEAR 拒 allowance）。
5. **✅ 升级 resolveSpec** — EVM product authority/governance 拒绝；UUPS 仅 backend transport spike；Solana authority / NEAR redeploy。
6. **✅ 机械堆挂管线** — `requireMechanicsHonesty` 在 resolveSpec 调 `materializeMechanic`
   （crypto.hash / ecrecover / assertions→errorCode）;可迭代集合/NFT 仍缺。
7. **✅ FV/诚实测试** — `Tests/ChainAgnosticRoute.lean` 驱动 resolveSpec/plan/ensurePortableCrosscallAccounts。

**仍 remaining（未 ✅）:** 可迭代集合;NFT 全家;NEAR continuation;Solana self/timestamp lower;
非 triad HostEnv 行;transparent proxy lower。

## 六、一句话

> **机械堆是"工作量",有现成机器,可并行磨;真正决定成败的是那 5 个根本性语义冲突(同步/异步、
> Solana 账户、地址、token 授权、升级)——它们要的是设计取舍 + 诚实拒绝,不是多写代码。** 先做
> host-env 去 EVM 化 + 便携 Address 两个高杠杆前置,再逐个啃那 5 个硬骨头,机械堆交给 agent 批量推。
