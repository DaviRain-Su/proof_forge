---
id: SPEC-CLI-001
title: CLI 契约
status: proposed
owner: cli
updated: 2026-08-04
normative: true
---

# CLI 契约

> **当前实现状态（2026-08-04）**：产品 `check` / `build` 为进程内 **单次**
> `IO.FS.readFile` → `Loader.selectProgramV1ProductWithTheoremInventory` →
> `compileProgramProductV1` → **`certifyInlineProofV1`**（held raw source；非 sandbox）→
> 仅在 cert 成功或显式 `noProof` 后 → target resolve / materialize。不经过 B11/B12
> supervisor；不输出 supervised `receipts`。`--proof-bundle` / `--proof-bundle-digest`
> 已从产品 CLI **删除**（unknown option / exit 2）；`ProofBundleV1` /
> `ProofReferenceJoinV1` 仅 library/historical/formal-oriented，**不是** check/build
> alternate surface 或 fallback。六类 `--resource-limit` 中 `wall-ms` 与 build
> `artifact-output.published-bytes` 已进程内强制。以下 receipt/containment 条款是
> proposed 目标。
>
> **Inline proof（ADR-0026 sole product gate）**：ProgramV1/`semanticHash` 不含 theorem
> body；固定 axiom `Classical.choice`/`Quot.sound`/`propext`；当前仅
> `InvariantTheoremV1`/`StateConformsV1`；**不** 声称 formal TST/release。check 成功输出
> `proofStatus` / theorem count / certification digest；build 只做门禁、成功输出 **不**
> 携带 proof 字段。raw-source 生成证书 / product-positive certified 路径仍可在并行收尾，
> **不得** 仅凭 wiring 宣称 feature 完成。

可执行文件固定 `proof-forge-next`。所有命令 non-interactive；JSON 输出 stdout，日志和
human diagnostics 到 stderr。

## Commands

```text
proof-forge-next check <source> --module <lean-module-name> [--language-version <semver>]
  [--program <qualified>] [--resource-limit <stage>.<field>=<n>]...
  [--format human|json]
proof-forge-next build <source> --module <lean-module-name> --target <id> [--profile <id>]
  [--language-version <semver>] [--minimum-evidence <grade>]
  [--program <qualified>] [--resource-limit <stage>.<field>=<n>]...
  --output <dir> [--force] [--format human|json]
proof-forge-next inspect <output-dir> [--format human|json]
proof-forge-next list-targets [--all] [--format human|json]
proof-forge-next prove <output-dir> --inputs <private-input-file>
  --proof-output <dir> [--format human|json]
proof-forge-next verify <output-dir> --proof <file> --public-inputs <file>
  [--format human|json]
proof-forge-next deploy <output-dir> --network <network-profile-id>
  --signer-fd <n> [--format human|json]
```

**已删除（产品面）**：`--proof-bundle`、`--proof-bundle-digest`。任一出现为 unknown
option / usage error / exit 2。

Phase 1 required：check/build/inspect/list-targets、Noir prove/verify；deploy 接口可存在但
仅对通过 target dossier network gate 的 profile 开放，其他返回 stable unavailable。

## Selection Rules

`check/build` 的 `--module` 必填。其值由锁定 Lean identifier parser exact-consume，必须是 pure
`.str` chain；不得从 source path 推导或按 `.` split。`programIdentity` 为 module raw components、
active namespace raw components 与 declaration raw components 的精确串接。`--program` 使用同一
parser 与 raw-array equality；文件路径和 rendered dotted string 不参与 source identity/hash。

一个候选自动选择；零候选 `PF-EXPORT-003`；多个候选必须 exact `--program`，否则
`PF-EXPORT-002`。target/profile exact lookup；省略 profile 使用 registry 唯一 default。
build 禁止 `--network`；deploy 不接受 source/target/profile，而是信任并重验 OutputSet。
`--language-version` 只接受当前 compiler 内已登记 parser 的 **exact SemVer**（ADR-0022 D1 /
`SPEC-VER-001`）。当前 DSL major 为 **`1`**，其 sole enabled default 为 **`1.0.0`**：省略
`--language-version` 与显式 `1.0.0` **解析为同一** parser descriptor。拒绝 ranges、`latest`、
negotiation、unknown exact、disabled/revoked 与 non-unique current-major default（稳定码
`PF-LANGUAGE-VERSION-UNKNOWN` / `PF-LANGUAGE-VERSION-DISABLED` / `PF-LANGUAGE-DEFAULT`）。
**`languageVersion` 永不进入** ProgramV1 `programIdentity` / `sourceHashV1` / `NodeId` preimage。
`--minimum-evidence` 只接受
`specified | artifact_validated | local_runtime | network_or_proof_validated`；有效值是
`max(profile.minimumEvidence, cliRequested)`，CLI 不得降低 profile 下限。

`--resource-limit` 是 repeatable、逐 stage/field 的 lower-only override。CLI 名称固定映射到
SPEC-COMMON-001，不创建第二套 resource profile：

