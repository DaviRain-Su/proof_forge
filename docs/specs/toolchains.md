---
id: SPEC-TOOL-001
title: 工具链锁定规格
status: proposed
owner: build
updated: 2026-08-01
normative: true
---

# 工具链锁定规格

## 信任模型

按 [ADR-0013](../adr/0013-content-addressed-tools-and-host-profile.md) 分离两类闭包，
跨平台形态按 [ADR-0016](../adr/0016-cross-platform-host-profile-and-linux-eligibility.md)：

- Tool Lock 家族：可下载、内容寻址并离线物化的 compiler/tool/runtime 资产，以及
  commit-pinned source-build（`cargo-git`）资产，按平台拆为 per-platform 文件：
  `toolchains.lock.json`（darwin-arm64）与 `toolchains-linux-x86_64.lock.json`
  （linux-x86_64）；两平台当前均为 **Tool Lock v4**（`proof-forge.toolchains.v4`）。
- `host-profiles.lock.json`：不能打包进 cache 的 host/system runtime TCB（macOS/Xcode
  或 linux distro；schema v2 见下）。

正式 hermetic 只相对于一个验证通过且 `eligibleForHermetic=true` 的 host profile。当前
Darwin profile 因系统卷 seal broken 且 Xcode pathname 可由当前 admin 用户替换而明确为
development-only；它不能关闭 `TASK-D0-03/04`。linux profile 的 eligibility 谓词与信任根
弱化声明见 Host Profile v2 节；任一谓词观察不到即 ineligible，formal 入口 fail closed。

## Tool Lock v4（当前权威；两平台）

两平台 lock 文件共享 schema 名 `proof-forge.toolchains.v4`，由 `platform` 与 policy 键区分：

| File | platform | policy key |
|---|---|---|
| `toolchains.lock.json` | `darwin-arm64` | `machoPolicy` |
| `toolchains-linux-x86_64.lock.json` | `linux-x86_64` | `elfPolicy` |

```text
schema: "proof-forge.toolchains.v4"
platform
assets[]: one of
  content-addressed download asset:
    {id, url, size, sha256, format ∈ {tar.gz, zip, file},
     auth? {type, realm, service, scope}}
  cargo-git source-build asset (no size/sha256; commit is the trust anchor):
    {id, url (HTTPS git), commit (40 lowercase hex), format: "cargo-git",
     package (cargo package name), bin (release binary name), version (SemVer)}
compilerToolchain: {
  id, version, sourceCommit, platform, assetId,
  archiveRoot, stripComponents, entryCount, unpackedSize,
  executables[] {path, sha256},
  versionProbes[] {path, args, expected}
}
bundleFiles[]: {path, assetId, member?, size, sha256, mode}
  -- only members of content-addressed download assets; never cargo-git products
darwin: machoPolicy {
  allowedSystemLoadRoots[],
  files[] {path, installId?, externalLoads[] {installName, bundlePath}}
}
linux: elfPolicy {
  allowedSystemLoadRoots[],
  files[] {path, needed[] {soname, bundlePath?}, runpath?}
}
tools[]: {
  id, version, sourceUrl, platform, assetId, executable,
  defaultPath, executableSha256 (string | null), runtimeLibrarySubdir?,
  runtimeFiles[] {path, sha256},
  versionArgs, expectedVersion, licenseSpdx, requiredByProfiles[],
  sourceBuild (null | {assetId})
}
unresolved: {barretenberg, nargo, nearSandbox, solanaAssembler}
```

root object 恰为
`schema,platform,assets,compilerToolchain,bundleFiles,(machoPolicy|elfPolicy),tools,unresolved`；
policy 键与 platform 绑定：`darwin-arm64` 必须 `machoPolicy` 且不得含 `elfPolicy`，
`linux-x86_64` 必须 `elfPolicy` 且不得含 `machoPolicy`。除 `assets[].auth` 可缺失外，
nested object 必须包含且只包含上面列出的字段，显式 nullable 字段必须保留为 `null`，不能用
缺字段代替。`unresolved` 恰含上述四个 key，value 只允许 `null` 或 canonical version string；
增加 root/nested field、unresolved key 或改变 nullable 语义必须升级 Tool Lock schema。
consumer 必须在 hash 前拒绝 duplicate/unknown/missing field、错误 JSON scalar 类型、非
canonical array order、重复 ID/path/ref 和所有 cross-reference/leaf-closure 错误。

### sourceBuild 与 cargo-git

- `tools[].sourceBuild == null`：普通内容寻址工具。`executableSha256` 必须为 64-hex 且等于
  `bundleFiles[executable].sha256`；`executable` 与 `runtimeFiles[]` 必须闭合到
  `bundleFiles` 与 macho/elf 邻接闭包（v2/v3 同规则）。
- `tools[].sourceBuild == {assetId}`：source-built 工具。`assetId` 必须等于
  `tools[].assetId` 且引用 `format: "cargo-git"` 资产；`executableSha256` 必须为 `null`；
  `runtimeLibrarySubdir` 必须为 `null` 且 `runtimeFiles` 必须为 `[]`；该工具的
  executable **不得** 出现在 `bundleFiles`（因此也不进 macho/elf policy）。闭包哈希校验
  豁免：信任锚是 git `commit`；运行时权威校验是执行 `versionArgs` 并要求
  stdout+stderr **包含** `expectedVersion`（与普通工具 version probe 相同包含语义）。
- cargo build **不**保证字节可复现，禁止对 source-built 二进制做跨主机 SHA-256 pin。
- cargo-git 资产 cache 布局：`cargo-git/<commit>/<asset-id>/`（workspace checkout +
  `cargo build --release -p <package>`；命中已构建 `target/release/<bin>` 且 version
  probe 通过则不重建）。download 资产仍为 `sha256/<asset-sha256>/<asset-id>`。

`ToolLockV4Digest` 由本规格唯一拥有，使用 SPEC-COMMON-001 PF-JCS v1：

```text
ToolLockV4Digest = SHA-256(
  "proof-forge.toolchains.v4" || 0x00 || PF-JCS(validated ToolLockV4)
)
```

`toolchainLockSha256` 只表示 retained lock file exact file bytes 的 raw SHA-256；它与
`ToolLockV4Digest` 是不同类型。所有名为 `lockDigest` 或 `toolchainLockDigest` 的 typed
identity 字段都必须消费 `ToolLockV4Digest`。编译期 active lock 选择必须 fail closed：Linux
仅接受 exact `x86_64-unknown-linux-gnu`；Darwin 接受 `aarch64|arm64-apple-darwin` 及 Lean
实际 host target 使用的 `darwinN(.N)*` 十进制 kernel-version 后缀，其他架构、vendor、OS、ABI
或畸形后缀均不得回退到另一平台 lock。legacy domains
`proof-forge.toolchain-lock.v1`、`proof-forge.toolchains.v2`、`proof-forge.toolchains.v3`
一律拒绝，禁止 fallback 或 dual-domain acceptance。
该决定由 [ADR-0015](../adr/0015-canonical-tool-lock-and-candidate-bound-sbom.md) 与
[ADR-0016](../adr/0016-cross-platform-host-profile-and-linux-eligibility.md) 的
schema-closed 规则固定；v4 同时吸收 v2（darwin/macho）与 v3（linux/elf）平台形态并加入
cargo-git/sourceBuild。

