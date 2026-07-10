import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Validate

/-! # EVM lowering requirement analysis

Pure analyses over semantic plans used by `Lower.lean` when assembling a full
`ModulePlan`: checked arithmetic, helper requirements, local-array helper
requirements, and context operation discovery.
-/

namespace ProofForge.Backend.Evm.Lower

open ProofForge.IR
open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Validate

def valuePlanUsesCheckedArithmetic : ValuePlan → Bool
  | .irExpr expr => ProofForge.Backend.Evm.Validate.exprUsesCheckedArithmetic expr

def storagePathSegmentUsesCheckedArithmetic : StoragePathSegment → Bool
  | .field _ => false
  | .index index => ProofForge.Backend.Evm.Validate.exprUsesCheckedArithmetic index
  | .mapKey key => ProofForge.Backend.Evm.Validate.exprUsesCheckedArithmetic key

def storageSlotPlanUsesCheckedArithmetic : StorageSlotPlan → Bool
  | .scalarSlot _ | .fixedSlot _ => false
  | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
      keys.any valuePlanUsesCheckedArithmetic
  | .arraySlot _ _ index
  | .structArrayFieldSlot _ _ _ _ index
  | .dynamicArraySlot _ index =>
      valuePlanUsesCheckedArithmetic index

def storagePathWriteTargetPlanUsesCheckedArithmetic : StoragePathWriteTargetPlan → Bool
  | .mapWrite _ key =>
      valuePlanUsesCheckedArithmetic key
  | .singleSlot slot =>
      storageSlotPlanUsesCheckedArithmetic slot
  | .mapValuePresence valueSlot presenceSlot =>
      storageSlotPlanUsesCheckedArithmetic valueSlot ||
        storageSlotPlanUsesCheckedArithmetic presenceSlot

