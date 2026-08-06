---
id: ADR-0032
title: Solana 统一 materializer（吸收单账户 body 进 sole CPI rail）
status: proposed
owner: architecture
updated: 2026-08-06
normative: true
---

# ADR-0032：Solana 统一 materializer

## 状态

`proposed`（2026-08-06）。本 ADR **冻结统一方向与分阶段合并合同**；不声称当日已删
`solana-sbpf-plan-v1` / `solana-sbpf-elf-v1` 或 formal TASK-D5。

## 问题

Solana 当前存在**刻意双轨**（ADR-0028 + epic #110–#125）：

| 轨 | Profile | 能力 |
|---|---|---|
| 单账户全语言面（历史称 legacy） | `solana-sbpf-plan-v1` / `solana-sbpf-elf-v1` | 完整 Semantic body（Map/宽字/CFG…）；**无** 多账户 / 真 CPI / `context.caller` |
| 多账户 CPI 合同 | `solana-sbpf-cpi-elf-v1` | roles / PDA / `invoke_signed` / pf.assets / **`context.caller`**；body **窄**（首切片仅 add 等） |

结果：`Examples/MiniAmm` 需要的 **Map Principal + `context.caller` + 乘除** 被拆在两条管线，无法同构。  
「有了 CPI 就什么都能」是**错误预期**——CPI epic 闭合的是**账户与调用合同**，不是 full-body materializer。

## 决策（U1）

1. **Sole product rail** 目标：`solana-sbpf-cpi-elf-v1`（及后续同 id 修订）成为 **唯一** Solana 产品物化面。  
2. **吸收** 今日 LowerSemantic/EmitSbpf 的 **全量 body 语言面** 进入该 rail 的 Plan/IR/emit（共享实现，禁止第二套假 Map IR）。  
3. **保留** multi-account / CPI site / pf_caller / frozen catalog 纪律（ADR-0028 不废，改为「统一 rail 上的账户层」）。  
4. **`solana-sbpf-plan-v1` / `solana-sbpf-elf-v1` 为过渡 shim**：合并完成前仍服务现有 Counter/Map/WideDiv 矩阵；**禁止**新功能只开在 shim 上。合并绿后默认 profile 切到统一 rail，shim 再 deprecate。  
5. **禁止** 在单账户 shim 上假开 `context.caller`（破坏 ADR-0031 pf_caller 诚实性）。caller 只在统一 rail 的 role 模型下开放。  
6. **命名**：文档逐步将 “legacy” 改称 **single-account shim**；代码标识符可分批 rename，不阻塞功能合并。

## 非目标

- 不把 dynamic/arbitrary CPI、Token-2022、schedule 等 ADR-0028 FC 面一并打开。  
- 不声称 formal / mainnet / hermetic。  
- 不一次 PR 删光 preactivation `EmitCpi*Token|Ata|…` 历史 lane（可后置清扫）。

## 阶段

| 期 | 内容 | 完成信号 |
|---|---|---|
| **P0** | 本 ADR + 命名/文档 | `proposed` 落地；targets/backlog 指向统一 |
| **P1** | Op 能力矩阵：Semantic op × unified rail | 表内 OPEN/WIP/FC 可测 |
| **P2** | **共享 body lower**：product IR 吸收 UInt64 算术 → 多叶 state → IndexGet/Set(Map) → 控制流；与 `context.caller`/state role 共存 | MiniAMM 数学在 **cpi-elf** 上 Plan/IR/asm 钉测（可无 Token transfer） |
| **P3** | **统一 emit**：body 走 EmitSbpf 全表面（或与 product asm 合成）；CPI preflight/invoke 前缀保留 | 同 ELF 含 full body + 可选 CPI sites |
| **P4** | 默认 profile = 统一 rail；shim 只读兼容或删除；`Examples/MiniAmm` 双链同构 + Mollusk 应用门 | E4 Solana 镜像 honest |

## P1 能力矩阵（初始，随合并更新）

| Semantic 族 | single-account shim | 统一 rail（cpi-elf）目标 |
|---|---|---|
| public UInt64 state load/store | OPEN | OPEN（P2：多叶） |
| UInt64 add/sub/mul/div/mod | OPEN | **P2 起吸收**（首刀：arith） |
| Map Principal / Map UInt64 | OPEN | **P2** IndexGet/Set |
| if/match/for/assert | OPEN | **P2–P3** |
| `context.caller` | FC | OPEN（已有 pf_caller） |
| `context.blockHeight` | OPEN（Clock syscall） | **P2** 接统一 leaf（今日 product 仍 defer） |
| ExternalCall / pf.assets CPI | FC | OPEN（catalog） |
| schedule / async | FC | FC |

## 实现约束

