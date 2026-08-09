import Lean
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.WireV1

/-!
  ProofForgeV2.Language.SubjectDataQuoteV1 — elaborator quoter for structured
  `SemanticProgramDataV1` (wave-3′ mig-a3-elab).

  Product surface: emit `subjectDataV1` as a constructor spine so same-file
  proofs can reason on tables/callables without large `subjectBytesV1` spine
  defeq. Byte identity remains owned by `subjectBytesV1` / pin for the
  certifier; this module only builds Lean syntax from Normalize data.
-/

namespace ProofForgeV2.Language.SubjectDataQuoteV1

open Lean
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1

/-- Transparent `ByteArray.mk (List.toArray […])` (same shape as elaborator
    `quoteByteArraySpine`). -/
def quoteByteArraySpine (bytes : ByteArray) : MacroM (TSyntax `term) := do
  let mut elems : Array (TSyntax `term) := #[]
  for b in bytes do
    elems := elems.push (quote b.toNat)
  `(ByteArray.mk (List.toArray [$elems,*]))

private def quoteU16 (n : UInt16) : MacroM (TSyntax `term) :=
  `(UInt16.ofNat $(quote n.toNat))
private def quoteU32 (n : UInt32) : MacroM (TSyntax `term) :=
  `(UInt32.ofNat $(quote n.toNat))

private def quoteU64 (n : UInt64) : MacroM (TSyntax `term) :=
  `(UInt64.ofNat $(quote n.toNat))

private def quoteOption
    (quoteA : α → MacroM (TSyntax `term)) (o : Option α) :
    MacroM (TSyntax `term) := do
  match o with
  | none => `(none)
  | some a =>
      let t ← quoteA a
      `(some $t)

private def quoteArray
    (quoteA : α → MacroM (TSyntax `term)) (xs : Array α) :
    MacroM (TSyntax `term) := do
  let mut elems : Array (TSyntax `term) := #[]
  for x in xs do
    elems := elems.push (← quoteA x)
  `(#[$elems,*])

private def quoteStringArray (xs : Array String) : MacroM (TSyntax `term) :=
  quoteArray (fun s => pure (quote s)) xs

