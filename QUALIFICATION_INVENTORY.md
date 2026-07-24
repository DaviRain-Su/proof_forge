# TaskQualification 隔离清单

本清单记录 2026-07-25 recovery 工作树中的事实，只盘点
`scripts/*task_qualification*`。它不把历史资格声明改写成产品完成，也不授权删除、搬迁或继续扩张资格协议。

## 结论

- qualification 子系统共有 **84 个文件、58,429 行**。
- `ProofForgeV2/**`、`Tests/**`、CLI、Lake targets 和 hosted CI 对它的直接代码依赖均为 **0**。
- `just dev-check` 与 `just ci` 使用 development docs profile，在 task/freeze/evidence 检查前返回，不加载 qualification 代码。
- `just governance-check` 的 qualification 闭包只有 **3 个文件、10,968 行**：
  `task_qualification_objects.py`、`task_qualification_fixture_builder.py`、
  `task_qualification_verifier.py`。
- `just release-check` 除继承上述 governance 闭包外，不调用 ceremony、authority store、native custody/service 或其 self-test。
- 其余 **81 个文件、47,461 行**没有 ordinary product gate 的执行入口；它们是历史 release ceremony 实现、协议实现、自测、生成器或已被后续实现取代的 standalone foundation。

因此，TaskQualification 已经可以从产品开发语义中隔离；继续把它视为每个编译器任务的完成前置没有代码依赖依据。

## 可执行引用矩阵

| 调用面 | 实际 qualification 依赖 | 结论 |
|---|---|---|
| `proof-forge-next` / `ProofForgeV2/**` | 无 | 不是编译产品运行时 |
| Lean product tests / `Tests/**` | 无 | 不是产品测试依赖 |
| `just dev-check` | 无 | development docs profile 在治理检查前返回 |
| `just ci` / `.github/workflows/ci.yml` | 无 | 普通主机产品门禁不执行资格协议 |
| `just governance-check` | 3-file Python 闭包 | 只为历史 D0-10 文档/fixture 审计保留 |
| `just release-check` | 上述 governance 闭包 | 当前 recipe 没有 steady-state ceremony/service 入口 |
| 历史 specs、ledger、implementation log | 文本引用 | 记录历史，不构成可执行产品依赖 |

`docs_check.py --profile governance` 以 exact-path 方式加载
`task_qualification_objects.py`。`docs_check_self_test.py` 直接导入
`task_qualification_fixture_builder.py` 与 `task_qualification_objects.py`，builder 再导入
`task_qualification_verifier.py`。这是当前仓库 gate 的完整 qualification 代码闭包。

## 文件分层

行数按当前工作树文本的 `splitlines()` 统计。

| 分层 | 文件数 | 行数 | 内容 | 建议 |
|---|---:|---:|---|---|
| 历史 governance 闭包 | 3 | 10,968 | objects、fixture builder、pure verifier | 搬迁前保留；不得误称产品依赖 |
| Ceremony / protected Python | 5 | 7,214 | authority-store client、ceremony、closeout、completion、protected adapter | 整体迁入 release-only 工具目录 |
| Native protocol stack | 54 | 25,750 | 34 C、19 headers、1 generated table | 与 ceremony 一起迁移，不留在产品脚本平面 |
| Qualification self-tests | 20 | 13,610 | Python/native harness 与 RED matrix | 与所属工具一起迁移；不加入产品 CI |
| Standalone fixture foundation | 1 | 728 | `task_qualification_fixture_core.py` | 最强删除/归档候选；当前仅历史日志引用 |
| Unicode table generator | 1 | 159 | 生成 native Unicode table | 与 native stack 一起迁移 |
| **合计** | **84** | **58,429** |  |  |

### 历史 governance 闭包（当前必须保持可运行）

- `scripts/task_qualification_objects.py`
- `scripts/task_qualification_fixture_builder.py`
- `scripts/task_qualification_verifier.py`

这里的“必须”只表示 `just governance-check` 当前仍引用它们，不表示 PAE 产品或日常开发需要它们。

### Ceremony / protected Python（无仓库 gate 入口）

- `scripts/task_qualification_authority_store_v2.py`
- `scripts/task_qualification_ceremony.py`
- `scripts/task_qualification_closeout.py`
- `scripts/task_qualification_completion.py`
- `scripts/task_qualification_protected_adapter.py`

这些文件互相引用，并依赖上面的 3-file 闭包。部分代码还通过固定同目录路径读取自身、adapter、verifier 或 native probe，因此不应零散移动。

### Native protocol stack

54 个 native 文件覆盖以下 family：

- artifact payload、authority policy、authority-policy FD；
- authority-store service、durable state；
- custody capability/transition/seed custody；
- descriptor、wire、PF-JCS、Unicode；
- FD manifest、handoff、pre-exec payloads；
- isolation policy、seccomp、namespace、kernel transition、socket。

它们由同目录 Python self-test 编译或驱动；普通产品 build、Lean tests 和 CI 均不编译这些 C 文件。

### Self-test 集合

20 个 `task_qualification_*_self_test.py` 包括 protocol/native harness、authority store、protected adapter、artifact owner 和 RED matrix。它们没有 `justfile` 或 hosted CI 的直接 recipe；但 ceremony/closeout 内部引用其中少数模块，所以迁移时必须把整个 qualification 子系统作为一个闭包处理。

### 最强独立清理候选

`scripts/task_qualification_fixture_core.py` 是 standalone self-check：没有代码、gate 或 CI 引用，仓库中只有 `docs/06-implementation-log.md` 对其历史加入与当时运行结果的记录。删除它仍属破坏性动作，本轮不执行。

## 建议的后续动作

### Q1：目录隔离（推荐）

把全部 84 个文件作为一个闭包迁到：

```text
tools/release-qualification/
```

同时只做机械更新：

1. 修正 Python import、同目录 identity/read-bytes 路径和 C compile/include 路径；
2. 把 `docs_check.py` 的 exact-path loader 与 `docs_check_self_test.py` 的 fixture import 指向新目录；
3. 更新仍把 `scripts/...` 当作当前路径的规格、ledger 和实现日志链接；历史命令文字可以保留并标注 historical path；
4. 保证 `just governance-check` 结果不变；
5. 不把任何 qualification self-test 重新加入 `dev-check` 或 `ci`。

整组迁移优于留下 3 个文件、移动 81 个文件：后者会制造跨目录 import、重复 decoder 或兼容 shim，重新扩大维护面。

### Q2：删除决策（另行确认）

目录隔离后，再分别决定：

- 是否删除无引用的 standalone fixture foundation；
- 是否仍需要本地 D0-10 ceremony/native stack，还是只保留不可变历史产物与最小 consumer；
- 是否把历史 D0-10 consumer 固化为独立 archive checker，从活动 `scripts/` 完全移出。

任何删除都应先证明历史 receipt/ledger 的读取需求已有替代，并由用户单独确认。

## 本轮边界

本清单阶段只记录盘点并更新 `RECOVERY.md` 指针。**没有删除、移动、重命名或执行 qualification ceremony，也没有生成 formal evidence。**
