---
id: SPEC-COMMON-001
title: 公共类型、规范编码与资源 Profile
status: proposed
owner: architecture
updated: 2026-07-29
normative: true
---

# 公共类型、规范编码与资源 Profile

本文件是所有 normative schema 的 primitive authority。其他规格可以缩窄值域，不能重新定义
同名类型、wire form、比较或 hash 规则。

Unicode string validation 固定为 Unicode 17.0.0 / UAX #15 revision 57（`ADR-0014`，
`SRC-UNICODE-001/002`）。字段规则写“先 NFC”时，decoder 必须要求输入已经是 NFC 并对非 canonical
spelling fail closed，不得静默 normalize 后接受；pure-Lean tables/generator 的 exact file digests
由 `unicode.lock.json` 固定。`General_Category=Cc` 使用同一 UCD 版本。

## 标量与身份

```lean
universe u

inductive DigestAlgorithm
  | sha256

structure ProjectRelativePath where value : String
structure UtcInstant where value : String

structure NonEmptyArray (α : Type u) where
  head : α
  tail : Array α

structure Digest where algorithm : DigestAlgorithm; bytes : ByteArray
structure SemVer where major minor patch : UInt64; prerelease build : Array String
structure SchemaId where value : String
structure EvidenceId where value : String
structure AcceptanceProfileId where value : String
structure ContentRef where
  schema  : SchemaId
  id      : String
  version : SemVer
  digest  : Digest

structure NodeId where bytes : ByteArray
structure QualifiedName where components : NonEmptyArray String
structure SourceOrigin where
  sourcePath : ProjectRelativePath
  startByte  : UInt64
  endByte    : UInt64
  nodeId     : NodeId

inductive DocumentStatus
  | notStarted | draft | proposed | inReview | accepted | superseded | archived

inductive ArtifactDeployability
  | deployable | verifiableWorkload | intermediateOnly | nonDeployable
```

- `DigestAlgorithm` 在 schema v1 只允许 SHA-256。JSON/wire form 是
  `sha256:<64 lowercase hex>`；比较按 32 raw bytes，拒绝大写、裸 hex、其他长度和 unknown
  algorithm。digest 输入必须由拥有该 schema 的规格定义 domain tag 和 canonical bytes。
- `NonEmptyArray<T>` 的 canonical JSON/binary wire 与所属 schema 的 `Array<T>` 完全相同，只额外要求
  count `>= 1`；`head/tail` 是 Lean 内存表示，不编码为 object 或两个字段。empty array 必须在构造
  typed value 前拒绝。
- `SemVer` 严格遵循 SemVer 2.0.0 grammar；core number 禁止 leading zero，identifier 非空。
  precedence 忽略 build metadata，但 exact identity 比较包含 canonical build metadata；不接受
  `v` 前缀、range、wildcard、`latest` 或缺 patch。wire form 是唯一 canonical SemVer ASCII
  string；没有 prerelease/build 时不出现对应 `-`/`+`，排序 identity 时按该完整 string 的
  UTF-8 bytes，而不是 SemVer precedence。
- `SchemaId` 是 1..127 bytes 的 lowercase dotted ASCII；每个 segment 使用
  `[a-z][a-z0-9]*(?:-[a-z0-9]+)*`，且至少包含一个 `.`。因此 `proof-forge.output.v1`
  和 `proof-forge.resource-profile.v1` 均是合法值，而 leading/trailing/consecutive hyphen
  或空 segment 不合法。`TargetId` 另按 SPEC-REG-001 的 1..32 bytes grammar；
  `CodegenProfileId`/`NetworkProfileId` 是 1..127 bytes、grammar
  `[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*`。
- `AcceptanceProfileId` 使用与 profile ID 相同的 1..127-byte grammar。`NodeId` 恰好 16 bytes，
  wire form 为 `nodeid:<32 lowercase hex>`；其 domain/preimage、path traversal 与 collision contract
  由 SPEC-LANG-001 和 SPEC-SOURCE-WIRE-001 固定。
- `ContentRef` wire object 恰为 `schema,id,version,digest`。`id` 使用 profile ID grammar；它只
  引用由 `schema` 所属规格定义的 immutable payload，consumer 必须按该规格的 domain tag 重算
  payload digest 并 exact compare。Common 不为不同 schema 再套一层通用 content hash。
