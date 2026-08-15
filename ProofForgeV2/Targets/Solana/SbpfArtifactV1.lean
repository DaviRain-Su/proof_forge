import ProofForgeV2.Core.Crypto
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import SbpfSemantics.Api

/-!
# Solana SbpfArtifactV1

Strict, bounded parsing and label resolution for the exact assembly text
returned by `emitSbpfAsmV1`. This is an artifact consumer, not another
HandlerIR lowering and not another sBPF execution semantics. Resolved
instructions are executed only by the pinned `SbpfSemantics.Api` provider.

The first slice accepts exactly the instruction/directive vocabulary emitted by
the production StateCell `get/initialize/increment` artifact. Every unknown,
duplicate, unresolved, out-of-range, or structurally invalid form fails closed.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics

/-- Closed parser/resolver failure. `line = 0` denotes an artifact-level check. -/
structure SbpfArtifactErrorV1 where
  line : Nat
  message : String
  deriving BEq, Repr

def SbpfArtifactErrorV1.render (error : SbpfArtifactErrorV1) : String :=
  if error.line == 0 then
    s!"sBPF artifact: {error.message}"
  else
    s!"sBPF artifact line {error.line}: {error.message}"

abbrev SbpfArtifactResultV1 (α : Type) := Except SbpfArtifactErrorV1 α

/-- Resolved view of one exact production `.s` artifact. Constants and labels
    are retained so an invocation adapter can bind its input layout to the
    parsed artifact instead of trusting a parallel layout description. -/
structure ResolvedSbpfArtifactV1 where
  sourceSha256 : String
  global : String
  constants : Array (String × Int)
  labels : Array (String × Nat)
  program : SbpfSemantics.Program
  deriving Repr

def ResolvedSbpfArtifactV1.constant? (artifact : ResolvedSbpfArtifactV1)
    (name : String) : Option Int :=
  artifact.constants.findSome? fun entry =>
    if entry.1 == name then some entry.2 else none

def ResolvedSbpfArtifactV1.label? (artifact : ResolvedSbpfArtifactV1)
    (name : String) : Option Nat :=
  artifact.labels.findSome? fun entry =>
    if entry.1 == name then some entry.2 else none

/-- A resolved artifact whose exact source bytes have passed a caller-supplied
    production SHA-256 identity gate. Provider execution accepts only this
    private-constructor carrier, never a merely parseable artifact. -/
structure BoundResolvedSbpfArtifactV1 where
  private mk ::
  artifact : ResolvedSbpfArtifactV1

namespace BoundResolvedSbpfArtifactV1

/-- Recover the strictly parsed artifact after its source identity was bound. -/
def resolvedOf (bound : BoundResolvedSbpfArtifactV1) : ResolvedSbpfArtifactV1 :=
  bound.artifact

end BoundResolvedSbpfArtifactV1

private structure PendingInstructionV1 where
  line : Nat
  mnemonic : String
  operands : Array String
  deriving Inhabited

private def maxArtifactBytesV1 : Nat := 1024 * 1024
private def maxArtifactLinesV1 : Nat := 4096
private def maxArtifactLineBytesV1 : Nat := 4096

private def failArtifactV1 (line : Nat) (message : String) :
    SbpfArtifactResultV1 α :=
  .error { line, message }

