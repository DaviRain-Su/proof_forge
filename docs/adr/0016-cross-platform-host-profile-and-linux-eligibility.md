---
id: ADR-0016
title: 跨平台 Host Profile、per-platform Tool Lock 与 Linux eligibility
status: accepted
owner: build
updated: 2026-07-18
normative: true
approvers: architecture-owner, quality-owner
approvedAt: 2026-07-18
reviewCommit: fcdeb37645f8405830f9e68340c55ccfa78d6193
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/fcdeb37645f8405830f9e68340c55ccfa78d6193
openFindings: none
---

# ADR-0016：跨平台 Host Profile、per-platform Tool Lock 与 Linux eligibility

- 状态：`accepted`
- 日期：2026-07-18

## 背景

[ADR-0013](0013-content-addressed-tools-and-host-profile.md) 建立的两类信任分离在数据上
完全是 Darwin 形状：Host Profile v1 的 `platform`/`developerTools` 闭集只有
sip/authenticatedRoot/systemVolumeSeal/Xcode 概念；`toolchains.lock.json`（Tool Lock v2）
root `platform` 被锁定为单值 `darwin-arm64`，全部资产是 darwin 构建；Stage-0 依赖
codesign 与 Xcode 内 Git/Python。GOV-CI-001 已声明 hermetic host/toolchain/clean-room
证据 "remain local macOS development gates **until a linux host profile and locked
external tool root exist**"。

当前唯一 Darwin profile 因 SSV seal broken 且 Xcode pathname 可由当前用户替换而为
development-only，`TASK-D0-04` 的 eligible Stage-0 handoff 因此没有可用宿主。开发机同时
存在 macOS 与 Linux；V2 必须能相对两种宿主表达 hermetic 断言，同时不得削弱已发出的
Darwin genesis 证据（`TST-HOST-001`、`TST-TOOL-001`、D0-03 关闭）。

## 决定

1. **Host Profile schema v1 → v2（platform-discriminated）**：schema id 升级为
   `proof-forge.host-profiles.v2`。darwin profile 的字段集、eligibility 谓词与
   Stage-0 行为**逐字保留 v1 语义**（genesis 证据红线）；新增 linux profile 段：
   `platform{osReleaseId, osReleaseVersionId, kernelRelease, arch, secureBoot}`，
   `developerTools` 替换为 `distroTools`（git/python3/readelf 的 path/sha256/version 与
   root-owned/mutability 观察），`systemTools[]` 结构不变，
   `systemRuntime.allowedLoadRoots` 按平台取 exact 值（linux 如 `/usr/lib/`、`/lib/`、
   `/lib64/`）。consumer 对 v1 文件 fail closed 并给出迁移错误；既有 darwin profile 按
   v2 原样重登记，字段语义不变，仅 schema id 与受影响的 digest pin 在同一变更集更新。
   "恰好一个 profile" 放宽为"每个已登记平台恰好一个 active profile，consumer 按
   host 平台选择"。
2. **Linux eligibility 谓词**：`eligibleForHermetic=true` 必须同时蕴含：native arch
   （`x86_64` 或 `aarch64`，非 qemu-user/翻译）、`secureBoot == enabled`、全部
   `systemTools` 的 sha256/mode/nlink/root-owned 与 lock 精确匹配、全部 profile 路径
   非 current-user-mutable、`distroTools` pin 精确匹配、`allowedLoadRoots` exact。
   任一谓词观察不到或不可用（如无 Secure Boot 固件）**必须**记录为 ineligible 并给出
   reason；不得猜测、不得 best effort。不满足谓词的机器允许登记 development profile，
   但只产 development 证据，formal 入口继续 fail closed。
   **信任根弱化声明**：Linux 没有 Apple SSV/AMFI 的等价物；linux eligibility 的信任根是
   Secure Boot + distro 包完整性 + pinned digest，弱于 Darwin 的 SSV 锚定。该弱化必须
   写入每条 linux-eligible 证据的 limitation，且 Stage-0 在 Linux 上**没有** codesign
   等价验证步骤（不伪造平台签名检查）。
3. **Tool Lock per-platform 文件与 v3 schema**：保留单平台封闭字段集原则，按平台拆文件：
   - `toolchains.lock.json`（darwin-arm64，Tool Lock v2）：**字节不变**，`ToolLockV2Digest`
     与全部下游 identity 不受影响。
   - `toolchains-linux-x86_64.lock.json`（新，Tool Lock v3）：root 恰为
     `schema,platform,assets,compilerToolchain,bundleFiles,elfPolicy,tools,unresolved`；
     `elfPolicy{allowedSystemLoadRoots[], files[]{path, neededLibs[], runpath?}}` 取代
     `machoPolicy`；digest domain 为 `proof-forge.toolchains.v3`，算法同 v2
     （`SHA-256(domain || 0x00 || PF-JCS(validated lock))`）。`proof-forge.toolchain-lock.v1`
     仍为拒绝的 legacy domain。linux 资产首期：`lean-4.31.0-linux.zip`（与 darwin 同
     sourceCommit）、solc static linux、wabt linux、foundry linux、jv linux；lean 的
     version probe 三元组按 linux 实测重锁。
   - consumer 按 host 平台选择对应 lock 文件；平台不匹配、跨文件 ref、缺文件全部
     fail closed。supply-chain closure（SPEC-TOOL-001 inventory 节）的范围相应定义为
     "全部已提交 per-platform lock 文件的每种 leaf ref"。
