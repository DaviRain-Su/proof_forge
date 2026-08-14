# Next-wave drain queue (2026-08-12)

**Authority:** `docs/engineering-backlog.md` 推荐击杀顺序 · ADR-0036 · AGENTS Next task  
**Live status:** Goal-auto drain **empty**. Track A/B/F and later honesty pins are all `done`. **Do not** launch `/goal @.grok/goals/prompt-next-wave.md` or `/workflow next-wave-runner`. Formal `TASK-D2-07` / `TST-SEM-002/003` stay pending — not a coding slice. Next work = honesty docs / product decisions (see `docs/research/28-project-wide-honesty-audit.md`). Backlog wins on conflict.
**Mode:** Retired drain. Do **not** invent new LH/F rows.  
**Sole L1 step:** `SemanticProgramV1 → admitReferenceProgramSliceV1 → stepReferenceSliceV1`  
**Forbidden:** close formal TASK/TST/EV · Anvil lossless OutcomeWire (spec-FC) · invent TASK-* · push · `git add -A` · `git reset --hard` · supersede ADR-0027 · silent accepted-PRD expansion

## How Goal and workflow cooperate

| Surface | Command | What it does |
|---|---|---|
| **Goal (drain)** | `/goal @.grok/goals/prompt-next-wave.md --budget 8000000` | One long session: pick → implement/review/commit → next, until hard-stop |
| **Workflow (one slice)** | `/workflow next-wave-runner` | Select + implement + review + verify + **one** local commit |
| Resume after budget | same Goal `starting at <NEXT>` | Never restart from LH-1 |

Goal **should** call `next-wave-runner` for medium/large slices. Small doc-only rows may be done in-Goal. Workflows cannot nest; one fire = one slice.

## Track A — EVM formal lighthouse (serial; primary)

Engineering packaging toward TASK-D2-07 / TST-SEM-002/003 / C-3.  
**Never** mark those formal IDs `done`. Anvil ↛ OutcomeWire lossless stays fail-closed (`docs/specs/evm-outcome-adapter-v1.md`).

| id | status | objective |
|---|---|---|
| LH-1 | done | OutcomeWireV1 / `pf.reference-outcome.v1` (2026-08-12) |
| LH-2 | done | public `step` façade + EVM Outcome adapter; Anvil lossless FC |
| LH-3 | done | ArithOps OutcomeWire + digest-case close-case 硬门 (`sidecars=18`) |
| LH-4 | done | EventFlow Reference OutcomeWire mint + digest list + close-case join; keep Anvil↛wire FC (`sidecars=23`) |
| LH-5 | done | OwnableLike Reference OutcomeWire mint (caller context + assertionFailed); `sidecars=28` |
| LH-6 | done | Engineering Counter reference-trace pin in TST-SEM-002 *shape* (`Tests.Semantic.Sem002ShapeV1`); formal TASK/TST still pending |
| LH-7 | done | Engineering overflow/revert rollback pin in TST-SEM-003 *shape* (`Tests.Semantic.Sem003ShapeV1`); formal TASK/TST still pending |
| LH-8 | done | Sem003 fault + response-precedence OutcomeWire pin; allowlist only `Tests/Semantic/Sem003ShapeV1.lean`. Reviewer FIX P1 (`top-level main`) removed; `lake build proof_forge_next_fast_tests` exit 0. **Not** formal TST-SEM-003 |
| LH-9 | done | Sem002 external-response returned/reverted + context extra/dup + wrong-arity pin; allowlist only `Tests/Semantic/Sem002ShapeV1.lean`. **Not** formal TST-SEM-002 |
| LH-10 | done | Remaining standard revert codes via public `step` + OutcomeWire; allowlist only `Tests/Semantic/Sem003ShapeV1.lean`. Focused `#eval run` ok. **Not** formal TST-SEM-003 |
| LH-11 | done | Sem002 negatives: wrong kind / wrong arg type / response duplicate+reordered / noncanonical arg bytes; allowlist only `Tests/Semantic/Sem002ShapeV1.lean`. Focused `#eval run` ok. **Not** formal TST-SEM-002 |
| LH-12 | done | AGENTS.md honesty only; formal TASK/TST status unchanged |
| LH-13 | done | Sem003 trap + unconsumed response → unique invalidExternalResponse; allowlist only `Tests/Semantic/Sem003ShapeV1.lean`. Focused `#eval run` ok. **Not** formal TST-SEM-003 |
| LH-14 | done | backlog: mark LH-12 engineering done to match queue/`f48a90f79` |
| LH-15 | done | RECOVERY.md current-wave pointer: lighthouse drain through LH-12, formal still 0/27 |
| LH-16 | done | EvmOutcomeAdapterV1 in-process Outcome constructor → shared-status pin vs committed case `expectedSharedStatus` (28 digest-listed steps). Allowlist only `Tests/Materialization/EvmOutcomeAdapterV1.lean`. Focused `#eval run` ok (`dfbb4532a`). **Not** Anvil lossless / C-3 / formal |
| LH-17 | done | `MIGRATION_MATRIX.md` header date `2026-08-07` → `2026-08-13` + short increment index (`f093262eb`). Formal 0/27 unchanged |
| LH-18 | done | Retire `prompt-master-queue.md` as live Goal entry; point `docs/index.md` at next-wave queue (`ea0f19078`) |
| LH-19 | done | RECOVERY.md current-wave through LH-13 + `docs/document-status.md` `updated` date (`ed0ab1cd4`). Formal still 0/27 |
| LH-20 | done | Quint `context.attachedValue` Plan/materialize outside-Q0 pin; allowlist `Tests/Materialization/QuintSourceV1.lean` (`88da32e57`). **Not** formal |
| LH-21 | done | backlog INV-2 wave-3′ honesty + LH-16 record (`25520ecea`) |
| LH-22 | done | AGENTS.md Solana 23/414 marked Mollusk-only, not ordinary CI (`fdfb24dbe`). docs-check checkpoint phrases preserved |

