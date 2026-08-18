---
id: PLAN-EVM-FORMAL-D2-06-TYPEKEY-USAGE
title: EVM formal lighthouse — TASK-D2-06 TypeKey usage / rank inventory
status: draft
owner: engineering
updated: 2026-08-14
normative: false
---

# EVM formal lighthouse：D2-06 TypeKey usage / rank gap

> Engineering inventory only. Does **not** close `TASK-D2-06`, `TST-SEM-001`,
> `TST-PROOF-001`, or any EV/qualification object. Does **not** invent a new
> `TASK-*`. Rank + usage-closure StructureV1 wiring are **engineering-only**
> (Stage A–D); they do not create EV or formal closeout.

Authority: [`04-task-breakdown.md`](../04-task-breakdown.md) `TASK-D2-06` →
[`05-test-spec.md`](../05-test-spec.md) `TST-SEM-001` ·
[`semantic-program-wire.md`](../specs/semantic-program-wire.md)
`## 5. Canonical type/value encoding` ·
[`evm-formal-d2-06-gap.md`](evm-formal-d2-06-gap.md) · ADR-0036.

## Why this cannot be marked formal-done

Same blockers as [`evm-formal-d2-06-gap.md`](evm-formal-d2-06-gap.md):

| Blocker | Fact |
|---|---|
| Evidence | Formal closeout needs EV retained-artifact digest binding of canonical `.pfsem` / `.pfprov`. Production encoders exist; no formal EV object. |
| Qualification | `TASK-D1-01` still blocked; recovery forbids inventing freeze/EV ceremony. |
| Proof join | `TST-PROOF-001` requires `TST-SEM-001` first. Inline ADR-0027 is engineering-only. |
| Dependency | `TASK-D2-07` / `TST-SEM-002/003` stay pending until D2-06 is formal-done. |
| This inventory | Closing usage/rank would still be an engineering subset of SPEC §5. It does not create EV, qualification, or a new `TASK-*`. |

## Engineering already pins

`validateTypeKeyPhasesV1` (`ProofForgeV2/Semantic/Wire/TypeKeyV1.lean`) is the
sole TypeKey phase seam. Public error is `.nonCanonical`; the phase enum makes
precedence observable. `Tests/Semantic/WireV1.lean` drives both structure and
structure-gated encode.

| Subphase | What is pinned | Suite |
|---|---|---|
| `namedPrefix` | All `name=some` Struct/Enum occupy `types[0 .. namedCount)`. Named after an anonymous row is `.nonCanonical`. | `testNamedTypePrefixRank` |
| `primitiveLeaf` | One anonymous TypeId per Bool / same-width UInt / same-width Int / Principal / Unit / same-length Bytes / exact FieldSpec. Duplicate → `.nonCanonical`. | `testPrimitiveAnonymousTypeKeyUniqueness` |
| `recursiveAnonymous` | Anonymous Array/Map/Option structural-class uniqueness via fixed-size signatures (not nested child keys). Anonymous-only cycles `.nonCanonical`. | `testRecursiveAnonymousTypeKeyUniqueness` |
| `namedBodyCycle` | After removing Option nodes/edges, the induced graph is acyclic. Combined with `recursiveAnonymous`, an accepted cycle has a named key **and** an Option. | `testNamedBodyOptionCycleLegality` |

`anonymousRank` and `usageClosure` are now StructureV1 phases (engineering).
The recursive signature builder remains **not** a substitute for claiming
formal SPEC rank reconstruction / EV closeout.

Earlier than TypeKey: table id==index, shallow TypeId range
(`checkTypeShapeRefs` / `checkTypeIdInRange` on constants, state, events,
errors, callable params/results), and type-shape / FieldSpec / Map-key
legality. Those are not usage closure.

## Remaining holes

SPEC cite for all three: [`semantic-program-wire.md`](../specs/semantic-program-wire.md)
**`## 5. Canonical type/value encoding`**, algorithm steps 3–5 and the
`TypeKeyV1` byte-form block. Related empty-table rule:
**`## 6. Canonical IDs、table order 与 structural validation`**
(“types 只能在没有任何 reference 时为空”). Phase slot:
**`### 6.2 Stable validation order`** (“type graph/Field spec”).