| CLI stage | `ResourceStage` | `check` | `build` |
|---|---|---|---|
| `frontend` | `frontend` | allowed | allowed |
| `compiler-core` | `compilerCore` | allowed | allowed |
| `external-tool` | `externalTool` | rejected | allowed |
| `artifact-output` | `artifactOutput` | rejected | allowed |

field 只允许 `wall-ms`、`memory-bytes`、`processes`、`protocol-bytes`、`stderr-bytes`、
`published-bytes`，分别一一映射 `ResourceProfileV1` 的六个 limit 字段。值必须是无符号十进制
正整数；同一 `(stage,field)` 重复、unknown stage/field、`0`、负数、指数、overflow、该 hard
maximum 为 `0`，或值大于该 stage/field hard maximum，均在 spawn/source open/output staging 前
以 usage error/exit 2 拒绝。不存在 clamp：合法 override 就是 effective limit，省略的字段恰为
SPEC-COMMON-001 hard maximum。不同 stage 的 maximum 互不比较，因此例如 tool wall override
不会被 frontend wall maximum 误拒绝。

selection 后未执行的 target-specific external tool 仍可带合法 override，但 receipt 必须将该 stage
记录为 `not-executed`，不能伪造 observed peak；`check` 因命令面明确没有 tool/output stage，直接
拒绝对应 override。exact limit 接受，首次超过以对应 `PF-RESOURCE-*`、exit 6 终止并保持旧输出；
receipt 记录全部 effective limits 与 override source。target execution gas/compute/proof limits 属于
target semantics/Plan，不得通过这些 compiler-operation flags 改写。

## Proof certification（sole product gate：inline same-file）

产品 `check` / `build` **唯一** proof 路径是 ADR-0026 inline same-file certification。
**不存在** 产品 CLI alternate / fallback 到 external `ProofBundleV1`。

### 固定执行顺序

```text
single IO.FS.readFile (project-root-relative source)
  → selectProgramV1ProductWithTheoremInventory (raw held in memory)
  → CheckV1 / normalizeProgramLocatedV1 / compileProgramProductV1
  → certifyInlineProofV1 (same held raw source; in-process; not a sandbox)
       · noProof        → ProductProofStatusV1.notRequired (continue)
       · certified      → private CertifiedInlineProofV1 only (continue)
       · failed         → PF-SRC-INVALID / exit 3; zero Plan / zero staging
  → TargetRegistry resolve / capability / materialize / finalize / publish
```

1. theorem inventory 与 program `proof` / invariant exact bijection（inventory untrusted，
   由 program items 重算对照）；
2. Environment 审计 root theorem kind、kernel defeq 到 `InvariantTheoremV1` / 生成 Prop
   alias、dependency 闭包与固定 trust policy（仅 `Classical.choice` / `Quot.sound` /
   `propext`）；
3. **禁止** 用户 `.olean`、ambient lake、`LEAN_PATH` 或任何 external bundle 作 theorem
   authority；
4. Adjacent theorem body **不** 进入 ProgramV1 wire/`sourceHash`；**永不** 进入
   `semanticHash`；
5. 当前命题仅全体 `StateConformsV1` 上 `evalInvariantV1 = .returnedTrue`；不声称
   reachability / init-step safety / target refinement / formal `TST-PROOF-001`；
6. nonempty invariant 的 **target materializer** 仍可 fail closed（与 proof gate 正交）。

### check / build 输出差异

| 命令 | proof 观察面 |
|---|---|
| `check` 成功 | human/JSON 输出 `proofStatus`（`not-required` \| `certified`）、`proofTheoremCount`、`proofCertificationDigest`（`not-required` 时 none/null） |
| `build` 成功 | **仅门禁**：proof 失败则不 materialize；成功输出 **不** 携带 proof 字段（artifact identity 仍不含 certification digest） |
| 任一失败 | 零 destination artifact 变更；proof 失败优先于 unknown target（cert 在 registry resolve 前） |

### Library-only：ProofBundleV1 / ProofReferenceJoinV1（superseded product surface）

`ProofBundleV1`、`ProofReferenceJoinV1`、`openProofBundleV1` 与历史 structural bundle join
**保留为 library / formal-oriented / historical** 模块与测试资产。它们：

- **不是** 产品 `check`/`build` 入口；
- **不得** 被 CLI 作为 silent fallback 调用；
- 产品 argv **不得** 再接受 `--proof-bundle` / `--proof-bundle-digest`（unknown option）。

Formal `TST-PROOF-001`（immutable bundle + olean closure）仍独立 pending，不由 inline
engineering gate 代签。Noir `prove --inputs` 的 ZK proof 与本 certification 完全不同。

## JSON Results

当前已实现的成功 object 为 `schema`, `command`, `status:"ok"`, `result`；失败 object 为同
schema、`status:"error"`, `diagnostics:[...]`。不混入日志；输入/输出皆 UTF-8，JSON duplicate
key 拒绝。human output 不作为稳定 API。当前 in-process `check`/`build` **不**输出
`receipts`，也不得伪造 `contained` assurance。

若后续恢复 supervised 产品路径，success/failure object 应另含与 `diagnostics` 并列的顶层
`receipts`，且 assurance class 必须可区分、不得 silent 升格。