| LH-23 | done | StepFacadeV1 pin façade==machine for declared revert + invalidExternalResponse + invalidInvocation (`885d2c048`). **Not** formal |
| LH-24 | done | OutcomeWireV1 decode negatives: truncated envelope + OOR outcome/revert tags (`9650c5358`). **Not** formal |
| LH-25 | done | `Examples/AttachedValueCheck.lean` comment honesty after S4 leaves (`10c280f07`) |
| LH-26 | done | blockHeight/chainId/self cross-target admit-decline matrix in `Tests/Materialization/Targets.lean`. **Not** formal |
| LH-27 | done | invariant-body `context.attachedValue` Normalize fail-closed pin in `Tests/Semantic/AttachedValueContextV1.lean`. **Not** formal |
| LH-28 | done | `docs/specs/semantic-program-wire.md` ContextRead six-key catalog + wire≠target support. **Not** formal |

Track A LH-1…13 + LH-16…28 is **engineering-done**. Formal closeout is the next **human/main-agent** axis (Track F); Goal drain still must **not** mark formal IDs `done`. C-3 stays `formal-blocked`.

## Track F — EVM formal closeout (serial; not Goal-auto-done)

Engineering packaging is exhausted. This track prepares / implements the first formal-prerequisite slice. **Never** flip `TASK-*` / `TST-*` to `done` in `04-task-breakdown` / `05-test-spec` from a Goal drain.

