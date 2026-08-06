---
id: PLAN-SOLANA-U1-P3-OWN
title: Solana U1 P3 并行 lane 文件所有权
status: draft
owner: engineering
updated: 2026-08-06
normative: false
---

# Solana U1 P3 — 文件所有权（并行 lane）

配套设计：[`solana-u1-p3-body-cpi-synthesis.md`](solana-u1-p3-body-cpi-synthesis.md)。

## 硬规则

1. **Sole integration = `main`**；lane worktree 文件不重叠。  
2. **禁止** 并行改同一 Lean 文件（即使「只加 def」）。  
3. 新模块优先于在 2k+ 行巨石上叠 patch，减少冲突。  
4. `docs/adr/0032*`、`docs/engineering-backlog.md`、`docs/targets/02-solana.md`、SBOM、`lakefile`/`justfile`/CI：**仅主代理串行**。  
5. `runtime-tests/solana/**`：独立 runtime lane；**不** 与 materializer Lean 同 PR 除非主代理编排。  
6. Lane C（本文设计）**只** 拥有 `docs/plan/solana-u1-p3-*.md`。

## 切片 × 所有权矩阵

| 切片 | 独占可写 | 只读依赖 | 禁止触碰 |
|---|---|---|---|
| **P3-0 设计** | `docs/plan/solana-u1-p3-body-cpi-synthesis.md`、`docs/plan/solana-u1-p3-file-ownership.md` | ADR-0032、Solana Targets/* | 一切代码 / Tests / supply-chain |
| **P3-a 显式 FC 诊断**（可选过渡） | `EmitSbpfAsmV1.lean` **仅** `buildFromCapability` 尾部分支（或抽 private helper 到新文件更佳） | `CpiProductV1`、Semantic wire | `CpiEscrowIRV1` 大改、Finalize、runtime |
| **P3-b 帧合同** | **新建** `ProofForgeV2/Targets/Solana/ProductFrameV1.lean`；可选极小 re-export 自 `CpiEscrowIRV1` 的常量 **只读引用**（复制数值 + 单测对齐，避免改巨石） | `CpiEscrowIRV1` frame 常量名、`maxSbpfStackBytesV1` | Emit 实现、Plan derive |
| **P3-c 合成 skeleton** | **新建** `ProductSynthesizeV1.lean`；`CpiProductV1.lean`（base files 入口改 thin）；`EmitSbpfAsmV1.lean` dispatch 收敛；`EmitIRV1.lean` 仅当需 export `fullBodyIr*` 可见性 | LowerSemantic、CpiPlan、ProductFrame | `EmitCpiEscrowSbpfV1` 大改、runtime、ADR |
| **P3-d site hooks** | `ProductSynthesizeV1.lean`；**抽取** invoke recipe helpers 时优先 **新建** `ProductCpiRecipesV1.lean` 从 `EmitCpiEscrowSbpfV1` 迁出共享（迁出 PR 单独、短） | `emitCpiProductSbpfV1` 行为钉测 | 同时改 Token/ATA/System 专用 preactivation emitters |
| **P3-e CFG×site** | `ProductSynthesizeV1.lean`；必要时 `EmitSbpfAsmV1.lean` region/label helpers | EmitIR Operation 表面 | LowerSemantic 语义改写 |
| **P3-f Map+site demo** | **新建** `Examples/BodyCpiMapTip.lean`（名可调）；**新建** `Tests/Product/BodyCpiMapTipSolanaV1.lean`；lakefile/Tests 注册 **主代理** | 合成器已支持 Index* | MiniAmm 源改写、Token catalog |
| **P3-g Finalize 诚实** | `FinalizeV1.lean`；`CpiProductV1.lean` bindings 若尚未统一 | Product pins | runtime-tests |
| **P3-h layout + Mollusk** | `EmitSbpfAsmV1.lean` multi-account offsets；`runtime-tests/solana/**`；scripts | 合成器 API 冻结 | 并行改 ProductSynthesize |

## 建议新建模块（减少巨石冲突）

| 建议路径 | 职责 |
|---|---|
| `ProofForgeV2/Targets/Solana/ProductFrameV1.lean` | 统一 `r10` 区域：role table / slots / body temps / CPI scratch；pure 预算 |
| `ProofForgeV2/Targets/Solana/ProductSynthesizeV1.lean` | Plan + full-body IR → product assembly text；site 锚点插入 |
| `ProofForgeV2/Targets/Solana/ProductCpiRecipesV1.lean` | 自 escrow emitter 抽出的 invoke/siteChecks 文本配方（可选第二 PR） |

**不** 新建第二套 Map lower：Map 继续 `LowerSemanticV1` → `EmitIRV1` → 既有 `EmitSbpfAsmV1` op 实现。

## 现有巨石「谁可以碰」

| 文件 | 约行数 | 可碰切片 | 备注 |
|---|---|---|---|
| `LowerSemanticV1.lean` | ~4.1k | 尽量只读；仅当 caller leaf 统一需要最小补丁 | 新 body 能力不得只进 shim |
| `CpiEscrowIRV1.lean` | ~3.1k | P3-d 若必须放宽 straight-line——**强烈倾向不扩 body op**，改走 synthesize | 避免 R2 |
| `EmitCpiEscrowSbpfV1.lean` | ~2.8k | 仅 recipe 抽取 PR | 产品 `emitCpiProductSbpfV1` 行为锁 |
| `EmitSbpfAsmV1.lean` | ~2.3k | P3-a/c/e/h 分 PR，禁止三 lane 同改 | dispatch 尽快变 thin |
| `CpiDeriveV1.lean` / `CpiPlanV1.lean` | 大 | 只读 unless site anchor 缺口 | Plan 权威 |
| `CpiProductV1.lean` | ~210 | P3-c/g | 保持 base 文件序 |
| `FinalizeV1.lean` | 中 | P3-g only | sole buildFromCapability |
| `MaterializationV1.lean` | 小 | 通常不改 | tagged sum 入口 |

## 测试注册所有权

| 动作 | 所有者 |
|---|---|
| 新 `Tests/Product/*` / `Tests/Materialization/*` 文件 | 实现该 demo 的 lane |
| `Tests.lean` / `Tests/Fast.lean` / `Tests/Shards/*` / `lakefile.lean` 注册 | **主代理** 或与 lane 串行单一 PR |
| `just solana-runtime` / Mollusk fixture | runtime lane |

## 并行示意（无文件重叠时）

```
        P3-0 (docs)
           │
        P3-b (ProductFrameV1)  ──可与──  P3-a 诊断（若抽到新文件）
           │
        P3-c (Synthesize skeleton + MiniAmm pin)
           │
        P3-d (site hooks)
           │
     ┌─────┴─────┐
  P3-e CFG     P3-g Finalize（若 c 已真 IR，可早做）
     │
  P3-f Map demo
     │
  P3-h layout/Mollusk（runtime lane）
```

## 冲突升级

若两 lane 都需要改 `EmitSbpfAsmV1.lean`：  
1) 先抽 helper 到新文件的 **短串行 PR**；或  
2) 主代理 rebase 排队。  
禁止 long-lived 分叉改同一巨石。
