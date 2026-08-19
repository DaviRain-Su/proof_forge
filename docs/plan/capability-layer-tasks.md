---
id: PLAN-CAP-LAYER-TASKS
title: 十三 target 同一能力层 — 任务拆分
status: draft
owner: engineering
updated: 2026-08-19
normative: false
---

# 十三 target 同一能力层：任务拆分

> Engineering tasks only. **Not** `docs/04-task-breakdown.md` formal
> `TASK-*`. Do not mark TST/EV done. Design:
> [`capability-layer-parity.md`](capability-layer-parity.md).
> Verify with focused `lake env lean <suite>`, never
> `lake build proof_forge_next_tests_shard_*`.

Shared-core stays serial. Target leaves may run in parallel when
allowlists do not overlap. Skip a row rather than invent a host.

## Wave 0 — entry (this change)

| ID | Status | Objective | Allowlist | Verify |
|---|---|---|---|---|
| **CAP-0** | **this PR** | Point live entry at the design + this breakdown | `docs/index.md` · `AGENTS.md` · `RECOVERY.md` · `docs/document-status.md` · `docs/engineering-backlog.md` · `docs/research/README.md` · `docs/research/28-project-wide-honesty-audit.md` · `.grok/next-wave-queue.md` | `just docs-check` |

## Wave 1 — product decisions（**已全部拍板：2026-08-16 owner 决定全开**）

These are product decisions. Goal / Amp must **stop** and ask.

| ID | Decision | Decided | Unlocks |
|---|---|---|---|
| **CAP-D-SOL-TIME** | Solana `unixTimeSeconds` ← `Clock.unix_timestamp` (i64, stake-weighted)? | **yes（2026-08-16）** | CAP-2 |
| **CAP-D-TON-SHA** | Lift TON feature freeze for honest stdlib sha256 (not `string_hash`)? | **yes（2026-08-16；仅解冻 sha256 一项，不整体解冻 TON） ** | CAP-5 |
| **CAP-D-SOR-LEDGER** | Allow S0 Plan to emit `env.ledger()` / `env.crypto.sha256` without Wasm Finalize? | **yes（2026-08-16）** | CAP-3 / CAP-4 |
| **CAP-D-ICP-PRINCIPAL** | ICP caller valueBytes = ADR-0025-class `u32le(len)‖principal`? | **yes（2026-08-16）** | CAP-1b |

四项决策均只授权「绑定真实 host 或 named fail-closed」，不发明伪能力、不改 catalog、
不扩 accepted PRD、不关 formal TASK/TST。CAP-2 / CAP-1b / CAP-3 / CAP-4 / CAP-5 现为可编码行。

## Wave 1b — XRPL host-key decisions（ADR-0052；**不开叶**）

第 13 个 materializer 的 catalog 键。只冻符号或 keep-FC。**不要**发明
CAP-7 / CAP-8 / CAP-9。owner 未拍 TIME/CALLER **yes** 之前禁止 Lower/Emit。

| ID | Decision | Decided | Unlocks |
|---|---|---|---|
| **CAP-D-XRPL-TIME** | `unixTimeSeconds` ← `get_parent_ledger_time` + `946684800`（Ripple Time→Unix）？ | **proposed / awaiting owner**（符号已冻；叶仍 FC） | 另批 leaf ID（yes 之后） |
| **CAP-D-XRPL-CALLER** | `caller` ← `get_current_contract_call().get_account()`（20B AccountID；ADR-0025-class `u32le(20)‖bytes`；仅 entry）？ | **proposed / awaiting owner**（符号已冻；叶仍 FC） | 另批 leaf ID（yes 之后） |
| **CAP-D-XRPL-SHA** | 有无诚实 `pf.crypto.sha256` host？ | **keep-FC（2026-08-17）**：仅 `compute_sha512_half`；不得冒充 sha256 | 无 |

## Wave 2 — state-class deepen (existing targets)

