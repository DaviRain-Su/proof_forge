/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — Protocols

Clients for **on-chain programs / interfaces already in the ecosystem**.

Not the host runtime (Layer A: Capability / HostBridge / syscalls).
Not deployable stdlib mixins (Layer C: `Contract.Stdlib`).

See `docs/protocols-layer.md`.
-/
import ProofForge.Protocols.Solana
import ProofForge.Protocols.Evm.IERC20
import ProofForge.Protocols.Evm.IERC20Permit
import ProofForge.Protocols.Evm.IERC4626
import ProofForge.Protocols.Evm.IERC721
import ProofForge.Protocols.Evm.Multicall
import ProofForge.Protocols.Evm.Permit2
import ProofForge.Protocols.Near.FungibleToken

namespace ProofForge.Protocols

/-- Product layer tag for docs and diagnostics. -/
def layerId : String := "protocols"

/-- Primary hosts with a Protocols catalog entry. -/
def primaryHosts : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

end ProofForge.Protocols
