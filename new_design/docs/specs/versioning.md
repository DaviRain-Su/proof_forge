---
id: SPEC-VER-001
title: 版本与兼容策略
status: proposed
owner: release
updated: 2026-07-16
normative: true
---

# 版本与兼容策略

## 版本轴

Compiler release 使用 SemVer。DSL、SourceModule、SemanticProgram、Requirement semantics、
Plan、TargetIR、Output manifest、diagnostic JSON、gate evidence/revocation 和 registry 各自有
schema ID/version，不能由 compiler version 隐式代替。

## 兼容规则

- DSL patch：只修诊断/非语义 bug；minor：新增不冲突语法；major：解析或语义破坏。
- Semantic schema：reader 接受同 major 且只含声明 optional fields；unknown required field
  拒绝。semantic meaning 改变必须 major，semantic hash tag 随之变化。
- Requirement：语义变化必须新 exact version+digest；旧 key 可保留但不能 alias。
- Plan/TargetIR：target-owned；field 语义/布局变化升 major，新增 optional metadata 升 minor。
- Output manifest：consumer 按 schema major；未知 artifact role 可忽略，未知 required
  deployability/settlement 字段不可忽略。
- CodegenProfile：任何影响 ABI、state layout、proof、artifact bytes 或 tool compatibility 的
  变化新 profile ID 或 major version。
- NetworkProfile：endpoint/fees 可 patch；chain identity/genesis 改变是新 ID。
- Gate evidence：`proposed` v1 可以加入不重解释旧 variant、且由新 reader 保持全部旧 records
  有效的条件字段。当前 `networkPort` 只对新 `exact-local-port` variant 必填；新 reader 必须
  继续接受旧 deny-all/loopback v1 records，旧 reader 拒绝新 record 是预期 fail-closed，不构成
  forward compatibility。当前 formal publisher disabled，仓库没有 tracked formal v1 fixture；
  这不是对外部 consumer 的穷举证明。schema 一旦 accepted，字段重解释/删除、旧 record 失效
  或要求旧 reader 理解新语义都必须升级 schema major；validator digest 必须进入正式 evidence
  信任链。
- Gate catalog：schema version、catalog exact SemVer 与 domain-separated digest 是三个独立轴；
  任何 required set、lock、host/candidate policy 或 binding 语义变化都使用新的 exact catalog
  version/digest，不允许 range、`latest`、alias 或同 `(id,version)` 不同 digest。Finalization record
  使用独立 schema；已发布 record 不因 catalog 更新被原地重解释。

## Source Compatibility

compiler 默认只接受当前 DSL major。`--language-version` 只能选择编译器内已实现 parser，
不能调用父项目或下载转换器。migration tool 输出新文件和报告，不原地覆盖；转换后仍需
重新 type/semantic/target validation。

## Deprecation 与 EOL

公开 stable schema/profile 删除前至少两个 minor releases、90 天和一份 migration guide。
experimental profile 可一个 minor 后删除，但 release notes 必须列出。安全漏洞可立即禁用，
以 `PF-PROFILE-REVOKED` fail closed，并发布 advisory。

## 边界与验收

覆盖 patch/minor/major fixtures、unknown optional/required fields、old/new reader matrix、
same requirement version different digest、profile ABI/layout drift、network identity drift、
deprecated warning、revoked profile、migration roundtrip、hash domain separation、compiler newer/
older、prerelease SemVer、malformed version，并冻结 legacy-v1 deny-all/loopback 与 exact-port
fixtures。关联 `NFR-006`；compatibility matrix 必须成为 release gate，任何 golden 更新都需
对应 ADR/version justification。
