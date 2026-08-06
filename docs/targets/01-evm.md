---
id: TARGET-EVM
title: EVM target dossier
status: proposed
owner: architecture
updated: 2026-08-06
normative: true
---

# Target Dossier：EVM

状态：`proposed`
Target ID：`evm`
Phase 1：实现

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，structure-gate 后 private
lowering 构造 target-owned `EvmPlan`；module 内无 `alphaResidualOf` / `makePlanFromAlpha`。

**工程已接线（摘）**：

- multi-width UInt/Int 与 body 窄宽、UInt128/256（EVM-only）ABI/body 子集；Field(bn254) mod-p 通道；
- 控制流 if/match、fn/localCall、let/bounded for、shift/bitwise/logical、revert/emit；
- named 聚合 flatten、定长 Array IndexGet/Set（bounds revert）；String 类型面（**String match switch 已落地 N-A1**）；
- **Map UInt64→UInt64 dense pilot（cap-8）+ Bytes（N×UInt8 leaves，D4-E2）**；
  aggregate `StateStore` 以 `storeAtomic` 两阶段 Yul：每个 leaf 在独立 block 中求值并 spill 到
  reserved memory，全部 leaf 完成后再连续 `sstore`。`EvmSmoke` 固定 empty Map upsert、双 batch
  可见性与 spill 结构；`EvmSolcAcceptance` 检查 host solc，`TokenV1` 产品路径锁定 solc 0.8.34；
- **Option UInt64 state（BL-31）**：Enum-shaped tag/payload 双 slot；`none` 与 reset 清零 payload，
  `StateStore` 复用 `storeAtomic`；Option parameter、非 UInt64 payload 与 nested Option 仍 fail-closed；
- **bounded aggregate return ABI**：named Struct/Enum 与 anonymous `Array UInt64 N`（1..8）/
  `Option UInt64` 发 Solidity tuple；Map/Bytes/nested/非 UInt64元素与 target pureFn aggregate仍 FC；
- **static-QN external call/schedule**：sync 发真实 `CALL`；result-bearing UInt64 路径要求
  `returndatasize ≥ 32`、读取首 word并做 UInt64 range check；schedule 仍同步 CALL+discard。
  callee 仍为 target-path hash stub，真实 deployment-address binding 未闭合；
- Token 当前仅恢复到 **locked-solc engineering finalization**：creation bytecode 为 258460 B，
  已超过 EIP-3860 的 49152 B initcode 上限，因此没有 Anvil/mainnet deployment、runtime 或 OZ 声明；
- Yul + digest-pinned `solc` bytecode；**EvmSolc** `solc --strict-assembly` 验收门（工具缺席干净跳过）；
- engineering planDigest 可绑 BuildIdentity/OutputSet；G4 `evm_anvil_differential.sh` 从产品 CLI
  制品运行 Counter/Accumulator/ArithOps/EventFlow，固定 overflow state-hold 与 emit 日志。
- **双 profile（EVMOZ-001）**：默认 `evm-yul-solc-0.8.34-v1`（历史 solc 参数，无 ambient
  `--evm-version`）；显式 `evm-yul-solc-0.8.34-cancun-v1` 在 Finalize 加
  `solc --evm-version cancun`，runtime 经 `PF_EVM_PROFILE=…cancun-v1` 启动
  `anvil --hardfork cancun`。两 profile 共用锁定 solc 0.8.34 / Anvil 0.3.0，不升级工具。
- **`pf.assets` native binding（ADR-0029 Phase B2，2026-08-05）**：两 profile 均 advertise
  exact `extension.pf-assets`（resolver multi-permit）。`pf.assets.native.deposit` →
  exact `callvalue()==amount`（无 deposit 的 entry 强制 `callvalue()==0`；无 payable
  entry 的程序 Yul 字节不变）；`pf.assets.native.transfer` → full-gas value `CALL`
  （空 calldata，failure → revert 传播）；dst Principal 运行时须 exact wire shape
  `u32le(20)||addr20`（高肢清零；B-3 wire-identity 存储 pin 不破）。重入诚实注记：
  value CALL 可能执行接收方代码（含重入），Reference 无重入模型，属 opaque-effect
  契约。`PfAssetsCatalogV1` 含 `interface-standard` artifactBinding 骨架（native 用
  `runtimeNative`；ERC-20 留后续）。token/async 保持 FC。Anvil 工程门
  `scripts/evm_tipjar_anvil_smoke.sh` 已真跑（deploy/tip/余额 + 四类负例全过）；
  产品纵切 `Tests/Product/TipJarEvmV1`（`TipJar.bin` solc 0.8.34 + exact closure）。
