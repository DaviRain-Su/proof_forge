---
id: PLAN-CAP-LAYER-PARITY
title: 十三 target 同一能力层 — 设计
status: draft
owner: engineering
updated: 2026-08-19
normative: false
---

# 十三 target 同一能力层

> Engineering design only. Does **not** add a TargetId, expand accepted
> PRD Phase 1, close formal TASK/TST, open SOR-1 Wasm, or auto-open
> Merkle / Bytes / extra signatures.
> Authority: ADR-0031 · ADR-0036 · RPT-020/027/028 ·
> [`.agents/notes/`](../../.agents/notes/README.md).
> Executable rows: [`capability-layer-tasks.md`](capability-layer-tasks.md).

## 1. What “same layer” is

The thirteen materializers already share one product path
(`SemanticProgramV1` → capability Plan). They do **not** share hosts,
failure models, or maturity labels. Forcing one `GenericWasmHostPlan` or
one `ZkPlan` is the failure mode ADR-0036 / RPT-025 forbid.

**Same layer** means one catalog row, thirteen honest dispositions:

```text
catalog QN / ContextRead key
  → each target: named host binding  OR  named no-host fail-closed
  → circuit class stays FC on chain-anchored values
  → no weak primitive masquerading as the catalog item
```

That is already the SYS-CAP / S5 discipline. The remaining work is to
finish the matrix on **state-class hosts that exist but are unbound**,
not to mint cairo / risc0 / sp1 or flatten TON `string_hash` into
`pf.crypto.sha256`.

## 2. Two families, one catalog

| Family | Targets | What “parity” may do | What it must not do |
|---|---|---|---|
| State-class | EVM, Solana, NEAR, CosmWasm, TON, Soroban, ICP | Bind a real opcode / host / sysvar / env | Invent a host; treat axis labels as delivered capability |
| Circuit / model | Noir, OpenVM, Psy, Aleo (proof), Quint | Named no-host FC; optional later witness/oracle ADR | Claim the hash “happened on chain” |

Aleo finalize can read chain state; that is a **per-key** decision, not a
blanket open. Psy `hash*` / keccak gadgets stay off the S5 catalog
([rejected note](../../.agents/notes/rejected/architecture/2026-08-15-ext-crypto-auto-open.md)).

## 3. Current layer (engineering, 2026-08-15)

Legend: **A** = admitted with named host · **F** = named fail-closed ·
**P** = partial (view / profile / stub) · **—** = type-closure rejects
before the Plan key.

### 3.1 L1 ContextRead

| Key | EVM | Solana | NEAR | CW | TON | Soroban | ICP | Noir/OpenVM/Psy/Aleo/Quint |
|---|---|---|---|---|---|---|---|---|
| `caller` | A | P (CPI signer) | P (init/entry) | P (exec/init) | — / F | — / F | **P**（CAP-1b 2026-08-16：`ic0.msg_caller_*` init/entry；view 名义 FC） | F |
| `blockHeight` | A | A (`Clock.slot`) | A | A | F (no honest height) | **A**（CAP-3 2026-08-16：`env.ledger().sequence()` u32→u64） | F (no API) | F |
| `unixTimeSeconds` | A | **A**（CAP-2 2026-08-16：`Clock.unix_timestamp` i64@32 raw bits） | A | A | A | **A**（CAP-3 2026-08-16：`env.ledger().timestamp()`） | **A** `ic0.time` ns÷10⁹ | F |
| `chainId` | A | F | A | F (String, no silent hash) | F | F (`network id` exists) | F | F |
| `attachedValue` | A | F | P (init/entry) | P (exec/init) | F | F | F | F |
| `self` | A | F | A | A | F | — / F | F | F |

### 3.2 L2 / `pf.crypto` (UInt256 word ABI only)

| QN | EVM | Solana | NEAR | CW | TON | Soroban | ICP | circuit / Quint |
|---|---|---|---|---|---|---|---|---|
| `sha256` | A `0x02` | A `sol_sha256` | A host | F (no host) | **A**（CAP-5 2026-08-16：Tolk `slice.bitsHash()`/TVM `SHA256U` over LE image；`string_hash` 永不发射） | **A**（CAP-4 2026-08-16：`env.crypto().sha256`，UInt256 LE-limb plumbing-only；keccak/siblings 仍名义 FC） | F (no direct) | F |
| `keccak256` | A opcode | A `sol_keccak256` | A host | F | F (no keccak) | F | F | F |
| `ecdsaRecoverSecp256k1` | A `0x01` | F | F | F | F | F | F | F |
| `sha256Bytes`（Bytes N→UInt256） | **A**（N≤64，`0x02` over memory） | **A**（N≤64，`sol_sha256` 单 slice） | **A**（N≤64，host register bytes） | F (no host) | **A**（N≤127，`SHA256U` 单 cell bits） | **A**（N≤8，`env.crypto().sha256` S0 Bytes） | F (no direct) | F |
| `merkleVerifyKeccak256`（UInt256×(2+D)→Bool） | **A**（D≤8，sorted-pair keccak 链，false-not-revert） | F (no host shape) | F | F | F | F | F | F |
| Bytes / Merkle / other verify | F | F | F | F | F | F | F | F |

