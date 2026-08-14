import ProofForgeV2.Targets.Solana.SbpfProviderStepV1
import ProofForgeV2.Targets.Solana.SbpfArtifactV1

/-!
# Solana StateCell `get` provider certificate

Sparse, kernel-checkable execution certificates for the complete 55-step
production StateCell `get` path. An executable, sound checker binds every
instruction lookup used by the certificate to an exact production artifact
identity; a second executable, sound checker binds every sparse read to a
concrete Loader input. A proof-bearing provider evaluator derives the two stack
store effects and fails closed when the stores or resulting reads differ. The
module neither clones a proof-only program nor claims a complete source-to-sBPF
refinement theorem.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics
open ProviderStepV1

/-- Exact current production StateCell `.s` identity. This is the sole identity
    used by the strict artifact gate, provider certificate, and HandlerIR join. -/
def stateCellProductionSbpfSha256V1 : String :=
  "c93b1448aa782550b7643ccced44209c57df604a866c236552dadc5ac6a159c1"

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

instance (program : Program) :
    Decidable (StateCellGetDispatchPrefixProgramV1 program) := by
  let checks : Prop :=
    (program[0]? = some (.binReg .Mov64Reg 6 1) ∧
      program[1]? = some (.loadMem .Ldxdw 1 6 0) ∧
      program[2]? = some (.jumpImm .JneImm 1 1 5) ∧
      program[3]? = some (.loadMem .Ldxb 1 6 8) ∧
      program[4]? = some (.jumpImm .JneImm 1 255 3) ∧
      program[5]? = some (.loadMem .Ldxdw 1 6 10360) ∧
      program[6]? = some (.jumpImm .JltImm 1 8 1) ∧
      program[7]? = some (.ja 2))
  apply decidable_of_iff checks
  constructor
  · rintro ⟨h0, h1, h2, h3, h4, h5, h6, h7⟩
    exact ⟨h0, h1, h2, h3, h4, h5, h6, h7⟩
  · intro h
    exact ⟨h.pc0, h.pc1, h.pc2, h.pc3, h.pc4, h.pc5, h.pc6, h.pc7⟩

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
  savedR7 : machine.getReg 7 = (Machine.entry input).getReg 7
  savedR8 : machine.getReg 8 = (Machine.entry input).getReg 8
  savedR9 : machine.getReg 9 = (Machine.entry input).getReg 9
  framePointer : machine.getReg 10 = (Machine.entry input).getReg 10

/-- Exact fetched instructions for the production StateCell method-dispatch
segment. The two preceding discriminators are rejected before the `get`
discriminator is accepted and its relative call enters PC 128. -/
structure StateCellGetMethodDispatchProgramV1 (program : Program) : Prop where
  pc10 : program[10]? = some (.loadMem .Ldxdw 1 6 10368)
  pc11 : program[11]? = some (.lddw 2 7217115878876727646)
  pc12 : program[12]? = some (.jumpReg .JneReg 1 2 2)
  pc15 : program[15]? = some (.lddw 2 2467651336600536989)
  pc16 : program[16]? = some (.jumpReg .JneReg 1 2 2)
  pc19 : program[19]? = some (.lddw 2 4025532893697057444)
  pc20 : program[20]? = some (.jumpReg .JneReg 1 2 2)
  pc21 : program[21]? = some (.callRel 106)

instance (program : Program) :
    Decidable (StateCellGetMethodDispatchProgramV1 program) := by
  let checks : Prop :=
    (program[10]? = some (.loadMem .Ldxdw 1 6 10368) ∧
      program[11]? = some (.lddw 2 7217115878876727646) ∧
      program[12]? = some (.jumpReg .JneReg 1 2 2) ∧
      program[15]? = some (.lddw 2 2467651336600536989) ∧
      program[16]? = some (.jumpReg .JneReg 1 2 2) ∧
      program[19]? = some (.lddw 2 4025532893697057444) ∧
      program[20]? = some (.jumpReg .JneReg 1 2 2) ∧
      program[21]? = some (.callRel 106))
  apply decidable_of_iff checks
  constructor
  · rintro ⟨h10, h11, h12, h15, h16, h19, h20, h21⟩
    exact ⟨h10, h11, h12, h15, h16, h19, h20, h21⟩
  · intro h
    exact ⟨h.pc10, h.pc11, h.pc12, h.pc15, h.pc16, h.pc19, h.pc20,
      h.pc21⟩

