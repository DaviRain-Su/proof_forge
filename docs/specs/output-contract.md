---
id: SPEC-OUT-001
title: OutputSet 与 Artifact Manifest 契约
status: proposed
owner: artifacts
updated: 2026-07-15
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
compiler: {name, version, commit, dirty}
program: {qualifiedName, sourceHash, semanticHash}
selection: {targetId, codegenProfileId}
plan: {schema, digest}
targetIR: {schema, digest}
toolchains: [{id, version, digest}]
support: {registryDigest, minimumEvidence, decisionsPath}
artifacts: [{role, path, mediaType, size, sha256, deployability}]
stateContinuity: "native" | "external" | "none"
settlement: {model, adapter: null|string}
reproducibility: {mode: "hermetic", environmentDigest}
```

JSON 用 RFC 8785 JCS 后 SHA-256。`compiler.dirty=true` 的 build 可用于开发，但 release
gate 拒绝。manifest 不记录 timestamp、absolute cwd、username、RPC、secret 或 private
witness。

## Artifact Roles

至少一个 primary role：EVM `deploy-bytecode`/`runtime-bytecode`，Solana `program-elf`，
NEAR `contract-wasm`，Noir `circuit`/`verification-key`。中间制品如 Yul/sBPF text/WAT/`.nr`
标记 `intermediate`，ABI/IDL 为 interface，source map/provenance 为 metadata。

`deployability`：`deployable`、`verifiable-workload`、`intermediate-only`、`non-deployable`。
Noir 没有 settlement adapter 时为 verifiable-workload，不得宣称 deployable。

## 写盘算法

1. 验证 output root 不为 source root 且不穿越 symlink。
2. 在同父目录创建 mode `0700` 随机 staging；文件 mode `0644`。
3. emitter 写 bytes，逐项限制并 hash；拒绝重复 path。
4. 运行 target artifact validators，生成 support/source-map。
5. 写 canonical manifest，fsync files/staging（平台支持时）。
6. 若 destination 存在且无 `--force`，失败；有 `--force` 时先保留 rollback rename。
7. atomic rename；失败恢复旧目录并清理 staging。

## 限制

默认单 artifact 64 MiB、总计 256 MiB、文件数 1024、path 240 bytes；profile 可降低，
提高需显式 resource policy。stdout/stderr logs 不进入 OutputSet hash。

## 错误与边界

`PF-OUTPUT-PATH`、`PF-OUTPUT-COLLISION`、`PF-OUTPUT-LIMIT`、`PF-OUTPUT-ATOMICITY`、
`PF-ARTIFACT-INVALID`、`PF-ARTIFACT-NONDEPLOYABLE`。覆盖 destination 存在、force、
symlink/path traversal、case collision、duplicate path、zero-byte required artifact、size/file
limits、disk full、permission、signal、validator fail、manifest hash mismatch、concurrent same
output、rollback failure、Noir deploy request、dirty release、JCS ordering。

## 验收

关联 `FR-009`、`TST-OUT-001/002`、`TST-SEC-001`。schema JSON validation、每个 hash
重算、failure injection atomicity、连续 build digest equality、consumer 在不读取编译器内部
文件时可完整验证 bundle。
