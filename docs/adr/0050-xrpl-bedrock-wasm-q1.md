---
id: ADR-0050
title: XRPL Bedrock opt-in WASM Q1 dual profile (ambient rustc → .wasm extra)
status: proposed
owner: architecture
updated: 2026-08-17
normative: true
---

# ADR-0050：XRPL Bedrock opt-in WASM Q1 dual profile（ambient rustc → `.wasm` extra）

## 状态

proposed

## 背景

ADR-0049 已交付 XRPL Q0：sole default profile `xrpl-bedrock-source-u64-v1`，Lean
发射 Bedrock 形 `{name}.rs`，zero-tool finalize，无 rustc / wasm-opt / bedrock /
AlphaNet / 主网。

Commons scaffold-xrp 的真实编译面是：

```text
cargo build --target wasm32-unknown-unknown --release
→ target/wasm32-unknown-unknown/release/{package}.wasm
```

依赖钉在 `Transia-RnD/craft` 的 `dangell/smart-contracts` 分支。分支引用不是
hermetic lock；本 ADR 把它冻成 **exact commit**。

本 ADR 打开 **下一独立 codegen profile**，只覆盖 locked/ambient rustc → `.wasm`
extra。严格不进入 `ContractCreate` / `ContractCall` / AlphaNet / 主网。形态对齐
OpenVM 的 source 默认 + ELF opt-in 双 profile 纪律（ADR-0046）：默认仍
zero-tool；opt-in profile 才调用工具。

## 决策

1. **双 profile（同一 Plan/IR 表面）**
   - 默认 / 既有：`xrpl-bedrock-source-u64-v1`（ADR-0049；zero-tool；不变）
   - 新增 opt-in：`xrpl-bedrock-wasm-u64-v1`
2. **Registry**：`xrpl` 仍为 implemented；profiles 升为
   `#[xrpl-bedrock-source-u64-v1, xrpl-bedrock-wasm-u64-v1]`（ASCII 升序），
   **default 仍为** `xrpl-bedrock-source-u64-v1`。maturity 保持 `source-only`
   （`.wasm` 为 engineering extra，不升 deployable，不改 accepted Phase 1）。
   工程计数仍为 **13 = 13 implemented + 0 design-only**。resolver 行数
   **16 → 17**（XRPL×2）。
3. **ArtifactEncoding**：descriptor 默认编码仍为 `xrplBedrockSource`（与 OpenVM
   默认 `openvmGuestSource` / Noir 默认 `noirSource` 同纪律）；WASM profile 经
   Finalize extras 附加二进制，不新开 encoding enum。
4. **Guest 表面（两 profile 共享 base materialize）**：Lean 继续只发射单个
   `{program}.rs`（ADR-0049 Q0 形状）。WASM Finalize 在临时 crate 里包装该
   `.rs`，不把 `Cargo.toml` 写进 product disk-closure。
5. **Crate / stdlib pin（文字钉，不是 Tool Lock 可复现 rustc 二进制）**
   - crate-type `cdylib`；edition `2021`
   - `xrpl-wasm-std` git `https://github.com/Transia-RnD/craft.git`
     rev `ffbe88da26df27e59a72b6202883f42f696933cc`（`dangell/smart-contracts`
     HEAD as of 2025-10-21；message `add export macro`）
   - **不**依赖 `xrpl-wasm-macros`：Q0 发射面只用 `no_mangle` +
     `get_data`/`set_data`，宏 crate 不是本 profile 的必要输入
   - target triple **`wasm32-unknown-unknown`**（scaffold-xrp 产品命令；不是
     official `ripple/xrpl-wasm-stdlib` 的 `wasm32v1-none`）
   - rustc/cargo：**ambient**（host rustup）。craft 自己的
     `rust-toolchain.toml` 声明 `1.89.0` + `wasm32v1-none`；本 profile **不**
     伪称已锁定可复现 rustc 二进制，也不把 host `1.97.1` 写成 Tool Lock
   - `requiredByProfiles` 不新增 Tool Lock 行：没有可哈希的 rustc asset
6. **Finalize（`xrpl-bedrock-wasm-u64-v1`）**
   - 校验 staging base 与 materialized `{program}.rs` bytes exact
   - 在临时目录写 `Cargo.toml` + `src/lib.rs`（= staged `.rs`）
   - 调用 ambient `cargo build --target wasm32-unknown-unknown --release --offline`
     失败时再允许一次非 `--offline` 的 pin-rev fetch（git rev 已冻；仍禁止
     branch floating）
   - 将产出的 `{crate}.wasm` 以 extra 写入稳定路径
     `xrpl-build/{program}.wasm`
   - `deployable=false`；evidence 明确：已 rustc/cargo 编译，**无** bedrock /
     rippled / `ContractCreate` / `ContractCall` / AlphaNet / 主网
   - 缺失 rustc/cargo/`wasm32-unknown-unknown` 以 `PF-TOOLCHAIN-MISSING`
     fail closed
   - 默认 source profile Finalize 行为与 ADR-0049 完全一致（零 extras）
7. **Capability**：两 profile 共用 ADR-0049 的 4-key 子集；不扩
   call/event/assets。
8. **明确排除**：AlphaNet / 主网、`ContractCreate`/`ContractCall`、bedrock CLI、
   wasm-opt、Hooks、EVM sidechain、official `xrpl-wasm-stdlib` crate 切换、
   accepted PRD 扩面、formal D3/D4。

## 理由

- 把 rustc 与 AlphaNet 部署拆开，避免 Q0 静默膨胀；与 OpenVM O1 / Noir
  compile-only opt-in 同级诚实。
- 共享 Plan/IR + 既有 `{name}.rs`，使 WASM profile 不发明第二套 Semantic 解释。
- git rev pin 禁止继续漂在 `dangell/smart-contracts` 分支 HEAD 上。

## 影响

- Resolver 行数：XRPL 由 1 行变为 2 行；总 resolver rows **16 → 17**。
- install/doctor：`xrpl` core tools 仍为空（rustc 是 ambient host 前提，不是
  Tool Lock 成员）。
- 文档：dossier `16-xrpl.md`、ADR-0049 交叉引用、task/gap 同步。
- 测试：source 默认零 extras；`--profile xrpl-bedrock-wasm-u64-v1` 在工具可用时
  产出 `.wasm` extra；工具缺失 fail closed；不声称 AlphaNet/主网。

## 备选

- 把 rustc 塞进默认 profile（拒绝：破坏 ADR-0049 zero-tool 契约）。
- Q1 直接 `ContractCreate`（拒绝：留给 XRPL-10 / C）。
- 切到 official `ripple/xrpl-wasm-stdlib` + `wasm32v1-none`（拒绝：与 A 已钉的
  scaffold-xrp / `xrpl_wasm_std` 发射面不一致；另批）。
