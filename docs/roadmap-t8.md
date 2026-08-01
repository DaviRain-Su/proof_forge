---
id: ROADMAP-T8
title: T8 路线图（持久执行计划）
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# T8 路线图（持久执行计划）

> 本文件是 T8 系列切片的**持久执行权威**。任何调度任务/协作 agent 按本文件推进；
> 状态只允许 `pending / in_progress / merged / blocked`；完成后更新状态与日期。
> 主代理（Grok Build）持有控制面（AGENTS.md/Agents.md/MIGRATION_MATRIX.md）与共享文档的合并权。

## 执行协议（每个切片必须遵守）

1. **基座**：`git fetch origin` 后从 `origin/main` 建隔离 worktree：`git worktree add ~/.grok/worktrees/projects-proof-forge/<slice> origin/main`
2. **实现**：派 general-purpose 子代理实现（brief 必须包含：背景事实、设计规格、验证清单、`--run` 提示、fail-closed 边界）；**禁止子代理 commit**、**禁止子代理改 AGENTS.md/Agents.md/MIGRATION_MATRIX.md**（主代理合并时处理）
3. **审计**（主代理/协调者）：读关键 diff；**Amp 共享文件检查**：`git log <worktree-base>..origin/main -- <文件集>` 非空 → 该文件不能用 worktree 版整文件复制，改用 `git -C $WT diff <base> -- <file> | git apply --3way`；语义性冲突（如 N3×T8b）→ oracle 出方案后手工整合
4. **合并**：
   - 非共享代码文件：从 worktree 复制到 main
   - `docs/06-implementation-log.md`：**永远从 HEAD 版追加**（提取 worktree 的切片条目 → append），禁止整文件覆盖
   - `supply-chain/lean-package-files.v1.json`：**在 main 里重跑** `just sbom-package-files-refresh`（禁止复制 worktree 的 pin——基座旧哈希会污染）。**顺序硬规则**：refresh 必须是 commit 前最后一步——之后任何 ProofForgeV2/** 变更（包括合并、stash pop、Amp 文件进入）都必须重刷，否则 CI sbom 检查必挂（T8a/T8d 两次踩坑）
   - main 验证：`lake build` + `rm -f .lake/build/bin/proof-forge-next-tests-shard-targets* && lake build proof_forge_next_tests_shard_targets && lake env .lake/build/bin/proof-forge-next-tests-shard-targets`（**必须 `lake env` 前缀**，裸跑缺 LEAN_PATH 报 unknown module prefix）；Solana 相关切片还要 `PROOF_FORGE_TOOL_ROOT=$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64 bash scripts/solana_runtime_test.sh`
5. **提交推送**：显式 `git add`（列文件），消息描述事实；推送被拒 → `git rebase --autostash origin/main`；docs 冲突 → 并集
6. **清理**：合并后**立即** `git worktree remove --force` + `rm -rf`
7. **CI**：main CI 会被 Amp 推送取消；用隔离验证：`git branch ci-verify-<slice> <commit> && git push origin ci-verify-<slice> && curl -X POST .../actions/workflows/304626303/dispatches -d '{"ref":"ci-verify-<slice>"}'`，完成后删分支。**不要循环等待**；结果顺手查一次
8. **控制面**：AGENTS.md/Agents.md 状态行由主代理在切片合并时更新（用精确文本替换，先确认锚点在 HEAD 只出现一次）

## 已踩的坑（必读）

- `lake env lean <file>` 不执行 main——必须 `--run`
- stale olean/残次 exe：`python3 -I -S scripts/ci/prune_stale_oleans.py` + 删除 `proof-forge-next-tests-shard-targets*` 后重建
- SBOM 提交时 pin 必须与提交树一致（CI `sbom-package-files-check` 按 checkout 树比对）——先 refresh 再 commit；若 refresh 后文件又改（如 EnvelopeV1 合并），必须重刷
- 共享工作区：Amp 的 agent 在同一 checkout 提交/暂存——commit 前查 `git status`，防止扫走他人暂存文件（如 docs/research/* 事故）
- Lean doc comment 后**不能空行再接 doc comment**（parse error）
- ProgramV1 源里 `/- -/` doc comment 会 PF-SRC-INVALID；用 `--` 行注释
- Solana 运行时 fixture 的 discriminator/layout marker 由 Rust 独立计算并与 plan 交叉验证——签名宽度化后 Rust 侧必须同步

## 切片清单

### [merged] T8b-EVM：EVM state/param UInt8/16/32 ABI（2026-08-01, dd8a00280）
模板实现。EnvelopeV1 `isAbiUintWidth`/`requirePublicUintAbiOrInt64*`/`byteWidthOfBitWidth`；
StorageBinding/Param/Store.byteWidth；selector `uint8/16/32`；Yul `and` 掩码。与 N3 aggregate 并存
（aggregate 叶子保持 64 位）。CI 隔离验证绿。

### [merged] T8b-Solana：Solana state/param UInt8/16/32 ABI（2026-08-01, acc7eb514）
模板实现。byteWidth 1/2/4/8、8B 槽位；SBPF ldxb/h/w + stxb/h/w + imm stb/h/w；
discriminator 签名 `u8/16/32`（64 位含 Int64 保持 `u64`）；layout marker `u8-le` 等；IDL 同步；
NarrowAbi 运行时 fixture（34 测试）。CI 隔离验证中。

### [merged] T8b-NEAR：NEAR state/param UInt8/16/32 ABI（2026-08-01, 7b897fdaf）
参照 T8b-Solana：`requirePublicUintAbiOrInt64*`；param 8B pitch + 窄值低位；
KV 值长=byteWidth；narrowParam/StateLoad + Store.byteWidth；WAT i32.load8_u/… +
storage_write exact length；near-abi.json `u8-le/…`。Body 多宽仍 T8c。
NearHostModel AbiMw + UInt128/Int8 负向；shard-targets 绿。CI 隔离验证中。

### [merged] T8b-Noir：Noir state/param UInt8/16/32 ABI（2026-08-01, be812b0d4）
参照 T8b-NEAR：`requirePublicUintAbiOrInt64OrField*` + `pilotUintWidthPolicyNoirAbi`；
`InputType` 增 u8/u16/u32；与 Field 并存；窄载入 zero-extend 到 UInt64 body temps；
emit 原生 Noir 类型 + assertEqual 窄宽 cast；UInt128/Int8/窄结果 fail closed。
Body 多宽仍 T8d。NoirRelationModel goldens；shard-targets 绿。CI 隔离验证中。

### [merged] T8c：NEAR body 多宽 UInt8/16/32（2026-08-01, 451a452b3）
镜像 T8a：Envelope `pilotUintWidthPolicyNearBody`；LowerSemantic UInt{8,16,32,64}
body temps + narrowChecked*/narrowBit*/narrowShl/Shr；EmitIR/WAT 高位 shr_u 守卫；
NearHostModel + `testNarrowBodyProductPath`；UInt32 count 用 narrowCheckedAdd 32。
shard-targets 绿。隔离 CI 已 dispatch（ci-verify-t8c-near-body）。

