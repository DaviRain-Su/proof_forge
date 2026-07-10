/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# IR portability classification (D-050)

Classifies portable-IR constructors and module metadata into portability
layers so authors and backends share one vocabulary:

* `PortableCore` — safe on every Experimental primary target (EVM, Solana, NEAR)
  for the supported fragment.
* `FamilyShared` — shared by ≥2 target families; still capability-gated.
* `TargetFamilyOnly` — belongs to one family; must not silently lower on others.
* `TargetMetadata` — module/entrypoint fields that are target-resolved baggage,
  not portable business logic.

D-027 already says chain-only effects stay out of the portable IR. This module
makes the inventory machine-checkable so EVM-shaped constructors
(`create`/`create2`, `fallback`/`receive`) and NEAR Promise constructors are
flagged explicitly instead of looking like portable core.
-/
import ProofForge.IR.Contract
import ProofForge.Target.Registry

namespace ProofForge.IR.Portability

open ProofForge.IR
open ProofForge.Target

inductive PortabilityClass where
  | portableCore
  | familyShared
  | targetFamilyOnly (family : TargetFamily)
  | targetMetadata (family? : Option TargetFamily)
  deriving BEq, Repr

def PortabilityClass.describe : PortabilityClass → String
  | .portableCore => "portable-core"
  | .familyShared => "family-shared"
  | .targetFamilyOnly family => s!"target-family-only:{family.id}"
  | .targetMetadata none => "target-metadata"
  | .targetMetadata (some family) => s!"target-metadata:{family.id}"

structure PortabilityFinding where
  path : String
  detail : String
  class_ : PortabilityClass
  deriving Repr

def finding (path detail : String) (class_ : PortabilityClass) : PortabilityFinding :=
  { path := path, detail := detail, class_ := class_ }

def classifyEntrypointKind : EntrypointKind → PortabilityClass
  | .function => .portableCore
  | .fallback | .receive => .targetFamilyOnly .evm

def entrypointKindName : EntrypointKind → String
  | .function => "function"
  | .fallback => "fallback"
  | .receive => "receive"

