---
id: RPT-OZ-EVM-COVERAGE-001
title: OpenZeppelin v5.7.0 与 ProofForge EVM 行为能力覆盖审计
status: draft
owner: research
updated: 2026-08-03
normative: false
---

# OpenZeppelin v5.7.0 与 ProofForge EVM 行为能力覆盖审计

> 核心问题：以 OpenZeppelin Contracts v5.7.0 的生产模块为行为能力基线，ProofForge 当前统一
> `program` → `SemanticProgramV1` → EVM 产品路径能等价表达、物化并在真实 EVM 上验证哪些能力，
> 还缺哪些能力，以及是否需要逐个重写 OpenZeppelin 合约？

本报告是非规范性比较研究，不是新的工程 gap authority。可执行缺口仍须回写
[`11-feature-coverage-audit.md`](11-feature-coverage-audit.md)、
[`12-target-coverage-matrix.md`](12-target-coverage-matrix.md) 与
[`../engineering-backlog.md`](../engineering-backlog.md)。报告不改变 formal `TASK-*` 状态、
SupportClaim、EVM maturity 或产品范围。

## 1. 结论先行

### 1.1 不应逐文件、逐继承图重写 OpenZeppelin

**不需要，也不建议把 OpenZeppelin 的 248 个生产 `.sol` 文件或 112 个稳定实现声明逐个对等实现。**

更合适的产品模型是：

1. 把 OpenZeppelin 固定版本当作 **Ethereum 行为压力语料和 oracle**，而不是源码兼容清单或产品依赖。
2. 在共享语义与 EVM profile 中实现少量、版本化、可精确验证的 primitive，例如 caller/address、
   mapping、动态调用、payable/value、crypto 和动态 ABI。
3. 用代表性 vertical slice 证明这些 primitive 能组合成标准行为；只有通过独立标准 corpus 的 ERC/EIP
   才能声明该标准兼容。
4. 对未支持能力继续 fail closed，不以“可以手写近似逻辑”“Yul 能编译”或“Reference 能执行”冒充
   Ethereum 行为等价。

“Ethereum 上所有已有 contract”没有稳定、有限的分母；任意 assembly、历史 hardfork、precompile、
proxy 技巧和外部协议都可以继续扩张它。因此本项目不应发布“覆盖 Ethereum 合约 X%”或“支持所有
Ethereum 合约”的声明。可审计的承诺应写成：

> 在固定的 EVM profile、hardfork、ABI 与 corpus 版本下，ProofForge 精确支持哪些 primitive、
> observable scenarios 和 ERC/EIP；其余能力确定性拒绝。

### 1.2 当前严格结果：20 个族全部 `Blocked`

本报告采用严格的 **当前 OpenZeppelin-family behavior compatibility** 轴。每个 family 必须先冻结
非空、版本化的 required-scenario set 和 residual-blocker list，状态才可迁移：

- `Exact`：required-scenario set 全部通过 `ReferenceV1 ↔ PF EVM ↔ pinned OZ` 所要求的 legs，
  且该 family 的行为 residual 为空。
- `Partial`：required-scenario set 中有严格非空子集通过 `oz-behavior` 或 `abi` case，
  但仍有未通过场景且 residual 非空。
- `Blocked`：当前没有任何可计入 family 状态的 `oz-behavior`/`abi` 场景；不表示所有底层 primitive
  都不存在。
- `Out-of-scope`：只有已接受的产品决策才能使用；研究建议不算已接受边界。

四个状态互斥。`primitive` 和 `adapter` case 可以证明工程进展，但不改变 family 状态；ABI 与标准兼容
仍是独立轴，只有 `abi` case 能改变相应 ABI/standard claim。这样一个 green `transfer` 场景不能同时把
ERC20 计作 `Exact`，也不能用非标准 Token adapter 计作 `Partial`。

按此口径，当前结果是：

| 状态 | 族数 |
|---|---:|
| `Exact` | 0 |
| `Partial` | 0 |
| `Blocked` | **20** |
| 已接受 `Out-of-scope` | 0 |

这里的两个容易误判点是：

- `Examples/Token.lean` 的 UInt64、dense Map cap-8 账本是有价值的 primitive/adapter pilot，
  **不是 ERC-20 Partial**：它没有 address/caller、标准 mapping/allowance、标准 ABI 或 indexed `Transfer`。
- 普通 Bool state 可以表达 pause/guard 标志，但仓库没有执行过 OpenZeppelin-compatible
  Pausable/Reentrancy 场景，且重入 oracle、callback 和 transient storage 仍缺，因此共享 mixin 族也仍是
  `Blocked`。

Proxy、ERC-4337 Account、Paymaster、ERC-7786/cross-chain 是强烈的当前范围外候选，但在产品决策接受前，
事实状态仍是 `Blocked`，不能把建议写成既成政策。

### 1.3 Family 状态不是唯一进度轴

为了避免“先补 primitive 但 20-family 表仍全红”被误读为零进展，后续应同时展示多层、互不代签的
scorecard：

| Scorecard | 当前事实 | 何时变化 |
|---|---|---|
| Engineering substrate | shared semantics 已有整数/聚合/control/effect/Reference；EVM 已有 Plan/Yul/solc primitive 子集 | `primitive` case 或 target gate 通过即可增加，不产生 OZ claim |
| OZ family behavior | `Exact 0 / Partial 0 / Blocked 20` | 只有 `oz-behavior`/`abi` required case 可改变 |
| ABI/standard | 当前没有 OZ/ERC claim | 只有无 adapter 的 `abi` corpus 可改变 |
| Runtime revalidation | 历史工程 Anvil fixtures 存在；本次 HEAD 被 Tool Lock 前置阻断 | fixed Tool Lock + hardfork 后重跑才可记当前 pass |

