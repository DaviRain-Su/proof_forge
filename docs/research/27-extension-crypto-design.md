---
id: RESEARCH-027
title: extension.crypto 设计钉（SHA-256 现状 + Merkle/签名/余 target）
status: draft
owner: engineering
updated: 2026-08-13
normative: false
---

# extension.crypto 设计钉

> **目的**：在 **不改 TargetRegistry / 不抢 Soroban·ICP·OpenVM 车道** 的前提下，固定
> `extension.crypto` / `pf.crypto.*` 的产品纪律、已交付事实、缺口与下一刀顺序。  
> **不是** 实现切片、不是 formal、不是 IBC 完成。  
> 相关：RPT-020/021 系统能力、SYS-S5 sha256 三叶（EVM/Solana/NEAR）、backlog `EXT-CRYPTO`。

状态：`draft`。日期：2026-08-13。

---

## 0. 一句话

`pf.crypto.*` 是 **按键精确、按 target fail-closed** 的能力命名空间，不是「有哈希就开放全家桶」。  
已开：`pf.crypto.sha256(UInt256)→UInt256` 在 **EVM / Solana / NEAR**。  
未开：Bytes 输入、Merkle、签名验证、其余 target 的 sha256（诚实 FC 或另开叶）。

---

## 1. 产品纪律（不可破）

1. **QualifiedName 精确匹配**：只承认文档列出的完整 QN；前缀开放或「差不多的 hash」禁止。  
2. **Target 独占 binding**：同一 QN 在不同链绑不同 host（EVM `0x02` / Solana `sol_sha256` / NEAR `env.sha256`）；禁止共享 Plan 节点假装可移植字节码。  
3. **ABI 精确**：当前 sha256 叶锁定 `UInt256→UInt256`（32B word）；`Bytes` / 流式 / 多块 **另 profile**。  
4. **Fail closed 优于假绑定**：无原生 host 的 target（例：CosmWasm 无 sha256 host）必须 Plan FC，不得用弱原语冒充（TON `string_hash`、Noir 电路压缩、Aleo BHP 等已钉诚实拒绝）。  
5. **电路/zkVM/应用链**：Noir/OpenVM/Cairo/risc0/sp1 若开放，必须标 **约束/guest 原语** 而非「链上哈希已发生」；Aleo/Psy 已有平台专用 `pf.crypto.hash*` 等，**不得**与 S5 sha256 混成同一 SupportClaim。  
6. **不扩 accepted PRD**；不改 ADR-0036 的 9+3 工程范围叙事（除非另 ADR）。

---

## 2. 已交付事实（工程，非 formal）

| QN / 面 | EVM | Solana | NEAR | CosmWasm | TON | Noir | Aleo | Psy | Quint |
|---|---|---|---|---|---|---|---|---|---|
| `pf.crypto.sha256` UInt256→UInt256 | **LOWERED**（precompile `0x02` + Anvil companion） | **LOWERED**（`sol_sha256` + Mollusk） | **LOWERED**（host `sha256` + sandbox） | **FC**（无 host） | **FC**（诚实钉） | **FC** | **FC** | **FC**（另有 hashNoPad 等） | **FC** |
| `pf.crypto.ecdsaRecoverSecp256k1` 4×UInt256→UInt256 | **LOWERED**（precompile `0x01` + Anvil companion；失败短 returndata → 零地址字，对齐 Solidity `ecrecover`，不 auto-revert） | **FC** | **FC** | **FC** | **FC** | **FC** | **FC** | **FC** | **FC** |
| 其它 `pf.crypto.*`（非 Psy 专用） | FC | FC | FC | FC | FC | FC | 见平台 gadget | hash*/keccak 子集 | FC |
| Bytes→digest ABI | FC | FC | FC | FC | FC | FC | FC | FC | FC |
| Merkle verify | FC | FC | FC | FC | FC | FC | FC | FC | FC |
| 其它签名 verify（ed25519/…） | FC | FC | FC | FC | FC | FC | FC | FC | FC |

Psy 的 `pf.crypto.hashNoPad` / `hashPad` / `hashTwoToOne` / `keccak256` 属于 **Psy DPN gadget 面**，不计入 S5 sha256 完成度，也不自动授权其它 target。

---

## 3. 缺口分桶

### A. 闭合 S5 sha256（文档/测，可选代码）

| ID | 项 | 冲突风险 | 建议 |
|---|---|---|---|
| **CRYPTO-A1** | 把 §2 表回写 `research/12` 或独立 matrix 行 | 低（docs） | 与本文件同步即可 |
| **CRYPTO-A2** | Aleo/Psy/Quint/TON/Noir/CW sha256 **FC 钉测**是否已全覆盖 | 中（改各 Lower 文件） | 他车道合并后再扫；本车道只列清单 |
| **CRYPTO-A3** | Soroban/ICP/OpenVM 新叶：sha256 **默认 FC** 直至独立 leaf ADR | **高（registry）** | **留给各实现车道**；本设计只要求默认 FC |