mutual
  partial def classifyExpr (path : String) : Expr → Array PortabilityFinding
    | .crosscallCreate callValue _ =>
        #[finding path "crosscallCreate (initcode deploy)" (.targetFamilyOnly .evm)] ++
          classifyExpr s!"{path}.value" callValue
    | .crosscallCreate2 callValue salt _ =>
        #[finding path "crosscallCreate2 (CREATE2 deploy)" (.targetFamilyOnly .evm)] ++
          classifyExpr s!"{path}.value" callValue ++ classifyExpr s!"{path}.salt" salt
    | .crosscallNamed _ _ args _ =>
        -- RFC 0015 D4: named-callee app-chain call (Aleo _dynamic_call).
        #[finding path "crosscallNamed (named-callee app-chain call)" (.targetFamilyOnly .zkCircuitSourcegen)] ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .crosscallInvokeStaticTyped target methodId args _returnType =>
        #[finding path "crosscallInvokeStaticTyped (STATICCALL)" (.targetFamilyOnly .evm)] ++
          classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.method" methodId ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .crosscallInvokeDelegateTyped target methodId args _returnType =>
        #[finding path "crosscallInvokeDelegateTyped (DELEGATECALL)" (.targetFamilyOnly .evm)] ++
          classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.method" methodId ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        #[finding path "nearCrosscallInvokePool" (.targetFamilyOnly .wasmHost)] ++
          classifyExpr s!"{path}.account" accountIndex ++
          classifyExpr s!"{path}.method" methodId ++
          classifyExpr s!"{path}.deposit" deposit ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
        #[finding path "nearPromiseThen" (.targetFamilyOnly .wasmHost)] ++
          classifyExpr s!"{path}.parent" parentPromise ++
          classifyExpr s!"{path}.callback" callbackMethod ++
          classifyExpr s!"{path}.deposit" deposit ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .nearPromiseResultsCount =>
        #[finding path "nearPromiseResultsCount" (.targetFamilyOnly .wasmHost)]
    | .nearPromiseResultStatus index =>
        #[finding path "nearPromiseResultStatus" (.targetFamilyOnly .wasmHost)] ++
          classifyExpr s!"{path}.index" index
    | .nearPromiseResultU64 index =>
        #[finding path "nearPromiseResultU64" (.targetFamilyOnly .wasmHost)] ++
          classifyExpr s!"{path}.index" index
    | .crosscallInvoke target methodId args =>
        #[finding path "crosscall.invoke" .familyShared] ++
          classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.method" methodId ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .crosscallInvokeTyped target methodId args _returnType =>
        #[finding path "crosscall.invoke.typed" .familyShared] ++
          classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.method" methodId ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .crosscallInvokeValueTyped target methodId callValue args _returnType =>
        #[finding path "crosscall.invoke.value" .familyShared] ++
          classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.method" methodId ++
          classifyExpr s!"{path}.value" callValue ++
          args.foldl (fun acc arg => acc ++ classifyExpr s!"{path}.arg" arg) #[]
    | .nativeValue =>
        #[finding path "nativeValue" .familyShared]
    | .effect eff => classifyEffect path eff
    | .literal _ | .local _ => #[]
    | .arrayLit _ values =>
        values.foldl (fun acc v => acc ++ classifyExpr s!"{path}.elem" v) #[]
    | .arrayGet array index =>
        classifyExpr s!"{path}.array" array ++ classifyExpr s!"{path}.index" index
    | .memoryArrayNew _ length => classifyExpr s!"{path}.len" length
    | .memoryArrayLength array => classifyExpr s!"{path}.array" array
    | .memoryArrayGet array index =>
        classifyExpr s!"{path}.array" array ++ classifyExpr s!"{path}.index" index
    | .structLit _ fields =>
        fields.foldl (fun acc f => acc ++ classifyExpr s!"{path}.field" f.snd) #[]
    | .field base _ => classifyExpr s!"{path}.base" base
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        classifyExpr s!"{path}.lhs" lhs ++ classifyExpr s!"{path}.rhs" rhs
    | .ecrecover a b c d =>
        classifyExpr s!"{path}.a" a ++ classifyExpr s!"{path}.b" b ++
          classifyExpr s!"{path}.c" c ++ classifyExpr s!"{path}.d" d
    | .eip712PermitDigest a b c d e f =>
        classifyExpr s!"{path}.a" a ++ classifyExpr s!"{path}.b" b ++
          classifyExpr s!"{path}.c" c ++ classifyExpr s!"{path}.d" d ++
          classifyExpr s!"{path}.e" e ++ classifyExpr s!"{path}.f" f
    | .crosscallAbiPacked target _ _ _ _ _ dynLen? _dynOffs dynTargets =>
        let base :=
          #[finding path "crosscallAbiPacked (ABI Call[] plan; optional runtime length/targets)"
              (.targetFamilyOnly .evm)] ++
            classifyExpr s!"{path}.target" target
        let base :=
          match dynLen? with
          | none => base
          | some len => base ++ classifyExpr s!"{path}.dynLen" len
        dynTargets.foldl (init := base) fun acc t =>
          acc ++ classifyExpr s!"{path}.dynTarget" t
    | .cast value _ | .boolNot value | .hash value =>
        classifyExpr s!"{path}.value" value
    | .hashValue a b c d =>
        classifyExpr s!"{path}.a" a ++ classifyExpr s!"{path}.b" b ++
          classifyExpr s!"{path}.c" c ++ classifyExpr s!"{path}.d" d

  partial def classifyEffect (path : String) : Effect → Array PortabilityFinding
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        classifyExpr s!"{path}.value" value
    | .storageMapContains _ key | .storageMapGet _ key =>
        classifyExpr s!"{path}.key" key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        classifyExpr s!"{path}.key" key ++ classifyExpr s!"{path}.value" value
    | .storageArrayRead _ index => classifyExpr s!"{path}.index" index
    | .storageArrayWrite _ index value =>
        classifyExpr s!"{path}.index" index ++ classifyExpr s!"{path}.value" value
    | .storageArrayStructFieldRead _ index _ => classifyExpr s!"{path}.index" index
    | .storageArrayStructFieldWrite _ index _ value =>
        classifyExpr s!"{path}.index" index ++ classifyExpr s!"{path}.value" value
    | .storageDynamicArrayPush _ value => classifyExpr s!"{path}.value" value
    | .storageDynamicArrayPop _ => #[]
    | .memoryArraySet array index value =>
        classifyExpr s!"{path}.array" array ++ classifyExpr s!"{path}.index" index ++
          classifyExpr s!"{path}.value" value
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ value => classifyExpr s!"{path}.value" value
    | .storagePathRead _ pathSegs =>
        pathSegs.foldl (fun acc seg => acc ++ classifyPathSegment s!"{path}.seg" seg) #[]
    | .storagePathWrite _ pathSegs value =>
        pathSegs.foldl (fun acc seg => acc ++ classifyPathSegment s!"{path}.seg" seg)
          (classifyExpr s!"{path}.value" value)
    | .storagePathAssignOp _ pathSegs _ value =>
        pathSegs.foldl (fun acc seg => acc ++ classifyPathSegment s!"{path}.seg" seg)
          (classifyExpr s!"{path}.value" value)
    | .contextRead field =>
        match field with
        | _ => if field.isPortableEnv then
                 #[finding path s!"contextRead.{field.name}" .familyShared]
               else
                 #[finding path s!"contextRead.{field.name}" (.targetFamilyOnly .evm)]
    | .eventEmit _ fields =>
        fields.foldl (fun acc f => acc ++ classifyExpr s!"{path}.field" f.snd) #[]
    | .eventEmitIndexed _ indexed data =>
        indexed.foldl (fun acc f => acc ++ classifyExpr s!"{path}.indexed" f.snd)
          (data.foldl (fun acc f => acc ++ classifyExpr s!"{path}.data" f.snd) #[])
    | .checkErc721Received a b c d =>
        -- EVM-only IERC721Receiver check (PF-P2-02); not triad-portable.
        #[finding path "checkErc721Received" (.targetFamilyOnly .evm)] ++
          classifyExpr s!"{path}.operator" a ++
          classifyExpr s!"{path}.from" b ++
          classifyExpr s!"{path}.to" c ++
          classifyExpr s!"{path}.tokenId" d
    | .checkErc1155Received a b c d e =>
        -- EVM-only IERC1155Receiver check (PF-P2-02); not triad-portable.
        #[finding path "checkErc1155Received" (.targetFamilyOnly .evm)] ++
          classifyExpr s!"{path}.operator" a ++
          classifyExpr s!"{path}.from" b ++
          classifyExpr s!"{path}.to" c ++
          classifyExpr s!"{path}.id" d ++
          classifyExpr s!"{path}.amount" e

  partial def classifyPathSegment (path : String) : StoragePathSegment → Array PortabilityFinding
    | .field _ => #[]
    | .index index => classifyExpr s!"{path}.index" index
    | .mapKey key => classifyExpr s!"{path}.key" key

  partial def classifyStatement (path : String) : Statement → Array PortabilityFinding
    | .letBind _ _ value | .letMutBind _ _ value => classifyExpr s!"{path}.value" value
    | .assign target value =>
        classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.value" value
    | .assignOp target _ value =>
        classifyExpr s!"{path}.target" target ++ classifyExpr s!"{path}.value" value
    | .effect eff => classifyEffect path eff
    | .assert condition _ _ => classifyExpr s!"{path}.cond" condition
    | .assertEq lhs rhs _ _ =>
        classifyExpr s!"{path}.lhs" lhs ++ classifyExpr s!"{path}.rhs" rhs
    | .revert _ | .revertWithError _ | .release _ => #[]
    | .ifElse condition thenBody elseBody =>
        classifyExpr s!"{path}.cond" condition ++
          thenBody.foldl (fun acc stmt => acc ++ classifyStatement s!"{path}.then" stmt) #[] ++
          elseBody.foldl (fun acc stmt => acc ++ classifyStatement s!"{path}.else" stmt) #[]
    | .boundedFor _ _ _ body =>
        body.foldl (fun acc stmt => acc ++ classifyStatement s!"{path}.for" stmt) #[]
    | .whileLoop condition body =>
        classifyExpr s!"{path}.while.cond" condition ++
          body.foldl (fun acc stmt => acc ++ classifyStatement s!"{path}.while" stmt) #[]
    | .return value => classifyExpr s!"{path}.return" value
end

def classifyEntrypoint (ep : Entrypoint) : Array PortabilityFinding :=
  let kindFindings :=
    match classifyEntrypointKind ep.kind with
    | .portableCore => #[]
    | other =>
        #[finding s!"entrypoint.{ep.name}.kind" (entrypointKindName ep.kind) other]
  let selectorFindings :=
    if ep.selector?.isSome then
      #[finding s!"entrypoint.{ep.name}.selector" "optional dispatch tag" (.targetMetadata none)]
    else #[]
  let abiFindings :=
    if ep.paramAbiWords.any (·.isSome) then
      #[finding s!"entrypoint.{ep.name}.paramAbiWords" "ABI surface overrides"
          (.targetMetadata (some .evm))]
    else #[]
  let bodyFindings :=
    ep.body.foldl (fun acc stmt => acc ++ classifyStatement s!"entrypoint.{ep.name}" stmt) #[]
  kindFindings ++ selectorFindings ++ abiFindings ++ bodyFindings