因此 Ownable-like 的 Reference↔PF Anvil vertical 本身先增加 engineering scenario 证据；再加入 pinned OZ
行为 oracle 且不丢弃授权/revert/state 等语义字段后，F01 才可进入 `Partial`。标准 ABI 仍需独立 `abi` case。

## 2. 基线、分母与方法

### 2.1 固定语料

- 上游：OpenZeppelin Contracts `v5.7.0`
- commit：`cab19933c33c2ad1d4c7a84864a3601dddfd16f3`
- 纳入：`contracts/` 下生产源码、官方 Hardhat/Foundry tests，以及行为复用文件
- 排除：`contracts/mocks/**`、历史版本、测试辅助合约的逐个移植、Solidity 源码/继承/assembly 兼容
- ProofForge 观察基线：本次审计时 HEAD `31e271474c85e18fb345fe709694dbd069cd8893`

文件数不是行为覆盖率。本报告同时保留多个分母，各自只回答一种问题：

| 分母 | 数量 | 用途 |
|---|---:|---|
| `contracts/**/*.sol` | 368 | 上游文件系统总量 |
| `contracts/mocks/**/*.sol` | 120 | 被排除的测试辅助源码 |
| 生产 `.sol` | **248** | 固定供应链语料，不作覆盖百分比 |
| 实现声明（abstract + concrete） | 119 | 行为实现对象 |
| 稳定实现声明 | **112** | 本报告 20-family 划分对象 |
| draft 实现声明 | 7 | 单列实验面，不进入稳定族状态 |
| library 声明 | 64 | primitive/算法能力语料，不与应用实现等权 |
| interface 声明 | 74 | ABI/标准目录，不与实现等权 |
| import-only re-export 文件 | 11 | 行为权重为零 |
| 行为族 | **20** | 管理与状态汇总分母 |

完整的 112 对象归属保存在
[`openzeppelin-v5.7.0-family-membership-v1.json`](openzeppelin-v5.7.0-family-membership-v1.json)：

- 规则：去注释后扫描顶层 `abstract contract`/`contract`，排除 mocks、interface、library 与 `draft-*`，
  以有序 path-prefix 规则分族，再按 `path::declaration` 排序。
- stable objects：112；draft objects：7；families：20。
- duplicate：0；unassigned：0。
- membership-set SHA-256：
  `549ae7d95f8ea56e14e78dad271156847df41c2387db7addeb3484913be6a122`。
- tracked manifest exact-byte SHA-256：
  `cc416aefc9cbf184c5c3464cf5fa8d6396054258a0e05442cfb0fb1f85333b6b`。

该划分是可复核的研究 heuristic，不是 Solidity compiler AST，也不表示每个对象等权。

### 2.2 五个兼容轴必须分开

| 轴 | 本报告结论 |
|---|---|
| Solidity source compatibility | 明确排除；ProofForge 不是 Solidity frontend |
| Primitive coverage | 由 op/type/context/effect × EVM target 的精确矩阵与 SupportClaim 管理 |
| Observable behavior equivalence | 本报告的主要目标；比较返回、state、logs、revert、external effects 与 rollback |
| ABI compatibility | 独立、profile-owned、需逐标准验证；当前没有 OZ/ERC ABI 兼容声明 |
| Standard conformance | 默认无；每个 ERC/EIP 必须有版本化 claim 与独立 corpus |

“可以用不同源码写出相似业务逻辑”不等于 ABI 或标准兼容。反过来，缺少 Solidity 继承/modifier
语法也不必然阻止行为等价：只要语义 primitive 足够，normalizer 可以把组合后的业务行为直接表达出来。

### 2.3 研究执行与证据等级

本次研究完成 4 轮并行探索，每轮均覆盖上游语料、ProofForge 分层实现、最小反例和验证设计；
第 4 轮后的独立 verifier 要求把 20-family 台账与结论从 scratch 提升为受审计文档。本报告与 tracked
manifest 完成该闭环后，另一名 fresh read-only verifier 对正式工件返回 `PASS`。

证据等级在本报告中严格区分：

- `static-reviewed-OZ`：阅读了固定 commit 的源码和官方测试，但未执行上游 test runner。
- `executed-PF-focused`：执行了聚焦 Lean/Wire/EVM 工程 suites。
- `tool-blocked`：当前产品/Anvil 路径被 Tool Lock 一致性错误提前阻断。
- `proposal`：测试 schema/case 设计尚未落入仓库，不能写成现有 gate。

## 3. OpenZeppelin 暴露的 Ethereum 能力面

OpenZeppelin 的价值不在文件数量，而在它把许多 Ethereum 运行时原语组合成可观察协议：

1. **身份与授权**：`msg.sender`、20-byte address、owner/role/admin、trusted forwarder。
2. **状态结构**：Solidity mapping、nested/compound keys、动态数组、EnumerableSet、Checkpoints、
   allowance/approval/delegation 历史。
3. **原生资产与上下文**：payable、`msg.value`、contract/account balance、receive/fallback、timestamp、
   block number/hash、chainid、basefee、`address(this)`、code length。
4. **调用与部署**：动态 target `CALL`、`STATICCALL`、`DELEGATECALL`、value、raw calldata、exact returndata、
   revert bubbling、receiver callback magic、`CREATE`/`CREATE2`/`CREATE3`。
5. **ABI 与观察面**：address/bytes4/bytes/string/dynamic arrays/nested structs、indexed events、custom errors、
   ERC165、fallback/receive。
6. **密码学与 precompile**：user-visible keccak、EIP-712/191、ecrecover、ERC1271/ERC7913、P256、RSA/modexp、
   SHA-256、Merkle/Trie/WebAuthn。
7. **精确 EVM 状态机制**：ERC-1967/ERC-7201 slots、proxy storage aliasing、transient storage、extcodecopy、
   hardfork-sensitive opcode 行为。
