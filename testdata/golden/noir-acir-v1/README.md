# noir-acir-v1 golden (NOIR-IR-1 + IR-2 + IR-3/G3 + IR-4 multi-fixture + IR-5 honesty + IR-6 dual-write)

Frozen **Examples/Counter** product Noir relation packages plus locked
**nargo 1.0.0-beta.26** `nargo compile` ProgramArtifact JSON, plus IR-4
path-normalized multi-fixture admit inventory under `fixtures/`.

## Authority

- **Target authority direction:** ACIR / nargo circuit artifacts (not sole `.nr`).
- **IR-1 freeze:** multi-file exact SHA-256 inventory of path-normalized nargo
  ProgramArtifact JSON + product package sources.
- **IR-2 Plan→ACIR MVP:** sole path = **nargo-assisted capture** from product
  Plan emit (not pure-Lean ACIR opcode encoder). Counter product `.nr` packages
  must byte-match `product/relations/*`; when nargo is present, compile of those
  packages must match circuit core (`noir_version`+`hash`+`bytecode`) of
  `nargo-compile/*`. See `ProofForgeV2/Targets/Noir/Acir/CaptureV1.lean`.
- **IR-3 / G3 admit surface:** circuit-hash pins for control-flow / aggregate
  product fixtures already admitted by Noir Plan — BranchCounter (if), LoopSum
  (for), OptionState, ArrayRet full capture; MapMini init capture + put/get
  **nargo type residual** (Plan emits packages; locked nargo compile fails —
  honesty pin, not silent pass). Live capture honest-skips when nargo is
  missing; package-stem pins always run.
- **IR-4 multi-fixture inventory:** path-normalized ProgramArtifact leaves under
  `fixtures/{FixtureId}/nargo-compile/{stem}/*.json` (14 nargo-ok relations =
  G3 success pins) + `inventory-admit.json` + Lean `admitInventoryEntriesV1`.
  **Not** a full product-source byte matrix. MapMini put/get have **no** inventory
  leaves (honesty residual). Inventory pin always runs; live recheck skips
  without nargo.
- **IR-5 / G5 honesty matrix:** §3.2 status column in
  `CaptureV1.honestyMatrixRowsV1` + `NoirAcirV1` FC pins —
  call/schedule **P** (witness-binding only, never ACIR Y),
  String state / Option non-UInt64 **F** (plan-FC),
  prove/VK **F** (Finalize `deployable=false`; no product prove). No false Y.
- **IR-6 / G4 product dual-write:** default profile
  `noir-source-u64-relations-v1` remains **zero-tool** Finalize (`.nr`
  transitional/debug base). Explicit profile
  `noir-nargo-1.0.0-beta.26-acir-v1` dual-writes path-normalized ProgramArtifact
  JSON as `finalized-extra` under `nargo-compile/{stem}/*.json` (Counter extras
  ≡ this golden when nargo is present). Missing nargo on ACIR profile →
  `PF-TOOLCHAIN-MISSING`. Still `deployable=false`; no prove/VK.
- **Not claimed:** ACIR opcode decode, prove/verify, deployable, formal.

## Tool pin

| Field | Value |
|---|---|
| Tool Lock id | `nargo` |
| Version | `1.0.0-beta.26` |
| Exact `noir_version` in artifacts | `1.0.0-beta.26+40d6574f851d926f93e0c3a271bac3e6e82ac905` |
| Git hash | `40d6574f851d926f93e0c3a271bac3e6e82ac905` |
| Default profile | `noir-source-u64-relations-v1` (zero-tool) |
| ACIR dual-write profile | `noir-nargo-1.0.0-beta.26-acir-v1` (IR-6) |

## Layout

```
inventory.json                 Counter multi-file inventory (IR-1)
inventory-admit.json           multi-fixture admit inventory (IR-4)
product/
  Counter.noir-relations.json  product relation IR summary
  relations/r0-init/…          Nargo.toml + src/main.nr (init)
  relations/r1-increment/…     increment entry
  relations/r2-get/…           get view
nargo-compile/
  r0-init/pf_relation_0.json   path-normalized ProgramArtifact (Counter)
  r1-increment/pf_relation_1.json
  r2-get/pf_relation_2.json
fixtures/
  BranchCounter/nargo-compile/…  IR-4 path-normalized ProgramArtifact
  LoopSum/nargo-compile/…
  OptionState/nargo-compile/…
  ArrayRet/nargo-compile/…
  MapMini/nargo-compile/r0-init/…  (init only; put/get residual absent)
```

## Normalization

Raw `nargo compile` writes absolute `file_map.*.path` (host-local). Golden files
rewrite that field to package-relative `src/main.nr`. All other fields
(`noir_version`, `hash`, `abi`, `bytecode`, `debug_symbols`, `file_map` source
text) are otherwise byte-stable for the pinned nargo on the same sources.

JSON encoding: compact `json.dumps(..., separators=(',', ':'))` + trailing
newline.

## ProgramArtifact envelope (observed nargo 1.0.0-beta.26)

Top-level keys (exact set):

- `noir_version` (string)
- `hash` (decimal string circuit identity)
- `abi` (parameters / return_type / error_types)
- `bytecode` (base64 of gzip-compressed ACIR)
- `debug_symbols` (base64)
- `file_map` (source debug map; path normalized in golden)

Full ACIR opcode schema is **not** frozen here — only inventory + envelope.

## Capture recipe (engineering)

```bash
# product package
lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean \
  --module Examples.Counter --target noir -o build/v2/noir-acir-capture
# compile each relations/* package with locked nargo
# normalize file_map.path → src/main.nr; write under nargo-compile/
```

Live recheck is optional when nargo is present; missing nargo → suite skip
honesty for **live capture paths only** (Counter inventory pin, IR-4 admit
inventory pin, Counter product source-join, and G3 package-stem pins still run
from frozen files / product Plan emit).

## Non-goals

- Default-profile Finalize does **not** invoke nargo (zero-tool honesty).
- No prove/verify/VK/witness product leaves.
- `deployable=false` on both Noir profiles.
- No pure-Lean ACIR opcode encoder (IR-2 decision: nargo-assisted only).
- IR-4 does **not** freeze product-source leaves for fixtures (compile inventory
  only); MapMini put/get remain honesty residuals without inventory leaves.
