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
  --output build/tools/proof-forge-wasmcert-provider-v1
```

The script exports the exact upstream tree to a temporary directory, overlays
`proof_forge_wasmcert_provider_v1.ml` and `dune.v1`, builds with one release
worker, probes `--version`, and atomically publishes the local executable.

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

This overlay source and build recipe do **not** provision the provider. Two clean
same-host builds in the current Linux orb produced identical bytes with SHA-256
`3c6af34d068e08cd34ea6bf627ec1c1e597f5577f163d89f5f63f462303b0ad4`, but a
local ELF hash or same-host repeat is not a per-platform Tool Lock identity.
Until a real executable artifact, runtime dependency closure, version probe,
and per-platform lock rows are committed,
`requireWasmCertProviderProvisionedV1` must continue to return
`executableUnprovisioned` and no product target-refinement evidence may consume
provider records.