private def quoteVisibility (v : VisibilityV1) : MacroM (TSyntax `term) :=
  match v with
  | .public_ =>
      `(ProofForgeV2.Semantic.WireV1.VisibilityV1.public_)
  | .private_ =>
      `(ProofForgeV2.Semantic.WireV1.VisibilityV1.private_)
  | .commitment =>
      `(ProofForgeV2.Semantic.WireV1.VisibilityV1.commitment)

private def quoteSchemaId (id : SchemaId) : MacroM (TSyntax `term) :=
  `({ value := $(quote id.value) : ProofForgeV2.Core.Common.SchemaId })

private def quoteFieldSpec (spec : FieldSpecV1) : MacroM (TSyntax `term) := do
  let id ← quoteSchemaId spec.id
  let mod ← quoteByteArraySpine spec.modulusBE
  `({ id := $id, modulusBE := $mod :
      ProofForgeV2.Semantic.WireV1.FieldSpecV1 })

private def quoteStructField (f : StructFieldV1) : MacroM (TSyntax `term) := do
  let tid ← quoteU32 f.typeId
  `({ name := $(quote f.name), typeId := $tid :
      ProofForgeV2.Semantic.WireV1.StructFieldV1 })

private def quoteEnumVariant (v : EnumVariantV1) : MacroM (TSyntax `term) := do
  let payloads ← quoteArray quoteU32 v.payloadTypes
  `({ name := $(quote v.name), payloadTypes := $payloads :
      ProofForgeV2.Semantic.WireV1.EnumVariantV1 })

private def quoteTypeShape (shape : TypeShapeV1) : MacroM (TSyntax `term) := do
  match shape with
  | .bool =>
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.bool)
  | .uint w =>
      let ww ← quoteU16 w
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.uint $ww)
  | .int w =>
      let ww ← quoteU16 w
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.int $ww)
  | .principal =>
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.principal)
  | .unit =>
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.unit)
  | .string =>
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.string)
  | .bytes len =>
      let l ← quoteU32 len
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.bytes $l)
  | .array el len =>
      let e ← quoteU32 el
      let l ← quoteU32 len
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.array $e $l)
  | .map k v =>
      let kk ← quoteU32 k
      let vv ← quoteU32 v
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.map $kk $vv)
  | .option el =>
      let e ← quoteU32 el
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.option $e)
  | .field spec =>
      let s ← quoteFieldSpec spec
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.field $s)
  | .struct fields =>
      let fs ← quoteArray quoteStructField fields
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.struct $fs)
  | .enum variants =>
      let vs ← quoteArray quoteEnumVariant variants
      `(ProofForgeV2.Semantic.WireV1.TypeShapeV1.enum $vs)

/-- Quote one production type declaration for generated proof terms. -/
def quoteTypeDeclV1 (t : TypeDeclV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 t.id
  let name ← quoteOption (fun s => pure (quote s)) t.name
  let shape ← quoteTypeShape t.shape
  `({ id := $id, name := $name, shape := $shape :
      ProofForgeV2.Semantic.WireV1.TypeDeclV1 })

private def quoteConstant (c : ConstantV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 c.id
  let tid ← quoteU32 c.typeId
  let vb ← quoteByteArraySpine c.valueBytes
  `({ id := $id, name := $(quote c.name), typeId := $tid, valueBytes := $vb :
      ProofForgeV2.Semantic.WireV1.ConstantV1 })

/-- Quote one production logical-state declaration for generated proof terms. -/
def quoteStateDeclV1 (s : StateDeclV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 s.id
  let tid ← quoteU32 s.typeId
  let vis ← quoteVisibility s.visibility
  `({ id := $id, name := $(quote s.name), typeId := $tid, visibility := $vis :
      ProofForgeV2.Semantic.WireV1.StateDeclV1 })

private def quoteInterfaceField (f : InterfaceFieldV1) : MacroM (TSyntax `term) := do
  let tid ← quoteU32 f.typeId
  let vis ← quoteVisibility f.visibility
  `({ name := $(quote f.name), typeId := $tid, visibility := $vis :
      ProofForgeV2.Semantic.WireV1.InterfaceFieldV1 })

private def quoteEventDecl (e : EventDeclV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 e.id
  let fields ← quoteArray quoteInterfaceField e.fields
  `({ id := $id, name := $(quote e.name), fields := $fields :
      ProofForgeV2.Semantic.WireV1.EventDeclV1 })

private def quoteErrorDecl (e : ErrorDeclV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 e.id
  let fields ← quoteArray quoteInterfaceField e.fields
  `({ id := $id, name := $(quote e.name), fields := $fields :
      ProofForgeV2.Semantic.WireV1.ErrorDeclV1 })

private def quoteCallableKind (k : CallableKindV1) : MacroM (TSyntax `term) :=
  match k with
  | .initializer =>
      `(ProofForgeV2.Semantic.WireV1.CallableKindV1.initializer)
  | .entry =>
      `(ProofForgeV2.Semantic.WireV1.CallableKindV1.entry)
  | .view =>
      `(ProofForgeV2.Semantic.WireV1.CallableKindV1.view)
  | .pureFn =>
      `(ProofForgeV2.Semantic.WireV1.CallableKindV1.pureFn)
  | .invariant =>
      `(ProofForgeV2.Semantic.WireV1.CallableKindV1.invariant)

private def quoteParameter (p : ParameterV1) : MacroM (TSyntax `term) := do
  let vid ← quoteU32 p.valueId
  let tid ← quoteU32 p.typeId
  let vis ← quoteVisibility p.visibility
  `({ valueId := $vid, name := $(quote p.name), typeId := $tid,
      visibility := $vis : ProofForgeV2.Semantic.WireV1.ParameterV1 })

private def quoteCallableResult (r : CallableResultV1) : MacroM (TSyntax `term) := do
  let tid ← quoteU32 r.typeId
  let vis ← quoteVisibility r.visibility
  `({ typeId := $tid, visibility := $vis :
      ProofForgeV2.Semantic.WireV1.CallableResultV1 })

private def quoteValueDef (v : ValueDefV1) : MacroM (TSyntax `term) := do
  let vid ← quoteU32 v.valueId
  let tid ← quoteU32 v.typeId
  `({ valueId := $vid, typeId := $tid :
      ProofForgeV2.Semantic.WireV1.ValueDefV1 })

private def quoteBlockParam (p : BlockParameterV1) : MacroM (TSyntax `term) := do
  let vid ← quoteU32 p.valueId
  let tid ← quoteU32 p.typeId
  `({ valueId := $vid, typeId := $tid :
      ProofForgeV2.Semantic.WireV1.BlockParameterV1 })

private def quoteUnaryOp (op : UnaryOpV1) : MacroM (TSyntax `term) :=
  match op with
  | .neg => `(ProofForgeV2.Semantic.WireV1.UnaryOpV1.neg)
  | .not => `(ProofForgeV2.Semantic.WireV1.UnaryOpV1.not)
  | .bitNot => `(ProofForgeV2.Semantic.WireV1.UnaryOpV1.bitNot)

private def quoteBinaryOp (op : BinaryOpV1) : MacroM (TSyntax `term) :=
  match op with
  | .add => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.add)
  | .sub => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.sub)
  | .mul => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.mul)
  | .div => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.div)
  | .mod => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.mod)
  | .eq => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.eq)
  | .ne => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.ne)
  | .lt => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.lt)
  | .le => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.le)
  | .gt => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.gt)
  | .ge => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.ge)
  | .and => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.and)
  | .or => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.or)
  | .bitAnd => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.bitAnd)
  | .bitOr => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.bitOr)
  | .bitXor => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.bitXor)
  | .shl => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.shl)
  | .shr => `(ProofForgeV2.Semantic.WireV1.BinaryOpV1.shr)

private def quoteEnvReadKey (k : EnvReadKeyV1) : MacroM (TSyntax `term) :=
  match k with
  | .nativeVaultBalance =>
      `(ProofForgeV2.Semantic.WireV1.EnvReadKeyV1.nativeVaultBalance)
  | .tokenVaultBalance =>
      `(ProofForgeV2.Semantic.WireV1.EnvReadKeyV1.tokenVaultBalance)