/-- Sparse Loader V3 instruction-data read used by method dispatch. -/
structure StateCellGetMethodDispatchInputV1 (input : Array UInt8) : Prop where
  discriminator :
    (Machine.entry input).mem.readU64 (inputStart + 10368#64) =
      some 4025532893697057444

/-- Provider machine facts while the production StateCell `get` call is active.
The exact call frame is retained so the later body certificate can prove that
PC 167 returns to the dispatcher exit at PC 22. -/
structure StateCellGetActiveCallV1 (input : Array UInt8) (expectedPc : Nat)
    (machine : Machine) : Prop where
  pc : machine.pc = expectedPc
  halted : machine.halted = none
  memory : machine.mem = (Machine.entry input).mem
  frames : machine.frames = [{
    returnPc := 22
    savedR6 := inputStart
    savedR7 := (Machine.entry input).getReg 7
    savedR8 := (Machine.entry input).getReg 8
    savedR9 := (Machine.entry input).getReg 9
    savedFp := (Machine.entry input).getReg 10
  }]
  maxDepth : machine.maxDepth = defaultMaxCallDepth
  returnData : machine.returnData = #[]
  inputBase : machine.getReg 6 = inputStart
  framePointer :
    machine.getReg 10 = (Machine.entry input).getReg 10 + stackFrameSize

/-- Entry to the production StateCell `get` body. -/
abbrev StateCellGetPc128V1 (input : Array UInt8) (machine : Machine) : Prop :=
  StateCellGetActiveCallV1 input 128 machine

/-- Start of the owner/program-id validation block. -/
abbrev StateCellGetPc138V1 (input : Array UInt8) (machine : Machine) : Prop :=
  StateCellGetActiveCallV1 input 138 machine ∧
    machine.getReg 2 = inputStart + 10376#64

/-- Entry to the state-layout validation block after owner/program-id checks. -/
abbrev StateCellGetPc150V1 (input : Array UInt8) (machine : Machine) : Prop :=
  StateCellGetActiveCallV1 input 150 machine

/-- Entry to the return-data epilogue after all `get` body validation. -/
abbrev StateCellGetPc158V1 (input : Array UInt8) (machine : Machine) : Prop :=
  StateCellGetActiveCallV1 input 158 machine

/-- Final provider facts needed by the HandlerIR/provider observation join. -/
structure StateCellGetReturnedV1 (input returnBytes : Array UInt8)
    (machine : Machine) : Prop where
  pc : machine.pc = 22
  halted : machine.halted = some 0
  frames : machine.frames = []
  inputMemory : machine.mem.input = (Machine.entry input).mem.input
  returnData : machine.returnData = returnBytes
  result : machine.getReg 0 = 0
  framePointer : machine.getReg 10 = (Machine.entry input).getReg 10

/-- Provider facts after `sol_set_return_data` and before the two exits. -/
structure StateCellGetPc166V1 (input returnBytes : Array UInt8)
    (machine : Machine) : Prop where
  pc : machine.pc = 166
  halted : machine.halted = none
  inputMemory : machine.mem.input = (Machine.entry input).mem.input
  frames : machine.frames = [{
    returnPc := 22
    savedR6 := inputStart
    savedR7 := (Machine.entry input).getReg 7
    savedR8 := (Machine.entry input).getReg 8
    savedR9 := (Machine.entry input).getReg 9
    savedFp := (Machine.entry input).getReg 10
  }]
  returnData : machine.returnData = returnBytes
  framePointer :
    machine.getReg 10 = (Machine.entry input).getReg 10 + stackFrameSize

/-- Provider facts after the two stack stores and before return-data setup. -/
structure StateCellGetPc162V1 (input : Array UInt8) (origin : Machine)
    (storedMemory : Memory) (machine : Machine) : Prop where
  pc : machine.pc = 162
  halted : machine.halted = none
  memory : machine.mem = storedMemory
  frames : machine.frames = [{
    returnPc := 22
    savedR6 := inputStart
    savedR7 := (Machine.entry input).getReg 7
    savedR8 := (Machine.entry input).getReg 8
    savedR9 := (Machine.entry input).getReg 9
    savedFp := (Machine.entry input).getReg 10
  }]
  returnData : machine.returnData = #[]
  framePointer : machine.getReg 10 = origin.getReg 10

/-- Provider facts immediately before `sol_set_return_data`. -/
structure StateCellGetPc165V1 (input : Array UInt8) (origin : Machine)
    (storedMemory : Memory) (machine : Machine) : Prop where
  pc : machine.pc = 165
  halted : machine.halted = none
  memory : machine.mem = storedMemory
  frames : machine.frames = [{
    returnPc := 22
    savedR6 := inputStart
    savedR7 := (Machine.entry input).getReg 7
    savedR8 := (Machine.entry input).getReg 8
    savedR9 := (Machine.entry input).getReg 9
    savedFp := (Machine.entry input).getReg 10
  }]
  returnData : machine.returnData = #[]
  framePointer : machine.getReg 10 = origin.getReg 10
  returnPointer :
    machine.getReg 1 = origin.getReg 10 + BitVec.ofInt 64 (-16)
  returnLength : (machine.getReg 2).toNat = 8

/-- Exact fetched instructions for the `get` body prelude. This block repeats
the Loader V3 shape checks and derives the program-id pointer in `r2`. -/
structure StateCellGetBodyPreludeProgramV1 (program : Program) : Prop where
  pc128 : program[128]? = some (.loadMem .Ldxdw 1 6 0)
  pc129 : program[129]? = some (.jumpImm .JneImm 1 1 26)
  pc130 : program[130]? = some (.loadMem .Ldxb 1 6 8)
  pc131 : program[131]? = some (.jumpImm .JneImm 1 255 24)
  pc132 : program[132]? = some (.loadMem .Ldxdw 1 6 10360)
  pc133 : program[133]? = some (.jumpImm .JneImm 1 8 22)
  pc134 : program[134]? = some (.loadMem .Ldxdw 1 6 10360)
  pc135 : program[135]? = some (.binReg .Mov64Reg 2 6)
  pc136 : program[136]? = some (.binImm .Add64Imm 2 10368)
  pc137 : program[137]? = some (.binReg .Add64Reg 2 1)

instance (program : Program) :
    Decidable (StateCellGetBodyPreludeProgramV1 program) := by
  let checks : Prop :=
    (program[128]? = some (.loadMem .Ldxdw 1 6 0) ∧
      program[129]? = some (.jumpImm .JneImm 1 1 26) ∧
      program[130]? = some (.loadMem .Ldxb 1 6 8) ∧
      program[131]? = some (.jumpImm .JneImm 1 255 24) ∧
      program[132]? = some (.loadMem .Ldxdw 1 6 10360) ∧
      program[133]? = some (.jumpImm .JneImm 1 8 22) ∧
      program[134]? = some (.loadMem .Ldxdw 1 6 10360) ∧
      program[135]? = some (.binReg .Mov64Reg 2 6) ∧
      program[136]? = some (.binImm .Add64Imm 2 10368) ∧
      program[137]? = some (.binReg .Add64Reg 2 1))
  apply decidable_of_iff checks
  constructor
  · rintro ⟨h128, h129, h130, h131, h132, h133, h134, h135, h136, h137⟩
    exact ⟨h128, h129, h130, h131, h132, h133, h134, h135, h136, h137⟩
  · intro h
    exact ⟨h.pc128, h.pc129, h.pc130, h.pc131, h.pc132, h.pc133, h.pc134,
      h.pc135, h.pc136, h.pc137⟩

/-- Exact fetched instructions for four little-endian owner/program-id chunk
comparisons in the production `get` body. -/
structure StateCellGetOwnerCheckProgramV1 (program : Program) : Prop where
  pc138 : program[138]? = some (.loadMem .Ldxdw 1 6 48)
  pc139 : program[139]? = some (.loadMem .Ldxdw 3 2 0)
  pc140 : program[140]? = some (.jumpReg .JneReg 1 3 15)
  pc141 : program[141]? = some (.loadMem .Ldxdw 1 6 56)
  pc142 : program[142]? = some (.loadMem .Ldxdw 3 2 8)
  pc143 : program[143]? = some (.jumpReg .JneReg 1 3 12)
  pc144 : program[144]? = some (.loadMem .Ldxdw 1 6 64)
  pc145 : program[145]? = some (.loadMem .Ldxdw 3 2 16)
  pc146 : program[146]? = some (.jumpReg .JneReg 1 3 9)
  pc147 : program[147]? = some (.loadMem .Ldxdw 1 6 72)
  pc148 : program[148]? = some (.loadMem .Ldxdw 3 2 24)
  pc149 : program[149]? = some (.jumpReg .JneReg 1 3 6)

instance (program : Program) :
    Decidable (StateCellGetOwnerCheckProgramV1 program) := by
  let checks : Prop :=
    (program[138]? = some (.loadMem .Ldxdw 1 6 48) ∧
      program[139]? = some (.loadMem .Ldxdw 3 2 0) ∧
      program[140]? = some (.jumpReg .JneReg 1 3 15) ∧
      program[141]? = some (.loadMem .Ldxdw 1 6 56) ∧
      program[142]? = some (.loadMem .Ldxdw 3 2 8) ∧
      program[143]? = some (.jumpReg .JneReg 1 3 12) ∧
      program[144]? = some (.loadMem .Ldxdw 1 6 64) ∧
      program[145]? = some (.loadMem .Ldxdw 3 2 16) ∧
      program[146]? = some (.jumpReg .JneReg 1 3 9) ∧
      program[147]? = some (.loadMem .Ldxdw 1 6 72) ∧
      program[148]? = some (.loadMem .Ldxdw 3 2 24) ∧
      program[149]? = some (.jumpReg .JneReg 1 3 6))
  apply decidable_of_iff checks
  constructor
  · rintro ⟨h138, h139, h140, h141, h142, h143, h144, h145, h146, h147,
      h148, h149⟩
    exact ⟨h138, h139, h140, h141, h142, h143, h144, h145, h146, h147,
      h148, h149⟩
  · intro h
    exact ⟨h.pc138, h.pc139, h.pc140, h.pc141, h.pc142, h.pc143, h.pc144,
      h.pc145, h.pc146, h.pc147, h.pc148, h.pc149⟩

/-- Sparse Loader V3 reads witnessing exact equality of all four 64-bit owner
and program-id chunks. -/
structure StateCellGetOwnerCheckInputV1 (input : Array UInt8) : Prop where
  chunk0 : ∃ value : Word,
    (Machine.entry input).mem.readU64 (inputStart + 48#64) = some value ∧
    (Machine.entry input).mem.readU64 (inputStart + 10376#64) = some value
  chunk1 : ∃ value : Word,
    (Machine.entry input).mem.readU64 (inputStart + 56#64) = some value ∧
    (Machine.entry input).mem.readU64 (inputStart + 10384#64) = some value
  chunk2 : ∃ value : Word,
    (Machine.entry input).mem.readU64 (inputStart + 64#64) = some value ∧
    (Machine.entry input).mem.readU64 (inputStart + 10392#64) = some value
  chunk3 : ∃ value : Word,
    (Machine.entry input).mem.readU64 (inputStart + 72#64) = some value ∧
    (Machine.entry input).mem.readU64 (inputStart + 10400#64) = some value

/-- Exact fetched instructions validating the StateCell account-data length and
layout marker before entering the return-data epilogue. -/
structure StateCellGetStateCheckProgramV1 (program : Program) : Prop where
  pc150 : program[150]? = some (.loadMem .Ldxdw 1 6 88)
  pc151 : program[151]? = some (.jumpImm .JneImm 1 16 4)
  pc152 : program[152]? = some (.loadMem .Ldxdw 1 6 96)
  pc153 : program[153]? = some (.lddw 2 846264958600013564)
  pc154 : program[154]? = some (.jumpReg .JneReg 1 2 1)
  pc155 : program[155]? = some (.ja 2)

instance (program : Program) :
    Decidable (StateCellGetStateCheckProgramV1 program) := by
  let checks : Prop :=
    (program[150]? = some (.loadMem .Ldxdw 1 6 88) ∧
      program[151]? = some (.jumpImm .JneImm 1 16 4) ∧
      program[152]? = some (.loadMem .Ldxdw 1 6 96) ∧
      program[153]? = some (.lddw 2 846264958600013564) ∧
      program[154]? = some (.jumpReg .JneReg 1 2 1) ∧
      program[155]? = some (.ja 2))
  apply decidable_of_iff checks
  constructor
  · rintro ⟨h150, h151, h152, h153, h154, h155⟩
    exact ⟨h150, h151, h152, h153, h154, h155⟩
  · intro h
    exact ⟨h.pc150, h.pc151, h.pc152, h.pc153, h.pc154, h.pc155⟩

/-- Sparse account-data reads needed by StateCell layout validation. -/
structure StateCellGetStateCheckInputV1 (input : Array UInt8) : Prop where
  accountDataLength :
    (Machine.entry input).mem.readU64 (inputStart + 88#64) = some 16
  stateMarker :
    (Machine.entry input).mem.readU64 (inputStart + 96#64) =
      some 846264958600013564

/-- Exact fetched instructions for publishing the StateCell value, returning
from the method call, and halting at the dispatcher exit. -/
structure StateCellGetReturnProgramV1 (program : Program) : Prop where
  pc158 : program[158]? = some (.loadMem .Ldxdw 1 6 104)
  pc159 : program[159]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8)))
  pc160 : program[160]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-8)))
  pc161 : program[161]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-16)))
  pc162 : program[162]? = some (.binReg .Mov64Reg 1 10)
  pc163 : program[163]? = some (.binImm .Add64Imm 1 (BitVec.ofInt 64 (-16)))
  pc164 : program[164]? = some (.lddw 2 8)
  pc165 : program[165]? = some (.callSyscall "sol_set_return_data")
  pc166 : program[166]? = some (.lddw 0 0)
  pc167 : program[167]? = some .exit
  pc22 : program[22]? = some .exit

instance (program : Program) : Decidable (StateCellGetReturnProgramV1 program) := by
  let checks : Prop :=
    (program[158]? = some (.loadMem .Ldxdw 1 6 104) ∧
      program[159]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) ∧
      program[160]? = some (.loadMem .Ldxdw 1 10 (BitVec.ofInt 16 (-8))) ∧
      program[161]? = some (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-16))) ∧
      program[162]? = some (.binReg .Mov64Reg 1 10) ∧
      program[163]? = some (.binImm .Add64Imm 1 (BitVec.ofInt 64 (-16))) ∧
      program[164]? = some (.lddw 2 8) ∧
      program[165]? = some (.callSyscall "sol_set_return_data") ∧
      program[166]? = some (.lddw 0 0) ∧
      program[167]? = some .exit ∧
      program[22]? = some .exit)
  apply decidable_of_iff checks
  constructor
  · rintro ⟨h158, h159, h160, h161, h162, h163, h164, h165, h166, h167,
      h22⟩
    exact ⟨h158, h159, h160, h161, h162, h163, h164, h165, h166, h167,
      h22⟩
  · intro h
    exact ⟨h.pc158, h.pc159, h.pc160, h.pc161, h.pc162, h.pc163, h.pc164,
      h.pc165, h.pc166, h.pc167, h.pc22⟩