**版本串选择理由**：darwin 历史上为 v2、linux 为 v3（elfPolicy 替换 machoPolicy）。
cargo-git 资产形状与 `sourceBuild`/`executableSha256=null` 改变了 closed field 与
nullable 语义，必须升 schema。darwin **不能**占用 v3（v3 已专指 linux+elfPolicy）。
因此两平台统一升至 **v4**，以 `platform`+policy 键保留 per-platform 差异。

数组按 ID/path 排序；ID 唯一；download 资产的 size 是正整数；所有声明的 SHA-256 是 64 位
小写十六进制；URL 必须 HTTPS；member/path 必须相对且不能含 `.`、`..`、NUL、symlink 或特殊
文件。普通 build 不自动下载/构建。下载层对瞬时错误（HTTP 429/5xx、连接/超时错误）做有界
重试（4 次尝试、2/5/10s 固定退避）；4xx 与其他错误立即失败，不做 best-effort 降级。

### 历史 schema（拒绝）

- Tool Lock v2（`proof-forge.toolchains.v2`，仅 darwin+machoPolicy）与 v3
  （`proof-forge.toolchains.v3`，仅 linux+elfPolicy）已由 v4 取代；consumer 对 v2/v3
  文件 fail closed。

## Host Profile v2

`host-profiles.lock.json`（schema `proof-forge.host-profiles.v2`）按平台记录 closed 字段
集；consumer 对 v1 文件 fail closed 并给出迁移错误。每个已登记平台恰好一个 active
profile，consumer 按 host 平台选择。JSON 拒绝 duplicate key。

darwin profile（字段集与 eligibility 谓词逐字保留 v1 语义）：

```text
schema, profile.id
platform {productVersion, buildVersion, kernelRelease, arch,
          procTranslated, sip, authenticatedRoot, systemVolumeSeal}
eligibleForHermetic, ineligibilityReason (string or null)
developerTools {developerDir, xcodeAppPath, xcodeVersion/build,
                identifier/team/designatedRequirement/CDHash,
                xcodeMutableByCurrentUser, allowedRuntimeRoots,
                Git/otool path/hash/version,
                Python dispatchPath + resolved path/hash/version}
digestBootstrap {path, sha256, known-answer input/hash}
systemRuntime.allowedLoadRoots[]
systemTools[] {id, path, nodeKind, linkTarget, resolvedPath,
               resolvedNlink, mode, sha256}
```

darwin `eligible=true` 必须蕴含 native arm64、非 Rosetta、SIP enabled、authenticated root
enabled、system volume sealed 且 Xcode pathname 不可由当前用户替换（与 v1 相同）。

linux profile：

```text
schema, profile.id
platform {osReleaseId, osReleaseVersionId, kernelRelease, arch, secureBoot}
eligibleForHermetic, ineligibilityReason (string or null)
distroTools {git/python3/readelf path+sha256+version,
             root-owned, mutableByCurrentUser}
digestBootstrap {path, sha256, known-answer input/hash}
systemRuntime.allowedLoadRoots[]
systemTools[] {id, path, nodeKind, linkTarget, resolvedPath,
               resolvedNlink, mode, sha256}
```

linux `eligible=true` 必须同时蕴含：native arch（`x86_64` 或 `aarch64`，非翻译）、
`secureBoot == enabled`、全部 systemTools sha256/mode/nlink/root-owned 与 lock 精确匹配、
全部 profile 路径非 current-user-mutable、distroTools pin 精确匹配、allowedLoadRoots
exact。任一谓词观察不到或不可用（如无 Secure Boot 固件）必须记录 ineligible 与 reason，
不得猜测或 best effort；不满足谓词的机器只允许登记 development profile。

**信任根弱化**：Linux 没有 Apple SSV/AMFI 等价物；linux eligibility 的信任根为
Secure Boot + distro 包完整性 + pinned digest，弱于 Darwin 的 SSV 锚定，Stage-0 在
Linux 没有 codesign 等价验证步骤。该弱化必须写入每条 linux-eligible 证据的 limitation。

Stage 0 必须在任何 Git/Python 前由调用者直接以 `env -i`、`/bin/bash --noprofile --norc`
启动，并按 `uname -s` 分派平台路径。它用 Bash builtin 按固定顺序解析平台对应 bootstrap
record（darwin 为 `host-bootstrap.lock`，linux 为 `host-bootstrap-linux.lock`），不得
`source`/`eval`。darwin 路径先绑定 launcher、Python verifier、两份 lock、direct Xcode
Python/Git 和最小 Apple platform TCB，验证 Xcode deep/strict signature 后才允许 Python
解析完整 JSON；linux 路径没有 codesign 等价步骤，绑定 launcher、Python verifier、平台
lock 文件与 distro Git/Python 后，额外断言
`LD_PRELOAD`/`LD_LIBRARY_PATH`/`LD_AUDIT`/`LD_DEBUG` 为空，再以锁定的 distro
`python3 -I -S` 启动 verifier。OpenSSL SHA-256 KAT 只是行为/完整性探针，不是独立信任根；
Apple SSV/AMFI（darwin）或 Secure Boot + pinned digest（linux）和外部审阅的
candidate/release digest 仍是起始信任。开发模式可输出 ineligible 的本地时点 observation；
正式模式必须 fail closed。系统工具既不是 content asset，也不能只凭 PATH 名称接受。

## 当前精确资产

| Asset | Pin | Archive/file SHA-256 | 闭包状态 |
|---|---|---|---|
| Lean/Lake | `v4.31.0`, commit `68218e8…1783` Darwin arm64 ZIP | `e8cd241b…e0656` | ZIP 含完整 2.6 GiB toolchain；Lean/Lake 声明入口的可达非系统闭包均在树内；不可达 SDK dylib 不作为独立入口承诺 |
| solc | official universal macOS `0.8.34+commit.80d5c536` | `0a282929…7746` | 仅 Apple system dylib；替代 Homebrew+Boost build |
| WABT | official macOS arm64 `1.0.41` | `e5269d6b…ff5d` | executable 仍需 bundle `libcrypto.3.dylib` |
| OpenSSL dependency | Homebrew arm64 Tahoe bottle `3.6.3_1` | `2d995a1b…f92f` | 仅取锁定 `libcrypto.3.dylib`，file SHA `64bc8854…6f4` |
| Foundry | official `v0.3.0` Darwin arm64 archive, commit `5a8bd89` | `38756791…3e94` | Anvil/Cast 仅 Apple system dylib/framework |

| sBPF assembler (`sbpf`) | blueshift-gg/sbpf `0.2.2` @ `d835bc6e…a5ba`，`format: cargo-git`，`sourceBuild` | n/a（非字节 pin；`sbpf --version` → `sbpf 0.2.2`） | 已登记；`unresolved.solanaAssembler="0.2.2"` 记录 version pin |

