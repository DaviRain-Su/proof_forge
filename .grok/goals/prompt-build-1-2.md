# Goal prompt — BUILD-1 + BUILD-2（反馈循环）

> **用法**：在 Grok 会话中（仓库根、干净 worktree）执行：
>
> ```text
> /goal @.grok/goals/prompt-build-1-2.md --budget 800000
> ```
>
> 或把下文「OBJECTIVE」整段粘贴到 `/goal ...`。  
> 也可由主代理直接 `workflow name=proof-forge-engineering-slice` 带下方 JSON args。

---

## OBJECTIVE

在 **ProofForge V2** 仓库（当前 `main` HEAD）实现工程 backlog 的 **BUILD-1 + BUILD-2**，
提升日常构建/测试反馈速度，**不改变产品语义**。

权威队列：`docs/engineering-backlog.md`（§0 BUILD-1/BUILD-2）。  
控制面：`AGENTS.md`、`RECOVERY.md`（产品 CLI 已是进程内 `Loader.selectProgramV1Product`）。

### BUILD-1 — 测试 shard 有界并行

**现状**：`justfile` 的 `test` 在一次 `lake build …shards…` 后**串行**跑 9 个
`lake env .lake/build/bin/proof-forge-next-tests-shard-*`。

**要求**：

1. 保留一次 `lake build` 构建全部 shard 可执行文件（可继续串行 build 列表）。
2. **运行**阶段支持有界并行，默认例如 `P=4`，可用环境变量覆盖
   （建议名：`PROOF_FORGE_TEST_JOBS`，默认 `4`；设为 `1` 则完全串行，兼容 CI 紧内存）。
3. 任一 shard 非零退出 → 整体失败；日志中能看出**哪个 shard**失败。
4. 不改 shard 内容、不改 Lean 产品代码。
5. 注释说明：CI 可设 `PROOF_FORGE_TEST_JOBS=1` 或 `2` 以防 runner OOM。

### BUILD-2 — 默认 `build` 去掉 frontend worker

**现状**：`justfile` `build:` 含 `proof_forge_frontend_worker_v1`；产品 CLI 已不依赖该 exe。

**要求**：

1. 默认 `build` / `test-fast` / `dev-check` 依赖链**不再**构建 `proof_forge_frontend_worker_v1`。
2. 若 `just ci` 或 Frontend 测试仍需要 worker，改为显式 target
   （例如 `build-frontend-worker` 配方，由 `ci` 或相关 test 依赖）。
3. 核对 `Tests/Frontend/WorkerV1` / Protocol 是否仍进 ordinary CI；若进，ci 路径须能编出 worker。
4. 不删除 `lakefile.lean` 里的 `lean_exe` 定义（仅从默认路径摘掉）。

### 文档

- 更新 `docs/engineering-backlog.md`：BUILD-1/BUILD-2 → `done`，变更记录一行日期 `2026-08-02`。
- 不必大改 AGENTS/RECOVERY，除非某处仍写“默认 build 含 worker”。

### 验证（必须真实跑）

```bash
git status --short   # 开始时干净
just build           # 成功且不应强制 link frontend worker（可看 lake 目标列表）
just test-fast       # 绿
# 若改了 test 并行：
PROOF_FORGE_TEST_JOBS=2 just test   # 或至少跑你改过的 test 配方到绿
just docs-check
git diff --check
```

**不要**跑 `just governance-check` / `just release-check`。  
**不要** push。

### 与 workflow 配合

**路径 A（推荐，Goal 自实现）**

1. 记录 `BASE=$(git rev-parse HEAD)`。
2. 改 justfile（+ 必要 docs）。
3. 跑上述验证到绿。
4. 调用 **workflow** `proof-forge-one-slice`：

```json
{
  "slice": "BUILD-1-2",
  "base_commit": "<BASE>",
  "task_prompt": "BUILD-1 bounded parallel test shards via PROOF_FORGE_TEST_JOBS; BUILD-2 remove frontend worker from default build",
  "changed_files": ["justfile", "docs/engineering-backlog.md"]
}
```

5. 若 review 有 P0/P1 → 修 → 重跑验证 → 可再调 one-slice。
6. 本地 **一个** commit，消息示例：

   `build: parallel test shards and drop worker from default build`

7. 更新 backlog 状态后可并入同一 commit 或第二个 docs commit。
8. Goal 完成条件：clean tree、上述 commit 在 `git log -1`、backlog BUILD-1/2 = done、未 push。

**路径 B（整切片交给 engineering-slice）**

由 Goal 或用户直接启动：

```text
/workflow proof-forge-engineering-slice
```

args（JSON）：

```json
{
  "slice_id": "BUILD-1-2",
  "milestone": "D2",
  "objective": "BUILD-1: just test runs shards with bounded parallelism (PROOF_FORGE_TEST_JOBS, default 4, 1=serial). BUILD-2: remove proof_forge_frontend_worker_v1 from default just build/dev-check; keep explicit recipe for CI/tests that need the worker. Update docs/engineering-backlog.md statuses. No product Lean semantic changes.",
  "dependencies": [],
  "allowed_paths": [
    "justfile",
    "docs/engineering-backlog.md",
    ".github/workflows/ci.yml"
  ],
  "focused_checks": [
    "just build",
    "just test-fast"
  ],
  "verification_commands": [
    "just docs-check",
    "just dev-check",
    "just ci",
    "git diff --check"
  ],
  "deletion_zero_patterns": [],
  "shared_cutover": false,
  "commit_message": "build: parallel test shards and drop worker from default build",
  "constraints": "Do not change ProofForgeV2/** or Tests/** unless required to unbreak CI after removing worker from default build. Prefer env PROOF_FORGE_TEST_JOBS. Never push. Never formal/release gates."
}
```

若 CI 文件无需改，可从 `allowed_paths` / 实际 diff 去掉 `.github/workflows/ci.yml`。

### 禁止

- 不改 Normalize / target Plan 语义  
- 不新增 formal TASK  
- 不声称 formal 完成  
- 不 `git add -A`  

### 完成时 Goal 报告模板

```text
BASE: <sha>
COMMIT: <sha>
COMMANDS: just build / test-fast / … exit codes
BACKLOG: BUILD-1 done, BUILD-2 done
PUSHED: no
```
