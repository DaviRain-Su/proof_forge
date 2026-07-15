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

0. 调用者以 `env -i` + `/bin/bash --noprofile --norc` 直接执行 Stage-0
   `--require-eligible`；只有最小 bootstrap 与 Xcode closure 验证后才可启动锁定的 direct
   Python 完成 live attestation，失败时不得启动 Git 或正式 clean-room。
1. 以已验证的 direct Git 对 **commit object + `new_design` pathspec** 生成 tar archive；禁止
   直接对 subtree tree object 归档，因为 Git 会为 tree-ish 使用调用时刻 mtime，导致 archive
   SHA 不稳定。archive 必须由 `git get-tar-commit-id` 反查到外部选择的完整 candidate
   commit，同时记录 `commit:new_design` tree object ID、archive SHA-256/size，并扫描拒绝
   symlink、submodule 与越界 path。
2. 解包到随机空目录，建立空 HOME、Lake cache、tool root 和 output。
3. `env -i` 仅注入 HOME、XDG/Lake cache、TMPDIR、内部 source/output/tool root、PATH
   （只含锁定 tool shims）、TZ、LC_ALL、SOURCE_DATE_EPOCH。
4. 确认 `git rev-parse` 不可见父 repo；`LEAN_PATH`/`LEAN_SRC_PATH`/Lake env 为空。
5. 静态扫描拒绝 `import ProofForge.`、`require ..`、父路径、父 binary/fixtures/scripts hashes。
6. 从 content-addressed tool cache 执行 docs-check、Lake build/tests、四目标 gates。
7. 记录 archive/tool/environment/artifact hashes 到 `EV-ISO-*`。

正式调用者必须在 checkout 外保存预期 candidate commit、subtree tree ID 与 archive
SHA-256，并通过净化的
launcher 显式传入；harness 不得用“同一 checkout 内脚本计算出的 digest”自证真实性。
运行开始和结束都必须复核 HEAD、subtree tree 与 worktree status。`formal` 要求 clean 且
前后不变；`development` 可记录 dirty，但仍要求前后状态完全一致。该复核不排除同 UID 或
特权进程在两次采样之间修改后恢复，正式执行仍需受控 runner/workspace。

网络默认完全禁止；需要本地 RPC 的 runtime 子门禁可使用独立 profile 仅放行 loopback，
并必须有非 loopback 连接失败的负向断言。首次 tool cache provision 是独立、可审计步骤，
不属于 gate。

当前 `v2-clean-room-alpha` 已实现 committed archive、空 HOME/cache、`env -i`、父目录 deny、
Core 全断网、EVM localhost-only、clean build/test、四目标复现与 EVM runtime。consumer
实现已把 Lean ZIP 与 external solc/WABT+libcrypto/Foundry 都改为从 content-addressed cache
离线物化，不再读取 elan/Homebrew/Foundry install tree；物化本身使用 isolated/no-site
Python、`env -i` 与 no-network sandbox，包含其 Lean/Lake/external version probes。Lean
consumer 已在 commit `0b0aebda…643c8` 完成完整 development archive gate。当前 macOS host
的 H0 development attestation 已闭合，但 formal mode 因 broken seal 与 current-user-mutable
Xcode pathname 正确拒绝；这只是 local、point-in-time observation。deny-default
sandbox/evidence 也未闭合。当前 continuation 只接受显式 `--development`；formal 入口还必须
由 Stage-0 在验证 continuation digest 后直接 handoff，不能从 continuation 内部反向调用
Stage-0 冒充权威入口。因此
`TASK-D0-03` 仍在进行，`TASK-D0-04` 仍为 blocked。

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
