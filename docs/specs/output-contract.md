---
id: SPEC-OUT-001
title: OutputSet 与 Artifact Manifest 契约
status: proposed
owner: artifacts
updated: 2026-07-16
normative: true
---

# OutputSet 与 Artifact Manifest 契约

## 目录

```text
<output>/
  proof-forge-output.json
  artifacts/<target-owned files>
  interfaces/<abi|idl|circuit-abi files>
  provenance/support-decisions.json
  provenance/source-map.json
```

manifest 必须最后写入并原子发布；所有路径为 `/` 分隔的相对 NFC 路径，不含 `..`、
绝对路径、空 segment、symlink 或 case-fold collision。

## ManifestV1

```text
schema: "proof-forge.output.v1"
candidate: {commit, treeObjectId, archiveDigest, digest}
compiler: {name, version, commit, dirty}
program: {qualifiedName, sourceHash, semanticHash, semanticProvenanceDigest}
selection: {
  targetId, targetSemanticsVersion, targetSemanticsDigest,
  codegenProfileId, codegenProfileDigest
}
plan: {schema, digest}
targetIR: {schema, digest}
toolchains: [{id, version, lockDigest, digest}]
support: {registryDigest, minimumEvidence, decisionsPath, decisionsDigest}
artifacts: [{role, path, mediaType, size, sha256, deployability}]
stateContinuity: "native" | "external" | "none"
settlement: {model, adapter: null|ContentRef}
reproducibility: {mode: "development"|"hermetic", environmentDigest}
```

root wire object 恰为
`schema,candidate,compiler,program,selection,plan,targetIR,toolchains,support,artifacts,`
`stateContinuity,settlement,reproducibility`；所有 root/nested object 都必须包含且只包含上面列出的
字段。`schema` 固定为 `proof-forge.output.v1`，manifest 不内嵌自引用 digest；其唯一 digest 为：

```text
manifestDigest = SHA-256("proof-forge.output.v1" || 0x00 || JCS(ManifestV1))
```

`candidate` 是 SPEC-CAP-001 的完整 `CandidateIdentity`；`compiler.name` 是 1..127-byte lowercase
kebab ASCII，`version` 是 canonical SemVer，`commit` 是 TRACE-EV-001 `GitObjectId`，且必须
`compiler.commit == candidate.commit`。`dirty` 只接受 JSON Bool；`dirty=true` 的 build 可用于开发，
但 release gate 拒绝。manifest 不记录 timestamp、absolute cwd、username、RPC、secret 或 private
witness。

`program.qualifiedName` 使用 SPEC-COMMON-001 `QualifiedName` nonempty component array；
`sourceHash`/`semanticHash`/`semanticProvenanceDigest` 是 Digest。前两项分别绑定 canonical
Source.Program 与 business SemanticProgram；第三项绑定已对当前 source inventory 验证的 companion
provenance，但不得成为 target lowering 分支条件。`selection` 是 SPEC-REG-001 flattened BuildIdentity。
`plan`/`targetIR` 恰为 `schema,digest`，schema 必须 resolve 到 selected target/profile 的 exact
typed schema。`toolchains` 的每项是 SPEC-REG-001 `ToolchainIdentity`，至少包含 selected
CodegenProfile 的 `compilerToolchain` 及所有实际执行的 external tool closure，按
`(id UTF-8,version UTF-8,lockDigest,digest)` 唯一升序。

`support` 恰为 `registryDigest,minimumEvidence,decisionsPath,decisionsDigest`；
`minimumEvidence` 是 effective minimum，必须 `>=` profile minimum 且等于 decision-set root
`minimum`。`decisionsPath` 固定为 `provenance/support-decisions.json`。`artifacts` 按 path 的 NFC
UTF-8 bytes 唯一升序；role 相同可重复，path 不可重复。每项 `size` 必须等于实际 bytes 且不超过
JSON safe integer，`sha256` 使用 Digest wire form，并等于实际 bytes 的 raw SHA-256。

