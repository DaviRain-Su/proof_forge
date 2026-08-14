# ProofForge WasmCert provider overlay v1

This directory owns the structured NEAR execution wrapper compiled **inside**
WasmCert-Coq 2.2.1 at revision
`9ab0f87f03fff5507749efc273ec662fe27e6d14`. It calls the extracted
`module_type_checker`, instantiator, and `run_one_step` interpreter directly;
it does not parse the upstream human CLI and does not define another Wasm or
ProofForge business semantics.

The strict first host profile implements only these imports:

```text
env.input              env.register_len       env.read_register
env.storage_read       env.storage_write      env.value_return
env.attached_deposit   env.log_utf8            env.panic_utf8
```

It rejects other imports, wrong function types, SIMD, unbounded fuel, unsupported
module/memory shapes, view writes, malformed memory accesses, and resource-limit
violations. Interpreter fuel counts every `run_one_step` call across module
instantiation and export invocation. Wasm traps are preserved as terminal
observations; storage and promises are rolled back at the call boundary.

## Build the overlay

Use a clean checkout at the exact revision and an already-created opam switch
whose required package versions match `opam-packages.v1.lock`:

```bash
scripts/build_wasmcert_provider_v1.sh \
  --source /path/to/WasmCert-Coq \
  --opam-root /path/to/opam-root \
  --switch pf-wasmcert \
  --output build/tools/proof-forge-wasmcert-provider-v1 \
  --repeat-check
```

The script exports the exact upstream tree to a temporary directory, overlays
`proof_forge_wasmcert_provider_v1.ml` and `dune.v1`, builds with one release
worker, probes `--version`, and atomically publishes the local executable.
It accepts only native Linux x86_64 or Darwin arm64, uses the same Python
SHA-256 implementation on both platforms, and `--repeat-check` requires two
independent clean builds to be byte-identical before publication. This makes
the Darwin candidate build runnable without GNU `sha256sum`. Manual matrix run
`31766677105` produced and audited both native candidates; neither archive is
admitted to Tool Lock yet.

Given an already-finalized VerifiedVaultPF Wasm, run the executable acceptance
and the repository's Lean canonical content joins with:

```bash
python3 scripts/wasmcert_provider_smoke_v1.py \
  --provider build/tools/proof-forge-wasmcert-provider-v1 \
  --wasm build/v2/near-runtime/VerifiedVaultPF/VerifiedVaultPF.wasm
```

The five cases are `init`, `deposit`, `withdraw`, `status`, and an overdraw
Wasm-trap/rollback case. After canonical artifact and deterministic host-replay
validation, the Lean consumer runs the sole `ReferenceMachineV1` for the exact
VerifiedVaultPF subject and compares return data, production storage, and
rollback. The Python harness deliberately carries no hand-written business
post-state oracle. Temporary request/result/trace/observation files are removed
after the check.

The machine protocol remains:

```text
proof-forge-wasmcert-provider-v1 \
  check-execute --request <request.pf-jcs.json> --result <result.pf-jcs.json>
```

For a result path `R`, the wrapper writes the already-frozen canonical artifacts
to `R.host-trace.pf-jcs.json` and `R.observation.pf-jcs.json`, then writes `R`.
All paths and semantics-bearing inputs are explicit; stdout/stderr are
diagnostics only.

## Assurance boundary

This overlay source and build recipe do **not** provision the provider. Run
`31766677105` produced byte-identical Darwin arm64 and Linux x86_64 candidates
with executable SHA-256 values
`696b55dd6c02159a5c45f7aba0e1196ee4cc046ac903ffe6b7387763e3399842` and
`c08b1622b5e9593f9803e60977c40f8531e52e9596dc2549fea14edaf2615919`.
The Linux candidate also passed the five-path smoke in a Debian 12 / GLIBC 2.36
orb. Candidate hashes and same-host repeat builds are still not per-platform
Tool Lock identities. Until durable content-addressed assets, runtime closures,
and per-platform lock rows are committed,
`requireWasmCertProviderProvisionedV1` must continue to return
`executableUnprovisioned` and no product target-refinement evidence may consume
provider records.
