---
id: ADR-0025
title: EVM context.caller Principal realization（encoding contract）
status: accepted
owner: architecture
updated: 2026-08-06
normative: true
approvers: architecture-owner, davirain, quality-owner
approvedAt: 2026-08-03
reviewCommit: aa603834e2f63dc0537f4636b4d54c17533bffe3
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/aa603834e2f63dc0537f4636b4d54c17533bffe3
openFindings: none
---

# ADR-0025：EVM `context.caller` Principal realization（encoding contract）

## 状态

**accepted** — 本 ADR **冻结 encoding / product contract**（不因 encoding 自动升格
OZ/ABI/formal/release claim）。

**实现进度（2026-08-06 DOC-SYNC）**：EVM target-owned Plan/IR/Yul **已原子 cutover**
（ADR-0031 S1 / `callerPrincipalWord` + Anvil `CallerCheck` + corpus
`pf.primitive.ownablelike.caller-admit.v1`）。**仍未**因 cutover 解锁 Solidity
`address` ABI、indexed ownership event、OZ F01 family Partial、或他 target 自动镜像。
他 target ContextRead 仍各自 fail closed 或仅开 unixTime（见
`docs/research/12-target-coverage-matrix.md`）。

## 背景

共享语义面已有：

- Source spelling `context.caller` → Semantic
  `Op.ContextRead proof-forge.context.caller.v1` → 匿名 `Principal`
  （`Source.ContextCommitSurfaceV1` / N-2 / RequirementsInfer / Wire exact row）。
- Wire `Principal` valueBytes = `concat(u32le length, opaque body)`，
  length `1..4096`（SPEC-SEM-WIRE-001）；**TypeShape 无 Address 构造子**。
- Reference：`InvocationV1.context` 对可达 ContextRead key 要求 exact membership、
  TypeId 匹配与 **canonical valueBytes**；equality 为 full-consume re-encode identity
  （byte-exact），不由 TargetId 改写。
- EVM T10 将 Principal **state/param** 以 `len + 8×UInt64` leaf 原样存 wire identity
  （≤64B body）；**不是** 20-byte address ABI，也不把 CALL 目标解为 Principal ValueId
  （B-3 PrincipalAddr pin + AddressBearing static QN）。
- **历史（cutover 前）**：EVM `LowerSemanticV1` 曾对 `context.caller` /
  `unix-time-seconds` 显式 fail closed（naive bare `caller()` 会把 20B address
  泄漏进 Principal slot，违反 PrincipalAddr pin）。**2026-08-06 后**：二者均已
  LOWERED（caller → 本 ADR encoding；unixTime → `timestamp()`）。

OpenZeppelin 审计（`docs/research/17-openzeppelin-ethereum-coverage-audit.md`）将
**EVM address/caller 精确关系**列为 P0 产品决策门；F01 Ownable 在 caller 物化前保持
`Blocked`。本 ADR 关闭该决策门的 **encoding 半边**，不解锁实现或 family status。

## 决策

### 1. Shared Principal wire 不变

- `Type.Principal` / TypeShape / codec / canonical valueBytes 规则 **保持**
  `u32le(len) || opaque body`（`1 ≤ len ≤ 4096`）。
- **禁止** 新增 Address type、改 TypeShape、改 shared codec、或为 EVM 发明第二套
  Principal wire spelling。
- Target Plan 只能 **物化** 符合既有 wire 的 valueBytes；不能无损表示则 fail closed
  （既有 type-effect 纪律）。

### 2. EVM `context.caller` 唯一 realization（next-sprint 实现契约）

当且仅当后续 EVM target-owned Plan/IR/Yul 原子 cutover 打开
`Op.ContextRead proof-forge.context.caller.v1` 时，结果 `Principal` 的 canonical
valueBytes **精确**为：

```text
valueBytes = u32le(20) || address20
```

其中：

- `u32le(20)` 是 little-endian 无符号 32-bit length 前缀（与 SPEC-SEM-WIRE-001 一致）；
- `address20` 是 EVM opcode **`CALLER`** 返回值的 **network-order 20 raw bytes**
  （即 `msg.sender` 的 20 字节地址本体，**不是** left-padded 32-byte word、**不是**
  hex 字符串、**不是** checksummed spelling）。

因此 wire body length **恒为 20**；完整 valueBytes 长度恒为 **24**。

### 3. 禁止的映射与 fallback

实现与文档 **必须拒绝** 下列任何一条（fail closed，无 silent coerce）：

