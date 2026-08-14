---
id: ADR-0045
title: OpenVM guest-source O0 capability-gated target integration
status: proposed
owner: architecture
updated: 2026-08-13
normative: true
---

# ADR-0045：OpenVM guest-source O0 capability-gated target 集成

## 状态

proposed

## 背景

OpenVM 是模块化 zkVM：guest 经 RV32IM ELF/VmExe 执行并可生成 application、STARK
或 EVM-oriented proof（ADR-0008；family-zkvm；dossier `TARGET-OPENVM`）。它不是
circuit DSL（Noir）、也不是带链上结算的 ZK application chain（Aleo/Psy）。

在本 ADR 之前，`TargetId.openvm` 已在工程 registry 中作为 **design-only** 行存在
（空 profiles、`research-only`），无 Plan/IR/materializer。Quint（ADR-0026）与
Aleo/Psy（ADR-0035）已提供 **zero-tool source-only / direct-native** engineering
leaf 先例。OpenVM O0 采用同一纪律：先冻结受控 Rust guest 源码发射，**不**在
product finalization 中调用 guest build、transpile、keygen、execute、prove 或 verify。

Accepted PRD Phase 1 仍为 EVM/Solana/NEAR/Noir（ADR-0036）。本 ADR 只把 OpenVM
提升为第 10 个 engineering materializer，不静默扩 accepted 范围，不改变 EVM-first
formal lighthouse。

## 决策

1. **身份与归类**：复用既有 `TargetId.openvm`。执行语义归类为 **zkVM guest
   workload**（ADR-0008）。**不得**复用 Noir/Aleo/Psy/Quint 或任一既有 `*Plan` /
   `*IR` 类型；不建立 `ZkPlan`。
2. **Registry（工程意图冻结）**：`TargetRegistryV1` 将 `openvm` 从 design-only
   提升为 implemented。计数变为 **12 targets = 10 implemented + 2 design-only**
   （design-only 仅 `soroban` / `icp`）。六轴保持既有 registry seed：
   - `executionHost` = `openvm-guest`
   - `commit` = `guest-external`
   - `state` = `guest-memory-io`
   - `call` = `guest-internal`
   - `proof` = `zkvm-execution`
   - `settlement` = `external-verifier`
   `CodegenProfileId` wire = `openvm-guest-source-v1`（sole product profile / default）；
   `ArtifactEncoding` = `openvmGuestSource`；
   `AcceptanceProfileRef` = `research.openvm.v1`；
   registry maturity 标签 = **`source-only`**（不可部署；无 prove/settle）。
3. **Capability（honest 4-key 子集）**：resolver **仅** 承认
   `failure.atomic-rollback`、`state.persistent`、`value.bool`、
   `value.checked-arithmetic`。显式拒绝（非穷举）：`effect.event`、
   `effect.synchronous-call`、`effect.asynchronous-workflow`、`extension.pf-assets`
   以及本 4-key 外一切 S2 键。guest-internal call 轴描述 guest 内普通调用；本
   profile **不**把 portable `call`/`schedule` 映射为 zkVM 外调或宿主 CPI。
4. **Guest 生成策略（G1）**：Lean 自 target-owned Plan/IR **渲染受控 Rust guest
   模板**（`guest/Cargo.toml`、`guest/src/main.rs`）。`Cargo.toml` 将
   `openvm-rv32im-guest = "=2.0.1"`（及 ADR 冻结的配套 crate 文本）写为**声明依赖**；
   O0 **不**执行 `cargo`/`rustc` guest 交叉编译。Lean direct guest ISA emitter
   不在本 profile。
5. **版本线意图（docs-only pin candidate）**：后续 prove profile 的唯一候选主线为
   OpenVM **2.0.x**（含 `openvm-rv32im-guest` 2.0.x）。本 O0 profile **不**写入
   Tool Lock、不调用 OpenVM CLI、不跨版本拼接命令。真实 ELF/VmExe/prove 工具链
   pin 属于后续独立 `CodegenProfile`。