| id | status | objective |
|---|---|---|
| F-D2-07-GAP | done | Inventory + plan [`docs/plan/evm-formal-d2-07-gap.md`](../docs/plan/evm-formal-d2-07-gap.md). Formal TASK/TST still pending. **Not** C-3 / Anvil lossless |
| F-SEM002-HOLES | done | Sem002 isolated holes: response missing/extra + context wrong TypeId (`Tests/Semantic/Sem002ShapeV1.lean`). Focused run ok. **Not** formal TST-SEM-002 |
| F-D2-06-GAP | done | Inventory + plan [`docs/plan/evm-formal-d2-06-gap.md`](../docs/plan/evm-formal-d2-06-gap.md). **Not** formal TST-SEM-001 |
| F-SEM001-SHAPE | done | Sem001 path-vs-semantic / business-hash pin (`Tests/Semantic/Sem001ShapeV1.lean`). **Not** formal TST-SEM-001 |
| F-SEM00X-SHARD | done | Sem001/002/003 registered in `Tests/Shards/Typed.lean` so ordinary `just ci` runs the shape pins. **Not** formal |
| F-CTX-CORE-TYPEID | done | Isolated Wire `.badCfg` pin for same-key ContextRead different Core result TypeId (`Tests/Semantic/Sem002ShapeV1.lean` `ctx/core-type`; structure+encode). Normalize fn purity is now body-local so a later `fn` after an entry ContextRead is not poisoned. **Not** formal TST-SEM-002 |
| F-SEM001-SPAN | done | Isolated layout/span-only companion: same AST + leading-comment span shift keeps `.pfsem`/`semanticHash`/`sourceHash`; only `.pfprov` moves (`Tests/Semantic/Sem001ShapeV1.lean`). Focused run ok. **Not** formal TST-SEM-001 |
| F-CALL-SERIAL | done | Wire structure gate: ExternalCall/Schedule args must be Bool / legal UInt/Int / Bytes / Principal (Normalize / Reference / pf.assets). Do not reuse Eq/Ne `serializableType`. Focused `Tests.Semantic.WireV1.run` ok. **Not** formal TASK-D2-06 / TST-SEM-001 |
| F-CTX-OPEN-CLOSE | done | Honesty-close `B-CTX-OPEN`: NEAR/CW `blockHeight` runtime gates already exist (`scripts/near_runtime_test.sh` BlockHeightCheck + `runtime-tests/cosmwasm/tests/block_height.rs`). Docs only. **Not** a re-implement. **Not** formal |
| F-TYPEKEY-USAGE-GAP | done | Inventory-only plan [`docs/plan/evm-formal-d2-06-typekey-usage.md`](../docs/plan/evm-formal-d2-06-typekey-usage.md). Usage/rank structure gates would mass-break hand-built tables. Next pin = isolated SPEC `typeKey` byte form. **Not** formal TASK-D2-06 |
| F-TYPEKEY-BYTES | done | Isolated SPEC `typeKey` byte-form encoder + WireV1 unit tests. Not a structure gate. Focused `Tests.Semantic.WireV1.run` ok. **Not** formal TASK-D2-06 |
| SYS-S5-NEW-TARGETS | done | ICP/Soroban/OpenVM Plan honesty: `pf.crypto.*` fail closed with named no-host diagnostic. Focused Icp/Soroban/OpenVm suites ok. **Not** EXT-CRYPTO / formal |
| SYS-S4-NEW-TARGETS | done | ICP/Soroban/OpenVM Plan honesty: UInt64 ContextRead keys named no-host FC. caller/self stay generic (Principal). Focused suites ok. **Not** formal |
| SYS-S4-QUINT-KEYS | done | Quint: four UInt64 ContextRead keys named no-host FC. caller/self stay generic. Focused QuintSourceV1 ok. **Not** formal |
| SYS-E2-NEW-TARGETS | done | ICP/Soroban/OpenVM: envRead nativeVaultBalance named no-host FC. token/U128 stay generic. Focused suites ok. **Not** formal |
| SYS-S4-TON-KEYS | done | TON: named Plan FC for attachedValue/chainId/self; unixTime still `blockchain.now()`. Focused TonPlanV1 ok. **Not** formal |
| SYS-S4-CIRCUIT-KEYS | done | Aleo/Noir/Psy named remaining ContextRead keys; Targets.lean matrix needles updated (incl. leftover Quint/Soroban UInt64 rows). unixTime not opened. **Not** formal |
| SYS-S4-MATRIX-NEW | done | ICP/OpenVM added to Targets.lean ContextRead matrix (contains-loops + exact blockHeight/chainId/self). **Not** formal |
| SYS-E2-CIRCUIT | done | Aleo/Noir/Psy: envRead nativeVaultBalance named no-host FC. Compile reached Plan. Focused suites ok. **Not** formal |
| SYS-E2-TON | done | TON: envRead nativeVaultBalance named no-host FC. unixTime still admitted. Focused TonPlanV1 ok. **Not** formal |
| SOR-1-GAP | done | Inventory [`docs/plan/soroban-s1-wasm-finalize-gap.md`](../docs/plan/soroban-s1-wasm-finalize-gap.md). Next implementable = SOR-1a Finalize honesty pins. Opening Wasm/auth/TTL needs a product decision. **Not** formal |
| SOR-1A | done | S0 Finalize honesty + unknown profile FC in `SorobanPlanV1`. extraFiles empty, deployable=false. **Not** SOR-1 / formal |
| F-COMMIT-COMMENT | done | Honesty: CfgTyping/InvariantClosure comments now point at `validateCommitRequirementsV1` (`testCfgCommitCatalogRequirements`). Comments only. **Not** formal |
| ICP-1A | done | ICP Finalize honesty: locked wat2wasm extra=`StateCell.wasm` + deployable=true + PocketIC not invoked; unknown profile `PF-PROFILE-UNKNOWN`. Suite header no longer says zero-tool. **Not** PocketIC/formal |
| F-CALL-SERIAL-COMMENT | done | Honesty: invariant-closure ExternalCall/Schedule comments no longer say arg serializability is deferred. **Not** formal |
| OPENVM-1A | done | OpenVM unknown-profile FC: `not-a-real-profile-v1` → `PF-PROFILE-UNKNOWN`. Sole legal ids remain source+elf. **Not** prove/formal |
| QUINT-1A | done | Quint unknown-profile FC: `not-a-real-profile-v1` → `PF-PROFILE-UNKNOWN`. No ITF/MBT id invented. **Not** QUINT-2 / formal |
| SYS-S5-ECDSA-FC | done | Solana/NEAR/CW Plan FC for `pf.crypto.ecdsaRecoverSecp256k1` (scope/no-host + QN). EVM leaf unchanged. **Not** EXT-CRYPTO / formal |
| SYS-S5-ECDSA-FC-REST | done | Noir/TON/Aleo named no-host + QN; Psy void-call names QN as value-producing (result-bearing hits generic admit list). **Not** EXT-CRYPTO / formal |
| SYS-S5-ECDSA-FC-NEW | done | ICP/Soroban/OpenVM/Quint ecdsaRecover named no-host + QN on existing crypto tests. **Not** EXT-CRYPTO / formal |
| TON-1A | done | TON unknown-profile FC: `not-a-real-profile-v1` → `PF-PROFILE-UNKNOWN`. **Not** formal |
| ALEO-1A | done | Aleo Finalize honesty: extraFiles empty, deployable=false, evidence names no compilation/VM/proof/deploy. Unknown profile `PF-PROFILE-UNKNOWN`. **Not** Leo/formal |
| PSY-1A | done | Psy Finalize honesty: extraFiles empty, deployable=false, evidence names no compilation/VM/proof/UPS/deploy. Unknown profile `PF-PROFILE-UNKNOWN`. **Not** formal |
| CW-1A | done | CosmWasm Finalize honesty: locked wat2wasm extra=`StateCell.wasm` + deployable=true + runtime remains separate; unknown profile `PF-PROFILE-UNKNOWN`. **Not** wasmd/formal |
| F-TYPEKEY-LEAVES | done | Isolated SPEC `typeKey` pins: Int 8/64, Principal, Unit, Array(UInt8,4). Not a structure gate. **Not** formal TASK-D2-06 |
| F-TYPEKEY-FIELDS | done | Isolated SPEC `typeKey` pins for BLS12-377 Fr and Goldilocks FieldSpec (bn254 already pinned). Not a structure gate. **Not** formal |
| DOC-12T-SYNC | done | Refresh RPT-025 12+0 + matrix §2 Soroban/OpenVM/ICP columns + targets README intro. **Not** accepted-PRD expansion |
| SOL-0048-GAP | done | Inventory [`docs/plan/solana-adr-0048-next.md`](../docs/plan/solana-adr-0048-next.md): get certificate exists; init/increment/overflow still observation-only. **Not** formal D5 |
| SOL-0048-INIT | done | StateCell initialize production subject + generic executed HandlerIR/provider join. No 55-step sparse cert yet. **Not** formal D5 |
| SOL-0048-INC | done | StateCell increment-success production subject + generic executed HandlerIR/provider join (argument=1, initialized 41). No 55-step sparse cert yet. **Not** formal D5 |
| SOL-0048-OVF | done | StateCell increment-overflow production subject + generic executed HandlerIR/provider join (UInt64 max prestate, argument=1). No 55-step sparse cert yet. **Not** formal D5 |
| EVM-CALL-ADDR-GAP | done | Inventory [`docs/plan/evm-call-addr-gap.md`](../docs/plan/evm-call-addr-gap.md): static-QN CALL is last-20 keccak of path UTF-8, not CREATE/CREATE2. Next implementable = exact hex pin. Binding stays `B-CALL-SEM`. **Not** emitter change |
| EVM-CALL-ADDR-PIN | done | CallGate/ScheduleGate Yul pin exact keccak last-20 of `Oracle`/`Ledger`. No emitter change. Binding stays `B-CALL-SEM`. **Not** CREATE/CREATE2 |
| NOIR-CALL-RET-FC | in_progress | Pin `let x : UInt64 := call Oracle.feed(...)` Plan FC (existing result-bearing diagnostic). Allowlist `Tests/Materialization/NoirRelationModel.lean`. **Not** response-witness / prove |
| EVM-CALL-INT-FC | done | Pin Int64 result-bearing CALL Plan FC beside existing Bool pin in `EvmSmoke`. **Not** opening signed ABI / B-CALL-SEM |
| DOC-MATRIX-CTRL | done | research/12 D-1=12+0 + §1d Soroban/OpenVM/ICP；ContextRead 行对齐 S3/S4/S3b；ADR-0031 S2 不再写 CPI Clock residual FC。**Not** formal |

