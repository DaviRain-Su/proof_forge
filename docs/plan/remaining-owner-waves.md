---
id: PLAN-REMAINING-OWNER-WAVES
title: Remaining owner-decision waves (post daily-engineering drain)
status: draft
owner: engineering
updated: 2026-08-21
normative: false
---

# Remaining owner-decision waves

Sequencing plan only. ADR-0036 / ADR-0053 were accepted by owner directive on
2026-08-21. This plan **does not** accept ADR-0051 / 0052,
open XRPL TIME/CALLER leaves, mark formal TASK/TST done, or reopen
Goal drain. Recommended defaults are **recommendations**; each wave
starts only after the owner pick for that wave (or an explicit
override).

Live checkpoint this plan assumes (2026-08-21): Goal queue empty;
CAP-1a…5 / CAP-X-BYTES / CAP-X-MERKLE / honesty-boundary wave done;
registry **13 implemented + 0 design-only / 17 resolver rows**;
formal D1–D4 = **0/27**; ADR-0053 Wave 1–4 engineering DoD is green;
ADR-0036 / 0053 acceptance records bind review commit
`239e335ac4272f7b292eb87c913e46c8c805c0b9` with no open findings.

Authorities this file does not replace: accepted ADR → PRD →
architecture → SPEC → code fact. Conflict: those win.

Companion inventories (do not copy):

- B-CALL-SEM sub-decisions: `.agents/notes/proposed/architecture/2026-08-16-b-call-sem-decision-inventory.md`
- EVM address binding: [`evm-call-addr-gap.md`](evm-call-addr-gap.md)
- D3-E8 phases: [`d3-e8-minimum-evidence.md`](d3-e8-minimum-evidence.md)
- Soroban S1 holes: [`soroban-s1-wasm-finalize-gap.md`](soroban-s1-wasm-finalize-gap.md)
- Honesty audit: [`../research/28-project-wide-honesty-audit.md`](../research/28-project-wide-honesty-audit.md)

---

## Wave 0 — paper close (docs / status)

No product-behavior change except honesty of status fields.

| ID | Recommended pick | Follow-on | Must not |
|---|---|---|---|
| **ADR-0051** | Accept as written | One SPEC-SEM-001 text revision (`ExternalResponseV1.returnValue?`; schedule stays void). No code. | Close TST-SEM-002; decide EVM address binding |
| **ADR-0036** | **Accepted 2026-08-21** with live count **13+0** | accepted PRD stays four targets; formal lighthouse stays EVM-first | Expand accepted PRD; mark D1–D4 done |
| **ADR-0053** | **Accepted 2026-08-21**；Wave 1–4 engineering boundary 已落地 | EVM static identity 不冒充 code-at-address；Solana/CW identity 与 unsupported Solana shapes FC | Read runtime green as C-3/formal/release; close all B-CALL-SEM |
| **ADR-0052** | Accept as written | SHA keep-FC stays; TIME/CALLER symbols frozen | Open Plan/IR/Emit leaves (Wave 6) |
| **DOC-JUST-CONTROL** | Keep recipes absent | Current “不可执行” honesty stays | Fake `just governance-check` / `release-check` |
| **Hash endian** (`sha256*` UInt256) | Document target-local integer interpretation | EVM BE-word vs Solana/NEAR LE-image pins stay | Flip emitters in this wave |

---

## Wave 1 — B-CALL-SEM / CALL-BIND

Owner pick (2026-08-20): compile-time versioned opt-in table
(`proof-forge.call-bind.v1` / `--bindings`). Not NetworkProfile / Anvil
receipt. EVM = pre-placed 20-byte only (no CREATE/CREATE2). Empty-account
void CALL is Wave 2a (done: `extcodesize` fail closed). `schedule` stays same-tx fire-and-forget.
Bool/Int/Bytes returndata stay fail closed. `pf.crypto.*` / `pf.assets`
never consult the table.

**Wave 1: parse only (done).** CLI accepts `--bindings`; table decodes.

**Wave 2 (done):** with `--bindings`, generic `call`/`schedule`
on evm/solana/cosmwasm without a matching row fails closed. Table is
explicit (never ambient). The EVM exact endpoint is carried by its Plan and
changes Plan digest / EngineeringBuildIdentity / engineering OutputSet identity;
the optional row `identity` digests remain unverified metadata.

**Wave 2a (done):** generic void CALL reverts when `extcodesize==0`.
`schedule` stays fire-and-forget; result-bearing CALL still uses
`returndatasize`.

**Wave 2b (done):** Solana nonempty `accounts` pack
compile-time AccountMetas (≤8).

**Wave 2c (done):** successful `build` reports
program-level `callScheduleResidual`. No generic call → `null`.
EVM/CW covered rows → `null`. Target `inspect <target>` stays the
closed kind table.

