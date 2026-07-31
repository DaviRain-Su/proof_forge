---
id: ADR-0017
title: 研究期新增目标 TON/TVM、Move (Aptos/Sui)、Cairo、RISC Zero/SP1
status: proposed
owner: architecture
updated: 2026-07-18
normative: true
---

# ADR-0017：研究期新增目标 TON/TVM、Move (Aptos/Sui)、Cairo、RISC Zero/SP1

- 状态：`proposed`
- 日期：2026-07-18

## 背景

[ADR-0011](0011-static-target-registry.md) 建立静态目标注册表；PRD 把 Phase 1 锁定为
`evm`/`solana`/`near`/`noir` 四个实现目标，并把 `cosmwasm`/`soroban`/`icp`/`openvm`/
`aleo`/`psy` 列为设计但不实现的目标。当前 `docs/targets/` 覆盖这 10 个 `TargetId`，
归入 6 个 family 视图（EVM contract VM、SVM explicit-account、Wasm host、ZK circuit、
zkVM、ZK application chain）。

为扩大研究覆盖面，需在不触动 Phase 1 锁定边界、不开 TASK、不实现 materializer 的前提下，
把以下平台纳入研究期 dossier：TON (TVM)、Aptos 与 Sui (共享 Move VM)、Starknet (Cairo)、
RISC Zero、Succinct SP1。这些平台既非 EVM/SVM 也非 Wasm host（TON/Move），或在 zkVM 轴上
与 OpenVM 同族但执行模型不同（Cairo 的 STARK-proven Cairo VM、RISC Zero 与 SP1 的 RISC-V
zkVM）。它们当前都没有 dossier、family 归类或 registry 条目。

本 ADR 只决定研究期登记与 family 归类；不决定实现顺序、不创建 `TASK-*`、不修改
`TargetId` 枚举或 `Registry.lean`。任何 materializer 实现须由后续独立 ADR 与冻结任务在
Phase 1 DoD 闭合后驱动。

## 决定

1. **新增 6 个研究期 `TargetId`，maturity 为 `research`**：`ton`、`aptos`、`sui`、
   `cairo`、`risc0`、`sp1`。研究期 dossier ceiling 为 `research`：只有资料与 family 归类，
   没有 decision-complete dossier、没有 `TargetDescriptor`、没有 capability/extension、
   没有制品或运行/证明证据。不得把本 ADR 写成这些 target 的 specified/prototype 或更高
   maturity。
2. **family 归类**：
   - `ton` → 新 family **TVM Stack-Account**（`docs/targets/family-tvm-stack-account.md`，
     `FAMILY-TVM-STACK-ACCOUNT`）。TON 的 Threaded Virtual Machine 是栈式、account-based
     但既非 EVM 也非 SVM 也非 Wasm；不能塞进既有 6 个 family。
   - `aptos`、`sui` → 新 family **Move Resource VM**（`docs/targets/family-move-resource-vm.md`，
     `FAMILY-MOVE-RESOURCE-VM`）。两链共享 Move VM 与 resource-oriented 模型，但作为两个
     独立 `TargetId`，由各自的 `NetworkProfileId` 区分链；这是
     [ADR-0009](0009-separate-target-codegen-network-profiles.md) 三个独立身份的典型用例，
     不得合并为单一 target。
   - `cairo` → 既有 **zkVM** family（`docs/targets/family-zkvm.md`）。Cairo VM 是被 STARK
     证明的虚拟机，证明的是一段 VM 执行而非算术电路 DSL，与 OpenVM 同属 zkVM 轴；但其 ISA、
     prover、continuation 模型与 OpenVM 的 RV32IM 不同，dossier 必须明确差异，不得复用
     `OpenVmPlan`。
   - `risc0`、`sp1` → 既有 **zkVM** family。二者为通用 RISC-V zkVM，与 OpenVM 同轴；dossier
     必须区分 guest ABI、proof 系统、cycle/递归与 settlement 假设，不得共享 Plan 类型。
3. **Phase 1 边界不变**：本 ADR 不修改 PRD 的 Phase 1 四目标、不修改 FR-008、不新增
   `FR-*`/`NFR-*`、不新增 `TASK-*`/`TST-*`。研究期 target 不进入
   `docs/traceability/requirements-matrix.md`（该矩阵行要求非空 TASK/TST 轴）。它们只登记在
   `docs/targets/README.md` 的 TARGET-INDEX 表与各自的 dossier。`Registry.lean` 的
   `phase1`/`researched`/`descriptor?`/`materialize` 全部不动；`TargetId` 枚举不新增构造子，
   因此本期这些 target 在编译器中不可寻址，`checkSupport`/`materialize` 对其继续 fail
   closed（当前枚举不含它们，`parse?` 返回 `none`）。
