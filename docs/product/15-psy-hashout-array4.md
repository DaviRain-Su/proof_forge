---
id: PRODUCT-PSY-HASHOUT-ARRAY4
title: Psy HashOut full limbs (Array UInt64 4) — author guide
status: draft
owner: product+engineering
updated: 2026-08-11
normative: false
---

# Psy: full HashOut via `Array UInt64 4`

## When to use this

| Goal | Result type | API |
|------|-------------|-----|
| Single Felt for further arithmetic / storage | `UInt64` | `call pf.crypto.hashNoPad(...)` etc. |
| Full Poseidon HashOut (4 limbs) for chaining / compare | `Array UInt64 4` | same call, **annotate** `Array UInt64 4` |

Scalar path is unchanged and remains the default for simple counters and probes
(`Examples/HashProbe.lean`).

## Minimal example

```lean
import ProofForgeV2
namespace Examples
open ProofForgeV2.Language

program HashOutDemo where
  state last0 : UInt64

  init() do
    last0 := 0

  -- Full 4-limb HashOut (official simulate → 4 circuit outputs)
  entry hashPairFull(a : UInt64, b : UInt64) : Array UInt64 4 do
    let h : Array UInt64 4 := call pf.crypto.hashNoPad(a, b)
    last0 := h[0]
    return h

  -- Two-to-one over two HashOuts (8 limbs in, 4 out)
  entry combineFull(
      a0 : UInt64, a1 : UInt64, a2 : UInt64, a3 : UInt64,
      b0 : UInt64, b1 : UInt64, b2 : UInt64, b3 : UInt64
  ) : Array UInt64 4 do
    let h : Array UInt64 4 :=
      call pf.crypto.hashTwoToOne(a0, a1, a2, a3, b0, b1, b2, b3)
    last0 := h[0]
    return h

  view getLast0() : UInt64 do
    return last0
end Examples
```

Ship reference: `Examples/HashOutProbe.lean`.

## Build & simulate

```bash
# product CLI (after pf setup --target psy)
pf build path/to/HashOutDemo.pf --module HashOutDemo --target psy -o build/out

# or monorepo next binary
proof-forge-next build Examples/HashOutProbe.lean \
  --module Examples.HashOutProbe --target psy -o build/v2/hof

# official authority (required for hash values — session harness does not Poseidon)
psy_user_cli simulate \
  --circuit-defs-path build/v2/hof/HashOutProbe.dpn.json \
  --method hashPairFull --format json \
  --inputs 1 --inputs 2
```

Expected shape (illustrative):

```json
{
  "success": true,
  "outputs": [
    17222278624453642754,
    11209788157740309596,
    13716685746781302004,
    16073914926410643468
  ]
}
```

**Invariant:** `outputs[0]` equals the scalar `hashPair(1,2)` first limb from
`Examples/HashProbe.lean` under the same inputs.

## What is admitted (full Array4)

| Call | Full `Array UInt64 4` | Notes |
|------|:---------------------:|-------|
| `pf.crypto.hashNoPad` | yes | Poseidon; official fills HashOut arrays |
| `pf.crypto.hashTwoToOne` | yes | 8 input limbs = left\|\|right HashOut |
| `pf.crypto.hashPad` | no | emit-only on official software eval |
| `pf.crypto.keccak256` | no | official stores U32 words, not HashOut arrays |
| `pf.context.userPublicKeyHash` | no | limb0 via `UInt64` only |
| `pf.context.sessionProofTreeRoot` | no | limb0 via `UInt64` only |
| `pf.crypto.calculateMerkleRoot` | no | official software evaluator `todo!` |

Using `Array UInt64 4` on a non-admitted call fails closed at Plan with a
diagnostic that points back to limb0 / wait-for-upstream.

## Lowering picture (engineering)

```
call result Array UInt64 4
  → Plan Expr.hashOutLimb kind i args   (i = 0..3, CSE)
  → DPN: one HashOut-typed op (data_type=hashOut)
       + four TargetAt(hash, limbIndex)
  → circuit_outputs: four Target wire ids
```

Store+return of the same hash share one HashOut def (CSE). Session harness
**fail-closes** on Poseidon/Keccak — always use `psy_user_cli simulate` for
values.

## Related surfaces

| Topic | Doc / probe |
|-------|-------------|
| Scalar hash | ADR-0039, `Examples/HashProbe.lean` |
| Context ids (limb0) | `docs/targets/psy-p3-context-commit-gate.md`, `ContextProbe` |
| IMT | `Examples/ImtProbe.lean` |
| Commit (still FC) | [ADR-0041](../adr/0041-psy-commit-public-input-gate.md) |
| OP coverage | `docs/targets/psy-op-coverage.md` |

## Waiting on upstream (not PF work)

- Official software eval: full HashOut arrays for keccak / context ops
- Official software eval: `CalculateMerkleRoot` implementation
- UPS / public-input Commit binding (ADR-0041 checklist)