- `EvidenceId` 只接受 `EV-[0-9]{8}-[0-9]{4}`；日期必须是真实 Gregorian UTC date。
- `QualifiedName` 只允许 1..256 个非 anonymous、非 numeral Lean identifier component；每个
  component 先 NFC，UTF-8 长度 1..240 bytes。这里的 canonical component 必须由
  `Lean.isIdFirst` + `Lean.isIdRest` 直接接受且不得为 exact `_`；`«...»` escape token spelling
  不进入 wire。keyword reservation 属于产生该 `QualifiedName` 的语法 owner；Common 不复制
  ambient parser keyword set，因此 keyword-shaped component 仍按上述固定字符规则验证。
  wire form 是按声明次序保存的 nonempty JSON
  string array；比较和排序按各 component 的 NFC UTF-8 bytes，不按 locale。
- `ProjectRelativePath.value` 使用 `/`，UTF-8 NFC，1..1024 bytes；其 wire form 是该 String 本身，
  拒绝 `/` 开头或 ASCII drive-prefix（如 `C:/`）absolute、空/`.`/`..`
  segment、反斜线和 Unicode General_Category=`Cc` code point。这只是 total lexical wire validation：它不访问文件系统，
  也不能单独判断 symlink、hardlink、mount 或 case-fold collision。
- `SourceOrigin` wire object 恰为 `sourcePath,startByte,endByte,nodeId`；origin 集合的 canonical
  key 是 `(sourcePath UTF-8,startByte,endByte,nodeId raw bytes)`。scalar validator 只要求
  `startByte <= endByte`；byte offsets 指向原始 UTF-8，line/column 只可派生，不能参与 identity。
  `endByte <= sourceBytes` 必须由持有同一次 immutable source snapshot 的 Source/provenance join 验证。
  **`nodeId` 在 common `SourceOrigin` 上不可空**（恰好 16 bytes）。pre-node parser 位置的显式
  nullable NodeId 属于 diagnostic-only `DiagnosticOriginV1`（见
  [`SPEC-DIAG-001`](diagnostics.md) 与 [`ADR-0022`](../adr/0022-d1-diagnostics-contained-frontend-contract.md)），
  不得把 `Option NodeId` 塞进本结构，也不得把全零 sentinel 定义为 common identity 语义。

`ProjectRelativePath` 集合 owner 必须另做 NFC + Unicode default casefold 后的全局唯一性检查；文件
consumer 必须在其规格规定的 trusted root 下执行 component-by-component no-follow safe-open，并验证
regular/single-link/ownership/mode/stable inode-size-digest。上述 contextual checks 不能塞回 scalar decoder，
也不能由一条未解析 filesystem 的 path string 自证。
- `UtcInstant.value` 的唯一 wire form 是该 String 本身，必须为 RFC 3339 UTC 秒精度
  `YYYY-MM-DDTHH:MM:SSZ`；禁止 fractional
  seconds、offset 和 leap second。`UInt*` JSON 值为无符号十进制 integer，不接受 float、指数、
  `-0` 或超过 `2^53-1` 的值；更大整数必须由所属 schema 显式定义 decimal-string wrapper。
- `DocumentStatus` 的唯一 wire enum 与顺序是 `not_started < draft < proposed < in_review <`
  `accepted < superseded < archived`；其生命周期语义由 [`DOC-STATUS`](../document-status.md) 拥有。
  `ArtifactDeployability` 的唯一 wire enum 与顺序是 `deployable < verifiable-workload <`
  `intermediate-only < non-deployable`；primary 完整性不改变该值。
- `Option T` 在 object 的已声明字段上必须显式编码为 `null` 或 `T` 的 exact wire value，禁止靠字段
  缺失表达 `none`；`Bool` 只接受 JSON literal `true`/`false`。上述 scalar/ref/object 均拒绝
  unknown field、unknown enum 和非 canonical alternate spelling。

## Canonical JSON 与 hash

JSON reader 必须在构造对象前拒绝 duplicate key、invalid UTF-8、lone surrogate、NaN/Infinity、
unknown enum 和 schema 禁止的 unknown field。字符串先按所属字段规则验证/NFC，再按 RFC 8785
JCS 生成 UTF-8；array 顺序由所属 schema 决定，集合必须先按其 canonical key 排序并拒绝重复。
schema digest 为 `SHA-256(UTF8(domainTag) || 0x00 || JCS(value))`，domainTag 是非空 lowercase
ASCII profile-style ID（1..127 bytes，使用本文件 profile ID grammar）且由所属 schema 固定。
不得 hash pretty JSON、map iteration order、absolute path 或时间。

