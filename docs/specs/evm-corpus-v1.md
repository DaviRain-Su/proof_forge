---
id: SPEC-EVM-CORPUS-001
title: EVM corpus case and observation schema v1
status: proposed
owner: quality
updated: 2026-08-03
normative: false
---

# EVM corpus case and observation schema v1

本规格冻结 closed、versioned 的

- `proof-forge.evm-corpus-case.v1`
- `proof-forge.evm-observation.v1`
- `proof-forge.evm-corpus-manifest.v1`

工程 schema foundation。它实现
[`docs/research/17-openzeppelin-ethereum-coverage-audit.md`](../research/17-openzeppelin-ethereum-coverage-audit.md)
§8 的可执行契约，由 `scripts/evm_corpus_v1.py` 做 pure structural validation + closed inventory join。

本文件 `normative: false` 仅因当前 docs 导航尚未从 `docs/index.md` 接达（本切片禁止改 index）；
schema 对 corpus harness 仍是 sole closed authority。后续导航接线任务不得改写本 schema 语义。

## 与 `proof-forge.evidence.v1` 的关系

| 载体 | 角色 |
|---|---|
| `proof-forge.evm-corpus-case.v1` | 输入 case：pins、actors、steps、class 合同、oracle/skip 策略 |
| `proof-forge.evm-observation.v1` | 单 leg / 单 step 的 observation 载体（shared + optional EVM raw） |
| `proof-forge.evidence.v1` | gate 运行 envelope（command/tools/artifacts/result） |

规则：

1. corpus case / observation **不是** evidence envelope，也 **不** 替代
   [`TRACE-EV-001`](../traceability/evidence-schema.md) 的 `proof-forge.evidence.v1`。
2. 正式 gate 若发布 EV，必须另 mint evidence；可将 corpus case/observation 列为
   `inputs[]` / retained artifacts，但 digest/identity 仍由 evidence schema 拥有。
3. 本 schema **不进入** 产品 Lean import graph、`ProofForgeV2/**`、materializer 或 CLI product
   path。校验器是 development/test harness only。
4. 禁止第二套宽松 JSON authority：解码使用与 evidence 同构的 restricted PF integer-only /
   ASCII-graphic-key JCS profile（见下），解析后必须 `canonical_bytes(value) == input_bytes`。

## JSON profile（restricted PF-JCS）

与 evidence v1 相同的受限 profile（**不是**完整 RFC 8785）：

- 输入无 BOM 的 UTF-8；canonical 文件无前后空白、无 trailing newline。
- object key：1–256 个 ASCII graphic（`0x21..0x7e`）；duplicate key 立即拒绝。
- number 仅安全整数 `[-(2^53-1), 2^53-1]`；拒绝 float / NaN / Infinity。
- string 无 NUL / surrogate；业务 Unicode 保持 UTF-8，不做静默 NFC 改写（path 另要求已是 NFC）。
- 最大 JSON 深度 64、最大 value node 100_000。
- object key 按 ASCII 字节序排序编码；array 保持 schema 规定顺序；无非必要空白。
- 所有结构 object `additionalProperties=false`（未知字段 fail closed）。

### 公共 primitive