4. **命名**：`TargetId` 字面量为 `ton`、`aptos`、`sui`、`cairo`、`risc0`、`sp1`（小写、
   无分隔符）。dossier 文件按现有编号续排：`11-ton.md`、`12-aptos.md`、`13-sui.md`、
   `14-cairo.md`、`15-risc0.md`、`16-sp1.md`；frontmatter id 分别为 `TARGET-TON`、
   `TARGET-APTOS`、`TARGET-SUI`、`TARGET-CAIRO`、`TARGET-RISC0`、`TARGET-SP1`。
5. **与既有 ZK 边界的关系**：`cairo`/`risc0`/`sp1` 归 zkVM 轴，遵守
   [ADR-0008](0008-separate-zk-execution-models.md)：zkVM（prove VM execution）与 ZK circuit
   （`noir`，编译为算术电路 DSL）和 ZK application chain（`aleo`/`psy`，带链状态与
   finalization）三者分离，不得共用 Plan/TargetIR。`ton`/`aptos`/`sui` 属非 zk 的 L1 VM 轴，
   与 zkVM/circuit/ZK 链无 Plan 共享。
6. **source 注册与验证限制**：本 session 未配置 web 访问（`/web-tools` 未运行），无法对
   外部文档做内容快照或访问验证。因此本批 dossier 只以官方文档的 markdown 链接形式引用
   来源，**不**登记 `SRC-*` 条目，也**不**登记 `CLM-*` claim。`docs/research/source-register.json`
   与 `docs/research/claim-register.json` 本期不变。待 web-tools 配置后，由独立后续变更按
   [ADR-0013](0013-content-addressed-tools-and-host-profile.md) 的访问/快照纪律补齐
   `SRC-*`/`CLM-*`，并把 dossier 的"来源"段从 plain link 升级为 `SRC-*` 引用；在该补齐之前，
   这些 dossier 不得作为 specified 或更高 maturity 的输入，也不得驱动任何 TASK。

## 后果

- `docs/targets/` 新增 6 个 dossier 与 2 个 family 文档；`docs/targets/family-zkvm.md`
  增列 Cairo/RISC Zero/SP1 候选说明；`docs/targets/README.md` 的成熟度表与 family 视图列表
  相应扩展。`docs/adr/README.md` 增列 ADR-0017 行。
- PRD 的"范围与非目标"段把研究期候选 target 列入"设计但不实现"的扩展清单，明确不进入
  Phase 1；不新增 FR/NFR。
- 编译器代码零改动：`TargetId` 枚举、`Registry.lean`、materializer、Plan/IR 类型全部不变。
  若未来要把任一研究期 target 推进到 specified 或实现，必须先：
  (a) 新增独立 ADR 决定其 `TargetDescriptor`、capability/extension、Plan/TargetIR schema；
  (b) 把构造子加入 `TargetId` 枚举与 `Registry.lean` 的 `researched`/`descriptor?`/`materialize`；
  (c) 按 `GOV-TASK-FREEZE-001` 立项冻结任务后才能 in_progress。
- family 归类是阅读视图，不进入用户源码（统一 `program ... where` 入口不变，无用户可写
  顶层类别标记，遵守 [ADR-0002](0002-unified-program-dsl.md) 与
  [ADR-0003](0003-target-selects-materialization.md)）。
- Aptos/Sui 共享 Move VM 但为两个 `TargetId`，确立 ADR-0009 的 Target/Network 分离在
  共享 VM 链上的应用范式；后续若出现更多 Move 链，按同一范式新增 `TargetId` 而非扩
  现有 target。

## 验证

- 本变更纯文档。静态校验：`python3 -I -S scripts/docs_check.py` 通过；`git diff --check`
  干净。
- 不运行 target 构建或测试（无代码改动，无 materializer）。
- dossier frontmatter `status` 为 `proposed`、`normative` 为 `true`；family 文档
  `status` 为 `draft`、`normative` 为 `false`，与既有 family 文档一致。
- 本 ADR 为 `proposed`，需 architecture-owner 与 quality-owner 评审接受后才可驱动后续
  specified/实现 ADR；在此之前不得把任一新 target 写入 registry 或任务。