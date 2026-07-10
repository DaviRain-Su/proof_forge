import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Validate
import ProofForge.IR.Contract

/-! # EVM helper discovery during lowering

This module discovers crosscall and contract-creation helper requirements from
portable IR and lowered entrypoint plans. `Lower.lean` uses the plan-level
entrypoints while the legacy `Evm.IR` path still uses the IR-level builders.
-/

namespace ProofForge.Backend.Evm.Lower

open ProofForge.IR
open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Validate

/-! ## Helper plan discovery -/

def plainValueTransferMethodId? : Expr → Bool
  | .literal (.u64 0) => true
  | _ => false

def plainValueTransferCall? (methodId : Expr) (args : Array Expr) : Bool :=
  plainValueTransferMethodId? methodId && args.isEmpty

def pushCrosscallHelperSpecIfMissing
    (acc : Array CrosscallHelperSpec)
    (value : CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCrosscallHelperSpecs
    (lhs rhs : Array CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  rhs.foldl pushCrosscallHelperSpecIfMissing lhs

def crosscallArgWordCountForExpr
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (arg : Expr) : Except LowerError Nat := do
  let type ← inferExprType module env arg
  let words ← crosscallArgWordTypes module context type
  .ok words.size

def crosscallArgWordCountForArgs
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (args : Array Expr) : Except LowerError Nat := do
  let mut count := 0
  for arg in args do
    count := count + (← crosscallArgWordCountForExpr module env context arg)
  .ok count

def crosscallHelperSpec
    (module : Module)
    (context : String)
    (arity : Nat)
    (returnType : ValueType)
    (mode : CrosscallMode)
    (plainTransfer : Bool := false) : Except LowerError CrosscallHelperSpec := do
  let wordTypes ← crosscallReturnWordTypes module context returnType
  .ok { arity, returnType, wordTypes, mode, plainTransfer }

mutual
  partial def crosscallHelperSpecsFromExpr
      (module : Module)
      (env : TypeEnv) : Expr → Except LowerError (Array CrosscallHelperSpec)
    | .literal _ | .local _ | .nativeValue => .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env value))
    | .arrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .memoryArrayNew _ length =>
        crosscallHelperSpecsFromExpr module env length
    | .memoryArrayLength array =>
        crosscallHelperSpecsFromExpr module env array
    | .memoryArrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .field base _ =>
        crosscallHelperSpecsFromExpr module env base
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let lhsSpecs ← crosscallHelperSpecsFromExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsFromExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs)
    | .ecrecover a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env a)
          (← crosscallHelperSpecsFromExpr module env b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env c)
          (← crosscallHelperSpecsFromExpr module env d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .eip712PermitDigest a b c d e f => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env a)
          (← crosscallHelperSpecsFromExpr module env b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env c)
          (← crosscallHelperSpecsFromExpr module env d)
        let ef := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env e)
          (← crosscallHelperSpecsFromExpr module env f)
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs ab cd) ef)
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        crosscallHelperSpecsFromExpr module env target
    | .cast value _ | .boolNot value | .hash value =>
        crosscallHelperSpecsFromExpr module env value
    | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env a)
          (← crosscallHelperSpecsFromExpr module env b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env c)
          (← crosscallHelperSpecsFromExpr module env d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .crosscallInvoke target methodId args => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let spec ← crosscallHelperSpec module "crosscall return" args.size .u64 .call
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "typed crosscall argument" args
        let spec ← crosscallHelperSpec module "typed crosscall return" argWordCount returnType .call
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env callValue)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "value crosscall argument" args
        let plainTransfer := plainValueTransferCall? methodId args && isCrosscallWordType returnType
        let spec ← crosscallHelperSpec
          module
          "value crosscall return"
          argWordCount
          returnType
          .callValue
          plainTransfer
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "static crosscall argument" args
        let spec ← crosscallHelperSpec module "static crosscall return" argWordCount returnType .staticcall
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "delegate crosscall argument" args
        let spec ← crosscallHelperSpec module "delegate crosscall return" argWordCount returnType .delegatecall
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallCreate callValue _ =>
        crosscallHelperSpecsFromExpr module env callValue
    | .crosscallCreate2 callValue salt _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env callValue)
          (← crosscallHelperSpecsFromExpr module env salt))
    | .crosscallNamed _ _ _ _
    | .nearPromiseThen _ _ _ _ | .nearCrosscallInvokePool _ _ _ _ | .nearPromiseResultsCount | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ => .ok #[]
    | .effect effect =>
        crosscallHelperSpecsFromEffect module env effect

  partial def crosscallHelperSpecsFromEffect
      (module : Module)
      (env : TypeEnv) : Effect → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => .ok #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        crosscallHelperSpecsFromExpr module env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        crosscallHelperSpecsFromExpr module env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value => do
        let keySpecs ← crosscallHelperSpecsFromExpr module env key
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .storageDynamicArrayPush _ value =>
        crosscallHelperSpecsFromExpr module env value
    | .storageDynamicArrayPop _ =>
        .ok #[]
    | .memoryArraySet array index value => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs arraySpecs indexSpecs) valueSpecs)
    | .storagePathRead _ path =>
        path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStoragePathSegment module env segment))
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value => do
        let pathSpecs ← path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStoragePathSegment module env segment))
        .ok (mergeCrosscallHelperSpecs pathSpecs (← crosscallHelperSpecsFromExpr module env value))
    | .eventEmit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .checkErc721Received a b c d => do
        let s1 ← crosscallHelperSpecsFromExpr module env a
        let s2 ← crosscallHelperSpecsFromExpr module env b
        let s3 ← crosscallHelperSpecsFromExpr module env c
        let s4 ← crosscallHelperSpecsFromExpr module env d
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs s1 s2) (mergeCrosscallHelperSpecs s3 s4))
    | .checkErc1155Received a b c d e => do
        let s1 ← crosscallHelperSpecsFromExpr module env a
        let s2 ← crosscallHelperSpecsFromExpr module env b
        let s3 ← crosscallHelperSpecsFromExpr module env c
        let s4 ← crosscallHelperSpecsFromExpr module env d
        let s5 ← crosscallHelperSpecsFromExpr module env e
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs s1 s2) (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs s3 s4) s5))

  partial def crosscallHelperSpecsFromStoragePathSegment
      (module : Module)
      (env : TypeEnv) : StoragePathSegment → Except LowerError (Array CrosscallHelperSpec)
    | .field _ => .ok #[]
    | .index index => crosscallHelperSpecsFromExpr module env index
    | .mapKey key => crosscallHelperSpecsFromExpr module env key

  partial def crosscallHelperSpecsFromStatement
      (module : Module)
      (env : TypeEnv) : Statement → Except LowerError (Array CrosscallHelperSpec × TypeEnv)
    | .letBind name type value => do
        let specs ← crosscallHelperSpecsFromExpr module env value
        let nextEnv ← addLocal env name type false
        .ok (specs, nextEnv)
    | .letMutBind name type value => do
        let specs ← crosscallHelperSpecsFromExpr module env value
        let nextEnv ← addLocal env name type true
        .ok (specs, nextEnv)
    | .assign target value | .assignOp target _ value => do
        let targetSpecs ← crosscallHelperSpecsFromExpr module env target
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs targetSpecs valueSpecs, env)
    | .effect effect => do
        .ok (← crosscallHelperSpecsFromEffect module env effect, env)
    | .assert condition _ _ => do
        .ok (← crosscallHelperSpecsFromExpr module env condition, env)
    | .assertEq lhs rhs _ _ => do
        let lhsSpecs ← crosscallHelperSpecsFromExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsFromExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs, env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let conditionSpecs ← crosscallHelperSpecsFromExpr module env condition
        let (thenSpecs, _) ← crosscallHelperSpecsFromStatements module env thenBody
        let (elseSpecs, _) ← crosscallHelperSpecsFromStatements module env elseBody
        .ok (mergeCrosscallHelperSpecs conditionSpecs (mergeCrosscallHelperSpecs thenSpecs elseSpecs), env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodySpecs, _) ← crosscallHelperSpecsFromStatements module loopEnv body
        .ok (bodySpecs, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value => do
        .ok (← crosscallHelperSpecsFromExpr module env value, env)

  partial def crosscallHelperSpecsFromStatements
      (module : Module)
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array CrosscallHelperSpec × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (specs, currentEnv) := acc
      let (stmtSpecs, nextEnv) ← crosscallHelperSpecsFromStatement module currentEnv stmt
      .ok (mergeCrosscallHelperSpecs specs stmtSpecs, nextEnv)
end

def buildCrosscallHelperPlans (module : Module) : Except LowerError (Array CrosscallHelperSpec) := do
  let mut specs : Array CrosscallHelperSpec := #[]
  for entrypoint in module.entrypoints do
    let (entrypointSpecs, _) ←
      crosscallHelperSpecsFromStatements module (entrypointTypeEnv entrypoint) entrypoint.body
    specs := mergeCrosscallHelperSpecs specs entrypointSpecs
  .ok specs

def plainValueTransferMethodIdPlan? : ExprPlan → Bool
  | .literalWord 0 => true
  | _ => false

def plainValueTransferCallPlan? (methodId : ExprPlan) (args : Array CrosscallArgWordPlan) : Bool :=
  plainValueTransferMethodIdPlan? methodId && args.isEmpty

mutual
  partial def crosscallHelperSpecsFromContextExprPlan
      (module : Module) : ContextExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .blockHash blockNumber =>
        crosscallHelperSpecsFromExprPlan module blockNumber
    | .userId | .userIdHash | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        .ok #[]

  partial def crosscallHelperSpecsFromStorageSlotExprPlan
      (module : Module) : StorageSlotExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .scalarSlot _ | .fixedSlot _ => .ok #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldlM (init := #[]) fun acc key => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module key))
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        crosscallHelperSpecsFromExprPlan module index

  partial def crosscallHelperSpecsFromStoragePathWriteExprTargetPlan
      (module : Module) : StoragePathWriteExprTargetPlan → Except LowerError (Array CrosscallHelperSpec)
    | .mapWrite _ key =>
        crosscallHelperSpecsFromExprPlan module key
    | .singleSlot slot =>
        crosscallHelperSpecsFromStorageSlotExprPlan module slot
    | .mapValuePresence valueSlot presenceSlot => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromStorageSlotExprPlan module valueSlot)
          (← crosscallHelperSpecsFromStorageSlotExprPlan module presenceSlot))

  partial def crosscallHelperSpecsFromAbiValuePlan
      (module : Module) : AbiValuePlan → Except LowerError (Array CrosscallHelperSpec)
    | .expr value =>
        crosscallHelperSpecsFromExprPlan module value
    | .local .. | .storage .. =>
        .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module value))
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field.snd))

  partial def crosscallHelperSpecsFromCrosscallArgWordPlan
      (module : Module) : CrosscallArgWordPlan → Except LowerError (Array CrosscallHelperSpec)
    | .expr value =>
        crosscallHelperSpecsFromExprPlan module value
    | .local .. | .storage .. =>
        .ok #[]

  partial def crosscallHelperSpecsFromExprPlan
      (module : Module) : ExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        .ok #[]
    | .storageLoad slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldlM (init := #[]) fun acc valuePlan => do
              match valuePlan with
              | .irExpr _ => .ok acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            .ok #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldlM (init := #[]) fun acc arg => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module arg))
    | .checkedArith _ lhs rhs _
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module lhs)
          (← crosscallHelperSpecsFromExprPlan module rhs))
    | .ecrecover a b c d => do
        .ok (mergeCrosscallHelperSpecs
          (mergeCrosscallHelperSpecs
            (← crosscallHelperSpecsFromExprPlan module a)
            (← crosscallHelperSpecsFromExprPlan module b))
          (mergeCrosscallHelperSpecs
            (← crosscallHelperSpecsFromExprPlan module c)
            (← crosscallHelperSpecsFromExprPlan module d)))
    | .eip712PermitDigest a b c d e f => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module a)
          (← crosscallHelperSpecsFromExprPlan module b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module c)
          (← crosscallHelperSpecsFromExprPlan module d)
        let ef := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module e)
          (← crosscallHelperSpecsFromExprPlan module f)
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs ab cd) ef)
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        crosscallHelperSpecsFromExprPlan module target
    | .hashPack a b c d | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module a)
          (← crosscallHelperSpecsFromExprPlan module b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module c)
          (← crosscallHelperSpecsFromExprPlan module d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .context field =>
        crosscallHelperSpecsFromContextExprPlan module field
    | .crosscall mode target methodId callValue? args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module target)
          (← crosscallHelperSpecsFromExprPlan module methodId)
        match callValue? with
        | some callValue =>
            nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExprPlan module callValue)
        | none => pure ()
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromCrosscallArgWordPlan module arg)
        let plainTransfer :=
          match mode with
          | .callValue => plainValueTransferCallPlan? methodId args && isCrosscallWordType returnType
          | .call | .staticcall | .delegatecall => false
        let spec ← crosscallHelperSpec
          module
          "planned crosscall return"
          args.size
          returnType
          mode
          plainTransfer
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .create _ callValue salt? _ => do
        let callValueSpecs ← crosscallHelperSpecsFromExprPlan module callValue
        match salt? with
        | some salt =>
            .ok (mergeCrosscallHelperSpecs callValueSpecs (← crosscallHelperSpecsFromExprPlan module salt))
        | none =>
            .ok callValueSpecs
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        crosscallHelperSpecsFromExprPlan module source
    | .localArrayGet _ path _ =>
        path.foldlM (init := #[]) fun acc index => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module index))
    | .memoryArrayNew _ length =>
        crosscallHelperSpecsFromExprPlan module length
    | .memoryArrayGet array index => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module array)
          (← crosscallHelperSpecsFromExprPlan module index))
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module field.snd))
    | .effect effect =>
        crosscallHelperSpecsFromEffectPlan module effect

  partial def crosscallHelperSpecsFromEffectPlan
      (module : Module) : EffectPlan → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        .ok #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        crosscallHelperSpecsFromExprPlan module value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        crosscallHelperSpecsFromExprPlan module key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value => do
        let keySpecs ← crosscallHelperSpecsFromExprPlan module key
        let valueSpecs ← crosscallHelperSpecsFromExprPlan module value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .memoryArraySet array index value => do
        let arraySpecs ← crosscallHelperSpecsFromExprPlan module array
        let indexSpecs ← crosscallHelperSpecsFromExprPlan module index
        let valueSpecs ← crosscallHelperSpecsFromExprPlan module value
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs arraySpecs indexSpecs) valueSpecs)
    | .storagePathRead _ _ =>
        .ok #[]
    | .storagePathReadTarget slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldlM (init := #[]) fun acc valuePlan => do
              match valuePlan with
              | .irExpr _ => .ok acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            .ok #[]
    | .storagePathReadExprTarget slot =>
        crosscallHelperSpecsFromStorageSlotExprPlan module slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        crosscallHelperSpecsFromExprPlan module value
    | .storagePathWriteTarget target value
    | .storagePathAssignOpTarget target _ value => do
        let targetSpecs ←
          match target with
          | .mapWrite _ (.irExpr _) => .ok #[]
          | .singleSlot _ => .ok #[]
          | .mapValuePresence _ _ => .ok #[]
        .ok (mergeCrosscallHelperSpecs targetSpecs (← crosscallHelperSpecsFromExprPlan module value))
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromStoragePathWriteExprTargetPlan module target)
          (← crosscallHelperSpecsFromExprPlan module value))
    | .contextRead field =>
        crosscallHelperSpecsFromContextExprPlan module field
    | .eventEmit _ dataFields =>
        dataFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldlM (init := #[]) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords => do
        let indexedSpecs ← indexedFieldWords.foldlM (init := #[]) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
        dataFieldWords.foldlM (init := indexedSpecs) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
    | .checkErc721Received a b c d => do
        let s1 ← crosscallHelperSpecsFromExprPlan module a
        let s2 ← crosscallHelperSpecsFromExprPlan module b
        let s3 ← crosscallHelperSpecsFromExprPlan module c
        let s4 ← crosscallHelperSpecsFromExprPlan module d
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs s1 s2) (mergeCrosscallHelperSpecs s3 s4))
    | .checkErc1155Received a b c d e => do
        let s1 ← crosscallHelperSpecsFromExprPlan module a
        let s2 ← crosscallHelperSpecsFromExprPlan module b
        let s3 ← crosscallHelperSpecsFromExprPlan module c
        let s4 ← crosscallHelperSpecsFromExprPlan module d
        let s5 ← crosscallHelperSpecsFromExprPlan module e
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs s1 s2) (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs s3 s4) s5))

  partial def crosscallHelperSpecsFromStmtPlan
      (module : Module) : StmtPlan → Except LowerError (Array CrosscallHelperSpec)
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        crosscallHelperSpecsFromExprPlan module value
    | .assign target value
    | .assignOp target _ value => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module target)
          (← crosscallHelperSpecsFromExprPlan module value))
    | .effect effect =>
        crosscallHelperSpecsFromEffectPlan module effect
    | .assertEq lhs rhs _ _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module lhs)
          (← crosscallHelperSpecsFromExprPlan module rhs))
    | .release _ | .revert _ | .revertWithError _ =>
        .ok #[]
    | .ifElse condition thenBody elseBody => do
        let conditionSpecs ← crosscallHelperSpecsFromExprPlan module condition
        let thenSpecs ← crosscallHelperSpecsFromStmtPlans module thenBody
        let elseSpecs ← crosscallHelperSpecsFromStmtPlans module elseBody
        .ok (mergeCrosscallHelperSpecs conditionSpecs (mergeCrosscallHelperSpecs thenSpecs elseSpecs))
    | .boundedFor _ _ _ body =>
        crosscallHelperSpecsFromStmtPlans module body

  partial def crosscallHelperSpecsFromStmtPlans
      (module : Module)
      (statements : Array StmtPlan) : Except LowerError (Array CrosscallHelperSpec) :=
    statements.foldlM (init := #[]) fun acc stmt => do
      .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStmtPlan module stmt))