| ID | Pri | Objective | Files (expected) | Done when | Not |
|---|---|---|---|---|---|
| **CAP-1a** | P1 | **done 2026-08-15**: ICP `context.unixTimeSeconds` → `ic0.time` ns÷10⁹ on init/entry/query | `Targets/Icp/{Lower,Emit,Validate}*` · `IcpPlanV1` · `Targets.lean` needle · matrix §1d | Plan/IR/WAT pin + named diagnostic gone for this key only | PocketIC formal; blockHeight |
| **CAP-1b** | P1 | **done 2026-08-16**: ICP `context.caller` → `ic0.msg_caller_size/copy`（ADR-0025-class `u32le(len)‖bytes`，max 29；9-leaf len+8×u64；Principal identity storage/param/`==`/`!=` S1-shaped；init/entry admit、query/view 名义 FC `ICP-VIEW-CALLER`；Principal result/`self` 仍 FC） | `Targets/Icp/{LowerSemantic,ValidatePlan,EmitIR}V1` + façade · `IcpPlanV1` pins · N5 caller matrix | S1-shaped pin; view policy named | mapping Principal→account-id globally |
| **CAP-2** | P1 | **done 2026-08-16**: Solana `unixTimeSeconds` → `Clock.unix_timestamp`（i64@32 raw bits as u64，同 `sol_get_clock_sysvar` 路径；escrow composite 仍 FC） | `Targets/Solana/{LowerSemantic,CpiDerive,EmitIR,EmitSbpfAsm,PlanSchema,ValidatePlan}V1` · `SolanaCpiDeriveV1`/`SolanaPlanV1`/`SolanaCpiPfAssetsV1` pins · N5 admit · Mollusk `unix_time_seconds.rs` 4/4 | product profile admits; `unixTime` FC pin removed; `blockHeight` unchanged | Clock.slot alias; formal D5 |
| **CAP-3** | P2 | **done 2026-08-16**: Soroban S0 `unixTimeSeconds`/`blockHeight` → `env.ledger().timestamp()`/`u64::from(env.ledger().sequence())`（init/entry/view；attachedValue/chainId/caller/self 仍名义 FC） | `Targets/Soroban/{LowerSemantic,ValidatePlan,EmitIR}V1` + façade · `SorobanPlanV1` pins · N5 admit | `.rs` contains ledger reads; Finalize still zero-tool | SOR-1 Wasm / auth / TTL |
| **CAP-4** | P2 | **done 2026-08-16**: Soroban S0 `pf.crypto.sha256` UInt256→UInt256 → `env.crypto().sha256`（32-byte LE wire image = 4×u64 LE limbs；UInt256 仅 sha256 plumbing，state/param/result/arith 仍 FC；keccak256/siblings 名义 FC） | `Targets/Soroban/{LowerSemantic,ValidatePlan,EmitIR}V1` · `SorobanPlanV1` pins | exact QN lowered; other `pf.crypto.*` still named FC | Bytes ABI; stellar-cli |
| **CAP-5** | P2 | **done 2026-08-16**: TON exact `pf.crypto.sha256` → Tolk `slice.bitsHash()`（TVM `SHA256U`）over Semantic UInt256 LE image；`string_hash`/`HASHCU`/`HASHBU` 负针 pin；keccak/siblings 名义 FC；freeze 其余不变 | `Targets/Ton/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR}V1` · `TonPlanV1` pins | stdlib sha256 (document which); `string_hash` still not used | keccak; pf.assets; unfreeze whole TON |
| **CAP-6** | P3 | **done 2026-08-15** (unixTime leaf): N5 matrix admits ICP; decline list +Quint/Soroban. Focused `/tmp/run_Cap6UnixTimeMatrix.lean` | `Tests/Materialization/Targets.lean` | focused driver, not shard / full Targets.run | opening `Tests.lean` in LSP |

## Wave 3 — explicitly out

| ID | Why skip |
|---|---|
| **CAP-X-NEW-TARGET** | No cairo/risc0/sp1/Move/Bitcoin this wave (RPT-025/026) |
| **CAP-X-MERKLE** | ~~EXT-CRYPTO auto-open rejected~~ → **done 2026-08-19 via Wave 5**（owner 拍板后开为命名切片；EVM-only `merkleVerifyKeccak256`） |
| **CAP-X-CW-SHA** | CosmWasm has no sha256 host — keep F |
| **CAP-X-XRPL-SHA** | XRPL has no sha256 host — only `compute_sha512_half` (ADR-0052) |
| **CAP-X-ICP-HEIGHT** | ICP has no block-height API — keep F |
| **CAP-X-CIRCUIT** | Noir/OpenVM/Psy chain-anchored keys stay F |
| **CAP-X-FORMAL** | [Goal ↛ formal](../../.agents/notes/implemented/process/2026-08-15-goal-must-not-close-formal.md) |

## Wave 4 — CAP-X-BYTES：`pf.crypto.sha256Bytes` 共享核 + 五叶（active，2026-08-19 冻结）

