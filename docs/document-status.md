# Documentation Status and Archive Index

Status: **Authoritative documentation lifecycle index (2026-07-15)**

This page answers which documents are current, which are execution ledgers,
and which are retained only as historical evidence. Code, runnable gates, and
generated artifacts remain the implementation truth.

## Current Documents

| Responsibility | Authoritative document |
|---|---|
| Settled decisions | [decisions.md](decisions.md) |
| Current compiler architecture | [Canonical Core design](superpowers/specs/2026-07-11-core-ir-target-plan-design.md) |
| IR versus target-extension ownership | [IR Target Extension Boundary design](superpowers/specs/2026-07-14-ir-target-extension-boundary-design.md) |
| Next architecture and product direction | [Portable Intent design](superpowers/specs/2026-07-12-portable-intent-abstraction-design.md) |
| Incremental legacy replacement policy | [Legacy Replacement design](superpowers/specs/2026-07-12-incremental-legacy-replacement-design.md) |
| **Active merge priority (D-056)** | [PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104) direct authoring cutover + primary-triad native differential — rebase onto `main` and land before deep secondary-host work |
| Current execution order | [NEAR NEP-141 / NEP-145 interop plan](superpowers/plans/2026-07-13-near-nep141-interop-execution.md) (after cutover baseline) |
| Active architecture prerequisite | [IR Target Extension Boundary plan](superpowers/plans/2026-07-14-ir-target-extension-boundary.md) |
| Cross-program portable-intent order | [Portable Intent implementation plan](superpowers/plans/2026-07-12-portable-intent-abstraction.md) |
| Companion legacy migration order | [Legacy Replacement implementation plan](superpowers/plans/2026-07-12-incremental-legacy-replacement.md) |
| Legacy migration ledger | [legacy-replacement-ledger.md](legacy-replacement-ledger.md) |
| Current executable work inventory | [implementation-backlog.md](implementation-backlog.md) |
| Agent bootstrap and current checkpoint | [AGENTS.md](../AGENTS.md) |
| Current concise execution evidence | [implementation-log.md](implementation-log.md) |
| Target portfolio sequencing | [target-roadmap.md](target-roadmap.md) |
| Phase/gate decisions | [gate-status.md](gate-status.md) |
| Validation commands | [validation-gates.md](validation-gates.md) |
| Target maturity and per-target facts | [targets/README.md](targets/README.md) and target notes |
| Soroban Counter MVP + gap / slice order | [targets/stellar-soroban.md](targets/stellar-soroban.md) |
| Wasm-host promotion analysis | [Wasm-host analysis](superpowers/specs/2026-07-12-wasm-host-target-analysis.md) |
| ZK promotion analysis | [ZK target analysis](superpowers/specs/2026-07-12-psy-integration-analysis.md) |
| OpenVM research brief (C3, defer) | [targets/openvm-research.md](targets/openvm-research.md) |

## Historical Baselines

These files remain at their original paths so old commits, reviews, and links
stay traceable. They must not be used as current scheduling authority.

| Document | Archived role | Successor |
|---|---|---|
| `multi-chain-gap-audit-2026-07-10.md` | July 10 audit and remediation evidence | July 12 design plus current backlog |
| `agent-goal-prompt.md` | PF-P0/P1/P2/P3 long-running remediation ledger | July 12 implementation plan |
| `superpowers/plans/2026-07-08-project-completion-roadmap.md` | pre-consolidation completion proposal | current backlog and roadmap |
| `superpowers/plans/2026-07-09-portable-sdk-unification.md` | completed portable SDK waves | July 12 intent design |
| `superpowers/plans/2026-07-09-unified-support-roadmap.md` | HostEnv/crosscall/FV consolidation history | July 12 intent and target analyses |
| `superpowers/plans/2026-07-10-post-review-execution.md` | triad hardening and benchmark execution history | July 12 implementation plan |
| `superpowers/plans/2026-07-11-core-ir-target-plan.md` | completed Canonical Core migration tasks | Canonical Core design and current code |
| `superpowers/plans/2026-07-11-primary-triad-runtime-handoff.md` | branch/checkpoint handoff | primary-triad roadmap history |
| `doc-code-sync-audit-2026-07.md` | point-in-time documentation audit | this lifecycle index and docs gates |

The primary-triad runtime roadmap remains an architecture/product evidence
record until its remaining waves are formally closed. It does not override the
July 12 execution order.

`development-log.md` is the detailed historical engineering stream. Agents
should use the concise `implementation-log.md` for current task handoff and
search the historical log only when older evidence is required.

## Lifecycle Rules

1. A design spec defines an accepted boundary; it is not an execution ledger.
2. One plan at a time is marked as the current execution order.
3. Completed or superseded plans receive a `Historical` status at their
   original path instead of being deleted or silently rewritten.
4. `implementation-backlog.md` contains current reviewable slices; completed
   detail may remain for traceability but must be labeled historical.
5. `target-roadmap.md` sequences target promotion; it does not claim code is
   implemented.
6. `gate-status.md` records closed/open phase decisions with reproducible
   evidence.
7. New architecture work updates decisions, this index, the relevant design,
   backlog, roadmap, gates, and validation docs in the same documentation
   phase before code implementation begins.
8. Legacy code is migrated incrementally behind tests. Documentation must name
   the legacy boundary and intended replacement rather than pretending the old
   path has already been deleted.
9. Root `AGENTS.md` is the mandatory agent entry point. It contains only the
   current checkpoint and links; detailed task state remains in the current
   plan, and completed-task evidence is appended to `implementation-log.md`.

## Current Migration Principle

Legacy `ContractSpec` and adapters remain compatibility inputs while product
surfaces move toward:

```text
portable authoring
  -> IntentContract / Frontend Surface
  -> CheckedCanonicalContract
  -> CapabilityPlan + target materializer
  -> target plan
  -> artifact and runtime evidence
```

Each replacement slice must preserve observable behavior, add a strict gate,
and remove legacy code only after all callers and fixtures have migrated.