| near-sandbox | official nearcore `2.13.0`（Darwin-arm64 / Linux-x86_64 tar.gz） | darwin archive `330bb412…a666`、linux archive `522f9877…89de`（executable digest 见 lock） | Darwin 捆绑 Homebrew `xz 5.8.3` bottle 的 `liblzma.5.dylib`（`55c891f5…69d5`）；`unresolved.nearSandbox="2.13.0"` 记录 version pin |
| nargo | noir-lang `v1.0.0-beta.26`（compile-only 门；**不**含 prove/verify） | darwin archive `2b8a938a…9b32`、linux archive `64048040…fb80` | `unresolved.nargo="1.0.0-beta.26"` 记录 version pin；barretenberg 仍 `null` |
| leo | ProvableHQ `v4.0.2`（darwin aarch64 / linux x86_64-gnu） | darwin archive `0b7e5010…701f`、linux archive `7dc54a9f…7be8` | system-only 闭包（Linux 含 `libssl.so.3`/`libcrypto.so.3` system soname） |
| cosmwasm-check | CosmWasm monorepo `v3.0.9` @ `fe5b55d2…9283`，`format: cargo-git`，`sourceBuild` | n/a（非字节 pin；`cosmwasm-check --version` → `Contract checking 3.0.9`） | `requiredByProfiles` 含 `cosmwasm-wasm-u64-v1`；静态 ABI/imports/capabilities 门。cosmwasm-vm 3.0.9 依赖 wasmer 5.0.6，其引用 `__rust_probestack`；Rust ≥1.89 起 Linux x86_64 链接失败（lld 与 GNU ld 均失败）。Tool Lock v4 保持 closed schema；package-owned engineering compatibility policy 仅对 exact `(asset id, commit)` 选择 Rust `1.88.0`，使用 staging-owned `HOME`/`CARGO_HOME` 与只读 policy marker 防止旧 cache 复用。正式 per-asset Rust identity 留待 Tool Lock v5 |
| tolk | ton-blockchain `tolk-1.4.2` 官方 binary（darwin `tolk-mac-arm64` / linux `tolk-linux-x86_64`） | darwin `52c00e29…1740`、linux `54286978…7940` | 自报 `Tolk compiler v1.4.1`（expectedVersion 按真实输出钉 `1.4.1`）；darwin system-only 闭包、linux static-pie 无 NEEDED；`requiredByProfiles` 含 `ton-tolk-boc-v1` |

未冻结：Barretenberg；`null` 表示未进入实现承诺，不能从 PATH 猜测。near-sandbox / nargo /
leo 已入 `tools[]`（G123 工程切片，2026-08-03）；验收门为可选工具门（缺席 skip-clean），
Noir 仅 compile-only，不升格 prove/verify。

## Provision 与离线物化

联网 provision 是独立命令：download 资产下载到同 filesystem 私有 staging，边下载边限制
size/hash，只在完全匹配后原子 publish 到 content-addressed cache；cargo-git 资产在
`cargo-git/<commit>/<asset-id>/` 下 clone+`git checkout` 精确 commit，再
`cargo build --release -p <package>`，产物为 `target/release/<bin>`，缓存命中且 version
probe 通过则跳过重建。OCI bearer token 只用于读取公开 blob，不进入 lock/evidence。
partial、redirect 降级、HTTP、额外 bytes、已有错误 cache、symlink/hardlink/特殊文件、
cargo/git 失败均失败。

离线物化只读 cache：安全读取精确 member，生成私有 staging；external bundle 的每个
`bundleFiles` 最终 file 都验证 hash/mode 与 Mach-O/ELF closure；每个 `sourceBuild` 工具
从 cargo-git cache 复制 `target/release/<bin>` 到 tool root 的 `executable` 路径（mode
`0555`，无字节 hash 校验），再原子 publish tool root。Lean ZIP 只接受单一固定
root；锁定 15,194 个 central-directory entry 和 2,761,381,330 个解压文件字节，strip 1 后
拒绝路径穿越、重复/缺失父目录、symlink、特殊文件和 privilege bits。最终 Lean 树必须逐项
匹配 path/kind/size、owner、单 hardlink 与规范化的 `0444/0555` mode；内容信任来自已复验的
完整 archive SHA-256，并额外验证 Lean/Lake executable hash 与独立 version probe。最后从
两个声明入口按真实 `LC_RPATH` 计算可达 Mach-O 闭包，与 dyld 实际加载集合精确比较。正式
gate 不调用 elan，也不从 Homebrew/Foundry install root 复制。

显式联网步骤为 `just toolchains-provision-lean` 和
`just toolchains-provision-external`。`just toolchains-materialize-lean` 与
`just toolchains-materialize-external` 是离线检查入口；clean-room harness 自己从同一 cache
物化临时 Lean/external roots，且不把 provision 隐藏在 build 中。普通 development
convenience recipes 可使用 `/usr/bin/python3 -I -S` dispatch；Stage-0、clean-room policy
renderer/launcher、物化与 stage 内 validator 必须使用 Host Profile 锁定的 direct Xcode
Python 并带 `-I -S`，不得退回 dispatch 或 site-enabled interpreter。clean-room 物化由
`env -i` 清空环境并置于 deny-default/no-network stage，版本探针子进程继承同一策略。

## Runtime Resolution

执行顺序：读取 embedded lock → 精确平台（schema `proof-forge.toolchains.v4`）→ 显式
`PROOF_FORGE_TOOL_ROOT` 或 lock default cache root → canonical regular executable →
（content-addressed 工具）SHA-256 与 lock pin 一致 / （`sourceBuild` 工具）记录 observed
hash 供 evidence 但**不**与 lock pin 比较 → 安全 runtime library subdir（仅 non-sourceBuild）→
version probe（stdout+stderr 必须包含 `expectedVersion`）→ `VerifiedTool`。
`sourceBuild` 工具的 version probe 失败报告 `PF-TOOLCHAIN-MISMATCH`；缺失报告
`PF-TOOLCHAIN-MISSING`。所有工具通过 host profile 中 hash-locked `/usr/bin/env -i`
启动，同时 spawn 使用 `inheritEnv=false`，只注入固定 locale/timezone 以及该工具锁定的 runtime
library path；因此不是依靠有限 denylist 过滤 `DYLD_*`。
每次 product spawn 前先由 `tools[].executable + tools[].runtimeFiles[]` 计算选中工具的
exact closure（`sourceBuild` 工具的 required closure 仅为自身 executable，无 bundle hash）。
content-addressed closure 成员必须验证 regular file、single link、size/hash/mode；
tool root 中实际出现的其他文件必须是 `bundleFiles[]` 成员或声明的 `sourceBuild` tool
executable，unknown/symlink/special node 一律拒绝，但未被选中工具引用的缺失
bundle/`sourceBuild` 成员不得阻塞产品执行。例如 EVM `solc` 不依赖 SBOM validator `jv` 或
`sbpf`。不搜索 cwd、父目录或 PATH。WABT 仍只能使用 tool root 内锁定的 `libcrypto`。

上述 product per-tool closure 不替代 release exact-set：`toolchain_assets.py verify-external` 与
clean-room 设计仍要求完整全局 bundle + 全部 sourceBuild 可执行文件，并执行 Mach-O/ELF
static/runtime closure（仅 bundle 成员）与 version probe（含 sourceBuild）。当前仓库没有
`release-check` recipe，恢复 wrapper 前不得声称已执行这些 release gates。
development 与 release 两种结论不得混写。

