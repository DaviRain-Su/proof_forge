---
id: SPEC-REG-001
title: Target 与 Profile 注册表
status: proposed
owner: targets
updated: 2026-07-15
normative: true
---

# Target 与 Profile 注册表

## 三种身份

- `TargetId`：执行、状态、调用、证明和结算语义；小写 ASCII `[a-z][a-z0-9-]{0,31}`。
- `CodegenProfileId`：target 的 ABI、lowering、artifact encoding、工具适配策略。
- `NetworkProfileId`：RPC/chain ID/deploy policy，只用于显式 deploy/verify。

三者不能拼接成隐式复合字符串，不能从 network 反推 codegen，也不能让 network 改变
semantic/plan hash。

## Descriptor

```lean
structure TargetDescriptor where
  targetId         : TargetId
  displayName      : String
  artifactEncoding : ArtifactEncoding
  executionHost    : ExecutionHost
  commitModel      : CommitModel
  stateBinding     : StateBinding
  callModel        : CallModel
  proofModel       : ProofModel
  settlementModel  : SettlementModel
  abiModel         : AbiModel
  resourceModel    : ResourceModel
  maturity         : Maturity
  supportClaims    : Array SupportClaim
  codegenProfiles  : NonEmptyArray CodegenProfileId
```

`family/view label` 可从 descriptor 生成文档视图，但不存在参与 dispatch 的单一 family
字段。Registry 是 compile-time static array，创建时检查全部 target/profile/key 唯一。

## Initial Registry

| TargetId | Default CodegenProfileId | Phase 1 | Descriptor 摘要 |
|---|---|---|---|
| `evm` | `evm.yul-solc.v1` | implement | bytecode/EVM/storage/sync call/transaction commit/no proof/EVM settlement |
| `solana` | `solana.sbpf-v0.v1` | implement | ELF/SVM/explicit accounts+CPI/transaction commit/Solana settlement |
| `near` | `near.wasm32.v1` | implement | Wasm/NEAR host/KV/receipt-local commit/Promise/NEAR settlement |
| `noir` | `noir.acir-bb.v1` | implement | ACIR/constraint system/external state/proof/external verifier |
| `cosmwasm` | `cosmwasm.wasm32.v1` | design | Wasm/CosmWasm host/KV/submessage+reply/Cosmos settlement |
| `soroban` | `soroban.wasm32.v1` | design | Wasm/Soroban host/TTL storage/auth tree/Stellar settlement |
| `icp` | `icp.wasm32.v1` | design | Wasm/canister actor/stable memory/await commit/ICP settlement |
| `openvm` | `openvm.rv32im.v1` | design | RV32IM guest/zkVM proof/external verifier |
| `aleo` | `aleo.leo4.v1` | design | Aleo Instructions/records+mappings/private+final/Aleo settlement |
| `psy` | `psy.dpn.v1` | design | DPN/user-partitioned state/recursive proof/Psy settlement |

Design-only entries可出现在 `list-targets --all`，但 `build` 必须返回
`PF-TARGET-NOT-IMPLEMENTED`；默认 `list-targets` 只列有实现且达到 profile 最低 evidence
的 entries。

## Lookup API

```lean
def TargetRegistry.create : Array TargetRegistration → Except RegistryError TargetRegistry
def TargetRegistry.resolveTarget : TargetId → Except Diagnostic TargetRegistration
def TargetRegistration.resolveCodegen : CodegenProfileId → Except Diagnostic CodegenProfile
def NetworkRegistry.resolve : NetworkProfileId → Except Diagnostic NetworkProfile
```

lookup exact、case-sensitive，不接受 alias。默认 profile 只在用户未给 `--profile` 且
target registration 明确唯一 default 时使用。`--network` 对 build 是 CLI 错误。

## 错误、边界与安全

`PF-TARGET-UNKNOWN`、`PF-TARGET-NOT-IMPLEMENTED`、`PF-PROFILE-UNKNOWN`、
`PF-REGISTRY-DUPLICATE`、`PF-REGISTRY-INVALID`。覆盖空 registry、duplicate target/profile/
claim、大小写、Unicode、过长 ID、无 default/多 default、profile 属于另一 target、design-only
build、unknown network、network 用于 build、descriptor 缺轴、support claim 排序、registry
hash 决定性、恶意动态配置。Registry 不从 cwd、环境、网络或用户文件加载 executable
plugin；可选 JSON 只允许选择已编译 profile，不可新增代码。

## 验收

关联 `FR-005/008`、`TST-REG-001/002`。输出 target list 与 registry canonical hash；
重排源 registration 不改变 hash；所有 design-only target honest reject。