PF-JCS v1 的公共 codec 只暴露当前 closed schemas 所需的 `null`、boolean、I-JSON safe integer
（`-(2^53-1)..2^53-1`）、Unicode scalar string、array 与 object；object key 使用 RFC 8785 的
UTF-16 code-unit 顺序。decimal fraction、exponent、negative zero 与超出 safe-integer 的 number
全部拒绝，而不是借 ambient floating-point formatter 隐式接受。未来 schema 若需要非整数 number，
必须先版本化扩展公共 codec 与验收向量。

## ResourceProfileV1

```lean
inductive ResourceStage
  | frontend | compilerCore | externalTool | artifactOutput

inductive MemoryMetric
  | darwinPhysFootprintAggregate | linuxCgroupMemoryCurrent | jobObjectCommitAggregate

structure ResourceProfileV1 where
  schema                 : SchemaId
  profileId              : SchemaId
  stage                  : ResourceStage
  maxWallMillis          : UInt64
  maxAggregateMemoryBytes : UInt64
  memoryMetric           : MemoryMetric
  maxProcesses           : UInt32
  maxProtocolBytes       : UInt64
  maxStderrBytes         : UInt64
  maxPublishedBytes      : UInt64
```

`ResourceProfileV1` 的 exact wire object 恒为
`schema,profileId,stage,maxWallMillis,maxAggregateMemoryBytes,memoryMetric,maxProcesses,`
`maxProtocolBytes,maxStderrBytes,maxPublishedBytes` 这十个字段，不允许 unknown field。
`schema` 固定为 `proof-forge.resource-profile.v1`；`ResourceStage` 与 `MemoryMetric` 按上述
constructor 名的 ASCII string 编码。profile digest 为
`SHA-256("proof-forge.resource-profile.v1" || 0x00 || JCS(wireObject))`，不得将 digest
本身放回该 object。

初始 hard maxima 如下；CLI/target policy 对每个非零数值只能取更小正整数，不能提高。
hard maximum 为 `0` 时 effective 值必须仍为 `0`，表示该 stage 禁止发布 artifact，
不表示 unlimited。提高任一 hard maximum 需要新 `profileId` version、review 和 digest；
只有 wire field/语义变化才提升 resource-profile schema。

| Profile ID | Stage | Wall | Aggregate memory | Processes | Protocol/stdout | stderr | Published bytes |
|---|---|---:|---:|---:|---:|---:|---:|
| `proof-forge.resource.frontend.v1` | frontend | 10,000 ms | 2 GiB | 1 | 64 MiB | 64 KiB | 0 |
| `proof-forge.resource.core.v1` | compilerCore | 30,000 ms | 2 GiB | 1 | 64 MiB | 64 KiB | 0 |
| `proof-forge.resource.tool.v1` | externalTool | 600,000 ms | 4 GiB | 8 | 64 MiB | 64 KiB | 0 |
| `proof-forge.resource.output.v1` | artifactOutput | 60,000 ms | 2 GiB | 1 | 1 MiB | 64 KiB | 256 MiB |

Frontend stage 的 protocol/stdout 硬上限 **64 MiB**（`maxProtocolBytes`）与 source open 的
**16 MiB** source-byte 上限是 B9/B9R `FrontendProtocolV1`（`ProofForgeV2/Frontend/ProtocolV1.lean`）
解码器 precheck 的权威数字：一帧 request 或 response 超过 64 MiB、source/canonical bytes 超过
16 MiB、或 span/node 计数超过 100000 时 fail closed。**B9R**：module/program selector 不再带
任意 4096-byte 语义上限——仅受 `maxProtocolBytes` 分配/帧 guard 约束（`maxSelectorBytes` 仅为
等于该值的兼容别名）；精确 Lean `1..256 × 1..240` 组件合法性与源诊断分类推迟到 Loader。
Failure 帧在 `parsePfJcs` 前对 PF-JCS 诊断数组做 top-level 条目预扫描（0 或 >101 拒绝；嵌套/
字符串逗号不计），canonical 权威仍为 `mkFailureBundleV1` re-encode identity。**B10** standalone
worker 的 stdin reader 以 64 KiB chunks 累积，最多探测到 `maxProtocolBytes+1` 后 fail closed；
worker 自身不打开路径。**B11a** package-owned native safe-open foundation 复用 `maxSourceBytes`，在
读取前按 initial `fstat` 拒绝 `>16 MiB`，并执行 component no-follow、regular/single-link、exact-size
read + one-byte probe 和 fd/path metadata recheck。它尚未进入 killable supervisor 或产品 CLI；
read deadline、wall/memory/process enforcement、receipt、contained assurance 与 formal TASK-D1-08
仍 pending。详见 [`source-frontend.md`](../modules/source-frontend.md)。