## Supply-chain inventory

D0-05 的 `proof-forge.license-inventory.v1` 是 bootstrap development format；它按 asset digest
聚合且允许无 root hash，不能作为 release input。D0-08 的 release path 只接受新的
`docs/supply-chain/supply-chain-inventory.v1.json`，schema 固定为
`proof-forge.supply-chain-inventory.v1`，不 dual-read 旧 schema。

```text
SupplyChainInventoryV1 {
  schema, schemaVersion, platform, rootPackageComponentId, components
}

InventoryComponentV1 {
  id, kind, name, version, supplier, source,
  licenseSpdx, licenseTextComponentIds, redistributable, dependencies
}

CandidateFileSourceV1 {kind, path}
GitUpstreamV1 {kind, url, commit}
CandidateFileSetSourceV1 {kind, roots, files, upstream}
ToolLockSourceV1 {kind, lockRefs}
CompilerRuntimeSourceV1 {kind, compilerToolchainId, path}
ToolLockLeafRefV1 {kind, id, path}
DependencyRefV1 {kind, to}
```

root/nested object 恰含上述字段；`schemaVersion` 精确为 integer `1`，`platform` 必须等于 Tool
Lock v4 platform，`rootPackageComponentId` 必须唯一命中 `kind=lean-package` component。component
`id` 是 1..127-byte
lowercase ASCII `[a-z0-9][a-z0-9._-]*`，全局唯一并按 UTF-8 升序；`name/version/supplier` 是
nonempty NFC string，禁止 Cc、absolute path 和 host/user data。`kind` 恰为下列互斥 enum 之一：

```text
lean-package
source-dependency
download-asset
compiler-executable
tool-executable
runtime-dylib
license-text
```

candidate archive 是 release/BOM synthetic root，不是 inventory component。bytes 相同不等于同一
logical component：`id/kind` 进入 component identity，shared bytes 只通过独立 ContentIdentity
复用；因此 `download-asset` 与 `tool-executable` 不能合并。

下述 D0-08 新 schema 中所有名为 `digest` 或 `sha256` 的字段都使用 SPEC-COMMON-001
`Digest` wire form `sha256:<64 lowercase hex>`；`sha256` 字段的 preimage 是 exact file bytes，
`digest` 字段的 preimage 由所属 schema 的 domain 公式定义。唯一例外是嵌入读取的 Tool Lock
leaf checksum（content-addressed tools），其 wire 仍按本规格前文的裸 64-hex 校验，resolve
进入新 schema 前必须构造 typed Digest；两种表示不得按字符串相等、截前缀或隐式 coercion 比较。
sourceBuild 工具无 lock-pinned executable digest。

`source` 是四种 exact closed object union：

| source.kind | exact fields | 允许的 component.kind | 规则 |
|---|---|---|---|
| `candidate-file` | `kind,path` | `license-text` | path 是同一 candidate 内的 ProjectRelativePath regular file |
| `candidate-file-set` | `kind,roots,files,upstream` | `lean-package`,`source-dependency` | roots/files 是 ProjectRelativePath unique sorted arrays；每个 root 的完整 descendant regular-file closure 加 standalone files，不能只列部分成员 |
| `tool-lock` | `kind,lockRefs` | `download-asset`,`compiler-executable`,`tool-executable`,`runtime-dylib` | refs 按下述 matrix exact resolve |
| `compiler-runtime-file` | `kind,compilerToolchainId,path` | `runtime-dylib` | path 必须唯一来自本次 retained `CompilerRuntimeClosureManifestV1` |

`candidate-file-set.roots/files` 不能为空集合，彼此不得 overlap、ancestor-alias、NFC/casefold collision；
walker 在 candidate archive immutable snapshot 上拒绝 symlink/submodule/special file，生成完整 member
set。`upstream` 对 root package 必须为 `null`；对每个 non-root Lean/source pair 必须是同一 closed
`GitUpstreamV1`，kind 固定 `git`，url 是 exact HTTPS source URL，commit 是 SPEC-COMMON-001
`GitObjectId`，并与 retained `lake-manifest.json` package URL/rev exact match；branch/tag/range 或
revision-only 声明拒绝。file-set identity 固定为：

```text
SupplyChainFileSetV1Digest = SHA-256(
  "proof-forge.supply-chain-file-set.v1" || 0x00 ||
  PF-JCS({size,members:[{path,size,digest}...]})
)
```

members 按 path NFC UTF-8 唯一升序，size 是全部 member size checked sum。Phase 1 non-root package/
source dependency 必须 vendored 在 candidate file-set；revision-only、ambient `.lake/packages` 或未定义
source snapshot 全部拒绝。根 `lake-manifest.json` package 与每个 transitive `packages[]` exact set
必须由 `lean-package` components 覆盖；每个非-root Lean package 同时必须有一个对应
`source-dependency` logical component，二者可以共享同一 file-set content identity，但 component
identity 必须不同。跨 file-set 的 member path 必须形成 partition：唯一允许的重复 ownership 是一个
non-root Lean package 与其对应 source-dependency 共享完全相同的 member set/content；root package
必须排除所有 vendored Lean/standards dependency members，其他 partial/overlap ownership 全部拒绝。

`ToolLockLeafRefV1.kind` 只允许 `asset|compiler-executable|bundle-file|tool-executable|tool-runtime-file`；
`asset` 的 `id=assets[].id,path=null`，其他 kind 的 `id` 分别是 compiler toolchain ID、
`bundleFiles[].assetId` 或 tool ID，`path` 是对应 exact locked path。refs 按 `(kind,id,path/null)`
唯一升序。binding matrix 固定为：

| component.kind | authoritative refs/source |
|---|---|
| `download-asset` | exactly one `asset` |
| `compiler-executable` | exactly one `compiler-executable` |
| `tool-executable` | exactly one `bundle-file` + one `tool-executable`，二者 size/digest/path join |
| external `runtime-dylib` | exactly one `bundle-file` + one or more owner-specific `tool-runtime-file`，全部解析到相同 bytes |
| compiler `runtime-dylib` | exactly one `compiler-runtime-file` source from retained compiler closure manifest |
| `lean-package/source-dependency` | complete candidate file-set |
| `license-text` | candidate regular file |

每个 `assets[]`、`compilerToolchain.executables[]`、`bundleFiles[]`、`tools[].executable` 和
`tools[].runtimeFiles[]` authoritative leaf 必须恰由一个 compatible logical component 消费；同一
runtime dylib 可以有多个 owner refs，但仍只有一个 runtime component。missing/extra/duplicate/
wrong-kind/multi-owner/path/size/digest substitution 全部 `PF-SBOM-CLOSURE`。闭合并行于全部
已提交 per-platform lock 文件（ADR-0016）：每份文件的每种 leaf ref 都参与 exact resolve，
跨文件重复 logical kind 不合并、各自成 component。

