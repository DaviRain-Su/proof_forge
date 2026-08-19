---
id: RESEARCH-027
title: extension.crypto 设计钉（SHA-256 现状 + Merkle/签名/余 target）
status: draft
owner: engineering
updated: 2026-08-19
normative: false
---

# extension.crypto 设计钉

> **目的**：在 **不改 TargetRegistry / 不抢车道** 的前提下，固定
> `extension.crypto` / `pf.crypto.*` 的产品纪律、已交付事实、缺口与下一刀顺序。  
> **不是** 实现切片、不是 formal、不是 IBC 完成。  
> 相关：RPT-020/021 系统能力、SYS-S5 sha256 三叶（EVM/Solana/NEAR）、backlog `EXT-CRYPTO`、
> [`docs/plan/capability-layer-parity.md`](../plan/capability-layer-parity.md)（现行矩阵权威）。

状态：`draft`。日期：2026-08-13。**事实刷新：2026-08-19**——吸收 CAP-4/5（Soroban/TON
sha256 叶）、SYS-S5 keccak 三叶、CAP-X-BYTES（`sha256Bytes` 共享核+五叶）、
CAP-X-MERKLE（`merkleVerifyKeccak256` EVM 叶）、ecdsa host-syscall predicate 修复。
2026-08-13 的原始分桶与推荐序保留为历史，落地事实以 §2/§3 标注为准。

---

## 0. 一句话

`pf.crypto.*` 是 **按键精确、按 target fail-closed** 的能力命名空间，不是「有哈希就开放全家桶」。  
已开（2026-08-19）：`sha256` 五叶（EVM/Solana/NEAR/TON/Soroban）、`keccak256` 三叶
（EVM/Solana/NEAR）、`sha256Bytes` 五叶（EVM/Solana/NEAR/TON/Soroban，N 上限各异）、
`merkleVerifyKeccak256` EVM-only 叶、`ecdsaRecoverSecp256k1` EVM 叶。  
未开：流式 hash、其余 target 的上述 QN（命名 FC）、签名 verify 其它叶（Solana ed25519 挂
B-CALL-SEM；NEAR verify 待人拍）。

---

## 1. 产品纪律（不可破）

1. **QualifiedName 精确匹配**：只承认文档列出的完整 QN；前缀开放或「差不多的 hash」禁止。  
2. **Target 独占 binding**：同一 QN 在不同链绑不同 host（EVM `0x02` / Solana `sol_sha256` / NEAR `env.sha256`）；禁止共享 Plan 节点假装可移植字节码。  
3. **ABI 精确**：每叶锁定自己的精确 ABI；**split-QN 纪律**——Bytes arity 走独立 QN
   `pf.crypto.sha256Bytes`（CRYPTO-B1，2026-08-19 已落地），禁止同 QN 多 arity；流式/多块永久 FC。  
4. **Fail closed 优于假绑定**：无原生 host 的 target（例：CosmWasm 无 sha256 host）必须 Plan FC，不得用弱原语冒充（TON `string_hash`、Noir 电路压缩、Aleo BHP 等已钉诚实拒绝；TON 现经 CAP-5 走诚实 stdlib `slice.bitsHash()`/TVM `SHA256U`，`string_hash`/`HASHCU`/`HASHBU` 负针永禁）。  
5. **电路/zkVM/应用链**：Noir/OpenVM/Cairo/risc0/sp1 若开放，必须标 **约束/guest 原语** 而非「链上哈希已发生」；Aleo/Psy 已有平台专用 `pf.crypto.hash*` 等，**不得**与 S5 sha256 混成同一 SupportClaim。  
6. **不扩 accepted PRD**；ADR-0036（仍 `proposed`）的工程范围叙事现为 13 implemented + 0 design-only（XRPL 经 ADR-0049/0050 于 2026-08-17 加入；升格/改写属人拍）。

---

## 2. 已交付事实（工程，非 formal；2026-08-19 现状）

按 QN 分行；「LOWERED」= 有 named host binding 的 target 叶，「FC」= 命名 fail-closed（引 QN 诊断）。

