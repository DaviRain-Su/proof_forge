/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Solana compatibility wrapper for the canonical portable Counter.

The contract logic lives in `Examples.Shared.Counter`; this file preserves the
historical Solana example path for docs and local experiments. Use the shared
source directly when demonstrating target-independent authoring.

Compile the shared source to sBPF assembly:
  lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format s \
    -o build/solana/Counter.s \
    --artifact-output build/solana/proof-forge-artifact.json

The command above emits the same shape as this example because the backend's
Phase 1 fixture mirrors this module. A `manifest.toml` is written alongside
the `.s` describing the instruction dispatch and the single writable account.

Build the Solana ELF (requires `sbpf` on PATH):
  lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format elf -o build/solana/Counter.so
-/

import Examples.Shared.Counter

namespace Examples.Solana.Counter

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.Counter.spec

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Solana.Counter
