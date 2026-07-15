---
id: SPEC-DIAG-001
title: 稳定诊断规格
status: proposed
owner: frontend
updated: 2026-07-15
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

## 初始错误码

| Code | 条件 |
|---|---|
| `PF-SRC-001/010/020` | grammar、重复、非法 item |
| `PF-TYPE-001..004` | mismatch、name、cast、interface type |
| `PF-EFFECT-001/002` | callable effect、未声明 effect |
| `PF-BOUND-001` | 无界控制/资源 |
| `PF-VIS-001` | 信息披露违规 |
| `PF-EXT-001` | 未声明 extension syntax |
| `PF-EXPORT-001/002` | identity 冲突、program 选择歧义 |
| `PF-TARGET-UNKNOWN` | TargetId 不存在 |
| `PF-TARGET-NOT-IMPLEMENTED` | 只有设计档案 |
| `PF-REQ-UNSUPPORTED` | exact requirement 无 claim |
| `PF-REQ-PRECONDITION` | claim predicate 不满足 |
| `PF-REQ-EVIDENCE` | evidence 低于 profile 要求 |
| `PF-REQ-CONFLICT` | requirements 不可合并 |
| `PF-SEMANTICS-MISMATCH` | target observation 不等价 |
| `PF-EXTENSION-VERSION` | version/digest mismatch |
| `PF-PLAN-INVARIANT` | Plan 非法 |
| `PF-LOWER-INVARIANT` | TargetIR 非法 |
| `PF-TOOLCHAIN-MISMATCH` | tool missing/version/hash mismatch |
| `PF-ARTIFACT-INVALID` | 制品/manifest 校验失败 |
| `PF-ARTIFACT-NONDEPLOYABLE` | 请求部署不可部署制品 |
| `PF-SETTLEMENT-UNAVAILABLE` | 无 settlement adapter |
| `PF-OUTPUT-*` | 路径、限制、原子写盘 |
| `PF-INTERNAL` | compiler bug；永不用于用户输入错误 |

Requirement rejection 必须带 target、requirementId、version/digest、所有 source origins、
expected claim 和 actual/missing；toolchain error 带预期版本/checksum、解析到的 executable
路径与实际版本，但不输出敏感环境。

## 隐私与安全

diagnostic 只显示 source lexeme 的安全截断；private literal、witness、secret env、RPC token、
private key 一律替换为 `<redacted>`。路径默认 project-relative；`--verbose-paths` 也不进入
JSON/reproducible evidence。外部工具 stderr 以 64 KiB 截断、去 ANSI、标记 untrusted。

## 边界与验收

覆盖无 span、多个 origin、Unicode、100/101 errors、related cycle、private literal、外部工具
二进制输出/ANSI/巨大 stderr、unknown enum field、JSON roundtrip、排序稳定、同 code 不同
target、suggestion 缺失、compiler bug backtrace（只在 debug）、broken pipe。关联
`NFR-002`、`TST-DIAG-001`、全部 negative TST；golden 固定 JSON fields/code 而非完整英文
message。