8. **外部协议宿主**：ERC-4337 EntryPoint、paymaster lifecycle、ERC-7786 gateway/bridge、remote executor。

其中 math、SafeCast、nonces、pause flag、队列、集合、checkpoint 算法和 Merkle fold 等可以在基础 primitive
齐备后重写；caller/value/call/delegate/create/raw calldata/precompile/外部 host 等则是不可用纯业务逻辑替代的
运行时语义。

## 4. ProofForge 当前真实能力边界

### 4.1 已有且有价值的基础

当前共享 Source/Typed/Normalize/Reference 已覆盖相当强的静态业务子集：

- Bool、UInt/Int 8..256、checked arithmetic、比较、bitwise/shift、bn254 Field 子集。
- fixed Array/Bytes、Map、Option、Struct、Enum、String 与 Principal wire identity。
- state、entry/view/init、不可变 let、if/match、静态 bounded for、pure local functions。
- assert/revert/emit、static qualified call/schedule、constants、invariants、ContextRead/Commit shared semantics。
- Reference machine 有 overlay rollback、ordered effects、external response cursor，并能解释
  `context.caller` 与 `context.unixTimeSeconds`。

EVM target 也不是空壳：它有 target-owned Plan/IR、Yul/ABI、locked solc finalize、checked arithmetic、
多宽整数、固定聚合、named aggregate flatten、fixed Array/Bytes、UInt64→UInt64 dense Map cap-8、
bn254 Field、control flow、bounded loop、static-QN call/schedule 和工程 Anvil fixtures。

这些能力足以证明编译链和若干 primitive，但不足以推出任何 OpenZeppelin family 兼容。

### 4.2 决定性边界

| 层 | 当前事实 | 对 OZ/Ethereum 的影响 |
|---|---|---|
| Type/identity | `Principal` 是 opaque wire identity；EVM 以 `len + 8×UInt64` 保存，不是 20-byte address | 不能替代 owner、spender、receiver 或标准 address ABI |
| Context | shared Reference 支持 caller/time；EVM `LowerSemanticV1` 对两种 `ContextRead` 都显式 fail closed | Ownable、tokens、vesting、timelock 等在 target Plan 前被阻断 |
| Value/payable | dispatcher 与 constructor 都生成 `if callvalue() { revert(0, 0) }` | 不能 receive ETH、读 `msg.value`、按 value 调用或核对余额 |
| Map | EVM 仅 dense cap-8 `Map UInt64 UInt64` | 不是 Solidity keccak mapping；无 address/UInt256/nested allowance map |
| ABI | EVM 入口/结果已含 UInt8..256、Int8..64、Bool、bn254 Field、named Struct/Enum 扁平（结果≤8 leaves）以及 String/Principal 自定义 leaves | 仍无标准 `address`、dynamic `bytes`/`string`/array/tuple ABI；Int128/256 与 anonymous-container 返回继续 FC |
| Events/errors | EVM emitter 使用 `log1(topic0)`，所有字段写 static UInt64 data；error 同样是 UInt64 words | 无 indexed address topics，也无标准 address/string error payload |
| External call | Semantic op 无返回 SSA；EVM target 是 static QN→hashed address、value=0、UInt64 args、returndata ignored | 不能实现 safe receiver、SafeERC20、timelock、proxy、AA 等调用契约 |
| Crypto | closed `SemanticOpV1` 没有 user keccak/ecrecover/SHA/precompile op | EVM `Keccak.lean` 只服务 selector/topic/static address，不能算用户 crypto |
| Storage/deploy | 无 dynamic mapping layout、exact reserved slots、delegate/create/transient/extcode surface | proxy、clone、UUPS、transient guard 被阻断 |
| Constants/invariants | EVM Plan 对 nonempty tables仍 fail closed | shared 层存在不等于 target 已物化 |

Map 容量以实际定义 `evmMapPilotCapacityV1 := 8` 为准；相邻源码注释仍残留 “Capacity 12”/“16×”
旧文字，不能把该注释当作能力证据。

关键代码证据：

- `ProofForgeV2/Semantic/Wire/ModelV1.lean`：closed `TypeShapeV1` 与 `SemanticOpV1`；
  `externalCall`/`schedule` 是 void effect，没有 crypto/delegate/create op。
- `ProofForgeV2/Semantic/ReferenceMachineV1.lean`：caller/time、void external responses、rollback 与
  Commit identity 语义。
- `ProofForgeV2/Targets/Evm/LowerSemanticV1.lean`：Principal 非 address、Map cap-8、
  `context.caller`/timestamp fail-closed、constants/invariants fail-closed。
- `ProofForgeV2/Targets/Evm/EmitIRV1.lean`：callvalue rejection、`log1` UInt64 event、static hashed-address
  `CALL(..., value=0, ..., out=0)`。
- `ProofForgeV2/Targets/Evm/ValidateIRV1.lean`：当前只是 bounded structural gate，不是完整 Yul parser 或
  formal semantic equivalence gate。

## 5. 20-family 状态总表

`Blocked` 表示“当前没有通过的 OZ-compatible runtime scenario”，并不否定相关 primitive 的存在。

