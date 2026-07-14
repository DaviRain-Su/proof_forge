import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.LabeledSbpf
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

/-! ## sBPF binary encoder + labeled assembly smoke (mathlib-free default path)

Pins that EmitSBPF output for Counter (and ValueVault) encodes to a
well-formed `BpfBinBytes` list — the seam that the opt-in solanalib adapter
consumes — and that the Scheme 2 labeled view matches that encode.
No solanalib / mathlib import.
-/

namespace ProofForge.Tests.SolanaBpfEncode

open ProofForge.Backend.Solana.BpfEncode
open ProofForge.Backend.Solana.LabeledSbpf
open ProofForge.Backend.Solana.Asm

/-- exit encodes to the single slot `95 00 00 00 00 00 00 00`. -/
def exitBytes : BpfBinBytes :=
  match encodeResolved { opcode := .exit } with
  | .ok b => b
  | .error _ => #[]

theorem exit_encode_ok :
    exitBytes = #[0x95, 0, 0, 0, 0, 0, 0, 0] := by
  native_decide

/-- mov64 r0, 1 → opcode 0xb7, dst=0, imm=1. -/
def mov64r0imm1 : BpfBinBytes :=
  match encodeResolved { opcode := .mov64, dst := 0, immBits := 1 } with
  | .ok b => b
  | .error _ => #[]

theorem mov64_imm_encode_ok :
    mov64r0imm1 = #[0xb7, 0, 0, 0, 1, 0, 0, 0] := by
  native_decide

/-- add64 r3, r4 (reg form) → opcode 0x0f, dst=3, src=4. -/
def add64r3r4 : BpfBinBytes :=
  match encodeResolved { opcode := .add64, dst := 3, src := 4, usesRegSrc := true } with
  | .ok b => b
  | .error _ => #[]

theorem add64_reg_encode_ok :
    add64r3r4 = #[0x0f, 0x43, 0, 0, 0, 0, 0, 0] := by
  native_decide

/-- Local helper calls use the eBPF pseudo-call source tag and a relative
instruction offset; they are not hashed as runtime syscalls. -/
def internalCallEncodesOk : Bool :=
  match toBpfBin #[
    .instruction { opcode := .call, imm := some (.sym "helper") },
    .instruction { opcode := .exit },
    .label "helper",
    .instruction { opcode := .exit }
  ] with
  | .ok bytes => bytes == #[
      0x85, 0x10, 0, 0, 1, 0, 0, 0,
      0x95, 0, 0, 0, 0, 0, 0, 0,
      0x95, 0, 0, 0, 0, 0, 0, 0]
  | .error _ => false

theorem internal_call_encode_ok :
    internalCallEncodesOk = true := by
  native_decide

theorem allocator_syscall_id_ok :
    syscallId? "sol_alloc_free_" = some 0x83f00e8f := by
  native_decide

theorem counter_module_encodes_ok :
    moduleEncodesOk ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem value_vault_module_encodes_ok :
    moduleEncodesOk
      ProofForge.IR.Examples.ValueVault.module = true := by
  native_decide

#check counter_labeled_ok
#check counter_labeled_matches_encode

theorem value_vault_labeled_ok :
    moduleLabeledOk ProofForge.IR.Examples.ValueVault.module = true := by
  native_decide

end ProofForge.Tests.SolanaBpfEncode

def main : IO UInt32 := do
  IO.println "solana-bpf-encode-smoke: unit opcodes + Counter/ValueVault encode + labeled view checked"
  return 0
