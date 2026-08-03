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

工程 schema foundation。它实现
[`docs/research/17-openzeppelin-ethereum-coverage-audit.md`](../research/17-openzeppelin-ethereum-coverage-audit.md)
§8 的可执行契约，由 `scripts/evm_corpus_v1.py` 做 pure structural validation。

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

## 校验器与 fixtures

- 实现：`scripts/evm_corpus_v1.py`（`/usr/bin/python3 -I -S`，无第三方包）。
- 命令：
  - `validate-case PATH`
  - `validate-observation PATH`
  - `self-test`（内建 + `testdata/evm-corpus/v1/schema-tests/**`）
- 成功：stdout `corpus-schema-validated ...` 且 exit 0。
- 失败：stderr `PF-CORPUS-...: ...` 且 exit 1。
- 输入必须已是 canonical PF-JCS bytes；validator 不做 publish canonicalize。

### 错误码

| code | 用途 |
|---|---|
| `PF-CORPUS-JSON` | 非法 UTF-8/JSON/BOM |
| `PF-CORPUS-DUPLICATE-KEY` | duplicate object key |
| `PF-CORPUS-NUMBER` | float / 非有限 / 超 safe int |
| `PF-CORPUS-KEY` | 非 ASCII-graphic / 超长 key |
| `PF-CORPUS-SCHEMA` | 缺字段 / 未知字段 / 类型 / enum |
| `PF-CORPUS-INVARIANT` | class-leg / claims / projection / skip 代数 / 排序唯一性 |
| `PF-CORPUS-PATH` | 路径 traversal / 非 NFC / 非相对 |
| `PF-CORPUS-LIMIT` | 资源上限 |
| `PF-CORPUS-CANONICAL` | 输入 bytes ≠ canonical re-encode |

## 非声明

- 本切片 **不** 实现 Anvil/OZ runner、manifest、业务 case corpus、family 计分或 formal evidence。
- schema-tests 通过 **不** 表示 OZ 兼容、Reference↔Anvil formal closure 或 maturity 提升。
- 不绑定 `proof-forge.output.v1` product publisher。
- CosmWasm / 其他 target 不在本 schema 范围。
