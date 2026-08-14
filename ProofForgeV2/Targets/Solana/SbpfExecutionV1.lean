import ProofForgeV2.Targets.Solana.SbpfArtifactV1

/-!
# Solana SbpfExecutionV1

Loader V3 ABIv1 single-account input serialization and provider-backed
execution for an exact resolved production `.s` artifact. This module does not
interpret HandlerIR or ProofForge business semantics. The only state transition
is the pinned `SbpfSemantics` machine.

The returned account bytes are the final bytes in the provider's permissive
input memory. They are not a claim about Solana loader validation, transaction
rollback, compute units, ELF loading, or runtime conformance.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics

/-- Closed failure before provider execution. A provider `.stuck` or
    `.outOfFuel` result remains an explicit successful observation. -/
structure SbpfExecutionErrorV1 where
  message : String
  deriving BEq, Repr

def SbpfExecutionErrorV1.render (error : SbpfExecutionErrorV1) : String :=
  s!"sBPF execution: {error.message}"

abbrev SbpfExecutionResultV1 (α : Type) := Except SbpfExecutionErrorV1 α

/-- Concrete fields of the first Loader V3 ABIv1 adapter. Byte identities are
    kept raw: owner equality with the current program remains a program check,
    not an adapter assumption. -/
structure LoaderV3SingleAccountInvocationV1 where
  accountKey : Array UInt8
  owner : Array UInt8
  programId : Array UInt8
  lamports : UInt64 := 0
  accountData : Array UInt8
  instructionData : Array UInt8
  isSigner : Bool := false
  isWritable : Bool := false
  executable : Bool := false
  deriving BEq, Repr

/-- Provider result plus the exact account-data window left in input memory.
    `finalAccountData = none` means the final memory does not contain the full
    artifact-declared window (for example, a short malformed raw input). -/
structure SbpfExecutionObservationV1 where
  artifactSha256 : String
  provider : SbpfSemantics.Observation
  finalAccountData : Option (Array UInt8)
  deriving Repr

/-- Execution and input bounds for this intentionally narrow adapter. -/
def maxSbpfExecutionFuelV1 : Nat := 100_000
def defaultSbpfExecutionFuelV1 : Nat := 10_000
def maxSbpfInputImageBytesV1 : Nat := 1024 * 1024
def maxSbpfInstructionDataBytesV1 : Nat := 1024

private def executionFailV1 (message : String) : SbpfExecutionResultV1 α :=
  .error { message }

private def artifactConstantNatV1
    (artifact : ResolvedSbpfArtifactV1)
    (name : String) : SbpfExecutionResultV1 Nat :=
  match artifact.constant? name with
  | none => executionFailV1 s!"artifact is missing required constant '{name}'"
  | some value =>
      if value < 0 then
        executionFailV1 s!"artifact constant '{name}' must be nonnegative"
      else
        pure value.toNat

private def requireArtifactConstantV1
    (artifact : ResolvedSbpfArtifactV1)
    (name : String)
    (expected : Nat) : SbpfExecutionResultV1 Unit := do
  let actual ← artifactConstantNatV1 artifact name
  unless actual == expected do
    return ← executionFailV1
      s!"artifact constant '{name}' must be {expected}, got {actual}"

private structure SingleAccountLayoutV1 where
  header : Nat
  key : Nat
  owner : Nat
  lamports : Nat
  dataLen : Nat
  data : Nat
  exactDataLen : Nat
  rentEpoch : Nat
  instructionDataLen : Nat
  instructionData : Nat

/-- Recover and validate the exact fixed-offset contract from the parsed `.equ`
    table. This prevents the input encoder from silently following a mutated or
    partially compatible artifact layout. -/
