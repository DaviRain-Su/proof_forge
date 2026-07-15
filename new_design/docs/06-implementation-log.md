---
id: PHASE-6
title: 实现日志
status: draft
owner: engineering
updated: 2026-07-15
normative: false
---

# Phase 6：实现日志

已进入 pre-acceptance alpha 实现阶段。本文件只追加实际完成的工作；这些结果验证架构
可行性，不会越过仍为 `proposed` 的规范或自动关闭正式 Phase 1 任务。

## 2026-07-15 — TASK-A0-01 / TASK-A0-02

- Commit/worktree：父仓库 `26d2a8dd33b76201eb7062e3a86fbf87641697cd` 上的未提交
  `new_design/` 独立目录；没有父源码 import 或运行时 fallback。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SEM-001`、`SPEC-MAT-001`；
  `TST-SRC-003`、`TST-SEM-002/003`、`TST-MAT-001`。
- Changed：建立独立 Lean/Lake package、`program ... where` command DSL、目标中立 Program、
  requirement inference、参考解释器、associated `Materializer.Plan/TargetIR` 与稳定错误码。
- Commands：`lake build ProofForgeV2 proof_forge_next`；
  `lake build proof_forge_next_tests && .lake/build/bin/proof-forge-next-tests`。
- Results：均 exit 0；测试覆盖 init、increment、overflow、无源码 kind、需求推导、四目标
  materialization、Noir sync-call 拒绝和 private witness 不泄漏到 EVM。
- Evidence：`EV-20260715-0001`、`EV-20260715-0002`。
- Limitations：grammar 仍是 Counter/PrivateSum4 所需最小子集；尚无完整 name/type/effect、
  span/NodeId、循环/结构体/事件/扩展 elaboration。
- Next：正式接受规格后扩展 D1/D2，不把 alpha subset 标为完整 frontend。

## 2026-07-15 — TASK-A0-03

- Spec/Test：`SPEC-OUT-001`、四个 target dossier；`TST-EVM-003/004/005`、
  `TST-NEAR-003/004`、`TST-SOL-003`、`TST-NOIR-003`。
- Changed：同一 Counter 生成 EVM Yul/ABI/bytecode、Solana assembly plan/IDL、NEAR
  host-import WAT/Wasm、Noir source/Prover input；manifest 绑定同一 semantic hash。
- Commands：`just target-smoke`；`bash scripts/smoke_evm.sh`。
- Results：artifact validation exit 0；EVM 在 Anvil 验证 initial=7、increment=12，max+1
  revert 后状态仍为 max；NEAR `wat2wasm` 通过。
- Evidence：`EV-20260715-0003`、`EV-20260715-0004`。
- Limitations：Solana `.s` 是 plan-level assembly，尚非语义完整 ELF；NEAR 未跑 sandbox；
  Noir 未安装 Nargo/BB，故没有 ACIR、proof、VK 或 verify，二者 manifest 保持 non-deployable。
- Next：先补 sBPF ELF/runtime 与 Nargo/BB exact profile，再提升对应 maturity。

## 2026-07-15 — TASK-A0-04

- Spec/Test：`SPEC-REPRO-001`、`TST-ISO-002/003`。
- Changed：加入 docs checker、负语法 gate、四目标 artifact validator 与 archive-style
  isolation harness。
- Command：`just isolated-check`。
- Results：临时目录从归档源码重建 45 jobs，测试、文档检查和父 `ProofForge` import/
  symlink 扫描全部 exit 0。
- Evidence：`EV-20260715-0005`。
- Limitations：脚本没有创建新 HOME/Lake cache，没有把 PATH 限制为锁定工具 shims，也没有
  证明父 Git root 不可发现；因此这只是 archive isolation smoke，不是 `SPEC-REPRO-001`
  定义的完整 clean-room gate。当前还是 dirty development evidence；release evidence 必须
  在提交后重新生成。
- Next：完成正式评审后在候选 commit 重跑并记录 artifact digest。

## 2026-07-15 — TASK-A0-05

- Commit：`6d1d0b5a334e2575e140e1be28392da2710c013c`。
- Changed：CLI source loader 改为 Lean Parser 加 DSL command 白名单，不 elaboration 用户
  module；command elaborator 与 loader 共用 syntax decoder。编译边界拆成独立
  `Source.Program → Typed.Program → Semantic.Program`，target materializer 只接收后者；
  SourceHash 与 SemanticHash 分离。外部工具按 lock 校验版本与 executable SHA-256，输出
  先写 sibling staging，已有 destination 默认 `PF-OUTPUT-COLLISION`，不再覆盖用户目录。
- Commands：`just check`；`just evm-runtime`；`just reproducibility`；
  `just isolated-check`；`git diff --cached --check`（暂存后执行）。
- Results：完整 alpha gate exit 0；Lean parser/typed/semantic/target/negative/path tests 通过；
  EVM Anvil 验证 nonpayable、7+5=12 与 max+1 回滚；四目标两次构建共 19 文件逐字节一致；
  archive isolation smoke 在临时目录重建 61 jobs 并运行测试/docs-check。独立复核发现的
  existing-output/source-directory 数据丢失风险已修复，并由回归测试确认原文件保持不变。
- Evidence：`EV-20260715-0006`、`EV-20260715-0007`。
- Limitations：当前仍是 Counter/PrivateSum4 alpha 子集；完整 span/NodeId、effect/bound/
  disclosure 系统及正式 hermetic clean-room gate 均未完成；Solana 仍无 ELF/runtime、NEAR
  仍无 sandbox receipt、Noir 仍无 ACIR/prove/verify。
- Next：先完成 `TASK-D0-04` hermetic clean-room gate，再继续正式 D1/D2；不能以本条提升
  目标 maturity。

## 2026-07-15 — TASK-A0-06

- Commit/input：clean-room 输入为已提交树
  `6d1d0b5a334e2575e140e1be28392da2710c013c:new_design`；归档 SHA-256 为
  `fa875a84201428e4bbc4f2d1681ce4845cd099a9d27a30844a07d8ff24d506d7`。
- Spec/Test：`SPEC-REPRO-001`、`TST-ISO-002`、`TST-EVM-005`。
- Changed：`verify_isolation.sh` 只归档已提交 V2 子树，拒绝 symlink/submodule、父路径和
  父 `ProofForge` import；在随机 HOME/cache/tool/output 下以 `env -i` 运行，Core sandbox
  禁止全部网络，EVM sandbox 仅允许 localhost；复制并校验 Lean/Lake 与外部工具可执行文件，
  clean build/test 后验证四目标制品、19 个文件逐字节复现及 Anvil Counter runtime。
- Command：`just v2-clean-room-alpha`。
- Results：Darwin arm64 上 exit 0；61-job clean build、测试、docs-check、四目标 artifact
  validator 和两轮 reproducibility 通过；sandbox probe 证明 Core 无 localhost，EVM profile
  允许 localhost 且拒绝非本地地址；EVM 验证 nonpayable、7+5=12 与 max+1 回滚。
- Evidence：`EV-20260715-0008`。
- Limitations：这是 network-denied clean-room alpha，不是正式 hermetic gate。复制的
  `/opt/homebrew/bin/solc` 与 `wat2wasm` 仍从宿主加载未锁定 dylib；Lean toolchain closure
  不是内容寻址发布归档；`/usr/bin/python3`、Git、tar、shasum、`sandbox-exec` 等 harness
  runtime 也未锁定。未生成 schema-complete `EV-ISO-*` JSON，且只验证 Darwin arm64。
- Next：完成 `TASK-D0-03` 的完整工具/运行时 closure 锁定后解除 `TASK-D0-04` blocker；
  在此之前不得把 alpha 改称 hermetic 或 release evidence。

## 记录模板

```markdown
### YYYY-MM-DD — TASK-*

- Commit/worktree: `<sha>` / clean|dirty（列出 task-owned diff）
- Spec/Test: `SPEC-*`, `TST-*`
- Changed: 精确文件与行为
- Commands: 完整可复现命令
- Results: exit code、case 数和关键观测
- Evidence: `EV-*` 路径与 artifact hashes
- Limitations: 未验证工具/网络/安全边界
- Next: 下一项唯一任务
```

禁止用“看起来正常”“应该通过”代替命令结果；失败和回退尝试也应记录。
