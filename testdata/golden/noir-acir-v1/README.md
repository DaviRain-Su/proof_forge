# noir-acir-v1 golden (NOIR-IR-1 + IR-2 + IR-3/G3)

Frozen **Examples/Counter** product Noir relation packages plus locked
**nargo 1.0.0-beta.26** `nargo compile` ProgramArtifact JSON.

## Authority

- **Target authority direction:** ACIR / nargo circuit artifacts (not sole `.nr`).
- **IR-1 freeze:** multi-file exact SHA-256 inventory of path-normalized nargo
  ProgramArtifact JSON + product package sources.
- **IR-2 Plan→ACIR MVP:** sole path = **nargo-assisted capture** from product
  Plan emit (not pure-Lean ACIR opcode encoder). Counter product `.nr` packages
  must byte-match `product/relations/*`; when nargo is present, compile of those
  packages must match circuit core (`noir_version`+`hash`+`bytecode`) of
  `nargo-compile/*`. See `ProofForgeV2/Targets/Noir/Acir/CaptureV1.lean`.
- **IR-3 / G3 admit surface:** circuit-hash pins (not multi-file inventory here)
  for control-flow / aggregate product fixtures already admitted by Noir Plan —
  BranchCounter (if), LoopSum (for), OptionState, ArrayRet full capture;
  MapMini init capture + put/get **nargo type residual** (Plan emits packages;
  locked nargo compile fails — honesty pin, not silent pass). Live capture
  honest-skips when nargo is missing; package-stem pins always run.
- **Not claimed:** ACIR opcode decode, product ACIR OutputFile (IR-6),
  prove/verify, deployable, formal.

## Tool pin

| Field | Value |
|---|---|
| Tool Lock id | `nargo` |
| Version | `1.0.0-beta.26` |
| Exact `noir_version` in artifacts | `1.0.0-beta.26+40d6574f851d926f93e0c3a271bac3e6e82ac905` |
| Git hash | `40d6574f851d926f93e0c3a271bac3e6e82ac905` |
| Profile | `noir-source-u64-relations-v1` |

## Layout

```
inventory.json                 multi-file inventory (documentation + pins)
product/
  Counter.noir-relations.json  product relation IR summary
  relations/r0-init/…          Nargo.toml + src/main.nr (init)
  relations/r1-increment/…     increment entry
  relations/r2-get/…           get view
nargo-compile/
  r0-init/pf_relation_0.json   path-normalized ProgramArtifact
  r1-increment/pf_relation_1.json
  r2-get/pf_relation_2.json
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
honesty for **live capture paths only** (Counter inventory pin, Counter product
source-join, and G3 package-stem pins still run from frozen files / product
Plan emit).

## Non-goals

- Product Finalize does **not** ship these as OutputFile yet (IR-6).
- No prove/verify/VK/witness product leaves.
- `deployable=false`.
- No pure-Lean ACIR opcode encoder (IR-2 decision: nargo-assisted only).
- G3 does **not** expand this directory with multi-fixture ProgramArtifact
  inventory (optional IR-4); pins live in `CaptureV1.admitSurfaceFixturesV1`.