private def singleAccountLayoutV1
    (artifact : ResolvedSbpfArtifactV1) :
    SbpfExecutionResultV1 SingleAccountLayoutV1 := do
  unless artifact.global == "entrypoint" do
    return ← executionFailV1 "artifact global must be 'entrypoint'"
  unless artifact.label? "entrypoint" == some 0 do
    return ← executionFailV1 "artifact entrypoint must resolve to instruction zero"
  requireArtifactConstantV1 artifact "NUM_ACCOUNTS" 0
  requireArtifactConstantV1 artifact "ACC0_HEADER" accountHeaderOffsetV1
  requireArtifactConstantV1 artifact "ACC0_KEY" accountKeyOffsetV1
  requireArtifactConstantV1 artifact "ACC0_OWNER" accountOwnerOffsetV1
  requireArtifactConstantV1 artifact "ACC0_LAMPORTS" accountLamportsOffsetV1
  requireArtifactConstantV1 artifact "ACC0_DATA_LEN" accountDataLenOffsetV1
  requireArtifactConstantV1 artifact "ACC0_DATA" accountDataOffsetV1
  requireArtifactConstantV1 artifact "MAX_PERMITTED_DATA_INCREASE"
    maxPermittedDataIncreaseV1
  let exactDataLen ← artifactConstantNatV1 artifact "EXACT_DATA_LEN"
  let expected := computeInputLayoutV1 exactDataLen
  requireArtifactConstantV1 artifact "ACC0_RENT_EPOCH" expected.rentEpoch
  requireArtifactConstantV1 artifact "INSTRUCTION_DATA_LEN"
    expected.instructionDataLen
  requireArtifactConstantV1 artifact "INSTRUCTION_DATA" expected.instructionData
  pure {
    header := accountHeaderOffsetV1
    key := accountKeyOffsetV1
    owner := accountOwnerOffsetV1
    lamports := accountLamportsOffsetV1
    dataLen := accountDataLenOffsetV1
    data := accountDataOffsetV1
    exactDataLen
    rentEpoch := expected.rentEpoch
    instructionDataLen := expected.instructionDataLen
    instructionData := expected.instructionData
  }

private def writeBytesAtV1
    (target : Array UInt8)
    (offset : Nat)
    (bytes : Array UInt8) : Option (Array UInt8) :=
  if offset + bytes.size ≤ target.size then
    some <| Id.run do
      let mut result := target
      for index in [:bytes.size] do
        result := result.set! (offset + index) bytes[index]!
      return result
  else
    none

private def writeBytesAtCheckedV1
    (target : Array UInt8)
    (offset : Nat)
    (bytes : Array UInt8)
    (field : String) : SbpfExecutionResultV1 (Array UInt8) :=
  match writeBytesAtV1 target offset bytes with
  | some result => pure result
  | none => executionFailV1 s!"'{field}' exceeds the bounded input image"

private def uint64LeV1 (value : UInt64) : Array UInt8 :=
  SbpfSemantics.wordToLE (BitVec.ofNat 64 value.toNat)

private def natAsUInt64LeV1 (value : Nat) : SbpfExecutionResultV1 (Array UInt8) := do
  unless value < 2 ^ 64 do
    return ← executionFailV1 "input image offset does not fit UInt64"
  pure <| SbpfSemantics.wordToLE (BitVec.ofNat 64 value)

private def align8V1 (value : Nat) : Nat :=
  value + (8 - value % 8) % 8

/-- Serialize one exact non-duplicate account, instruction data, current program
    id, tail padding, and the Loader V3 account-marker pointer table. Layout
    offsets come from the resolved production artifact and must also satisfy the
    production emitter's formula. -/