4. **Stage-0 平台分派**：`scripts/verify_host_stage0.sh` 以 `uname -s` 分派。Darwin 路径
   逐字节保留。Linux 路径复用全部通用段（净化环境断言、watchdog/资源限制、TCB 节点
   检查、OpenSSL KAT、bootstrap closure digest），并：补充断言
   `LD_PRELOAD`/`LD_LIBRARY_PATH`/`LD_AUDIT`/`LD_DEBUG` 为空；解析独立的 linux bootstrap
   record（`host-bootstrap-linux.lock`，无 CODESIGN/XCODE_APP 字段，git/python3 来自
   distro 锁定路径）；跳过一切 codesign/Xcode 步骤；以锁定的 distro `python3 -I -S`
   启动 `toolchain_assets.py verify-host`。KAT digest 与各节点 digest 按 linux 实测登记。
5. **Linux clean-room 沙箱引擎不在本期**：`sandbox-exec`/SBPL 无对等物，
   `isolated-check`/`v2-clean-room-alpha` 继续仅限 macOS；Linux 上该族命令必须显式
   fail closed（报平台不支持），不得静默降级为无沙箱运行。Linux 化需要新引擎
   （bubblewrap/seccomp/netns 级别）与独立 ADR/任务。
6. **立项 `TASK-D0-09`**（Milestone D0 新增一行，调度变更）：linux host profile
   schema v2/生成器/验证器、locked linux tool root（Tool Lock v3 per-platform 文件、
   elfPolicy、linux 资产）与 Stage-0 linux 分支。现有任务不能承载：
   `TASK-D0-03` 已 `done`，完成面禁止变胖（GOV-TASK-FREEZE-001 §2）；`TASK-D0-04`
   的 outOfScope 禁止扩面，且 host/工具属外部前置（§4 R5），不得塞入其完成面；
   `TASK-D0-07` 依赖 activation 之后。故按 §4 R3 新开任务：Dependencies=`TASK-D0-03`，
   Tests=`TST-HOST-002`。本 ADR 经 Architecture + Quality 批准转 `accepted` 时，
   同变更更新 `docs/governance/task-set.lock.json` 与
   [`../04-task-breakdown.md`](../04-task-breakdown.md) 任务表（行与 lock 已随本 ADR
   一并提交，批准前该任务保持 `pending`，不得 `in_progress`）。
7. **与 `TASK-D0-08` 的耦合**：D0-08 的 closure exact counts 以其 RED 前盘点时**已提交**
   的全部 per-platform lock 文件为准并固化于冻结包；D0-09 在其前完成则 counts 含 linux
   leaf，否则只含 darwin。两任务不得互相把对方范围写入自己的完成面。

## 后果

- darwin 的 Tool Lock v2 文件、digest、Stage-0 路径、eligibility 谓词与 genesis 证据
  全部不变；`TASK-D0-03` 的关闭记录不受本 ADR 影响。
- linux-eligible profile 出现前，Linux 侧全部输出保持 development 级；formal 入口在
  Linux 上 fail closed。`TASK-D0-04` 的 host blocker 因此多一条解除路径（合格 Linux
  机器登记 eligible profile），但不自动解除：离线 `BootstrapAuthorityPolicyV1` 签发与
  authority 基建是独立前置。
- `TASK-D0-09` 交付机制（schema/生成器/验证器/资产/Stage-0 分支/CI lane）；在真实
  Linux 机器上登记 eligible profile 是 `TASK-D0-04` 的外部前置（GOV-TASK-FREEZE-001
  R5），不属于 D0-09 完成面。Ubuntu CI runner 可用于验证生成器/验证器闭环（产出
  ineligible development profile 即为正确结果）。
- hosted CI 增加 linux tool-root lane 后，GOV-CI-001 的 "Current hosted subset" 段落
  相应修订；不得把 linux lane 绿写成 hermetic 或 formal 证据。

## 验证

- `TST-HOST-002`（先 RED）：linux profile 生成器/验证器正负例——Ubuntu 观察闭环、
  digest/mode/nlink/root-owned/mutable/secureBoot 逐项负例、linux↔darwin lock 与
  profile 文件互相拒绝、v1→v2 迁移错误、观察缺失 fail closed。
- 回归：`TST-HOST-001`（darwin）逐字不变；darwin 上 `toolchains-validate`、
  `host-stage0-development`、`just ci` 全绿。
- `TST-SBOM-002` 的 counts 盘点覆盖全部已提交 per-platform lock 文件。