/-- All sparse production instruction lookups consumed by the complete `get`
certificate. This aggregates predicates only; it does not define a program. -/
structure StateCellGetProgramLookupsV1 (program : Program) : Prop where
  dispatchPrefix : StateCellGetDispatchPrefixProgramV1 program
  methodDispatch : StateCellGetMethodDispatchProgramV1 program
  bodyPrelude : StateCellGetBodyPreludeProgramV1 program
  ownerCheck : StateCellGetOwnerCheckProgramV1 program
  stateCheck : StateCellGetStateCheckProgramV1 program
  returnPath : StateCellGetReturnProgramV1 program

instance (program : Program) : Decidable (StateCellGetProgramLookupsV1 program) := by
  let checks : Prop :=
    (StateCellGetDispatchPrefixProgramV1 program ∧
      StateCellGetMethodDispatchProgramV1 program ∧
      StateCellGetBodyPreludeProgramV1 program ∧
      StateCellGetOwnerCheckProgramV1 program ∧
      StateCellGetStateCheckProgramV1 program ∧
      StateCellGetReturnProgramV1 program)
  apply decidable_of_iff checks
  constructor
  · rintro ⟨dispatch, method, prelude, owner, state, returnPath⟩
    exact ⟨dispatch, method, prelude, owner, state, returnPath⟩
  · intro h
    exact ⟨h.dispatchPrefix, h.methodDispatch, h.bodyPrelude, h.ownerCheck,
      h.stateCheck, h.returnPath⟩

/-- Executable fail-closed check for every production instruction lookup used
    by the complete StateCell `get` certificate. -/
def checkStateCellGetProgramLookupsV1 (program : Program) : Bool :=
  decide (StateCellGetProgramLookupsV1 program)

theorem checkStateCellGetProgramLookupsV1_eq_true_iff (program : Program) :
    checkStateCellGetProgramLookupsV1 program = true ↔
      StateCellGetProgramLookupsV1 program := by
  simp [checkStateCellGetProgramLookupsV1]

/-- The identity-bound artifact check admits only the exact production source
    digest and a resolved provider program containing all lookups consumed by
    the 55-step certificate. -/
def checkStateCellGetArtifactV1 (bound : BoundResolvedSbpfArtifactV1) : Bool :=
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  decide (artifact.sourceSha256 = stateCellProductionSbpfSha256V1) &&
    checkStateCellGetProgramLookupsV1 artifact.program

theorem checkStateCellGetArtifactV1_eq_true_iff
    (bound : BoundResolvedSbpfArtifactV1) :
    checkStateCellGetArtifactV1 bound = true ↔
      let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
      artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
        StateCellGetProgramLookupsV1 artifact.program := by
  simp [checkStateCellGetArtifactV1, checkStateCellGetProgramLookupsV1]

/-- Kernel projection from a successful executable artifact check. Downstream
    proofs no longer need callers to supply 55 independent lookup equations. -/