| QN（精确） | LOWERED targets | FC targets |
|---|---|---|
| `pf.crypto.sha256` UInt256→UInt256 | EVM（`0x02`）、Solana（`sol_sha256`）、NEAR（host）、TON（CAP-5：`bitsHash`/`SHA256U` over LE image）、Soroban（CAP-4：`env.crypto().sha256`，UInt256 LE-limb plumbing-only） | CosmWasm（无 host）、Noir、Aleo、Psy、Quint、ICP、OpenVM、XRPL（ADR-0052 keep-FC：仅 `compute_sha512_half`） |
| `pf.crypto.keccak256` UInt256→UInt256 | EVM（opcode）、Solana（`sol_keccak256`）、NEAR（host） | TON（无 keccak）、Soroban、CosmWasm、Noir、Aleo、Quint、ICP、OpenVM、XRPL；Psy 的 `keccak256` 是 DPN gadget（UInt64 first-limb），UInt256 host ABI 仍 FC |
| `pf.crypto.sha256Bytes` Bytes N→UInt256（CAP-X-BYTES，2026-08-19） | EVM（`0x02` over memory，N≤64）、Solana（`sol_sha256` 单 slice，N≤64）、NEAR（host register bytes，N≤64）、TON（`SHA256U` 单 cell bits，N≤127）、Soroban（S0 `env.crypto().sha256` over `Bytes::from_array`，N 1..8） | Noir、Psy、Aleo、Quint、CosmWasm、ICP、OpenVM、XRPL（命名 FC） |
| `pf.crypto.merkleVerifyKeccak256` (root, leaf, s0…s_{D-1})→Bool（CAP-X-MERKLE，2026-08-19；D∈1..8，OpenZeppelin sorted-pair，false-not-revert） | EVM（unrolled `keccak256(0,64)` 链，statement tag 25） | 其余十二 target（按各自首道门命名 FC） |
| `pf.crypto.ecdsaRecoverSecp256k1` 4×UInt256→UInt256 | EVM（precompile `0x01` STATICCALL + Anvil companion；失败短 returndata → 零地址字，对齐 Solidity `ecrecover`，不 auto-revert） | 其余十二 target |
| Psy 平台 gadget：`hashNoPad`/`hashPad`/`hashTwoToOne`/`keccak256`、`pf.imt.*` | Psy（DPN gadget；**不计入** S5 sha256 完成度，不自动授权其它 target） | — |

Requirements 纪律（2026-08-19 起）：`sha256`/`keccak256`/`sha256Bytes`/`merkleVerifyKeccak256`/
`ecdsaRecoverSecp256k1` 均在 `isPfCryptoHostSyscallQnV1`
（`ProofForgeV2/Core/RequirementIdsV1.lean`），**不贡献** `effect.synchronous-call`
（precompile/host syscall/纯计算 ≠ 跨合约调用）。ecdsa 的 predicate 裂缝于 2026-08-19
修复（owner 接受既有程序 requirements/`semanticHash`/manifest digest cut over；sourceHash 不变）。

---

## 3. 缺口分桶（2026-08-19 刷新状态）

### A. 闭合 S5 sha256（文档/测，可选代码）

| ID | 项 | 状态 |
|---|---|---|
| **CRYPTO-A1** | 已交付表回写 | **done 2026-08-19**（本文件 §2 + parity 矩阵） |
| **CRYPTO-A2** | 无 host target 的 sha256 FC 钉测 | **done**（十三 target 均有引 QN 命名 FC 臂；Targets.lean needle 覆盖） |
| **CRYPTO-A3** | Soroban/ICP/OpenVM 新叶默认 FC 直至独立 leaf 决策 | **部分过期**：Soroban 已经 CAP-4 开叶（2026-08-16 owner 拍板）；ICP/OpenVM/XRPL 仍命名 FC |

### B. ABI 扩面（共享核敏感）

| ID | 项 | 状态 |
|---|---|---|
| **CRYPTO-B1** | `pf.crypto.sha256Bytes`（Bytes N→UInt256） | **done 2026-08-19**（CAP-X-BYTES：共享核 QN-scoped Bytes 放行 + 五叶；split-QN，非同 QN 多 arity） |
| **CRYPTO-B2** | 流式/多块 update+finalize | 永久/远期 FC（不变） |

### C. Merkle

| ID | 项 | 状态 |
|---|---|---|
| **CRYPTO-C1** | 冻结 QN | **done（变体）2026-08-19**：owner 拍板 keccak 族——`pf.crypto.merkleVerifyKeccak256`（定深 UInt256 sibling，非 `path: Array Bytes`；sha256 变体属未来独立 QN） |
| **CRYPTO-C2** | EVM Merkle verify 叶 | **engineering done 2026-08-19**（CAP-X-MERKLE：unrolled sorted-pair keccak 链，D≤8，false-not-revert；gas 诚实注释；不声称 Anvil differential） |
| **CRYPTO-C3** | Solana Merkle | 默认 FC（不变；无通用 syscall） |
| **CRYPTO-C4** | NEAR Merkle | 默认 FC（不变） |
| **CRYPTO-C5** | 电路 target Merkle | FC；约束路径 vs 见证路径必须分开声称（不变） |