`dependencies` 是 unique sorted `DependencyRefV1` array；kind 只允许
`package-depends-on|build-uses|derived-from|runtime-depends-on`，按 `(kind rank,to UTF-8)` 排序。
`package-depends-on` 从 Lean package 指向 transitive Lean package；`build-uses` 只从 root Lean package
指向 inventory 中每个 compiler/tool executable logical component，以及每个不与 Lean package 配对的
standalone source-dependency component，且各一次；`derived-from` 从
executable/runtime 指向 exact
asset，或从 non-root Lean package 指向与其共享 complete file-set 的 source-dependency；
`runtime-depends-on` 从 executable 指向 runtime dylib。每个 executable 必须从 root 的 `build-uses`
可达，且每个 non-root Lean package 必须恰有一条 source `derived-from` edge。dependency graph 必须
acyclic；所有
non-license components 必须从 synthetic root 经 `rootDependsOn`/dependencies 可达，所有 license text
必须被可达 component 的 `licenseTextComponentIds` 引用，禁止 self-edge、悬空、orphan 和 same-count
edge-kind substitution。Mach-O system load 仍由 Host Profile/TCB 拥有，不伪装成 content asset。

`licenseSpdx` 对非-license-text component 是 canonical SPDX expression；对 `license-text` component
是其代表的单个 official SPDX license/exception ID，而不是伪称 license-text file 自身的授权。
`licenseTextComponentIds` 对前者为覆盖 expression 所有 license/exception leaf 的 nonempty unique
sorted IDs，对后者必须为 `[]`。
expression parser 必须按本节锁定的 SPDX ABNF、license list 与 exception list 解析，identifier 使用
官方 canonical case，operator 固定大写；`AND`/`OR` 同类节点递归 flatten 后按 canonical subtree
standalone printer 输出的 UTF-8 bytes 排序，重复 operand 拒绝，printer 按
`+ > WITH > AND > OR` 的固定 precedence 只保留必需括号。child standalone output 先递归完成，因此
排序不依赖 parent order 或实现 AST layout。v1 没有 custom-license-text wire，所以
`DocumentRef`/`LicenseRef`/`AdditionRef` 全部拒绝；
official ID 与 unary `+` 仍按 grammar 接受。parser 重新解析 printer 输出所得 AST 必须
byte-identical；不得以字符串 split、host package 版本或网络查询决定语义。[CLM-SBOM-002]

`NOASSERTION/NONE`、unknown/malformed expression、缺正文或 digest mismatch 都拒绝。
`license-policy.v1.json` root 恰为
`schema,schemaVersion,allow,review,deny,externalCli`；nested `externalCli` 恰为
`allowedDenyLicensesWhenNotRedistributable,notes`。schema 固定 `proof-forge.license-policy.v1`，
schemaVersion 精确为 integer `1`，notes 是 nonempty NFC string。三个 policy set 唯一升序且两两不交，
external exception 必须是 deny 的子集。policy 只求值 non-license components：任一 review/未分类 leaf
都 fail closed；任一 deny leaf 也拒绝，除非 component `redistributable=false`、kind 是
`download-asset|tool-executable`、source.kind 是 `tool-lock`、所有 deny leaf 都属于 external exception，
且其 bytes 不在 candidate/release archive。该 exception 仍保留 component 与 license-text metadata，
不得把 deny 改写成 allow。license-text 的 `licenseSpdx` 只是 represented atom，不作为该正文文件自身
license 再次求值。

inventory/policy identity 分别为：

```text
SupplyChainInventoryV1Digest = SHA-256(
  "proof-forge.supply-chain-inventory.v1" || 0x00 || PF-JCS(validated inventory)
)
LicensePolicyV1Digest = SHA-256(
  "proof-forge.license-policy.v1" || 0x00 || PF-JCS(validated policy)
)
```

## Resolved closure 与 component identity

generator 必须先由 SPEC-REPRO-001 外部 caller 提供 candidate archive regular file、其 positive safe
integer size 与完整 `CandidateIdentity`；重算 archive raw SHA-256、Git commit marker/tree binding 和
candidate digest 后才读取 archive 中的 inventory/policy/Tool Lock。不能在 checkout 内自选 HEAD 或
用 inventory 自报 root digest。

```text
ContentMemberV1 {path, size, digest}
ContentIdentityV1 {kind, size, digest, members}

CompilerRuntimeLoadV1 {installName, resolvedPath}
CompilerRuntimeEntrypointV1 {path, size, digest, loads}
CompilerRuntimeFileV1 {path, size, digest, owners, loads}
CompilerRuntimeClosureManifestV1 {
  schema, compilerToolchainId, assetId, assetDigest, entrypoints, files
}
CompilerRuntimeClosureRefV1 {manifest, digest}

ClosureComponentV1 {
  id, kind, name, version, supplier, source, content,
  licenseSpdx, licenseTextComponentIds, redistributable, dependencies,
  componentDigest, bomRef
}

RelationshipV1 {from, kind, to}

SupplyChainClosureV1 {
  schema, candidate, candidateArchive, rootBomRef,
  toolchainLockDigest, toolchainLockSha256,
  inventoryDigest, licensePolicyDigest, cycloneDxSchema, spdxStandards,
  compilerRuntimeClosures, contents,
  rootPackageComponentId, rootDependsOn, components, relationships
}
```

`ContentIdentityV1.kind` 只允许 `file|file-set`。file 的 `members=[]`、size 是 raw byte count、digest
是 raw file SHA-256；file-set 的 members nonempty 且按 path 唯一升序，size 是 checked sum，digest
是上节 `SupplyChainFileSetV1Digest`。contents 按 `(kind rank,digest raw 32 bytes)` 唯一升序，每项必须
被至少一个 component 引用，不能留下 content orphan；component 的 `content` 恰为
`{kind,digest}`。相同 content 可由多个 logical components 引用。

Lean compiler runtime closure 不能只凭运行时 observation 或 archive-level hash 省略。对每个 selected
compiler toolchain，从已验证 archive/materialized tree 的全部声明 entrypoints 解析真实 Mach-O
`LC_LOAD_*`/`LC_RPATH`，递归保留每个可达非-system regular file、owner entrypoint 与 resolved internal
load edge；不得读取 ambient SDK/Homebrew。manifest schema 固定
`proof-forge.compiler-runtime-closure.v1`，root/file/load objects 恰含上面字段。entrypoints、file path、
owners 与 resolvedPath 均是 materialized compiler root-relative NFC ProjectRelativePath；installName 是
Mach-O exact NFC load string。entrypoints/owners 按 UTF-8 唯一升序，loads 按
`(installName,resolvedPath)` 唯一升序，files 按 path 唯一升序；每个 file size/digest 与 immutable tree
bytes exact。`assetId` 必须等于 compilerToolchain.assetId；`assetDigest` 是该 ID 唯一解析的
`assets[].sha256` raw archive checksum 转成的 typed Digest。entrypoints 恰与
compilerToolchain.executables[] exact set 相等，path/digest exact join，size 来自 immutable tree；
`files` 只含递归可达的非-system、非-entrypoint runtime files，禁止把 entrypoint 再编码为
runtime-dylib。owners 是传递可达该 file 的 entrypoint path exact set；entrypoint/file 的 loads 恰含
其每条 direct resolved internal load edge，resolvedPath 必须命中 files 中唯一 path。每条其他 Mach-O
load 必须解析到 Host Profile allowed system root，否则 closure 失败。manifest 不自含 digest：

