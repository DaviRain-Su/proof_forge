---
id: RPT-017
title: J1 Noir toolchain (nargo/bb) availability — acceptance gate decision
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# J1: Noir `nargo` / `bb` toolchain — promote acceptance gate?

## Question

Can ProofForge promote a **real** Noir toolchain acceptance gate this wave
(analogous to EvmSolc `solc --strict-assembly`, NearWasmAcceptance
`wat2wasm`/`wasm-interp`, or Solana Mollusk), or must Noir maturity remain
**source-only** (relation packages + Lean relation model)?

Scope covers both:

1. **Compile-only** gate: materialize `.nr` → host `nargo compile` succeeds.
2. **Prove/verify** gate: `nargo execute` / `nargo prove` / `nargo verify` +
   Barretenberg (`bb`) backend.

This note re-verifies host and in-tree facts on 2026-08-02 (worktree base
`bc7568ef3`) and records the product decision. It **confirms** the earlier
C-4 research outcome in [`16-noir-prove-path.md`](16-noir-prove-path.md)
(RPT-016) and adds emit-surface / install-path detail for a future gate.

## Method

| Check | Result |
|---|---|
| Host `which nargo` / `command -v nargo` | **not found** |
| Host `which bb` / `command -v bb` | **not found** |
| Common install locations (`~/.nargo`, `/opt/homebrew/bin`, `~/.cargo/bin`) | no `nargo` / `bb` binaries |
| Tool Lock / `supply-chain/*` asset pin for nargo/noirc/bb | **absent** |
| SPEC toolchains `unresolved` | includes `nargo`, `barretenberg` (not frozen) |
| Product Noir emitter (`Targets/Noir/EmitIRV1.lean`) | source packages only |
| `ValidatePlanV1` / Finalize | `proofStatus=notProduced`; zero-tool finalize |
| `scripts/validate_artifacts.py` Noir path | **forbids** `.acir`/`.proof`/`.vk`/`.witness`; non-deployable |
| Network install of toolchain in this slice | **not performed** (no ad-hoc PATH pin) |

## In-tree engineering facts

### Product surface

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`ProofForgeV2/Targets/Noir/*`) |
| Product materialize | Per-relation package: `relations/<stem>/Nargo.toml` + `src/main.nr`; root `<Program>.noir-relations.json` |
| Profile / dialect | `noir-source-u64-relations-v1` / `noir-native-u64-relations-v1` |
| `artifactKind` / `proofStatus` | `source-only` / `not-produced` (JSON interface + Plan) |
| FinalizeV1 | Zero tools; `deployable=false`; evidence notes no pinned compiler/proving backend |
| Lean relation model | `Tests/Materialization/NoirRelationModel` — **not** Nargo/ACIR execution |
| Tool Lock pin | **No** nargo / noirc / Barretenberg (or other proving backend) asset |

### What `.nr` is emitted (EmitIRV1)

`emitFromIR` writes one independent Nargo package per relation:

```text
<Program>.noir-relations.json          # catalog: planHash, inputs, proofStatus
relations/<artifactStem>/Nargo.toml    # minimal [package] name/type/authors
relations/<artifactStem>/src/main.nr   # fn main(<typed inputs>) { ... asserts/lets }
```

`renderSource` produces a single `fn main(...)` with:

- Public inputs as `name: pub Type` (verifier-visible); private witness params
  without `pub`.
- Native checked `u64` / narrow `u8`/`u16`/`u32` / `u128` (T11) / `Field`
  (bn254) / `bool` temps and ops.
- Constraint body: `let` bindings, `assert(...)` for overflow/zero-div/guards,
  region nesting for if/match/for (predicate-style), call/schedule status/arg
  slots as public inputs.

`renderPackage` is intentionally minimal:

```toml
[package]
name = "pf_relation_<index>"
type = "bin"
authors = ["ProofForge V2"]
```

There is **no** pinned `compiler_version` / backend / CRS field in emitted
`Nargo.toml`. That is correct for a source-only intermediate profile and would
need an explicit product decision before any compile gate.

`ValidatePlanV1` enforces plan canonicity (resource limits, param shape,
continuity, `proofStatus == .notProduced`, failure policy, etc.) before IR
lowering — structure only, not toolchain execution.

### Artifact validator (source-only contract)

`validate_noir_bundle` in `scripts/validate_artifacts.py`:

- Expects source package layout + relations JSON.
- **Rejects** proof-stage leaves: `.acir`, `.proof`, `.vk`, `.witness`.
- Requires Noir non-deployable until nargo/bb proof evidence exists.

