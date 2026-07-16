---
id: SPEC-TOOL-001
title: 工具链锁定规格
status: proposed
owner: build
updated: 2026-07-15
normative: true
---

# 工具链锁定规格

## 信任模型

按 [ADR-0013](../adr/0013-content-addressed-tools-and-host-profile.md) 分离两类闭包：

- `toolchains.lock.json`：可下载、内容寻址并离线物化的 compiler/tool/runtime 资产。
- `host-profiles.lock.json`：不能打包进 cache 的 macOS/Xcode/system runtime TCB。

正式 hermetic 只相对于一个验证通过且 `eligibleForHermetic=true` 的 host profile。当前
Darwin profile 因系统卷 seal broken 且 Xcode pathname 可由当前 admin 用户替换而明确为
development-only；它不能关闭 `TASK-D0-03/04`。

## Tool Lock v2

根目录 `toolchains.lock.json` 是机器可读权威：

```text
schema: "proof-forge.toolchains.v2"
platform
assets[]: {
  id, url, size, sha256, format,
  auth? {type, realm, service, scope}
}
compilerToolchain: {
  id, version, sourceCommit, platform, assetId,
  archiveRoot, stripComponents, entryCount, unpackedSize,
  executables[] {path, sha256},
  versionProbes[] {path, args, expected}
}
bundleFiles[]: {path, assetId, member?, size, sha256, mode}
machoPolicy: {
  allowedSystemLoadRoots[],
  files[] {path, installId?, externalLoads[] {installName, bundlePath}}
}
tools[]: {
  id, version, sourceUrl, platform, assetId, executable,
  defaultPath, executableSha256, runtimeLibrarySubdir?,
  runtimeFiles[] {path, sha256},
  versionArgs, expectedVersion, licenseSpdx, requiredByProfiles[]
}
```

数组按 ID/path 排序；ID 唯一；所有 size 是正整数；所有 SHA-256 是 64 位小写十六进制；URL 必须 HTTPS；
member/path 必须相对且不能含 `.`、`..`、NUL、symlink 或特殊文件。asset cache 布局固定为
`sha256/<asset-sha256>/<asset-id>`。普通 build 不自动下载。

## Host Profile v1

`host-profiles.lock.json` 记录：

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

JSON 拒绝 duplicate key，且 v1 当前恰好包含一个 profile。`eligible=true` 必须蕴含 native
arm64、非 Rosetta、SIP enabled、authenticated root enabled、system volume sealed 且 Xcode
pathname 不可由当前用户替换。

Stage 0 必须在任何 Git/Python 前由调用者直接以 `env -i`、`/bin/bash --noprofile --norc`
启动。它用 Bash builtin 按固定顺序解析 `host-bootstrap.lock`，不得 `source`/`eval`；先绑定
launcher、Python verifier、两份 lock、direct Xcode Python/Git 和最小 Apple platform TCB，
验证 Xcode deep/strict signature 后才允许 Python 解析完整 JSON。OpenSSL SHA-256 KAT 只是
行为/完整性探针，不是独立信任根；Apple SSV/AMFI 和外部审阅的 candidate/release digest
仍是起始信任。开发模式可输出 ineligible 的本地时点 observation；正式模式必须 fail closed。
系统工具既不是 content asset，也不能只凭 PATH 名称接受。

## 当前精确资产

| Asset | Pin | Archive/file SHA-256 | 闭包状态 |
|---|---|---|---|
| Lean/Lake | `v4.31.0`, commit `68218e8…1783` Darwin arm64 ZIP | `e8cd241b…e0656` | ZIP 含完整 2.6 GiB toolchain；Lean/Lake 声明入口的可达非系统闭包均在树内；不可达 SDK dylib 不作为独立入口承诺 |
| solc | official universal macOS `0.8.34+commit.80d5c536` | `0a282929…7746` | 仅 Apple system dylib；替代 Homebrew+Boost build |
| WABT | official macOS arm64 `1.0.41` | `e5269d6b…ff5d` | executable 仍需 bundle `libcrypto.3.dylib` |
| OpenSSL dependency | Homebrew arm64 Tahoe bottle `3.6.3_1` | `2d995a1b…f92f` | 仅取锁定 `libcrypto.3.dylib`，file SHA `64bc8854…6f4` |
| Foundry | official `v0.3.0` Darwin arm64 archive, commit `5a8bd89` | `38756791…3e94` | Anvil/Cast 仅 Apple system dylib/framework |

未冻结：sBPF assembler、Nargo、Barretenberg；`null` 表示未进入实现承诺，不能从 PATH 猜测。

## Provision 与离线物化

联网 provision 是独立命令：下载到同 filesystem 私有 staging，边下载边限制 size/hash，
只在完全匹配后原子 publish 到 content-addressed cache。OCI bearer token 只用于读取公开
blob，不进入 lock/evidence。partial、redirect 降级、HTTP、额外 bytes、已有错误 cache、
symlink/hardlink/特殊文件均失败。

离线物化只读 cache：安全读取精确 member，生成私有 staging；external bundle 的每个最终
file 都验证 hash/mode 与 Mach-O closure，再原子 publish tool root。Lean ZIP 只接受单一固定
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

执行顺序：读取 embedded lock → 精确平台 → 显式 `PROOF_FORGE_TOOL_ROOT` 或 lock default
cache root → canonical regular executable → SHA-256 → 安全 runtime library subdir → exact
version probe → `VerifiedToolchain`。所有工具通过 host profile 中 hash-locked `/usr/bin/env -i`
启动，同时 spawn 使用 `inheritEnv=false`，只注入固定 locale/timezone 以及该工具锁定的 runtime
library path；因此不是依靠有限 denylist 过滤 `DYLD_*`。
每次 spawn 前递归验证 exact bundle tree、regular file、single link、size/hash/mode 和目录
不可 group/world writable；不搜索 cwd、父目录或 PATH。WABT 仅可使用 tool root 内锁定的 `libcrypto`，sandbox
同时拒绝 `/opt/homebrew`，并以实际 loaded-library observation 证明未回退。

## Profile Mapping

- `evm-yul-solc-0.8.34-v1`：官方 solc asset；runtime profile 使用同一 Foundry archive。
- `solana-sbpf-plan-v1`：Lean typed audit-plan/IDL 已锁；没有 approved assembler，
  sBPF instructions、object/ELF 与 runtime 均未验证。
- `near-wasm-raw-u64-v1`：WABT + libcrypto bundle；sandbox runtime 未验证。
- `noir-acir-bb-v1`：仅 Lean source materialization；Nargo/BB 未冻结。

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

关联 `NFR-001/009`、`TST-TOOL-001`、`TST-HOST-001`、`TST-XTARGET-002`、
`TST-ISO-002/003`。manifest/evidence
记录全部 asset、executable、runtime dependency 与 host-profile digest。