- **`pf.assets.token.transfer` binding（ADR-0030 E1a，2026-08-05）**：payload 不变的
  per-target 绑定。mint Principal 参数经 exact wire shape `u32le(20)||addr20`（高肢
  清零，负例 revert）解码为 20 字节 ERC-20 合约地址——**受控动态 callee**，仅
  catalog token 家族准入，generic dynamic callee 仍 FC；calldata exact（selector
  `0xa9059cbb` + 32B address + 32B amount）；返回值三分支 catalog predicate
  （returndatasize 0 → USDT 式成功；32 → 首 word 非零，否则 revert；其余长度
  revert），CALL 失败传播 revert；合约自身 ERC-20 余额即 vault，entry 保持
  nonpayable。产品纵切 `TokenJarEvmV1` 扩展 + Anvil 工程门
  `scripts/evm_tokenjar_anvil_smoke.sh`（`evm_anvil_differential.sh` companion leg）
  已真跑：ERC20Mock mint 2000 → `tipToken(mint,dst,1000)` 精确 ±1000、超额 revert
  状态保持、returnFalse 负例、USDT 无返回成功、wire-shape 负例全过。
  `token.transferAsync` 与其余 token 家族仍 FC；**非** formal/mainnet parity。
- **`pf.assets.*.balanceOfSelf` env-read binding（ADR-0030 E2-3-EVM，2026-08-05）**：
  payload v1.1.0 新 QN 的 per-target 绑定（read-only、view/entry-callable、
  effect-free、结果 UInt64）。native → `SELFBALANCE` opcode + UInt64 range guard
  （值 ≥ 2^64 → revert）；token → 只读 `STATICCALL balanceOf(address)`（selector
  `0x70a08231` + 32B self `ADDRESS`；mint Principal 经 E1a 同款受控动态 callee
  wire shape `u32le(20)||addr20` 高肢清零；returndatasize==32 且返回 word 高 192
  位清零，否则 revert）。产品纵切 `Examples/EnvReadJar.lean`；Anvil 工程门
  envread leg 真跑（`scripts/evm_envread_anvil_smoke.sh` 作为
  `evm_anvil_differential.sh` companion leg，corpus manifest 同步）：合约充
  1 ETH → `nativeBalance()`==1e18（SELFBALANCE 精确）；ERC20Mock mint 2000 →
  `tokenBalance(mock)`==2000（STATICCALL `balanceOf` 精确）。
  **非** formal/mainnet parity。

**明确未闭合**：完整 SemanticProgramV1 表面；ContextRead 只开放已版本化的 `unixTimeSeconds` 与 `caller`，`blockHeight`/未知键仍在 EVM Plan fail closed（S2 target lane 尚未交付）；Option parameter、非 UInt64 payload 与 nested Option 仍 fail-closed；static-QN callee 仍是 hashed-address stub，缺真实 deployment-address binding；formal Plan/IR/Build/Output identity 与 identity-bound Reference↔Anvil formal differential；G4 不是 formal TST closure，不得写成 D4 / formal TASK 完成；**不得**把 Cancun profile 写成 OZ compatibility 或 formal hardfork 闭合；**不得**把 ADR-0025/S1 写成 Ownable/OZ/ABI/formal 完成。

## 0.1 `context.caller` Principal encoding 与物化合同（ADR-0025；S1-EVM）

[ADR-0025](../adr/0025-evm-caller-principal-realization.md) 的唯一拼写已于 **2026-08-06** 经 ADR-0031 S1 / ADR-0030 E3 原子接入 target-owned EVM Plan/IR/Yul：

