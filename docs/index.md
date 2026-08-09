---
id: DOC-INDEX
title: ProofForge V2 文档导航
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# 文档导航

## 当前产品恢复

日常产品执行以根级 [`RECOVERY.md`](../RECOVERY.md) 与 [`AGENTS.md`](../AGENTS.md) 为边界，
并以 [`MIGRATION_MATRIX.md`](../MIGRATION_MATRIX.md) 的 27 行事实矩阵按 D1 → D2 → D3 → D4
区分 **formal task** 与 **工程地基**。

**当前工程路径（非 formal 完成）**：CLI 进程内单次 read →
`selectProgramV1ProductWithTheoremInventory` → CheckV1/Normalize →
`CompiledSemanticV1` → **`certifyInlineProofV1`** → capability Plan/IR → 工程制品/disk
closure（无 `--proof-bundle*`）。
工程 registry **12 = 9 implemented + 3 design-only**；**九个 materializer**
（EVM/Solana/NEAR/Noir/Aleo/Psy/Quint/CosmWasm/TON）均直连 retained `SemanticProgramV1`。
Quint：source-only `.qnt` + zero-tool finalize；CosmWasm：WAT + locked check + mock 28 tests +
wasmd Docker rung-1；TON：Tolk/BoC + sandbox 10/10（schedule `createMessage` PARTIAL）。**Accepted PRD Phase 1 仍为四目标**
（EVM/Solana/NEAR/Noir）；Aleo/Psy/Quint/CosmWasm/TON
为 engineering leaves，范围 reconciliation 待 **`DOC-ADR-SCOPE`**。Normalize 为扩展中的
子集（超出最初 Counter-only S1，仍非完整语言面）。前端监督层已于 2026-08-01 移除。

**日常工程队列**（可勾选缺口）：[`engineering-backlog.md`](engineering-backlog.md)。
**Goal 全队列执行**：[`.grok/goals/prompt-master-queue.md`](../.grok/goals/prompt-master-queue.md)（[`QUEUE.md`](../.grok/goals/QUEUE.md) + [`slices/`](../.grok/goals/slices/)）。
宽度/ABI 专项：[`roadmap-t8.md`](roadmap-t8.md)。
Op×target 格子：[`research/12-target-coverage-matrix.md`](research/12-target-coverage-matrix.md)。
Psy DPN 物化规划：[`targets/10-psy-dpn-lowering.md`](targets/10-psy-dpn-lowering.md)（lane idle）。
Aleo Instructions IR 物化规划：[`targets/09-aleo-instructions-lowering.md`](targets/09-aleo-instructions-lowering.md)（idle residual；OPTION-COMPARE done）。
Aleo 本地 sandbox（**通用** ProgramV1 → package → offline run）：[`targets/09b-aleo-local-sandbox.md`](targets/09b-aleo-local-sandbox.md)（`just aleo-sandbox -- --source … --module …`；非 ordinary ci / 非 snarkVM package-only）。
外部 ProgramV1 工程（`--root` + 模板 Hello）：[`product/02-external-program-v1.md`](product/02-external-program-v1.md)（`templates/external-aleo-hello/`；`just external-hello-smoke`）。
Hello dApp Agent 剧本：[`product/03-hello-dapp-agent-playbook.md`](product/03-hello-dapp-agent-playbook.md)。
多链客户端 catalog：[`product/04-chain-client-catalog.md`](product/04-chain-client-catalog.md) / [`product/chain-client-catalog.v1.json`](product/chain-client-catalog.v1.json)（MCP `pf_chain_catalog`）。
分发架构（CLI dist · Lean Author SDK · Host SDK）：[`product/05-distribution-and-packages.md`](product/05-distribution-and-packages.md)。
Aleo 网络维 deploy/execute：[`targets/09c-aleo-network.md`](targets/09c-aleo-network.md)（`just aleo-network`；需 endpoint+密钥+`--broadcast`；默认 Finalize 仍 `deployable=false`）。
产品面阶梯（install/doctor → CLI → MCP/SDK）：[`product/01-toolchain-install-surface.md`](product/01-toolchain-install-surface.md)（workflow `product-surface-ladder`；I0–I3 + MCP-V0 + SDK-V0 已接线；非 formal/hermetic；无默认 `deployable=true`）。
Noir ACIR 物化规划：[`targets/07-noir-acir-lowering.md`](targets/07-noir-acir-lowering.md)（lane **idle** residual；IR-0..IR-7 done；金样 `testdata/golden/noir-acir-v1/` Counter + IR-4 multi-fixture `fixtures/*` inventory + G3 circuit-hash pins + 诚实矩阵 + opt-in dual-write）。
EVM bytecode sole 权威 cutover：**仅研究暂停** [`targets/08-evm-bytecode-lowering.md`](targets/08-evm-bytecode-lowering.md)（**不** Active；用户未授权实现 lane；见 backlog `EVM-BC-RESEARCH`）。

既有 formal task 与 TaskQualification 资料继续如实保留，但不冒充工程实现完成度，也不阻塞日常开发。