| ID | OpenZeppelin family | 稳定对象 | 当前状态 | 最小决定性原因 |
|---|---|---:|---|---|
| F01 | Ownable / roles | 5 | `Blocked` | EVM caller/address；role map；address logs/errors |
| F02 | AccessManager | 2 | `Blocked` | caller/address、timestamp、selector policy、dynamic call/value |
| F03 | ERC20 family | 12 | `Blocked` | caller/address、scalable balances/allowance、standard ABI、indexed `Transfer` |
| F04 | ERC721 | 11 | `Blocked` | address ownership/approval、dynamic bytes、receiver callback returndata |
| F05 | ERC1155 | 7 | `Blocked` | owner×id map、dynamic batch arrays、safe callback |
| F06 | ERC6909 | 4 | `Blocked` | owner×id/spender maps、address ABI/events |
| F07 | ERC2981 royalties | 1 | `Blocked` | address return + ERC165/bytes4 interface |
| F08 | Vesting | 2 | `Blocked` | target timestamp、payable/balance、native/ERC20 value transfer |
| F09 | Governor / Timelock | 19 | `Blocked` | clock/checkpoints/signatures、dynamic multi-call/value |
| F10 | Votes | 2 | `Blocked` | address delegation、checkpoints/clock、signature flow |
| F11 | Proxy / upgradeability | 8 | `Blocked` | raw fallback、`DELEGATECALL`、exact slots、create；OOS 候选 |
| F12 | ERC4337 Account | 1 | `Blocked` | EntryPoint、value/prefund、dynamic UserOp、crypto；OOS 候选 |
| F13 | Paymaster | 5 | `Blocked` | EntryPoint lifecycle、deposit/value、token/crypto/dynamic ABI；OOS 候选 |
| F14 | ERC2771 | 2 | `Blocked` | raw calldata suffix sender rewrite、caller/address、forwarder crypto |
| F15 | Cross-chain / ERC7786 | 10 | `Blocked` | gateway host、caller、dynamic payload、remote execution；OOS 候选 |
| F16 | Shared mixins | 7 | `Blocked` | 没有 OZ-compatible scenario；callback/transient/raw multicall 仍缺 |
| F17 | Signers | 9 | `Blocked` | user crypto/precompile、address/code、dynamic signature bytes |
| F18 | Verifiers | 3 | `Blocked` | P256/RSA/WebAuthn precompile/modexp 与 dynamic proof bytes |
| F19 | EIP712 | 1 | `Blocked` | user keccak、chainid、`address(this)`、domain separator ABI |
| F20 | ERC165 introspection | 1 | `Blocked` | bytes4/standard interface ABI 与 selector claim 尚无 |

## 6. 逐族证据台账

下表中的 OZ 测试路径均来自固定 commit，状态都是 `static-reviewed-OZ`，**未在本次审计执行**。
“PF 首个 blocker”只列最早足以否定当前兼容声明的边界；后续 residual 仍必须保留，不能因补一个 primitive
就把整族标为完成。

| ID | 代表 OZ 源码 | 官方 test/behavior | 建议场景 ID | PF 首个 blocker 与 residual |
|---|---|---|---|---|
| F01 | `contracts/access/Ownable.sol` | `test/access/Ownable.test.js` | `oz.f01.ownable.onlyowner.blocked.v1` | `Evm/LowerSemanticV1` 拒绝 `context.caller`；Principal 非 address；仍需 ownership event/error ABI |
| F02 | `contracts/access/manager/AccessManager.sol` | `test/access/manager/AccessManager.test.js` | `oz.f02.accessmanager.delayed-execute.blocked.v1` | caller/time 均未物化；static-QN void CALL 不能执行 runtime target/value/calldata |
| F03 | `contracts/token/ERC20/ERC20.sol` | `test/token/ERC20/ERC20.behavior.js` | `oz.f03.erc20.transfer.blocked.v1` | 无 caller/address；EVM Map 仅 cap-8 UInt64→UInt64；`log1` 无 indexed sender/receiver；allowance residual |
| F04 | `contracts/token/ERC721/ERC721.sol` | `test/token/ERC721/ERC721.behavior.js` | `oz.f04.erc721.safe-transfer.blocked.v1` | 无 address owner/approval；call 无 returndata/code check/dynamic bytes，不能验证 receiver magic |
| F05 | `contracts/token/ERC1155/ERC1155.sol` | `test/token/ERC1155/ERC1155.behavior.js` | `oz.f05.erc1155.safe-batch.blocked.v1` | 无 address×id state 与 dynamic batch ABI；safe callback/returndata residual |
| F06 | `contracts/token/ERC6909/ERC6909.sol` | `test/token/ERC6909/ERC6909.behavior.js` | `oz.f06.erc6909.transfer-from.blocked.v1` | 无 owner×id/spender compound map、caller/address 与标准 topics |
| F07 | `contracts/token/common/ERC2981.sol` | `test/token/common/ERC2981.behavior.js` | `oz.f07.erc2981.royalty-info.blocked.v1` | 无 20-byte address return ABI；ERC165 bytes4 surface 同时缺失 |
| F08 | `contracts/finance/VestingWallet.sol` | `test/finance/VestingWallet.behavior.js` | `oz.f08.vesting.native-release.blocked.v1` | EVM timestamp ContextRead fail closed；所有入口拒绝 callvalue；无 balance/value CALL |
| F09 | `contracts/governance/Governor.sol` | `test/governance/Governor.test.js` | `oz.f09.governor.execute-batch.blocked.v1` | fixed Array/Bytes 不能承载动态 targets/values/calldatas；clock、signature、dynamic CALL residual |
| F10 | `contracts/governance/utils/Votes.sol` | `test/governance/utils/Votes.behavior.js` | `oz.f10.votes.delegate-checkpoint.blocked.v1` | 无 address/caller；无 scalable checkpoint history/clock；signature delegation residual |
| F11 | `contracts/proxy/Proxy.sol` | `test/proxy/Proxy.behaviour.js` | `oz.f11.proxy.fallback-delegate.blocked.v1` | closed Semantic op 无 fallback/raw calldata/DELEGATECALL；无 exact returndata、ERC-1967 slots 或 create |
| F12 | `contracts/account/Account.sol` | `test/account/Account.behavior.js` | `oz.f12.erc4337.validate-userop.blocked.v1` | 无 EntryPoint host、dynamic UserOp ABI、prefund/value 与 signature op |
| F13 | `contracts/account/paymaster/Paymaster.sol` | `test/account/paymaster/Paymaster.behavior.js` | `oz.f13.paymaster.validate-postop.blocked.v1` | 无 EntryPoint lifecycle/deposit/value；token/crypto/dynamic context residual |
| F14 | `contracts/metatx/ERC2771Context.sol` | `test/metatx/ERC2771Context.test.js` | `oz.f14.erc2771.forwarded-sender.blocked.v1` | 无 raw calldata suffix或 EVM caller；不能在 trusted-forwarder 条件下重写 logical sender |
| F15 | `contracts/crosschain/ERC7786Recipient.sol` | `test/crosschain/ERC7786Recipient.test.js` | `oz.f15.erc7786.receive-message.blocked.v1` | 无 gateway host/caller authentication、dynamic payload、remote target execution |
| F16 | `contracts/utils/ReentrancyGuard.sol` | `test/utils/ReentrancyGuard.test.js` | `oz.f16.reentrancy.callback.blocked.v1` | 可手写 flag 但无 OZ runtime case；static void CALL 不能建立重入 counterparty；transient variant 无 TSTORE/TLOAD |
| F17 | `contracts/utils/cryptography/signers/SignerECDSA.sol` | `test/account/AccountECDSA.test.js` | `oz.f17.signer.ecdsa.blocked.v1` | closed Semantic op 无 keccak/ecrecover/ERC1271 code path；signature bytes/address ABI 缺失 |
| F18 | `contracts/utils/cryptography/verifiers/ERC7913P256Verifier.sol` | `test/account/AccountERC7913.test.js` | `oz.f18.verifier.p256.blocked.v1` | 无 P256/RSA/modexp/WebAuthn precompile surface与 dynamic proof bytes |
| F19 | `contracts/utils/cryptography/EIP712.sol` | `test/utils/cryptography/EIP712.test.js` | `oz.f19.eip712.domain-hash.blocked.v1` | 无 user keccak、chainid、`address(this)`；target-owned selector Keccak 不能替代业务 hash |
| F20 | `contracts/utils/introspection/ERC165.sol` | `test/utils/introspection/ERC165.test.js` | `oz.f20.erc165.supports-interface.blocked.v1` | EVM ABI 无 bytes4/interface-id profile；没有已验证 selector→Bool 标准场景 |

