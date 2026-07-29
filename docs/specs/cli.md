---
id: SPEC-CLI-001
title: CLI 契约
status: proposed
owner: cli
updated: 2026-07-29
normative: true
---

# CLI 契约

可执行文件固定 `proof-forge-next`。所有命令 non-interactive；JSON 输出 stdout，日志和
human diagnostics 到 stderr。

## Commands

```text
proof-forge-next check <source> --module <lean-module-name> [--language-version <semver>]
  [--program <qualified>] [--resource-limit <stage>.<field>=<n>]...
  [--proof-bundle <dir> --proof-bundle-digest <sha256:64-lowercase-hex>]
  [--format human|json]
proof-forge-next build <source> --module <lean-module-name> --target <id> [--profile <id>]
  [--language-version <semver>] [--minimum-evidence <grade>]
  [--program <qualified>] [--resource-limit <stage>.<field>=<n>]...
  [--proof-bundle <dir> --proof-bundle-digest <sha256:64-lowercase-hex>]
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

## Proof bundle input

`--proof-bundle` 只用于 `check/build` 验证 source 中的 `proof ... using ...` certification reference；
它与 Noir `prove --inputs` 产生的 ZK proof 完全不同。`--proof-bundle` 与
`--proof-bundle-digest` 必须成对且各出现一次；digest 使用 SPEC-COMMON-001 的 exact lowercase
SHA-256 wire form。缺一、重复、空值或把这两个 flag 传给其他 command，均在访问 source/bundle
前作为 usage error、exit 2 拒绝。

source 没有 proof reference 时禁止提供 bundle pair；source 有至少一个 proof reference 时必须提供
恰好一个 pair，且 bundle manifest exports 必须与 source reference 的
`(invariantName,theoremQualifiedName)` 集合一一 exact 相等，不允许遗漏、额外 export、短名或
跨 bundle fallback。缺 bundle 或 theorem 使用 `PF-TYPE-002`/exit 3；source 无 reference 却提供
bundle 是 usage error/exit 2。

执行顺序固定为：frontend parse/decode → type/effect/bound/disclosure → canonical
`SemanticProgramV1` normalize/validate/serialize/hash → ProofBundleV1 safe load/closed expected-type
validation → target resolution/materialization。CLI 只能把当前 canonical program、其 semanticHash、
当前 sourceHash、validated semanticProvenanceDigest、source proof bindings、bundle dirfd 和 expected bundle digest 传给 SPEC-SEM-001
proof loader；不得把 source/import environment 或 ambient path 传入。bundle manifest sourceHash/
semanticHash/semanticProvenanceDigest、toolchain lock、ABI、
trusted base closure、trust policy、module closure、files 和 CLI digest 必须全部 exact match。

bundle path/schema/layout/digest/closure/trust/kernel-load failure、stale sourceHash/semanticHash/
semanticProvenanceDigest 或 forbidden
declaration 使用 `PF-ARTIFACT-INVALID`/exit 6；export name/ordinal 不存在使用
`PF-TYPE-002`/exit 3；theorem type 与
`InvariantTheoremV1 canonicalProgram ordinal` 不 definitionally equal 使用
`PF-TYPE-001`/exit 3。所有失败都不得进入 target Plan、不得创建/替换 output，也不得读取其他
`.olean` 或 retry/fallback。成功结果的 certification summary 固定包含 sourceHash、semanticHash、
semanticProvenanceDigest、
proofBundleDigest，以及按 invariant name 排序的 `(invariantName,invariantOrdinal,theoremName)`；
不得包含 theorem body、Environment、host path 或 private value，且该 summary 不参与
sourceHash/semanticHash/semanticProvenanceDigest。

## JSON Results

成功 object：`schema`, `command`, `status:"ok"`, `result`；在 **supervised** `check`/`build`
上另含顶层 **`receipts`**（ADR-0022 D3）。失败 object：同 schema、`status:"error"`、
`diagnostics:[...]`；supervised `check`/`build` 失败同样 **始终** 含顶层 **`receipts`**
（与 `diagnostics` 并列，不是其成员）。不混入日志。输入/输出皆 UTF-8，JSON duplicate key
拒绝。human output 不作为稳定 API。

未 supervised 的 development in-process 路径 **不得** 伪造 `contained` 级 receipt 语义，也
不得在字段清单上假装已有 controller-backed containment；若仍发出 development observation
投影，assurance class 必须可区分且不得 silent 升格。

### Supervised public `receipts`（ADR-0022 D3）

在 **supervised** `check`/`build` 路径上，JSON stdout object 在 **success 与 failure** 均携带
顶层 **`receipts`** 字段（见上字段清单）。`receipts` 是 supervisor/controller 结果的
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

### B8a engineering note（非 product cutover）

`ProofForgeV2/Core/DiagnosticBundleV1.lean` 提供 inert `DiagnosticBundleV1.selectExitCode`：
仅考虑 `severity=error`；`PF-DIAG-LIMIT` 与 warning/note 中立；`PF-INTERNAL` → 70；phase
deploy/verify → 7；emit/tool → 6；plan/lower → 5；resolve → 4；source/type/effect/semantic → 3。
**B8a 未接线** CLI/compiler 产品路径；alpha 单错误 `CompileError` exit 行为不变。**B8b** 才做
sole atomic product cutover；formal `TASK-D1-07` 仍 pending。

## Secret、Inputs 与副作用

private witness 文件必须 mode 0600、regular file、非 symlink；prove 不复制到 bundle。
ProofBundleV1 是只读 public certification input，不得放入 private witness、signer material 或
任意 runtime input；其 safe-open、closure、trust 与 resource 规则由 SPEC-SEM-001 唯一定义。
signer 只从已打开 FD 读取，CLI/env/JSON 禁止 key。check/build/inspect/list 不访问网络；
deploy 先验证 network chain identity、artifact/profile/hash，再请求明确确认策略（CI 使用
预批准 policy file，不使用 prompt）。

## 边界与验收

覆盖无/多 source、unknown flag、重复 flag、missing value、`--`、Unicode path/name、
多 program、unknown target/profile/network、build with network、output exists/force、JSON
broken pipe、TTY/non-TTY、private file permissions/symlink、bad signer FD、proof mismatch、
deploy non-deployable、unknown/unsupported language version、malformed/lower-than-profile minimum
evidence、resource override duplicate/unknown stage-field/zero/equal/over/hard-max、check-with-tool-
stage、unused build stage receipt、proof-bundle paired flags/unused/missing/stale digest、manifest/
closure/path mutation、ambient `.olean` poisoning、forbidden declaration/signature mismatch、signals、
concurrent invocation。关联
`FR-008/010/011/014`、`NFR-008`、
`TST-CLI-001..004`；help/version/list JSON golden，所有失败 exit code 和 schema 固定。