/-- Portable state declarations are always chain-neutral (shape only).
Native binding is target-resolved via `Target.StorageBinding`, not IR fields. -/
def classifyState (_state : StateDecl) : Array PortabilityFinding := #[]

def classifyModule (module : Module) : Array PortabilityFinding :=
  let stateFindings := module.state.foldl (fun acc s => acc ++ classifyState s) #[]
  let entryFindings :=
    module.entrypoints.foldl (fun acc ep => acc ++ classifyEntrypoint ep) #[]
  let proxyFindings :=
    match module.proxyPattern? with
    | some pattern =>
        #[finding "module.proxyPattern" pattern (.targetMetadata (some .evm))]
    | none => #[]
  let nearStringFindings :=
    if module.nearCrosscallStrings.isEmpty then #[]
    else
      #[finding "module.nearCrosscallStrings" "NEAR host string pool"
          (.targetMetadata (some .wasmHost))]
  stateFindings ++ entryFindings ++ proxyFindings ++ nearStringFindings

/-- Findings that are not portable-core and not generic metadata. -/
def nonPortableFindings (module : Module) : Array PortabilityFinding :=
  (classifyModule module).filter fun f =>
    match f.class_ with
    | .portableCore => false
    | .targetMetadata none => false
    | _ => true

/-- True when the module only uses portable-core / family-shared constructors
plus neutral metadata (selectors). Capability gating still applies per target. -/
def isPortableCoreModule (module : Module) : Bool :=
  (classifyModule module).all fun f =>
    match f.class_ with
    | .portableCore | .familyShared | .targetMetadata none => true
    | .targetFamilyOnly _ | .targetMetadata (some _) => false

/-- Reject target-family-only constructors when lowering for a different family. -/
def familyOnlyViolations (module : Module) (family : TargetFamily) : Array PortabilityFinding :=
  (classifyModule module).filter fun f =>
    match f.class_ with
    | .targetFamilyOnly other => other != family
    | .targetMetadata (some other) => other != family
    | _ => false

def renderFinding (f : PortabilityFinding) : String :=
  s!"{f.path}: {f.detail} [{f.class_.describe}]"

def renderViolations (findings : Array PortabilityFinding) : String :=
  String.intercalate "; " (findings.map renderFinding).toList

end ProofForge.IR.Portability