```text
CompilerRuntimeClosureV1Digest = SHA-256(
  "proof-forge.compiler-runtime-closure.v1" || 0x00 ||
  PF-JCS(CompilerRuntimeClosureManifestV1)
)
```

`compilerRuntimeClosures` 是按 compilerToolchainId 唯一升序的 `{manifest,digest}`；每个 manifest file
恰好对应一个 `kind=runtime-dylib,source.kind=compiler-runtime-file` component，反向也必须成立。
unreachable archive dylib 不加入 closure；可达 file missing/extra/wrong owner/load/hash 均
`PF-SBOM-CLOSURE`。Apple system dylib 只验证 allowed Host Profile root，不进入 content inventory。
linux 平台的对应物为 ELF：`neededLibs` 取代 installName load，resolvedPath 必须命中
`elfPolicy.allowedSystemLoadRoots` 内的 system library，其余规则相同（ADR-0016）。

resolved component 保留 inventory 的全部字段并把 source exact resolve 到 `content`；
`componentDigest` 与 `bomRef` 都不进入自身 preimage：

```text
componentDigest = SHA-256(
  "proof-forge.supply-chain-component.v1" || 0x00 ||
  PF-JCS(component fields except componentDigest and bomRef)
)
bomRef = "urn:proofforge:component:" || lowerhex(raw32(componentDigest))
```

`raw32` 是 Digest wire 中的 32 bytes，不把 `sha256:` prefix 放进 URN。因此相同 content 的 solc
asset 与 solc executable 仍有不同 component identity；同一 runtime dylib 的 bundle/tool-owner refs
留在一个 logical component。components 按 id 唯一升序，componentDigest/bomRef 也必须全局唯一。

`RelationshipV1.kind` 只允许 inventory 的四种 dependency kind 与 `licensed-by`；前者从
`dependencies` 一对一投影，后者从每个非-license component 到全部 licenseTextComponentIds 投影。
relationships 按 `(from,kind rank,to)` 唯一升序，必须与 inventory exact set 相等。synthetic candidate
root 不进入 components/contents；`rootBomRef` 固定为
`urn:proofforge:candidate:<lowerhex(raw32(candidate.digest))>`，`rootDependsOn` 恰为
`[rootPackageComponentId]`。从 root 经 rootDependsOn/relationships 必须到达全部 components，无
missing/extra/orphan/self-edge/cycle 或 same-count edge-kind substitution。

closure schema 固定为 `proof-forge.supply-chain-closure.v1`；candidate 是 SPEC-CAP-001 完整
`CandidateIdentity`，`candidateArchive` 恰为 `{size,sha256}`，positive safe integer size 与 raw sha256
必须等于外部 archive observation/`candidate.archiveDigest`。`toolchainLockDigest` 是 canonical `ToolLockV4Digest`，
`toolchainLockSha256` 是 candidate 内 retained lock exact bytes 的 raw SHA-256。closure 不自含 digest：

```text
SupplyChainClosureV1Digest = SHA-256(
  "proof-forge.supply-chain-closure.v1" || 0x00 || PF-JCS(SupplyChainClosureV1)
)
```

## CycloneDX 1.6 与 release binding

official CycloneDX 1.6 JSON schema 的完整 local `$ref` closure、SPDX expression/list inputs 与离线
validator 必须先形成。[CLM-SBOM-001] [CLM-SBOM-002]

```text
CycloneDxSchemaFileV1 {path, size, sha256}
CycloneDxSchemaIdentityV1 {
  schema, specVersion, sourceRevision, files, validator, digest
}

SpdxStandardsFileV1 {role, path, size, sha256}
SpdxStandardsIdentityV1 {
  schema, specVersion, sourceRevision, licenseListVersion,
  licenseListRevision, files, digest
}
```

root/nested fields closed；schema 固定 `proof-forge.cyclonedx-schema-closure.v1`，specVersion 固定
`1.6`，`sourceRevision` 是 official specification repository 的 exact 40-character lowercase Git commit；
files 是 candidate-relative regular schema files，按 path 唯一升序并 exact 覆盖所有 transitive local
`$ref`，不得读取 network/ambient schema cache。validator 是 SPEC-REG-001 `ToolchainIdentity`，
必须由 Tool Lock exact resolve 且离线执行；跟随 floating branch/URL 或只记录版本字符串不合格。
identity 不自含 digest：

```text
CycloneDxSchemaIdentityV1.digest = SHA-256(
  "proof-forge.cyclonedx-schema-closure.v1" || 0x00 ||
  PF-JCS({schema,specVersion,sourceRevision,files,validator})
)
```

`SpdxStandardsIdentityV1.schema` 固定 `proof-forge.spdx-standards-closure.v1`，specVersion 固定 `3.0.1`；
source/license-list revision 均为对应 official repository 的 exact 40-character lowercase Git commit，
licenseListVersion 是该 revision 声明的 exact nonempty version。files 的 role 恰含一次
`expression-grammar|license-list|exception-list`，按 role rank 唯一升序，path 是 candidate-relative
regular file；size/sha256 绑定 exact bytes，不接受 webpage cache、URL 字符串 hash 或 ambient library。
identity 不自含 digest：

```text
SpdxStandardsIdentityV1.digest = SHA-256(
  "proof-forge.spdx-standards-closure.v1" || 0x00 ||
  PF-JCS({schema,specVersion,sourceRevision,licenseListVersion,
          licenseListRevision,files})
)
```

closure 的 `cycloneDxSchema`/`spdxStandards` 是上述完整 identities。D0-08 freeze/RED 必须固定实际
official files、commits、raw hashes、validator ToolchainIdentity 和最终 Tool Lock leaf 分母；缺任一项
保持 RED，不能以手写字段检查冒充 official schema validation，也不能以未锁 SPDX parser/list
接受 expression。每个 standards file 必须恰属于一个 standalone `source-dependency` complete file-set，
其 Git upstream/revision 与 standards identity exact join，并由 inventory 的 license text/policy 正常覆盖；
不得把 vendored official bytes 隐入 root package license。

从 resolved closure 唯一投影 CycloneDX JSON，root exact fields 恰为
`$schema,bomFormat,specVersion,version,metadata,components,dependencies`：

```text
$schema = "http://cyclonedx.org/schema/bom-1.6.schema.json"
bomFormat = "CycloneDX"
specVersion = "1.6"
version = 1
```

禁止 serialNumber、timestamp、absolute path、username、环境值和随机字段。`metadata` 恰为
`{component}`；其中 component 是 synthetic candidate archive root，exact fields 恰为
`bom-ref,type,name,version,supplier,hashes,licenses,properties`。type 固定 `application`，
`bom-ref=rootBomRef`，hashes 恰为
`[{alg:"SHA-256",content:lowerhex(raw32(candidateArchive.sha256))}]`，name/version/supplier/license 从
rootPackageComponent exact 投影，license 使用下述 expression branch；properties 恰为
`proofforge:candidate-digest` 与 `proofforge:component-kind=candidate-archive`。synthetic root 只在
`metadata.component` 出现，禁止在 `components[]` 重复同一 bom-ref。