6. **制品与 finalization**：engineering materializer 产出
   - `guest/Cargo.toml`
   - `guest/src/main.rs`
   - `{programName}.openvm-guest.json` catalog（`artifactKind: source-only`、
     `proofStatus: not-produced`）
   以及 manifest/evidence 侧车；`deployable=false`。**Product finalization 为零工具**：
   不 guest build、不 transpile、不 keygen、不 execute、不 prove、不 verify、不写
   Tool Lock 条目。ELF/VmExe/proof/VK/EVM-proof mode 均属后续 profile。
7. **O0 语言/CFG 子集（唯一本 profile 合法面）**：
   - 类型：仅 **anonymous** `UInt64` / `Bool` / `Unit`；
   - 状态与参数：仅 **public** `UInt64` state / params；
   - 结果：仅 **public** `Unit` / `UInt64` / `Bool`；
   - CFG：至少一个 entry；**single-block** only（无 loops / branch / switch /
     block params）；
   - 指令/op 面：literal、state load + store、checked `UInt64` `+`/`-`、比较、
     Bool `and`/`or`/`not`、pureCall inline、bare assert、zero-payload declared
     revert；
   - `OpenVmPlan` 字段：`profile`、冻结 `vmConfig` stub、`guestInputs` /
     `publicValues` / `memoryLayout` / `entry`、`enabledExtensions=[]`、
     `executableCommitment=none`、`proofMode=none`、`verifierBinding=none`；
   - 上述以外一律 **fail closed**（含 multi-width、Int、Field、Principal、String、
     聚合、named 类型、if/match/for、emit/nonzero revert payload、call/schedule、
     ContextRead/Commit、nonempty constants、nonempty invariants、pf.assets 等）。
8. **不做（本 ADR 明确排除）**：
   - 把 OpenVM 写入 accepted PRD Phase 1；
   - formal TASK/TST、formal D3 registry root / SupportClaim / BuildIdentity、
     formal D4 或 Reference↔OpenVM 差分因本 ADR **完成**；
   - product 路径上的 guest build / ELF / VmExe / prove / verify；
   - `ArtifactDeployability=verifiable-workload`（留给后续 proof/VK profile）；
   - 与其它 target 共享 Plan/IR，或第二套 Semantic 解释路径；
   - 假 install 的 OpenVM prove toolchain（doctor/SDK 不得假装可安装 prover）。

## 理由

- zkVM 与 circuit / application-chain 分离是 ADR-0008 的硬边界；O0 只诚实发射
  guest 源码，避免未 pin 的 prove 闭包进入 product finalize。
- 受控 Rust 模板对齐官方 OpenVM Rust frontend，同时把 ISA/工具链风险关在后续
  profile 门外。
- 4-key + Counter 形 single-block 子集与 Quint Q0 同级，是在不重开 multi-block /
  effect 矩阵前提下可 fail-closed 的最小纵切面。

## 影响

- 工程 registry：implemented **9 → 10**；design-only **3 → 2**（去掉 `openvm`）；
  resolver 静态行 **11 → 12**。ADR-0036 同步修订为 engineering **10 + 2**。
- `ArtifactEncoding` 新增 `openvmGuestSource`；`CodegenProfileId` 新增
  `openvm-guest-source-v1`。
- 文档：[`docs/targets/08-openvm.md`](../targets/08-openvm.md) 为 sole dossier；
  TARGET-INDEX / ADR 索引登记本决定。
- engineering leaf 接线：registry/descriptor/resolver、
  `Registry.materializeResult`/planDigest/finalize dispatch 与 exact output closure
  同源；unsupported shape 必须 target-local fail closed。

## 备选

- 保持 design-only（拒绝：O0 guest-source 子集与 4-key capability 已可决策冻结）。
- Finalize 内嵌 OpenVM CLI / prove（拒绝：版本线与 Tool Lock 成本超出 O0；留给后续
  profile）。
- Lean direct guest ISA（拒绝：本切片选择 G1 受控 Rust 模板；direct guest 需独立
  ADR）。
- 复用 Noir Plan（拒绝：circuit ≠ zkVM）。