`merkleVerifyKeccak256` QN 已于 2026-08-19 由 owner 拍板冻结并落地 EVM 叶
（CAP-X-MERKLE；见 [`capability-layer-tasks.md`](capability-layer-tasks.md) Wave 5）：
keccak 原生 opcode + OpenZeppelin sorted-pair 惯例；定深 UInt256 sibling（D≤8）；
Bool verify 结果（false，不 revert）；不声称 ICS-23/IBC/NS-2。无 host target 永 F。

`sha256Bytes` QN 已于 2026-08-19 冻结并落地（CAP-X-BYTES，共享核 + 五叶；
见 [`capability-layer-tasks.md`](capability-layer-tasks.md) Wave 4）。N 上限为
各叶诚实预算（EVM/Solana/NEAR 64、TON 单 cell 127、Soroban S0 flatten 8），
超限 named FC。无 host target（CW / ICP / XRPL / circuit class）永 F。

### 3.3 What is already “same layer”

Named admit-or-FC for the six ContextRead keys and the three crypto QNs
is largely **done** on all thirteen implemented targets (XRPL is the 13th
and stays named F in this layer; not an extra admitted column — §3.4).
The holes are not missing diagnostics. They are **unbound honest hosts**
on under-served state-class leaves.

### 3.4 XRPL (13th materializer; named-FC)

XRPL 已在 registry（ADR-0049/0050）。**尚未**加入本层的 admitted 列。
ADR-0052 冻 TIME/CALLER 符号并拍 SHA keep-FC；六键 + `sha256` **全 F**，
直到对应 `CAP-D-XRPL-*` owner yes + 另批 leaf。不把 XRPL 塞进上表当 A。

## 4. Do not add these targets

| Candidate | Why not this wave |
|---|---|
| cairo / risc0 / sp1 | RPT-026 design only; would steal the EVM formal + 13-target honesty budget |
| aptos / sui | product `wontfix` |
| Bitcoin Script / BitVM | UTXO predicate ≠ account Semantic (RPT-025 档 D) |
| Fuel, Cardano, Stylus-as-EVM, ink! | no ADR, no catalog row |

XRPL is already the 13th materializer; joining this layer still needs
CAP-D yes + a later leaf ID (ADR-0052). New TargetIds are out of scope.
Joining the layer means bring an existing implemented leaf onto the catalog,
not auto-admit XRPL because it is already registered.

## 5. Priority to raise (existing leaves only)

Order is host honesty × product freeze × file isolation.

| Pri | Move | Why this one | Blocked by |
|---|---|---|---|
| **P0** | Keep the matrix honest; no new TargetId | RPT-028 / empty Goal | — |
| **P1a** | ICP `unixTimeSeconds` → `ic0.time` ns÷10⁹ | Host exists; S0 already emits Wasm; named FC today is a gap, not a freeze | none (Plan/IR/WAT leaf) |
| **P1b** | ICP `caller` → `msg_caller` | Same as S1 on NEAR/CW; view-safety must be named | ~~Principal wire vs canister principal bytes~~ **decided 2026-08-16**（CAP-D-ICP-PRINCIPAL yes：ADR-0025-class `u32le(len)‖principal`） |
| **P1c** | Solana `unixTimeSeconds` → `Clock.unix_timestamp` | Sysvar already used for `blockHeight`; last S2 hole on the strongest SVM leaf | ~~product: stake-weighted i64 vs UInt64~~ **decided 2026-08-16**（CAP-D-SOL-TIME yes） |
| **P2a** | Soroban `unixTimeSeconds` / `blockHeight` as **source** `env.ledger()` | Host exists in the dialect S0 already emits | [S0 ≠ Wasm](../../.agents/notes/implemented/architecture/2026-08-15-soroban-s0-not-wasm.md): Plan-only, no Finalize/tool；**decided 2026-08-16**（CAP-D-SOR-LEDGER yes，仍 Plan-only） |
| **P2b** | Soroban `pf.crypto.sha256` as source `env.crypto.sha256` | Completes S5 on the one Wasm host that has the API | same S0 ceiling; no stellar-cli；**decided 2026-08-16**（同上） |
| **P2c** | TON SHA-256 via honest stdlib (not `string_hash`) | RPT-020 lists a real sha256; current FC is correct vs `string_hash` | ~~TON feature freeze~~ **decided 2026-08-16**（CAP-D-TON-SHA yes：仅解冻 sha256 一项；pf.assets/其余 freeze 不变） |
| **P3** | stop | Merkle, Bytes ABI, ed25519, Cairo, prove, SOR-1 Wasm | Agent Notes + Track C |

ICP has **no** block-height API. That cell stays F. CosmWasm has **no**
sha256 host. That cell stays F. XRPL has **no** sha256 host
(`compute_sha512_half` only; ADR-0052). Circuit class stays F.

## 6. Non-goals

- Same deployable / maturity / runtime gate on all thirteen
- `B-CALL-SEM` true callee addresses
- TypeKey unused / rank structure gate
- Goal flipping `TASK-*` / `TST-*`
- Anvil lossless OutcomeWire
- Quiet accepted-PRD expansion

## 7. How a slice proves it belongs on the layer

1. Catalog QN / key already exists (no new shared-core type).
2. Target either lowers to a **named** host or keeps a **named** no-host
   diagnostic that cites the QN.
3. Focused `lake env lean` on that target suite; no shard exe
   ([process note](../../.agents/notes/implemented/process/2026-08-15-focused-lean-verification.md)).
4. Matrix / backlog one honest line. No formal status edit.