private def quoteQualifiedName (qn : QualifiedName) : MacroM (TSyntax `term) := do
  let head := quote qn.components.head
  let tail ← quoteStringArray qn.components.tail
  `({ components :=
        (⟨$head, $tail⟩ : ProofForgeV2.Core.Common.NonEmptyArray String) :
      ProofForgeV2.Core.Common.QualifiedName })

private partial def quoteOp (op : SemanticOpV1) : MacroM (TSyntax `term) := do
  match op with
  | .literal tid bytes =>
      let t ← quoteU32 tid
      let b ← quoteByteArraySpine bytes
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.literal $t $b)
  | .constant cid =>
      let c ← quoteU32 cid
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.constant $c)
  | .stateLoad sid =>
      let s ← quoteU32 sid
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.stateLoad $s)
  | .stateStore sid v =>
      let s ← quoteU32 sid
      let vv ← quoteU32 v
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.stateStore $s $vv)
  | .construct tid idx args =>
      let t ← quoteU32 tid
      let i ← quoteU32 idx
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.construct $t $i $a)
  | .fieldGet base idx =>
      let b ← quoteU32 base
      let i ← quoteU32 idx
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.fieldGet $b $i)
  | .fieldSet base idx v =>
      let b ← quoteU32 base
      let i ← quoteU32 idx
      let vv ← quoteU32 v
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.fieldSet $b $i $vv)
  | .variantTag base =>
      let b ← quoteU32 base
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.variantTag $b)
  | .variantPayload base vi pi =>
      let b ← quoteU32 base
      let v ← quoteU32 vi
      let p ← quoteU32 pi
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.variantPayload $b $v $p)
  | .indexGet base index =>
      let b ← quoteU32 base
      let i ← quoteU32 index
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.indexGet $b $i)
  | .indexSet base index value =>
      let b ← quoteU32 base
      let i ← quoteU32 index
      let v ← quoteU32 value
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.indexSet $b $i $v)
  | .checkedCast value toType =>
      let v ← quoteU32 value
      let t ← quoteU32 toType
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.checkedCast $v $t)
  | .unary op operand =>
      let o ← quoteUnaryOp op
      let a ← quoteU32 operand
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.unary $o $a)
  | .binary op lhs rhs =>
      let o ← quoteBinaryOp op
      let l ← quoteU32 lhs
      let r ← quoteU32 rhs
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.binary $o $l $r)
  | .pureCall cid args =>
      let c ← quoteU32 cid
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.pureCall $c $a)
  | .contextRead key =>
      let k ← quoteSchemaId key
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.contextRead $k)
  | .envRead key args =>
      let k ← quoteEnvReadKey key
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.envRead $k $a)
  | .commit value =>
      let v ← quoteU32 value
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.commit $v)
  | .assert_ cond errId args =>
      let c ← quoteU32 cond
      let e ← quoteOption quoteU32 errId
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.assert_ $c $e $a)
  | .emit eid eventId args =>
      let e ← quoteU32 eid
      let ev ← quoteU32 eventId
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.emit $e $ev $a)
  | .externalCall eid callee args =>
      let e ← quoteU32 eid
      let c ← quoteQualifiedName callee
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.externalCall $e $c $a)
  | .schedule eid callee args =>
      let e ← quoteU32 eid
      let c ← quoteQualifiedName callee
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.SemanticOpV1.schedule $e $c $a)

private def quoteInstruction (ins : InstructionV1) : MacroM (TSyntax `term) := do
  let result ← quoteOption quoteValueDef ins.result
  let op ← quoteOp ins.op
  `({ result := $result, op := $op :
      ProofForgeV2.Semantic.WireV1.InstructionV1 })

private def quoteJumpTarget (t : JumpTargetV1) : MacroM (TSyntax `term) := do
  let bid ← quoteU32 t.blockId
  let args ← quoteArray quoteU32 t.args
  `({ blockId := $bid, args := $args :
      ProofForgeV2.Semantic.WireV1.JumpTargetV1 })

private def quoteSwitchCase (c : SwitchCaseV1) : MacroM (TSyntax `term) := do
  let tid ← quoteU32 c.typeId
  let vb ← quoteByteArraySpine c.valueBytes
  let tgt ← quoteJumpTarget c.target
  `({ typeId := $tid, valueBytes := $vb, target := $tgt :
      ProofForgeV2.Semantic.WireV1.SwitchCaseV1 })

private def quoteTrapCode (c : SemanticTrapCodeV1) : MacroM (TSyntax `term) :=
  match c with
  | .unreachable =>
      `(ProofForgeV2.Semantic.WireV1.SemanticTrapCodeV1.unreachable)
  | .invalidExternalResponse =>
      `(ProofForgeV2.Semantic.WireV1.SemanticTrapCodeV1.invalidExternalResponse)
  | .resourceExhausted =>
      `(ProofForgeV2.Semantic.WireV1.SemanticTrapCodeV1.resourceExhausted)
  | .internalInvariant =>
      `(ProofForgeV2.Semantic.WireV1.SemanticTrapCodeV1.internalInvariant)