设计冻结：新 QN **`pf.crypto.sha256Bytes(Bytes N) -> UInt256`**（`N ≤ maxTypeLengthV1`；
result 沿用 UInt256 digest 惯例；TON/Soroban 继续 LE image 纪律）。不开同 QN 多 arity、
不开流式（CRYPTO-B2 永久 FC）、不开 Merkle。共享核只做「承认 Bytes 参数」：
TypeCheck/EffectCheck/Wire 均无需改动（expected-type 钉 result；`externalCallSync`
纪律与既有 sha256 相同，view 仍关；Bytes 参数 serializability 在 Wire 已闭合）；
Reference 走 generic ExternalCall response cursor，不在 L1 机内算 hash。
无 host 的八个 target（Noir/Psy/Aleo/Quint/CosmWasm/ICP/OpenVM/XRPL）保持引 QN 的命名 FC。

| ID | Pri | Objective | Files (expected) | Done when | Not |
|---|---|---|---|---|---|
| **CAP-X-BYTES-CORE** | P1 | **done 2026-08-19**：共享核承认新 QN：`Core/RequirementIdsV1` 新 QN 常量 + `isPfCryptoHostSyscallQnV1` 纳入；`Semantic/NormalizeV1` 表达式 call 臂对 exact QN 放行 anonymous `Bytes N` 参数（其余 QN 仍 anonymous-integer/Principal 纪律）；`Typed/RequirementsInferV1` 经共享 predicate 自动走 env-read 纪律 | `Core/RequirementIdsV1.lean` · `Semantic/NormalizeV1.lean` · `Tests/Semantic/NormalizeSha256BytesV1.lean` | Loader→CheckV1→Normalize 正/负 + Bytes 4096/4097 边界（4097 在 source type surface 即 PF-SRC-INVALID）+ 老 `pf.crypto.sha256` UInt256 回归全过；Reference 走 generic response cursor（不算 hash）pin；八 target 命名 FC 不动 | 不改 TypeCheck/EffectCheck/Wire/Reference；不钉 UInt256 result（target-owned exact ABI）；statement 位置仍 generic FC |
| **CAP-X-BYTES-EVM** | P2 | **done 2026-08-19**：EVM `sha256BytesPrecompile`，N ≤ 64 → precompile `0x02` over memory（逐叶 `mstore(i, shl(248, …))`，inlen=N，digest 在 ceil32(N)×32）；wire tag 24 | `Targets/Evm/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR}V1.lean` · `EvmSmoke.lean`/`EvmPlanSchemaV1.lean` | focused suite 正/负过 | generic AddressBearing CALL；B-CALL-SEM |
| **CAP-X-BYTES-SOL** | P2 | **done 2026-08-19**：Solana `sha256BytesHost`（statement tag 17）→ IR `sha256BytesSyscall` → SBPF 单 slice `sol_sha256`（N ≤ 64；`CpiDeriveV1` crypto 判定改委托共享 predicate） | `Targets/Solana/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR,EmitSbpfAsm,ProductSynthesize,CpiDerive}V1.lean` · `SolanaPlanV1.lean` | focused suite 过 | CPI 面；Mollusk 独立门（本波未加 fixture） |
| **CAP-X-BYTES-NEAR** | P2 | **done 2026-08-19**：NEAR `sha256BytesHost`（statement tag 16）→ host `sha256(N, ptr, register)` over register bytes（N ≤ 64）；HostModel 同现叶 `modelError`（不执行 host syscall） | `Targets/Near/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR}V1.lean` · `NearHostModel.lean` | focused suite 过 | view-caller 等既有 FC 边界不变 |
| **CAP-X-BYTES-TON** | P2 | **done 2026-08-19**：TON `Expr.sha256Bytes`（Expr tag 58）→ 独立 `beginCell().storeUint(b,8)×N.endCell().beginParse().bitsHash()`（N ≤ 127，单 cell 1023-bit 容量；`string_hash`/`HASHCU`/`HASHBU` 负针同覆盖新叶） | `Targets/Ton/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR}V1.lean` · `TonPlanV1.lean` | focused suite 过 | keccak/其余 freeze 不变 |
| **CAP-X-BYTES-SOR** | P2 | **done 2026-08-19**：Soroban S0 `Sha256BytesSite`/`sha256BytesLimb`（ctor tag 14）→ `Bytes::from_array` + `env.crypto().sha256`（N 1..8，S0 flatten 上限）；Finalize 仍 zero-tool | `Targets/Soroban/{LowerSemantic,ValidatePlan,EmitIR,PlanSchema}V1.lean` · `SorobanPlanV1.lean` | `.rs` 含 Bytes sha256；Finalize 仍 zero-tool | SOR-1 Wasm / stellar-cli |

## Wave 5 — CAP-X-MERKLE：`pf.crypto.merkleVerifyKeccak256` EVM-only（active，2026-08-19 owner 拍板）

设计冻结（owner 在三选一产品问题上的拍板，默认值经确认）：