mutual
  partial def contextExprPlanUsesCheckedArithmetic : ContextExprPlan → Bool
    | .blockHash blockNumber =>
        exprPlanUsesCheckedArithmetic blockNumber
    | .userId | .userIdHash | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        false

  partial def storageSlotExprPlanUsesCheckedArithmetic : StorageSlotExprPlan → Bool
    | .scalarSlot _ | .fixedSlot _ => false
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.any exprPlanUsesCheckedArithmetic
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        exprPlanUsesCheckedArithmetic index

  partial def storagePathWriteExprTargetPlanUsesCheckedArithmetic :
      StoragePathWriteExprTargetPlan → Bool
    | .mapWrite _ key =>
        exprPlanUsesCheckedArithmetic key
    | .singleSlot slot =>
        storageSlotExprPlanUsesCheckedArithmetic slot
    | .mapValuePresence valueSlot presenceSlot =>
        storageSlotExprPlanUsesCheckedArithmetic valueSlot ||
          storageSlotExprPlanUsesCheckedArithmetic presenceSlot

  partial def abiValuePlanUsesCheckedArithmetic : AbiValuePlan → Bool
    | .expr value =>
        exprPlanUsesCheckedArithmetic value
    | .local .. | .storage .. =>
        false
    | .arrayLit _ values =>
        values.any abiValuePlanUsesCheckedArithmetic
    | .structLit _ fields =>
        fields.any (fun field => abiValuePlanUsesCheckedArithmetic field.snd)

  partial def crosscallArgWordPlanUsesCheckedArithmetic : CrosscallArgWordPlan → Bool
    | .expr value =>
        exprPlanUsesCheckedArithmetic value
    | .local .. | .storage .. =>
        false

  partial def exprPlanUsesCheckedArithmetic : ExprPlan → Bool
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        false
    | .storageLoad slot =>
        storageSlotPlanUsesCheckedArithmetic slot
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.any exprPlanUsesCheckedArithmetic
    | .checkedArith op lhs rhs _ =>
        needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic lhs ||
          exprPlanUsesCheckedArithmetic rhs
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs =>
        exprPlanUsesCheckedArithmetic lhs || exprPlanUsesCheckedArithmetic rhs
    | .ecrecover a b c d =>
        exprPlanUsesCheckedArithmetic a || exprPlanUsesCheckedArithmetic b ||
          exprPlanUsesCheckedArithmetic c || exprPlanUsesCheckedArithmetic d
    | .eip712PermitDigest a b c d e f =>
        exprPlanUsesCheckedArithmetic a || exprPlanUsesCheckedArithmetic b ||
          exprPlanUsesCheckedArithmetic c || exprPlanUsesCheckedArithmetic d ||
          exprPlanUsesCheckedArithmetic e || exprPlanUsesCheckedArithmetic f
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        exprPlanUsesCheckedArithmetic target
    | .hashPack a b c d | .hashValue a b c d =>
        exprPlanUsesCheckedArithmetic a ||
          exprPlanUsesCheckedArithmetic b ||
          exprPlanUsesCheckedArithmetic c ||
          exprPlanUsesCheckedArithmetic d
    | .context field =>
        contextExprPlanUsesCheckedArithmetic field
    | .crosscall _ target methodId callValue? args _ =>
        exprPlanUsesCheckedArithmetic target ||
          exprPlanUsesCheckedArithmetic methodId ||
          (match callValue? with
          | some callValue => exprPlanUsesCheckedArithmetic callValue
          | none => false) ||
          args.any crosscallArgWordPlanUsesCheckedArithmetic
    | .create _ callValue salt? _ =>
        exprPlanUsesCheckedArithmetic callValue ||
          (match salt? with
          | some salt => exprPlanUsesCheckedArithmetic salt
          | none => false)
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        exprPlanUsesCheckedArithmetic source
    | .localArrayGet _ path _ =>
        path.any exprPlanUsesCheckedArithmetic
    | .memoryArrayNew _ length =>
        exprPlanUsesCheckedArithmetic length
    | .memoryArrayGet array index =>
        exprPlanUsesCheckedArithmetic array || exprPlanUsesCheckedArithmetic index
    | .structLit _ fields =>
        fields.any (fun field => exprPlanUsesCheckedArithmetic field.snd)
    | .effect effect =>
        effectPlanUsesCheckedArithmetic effect

  partial def effectPlanUsesCheckedArithmetic : EffectPlan → Bool
    | .storageScalarRead _ | .storageStructFieldRead _ _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        false
    | .storageScalarReadTarget target =>
        storageSlotPlanUsesCheckedArithmetic target.slot
    | .storageStructFieldReadTarget target =>
        storageSlotPlanUsesCheckedArithmetic target.slot
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        exprPlanUsesCheckedArithmetic value
    | .storageScalarAssignOp _ op value
    | .storageScalarAssignOpTarget _ op value =>
        needsCheckedArithmetic op || exprPlanUsesCheckedArithmetic value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        exprPlanUsesCheckedArithmetic key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        exprPlanUsesCheckedArithmetic key || exprPlanUsesCheckedArithmetic value
    | .memoryArraySet array index value =>
        exprPlanUsesCheckedArithmetic array ||
          exprPlanUsesCheckedArithmetic index ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathRead _ path =>
        path.any storagePathSegmentUsesCheckedArithmetic
    | .storagePathReadTarget slot =>
        storageSlotPlanUsesCheckedArithmetic slot
    | .storagePathReadExprTarget slot =>
        storageSlotExprPlanUsesCheckedArithmetic slot
    | .storagePathWrite _ path value =>
        path.any storagePathSegmentUsesCheckedArithmetic ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathAssignOp _ path op value =>
        path.any storagePathSegmentUsesCheckedArithmetic ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathWriteTarget target value =>
        storagePathWriteTargetPlanUsesCheckedArithmetic target ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathAssignOpTarget target op value =>
        storagePathWriteTargetPlanUsesCheckedArithmetic target ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathWriteExprTarget target value =>
        storagePathWriteExprTargetPlanUsesCheckedArithmetic target ||
          exprPlanUsesCheckedArithmetic value
    | .storagePathAssignOpExprTarget target op value =>
        storagePathWriteExprTargetPlanUsesCheckedArithmetic target ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .contextRead field =>
        contextExprPlanUsesCheckedArithmetic field
    | .eventEmit _ dataFields =>
        dataFields.any abiValuePlanUsesCheckedArithmetic
    | .eventEmitIndexed _ indexedFields dataFields =>
        indexedFields.any abiValuePlanUsesCheckedArithmetic ||
          dataFields.any abiValuePlanUsesCheckedArithmetic
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.any (fun words => words.any exprPlanUsesCheckedArithmetic)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        indexedFieldWords.any (fun words => words.any exprPlanUsesCheckedArithmetic) ||
          dataFieldWords.any (fun words => words.any exprPlanUsesCheckedArithmetic)
    | .checkErc721Received a b c d =>
        exprPlanUsesCheckedArithmetic a || exprPlanUsesCheckedArithmetic b ||
          exprPlanUsesCheckedArithmetic c || exprPlanUsesCheckedArithmetic d
    | .checkErc1155Received a b c d e =>
        exprPlanUsesCheckedArithmetic a || exprPlanUsesCheckedArithmetic b ||
          exprPlanUsesCheckedArithmetic c || exprPlanUsesCheckedArithmetic d ||
          exprPlanUsesCheckedArithmetic e

  partial def stmtPlanUsesCheckedArithmetic : StmtPlan → Bool
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        exprPlanUsesCheckedArithmetic value
    | .assign target value =>
        exprPlanUsesCheckedArithmetic target || exprPlanUsesCheckedArithmetic value
    | .assignOp target op value =>
        exprPlanUsesCheckedArithmetic target ||
          needsCheckedArithmetic op ||
          exprPlanUsesCheckedArithmetic value
    | .effect effect =>
        effectPlanUsesCheckedArithmetic effect
    | .assertEq lhs rhs _ _ =>
        exprPlanUsesCheckedArithmetic lhs || exprPlanUsesCheckedArithmetic rhs
    | .release _ | .revert _ | .revertWithError _ =>
        false
    | .ifElse condition thenBody elseBody =>
        exprPlanUsesCheckedArithmetic condition ||
          thenBody.any stmtPlanUsesCheckedArithmetic ||
          elseBody.any stmtPlanUsesCheckedArithmetic
    | .boundedFor _ _ _ body =>
        body.any stmtPlanUsesCheckedArithmetic
end