| 禁止项 | 说明 |
|---|---|
| truncate / pad | 不得把 32-byte word 截断为 20、或把短 body 右侧/左侧 pad 成 20 |
| hash / prefix strip | 不得 `keccak`/`sha256` 派生，不得剥 `u32le` 前缀当 address |
| 第二套 identity spelling | 不得并行接受 bare 20B、left-padded 32B、hex、checksum、ENS 等 |
| approximate Principal→address | 任意 `len ≠ 20` 或 body ≠ CALLER 字节 **不得** 当 EVM address 使用 |
| dynamic CALL/callee 解锁 | 本 contract **不** 把 Principal ValueId 变为 CALL 目标 |

CALL 目标继续遵循既有 AddressBearing：**static QualifiedName** →
`keccak256(path)` 后 20 字节；与 `context.caller` Principal **无关**。

### 4. 明确不解锁的表面

本 ADR **不** 授权、不实现、不暗示下列任一完成：

- Solidity / ABI JSON 标准 `address` 类型或 selector 编码；
- indexed `address` event/error topic ABI；
- dynamic CALL / 动态 callee / `DELEGATECALL` / `STATICCALL` 语义扩展；
- payable / `callvalue` / balance / native ETH transfer；
- proxy / create / create2 / upgrade 路径；
- Solana / NEAR / Noir / Aleo / Psy / CosmWasm / TON 的 ContextRead 或 native identity 映射；
- OpenZeppelin Ownable **F01** 由 `Blocked` 升格，或任何 OZ / ABI / formal / release claim。

Ownable F01 **仍为 Blocked**，直到后续实现 cutover **且** 审计文档独立批准的
behavior / observation 条件满足（本 ADR 不改 family status 表）。

### 5. 当前工程状态（2026-08-06 DOC-SYNC）

| 层 | 状态 |
|---|---|
| Source / Typed / Normalize / Wire / Requirements | 已支持 `context.caller` → Principal ContextRead |
| Reference invocation | 已要求 context 提供 canonical Principal valueBytes；**不** 绑定 EVM 20B |
| EVM Plan/IR/Yul | **LOWERED**：`callerPrincipalWord` 九叶 + Yul `byte(_, caller())` 装配；ValidatePlan/IR + Anvil/corpus 正向/负向 |
| 他 target ContextRead Plan | **非均匀（后续 ADR-0031 S1）**：Solana 仅 exact CPI profile 开 signer-role caller（legacy FC）；NEAR 开 init/entry predecessor caller（view FC）；CW 开 instantiate/execute sender caller（query/view FC）；TON 仍仅 unixTime；Noir/Psy/Aleo/Quint FC |
| T10 Principal state/param storage | **不变**（wire identity leaf；≠ address ABI） |
| Ownable / OZ / address ABI | **仍非本 ADR 解锁**：F01 OZ family 仍 Blocked 于标准 address ABI/event 与 pinned OZ leg |

实现纪律：禁止半开 surface 或 best-effort；偏离本 encoding 的第二拼写 fail closed。

### 6. Reference invocation、equality 与跨 target 非均匀 capability

**Reference（target-neutral）**

1. 程序若静态可达 `Op.ContextRead proof-forge.context.caller.v1`，则
   `InvocationV1.context` 必须含该 key，result TypeId 为匿名 Principal，
   `valueBytes` 必须通过 Principal canonical decoder（full-consume +
   `encode(decode) == bytes`）。
2. Equality / 比较：Principal 与其它 shape 一样，对 **完整** canonical
   valueBytes 做 byte-exact equality（含 `u32le` 前缀）。因此
   `u32le(20)||addr` **不等于** bare `addr`、**不等于**
   `u32le(32)||leftPad12||addr`、**不等于** 其它 length 的 opaque body。
3. Reference **不** 根据 TargetId 改写 context bytes 或业务语义；它只解释
   SemanticProgram + invocation 输入。EVM realization 是 **materialization
   合同**：链上 `CALLER` 读数必须装配为与 Reference 可比对的同一 canonical
   bytes，以便未来 Reference↔Anvil 差分使用 **同一** valueBytes 拼写。

**EVM（本 ADR 冻结）**

- 运行时 `CALLER` → `u32le(20) || address20` 是 **唯一** 合法 caller Principal
  拼写；产品测试夹具与 oracle 必须使用该 24-byte form。
- 与 T10 存储的交互：若 state 中存有同一 24-byte Principal，byte-exact `==`
  成立当且仅当 body 与当前 caller 相同；**不得** 把 storage leaf 布局改成
  固定 20B address slot 以“优化”caller。