### [merged] T8d：Noir body 多宽 UInt8/16/32（2026-08-01, 91bd079ff）
镜像 T8a/T8c：Envelope `pilotUintWidthPolicyNoirBody`；LowerSemantic UInt{8,16,32,64}
body temps + narrow* Plan ops（Field 仍 field*）；EmitIR `assert((t >> w) == 0)`；
NoirRelationModel host + `checkNarrowBodyProduct`。shard-targets 绿。
隔离 CI 已 dispatch（ci-verify-t8d-noir-body）。

### [merged] M4 闭合：EVM planDigest 绑进 BuildIdentity/OutputSet（2026-08-01, 13e3a54be）
`EngineeringBuildIdentityV1`/`EngineeringOutputSetV1` 增 `planDigest`；EVM 用
`engineeringEvmPlanDigestV1`，其他 target `engineeringAbsentPlanDigestV1`；
manifest/CLI/validate_artifacts 发布字段。shard-targets 绿。
隔离 CI 已 dispatch（ci-verify-m4-plan-digest）。

## T9 阶段切片清单（2026-08-02 起）

> 执行模式：参照 T8 的 merged 切片（T8b-EVM 是 ABI 模板、T8a 是 body 模板、M4 是 digest 模板）。
> 每切片按"执行协议"走完整流程；顺序固定（依赖关系），不跳项。

### [merged] T9a：窄结果四 target（entry/view 返回 UInt8/16/32）（2026-08-01, 642e6016e）
EVM/Solana/NEAR/Noir resultKind 扩展 UInt8/16/32；EVM ABI uint8/16/32；Solana
set_return_data 1/2/4 + SBPF stxb/h/w；NEAR value_return 长度 + u8-le ABI；Noir
原生 result InputType。UInt128 结果 fail closed。NarrowResult Mollusk 三测绿。
shard-targets 绿。隔离 CI 已 dispatch（ci-verify-t9a-narrow-result）。

### [merged] T9b：EVM UInt128/256 ABI（state/param + body）（2026-08-01, 09c07cfc8）
EVM-only：type-table/isEvmAbiUintWidth 扩 {128,256}；byteWidth 16/32；wide LE
literal + bigLiteral；ResultKind uint128/256；Yul 掩码 + ABI；PlanSchema tag 49。
Solana/NEAR/Noir 保持 fail closed。EvmSmoke WideUint 绿；shard-targets 绿。
隔离 CI 已 dispatch（ci-verify-t9b-evm-u128-256）。

