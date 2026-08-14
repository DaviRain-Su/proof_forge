# Agent Note: TypeKey unused / rank stay out of the structure gate

Status: rejected — unused rejection and decoder-side rank would mass-break hand-built Wire / Sem00x tables

## Problem

SPEC §5 asks unused TypeKey rows to be rejected and anonymous types to be
ranked by raw `typeKey` bytes. After the isolated byte-form pin
(`encodeTypeKeyBytesForTestV1`), the tempting next slice is to feed unused
rejection or that rank into `validateSemanticProgramStructureV1`.

Hand-built tables are not Normalize-emitted `named ++ sorted-anonymous`.
`cfgOpTypes` anonymous order is Bool, UInt8, UInt32, Option, Map, Bytes.
SPEC sort keys start with `u16le(tagLen)`, so `map` (3) precedes `bool` /
`uint` (4). Installing the gate now turns a formal-prep inventory into a
shared-table migration.

## Proposal

Add unused-TypeDecl rejection and/or decoder-side anonymous rank as a
structure-gate phase in the same wave as the byte-form pin.

## Alternatives considered

- **Install unused rejection now** — rejected: it is the dual of a
  completeness walk over every used shape. Isolated OOR TypeId negatives
  already fail `.badReference` before TypeKey. A new completeness walk
  would fail the fat hand-built fixtures that carry unused interned shapes
  on purpose.
- **Install decoder-side rank now** — rejected: it reorders or rejects
  `cfgOpTypes`, Sem001/002/003 carriers, and entry-gate tables that Lake
  and focused suites currently accept. That needs an explicit product
  choice: migrate fixtures, or keep rank Normalize-only.
- **Treat the byte-form pin as authorization** — rejected:
  [`docs/plan/evm-formal-d2-06-typekey-usage.md`](../../../../docs/plan/evm-formal-d2-06-typekey-usage.md)
  pins the encoder only and says the inventory does not authorize a
  structure gate.
- **Leave the warning only in the gap plan** — rejected as the sole
  record: the plan is easy to read as “next implementable slice” and get
  drained by a Goal that is supposed to skip product decisions.

Re-open only after a product decision to migrate hand-built tables or to
keep rank on the Normalize emit path. Do not mark `TASK-D2-06` /
`TST-SEM-001` done either way.