end

def buildCrosscallHelperPlansFromEntrypoints
    (module : Module)
    (entrypoints : Array EntrypointPlan) : Except LowerError (Array CrosscallHelperSpec) :=
  entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStmtPlans module entrypoint.body))

def pushCreateHelperSpecIfMissing
    (acc : Array CreateHelperSpec)
    (value : CreateHelperSpec) : Array CreateHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCreateHelperSpecs
    (lhs rhs : Array CreateHelperSpec) : Array CreateHelperSpec :=
  rhs.foldl pushCreateHelperSpecIfMissing lhs

mutual
  partial def createHelperSpecsFromExpr : Expr → Array CreateHelperSpec
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr value)
    | .arrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index)
    | .memoryArrayNew _ length =>
        createHelperSpecsFromExpr length
    | .memoryArrayLength array =>
        createHelperSpecsFromExpr array
    | .memoryArrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .field base _ =>
        createHelperSpecsFromExpr base
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr lhs) (createHelperSpecsFromExpr rhs)
    | .ecrecover a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (createHelperSpecsFromExpr d))
    | .eip712PermitDigest a b c d e f =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs
            (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
            (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (createHelperSpecsFromExpr d)))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr e) (createHelperSpecsFromExpr f))
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        createHelperSpecsFromExpr target
    | .cast value _ | .boolNot value | .hash value =>
        createHelperSpecsFromExpr value
    | .hashValue a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (createHelperSpecsFromExpr d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr methodId)
        let nested := mergeCreateHelperSpecs nested (createHelperSpecsFromExpr callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr arg)
    | .crosscallCreate callValue initCodeHex =>
        pushCreateHelperSpecIfMissing (createHelperSpecsFromExpr callValue) { mode := .create, initCodeHex }
    | .crosscallCreate2 callValue salt initCodeHex =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr callValue) (createHelperSpecsFromExpr salt)
        pushCreateHelperSpecIfMissing nested { mode := .create2, initCodeHex }
    | .crosscallNamed _ _ _ _
    | .nearPromiseThen _ _ _ _ | .nearCrosscallInvokePool _ _ _ _ | .nearPromiseResultsCount | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ => #[]
    | .effect effect =>
        createHelperSpecsFromEffect effect

  partial def createHelperSpecsFromEffect : Effect → Array CreateHelperSpec
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        createHelperSpecsFromExpr value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        createHelperSpecsFromExpr key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr key) (createHelperSpecsFromExpr value)
    | .storageDynamicArrayPush _ value =>
        createHelperSpecsFromExpr value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index))
          (createHelperSpecsFromExpr value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromStoragePathSegment segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathSpecs := path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromStoragePathSegment segment)
        mergeCreateHelperSpecs pathSpecs (createHelperSpecsFromExpr value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .checkErc721Received a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (createHelperSpecsFromExpr d))
    | .checkErc1155Received a b c d e =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (mergeCreateHelperSpecs (createHelperSpecsFromExpr d) (createHelperSpecsFromExpr e)))

  partial def createHelperSpecsFromStoragePathSegment : StoragePathSegment → Array CreateHelperSpec
    | .field _ => #[]
    | .index index => createHelperSpecsFromExpr index
    | .mapKey key => createHelperSpecsFromExpr key

  partial def createHelperSpecsFromStatement : Statement → Array CreateHelperSpec
    | .letBind _ _ value | .letMutBind _ _ value =>
        createHelperSpecsFromExpr value
    | .assign target value | .assignOp target _ value =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr value)
    | .effect effect =>
        createHelperSpecsFromEffect effect
    | .assert condition _ _ =>
        createHelperSpecsFromExpr condition
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr lhs) (createHelperSpecsFromExpr rhs)
    | .release _ =>
        #[]
    | .revert _ => #[]
    | .revertWithError _ => #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExpr condition)
          (mergeCreateHelperSpecs (createHelperSpecsFromStatements thenBody) (createHelperSpecsFromStatements elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsFromStatements body
    | .whileLoop _ _ => #[]
    | .return value =>
        createHelperSpecsFromExpr value

  partial def createHelperSpecsFromStatements (statements : Array Statement) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsFromStatement stmt)
end

def buildCreateHelperPlans (module : Module) : Array CreateHelperSpec :=
  module.entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsFromStatements entrypoint.body)