### 6.1 十个最小反例

以下场景足以说明为什么当前“相似逻辑”不能升级为兼容声明：

| 场景 | 最早阻断点 | 为什么近似不等价 |
|---|---|---|
| Ownable `onlyOwner` | EVM caller ContextRead FC | 外部参数注入 owner 不能替代真实 `msg.sender` |
| ERC20 `transfer` | caller/address/Map/event ABI | UInt64 `src` + cap-8 map 不是 address mapping 或 indexed Transfer |
| ERC20 `transferFrom` | compound allowance map + caller | 无 owner→spender→allowance state |
| ERC721 safe transfer | void static call | 无 dynamic receiver/code check/bytes/magic returndata |
| Vesting native ETH | callvalue rejection + timestamp FC | 不能收 ETH、读 balance 或按 value 释放 |
| ERC20Permit | 无 crypto/chain context | `Commit` 是 identity label，不是 keccak/EIP-712/ecrecover |
| Timelock execute | static-QN/value=0/void call | 无 runtime target/value/raw calldata/returndata |
| Proxy/UUPS | 无 fallback/DELEGATECALL/exact slots | 普通 CALL 不共享 proxy storage，也不透传 calldata/returndata |
| ERC2771 | 无 raw calldata suffix + caller FC | 参数化 caller 不是 trusted forwarder sender rewrite |
| ERC4337/ERC7786 | host + value/crypto/dynamic ABI 缺失 | static-QN CALL pilot 不是 EntryPoint 或 gateway protocol |

## 7. 缺口优先级与决策门

下面的 primitive 是高杠杆 **必要条件**，不是完成某个 family 的充分条件。

### 7.1 先做产品决策，再写代码

| 决策 | 必须冻结的问题 |
|---|---|
| EVM address/caller | Principal 与 20-byte address 的精确关系；ABI/storage/wire codec；禁止 truncate/pad fallback |
| Native ETH/value | target-neutral semantic extension 还是 EVM-specific capability；payable/receive/balance/value rollback |
| `B-CALL-SEM` | 降低当前 static-QN call/schedule support claim，或实现真实 dynamic call/returndata/value contract |
| Hardfork | solc、runtime、opcode/precompile 的同一固定 hardfork；不能使用 ambient `latest` |
| Proxy/create/delegate | 是否进入产品范围；若进入，必须接受 storage aliasing 和 raw ABI 复杂度 |
| ERC-4337/ERC-7786 | 是否维护 EntryPoint/gateway 外部 host oracle 与协议版本 |

### 7.2 推荐实施顺序

| 优先级 | Cluster | 先解锁的 claim layer / vertical | 仍然残留的 blocker |
|---|---|---|---|
| P0-Gate | 修复 Tool Lock identity；冻结同一 hardfork；落 corpus/observation identity | Counter 等现有 runtime 重新成为 current evidence | 不增加任何 OZ family 能力，只恢复可信测试前提 |
| P0-Behavior | 20-byte address-bearing identity + real EVM caller | Ownable-like Reference↔PF behavior | 若要 family Partial，仍需 OZ behavior leg；若要 ABI claim，仍需标准 event/error bytes |
| P0-Data | scalable address/UInt256 mapping + compound/nested keys | ERC20 balances/allowance substrate | 仍需 caller、indexed events、标准 errors 与完整边界 corpus |
| P0-ABI | indexed address events/errors | Ownable/ERC20 ABI observation | 不解决 state、caller 或 call semantics；不是 Ownable behavior 首个 pass 的前置 |
| P1-Behavior | timestamp + payable/value/balance | Vesting native-release | 仍需 asset transfer、rollback、recipient behavior |
| P1-Call | dynamic target CALL + value + exact returndata + code/static checks | ERC721 safe receiver 或 SafeERC20 | 仍需 dynamic bytes ABI 与 reentrancy/callback corpus |
| P1-ABI | dynamic ABI bytes/string/arrays/structs | callback/governance input | 不自动带来 runtime call 或 protocol host |
| P2-Crypto | user keccak/ecrecover + chainid/address(this) | ERC20Permit/EIP712 | 仍需 ERC20 core、nonce/deadline、signature failure corpus |
| P2-Data | checkpoints/enumerable data structures | Votes | 仍需 address/clock/signature flow |
| Scope gate | DELEGATECALL/exact slots/CREATE/transient/extcode | Proxy/Clones/UUPS | 建议独立 EVM extension profile，不污染默认 portable core |
| Scope gate | EntryPoint / ERC7786 host | Account/Paymaster/Cross-chain | 需要外部协议版本、counterparty 与 integration oracle |