每个 closure logical component（包括 root Lean package）恰在 `components[]` 出现一次，type mapping
固定为：

| ProofForge kind | CycloneDX `type` |
|---|---|
| root `lean-package` | `application` |
| other `lean-package` / `source-dependency` | `library` |
| `download-asset` | `file` |
| `compiler-executable` / `tool-executable` | `application` |
| `runtime-dylib` | `library` |
| `license-text` | `file` |

non-license-text component exact fields 为
`bom-ref,type,name,version,supplier,hashes,licenses,properties`；supplier 恰为 `{name}`，hashes 恰为
`[{alg:"SHA-256",content:lowerhex(raw32(content.digest))}]`，compound SPDX 必须投影为
`licenses:[{expression:<canonical expression>,acknowledgement:"concluded"}]`，不得错误塞入
`license.id`。license-text component exact fields 去掉 `licenses`，不伪造该正文文件自身 license。

所有 component 的 properties 至少且只含
`proofforge:component-id,proofforge:component-kind,proofforge:content-kind,`
`proofforge:redistributable,proofforge:source-kind`；带 nonnull upstream 的 file-set component 另含
`proofforge:upstream-url,proofforge:upstream-commit`；non-license component 另含
`proofforge:license-text-ids`（sorted IDs 以 `,` 连接），license-text 另含
`proofforge:represented-spdx-id`。properties 按 `(name,value)` UTF-8 唯一升序；root properties 恰为
`proofforge:candidate-digest` 与 `proofforge:component-kind=candidate-archive`。

每个 property object 恰为 `{name,value}`，value 固定为下表字符串，不做 locale formatting、JSON
scalar coercion 或 trim：

| property name | exact value |
|---|---|
| `proofforge:component-id` | component `id` |
| `proofforge:component-kind` | component `kind`；synthetic root 固定 `candidate-archive` |
| `proofforge:content-kind` | `content.kind` |
| `proofforge:redistributable` | lowercase ASCII `true` 或 `false` |
| `proofforge:source-kind` | `source.kind` |
| `proofforge:upstream-url` | `source.upstream.url` exact bytes |
| `proofforge:upstream-commit` | canonical `source.upstream.commit` wire |
| `proofforge:license-text-ids` | component IDs 按 UTF-8 排序后以单个 ASCII comma 连接，无空格 |
| `proofforge:represented-spdx-id` | license-text `licenseSpdx` canonical ID |
| `proofforge:candidate-digest` | synthetic root `candidate.digest` Digest wire |

`dependencies[]` 恰含 synthetic root ref 与每个 component bom-ref 各一次，按 ref UTF-8 升序；root
dependsOn 从 rootDependsOn 投影，每个 component dependsOn 是该 component 所有 typed relationship
targets（含 `licensed-by`）的 bom-ref unique sort。edge kind 的 authority 仍是 closure relationships，
因为 CycloneDX dependencies 不保存 edge kind。components 同样按 bom-ref 唯一升序。

BOM 必须先通过 exact projection 重算，再由 `cycloneDxSchema.validator` 对锁定 official schema closure
离线验证。BOM semantic digest 与 raw file hash分离：

```text
CycloneDx16Digest = SHA-256(
  "proof-forge.cyclonedx-1-6.v1" || 0x00 || PF-JCS(BOM)
)
```

consumer 必须重算 inventory/content/component/relationship/closure/BOM/schema/validator 全部 join，
不能只跑 JSON schema，也不能只做手写 projection 检查。

candidate-bound sidecar bundle 恰含三个 regular single-link files：

```text
supply-chain-closure.v1.json
bom.cdx.json
sbom-release-binding.v1.json
```

前两项 file bytes 分别是 PF-JCS(closure) 与 PF-JCS(BOM)，无 BOM/whitespace/trailing LF。binding：

```text
SbomReleaseBindingV1 {
  schema, candidate, candidateArchive,
  toolchainLock: {path, size, sha256, digest},
  licensePolicy: {path, size, sha256, digest},
  inventory: {path, size, sha256, digest},
  cycloneDxSchema, spdxStandards,
  closure: {path, size, sha256, digest},
  bom: {path, size, mediaType, sha256, digest, schemaDigest},
  generator: {path, size, sha256}
}
```

root/nested object 只允许上述字段；schema 固定 `proof-forge.sbom-release-binding.v1`；
`candidateArchive` 恰为 `{size,sha256}` 且与 closure/candidate exact。三项 input path 固定为
`toolchains.lock.json`、`docs/supply-chain/license-policy.v1.json`、
`docs/supply-chain/supply-chain-inventory.v1.json`，均为 candidate-relative；size/sha256 是 retained
exact file bytes，digest 分别是 `ToolLockV4Digest`、`LicensePolicyV1Digest` 与
`SupplyChainInventoryV1Digest`。

`cycloneDxSchema` 是 closure 中同一完整 `CycloneDxSchemaIdentityV1`，`spdxStandards` 是同一完整
`SpdxStandardsIdentityV1`。closure path 固定
`supply-chain-closure.v1.json`，size/sha256 是 exact sidecar bytes，digest 是
`SupplyChainClosureV1Digest`；BOM path 固定 `bom.cdx.json`，media type 固定
`application/vnd.cyclonedx+json`，size/sha256 是 exact BOM bytes，digest 是 `CycloneDx16Digest`，
schemaDigest 等于 cycloneDxSchema.digest。generator path 是 candidate 内实际执行的 project-relative
regular file，size/sha256 是 raw bytes。所有 raw sha256 与 typed digest 都必须从同一 retained snapshot
重算，不能由 caller 自报或互换。binding 不自含 digest：

```text
SbomReleaseBindingV1Digest = SHA-256(
  "proof-forge.sbom-release-binding.v1" || 0x00 || PF-JCS(SbomReleaseBindingV1)
)
```

三份 sidecar 必须位于 candidate archive 外；把它们写回 candidate 或让 root hash 指向含 sidecar 的
outer package 都是 `PF-SBOM-BIND`。binding 本身不携带 `development/formal` 或时间字段；maturity、
freshness、revocation 与 signature 属于 D0-07 formal evidence envelope，避免同一内容 identity 因
运行时间变化。D3-05 将 exact binding digest/ref 接入 OutputSet，D8-05 才执行 release 签名。

## SBOM v1 资源边界

下表是 SPEC-TOOL-001 拥有的 v1 hard maxima，不从输入或 production output 推导。equal 接受，首次
over 必须在分配/发布下一单位前以 `PF-SBOM-LIMIT` 失败；checked sum 溢出同样失败。提高任一值必须
升级 supply-chain closure/binding schema、重审 ADR-0015 与 TST-SBOM-002，不能只改 runtime flag。

| Boundary | v1 maximum |
|---|---:|
| candidate archive bytes | 1,073,741,824 |
| each JSON input bytes | 16,777,216 |
| each license text bytes | 16,777,216 |
| logical components | 4,096 |
| distinct content identities | 2,048 |
| typed relationships | 16,384 |
| members per file-set content | 131,072 |
| members across all file-set contents | 262,144 |
| compiler runtime files | 1,024 |
| standards files | 64 |
| distinct referenced content bytes checked sum | 8,589,934,592 |
| each sidecar file bytes | 67,108,864 |
| three sidecars aggregate bytes | 134,217,728 |

