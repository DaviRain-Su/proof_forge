---
id: TARGET-EVM
title: EVM target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：EVM

状态：`proposed`
Target ID：`evm`
Phase 1：实现

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

Phase-1 的首个通用 lowering 切片只接收 verifier-visible `UInt64` 状态、参数与返回值，
以及 literal、parameter/state load、checked addition、state store 和 return。Plan 必须逐项拥有：

- 由 `StateId` 决定且经唯一性验证的 storage slot；
- constructor 参数与 target-owned body；
- 每个 entry 的 Keccak-256 ABI selector、calldata 布局、mutability 与 target-owned body；
- checked-add 的 `UInt64` overflow → revert 映射和交易回滚语义。

`makePlan` 不得调用 fixture matcher，也不得按 program/entry/state 名特判。当前 semantic fragment
之外的类型、visibility 或 statement 必须以 `PF-PLAN-INVARIANT` fail closed。
当前 `evm-yul-solc-0.8.34-v1` profile 在 selector hashing 前只接受 ASCII
`[A-Za-z_][A-Za-z0-9_]*` identifier，byte length 限制为 240，
program artifact stem 因 `.abi.json` 后缀限制为 231 bytes；state/entry 各 1024、每 callable
参数 256、body statements 4096、表达式深度 256、整份 Plan nodes 100000。超限不进入
Keccak/Yul lowering；CLI 另对所有 target 的完整 artifact relative path 强制 240-byte 上限。

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
