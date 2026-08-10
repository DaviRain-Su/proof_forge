---
id: ADR-0040
title: Engineering host mode and external-author distribution bundle
status: proposed
owner: product+engineering
updated: 2026-08-10
normative: true
---

# ADR-0040：Engineering host mode 与外部作者 bundle 分发

## Status

`proposed`（2026-08-10；实现切片进行中）

## Context

外部作者与 Agent 无法以「克隆 monorepo + `lake build` + 手改 `host-profiles.lock.json`」
作为默认路径。慢点不在 Yul→solc，而在：

1. `proof-forge-next` **不在** crates.io；Release 曾只打 next、与 `pf` 分轨；
2. embedded host lock 钉死 Mint/特定 Darwin 的 `stat`/`env` digest，Debian/Ubuntu 直接
   `PF-TOOLCHAIN-MISMATCH`；
3. `pf setup` 以 copy-paste 为主，未把 `proof-forge-next install` 串成幂等装齐。

关联：ADR-0013/0016（host profile / hermetic 资格）、ADR-0037（`pf` ≠ compiler 权威）、
[`docs/product/14-external-author-mvp.md`](../product/14-external-author-mvp.md)。

## Decision

### D1 — 外部作者永不 `lake build`

产品默认安装与支持路径 **禁止** 要求 monorepo `lake build`。贡献者 monorepo 路径保留为
第二轨文档，不得出现在 `pf setup` NEED 的唯一建议里。

### D2 — `HostMode`：engineering 默认 `dev`

| Mode | 何时 | 行为 |
|---|---|---|
| **`dev`**（默认；`PROOF_FORGE_HOST_MODE` 未设 / `dev` / `engineering`） | 外部作者、日常 `pf build` | 使用本机 `/usr/bin/stat` 与 `/usr/bin/env`，**不**对照 embedded host lock digest；**仍** exact 校验 Tool Root 内 Tool Lock 工具 |
| **`hermetic`**（`hermetic` / `formal` / `strict`） | lock-native CI / formal | 现行为：`singleHostProfile` + `host:stat`/`host:env` digest pin |

- Dev 模式 **不** 声称 `eligibleForHermetic`、Stage-0、formal。
- Hermetic 失败 stderr 必须给出 `export PROOF_FORGE_HOST_MODE=dev` 可复制修复行。

### D3 — EVM public testnet broadcast

v0：**默认拒绝** public testnet broadcast；`--broadcast` 仅 `local`（既有 safety）。
若未来开放 testnet，必须显式 opt-in + key 仅 env + 与 `pf setup` 文档一致。本 ADR 不改 safety 表。

### D4 — `pf` 与 `proof-forge-next` 同 `VERSION` 打包

- 根目录 `VERSION` = Lean `ProductVersionV1.productVersionV1` = `proof-forge-pf` Cargo version。
- Engineering Release 主资产为 **bundle**：
  `proof-forge-bundle-<ver>-<platform>.tar.gz`
  含 `pf`、`proof-forge-next`、`scripts/`（doctor/install 引擎）、Tool Lock pins、`VERSION`、`INSTALL.md`。
- 可保留 next-only tarball 一版兼容；新文档默认指向 bundle。
- crates.io 仍只发 orchestrator；compiler 永不进 crates.io。

### D5 — Agent 双轨

| 轨 | 能力 |
|---|---|
| 本机 stdio MCP | spawn 本机 `pf` / `proof-forge-next`（需用户已 bootstrap） |
| 远程 edge MCP | docs / catalog / network metadata only；**不**装成可 compile |

### Bundle 与 setup

- `pf bootstrap` / `install.sh`：检测平台 → 校验 sha256 → 装到用户前缀 → PATH。
- `pf setup --target T -y`：缺 compiler 时提示 bootstrap URL；有 compiler 时 spawn
  `proof-forge-next install --targets T --yes`（及可选 runtime）；结束 doctor 无 NEED（core）。

## Consequences

- 非 Mint Linux 可在 dev 模式下 finalize EVM（Tool Root solc 仍 pin）。
- Hermetic 证据与 engineering 日常路径分离；不得用 dev build 冒充 hermetic。
- Release CI 必须增加「干净 Ubuntu + 仅 bundle → new → build」smoke，否则不得打
  engineering-dist 为外部作者可用。

## Non-goals

- 远程 MCP 持 key / 默认 broadcast
- 第二 Tool Lock 或 PATH 扫盘装工具进 Tool Root
- formal Stage-0 / clean-room 完成

## Implementation anchors

- `ProofForgeV2/Materialization/LockedToolchainV1.lean` — `HostMode` / `resolveHostMode`
- `ProofForgeV2/Core/Diagnostic.lean` — toolchain 错误 fix-up 行
- `scripts/package_bundle_dist.sh` — bundle packager
- `clients/pf-cli` — `pf bootstrap` / setup `-y` / version JSON
- `docs/product/14-external-author-mvp.md` — 执行队列与 AC