成功目录的 regular-file closure 必须 exact 等于
`{proof-forge-output.json, support.decisionsPath} ∪ {artifact.path}`；不得有 unlisted file、socket、
device、directory entry alias 或 manifest 外 sidecar。`support.decisionsPath` 不得同时出现在
`artifacts`，其 bytes/size 受同一 safe-read 与 output resource cap，digest 按 SPEC-CAP-001 重算。
`provenance/source-map.json`、所有 `interfaces/*` 及 target-owned file 若存在都必须各自作为一项
artifact 列出并匹配 selected profile 的 exact auxiliary/primary role；空目录不参与 closure，unknown
directory/file 一律 `PF-ARTIFACT-INVALID`。consumer 必须先 bounded walk/build closure，再信任任何
manifest path，避免只验证已列文件而忽略恶意附加内容。

`stateContinuity` wire enum/rank 为 `native < external < none`。`settlement.model` 必须等于 selected
TargetSemantics 的 `SettlementModel` wire value；`adapter` 字段始终存在，只能是 `null` 或
SPEC-COMMON-001 exact `ContentRef`。`reproducibility.mode` wire enum/rank 为
`development < hermetic`；`hermetic` 只有 formal eligible-host/clean-room binding 验证通过时可写，
release 必须为 `hermetic`。所有 array 以本节规定顺序参与 JCS；JCS 只排序 object key，不能替代
array canonicalization。

`selection` 五个字段共同构成 `BuildIdentity`，必须与 Plan、TargetIR 和每个 artifact provenance
完全一致。deploy/verify 只使用 manifest 中该 identity 与 `NetworkProfileV1.compatibleBuilds` 做
exact join；调用时解析出的 `NetworkProfileIdentity` 必须同时包含 ID 与 digest，
deploy/verify receipt 保留二者。不得从 target 名、endpoint、chain ID 或当前 registry default
猜测缺失字段，也不得只比较 profile ID 后忽略 digest。

identity/digest authority 不由 manifest 重定义：target semantic、CodegenProfileV1、NetworkProfileV1、
BuildIdentity 和 canonical registry digest 由 [`SPEC-REG-001`](target-registry.md) 产生并验证；manifest
只复制 exact selected values。`support-decisions.json` 由 [`SPEC-CAP-001`](capabilities-extensions.md)
拥有，必须包含 candidate、selected BuildIdentity、本次 canonical ProgramRequirements 的每个
request、descriptor exact claim/claimDigest、achieved grade 和 canonical `SupportBindingRef` 集合；
`decisionsDigest` 固定使用
`SHA-256("pf.support-decisions.v1" || NUL || JCS(support-decisions.json))`。support binding 本体使用
SPEC-CAP-001 的 `pf.support-evidence-binding.v1` domain。`registryDigest`、`decisionsDigest` 和所有
identity digest 均使用 SPEC-COMMON-001 `Digest` wire form；consumer 必须重算/lookup authority
schema，不能用 manifest 自己作为 digest oracle。

manifest 的 `candidate` 必须与 `support-decisions.json.candidate`、resolver 注入的
`ProfileSupportIndex.candidate` 以及 release evidence-set candidate 四者 exact 相等；consumer 必须
重算 candidate digest 后再比较。只匹配 commit 不够，treeObjectId、archiveDigest、candidate digest
任一不等都返回 `PF-EVIDENCE-BINDING` 且零输出。decision-set root `build` 必须等于 manifest
selection；decision requests 必须 exact 覆盖本次 program requirements，且每项 claim/claimDigest 必须
exact 来自该 registry digest 下的 selected descriptor；未请求的 static claim 不得伪造为 decision。
这禁止把 candidate A 的 valid decisions 重放到相同 BuildIdentity 的 candidate B。

## Artifact Roles