private def quoteTerminator (t : TerminatorV1) : MacroM (TSyntax `term) := do
  match t with
  | .jump tgt =>
      let x ← quoteJumpTarget tgt
      `(ProofForgeV2.Semantic.WireV1.TerminatorV1.jump $x)
  | .branch cond thenT elseT =>
      let c ← quoteU32 cond
      let th ← quoteJumpTarget thenT
      let el ← quoteJumpTarget elseT
      `(ProofForgeV2.Semantic.WireV1.TerminatorV1.branch $c $th $el)
  | .switch scrut cases defaultT =>
      let s ← quoteU32 scrut
      let cs ← quoteArray quoteSwitchCase cases
      let d ← quoteOption quoteJumpTarget defaultT
      `(ProofForgeV2.Semantic.WireV1.TerminatorV1.switch $s $cs $d)
  | .return_ value =>
      let v ← quoteOption quoteU32 value
      `(ProofForgeV2.Semantic.WireV1.TerminatorV1.return_ $v)
  | .revert errId args =>
      let e ← quoteU32 errId
      let a ← quoteArray quoteU32 args
      `(ProofForgeV2.Semantic.WireV1.TerminatorV1.revert $e $a)
  | .trap code =>
      let c ← quoteTrapCode code
      `(ProofForgeV2.Semantic.WireV1.TerminatorV1.trap $c)

private def quoteBlock (b : BlockV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 b.id
  let params ← quoteArray quoteBlockParam b.params
  let ins ← quoteArray quoteInstruction b.instructions
  let term ← quoteTerminator b.terminator
  `({ id := $id, params := $params, instructions := $ins, terminator := $term :
      ProofForgeV2.Semantic.WireV1.BlockV1 })

private def quoteLoopBound (lb : LoopBoundV1) : MacroM (TSyntax `term) := do
  let h ← quoteU32 lb.header
  let be ← quoteU32 lb.backEdgeFrom
  let m ← quoteU32 lb.maxIterations
  `({ header := $h, backEdgeFrom := $be, maxIterations := $m :
      ProofForgeV2.Semantic.WireV1.LoopBoundV1 })

private def quoteCallable (c : CallableV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 c.id
  let kind ← quoteCallableKind c.kind
  let name ← quoteOption (fun s => pure (quote s)) c.name
  let params ← quoteArray quoteParameter c.params
  let result ← quoteCallableResult c.result
  let entry ← quoteU32 c.entryBlock
  let blocks ← quoteArray quoteBlock c.blocks
  let lbs ← quoteArray quoteLoopBound c.loopBounds
  let steps ← quoteOption quoteU64 c.invariantSteps
  `({ id := $id, kind := $kind, name := $name, params := $params,
      result := $result, entryBlock := $entry, blocks := $blocks,
      loopBounds := $lbs, invariantSteps := $steps :
      ProofForgeV2.Semantic.WireV1.CallableV1 })

private def quoteInvariantDecl (inv : InvariantDeclV1) : MacroM (TSyntax `term) := do
  let id ← quoteU32 inv.id
  let cid ← quoteU32 inv.callableId
  `({ id := $id, name := $(quote inv.name), callableId := $cid :
      ProofForgeV2.Semantic.WireV1.InvariantDeclV1 })

private def quoteDigest (d : Digest) : MacroM (TSyntax `term) := do
  let bytes ← quoteByteArraySpine d.bytes
  match d.algorithm with
  | .sha256 =>
      `({ algorithm := ProofForgeV2.Core.Common.DigestAlgorithm.sha256,
          bytes := $bytes : ProofForgeV2.Core.Common.Digest })

private def quoteSemVer (v : SemVer) : MacroM (TSyntax `term) := do
  let major ← quoteU64 v.major
  let minor ← quoteU64 v.minor
  let patch ← quoteU64 v.patch
  let pre ← quoteStringArray v.prerelease
  let build ← quoteStringArray v.build
  `({ major := $major, minor := $minor, patch := $patch,
      prerelease := $pre, build := $build :
      ProofForgeV2.Core.Common.SemVer })

private def quoteRequirementPredicate
    (p : RequirementPredicateV1) : MacroM (TSyntax `term) := do
  match p with
  | .uintAtLeast name value =>
      let v ← quoteU64 value
      `(ProofForgeV2.Semantic.WireV1.RequirementPredicateV1.uintAtLeast
          $(quote name) $v)
  | .uintAtMost name value =>
      let v ← quoteU64 value
      `(ProofForgeV2.Semantic.WireV1.RequirementPredicateV1.uintAtMost
          $(quote name) $v)
  | .boolEquals name value =>
      `(ProofForgeV2.Semantic.WireV1.RequirementPredicateV1.boolEquals
          $(quote name) $(quote value))
  | .enumContains name values =>
      let vs ← quoteStringArray values
      `(ProofForgeV2.Semantic.WireV1.RequirementPredicateV1.enumContains
          $(quote name) $vs)
  | .digestEquals name value =>
      let d ← quoteDigest value
      `(ProofForgeV2.Semantic.WireV1.RequirementPredicateV1.digestEquals
          $(quote name) $d)

private def quoteRequirementRequest
    (r : RequirementRequestV1) : MacroM (TSyntax `term) := do
  let version ← quoteSemVer r.version
  let digest ← quoteDigest r.digest
  let preds ← quoteArray quoteRequirementPredicate r.predicates
  `({ id := $(quote r.id), version := $version, digest := $digest,
      predicates := $preds :
      ProofForgeV2.Semantic.WireV1.RequirementRequestV1 })

private def quoteRequirements
    (req : ProgramRequirementsV1) : MacroM (TSyntax `term) := do
  let items ← quoteArray quoteRequirementRequest req.items
  `({ items := $items : ProofForgeV2.Semantic.WireV1.ProgramRequirementsV1 })

/-- Quote a full Normalize/structure-gated `SemanticProgramDataV1` as a Lean
    constructor spine for product `subjectDataV1`. -/
def quoteSemanticProgramDataV1
    (data : SemanticProgramDataV1) : MacroM (TSyntax `term) := do
  let qn ← quoteQualifiedName data.qualifiedName
  let types ← quoteArray quoteTypeDeclV1 data.types
  let constants ← quoteArray quoteConstant data.constants
  let state ← quoteArray quoteStateDeclV1 data.logicalState
  let events ← quoteArray quoteEventDecl data.events
  let errors ← quoteArray quoteErrorDecl data.errors
  let callables ← quoteArray quoteCallable data.callables
  let invariants ← quoteArray quoteInvariantDecl data.invariants
  let requirements ← quoteRequirements data.requirements
  `({ qualifiedName := $qn
      types := $types
      constants := $constants
      logicalState := $state
      events := $events
      errors := $errors
      callables := $callables
      invariants := $invariants
      requirements := $requirements
      : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1 })

end ProofForgeV2.Language.SubjectDataQuoteV1