theorem stateCellGetArtifactV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (checked : checkStateCellGetArtifactV1 bound = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      StateCellGetProgramLookupsV1 artifact.program :=
  (checkStateCellGetArtifactV1_eq_true_iff bound).mp checked

/-- Sparse account-data read for the UInt64 returned by `get`. -/
structure StateCellGetReturnInputV1 (input : Array UInt8) (value : Word) : Prop where
  stateValue :
    (Machine.entry input).mem.readU64 (inputStart + 104#64) = some value

/-- Raw decidable read equations behind the complete `get` input contract.
    Owner/program-id equality is expressed without an existential so this
    proposition remains directly executable. -/
def StateCellGetInputReadChecksV1 (input : Array UInt8) (value : Word) : Prop :=
  let memory := (Machine.entry input).mem
  memory.readU64 (inputStart + 0#64) = some 1 ∧
  memory.readU8 (inputStart + 8#64) = some 255 ∧
  memory.readU64 (inputStart + 10360#64) = some 8 ∧
  memory.readU64 (inputStart + 10368#64) = some 4025532893697057444 ∧
  memory.readU64 (inputStart + 48#64) =
    memory.readU64 (inputStart + 10376#64) ∧
  memory.readU64 (inputStart + 48#64) ≠ none ∧
  memory.readU64 (inputStart + 56#64) =
    memory.readU64 (inputStart + 10384#64) ∧
  memory.readU64 (inputStart + 56#64) ≠ none ∧
  memory.readU64 (inputStart + 64#64) =
    memory.readU64 (inputStart + 10392#64) ∧
  memory.readU64 (inputStart + 64#64) ≠ none ∧
  memory.readU64 (inputStart + 72#64) =
    memory.readU64 (inputStart + 10400#64) ∧
  memory.readU64 (inputStart + 72#64) ≠ none ∧
  memory.readU64 (inputStart + 88#64) = some 16 ∧
  memory.readU64 (inputStart + 96#64) = some 846264958600013564 ∧
  memory.readU64 (inputStart + 104#64) = some value

instance (input : Array UInt8) (value : Word) :
    Decidable (StateCellGetInputReadChecksV1 input value) := by
  unfold StateCellGetInputReadChecksV1
  infer_instance

/-- All Loader input reads consumed by the complete StateCell `get`
    certificate, grouped by the certificate segment that uses them. -/
structure StateCellGetInputReadsV1 (input : Array UInt8) (value : Word) : Prop where
  dispatchPrefix : StateCellGetDispatchPrefixInputV1 input
  methodDispatch : StateCellGetMethodDispatchInputV1 input
  ownerCheck : StateCellGetOwnerCheckInputV1 input
  stateCheck : StateCellGetStateCheckInputV1 input
  returnValue : StateCellGetReturnInputV1 input value

/-- Executable fail-closed check for every concrete Loader memory read consumed
    by the 55-step `get` certificate. -/
def checkStateCellGetInputReadsV1 (input : Array UInt8) (value : Word) : Bool :=
  decide (StateCellGetInputReadChecksV1 input value)

private theorem samePresentWordReadsV1
    {left right : Option Word}
    (same : left = right)
    (present : left ≠ none) :
    ∃ value, left = some value ∧ right = some value := by
  cases hleft : left with
  | none => exact (present hleft).elim
  | some value =>
      exact ⟨value, rfl, same.symm.trans hleft⟩

/-- Kernel projection from a successful concrete input checker to all sparse
    read contracts used by the provider trace. -/
theorem stateCellGetInputReadsV1_sound
    (input : Array UInt8)
    (value : Word)
    (checked : checkStateCellGetInputReadsV1 input value = true) :
    StateCellGetInputReadsV1 input value := by
  have hchecks : StateCellGetInputReadChecksV1 input value :=
    of_decide_eq_true (by
      simpa [checkStateCellGetInputReadsV1] using checked)
  dsimp [StateCellGetInputReadChecksV1] at hchecks
  rcases hchecks with
    ⟨hcount, hmarker, hlength, hdiscriminator,
      hchunk0, hchunk0Present, hchunk1, hchunk1Present,
      hchunk2, hchunk2Present, hchunk3, hchunk3Present,
      hdataLength, hstateMarker, hvalue⟩
  exact {
    dispatchPrefix := ⟨hcount, hmarker, hlength⟩
    methodDispatch := ⟨hdiscriminator⟩
    ownerCheck := {
      chunk0 := samePresentWordReadsV1 hchunk0 hchunk0Present
      chunk1 := samePresentWordReadsV1 hchunk1 hchunk1Present
      chunk2 := samePresentWordReadsV1 hchunk2 hchunk2Present
      chunk3 := samePresentWordReadsV1 hchunk3 hchunk3Present
    }
    stateCheck := ⟨hdataLength, hstateMarker⟩
    returnValue := ⟨hvalue⟩
  }

/-- Provider store/read equations needed by the return epilogue. They are
constructed by `deriveStateCellGetReturnEffectsV1` from actual `execInstr`
results rather than a duplicate store semantics. -/
structure StateCellGetReturnEffectsV1 (start : Machine) (value : Word)
    (returnBytes : Array UInt8) where
  firstMemory : Memory
  secondMemory : Memory
  firstStore :
    let loaded := put64 start 1 value
    execInstr asmDefaultHost loaded
        (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) =
      some ({ loaded with mem := firstMemory }.advancePc)
  firstRead :
    firstMemory.readU64
      (calcAddr (start.getReg 10) (BitVec.ofInt 16 (-8))) = some value
  secondStore :
    let loaded := put64 start 1 value
    let afterFirst := { loaded with mem := firstMemory }.advancePc
    let reloaded := put64 afterFirst 1 value
    execInstr asmDefaultHost reloaded
        (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-16))) =
      some ({ reloaded with mem := secondMemory }.advancePc)
  returnRead :
    secondMemory.readBytes
      (start.getReg 10 + BitVec.ofInt 64 (-16)) 8 = some returnBytes
  inputPreserved : secondMemory.input = start.mem.input

private instance : DecidableEq Memory := fun left right =>
  decidable_of_iff
    (left.rodata = right.rodata ∧ left.stack = right.stack ∧
      left.heap = right.heap ∧ left.input = right.input) <| by
    constructor
    · rintro ⟨hrodata, hstack, hheap, hinput⟩
      cases left
      cases right
      simp_all
    · intro h
      cases h
      exact ⟨rfl, rfl, rfl, rfl⟩

private instance : DecidableEq CallFrame := fun left right =>
  decidable_of_iff
    (left.returnPc = right.returnPc ∧ left.savedR6 = right.savedR6 ∧
      left.savedR7 = right.savedR7 ∧ left.savedR8 = right.savedR8 ∧
      left.savedR9 = right.savedR9 ∧ left.savedFp = right.savedFp) <| by
    constructor
    · rintro ⟨hpc, hr6, hr7, hr8, hr9, hfp⟩
      cases left
      cases right
      simp_all
    · intro h
      cases h
      exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

private instance : DecidableEq Machine := fun left right =>
  decidable_of_iff
    (left.regs = right.regs ∧ left.pc = right.pc ∧ left.mem = right.mem ∧
      left.frames = right.frames ∧ left.maxDepth = right.maxDepth ∧
      left.halted = right.halted ∧ left.returnData = right.returnData) <| by
    constructor
    · rintro ⟨hregs, hpc, hmem, hframes, hdepth, hhalted, hreturnData⟩
      cases left
      cases right
      simp_all
    · intro h
      cases h
      exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- Execute and check the two provider stack stores used by the `get` return
    path. A successful result is itself the kernel-checkable certificate; the
    memories and equations come from `execInstr`, rather than a duplicate
    proof-only store semantics. -/
def deriveStateCellGetReturnEffectsV1
    (start : Machine) (value : Word) (returnBytes : Array UInt8) :
    Option (StateCellGetReturnEffectsV1 start value returnBytes) :=
  let loaded := put64 start 1 value
  match hfirst : execInstr asmDefaultHost loaded
      (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-8))) with
  | none => none
  | some afterFirst =>
      if hfirstShape : afterFirst = ({ loaded with mem := afterFirst.mem }.advancePc) then
        if hfirstRead : afterFirst.mem.readU64
            (calcAddr (start.getReg 10) (BitVec.ofInt 16 (-8))) = some value then
          let reloaded := put64 afterFirst 1 value
          match hsecond : execInstr asmDefaultHost reloaded
              (.storeReg .Stxdw 10 1 (BitVec.ofInt 16 (-16))) with
          | none => none
          | some afterSecond =>
              if hsecondShape :
                  afterSecond = ({ reloaded with mem := afterSecond.mem }.advancePc) then
                if hreturnRead : afterSecond.mem.readBytes
                    (start.getReg 10 + BitVec.ofInt 64 (-16)) 8 =
                    some returnBytes then
                  if hinputPreserved : afterSecond.mem.input = start.mem.input then
                    some {
                      firstMemory := afterFirst.mem
                      secondMemory := afterSecond.mem
                      firstStore := by
                        exact hfirst.trans (congrArg some hfirstShape)
                      firstRead := hfirstRead
                      secondStore := by
                        dsimp only
                        rw [← hfirstShape]
                        exact hsecond.trans (congrArg some hsecondShape)
                      returnRead := hreturnRead
                      inputPreserved := hinputPreserved
                    }
                  else none
                else none
              else none
        else none
      else none

/-- Single executable gate for every premise of the identity-bound 55-step
    trace: production identity/lookups, concrete Loader reads, and the two
    provider stack stores at the actual 44-step prefix machine. -/
def checkStateCellGetTraceV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input returnBytes : Array UInt8)
    (value : Word) : Bool :=
  checkStateCellGetArtifactV1 bound &&
    (checkStateCellGetInputReadsV1 input value &&
      let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
      let beforeReturn :=
        (runFuel asmDefaultHost artifact.program 44 (Machine.entry input)).1
      (deriveStateCellGetReturnEffectsV1 beforeReturn value returnBytes).isSome)

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

/-- Starting from the first certificate's PC-10 carrier, the provider rejects
the `initialize` and `increment` discriminators, accepts `get`, and enters the
production method body at PC 128 with one exact call frame. -/
theorem stateCellGet_methodDispatch_stepsV1
    (program : Program)
    (input : Array UInt8)
    (start : Machine)
    (programRel : StateCellGetMethodDispatchProgramV1 program)
    (inputRel : StateCellGetMethodDispatchInputV1 input)
    (startRel : StateCellGetPc10V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 8 start machine ∧
      StateCellGetPc128V1 input machine := by
  let m1 := put64 start 1 4025532893697057444
  let m2 := put64 m1 2 7217115878876727646
  let m3 := condJump m2
    (4025532893697057444 != 7217115878876727646) 2
  let m4 := put64 m3 2 2467651336600536989
  let m5 := condJump m4
    (4025532893697057444 != 2467651336600536989) 2
  let m6 := put64 m5 2 4025532893697057444
  let m7 := condJump m6
    (4025532893697057444 != 4025532893697057444) 2
  let frame : CallFrame := {
    returnPc := m7.pc + 1
    savedR6 := m7.getReg 6
    savedR7 := m7.getReg 7
    savedR8 := m7.getReg 8
    savedR9 := m7.getReg 9
    savedFp := m7.getReg 10
  }
  let m8 :=
    ((({ m7 with frames := frame :: m7.frames }).setReg 10
      (frame.savedFp + stackFrameSize)).setPc 128)
  have haddr10368 :
      calcAddr inputStart (10368#16) = inputStart + 10368#64 := by
    decide
  refine ⟨m8, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc10)
        (by
          apply execInstrLdxdw
          · exact startRel.halted
          · rw [startRel.memory, startRel.inputBase]
            rw [haddr10368]
            exact inputRel.discriminator)
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.halted])
        (by simpa [m1, startRel.pc] using programRel.pc11)
        (by simp [m1, m2, startRel.halted])
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m1, m2, startRel.halted])
        (by simpa [m1, m2, startRel.pc] using programRel.pc12)
        (by simp [m1, m2, m3, startRel.halted, condJump, doJump])
    apply Steps.succ (m' := m4)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, startRel.halted, condJump, doJump])
        (by
          simpa [m1, m2, m3, startRel.pc, condJump, doJump] using
            programRel.pc15)
        (by simp [m1, m2, m3, m4, startRel.halted, condJump, doJump])
    apply Steps.succ (m' := m5)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, startRel.halted, condJump, doJump])
        (by
          simpa [m1, m2, m3, m4, startRel.pc, condJump, doJump] using
            programRel.pc16)
        (by simp [m1, m2, m3, m4, m5, startRel.halted, condJump, doJump])
    apply Steps.succ (m' := m6)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, m5, startRel.halted, condJump, doJump])
        (by
          simpa [m1, m2, m3, m4, m5, startRel.pc, condJump, doJump] using
            programRel.pc19)
        (by
          simp [m1, m2, m3, m4, m5, m6, startRel.halted, condJump,
            doJump])
    apply Steps.succ (m' := m7)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, startRel.halted, condJump,
            doJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, startRel.pc, condJump,
            doJump] using
            programRel.pc20)
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, startRel.halted,
            condJump, doJump])
    apply Steps.succ (m' := m8)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, startRel.halted,
            condJump, doJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, startRel.pc,
            condJump, doJump] using programRel.pc21)
        (by
          rw [execInstrCallRel asmDefaultHost m7 (106#64)]
          · simp [execCallRel, Machine.pushFrame, Machine.callDepth, m8,
              frame, m7, m6, m5, m4, m3, m2, m1, startRel.pc,
              startRel.frames, startRel.maxDepth, defaultMaxCallDepth,
              condJump, doJump]
          · simp [m7, m6, m5, m4, m3, m2, m1, startRel.halted,
              condJump, doJump])
    exact Steps.zero _
  · refine {
      pc := by simp [m8]
      halted := by
        simp [m8, m7, m6, m5, m4, m3, m2, m1, startRel.halted,
          condJump, doJump]
      memory := by
        simp [m8, m7, m6, m5, m4, m3, m2, m1, startRel.memory,
          condJump, doJump]
      frames := by
        simp [m8, frame, m7, m6, m5, m4, m3, m2, m1, startRel.pc,
          startRel.frames, startRel.inputBase, startRel.savedR7,
          startRel.savedR8, startRel.savedR9, startRel.framePointer,
          condJump, doJump]
      maxDepth := by
        simp [m8, m7, m6, m5, m4, m3, m2, m1, startRel.maxDepth,
          condJump, doJump]
      returnData := by
        simp [m8, m7, m6, m5, m4, m3, m2, m1,
          startRel.returnData, condJump, doJump]
      inputBase := by
        simp only [m8, setPc_getReg]
        rw [setReg_getReg_ne _ 10 6 _ (by decide)]
        change m7.getReg 6 = inputStart
        simp [m7, m6, m5, m4, m3, m2, m1, startRel.inputBase,
          condJump, doJump]
      framePointer := by
        simp only [m8, setPc_getReg, setReg_getReg_same]
        change frame.savedFp + stackFrameSize =
          (Machine.entry input).getReg 10 + stackFrameSize
        simp [frame, m7, m6, m5, m4, m3, m2, m1,
          startRel.framePointer, condJump, doJump]
    }

/-- The two dispatch slices compose to a sixteen-step provider certificate from
the Loader V3 entry machine to the production `get` body at PC 128. -/
theorem stateCellGet_dispatchToBody_stepsV1
    (program : Program)
    (input : Array UInt8)
    (prefixProgramRel : StateCellGetDispatchPrefixProgramV1 program)
    (methodProgramRel : StateCellGetMethodDispatchProgramV1 program)
    (prefixInputRel : StateCellGetDispatchPrefixInputV1 input)
    (methodInputRel : StateCellGetMethodDispatchInputV1 input) :
    ∃ machine,
      Steps asmDefaultHost program 16 (Machine.entry input) machine ∧
      StateCellGetPc128V1 input machine := by
  rcases stateCellGet_dispatchPrefix_stepsV1 program input prefixProgramRel
      prefixInputRel with ⟨mid, hprefix, midRel⟩
  rcases stateCellGet_methodDispatch_stepsV1 program input mid
      methodProgramRel methodInputRel midRel with
    ⟨machine, hmethod, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost program 8 8 (Machine.entry input) mid machine
      hprefix hmethod)

/-- The first ten instructions of the production `get` body revalidate the
single-account Loader input and derive the program-id pointer at PC 138. -/
theorem stateCellGet_bodyPrelude_stepsV1
    (program : Program)
    (input : Array UInt8)
    (start : Machine)
    (programRel : StateCellGetBodyPreludeProgramV1 program)
    (inputRel : StateCellGetDispatchPrefixInputV1 input)
    (startRel : StateCellGetPc128V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 10 start machine ∧
      StateCellGetPc138V1 input machine := by
  let m1 := put64 start 1 1
  let m2 := condJump m1 (1 != 1) 26
  let m3 := put64 m2 1 255
  let m4 := condJump m3 (255 != 255) 24
  let m5 := put64 m4 1 8
  let m6 := condJump m5 (8 != 8) 22
  let m7 := put64 m6 1 8
  let m8 := put64 m7 2 inputStart
  let m9 := put64 m8 2 (inputStart + 10368#64)
  let m10 := put64 m9 2 ((inputStart + 10368#64) + 8#64)
  have haddr0 : calcAddr inputStart (0#16) = inputStart + 0#64 := by
    decide
  have haddr8 : calcAddr inputStart (8#16) = inputStart + 8#64 := by
    decide
  have haddr10360 :
      calcAddr inputStart (10360#16) = inputStart + 10360#64 := by
    decide
  refine ⟨m10, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc128)
        (by
          apply execInstrLdxdw
          · exact startRel.halted
          · rw [startRel.memory, startRel.inputBase, haddr0]
            exact inputRel.accountCount)
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.halted])
        (by simpa [m1, startRel.pc] using programRel.pc129)
        (by simp [m1, m2, startRel.halted, condJump])
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m1, m2, startRel.halted, condJump])
        (by simpa [m1, m2, startRel.pc, condJump] using programRel.pc130)
        (by
          apply execInstrLdxb
          · simp [m1, m2, startRel.halted, condJump]
          · simpa [m2, m1, condJump, startRel.memory,
              startRel.inputBase, haddr8] using inputRel.accountMarker)
    apply Steps.succ (m' := m4)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, startRel.pc, condJump] using programRel.pc131)
        (by simp [m1, m2, m3, m4, startRel.halted, condJump])
    apply Steps.succ (m' := m5)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, startRel.pc, condJump] using
            programRel.pc132)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, startRel.halted, condJump]
          · simpa [m4, m3, m2, m1, condJump, startRel.memory,
              startRel.inputBase, haddr10360] using
              inputRel.instructionDataLength)
    apply Steps.succ (m' := m6)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, m5, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, startRel.pc, condJump] using
            programRel.pc133)
        (by simp [m1, m2, m3, m4, m5, m6, startRel.halted, condJump])
    apply Steps.succ (m' := m7)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, m5, m6, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, startRel.pc, condJump] using
            programRel.pc134)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, m5, m6, startRel.halted, condJump]
          · simpa [m6, m5, m4, m3, m2, m1, condJump,
              startRel.memory, startRel.inputBase, haddr10360] using
              inputRel.instructionDataLength)
    apply Steps.succ (m' := m8)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, startRel.halted,
            condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, startRel.pc,
            condJump] using programRel.pc135)
        (by
          simpa [m8, m7, m6, m5, m4, m3, m2, m1,
            startRel.inputBase, condJump] using
            (execInstrMov64Reg asmDefaultHost m7 2 6
              (by
                simp [m7, m6, m5, m4, m3, m2, m1,
                  startRel.halted, condJump])))
    apply Steps.succ (m' := m9)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8,
            startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, m8, startRel.pc,
            condJump] using programRel.pc136)
        (by
          simpa [m9, m8] using
            (execInstrAdd64Imm asmDefaultHost m8 2 10368
              (by
                simp [m8, m7, m6, m5, m4, m3, m2, m1,
                  startRel.halted, condJump])))
    apply Steps.succ (m' := m10)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8, m9,
            startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, m8, m9,
            startRel.pc, condJump] using programRel.pc137)
        (by
          simpa [m10, m9, m8, m7] using
            (execInstrAdd64Reg asmDefaultHost m9 2 1
              (by
                simp [m9, m8, m7, m6, m5, m4, m3, m2, m1,
                  startRel.halted, condJump])))
    exact Steps.zero _
  · refine ⟨?_, ?_⟩
    · constructor <;>
        simp [m10, m9, m8, m7, m6, m5, m4, m3, m2, m1,
          startRel.pc, startRel.halted, startRel.memory, startRel.frames,
          startRel.maxDepth, startRel.returnData, startRel.inputBase,
          startRel.framePointer, condJump]
    · simp [m10, m9, m8]
      decide

/-- Four 64-bit comparisons establish exact owner/program-id equality and
advance the production `get` body to its state-layout checks at PC 150. -/
theorem stateCellGet_ownerCheck_stepsV1
    (program : Program)
    (input : Array UInt8)
    (start : Machine)
    (programRel : StateCellGetOwnerCheckProgramV1 program)
    (inputRel : StateCellGetOwnerCheckInputV1 input)
    (startRel : StateCellGetPc138V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 12 start machine ∧
      StateCellGetPc150V1 input machine := by
  rcases inputRel.chunk0 with ⟨value0, howner0, hprogram0⟩
  rcases inputRel.chunk1 with ⟨value1, howner1, hprogram1⟩
  rcases inputRel.chunk2 with ⟨value2, howner2, hprogram2⟩
  rcases inputRel.chunk3 with ⟨value3, howner3, hprogram3⟩
  let m1 := put64 start 1 value0
  let m2 := put64 m1 3 value0
  let m3 := condJump m2 (value0 != value0) 15
  let m4 := put64 m3 1 value1
  let m5 := put64 m4 3 value1
  let m6 := condJump m5 (value1 != value1) 12
  let m7 := put64 m6 1 value2
  let m8 := put64 m7 3 value2
  let m9 := condJump m8 (value2 != value2) 9
  let m10 := put64 m9 1 value3
  let m11 := put64 m10 3 value3
  let m12 := condJump m11 (value3 != value3) 6
  have hownerAddr0 :
      calcAddr inputStart (48#16) = inputStart + 48#64 := by decide
  have hownerAddr1 :
      calcAddr inputStart (56#16) = inputStart + 56#64 := by decide
  have hownerAddr2 :
      calcAddr inputStart (64#16) = inputStart + 64#64 := by decide
  have hownerAddr3 :
      calcAddr inputStart (72#16) = inputStart + 72#64 := by decide
  have hprogramAddr0 :
      calcAddr (inputStart + 10376#64) (0#16) =
        inputStart + 10376#64 := by decide
  have hprogramAddr1 :
      calcAddr (inputStart + 10376#64) (8#16) =
        inputStart + 10384#64 := by decide
  have hprogramAddr2 :
      calcAddr (inputStart + 10376#64) (16#16) =
        inputStart + 10392#64 := by decide
  have hprogramAddr3 :
      calcAddr (inputStart + 10376#64) (24#16) =
        inputStart + 10400#64 := by decide
  refine ⟨m12, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.1.halted
        (by simpa [startRel.1.pc] using programRel.pc138)
        (by
          apply execInstrLdxdw
          · exact startRel.1.halted
          · rw [startRel.1.memory, startRel.1.inputBase, hownerAddr0]
            exact howner0)
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.1.halted])
        (by simpa [m1, startRel.1.pc] using programRel.pc139)
        (by
          apply execInstrLdxdw
          · simp [m1, startRel.1.halted]
          · simpa [m1, startRel.1.memory, startRel.2, hprogramAddr0] using
              hprogram0)
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m1, m2, startRel.1.halted])
        (by simpa [m1, m2, startRel.1.pc] using programRel.pc140)
        (by simp [m1, m2, m3, startRel.1.halted, condJump])
    apply Steps.succ (m' := m4)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, startRel.1.pc, condJump] using
            programRel.pc141)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, startRel.1.halted, condJump]
          · simpa [m3, m2, m1, condJump, startRel.1.memory,
              startRel.1.inputBase, hownerAddr1] using howner1)
    apply Steps.succ (m' := m5)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, startRel.1.pc, condJump] using
            programRel.pc142)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, startRel.1.halted, condJump]
          · simpa [m4, m3, m2, m1, condJump, startRel.1.memory,
              startRel.2, hprogramAddr1] using hprogram1)
    apply Steps.succ (m' := m6)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, m5, startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, startRel.1.pc, condJump] using
            programRel.pc143)
        (by
          simp [m1, m2, m3, m4, m5, m6, startRel.1.halted,
            condJump])
    apply Steps.succ (m' := m7)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, startRel.1.halted,
            condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, startRel.1.pc,
            condJump] using programRel.pc144)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, m5, m6, startRel.1.halted, condJump]
          · simpa [m6, m5, m4, m3, m2, m1, condJump,
              startRel.1.memory, startRel.1.inputBase, hownerAddr2] using
              howner2)
    apply Steps.succ (m' := m8)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, startRel.1.halted,
            condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, startRel.1.pc,
            condJump] using programRel.pc145)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, m5, m6, m7,
              startRel.1.halted, condJump]
          · simpa [m7, m6, m5, m4, m3, m2, m1, condJump,
              startRel.1.memory, startRel.2, hprogramAddr2] using
              hprogram2)
    apply Steps.succ (m' := m9)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8,
            startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, m8,
            startRel.1.pc, condJump] using programRel.pc146)
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8, m9,
            startRel.1.halted, condJump])
    apply Steps.succ (m' := m10)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8, m9,
            startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, m8, m9,
            startRel.1.pc, condJump] using programRel.pc147)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, m5, m6, m7, m8, m9,
              startRel.1.halted, condJump]
          · simpa [m9, m8, m7, m6, m5, m4, m3, m2, m1,
              condJump, startRel.1.memory, startRel.1.inputBase,
              hownerAddr3] using howner3)
    apply Steps.succ (m' := m11)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10,
            startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10,
            startRel.1.pc, condJump] using programRel.pc148)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10,
              startRel.1.halted, condJump]
          · simpa [m10, m9, m8, m7, m6, m5, m4, m3, m2, m1,
              condJump, startRel.1.memory, startRel.2,
              hprogramAddr3] using hprogram3)
    apply Steps.succ (m' := m12)
    · exact step_of_fetch_exec
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11,
            startRel.1.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11,
            startRel.1.pc, condJump] using programRel.pc149)
        (by
          simp [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11,
            m12, startRel.1.halted, condJump])
    exact Steps.zero _
  · constructor <;>
      simp [m12, m11, m10, m9, m8, m7, m6, m5, m4, m3, m2, m1,
        startRel.1.pc, startRel.1.halted, startRel.1.memory,
        startRel.1.frames, startRel.1.maxDepth, startRel.1.returnData,
        startRel.1.inputBase, startRel.1.framePointer, condJump]