| 项 | 合同 |
|---|---|
| Shared `Principal` wire | **不变**：`u32le(len) \|\| opaque body`（`1..4096`）；无 Address TypeShape / 第二套 codec |
| EVM `context.caller` 结果 | **唯一** canonical valueBytes = `u32le(20) \|\| address20`，其中 `address20` = opcode **`CALLER`** 的 network-order 20 raw bytes |
| Plan/IR/Yul | `ContextRead(callerContextKeyV1)` 必须产出 Principal 的 `len=20 + 8×UInt64` 九叶布局；Yul `byte(index, caller())` 组装前三个 body word，其余高 12 bytes 清零；未知 key 与错误 TypeId fail closed |
| View safety | `CALLER` 在 `STATICCALL`/`eth_call` 读取安全；EVM entry 与 view 均可比较 caller Principal；多字 Principal 直接 return ABI 仍 fail closed |
| 禁止 | truncate/pad/hash/prefix-strip、bare-20B / left-pad-32B 并行拼写、任意 Principal→address 近似映射、静默 fallback |
| 不解锁 | Solidity `address` ABI、indexed address event/error、dynamic CALL/callee、proxy；T10 Principal **storage** 仍为 wire-identity leaf（≠ 20B address slot） |
| Reference/runtime | Reference invocation 使用同一 canonical Principal bytes；`CallerCheck` Anvil 验证 match/mismatch + view，`pf.primitive.ownablelike.caller-admit.v1` 验证 owner/stranger 与 rollback |
| 他 target | 每个 target 仍须独立冻结 identity source、长度、view-safety 与 runtime 门；EVM 结果不能外推为 Solana/NEAR/CosmWasm 结论 |
| Ownable F01 | PF primitive 已从 blocked case 升为 Reference↔PF-Anvil pass；**OZ family 仍 Blocked**，因为没有 pinned OZ behavior leg、标准 address ABI、ownership event/error ABI；无 ABI/formal/release credit |

B-3 PrincipalAddr pin（wire Principal ≠ 固定 EVM address type；CALL 非 dynamic Principal 地址）与
AddressBearing static-QN CALL **继续有效**；本合同只开放 **ContextRead caller identity read**，
不修复 B-CALL-SEM。

## 1. 身份与来源

EVM 是带账户代码、持久 storage、同步 message call、gas 和交易状态转换的 contract VM。主要依据 [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)（`SRC-EVM-001`，verified）。具体 fork、precompile 集和 gas schedule 进入 target semantics digest，`CodegenProfile` 只能 exact 引用并实现；chain/genesis identity 与部署端点由 `NetworkProfile` 固定。

## 2. 执行、状态、调用、失败与资源

- 执行：单交易内可同步嵌套调用；call frame 拥有 memory/stack/context。
- 状态：逻辑 state 映射到合约 account storage；布局是 ABI 稳定性的一部分。
- 调用：`CALL` 等模式的 caller/value/static/delegate 语义不能合并。
- 失败：业务 `revert`、VM trap/out-of-gas 与外部 call failure 分开记录；失败路径不得提交当前 frame 状态。
- 资源：gas schedule 随 target semantic fork 变化，不进入 target-neutral 源语言语义，但必须进入
  target semantics digest、Plan 假设和 provenance；`CodegenProfile` 只能实现并 exact 引用该
  schedule，不能选择另一套 gas 语义。

## 3. Portable fragment 与扩展

Portable：固定宽度整数、Bool、Bytes、Cell/Map、同步 entry/view、event、checked arithmetic、caller/attached value、原子失败。

版本化扩展：raw calldata/returndata、delegate/static call、create/create2、precompile、EVM log topics、self balance。扩展 ID 必须携带 exact semver 和 semantics digest。

## 4. `EvmPlan` schema

```text
EvmPlan {
  profile, entries, abi, storageLayout,
  constructor, dispatch, blocks,
  externalCalls, events, errors,
  gasAssumptions, linkReferences
}
```