def entrypointsUseCheckedArithmetic (entrypoints : Array EntrypointPlan) : Bool :=
  entrypoints.any fun entrypoint => entrypoint.body.any stmtPlanUsesCheckedArithmetic

def pushNatIfMissing (acc : Array Nat) (value : Nat) : Array Nat :=
  if acc.contains value then acc else acc.push value

def mergeNatSets (lhs rhs : Array Nat) : Array Nat :=
  rhs.foldl pushNatIfMissing lhs

def pushNatArrayIfMissing
    (acc : Array (Array Nat))
    (value : Array Nat) : Array (Array Nat) :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeNatArraySets (lhs rhs : Array (Array Nat)) : Array (Array Nat) :=
  rhs.foldl pushNatArrayIfMissing lhs

abbrev LocalArrayHelperRequirements := Array Nat × Array (Array Nat)

def emptyLocalArrayHelperRequirements : LocalArrayHelperRequirements :=
  (#[], #[])

def mergeLocalArrayHelperRequirements
    (lhs rhs : LocalArrayHelperRequirements) : LocalArrayHelperRequirements :=
  (mergeNatSets lhs.fst rhs.fst, mergeNatArraySets lhs.snd rhs.snd)

def addLocalArrayGetLength
    (requirements : LocalArrayHelperRequirements)
    (length : Nat) : LocalArrayHelperRequirements :=
  (pushNatIfMissing requirements.fst length, requirements.snd)

def addNestedLocalArrayGetShape
    (requirements : LocalArrayHelperRequirements)
    (shape : Array Nat) : LocalArrayHelperRequirements :=
  (requirements.fst, pushNatArrayIfMissing requirements.snd shape)

def exprPlanLiteralWord? : ExprPlan → Option Nat
  | .literalWord value => some value
  | _ => none

def exprPlanPathIsStatic (path : Array ExprPlan) : Bool :=
  path.all fun index => exprPlanLiteralWord? index |>.isSome

def localArrayGetRequirementsFromPath
    (path : Array ExprPlan)
    (lengths : Array Nat) : LocalArrayHelperRequirements :=
  if path.size == lengths.size && !exprPlanPathIsStatic path then
    match lengths.toList with
    | [] => emptyLocalArrayHelperRequirements
    | [length] => addLocalArrayGetLength emptyLocalArrayHelperRequirements length
    | _ => addNestedLocalArrayGetShape emptyLocalArrayHelperRequirements lengths
  else
    emptyLocalArrayHelperRequirements

mutual
  partial def localArrayHelperRequirementsFromStorageSlotExprPlan :
      StorageSlotExprPlan → LocalArrayHelperRequirements
    | .scalarSlot _ | .fixedSlot _ => emptyLocalArrayHelperRequirements
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := emptyLocalArrayHelperRequirements) fun acc key =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        localArrayHelperRequirementsFromExprPlan index

  partial def localArrayHelperRequirementsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → LocalArrayHelperRequirements
    | .mapWrite _ key =>
        localArrayHelperRequirementsFromExprPlan key
    | .singleSlot slot =>
        localArrayHelperRequirementsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromStorageSlotExprPlan valueSlot)
          (localArrayHelperRequirementsFromStorageSlotExprPlan presenceSlot)

  partial def localArrayHelperRequirementsFromContextExprPlan :
      ContextExprPlan → LocalArrayHelperRequirements
    | .blockHash blockNumber =>
        localArrayHelperRequirementsFromExprPlan blockNumber
    | .userId | .userIdHash | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        emptyLocalArrayHelperRequirements

  partial def localArrayHelperRequirementsFromAbiValuePlan :
      AbiValuePlan → LocalArrayHelperRequirements
    | .expr value =>
        localArrayHelperRequirementsFromExprPlan value
    | .local .. | .storage .. =>
        emptyLocalArrayHelperRequirements
    | .arrayLit _ values =>
        values.foldl (init := emptyLocalArrayHelperRequirements) fun acc value =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field.snd)

  partial def localArrayHelperRequirementsFromCrosscallArgWordPlan :
      CrosscallArgWordPlan → LocalArrayHelperRequirements
    | .expr value =>
        localArrayHelperRequirementsFromExprPlan value
    | .local .. | .storage .. =>
        emptyLocalArrayHelperRequirements

  partial def localArrayHelperRequirementsFromExprPlan :
      ExprPlan → LocalArrayHelperRequirements
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        emptyLocalArrayHelperRequirements
    | .storageLoad _ =>
        emptyLocalArrayHelperRequirements
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := emptyLocalArrayHelperRequirements) fun acc arg =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan arg)
    | .checkedArith _ lhs rhs _
    | .hashTwoToOne lhs rhs =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan lhs)
          (localArrayHelperRequirementsFromExprPlan rhs)
    | .ecrecover a b c d =>
        mergeLocalArrayHelperRequirements
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromExprPlan a)
            (localArrayHelperRequirementsFromExprPlan b))
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromExprPlan c)
            (localArrayHelperRequirementsFromExprPlan d))
    | .eip712PermitDigest a b c d e f =>
        let ab := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan a)
          (localArrayHelperRequirementsFromExprPlan b)
        let cd := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan c)
          (localArrayHelperRequirementsFromExprPlan d)
        let ef := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan e)
          (localArrayHelperRequirementsFromExprPlan f)
        mergeLocalArrayHelperRequirements (mergeLocalArrayHelperRequirements ab cd) ef
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        localArrayHelperRequirementsFromExprPlan target
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan a)
          (localArrayHelperRequirementsFromExprPlan b)
        let cd := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan c)
          (localArrayHelperRequirementsFromExprPlan d)
        mergeLocalArrayHelperRequirements ab cd
    | .context field =>
        localArrayHelperRequirementsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan target)
          (localArrayHelperRequirementsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue =>
              mergeLocalArrayHelperRequirements nested (localArrayHelperRequirementsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromCrosscallArgWordPlan arg)
    | .create _ callValue salt? _ =>
        match salt? with
        | some salt =>
            mergeLocalArrayHelperRequirements
              (localArrayHelperRequirementsFromExprPlan callValue)
              (localArrayHelperRequirementsFromExprPlan salt)
        | none =>
            localArrayHelperRequirementsFromExprPlan callValue
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        localArrayHelperRequirementsFromExprPlan source
    | .arrayGet array index =>
        let nested := mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan array)
          (localArrayHelperRequirementsFromExprPlan index)
        match array with
        | .arrayLit _ values =>
            if values.isEmpty || (exprPlanLiteralWord? index).isSome then
              nested
            else
              addLocalArrayGetLength nested values.size
        | _ =>
            nested
    | .localArrayGet _ path lengths =>
        let nested := path.foldl (init := emptyLocalArrayHelperRequirements) fun acc index =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan index)
        mergeLocalArrayHelperRequirements nested (localArrayGetRequirementsFromPath path lengths)
    | .memoryArrayNew _ length =>
        localArrayHelperRequirementsFromExprPlan length
    | .memoryArrayGet array index =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan array)
          (localArrayHelperRequirementsFromExprPlan index)
    | .structLit _ fields =>
        fields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromExprPlan field.snd)
    | .effect effect =>
        localArrayHelperRequirementsFromEffectPlan effect

  partial def localArrayHelperRequirementsFromEffectPlan :
      EffectPlan → LocalArrayHelperRequirements
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        emptyLocalArrayHelperRequirements
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        localArrayHelperRequirementsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        localArrayHelperRequirementsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan key)
          (localArrayHelperRequirementsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeLocalArrayHelperRequirements
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromExprPlan array)
            (localArrayHelperRequirementsFromExprPlan index))
          (localArrayHelperRequirementsFromExprPlan value)
    | .storagePathRead _ _ | .storagePathReadTarget _ =>
        emptyLocalArrayHelperRequirements
    | .storagePathReadExprTarget slot =>
        localArrayHelperRequirementsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        localArrayHelperRequirementsFromExprPlan value
    | .storagePathWriteTarget _ value | .storagePathAssignOpTarget _ _ value =>
        localArrayHelperRequirementsFromExprPlan value
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromStoragePathWriteExprTargetPlan target)
          (localArrayHelperRequirementsFromExprPlan value)
    | .contextRead field =>
        localArrayHelperRequirementsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (init := emptyLocalArrayHelperRequirements) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field)
        dataFields.foldl (init := indexed) fun acc field =>
          mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := emptyLocalArrayHelperRequirements) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeLocalArrayHelperRequirements wordAcc (localArrayHelperRequirementsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexed := indexedFieldWords.foldl (init := emptyLocalArrayHelperRequirements) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeLocalArrayHelperRequirements wordAcc (localArrayHelperRequirementsFromExprPlan word)
        dataFieldWords.foldl (init := indexed) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeLocalArrayHelperRequirements wordAcc (localArrayHelperRequirementsFromExprPlan word)
    | .checkErc721Received a b c d =>
        mergeLocalArrayHelperRequirements
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromExprPlan a)
            (localArrayHelperRequirementsFromExprPlan b))
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromExprPlan c)
            (localArrayHelperRequirementsFromExprPlan d))
    | .checkErc1155Received a b c d e =>
        mergeLocalArrayHelperRequirements
          (mergeLocalArrayHelperRequirements
            (mergeLocalArrayHelperRequirements
              (localArrayHelperRequirementsFromExprPlan a)
              (localArrayHelperRequirementsFromExprPlan b))
            (mergeLocalArrayHelperRequirements
              (localArrayHelperRequirementsFromExprPlan c)
              (localArrayHelperRequirementsFromExprPlan d)))
          (localArrayHelperRequirementsFromExprPlan e)

  partial def localArrayHelperRequirementsFromStmtPlan :
      StmtPlan → LocalArrayHelperRequirements
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        localArrayHelperRequirementsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan target)
          (localArrayHelperRequirementsFromExprPlan value)
    | .effect effect =>
        localArrayHelperRequirementsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan lhs)
          (localArrayHelperRequirementsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        emptyLocalArrayHelperRequirements
    | .ifElse condition thenBody elseBody =>
        mergeLocalArrayHelperRequirements
          (localArrayHelperRequirementsFromExprPlan condition)
          (mergeLocalArrayHelperRequirements
            (localArrayHelperRequirementsFromStmtPlans thenBody)
            (localArrayHelperRequirementsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        localArrayHelperRequirementsFromStmtPlans body

  partial def localArrayHelperRequirementsFromStmtPlans
      (statements : Array StmtPlan) : LocalArrayHelperRequirements :=
    statements.foldl (init := emptyLocalArrayHelperRequirements) fun acc stmt =>
      mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromStmtPlan stmt)
end

def buildLocalArrayHelperRequirementsFromEntrypoints
    (entrypoints : Array EntrypointPlan) : LocalArrayHelperRequirements :=
  entrypoints.foldl (init := emptyLocalArrayHelperRequirements) fun acc entrypoint =>
    mergeLocalArrayHelperRequirements acc (localArrayHelperRequirementsFromStmtPlans entrypoint.body)

def pushHelperIfMissing (helpers : HelperSet) (helper : Helper) : HelperSet :=
  HelperSet.insert helpers helper

def mergeHelperSets (lhs rhs : HelperSet) : HelperSet :=
  rhs.foldl pushHelperIfMissing lhs

def removeMemoryArrayHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper =>
    !(helper == Helper.memoryArrayNew) && !(helper == Helper.memoryArrayGet)

def replaceMemoryArrayHelpers (helpers memoryHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeMemoryArrayHelpers helpers) memoryHelpers

def isMemoryArrayHelper : Helper → Bool
  | .memoryArrayNew | .memoryArrayGet => true
  | _ => false

def isHashHelper : Helper → Bool
  | .hashWord | .hashPair | .ecrecover | .eip712PermitDigest => true
  | _ => false

def isStorageArrayHelper : Helper → Bool
  | .arraySlot | .structArraySlot | .dynamicArraySlot => true
  | _ => false

def isMapHelper : Helper → Bool
  | .mapSlot | .mapPresenceSlot | .mapWrite | .mapSetReturn | .mapAssign _ => true
  | _ => false

def removeHashHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper =>
    !(helper == Helper.hashWord) && !(helper == Helper.hashPair) &&
      !(helper == Helper.ecrecover) && !(helper == Helper.eip712PermitDigest)

def replaceHashHelpers (helpers hashHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeHashHelpers helpers) hashHelpers

def removeStorageArrayHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper =>
    !(helper == Helper.arraySlot) &&
      !(helper == Helper.structArraySlot) &&
      !(helper == Helper.dynamicArraySlot)

def replaceStorageArrayHelpers (helpers storageArrayHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeStorageArrayHelpers helpers) storageArrayHelpers

def removeMapHelpers (helpers : HelperSet) : HelperSet :=
  helpers.filter fun helper => !isMapHelper helper

def insertMapHelperDependencies (helpers : HelperSet) : Helper → HelperSet
  | .mapWrite =>
      HelperSet.insert
        (HelperSet.insert
          (HelperSet.insert helpers .mapSlot)
          .mapPresenceSlot)
        .mapWrite
  | .mapSetReturn =>
      HelperSet.insert
        (HelperSet.insert
          (HelperSet.insert helpers .mapSlot)
          .mapPresenceSlot)
        .mapSetReturn
  | .mapAssign op =>
      HelperSet.insert
        (HelperSet.insert
          (HelperSet.insert helpers .mapSlot)
          .mapPresenceSlot)
        (.mapAssign op)
  | helper =>
      HelperSet.insert helpers helper

def closeMapHelpers (helpers : HelperSet) : HelperSet :=
  helpers.foldl insertMapHelperDependencies #[]

def replaceMapHelpers (helpers mapHelpers : HelperSet) : HelperSet :=
  mergeHelperSets (removeMapHelpers helpers) (closeMapHelpers mapHelpers)

mutual
  partial def plannedHelpersFromStorageSlotExprPlan : StorageSlotExprPlan → HelperSet
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys =>
        let nested := keys.foldl (init := #[]) fun acc key =>
          mergeHelperSets acc (plannedHelpersFromExprPlan key)
        HelperSet.insert nested .mapSlot
    | .mapPresenceSlot _ keys =>
        let nested := keys.foldl (init := #[]) fun acc key =>
          mergeHelperSets acc (plannedHelpersFromExprPlan key)
        let helpers := HelperSet.insert nested .mapPresenceSlot
        if keys.size > 1 then HelperSet.insert helpers .mapSlot else helpers
    | .arraySlot _ _ index =>
        HelperSet.insert (plannedHelpersFromExprPlan index) .arraySlot
    | .structArrayFieldSlot _ _ _ _ index =>
        HelperSet.insert (plannedHelpersFromExprPlan index) .structArraySlot
    | .dynamicArraySlot _ index =>
        HelperSet.insert (plannedHelpersFromExprPlan index) .dynamicArraySlot

  partial def plannedHelpersFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → HelperSet
    | .mapWrite _ key =>
        HelperSet.insert (plannedHelpersFromExprPlan key) .mapWrite
    | .singleSlot slot =>
        plannedHelpersFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeHelperSets
          (plannedHelpersFromStorageSlotExprPlan valueSlot)
          (plannedHelpersFromStorageSlotExprPlan presenceSlot)

  partial def plannedHelpersFromContextExprPlan : ContextExprPlan → HelperSet
    | .blockHash blockNumber =>
        plannedHelpersFromExprPlan blockNumber
    -- `userIdHash` lowers as `hashWord(caller)`; emit the keccak helper body.
    | .userIdHash =>
        #[.hashWord]
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        #[]

  partial def plannedHelpersFromAbiValuePlan : AbiValuePlan → HelperSet
    | .expr value =>
        plannedHelpersFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field.snd)

  partial def plannedHelpersFromCrosscallArgWordPlan : CrosscallArgWordPlan → HelperSet
    | .expr value =>
        plannedHelpersFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def plannedHelpersFromExprPlan : ExprPlan → HelperSet
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad slot =>
        slot.requiredHelpers
    | .builtin _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeHelperSets acc (plannedHelpersFromExprPlan arg)
    | .helperCall helper args =>
        let nested := args.foldl (init := #[]) fun acc arg =>
          mergeHelperSets acc (plannedHelpersFromExprPlan arg)
        HelperSet.insert nested helper
    | .checkedArith _ lhs rhs _
    | .arrayGet lhs rhs =>
        mergeHelperSets
          (plannedHelpersFromExprPlan lhs)
          (plannedHelpersFromExprPlan rhs)
    | .hashTwoToOne lhs rhs =>
        HelperSet.insert
          (mergeHelperSets
            (plannedHelpersFromExprPlan lhs)
            (plannedHelpersFromExprPlan rhs))
          .hashPair
    | .ecrecover digest v r s =>
        let d := plannedHelpersFromExprPlan digest
        let vr := mergeHelperSets (plannedHelpersFromExprPlan v) (plannedHelpersFromExprPlan r)
        let rs := mergeHelperSets vr (plannedHelpersFromExprPlan s)
        HelperSet.insert (mergeHelperSets d rs) .ecrecover
    | .eip712PermitDigest owner spender value nonce deadline domainSep =>
        let o := plannedHelpersFromExprPlan owner
        let s := mergeHelperSets o (plannedHelpersFromExprPlan spender)
        let v := mergeHelperSets s (plannedHelpersFromExprPlan value)
        let n := mergeHelperSets v (plannedHelpersFromExprPlan nonce)
        let d := mergeHelperSets n (plannedHelpersFromExprPlan deadline)
        HelperSet.insert
          (mergeHelperSets d (plannedHelpersFromExprPlan domainSep))
          .eip712PermitDigest
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        plannedHelpersFromExprPlan target
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeHelperSets
          (plannedHelpersFromExprPlan a)
          (plannedHelpersFromExprPlan b)
        let cd := mergeHelperSets
          (plannedHelpersFromExprPlan c)
          (plannedHelpersFromExprPlan d)
        mergeHelperSets ab cd
    | .context field =>
        plannedHelpersFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeHelperSets
          (plannedHelpersFromExprPlan target)
          (plannedHelpersFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue =>
              mergeHelperSets nested (plannedHelpersFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeHelperSets acc (plannedHelpersFromCrosscallArgWordPlan arg)
    | .create _ callValue salt? _ =>
        match salt? with
        | some salt =>
            mergeHelperSets
              (plannedHelpersFromExprPlan callValue)
              (plannedHelpersFromExprPlan salt)
        | none =>
            plannedHelpersFromExprPlan callValue
    | .cast source _
    | .structField source _
    | .memoryArrayLength source =>
        plannedHelpersFromExprPlan source
    | .hash source =>
        HelperSet.insert (plannedHelpersFromExprPlan source) .hashWord
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeHelperSets acc (plannedHelpersFromExprPlan index)
    | .memoryArrayNew _ length =>
        HelperSet.insert (plannedHelpersFromExprPlan length) .memoryArrayNew
    | .memoryArrayGet array index =>
        HelperSet.insert
          (mergeHelperSets
            (plannedHelpersFromExprPlan array)
            (plannedHelpersFromExprPlan index))
          .memoryArrayGet
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromExprPlan field.snd)
    | .effect effect =>
        plannedHelpersFromEffectPlan .mapSetReturn effect

  partial def plannedHelpersFromEffectPlan (mapWriteHelper : Helper) : EffectPlan → HelperSet
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        plannedHelpersFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key =>
        HelperSet.insert (plannedHelpersFromExprPlan key) .mapPresenceSlot
    | .storageMapGet _ key
    | .storageMapGetTarget _ key =>
        HelperSet.insert (plannedHelpersFromExprPlan key) .mapSlot
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        plannedHelpersFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value =>
        HelperSet.insert
          (mergeHelperSets
            (plannedHelpersFromExprPlan key)
            (plannedHelpersFromExprPlan value))
          mapWriteHelper
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeHelperSets
          (plannedHelpersFromExprPlan key)
          (plannedHelpersFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeHelperSets
          (mergeHelperSets
            (plannedHelpersFromExprPlan array)
            (plannedHelpersFromExprPlan index))
          (plannedHelpersFromExprPlan value)
    | .storagePathRead _ _ | .storagePathReadTarget _ =>
        #[]
    | .storagePathReadExprTarget slot =>
        plannedHelpersFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        plannedHelpersFromExprPlan value
    | .storagePathWriteTarget _ value | .storagePathAssignOpTarget _ _ value =>
        plannedHelpersFromExprPlan value
    | .storagePathWriteExprTarget target value =>
        mergeHelperSets
          (plannedHelpersFromStoragePathWriteExprTargetPlan target)
          (plannedHelpersFromExprPlan value)
    | .storagePathAssignOpExprTarget target op value =>
        let targetHelpers :=
          match target with
          | .mapWrite _ key =>
              HelperSet.insert (plannedHelpersFromExprPlan key) (.mapAssign op)
          | .singleSlot slot =>
              plannedHelpersFromStorageSlotExprPlan slot
          | .mapValuePresence valueSlot presenceSlot =>
              mergeHelperSets
                (plannedHelpersFromStorageSlotExprPlan valueSlot)
                (plannedHelpersFromStorageSlotExprPlan presenceSlot)
        mergeHelperSets targetHelpers (plannedHelpersFromExprPlan value)
    | .contextRead field =>
        plannedHelpersFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (init := #[]) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field)
        dataFields.foldl (init := indexed) fun acc field =>
          mergeHelperSets acc (plannedHelpersFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeHelperSets wordAcc (plannedHelpersFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexed := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeHelperSets wordAcc (plannedHelpersFromExprPlan word)
        dataFieldWords.foldl (init := indexed) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeHelperSets wordAcc (plannedHelpersFromExprPlan word)
    | .checkErc721Received a b c d =>
        mergeHelperSets
          (mergeHelperSets (plannedHelpersFromExprPlan a) (plannedHelpersFromExprPlan b))
          (mergeHelperSets (plannedHelpersFromExprPlan c) (plannedHelpersFromExprPlan d))
    | .checkErc1155Received a b c d e =>
        mergeHelperSets
          (mergeHelperSets
            (mergeHelperSets (plannedHelpersFromExprPlan a) (plannedHelpersFromExprPlan b))
            (mergeHelperSets (plannedHelpersFromExprPlan c) (plannedHelpersFromExprPlan d)))
          (plannedHelpersFromExprPlan e)

  partial def plannedHelpersFromStmtPlan : StmtPlan → HelperSet
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        plannedHelpersFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeHelperSets
          (plannedHelpersFromExprPlan target)
          (plannedHelpersFromExprPlan value)
    | .effect effect =>
        plannedHelpersFromEffectPlan .mapWrite effect
    | .assertEq lhs rhs _ _ =>
        mergeHelperSets
          (plannedHelpersFromExprPlan lhs)
          (plannedHelpersFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeHelperSets
          (plannedHelpersFromExprPlan condition)
          (mergeHelperSets
            (plannedHelpersFromStmtPlans thenBody)
            (plannedHelpersFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        plannedHelpersFromStmtPlans body

  partial def plannedHelpersFromStmtPlans (statements : Array StmtPlan) : HelperSet :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeHelperSets acc (plannedHelpersFromStmtPlan stmt)
end

def buildPlannedHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeHelperSets acc (plannedHelpersFromStmtPlans entrypoint.body)

def buildMemoryArrayHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isMemoryArrayHelper

def buildHashHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isHashHelper

def buildStorageArrayHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isStorageArrayHelper

def buildMapHelpersFromEntrypoints (entrypoints : Array EntrypointPlan) : HelperSet :=
  (buildPlannedHelpersFromEntrypoints entrypoints).filter isMapHelper
    |> closeMapHelpers

def contextFieldFromContextExprPlan : ContextExprPlan → ContextField
  | .userId => .userId
  | .userIdHash => .userIdHash
  | .contractId => .contractId
  | .checkpointId => .checkpointId
  | .timestamp => .timestamp
  | .chainId => .chainId
  | .gasPrice => .gasPrice
  | .gasLeft => .gasLeft
  | .baseFee => .baseFee
  | .prevRandao => .prevRandao
  | .origin => .origin
  | .coinbase => .coinbase
  | .blockHash _ => .blockHash (.literal (.u64 0))

def pushContextPlanIfMissing (ops : Array ContextPlan) (op : ContextPlan) : Array ContextPlan :=
  if ops.any (fun existing => existing.field.name == op.field.name) then ops else ops.push op

def mergeContextPlans (lhs rhs : Array ContextPlan) : Array ContextPlan :=
  rhs.foldl pushContextPlanIfMissing lhs

mutual
  partial def contextOpsFromStorageSlotExprPlan :
      StorageSlotExprPlan → Array ContextPlan
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := #[]) fun acc key =>
          mergeContextPlans acc (contextOpsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        contextOpsFromExprPlan index

  partial def contextOpsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → Array ContextPlan
    | .mapWrite _ key =>
        contextOpsFromExprPlan key
    | .singleSlot slot =>
        contextOpsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeContextPlans
          (contextOpsFromStorageSlotExprPlan valueSlot)
          (contextOpsFromStorageSlotExprPlan presenceSlot)

  partial def contextOpsFromContextExprPlan : ContextExprPlan → Array ContextPlan
    | .blockHash blockNumber =>
        mergeContextPlans
          #[{ field := contextFieldFromContextExprPlan (.blockHash blockNumber) }]
          (contextOpsFromExprPlan blockNumber)
    | field =>
        #[{ field := contextFieldFromContextExprPlan field }]

  partial def contextOpsFromAbiValuePlan : AbiValuePlan → Array ContextPlan
    | .expr value =>
        contextOpsFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field.snd)

  partial def contextOpsFromCrosscallArgWordPlan : CrosscallArgWordPlan → Array ContextPlan
    | .expr value =>
        contextOpsFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def contextOpsFromExprPlan : ExprPlan → Array ContextPlan
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad _ =>
        #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeContextPlans acc (contextOpsFromExprPlan arg)
    | .checkedArith _ lhs rhs _
    | .hashTwoToOne lhs rhs =>
        mergeContextPlans
          (contextOpsFromExprPlan lhs)
          (contextOpsFromExprPlan rhs)
    | .ecrecover a b c d =>
        mergeContextPlans
          (mergeContextPlans (contextOpsFromExprPlan a) (contextOpsFromExprPlan b))
          (mergeContextPlans (contextOpsFromExprPlan c) (contextOpsFromExprPlan d))
    | .eip712PermitDigest a b c d e f =>
        let ab := mergeContextPlans (contextOpsFromExprPlan a) (contextOpsFromExprPlan b)
        let cd := mergeContextPlans (contextOpsFromExprPlan c) (contextOpsFromExprPlan d)
        let ef := mergeContextPlans (contextOpsFromExprPlan e) (contextOpsFromExprPlan f)
        mergeContextPlans (mergeContextPlans ab cd) ef
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        contextOpsFromExprPlan target
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeContextPlans
          (contextOpsFromExprPlan a)
          (contextOpsFromExprPlan b)
        let cd := mergeContextPlans
          (contextOpsFromExprPlan c)
          (contextOpsFromExprPlan d)
        mergeContextPlans ab cd
    | .context field =>
        contextOpsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeContextPlans
          (contextOpsFromExprPlan target)
          (contextOpsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue =>
              mergeContextPlans nested (contextOpsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeContextPlans acc (contextOpsFromCrosscallArgWordPlan arg)
    | .create _ callValue salt? _ =>
        match salt? with
        | some salt =>
            mergeContextPlans
              (contextOpsFromExprPlan callValue)
              (contextOpsFromExprPlan salt)
        | none =>
            contextOpsFromExprPlan callValue
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        contextOpsFromExprPlan source
    | .arrayGet array index
    | .memoryArrayGet array index =>
        mergeContextPlans
          (contextOpsFromExprPlan array)
          (contextOpsFromExprPlan index)
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeContextPlans acc (contextOpsFromExprPlan index)
    | .memoryArrayNew _ length =>
        contextOpsFromExprPlan length
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromExprPlan field.snd)
    | .effect effect =>
        contextOpsFromEffectPlan effect

  partial def contextOpsFromEffectPlan : EffectPlan → Array ContextPlan
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        contextOpsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        contextOpsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeContextPlans
          (contextOpsFromExprPlan key)
          (contextOpsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeContextPlans
          (mergeContextPlans
            (contextOpsFromExprPlan array)
            (contextOpsFromExprPlan index))
          (contextOpsFromExprPlan value)
    | .storagePathRead _ _ | .storagePathReadTarget _ =>
        #[]
    | .storagePathReadExprTarget slot =>
        contextOpsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        contextOpsFromExprPlan value
    | .storagePathWriteTarget _ value | .storagePathAssignOpTarget _ _ value =>
        contextOpsFromExprPlan value
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeContextPlans
          (contextOpsFromStoragePathWriteExprTargetPlan target)
          (contextOpsFromExprPlan value)
    | .contextRead field =>
        contextOpsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (init := #[]) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field)
        dataFields.foldl (init := indexed) fun acc field =>
          mergeContextPlans acc (contextOpsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeContextPlans wordAcc (contextOpsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexed := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeContextPlans wordAcc (contextOpsFromExprPlan word)
        dataFieldWords.foldl (init := indexed) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeContextPlans wordAcc (contextOpsFromExprPlan word)
    | .checkErc721Received a b c d =>
        contextOpsFromExprPlan a ++ contextOpsFromExprPlan b ++
          contextOpsFromExprPlan c ++ contextOpsFromExprPlan d
    | .checkErc1155Received a b c d e =>
        contextOpsFromExprPlan a ++ contextOpsFromExprPlan b ++
          contextOpsFromExprPlan c ++ contextOpsFromExprPlan d ++
          contextOpsFromExprPlan e

  partial def contextOpsFromStmtPlan : StmtPlan → Array ContextPlan
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        contextOpsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeContextPlans
          (contextOpsFromExprPlan target)
          (contextOpsFromExprPlan value)
    | .effect effect =>
        contextOpsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeContextPlans
          (contextOpsFromExprPlan lhs)
          (contextOpsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeContextPlans
          (contextOpsFromExprPlan condition)
          (mergeContextPlans
            (contextOpsFromStmtPlans thenBody)
            (contextOpsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        contextOpsFromStmtPlans body

  partial def contextOpsFromStmtPlans (statements : Array StmtPlan) : Array ContextPlan :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeContextPlans acc (contextOpsFromStmtPlan stmt)
end

def buildContextOpsFromEntrypoints (entrypoints : Array EntrypointPlan) : Array ContextPlan :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeContextPlans acc (contextOpsFromStmtPlans entrypoint.body)

end ProofForge.Backend.Evm.Lower