**Wave 3 (engineering done 2026-08-21):** the Solana supported subset
(state-bearing, synchronous generic void CALL, one distinct callee,
1..8 non-alias account rows, no frozen CPI sites) projects exact bound
accounts + executable callee program into the outer AccountInfo list.
Plan / IDL / IR / emitter / client verifier agree on the same role order
and privileges; product-built caller + callee pass an 8-test Mollusk
positive/negative/rollback suite. The supported program residual is
`null`. Empty-state / schedule / empty-row / multi-callee / mixed-site /
generic result-bearing forms remain FC or retain
`callee-identity-outer-account-open`.

**Wave 4 (engineering done 2026-08-21):** EVM optional identity is no longer
parse-only. An identity-bearing row requires EVM-only canonical
`proof-forge.call-bind-evidence.v1` / `--binding-evidence`; each row maps exact
callee/address to a deployable EVM engineering output directory. Product
validation rechecks sidecars, per-file SHA-256, exact disk closure and
`outputSetDigest`, then compares optional source/semantic and mandatory raw
published `.bin` SHA-256. The expected identity-table digest enters EVM Plan /
planDigest / caller OutputSet provenance; no identity keeps historical Plan
bytes. This is static artifact/address attestation, not deployment receipt /
RPC / code-at-address validation.

Open remainder: resolver support keys must not be read as
“cross-platform call done.” EVM on-chain code-at-address, Solana/CosmWasm
identity, target inspect residual, EVM/CW no-table stubs and all unsupported
target families retain their documented boundaries.

### Decisions (inventory 2026-08-16 + evm-call-addr-gap §3)

Recommended conservative honesty:

1. **EVM callee binding** — ADR-0053 已选择并交付 compile-time versioned table；有表用 exact pre-placed 20-byte address，endpoint 进入 EVM Plan/digest/build identity；无表继续 historical Plan tags 与 hashed-QN stub，有表缺行 FC。Wave 4 已将 optional identity 对到完整重验的 static EVM OutputSet 和 raw `.bin` digest。Product `build` 仍不消费 Anvil placement，且未做 receipt/RPC/code-at-address join；CREATE/CREATE2/NetworkProfile 不混入。Empty-account void CALL 由 Wave 2a `extcodesize` fail closed。
2. **EVM `schedule` spelling** — same-tx fire-and-forget must not keep advertising `effect.asynchronous-workflow` without a distinct caveat.
3. **EVM returndata residual** — Bool / Int / Bytes stay FC.
4. **Solana product CPI** — Wave 3 closes the exact outer AccountInfo join only for its stated product subset; async, generic result-bearing, empty-row/state, multi-callee, mixed frozen-site, and Solana identity verification stay FC/open.
5. **CosmWasm** — ADR-0053 已令有表的 `SubMsg.contract_addr` 使用 exact row；无表 QN stub 不变。bech32 与 CosmWasm identity verification 仍 open。
6. **Noir** — keep witness-binding only; result-bearing FC until a response-witness contract exists.
7. **NEAR / TON / ICP / Psy / Aleo / Soroban / OpenVM / Quint** — keep current per-target honesty (no silent expansion).
8. **ADR-0029** portable branch stays proposed; accepting it does not close B-CALL-SEM.

`EVM-CALL-ADDR-PIN` already pins the hashed stub. That is **not** the binding.

### After the pick

ADR-0036 / 0053 approval record 已完成；当前进入 accepted four-target engineering DoD。
若后续扩大 call-bind，只能在「EVM deployment receipt / block / code-at-address evidence」
或已列 Solana unsupported shape 中经 owner 决策一次选一项；不得把 Wave 4 static
artifact evidence 写成链上 deployment join，也不能据支持子集声称 cross-platform
call complete。Does not close formal D2/D4 or C-3.

---

## Wave 2 — D3-E8 enforcement

Fail-closed honesty slice (2026-08-21) already shipped: parser retains the closed
wire whitelist, but every explicit request exits 2 before source open / resolver /
staging because no evaluator exists. Successful builds without the flag report
`minimumEvidenceEnforcement: unavailable-fail-closed` and null request/effective
grades. The flag still does **not** enter resolver / claim / manifest / exit 4.

Owner freeze (from the D3-E8 plan):

1. Profile defaults — per-`CodegenProfileId` `minimumEvidence`
2. Achieved grade — engineering resolver stays `specified` until formal `ProfileSupportIndex`
3. Failure mode — recommended **`PF-REQ-EVIDENCE` / exit 4** (never silent pass)
4. Manifest binding — `support.minimumEvidence` in Phase C, not A

Then Phase A (registry scaffold, no gate) → B (resolver observation) → C (enforce) → D (formal, out of daily engineering).

---

## Wave 3 — RES-1B real producers

Output published-bytes already enforced. Four unused flags
(`memory-bytes` / `processes` / `protocol-bytes` / `stderr-bytes`)
already fail closed at preflight (exit 2).

Remaining work is an **in-process** producer / containment design
(D3-E6: do not revive SafeOpen/supervisor). Formal NFR-008 stays
open. 59-code diagnostic table stays put until the design lands.

SYS-CAP-UNIFY residual (S5 / L2 official-program catalog) may run
in parallel once per-row L2 keys are picked; unknown keys stay FC.

---

## Wave 4 — B-COMMIT-ZK