## Track B — system capability leaves (after Track A, or file-isolated parallel)

Do **not** start these while an LH slice is `in_progress`. Shared-core first.

| id | status | objective |
|---|---|---|
| SYS-S4-SHARED | done | ADR-0031 S4 shared: `context.attachedValue` → UInt64 ContextRead + wire requirement; target Plans remain FC |
| SYS-S4-EVM | done | EVM `CALLVALUE` Plan/IR/Yul + Anvil engineering gate; view/non-payable exact-zero discipline |
| SYS-S4-NEAR | done | NEAR `attached_deposit` init/entry; **view FC**; sandbox gate |
| SYS-S4-CW | done | CW `MessageInfo.funds` single-denom (`stake` C1); query/view FC; cw-vm mock gate |

S5 `pf.crypto.sha256` is an independent payload wave — **not** in this drain.

## Track C — residual that is *not* auto-drainable

Leave these `blocked` / `decision`. Goal must **skip**, not implement.

| id | status | why skip |
|---|---|---|
| C-3 | formal-blocked | Reference↔Anvil formal; Track A only prepares |
| B-CALL-SEM | decision | callee deployment-address + cross-chain call honesty |
| B-COMMIT-ZK | decision | Psy/Noir commitment binding freeze first |
| D3-E8 | decision | `--minimum-evidence` grade semantics not frozen |
| DOC-JUST-CONTROL | decision | restore `release-check` recipe or keep absent |
| QUINT-2 | decision | Tool Lock + ITF/MBT/verify; no silent product Quint |
| NS-2 / EXT-CRYPTO | gated | language/crypto catalog not ready |
| RES-1B-MEM | later | memory/process/protocol/stderr; not lighthouse |
| EA-P1-5 | later | contributor incremental compile |
| SYS-S2-NEAR-RT / SYS-S2-CW-RT | **already in tree** | `runtime-tests/near` BlockHeightCheck + `runtime-tests/cosmwasm/tests/block_height.rs` exist; do not re-implement |

Standing why/why-not for those skips: [`.agents/notes/README.md`](../.agents/notes/README.md)
(TypeKey structure gate, EXT-CRYPTO auto-open, Soroban S0≠Wasm, focused Lean
verification, Goal↛formal).

## Runner notes

1. Track A/B/F and later file-isolated honesty pins are **done**. Queue has **zero pending**. Goal must **not** auto-close formal IDs and must **not** resume at LH-4 or emit `NEXT=FORMAL_C3`. Never Track C. Unused TypeKey rejection / decoder-side rank / SPEC-honesty ADR / EV binding / C-3 / SOR-1 Wasm remain product/formal decisions.
2. Mark claimed row `in_progress` only on a clean tree (or WIP wholly inside that slice allowlist).
3. One local commit per id. Touch `ProofForgeV2/**` → `just sbom-package-files-refresh`. Docs → `just docs-check`.
4. After commit: this file `done`, `docs/engineering-backlog.md` one honest line, AGENTS Current/Next if Track A pointer moves.
5. Stuck >2 focused failures → `blocked` with evidence; skip to next **independent** row only if allowlists do not overlap. Shared-core stays serial.