最短的产品路线不是 Governor、Proxy 或 ERC-4337，而是：

0. **先恢复 runtime evidence 前提**：Tool Lock、hardfork 和 case identity 不闭合时，不开始新的兼容计分。
1. **Ownable-like behavior**：两个真实 EOA、unauthorized revert、authorized state change，先完成
   Reference↔PF Anvil；再加入 pinned OZ `oz-behavior` leg 才能把 F01 计为 `Partial`。ABI claim 另行审批。
2. **ERC20 core**：只有在 address/caller、scalable/nested map、indexed events 和 ABI 决策完成后开始；
   当前 Token 保持 adapter。
3. 然后在 **Vesting**（time/value）与 **Permit**（crypto/chain context）中选一个扩展轴，避免同时展开。

## 8. 可执行验证设计

当前仓库还没有下面的统一 schema/harness；本节是可落地的设计，不是已有 gate。

### 8.1 Case 分类

每个 `proof-forge.evm-corpus-case.v1` 必须且只能声明一种 class：

| class | 允许的结论 | 必须执行的 legs |
|---|---|---|
| `primitive` | PF primitive 在 EVM 上保持 shared semantics | ReferenceV1 ↔ PF Anvil；禁止 OZ claim |
| `adapter` | 仅声明的业务投影相同，不计 family 状态 | 每个 leg 可有不同 driver；只比较显式 projection，禁止 ABI/standard claim |
| `oz-behavior` | 一个 OZ family 行为场景等价，但不声明 ABI | ReferenceV1 ↔ PF Anvil ↔ OZ Anvil 的 shared business projection；不得丢弃场景关键字段 |
| `abi` | 标准 ABI + observable behavior | ReferenceV1 ↔ PF Anvil ↔ OZ Anvil；PF/OZ 使用相同 EVM call bytes，禁止 adapter 隐藏差异 |
| `blocked` | 当前精确 fail-closed | typed phase/target/reason contract；不得把 unrelated early failure 当 pass |
| `oos` | 已接受的产品边界 | 必须引用 accepted decision；研究建议不可使用 |

建议 case 绑定：PF commit/sourceHash/semanticHash、OZ commit、target/profile、Tool Lock digest、solc/anvil
版本、hardfork、actors、initial state、step sequence、expected observations、oracle legs 和显式 skip policy。

建议资源上限：case JSON 64 KiB、observation 256 KiB、32 steps、8 actors、每步 32 logs、每 log 4 topics，
以及至多 8 个长度 128 的 diagnostic patterns。未知字段、未知 enum、越界或非 canonical input 一律拒绝。

当前 EVM lowering 多数边界表现为 typed `CompileError.planInvariant(.evm, message)`，CLI message 仍含 free text，
尚不存在稳定的 case-bound capability diagnostic code。因此 W2 blocked catalog 应分两步：先在 Lean focused
case 中匹配 typed phase/target + bounded exact reason；再冻结 closed diagnostic discriminator 后接产品 CLI。
在此之前 §8 仍是 proposal，不能声称已有稳定 blocked harness。

### 8.2 分层观察面

`proof-forge.evm-observation.v1` 必须显式拆成两个子投影，不能要求 target-neutral Reference 伪造 EVM 字段：

- `shared`：success/revert/trap、typed return、logical state、ordered semantic effects，以及失败前后
  logical state/effect 的 rollback equality。ReferenceV1 与 PF EVM 都必须填充。
- `evm`：raw calldata/returndata、声明的 raw storage slots、ordered logs（address/topics/data）、raw revert
  bytes/selector、external calls（target/value/calldata/returndata）、actor/contract balances，以及对应 rollback。
  由 PF Anvil 和 OZ Anvil 填充；ReferenceV1 必须留 absent，不能填 synthetic 值。

`oz-behavior` case 还要声明 `sharedProjectionSchema`，将 OZ 的 EVM observation 归一到 shared business
observation；projection 必须列出保留/丢弃字段，并禁止丢弃该场景的授权主体、状态变更、返回、revert 或
rollback。`adapter` 则声明独立 `pfDriver`/`ozDriver` 与 projection，允许 call bytes 不同，但永远不产生
family/ABI/standard credit。

gas 默认排除，因为优化和 compiler 版本会改变 gas；只有未来标准或安全 claim 明确依赖 stipend、63/64 rule
等 gas 行为时，才把它纳入版本化观察面。

### 8.3 三角 oracle 规则

```text
        ReferenceV1  == shared observation ==>  PF EVM / Anvil
                                                   ||
                           oz-behavior: shared projection
                           abi: full EVM observation + same call bytes
                                                   ||
                                        OZ v5.7.0 / Anvil
```

- Primitive：只做 ReferenceV1↔PF Anvil `shared`；不借 OZ 提高声明。
- Adapter：每个 leg 可用不同 driver，只比较声明的 adapter projection；例如 UInt64 Token 只能比较守恒、
  余额变更和 rollback，不能比较 ERC20 ABI，也不计 family status。