/-- Exact StateCell data length and marker checks enter the production
return-data epilogue at PC 158. -/
theorem stateCellGet_stateCheck_stepsV1
    (program : Program)
    (input : Array UInt8)
    (start : Machine)
    (programRel : StateCellGetStateCheckProgramV1 program)
    (inputRel : StateCellGetStateCheckInputV1 input)
    (startRel : StateCellGetPc150V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 6 start machine ∧
      StateCellGetPc158V1 input machine := by
  let m1 := put64 start 1 16
  let m2 := condJump m1 (16 != 16) 4
  let m3 := put64 m2 1 846264958600013564
  let m4 := put64 m3 2 846264958600013564
  let m5 := condJump m4
    (846264958600013564 != 846264958600013564) 1
  let m6 := doJump m5 2
  have haddr88 : calcAddr inputStart (88#16) = inputStart + 88#64 := by
    decide
  have haddr96 : calcAddr inputStart (96#16) = inputStart + 96#64 := by
    decide
  refine ⟨m6, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc150)
        (by
          apply execInstrLdxdw
          · exact startRel.halted
          · rw [startRel.memory, startRel.inputBase, haddr88]
            exact inputRel.accountDataLength)
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.halted])
        (by simpa [m1, startRel.pc] using programRel.pc151)
        (by simp [m1, m2, startRel.halted, condJump])
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m1, m2, startRel.halted, condJump])
        (by simpa [m1, m2, startRel.pc, condJump] using programRel.pc152)
        (by
          apply execInstrLdxdw
          · simp [m1, m2, startRel.halted, condJump]
          · simpa [m2, m1, condJump, startRel.memory,
              startRel.inputBase, haddr96] using inputRel.stateMarker)
    apply Steps.succ (m' := m4)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, startRel.pc, condJump] using
            programRel.pc153)
        (by simp [m1, m2, m3, m4, startRel.halted, condJump])
    apply Steps.succ (m' := m5)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, startRel.pc, condJump] using
            programRel.pc154)
        (by simp [m1, m2, m3, m4, m5, startRel.halted, condJump])
    apply Steps.succ (m' := m6)
    · exact step_of_fetch_exec
        (by simp [m1, m2, m3, m4, m5, startRel.halted, condJump])
        (by
          simpa [m1, m2, m3, m4, m5, startRel.pc, condJump] using
            programRel.pc155)
        (by
          simpa [m6] using
            (execInstrJa asmDefaultHost m5 2
              (by
                simp [m5, m4, m3, m2, m1, startRel.halted,
                  condJump])))
    exact Steps.zero _
  · constructor <;>
      simp [m6, m5, m4, m3, m2, m1, startRel.pc, startRel.halted,
        startRel.memory, startRel.frames, startRel.maxDepth,
        startRel.returnData, startRel.inputBase, startRel.framePointer,
        condJump, doJump]

/-- The three body slices compose to the 28-step validation path from the
method entry at PC 128 to the return-data epilogue at PC 158. -/
theorem stateCellGet_body_stepsV1
    (program : Program)
    (input : Array UInt8)
    (start : Machine)
    (preludeProgramRel : StateCellGetBodyPreludeProgramV1 program)
    (ownerProgramRel : StateCellGetOwnerCheckProgramV1 program)
    (stateProgramRel : StateCellGetStateCheckProgramV1 program)
    (shapeInputRel : StateCellGetDispatchPrefixInputV1 input)
    (ownerInputRel : StateCellGetOwnerCheckInputV1 input)
    (stateInputRel : StateCellGetStateCheckInputV1 input)
    (startRel : StateCellGetPc128V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 28 start machine ∧
      StateCellGetPc158V1 input machine := by
  rcases stateCellGet_bodyPrelude_stepsV1 program input start
      preludeProgramRel shapeInputRel startRel with
    ⟨afterPrelude, hprelude, afterPreludeRel⟩
  rcases stateCellGet_ownerCheck_stepsV1 program input afterPrelude
      ownerProgramRel ownerInputRel afterPreludeRel with
    ⟨afterOwner, howner, afterOwnerRel⟩
  rcases stateCellGet_stateCheck_stepsV1 program input afterOwner
      stateProgramRel stateInputRel afterOwnerRel with
    ⟨machine, hstate, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  have hfirst : Steps asmDefaultHost program 22 start afterOwner := by
    simpa using
      (Steps_trans asmDefaultHost program 10 12 start afterPrelude afterOwner
        hprelude howner)
  simpa using
    (Steps_trans asmDefaultHost program 22 6 start afterOwner machine
      hfirst hstate)

/-- The dispatch and body certificates compose to 44 exact provider steps from
the Loader entry machine to the return-data epilogue at PC 158. -/
theorem stateCellGet_toReturnEpilogue_stepsV1
    (program : Program)
    (input : Array UInt8)
    (prefixProgramRel : StateCellGetDispatchPrefixProgramV1 program)
    (methodProgramRel : StateCellGetMethodDispatchProgramV1 program)
    (preludeProgramRel : StateCellGetBodyPreludeProgramV1 program)
    (ownerProgramRel : StateCellGetOwnerCheckProgramV1 program)
    (stateProgramRel : StateCellGetStateCheckProgramV1 program)
    (shapeInputRel : StateCellGetDispatchPrefixInputV1 input)
    (methodInputRel : StateCellGetMethodDispatchInputV1 input)
    (ownerInputRel : StateCellGetOwnerCheckInputV1 input)
    (stateInputRel : StateCellGetStateCheckInputV1 input) :
    ∃ machine,
      Steps asmDefaultHost program 44 (Machine.entry input) machine ∧
      StateCellGetPc158V1 input machine := by
  rcases stateCellGet_dispatchToBody_stepsV1 program input prefixProgramRel
      methodProgramRel shapeInputRel methodInputRel with
    ⟨bodyStart, hdispatch, bodyStartRel⟩
  rcases stateCellGet_body_stepsV1 program input bodyStart preludeProgramRel
      ownerProgramRel stateProgramRel shapeInputRel ownerInputRel stateInputRel
      bodyStartRel with
    ⟨machine, hbody, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost program 16 28 (Machine.entry input) bodyStart
      machine hdispatch hbody)

/-- Four provider steps load the StateCell value and copy it through the two
stack slots used by the generated return-data epilogue. -/
theorem stateCellGet_returnStores_stepsV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (inputRel : StateCellGetReturnInputV1 input value)
    (effects : StateCellGetReturnEffectsV1 start value returnBytes)
    (startRel : StateCellGetPc158V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 4 start machine ∧
      StateCellGetPc162V1 input start effects.secondMemory machine := by
  let m1 := put64 start 1 value
  let m2 := ({ m1 with mem := effects.firstMemory }.advancePc)
  let m3 := put64 m2 1 value
  let m4 := ({ m3 with mem := effects.secondMemory }.advancePc)
  have haddr104 : calcAddr inputStart (104#16) = inputStart + 104#64 := by
    decide
  have hm1fp : m1.getReg 10 = start.getReg 10 := by
    simp [m1]
  have hm2fp : m2.getReg 10 = start.getReg 10 := by
    change m1.getReg 10 = start.getReg 10
    exact hm1fp
  have hm3fp : m3.getReg 10 = start.getReg 10 := by
    simp [m3, hm2fp]
  have hm4fp : m4.getReg 10 = start.getReg 10 := by
    change m3.getReg 10 = start.getReg 10
    exact hm3fp
  refine ⟨m4, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc158)
        (by
          apply execInstrLdxdw
          · exact startRel.halted
          · rw [startRel.memory, startRel.inputBase, haddr104]
            exact inputRel.stateValue)
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.halted])
        (by simpa [m1, startRel.pc] using programRel.pc159)
        (by simpa [m1, m2] using effects.firstStore)
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m2, m1, startRel.halted])
        (by simpa [m2, m1, startRel.pc] using programRel.pc160)
        (by
          apply execInstrLdxdw
          · simp [m2, m1, startRel.halted]
          · change effects.firstMemory.readU64
              (calcAddr (m2.getReg 10) (BitVec.ofInt 16 (-8))) = some value
            rw [hm2fp]
            exact effects.firstRead)
    apply Steps.succ (m' := m4)
    · exact step_of_fetch_exec
        (by simp [m3, m2, m1, startRel.halted])
        (by simpa [m3, m2, m1, startRel.pc] using programRel.pc161)
        (by simpa [m3, m2, m1, m4] using effects.secondStore)
    exact Steps.zero _
  · refine {
      pc := by
        simp [m4, m3, m2, m1, startRel.pc]
      halted := by
        simp [m4, m3, m2, m1, startRel.halted]
      memory := by rfl
      frames := by
        simp [m4, m3, m2, m1, startRel.frames]
      returnData := by
        simp [m4, m3, m2, m1, startRel.returnData]
      framePointer := hm4fp
    }

/-- Three provider steps prepare the stack pointer and byte length consumed by
the return-data syscall. -/
theorem stateCellGet_prepareReturn_stepsV1
    (program : Program)
    (input : Array UInt8)
    (origin start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (storedMemory : Memory)
    (startRel : StateCellGetPc162V1 input origin storedMemory start) :
    ∃ machine,
      Steps asmDefaultHost program 3 start machine ∧
      StateCellGetPc165V1 input origin storedMemory machine := by
  let m1 := put64 start 1 (start.getReg 10)
  let m2 := put64 m1 1 (start.getReg 10 + BitVec.ofInt 64 (-16))
  let m3 := put64 m2 2 8
  have hm3fp : m3.getReg 10 = origin.getReg 10 := by
    simp [m3, m2, m1, startRel.framePointer]
  refine ⟨m3, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc162)
        (by simpa [m1] using
          (execInstrMov64Reg asmDefaultHost start 1 10 startRel.halted))
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.halted])
        (by simpa [m1, startRel.pc] using programRel.pc163)
        (by
          simpa [m2, m1] using
            (execInstrAdd64Imm asmDefaultHost m1 1 (BitVec.ofInt 64 (-16))
              (by simp [m1, startRel.halted])))
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m2, m1, startRel.halted])
        (by simpa [m2, m1, startRel.pc] using programRel.pc164)
        (by simp [m3, m2, m1, startRel.halted])
    exact Steps.zero _
  · refine {
      pc := by simp [m3, m2, m1, startRel.pc]
      halted := by simp [m3, m2, m1, startRel.halted]
      memory := by simp [m3, m2, m1, startRel.memory]
      frames := by simp [m3, m2, m1, startRel.frames]
      returnData := by simp [m3, m2, m1, startRel.returnData]
      framePointer := hm3fp
      returnPointer := by
        simp [m3, m2, m1, startRel.framePointer]
      returnLength := by simp [m3]
    }

