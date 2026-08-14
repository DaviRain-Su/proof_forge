---
id: ADR-0046
title: OpenVM O1 guest-elf dual profile (build→ELF/VmExe, no prove)
status: proposed
owner: architecture
updated: 2026-08-13
normative: true
---

# ADR-0046：OpenVM O1 guest-elf dual profile（build→ELF/VmExe，无 prove）

## 状态

proposed

## 背景

ADR-0045 已交付 OpenVM O0：sole default profile `openvm-guest-source-v1`，Lean 渲染
受控 Rust guest + catalog，zero-tool finalize，无 Tool Lock、无 ELF/VmExe/prove。

官方 OpenVM 2.0.x 工作流为：

```text
cargo openvm build → RV32IM ELF + .vmexe → (later) keygen / prove / verify
```

本 ADR 打开 **下一独立 codegen profile**，只覆盖 build/transpile，严格不进入
keygen/prove/verify。形态对齐 Noir 的 source 默认 + nargo ACIR opt-in 双 profile
纪律（ADR-0035 / Noir Finalize）：默认仍 zero-tool；opt-in profile 才调用锁定工具。

## 决策

1. **双 profile（同一 Plan/IR 表面）**
   - 默认 / 既有：`openvm-guest-source-v1`（ADR-0045；zero-tool；不变）
   - 新增 opt-in：`openvm-guest-elf-v1`
2. **Registry**：`openvm` 仍为 implemented；profiles 升为
   `#[openvm-guest-elf-v1, openvm-guest-source-v1]`（ASCII 升序），**default 仍为**
   `openvm-guest-source-v1`。maturity 保持 `source-only`（ELF/VmExe 为 engineering
   extras，不升 `verifiable-workload`，不改 accepted Phase 1）。
3. **ArtifactEncoding**：descriptor 默认编码仍为 `openvmGuestSource`（与 Noir
   默认 `noirSource` 同纪律）；ELF profile 经 Finalize extras 附加二进制，不新开
   encoding enum（避免双 descriptor 表）。
4. **Guest 表面（两 profile 共享 base materialize）**：Lean 发射可编译的 minimal
   OpenVM guest：
   - `guest/Cargo.toml`：`openvm = "=2.0.1"`（及 ADR 冻结配套）
   - `guest/openvm.toml`：最小 `rv32i` / `rv32m` / `io`
   - `guest/src/main.rs`：`no_std`/`no_main` + `openvm::entry!(main)` +
     `openvm::io::read` / reveal；内嵌 O0 已有 State/entry/view 转移函数
   - `{program}.openvm-guest.json` catalog（`files` 含 `openvm.toml`）
5. **Tool Lock**：pin `cargo-openvm` **2.0.1**，git tag `v2.0.1` /
   commit `b820b25baab6c5d9b055f64e0286b6b1058e707c`，`format: cargo-git`，
   package/bin `cargo-openvm`；`requiredByProfiles` 仅含 `openvm-guest-elf-v1`。
   Host/guest Rust toolchain（含 `riscv32im-risc0-zkvm-elf`）属 host profile /
   ambient rustup 前提，**不**伪称为 Tool Lock 可复现二进制；缺失以
   `PF-TOOLCHAIN-MISSING` fail closed。
6. **Finalize（`openvm-guest-elf-v1`）**：
   - 校验 staging base 与 materialized bytes exact
   - 在临时目录调用锁定/可解析的 `cargo-openvm`：`cargo openvm build --manifest-path guest/Cargo.toml`
   - 将产出的 RV32IM ELF 与 `.vmexe` 以 extras 写入（路径稳定，如
     `openvm-build/{program}` 与 `openvm-build/{program}.vmexe`）
   - `deployable=false`；evidence 明确：已 build/transpile，**无** keygen/execute/prove/verify
   - 默认 source profile Finalize 行为与 ADR-0045 完全一致（零 extras）
7. **Capability**：两 profile 共用 ADR-0045 的 4-key 子集；不扩 call/event/assets。
8. **明确排除**：keygen、`cargo openvm run`、prove/verify、STARK/EVM aggregation、
   `ArtifactDeployability=verifiable-workload`、accepted PRD 扩面、formal D3/D4。

## 理由

- 把 Tool Lock 与 prove 拆开，避免 O0 静默膨胀；与 Noir compile-only opt-in 同级诚实。
- 共享 Plan/IR + 升格 guest 为可编译形状，使 ELF profile 不发明第二套 Semantic 解释。
- cargo-git pin 到 exact tag commit，禁止跨 2.0.x 次版本拼装 CLI 与 guest crates。

## 影响

- Resolver 行数：OpenVM 由 1 行变为 2 行（source + elf）；总 resolver rows **12 → 14**（Soroban 已在 12；再 +OpenVM×2）。
- install/doctor：`openvm` core tools 对 elf profile 需要 `cargo-openvm`；source-only
  路径仍可空工具成功。
- 文档：dossier `08-openvm.md`、ADR-0045 交叉引用、toolchain install 表同步。
- 测试：source 默认零 extras；`--profile openvm-guest-elf-v1` 在工具可用时产出
  ELF/VmExe extras；工具缺失 fail closed；prove 命令仍不存在于产品面。

## 备选

- 把 build 塞进默认 profile（拒绝：破坏 O0 zero-tool 契约与 Noir 双轨先例）。
- O1 直接 prove（拒绝：供应链与资源面过大；留给 O2）。
- Lean 直接发射 ELF（拒绝：与官方 frontend/transpile 权威冲突）。
