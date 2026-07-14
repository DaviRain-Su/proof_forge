import ProofForge.Contract.Source.Solana.Internal.Authored

/-! # Solana source internals

This module exposes only the direct Authored builder seam. Target-specific
payload schemas live under `Target.HostOps.Solana`; public source macros lower
to those schemas without constructing `ContractSpec`, `IR.Module`, or a Legacy
Solana intent.
-/
