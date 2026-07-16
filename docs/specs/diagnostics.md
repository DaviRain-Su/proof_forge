---
id: SPEC-DIAG-001
title: 稳定诊断规格
status: proposed
owner: frontend
updated: 2026-07-16
normative: true
---

# 稳定诊断规格

## Schema

```lean
structure Diagnostic where
  schemaVersion : Nat -- 1
  code          : DiagnosticCode
  severity      : error | warning | note
  phase         : source | type | effect | semantic | resolve | plan | lower | emit | tool | deploy | verify
  message       : String
  primary       : Option SourceOrigin
  related       : Array RelatedOrigin
  program       : Option Name
  target        : Option TargetId
  requirement   : Option RequirementKey
  extension     : Option ExtensionKey
  expected      : Option Json
  actual        : Option Json
  suggestion    : Option String
```

JSON 模式 `proof-forge.diagnostic.v1`。人类 message 可改措辞；code、phase 和字段语义在
major version 内稳定。多错误按 source location/code/context 排序；默认最多 100 errors，
超出追加 `PF-DIAG-LIMIT`。

`schemaVersion`、`code`、`severity`、`phase`、`message` 在每个 diagnostic 中始终必填；`related`
始终存在（可为空）。其余字段按下表条件必填，未列为 required 的字段允许为空；`suggestion`
始终可空，不能为了满足指标生成无意义建议。

| Condition | Required context | 必须为空/限制 |
|---|---|---|
| CLI usage、source open/UTF-8、零 program | `expected`, `actual` | `target`, `requirement`, `extension` 为空；无合法 span 时 `primary` 为空 |
| source/type/effect/semantic 且节点已建立 | `primary`, `program`, `expected`, `actual` | target-free `check` 的 `target` 为空 |
| `PF-TARGET-UNKNOWN`/profile/registry selection | `target`, `expected`, `actual` | 无 source-backed program 时 `primary`/`program` 为空 |
| `PF-REQ-*`/`PF-EXTENSION-VERSION` | `program`, `target`, `primary`, `requirement` 或 `extension`, `expected`, `actual` | `related` 包含其余全部 origin，按 SourceOrigin 排序 |
| plan/lower/emit/artifact build failure | `program`, `target`, `expected`, `actual` | `primary` 仅在错误可追溯到 source 时出现 |
| tool/output/resource containment | `expected`, `actual` | 只有 build context 已建立时才要求 `program`/`target`；不得输出 secret/absolute cwd |
| internal compiler fault | `actual` 为稳定 fault class | release JSON 不含 backtrace、地址或宿主路径 |

`TST-DIAG-001` 必须逐行覆盖 required-field 缺失、target-free 合法 null、source-backed span、
多 origin 顺序、context 尚未建立时的合法 null 和 privacy-forbidden value；schema validator 对
requiredness 失败使用 `PF-INTERNAL`，因为 emitter 生成非法自身协议属于 compiler bug。

## 初始错误码