/-! ## Compile-time ABI-packed CALL helpers (`crosscallAbiPacked`) -/

def pushAbiPackedHelperSpecIfMissing
    (acc : Array AbiPackedHelperSpec)
    (value : AbiPackedHelperSpec) : Array AbiPackedHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeAbiPackedHelperSpecs
    (lhs rhs : Array AbiPackedHelperSpec) : Array AbiPackedHelperSpec :=
  rhs.foldl pushAbiPackedHelperSpecIfMissing lhs

mutual
  partial def abiPackedHelperSpecsFromExpr : Expr → Array AbiPackedHelperSpec
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr value)
    | .arrayGet array index | .memoryArrayGet array index =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr array) (abiPackedHelperSpecsFromExpr index)
    | .memoryArrayNew _ length => abiPackedHelperSpecsFromExpr length
    | .memoryArrayLength array | .field array _ | .cast array _ | .boolNot array | .hash array =>
        abiPackedHelperSpecsFromExpr array
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr field.snd)
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr lhs) (abiPackedHelperSpecsFromExpr rhs)
    | .ecrecover a b c d | .hashValue a b c d =>
        mergeAbiPackedHelperSpecs
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr a) (abiPackedHelperSpecsFromExpr b))
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr c) (abiPackedHelperSpecsFromExpr d))
    | .eip712PermitDigest a b c d e f =>
        mergeAbiPackedHelperSpecs
          (mergeAbiPackedHelperSpecs
            (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr a) (abiPackedHelperSpecsFromExpr b))
            (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr c) (abiPackedHelperSpecsFromExpr d)))
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr e) (abiPackedHelperSpecsFromExpr f))
    | .crosscallAbiPacked target selector stores argsSize outSize dynLenOffset? dynLen?
        dynTargetOffsets dynTargets =>
        let nested :=
          match dynLen? with
          | none => abiPackedHelperSpecsFromExpr target
          | some len =>
              mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr target)
                (abiPackedHelperSpecsFromExpr len)
        let nested := dynTargets.foldl (init := nested) fun acc t =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr t)
        pushAbiPackedHelperSpecIfMissing nested
          { selector, stores, argsSize, outSize, dynLenOffset?, dynTargetOffsets }
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr target)
          (abiPackedHelperSpecsFromExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr target)
          (abiPackedHelperSpecsFromExpr methodId)
        let nested := mergeAbiPackedHelperSpecs nested (abiPackedHelperSpecsFromExpr callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr arg)
    | .crosscallCreate callValue _ | .nearPromiseResultStatus callValue | .nearPromiseResultU64 callValue =>
        abiPackedHelperSpecsFromExpr callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr callValue) (abiPackedHelperSpecsFromExpr salt)
    | .nearPromiseThen a b args d =>
        let nested := mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr a) (abiPackedHelperSpecsFromExpr b)
        let nested := args.foldl (init := nested) fun acc arg =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr arg)
        mergeAbiPackedHelperSpecs nested (abiPackedHelperSpecsFromExpr d)
    | .nearCrosscallInvokePool a b args d =>
        let nested := mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr a) (abiPackedHelperSpecsFromExpr b)
        let nested := args.foldl (init := nested) fun acc arg =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr arg)
        mergeAbiPackedHelperSpecs nested (abiPackedHelperSpecsFromExpr d)
    | .crosscallNamed _ _ _ _ => #[]
    | .nearPromiseResultsCount => #[]
    | .effect effect => abiPackedHelperSpecsFromEffect effect

  partial def abiPackedHelperSpecsFromEffect : Effect → Array AbiPackedHelperSpec
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _
    | .storageDynamicArrayPop _ => #[]
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value => abiPackedHelperSpecsFromExpr value
    | .storageMapContains _ key | .storageMapGet _ key => abiPackedHelperSpecsFromExpr key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr key) (abiPackedHelperSpecsFromExpr value)
    | .storageArrayRead _ index | .storageArrayStructFieldRead _ index _ =>
        abiPackedHelperSpecsFromExpr index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr index) (abiPackedHelperSpecsFromExpr value)
    | .storageDynamicArrayPush _ value | .memoryArraySet _ _ value =>
        abiPackedHelperSpecsFromExpr value
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc seg =>
          match seg with
          | .field _ => acc
          | .index index | .mapKey index =>
              mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr index)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let fromPath := path.foldl (init := #[]) fun acc seg =>
          match seg with
          | .field _ => acc
          | .index index | .mapKey index =>
              mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr index)
        mergeAbiPackedHelperSpecs fromPath (abiPackedHelperSpecsFromExpr value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc f =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr f.snd)
    | .eventEmitIndexed _ indexed data =>
        let a := indexed.foldl (init := #[]) fun acc f =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr f.snd)
        data.foldl (init := a) fun acc f =>
          mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromExpr f.snd)
    | .checkErc721Received a b c d =>
        mergeAbiPackedHelperSpecs
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr a) (abiPackedHelperSpecsFromExpr b))
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr c) (abiPackedHelperSpecsFromExpr d))
    | .checkErc1155Received a b c d e =>
        mergeAbiPackedHelperSpecs
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr a) (abiPackedHelperSpecsFromExpr b))
          (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr c) (mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr d) (abiPackedHelperSpecsFromExpr e)))

  partial def abiPackedHelperSpecsFromStatement : Statement → Array AbiPackedHelperSpec
    | .letBind _ _ value | .letMutBind _ _ value | .return value =>
        abiPackedHelperSpecsFromExpr value
    | .assign target value | .assignOp target _ value =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr target) (abiPackedHelperSpecsFromExpr value)
    | .effect effect => abiPackedHelperSpecsFromEffect effect
    | .assert condition _ _ => abiPackedHelperSpecsFromExpr condition
    | .assertEq lhs rhs _ _ =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr lhs) (abiPackedHelperSpecsFromExpr rhs)
    | .release _ | .revert _ | .revertWithError _ => #[]
    | .ifElse condition thenBody elseBody =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr condition)
          (mergeAbiPackedHelperSpecs
            (abiPackedHelperSpecsFromStatements thenBody)
            (abiPackedHelperSpecsFromStatements elseBody))
    | .boundedFor _ _ _ body => abiPackedHelperSpecsFromStatements body
    | .whileLoop cond body =>
        mergeAbiPackedHelperSpecs (abiPackedHelperSpecsFromExpr cond)
          (abiPackedHelperSpecsFromStatements body)

  partial def abiPackedHelperSpecsFromStatements (statements : Array Statement) : Array AbiPackedHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromStatement stmt)