### Unused / unreferenced TypeDecl rejection

| | |
|---|---|
| SPEC | Step 5: decoder rebuilds the same closure/key order from the named prefix, all type usage, and anonymous declarations. An anonymous declaration that is not reached from a named body, Core slot, or another required anonymous type is `nonCanonical`. |
| Code | **Engineering Stage D done:** `validateAnonymousTypeUsageClosureV1` runs after `anonymousRank` inside StructureV1. Unused anonymous → `.nonCanonical` (`usageClosure` phase). |
| Fixture risk | Mitigated: `programWithTypes` / builders compact unused anonymous rows; shape positives Core-anchor via `logicalState`; Normalize no longer force-interns unused UInt64 envelope. **Still not** formal TASK-D2-06 / TST-SEM-001. |

### Missing referenced type (if not already shallow-ref)

| | |
|---|---|
| SPEC | Step 5 `missing`: a required anonymous key from named-body / Core usage is absent from the interned table. Step 3: closure roots are named-body field/payload types **and** every Core type slot. |
| Code | Out-of-range TypeId is already `.badReference`: shape children (`checkTypeShapeRefs`), declaration slots (`StructureV1` prelude), CFG def-site range (step h). That is shallow existence, not “this used shape has no interned TypeKey.” |
| Fixture risk | A new completeness walk (every used shape must appear as a TypeDecl) is the dual of unused rejection. Same shared-table risk as above. Isolated OOR negatives already exist and must stay `.badReference` before TypeKey. **No new missing-TypeId gate is needed.** |

### SPEC canonical anonymous rank / order bytes

| | |
|---|---|
| SPEC | Step 4: sort all anonymous keys by unsigned-lexicographic **raw `typeKey` bytes**; rank `i` gets TypeId `namedCount + i`. The byte form is `u16le(ASCII(tag).size) \|\| ASCII(tag) \|\| …` with nested child keys. Pretty names, hashes, locale sort, and final TypeId are forbidden as sort keys. Wrong-rank is `nonCanonical`. |
| Code | `TypeKeyV1` uses fixed-size structural-class signatures for equality/interning only. Comments state this is **not** the SPEC ranking byte form; ranking/order is a deferred normalizer concern. The types table is not re-sorted or rank-checked. |
| Fixture risk | **Would mass-break hand-built tables.** `cfgOpTypes` anonymous order is Bool, UInt8, UInt32, Option, Map, Bytes. SPEC sort keys start with `u16le(tagLen)`, so shorter tags (`map` = 3) precede `bool`/`uint` (4). Hand-built Wire/Sem00x tables are not Normalize-emitted `named ++ sorted-anonymous`. Enforcing rank at the structure gate requires a product decision to migrate those fixtures or to keep rank Normalize-only. |

## Recommended next implementable engineering slice

**Stage D (done 2026-08-17):** SPEC §5 **usage closure** is wired into
`validateSemanticProgramStructureV1` after `anonymousRank` via
`validateTypeKeyPhasesWithUsageClosureV1`. Unused anonymous TypeDecls fail
`.nonCanonical` at phase `usageClosure`. Fat fixtures compact or Core-anchor;
Normalize no longer force-interns unused UInt64 envelope types (StructureV1
rejects any residual unused anonymous). SimpleClosure is Bool-only. Still
**not** formal TASK-D2-06 / TST-SEM-001.

**Next engineering (outside this TypeKey plan):** `B-CALL-SEM` decision pack
(human) or `CAP-X-BYTES` shared-core cutover — not formal TASK closeout.

**History:** byte-form pin 2026-08-14; Stage A/B/C rank cutover 2026-08-17;
Stage D usage-closure StructureV1 wiring 2026-08-17.

## Non-claims

No formal TASK/TST status change. Usage-closure StructureV1 wiring is
engineering-only. No Anvil lossless. No second Semantic serializer. No
accepted-PRD expansion. No EV / `TASK-D1-01` ceremony.
