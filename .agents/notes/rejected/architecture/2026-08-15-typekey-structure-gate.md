# Agent Note: TypeKey unused / rank stay out of the structure gate

Status: **superseded in part (2026-08-17)** — product decision accepted Stage A/B/C
staged cutover. **Anonymous `typeKey` rank is now a structure-gate phase**
(`anonymousRank` in `validateTypeKeyPhasesV1`). **Usage-closure is
implemented** as `validateAnonymousTypeUsageClosureV1` but **not yet wired**
into `validateSemanticProgramStructureV1` (fat hand-built tables such as
`cfgOpTypes` still carry intentionally unused anonymous rows; wiring needs a
follow-on fixture-tightening slice). Formal TASK-D2-06 / TST-SEM-001 remain
pending.

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

- **Install unused rejection now** — deferred after rank: it is the dual of a
  completeness walk over every used shape. Isolated OOR TypeId negatives
  already fail `.badReference` before TypeKey. A new completeness walk still
  fails fat hand-built fixtures that carry unused interned shapes on purpose
  (and the InvariantABI golden historically kept an unused Principal to pin
  selected-closure). Validator exists; StructureV1 wiring waits on fixture
  purge.
- **Install decoder-side rank now** — **accepted and shipped** after
  Normalize Stage A + subject/fixture Stage B migration (`cfgOpTypes` remapped
  to SPEC order Map, Bool, UInt8, UInt32, Bytes, Option).
- **Treat the byte-form pin as authorization** — rejected at the time:
  [`docs/plan/evm-formal-d2-06-typekey-usage.md`](../../../../docs/plan/evm-formal-d2-06-typekey-usage.md)
  pinned the encoder only. Later owner decision authorized structure rank.
- **Leave the warning only in the gap plan** — rejected as the sole
  record: the plan is easy to read as “next implementable slice” and get
  drained by a Goal that is supposed to skip product decisions.

Re-open only for **usage-closure StructureV1 wiring** after tight fixtures.
Do not mark `TASK-D2-06` / `TST-SEM-001` done either way.
