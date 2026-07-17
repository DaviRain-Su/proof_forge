---
id: ADR-0014
title: 固定 Unicode 17.0.0 并在纯 Lean 层执行 NFC
status: proposed
owner: architecture
updated: 2026-07-17
normative: true
---

# ADR-0014：固定 Unicode 17.0.0 并在纯 Lean 层执行 NFC

- 状态：`proposed`
- 日期：2026-07-17

## 背景

`SPEC-COMMON-001` 要求 `ProjectRelativePath`、`QualifiedName` 与 canonical string fields
使用 NFC，但此前没有固定 Unicode 数据版本。Lean 4.31 也没有可供该 common wire 层直接使用的
NFC normalization API。依赖 macOS Foundation、系统 ICU 或构建机 Python 会让相同源码在不同
host 上产生不同 canonical bytes/hash，违反复现与 clean-room 边界。

Unicode 17.0.0 的 UAX #15 revision 57 定义 normalization form，并由同版本 UCD 提供 canonical
decomposition、canonical combining class、composition exclusion 与 conformance vectors
（`SRC-UNICODE-001`、`SRC-UNICODE-002`）。

## 决定

1. V2 common wire 固定 Unicode **17.0.0**；NFC 精确指 UAX #15 revision 57。
2. 官方 `UnicodeData.txt`、`CompositionExclusions.txt` 与 `NormalizationTest.txt` 的 URL、byte size
   和 SHA-256 写入仓库 lock。生成器只接受 digest 完全匹配的本地输入，输出确定的纯 Lean data。
3. runtime/build/test 不调用 Foundation、ICU、Python 或网络；canonical decomposition、CCC stable
   reorder、Hangul algorithmic composition/decomposition 与 composition table 均在纯 Lean 中执行。
4. scalar decoder 对非 NFC 输入 **fail closed**，不得静默 normalize 后接受；`normalizeNfc` 仅作为
   可测试 primitive，`requireNfc` 通过 exact code-point comparison 建立 typed value。
5. PF-JCS 本身不做全局 normalization。各 schema owner 在构造 typed value 前调用所属字段的 NFC
   validator；随后 JCS 只编码已经验证的 Unicode scalar sequence。
6. `General_Category=Cc` 也使用同一 Unicode 17.0.0 data contract。升级 Unicode 版本会改变 accepted
   value set，必须新增 ADR、重生成 lock/data/tests，并按所属 schema 的 versioning 规则评审。

## 后果

- 首次实现会增加生成数据和 conformance gate，但不会增加 runtime 外部依赖。
- 未分配于 Unicode 17.0.0 的新 code point 可作为 scalar 保留；是否满足 NFC 由固定算法/data 判定，
  不随 host 更新漂移。
- `TST-COMMON-001` 必须包含 composed/decomposed、combining-order、Hangul 与 direct-construction
  fail-closed vectors；生成器 self-test 必须跑完固定 `NormalizationTest.txt`。

## 验证

- 三个输入文件逐项 size/SHA-256 mismatch 均拒绝且零输出。
- 同一输入生成两次 byte-identical Lean data。
- 官方 normalization conformance corpus 通过；路径/QName composed positive 与 decomposed negative
  通过；禁用网络和系统 Unicode library 后 focused Lean tests 仍通过。
