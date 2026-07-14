/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Opt-in adapter: ProofForge sBPF bytes → solanalib.SBPF

Mirrors `ProofForgeFormal/Evm/PowdrAdapter.lean`: this module is **outside** the
default `ProofForge` root. Building the `ProofForgeFormalSolana` Lake target pulls
`solanalib` (and its mathlib pin) and reinterprets the mathlib-free
`BpfEncode.BpfBinBytes` seam as `Solanalib.SBPF.BpfBin`.

Default CLI / product gates stay free of solanalib. Opt-in via:

```
just solana-solanalib-adapter
# or
lake build ProofForgeFormalSolana
```
-/

import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract
import Solanalib.SBPF.CommType
import Solanalib.SBPF.Syntax
import Solanalib.SBPF.Decoder
import Solanalib.SBPF.Verifier
import Solanalib.SBPF.Interpreter
import Solanalib.SBPF.State

namespace ProofForgeFormal.Solana.SolanalibAdapter

open ProofForge.Backend.Solana.BpfEncode
open ProofForge.IR
open Solanalib.SBPF

/-- Convert a single byte `Nat` (`0..255`) into solanalib `U8`. -/
def u8OfNat (n : Nat) : U8 :=
  BitVec.ofNat 8 n

/-- Convert the mathlib-free byte array into solanalib `BpfBin`. -/
def toBpfBin (bytes : BpfBinBytes) : BpfBin :=
  (bytes.map u8OfNat).toList

/-- Lower an IR module all the way to solanalib `BpfBin`. -/
def lowerModuleToBpfBin (module : Module) : Except String BpfBin :=
  match ProofForge.Backend.Solana.BpfEncode.lowerModuleToBpfBin module with
  | .error msg => .error msg
  | .ok bytes => .ok (toBpfBin bytes)

/-- Decode every instruction slot in a `BpfBin` (handles 16-byte `ldImm`).

Fuel-bounded on the remaining slot count so the Lean kernel accepts the
recursion without a custom well-founded proof. -/
def decodeAll (bin : BpfBin) : Except String (List BpfInstruction) :=
  let maxSlots := bin.length / 8 + 1
  go maxSlots 0 []
where
  go : Nat → Nat → List BpfInstruction → Except String (List BpfInstruction)
    | 0, _, _ => .error "solanalib decode: fuel exhausted"
    | fuel + 1, pc, acc =>
        if bin.length ≤ pc * 8 then
          .ok acc.reverse
        else
          match findInstr pc bin with
          | none => .error s!"solanalib decode failed at pc={pc}"
          | some ins =>
              -- ldImm consumes two slots; findInstr already reads 16 bytes, so
              -- advance by 2 when the opcode at this pc is 0x18.
              let opc := bin.getD (pc * 8) 0
              let step := if opc = 0x18 then 2 else 1
              go fuel (pc + step) (ins :: acc)

/-- Instruction-level verifier over a whole program (v1 ISA, matching the
Counter/ValueVault emit class). -/
def verifyAll (insns : List BpfInstruction) (sv : SBPFV := .v1) : Bool :=
  insns.all (fun ins => verifyInstr ins sv)

/-- Encode + decode + verify pipeline for an IR module. -/
def moduleVerifyOk (module : Module) : Bool :=
  match lowerModuleToBpfBin module with
  | .error _ => false
  | .ok bin =>
      match decodeAll bin with
      | .error _ => false
      | .ok insns =>
          !insns.isEmpty && verifyAll insns .v1

/-- Fuel-bounded solanalib interpreter entry (for future differential gates).

`bpfInterp fuel prog state enableCallDepth programVmAddr` — this does **not**
yet wire Solana account input memory or syscall handlers; those stay on the
ProofForge `SbpfInterpreter` / external Mollusk path until a host bridge is
designed. The surface exists so CompileCorrect can name `bpfInterp` without
inventing a second driver. -/
def runBpfInterp (bin : BpfBin) (fuel : Nat) (sv : SBPFV := .v1) : BpfState :=
  bpfInterp fuel bin (initBpfState initRegMap initMem (BitVec.ofNat 64 fuel) sv) false 0

/-- Round-trip smoke: encode bytes are well-formed and solanalib decodes at
least one instruction for the Counter module. -/
def counterPipelineOk : Bool :=
  moduleVerifyOk ProofForge.IR.Examples.Counter.module

end ProofForgeFormal.Solana.SolanalibAdapter
