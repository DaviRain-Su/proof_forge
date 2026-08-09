# Business formalization queue (track 1)

**Authority:** ADR-0027（inline same-file base）· ADR-0034 D10 · INV-2 · Agents Next task  
**Mode:** autonomous runner — do **not** wait for the user to say continue  
**Sole step:** `SemanticProgramV1 → admitReferenceProgramSliceV1 → stepReferenceSliceV1`  
**Product decision (2026-08-09, user-confirmed):** 形式化验证与业务合约同文件；**ProofInstances 合约专属 lemma 库与 ClosedSubjectPin 是待拆除的捷径**。产品包最终零合约专属内容。  
**Forbidden:** second State/Effect/step · contract-specific content in `ProofForgeV2/` product modules · supersede ADR-0027 · formal TASK/TST claims · push unless user later asks · delete anything before its removal gate below

## Migration plan (wave-3′) — generic-first

### A. 通用机器下沉（contract-agnostic）

| id | status | objective |
|---|---|---|
| mig-a1-codec | pending | **Generic codec round-trip**：structure-gated `decodeSemanticProgramDataV1 (encode…)= .ok d`（即 `ProofBridgeV1` 文档声明的 remaining gap），一次证明处处可用；先写 focused 负/正测试再实现；不引入 sorry/native_decide |
| mig-a2-shape | pending | **形状族 preservation 定理**入 `ProofForgeV2/Semantic/`：对 stepReferenceSliceV1 的通用形状推理（store-constant 族等），使任意合约的同文件证明 = apply 通用定理 + decide/rfl 形状事实；复用 triple-UInt64 packaging（`4b7219a2b`） |
| mig-a3-elab | pending | Elaborator 发**结构化** `subjectDataV1`（非字节 spine）+ generic bridge；移除 subjectBytes 大 spine defeq 依赖；certifier 白名单按需放行 bounded `apply`/`decide`（审计面保持 closed） |

### B. 合约迁移（inline same-file 真正落地）

| id | status | objective |
|---|---|---|
| mig-b1-evencounter | pending | EvenCounter 改为普通合约（`Examples/` 或测试夹具）：同文件小证明走产品链；不再依赖 pin/ProofInstances；product positive 保持 GREEN |
| mig-b2-zerocounter | pending | ZeroCounter 同上 |
| mig-b3-miniamm | pending | MiniAmm L1 P1（emptyPool）：在迁移后的通用路径上完成 preserve + product；不再新增 ProofInstances golden |

### C. 删除（仅当 A+B 全 GREEN）

| id | status | objective |
|---|---|---|
| mig-c1-delete | pending | 删除 `ProofForgeV2/ProofInstances/`、`ProofForgeV2/Semantic/ClosedSubjectPinV1`；摘除 `InlineProofCertifierV1`/`ProgramElaborationV1` 对合约模块的 import；umbrella/lakefile/SBOM 清理；实例移入 `Tests/`/`Examples/` 普通验收位置；`just ci` GREEN |
| mig-c2-docs | pending | ADR-0034/0027、INV-2、Agents、research-023、document-status 记录迁移完成与「pin/库已删」事实；不 supersede 0027 |

## Legacy waves (done)

- wave-1: packaging/unpin/docs — done
- wave-2: ZeroCounter 第二实例 — done
- wave-3（旧）: MiniAmmEmptyPool golden data/decode — 已提交部分将随 mig-c1 迁移；**不再按旧模式推进 bf3-product**

## Done criteria

C 完成后：`ProofForgeV2/` 内无合约专属 proof/data/pin；三个合约以 inline same-file 普通形态保持 product certified；`just ci` GREEN；ADR-0027 未 supersede。

## Runner notes

1. 顺序严格 A→B→C；A 未完成不得动 B，C 前置 = B 全 GREEN + 用户已知。
2. 每个切片 local commit only；focused `lake build` + 触 `ProofForgeV2/**` 则 `just sbom-package-files-refresh`；docs 则 `just docs-check`。
3. 通用定理属 `ProofForgeV2/Semantic/`；合约专属内容**禁止**新增到产品包。
4. 若切片卡住 >2 次提交：标 `blocked` 写明失败定理，继续下一独立项。
5. Goal: `/goal @.grok/goals/prompt-business-formalization.md`；Workflow: `business-formalization-drain`。
