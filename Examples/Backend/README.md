# Backend examples (not product)

This tree is for **compiler engineers**: goldens, chain Surfaces, live/Pinocchio
gates, and research spikes.

**Application authors should use [`../Product/`](../Product/) only.**

```text
Author path:  Examples/Product/*.lean + --target …
This path:    fixtures · goldens · Source.Solana · Learn · spikes
```

| Subtree | Notes |
|---------|--------|
| `Evm/` | Golden Yul, Foundry, proxy/constructor probes |
| `Solana/` | Golden sBPF + manifests; may re-export Product Counter |
| `WasmNear/` | Golden WAT + Layer B `FtPeerClient` (NEP-141 peer, not stdlib FT body) |
| `Stylus/` | Nitro deployment peers and target-only live fixtures |
| `Learn/` | Legacy parser fixtures |
| `Psy/`, `Aleo/`, `Aptos/`, `CosmWasm/`, `CloudflareWorkers/`, `near/` | Target research |

Source.Solana / NEAR host-extension syntax here is **fixture-only**, not the
portable product API (see product-authoring-architecture C.4).