| Code | 条件 |
|---|---|
| `PF-SRC-001` | grammar/token 错误 |
| `PF-SRC-010` | declaration/name 重复 |
| `PF-SRC-020` | 非法/不受支持 item |
| `PF-SRC-NODEID-COLLISION` | 两个不同 canonical node preimage 截断为同一 128-bit NodeId；整份 program 零输出拒绝 |
| `PF-TYPE-001` | type mismatch |
| `PF-TYPE-002` | unknown/ambiguous name |
| `PF-TYPE-003` | invalid checked cast |
| `PF-TYPE-004` | non-serializable interface type |
| `PF-EFFECT-001` | callable 不允许推导出的 effect |
| `PF-EFFECT-002` | effect 未声明/不受支持 |
| `PF-BOUND-001` | portable Syntax/identifier/program identity 超过 100000 nodes 或 nesting/components 256；未来也用于无法证明的控制流 bound |
| `PF-SRC-INVALID` | source 非 UTF-8、超过 16 MiB 或无法进入 parser |
| `PF-RESOURCE-TIME` | contained compiler worker 超过 versioned monotonic wall budget |
| `PF-RESOURCE-MEMORY` | contained compiler worker 超过 versioned memory budget |
| `PF-RESOURCE-PROCESS` | contained compiler worker 创建超过允许数量的进程或逃逸 containment |
| `PF-RESOURCE-OUTPUT` | contained compiler worker protocol/stdout/stderr 超过 versioned budget |
| `PF-FRONTEND-PROTOCOL` | frontend worker 异常退出或返回 malformed/truncated/version-mismatched payload |
| `PF-LANGUAGE-VERSION-UNKNOWN` | 请求的 exact DSL parser version 未登记 |
| `PF-LANGUAGE-VERSION-DISABLED` | parser version 已禁用/撤销 |
| `PF-LANGUAGE-DEFAULT` | static parser registry 无唯一 current-major default |
| `PF-MIGRATION-FAILED` | source/schema migration 未能原子保持语义 |
| `PF-VIS-001` | 信息披露违规 |
| `PF-EXT-001` | 未声明 extension syntax |
| `PF-EXPORT-001` | exported program identity 冲突 |
| `PF-EXPORT-002` | 多 program 且选择缺失/歧义 |
| `PF-EXPORT-003` | source 中没有可导出的 program |
| `PF-TARGET-UNKNOWN` | TargetId 不存在 |
| `PF-TARGET-NOT-IMPLEMENTED` | 只有设计档案 |
| `PF-PROFILE-UNKNOWN` | Codegen/Network profile 不存在或属于其他 target |
| `PF-PROFILE-REVOKED` | profile/evidence 已撤销或过期 |
| `PF-REGISTRY-DUPLICATE` | registry ID/key/default 重复 |
| `PF-REGISTRY-INVALID` | descriptor/profile/digest/compatibility invariant 失败 |
| `PF-REQ-UNSUPPORTED` | exact requirement 无 claim |
| `PF-REQ-PRECONDITION` | claim predicate 不满足 |
| `PF-REQ-EVIDENCE` | evidence 低于 profile 要求 |
| `PF-REQ-CONFLICT` | requirements 不可合并 |
| `PF-EVIDENCE-BINDING` | support EV 缺失 candidate/target/profile/requirement/freshness/revocation binding |
| `PF-SEMANTICS-MISMATCH` | target observation 不等价 |
| `PF-SEMANTIC-INVALID` | canonical semantic schema/invariant 失败 |
| `PF-SEMANTIC-INTERNAL` | reference interpreter 命中不可能状态 |
| `PF-EXTENSION-VERSION` | version/digest mismatch |
| `PF-PLAN-INVARIANT` | Plan 非法 |
| `PF-LOWER-INVARIANT` | TargetIR 非法 |
| `PF-TOOLCHAIN-MISMATCH` | tool missing/version/hash mismatch |
| `PF-TOOLCHAIN-MISSING` | required locked asset/cache/tool 不存在 |
| `PF-TOOL-UNTRUSTED` | executable/path/env/closure 未通过信任验证 |
| `PF-TOOL-PROTOCOL` | external tool 异常退出或返回 malformed/truncated/version-mismatched payload |
| `PF-HOST-STAGE0` | Stage-0 record、bootstrap digest、签名或启动环境无效 |
| `PF-HOST-INELIGIBLE` | live host 匹配 development profile，但不具备 formal hermetic 资格 |
| `PF-ARTIFACT-INVALID` | 制品/manifest 校验失败 |
| `PF-ARTIFACT-NONDEPLOYABLE` | 请求部署不可部署制品 |
| `PF-SETTLEMENT-UNAVAILABLE` | 无 settlement adapter |
| `PF-OUTPUT-PATH` | output path/containment/symlink 违规 |
| `PF-OUTPUT-COLLISION` | destination/artifact path/casefold 冲突 |
| `PF-OUTPUT-LIMIT` | file/count/path/published byte limit 超限 |
| `PF-OUTPUT-ATOMICITY` | staging/fsync/rename/rollback 失败 |
| `PF-DIAG-LIMIT` | 超过 100 条诊断后的唯一截断 sentinel |
| `PF-INTERNAL` | compiler bug；永不用于用户输入错误 |

Requirement rejection 必须带 target、requirementId、version/digest、所有 source origins、
expected claim 和 actual/missing；toolchain error 带预期版本/checksum、解析到的 executable
路径与实际版本，但不输出敏感环境。

当前 alpha 尚未实现上面的完整 `Diagnostic v1` record/JSON/span。Syntax preflight 通过
`CompileError.resourceBound` 保留稳定 code `PF-BOUND-001`，human message 只说明超出的
node/nesting/identity limit。CLI 的 16 MiB parser 前文件上限仍是
`CompileError.invalidProgram` / `PF-SRC-INVALID`；这两个边界不得在证据中混写。

## 隐私与安全

diagnostic 只显示 source lexeme 的安全截断；private literal、witness、secret env、RPC token、
private key 一律替换为 `<redacted>`。路径默认 project-relative；`--verbose-paths` 也不进入
JSON/reproducible evidence。外部工具 stderr 以 64 KiB 截断、去 ANSI、标记 untrusted。

clean-room stage failure receipt 不属于公共 `Diagnostic v1`。development continuation 只把
stdout/stderr 各最后 32768 bytes 转成 ASCII representation 后回显，并同时输出 receipt
digest；该转义阻止控制字节操纵终端，但不会自动删除 printable secret。formal evidence
必须先 retained、private-scanned/redacted，再决定可公开的诊断摘要。

## 边界与验收

覆盖无 span、多个 origin、Unicode、100/101 errors、related cycle、private literal、外部工具
二进制输出/ANSI/巨大 stderr、unknown enum field、JSON roundtrip、排序稳定、同 code 不同
target、suggestion 缺失、compiler bug backtrace（只在 debug）、broken pipe。关联
`NFR-002`、`TST-DIAG-001`、全部 negative TST；golden 固定 JSON fields/code 而非完整英文
message。
