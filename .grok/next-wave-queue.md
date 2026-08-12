# Next-wave drain queue (2026-08-12)

**Authority:** `docs/engineering-backlog.md` 推荐击杀顺序 · ADR-0036 · AGENTS Next task  
**Live status:** this file. Backlog wins on conflict; this file wins on *order*.  
**Mode:** Goal drain *or* one-slice workflow. Do **not** wait for chat “继续”.  
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

After LH-7, Track A is **drain-complete**. Next formal closeout is **excluded**.

## Track B — system capability leaves (after Track A, or file-isolated parallel)

Do **not** start these while an LH slice is `in_progress`. Shared-core first.

| id | status | objective |
|---|---|---|
| SYS-S4-SHARED | done | ADR-0031 S4 shared: `context.attachedValue` → UInt64 ContextRead + wire requirement; target Plans remain FC |
| SYS-S4-EVM | done | EVM `CALLVALUE` Plan/IR/Yul + Anvil engineering gate; view/non-payable exact-zero discipline |
| SYS-S4-NEAR | pending | NEAR `attached_deposit` init/entry; **view FC**; sandbox gate |
| SYS-S4-CW | pending | CW `MessageInfo.funds` single-denom (`stake` C1); query/view FC; cw-vm mock gate |

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

## Runner notes

1. First `pending` row in Track A, then Track B. Never Track C.
2. Mark claimed row `in_progress` only on a clean tree (or WIP wholly inside that slice allowlist).
3. One local commit per id. Touch `ProofForgeV2/**` → `just sbom-package-files-refresh`. Docs → `just docs-check`.
4. After commit: this file `done`, `docs/engineering-backlog.md` one honest line, AGENTS Current/Next if Track A pointer moves.
5. Stuck >2 focused failures → `blocked` with evidence; skip to next **independent** row only if allowlists do not overlap. Shared-core stays serial.