- OZ behavior：比较 Reference/PF shared 与 OZ→shared projection；可以增加 family behavior 状态，
  但不能增加 ABI/standard 状态。
- ABI：Reference↔PF 比较 shared；PF↔OZ 使用相同 actor/call bytes 比较完整 EVM observation。
- Blocked：当前 Lean case 匹配 typed phase/target/bounded reason；未来 CLI case 必须使用 closed diagnostic。
  Tool Lock、parse error 或别的早期失败不能算 expected blocker。
- `skip` 不是 `pass`。可选工具不存在可以使可选 runtime leg `skip`；工具存在但 build/assertion 失败必须 hard fail。

### 8.4 三个具体 case

#### A. 现有 primitive 迁移

`pf.primitive.counter.overflow-hold.v1`

- class：`primitive`
- 输入：`Examples/Counter.lean`
- 现有证据映射：`Tests/Semantic/ReferenceV1.lean`、`scripts/evm_anvil_differential.sh`、
  `scripts/smoke_evm.sh`
- 断言：overflow revert；logical/raw state 不变；没有 committed logs；balance 不变。
- 当前状态：工程逻辑已有，但本次产品 build/Anvil leg 被 Tool Lock mismatch 阻断，不能记 pass。

#### B. 可执行 blocker

`oz.f01.ownable.onlyowner.blocked.v1`

- class：`blocked`
- 输入：包含 `context.caller` 的最小 Ownable-like PF program。
- 当前可执行形态：Lean focused case 在 EVM capability/Plan 阶段匹配
  `CompileError.planInvariant(.evm, boundedReason)`，拒绝 caller/address mapping；不产生 artifact，不启动 Anvil。
- 产品 CLI successor 必须等待 closed diagnostic discriminator；`PF-TOOLCHAIN-MISMATCH`、parse failure 或
  unrelated type error 均不能满足该 case。

#### C. 未来 ERC20 ABI claim

`oz.f03.erc20.transfer.blocked.v1` 在当前保持 `blocked`；primitive 到位后才能另建
`oz.f03.erc20.transfer.abi.v1`。未来 ABI case 至少比较：

- `transfer(address,uint256)` selector、Bool return 与 exact calldata/returndata；
- address-key balances 和 total supply；
- indexed `Transfer(from,to,value)` topics/data；
- insufficient-balance custom error bytes；
- revert 后 state/log/balance 全部回滚。

当前 Token 只能有单独的 `adapter` case，不能重命名或复用为此 ABI case。

### 8.5 CI 分层

> **以下整张表与 W0–W4 均为 proposal，当前仓库尚未注册该 schema/harness/cases，不得引用为现有 CI。**

| 层 | 内容 | 失败策略 |
|---|---|---|
| Fast/static | schema、manifest、case IDs、blocked diagnostics、PF Source/Typed/Normalize/Wire | always-on；任何非预期拒绝 hard fail |
| PF engineering | Reference cases、EVM Plan/IR/Yul、solc acceptance | ordinary CI；不冒充 runtime/formal |
| EVM runtime | locked solc + fixed-hardfork Anvil，执行 primitive/adapter/ABI PF leg | 工具已物化时 hard fail；不得 silent skip |
| OZ oracle | 隔离 checkout 固定 commit，安装 lockfile、生成 exposed contracts、固定 hardfork执行选定 tests | 不进入 PF 产品 import graph；结果绑定 commit/tool hashes |
| Sequence/property | bounded action sequences、failure injection、rollback/invariant | 基础 ABI case 稳定后加入 |
| Release/formal | 独立 identity/evidence 与 eligible-host 流程 | 普通 CI 通过不等于 release/formal |

建议波次：

- W0：把 Counter/Accumulator/ArithOps/EventFlow 迁成 `primitive` cases。
- W1：把 Token 固定为明确 `adapter`，加入 capacity/rollback/双账户序列。
- W2：先为 Ownable/ERC20/Vesting/Permit/Timelock/Proxy/ERC2771/ERC4337 建 Lean typed `blocked` catalog；
  closed diagnostic 冻结后再接产品 CLI。
- W3：primitive 和 hardfork 冻结后才增加 `abi` cases。
- W4：加入 bounded state-machine/property sequences，而不是只跑 happy path。

## 9. 本次可执行验证记录与限制

### 9.1 已执行的 ProofForge 证据

本次研究主机为 Darwin arm64，Lean 4.31.0，PF HEAD
`31e271474c85e18fb345fe709694dbd069cd8893`。观察到：

| 验证 | 结果 | 能证明什么 |
|---|---|---|
| focused Reference/Check/Normalize suites | exit 0 | shared semantic/typing 子集可执行 |
| focused WireV1 suite | exit 0 | 当前 wire structure 子集通过 |
| EvmPlanSchema/EvmSmoke/EvmSolcAcceptance | exit 0，PATH solc 0.8.34 | 工程 Plan/Yul 与五个 fixture 可编译 |
| ordinary typed/target shards | exit 1 | 在相关 suite 前被 Tool Lock raw digest mismatch 阻断 |
| product CLI EVM build | exit 1 | 同一 Tool Lock mismatch |
| `scripts/evm_anvil_differential.sh` | exit 1，非 skip | product build 失败，未形成新的 runtime 证据 |

聚焦 solc pass 不能替代 locked Finalize 或 Anvil observable equivalence。

### 9.2 HEAD-bound Tool Lock 错误

以下是 2026-08-03 在 HEAD `31e271474c85e18fb345fe709694dbd069cd8893` 上以
`shasum -a 256 toolchains.lock.json toolchains-linux-x86_64.lock.json` 复算的快照。两份 committed lock
都与 `ProofForgeV2/Core/ToolLockV4.lean` 的 embedded expected raw digest 不一致：