end

def buildAbiPackedHelperPlans (module : Module) : Array AbiPackedHelperSpec :=
  module.entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeAbiPackedHelperSpecs acc (abiPackedHelperSpecsFromStatements entrypoint.body)

mutual
  partial def createHelperSpecsFromContextExprPlan : ContextExprPlan → Array CreateHelperSpec
    | .blockHash blockNumber =>
        createHelperSpecsFromExprPlan blockNumber
    | .userId | .userIdHash | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        #[]

  partial def createHelperSpecsFromStorageSlotExprPlan : StorageSlotExprPlan → Array CreateHelperSpec
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := #[]) fun acc key =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        createHelperSpecsFromExprPlan index

  partial def createHelperSpecsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → Array CreateHelperSpec
    | .mapWrite _ key =>
        createHelperSpecsFromExprPlan key
    | .singleSlot slot =>
        createHelperSpecsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromStorageSlotExprPlan valueSlot)
          (createHelperSpecsFromStorageSlotExprPlan presenceSlot)

  partial def createHelperSpecsFromAbiValuePlan : AbiValuePlan → Array CreateHelperSpec
    | .expr value =>
        createHelperSpecsFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field.snd)

  partial def createHelperSpecsFromCrosscallArgWordPlan :
      CrosscallArgWordPlan → Array CreateHelperSpec
    | .expr value =>
        createHelperSpecsFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def createHelperSpecsFromExprPlan : ExprPlan → Array CreateHelperSpec
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldl (init := #[]) fun acc valuePlan =>
              match valuePlan with
              | .irExpr _ => acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan arg)
    | .checkedArith _ lhs rhs _
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan lhs)
          (createHelperSpecsFromExprPlan rhs)
    | .ecrecover a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan a) (createHelperSpecsFromExprPlan b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan c) (createHelperSpecsFromExprPlan d))
    | .eip712PermitDigest a b c d e f =>
        let ab := mergeCreateHelperSpecs (createHelperSpecsFromExprPlan a) (createHelperSpecsFromExprPlan b)
        let cd := mergeCreateHelperSpecs (createHelperSpecsFromExprPlan c) (createHelperSpecsFromExprPlan d)
        let ef := mergeCreateHelperSpecs (createHelperSpecsFromExprPlan e) (createHelperSpecsFromExprPlan f)
        mergeCreateHelperSpecs (mergeCreateHelperSpecs ab cd) ef
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        createHelperSpecsFromExprPlan target
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan a)
          (createHelperSpecsFromExprPlan b)
        let cd := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan c)
          (createHelperSpecsFromExprPlan d)
        mergeCreateHelperSpecs ab cd
    | .context field =>
        createHelperSpecsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan target)
          (createHelperSpecsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue => mergeCreateHelperSpecs nested (createHelperSpecsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromCrosscallArgWordPlan arg)
    | .create mode callValue salt? initCodeHex =>
        let nested :=
          match salt? with
          | some salt =>
              mergeCreateHelperSpecs
                (createHelperSpecsFromExprPlan callValue)
                (createHelperSpecsFromExprPlan salt)
          | none =>
              createHelperSpecsFromExprPlan callValue
        pushCreateHelperSpecIfMissing nested { mode, initCodeHex }
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        createHelperSpecsFromExprPlan source
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan index)
    | .memoryArrayNew _ length =>
        createHelperSpecsFromExprPlan length
    | .memoryArrayGet array index =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan array)
          (createHelperSpecsFromExprPlan index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan field.snd)
    | .effect effect =>
        createHelperSpecsFromEffectPlan effect

  partial def createHelperSpecsFromEffectPlan : EffectPlan → Array CreateHelperSpec
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
        createHelperSpecsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        createHelperSpecsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan key)
          (createHelperSpecsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs
            (createHelperSpecsFromExprPlan array)
            (createHelperSpecsFromExprPlan index))
          (createHelperSpecsFromExprPlan value)
    | .storagePathRead _ _ =>
        #[]
    | .storagePathReadTarget slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldl (init := #[]) fun acc valuePlan =>
              match valuePlan with
              | .irExpr _ => acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            #[]
    | .storagePathReadExprTarget slot =>
        createHelperSpecsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        createHelperSpecsFromExprPlan value
    | .storagePathWriteTarget target value
    | .storagePathAssignOpTarget target _ value =>
        let targetSpecs :=
          match target with
          | .mapWrite _ (.irExpr _) => #[]
          | .singleSlot _ => #[]
          | .mapValuePresence _ _ => #[]
        mergeCreateHelperSpecs targetSpecs (createHelperSpecsFromExprPlan value)
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromStoragePathWriteExprTargetPlan target)
          (createHelperSpecsFromExprPlan value)
    | .contextRead field =>
        createHelperSpecsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexedSpecs := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
        dataFieldWords.foldl (init := indexedSpecs) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
    | .checkErc721Received a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan a) (createHelperSpecsFromExprPlan b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan c) (createHelperSpecsFromExprPlan d))
    | .checkErc1155Received a b c d e =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan a) (createHelperSpecsFromExprPlan b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan c) (mergeCreateHelperSpecs (createHelperSpecsFromExprPlan d) (createHelperSpecsFromExprPlan e)))

  partial def createHelperSpecsFromStmtPlan : StmtPlan → Array CreateHelperSpec
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        createHelperSpecsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan target)
          (createHelperSpecsFromExprPlan value)
    | .effect effect =>
        createHelperSpecsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan lhs)
          (createHelperSpecsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan condition)
          (mergeCreateHelperSpecs (createHelperSpecsFromStmtPlans thenBody) (createHelperSpecsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsFromStmtPlans body

  partial def createHelperSpecsFromStmtPlans (statements : Array StmtPlan) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsFromStmtPlan stmt)
end

def buildCreateHelperPlansFromEntrypoints
    (entrypoints : Array EntrypointPlan) : Array CreateHelperSpec :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsFromStmtPlans entrypoint.body)

end ProofForge.Backend.Evm.Lower