Promoting a compile/prove gate must **not** silently start shipping forbidden
proof-stage leaves without a coordinated validator + profile + Tool Lock change.

## Upstream toolchain (research, not product pin)

| Tool | Role | Typical install (upstream, not endorsed pin) |
|---|---|---|
| `nargo` | Noir package manager / compiler driver (`compile`, `execute`, `prove`, `verify`) | Official Noir install (`noirup` / release binaries from noir-lang) |
| `noirc` | Compiler backend invoked by nargo | Bundled with nargo distribution |
| `bb` (Barretenberg CLI) | Common proving backend for Noir | Aztec/Barretenberg releases; selected **separately** from nargo |

Exact versions, binary digests, CRS/profile, and soundness contract are
**not** frozen in this repo. Dossier `docs/targets/07-noir.md` already requires
future `noir-acir-proof-v1` to carry arithmetic / CRS / soundness / proof-binding
/ privacy contract — bare binary alone is insufficient for product registry.

## What an acceptance suite would look like (deferred design)

Pattern parallel to `Tests/Materialization/EvmSolcAcceptance.lean` + optional
`scripts/noir_acceptance.sh`:

1. **Probe**: `command -v nargo` (and later `bb` for prove path); if absent →
   print skip and exit 0 (clean skip, not fail).
2. **Materialize**: product path for representative programs (Counter,
   aggregate-state, Field arithmetic, call/schedule) → staging dir of relation
   packages.
3. **Compile gate (minimum)**: for each relation package directory, run
   `nargo compile` (or current stable equivalent); non-zero → fail closed.
4. **Optional prove/verify (later profile)**: after Tool Lock pin of nargo+bb
   and CRS contract: execute/witness → prove → verify; bind proof artifacts to
   semantic/profile/plan hashes; open profile beyond
   `noir-source-u64-relations-v1`.
5. **CI wiring**: shard registration + optional recipe (justfile change is a
   separate integrator decision); never invent fake proofs when tools absent.

**Not** done this wave: no suite, no script, no justfile recipe, no Tool Lock
asset, no profile promotion.

## Recommendation (decision)

**Do not promote** a Noir nargo/bb acceptance gate in the J1 wave.

| Decision | Detail |
|---|---|
| Maturity stays | **source-only** Plan/IR + relation source packages + Lean relation model |
| Why | Host has no `nargo`/`bb`; Tool Lock has no pin; SPEC `unresolved` still lists nargo/barretenberg; validator intentionally rejects proof-stage leaves; Finalize is zero-tool |
| Compile-only alone | Still **no** — no pin means CI cannot claim a reproducible toolchain; ad-hoc PATH tool would be best-effort, forbidden by product boundaries |
| Prove/verify | Still **no** — depends on compile pin + CRS/soundness contract (RPT-016) |
| Follow-on | When product prioritizes: new ID `NoirCompileAcceptance` (nargo pin + compile skip/fail-closed) and/or `NoirProveAcceptance` (nargo+bb+CRS); then open profile past source-only |

## Explicit non-claims

- Not formal `TST-NOIR-*` completion.
- Not hermetic Stage-0 / release-qualification evidence.
- Not a claim that emitted `.nr` is invalid or that nargo cannot compile it later.
- Does **not** change emitters to emit ACIR/proof/VK/witness.
- Does **not** invent a second acceptance authority or PATH fallback pin.

## Decision table (J1 outcome)

| Gate | Promote now? | Notes |
|---|---|---|
| `nargo compile` acceptance suite | **No** | no host tool, no Tool Lock pin |
| `nargo execute` / witness | **No** | same |
| `nargo prove` / `bb` / verify | **No** | same + no CRS contract |
| Lean relation model only | **Keep** | engineering structure check only |
| Maturity label | **source-only** (unchanged) | coverage matrix §2 remains ❌ |

## Relation to prior research

| Doc | Relationship |
|---|---|
| [`16-noir-prove-path.md`](16-noir-prove-path.md) (RPT-016 / C-4) | Prior prove/verify deferral; J1 re-verifies and broadens to compile-gate question with emit/install detail |
| [`15-aleo-psy-compiler-vm.md`](15-aleo-psy-compiler-vm.md) (RPT-015) | Same class of decision for Aleo/Psy source-only maturity |
| [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md) §2 / C-4 | Authoritative engineering cell; updated with J1 confirmation |

## Host evidence (this worktree)

```text
$ which nargo; which bb
nargo not found
bb not found
$ git rev-parse HEAD
bc7568ef3501aa3ccd70558f691e9b8d964b7e77
```