publication aggregate 同时不得超过 effective artifact-output
`ResourceProfileV1.maxPublishedBytes`；取上表与 effective profile 的较小值。上表 schema maximum
超限是 `PF-SBOM-LIMIT`；effective profile/controller 超限遵循 SPEC-COMMON-001，返回
`PF-RESOURCE-OUTPUT`，不能重标为 SBOM 错误。offline schema validator 另在 effective external-tool
ResourceProfile containment 中运行，其 stdout/stderr/wall/memory/process 超限返回对应
`PF-RESOURCE-*`，不由本表放宽。

## Safe read、写盘与迁移

所有 JSON、license text、generator 与 candidate file 都必须 component-by-component dirfd/no-follow/
nonblocking safe-open，只接受 regular single-link node；bounded read 受上述 SBOM v1 maxima 控制，
publication 另受 effective artifact-output `ResourceProfileV1` 控制。读取前后验证 stable
device/inode/size/mtime，hash 后额外探测 EOF。duplicate
JSON key、invalid UTF-8、non-PF-JCS scalar、truncate/grow/replace race、symlink/hardlink/FIFO/device、
大小恰好 over limit 均在生成任何 output 前失败。

验证顺序固定为：

1. bounded safe-open candidate、Tool Lock、policy、inventory、standards、license/source files；
2. duplicate-key/PF-JCS/closed-schema/scalar/order validation；
3. 调用现有 authoritative `validate_tool_lock`，禁止 SBOM 模块实现宽松副本；
4. candidate identity、archive membership 与 marker/tree binding；
5. package/source/file-set exact closure；
6. executable/runtime/retained Mach-O leaf exact closure；
7. pinned SPDX parse、license-text coverage 与 policy evaluation；
8. content/component identity；
9. closure exact set、typed relationships 与 reachability；
10. CycloneDX exact projection及锁定 official schema 的 offline validation；
11. release binding 全量重算；
12. atomic publication。

destination parent 必须从 caller-owned dirfd 逐 component no-follow 打开，所有 path component 为当前
effective uid 拥有且不可 group/world writable；不接受 caller 提供的预解析 absolute realpath。
publish 在 destination 同父目录建立 private `0700` staging，closure/BOM 先写、binding 最后写，三文件
最终 mode 固定 `0444`。全部写完后从 staging dirfd 重读并重算 closure/BOM/binding，逐文件 `fsync`，
再 `fsync` staging directory，以 no-clobber atomic directory rename 发布；成功 rename 后必须
`fsync` destination parent directory 才返回成功。destination 已存在、concurrent winner、disk-full、
signal 以及 rename 前任一 write/file-fsync/staging-dir-fsync failure 都保持 caller-owned 旧目录
byte-identical，清理本次 staging 且不得留下 partial output。若 directory rename 已成功但 parent
`fsync` 失败，或进程在 rename 与成功确认之间被中断，则保留完整、只读、未确认 durability 的
destination；可返回时命令返回 `PF-OUTPUT-ATOMICITY`，绝不报告成功。
不得删除或覆盖它。后续只能用独立 `--verify-existing` 路径 safe-open 三文件、全量重算 binding，
成功 `fsync` parent 后确认；该路径不得生成、rename 或修改 sidecar。release 命令没有 `--force`。

D0-05 development files没有 accepted external consumer，D0-08 以首次 release schema 破坏性替代：
旧 inventory/null-root BOM/digest-map 输入到 release validator 必须稳定拒绝。若未来发现已接受的
legacy artifact，必须升级对应 schema/profile 并使用独立离线 migration tool；runtime 不 fallback。

SBOM 稳定错误族固定为：raw JSON/UTF-8/duplicate key=`PF-SBOM-JSON`，closed wire/type/order=
`PF-SBOM-SCHEMA`，component/graph/source declaration=`PF-SBOM-INVENTORY`，license text/expression=
`PF-SBOM-LICENSE`，policy classification=`PF-SBOM-POLICY`，Tool Lock/Lake/kind exact closure=
`PF-SBOM-CLOSURE`，candidate/root/BOM/sidecar/digest substitution=`PF-SBOM-BIND`，unsafe node/read race=
`PF-SBOM-IO`，本规格表内 schema maximum over=`PF-SBOM-LIMIT`。effective ResourceProfile controller
超限继续使用 SPEC-COMMON-001 `PF-RESOURCE-*`；staging/fsync/no-clobber/rename/cleanup 继续使用
artifact-output authority 的 `PF-OUTPUT-ATOMICITY`。同一 fixture 只引入一个 mutation；实现不得按
stderr substring 或检查偶然顺序把一种失败伪装成另一种。

## Profile Mapping

- `evm-yul-solc-0.8.34-v1`：官方 solc asset（默认）；runtime profile 使用同一 Foundry archive；
  Finalize 历史 argv（无 ambient `--evm-version`）。
- `evm-yul-solc-0.8.34-cancun-v1`：同一 solc 0.8.34 / Anvil·cast 0.3.0 二进制；Finalize 显式
  `solc --evm-version cancun`；runtime 经 `PF_EVM_PROFILE` 启动 `anvil --hardfork cancun`。
  工程硬分叉引脚，不升级工具，不声称 OZ/formal hardfork 闭合。
- `solana-sbpf-plan-v1`：Lean typed audit-plan/IDL 已锁；没有 approved assembler，
  sBPF instructions、object/ELF 与 runtime 均未验证。
- `near-wasm-raw-u64-v1`：WABT + libcrypto bundle；sandbox runtime 未验证。
- `noir-source-u64-relations-v1`：仅由锁定 Lean 编译器生成 typed relation schema 与
  independent Noir source packages；Nargo/noirc、Barretenberg 与 CRS 均未冻结，所以不生成
  ACIR/witness/proof/VK/verify evidence，不允许把 package 的宽松 version range 当成 binary pin。

## 错误与验收

`PF-TOOLCHAIN-MISMATCH` 带 tool/asset、expected/actual version/hash/path；
`PF-TOOLCHAIN-MISSING` 不允许 required gate skip。本 external slice 已覆盖 duplicate/unknown/
malformed lock、cache miss、partial/tampered archive、member/path attack、tool/dylib mutation、
extra/symlink/hardlink/writable bundle 与 PATH/DYLD shadow。Lean cache consumer 已接入 alpha
harness，并在 `0b0aebda…643c8` 完成完整 development gate。H0 已覆盖严格 Stage-0 record、
duplicate JSON、完整 live host/Xcode/tool observation 和 formal-ineligible 拒绝。H1c 已接入
deny-default development stages，并由 launcher 对每次 invocation 施加 stage timeout 与
bounded output。正式 gate 仍需 eligible host、Stage-0 direct digest handoff、process-session
containment、明确的 version-probe attack catalog 与 gate-catalog-bound schema evidence。

关联 `NFR-001/009`、`TST-TOOL-001`、`TST-SBOM-001`、`TST-HOST-001`、`TST-XTARGET-002`、
`TST-ISO-002/003`。manifest/evidence
记录全部 asset、executable、runtime dependency 与 host-profile digest。