### D. 签名

| ID | 项 | 状态 |
|---|---|---|
| **CRYPTO-D1** | QN 分离（禁单一 `pf.crypto.verify`） | **持续纪律**；`ecdsaRecoverSecp256k1` 已钉 |
| **CRYPTO-D2** | EVM `ecrecover` precompile 叶 | **engineering done**（tag 23 + STATICCALL `0x01` + Anvil companion）；2026-08-19 补：已纳入 host-syscall predicate |
| **CRYPTO-D3** | Solana ed25519 | **挂 B-CALL-SEM**（Ed25519 程序不可 CPI；账户 metas/sysvar 叙事；未拍前不可诚实编码） |
| **CRYPTO-D4** | NEAR verify | **待人拍**（2026-08-19 复核：`20-host-function-survey` 列 `ed25519_verify` host，与本桶「无一等廉价 verify」旧判断冲突；若拍 yes，形态类 NEAR sha256Bytes 叶——新 QN + Bytes ABI + view 政策，且**不**声称 IBC Tendermint 验签） |

---

## 4. 实现序（2026-08-19 刷新：交付记录 + 剩余项）

### 已交付波次（均 engineering，非 formal）

1. SYS-S5 三叶（sha256：EVM/Solana/NEAR）+ keccak 三叶 — 2026-08-13 前。  
2. CRYPTO-D2 EVM ecrecover 叶 — 2026-08-13。  
3. CAP-4 Soroban sha256 / CAP-5 TON sha256 — 2026-08-16（owner 拍板）。  
4. CAP-X-BYTES（B1：sha256Bytes 共享核+五叶）— 2026-08-19（owner 拍板）。  
5. CAP-X-MERKLE（C1 变体+C2：merkleVerifyKeccak256 EVM-only）— 2026-08-19（owner 拍板）。  
6. ecdsa host-syscall predicate 修复 — 2026-08-19（owner 接受 digest cut over）。

### 剩余项（全部须人拍，勿自动开）

1. **签名叶**：NEAR `ed25519_verify`（先纠正 D4 旧判断）；Solana ed25519（B-CALL-SEM 前置）；TON `check_signature` / CW `env.ed25519_verify`（另批；TON 仅解冻过 sha256 一项）。  
2. **Merkle 变体**：`merkleVerifySha256`（ICS-23 向）或 positional/indexed proof——各自独立 QN，独立拍板。  
3. **余 target keccak/sha256 叶**：CW（无 sha256 host，保持 F）、Psy（gadget 不得冒充 SHA-2）、电路类（约束声称问题）。  
4. **B2 流式**：永久 FC，勿开。

### 明确不做（避让，不变）

- 改 `TargetRegistryV1` / `RequirementResolverV1` / `DescriptorDataV1` / ADR-0036  
- Move / Aptos / Sui（产品 **wontfix**）  
- Cairo/risc0/sp1 materializer（等 `TGT-ZKVM-SECOND` 级决策）  
- 把 Merkle 写成 IBC/ICS-23 已支持（NS-2 仍 language-gated）

---

## 5. SupportClaim / resolver 意图（未来）

每条 crypto QN × target × profile 一行；缺失 = resolve 失败。  
禁止「extension.crypto 一开全开」。Psy gadget 与 S5 sha256 **分 catalog 段** 或分 requirement id，避免 digest 混谈。  
（2026-08-19 注：工程现实仍是各 Lower 命名 FC + `isPfCryptoHostSyscallQnV1` 纪律；formal SupportClaim/resolver 不变。）

---

## 6. 非声称

- 不声称 EXT-CRYPTO 完成（剩余项见 §4）。  
- 不声称跨链哈希语义相同（仅 QN 与域宽约定相同；五叶 N 上限互不相同）。  
- 不声称 Merkle = IBC/桥可用；不声称 positional proof。  
- 不声称 formal / hermetic / 主网。  
- 不把电路内 hash 写成链上事件已发生。

---

## 7. Backlog

| ID | 状态 |
|---|---|
| **EXT-CRYPTO-DESIGN** | **done**（本文 RPT-027） |
| **EXT-CRYPTO** | 实现总账：**B1/C1变体/C2/D2 + S5 五叶已 done**；剩余子项（签名叶、Merkle 变体、余 target 叶）均须人拍——见 §4 |
| **TGT-MOVE-DOSSIER** | **wontfix**（产品决定） |