**Inline proof（ADR-0027，`proposed`）**：产品 sole gate 为
`selectProgramV1ProductWithTheoremInventory` → `certifyInlineProofV1`（非 sandbox；无
`--proof-bundle*`）；hash 不含 theorem body；仅 `InvariantTheoremV1`/`StateConformsV1`；
check 报告 proofStatus；build 只门禁。**Engineering closed（narrow family）**：
legal-only simple-closure encode/decode + ordinal-0 `InvariantTheoremV1` + literal-true /
public-Bool-view same-file ordinary theorem 的真实 product `check` certified 正例；theorem
body 不改 source/semantic identity但改变 certification digest。formal TST、reachability、
target refinement、sandbox/hermetic/release 仍 open。见
[`adr/0027-inline-same-file-theorem-certification.md`](adr/0027-inline-same-file-theorem-certification.md)（**当前产品 holds authority**）、[`adr/0028-solana-explicit-accounts-pda-cpi.md`](adr/0028-solana-explicit-accounts-pda-cpi.md)、[`adr/0030-pf-assets-vocabulary-wave.md`](adr/0030-pf-assets-vocabulary-wave.md)、[`adr/0033-miniamm-asset-transaction-model.md`](adr/0033-miniamm-asset-transaction-model.md)、[`adr/0034-preservation-abi.md`](adr/0034-preservation-abi.md)（`proposed`；通用 ABI foundation 已实现；ProofKind/inventory/certifier/EvenCounter/product cutover pending；**不** supersede 0027）。

## 生命周期

| Phase | 文档 | 状态 | 进入下一阶段的条件 |
|---|---|---|---|
| 0 | [商业验证](00-business-validation.md) | `draft` | 证据达到 Go 条件或形成有时限的 founder exception |
| 1 | [PRD](01-prd.md) | `accepted` | FR/NFR/非目标/DoD 获批 |
| 2 | [Architecture](02-architecture.md) | `accepted` | 边界、不变量、威胁模型获批 |
| 3 | [Technical Spec](03-technical-spec.md) | `accepted` | 所有公共接口、状态、错误、版本和边界获批 |
| 4 | [Task Breakdown](04-task-breakdown.md) | `accepted` | 历史 release-qualification 任务与验收；当前产品执行见 Recovery |
| 5 | [Test Spec](05-test-spec.md) | `accepted` | raw artifact owner R2按single-maintainer owner waiver批准；可执行、签名与closeout门禁不变 |
| 6 | [Implementation Log](06-implementation-log.md) | `draft` | 只记录真实执行与证据；当前为 pre-acceptance alpha |
| 7 | [Review Report](07-review-report.md) | `not_started` | 规格、安全、依赖、性能、发布与回滚签署 |

## 架构图（Excalidraw）

可编辑白板图：[`diagrams/README.md`](diagrams/README.md)。在
[excalidraw.com](https://excalidraw.com) 打开 `.excalidraw` 后导出 PNG/SVG 用于 README。

## 规范入口

- 语言与语义：[`specs/language.md`](specs/language.md)、
  [`specs/source-program-wire.md`](specs/source-program-wire.md)、
  [`specs/type-effect-system.md`](specs/type-effect-system.md)、
  [`specs/semantic-core.md`](specs/semantic-core.md)、
  [`specs/semantic-program-wire.md`](specs/semantic-program-wire.md)。
- 目标求解：[`specs/capabilities-extensions.md`](specs/capabilities-extensions.md)、
  [`specs/target-registry.md`](specs/target-registry.md)、
  [`specs/target-aleo.md`](specs/target-aleo.md)、
  [`specs/materializer-protocol.md`](specs/materializer-protocol.md)。
- 公共产品面：[`specs/cli.md`](specs/cli.md)、
  [`specs/output-contract.md`](specs/output-contract.md)、
  [`specs/diagnostics.md`](specs/diagnostics.md)。
- 公共 primitive 与资源 profile：[`specs/common-types.md`](specs/common-types.md)。
- 工程可信度：[`specs/security.md`](specs/security.md)、
  [`specs/toolchains.md`](specs/toolchains.md)、
  [`specs/versioning.md`](specs/versioning.md)、
  [`specs/reproducibility.md`](specs/reproducibility.md)、
  [`specs/gate-catalog-finalization.md`](specs/gate-catalog-finalization.md)、
  [`specs/task-qualification.md`](specs/task-qualification.md)。

## 模块、目标与证据

- 模块边界：[`modules/README.md`](modules/README.md)。
- 目标档案：[`targets/README.md`](targets/README.md)。
- ADR：[`adr/README.md`](adr/README.md)。
- 调研：[`research/README.md`](research/README.md)（含特性审计 11、覆盖矩阵 12、IBC 北极星 10）。
- 工程 backlog：[`engineering-backlog.md`](engineering-backlog.md)。
- T8/T9 宽度路线图：[`roadmap-t8.md`](roadmap-t8.md)。
- 追踪矩阵：[`traceability/README.md`](traceability/README.md)（formal/release 轴）。
- 术语：[`glossary.md`](glossary.md)。

目标与 ADR/调研目录由对应工作流维护。缺失页面表示该工作流尚未完成，不能推断
目标已实现。
