---
id: ADR-INDEX
title: Architecture Decision Records
status: proposed
owner: architecture
updated: 2026-08-20
normative: true
---

# Architecture Decision Records

状态：`proposed`
更新日期：2026-08-20

ADR 是 V2 架构决定的最高规范性记录。frontmatter 生命周期统一使用
`draft | proposed | in_review | accepted | superseded | archived`；未采纳的提案使用 `archived`
并在正文记录 decision=`rejected`，不得发明独立 document status。修改 accepted 决定必须新增
ADR，并在旧 ADR frontmatter 中记录 `successor`，不得静默改写历史。

| ID | 决定 | 状态 |
|---|---|---|
| [ADR-0001](0001-isolated-v2.md) | 独立 V2 工程 | proposed |
| [ADR-0002](0002-unified-program-dsl.md) | 统一 `program ... where` DSL | proposed |
| [ADR-0003](0003-target-selects-materialization.md) | target 选择物化，源码无类别 | proposed |
| [ADR-0004](0004-semantic-core-and-target-plan.md) | 语义 Core 与 target Plan 分离 | proposed |
| [ADR-0005](0005-exact-capabilities-and-extensions.md) | 精确能力/扩展，默认拒绝 | proposed |
| [ADR-0006](0006-associated-plan-and-ir.md) | 关联 Plan/TargetIR 不擦除 | proposed |
| [ADR-0007](0007-wasm-encoding-not-host-semantics.md) | Wasm 只共享编码层 | proposed |
| [ADR-0008](0008-separate-zk-execution-models.md) | circuit、zkVM、ZK 链分离 | proposed |
| [ADR-0009](0009-separate-target-codegen-network-profiles.md) | Target/Codegen/Network profile 分离 | proposed |
| [ADR-0010](0010-artifact-contract-and-provenance.md) | 制品契约与来源 | proposed |
| [ADR-0011](0011-static-target-registry.md) | 静态目标注册表 | proposed |
| [ADR-0012](0012-parent-research-only.md) | 父项目仅作研究参考 | proposed |
| [ADR-0013](0013-content-addressed-tools-and-host-profile.md) | 内容工具闭包与受信 host profile 分离 | proposed |
| [ADR-0014](0014-pinned-unicode-normalization.md) | 固定 Unicode 17.0.0 与纯 Lean NFC | proposed |
| [ADR-0015](0015-canonical-tool-lock-and-candidate-bound-sbom.md) | Tool Lock 唯一摘要与 candidate-bound SBOM | proposed |
| [ADR-0016](0016-cross-platform-host-profile-and-linux-eligibility.md) | 跨平台 Host Profile、per-platform Tool Lock 与 Linux eligibility | accepted |
| [ADR-0017](0017-research-phase-targets-ton-move-cairo-zkvm.md) | 研究期新增目标 TON/TVM、Move、Cairo、RISC Zero/SP1 | proposed |
| [ADR-0018](0018-d0-07-formal-execution-semantics.md) | D0-07 formal 执行语义：fixture 验收域、linux bwrap stage 引擎、freshness 判定与 finalizer 身份 | accepted |
| [ADR-0019](0019-single-programv1-source-authority.md) | ProgramV1 单一 source authority 与 alpha cutover | accepted |
| [ADR-0020](0020-task-scoped-formal-qualification.md) | 任务作用域 formal qualification 与 release aggregate 分离 | accepted |
| [ADR-0021](0021-task-qualification-terminal-signing.md) | Task qualification protected acceptance 的一次性终结签名 | accepted |
| [ADR-0022](0022-d1-diagnostics-contained-frontend-contract.md) | D1 diagnostic / contained-frontend 工程契约（parser 1.0.0 default、containment class、receipts、DiagnosticOriginV1） | proposed |
| [ADR-0023](0023-aleo-target-integration.md) | Historical Aleo source-language target integration；superseded by direct Aleo Instructions materialization | superseded |
| [ADR-0024](0024-ton-target-integration.md) | TON（Tolk 1.4.2 / TVM）capability-gated target 集成（第 8 个 implemented target；source-only；sync call fail closed） | proposed |
| [ADR-0025](0025-evm-caller-principal-realization.md) | EVM `context.caller` Principal realization encoding contract（`u32le(20)\|\|CALLER`；shared wire 不变；**S1-EVM Plan 已 cutover 2026-08-06**） | accepted |
| [ADR-0026](0026-quint-target-integration.md) | Quint（executable specification / model surface）capability-gated target 集成（第 9 个 implemented target；source-only；zero-tool finalize；Q0 UInt64 子集） | proposed |
| [ADR-0027](0027-inline-same-file-theorem-certification.md) | Inline same-file theorem certification（单 snapshot；hash 不含 body；in-process 非 sandbox；固定 axiom；proof gate 早于 materialize；仅 `InvariantTheoremV1`/`StateConformsV1`） | proposed |
| [ADR-0028](0028-solana-explicit-accounts-pda-cpi.md) | Solana 显式账户、PDA/bump 与真实同步 CPI v1 合同（opt-in `solana-sbpf-cpi-elf-v1` product activation；#111–#125） | accepted |
| [ADR-0029](0029-portable-cross-program-interop.md) | Portable 跨程序互通层（L1 shared semantic extensions；词表判据；custody/vault 消隐 PDA；包装层 catalog：target binding catalog + NetworkProfile asset registry；`pf.assets` 草案与 A→D 分期） | proposed |
| [ADR-0030](0030-pf-assets-vocabulary-wave.md) | pf.assets 词汇扩展波（token.transfer 四链绑定 + balanceOfSelf env-read v1.1.0 + context.caller Plan 开放 + MiniAMM 北极星；Uniswap V2 能力分解） | proposed |
| [ADR-0031](0031-system-capability-unification.md) | 系统能力统一抽象波（L1 ContextRead 扩键 caller/blockHeight/chainId/attachedValue + L2 官方链上 program 能力 catalog；能力与形态解耦；view-safety/强制等级两轴；SYS-CAP-UNIFY） | proposed |
| [ADR-0032](0032-solana-unified-materializer.md) | Solana 统一 materializer：full body 吸收进 sole CPI rail（U1） | proposed |
| [ADR-0033](0033-miniamm-asset-transaction-model.md) | MiniAMM 真实资产事务模型冻结（pre-fund + vault credit；无 transferFrom；M0 数学面 / MiniAmmAssets 资产面分工） | proposed |
| [ADR-0034](0034-preservation-abi.md) | Preservation ABI（proposed extension/amendment to ADR-0027；L1 step-preservation；通用 ABI + kind plumbing + **EvenCounter + ZeroCounter（P=`count==0`）preserving product positive GREEN**；业务主路径 D10 vs 工具 formal track 2；wave-2 通用性门闭合；supersession/MiniAmm P1 pending；禁止 MiniAmm 特例；ADR-0027 仍为 inline base authority） | proposed |
| [ADR-0035](0035-direct-native-artifact-materializers.md) | Aleo Instructions + Psy DPN direct-only materializers；删除 source/compiler lanes | proposed |
| [ADR-0036](0036-engineering-scope-and-evm-formal-lighthouse.md) | Engineering 13+0 scope（含 XRPL）、retired frontend boundary 与 EVM-first formal lighthouse | proposed |
| [ADR-0037](0037-developer-cli-pf.md) | Rust Developer CLI `pf` 与 compiler CLI 权威分离；Aleo-first 安全编排 | proposed |
| [ADR-0038](0038-evm-hashed-map-storage-profile.md) | EVM hashed-Map storage profile folded into the product default | proposed |
| [ADR-0039](0039-psy-hash-gadgets-gate.md) | Psy hash gadgets；hashNoPad/twoToOne/keccak open；hashPad emit-only | proposed |
| [ADR-0040](0040-external-author-host-mode-and-bundle.md) | Engineering `HostMode=dev` 默认 + external-author bundle（pf+next 同 VERSION）；外部作者永不 lake build | proposed |
| [ADR-0041](0041-psy-commit-public-input-gate.md) | Psy Commit / public-input binding 保持 fail-closed 直至 official checklist | proposed |
| [ADR-0042](0042-proof-bearing-near-invariant-root-erasure.md) | Proof-bearing NEAR invariant-root erasure（私有 certificate authority、exact digest/coverage binding、versioned Plan partition；当前 Reference-verified + artifact built，runtime observation 待兼容 runner；非 target-refined） | proposed |
| [ADR-0043](0043-pinned-wasmcert-provider-boundary.md) | 固定 WasmCert-Coq source/protocol、逐层 mechanization status 与 purpose-built NEAR host边界；双平台 Tool Lock activation + locked VerifiedVault product/Reference join | proposed |
| [ADR-0044](0044-soroban-source-u64-target.md) | Soroban source-only S0（`soroban-source-u64-v1` → `.rs`；zero-tool；4-key；非 Wasm/deploy） | proposed |
| [ADR-0045](0045-openvm-guest-source-o0.md) | OpenVM guest-source O0 capability-gated target 集成；11th engineering materializer；zero-tool finalize、无 guest build/prove/verify | proposed |
| [ADR-0046](0046-openvm-guest-elf-o1.md) | OpenVM O1 guest-elf dual profile：opt-in `openvm-guest-elf-v1` 经锁定 `cargo-openvm` 2.0.1 build→ELF/VmExe；默认 source 仍 zero-tool；无 prove | proposed |
| [ADR-0047](0047-icp-target-integration.md) | ICP（canister / Wasm actor）capability-gated target 集成（第 12 个 implemented；`icp-wasm-candid-u64-v1`；sync/event FC；async advertise；ICP-1/2/3） | proposed |
| [ADR-0048](0048-optional-solana-sbpf-semantics-provider.md) | exact-pinned `SbpfSemantics.Api`；production `.s` strict parse/resolve → sBPF semantics，产品 ELF rail 不变 | accepted |
| [ADR-0049](0049-xrpl-bedrock-source-u64-target.md) | XRPL Bedrock source-only Q0（`xrpl-bedrock-source-u64-v1` → `.rs`；zero-tool；4-key；非 Wasm/AlphaNet/主网/Hooks/EVM 侧链） | proposed |
| [ADR-0050](0050-xrpl-bedrock-wasm-q1.md) | XRPL Bedrock opt-in WASM Q1：`xrpl-bedrock-wasm-u64-v1` 经 ambient rustc 产出 `.wasm` extra；默认 source 仍 zero-tool；无 AlphaNet/主网 | proposed |
| [ADR-0051](0051-spec-honesty-external-call-return.md) | SPEC-honesty：external call typed return 收口（SPEC-SEM-001 `ExternalResponseV1` 升级 `returnValue?`；schedule 维持 void；accepted 后才修订 semantic-core 旧句；不关 formal TST） | proposed |
| [ADR-0052](0052-xrpl-host-capability-keys.md) | XRPL host 三键：冻 `get_parent_ledger_time` / `get_account`；`sha256` keep-FC（无 host）；**不开叶** | proposed |
| [ADR-0053](0053-call-bind-v1.md) | Call-bind v1：编译期 opt-in `proof-forge.call-bind.v1`；Wave 2 三叶 generic call 无行 fail closed（空账户 CALL / Solana accounts 另刀） | proposed |