### B. ABI 扩面（共享核敏感）

| ID | 项 | 说明 |
|---|---|---|
| **CRYPTO-B1** | `pf.crypto.sha256Bytes` 或同 QN 多 arity | 需 Semantic/Normalize 承认 Bytes；**碰共享核** → 单独立项，避开三车道高峰 |
| **CRYPTO-B2** | 流式/多块 update+finalize | 超出 MVP；永久或远期 FC |

### C. Merkle

| ID | 项 | 说明 |
|---|---|---|
| **CRYPTO-C1** | 冻结 QN 候选：`pf.crypto.merkleVerifySha256`（精确 arity：root, leaf, path[]） | 仅设计；实现按 target 有无廉价验证 |
| **CRYPTO-C2** | EVM：纯 Yul/合约内循环 vs precompile 无 | 无标准 Merkle precompile → guest 循环 + gas 诚实 |
| **CRYPTO-C3** | Solana：无通用 syscall → 程序内或 FC | 默认 FC 直至 ADR |
| **CRYPTO-C4** | NEAR：同 C3 | 默认 FC |
| **CRYPTO-C5** | 电路 target：约束路径 vs 见证路径必须分开声称 | |

### D. 签名

| ID | 项 | 说明 |
|---|---|---|
| **CRYPTO-D1** | QN 候选分离：`pf.crypto.ecdsaRecoverSecp256k1` / `ed25519Verify` / … | **禁止** 单一 `pf.crypto.verify`；**D1 QN `ecdsaRecoverSecp256k1` 已钉** |
| **CRYPTO-D2** | EVM：`ecrecover` precompile 映射 | **engineering done（本车道）**：Plan tag 23（22=`keccak256Opcode`）+ STATICCALL `0x01` + `Examples/EcdsaRecoverCheck` + Anvil companion；其它 target 仍 FC |
| **CRYPTO-D3** | Solana：ed25519 程序 / sysvar 叙事 | 账户 metas → 挂 B-CALL-SEM 风险 |
| **CRYPTO-D4** | NEAR：无一等廉价 verify → FC 或宿主扩展 | |

---

## 4. 推荐实现序（本车道可做 / 不可做）

### 本车道（`feature-other`）现在可做

1. **本设计 RPT-027**（本文）— **done**。  
2. **CRYPTO-D2 EVM ecrecover 叶** — **engineering done**（见 §2 表；不碰 Registry）。  
3. 可选：仅 **新文件** 的 QN 草案 JSON（`docs/specs/pf-crypto-extension-v1-draft.json`）— 仍 draft，不进 resolver。  
4. 三车道合并后：在 **已实现 leaf 目录内** 补 FC 负例（不碰 Registry）；下一刀优先 **CRYPTO-C2 Merkle** 或其它 target 的签名叶。

### 明确不做（避让）

- 改 `TargetRegistryV1` / `RequirementResolverV1` / `DescriptorDataV1` / `ADR-0036`  
- Soroban / ICP / OpenVM 的 crypto leaf（各车道自己的默认 FC）  
- Move / Aptos / Sui（产品 **wontfix**）  
- Cairo/risc0/sp1 materializer（等 OpenVM 后 `TGT-ZKVM-SECOND`）

### 他车道合并后的第一刀代码（建议）

1. **CRYPTO-C1+C2**：EVM-only Merkle verify MVP（若产品要 IBC/桥）**或**  
2. 其它 target 的签名叶（Solana ed25519 / NEAR FC 钉）  
`CRYPTO-D2` 已在本车道闭合；勿重复开 EVM ecrecover。

---

## 5. SupportClaim / resolver 意图（未来）

每条 crypto QN × target × profile 一行；缺失 = resolve 失败。  
禁止「extension.crypto 一开全开」。Psy gadget 与 S5 sha256 **分 catalog 段** 或分 requirement id，避免 digest 混谈。

---

## 6. 非声称

- 不声称 EXT-CRYPTO 完成。  
- 不声称跨链哈希语义相同（仅 QN 与域宽约定相同）。  
- 不声称 formal / hermetic / 主网。  
- 不把电路内 hash 写成链上事件已发生。

---

## 7. Backlog

| ID | 状态 |
|---|---|
| **EXT-CRYPTO-DESIGN** | **done**（本文 RPT-027） |
| **EXT-CRYPTO** | 仍 **pending**（实现总账）；子项按 §3 拆波 |
| **TGT-MOVE-DOSSIER** | **wontfix**（产品决定） |