Psy stays fail-closed under **ADR-0041** until all five checklist
items (algorithm ADR, public-input layout, wire rows, official
fixture, probe+differential). Felt identity passthrough is forbidden.
Noir Commit stays FC until separately authorized.

---

## Wave 5 — toolchain profiles

### SOR-1

Locked Wasm Finalize + auth/TTL Plan fields. S0 must not claim them.
SOR-1A honesty pins already landed and do **not** close SOR-1.

Gap plan requires a product decision on all four: (1) new opt-in
profile vs mutating S0 — do not overwrite `soroban-source-u64-v1`;
(2) real cargo guest tree vs single `.rs` recipe; (3) ambient cargo
vs isolated `LockedToolchainV1` (CosmWasm wat2wasm isolation is not
a fit for stellar-cli); (4) `soroban-sdk` / stellar-cli / rustc
versions. Auth fields must not be always-pass `require_auth`. Local
invoke is a second decision. Do not fold into ordinary `just ci`.

### QUINT-2

Locked typecheck + ITF/MBT/verify. Independent Tool Lock. Product
finalize must not silently invoke Quint / Apalache / TLC / Java.
No small-integer domain pretending to be UInt64.

---

## Wave 6 — XRPL TIME / CALLER leaves

Only after an **explicit yes per key** (ADR-0052 sections are
independent):

- **TIME** — `get_parent_ledger_time` (Ripple Time) → `(host as u64) + 946684800`; `host < 0` FC. Do not treat Ripple Time as Unix. Do not bind `get_ledger_sqn`.
- **CALLER** — ContractCall `get_account()` as `u32le(20)‖AccountID`; **entry only**; init/view FC. Not `get_contract_account` / `get_owner` / T4 Principal.
- **SHA** — already keep-FC. Do not alias `compute_sha512_half`.

Not AlphaNet / `ContractCreate` / official stdlib / accepted-PRD
expansion. XRPL-C AlphaNet is a separate later batch.

---

## Wave 7 — zkVM follow-ups

RPT-026: OpenVM O0/O1 MVP is done (no prove). Next:
discipline replay → pick **RISC0 or SP1** as `TGT-ZKVM-SECOND` →
`TGT-CAIRO-MVP` (or explicit reorder). Three independent
`TargetId`s; **no** shared `ZkPlan`. Role =
`verifiable-workload` or weaker. Each leaf needs its own
implementation ADR. Do not expand accepted PRD. Do not cut in
front of the EVM formal lighthouse.

---

## Wave 8 — Formal D1–D4 (separate axis)

Still **0/27**: `TASK-D1-01` blocked on qualification/host (not
daily coding); D1-02…D1-08, D2 7/7, D3 7/7, D4 5/5 pending.
Engineering LH-1…28 + Track F must **not** be marked formal-done.
C-3 / Anvil↛OutcomeWire lossless stays fail-closed.

Reopen only with: formal qualification funding, ADR-0051 accepted
(SPEC carrier for TST-SEM-002), and EVM-first (ADR-0036). Other
target greens do not substitute. Do not invent EV. Do not revive
Goal `NEXT=FORMAL_C3`.

Q-* (SBOM / eligible-host / clean-room / custody) rides
DOC-JUST-CONTROL — no recipe today.

---

## Documented residuals (not a coding wave)

| ID | Note |
|---|---|
| **EXT-CRYPTO leftover** | CRYPTO-D3 Solana ed25519 hangs on B-CALL-SEM; CRYPTO-D4 NEAR verify is a separate yes; Merkle variants each need their own QN; TON/CW signatures 另批; CRYPTO-B2 streaming stays FC |
| **NS-2** | IBC-flavored packet mailbox; language-gated; Merkle ≠ ICS-23 |
| **C-5** | ongoing Solana Mollusk fixture drip; no new fork |
| **NEAR GLIBC Tool Lock** | product decision, no option table |
| **wasmd rung-2** | only if product needs it; rung-1 closed |
| **INV-2 / ADR-0027 / 0034** | engineering done; do not supersede 0027 from EvenCounter positives |
| **ADR status batch** | most ADRs still `proposed`; ADR-0036 / 0053 已单独 accepted，do **not** silently include 0051/0052 in a batch |
| **EVM-BC-RESEARCH** | research-only pause; not Active |
| **EA-P1-5** | contributor incremental compile; not the external-author path |
| **TGT-MOVE-DOSSIER** | wontfix |
| **TGT-BTC-SCRIPT-PIN** | pin only; default wontfix-until independent predicate ADR |
| **EXT-ASSETS E4** | engineering dual-chain closed; leftover is formal/hermetic/mainnet |

`roadmap-t8.md`: no leftover T8/T9 slices (all `[merged]`).

---

## Slice discipline

Same as `engineering-backlog.md`: one shared-core cutover at a time;
leaf worktrees with zero file overlap; fail-the-test first; no new
formal `TASK-*`; `just sbom-package-files-refresh` after
`ProofForgeV2/**`; commit each slice; push Cursor Origin, not GitHub.
Do **not** relaunch retired Grok drains — live index [`.grok/README.md`](../../.grok/README.md).