| 平台 | HEAD-bound lock raw SHA-256 | embedded expected |
|---|---|---|
| Darwin arm64 | `23ca3a77fc66f28c83bf1cdc7dabe28c908e2d6da92766fec366ca4373d90dcb` | `018989d100eee97ffabd03a2a7c99df12c3d55c27012ef3f06255173f8c79526` |
| Linux x86_64 | `7ea720f8d28e537e906a59314b26b903c58fe98a60d96e6e4933e9c3ee91c67f` | `8d870368c8a4dbb1637ac011811a7b2c05e418250489d6a992e1408fb54c45f2` |

候选原因是 lock 已扩入 CosmWasm/TON 等条目而 embedded expected 未同步；本报告不把该因果当作已证明的
产品事实。只要两个 digest 不相等，产品会在 tool resolution 前因 lock identity 失败。未来 lock 或 expected
变化后必须重新计算，不能沿用本表。本研究不修复该问题，也不把它当作 capability blocker 通过证据。

### 9.3 Hardfork 不一致

- 仓库事实：PF locked solc 为 0.8.34，`FinalizeV1` 未传 `--evm-version`；审计主机观察其默认产物面为 Osaka。
- 仓库事实：Anvil 脚本未固定 hardfork；审计主机上的 locked Anvil 0.3.0 `latest` 观察为 Cancun，
  且拒绝 `--hardfork osaka`。后两项是 host observation，不是源码不变式。
- OZ 配置事实：Hardhat 使用 solc 0.8.35、optimizer 200、hardfork/EVM `osaka`。
- OZ 配置事实：Foundry 使用 solc 0.8.31、optimizer 200、EVM `osaka`。

因此当前不能建立共享 hardfork 下的 PF↔OZ 正向 runtime oracle。该偏差不影响静态 first-blocker 结论，
但任何未来正向结果都必须先固定相同 hardfork 或明确证明 opcode/precompile 差异不相关。

### 9.4 OpenZeppelin runtime 未执行

本次使用 shallow pinned checkout 做源码/官方测试配对，没有安装 npm dependencies、generated exposed contracts
或 Foundry submodules，因此所有 OZ test 证据均为 `static-reviewed-OZ`，不是 runtime pass。
OZ `package.json` 为 5.7.0，但 `package-lock.json` root metadata 仍写 5.6.1；未来 oracle 应绑定 git commit 和
具体文件/tool hashes，不能只信 lockfile root version。

## 10. 推荐的兼容承诺

建议产品以后只发布分层、版本化声明：

1. **Portable semantic claim**：哪些 ProgramV1/SemanticProgramV1 primitive 被共享 Reference 精确定义。
2. **EVM profile claim**：哪些 primitive 在固定 EVM ABI/storage/hardfork/toolchain 下被 materialize。
3. **Behavior scenario claim**：哪些 corpus case 已通过 Reference↔PF EVM。
4. **ERC/EIP conformance claim**：哪些标准版本已通过 PF↔OZ/独立标准 oracle；默认没有。
5. **Explicit exclusion**：proxy、AA、cross-chain 等只有 accepted decision 后才成为 OOS；否则保持 blocked。

这允许 ProofForge 继续保持统一语言和 target-owned Plan，而不是为了追随 Solidity 表面语法，把 inheritance、
modifier、library 或 assembly 全部搬进共享 core。

## 11. 盲区与非声明

- 没有执行 OZ 官方 runtime tests。
- 当前 HEAD 的 product CLI/Anvil 正向路径被 Tool Lock mismatch 阻断。
- PF 与 OZ 的 compiler/runtime hardfork 尚未对齐。
- 仓库还没有统一 ABI byte-level、storage-layout 或 standard-conformance corpus。
- 没有 dynamic caller/value/callback/proxy/precompile 的 PF 产品 EVM 行为证据。
- 完整 Governor extension delta、crypto failure matrix 与 7 个 draft 实现未逐对象行为分类。
- 64 个 library 只做能力语料；本报告没有把每个纯算法库逐一判为 Exact/Blocked。
- gas/stipend/63-of-64 默认不在观察面。
- 112-object family grouping 是可审计 heuristic，不是 Ethereum-wide denominator，也不能转成覆盖百分比。
- 本报告不声称 formal D2/D3/D4、SupportClaim、hermetic/release evidence 或部署安全完成。

## 12. 最终建议

1. **立即停止“是否支持所有 OpenZeppelin/Ethereum 合约”的布尔提问**，改为版本化 primitive/scenario/standard
   coverage。
2. **不要逐个重写 OpenZeppelin 合约**；保留它作为隔离、pinned、MIT-licensed behavior oracle。
3. 先修复测试基础设施前置：Tool Lock identity、统一 hardfork、versioned corpus/observation schema。
4. 第一条产品 vertical 选 Ownable-like caller authorization；第二条在 P0 primitive 完成后选 ERC20 core。
5. Token 继续标为 nonstandard adapter；static-QN CALL 在 `B-CALL-SEM` 决策前不得算完整 EVM call。
6. Proxy/AA/cross-chain 先做正式 scope gate；未批准前保持 fail closed，不在共享 core 中预埋近似语义。
7. 每次新增 primitive 后只解锁对应 scenarios；每个 family 的 residual blocker 必须继续保留，直到完整证据闭合。

## 13. 证据注册

本报告的上游与本地证据登记为 `SRC-OZ-001`、`SRC-LOCAL-003`；核心结论登记为：

- `CLM-OZ-EVM-001`：固定语料分母与 112→20 family partition。
- `CLM-OZ-EVM-002`：当前严格 family compatibility 为 Exact 0 / Partial 0 / Blocked 20。
- `CLM-OZ-EVM-003`：应以 primitive + scenario + standard corpus 管理兼容，而非逐文件重写。
- `CLM-OZ-EVM-004`：当前 Tool Lock/hardfork 不一致阻止新的正向 PF↔OZ runtime claim。
