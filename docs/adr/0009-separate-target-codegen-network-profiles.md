---
id: ADR-0009
title: 分离 Target Codegen 与 Network Profile
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0009：分离 TargetId、CodegenProfile 与 NetworkProfile

- 状态：`proposed`
- 日期：2026-07-15

## 背景

平台身份、编译工具版本和部署网络规则变化速度不同。把它们编码进一个 target string 会造成别名和静默漂移。

## 决定

- `TargetId` 表示稳定的语义宿主名称，如 `near`；完整语义身份由
  `SPEC-REG-001` 的 canonical `TargetSemanticsV1` 派生，包含 `semanticsVersion` 与
  `semanticsDigest`。
- protocol/fork/precompile/resource/failure 等会改变可观察执行结果的规则属于 target
  semantics，并进入 `semanticsDigest`。
- ABI 的 dispatch/input/output/error 可观察意义只属于 target semantics。`CodegenProfileV1`
  只固定实现该语义的 ABI byte encoding、compiler/proof tool、artifact encoding、
  lowering 与 toolchain，并 exact 引用 target semantic identity；不得覆盖或增加可观察规则。
- `NetworkProfile` 只固定 chain/genesis identity、endpoint、fee、签名与部署策略；它可以声明
  兼容的 exact target semantics/codegen 组合，但不能改变编译结果。

解析必须 exact；build 不读取 network profile。BuildIdentity 恰好为
`(TargetId, semanticsVersion, semanticsDigest, CodegenProfileId, codegenProfileDigest)`。
deploy/verify 先 exact resolve `NetworkProfileId` 及其 digest，再用完整 BuildIdentity 做
`NetworkProfile.compatibleBuilds` membership join，不匹配只能拒绝。没有 network profile 仍可生成标记为未部署的 artifact，
但不能宣称 network-compatible。

## 后果

支持历史 profile 与可重现构建；用户需要显式选择或接受项目记录的默认 profile。

## 验证

profile mismatch/unknown/withdrawn tests，包括相同 CodegenProfileId 但 digest 不同的 negative；
network 不能改变 semantic/plan/artifact hash，manifest 包含完整 BuildIdentity 与 lock digest；
deploy receipt 另记录 network ID/digest。