### [merged] T9c-EVM：窄 Int（Int8/16/32 body + ABI）EVM-first（2026-08-01, f523b674f）
EVM-only：`pilotIntWidthPolicyNarrow`；ResultKind int8/16/32；ABI int*；
`narrowSigned*` Plan tags 51–58；Yul signextend+range；EvmSmoke NarrowInt。
Solana/NEAR/Noir 仍 Int64-only → 见 pending **T9c-2**。
隔离 CI 已 dispatch（ci-verify-t9c-evm-narrow-int）。

### [merged] T9c-2：窄 Int 其余三 target（Solana/NEAR/Noir body + ABI）（2026-08-01, 65bc46956）
Solana ResultKind i8/i16/i32 + layout i*-le + Plan narrowSigned*（Emit→signed IR）；
NEAR MethodResultKind int8/16/32 + i64 plan surface；Noir InputType i8..i64。
SolanaPlanV1 NarrowInt 绿。隔离 CI 已 dispatch（ci-verify-t9c2-narrow-int）。

- 镜像 T9c-EVM：`pilotIntWidthPolicyNarrow` + signed narrow Plan/IR/emit + results
- Solana layout `i*-le` + SBPF 宽度守卫；NEAR WAT；Noir i8/i16/i32
- 金样 + 可选 Mollusk NarrowInt fixture

- 当前 Int64-only（pilotIntWidthPolicyI64）；TypeCheck/Normalize 已开 Int 窄宽（T1）
- 工作面：Envelope Int 策略扩展；signed 语义（符号扩展、signed overflow min/max 检测、toward-zero div/rem、arsh 算术右移）；四 target
- 注意与 UInt 窄宽的区分（isInt 标志 + 宽度）；金样 + 负向（Int128/256 保持 fail closed）

### [pending] T9d：M5 其余 target planDigest 绑 identity（NEAR/Solana/Noir）
- 镜像 M4（13e3a54be）：NEAR/Solana/Noir plan schema digest + `engineering*PlanDigestV1` + BuildIdentity/OutputSet/manifest 字段 + CLI inspect
- 小-中切片；金样 IdentityChain/OutputSet

### [pending] T9e：Solana/NEAR UInt128/256（多字算术，大工程，最后）
- 64 位寄存器平台需要双字/四字软件算术（add/sub/mul/div、比较、移位）
- 先做设计（worktree 内 prototype + oracle 评审）再实现；EVM 的 T9b 语义是参照
- 可能拆分 T9e-Solana / T9e-NEAR

### [pending] T9-0：MIGRATION_MATRIX 深度对齐（主代理直接做，不进调度）
- D2 行 "target Plan ABI 仍 UInt64/Int64-only"、v2alpha1 残留、M3/M4/N2-N5 状态行——逐行按代码事实修正

## 执行顺序

T9-0（主代理）→ T9a → T9b → T9c → T9d → T9e（每个之间留 audit+CI 窗口；若 Amp 合入相关模块改动，先按协议 3 处理；Amp 的 N4 String/N5/NoirPrivate/ArrayState/EvmSolc 并行 lane 若与切片工作面交叉，按 3way/oracle 处理）

## 状态记录

| 日期 | 切片 | 结果 |
|---|---|---|
| 2026-08-01 | T8b-EVM | merged dd8a00280, CI 绿 |
| 2026-08-01 | T8b-Solana | merged acc7eb514, 隔离 CI 验证中 |
| 2026-08-01 | T8b-NEAR | merged 7b897fdaf, 隔离 CI 已 dispatch（ci-verify-t8b-near） |
| 2026-08-01 | T8b-Noir | merged be812b0d4, 隔离 CI 已 dispatch（ci-verify-t8b-noir） |
| 2026-08-01 | T8c | merged 451a452b3, 隔离 CI 已 dispatch（ci-verify-t8c-near-body） |
| 2026-08-01 | T8d | merged 91bd079ff, 隔离 CI 已 dispatch（ci-verify-t8d-noir-body） |
| 2026-08-01 | M4 | merged 13e3a54be, 隔离 CI 已 dispatch（ci-verify-m4-plan-digest） |
| 2026-08-01 | T9a | merged 642e6016e, 隔离 CI 已 dispatch（ci-verify-t9a-narrow-result） |
| 2026-08-01 | T9b | merged 09c07cfc8, 隔离 CI 已 dispatch（ci-verify-t9b-evm-u128-256） |
| 2026-08-01 | T9c-EVM | merged f523b674f, 隔离 CI 已 dispatch（ci-verify-t9c-evm-narrow-int） |
| 2026-08-01 | T9c-2 | merged 65bc46956, 隔离 CI 已 dispatch（ci-verify-t9c2-narrow-int） |