Plan 不再读取源码符号来猜 storage slot；每个 entry 的 selector、mutability、payability、return/error ABI 在 Plan 中完整确定。

Phase-1 当前通用 lowering 切片只接收 verifier-visible `UInt64` 状态、参数与返回值，
以及 literal、parameter/state load、checked addition/subtraction、state store 和 return。Plan 必须逐项拥有：

- 由 `StateId` 决定且经唯一性验证的 storage slot；
- constructor 参数与 target-owned body；
- 每个 entry 的 Keccak-256 ABI selector、calldata 布局、mutability 与 target-owned body；
- checked-add overflow 与 checked-sub underflow 的 `UInt64` → revert 映射和交易回滚语义。

`makePlan` 不得调用 fixture matcher，也不得按 program/entry/state 名特判。当前 semantic fragment
之外的类型、visibility 或 statement 必须以 `PF-PLAN-INVARIANT` fail closed。single-block lowering
还把每个 `stateStore` 与最终 `return` 视为 effect segment sink：该 sink必须消费自上一 store 后产生的
全部 value definitions，且依赖不得指向旧 segment；dead、reordered、stale 或跨 effect-boundary value
均 fail closed。该约束是当前 public-UInt64 evaluation-order合同，不应被泛化成完整 CFG lowering语义。
当前 EVM profiles（默认 `evm-yul-solc-0.8.34-v1`，显式
`evm-yul-solc-0.8.34-cancun-v1`）在 selector hashing 前只接受 ASCII
`[A-Za-z_][A-Za-z0-9_]*` identifier，byte length 限制为 240，
program artifact stem 因 `.abi.json` 后缀限制为 231 bytes；state/entry 各 1024、每 callable
参数 256、body statements 4096、表达式深度 256、整份 Plan nodes 100000。当前 V1 lowering
对表达式同时计算 SSA dependency depth 与**展开后的树节点数**，因此共享 ValueId 不能把实际
重复发射成本伪装成较小 DAG；超限不进入 Keccak/Yul lowering。CLI 另对所有 target 的完整
artifact relative path 强制 240-byte 上限。Cancun profile 只改变 solc/Anvil hardfork 引脚，
不改变 Plan schema 或 identifier 规则。

## 5. Target IR 与制品

Phase 1 路径：`EvmPlan → EvmIR → Yul → init/runtime bytecode`。输出 ABI JSON、Yul、runtime bytecode、deploy bytecode、source/semantic/plan hashes 和 manifest。Yul/bytecode 必须经过独立语法/字节码验证。

## 6. 工具链

Lean emitter 固定版本；外部 `solc`/Yul compiler、EVM interpreter、Anvil 都进入 `CodegenProfile` 和 binary digest。PATH 中未锁版本不得被自动采用。

## 7. 部署/证明流程

EVM 输出是 `deployable-contract`：生成 init code，模拟 constructor，部署到隔离 Anvil，校验 runtime code hash，再调用 ABI。正式网络部署不属于编译成功条件，需独立 `NetworkProfile` 和签名流程。

## 8. 安全

重点检查 reentrancy、delegatecall context、storage collision、unchecked return、selector collision、ABI malleability、gas griefing 和 value transfer。源级原子性只在同一交易同步范围内成立。

## 9. 验证阶梯

1. Plan invariants 与 selector/storage golden。
2. Yul/bytecode validation。
3. Semantic interpreter 与 EVM execution 差分。
4. Anvil deploy + Counter init/increment/get/overflow rollback。
5. 非 Counter 的 Accumulator（`total`/`add`/`current`）必须从同一 DSL 经动态 selector 和
   storage/body lowering 完成 init/add/read/overflow rollback，证明后端不是模板发射器。
6. 固定 network profile 后才可记录 network evidence。

## 10. 不支持、风险与成熟度退出

Phase 1 不支持 arbitrary assembly、delegatecall、create、proxy upgrade 和动态链接。实现退出条件：Counter 全流程、negative requirements、artifact reproducibility、Anvil runtime evidence、无 fallback。完整平台覆盖按扩展逐项增加，不以“能生成 bytecode”宣称完成。