1. **单一 Materializer / TargetKind `.solana`** 不变；可保留 transitional tagged sum，但 **新 body 能力不得只进 shim**。  
2. Body 语义以 **retained `SemanticProgramV1`** 为 sole 源；禁止 source 再扫。  
3. CPI sites 与 full body **同一 handler source order** 可见（ADR-0028 § overlay）。  
4. Frame/temp 预算与 SBPF 16-bit branch 纪律（含 long-range dispatch）继续强制。  
5. 每期合并必须：聚焦 Lean 钉测 +（若触 runtime）host-optional Mollusk；ordinary `just ci` 不因 Mollusk 变红。

## 与 ADR-0028 关系

ADR-0028 仍 accepted 于 **账户/CPI 合同**。  
本 ADR 是 **body 吸收与 rail 合并** 的 successor 方向；0028 的 profile id / extension / catalog digests 在统一过程中 **exact 保持** 或经 versioned revision 原子更新，不得 silent 改 digest。

## 验收（工程，非 formal）

- [x] `Examples/MiniAmm.lean` 在 `--target solana --profile solana-sbpf-cpi-elf-v1` 下 product build 成功（vault-internal；可无 pf.assets）。
  Pin：`Tests/Product/MiniAmmSolanaV1.lean`（check/build/inspect + default-profile FC）。
  Finalize 对 hybrid 经 `buildFromCapability` 重算 base（不再要求 escrow product IR）。
- [x] 同一 profile 上 TipJar 等既有 CPI 产品不回归（`Tests/Product/TipJarSolanaV1` 绿）。
  TokenJar 同 profile 既有 pin 仍在 Fast；本切片未改 escrow emitter。
- [ ] WideDiv/Map single-account 矩阵在 shim 退役前仍绿；退役后在统一 rail 复钉。
- [ ] 文档不再把 dual-rail 写成「永久设计终点」。

## 当前进度（2026-08-06）

- P0：本 ADR。
- P2 首刀：**product body 吸收 UInt64 sub/mul/div/mod**（与 add 同 checked 纪律）。
- P2 续：**full-body hybrid**（`EmitSbpfAsmV1.buildFromCapability`）：
  - 当 `solana-sbpf-cpi-elf-v1` 且 **零 CPI sites** 且 Semantic 需要 multi-block/Map 时，
    `.s` 改走 `materializeFullBodyPlanForProductV1` + `EmitSbpfAsm`（复用完整 Map/CFG）；
  - `context.caller` 在 full-body 路径上经 `callerPrincipalLeaf`（account[1] pf_caller key）开放；
  - 有 CPI sites 的产品（TipJar 等）仍走 escrow product IR；
  - **MiniAmm product pin 已绿**（full-body hybrid ELF + `irDigest=full-body-hybrid`；零 `sol_invoke`）；
  - **multi-account admitCaller layout 已绿**：`computeInputLayoutWithCallerV1`（state + zero-data pf_caller）+ entrypoint `num_accounts==2` + `ACC1_*`；
  - **MiniAmmHybrid Mollusk 成功路径 11/11**（init / first mint / swap / later mint / zero fail / layout pin）。
  - **P3-b/c skeleton 已绿**：`ProductFrameV1` + `ProductSynthesizeV1`（zero-site full body；`buildFromCapability` sole leaf）。
  - **P3-d partial 合成已绿**：`hasSites ∧ needsFullBody` → full-body Plan
    (`admitProductExternalCall`) + empty-meta `sol_invoke_signed_c` 同 ELF
    （钉测 `BodyCpiIfPay`；IR 标记 `p3d-partial-empty-meta`）。**不是** multi-role
    AccountMeta / PDA / Token 成熟度；TipJar 直通仍 escrow multi-role。
  - **P3-f Map+CPI demo 已绿**：`Examples/BodyCpiMapTip`（Map Principal + transfer +
    scratch 纪律）product pin / synthesize 路径；仍 empty-meta partial。
  - **P3-g IR digest 已绿**：full-body hybrid `irDigest` 改为 content-bound
    `sha256:…`（domain `pf.solana.full-body-hybrid-ir.v1`）；消灭 evidence 字面
    `full-body-hybrid`；bindings 内嵌可重算 digest。
  - **P3-e multi-role system.transfer 已绿**：`ProductCpiRecipesV1` +
    `withProductMultiRoleSystemTransferV1`（IR 与 sourcePlan 同 stamp）+
    EmitSbpfAsm outer role walk / AccountMeta / System 12B invoke；sole
    `solana.system.transfer` + ≥3 outer roles → `p3e-system-transfer-multi-role` /
    `unifiedCpi`。钉测 `BodyCpiSysPay`（outerRoleCount=4）。非 system.transfer 的
    full-body sites 仍 empty-meta partial。
  - P3-h 多账户 layout + MiniAmmHybrid Mollusk 11/11 已先完成。TipJar/escrow 多
    recipe multi-role、P4 默认 profile 仍后续。