**其它 target（非均匀 capability；本 ADR 本身不打开，后续 ADR-0031 S1 已逐 target cutover）**

- Solana 仅在 exact CPI profile 以 ABI `pf_caller` signer 的 32B pubkey 物化 caller，
  legacy profiles FC；NEAR 以 `predecessor_account_id` 开 init/entry、view FC；CosmWasm
  以 `MessageInfo.sender` 开 instantiate/execute、query/view FC；Noir/Aleo/Psy/Quint/TON
  caller 继续 FC。
- 各 target 可选择不同 body 长度/字节约定，但 **必须** 仍编码为 shared
  `u32le(len)||body`，且 **不得** 让 TargetId 在 Normalize/Typed 层改写程序业务语义
  （ADR-0003/0004）。跨 target 程序若依赖“caller 是 20B EVM address”则 **不是**
  portable claim——capability 矩阵必须诚实标出。

### 7. 与 B-3 / B-CTX-OPEN / B-CALL-SEM 的关系

| 项 | 本 ADR 后 |
|---|---|
| **B-3 PrincipalAddr** | **仍成立**：禁止 approximate 任意 Principal→20B/32B 映射；CALL 仍非 dynamic Principal 地址 |
| **B-3 AddressBearing** | **不变**：static QN callee；与 caller Principal 正交 |
| **B-CTX-OPEN** | EVM caller encoding + Plan/IR/Yul cutover 已完成；其它 target 的后续开放由 ADR-0031 S1 独立批准并按各自 runtime 身份绑定，未反向扩大本 ADR 的 EVM-only normative scope |
| **B-CALL-SEM** | **不变**：static-QN CALL / stub 语义债仍在；本 ADR 不修复 call/schedule 完整平台语义 |

## 理由

1. **单一 wire 权威**：保留 opaque Principal，避免第二 type 与 codec 分叉；EVM 只约束
   **一种** body 拼写，满足 fail-closed 与 exact equality。
2. **与 Yellow Paper / EVM 操作码对齐**：`CALLER` 提供 20-byte address；length-prefix
   使其成为合法 Principal valueBytes，而不是把 VM word 静默塞进 opaque slot。
3. **可差分**：Reference 与未来 Anvil 路径可对同一 24-byte valueBytes 做
   byte-exact 对齐，无需 TargetId 特判语义。
4. **范围控制**：显式不解锁 ABI/proxy/value/他链，防止“caller 打开 = Ownable/ERC20
   完成”的过度声明。

## 影响

- 文档：`docs/targets/01-evm.md`、`docs/research/12-target-coverage-matrix.md`、
  `docs/engineering-backlog.md`（B-CTX-OPEN / B-3 细化）与本 ADR 索引同步。
- **代码 / tests / scripts / tool locks / corpus / OZ family status：本切片不修改。**
- formal TASK-D\* / maturity 标签 / release qualification：**不抬高**。
- 后续实现切片（非本 ADR）必须引用本 encoding 并原子 cutover；偏离本 contract
  的实现视为产品 bug，不得以 fallback 交付。

## 备选（拒绝）

| 备选 | 拒绝原因 |
|---|---|
| 新增 `Type.Address` / EVM-only shape | 分裂 portable 类型；违背 Principal 不透明身份模型 |
| bare 20B 无 length 前缀 | 违反 SPEC-SEM-WIRE-001 Principal valueBytes |
| left-padded 32B 当 Principal body | 与 CALLER 20B 不等价；引入 pad/truncate 诱惑 |
| hash(path) 或 storage slot 当 caller | 不是 `msg.sender`；Ownable 语义错误 |
| 打开 Solidity `address` ABI 与本切片一并交付 | 范围膨胀；ABI claim 需独立决策 |
| 全部 target 同时打开 ContextRead | 非均匀 capability 未设计；违反 fail-closed |

## 参考

- `docs/specs/semantic-program-wire.md` § Principal valueBytes
- `docs/specs/type-effect-system.md` Principal 不透明身份
- `docs/specs/semantic-core.md` Invocation context / valueBytes
- `ProofForgeV2/Source/ContextCommitSurfaceV1.lean`
- `ProofForgeV2/Semantic/RequirementIdsV1.lean`（`context.caller`）
- `ProofForgeV2/Targets/Evm/LowerSemanticV1.lean` ContextRead fail-closed 注释
- `docs/research/17-openzeppelin-ethereum-coverage-audit.md` §7.1 EVM address/caller
- ADR-0003（target 选择物化）、ADR-0004（语义 Core 与 Plan 分离）、ADR-0005（exact capability）
