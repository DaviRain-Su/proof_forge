import ProofForgeV2.Targets.Solana.SbpfProviderStepV1

/-!
# Solana StateCell `get` provider certificate

Sparse, kernel-checkable execution certificates for the production StateCell
`get` path. This first slice proves the eight-step Loader V3 input-shape
dispatch prefix. It is parameterized by exact provider `Program` lookups and
relevant input-memory reads, so it neither clones a proof-only program nor
claims that those assumptions are already bound to the production artifact.

Later slices continue from `StateCellGetPc10V1`. Closing the full 55-step path
and separately deriving the lookup assumptions from the identity-bound strict
artifact parser remain required before this can discharge the provider
execution equation in `SbpfHandlerJoinV1`.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics
open ProviderStepV1

/-- Exact fetched instructions for the first production StateCell `get`
dispatch segment. This is a sparse lookup contract, not another program. -/
structure StateCellGetDispatchPrefixProgramV1 (program : Program) : Prop where
  pc0 : program[0]? = some (.binReg .Mov64Reg 6 1)
  pc1 : program[1]? = some (.loadMem .Ldxdw 1 6 0)
  pc2 : program[2]? = some (.jumpImm .JneImm 1 1 5)
  pc3 : program[3]? = some (.loadMem .Ldxb 1 6 8)
  pc4 : program[4]? = some (.jumpImm .JneImm 1 255 3)
  pc5 : program[5]? = some (.loadMem .Ldxdw 1 6 10360)
  pc6 : program[6]? = some (.jumpImm .JltImm 1 8 1)
  pc7 : program[7]? = some (.ja 2)

/-- Sparse Loader V3 input reads needed by the first dispatch segment. -/
structure StateCellGetDispatchPrefixInputV1 (input : Array UInt8) : Prop where
  accountCount :
    (Machine.entry input).mem.readU64 (inputStart + 0#64) = some 1
  accountMarker :
    (Machine.entry input).mem.readU8 (inputStart + 8#64) = some 255
  instructionDataLength :
    (Machine.entry input).mem.readU64 (inputStart + 10360#64) = some 8

/-- Provider machine facts retained at PC 10 for the next sparse certificate
segment. This predicate only describes one provider state. -/
structure StateCellGetPc10V1 (input : Array UInt8) (machine : Machine) : Prop where
  pc : machine.pc = 10
  halted : machine.halted = none
  memory : machine.mem = (Machine.entry input).mem
  frames : machine.frames = []
  maxDepth : machine.maxDepth = defaultMaxCallDepth
  returnData : machine.returnData = #[]
  inputBase : machine.getReg 6 = inputStart
  framePointer : machine.getReg 10 = (Machine.entry input).getReg 10

/-- The provider executes the first eight production StateCell `get` path
instructions and reaches PC 10 without mutating memory or call state. -/
theorem stateCellGet_dispatchPrefix_stepsV1
    (program : Program)
    (input : Array UInt8)
    (programRel : StateCellGetDispatchPrefixProgramV1 program)
    (inputRel : StateCellGetDispatchPrefixInputV1 input) :
    ∃ machine,
      Steps asmDefaultHost program 8 (Machine.entry input) machine ∧
      StateCellGetPc10V1 input machine := by
  let m0 := Machine.entry input
  let m1 := put64 m0 6 inputStart
  let m2 := put64 m1 1 1
  let m3 := condJump m2 (1 != 1) 5
  let m4 := put64 m3 1 255
  let m5 := condJump m4 (255 != 255) 3
  let m6 := put64 m5 1 8
  let m7 := condJump m6 (8 < 8) 1
  let m8 := doJump m7 2
  have haddr0 : calcAddr inputStart 0 = inputStart + 0#64 := by decide
  have haddr8 : calcAddr inputStart 8 = inputStart + 8#64 := by decide
  have haddr10360 :
      calcAddr inputStart 10360 = inputStart + 10360#64 := by
    decide
  refine ⟨m8, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        (by simp)
        (by simpa [m0] using programRel.pc0)
        (by simp [m0, m1])
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m0, m1])
        (by simpa [m0, m1] using programRel.pc1)
        (by
          apply execInstrLdxdw
          · simp [m0, m1]
          · simp only [m1, put64_mem, put64_getReg_same]
            have hread := inputRel.accountCount
            rw [← haddr0] at hread
            simpa [m0, m1] using hread)
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m0, m1, m2])
        (by simpa [m0, m1, m2] using programRel.pc2)
        (by simp [m0, m1, m2, m3, condJump])
    apply Steps.succ (m' := m4)
    · exact step_of_fetch_exec
        (by simp [m0, m1, m2, m3, condJump])
        (by
          simpa [m0, m1, m2, m3, condJump] using programRel.pc3)
        (by
          apply execInstrLdxb
          · simp [m0, m1, m2, m3, condJump]
          · simp [m0, m1, m2, m3, condJump]
            have hread := inputRel.accountMarker
            rw [← haddr8] at hread
            simpa [m0, m1, m2, m3, condJump] using hread)
    apply Steps.succ (m' := m5)
    · exact step_of_fetch_exec
        (by simp [m0, m1, m2, m3, m4, condJump])
        (by
          simpa [m0, m1, m2, m3, m4, condJump] using programRel.pc4)
        (by simp [m0, m1, m2, m3, m4, m5, condJump])
    apply Steps.succ (m' := m6)
    · exact step_of_fetch_exec
        (by simp [m0, m1, m2, m3, m4, m5, condJump])
        (by
          simpa [m0, m1, m2, m3, m4, m5, condJump] using
            programRel.pc5)
        (by
          apply execInstrLdxdw
          · simp [m0, m1, m2, m3, m4, m5, condJump]
          · simp [m0, m1, m2, m3, m4, m5, condJump]
            have hread := inputRel.instructionDataLength
            rw [← haddr10360] at hread
            simpa [m0, m1, m2, m3, m4, m5, condJump] using hread)
    apply Steps.succ (m' := m7)
    · exact step_of_fetch_exec
        (by simp [m0, m1, m2, m3, m4, m5, m6, condJump])
        (by
          simpa [m0, m1, m2, m3, m4, m5, m6, condJump] using
            programRel.pc6)
        (by simp [m0, m1, m2, m3, m4, m5, m6, m7, condJump])
    apply Steps.succ (m' := m8)
    · exact step_of_fetch_exec
        (by simp [m0, m1, m2, m3, m4, m5, m6, m7, condJump])
        (by
          simpa [m0, m1, m2, m3, m4, m5, m6, m7, condJump] using
            programRel.pc7)
        (by
          simpa [m8] using
            (execInstrJa asmDefaultHost m7 2
              (by
                simp [m0, m1, m2, m3, m4, m5, m6, m7,
                  condJump])))
    exact Steps.zero _
  · constructor <;>
      simp [m8, m7, m6, m5, m4, m3, m2, m1, m0, doJump,
        condJump]

end ProofForgeV2.Targets.Solana
