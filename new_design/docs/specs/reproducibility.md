---
id: SPEC-REPRO-001
title: 可重现构建与 Clean-room 规格
status: proposed
owner: build
updated: 2026-07-15
normative: true
---

# 可重现构建与 Clean-room 规格

## Reproducible Inputs

输入集合只有：归档内 tracked V2 files、`lean-toolchain`、`lake-manifest.json`、
`toolchains.lock.json`、显式 CLI 参数和指定 source。时间、locale、timezone、username、HOME、
cwd absolute path、Git parent、network、PATH 顺序和并发调度不得影响 semantic/plan/artifact
bytes。编译设置 `TZ=UTC`、`LC_ALL=C`、`SOURCE_DATE_EPOCH=0`。

## Hash Domains

每个 hash 以 ASCII domain tag + NUL 开头：`pf.source.v1`、`pf.semantic.v1`、
`pf.plan.<target>.v1`、`pf.targetir.<target>.v1`、`pf.artifact.v1`。统一 SHA-256；array 保序，
set/map canonical sort；JSON JCS；路径 project-relative NFC。

## Repeatability Gate

在两个不同 absolute roots、不同 HOME、不同 allowed job counts 下各 build 两次；比较
sourceHash、semanticHash、planHash、TargetIR hash、所有 artifact hash 和 manifest
（排除显式 `compiler.dirty` development field）。任一差异输出首个 byte offset 和关联阶段。

## Clean-room Gate

1. `git archive` 只包含 `new_design/` allowlist；扫描拒绝 symlink 和指向外部的 submodule。
2. 解包到随机空目录，建立空 HOME、Lake cache、tool root 和 output。
3. `env -i` 仅注入 HOME、PATH（只含锁定 tool shims）、TZ、LC_ALL、SOURCE_DATE_EPOCH。
4. 确认 `git rev-parse` 不可见父 repo；`LEAN_PATH`/`LEAN_SRC_PATH`/Lake env 为空。
5. 静态扫描拒绝 `import ProofForge.`、`require ..`、父路径、父 binary/fixtures/scripts hashes。
6. 从 content-addressed tool cache 执行 docs-check、Lake build/tests、四目标 gates。
7. 记录 archive/tool/environment/artifact hashes 到 `EV-ISO-*`。

网络默认完全禁止；首次 tool cache provision 是独立、可审计步骤，不属于 gate。

## Cache Policy

cache key 必须含 toolchain lock digest、compiler/source/profile/schema/platform；cache value 取出
后重验 hash/schema。release evidence 至少有一次 `cache=empty`。父项目 `.lake`、build、
olean、binary 和通用 writable PATH 不得进入 cache search。

## 边界与验收

覆盖 absolute root/HOME/locale/timezone/job count、file mtime/umask、reordered directory、dirty
Git、empty/poisoned cache、symlink/hardlink、parent Git discovery、LEAN_PATH/PATH poisoning、
network attempt、tool asset replacement、case-insensitive FS、不同 host arch、concurrent builds、
partial output、archive missing untracked required file。关联 `NFR-001/004`、
`TST-ISO-001..003`、`v2-artifact-repeatability`、`v2-clean-room`；Phase 1 release 要求两种
受支持 host platform 均通过或明确只发布单平台。
