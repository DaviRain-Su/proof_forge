---
id: PLAN-D3-E8
title: D3-E8 — minimum-evidence flag wiring plan
status: draft
owner: engineering
updated: 2026-08-19
normative: false
---

# D3-E8 — `--minimum-evidence` wiring plan

Engineering plan only. **Does not** freeze evidence-grade semantics, accept ADRs,
or close formal `SupportClaim` / `PF-REQ-EVIDENCE` / OutputSet `support` fields.

Normative intent lives in [`specs/cli.md`](../specs/cli.md),
[`specs/capabilities-extensions.md`](../specs/capabilities-extensions.md), and
[`specs/output-contract.md`](../specs/output-contract.md). Owner must decide
before resolver/manifest enforcement.

## Current state (2026-08-19)

| Layer | Behavior |
|---|---|
| Parse | `parseBuildArgsExcept` stores raw string in `BuildOptions.minimumEvidence` |
| Preflight | `validateBuildOptionsCliV1`: build-only; closed wire whitelist via `isValidMinimumEvidenceGradeV1`; check rejects |
| Product build | **No read** of `minimumEvidence` after parse — build succeeds regardless of grade |
| Resolver | `resolveEngineeringRequirementsV1` has no minimum-evidence parameter |
| Registry / profile | Engineering `CodegenProfile` / `TargetDescriptor` **lack** `minimumEvidence` field |
| Manifest / OutputSet | Engineering `proof-forge.output.v1` has no `support.minimumEvidence` |
| Build JSON | Echoes CLI request; `minimumEvidenceEnforcement: parse-only-not-enforced` (honesty slice) |

D3-E5 marked CLI **syntax** done; D3-E8 is the **semantics + enforcement** slice.

## Code path map

```text
argv
  → Main.run → parseProductCliCommandV1
       → parseCliCommandWithSeedV1 (registry seed)
       → parseCliCommandV1 → parseBuildArgsExcept
            [--minimum-evidence <grade>] → BuildOptions.minimumEvidence := some grade
  → validateBuildOptionsCliV1 (.build)
       → isValidMinimumEvidenceGradeV1 (whitelist only)
  → buildSource (Main.lean)
       → compile → certifyInlineProofV1
       → resolveBuildSelectionForCli
       → resolveEngineeringRequirementsV1  ← no minimumEvidence
       → emitProgram                       ← no minimumEvidence
       → renderBuildOkJsonV1(..., minimumEvidenceRequested)  ← observability only
```

**Not on path today:** `RequirementResolverV1`, `EngineeringSupportClaimV1`,
`mintEngineeringOutputSetV1`, manifest `supportClaimDigest` / evidence sidecars,
formal `EvidenceResolver.resolveSupport`.

## Owner decisions required (block enforcement)

1. **Profile defaults** — per-`CodegenProfileId` `minimumEvidence` in engineering
   registry (SPEC wire enum + total order already in capabilities-extensions).
2. **Achieved grade source** — engineering resolver stays `specified`-only until
   formal `ProfileSupportIndex` / binding refs exist; confirm interim behavior.
3. **Failure mode** — `PF-REQ-EVIDENCE` vs exit 4 vs build warning-only (must
   not silently pass).
4. **Manifest binding** — when `support.minimumEvidence` and
   `support-decisions.json` enter engineering OutputSet identity (D3-E4 gap).

Until (1)–(4) are decided, **must not** treat JSON echo or successful build as
evidence gating.

## Phased implementation (post-decision)

### Phase A — registry scaffold (no gate)

- Add `minimumEvidenceWireV1` on engineering profile rows (default `specified`).
- Pure `effectiveMinimumEvidenceV1 (profileMin cliOpt)` = lexicographic max on
  frozen wire order (mirror SPEC, no new enum names).
- Build JSON: `minimumEvidence` = effective, `minimumEvidenceRequested` = CLI opt.

### Phase B — resolver observation (still no gate)

- Thread `effectiveMinimum : WireGrade` into `resolveEngineeringRequirementsV1`.
- Attach `achievedGrade := specified` on each engineering support decision record
  (explicit, not inferred from Mollusk/Anvil).
- Optional `describe-target` / inspect-target JSON fields for profile minimum.

### Phase C — enforce (owner flip)

- After capability resolve, compare achieved vs effective; fail closed
  `PF-REQ-EVIDENCE` / exit 4 when below minimum.
- Mint `support-decisions.json` stub or full engineering subset; bind digest into
  OutputSet when D3 formal envelope allows.

### Phase D — formal alignment (out of daily engineering)

- Replace engineering claim/decision types with formal `SupportClaim` /
  `ResolvedSupportDecision` / candidate evidence-set injection.

## Honesty slice delivered without Phase A–C

Following RES-1B pattern (parse but no producer → explicit rejection or label):

- Build JSON adds `minimumEvidenceEnforcement: "parse-only-not-enforced"`.
- Renames observability: `minimumEvidenceRequested` = CLI flag value;
  `minimumEvidence` = `null` until effective minimum is wired (avoids implying
  SPEC-effective field is populated).
- Tests pin renderer + optional product build with high grade still exit 0.

## Verification

```bash
lake env lean Tests/CLI/ResourceFlagsV1.lean
just dev-check   # or focused shard containing Tests.CLI.ResourceFlagsV1
```

Product subprocess test (binary present): build Counter with
`--minimum-evidence network_or_proof_validated` must succeed — proves no gate.

## References

- Backlog: `docs/engineering-backlog.md` §5 D3-E8
- Queue: `.grok/next-wave-queue.md` (decision row)
- Tests: `Tests/CLI/ResourceFlagsV1.lean`