- **QN**：`pf.crypto.merkleVerifyKeccak256` 单 QN。选 keccak 因为 EVM 原生 opcode
  （无 precompile CALL）且对齐 OpenZeppelin `MerkleProof` 惯例；sha256 变体属未来独立
  QN/叶（RPT-027 split-QN 纪律，禁 overload/多 arity）。
- **ABI**：`(root : UInt256, leaf : UInt256, s0 … s_{D-1} : UInt256) -> Bool`，
  D ∈ 1..8 个定深 UInt256 sibling。不碰 Array-of-Bytes / Array 参数（第一刀零新类型）；
  D=0、D>8、非 UInt256 参数、非 Bool result 一律 named FC。
- **配对哈希**：OpenZeppelin 式 sorted-pair（commutative：每层 `keccak256(min‖max)`）；
  positional/indexed proof 属未来独立 QN。
- **结果**：Bool（verify 语义，不 revert）。
- **范围**：EVM-only；其余十二 target 命名 FC（引 QN）。明确**不**声称 ICS-23/IBC/桥/NS-2、
  不声称 formal/Anvil differential。
- **共享核**：`RequirementIdsV1` 新 QN 常量 + 纳入 `isPfCryptoHostSyscallQnV1`
  （merkle verify 是纯计算，不得贡献 `effect.synchronous-call`）；Normalize **零改动**
  （全 UInt256 参数过既有 anonymous-integer 门、Bool result 过既有 serializable 门）；
  Reference 走 generic response cursor。
- 记录在案的既有裂缝（**2026-08-19 诚实边界波已修**）：`ecdsaRecoverSecp256k1` 已纳入
  host-syscall predicate（owner 接受既有程序 requirement 集 cut over）。

| ID | Pri | Objective | Files (expected) | Done when | Not |
|---|---|---|---|---|---|
| **CAP-X-MERKLE-CORE** | P1 | **done 2026-08-19**：`RequirementIdsV1` 新 QN + predicate 纳入；聚焦套件 `Tests/Semantic/NormalizeMerkleVerifyV1`：Normalize 放行（全 UInt256、Bool result）、predicate 成员、`value.bool`-only requirements（无 sync-call/rollback 贡献）、view PF-EFFECT-001、Reference generic cursor、近似 QN FC、statement 位 void op 纪律 | `Core/RequirementIdsV1.lean` · `Tests/Semantic/NormalizeMerkleVerifyV1.lean` | 套件绿 + 反剧场验证（摘掉 predicate 即红） | 不改 Normalize/TypeCheck/EffectCheck/Wire/Reference |
| **CAP-X-MERKLE-EVM** | P1 | **done 2026-08-19**：EVM `merkleVerifyKeccak256` 叶（statement tag 25）：exact ABI（arity 3..10 = 2+D、全 anonymous UInt256、Bool result）、view/constructor 禁、Yul unrolled sorted-pair（`lt`+算术 mux → `mstore(0,min)`/`mstore(32,max)`/`keccak256(0,64)`/D 层）、`eq(mload(64), root)` 进 Bool、false-not-revert | `Targets/Evm/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR}V1.lean` · `EvmSmoke.lean`/`EvmPlanSchemaV1.lean` | 正/负矩阵绿：D=1/D=8 正例；arity<3、D>8、UInt64 参数、UInt64 result、view、近似 QN 负例；老 sha256/keccak/ecdsa/sha256Bytes 叶回归 | 不走 AddressBearing CALL；不碰 generic call 面；B-CALL-SEM |

## Suggested serial order（既有 CAP-D-* 已于 2026-08-16 全开；XRPL 仅 ADR）

```text
CAP-0 (docs, done)
  → CAP-1a (ICP time, done 2026-08-15)
  → CAP-6 needles (done 2026-08-15)
  → CAP-D-* decided yes (2026-08-16)
      → CAP-2 → CAP-1b → CAP-3 → CAP-4 → CAP-5
        (disjoint allowlists, parallel worktree OK; shared Targets.lean/docs serial)
  → CAP-D-XRPL-* (ADR-0052 proposed; SHA keep-FC; TIME/CALLER await owner)
  → CAP-X-BYTES-CORE (done 2026-08-19)
      → CAP-X-BYTES-{EVM,SOL,NEAR,TON,SOR} (done 2026-08-19)
  → CAP-X-MERKLE-CORE → CAP-X-MERKLE-EVM (done 2026-08-19；EVM-only)
  → stop（XRPL 叶另批；不要发明 CAP-7/8/9）
```

One local commit per ID. Touch `ProofForgeV2/**` → `just sbom-package-files-refresh`.
Docs → `just docs-check`. Do not push unless asked.
