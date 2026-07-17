---
id: ADR-0015
title: Tool Lock 唯一摘要与 Candidate-bound SBOM
status: proposed
owner: build
updated: 2026-07-17
normative: true
---

# ADR-0015：Tool Lock 唯一摘要与 Candidate-bound SBOM

- 状态：`proposed`
- 日期：2026-07-17

## 背景

同一份 `toolchains.lock.json` 当前分别以 `proof-forge.toolchains.v2` 和
`proof-forge.toolchain-lock.v1` 两个 domain 计算摘要，导致 proof bundle 与
`ToolchainIdentity` 无法得到同一个 lock identity。D0-05 的 development SBOM 只闭合到
download asset 粒度；product root 没有 archive hash，executable、runtime file 和 bundled
license text 也没有独立的可重算逻辑身份。

把 candidate archive digest 写回 archive 内的 inventory 会形成自引用；只用 raw content
SHA-256 作为 `bom-ref` 又会把 bytes 相同但角色不同的记录错误合并，例如同一份 solc bytes
同时作为 download asset 与 materialized tool executable。

## 决定

1. [`SPEC-TOOL-001`](../specs/toolchains.md) 是 `ToolLockV2Digest` 的唯一 authority：
   `SHA-256("proof-forge.toolchains.v2" || NUL || PF-JCS(validated ToolLockV2))`。
   raw `toolchains.lock.json` file checksum 使用独立的 `toolchainLockSha256` 字段；两者不得代换。
2. `proof-forge.toolchain-lock.v1` 是无效 legacy domain。consumer 必须拒绝，不能 dual-read、
   fallback 或把旧值原地解释为新值。保留既有 wire 字段名，但重新生成全部下游 identity。
3. supply-chain component 是互斥逻辑 kind 的记录，不是裸 content digest。逻辑 component identity
   与共享 `ContentIdentity` 分离；bytes 相同而逻辑 ID/kind 不同的记录保持独立，一个逻辑记录的
   多个精确 lock/closure ref 可以解析到同一 content identity。
4. candidate archive 先由 SPEC-REPRO-001 的外部调用者固定并构造
   `CandidateIdentity`，随后才生成 candidate-bound closure、CycloneDX 1.6 BOM 与 release
   binding。三份 sidecar 位于 candidate archive 外；SBOM root component 的 raw hash 精确等于
   `candidate.archiveDigest`，因此不产生自引用。
5. checked-in inventory 只声明可验证来源和 license metadata；resolved closure 记录七类互斥
   kind：Lean package、source dependency、download asset、compiler executable、tool executable、
   runtime dylib/file、bundled license text。candidate archive root 是 release/BOM synthetic root，
   不伪装成 source dependency。每个 Tool Lock leaf、compiler archive 可达 runtime leaf、source
   file-set 与 license text 必须 exact 覆盖，missing、extra、重复映射或跨 kind 替代全部 fail closed。
6. official CycloneDX 1.6 schema closure、offline validator、SPDX 3.0.1 expression grammar 与 exact
   license/exception list revision 都进入 candidate-bound identity；不允许 floating URL、ambient parser
   或只通过手写字段检查。CycloneDX expression 使用官方 single-expression branch。[CLM-SBOM-001]
   [CLM-SBOM-002]
7. D0-08 负责 deterministic generation、closure recomputation 与 candidate-bound development
   binding；D0-07 只在 eligible host、activation、freshness、revocation、private scan 和 formal
   finalizer 闭合后发布 formal evidence；D3-05 才把 binding 接入 OutputSet；D8-05 才执行发布签名。

## 后果

- D0-05 的 `proof-forge.license-inventory.v1`、null-root BOM 和
  `sbom-digests.v1.json` 仍可作为已登记的 bootstrap development evidence，但不能满足
  `TST-SBOM-002` 或 release consumer。
- D0-08 引入的新 supply-chain inventory/closure/release-binding schema 是破坏性替代；release
  路径必须拒绝旧 schema，不提供运行时迁移 fallback。若以后发现已对外接受的旧制品，只能以
  新 schema/profile 和独立离线迁移器处理。
- 修复顺序固定为 ToolLockV2Digest → ToolchainIdentity → CodegenProfile/BuildIdentity →
  registry/profile → proof bundle/support/output/finalizer/cache identities；不得改变 Source、
  SemanticProgram 或 SemanticProvenance 的业务语义/hash。

## 验证

`TST-SBOM-002` 覆盖 canonical-vs-raw digest、legacy-domain substitution、同 bytes 不同逻辑 kind、
每个 executable/runtime leaf、root archive binding、pinned standards、sidecar exact closure、safe-read、资源上限、
确定性与原子 no-clobber publication。`TST-PROOF-001` 和 `TST-REG-002` 分别覆盖 proof bundle 与
registry identity 的错误 lock domain；任一 P0/P1 finding 阻断 D0-08 freeze。
