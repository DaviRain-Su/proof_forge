# NEAR Sandbox dual-deploy harness

`pf-near-sandbox-dual` deploys ProofForge wasm and a near-sdk reference side by
side, runs the same scenario, and writes `sandbox-report.json`.

## Layout (NC-H1)

| Path | Role |
|------|------|
| `src/main.rs` | CLI, sandbox start, dual-side orchestration |
| `src/kind.rs` | `ContractKind` parse / display |
| `src/report.rs` | `Args`, `SideReport`, `write_dual_report` |
| `src/host.rs` | deploy/call/view helpers + **`SideCtx`** (collapses step boilerplate) |
| `src/scenarios/` | one module per contract; **`run_side` registry** in `mod.rs` |

## Add a contract

1. Add `ContractKind` arm in `kind.rs`.
2. Add `scenarios/<name>.rs` implementing `run_*_side(worker, wasm, SideKind)`.
3. Register in `scenarios/mod.rs` `run_side` match.
4. Prefer `SideCtx` for simple dual PF-raw / sdk-json scenarios:

```rust
let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
if ctx.is_pf() {
    ctx.call_raw("init", &[], "PF init").await?;
    ctx.view_raw_u64("get", "PF get", Some(0)).await?;
} else {
    ctx.call_json("init", json!({}), "sdk init").await?;
    ctx.view_json_u64("get", json!({}), "sdk get", Some(0)).await?;
}
ctx.finish().await
```

Remote-call is special-cased in `main` (peer rebuild + multi-account).

## Run

Invoked by the compare driver:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- \
  near <contract> --live
```
