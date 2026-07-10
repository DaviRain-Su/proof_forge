import ProofForge.IR.Contract

namespace ProofForge.IR.Mutability

open ProofForge.IR

mutual
  partial def exprViolations : Expr → Array String
    | .literal _ | .local _ => #[]
    | .nativeValue => #["native value read"]
    | .arrayLit _ values =>
        values.foldl (fun acc value => acc ++ exprViolations value) #[]
    | .arrayGet array index | .memoryArrayGet array index =>
        exprViolations array ++ exprViolations index
    | .memoryArrayNew _ length | .memoryArrayLength length | .field length _
    | .cast length _ | .boolNot length | .hash length => exprViolations length
    | .structLit _ fields =>
        fields.foldl (fun acc field => acc ++ exprViolations field.snd) #[]
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        exprViolations lhs ++ exprViolations rhs
    | .hashValue a b c d | .ecrecover a b c d =>
        exprViolations a ++ exprViolations b ++ exprViolations c ++ exprViolations d
    | .eip712PermitDigest a b c d e f =>
        exprViolations a ++ exprViolations b ++ exprViolations c ++ exprViolations d ++
          exprViolations e ++ exprViolations f
    | .crosscallInvokeStaticTyped target method args _ =>
        exprViolations target ++ exprViolations method ++
          args.foldl (fun acc arg => acc ++ exprViolations arg) #[]
    | .crosscallAbiPacked .. | .crosscallInvoke .. | .crosscallInvokeTyped ..
    | .crosscallInvokeValueTyped .. | .crosscallInvokeDelegateTyped ..
    | .crosscallCreate .. | .crosscallCreate2 .. | .crosscallNamed .. =>
        #["non-static crosscall"]
    | .nearCrosscallInvokePool .. | .nearPromiseThen .. | .nearPromiseResultsCount
    | .nearPromiseResultStatus .. | .nearPromiseResultU64 .. =>
        #["promise operation"]
    | .effect effect => effectViolations effect

  partial def effectViolations : Effect → Array String
    | .storageScalarRead _ | .storageStructFieldRead _ _ => #[]
    | .storageMapContains _ key | .storageMapGet _ key => exprViolations key
    | .storageArrayRead _ index | .storageArrayStructFieldRead _ index _ =>
        exprViolations index
    | .storagePathRead _ path =>
        path.foldl (fun acc segment => acc ++ pathSegmentViolations segment) #[]
    | .contextRead field =>
        match field with
        | .blockHash blockNumber => exprViolations blockNumber
        | _ => #[]
    | .memoryArraySet array index value =>
        exprViolations array ++ exprViolations index ++ exprViolations value
    | .storageScalarWrite .. | .storageScalarAssignOp ..
    | .storageMapInsert .. | .storageMapSet .. | .storageArrayWrite ..
    | .storageArrayStructFieldWrite .. | .storageDynamicArrayPush ..
    | .storageDynamicArrayPop .. | .storageStructFieldWrite ..
    | .storagePathWrite .. | .storagePathAssignOp .. => #["storage write"]
    | .eventEmit .. | .eventEmitIndexed .. => #["event emission"]
    | .checkErc721Received .. | .checkErc1155Received ..
    | .checkErc1155BatchReceived .. => #["non-static crosscall"]

  partial def pathSegmentViolations : StoragePathSegment → Array String
    | .field _ => #[]
    | .index index | .mapKey index => exprViolations index

  partial def statementViolations : Statement → Array String
    | .letBind _ _ value | .letMutBind _ _ value | .return value => exprViolations value
    | .assign target value | .assignOp target _ value =>
        exprViolations target ++ exprViolations value
    | .effect effect => effectViolations effect
    | .assert condition _ _ => exprViolations condition
    | .assertEq lhs rhs _ _ => exprViolations lhs ++ exprViolations rhs
    | .revert _ | .revertWithError _ | .release _ => #[]
    | .ifElse condition thenBody elseBody =>
        exprViolations condition ++
          thenBody.foldl (fun acc statement => acc ++ statementViolations statement) #[] ++
          elseBody.foldl (fun acc statement => acc ++ statementViolations statement) #[]
    | .boundedFor _ _ _ body =>
        body.foldl (fun acc statement => acc ++ statementViolations statement) #[]
    | .whileLoop condition body =>
        exprViolations condition ++
          body.foldl (fun acc statement => acc ++ statementViolations statement) #[]
end

def validateEntrypoint (entrypoint : Entrypoint) : Except String Unit := do
  if entrypoint.mutability == .call then
    return ()
  let violations :=
    entrypoint.body.foldl (fun acc statement => acc ++ statementViolations statement) #[]
  match violations[0]? with
  | none => pure ()
  | some violation =>
      .error s!"view entrypoint `{entrypoint.name}` contains {violation}; mark it `call` or remove the mutating operation"

def validateModule (module : Module) : Except String Unit := do
  for entrypoint in module.entrypoints do
    validateEntrypoint entrypoint

end ProofForge.IR.Mutability