def encodeLoaderV3SingleAccountInputV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1) :
    SbpfExecutionResultV1 (Array UInt8) := do
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  let layout ← singleAccountLayoutV1 artifact
  unless invocation.accountKey.size == 32 do
    return ← executionFailV1 "account key must contain exactly 32 bytes"
  unless invocation.owner.size == 32 do
    return ← executionFailV1 "account owner must contain exactly 32 bytes"
  unless invocation.programId.size == 32 do
    return ← executionFailV1 "current program id must contain exactly 32 bytes"
  unless invocation.accountData.size == layout.exactDataLen do
    return ← executionFailV1
      s!"account data must contain exactly {layout.exactDataLen} bytes"
  unless invocation.instructionData.size ≤ maxSbpfInstructionDataBytesV1 do
    return ← executionFailV1
      s!"instruction data exceeds {maxSbpfInstructionDataBytesV1} bytes"
  let programIdEnd := layout.instructionData + invocation.instructionData.size + 32
  let pointerTable := align8V1 programIdEnd
  let totalSize := pointerTable + 8
  unless totalSize ≤ maxSbpfInputImageBytesV1 do
    return ← executionFailV1
      s!"input image exceeds {maxSbpfInputImageBytesV1} bytes"
  let mut input := Array.replicate totalSize 0
  input ← writeBytesAtCheckedV1 input 0 (← natAsUInt64LeV1 1) "num_accounts"
  input := input.set! layout.header 0xff
  input := input.set! (layout.header + 1) (if invocation.isSigner then 1 else 0)
  input := input.set! (layout.header + 2) (if invocation.isWritable then 1 else 0)
  input := input.set! (layout.header + 3) (if invocation.executable then 1 else 0)
  -- Loader V3 ABIv1 carries original_data_len = 0 in this entry record.
  input ← writeBytesAtCheckedV1 input layout.key invocation.accountKey "account key"
  input ← writeBytesAtCheckedV1 input layout.owner invocation.owner "account owner"
  input ← writeBytesAtCheckedV1 input layout.lamports
    (uint64LeV1 invocation.lamports) "lamports"
  input ← writeBytesAtCheckedV1 input layout.dataLen
    (← natAsUInt64LeV1 invocation.accountData.size) "account data length"
  input ← writeBytesAtCheckedV1 input layout.data invocation.accountData "account data"
  input ← writeBytesAtCheckedV1 input layout.rentEpoch
    (uint64LeV1 0xffffffffffffffff) "rent epoch"
  input ← writeBytesAtCheckedV1 input layout.instructionDataLen
    (← natAsUInt64LeV1 invocation.instructionData.size) "instruction data length"
  input ← writeBytesAtCheckedV1 input layout.instructionData
    invocation.instructionData "instruction data"
  input ← writeBytesAtCheckedV1 input
    (layout.instructionData + invocation.instructionData.size)
    invocation.programId "current program id"
  let accountMarkerAddress := inputStart.toNat + layout.header
  input ← writeBytesAtCheckedV1 input pointerTable
    (← natAsUInt64LeV1 accountMarkerAddress) "account marker pointer"
  pure input

/-- Run raw provider input after validating the identity-bound artifact layout
    and resource bounds. This entrypoint intentionally permits short input so
    the provider's fail-closed `.stuck` observation can be tested directly. -/
def runBoundSbpfArtifactV1
    (bound : BoundResolvedSbpfArtifactV1)
    (input : Array UInt8)
    (fuel : Nat := defaultSbpfExecutionFuelV1) :
    SbpfExecutionResultV1 SbpfExecutionObservationV1 := do
  let artifact := BoundResolvedSbpfArtifactV1.resolvedOf bound
  let layout ← singleAccountLayoutV1 artifact
  unless 0 < fuel && fuel ≤ maxSbpfExecutionFuelV1 do
    return ← executionFailV1
      s!"fuel must be in 1..{maxSbpfExecutionFuelV1}"
  unless input.size ≤ maxSbpfInputImageBytesV1 do
    return ← executionFailV1
      s!"raw input exceeds {maxSbpfInputImageBytesV1} bytes"
  let (finalMachine, outcome) :=
    SbpfSemantics.runFuel SbpfSemantics.asmDefaultHost artifact.program fuel
      (SbpfSemantics.Machine.entry input)
  pure {
    artifactSha256 := artifact.sourceSha256
    provider := SbpfSemantics.observe finalMachine outcome
    finalAccountData := finalMachine.mem.readBytes
      (inputStart + BitVec.ofNat 64 layout.data) layout.exactDataLen
  }

/-- Serialize and execute one strict single-account invocation. -/
def executeLoaderV3SingleAccountV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat := defaultSbpfExecutionFuelV1) :
    SbpfExecutionResultV1 SbpfExecutionObservationV1 := do
  let input ← encodeLoaderV3SingleAccountInputV1 bound invocation
  runBoundSbpfArtifactV1 bound input fuel

end ProofForgeV2.Targets.Solana
