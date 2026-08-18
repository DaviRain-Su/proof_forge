# Agent Note: TypeKey unused / rank stay out of the structure gate

Status: **superseded (2026-08-17)** — product decision accepted Stage A/B/C/D
staged cutover. **Anonymous `typeKey` rank** is a structure-gate phase
(`anonymousRank` in `validateTypeKeyPhasesV1`). **Usage-closure** is wired as
`usageClosure` via `validateTypeKeyPhasesWithUsageClosureV1` →
`validateSemanticProgramStructureV1` (Stage D). Fat hand-built fixtures compact
unused anonymous rows (`compactSemanticProgramDataToUsageClosureV1`) or attach
real Core uses. Formal TASK-D2-06 / TST-SEM-001 remain pending.

## Problem

SPEC §5 asks unused TypeKey rows to be rejected and anonymous types to be
ranked by raw `typeKey` bytes. After the isolated byte-form pin
(`encodeTypeKeyBytesForTestV1`), the tempting next slice is to feed unused
rejection or that rank into `validateSemanticProgramStructureV1`.

Hand-built tables are not Normalize-emitted `named ++ sorted-anonymous`.
Historical `cfgOpTypes` anonymous order was Bool, UInt8, UInt32, Option, Map,
Bytes. SPEC sort keys start with `u16le(tagLen)`, so `map` (3) precedes
`bool` / `uint` (4). Installing the gate required an explicit product choice
to migrate fixtures (accepted 2026-08-17 staged plan).

## Proposal

Add unused-TypeDecl rejection and/or decoder-side anonymous rank as a
structure-gate phase in the same wave as the byte-form pin.

## Alternatives considered

- **Install unused rejection now** — **accepted Stage D**: StructureV1 calls
  `validateAnonymousTypeUsageClosureV1` after rank; Wire fixtures compact or
  Core-anchor; CanonicalInvariantABI golden dropped unused Principal.
- **Install decoder-side rank now** — **accepted and shipped** after
  Normalize Stage A + subject/fixture Stage B migration (`cfgOpTypes` remapped
  to SPEC order Map, Bool, UInt8, UInt32, Bytes, Option).
- **Treat the byte-form pin as authorization** — rejected at the time:
  [`docs/plan/evm-formal-d2-06-typekey-usage.md`](../../../../docs/plan/evm-formal-d2-06-typekey-usage.md)
  pinned the encoder only. Later owner decision authorized structure rank.
- **Leave the warning only in the gap plan** — rejected as the sole
  record: the plan is easy to read as “next implementable slice” and get
  drained by a Goal that is supposed to skip product decisions.

Do not mark `TASK-D2-06` / `TST-SEM-001` done either way.