primary contract 不由 TargetId 硬编码，而由 manifest selection exact resolve 的
`CodegenProfileV1.artifactEncoding.primaryGroups` 拥有。validator 必须选择且完整满足一个 canonical
group：组内每个 `(role,mediaType,deployability)` 至少有一份 size `> 0` 且 hash 正确的 artifact；
每份 artifact 必须 exact 匹配任一已声明 primary member 或 `auxiliary` role-spec，同时输出多个
alternative 的 primary member 合法。匹配零组、多个声明冲突、额外 role、wrong media type/
deployability 或 zero-byte required artifact 都是 `PF-ARTIFACT-INVALID`。

初始 profile 的 exact group 由 SPEC-REG-001 冻结：EVM bytecode、NEAR contract Wasm 是 deployable
primary；当前 `solana-sbpf-plan-v1` 的 `.sbpf-plan` 与
`noir-source-u64-relations-v1` 的 Noir source package 是 `intermediate-only` primary。因此二者可形成
schema-valid OutputSet，但 deploy/prove/verify 必须以 `PF-ARTIFACT-NONDEPLOYABLE` 拒绝，且不得被描述
为 ELF、ACIR、VK 或 proof。reserved `solana-sbpf-elf-v1`/`noir-acir-proof-v1` 只有正式注册并通过
各自 gate 后才使用新的 executable/proof group；不能借当前 profile ID 原地升级。

Yul/sBPF text/WAT、ABI/IDL、source map/provenance 只有在 selected profile 的 auxiliary list exact
登记后才合法。`ArtifactDeployability` wire form 由 SPEC-COMMON-001 拥有；primary 只表达 bundle
完整性，不表达 runtime/proof maturity。`verifiable-workload` 不等于 deployable；Noir 没有 exact
settlement adapter 时不得宣称 deployable。

## 写盘算法

1. 验证 output root 不为 source root 且不穿越 symlink。
2. 在同父目录创建 mode `0700` 随机 staging；文件 mode `0644`。
3. emitter 写 bytes，逐项限制并 hash；拒绝重复 path。
4. 运行 target artifact validators，生成 support/source-map。
5. 写 canonical manifest，fsync files/staging（平台支持时）。
6. 若 destination 存在且无 `--force`，失败；有 `--force` 时先保留 rollback rename。
7. atomic rename；失败恢复旧目录并清理 staging。

## 限制

默认单 artifact 64 MiB、总计 256 MiB、文件数 1024、path 240 bytes；profile/CLI 只可降低。
提高任一 hard maximum 必须按 SPEC-COMMON-001 发布新 `ResourceProfileV1.profileId` version、
review 和 digest，不能靠运行时 policy；只有 wire field 或语义变化才提升 resource-profile schema。
stdout/stderr logs 不进入 OutputSet hash。

## 错误与边界

`PF-OUTPUT-PATH`、`PF-OUTPUT-COLLISION`、`PF-OUTPUT-LIMIT`、`PF-OUTPUT-ATOMICITY`、
`PF-ARTIFACT-INVALID`、`PF-ARTIFACT-NONDEPLOYABLE`。覆盖 destination 存在、force、
symlink/path traversal、case collision、duplicate path、zero-byte required artifact、size/file
limits、disk full、permission、signal、validator fail、manifest hash mismatch、concurrent same
output、rollback failure、Noir deploy request、dirty release、JCS ordering、registry/support-decision
digest mismatch、candidate/tree/archive replay、missing/wrong-profile support binding、artifact group/
media/deployability mismatch、network profile ID 相同但 digest 不同。

## 验收

关联 `FR-009`、`TST-OUT-001/002`、`TST-SEC-001`。schema JSON validation、manifest 与所有 retained
file/content/support/registry identity hash 重算、failure injection atomicity、连续 build digest equality。
仅凭 OutputSet directory 不能重算未 retained 的 Source/Semantic/Plan/TargetIR preimage，因此 consumer
不得把 manifest 中这些 digest 的字段存在误报为 end-to-end provenance validation；formal 声明还必须
由 candidate-bound evidence 对 exact manifest digest、compiler inputs 和这些 canonical carrier digest
做外部 join。没有该 evidence 时 `inspect` 最多报告 structural/content validity，不能报告 formal provenance。
