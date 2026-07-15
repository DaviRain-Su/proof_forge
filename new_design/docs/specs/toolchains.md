---
id: SPEC-TOOL-001
title: 工具链锁定规格
status: proposed
owner: build
updated: 2026-07-15
normative: true
---

# 工具链锁定规格

## Lock Schema

根目录 `toolchains.lock.json` 是机器可读权威：

```text
schema: "proof-forge.toolchains.v1"
tools[]: {
  id, version, sourceUrl, sourceCommit?, platform,
  archiveSha256, executableSha256, versionCommand,
  expectedVersionRegex, licenseSpdx, requiredByProfiles[]
}
```

按 `(id, platform)` 排序，JSON JCS + SHA-256。每个平台资产都有 archive 和 executable
checksum；只声明版本号不算锁定。安装器下载到 content-addressed cache，离线 build 只读
cache；普通 build 不自动下载。

## Alpha Pins 与缺口

| Tool | Exact pin | 用途 |
|---|---|---|
| Lean/Lake | `leanprover/lean4:v4.31.0`, commit `68218e876d2a38b1985b8590fff244a83c321783` | V2 compiler |
| Solidity compiler | `solc 0.8.34+commit.80d5c536` | Yul → EVM bytecode；当前已验证 |
| Foundry Anvil | `0.3.0 (5a8bd89)`；darwin-arm64 executable SHA-256 `b1d817…02cde` | EVM local runtime；当前机器已验证 |
| Foundry Cast | `0.3.0 (5a8bd89)`；darwin-arm64 executable SHA-256 `80d8e6…53c71` | deploy/call/runtime observation；当前机器已验证 |
| sBPF assembler | 未冻结、当前基线未安装 | sBPF text → ELF；Solana 仍为 plan artifact |
| WABT | `1.0.41` | Wasm validation/inspection |
| Nargo/Noir | 未冻结、当前基线未安装 | `.nr` → ACIR/witness；当前只输出 source |
| Barretenberg | 未冻结、当前基线未安装 | prove/VK/verify；当前无 proof evidence |

`toolchains.lock.json` 记录当前实际验证状态；`null` 表示该工具链尚未进入实现承诺，而不是
从 PATH 猜测版本。Noir/BB 必须先在 research source/claim register 中登记官方兼容矩阵，再
冻结 exact pair；新版本必须新建 CodegenProfile 或通过完整 compatibility gate，不得静默替换。
Foundry 的 Anvil/Cast 已按当前 darwin-arm64 二进制进入 lock；其他平台资产仍未锁定。
sBPF assembler 必须先有来源、版本、checksum 和可重跑 gate 才能从 `null` 提升。

## Resolution

执行顺序：读取 lock → 选择 host platform → 定位显式 `PROOF_FORGE_TOOL_ROOT` 下的
content-addressed executable → 重算 sha256 → 运行 version command（5 秒/64 KiB）→ exact
regex → 构造 `VerifiedToolchain`。不搜索 cwd、父目录或任意 PATH；开发模式可通过
`--tool-root` 指向隔离目录，但仍验证 checksum。

## Profile Mapping

- `evm-yul-solc-0.8.34-v1`：Lean、solc 已验证；配套
  `evm-yul-solc-0.8.34-v1-runtime` 锁定当前 darwin-arm64 Anvil/Cast，已有 Counter 本地
  runtime 开发证据，但尚非跨平台 release profile。
- `solana-sbpf-asm-v1`：Lean 已验证，assembler/ELF/runtime 未验证。
- `near-wasm-raw-u64-v1`：Lean、WABT 已验证；sandbox runtime 未验证。
- `noir-acir-bb-v1`：仅 Lean source materialization；Nargo/BB profile 尚未冻结。

## 错误与边界

`PF-TOOLCHAIN-MISMATCH` 带 tool、expected version/hash、actual version/hash/path；
`PF-TOOLCHAIN-MISSING` 不允许 required gate skip。覆盖 missing platform/asset、checksum /
version mismatch、PATH shadow、symlink executable、world-writable root、huge/hanging version、
malformed output、duplicate IDs、profile missing tool、offline cache miss、partial download、
license missing、Noir/BB incompatible、host architecture mismatch。

## 验收

关联 `NFR-001/009`、`TST-TOOL-001`、`TST-XTARGET-002`。在隔离 root 验证全部 checksums；
任意 byte 修改失败；无网络 build；manifest 记录所有实际 executable hashes。