Darwin v1 的 `memoryMetric` 为 containment 内全部 live process `phys_footprint` 之和；其他 host
必须登记等价的 kernel/job-controller metric，不能把单 leader RSS 冒充 aggregate。wall clock 从
source open/worker spawn 之前的 supervisor arm 开始，使用 monotonic clock。进程数含 worker；
frontend/core 因上限为 1，不允许任何 descendant。formal runner 必须以不可逃逸 session/job/VM
边界强制 process/memory limit；development polling observation 不构成 formal enforcement。
`memoryMetric` 由 exact host profile 在构造 profile object 前选定；相同 `profileId` 在不同 host
metric 下必然产生不同 digest，不得只用 ID 跨 host 代换。

**Containment assurance（ADR-0022 D2）**：`darwin-development-observed` 允许 ordinary development
运行，但 **永不** 表示 process/session containment 或 formal/hermetic evidence。仅当 **每一个**
descendant 仍 controller-bound **且** resource attribution 由 controller event 支撑时，Linux 路径
才可声明 `contained`。禁止 silent assurance fallback：无法证明 controller-bound、或缺少 controller
event 时，不得将 development observation 升格为 `contained`，也不得用 stderr 猜测 OOM/逃逸。
本规格 **不** 冻结 cgroup 布局、polling 周期、OS API 表面或 host-probe 分类法。

source open 属于 frontend wall budget：supervisor 使用 dirfd-relative、no-follow、nonblocking、
close-on-exec open，`fstat` 后只接受 regular single-link file；size 大于 16 MiB 在读取前拒绝，
随后 bounded read 到 EOF 并额外探测 1 byte。FIFO/device/socket/symlink、read deadline、truncate/
grow race 和 short read 都稳定失败；攻击者不能在 worker budget 生效前阻塞 parent。

工程状态：B11a 已实现上述 no-follow/regular/single-link/size/read-probe/metadata-recheck primitive，
但尚无 killable unit 或 monotonic read deadline；因此当前实现**不能**声称已满足上一段的 parent
non-blocking、resource attribution 或 containment 结论。B11b supervisor 才拥有这些剩余合同。

超限归因优先级固定为 controller event：process denial → memory controller event → protocol/output
cap → monotonic deadline；无对应 controller event 的 signal、malformed/truncated response 或 worker
exit 按下表的 stage mapping 归因，不根据 stderr 猜 OOM。等于上限接受，首次超过即终止整个
containment，reap 全部成员、关闭 pipe、删除私有 staging，旧输出保持不变且不得发布部分 artifact。
lowering 后必须构造新的 exact `ResourceProfileV1` object 并重算 effective digest。internal receipt
同时记录 hard-profile ID/digest、effective object/digest、observed peak/elapsed、controller event 和
cleanup result。supervised CLI 向 public JSON 暴露的是 **bounded public-safe `receipts` 投影/digest**
（ADR-0022 D3 / SPEC-CLI-001），不是 raw/full receipt、不是 diagnostic、不是 artifact。

## 错误、版本与验收

primitive 解析失败使用所属阶段的具体 code。四个 stage 的 controller limit 都精确映射为
`PF-RESOURCE-TIME`、`PF-RESOURCE-MEMORY`、`PF-RESOURCE-PROCESS` 或
`PF-RESOURCE-OUTPUT`，CLI exit 均为 6。无 controller event 的 protocol/exit 映射固定为：

| Stage | Protocol/abnormal-exit code | CLI exit |
|---|---|---:|
| `frontend` | `PF-FRONTEND-PROTOCOL` | 6 |
| `compilerCore` | `PF-INTERNAL`（trusted compiler worker 违反自身协议） | 70 |
| `externalTool` | `PF-TOOL-PROTOCOL` | 6 |
| `artifactOutput` | staging/fsync/rename/rollback 失败为 `PF-OUTPUT-ATOMICITY` / 6；compiler-owned malformed payload 为 `PF-INTERNAL` / 70 | 6/70（按左列条件） |

source byte/UTF-8 错误仍为 exit 3；任何 stage 都不得用 stderr 文字改写上述归因。

`TST-COMMON-001` 覆盖每个 scalar 的 empty/min/max/over、Unicode/NFC、canonical/noncanonical、
duplicate/unknown field、SemVer prerelease/build、UTC leap/day、path escape 和 domain separation。
`TST-RESOURCE-001/002` 覆盖四 stage 的 equal/over、lower-only policy、FIFO/special/symlink、read
deadline、hang、aggregate-memory、fork/`setsid()`、protocol/stdout/stderr/published cap、signal、
cleanup/zero-partial-output、receipt digest 与 controller-event attribution。关联 NFR-002/006/008。