| 名 | 规则 |
|---|---|
| `sha256` | 64 位小写 hex |
| `git-object-id` | 40 或 64 位小写 hex |
| `safe-id` | 1–256 ASCII；首尾字母或数字；中间仅 `A-Za-z0-9._:+-` |
| `case-id` | 同 safe-id，且至少含一个 `.`（dotted case identity） |
| `relative-path` | 非空、已是 NFC、POSIX 相对路径；禁止 absolute、`\`、空/`.`/`..` 组件、control、尾 `/` |
| `hex-bytes` | `0x` + 偶数字母小写 hex（可 `0x` 空）；用于 calldata/returndata/topics/log data 等 variable-width 字节串 |
| `storage-word32` | `0x` + **恰好** 64 位小写 hex（32 raw bytes）；**仅**用于 EVM `storageSlots[].slot` 与 `storageSlots[].value`（真实 EVM storage word；禁止短写/大写/奇数长度） |
| `address20` | `0x` + 40 小写 hex |
| `uint-decimal` | 无符号十进制整数字符串，无前导零（`0` 除外），值可超过 JSON safe int |

## 资源上限

| 资源 | 上限 | 计量 |
|---|---|---|
| case 原始 UTF-8 bytes | 64 KiB（65536） | 输入 byte 长度 |
| observation 原始 UTF-8 bytes | 256 KiB（262144） | 输入 byte 长度 |
| manifest 原始 UTF-8 bytes | 256 KiB（262144） | 输入 byte 长度 |
| `manifest.files` | 256 | 数组长度 |
| `actors` | 8 | 数组长度 |
| `steps` | 32 | 数组长度 |
| `steps[].expectedLogs` / observation `evm.logs` | 32 / step | 数组长度 |
| 每个 log 的 `topics` | 4 | 数组长度 |
| `diagnosticPatterns` | 8 | 数组长度 |
| 每个 diagnostic pattern | 128 UTF-8 bytes | `len(utf-8)` |
| bounded reason / skip reason | 128 UTF-8 bytes | `len(utf-8)` |

越界 → 稳定 `PF-CORPUS-LIMIT`。

## Case classes

每个 case 必须且只能声明一种 `class`：

| class | 允许的 credit / 结论 | 强制 legs / 字段 |
|---|---|---|
| `primitive` | 仅 PF shared semantics；**禁止** family / ABI / standard credit；`ozCommit=null` | legs 恰为 `reference` + `pf-anvil`；`compare="shared"`；`sameCallBytes=false` |
| `adapter` | **永不**产生 family / ABI / standard credit | 必填 `adapter`；legs 非空；`claims` 全 false |
| `oz-behavior` | 可标 family behavior；**禁止** ABI / standard credit | 必填 `sharedProjection`；legs 恰含 `reference`+`pf-anvil`+`oz-anvil`；`compare="shared-projection"` |
| `abi` | 可标 ABI/standard 意图字段，但本 sprint 无正向业务 case | legs 恰含三 leg；`compare="full-evm"`；`sameCallBytes=true` |
| `blocked` | 精确 fail-closed；**不是** pass | 必填 `blocked`（typed phase/target/bounded reason）；禁止把 unrelated early failure 当满足 |
| `oos` | 已接受产品边界 | 必填 `oos` 且 `decisionStatus="accepted"` + project-relative decision ref |

Schema 识别全部六类。本 sprint **不** 提供产品 corpus 正向 `oz-behavior` / `abi` / `oos` 业务 case；
`testdata/evm-corpus/v1/schema-tests/**` 仅含 schema 形状自检，不得计为 OZ/family/ABI 通过。

## Root: `proof-forge.evm-corpus-case.v1`

根 object **恰好**含下列字段（无可选根字段；class 特有载荷嵌在固定键内，未用 class 时对应键为 `null`）：

```text
{
  "schema": "proof-forge.evm-corpus-case.v1",
  "id": case-id,
  "class": "primitive" | "adapter" | "oz-behavior" | "abi" | "blocked" | "oos",
  "pins": Pins,
  "actors": [Actor, ...],          // 1..8, unique id ascending
  "initialLogicalState": object,   // JSON object; closed only by size/profile
  "steps": [Step, ...],            // 1..32; index == position
  "oracle": Oracle,
  "skipPolicy": SkipPolicy,
  "claims": Claims,
  "adapter": AdapterBody | null,
  "sharedProjection": ProjectionBody | null,
  "blocked": BlockedBody | null,
  "oos": OosBody | null
}
```

### `pins`

```text
{
  "pfCommit": git-object-id,
  "sourcePath": relative-path,
  "sourceHash": sha256,
  "semanticHash": sha256,
  "ozCommit": git-object-id | null,
  "target": "evm",
  "profile": safe-id,
  "toolLockDigest": sha256,
  "solcVersion": safe-id,
  "anvilVersion": safe-id,
  "hardfork": safe-id,
  "runner": "lean-focused" | "product-cli" | "anvil-matrix" | "schema-only"
}
```

- `primitive` / `blocked`（无 OZ leg）要求 `ozCommit=null`。
- `oz-behavior` / `abi` 要求 `ozCommit` 为 git-object-id。
- `adapter` / `oos` 允许 `ozCommit` 为 id 或 `null`。
- 路径必须 project-relative、无 traversal（见 primitive）。
- `toolLockDigest` 必须是 SPEC-TOOL-001 **canonical `ToolLockV4Digest`**
  （`SHA-256("proof-forge.toolchains.v4" || 0x00 || PF-JCS(validated ToolLockV4))`），
  **不是** retained lock file 的 raw SHA-256（`toolchainLockSha256` / raw lock bytes digest）。
  业务 case 若 pin Darwin digest，则不得在 Linux/foreign ToolLock 主机上静默冒充通过。
- `pfCommit` 是 **compiler / product baseline** git object id：标识编写/验证该 case 时所依据的
  产品树与工具语义基线。它 **不要求** 该 commit 自包含后来才加入的 case 文件本身
  （否则 case 无法在引入自身的 commit 上自引用 pin）。case 源码与语义的 exact 身份由
  `sourcePath` + `sourceHash` + `semanticHash` 绑定；EVMOZ-006 最终 manifest 再以
  path + digest 闭包登记。未来 manifest 若覆盖 commit pin，仍不得放宽 source/semantic
  或 ToolLockV4Digest 身份。

### `actors[]`

```text
{ "id": safe-id, "role": "eoa" | "contract" | "system" }
```

- 长度 1..8；`id` 唯一；数组按 `id` ASCII 升序（set-like）。

### `steps[]`

```text
{
  "index": 0..31,                 // 必须等于数组下标
  "action": "call" | "deploy" | "view" | "assert-blocked",
  "actor": safe-id,               // 必须引用 actors[].id
  "entry": safe-id | null,        // call/view 必填；deploy/assert-blocked 可为 null
  "args": array,                  // profile-limited JSON array
  "valueWei": uint-decimal,
  "expectedSharedStatus": "success" | "revert" | "trap" | "blocked",
  "expectedLogs": [LogExpectation, ...]   // 0..32
}
```

`LogExpectation`：

```text
{
  "address": address20 | null,    // null = any / logical-only
  "topics": [hex-bytes, ...],     // 0..4
  "data": hex-bytes | null
}
```

`blocked` class 的每个 step 的 `action` 必须为 `assert-blocked`，
`expectedSharedStatus` 必须为 `blocked`。其他 class 禁止 `assert-blocked` / `blocked` status。

### `oracle`

```text
{
  "legs": ["reference" | "pf-anvil" | "oz-anvil", ...],  // unique, declaration order retained
  "compare": "shared" | "shared-projection" | "full-evm" | "none",
  "sameCallBytes": bool
}
```

class 约束见上表。`legs` 不得含重复。`oz-anvil` 仅当 class ∈ {adapter, oz-behavior, abi} 且
`ozCommit!=null`（adapter 可用不同 driver，但仍需显式 leg 列表）。

### `skipPolicy`

```text
{
  "optionalLegs": [leg, ...],          // subset of oracle.legs; unique ascending
  "requiredTools": [safe-id, ...],     // unique ascending; may be empty for schema-only
  "missingOptionalTool": "skip-leg",   // sole closed value
  "requiredToolFailure": "fail"        // sole closed value — 禁止 skip
}
```

代数：

- **skip ≠ pass**。optional leg 在工具缺席时可 `skip`；required tool 失败必须 `fail`。
- `requiredToolFailure` **只允许** `"fail"`。写成 `"skip"` / `"pass"` 等一律 schema 拒绝。
- `missingOptionalTool` **只允许** `"skip-leg"`。
- `optionalLegs` 必须是 `oracle.legs` 的子集；required legs（差集）失败不得记 skip。

### `claims`

```text
{
  "familyCredit": bool,
  "abiCredit": bool,
  "standardCredit": bool
}
```

强制：

- `primitive` / `adapter` / `blocked` / `oos`：三者全 `false`。
- `oz-behavior`：`abiCredit=false` 且 `standardCredit=false`；`familyCredit` 可为 true/false。
- `abi`：`familyCredit=false`（ABI case 不自动给 family behavior）；`abiCredit`/`standardCredit` 可为 true。

### `adapter` body（class=`adapter` 非 null；否则必须 null）

```text
{
  "pfDriver": safe-id,
  "ozDriver": safe-id,
  "retainedFields": [safe-id, ...],   // unique ascending, nonempty
  "discardedFields": [safe-id, ...]   // unique ascending; disjoint from retained
}
```

adapter **不** 产生 family/ABI/standard credit（由 `claims` 强制）。允许不同 call bytes。

### `sharedProjection` body（class=`oz-behavior` 非 null；否则必须 null）

```text
{
  "schemaId": safe-id,
  "retainedFields": [safe-id, ...],   // unique ascending
  "discardedFields": [safe-id, ...]
}
```

`retainedFields` **必须包含**下列最小场景字段（缺一拒绝）：

`authSubject`, `stateDelta`, `returnValue`, `revertStatus`, `rollback`

禁止把上述关键字段放进 `discardedFields`。

### `blocked` body（class=`blocked` 非 null；否则必须 null）

```text
{
  "phase": "capability" | "plan" | "lower" | "type" | "normalize",
  "target": "evm",
  "reason": string,                   // 1..128 UTF-8 bytes, exact match surface
  "reasonKind": "planInvariant" | "capabilityMissing" | "unsupportedShape",
  "diagnosticPatterns": [string, ...], // 0..8; each 1..128 UTF-8 bytes
  "forbiddenEarlyFailure": [          // must be present; exact fixed contract order
    "toolchain-mismatch",
    "parse-error",
    "unrelated-type-error",
    "missing-tool"
  ]
}
```

- `forbiddenEarlyFailure` 必须 **恰好** 等于上表四元组的 **固定合同序**（exact tuple order，
  **不是** ASCII 升序、也不是 set 重排）。任何缺项、多项、置换或拼写变化一律
  `PF-CORPUS-INVARIANT`。该合同防止把 toolchain-mismatch / parse-error /
  unrelated-type-error / missing-tool 等 early failure 记为 blocked pass。
- `runner` 建议 `lean-focused`；schema 不强制，但 product CLI closed diagnostic 未冻结前不得把
  blocked case 记为 runtime pass。

### `oos` body（class=`oos` 非 null；否则必须 null）

```text
{
  "decisionId": safe-id,
  "decisionStatus": "accepted",       // sole accepted value
  "decisionRef": relative-path        // project-relative docs/decision path
}
```

研究建议 / draft 决策不得使用 `decisionStatus="accepted"` 以外的值（其他值直接拒绝）。
schema 形状自检 fixture（如 `case-oos-shape.json`）仅证明结构可解码；输出
`claims-not-verified`，**不**构成产品 OOS  closure 或 accepted-decision 业务证据。

## Root: `proof-forge.evm-observation.v1`

```text
{
  "schema": "proof-forge.evm-observation.v1",
  "caseId": case-id,
  "leg": "reference" | "pf-anvil" | "oz-anvil",
  "stepIndex": 0..31,
  "verdict": "pass" | "fail" | "skip" | "tool-blocked" | "proposal",
  "skipReason": string | null,
  "shared": SharedObservation,
  "evm": EvmObservation | null
}
```

### Verdict 代数（不得混同）

| verdict | 含义 | `skipReason` |
|---|---|---|
| `pass` | 断言成立 | 必须 `null` |
| `fail` | 断言失败 / required tool 失败 | 必须 `null` |
| `skip` | **仅** optional leg 因缺 optional tool 跳过；**不是** pass | 非空 ≤128 bytes |
| `tool-blocked` | Tool Lock / hardfork / runner pin 阻断；**不是** skip 也不是 pass | 非空 ≤128 bytes |
| `proposal` | schema/设计占位，不得记工程 pass | 非空 ≤128 bytes |

禁止：

- `verdict="pass"` 且带 `skipReason`
- `verdict="skip"` 把 required leg / required tool 失败写成 skip（harness 责任；schema 通过
  case `skipPolicy.requiredToolFailure="fail"` 关闭 skip-as-pass 通道）
- 用 `tool-blocked` 冒充 `blocked` class 的 expected blocker

### `shared`（所有 leg 必填）

```text
{
  "status": "success" | "revert" | "trap" | "blocked",
  "returnValue": JSON | null,
  "logicalState": object,
  "effects": array,              // ordered semantic effects; profile-limited
  "rollbackEqual": bool          // failure 前后 logical state/effects 是否回滚相等
}
```

gas **默认不在** shared 面；未来 gas claim 必须升版本观察面。

### `evm`（EVM-only raw）

- `leg="reference"`：**必须** `evm=null`。禁止 synthetic EVM 字段。
- `leg="pf-anvil"` 或 `"oz-anvil"`：**必须** 为 object：

```text
{
  "calldata": hex-bytes,
  "returndata": hex-bytes,
  "storageSlots": [
    { "slot": storage-word32, "value": storage-word32 },
    ...
  ],
  "logs": [ { "address": address20, "topics": [hex-bytes,..≤4], "data": hex-bytes }, ... ], // ≤32
  "revertData": hex-bytes | null,
  "externalCalls": [
    {
      "target": address20,
      "valueWei": uint-decimal,
      "calldata": hex-bytes,
      "returndata": hex-bytes
    },
    ...
  ],
  "balances": [ { "id": safe-id, "wei": uint-decimal }, ... ]  // unique id ascending
}
```

`storageSlots` 规则（真实 EVM storage word，非 variable-width blob）：

- `slot` 与 `value` 均为 `storage-word32`：`0x` + 恰好 64 位 **小写** hex（32 bytes）；
  拒绝 `0x1`、奇数长度、大写、缺 `0x`、超/短于 32 bytes。
- `slot` 在数组内唯一。
- 数组按 `slot` 的 **exact wire 字符串** ASCII/UTF-8 字节升序排序（对固定 64-hex 左零填充
  形式，该序等于 unsigned big-endian 数值序）。乱序 → `PF-CORPUS-INVARIANT`。

## Root: `proof-forge.evm-corpus-manifest.v1`

Sole canonical path：`testdata/evm-corpus/v1/manifest.json`。

根 object **恰好**含：

```text
{
  "schema": "proof-forge.evm-corpus-manifest.v1",
  "files": [
    {
      "path": relative-path,   // project-relative POSIX; path-ascending unique
      "role": "case" | "source" | "schema-fixture" | "runner",
      "size": non-negative safe int,
      "sha256": sha256
    },
    ...
  ]                              // 1..256
}
```

### 闭合范围（exact inventory）

1. `testdata/evm-corpus/v1/**` 下全部 **regular** authority 文件，**除 manifest 自身**
   （禁止自引用；`path == testdata/evm-corpus/v1/manifest.json` → `PF-CORPUS-INVARIANT`）。
2. 全部 business case 的 `pins.sourcePath`（含外部 `Examples/Counter|Accumulator|Token.lean`
   与 `testdata/valid/ArithOps.lean`）。
3. Sole full-runtime harness（role=`runner`，exact 9 路径）：
   - `scripts/evm_corpus_v1.py`
   - `scripts/evm_corpus_reference.sh`
   - `scripts/evm_corpus_runtime.sh`
   - `scripts/evm_corpus_obs_write.py`
   - `scripts/evm_anvil_differential.sh`
   - `scripts/smoke_evm.sh`
   - `scripts/evm_token_anvil_smoke.sh`
   - `Tests/Materialization/EvmCorpusPrimitiveV1.lean`
   - `Tests/Materialization/EvmCorpusBlockedV1.lean`

当前 closed inventory 合计 **46** 条目（corpus authority 除 manifest 自身 + case
`sourcePath` + 上表 9 runners）。

### 角色与 join

| role | 用途 |
|---|---|
| `case` | `testdata/evm-corpus/v1/cases/<id>.json`；`id` 必须等于 filename stem |
| `source` | program / external source 文本；每个 case `sourcePath` 必须 listed 且 role=source；`sourcePath` 仅 `.lean` 且位于 closed roots `Examples/`、`testdata/valid/`、`testdata/evm-corpus/v1/programs/` |
| `schema-fixture` | `schema-tests/**` 形状自检 |
| `runner` | 上表 exact 9 harness 路径 |

未知 role / duplicate path / 非升序 path → fail closed。

**Allowlist-before-read**：validator 先从 corpus walk + 固定 `cases/` authority 解码出
`required_sources` 与 `REQUIRED_RUNNER_PATHS`，构造 exact allowlist；`listed` 必须恰等于
该集合（extra 含 `.env` 等恶意路径在读取前 `PF-CORPUS-INVARIANT`）。仅 allowlist 通过后
才对 listed 路径做 stable observation。

corpus 树与 listed 路径 **禁止** symlink（含 dirnames 中的 symlink 目录与 repo→leaf 任意
component）、hardlink（`nlink != 1`）、非 regular。stable read 使用
`O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK`（平台可用时）+ fstat/read/fstat 比较
`(ino,dev,mode,size,nlink,mtime_ns)`，要求 `size == len(bytes)` 与 sha256 exact。
这是 engineering stable observation，**不**声称 race-free/hermetic。

**Manifest 不是 formal evidence**，也不替代 `proof-forge.evidence.v1` / OutputSet。

## 校验器与 fixtures

- 实现：`scripts/evm_corpus_v1.py`（`/usr/bin/python3 -I -S`，无第三方包）。
- 命令：
  - `validate-case PATH`
  - `validate-observation PATH`
  - `validate-manifest PATH`（sole path = `testdata/evm-corpus/v1/manifest.json`）
  - `list-runnable-cases CASES_DIR`（exact 4 primitive + 1 adapter pin join）
  - `self-test`（内建 + `schema-tests/**` + manifest positive/negatives）
- just 入口（EVMOZ-006）：
  - `just evm-corpus-schema`：self-test + validate-manifest + 全部 business cases + runnable
  - `just evm-corpus-reference`：build 后 safe-clean OBS + Reference；exact 23 reference obs
  - `just evm-corpus-static`：schema + reference 聚合（接 `dev-check` / `ci-lean-product`）
  - `just evm-corpus-runtime`：手动 toolful Cancun full harness（**不**进 ordinary CI）
- 成功：stdout `corpus-schema-validated ...` / `corpus-manifest-validated ...` 且 exit 0。
- 失败：stderr `PF-CORPUS-...: ...` 且 exit 1。
- 输入必须已是 canonical PF-JCS bytes；validator 不做 publish canonicalize。

### 已实现工程边界（EVMOZ-002..006）

| 层 | 状态 |
|---|---|
| case/observation schema + schema-tests | 已实现 |
| business cases：4 primitive + 1 Token adapter + 1 Ownable blocked | 已实现 |
| closed manifest inventory | 已实现（EVMOZ-006） |
| Reference leg（23 obs）+ pin join | 已实现 |
| Ownable blocked Lean suite（Loader/Normalize/Reference + planInvariant） | 已实现并注册 |
| PF-Anvil Cancun full runtime harness | 手动 `evm-corpus-runtime`；Token 可 skip，不得 pass 冒充 |
| OZ leg / family·ABI·standard credit | **未**实现；Exact 0 / Partial 0 / Blocked 20 不变 |

### 错误码

| code | 用途 |
|---|---|
| `PF-CORPUS-JSON` | 非法 UTF-8/JSON/BOM |
| `PF-CORPUS-DUPLICATE-KEY` | duplicate object key |
| `PF-CORPUS-NUMBER` | float / 非有限 / 超 safe int |
| `PF-CORPUS-KEY` | 非 ASCII-graphic / 超长 key |
| `PF-CORPUS-SCHEMA` | 缺字段 / 未知字段 / 类型 / enum |
| `PF-CORPUS-INVARIANT` | class-leg / claims / projection / skip 代数 / 排序唯一性 / manifest inventory |
| `PF-CORPUS-PATH` | 路径 traversal / 非 NFC / 非相对 / symlink / hardlink / 非 regular |
| `PF-CORPUS-LIMIT` | 资源上限 |
| `PF-CORPUS-CANONICAL` | 输入 bytes ≠ canonical re-encode |

## 非声明

- schema-tests / manifest / Reference 通过 **不** 表示 OZ 兼容、Reference↔Anvil formal
  closure、Cancun=OZ hardfork 对齐，或 maturity / formal TASK 提升。
- 不绑定 `proof-forge.output.v1` product publisher；manifest **不是** formal evidence。
- CosmWasm / 其他 target 不在本 schema 范围。
- Ownable F01 保持 **Blocked**；无 EVM `context.caller` Plan/ABI lowering。
