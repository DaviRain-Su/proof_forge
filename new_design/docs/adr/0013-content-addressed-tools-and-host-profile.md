---
id: ADR-0013
title: 内容寻址工具闭包与受信 Host Profile 分离
status: proposed
owner: build
updated: 2026-07-15
normative: true
---

# ADR-0013：内容寻址工具闭包与受信 Host Profile 分离

- 状态：`proposed`
- 日期：2026-07-15

## 背景

只锁顶层 executable 不能锁定真实运行闭包。Homebrew `solc` 还加载 Boost，WABT
`wat2wasm` 还加载 OpenSSL；`/usr/bin/python3` 与 `/usr/bin/git` 又只是 Xcode dispatch
shim。另一方面，macOS dyld shared cache、系统 framework 与 `sandbox-exec` 不能合理复制
进项目 cache。

## 决定

V2 明确分成两类信任：

1. Lean、solc、WABT、OpenSSL dependency、Anvil 与 Cast 作为内容寻址资产。lock 记录精确
   release URL、archive size/SHA-256、archive member、最终文件 SHA-256、版本 probe 和
   非系统 Mach-O closure；联网 provision 与离线 gate 分离。
2. Bash、macOS utilities、Xcode Git/Python、系统 dylib/framework 与 sandbox 作为受信
   host profile。profile 记录 OS/Xcode build、原生架构、有效实现路径、文件 hash、签名/
   行为 probe 与资格状态。

“Hermetic”只表示相对于一个通过验证且 `eligibleForHermetic=true` 的 host profile。若
host profile 不合格，内容资产全部正确也必须 fail closed。开发 alpha 可记录不合格 host
观察，但不得提升 release evidence。

## 后果

- `toolchains.lock.json` 升级为 v2，并成为官方资产与 bundle file 的权威。
- `host-profiles.lock.json` 单独记录宿主 TCB；不能把系统工具伪装成内容资产。
- 普通 build 不联网；缺 cache 返回明确错误，用户单独运行 provision。
- 正式 clean-room 使用净化 launcher、离线 cache 和 deny-default sandbox；alpha 命令名
  保留到这些条件全部闭合。

## 验证

覆盖 asset/archive/member/file tamper、缺 cache、错误 OS/Xcode build、Rosetta、非系统
dylib 漂移、无效 sandbox 行为和不合格 host profile。证据记录 asset digests、closure、
host profile ID/digest 与全部 probe。