### 规划中的 supervised public `receipts`（ADR-0022 D3）

该字段尚未实现。在未来 **supervised** `check`/`build` 路径上，JSON stdout object 应在
**success 与 failure** 均携带顶层 **`receipts`** 字段。`receipts` 是 supervisor/controller 结果的
**bounded public-safe projection 与 digest**（hard/effective profile id/digest、observed
peak/elapsed 的可公开摘要、controller event class、cleanup result 等），**不是**：

- raw 或 full internal receipt bytes；
- stream tails、host absolute paths、secrets 或 unredacted stderr；
- `diagnostics[]` 的成员或替代物；
- OutputSet artifact 或 artifact path。

完整 public receipt projection 的字段 schema 仍可由后续实现切片钉死；本规格只冻结 **顶层
字段存在性、success/failure 必现、public-safe / 非 diagnostic / 非 artifact** 边界。
未 supervised 路径若发出 observation 投影，assurance class 必须可区分
（`darwin-development-observed` 永不等于 `contained` / formal evidence；Linux `contained` 仅在
controller-bound + controller-event attribution 下成立，禁止 silent fallback；ADR-0022 D2）。
human stderr 文本 **不是** `receipts` 的稳定替代 API。

## Exit Codes

| Code | 类别 |
|---|---|
| 0 | success |
| 2 | CLI usage/config |
| 3 | source/type/effect/semantic |
| 4 | target/profile/requirement resolution |
| 5 | plan/lower invariant |
| 6 | toolchain/artifact/output |
| 7 | deploy/prove/verify/runtime |
| 70 | internal compiler error |

多个 diagnostics 取最高优先级：70 > 7 > 6 > 5 > 4 > 3 > 2。

### B8b product diagnostic exit（engineering）

`check` / `build` 产品路径经进程内 `IO.FS.readFile` →
`Loader.selectProgramV1Product` → located Normalize → product Compiler；不经过 B10 worker 或
B11/B12 supervisor。Loader 与后续 compiler 失败在 stderr 一次打印全部
`DiagnosticBundleV1.renderHuman` 行。exit 为 `DiagnosticBundleV1.selectExitCode`：仅
`severity=error`；`PF-DIAG-LIMIT` 与 warning/note 中立；`PF-INTERNAL` → 70；phase
deploy/verify → 7；emit/tool → 6；plan/lower → 5；resolve → 4；
source/type/effect/semantic → 3。CLI usage/config（缺 `--module`/未知选项/未知 `--target`/非法
argv）**exit 2**（`failUsage` plain message），**不是** diagnostic，且不发明
`PF-CLI-USAGE`。source 16 MiB gate 由 Loader 在文件已读入后产生 `PF-SRC-INVALID`；host
source-open I/O fault、Emit/Toolchain 失败仍未全部迁入 bundle。

`check` / `build` 已接线 static `LanguageParserDescriptorV1`：省略与显式 `1.0.0` 解析为同一
descriptor；range、`latest`、malformed 与 unknown exact 在 source read 前以
`PF-LANGUAGE-VERSION-UNKNOWN`/exit 3/零制品拒绝。当前产品不按 Darwin/非 Darwin 区分，也
不输出 supervised receipts。Full receipt envelope、controller resource enforcement 与 formal
`TASK-D1-07` 仍 pending。

## Secret、Inputs 与副作用

private witness 文件必须 mode 0600、regular file、非 symlink；prove 不复制到 artifact tree。
产品 proof certification 不接受 external bundle path 作为 CLI input；library-only
`ProofBundleV1` 若用于 formal-oriented 工具，不得混入 private witness、signer material 或
runtime input。signer 只从已打开 FD 读取，CLI/env/JSON 禁止 key。check/build/inspect/list
不访问网络；deploy 先验证 network chain identity、artifact/profile/hash，再请求明确确认策略
（CI 使用预批准 policy file，不使用 prompt）。

## 边界与验收

覆盖无/多 source、unknown flag（含 **已删除** 的 `--proof-bundle*`）、重复 flag、missing value、
`--`、Unicode path/name、多 program、unknown target/profile/network、build with network、
output exists/force、JSON broken pipe、TTY/non-TTY、private file permissions/symlink、bad signer FD、
inline proof fail-closed（false theorem / inventory bijection / audit）、check
`proofStatus`/`proofTheoremCount`/`proofCertificationDigest`、build 无 proof 字段且 proof 失败零
staging、deploy non-deployable、unknown/unsupported language version、malformed/lower-than-profile
minimum evidence、resource override duplicate/unknown stage-field/zero/equal/over/hard-max、
check-with-tool-stage、unused build stage receipt、manifest/closure/path mutation、ambient
`.olean` 不得充当 theorem authority、forbidden declaration/signature mismatch、signals、
concurrent invocation。关联 `FR-008/010/011/014`、`NFR-008`、`TST-CLI-001..004`、
`TST-PROOF-INLINE-E1`；help/version/list JSON golden，所有失败 exit code 和 schema 固定。
