---
id: SPEC-CAP-001
title: Requirements、Capabilities 与 Extensions
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Requirements、Capabilities 与 Extensions

## 身份与 schema

```lean
structure RequirementId where value : String
structure RequirementRef where
  id      : RequirementId
  version : SemVer
  digest  : Digest
  origin  : NonEmptyArray SourceOrigin

structure SupportClaim where
  requirement : RequirementKey -- id + exact version + digest
  predicates  : Array SupportPredicate
  evidence    : EvidenceGrade
```

ID 为反向域式小写 dotted ASCII，如 `state.map`、`failure.atomic-revert`；version 使用完整
SemVer，解析后 exact equality，不接受范围、latest 或通配符。digest 是
`sha256:<64 lowercase hex>`，覆盖规范化语义定义而非实现代码。

## Requirement 域

- `value.*`：width、checked overflow、Field、Bytes、Principal。
- `control.*`：loop bound、call depth、recursion、allocation。
- `state.*`：cell/map/vector、atomic commit、continuity。
- `effect.*`：event、sync call、async workflow、protocol call。
- `context.*`：caller、authorizers、time、randomness。
- `disclosure.*`：verifier visible、prover witness、commitment only。
- `authority.*`：caller/signer/auth tree/record owner。
- `stateCustody.*`：program/account/user/record/external continuity。
- `failure.*`：revert/trap/external failure/commit boundary。
- `extension.*`：target/ecosystem-specific typed semantics。

## 推导

每个 typed operation 通过静态 table 贡献 requirements；复合节点取 key union，并合并
origin。参数化 requirement（width、bound、max bytes）使用 predicate payload，而不是动态
拼接 ID。相同 key 取更严格 predicate：numeric max 取最大需求、minimum 取最小需求、
集合取 union；不可比较 predicate 为 `PF-REQ-CONFLICT`。输出按 key 排序，推导与 target
无关且幂等。

## Support Resolution

```text
for requirement in canonicalOrder:
  claim := exact lookup(target, id, version, digest)
  if missing: reject PF-REQ-UNSUPPORTED
  if predicates do not imply requested payload: PF-REQ-PRECONDITION
  if claim.evidence < requested minimum: PF-REQ-EVIDENCE
if any rejection: return sorted DiagnosticBundle
else: construct ResolvedProgram target with immutable decisions
```

禁止 alias、nearest version、目标 fallback、best effort 或 evidence 自动降级。

## Extensions

用户只可用顶层：

```lean
requires extension near.promise version "1.0.0"
  digest "sha256:..."
```

extension 注册 typed syntax/operation、type/effect/requirement rules 和 target support claims；
不能注入任意 elaborator callback、文件 I/O 或动态 native code。未声明 extension syntax 为
`PF-EXT-001`，版本/digest 不符为 `PF-EXTENSION-VERSION`。使用 extension 不改变 DSL
入口，只使不支持它的 targets 精确拒绝。

## EvidenceGrade

顺序为 `specified < artifact_validated < local_runtime < network_or_proof_validated`。
claim 必须指向 `EV-*` 或仍为 specified；文档/父项目实现不能提升 V2 evidence。build 的
默认 minimum 是 profile 声明值，CLI 可要求更高但不可降低 profile 的安全下限。

## 版本与边界

语义改变必须新 version+digest；只增加 source locator 不改变 key。覆盖 duplicate key、
unknown ID、malformed SemVer/digest、same version different digest、predicate exact/equal/
just-over limit、incomparable predicate、origin merge/order、zero requirements、extension
未声明/重复/冲突、claim evidence 不足、registry target 不存在、resolver 全部错误聚合。

## 安全与验收

registry 静态编译并有 canonical hash；不加载网络或动态插件。diagnostic 必须带每个 origin
且不得泄露 private literal。关联 `FR-006/013`、`TST-REQ-001..003`、
`TST-XTARGET-002`；property test 证明 inference 与 source item/hash-map 顺序无关。