private def isAsciiLetterV1 (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z')

private def isLowerHexDigitV1 (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- Executable canonical spelling check used by the production artifact gate
    and its proof-carrying SHA replay theorem. -/
def isCanonicalSha256V1 (value : String) : Bool :=
  value.length == 64 && value.toList.all isLowerHexDigitV1

private def isIdentifierV1 (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      (isAsciiLetterV1 first || first == '_') &&
        rest.all fun c => isAsciiLetterV1 c || ('0' ≤ c && c ≤ '9') || c == '_'

private def compactAsciiSpaceV1 (value : String) : String :=
  String.ofList <| value.toList.filter fun c => c != ' ' && c != '\t'

private def hexDigitValueV1 (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

private def parseHexNatV1 (value : String) : Option Nat := do
  unless !value.isEmpty do none
  let mut result := 0
  for c in value.toList do
    let digit ← hexDigitValueV1 c
    result := result * 16 + digit
  pure result

private def parseNatLiteralV1 (value : String) : Option Nat :=
  if value.startsWith "0x" || value.startsWith "0X" then
    parseHexNatV1 (value.drop 2).copy
  else
    value.toNat?

private def lookupEntryV1 (entries : Array (String × α)) (name : String) : Option α :=
  entries.findSome? fun entry => if entry.1 == name then some entry.2 else none

private def parseAtomV1 (line : Nat) (constants : Array (String × Int))
    (value : String) : SbpfArtifactResultV1 Int :=
  match parseNatLiteralV1 value with
  | some literal => pure literal
  | none =>
      match lookupEntryV1 constants value with
      | some constant => pure constant
      | none => failArtifactV1 line s!"unknown immediate or constant '{value}'"

private def evalSignedPartsV1 (line : Nat) (constants : Array (String × Int))
    (parts : List String) : SbpfArtifactResultV1 Int := do
  let mut total : Int := 0
  for part in parts do
    unless !part.isEmpty do
      return ← failArtifactV1 line "empty term in immediate expression"
    let negative := part.startsWith "-"
    let atom := if negative then (part.drop 1).copy else part
    unless !atom.isEmpty do
      return ← failArtifactV1 line "empty signed immediate term"
    let value ← parseAtomV1 line constants atom
    total := if negative then total - value else total + value
  pure total

private def parseImmediateV1 (line : Nat) (constants : Array (String × Int))
    (value : String) : SbpfArtifactResultV1 Int := do
  let compact := compactAsciiSpaceV1 value
  unless !compact.isEmpty do
    return ← failArtifactV1 line "empty immediate"
  let normalized := compact.replace "-" "+-"
  let rawParts := normalized.splitOn "+"
  let parts :=
    match rawParts with
    | "" :: rest => if compact.startsWith "-" then rest else rawParts
    | _ => rawParts
  evalSignedPartsV1 line constants parts

private def register?V1 (value : String) : Option SbpfSemantics.Reg := do
  unless value.startsWith "r" do none
  let index ← (value.drop 1).toNat?
  if h : index < 11 then some ⟨index, h⟩ else none

private def parseRegisterV1 (line : Nat) (value : String) :
    SbpfArtifactResultV1 SbpfSemantics.Reg :=
  match register?V1 (compactAsciiSpaceV1 value) with
  | some register => pure register
  | none => failArtifactV1 line s!"invalid register '{value}'"

private def parseWordV1 (line : Nat) (value : Int) :
    SbpfArtifactResultV1 SbpfSemantics.Word := do
  let minValue : Int := -(2 ^ 63)
  let maxExclusive : Int := 2 ^ 64
  unless minValue ≤ value && value < maxExclusive do
    return ← failArtifactV1 line s!"64-bit immediate out of range: {value}"
  pure (BitVec.ofInt 64 value)

private def parseOff16V1 (line : Nat) (value : Int) :
    SbpfArtifactResultV1 SbpfSemantics.Off16 := do
  unless (-32768 : Int) ≤ value && value ≤ 32767 do
    return ← failArtifactV1 line s!"signed 16-bit offset out of range: {value}"
  pure (BitVec.ofInt 16 value)

private def parseAddressV1 (line : Nat) (constants : Array (String × Int))
    (value : String) : SbpfArtifactResultV1 (SbpfSemantics.Reg × SbpfSemantics.Off16) := do
  let compact := compactAsciiSpaceV1 value
  unless compact.startsWith "[" && compact.endsWith "]" && compact.length ≥ 3 do
    return ← failArtifactV1 line s!"invalid memory operand '{value}'"
  let inner := ((compact.drop 1).take (compact.length - 2)).copy
  let parts := (inner.replace "-" "+-").splitOn "+"
  let base :: offsetParts := parts |
    return ← failArtifactV1 line s!"invalid memory operand '{value}'"
  let register ← parseRegisterV1 line base
  let offset ←
    if offsetParts.isEmpty then pure 0
    else evalSignedPartsV1 line constants offsetParts
  pure (register, ← parseOff16V1 line offset)

private def targetOffsetV1 (line pc : Nat) (labels : Array (String × Nat))
    (target : String) : SbpfArtifactResultV1 Int :=
  match lookupEntryV1 labels target with
  | none => failArtifactV1 line s!"unresolved label '{target}'"
  | some targetPc => pure ((targetPc : Int) - (pc : Int) - 1)

private def checkedInstructionV1 (line : Nat) (instruction : SbpfSemantics.Instr) :
    SbpfArtifactResultV1 SbpfSemantics.Instr := do
  unless instruction.wellFormed do
    return ← failArtifactV1 line "provider rejected instruction operand shape"
  if instruction.syscall.isNone then
    unless instruction.encodable do
      return ← failArtifactV1 line "instruction is not encodable in the provider V3 domain"
  pure instruction

private def requireOperandCountV1 (instruction : PendingInstructionV1) (count : Nat) :
    SbpfArtifactResultV1 Unit :=
  if instruction.operands.size == count then pure ()
  else failArtifactV1 instruction.line
    s!"'{instruction.mnemonic}' expects {count} operands, got {instruction.operands.size}"

private def binaryOpcodesV1 (mnemonic : String) :
    Option (SbpfSemantics.Opcode × SbpfSemantics.Opcode) :=
  match mnemonic with
  | "mov64" => some (.Mov64Imm, .Mov64Reg)
  | "add64" => some (.Add64Imm, .Add64Reg)
  | "sub64" => some (.Sub64Imm, .Sub64Reg)
  | _ => none

private def jumpOpcodesV1 (mnemonic : String) :
    Option (SbpfSemantics.Opcode × SbpfSemantics.Opcode) :=
  match mnemonic with
  | "jeq" => some (.JeqImm, .JeqReg)
  | "jne" => some (.JneImm, .JneReg)
  | "jgt" => some (.JgtImm, .JgtReg)
  | "jlt" => some (.JltImm, .JltReg)
  | _ => none

private def resolveInstructionV1
    (constants : Array (String × Int))
    (labels : Array (String × Nat))
    (pc : Nat)
    (pending : PendingInstructionV1) : SbpfArtifactResultV1 SbpfSemantics.Instr := do
  let line := pending.line
  if let some (immediateOpcode, registerOpcode) := binaryOpcodesV1 pending.mnemonic then
    requireOperandCountV1 pending 2
    let destination ← parseRegisterV1 line pending.operands[0]!
    let instruction ←
      match register?V1 (compactAsciiSpaceV1 pending.operands[1]!) with
      | some source => pure <| Instr.binReg registerOpcode destination source
      | none =>
          let immediate ← parseImmediateV1 line constants pending.operands[1]!
          pure <| Instr.binImm immediateOpcode destination (← parseWordV1 line immediate)
    return ← checkedInstructionV1 line instruction
  if let some (immediateOpcode, registerOpcode) := jumpOpcodesV1 pending.mnemonic then
    requireOperandCountV1 pending 3
    let destination ← parseRegisterV1 line pending.operands[0]!
    let offset ← parseOff16V1 line <|
      ← targetOffsetV1 line pc labels pending.operands[2]!
    let instruction ←
      match register?V1 (compactAsciiSpaceV1 pending.operands[1]!) with
      | some source => pure <| Instr.jumpReg registerOpcode destination source offset
      | none =>
          let immediate ← parseImmediateV1 line constants pending.operands[1]!
          pure <| Instr.jumpImm immediateOpcode destination
            (← parseWordV1 line immediate) offset
    return ← checkedInstructionV1 line instruction
  let instruction ← match pending.mnemonic with
    | "lddw" => do
        requireOperandCountV1 pending 2
        let destination ← parseRegisterV1 line pending.operands[0]!
        let immediate ← parseImmediateV1 line constants pending.operands[1]!
        pure <| Instr.lddw destination (← parseWordV1 line immediate)
    | "ldxb" | "ldxdw" => do
        requireOperandCountV1 pending 2
        let destination ← parseRegisterV1 line pending.operands[0]!
        let (source, offset) ← parseAddressV1 line constants pending.operands[1]!
        let opcode := if pending.mnemonic == "ldxb" then Opcode.Ldxb else Opcode.Ldxdw
        pure <| Instr.loadMem opcode destination source offset
    | "stxdw" => do
        requireOperandCountV1 pending 2
        let (destination, offset) ← parseAddressV1 line constants pending.operands[0]!
        let source ← parseRegisterV1 line pending.operands[1]!
        pure <| Instr.storeReg .Stxdw destination source offset
    | "ja" => do
        requireOperandCountV1 pending 1
        let offset ← parseOff16V1 line <|
          ← targetOffsetV1 line pc labels pending.operands[0]!
        pure <| Instr.ja offset
    | "call" => do
        requireOperandCountV1 pending 1
        let target := pending.operands[0]!
        match lookupEntryV1 labels target with
        | some _ =>
            let offset ← targetOffsetV1 line pc labels target
            let word ← parseWordV1 line offset
            pure <| Instr.callRel word
        | none =>
            if target == "sol_set_return_data" then
              pure <| Instr.callSyscall target
            else
              failArtifactV1 line s!"unsupported syscall or unresolved call target '{target}'"
    | "exit" => do
        requireOperandCountV1 pending 0
        pure Instr.exit
    | mnemonic =>
        failArtifactV1 line s!"unsupported instruction '{mnemonic}'"
  checkedInstructionV1 line instruction

private def instructionFieldsV1 (line : String) : Option (String × Array String) :=
  let chars := line.toList
  let mnemonicChars := chars.takeWhile fun c => c != ' ' && c != '\t'
  let restChars := (chars.drop mnemonicChars.length).dropWhile fun c => c == ' ' || c == '\t'
  let mnemonic := String.ofList mnemonicChars
  if mnemonic.isEmpty then none
  else
    let rest := String.ofList restChars
    let operands :=
      if rest.isEmpty then #[]
      else (rest.splitOn ",").toArray.map (·.trimAscii.copy)
    some (mnemonic, operands)

/-- Parse and resolve exactly one production `.s` artifact into the pinned
    provider's L2 program. This function never accepts HandlerIR or Plan. -/
def resolveSbpfArtifactV1 (text : String) :
    SbpfArtifactResultV1 ResolvedSbpfArtifactV1 := do
  unless text.toUTF8.size ≤ maxArtifactBytesV1 do
    return ← failArtifactV1 0
      s!"artifact exceeds {maxArtifactBytesV1} UTF-8 bytes"
  let lines := (text.splitOn "\n").toArray
  unless lines.size ≤ maxArtifactLinesV1 do
    return ← failArtifactV1 0 s!"artifact exceeds {maxArtifactLinesV1} lines"
  let mut constants : Array (String × Int) := #[]
  let mut labels : Array (String × Nat) := #[]
  let mut pending : Array PendingInstructionV1 := #[]
  let mut global : Option String := none
  for lineIndex in [:lines.size] do
    let lineNumber := lineIndex + 1
    let sourceLine := lines[lineIndex]!
    unless sourceLine.toUTF8.size ≤ maxArtifactLineBytesV1 do
      return ← failArtifactV1 lineNumber
        s!"line exceeds {maxArtifactLineBytesV1} UTF-8 bytes"
    let withoutComment :=
      match sourceLine.splitOn ";" with
      | head :: _ => head
      | [] => ""
    let line := withoutComment.trimAscii.copy
    if line.isEmpty then
      continue
    else if line.startsWith ".equ " then
      let fields := ((line.drop 5).copy.splitOn ",").map (·.trimAscii.copy)
      let name :: value :: [] := fields |
        return ← failArtifactV1 lineNumber "malformed .equ directive"
      unless isIdentifierV1 name do
        return ← failArtifactV1 lineNumber s!"invalid .equ name '{name}'"
      if (lookupEntryV1 constants name).isSome || (lookupEntryV1 labels name).isSome then
        return ← failArtifactV1 lineNumber s!"duplicate symbol '{name}'"
      let some literal := parseNatLiteralV1 value |
        return ← failArtifactV1 lineNumber s!".equ value must be an unsigned literal: '{value}'"
      constants := constants.push (name, literal)
    else if line.startsWith ".globl " then
      let name := (line.drop 7).trimAscii.copy
      unless isIdentifierV1 name do
        return ← failArtifactV1 lineNumber s!"invalid global name '{name}'"
      unless global.isNone do
        return ← failArtifactV1 lineNumber "duplicate .globl directive"
      global := some name
    else if line.startsWith "." then
      return ← failArtifactV1 lineNumber s!"unsupported directive '{line}'"
    else if line.endsWith ":" then
      let name := (line.take (line.length - 1)).copy
      unless isIdentifierV1 name do
        return ← failArtifactV1 lineNumber s!"invalid label '{name}'"
      if (lookupEntryV1 labels name).isSome || (lookupEntryV1 constants name).isSome then
        return ← failArtifactV1 lineNumber s!"duplicate symbol '{name}'"
      labels := labels.push (name, pending.size)
    else
      let some (mnemonic, operands) := instructionFieldsV1 line |
        return ← failArtifactV1 lineNumber "malformed instruction"
      pending := pending.push { line := lineNumber, mnemonic, operands }
  let some globalName := global |
    return ← failArtifactV1 0 "missing .globl directive"
  let some globalPc := lookupEntryV1 labels globalName |
    return ← failArtifactV1 0 s!"global '{globalName}' has no label"
  unless globalPc == 0 do
    return ← failArtifactV1 0 s!"global '{globalName}' must resolve to instruction 0"
  unless !pending.isEmpty do
    return ← failArtifactV1 0 "artifact contains no instructions"
  let mut program : SbpfSemantics.Program := #[]
  for pc in [:pending.size] do
    program := program.push (← resolveInstructionV1 constants labels pc pending[pc]!)
  pure {
    sourceSha256 := ProofForgeV2.Crypto.sha256Hex text.toUTF8
    global := globalName
    constants
    labels
    program
  }

/-- Identity-bound entrypoint for a production artifact selected by an output
    set or other trusted producer. A syntactically valid mutation is still a
    different artifact and is rejected before parsing or execution. -/
def resolveBoundSbpfArtifactV1 (text expectedSha256 : String) :
    SbpfArtifactResultV1 BoundResolvedSbpfArtifactV1 := do
  unless isCanonicalSha256V1 expectedSha256 do
    return ← failArtifactV1 0 "expected SHA-256 must be 64 lowercase hex characters"
  let actualSha256 := ProofForgeV2.Crypto.sha256Hex text.toUTF8
  unless actualSha256 == expectedSha256 do
    return ← failArtifactV1 0 "artifact SHA-256 does not match the expected production identity"
  pure ⟨← resolveSbpfArtifactV1 text⟩

/-- Replay a kernel SHA certificate through the real identity-bound artifact
    resolver. Exact parser success remains a separate obligation; no copied
    assembly, alternate parser, or runtime Boolean is accepted as identity
    evidence. -/
theorem resolveBoundSbpfArtifactV1_eq_ok_of_sha256_certificate
    (certificate : ProofForgeV2.Crypto.Sha256HexCertificate
      text.toUTF8 expectedSha256)
    (canonical : isCanonicalSha256V1 expectedSha256 = true)
    (artifact : ResolvedSbpfArtifactV1)
    (parsed : resolveSbpfArtifactV1 text = .ok artifact) :
    ∃ bound : BoundResolvedSbpfArtifactV1,
      resolveBoundSbpfArtifactV1 text expectedSha256 = .ok bound ∧
      bound.resolvedOf = artifact := by
  refine ⟨⟨artifact⟩, ?_, rfl⟩
  have hashMatches :
      (ProofForgeV2.Crypto.sha256Hex text.toUTF8 == expectedSha256) = true := by
    simpa using certificate.sound
  unfold resolveBoundSbpfArtifactV1
  simp only [canonical, ↓reduceIte]
  rw [hashMatches, parsed]
  rfl

end ProofForgeV2.Targets.Solana