/-- The syscall step reads the exact prepared eight bytes and publishes them
as provider-visible return data. -/
theorem stateCellGet_setReturnData_stepV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (origin start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (effects : StateCellGetReturnEffectsV1 origin value returnBytes)
    (originRel : StateCellGetPc158V1 input origin)
    (startRel : StateCellGetPc165V1 input origin effects.secondMemory start) :
    ∃ machine,
      Steps asmDefaultHost program 1 start machine ∧
      StateCellGetPc166V1 input returnBytes machine := by
  let machine :=
    (({ start with returnData := returnBytes }).setReg 0 0).advancePc
  have hfp : machine.getReg 10 = origin.getReg 10 := by
    calc
      machine.getReg 10 =
          (({ start with returnData := returnBytes }).setReg 0 0).getReg 10 := rfl
      _ = ({ start with returnData := returnBytes }).getReg 10 := by simp
      _ = start.getReg 10 := rfl
      _ = origin.getReg 10 := startRel.framePointer
  refine ⟨machine, ?_, ?_⟩
  · apply Steps.succ (m' := machine)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc165)
        (by
          apply execInstrSetReturnData
          · exact startRel.halted
          · rw [startRel.memory, startRel.returnPointer,
              startRel.returnLength]
            exact effects.returnRead)
    exact Steps.zero _
  · refine {
      pc := by simp [machine, startRel.pc]
      halted := by simp [machine, startRel.halted]
      inputMemory := by
        rw [show machine.mem = effects.secondMemory by
          simp [machine, startRel.memory]]
        rw [effects.inputPreserved, originRel.memory]
      frames := by simp [machine, startRel.frames]
      returnData := by simp [machine]
      framePointer := by
        rw [hfp]
        exact originRel.framePointer
    }

/-- Four provider steps prepare and publish the exact eight return bytes. -/
theorem stateCellGet_publishReturn_stepsV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (origin start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (effects : StateCellGetReturnEffectsV1 origin value returnBytes)
    (originRel : StateCellGetPc158V1 input origin)
    (startRel : StateCellGetPc162V1 input origin effects.secondMemory start) :
    ∃ machine,
      Steps asmDefaultHost program 4 start machine ∧
      StateCellGetPc166V1 input returnBytes machine := by
  rcases stateCellGet_prepareReturn_stepsV1 program input origin start programRel
      effects.secondMemory startRel with
    ⟨beforeSyscall, hprepare, beforeSyscallRel⟩
  rcases stateCellGet_setReturnData_stepV1 program input returnBytes value origin
      beforeSyscall programRel effects originRel beforeSyscallRel with
    ⟨machine, hsyscall, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost program 3 1 start beforeSyscall machine
      hprepare hsyscall)

/-- The first eight return-epilogue steps load and publish the StateCell value,
stopping immediately before the method and dispatcher exits. -/
theorem stateCellGet_returnEpilogue_stepsV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (inputRel : StateCellGetReturnInputV1 input value)
    (effects : StateCellGetReturnEffectsV1 start value returnBytes)
    (startRel : StateCellGetPc158V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 8 start machine ∧
      StateCellGetPc166V1 input returnBytes machine := by
  rcases stateCellGet_returnStores_stepsV1 program input returnBytes value start
      programRel inputRel effects startRel with
    ⟨afterStores, hstores, afterStoresRel⟩
  rcases stateCellGet_publishReturn_stepsV1 program input returnBytes value
      start afterStores programRel effects startRel afterStoresRel with
    ⟨machine, hpublish, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost program 4 4 start afterStores machine
      hstores hpublish)

/-- The final three provider steps set the result register, restore the exact
call frame at PC 22, and halt the outer dispatcher with status zero. -/
theorem stateCellGet_returnControl_stepsV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (startRel : StateCellGetPc166V1 input returnBytes start) :
    ∃ machine,
      Steps asmDefaultHost program 3 start machine ∧
      StateCellGetReturnedV1 input returnBytes machine := by
  let m1 := put64 start 0 0
  let withoutFrame : Machine := { m1 with frames := [] }
  let m2 :=
    ((((((withoutFrame.setReg 6 inputStart).setReg 7
      ((Machine.entry input).getReg 7)).setReg 8
      ((Machine.entry input).getReg 8)).setReg 9
      ((Machine.entry input).getReg 9)).setReg 10
      ((Machine.entry input).getReg 10)).setPc 22)
  let m3 := m2.halt 0
  have hm1r0 : m1.getReg 0 = 0 := by simp [m1]
  have hwithoutFrameR0 : withoutFrame.getReg 0 = 0 := by
    change m1.getReg 0 = 0
    exact hm1r0
  have hm2r0 : m2.getReg 0 = 0 := by
    simp [m2, hwithoutFrameR0]
  have hm2frames : m2.frames = [] := by
    simp [m2, withoutFrame]
  refine ⟨m3, ?_, ?_⟩
  · apply Steps.succ (m' := m1)
    · exact step_of_fetch_exec
        startRel.halted
        (by simpa [startRel.pc] using programRel.pc166)
        (by simp [m1, startRel.halted])
    apply Steps.succ (m' := m2)
    · exact step_of_fetch_exec
        (by simp [m1, startRel.halted])
        (by simpa [m1, startRel.pc] using programRel.pc167)
        (by
          rw [execInstrExit asmDefaultHost m1]
          · simp [execExit, Machine.popFrame, m2, withoutFrame, m1,
              startRel.frames]
          · simp [m1, startRel.halted])
    apply Steps.succ (m' := m3)
    · exact step_of_fetch_exec
        (by simp [m2, withoutFrame, m1, startRel.halted])
        (by simpa [m2] using programRel.pc22)
        (by
          rw [execInstrExit asmDefaultHost m2]
          · simp [execExit, Machine.popFrame, m3, hm2frames, hm2r0]
          · simp [m2, withoutFrame, m1, startRel.halted])
    exact Steps.zero _
  · refine {
      pc := by simp [m3, m2]
      halted := by simp [m3]
      frames := by simpa [m3] using hm2frames
      inputMemory := by
        simpa [m3, m2, withoutFrame, m1] using startRel.inputMemory
      returnData := by
        simpa [m3, m2, withoutFrame, m1] using startRel.returnData
      result := by simpa [m3] using hm2r0
      framePointer := by simp [m3, m2]
    }

/-- The complete eleven-step return path publishes the value and exits both
the method call and dispatcher. -/
theorem stateCellGet_return_stepsV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (start : Machine)
    (programRel : StateCellGetReturnProgramV1 program)
    (inputRel : StateCellGetReturnInputV1 input value)
    (effects : StateCellGetReturnEffectsV1 start value returnBytes)
    (startRel : StateCellGetPc158V1 input start) :
    ∃ machine,
      Steps asmDefaultHost program 11 start machine ∧
      StateCellGetReturnedV1 input returnBytes machine := by
  rcases stateCellGet_returnEpilogue_stepsV1 program input returnBytes value
      start programRel inputRel effects startRel with
    ⟨beforeExits, hepilogue, beforeExitsRel⟩
  rcases stateCellGet_returnControl_stepsV1 program input returnBytes
      beforeExits programRel beforeExitsRel with
    ⟨machine, hexits, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost program 8 3 start beforeExits machine
      hepilogue hexits)

/-- The complete sparse certificate composes dispatch, method validation,
return-data publication, call-frame restoration, and the final dispatcher exit
into the exact 55-step production `get` trace. This low-level composition
theorem accepts the segmented relations directly; use
`stateCellGet_checkedArtifact_stepsV1` to project them from the executable
artifact/input checks and proof-bearing store derivation. -/
theorem stateCellGet_stepsV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (prefixProgramRel : StateCellGetDispatchPrefixProgramV1 program)
    (methodProgramRel : StateCellGetMethodDispatchProgramV1 program)
    (preludeProgramRel : StateCellGetBodyPreludeProgramV1 program)
    (ownerProgramRel : StateCellGetOwnerCheckProgramV1 program)
    (stateProgramRel : StateCellGetStateCheckProgramV1 program)
    (returnProgramRel : StateCellGetReturnProgramV1 program)
    (shapeInputRel : StateCellGetDispatchPrefixInputV1 input)
    (methodInputRel : StateCellGetMethodDispatchInputV1 input)
    (ownerInputRel : StateCellGetOwnerCheckInputV1 input)
    (stateInputRel : StateCellGetStateCheckInputV1 input)
    (returnInputRel : StateCellGetReturnInputV1 input value)
    (returnEffects :
      (machine : Machine) →
      StateCellGetPc158V1 input machine →
      StateCellGetReturnEffectsV1 machine value returnBytes) :
    ∃ machine,
      Steps asmDefaultHost program 55 (Machine.entry input) machine ∧
      StateCellGetReturnedV1 input returnBytes machine := by
  rcases stateCellGet_toReturnEpilogue_stepsV1 program input prefixProgramRel
      methodProgramRel preludeProgramRel ownerProgramRel stateProgramRel
      shapeInputRel methodInputRel ownerInputRel stateInputRel with
    ⟨beforeReturn, hprefix, beforeReturnRel⟩
  rcases stateCellGet_return_stepsV1 program input returnBytes value beforeReturn
      returnProgramRel returnInputRel
      (returnEffects beforeReturn beforeReturnRel) beforeReturnRel with
    ⟨machine, hreturn, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost program 44 11 (Machine.entry input)
      beforeReturn machine hprefix hreturn)

/-- Complete checked entry for the 55-step certificate. The program relations
come from the exact identity-bound production artifact, the read relations come
from the concrete Loader input, and each return-store witness is extracted only
from a successful proof-bearing provider evaluation. -/
theorem stateCellGet_checkedArtifact_stepsV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input returnBytes : Array UInt8)
    (value : Word)
    (artifactChecked : checkStateCellGetArtifactV1 bound = true)
    (inputChecked : checkStateCellGetInputReadsV1 input value = true)
    (returnEffectsChecked :
      let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
      let beforeReturn :=
        (runFuel asmDefaultHost artifact.program 44 (Machine.entry input)).1
      (deriveStateCellGetReturnEffectsV1 beforeReturn value returnBytes).isSome = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      ∃ machine,
        Steps asmDefaultHost artifact.program 55 (Machine.entry input) machine ∧
        StateCellGetReturnedV1 input returnBytes machine := by
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  have hartifact := stateCellGetArtifactV1_sound bound artifactChecked
  have hinput := stateCellGetInputReadsV1_sound input value inputChecked
  rcases stateCellGet_toReturnEpilogue_stepsV1 artifact.program input
      hartifact.2.dispatchPrefix hartifact.2.methodDispatch
      hartifact.2.bodyPrelude hartifact.2.ownerCheck hartifact.2.stateCheck
      hinput.dispatchPrefix hinput.methodDispatch hinput.ownerCheck
      hinput.stateCheck with
    ⟨beforeReturn, hprefix, beforeReturnRel⟩
  have hrunPrefix :
      runFuel asmDefaultHost artifact.program 44 (Machine.entry input) =
        (beforeReturn, .outOfFuel) :=
    steps_runFuel_outOfFuel asmDefaultHost artifact.program 44
      (Machine.entry input) beforeReturn hprefix beforeReturnRel.halted
  have heffectsChecked := returnEffectsChecked
  dsimp only at heffectsChecked
  rw [hrunPrefix] at heffectsChecked
  let effects :=
    (deriveStateCellGetReturnEffectsV1 beforeReturn value returnBytes).get
      heffectsChecked
  rcases stateCellGet_return_stepsV1 artifact.program input returnBytes value
      beforeReturn hartifact.2.returnPath hinput.returnValue effects
      beforeReturnRel with
    ⟨machine, hreturn, machineRel⟩
  refine ⟨hartifact.1, machine, ?_, machineRel⟩
  simpa using
    (Steps_trans asmDefaultHost artifact.program 44 11 (Machine.entry input)
      beforeReturn machine hprefix hreturn)

/-- Soundness of the single executable trace gate. A successful check projects
the exact production identity and a kernel-checked 55-step provider trace. -/
theorem checkStateCellGetTraceV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (input returnBytes : Array UInt8)
    (value : Word)
    (checked : checkStateCellGetTraceV1 bound input returnBytes value = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      ∃ machine,
        Steps asmDefaultHost artifact.program 55 (Machine.entry input) machine ∧
        StateCellGetReturnedV1 input returnBytes machine := by
  have hparts :
      checkStateCellGetArtifactV1 bound = true ∧
      checkStateCellGetInputReadsV1 input value = true ∧
      let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
      let beforeReturn :=
        (runFuel asmDefaultHost artifact.program 44 (Machine.entry input)).1
      (deriveStateCellGetReturnEffectsV1 beforeReturn value returnBytes).isSome = true := by
    simpa only [checkStateCellGetTraceV1, Bool.and_eq_true] using checked
  exact stateCellGet_checkedArtifact_stepsV1 bound input returnBytes value
    hparts.1 hparts.2.1 hparts.2.2

/-- The same 55-step certificate reduces the provider's executable `runFuel`
to a status-zero halt while retaining the exact returned-state facts. -/
theorem stateCellGet_runFuelV1
    (program : Program)
    (input returnBytes : Array UInt8)
    (value : Word)
    (prefixProgramRel : StateCellGetDispatchPrefixProgramV1 program)
    (methodProgramRel : StateCellGetMethodDispatchProgramV1 program)
    (preludeProgramRel : StateCellGetBodyPreludeProgramV1 program)
    (ownerProgramRel : StateCellGetOwnerCheckProgramV1 program)
    (stateProgramRel : StateCellGetStateCheckProgramV1 program)
    (returnProgramRel : StateCellGetReturnProgramV1 program)
    (shapeInputRel : StateCellGetDispatchPrefixInputV1 input)
    (methodInputRel : StateCellGetMethodDispatchInputV1 input)
    (ownerInputRel : StateCellGetOwnerCheckInputV1 input)
    (stateInputRel : StateCellGetStateCheckInputV1 input)
    (returnInputRel : StateCellGetReturnInputV1 input value)
    (returnEffects :
      (machine : Machine) →
      StateCellGetPc158V1 input machine →
      StateCellGetReturnEffectsV1 machine value returnBytes) :
    ∃ machine,
      runFuel asmDefaultHost program 55 (Machine.entry input) =
        (machine, .halted 0) ∧
      StateCellGetReturnedV1 input returnBytes machine := by
  rcases stateCellGet_stepsV1 program input returnBytes value prefixProgramRel
      methodProgramRel preludeProgramRel ownerProgramRel stateProgramRel
      returnProgramRel shapeInputRel methodInputRel ownerInputRel stateInputRel
      returnInputRel returnEffects with
    ⟨machine, hsteps, machineRel⟩
  refine ⟨machine, ?_, machineRel⟩
  exact runFuel_eq_halted_of_steps hsteps machineRel.halted

/-- Checked-artifact `runFuel` corollary. This is the provider execution
equation consumed by the next HandlerIR/provider join step; it remains scoped
to the exact production StateCell `get` path and concrete checked input. -/
theorem stateCellGet_checkedArtifact_runFuelV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input returnBytes : Array UInt8)
    (value : Word)
    (artifactChecked : checkStateCellGetArtifactV1 bound = true)
    (inputChecked : checkStateCellGetInputReadsV1 input value = true)
    (returnEffectsChecked :
      let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
      let beforeReturn :=
        (runFuel asmDefaultHost artifact.program 44 (Machine.entry input)).1
      (deriveStateCellGetReturnEffectsV1 beforeReturn value returnBytes).isSome = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      ∃ machine,
        runFuel asmDefaultHost artifact.program 55 (Machine.entry input) =
          (machine, .halted 0) ∧
        StateCellGetReturnedV1 input returnBytes machine := by
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  rcases stateCellGet_checkedArtifact_stepsV1 bound input returnBytes value
      artifactChecked inputChecked returnEffectsChecked with
    ⟨hidentity, machine, hsteps, machineRel⟩
  refine ⟨hidentity, machine, ?_, machineRel⟩
  exact runFuel_eq_halted_of_steps hsteps machineRel.halted

/-- The single executable gate also yields the exact provider `runFuel`
equation, without exposing segmented lookup/read/store premises to callers. -/
theorem checkStateCellGetTraceV1_runFuel_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (input returnBytes : Array UInt8)
    (value : Word)
    (checked : checkStateCellGetTraceV1 bound input returnBytes value = true) :
    let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
    artifact.sourceSha256 = stateCellProductionSbpfSha256V1 ∧
      ∃ machine,
        runFuel asmDefaultHost artifact.program 55 (Machine.entry input) =
          (machine, .halted 0) ∧
        StateCellGetReturnedV1 input returnBytes machine := by
  rcases checkStateCellGetTraceV1_sound bound input returnBytes value checked with
    ⟨hidentity, machine, hsteps, machineRel⟩
  refine ⟨hidentity, machine, ?_, machineRel⟩
  exact runFuel_eq_halted_of_steps hsteps machineRel.halted

end ProofForgeV2.Targets.Solana
