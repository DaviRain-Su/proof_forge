# Goal prompt — N-A2（多臂同外构造器 match 细化）

> **用法**：BUILD 切片合入/完成后，在干净 worktree：
>
> ```text
> /goal @.grok/goals/prompt-n-a2.md --budget 2000000
> ```
>
> 这是 **sole Normalize 共享核** 切片：禁止并行 leaf 改同一文件。

---

## OBJECTIVE

闭合工程 backlog **N-A2** / research matrix **N-A2**：  
`match` 多条 arm **共享同一外层构造器**时，允许安全细化（nested `VariantPayload` / 更细 pattern），
而不是一律 fail-closed。

权威：

- `docs/engineering-backlog.md` §2.2 N-A2  
- `docs/research/12-target-coverage-matrix.md`（match 多臂同构造器）  
- `docs/research/11-feature-coverage-audit.md`（match 嵌套子模式相关）  
- 代码：`ProofForgeV2/Semantic/NormalizeV1.lean`（及必要的 TypeCheck / Reference / 测试）

### 先做调研再写码（Goal 第一轮）

1. 在 `NormalizeV1.lean` 用 `rg`/`read_file` 定位当前「同外构造器多 arm」拒绝点与注释。  
2. 读 TypeCheck match 相关与既有 constructor pattern 正/负测。  
3. 写出**最小契约**（3–8 条）：合法源程序形状、降低后 CFG/op 序列、仍 fail-closed 的情况。  
4. 若发现需要改 Wire/schema 或四 target Plan 大改 → **停**，回写 backlog「blocked：依赖 …」，不要硬扩。

### 实现契约（预期方向，以代码事实为准）

- **正例**：同一 enum/Option 外构造器、不同 payload 子模式（或嵌套字段）的多 arm match，
  Normalize 产出 structure-valid `SemanticProgramV1`（`validateSemanticProgramV1` 过）。  
- **负例**：仍拒绝不安全/不可判定细化（重复全覆盖、冲突 arm、非法嵌套等），稳定诊断。  
- 不静默擦除 arm；不引入 fallback。  
- Reference 若 admit 该 op 序列，补步进正例；否则明确 defer 并测 Normalize-only。  
- 四 target：至少 **fail-closed 或 lower** 有测；优先复用现有 match region 路径，禁止半吊子 partial lower。

### 允许改动路径（尽量收紧）

```text
ProofForgeV2/Semantic/NormalizeV1.lean
ProofForgeV2/Semantic/ReferenceV1.lean          # 仅若必要
ProofForgeV2/Typed/TypeCheckV1.lean            # 仅若 typing 边界必须
Tests/Semantic/** 或 Tests/Typed/** 或挂在 CheckV1 的 Normalize 套件
docs/engineering-backlog.md
docs/research/12-target-coverage-matrix.md     # GAP→LOWERED 或说明
AGENTS.md                                      # 一行 Active task / slice 事实（可选）
supply-chain/lean-package-files.v1.json        # 改 ProofForgeV2 后 refresh
```

禁止：无关 target IR 大重构、T9e、crypto、formal TASK。

### 验证

```bash
# 聚焦（按你实际 suite 名调整）
lake build ProofForgeV2
lake env lean --run Tests/...   # 或 lake build 对应 shard + 跑相关测试
just test-fast
just dev-check                  # 若改产品 + SBOM
just sbom-package-files-refresh # 若动了 ProofForgeV2/**
just ci                         # 合并前；Goal 预算紧时可先 dev-check + 相关 shard，完成前应尽量 ci
git diff --check
```

### 与 workflow 配合

1. `BASE=$(git rev-parse HEAD)`，保持实现过程 **不 commit** 直到 review 绿（或使用 engineering-slice）。  
2. 实现 + 聚焦测试绿后，跑：

```text
workflow: proof-forge-one-slice
args:
  slice: "N-A2"
  base_commit: "<BASE>"
  task_prompt: "Normalize multi-arm match sharing same outer constructor: refine safely; fail-closed on unsafe; tests + matrix update"
  changed_files: [ ...exact list... ]
```

3. 修 P0/P1 → 再验证。  
4. 一个 local commit，例如：

   `feat(normalize): refine multi-arm same-outer-constructor match (N-A2)`

5. backlog N-A2 → `done`；matrix 更新。  
6. **不 push**。Goal 完成声明附 SHA + 命令结果。

### engineering-slice JSON（可选整包）

```json
{
  "slice_id": "N-A2",
  "milestone": "D2",
  "objective": "Close N-A2: allow Normalize to lower match arms that share the same outer constructor when refinement is safe (nested VariantPayload/subpatterns); keep unsafe cases fail-closed with stable diagnostics; add focused positive/negative tests; update engineering-backlog and coverage matrix. No formal TASK claims.",
  "dependencies": ["Wave2-S1-Normalize-base", "constructor-match-single-outer"],
  "allowed_paths": [
    "ProofForgeV2/Semantic/",
    "ProofForgeV2/Typed/",
    "Tests/",
    "docs/engineering-backlog.md",
    "docs/research/12-target-coverage-matrix.md",
    "AGENTS.md",
    "supply-chain/"
  ],
  "focused_checks": [
    "lake build ProofForgeV2",
    "just test-fast"
  ],
  "verification_commands": [
    "just docs-check",
    "just sbom-package-files-refresh",
    "just dev-check",
    "just ci",
    "git diff --check"
  ],
  "deletion_zero_patterns": [
    "planFromAlpha",
    "alphaResidualOf",
    "Core.Source"
  ],
  "shared_cutover": true,
  "commit_message": "feat(normalize): refine multi-arm same-outer-constructor match (N-A2)",
  "constraints": "Shared-core only. Serial with other Normalize slices. Never push. Never formal/release. Prefer minimal CFG change. If target Plan cannot lower yet, fail-closed with tests rather than inventing half-lowered IR."
}
```

`shared_cutover: true` 会强制 `just target-negative`——若本切片确不影响 target 边界，可改为 `false` 并在 preflight 说明。
