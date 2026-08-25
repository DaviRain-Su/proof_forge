import Lean
import ProofForge.Extract.Ops
import ProofForge.Profile
import ProofForge.Attr
import ProofForge.Svm.Runtime
import ProofForge.Evm.Runtime

open Lean

namespace ProofForge.Extract

private opaque localRef (i : Nat) : UInt64
private opaque methodArgRef (i : Nat) : UInt64
private def methodArgLocalBase : Nat := 1000000

def sketchOfExpr (e : Expr) : Array String :=
  let names := e.getUsedConstantsAsSet.toList.toArray.qsort (·.toString < ·.toString)
  names.map (·.toString)

private def isConstNamed (e : Expr) (n : Name) : Bool :=
  e.consumeMData.getAppFn.constName? == some n

private def isVectorSet (e : Expr) : Bool :=
  isConstNamed e ``Vector.set ||
    (e.getAppFn.constName?.map (·.toString.endsWith "Vector.set")).getD false

private def strip (e : Expr) : Expr :=
  e.consumeMData

private def endsWith (e : Expr) (suf : String) : Bool :=
  (e.getAppFn.constName?.map (·.toString.endsWith suf)).getD false

private def peelLams (e : Expr) : Nat × Expr :=
  let rec go (fuel : Nat) (n : Nat) (e : Expr) : Nat × Expr :=
    match fuel with
    | 0 => (n, e)
    | fuel' + 1 =>
      match strip e with
      | .lam _ _ body _ => go fuel' (n + 1) body
      | e => (n, e)
  go 32 0 e

private def peelLets (e : Expr) : Expr :=
  let rec go (fuel : Nat) (e : Expr) : Expr :=
    match fuel with
    | 0 => e
    | fuel' + 1 =>
      match strip e with
      | .letE _ _ _ body _ => go fuel' body
      | e => e
  go 16 e

/-- 把 `have x := v; e` 代进 `e`。剥 let 会丢掉 `have nodes := xs.set`。
必须走进 `dite` 的 proof λ，否则内层 `have` 还在。
`dite` 应用脊很长，fuel 要够。 -/
private def substLets (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .letE _ _ value body _ => substLets fuel' (body.instantiate1 (substLets fuel' value))
    | .lam n ty body bi => .lam n ty (substLets fuel' body) bi
    | .app _ _ =>
      let rec goApp (n : Nat) (e : Expr) : Expr :=
        match n, strip e with
        | n + 1, .app f a => .app (goApp n f) (substLets fuel' a)
        | _, e => substLets fuel' e
      goApp 32 e
    | e => e

/-- Drop only unused head lets and lower the remaining binders.
Effect calls commonly elaborate as `let _ := invoke; ok ...`; plain `peelLets` drops that
binder without lowering the source arguments, while substituting every let destroys the
local-result shape used by checked arithmetic decoding. -/
private def dropUnusedHeadLets (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .letE n ty value body nondep =>
      let body := dropUnusedHeadLets fuel' body
      if body.hasLooseBVar 0 then .letE n ty value body nondep
      else dropUnusedHeadLets fuel' (body.lowerLooseBVars 1 1)
    | e => e

private def isIteExpr (e : Expr) : Bool :=
  isConstNamed (peelLets (strip e)) ``ite || isConstNamed (peelLets (strip e)) ``dite

/-- Find an outer guard under only `Id.run` and leading lets, without searching through the guard
or hoisting a loop from one of its branches. -/
private def guardedRunBody? (fuel : Nat) (e : Expr) : Option Expr :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := strip e
    if isConstNamed e ``ite || isConstNamed e ``dite then some e
    else if isConstNamed e ``Id.run && e.getAppArgs.size ≥ 1 then
      guardedRunBody? fuel' e.getAppArgs[e.getAppArgs.size - 1]!
    else
      match e with
      | .letE _ _ value body _ => guardedRunBody? fuel' (body.instantiate1 value)
      | _ => none

/-- Preserve `UInt64` lets for lexical lowering. Zeta-reduce narrow scalar aliases and
aliases around `ite`; retain control/state lets for their dedicated decoders. -/
private def substIteLets (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .letE n ty value body nd =>
      let value := substIteLets fuel' value
      let body := substIteLets fuel' body
      let tyName := ty.consumeMData.getAppFn.constName?
      if tyName == some ``UInt64 then
        .letE n ty value body nd
      else if tyName == some ``UInt8 || tyName == some ``UInt16 ||
          tyName == some ``UInt32 || isIteExpr body then
        substIteLets fuel' (body.instantiate1 value)
      else
        .letE n ty value body nd
    | .lam n ty body bi => .lam n ty (substIteLets fuel' body) bi
    | .app _ _ =>
      let rec goApp (n : Nat) (e : Expr) : Expr :=
        match n, strip e with
        | n + 1, .app f a => .app (goApp n f) (substIteLets fuel' a)
        | _, e => substIteLets fuel' e
      goApp 32 e
    | e => e

/-- Substitute scalar captures while retaining mutable state/control lets needed to recognize a
state-carrying `for` loop. -/
private def substUInt64Lets (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .letE n ty value body nd =>
      let value := substUInt64Lets fuel' value
      let body := substUInt64Lets fuel' body
      if ty.consumeMData.getAppFn.constName? == some ``UInt64 then
        -- An unused UInt64 can still own an effect (for example `let _ := invoke ...`).
        -- Keep it until effect-aware loop normalization can distinguish the call from a
        -- disposable scalar alias.
        if body.hasLooseBVar 0 then substUInt64Lets fuel' (body.instantiate1 value)
        else .letE n ty value body nd
      else
        .letE n ty value body nd
    | .lam n ty body bi => .lam n ty (substUInt64Lets fuel' body) bi
    | .app _ _ =>
      let rec goApp (n : Nat) (e : Expr) : Expr :=
        match n, strip e with
        | n + 1, .app fn arg => .app (goApp n fn) (substUInt64Lets fuel' arg)
        | _, e => substUInt64Lets fuel' e
      goApp 32 e
    | e => e

/-- 剥 `pure` / `ForInStep.done` / `Option.some`；`Prod.mk` 只在末字段是 `PUnit` 时剥。 -/
private def peelControl (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => peelLets (strip e)
  | fuel' + 1 =>
    let e := peelLets (strip e)
    if (isConstNamed e ``Pure.pure || endsWith e ".pure" ||
          isConstNamed e ``ForInStep.done || endsWith e ".done" ||
          isConstNamed e ``Option.some || endsWith e ".some") &&
        e.getAppArgs.size ≥ 1 then
      peelControl fuel' e.getAppArgs[e.getAppArgs.size - 1]!
    else if (isConstNamed e ``Prod.mk || endsWith e ".Prod.mk") && e.getAppArgs.size ≥ 2 then
      let last := strip e.getAppArgs[e.getAppArgs.size - 1]!
      if endsWith last ".unit" || isConstNamed last ``PUnit.unit then
        peelControl fuel' e.getAppArgs[e.getAppArgs.size - 2]!
      else e
    else e

private def isForInYield (e : Expr) : Bool :=
  let rec go (fuel : Nat) (e : Expr) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 =>
      let e := peelLets (strip e)
      if isConstNamed e ``ForInStep.yield || endsWith e ".yield" then true
      else
        match e with
        | .lam _ _ body _ => go fuel' body
        | .letE _ _ value body _ => go fuel' value || go fuel' body
        | _ => e.getAppArgs.any (go fuel')
  go 8 e

/-- An early `return` from a `for` callback elaborates to `ForInStep.done`; it belongs to the
early-return loop lowering, not the state-carrying loop lowering. -/
private def isForInDone (e : Expr) : Bool :=
  let rec go (fuel : Nat) (e : Expr) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 =>
      let e := peelLets (strip e)
      if isConstNamed e ``ForInStep.done || endsWith e ".done" then true
      else
        match e with
        | .lam _ _ body _ => go fuel' body
        | .letE _ _ value body _ => go fuel' value || go fuel' body
        | _ => e.getAppArgs.any (go fuel')
  go 32 e

/-- `ForInStep.done` / `yield`：循环体里的 ite 不要降 proof λ。 -/
private def isForInStep (e : Expr) : Bool :=
  let rec go (fuel : Nat) (e : Expr) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 =>
      let e := peelLets (strip e)
      if isConstNamed e ``ForInStep.yield || endsWith e ".yield" ||
          isConstNamed e ``ForInStep.done || endsWith e ".done" then true
      else
        match e with
        | .lam _ _ body _ => go fuel' body
        | .letE _ _ value body _ => go fuel' value || go fuel' body
        | _ => e.getAppArgs.any (go fuel')
  go 8 e

/-- 无参数构造子的 inductive。构造子按声明顺序编号。 -/
private def enumCtorIndex (env : Environment) (tyName ctor : Name) : Option Nat :=
  match env.find? tyName with
  | some (.inductInfo info) =>
    if info.numParams != 0 || info.numIndices != 0 || info.ctors.isEmpty || info.isRec then
      none
    else
      info.ctors.findIdx? (· == ctor)
  | _ => none

private def isEnumLeaf (env : Environment) (tyName : Name) : Bool :=
  match env.find? tyName with
  | some (.inductInfo info) =>
    info.numParams == 0 && info.numIndices == 0 && !info.ctors.isEmpty && !info.isRec &&
      info.ctors.all fun ctor =>
        match env.find? ctor with
        | some (.ctorInfo c) => c.numFields == 0
        | _ => false
  | _ => false

/-- One constructor carrying one `UInt64`: a representational newtype, not a tagged union. -/
private def isUInt64Newtype (env : Environment) (tyName : Name) : Bool :=
  if isStructure env tyName then false
  else
    match env.find? tyName with
    | some (.inductInfo info) =>
      info.numParams == 0 && info.numIndices == 0 && info.ctors.length == 1 && !info.isRec &&
        match env.find? info.ctors[0]! with
        | some (.ctorInfo ctor) =>
          ctor.numFields == 1 &&
            match strip ctor.type with
            | .forallE _ ty _ _ => ty.consumeMData.getAppFn.constName? == some ``UInt64
            | _ => false
        | _ => false
    | _ => false

private def forallDomainAt? (fuel index : Nat) (type : Expr) : Option Expr :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    match strip type with
    | .forallE _ domain body _ =>
      if index == 0 then some domain else forallDomainAt? fuel' (index - 1) body
    | _ => none

private def uint64CtorPayloadWidth? (env : Environment) (ctorName : Name) : Option Nat := do
  let .ctorInfo ctor ← env.find? ctorName | none
  for index in [:ctor.numFields] do
    let fieldTy ← forallDomainAt? 32 index ctor.type
    if fieldTy.consumeMData.getAppFn.constName? != some ``UInt64 then none else pure ()
  return ctor.numFields

/--
Three or more constructors with only `UInt64` fields. Their fixed representation is one tag plus
the largest constructor payload; shorter alternatives receive canonical zero padding.
-/
private def uint64VariantPayloadWidth? (env : Environment) (tyName : Name) : Option Nat :=
  if isStructure env tyName then none
  else
    match env.find? tyName with
    | some (.inductInfo info) =>
      if info.numParams != 0 || info.numIndices != 0 || info.ctors.length < 3 || info.isRec then
        none
      else Id.run do
        let mut payloadWidth := 0
        for ctorName in info.ctors do
          let some ctorWidth := uint64CtorPayloadWidth? env ctorName | return none
          payloadWidth := max payloadWidth ctorWidth
        if payloadWidth == 0 then return none
        return some payloadWidth
    | _ => none

private def isUInt64Variant (env : Environment) (tyName : Name) : Bool :=
  (uint64VariantPayloadWidth? env tyName).isSome

private def uint64NewtypeCtorPayload? (env : Environment) (e : Expr) : Option Expr := do
  let ctorName ← e.getAppFn.constName?
  let .ctorInfo ctor ← env.find? ctorName | none
  if !isUInt64Newtype env ctor.induct || e.getAppArgs.isEmpty then none
  else e.getAppArgs[e.getAppArgs.size - 1]?

private def containsUInt64NewtypeCtor (env : Environment) (fuel : Nat) (e : Expr) : Bool :=
  match fuel with
  | 0 => false
  | fuel' + 1 =>
    (uint64NewtypeCtorPayload? env e).isSome ||
      e.getAppArgs.any (containsUInt64NewtypeCtor env fuel')

/-- A one-case matcher is representationally its payload branch; use Lean's matcher metadata. -/
private def reduceUInt64NewtypeMatch? (env : Environment) (e : Expr) : Option Expr := do
  let matcherName ← e.getAppFn.constName?
  let info ← Lean.Meta.getMatcherInfoCore? env matcherName
  if info.numDiscrs != 1 || info.numAlts != 1 then none else pure ()
  let altInfo ← info.altInfos[0]?
  if altInfo.numFields != 1 then none else pure ()
  let decl ← env.find? matcherName
  let discrType ← forallDomainAt? 32 info.getFirstDiscrPos decl.type
  let tyName ← discrType.consumeMData.getAppFn.constName?
  if !isUInt64Newtype env tyName then none else pure ()
  let args := e.getAppArgs
  let discr ← args[info.getFirstDiscrPos]?
  let alt ← args[info.getFirstAltPos]?
  match strip alt with
  | .lam _ _ body _ => some (body.instantiate1 discr)
  | _ => none

/-- 两构造子：一个 0 字段、一个 1 个 UInt64。按 Option 双叶展开。 -/
private def isOptionLikeInductive (env : Environment) (tyName : Name) : Bool :=
  match env.find? tyName with
  | some (.inductInfo info) =>
    info.numParams == 0 && info.numIndices == 0 && info.ctors.length == 2 && !info.isRec &&
      Id.run do
        let mut zeros := 0
        let mut ones := 0
        for ctor in info.ctors do
          match env.find? ctor with
          | some (.ctorInfo c) =>
            if c.numFields == 0 then zeros := zeros + 1
            else if c.numFields == 1 then
              match strip c.type with
              | .forallE _ ty _ _ =>
                if ty.consumeMData.getAppFn.constName? == some ``UInt64 then
                  ones := ones + 1
              | _ => pure ()
          | _ => pure ()
        return zeros == 1 && ones == 1
  | _ => false

private def matcherDiscrTypeName? (env : Environment) (e : Expr) : Option Name := do
  let matcherName ← e.getAppFn.constName?
  let info ← Lean.Meta.getMatcherInfoCore? env matcherName
  if info.numDiscrs != 1 then none else pure ()
  let decl ← env.find? matcherName
  let discrType ← forallDomainAt? 32 info.getFirstDiscrPos decl.type
  discrType.consumeMData.getAppFn.constName?

private def isOptionLikeMatcher (env : Environment) (e : Expr) : Bool :=
  match matcherDiscrTypeName? env e with
  | some tyName => tyName == ``Option || isOptionLikeInductive env tyName
  | none => false

private def isUInt64VariantMatcher (env : Environment) (e : Expr) : Bool :=
  match matcherDiscrTypeName? env e with
  | some tyName => isUInt64Variant env tyName
  | none => false

private def peelMatcherLams (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .lam _ _ body _ => peelMatcherLams fuel' body
    | e => e

private def asLit (fuel : Nat) (e : Expr) : Option Ops.Val :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    match strip e with
    | .lit (.natVal n) =>
      if n < UInt64.size then some (.lit (UInt64.ofNat n)) else none
    | e =>
      if isConstNamed e ``OfNat.ofNat then
        let args := e.getAppArgs
        match args.findSome? (asLit fuel') with
        | some v => some v
        | none =>
          if args.size ≥ 2 then asLit fuel' args[1]! else none
      else none

private def looksLikeOptionProj (env : Environment) (n : Name) : Bool :=
  match env.find? n with
  | some info => info.type.getUsedConstantsAsSet.toList.any (· == ``Option)
  | none => false

/-- `s.book.price` → 槽 `book_price`。动态向量投影保留逻辑叶名，稍后由 schema 解析。 -/
private def flattenField (base : Ops.Val) (leaf : String) : Ops.Val :=
  match base with
  | .field b parent => .field b s!"{parent}_{leaf}"
  | b@(.indexGet ..) => .field b leaf
  | b => .field b leaf

/-- 工具自己的模块。用户项目可以叫任何名字。 -/
private def isToolName (n : Name) : Bool :=
  let head := n.getRoot
  head == `ProofForge || head == `Lean || head == `Std || head == `Init ||
    head == `IO || head == `System || head == `Lake ||
    head == `HAdd || head == `HSub || head == `HMul || head == `HDiv ||
    head == `HMod || head == `HAnd || head == `HOr || head == `HXor ||
    head == `HShiftLeft || head == `HShiftRight || head == `Complement ||
    head == `LE || head == `LT || head == `GE || head == `GT ||
    head == `UInt8 || head == `UInt16 || head == `UInt32 || head == `UInt64 ||
    head == `Bool || head == `Nat || head == `Option || head == `Except ||
    head == `Prod || head == `Vector || head == `Array || head == `List ||
    head == `BitVec || head == `OfNat || head == `BEq || head == `Decidable ||
    head == `Float || head == `Float32 || head == `String || head == `Char

private def isReservedProj (last : String) : Bool :=
  last == "mk" || last == "set" || last == "ok" || last == "error" ||
    last == "getElem" || last == "getElem!" || last == "rfl" ||
    last.startsWith "_proof"

/-- 用户 datatype：structure 或 inductive，且不在工具模块里。 -/
private def isUserType (env : Environment) (n : Name) : Bool :=
  !isToolName n &&
    (isStructure env n ||
      match env.find? n with
      | some (.inductInfo _) => true
      | _ => false)

/-- 用户 structure / inductive 的投影 / 构造子。`UInt64.toNat`、`HSub.hSub` 不是。 -/
private def isUserName (env : Environment) (n : Name) : Bool :=
  if isToolName n || isReservedProj (Core.IR.lastName n.toString) then
    false
  else if isUserType env n then
    true
  else
    match env.find? n with
    | some (.ctorInfo info) => isUserType env info.induct
    | some _ =>
      match n with
      | .str p last =>
        last != "toNat" && last != "toUInt64" && isUserType env p
      | _ => false
    | none => false

/-- Recover the schema path owned by nested user-structure projections.
`s.book.right` is represented by two projection applications but owns the flattened leaf
`book_right`; stopping at the terminal projection would collide with every other nested `right`. -/
private def projectionPath (env : Environment) (fuel : Nat) (e : Expr) : Option String :=
  match fuel with
  | 0 => none
  | fuel' + 1 => do
    let e := strip e
    let n ← e.getAppFn.constName?
    let _ ← env.getProjectionFnInfo? n
    if !isUserName env n then none else
    let leaf := Core.IR.lastName n.toString
    let args := e.getAppArgs
    let parent :=
      if h : args.size > 0 then projectionPath env fuel' args[args.size - 1]
      else none
    match parent with
    | some parent => some s!"{parent}_{leaf}"
    | none => some leaf

/-- Trace an expression to the user projection whose result is the owning fixed vector. -/
private def vectorBaseName (env : Environment) (fuel : Nat) (e : Expr) : Option String :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    match e.getAppFn.constName? with
    | some n =>
      let last := Core.IR.lastName n.toString
      let skipTy :=
        match env.find? n with
        | some (.inductInfo _) => true
        | some (.ctorInfo _) => true
        | _ => false
      let returnsVector :=
        match env.find? n with
        | some info => info.type.getUsedConstantsAsSet.toList.any (· == ``Vector)
        | none => false
      if !isUserName env n || isReservedProj last || skipTy || !returnsVector then
        e.getAppArgs.findSome? (vectorBaseName env fuel')
      else projectionPath env fuel' e
    | none => e.getAppArgs.findSome? (vectorBaseName env fuel')

/--
Profile 已检查过且显式标记的用户 helper 按需 β 展开。控制流与 State
归一化共用这一个边界；未标记的定义不会因为碰巧能展开而进入 IR。
-/
private def unfoldUserHelper (env : Environment) (e : Expr) : Option (Name × Expr) :=
  let e := strip e
  match e.getAppFn.constName? with
  | none => none
  | some n =>
    if Attr.isInline env n then
      match env.find? n with
      | some (.defnInfo info) => some (n, info.value.beta e.getAppArgs)
      | _ => none
    else none

private def resultType (fuel : Nat) (type : Expr) : Expr :=
  match fuel with
  | 0 => type
  | fuel' + 1 =>
    match strip type with
    | .forallE _ _ body _ => resultType fuel' body
    | type => type

private def isScalarResult (env : Environment) (type : Expr) : Bool :=
  match (resultType 16 type).consumeMData.getAppFn.constName? with
  | some name => name == ``UInt64 || name == ``Bool || isUInt64Newtype env name
  | none => false

private def firstUserInputType (env : Environment) : Nat → Expr → Option Name
  | 0, _ => none
  | fuel + 1, type =>
      match strip type with
      | .forallE _ input body _ =>
          match input.consumeMData.getAppFn.constName? with
          | some name => if isUserType env name then some name else firstUserInputType env fuel body
          | none => firstUserInputType env fuel body
      | _ => none

/-- A marked structure helper is a state transition only when its result preserves the type of
its first user-typed input. This separates `State → … → State` updates from pure readers such as
`State → address → Node` without relying on declaration names. -/
private def inlineHelperPreservesUserType (env : Environment) (name : Name) : Bool :=
  match env.find? name with
  | some (.defnInfo helper) =>
      match firstUserInputType env 16 helper.type,
          (resultType 16 helper.type).consumeMData.getAppFn.constName? with
      | some input, some output => input == output
      | _, _ => false
  | _ => false

/-- Reduce `({ s with field := value }).field` before scalar lowering. -/
private def reduceCtorProjection? (env : Environment) (e : Expr) : Option Expr := do
  let projection ← e.getAppFn.constName?
  let projectionInfo ← env.getProjectionFnInfo? projection
  let args := e.getAppArgs
  let base ← args[args.size - 1]?
  let base := strip base
  let ctorName ← base.getAppFn.constName?
  if ctorName != projectionInfo.ctorName then none else pure ()
  let .ctorInfo ctor ← env.find? ctorName | none
  let fields := base.getAppArgs
  if fields.size < ctor.numFields || projectionInfo.i ≥ ctor.numFields then none
  else fields[fields.size - ctor.numFields + projectionInfo.i]?

/-- Reduce a projection over a marked structure helper without guessing from its name. A helper
whose first user-typed input and result have the same type is a State transition already emitted
by `decodeYieldState`, so its projection reads the current mutable source. Other helpers are pure
structure readers (for example a vector-node lookup), so project from their unfolded value. -/
private def reduceInlineProjection? (env : Environment) (e : Expr) : Option Expr := do
  let projection ← e.getAppFn.constName?
  let _ ← env.getProjectionFnInfo? projection
  let args := e.getAppArgs
  let base ← args[args.size - 1]?
  let (helperName, unfolded) ← unfoldUserHelper env base
  let baseArgs := base.getAppArgs
  let source ← baseArgs[0]?
  let replacement :=
    if inlineHelperPreservesUserType env helperName then source else unfolded
  return e.replace fun child => if child == base then some replacement else none

private def staticUInt64? : Ops.Val → Option UInt64
  | .lit value => some value
  | .bitNot value => staticUInt64? value |>.map (~~~·)
  | _ => none

/-- Decode a literal `#[...]` without interpreting its element type. Kept before `asVal` so
compile-time PDA seed lists can be values as well as CPI operands. -/
private def asStaticArrayElems (e : Expr) : Option (Array Expr) :=
  let rec fromList (fuel : Nat) (e : Expr) (acc : Array Expr) : Option (Array Expr) :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if isConstNamed e ``List.nil then some acc
      else if isConstNamed e ``List.cons && e.getAppArgs.size ≥ 2 then
        let args := e.getAppArgs
        fromList fuel' args[args.size - 1]! (acc.push args[args.size - 2]!)
      else none
  let e := strip e
  if isConstNamed e ``Array.mk && e.getAppArgs.size ≥ 1 then
    fromList 32 e.getAppArgs[e.getAppArgs.size - 1]! #[]
  else if isConstNamed e ``List.toArray && e.getAppArgs.size ≥ 1 then
    fromList 32 e.getAppArgs[e.getAppArgs.size - 1]! #[]
  else if isConstNamed e ``Array.empty || endsWith e ".empty" then
    some #[]
  else none

private def asPdaSeed (e : Expr) : Option Ops.PdaSeed :=
  let e := strip e
  if isConstNamed e ``ProofForge.Svm.Runtime.PdaSeed.ascii || endsWith e ".ascii" then
    if e.getAppArgs.size ≥ 1 then
      match strip e.getAppArgs[e.getAppArgs.size - 1]! with
      | .lit (.strVal value) => if value.isEmpty then none else some (.ascii value)
      | _ => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.PdaSeed.stateKey || endsWith e ".stateKey" then
    some .stateKey
  else if isConstNamed e ``ProofForge.Svm.Runtime.PdaSeed.accKey || endsWith e ".accKey" then
    if e.getAppArgs.size ≥ 1 then
      match asLit 8 e.getAppArgs[e.getAppArgs.size - 1]! with
      | some (.lit i) => some (.accKey i.toNat)
      | _ => none
    else none
  else none

private def asPdaSeeds (e : Expr) : Option (Array Ops.PdaSeed) := do
  let elems ← asStaticArrayElems e
  elems.mapM asPdaSeed

private def asVal (env : Environment) (fuel : Nat) (e : Expr) : Option Ops.Val :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := strip e
    match e with
    | .letE _ _ value body _ => asVal env fuel' (body.instantiate1 value)
    | .bvar i => some (.arg i)
    | _ =>
      if let some reduced := reduceCtorProjection? env e then
        asVal env fuel' reduced
      else if let some reduced := reduceInlineProjection? env e then
        asVal env fuel' reduced
      else if let some reduced := reduceUInt64NewtypeMatch? env e then
        asVal env fuel' reduced
      else if let some v := asLit fuel' e then some v
      else if let some payload := uint64NewtypeCtorPayload? env e then
        asVal env fuel' payload
      else if isConstNamed e ``localRef && e.getAppArgs.size ≥ 1 then
        match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
        | some (.lit i) => some (.local i.toNat)
        | _ => none
      else if isConstNamed e ``methodArgRef && e.getAppArgs.size ≥ 1 then
        match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
        | some (.lit i) => some (.local (methodArgLocalBase + i.toNat))
        | _ => none
      else if isConstNamed e ``ite && e.getAppArgs.size ≥ 4 then
        let args := e.getAppArgs
        let rawCond := strip args[args.size - 4]!
        let (cond, negate) :=
          if isConstNamed rawCond ``Not && rawCond.getAppArgs.size ≥ 1 then
            (strip rawCond.getAppArgs[rawCond.getAppArgs.size - 1]!, true)
          else
            (rawCond, false)
        let cmp? : Option Ops.Cmp :=
          if isConstNamed cond ``Eq || isConstNamed cond ``BEq.beq then some .eq
          else if isConstNamed cond ``Ne then some .ne
          else if isConstNamed cond ``LT.lt then some .lt
          else if isConstNamed cond ``LE.le then some .le
          else if isConstNamed cond ``GT.gt then some .gt
          else if isConstNamed cond ``GE.ge || endsWith cond ".ge" || endsWith cond ".hGe" then
            some .ge
          else none
        let invert : Ops.Cmp → Option Ops.Cmp
          | .eq => some .ne | .ne => some .eq
          | .lt => some .ge | .le => some .gt
          | .gt => some .le | .ge => some .lt
        let condArgs := cond.getAppArgs
        match cmp? with
        | some cmp =>
          if h : condArgs.size ≥ 2 then
            let lhs := condArgs[condArgs.size - 2]
            let rhs := condArgs[condArgs.size - 1]
            let cmp? := if negate then invert cmp else some cmp
            match cmp?, asVal env fuel' lhs, asVal env fuel' rhs,
                asVal env fuel' args[args.size - 2]!, asVal env fuel' args[args.size - 1]! with
            | some cmp, some lv, some rv, some thn, some els =>
                some (.select cmp lv rv thn els)
            | _, _, _, _, _ => none
          else none
        | none =>
          match asVal env fuel' rawCond,
              asVal env fuel' args[args.size - 2]!, asVal env fuel' args[args.size - 1]! with
          | some cond, some thn, some els => some (.select .ne cond (.lit 0) thn els)
          | _, _, _ => none
      else if let some n := e.getAppFn.constName? then
        let field := n.toString
        let user := isUserName env n
        if (isConstNamed e ``Eq || isConstNamed e ``BEq.beq || isConstNamed e ``Ne ||
            isConstNamed e ``LT.lt || isConstNamed e ``LE.le || isConstNamed e ``GT.gt ||
            isConstNamed e ``GE.ge || endsWith e ".ge" || endsWith e ".hGe") &&
            e.getAppArgs.size ≥ 2 then
          let args := e.getAppArgs
          let cmp : Ops.Cmp :=
            if isConstNamed e ``Eq || isConstNamed e ``BEq.beq then .eq
            else if isConstNamed e ``Ne then .ne
            else if isConstNamed e ``LT.lt then .lt
            else if isConstNamed e ``LE.le then .le
            else if isConstNamed e ``GT.gt then .gt
            else .ge
          match asVal env fuel' args[args.size - 2]!,
              asVal env fuel' args[args.size - 1]! with
          | some lhs, some rhs => some (.select cmp lhs rhs (.lit 1) (.lit 0))
          | _, _ => none
        else if isConstNamed e ``Bool.or && e.getAppArgs.size ≥ 2 then
          let args := e.getAppArgs
          match asVal env fuel' args[args.size - 2]!,
              asVal env fuel' args[args.size - 1]! with
          | some lhs, some rhs => some (.bitOr lhs rhs)
          | _, _ => none
        else if isConstNamed e ``Bool.and && e.getAppArgs.size ≥ 2 then
          let args := e.getAppArgs
          match asVal env fuel' args[args.size - 2]!,
              asVal env fuel' args[args.size - 1]! with
          | some lhs, some rhs => some (.bitAnd lhs rhs)
          | _, _ => none
        else if isConstNamed e ``Bool.not && e.getAppArgs.size ≥ 1 then
          (asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]!).map fun value =>
            .select .eq value (.lit 0) (.lit 1) (.lit 0)
        else if isConstNamed e ``Decidable.decide && e.getAppArgs.size ≥ 2 then
          asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!
        else if let some (_, unfolded) := unfoldUserHelper env e then
          match env.find? n with
          | some (.defnInfo info) =>
            if isScalarResult env info.type then asVal env fuel' unfolded else none
          | _ => none
        else if (endsWith e ".checkPdaSeeds" ||
            isConstNamed e ``ProofForge.Svm.Runtime.checkPdaSeeds) && e.getAppArgs.size ≥ 2 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
              asPdaSeeds e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit account), some seeds =>
              let account := account.toNat
              if Svm.Ops.cpiAccInRange account then some (.checkPdaSeeds account seeds) else none
          | _, _ => none
        else if (endsWith e ".findPdaSeeds" ||
            isConstNamed e ``ProofForge.Svm.Runtime.findPdaSeeds) && e.getAppArgs.size ≥ 1 then
          (asPdaSeeds e.getAppArgs[e.getAppArgs.size - 1]!).map Ops.Val.findPdaSeeds
        else if (endsWith e ".findPda" || isConstNamed e ``ProofForge.Svm.Runtime.findPda) &&
            e.getAppArgs.size ≥ 1 then
          match strip e.getAppArgs[e.getAppArgs.size - 1]! with
          | .lit (.strVal s) => if s.isEmpty then none else some (.findPda s)
          | _ => none
        else if (endsWith e ".sha256Lit" || isConstNamed e ``ProofForge.Svm.Runtime.sha256Lit) &&
            e.getAppArgs.size ≥ 1 then
          match strip e.getAppArgs[e.getAppArgs.size - 1]! with
          | .lit (.strVal s) => some (.sha256Lit s)
          | _ => none
        else if (endsWith e ".keccak256Lit" || isConstNamed e ``ProofForge.Svm.Runtime.keccak256Lit) &&
            e.getAppArgs.size ≥ 1 then
          match strip e.getAppArgs[e.getAppArgs.size - 1]! with
          | .lit (.strVal s) => some (.keccak256Lit s)
          | _ => none
        else if (endsWith e ".accKeyWord" || isConstNamed e ``ProofForge.Svm.Runtime.accKeyWord) &&
            e.getAppArgs.size ≥ 2 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
              asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc), some (.lit word) =>
            let a := acc.toNat
            let w := word.toNat
            if Svm.Ops.accInRange a && w ≤ 3 then some (.accKeyWord a w) else none
          | _, _ => none
        else if (endsWith e ".accOwnerWord" || isConstNamed e ``ProofForge.Svm.Runtime.accOwnerWord) &&
            e.getAppArgs.size ≥ 2 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
              asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc), some (.lit word) =>
            let a := acc.toNat
            let w := word.toNat
            if Svm.Ops.accInRange a && w ≤ 3 then some (.accOwnerWord a w) else none
          | _, _ => none
        else if (endsWith e ".checkPda" || isConstNamed e ``ProofForge.Svm.Runtime.checkPda) &&
            e.getAppArgs.size ≥ 2 then
          match strip e.getAppArgs[e.getAppArgs.size - 2]!,
              asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | .lit (.strVal s), some bump =>
            if s.isEmpty then none else some (.checkPda s bump)
          | _, _ => none
        else if (endsWith e ".rentExemption" ||
            isConstNamed e ``ProofForge.Svm.Runtime.rentExemption) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit n) => some (.rentExemption n)
          | _ => none
        else if (endsWith e ".accLamports" || isConstNamed e ``ProofForge.Svm.Runtime.accLamports) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.accLamportsN a) else none
          | _ => none
        else if (endsWith e ".accDataLen" || isConstNamed e ``ProofForge.Svm.Runtime.accDataLen) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.accDataLenN a) else none
          | _ => none
        else if (endsWith e ".isSigner" || isConstNamed e ``ProofForge.Svm.Runtime.isSigner) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.isSignerN a) else none
          | _ => none
        else if (endsWith e ".isWritable" || isConstNamed e ``ProofForge.Svm.Runtime.isWritable) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.isWritableN a) else none
          | _ => none
        else if (endsWith e ".isExecutable" || isConstNamed e ``ProofForge.Svm.Runtime.isExecutable) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.isExecutableN a) else none
          | _ => none
        else if (endsWith e ".signerKey" || isConstNamed e ``ProofForge.Svm.Runtime.signerKey) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.signerKeyN a) else none
          | _ => none
        else if (endsWith e ".ownerIsSelf" || isConstNamed e ``ProofForge.Svm.Runtime.ownerIsSelf) &&
            e.getAppArgs.size ≥ 1 then
          match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.lit acc) =>
            let a := acc.toNat
            if Svm.Ops.accInRange a then some (.ownerIsSelf a) else none
          | _ => none
        else if endsWith e ".evmMapGetAddr" || isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetAddr then
          let args := e.getAppArgs
          let get (n : Nat) : Ops.Val :=
            if args.size ≥ n + 1 then (asVal env fuel' args[args.size - 1 - n]!).getD (.arg n)
            else .arg n
          some (.mapGetAddr (get 3) (get 2) (get 1) (get 0))
        else if endsWith e ".evmMapGetPair" || isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetPair then
          let args := e.getAppArgs
          let get (n : Nat) : Ops.Val :=
            if args.size ≥ n + 1 then (asVal env fuel' args[args.size - 1 - n]!).getD (.arg n)
            else .arg n
          some (.mapGetPair (get 6) (get 5) (get 4) (get 3) (get 2) (get 1) (get 0))
        else if endsWith e ".evmMapGetU64" || isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetU64 then
          let args := e.getAppArgs
          let get (n : Nat) : Ops.Val :=
            if args.size ≥ n + 1 then (asVal env fuel' args[args.size - 1 - n]!).getD (.arg n)
            else .arg n
          some (.mapGetU64 (get 1) (get 0))
        else if user && field.contains "." && e.getAppArgs.size ≥ 1 then
          let proj :=
            match field.splitOn "." with
            | [] => field
            | parts => parts.getLast!
          if proj == "mk" || proj == "ok" || proj == "error" ||
              proj.startsWith "_proof" || proj == "rfl" ||
              (field.startsWith "ProofForge.Svm.Runtime." ||
                field.startsWith "ProofForge.Evm.Runtime.") then none
          else if match env.find? n with
              | some (.ctorInfo _) => true
              | some (.inductInfo _) => true
              | _ => false then none
          else
            -- 整个 Vector 投影本身不是叶。下标 / 元素字段再展开。
            let skipVector :=
              match env.find? n with
              | some info =>
                info.type.getUsedConstantsAsSet.toList.any (· == ``Vector)
              | none => false
            if skipVector then none
            else
              match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
              | some b =>
                let leaf := if looksLikeOptionProj env n then s!"{proj}_tag" else proj
                -- `s.nodes[0]!.value`：基是 `nodes_0`，叶是 `value`。
                some (flattenField b leaf)
              | none =>
                match e.getAppArgs[e.getAppArgs.size - 1]! with
                | .bvar i =>
                  let leaf := if looksLikeOptionProj env n then s!"{proj}_tag" else proj
                  some (flattenField (.arg i) leaf)
                | _ => none
        else if (isConstNamed e ``UInt8.toUInt64 || isConstNamed e ``UInt64.toUInt8 ||
            isConstNamed e ``UInt16.toUInt64 || isConstNamed e ``UInt64.toUInt16 ||
            isConstNamed e ``UInt32.toUInt64 || isConstNamed e ``UInt64.toUInt32 ||
            isConstNamed e ``UInt64.toNat || isConstNamed e ``UInt64.ofNat) &&
            e.getAppArgs.size ≥ 1 then
          asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]!
          else if (isConstNamed e ``HAdd.hAdd || endsWith e ".hAdd") && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.addU64 l r)
          | _, _ => none
          else if (isConstNamed e ``Nat.sub ||
              (isConstNamed e ``HSub.hSub && e.getAppArgs.size ≥ 3 &&
                isConstNamed e.getAppArgs[0]! ``Nat &&
                isConstNamed e.getAppArgs[1]! ``Nat &&
                isConstNamed e.getAppArgs[2]! ``Nat)) && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.select .ge l r (.subU64 l r) (.lit 0))
          | _, _ => none
          else if (isConstNamed e ``HSub.hSub || endsWith e ".hSub") &&
              e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.subU64 l r)
          | _, _ => none
          else if (isConstNamed e ``HMul.hMul || endsWith e ".hMul") &&
              e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.mulU64 l r)
          | _, _ => none
          else if (isConstNamed e ``HDiv.hDiv || endsWith e ".hDiv" ||
              isConstNamed e ``UInt64.div) && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.divU64 l r)
          | _, _ => none
          else if (isConstNamed e ``HMod.hMod || endsWith e ".hMod" ||
              isConstNamed e ``UInt64.mod) && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.modU64 l r)
          | _, _ => none
          else if (isConstNamed e ``HAnd.hAnd || endsWith e ".hAnd") && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.bitAnd l r)
          | _, _ => none
        else if (isConstNamed e ``HOr.hOr || endsWith e ".hOr") && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.bitOr l r)
          | _, _ => none
        else if (isConstNamed e ``HXor.hXor || endsWith e ".hXor") && e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.bitXor l r)
          | _, _ => none
        else if (isConstNamed e ``Complement.complement || endsWith e ".complement") &&
            e.getAppArgs.size ≥ 1 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some v => some (.bitNot v)
          | none => none
        else if (isConstNamed e ``HShiftLeft.hShiftLeft || endsWith e ".hShiftLeft") &&
            e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.shiftL l r)
          | _, _ => none
        else if (isConstNamed e ``HShiftRight.hShiftRight || endsWith e ".hShiftRight") &&
            e.getAppArgs.size ≥ 2 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 2]!,
                asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some l, some r => some (.shiftR l r)
          | _, _ => none
        else if (isConstNamed e ``Option.isSome || endsWith e ".isSome") && e.getAppArgs.size ≥ 1 then
          match asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
          | some (.field b n) =>
            if n.endsWith "_tag" then some (.field b n)
            else some (.field b s!"{n}_tag")
          | some b => some (.field b s!"slot_tag")
          | none => none
        else if endsWith e ".clockSlot" || isConstNamed e ``ProofForge.Svm.Runtime.clockSlot then
          some .clockSlot
        else if endsWith e ".clockEpoch" || isConstNamed e ``ProofForge.Svm.Runtime.clockEpoch then
          some .clockEpoch
        else if endsWith e ".unixTime" || isConstNamed e ``ProofForge.Svm.Runtime.unixTime then
          some .unixTime
        else if endsWith e ".slotsPerEpoch" || isConstNamed e ``ProofForge.Svm.Runtime.slotsPerEpoch then
          some .slotsPerEpoch
        else if endsWith e ".cpiReturn" || isConstNamed e ``ProofForge.Svm.Runtime.cpiReturn then
          some .cpiReturn
        else if endsWith e ".signerKey0" || isConstNamed e ``ProofForge.Svm.Runtime.signerKey0 then
          some .signerKey0
        else if endsWith e ".evmCaller" || isConstNamed e ``ProofForge.Evm.Runtime.evmCaller then
          some .evmCaller
        else if endsWith e ".evmBlockNumber" || isConstNamed e ``ProofForge.Evm.Runtime.evmBlockNumber then
          some .evmBlockNumber
        else if endsWith e ".evmTimestamp" || isConstNamed e ``ProofForge.Evm.Runtime.evmTimestamp then
          some .evmTimestamp
        else if endsWith e ".evmChainId" || isConstNamed e ``ProofForge.Evm.Runtime.evmChainId then
          some .evmChainId
        else if endsWith e ".evmSelf" || isConstNamed e ``ProofForge.Evm.Runtime.evmSelf then
          some .evmSelf
        else if endsWith e ".evmCallValue" || isConstNamed e ``ProofForge.Evm.Runtime.evmCallValue then
          some .evmCallValue
        else if endsWith e ".evmSelfBalance" || isConstNamed e ``ProofForge.Evm.Runtime.evmSelfBalance then
          some .evmSelfBalance
        else if endsWith e ".evmCallerW0" || isConstNamed e ``ProofForge.Evm.Runtime.evmCallerW0 then
          some .evmCallerW0
        else if endsWith e ".evmCallerW1" || isConstNamed e ``ProofForge.Evm.Runtime.evmCallerW1 then
          some .evmCallerW1
        else if endsWith e ".evmCallerW2" || isConstNamed e ``ProofForge.Evm.Runtime.evmCallerW2 then
          some .evmCallerW2
        else if endsWith e ".evmSelfW0" || isConstNamed e ``ProofForge.Evm.Runtime.evmSelfW0 then
          some .evmSelfW0
        else if endsWith e ".evmSelfW1" || isConstNamed e ``ProofForge.Evm.Runtime.evmSelfW1 then
          some .evmSelfW1
        else if endsWith e ".evmSelfW2" || isConstNamed e ``ProofForge.Evm.Runtime.evmSelfW2 then
          some .evmSelfW2
        else if endsWith e ".accLamports0" || isConstNamed e ``ProofForge.Svm.Runtime.accLamports0 then
          some .accLamports0
        else if endsWith e ".accOwner0" || isConstNamed e ``ProofForge.Svm.Runtime.accOwner0 then
          some .accOwner0
        else if endsWith e ".accDataLen0" || isConstNamed e ``ProofForge.Svm.Runtime.accDataLen0 then
          some .accDataLen0
        else if endsWith e ".accN" || isConstNamed e ``ProofForge.Svm.Runtime.accN then
          some .accN
        else if endsWith e ".isSigner0" || isConstNamed e ``ProofForge.Svm.Runtime.isSigner0 then
          some .isSigner0
        else if endsWith e ".isWritable0" || isConstNamed e ``ProofForge.Svm.Runtime.isWritable0 then
          some .isWritable0
        else if endsWith e ".isExecutable0" || isConstNamed e ``ProofForge.Svm.Runtime.isExecutable0 then
          some .isExecutable0
        else if endsWith e ".accLamports1" || isConstNamed e ``ProofForge.Svm.Runtime.accLamports1 then
          some .accLamports1
        else if endsWith e ".accOwner1" || isConstNamed e ``ProofForge.Svm.Runtime.accOwner1 then
          some .accOwner1
        else if endsWith e ".accDataLen1" || isConstNamed e ``ProofForge.Svm.Runtime.accDataLen1 then
          some .accDataLen1
        else if endsWith e ".isSigner1" || isConstNamed e ``ProofForge.Svm.Runtime.isSigner1 then
          some .isSigner1
        else if endsWith e ".isWritable1" || isConstNamed e ``ProofForge.Svm.Runtime.isWritable1 then
          some .isWritable1
        else if endsWith e ".isExecutable1" || isConstNamed e ``ProofForge.Svm.Runtime.isExecutable1 then
          some .isExecutable1
        else if (endsWith e ".systemTransfer" ||
            isConstNamed e ``ProofForge.Svm.Runtime.systemTransfer) && e.getAppArgs.size ≥ 1 then
          asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]!
        else if endsWith e ".invokeAcc1" || isConstNamed e ``ProofForge.Svm.Runtime.invokeAcc1 ||
            endsWith e ".invoke" || isConstNamed e ``ProofForge.Svm.Runtime.invoke ||
            endsWith e ".invokeSigned" || isConstNamed e ``ProofForge.Svm.Runtime.invokeSigned then
          some (.lit 0)
        else if ((endsWith e ".evmDeposit" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmDeposit) ||
            (endsWith e ".evmLogTipped" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmLogTipped) ||
            (endsWith e ".evmLogIncremented" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmLogIncremented) ||
            (endsWith e ".evmLogTransfer" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmLogTransfer) ||
            (endsWith e ".evmLogApproval" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmLogApproval) ||
            (endsWith e ".evmSendEth" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmSendEth) ||
            (endsWith e ".evmMapGetU64" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetU64) ||
            (endsWith e ".evmMapSetU64" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmMapSetU64) ||
            (endsWith e ".evmMapGetAddr" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetAddr) ||
            (endsWith e ".evmMapSetAddr" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmMapSetAddr) ||
            (endsWith e ".evmMapGetPair" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetPair) ||
            (endsWith e ".evmMapSetPair" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmMapSetPair) ||
            (endsWith e ".evmTokenTransfer" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmTokenTransfer) ||
            (endsWith e ".evmTokenBalanceOfSelf" ||
            isConstNamed e ``ProofForge.Evm.Runtime.evmTokenBalanceOfSelf)) &&
            e.getAppArgs.size ≥ 1 then
            if endsWith e ".evmMapGetU64" || isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetU64 then
            let args := e.getAppArgs
            let get (n : Nat) : Ops.Val :=
              if args.size ≥ n + 1 then (asVal env fuel' args[args.size - 1 - n]!).getD (.arg n)
              else .arg n
            some (.mapGetU64 (get 1) (get 0))
            else if endsWith e ".evmMapGetAddr" || isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetAddr then
            let args := e.getAppArgs
            let get (n : Nat) : Ops.Val :=
              if args.size ≥ n + 1 then (asVal env fuel' args[args.size - 1 - n]!).getD (.arg n)
              else .arg n
            some (.mapGetAddr (get 3) (get 2) (get 1) (get 0))
            else if endsWith e ".evmMapGetPair" || isConstNamed e ``ProofForge.Evm.Runtime.evmMapGetPair then
            let args := e.getAppArgs
            let get (n : Nat) : Ops.Val :=
              if args.size ≥ n + 1 then (asVal env fuel' args[args.size - 1 - n]!).getD (.arg n)
              else .arg n
            some (.mapGetPair (get 6) (get 5) (get 4) (get 3) (get 2) (get 1) (get 0))
            else
            asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]!
            else if isConstNamed e ``Bool.true || endsWith e ".true" then
            some (.lit 1)
        else if isConstNamed e ``Bool.false || endsWith e ".false" then
          some (.lit 0)
        else if user && e.getAppArgs.isEmpty then
          match e.getAppFn.constName? with
          | some ctor =>
            match env.find? ctor with
            | some (.ctorInfo c) =>
              match enumCtorIndex env c.induct ctor with
              | some i => some (.lit (UInt64.ofNat i))
              | none => none
            | _ => none
          | none => none
        else if isConstNamed e ``Option.none || endsWith e ".none" then
          some (.lit 0)
        else if (isConstNamed e ``Option.some || endsWith e ".some") && e.getAppArgs.size ≥ 1 then
          asVal env fuel' e.getAppArgs[e.getAppArgs.size - 1]!
        else if (isConstNamed e ``GetElem.getElem || isConstNamed e ``GetElem?.getElem! ||
            isConstNamed e ``Vector.get ||
            endsWith e ".getElem" || endsWith e ".getElem!" || endsWith e ".get") &&
            e.getAppArgs.size ≥ 2 then
          let args := e.getAppArgs
          -- Do not recursively search proof/type arguments for an index: their local binders
          -- are not source values. The collection/index positions are fixed by GetElem.
          let collIndex? : Option (Expr × Expr) :=
            if isConstNamed e ``GetElem.getElem || endsWith e ".getElem" then
              if h : args.size ≥ 3 then some (args[args.size - 3], args[args.size - 2])
              else none
            else if h : args.size ≥ 2 then
              some (args[args.size - 2], args[args.size - 1])
            else none
          let rec findState (fuel : Nat) (e : Expr) : Option Ops.Val :=
            match fuel with
            | 0 => none
            | fuel' + 1 =>
              match strip e with
              | .bvar j => some (.arg j)
              | e =>
                if isConstNamed e ``methodArgRef && e.getAppArgs.size ≥ 1 then
                  match asLit fuel' e.getAppArgs[e.getAppArgs.size - 1]! with
                  | some (.lit i) => some (.local (methodArgLocalBase + i.toNat))
                  | _ => none
                else e.getAppArgs.findSome? (findState fuel')
          match collIndex?.bind fun pair => (asVal env fuel' pair.2).map (pair.1, ·) with
          | some (collection, .lit n) =>
            let i := n.toNat
            let baseField :=
              match asVal env fuel' collection with
              | some (.field _ fname) => some fname
              | _ => none
            match findState fuel' collection, baseField with
            | some base, some fname =>
              let suf := s!"_{i}"
              let baseName :=
                if fname.endsWith suf then fname.dropEnd suf.length |>.copy else fname
              some (.field base s!"{baseName}_{i}")
            | some base, none =>
              match vectorBaseName env 8 collection with
              | some fname => some (.field base s!"{fname}_{i}")
              | none => none
            | _, _ => none
          | some (collection, idx) =>
            let lits := args.filterMap (asLit fuel')
            let len :=
              if h : lits.size > 0 then
                match lits[0] with
                | .lit n => n.toNat
                | _ => 0
              else 0
            match findState fuel' collection, vectorBaseName env 8 collection with
            | some base, some fname => some (.indexGet base fname idx len)
            | _, _ => none
          | none => none

        else if e.getAppArgs.isEmpty then
          match env.find? n with
          | some (.defnInfo info) =>
            if info.type.consumeMData.getAppFn.constName? == some ``UInt64 then
              match asVal env fuel' info.value with
              | some value =>
                  match staticUInt64? value with
                  | some literal => some (.lit literal)
                  | none => some value
              | none => none
            else none
          | _ => none
        else none
      else none

private def val (env : Environment) (e : Expr) : Option Ops.Val :=
  -- Bounded tree algorithms naturally compose several parent/child projections. Their elaborated
  -- `GetElem`/`toNat` wrappers are deeper than ordinary scalar expressions, but still finite.
  asVal env 32 e

/-- Decode a scalar binding through one explicitly-inline helper boundary before substituting it.
This preserves a shared helper result without increasing the global value-decoder fuel. -/
private partial def valNodeCount : Ops.Val → Nat
  | .arg _ | .local _ | .lit _ | .loopIx => 1
  | .field base _ | .bitNot base => 1 + valNodeCount base
  | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
  | .shiftL lhs rhs | .shiftR lhs rhs | .addU64 lhs rhs | .subU64 lhs rhs
  | .mulU64 lhs rhs | .divU64 lhs rhs | .modU64 lhs rhs =>
      1 + valNodeCount lhs + valNodeCount rhs
  | .indexGet base _ index _ _ => 1 + valNodeCount base + valNodeCount index
  | .select _ lhs rhs thn els =>
      1 + valNodeCount lhs + valNodeCount rhs + valNodeCount thn + valNodeCount els
  | .ext _ operands =>
      1 + operands.foldl (init := 0) fun total operand => total + valNodeCount operand

/-- Materialize scalar source values whose substitution would duplicate bounded control flow. -/
private def shouldMaterializeLocal (_type : Expr) (value : Ops.Val) : Bool :=
  match value with
  | .field .. | .indexGet .. | .select .. => true
  | value => valNodeCount value ≥ 1024

private def localScalarValue? (env : Environment) (fuel : Nat) (value : Expr) : Option Ops.Val :=
  val env value <|> do
    if fuel ≤ 32 then none else pure ()
    let (_, unfolded) ← unfoldUserHelper env value
    let decoded ← asVal env fuel unfolded
    if valNodeCount decoded < 1024 then none else some decoded

private def asUInt64VariantCtor (env : Environment) (e : Expr) :
    Option (UInt64 × Array Ops.Val × Nat) := do
  let ctorName ← e.getAppFn.constName?
  let .ctorInfo ctor ← env.find? ctorName | none
  let payloadWidth ← uint64VariantPayloadWidth? env ctor.induct
  let index ← enumCtorIndex env ctor.induct ctorName
  let args := e.getAppArgs
  if args.size < ctor.numFields then none else pure ()
  let mut payloads : Array Ops.Val := #[]
  for offset in [:ctor.numFields] do
    let payloadExpr ← args[args.size - ctor.numFields + offset]?
    let payload ← val env payloadExpr
    payloads := payloads.push payload
  return (UInt64.ofNat index, payloads, payloadWidth)

private def asSubFromMax (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := strip e
  if isConstNamed e ``HSub.hSub then
    let args := e.getAppArgs
    if args.size ≥ 2 then
      match val env args[args.size - 2]! >>= staticUInt64? with
      | some max => if max == ~~~(0 : UInt64) then val env args[args.size - 1]! else none
      | none => none
    else none
  else none

/-- `x ≤ u64Max - y`  →  checked add x y。单独的 `x ≤ u64Max` 不是 add。 -/
private def asCheckedAddGuard (env : Environment) (e : Expr) : Option (Ops.Val × Ops.Val) :=
  let e := strip e
  if isConstNamed e ``LE.le then
    let args := e.getAppArgs
    if args.size ≥ 2 then
      match val env args[args.size - 2]!, asSubFromMax env args[args.size - 1]! with
      | some lhs, some rhs => some (lhs, rhs)
      | _, _ => none
    else none
  else none

private def asDivFromMax (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := strip e
  if isConstNamed e ``HDiv.hDiv then
    let args := e.getAppArgs
    if args.size ≥ 2 then
      match val env args[args.size - 2]! >>= staticUInt64? with
      | some max => if max == ~~~(0 : UInt64) then val env args[args.size - 1]! else none
      | none => none
    else none
  else none

/-- `x ≤ u64Max / y`  →  checked mul x y -/
private def asCheckedMulGuard (env : Environment) (e : Expr) : Option (Ops.Val × Ops.Val) :=
  let e := strip e
  if isConstNamed e ``LE.le then
    let args := e.getAppArgs
    if args.size ≥ 2 then
      match val env args[args.size - 2]!, asDivFromMax env args[args.size - 1]! with
      | some lhs, some rhs => some (lhs, rhs)
      | _, _ => none
    else none
  else none

private def binArgs (e : Expr) : Option (Expr × Expr) :=
  let args := e.getAppArgs
  if args.size ≥ 2 then some (args[args.size - 2]!, args[args.size - 1]!) else none

private def asCmpCoreWithFuel (env : Environment) (fuel : Nat) (e : Expr) :
    Option (Ops.Cmp × Ops.Val × Ops.Val) :=
  let e := strip e
  if isConstNamed e ``Eq || isConstNamed e ``BEq.beq then
    match binArgs e with
    | some (l, r) =>
      match asVal env fuel l, asVal env fuel r with
      | some lv, some rv => some (.eq, lv, rv)
      | _, _ => none
    | none => none
  else if isConstNamed e ``Ne then
    match binArgs e with
    | some (l, r) =>
      match asVal env fuel l, asVal env fuel r with
      | some lv, some rv => some (.ne, lv, rv)
      | _, _ => none
    | none => none
  else if isConstNamed e ``LT.lt then
    match binArgs e with
    | some (l, r) =>
      match asVal env fuel l, asVal env fuel r with
      | some lv, some rv => some (.lt, lv, rv)
      | _, _ => none
    | none => none
  else if isConstNamed e ``LE.le then
    match binArgs e with
    | some (l, r) =>
      match asVal env fuel l, asVal env fuel r with
      | some lv, some rv => some (.le, lv, rv)
      | _, _ => none
    | none => none
  else if isConstNamed e ``GT.gt then
    match binArgs e with
    | some (l, r) =>
      match asVal env fuel l, asVal env fuel r with
      | some lv, some rv => some (.gt, lv, rv)
      | _, _ => none
    | none => none
  else if isConstNamed e ``GE.ge || endsWith e ".ge" || endsWith e ".hGe" then
    match binArgs e with
    | some (l, r) =>
      match asVal env fuel l, asVal env fuel r with
      | some lv, some rv => some (.ge, lv, rv)
      | _, _ => none
    | none => none
  else none

private def asCmpCore (env : Environment) (e : Expr) : Option (Ops.Cmp × Ops.Val × Ops.Val) :=
  asCmpCoreWithFuel env 32 e

private def asCmp (env : Environment) (e : Expr) : Option (Ops.Cmp × Ops.Val × Ops.Val) :=
  let e := strip e
  if isConstNamed e ``Not then
    let args := e.getAppArgs
    if args.size ≥ 1 then
      match asCmpCore env args[args.size - 1]! with
      | some (.eq, l, r) => some (.ne, l, r)
      | some (.ne, l, r) => some (.eq, l, r)
      | _ => none
    else none
  else
    match asCmpCore env e with
    | some t => some t
    | none =>
      if isConstNamed e ``Eq then
        match binArgs e with
        | some (l, r) =>
          let l := strip l
          let r := strip r
          let trueR := isConstNamed r ``Bool.true || endsWith r ".true"
          let noneR := isConstNamed r ``Option.none || endsWith r ".none"
          let noneL := isConstNamed l ``Option.none || endsWith l ".none"
          if trueR && (isConstNamed l ``Option.isSome || endsWith l ".isSome") then
            match val env l with
            | some (.field b n) =>
              let tag := if n.endsWith "_tag" then n else s!"{n}_tag"
              some (.ne, .field b tag, .lit 0)
            | some b => some (.ne, .field b "slot_tag", .lit 0)
            | none => some (.ne, .field (.arg 0) "slot_tag", .lit 0)
          else if noneR then
            match val env l with
            | some lv => some (.eq, lv, .lit 0)
            | none => none
          else if noneL then
            match val env r with
            | some rv => some (.eq, rv, .lit 0)
            | none => none
          else none
        | none => none
      else if isConstNamed e ``Option.isSome || endsWith e ".isSome" then
        let args := e.getAppArgs
        if args.size ≥ 1 then
          match val env args[args.size - 1]! with
          | some (.field b n) =>
            let tag := if n.endsWith "_tag" then n else s!"{n}_tag"
            some (.ne, .field b tag, .lit 0)
          | some b => some (.ne, .field b "slot_tag", .lit 0)
          | none => none
        else none
      else none

/-- Normalize pure Boolean syntax to a 0/1 value so compound guards do not duplicate branches. -/
private def asBoolVal (env : Environment) (fuel : Nat) (e : Expr) : Option Ops.Val :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := strip e
    if let .letE _ _ value body _ := e then
      asBoolVal env fuel' (body.instantiate1 value)
    else
    let args := e.getAppArgs
    let last? := if h : args.size > 0 then some args[args.size - 1] else none
    if isConstNamed e ``Bool.true then some (.lit 1)
    else if isConstNamed e ``Bool.false then some (.lit 0)
    else if isConstNamed e ``Bool.or && args.size ≥ 2 then
      match asBoolVal env fuel' args[args.size - 2]!, asBoolVal env fuel' args[args.size - 1]! with
      | some lhs, some rhs => some (.bitOr lhs rhs)
      | _, _ => none
    else if isConstNamed e ``Bool.and && args.size ≥ 2 then
      match asBoolVal env fuel' args[args.size - 2]!, asBoolVal env fuel' args[args.size - 1]! with
      | some lhs, some rhs => some (.bitAnd lhs rhs)
      | _, _ => none
    else if isConstNamed e ``Bool.not then
      last?.bind fun value =>
        (asBoolVal env fuel' value).map fun v => .select .eq v (.lit 0) (.lit 1) (.lit 0)
    else if (isConstNamed e ``ite || isConstNamed e ``dite) && args.size ≥ 4 then
      let peelProofLam (value : Expr) : Expr :=
        match strip value with
        | .lam _ _ body _ => body.lowerLooseBVars 1 1
        | value => value
      match asBoolVal env fuel' args[args.size - 4]!,
          asBoolVal env fuel' (peelProofLam args[args.size - 2]!),
          asBoolVal env fuel' (peelProofLam args[args.size - 1]!) with
      | some cond, some thn, some els => some (.select .ne cond (.lit 0) thn els)
      | _, _, _ => none
    else if isConstNamed e ``Decidable.decide && args.size ≥ 2 then
      asBoolVal env fuel' args[args.size - 2]!
    else if isConstNamed e ``Eq && args.size ≥ 2 then
      let lhs := strip args[args.size - 2]!
      let rhs := strip args[args.size - 1]!
      if isConstNamed rhs ``Bool.true then asBoolVal env fuel' lhs
      else if isConstNamed lhs ``Bool.true then asBoolVal env fuel' rhs
      else if isConstNamed rhs ``Bool.false then
        (asBoolVal env fuel' lhs).map fun v => .select .eq v (.lit 0) (.lit 1) (.lit 0)
      else if isConstNamed lhs ``Bool.false then
        (asBoolVal env fuel' rhs).map fun v => .select .eq v (.lit 0) (.lit 1) (.lit 0)
      else
        (asCmp env e).map fun (cmp, lhs, rhs) => .select cmp lhs rhs (.lit 1) (.lit 0)
    else
      match asCmp env e with
      | some (cmp, lhs, rhs) => some (.select cmp lhs rhs (.lit 1) (.lit 0))
      | none =>
        match e.getAppFn.constName? with
        | some name =>
          match env.find? name with
          | some (.defnInfo info) =>
            let rec resultType (fuel : Nat) (type : Expr) : Expr :=
              match fuel with
              | 0 => type
              | fuel' + 1 =>
                match strip type with
                | .forallE _ _ body _ => resultType fuel' body
                | type => type
            if (resultType 16 info.type).getAppFn.constName? == some ``Bool then
              asBoolVal env fuel' (info.value.beta args)
            else none
          | _ => none
        | none => none

private def asCondition (env : Environment) (e : Expr) : Option (Ops.Cmp × Ops.Val × Ops.Val) :=
  -- Bounded tree guards can contain several nested projected lookups. Keep ordinary value
  -- decoding conservative, but let an explicit control-flow boundary finish that finite tree.
  asCmp env e <|> asCmpCoreWithFuel env 128 e <|>
    (asBoolVal env 64 e).map fun value => (.ne, value, .lit 0)

/-- `x ≥ y` / `y ≤ x`  →  checked sub x y。`x ≤ lit` 是上界（255 / u64Max），不是 sub。 -/
private def asCheckedSubGuard (env : Environment) (e : Expr) : Option (Ops.Val × Ops.Val) :=
  match asCmp env e with
  | some (.le, _, .lit _) => none
  | some (.le, rhs, lhs) => some (lhs, rhs)
  | some (.ge, lhs, rhs) => some (lhs, rhs)
  | _ => none

/-- `den ≠ 0` 才是除法守卫。两边都是字面量的 `0 ≠ 1` 不算。 -/
private def asNeZero (env : Environment) (e : Expr) : Option Ops.Val :=
  match asCmp env e with
  | some (.ne, .lit _, .lit _) => none
  | some (.ne, v, .lit 0) => some v
  | some (.ne, .lit 0, v) => some v
  | _ => none

private def asEqZero (env : Environment) (e : Expr) : Option Ops.Val :=
  match asCmp env e with
  | some (.eq, v, .lit 0) => some v
  | some (.eq, .lit 0, v) => some v
  | _ => none

/-- 多字段 `State.mk a b …`：init 用第一个显式参数；checked 更新用最后一个。 -/
private def asStateMk (env : Environment) (e : Expr) (preferLast := false) : Option Ops.Val :=
  let e := strip e
  if isConstNamed e ``Prod.mk || endsWith e ".Prod.mk" then none
  else if endsWith e ".State.mk" || endsWith e ".mk" then
    let args := e.getAppArgs
    if args.size = 0 then none
    else if preferLast then val env args[args.size - 1]!
    else
      match args.findSome? (val env) with
      | some v => some v
      | none => val env args[args.size - 1]!
  else none

private def asOptionPayload (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := strip e
  if isConstNamed e ``Option.none || endsWith e ".none" then
    some (.lit 0)
  else if isConstNamed e ``Option.some || endsWith e ".some" then
    let args := e.getAppArgs
    if args.size ≥ 1 then val env args[args.size - 1]! else none
  else
    match e.getAppFn.constName? with
    | some ctor =>
      match env.find? ctor with
      | some (.ctorInfo c) =>
        if isOptionLikeInductive env c.induct || isEnumLeaf env c.induct then
          match enumCtorIndex env c.induct ctor with
          | some 0 => some (.lit 0)
          | some _ =>
            if c.numFields == 0 then some (.lit 1)
            else if e.getAppArgs.size ≥ 1 then val env e.getAppArgs[e.getAppArgs.size - 1]!
            else none
          | none => none
        else none
      | _ => none
    | none => none

/-- Preserve the constructor discriminant when an Option-like value becomes storage leaves. -/
private def asOptionStorage (env : Environment) (e : Expr) : Option (Ops.Val × Ops.Val) :=
  let e := strip e
  if isConstNamed e ``Option.none || endsWith e ".none" then
    some (.lit 0, .lit 0)
  else if isConstNamed e ``Option.some || endsWith e ".some" then
    let args := e.getAppArgs
    if args.size ≥ 1 then
      (val env args[args.size - 1]!).map fun payload => (.lit 1, payload)
    else none
  else
    match e.getAppFn.constName? with
    | some ctor =>
      match env.find? ctor with
      | some (.ctorInfo info) =>
        if isOptionLikeInductive env info.induct then
          match enumCtorIndex env info.induct ctor with
          | some 0 => some (.lit 0, .lit 0)
          | some _ =>
            if info.numFields == 0 then some (.lit 1, .lit 1)
            else if e.getAppArgs.size ≥ 1 then
              (val env e.getAppArgs[e.getAppArgs.size - 1]!).map fun payload =>
                (.lit 1, payload)
            else none
          | none => none
        else none
      | _ => none
    | none => none

/-- `#v[a, b, …]` = `Vector.mk (List.toArray (a :: b :: []))`。 -/
private def collectListVals (env : Environment) (fuel : Nat) (e : Expr) : Array Ops.Val :=
  match fuel with
  | 0 => #[]
  | fuel' + 1 =>
    let e := strip e
    if isConstNamed e ``List.nil || endsWith e ".nil" then
      #[]
    else if isConstNamed e ``List.cons || endsWith e ".cons" then
      let args := e.getAppArgs
      if args.size ≥ 2 then
        let head := args[args.size - 2]!
        let tail := args[args.size - 1]!
        match val env head with
        | some v => #[v] ++ collectListVals env fuel' tail
        | none => collectListVals env fuel' tail
      else #[]
    else if isConstNamed e ``List.toArray || endsWith e ".toArray" then
      let args := e.getAppArgs
      if args.size ≥ 1 then collectListVals env fuel' args[args.size - 1]! else #[]
    else
      match val env e with
      | some v => #[v]
      | none => #[]

private def findListVals (env : Environment) (fuel : Nat) (e : Expr) : Option (Array Ops.Val) :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := strip e
    if isConstNamed e ``List.cons || endsWith e ".cons" then
      some (collectListVals env 16 e)
    else
      e.getAppArgs.findSome? (findListVals env fuel')

private def asVectorLits (env : Environment) (e : Expr) : Option (Array Ops.Val) :=
  let e := strip e
  if isConstNamed e ``Vector.mk || endsWith e "Vector.mk" then
    match findListVals env 16 e with
    | some vs => if vs.isEmpty then none else some vs
    | none => none
  else none

/-- `xs.set i v`：只抽出被改的那一叶。 -/
private def asVectorSet (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := strip e
  if isVectorSet e then
    let args := e.getAppArgs
    -- 只认编译期常量下标。运行时下标走 `asIndexSet`。
    -- `Vector.set.{u} α n xs i v h` 里 `n` 是长度，不能当 index。
    let idx? : Option Nat :=
      Id.run do
        let mut seenLen := false
        for a in args do
          match asLit 8 a with
          | some (.lit n) =>
            if !seenLen then
              seenLen := true
            else
              return some n.toNat
          | _ => pure ()
        return none
    -- `Vector.set xs i v h`：值在字面量下标之后。
    -- 嵌套 `Node.mk` 时取被改的那一叶（preferLast）。
    let payload :=
      Id.run do
        let mut seenIdx := false
        for a in args do
          match asLit 8 a with
          | some (.lit _) =>
            seenIdx := true
          | _ =>
            if seenIdx then
              -- `{ s.nodes[0]! with value := v }` 展开成 `have __src := …; Node.mk …`。
              let a := peelLets (strip a)
              match asStateMk env a true with
              | some v => return some (true, v)
              | none =>
                match val env a with
                | some v => return some (false, v)
                | none => pure ()
        return none
    match idx?, payload, vectorBaseName env 16 e with
    | some i, some (true, v), some n => some (.field v s!"{n}_{i}_value")
    | some i, some (false, v), some n => some (.field v s!"{n}_{i}")
    | _, _, _ => none
  else none

/-- `State.mk` 每个字段一个值。`Option` 展开成 tag + payload；`Vector` 展开成各叶。 -/
private def asIndexSets (env : Environment) (e0 : Expr) : Option (Array Ops.Op) :=
  let rec go (fuel : Nat) (e : Expr) : Option Expr :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      match e with
      | .letE _ _ value body _ => go fuel' value <|> go fuel' body
      | .lam _ _ body _ => go fuel' body
      | _ =>
        if isConstNamed e ``Except.ok && e.getAppArgs.size ≥ 1 then
          go fuel' e.getAppArgs[e.getAppArgs.size - 1]!
        else if isConstNamed e ``Prod.mk && e.getAppArgs.size ≥ 2 then
          go fuel' e.getAppArgs[e.getAppArgs.size - 2]!
        else if isVectorSet e then
          some e
        else
          e.getAppArgs.findSome? (go fuel')
  match go 8 e0 with
  | none => none
  | some e =>
  if isVectorSet e then
    let args := e.getAppArgs
    let lits := args.filterMap (asLit 8)
    let len :=
      if h : lits.size > 0 then
        match lits[0] with
        | .lit n => n.toNat
        | _ => 0
      else 0
    -- `Vector.set α n xs i v h`：最后四项固定为 xs、下标、新元素、证明。
    -- 不要扫描证明参数；其中的局部 binder 不是源程序的动态下标。
    let parsed :=
      Id.run do
        if h : args.size ≥ 4 then
          let idx? := val env args[args.size - 3]
          let payload := substLets 8 (peelLets (strip args[args.size - 2]))
          let isCtor :=
            match payload.getAppFn.constName? with
            | some n =>
              match env.find? n with
              | some (.ctorInfo _) => true
              | _ => false
            | none => false
          if isCtor || isIteExpr payload then return (false, idx?, some payload, none)
          else return (false, idx?, none, val env payload)
        else
          return (false, none, none, none)
    let rec changedLeaves (selfIdx : Option Ops.Val) (fuel : Nat) (e : Expr) :
        Array (String × Ops.Val) :=
      match fuel with
      | 0 => #[]
      | fuel' + 1 =>
        let e := substLets 16 (strip e)
        match e.getAppFn.constName? with
        | some n =>
          match env.find? n with
          | some (.ctorInfo c) =>
            if isUserType env c.induct && isStructure env c.induct then
              let names := getStructureFields env c.induct
              let args := e.getAppArgs
              let nF := names.size
              if nF == 0 || args.size < nF then #[]
              else
                -- `{ src with left := a, parent := b }`：叶来自别的节点 / 别的字段就算改了。
                -- `y.parent := x.parent` 两边都叫 parent，不能只看字段名。
                Id.run do
                  let mut acc : Array (String × Ops.Val) := #[]
                  for i in [0:nF] do
                    if h : i < nF ∧ i < args.size then
                      let fname := names[i].toString
                      let arg := substLets 8 (strip args[args.size - nF + i])
                      let looksSame :=
                        match val env arg with
                        | some (.field (.arg _) n) =>
                          n == fname || n.endsWith ("_" ++ fname)
                        | some (.field (.indexGet _ _ i _ _) leaf) =>
                          -- 同一下标上的同一逻辑叶才算没改。
                          (leaf == fname || leaf.endsWith ("_" ++ fname)) &&
                            (match selfIdx with
                             | some j => i == j
                             | none => true)
                        | _ => false
                      unless looksSame do
                        match val env arg with
                        | some v => acc := acc.push (fname, v)
                        | none => pure ()
                  return acc
            else
              e.getAppArgs.foldl (init := #[]) fun a x =>
                a ++ changedLeaves selfIdx fuel' x
          | _ => e.getAppArgs.foldl (init := #[]) fun a x =>
              a ++ changedLeaves selfIdx fuel' x
        | none => e.getAppArgs.foldl (init := #[]) fun a x =>
            a ++ changedLeaves selfIdx fuel' x
    match parsed with
    | (true, _, _, _) => none
    | (false, some idx, some payloadE, _) =>
      match idx with
      | .lit _ => none
      | _ =>
        match vectorBaseName env 16 e with
        | none => none
        | some name =>
          let payloadOps (payload : Expr) : Array Ops.Op :=
            match asUInt64VariantCtor env payload with
            | some (tag, payloads, payloadWidth) => Id.run do
              let mut ops : Array Ops.Op := #[.indexSetLeaf name idx (.lit tag) len "tag"]
              for offset in [:payloadWidth] do
                ops := ops.push (.indexSetLeaf name idx
                  (payloads[offset]?.getD (.lit 0)) len s!"p{offset}")
              return ops
            | none =>
              let leaves := changedLeaves (some idx) 8 payload
              let leaves :=
                if leaves.isEmpty then
                  match val env payload with
                  | some v => #[("", v)]
                  | none => #[]
                else leaves
              leaves.map fun p => (.indexSetLeaf name idx p.2 len p.1 : Ops.Op)
          if isIteExpr payloadE then
            let args := payloadE.getAppArgs
            let peelProofLam (branch : Expr) : Expr :=
              match strip branch with
              | .lam _ _ body _ => substLets 16 (body.lowerLooseBVars 1 1)
              | branch => substLets 16 branch
            if args.size < 2 then none
            else
              match args.findSome? (asCondition env) with
              | none => none
              | some (cmp, lhs, rhs) =>
                let thn := payloadOps (peelProofLam args[args.size - 2]!)
                let els := payloadOps (peelProofLam args[args.size - 1]!)
                if thn.isEmpty && els.isEmpty then none else some #[.ite cmp lhs rhs thn els]
          else
            let ops := payloadOps payloadE
            if ops.isEmpty then none else some ops
    | (false, some idx, none, some payload) =>
      match idx with
      | .lit _ => none
      | _ =>
        match vectorBaseName env 16 e with
        | some name => some #[.indexSetLeaf name idx payload len]
        | none => none
    | _ => none
  else none

private def asIndexSet (env : Environment) (e0 : Expr) : Option Ops.Op :=
  match asIndexSets env e0 with
  | some ops => ops[0]?
  | none => none

private def peelForalls (e : Expr) : Expr :=
  let rec go (fuel : Nat) (e : Expr) : Expr :=
    match fuel with
    | 0 => e
    | fuel' + 1 =>
      match strip e with
      | .forallE _ _ body _ => go fuel' body
      | e => e
  go 32 e

private def fieldTypeExpr (env : Environment) (structName fieldName : Name) : Option Expr :=
  match getProjFnForField? env structName fieldName with
  | none => none
  | some proj =>
    match env.find? proj with
    | none => none
    | some info => some (peelForalls info.type)

private partial def collectListExprs (fuel : Nat) (e : Expr) : Option (Array Expr) :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := strip e
    if isConstNamed e ``List.nil || endsWith e ".nil" then
      some #[]
    else if isConstNamed e ``List.cons || endsWith e ".cons" then
      let args := e.getAppArgs
      if args.size < 2 then none
      else do
        let tail ← collectListExprs fuel' args[args.size - 1]!
        return #[args[args.size - 2]!] ++ tail
    else if isConstNamed e ``List.toArray || endsWith e ".toArray" then
      let args := e.getAppArgs
      if args.isEmpty then none else collectListExprs fuel' args[args.size - 1]!
    else
      e.getAppArgs.findSome? (collectListExprs fuel')

private def vectorElements (e : Expr) : Option (Array Expr) :=
  let e := strip e
  if isConstNamed e ``Vector.mk || endsWith e "Vector.mk" then
    collectListExprs 32 e
  else none

private def unfoldNullaryValue? (env : Environment) (e : Expr) : Option Expr :=
  let e := strip e
  if !e.getAppArgs.isEmpty then none
  else do
    let name ← e.getAppFn.constName?
    let .defnInfo info ← env.find? name | none
    return info.value

/-- Explicit source fields of one user-defined structure constructor. -/
private def userCtorFields (env : Environment) (e : Expr) : Option (Array Expr) :=
  let e := peelLets (strip e)
  match e.getAppFn.constName? with
  | none => none
  | some n =>
    match env.find? n with
    | some (.ctorInfo c) =>
      if isUserType env c.induct && isStructure env c.induct then
        let args := e.getAppArgs
        if args.size ≥ c.numFields then
          some (args.extract (args.size - c.numFields) args.size)
        else none
      else none
    | _ => none

/-- Flatten an initializer from its source type, producing exactly one value per schema leaf. -/
private partial def flattenInitValue (env : Environment) (fuel : Nat) (ty e : Expr) :
    Option (Array Ops.Val) :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := substLets 32 (strip e)
    match unfoldNullaryValue? env e with
    | some body => flattenInitValue env fuel' ty body
    | none =>
      let ty := strip ty
      let tyName? := ty.getAppFn.constName?
      if tyName? == some ``UInt64 || tyName? == some ``UInt32 ||
          tyName? == some ``UInt16 || tyName? == some ``UInt8 then
        (val env e).map (#[·])
      else if tyName? == some ``Bool then
        if isConstNamed e ``Bool.true || endsWith e ".true" then some #[.lit 1]
        else if isConstNamed e ``Bool.false || endsWith e ".false" then some #[.lit 0]
        else (val env e).map (#[·])
      else if tyName? == some ``Option then
        (asOptionStorage env e).map fun (tag, payload) => #[tag, payload]
      else if tyName? == some ``Vector then
        let tyArgs := ty.getAppArgs
        if tyArgs.size < 2 then none
        else
          match asLit 8 tyArgs[tyArgs.size - 1]!, vectorElements e with
          | some (.lit length), some elements =>
            if elements.size != length.toNat then none
            else Id.run do
              let mut values : Array Ops.Val := #[]
              for h : i in [:elements.size] do
                let some item := flattenInitValue env fuel' tyArgs[tyArgs.size - 2]! elements[i]
                  | return none
                values := values ++ item
              return some values
          | _, _ => none
      else if let some tyName := tyName? then
        if isEnumLeaf env tyName then
          match e.getAppFn.constName? with
          | some ctor => (enumCtorIndex env tyName ctor).map fun index => #[.lit (UInt64.ofNat index)]
          | none => none
        else if isUInt64Newtype env tyName then
          (val env e).map (#[·])
        else if isOptionLikeInductive env tyName then
          (asOptionStorage env e).map fun (tag, payload) => #[tag, payload]
        else if let some payloadWidth := uint64VariantPayloadWidth? env tyName then
          match asUInt64VariantCtor env e with
          | none => none
          | some (tag, payloads, _) =>
            Id.run do
              let mut values := #[.lit tag]
              for index in [:payloadWidth] do
                values := values.push (payloads[index]?.getD (.lit 0))
              return some values
        else if isUserName env tyName && isStructure env tyName then
          match userCtorFields env e with
          | none => none
          | some fields =>
            let names := getStructureFields env tyName
            if fields.size != names.size then none
            else Id.run do
              let mut values : Array Ops.Val := #[]
              for h : i in [:fields.size] do
                let some fieldTy := fieldTypeExpr env tyName names[i]! | return none
                let some fieldValues := flattenInitValue env fuel' fieldTy fields[i] | return none
                values := values ++ fieldValues
              return some values
        else none
      else none

private def asStateFields (env : Environment) (e : Expr) : Option (Array Ops.Val) := do
  let fields ← userCtorFields env (substLets 32 e)
  let ctor ← (substLets 32 e).getAppFn.constName?
  let .ctorInfo info ← env.find? ctor | none
  let names := getStructureFields env info.induct
  if fields.size != names.size then none else pure ()
  let mut values : Array Ops.Val := #[]
  for h : i in [:fields.size] do
    let fieldTy ← fieldTypeExpr env info.induct names[i]!
    let fieldValues ← flattenInitValue env 32 fieldTy fields[i]
    values := values ++ fieldValues
  return values

private def looksUnchangedField (v : Ops.Val) (leaf : String) : Bool :=
  match v with
  | .field _ n =>
    n == leaf || n.endsWith ("_" ++ leaf) || leaf.endsWith ("_" ++ n)
  | _ => false

/-- 把一个值摊成账户叶。`Vector.set` / 嵌套 `with` 只展开被改的那些。 -/
private partial def flattenLeaves (env : Environment) (base : String) (e : Expr)
    (appliedBases : Array Expr := #[]) : Array (String × Ops.Val) :=
  let e := peelLets (strip e)
  if isVectorSet e then
    let args := e.getAppArgs
    -- `Vector.set α n xs i v h`：第一个字面量是长度，第二个是下标。
    -- 长度之后的第一个非字面量是旧向量，两下标之后才是新元素。
    let parsed :=
      Id.run do
        let mut nLits : Nat := 0
        let mut xs? : Option Expr := none
        let mut idx? : Option Nat := none
        let mut payload? : Option Expr := none
        for a in args do
          if endsWith a "._proof_1" || endsWith a "._proof_2" || endsWith a ".rfl" then
            pure ()
          else
            match asLit 8 a with
            | some (.lit n) =>
              if nLits == 0 then
                nLits := 1
              else if nLits == 1 then
                nLits := 2
                idx? := some n.toNat
              else
                pure ()
            | some _ =>
              pure ()
            | none =>
              if nLits == 1 && xs?.isNone then
                xs? := some (peelLets (strip a))
              else if nLits ≥ 2 && payload?.isNone then
                payload? := some (peelLets (strip a))
        return (idx?, xs?, payload?)
    match parsed with
    | (some i, xs?, some payload) =>
      let pre := if base.isEmpty then s!"{i}" else s!"{base}_{i}"
      let here := flattenLeaves env pre payload appliedBases
      let here :=
        if here.isEmpty then
          match val env payload with
          | some v => #[(pre, v)]
          | none => #[]
        else here
      let prev :=
        match xs? with
        | some xs => flattenLeaves env base xs appliedBases
        | none => #[]
      prev ++ here
    | _ => #[]
  else if let some fields := userCtorFields env e then
    match e.getAppFn.constName? with
    | none => #[]
    | some n =>
      match env.find? n with
      | some (.ctorInfo c) =>
        let names := getStructureFields env c.induct
        Id.run do
          let mut acc : Array (String × Ops.Val) := #[]
          for i in [0:fields.size] do
            if h : i < names.size ∧ i < fields.size then
              let fname := names[i].toString
              let child := if base.isEmpty then fname else s!"{base}_{fname}"
              let arg := fields[i]
              let inheritedFromAppliedBase :=
                match (peelLets (strip arg)).getAppFn.constName? with
                | some projection =>
                  match env.getProjectionFnInfo? projection with
                  | some info =>
                    let args := (peelLets (strip arg)).getAppArgs
                    info.ctorName == n && info.i == i &&
                      (args[args.size - 1]?.map appliedBases.contains).getD false
                  | none => false
                | none => false
              -- A payload constructor is one typed variant field, not a nested scalar
              -- expression whose first argument can stand in for the whole field.
              let nested :=
                if (asUInt64VariantCtor env arg).isSome || (asOptionStorage env arg).isSome then #[]
                else flattenLeaves env child arg appliedBases
              let isVectorField :=
                match env.find? (c.induct.str fname) with
                | some info => info.type.getUsedConstantsAsSet.toList.any (· == ``Vector)
                | none => false
              -- Inner transitions represented by `appliedBases` were already lowered. A direct
              -- projection only inherits that field; reducing it through the constructor would
              -- replay a transition rather than describe an outer write.
              if inheritedFromAppliedBase then
                pure ()
              else if !nested.isEmpty then
                acc := acc ++ nested.filter fun p => !looksUnchangedField p.2 p.1
              else if isVectorField then
                -- A runtime-indexed vector is represented only by typed indexSet writes.
                -- Its root projection is not a scalar account leaf.
                pure ()
              else
                match asUInt64VariantCtor env arg with
                | some (tag, payloads, payloadWidth) =>
                  acc := acc.push (s!"{child}_tag", .lit tag)
                  for index in [:payloadWidth] do
                    acc := acc.push
                      (s!"{child}_p{index}", payloads[index]?.getD (.lit 0))
                | none =>
                  match asOptionStorage env arg with
                  | some (tag, payload) =>
                    acc := acc.push (s!"{child}_tag", tag) |>.push (s!"{child}_p0", payload)
                  | none =>
                    match val env arg with
                    | some v =>
                      unless looksUnchangedField v child || looksUnchangedField v fname do
                        acc := acc.push (child, v)
                    | none =>
                      if isConstNamed arg ``Bool.true || endsWith arg ".true" then
                        acc := acc.push (child, .lit 1)
                      else if isConstNamed arg ``Bool.false || endsWith arg ".false" then
                        acc := acc.push (child, .lit 0)
                      else
                        match arg.getAppFn.constName? with
                        | some ctor =>
                          match env.find? ctor with
                          | some (.ctorInfo info) =>
                            -- A payload variant must be flattened into its typed tag/payload
                            -- leaves. Falling back to the constructor index would create a raw
                            -- store for the non-leaf parent and silently discard its payload.
                            if (uint64VariantPayloadWidth? env info.induct).isNone then
                              match enumCtorIndex env info.induct ctor with
                              | some k => acc := acc.push (child, .lit (UInt64.ofNat k))
                              | none => pure ()
                          | _ => pure ()
                        | none =>
                          match asLit 8 arg with
                          | some v => acc := acc.push (child, v)
                          | none => pure ()
          acc
      | _ => #[]
  else
    match val env e with
    | some v =>
      if base.isEmpty || looksUnchangedField v base then #[] else #[(base, v)]
    | none => #[]

/-- `Except.ok (State.mk …, ret)`：按叶 diff，改了几个槽就写几条。 -/
private def asStoreFields (env : Environment) (e : Expr)
    (includeSingle : Bool := false) : Option (Array Ops.Op) :=
  -- Preserve the RHS of `let next := ...` before peeling the state constructor. Dropping a used
  -- scalar binder turns `next` into an unrelated outer `.arg` and silently stores the wrong value.
  let e := peelControl 8 (substUInt64Lets 64 (dropUnusedHeadLets 32 e))
  if isConstNamed e ``Except.ok then
    let args := e.getAppArgs
    if args.size ≥ 1 then
      let pair := strip args[args.size - 1]!
      if isConstNamed pair ``Prod.mk && pair.getAppArgs.size ≥ 2 then
        let st := pair.getAppArgs[pair.getAppArgs.size - 2]!
        let ret := pair.getAppArgs[pair.getAppArgs.size - 1]!
        let vectorBase := vectorBaseName env 32 st
        let leaves := (flattenLeaves env "" st).filter fun p => some p.1 != vectorBase
        let explicitSingle := includeSingle || containsUInt64NewtypeCtor env 16 st
        if leaves.isEmpty || (!explicitSingle && leaves.size == 1) then none
        else
          match val env ret with
          | none => none
          | some rv =>
            some ((leaves.map fun p => (.storeField p.1 p.2 : Ops.Op)).push (.okState rv))
      else none
    else none
  else none

private def asOkStateCore (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := peelControl 8 (dropUnusedHeadLets 32 e)
  if isConstNamed e ``Except.ok then
    let args := e.getAppArgs
    if args.size ≥ 1 then
      let pair := strip args[args.size - 1]!
      if isConstNamed pair ``Prod.mk then
        let pargs := pair.getAppArgs
        if pargs.size ≥ 2 then
          let st := pargs[pargs.size - 2]!
          let boolLit :=
            (strip st).getAppArgs.findSome? fun a =>
              if isConstNamed a ``Bool.true || endsWith a ".true" then some (.lit 1)
              else if isConstNamed a ``Bool.false || endsWith a ".false" then some (.lit 0)
              else none
          match boolLit with
          | some v => some v
          | none =>
          match asOptionPayload env st with
          | some v => some v
          | none =>
            -- `{ s with nodes := s.nodes.set i { … with value := v } }`
            -- 展开成 `State.mk s.root s.size (Vector.set …)`。`val` 会先吃到
            -- `s.root`，必须先认嵌套 Vector.set，否则 dest 落到错误槽。
            match asVectorSet env (strip st) <|>
                (strip st).getAppArgs.findSome? (asVectorSet env) with
            | some v => some v
            | none =>
            match val env st with
            | some (.clockSlot) => some .clockSlot
            | some (.clockEpoch) => some .clockEpoch
            | some (.unixTime) => some .unixTime
            | some (.slotsPerEpoch) => some .slotsPerEpoch
            | some (.cpiReturn) => some .cpiReturn
            | some (.signerKey0) => some .signerKey0
            | some (.accLamports0) => some .accLamports0
            | some (.accOwner0) => some .accOwner0
            | some (.accDataLen0) => some .accDataLen0
            | some (.accN) => some .accN
            | some (.isSigner0) => some .isSigner0
            | some (.isWritable0) => some .isWritable0
            | some (.isExecutable0) => some .isExecutable0
            | some (.accLamports1) => some .accLamports1
            | some (.accOwner1) => some .accOwner1
            | some (.accDataLen1) => some .accDataLen1
            | some (.isSigner1) => some .isSigner1
            | some (.isWritable1) => some .isWritable1
            | some (.isExecutable1) => some .isExecutable1
            | some (.findPda s) => some (.findPda s)
            | some (.checkPda s b) => some (.checkPda s b)
            | some (.rentExemption n) => some (.rentExemption n)
            | some (.sha256Lit s) => some (.sha256Lit s)
            | some (.keccak256Lit s) => some (.keccak256Lit s)
            | some (.accKeyWord a w) => some (.accKeyWord a w)
            | some (.accOwnerWord a w) => some (.accOwnerWord a w)
            | some (.accLamportsN a) => some (.accLamportsN a)
            | some (.accDataLenN a) => some (.accDataLenN a)
            | some (.isSignerN a) => some (.isSignerN a)
            | some (.isWritableN a) => some (.isWritableN a)
            | some (.isExecutableN a) => some (.isExecutableN a)
            | some (.signerKeyN a) => some (.signerKeyN a)
            | some (.ownerIsSelf a) => some (.ownerIsSelf a)
            | some v =>
              if Ops.hasEvmLeaf #[.returnU64 v] || Ops.isLangLeaf v then some v else none
            | _ =>
              match asVectorSet env (strip st) <|>
                  (strip st).getAppArgs.findSome? (asVectorSet env) with
              | some v => some v
              | none =>
                match asStateMk env st true with
                | some v => some v
                | none =>
                  let args := (strip st).getAppArgs
                  args.findSome? (asOptionPayload env) <|> asStateMk env st true
        else none
      else asStateMk env pair true
    else none
  else none

private def asOkState (env : Environment) (e : Expr) : Option Ops.Val :=
  match asOkStateCore env e with
  | result@(some (.field _ field)) =>
      let projectionScalar? := e.getUsedConstantsAsSet.toList.findSome? fun name =>
        if Core.IR.lastName name.toString != field || (env.getProjectionFnInfo? name).isNone then none
        else (env.find? name).map fun info => isScalarResult env info.type
      -- A structure/variant projection cannot be the scalar result of a mutating method. Let the
      -- full state decoder handle that branch instead of selecting an arbitrary constructor field.
      if projectionScalar? == some false then none else result
  | result => result

/-- Scalar `Except.ok` is an intermediate value producer, not a state commit. -/
private def asOkScalar (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := peelControl 8 (dropUnusedHeadLets 32 e)
  if isConstNamed e ``Except.ok then
    let args := e.getAppArgs
    if h : args.size > 0 then
      let payload := strip args[args.size - 1]
      if isConstNamed payload ``Prod.mk then none else val env payload
    else none
  else none

/-- `.ok (s, value)` with the original state is a successful no-op, not an implicit write. -/
private def asOkNoop (env : Environment) (e : Expr) : Option Ops.Val :=
  let e := peelControl 8 (dropUnusedHeadLets 32 e)
  if isConstNamed e ``Except.ok then
    let args := e.getAppArgs
    if h : args.size > 0 then
      let pair := strip args[args.size - 1]
      if isConstNamed pair ``Prod.mk then
        let pairArgs := pair.getAppArgs
        if h : pairArgs.size ≥ 2 then
          match strip pairArgs[pairArgs.size - 2] with
          | .bvar _ => val env pairArgs[pairArgs.size - 1]
          | state =>
            if isConstNamed state ``methodArgRef then val env pairArgs[pairArgs.size - 1]
            else
              let reconstructedFromOneBinder :=
                match userCtorFields env state with
                | some fields =>
                    !fields.isEmpty && fields.all fun value =>
                      let args := (strip value).getAppArgs
                      if h : args.size > 0 then
                        match strip args[args.size - 1] with
                        | .bvar _ => true
                        | _ => false
                      else false
                | none => false
              if reconstructedFromOneBinder then val env pairArgs[pairArgs.size - 1]
              else none
        else none
      else none
    else none
  else none

private def errorCtorName (e : Expr) : Option String :=
  let e := peelControl 8 e
  if isConstNamed e ``Except.error then
    let args := e.getAppArgs
    if h : args.size > 0 then
      let ctor := strip args[args.size - 1]
      match ctor.getAppFn.constName? with
      | some n =>
        let last := Core.IR.lastName n.toString
        if last == "overflow" then none else some last
      | none => none
    else none
  else none

private def isErrorOverflow (e : Expr) : Bool :=
  let e := peelControl 8 e
  if isConstNamed e ``Except.error then
    let args := e.getAppArgs
    if h : args.size > 0 then
      endsWith (strip args[args.size - 1]) ".overflow"
    else false
  else false

private def returnStatesOf (vs : Array Ops.Val) : Array Ops.Op :=
  vs.map fun value => .returnState value

private def isRuntimeName (n : Name) (suf : String) : Bool :=
  n == (`ProofForge.Svm.Runtime).append suf.toName ||
    n == (`ProofForge.Evm.Runtime).append suf.toName ||
    n.toString.endsWith s!".{suf}"

private def mentionsRuntime (e : Expr) (suf : String) : Bool :=
  let suf := if suf.front == '.' then String.ofList (suf.toList.drop 1) else suf
  e.getUsedConstantsAsSet.toList.any (isRuntimeName · suf)

/-- Runtime CPI wrappers are unfolded by namespace, not by an ever-growing list of recipe names. -/
private def mentionsSvmRuntime (e : Expr) : Bool :=
  e.getUsedConstantsAsSet.toList.any fun name =>
    name.toString.startsWith "ProofForge.Svm.Runtime."

private def natOfVal : Ops.Val → Option Nat
  | .lit n => some n.toNat
  | _ => none

private def asBoolLit (e : Expr) : Option Bool :=
  if isConstNamed e ``Bool.true || endsWith e ".true" then some true
  else if isConstNamed e ``Bool.false || endsWith e ".false" then some false
  else none

/-- A statically shaped `CpiMeta`, including its optional exact account-data length. -/
private def asCpiMeta (env : Environment) (e : Expr) : Option Ops.CpiMeta :=
  let e := strip e
  if isConstNamed e ``ProofForge.Svm.Runtime.CpiMeta.mk || endsWith e ".mk" then
    let args := e.getAppArgs
    if args.size ≥ 4 then
      let lenExpr := strip args[args.size - 1]!
      let expectedDataLen : Option (Option Nat) :=
        if isConstNamed lenExpr ``Option.none || endsWith lenExpr ".none" then
          some none
        else if (isConstNamed lenExpr ``Option.some || endsWith lenExpr ".some") &&
            lenExpr.getAppArgs.size ≥ 1 then
          (natOfVal <$> val env lenExpr.getAppArgs[lenExpr.getAppArgs.size - 1]!)
        else none
      match val env args[args.size - 4]!, asBoolLit args[args.size - 3]!,
          asBoolLit args[args.size - 2]!, expectedDataLen with
      | some accV, some signer, some writable, some expectedDataLen =>
        match natOfVal accV with
        | some acc => some { acc, signer, writable, expectedDataLen }
        | none => none
      | _, _, _, _ => none
    else none
  else none

private def asCpiWord (env : Environment) (e : Expr) : Option Ops.CpiWord :=
  let e := strip e
  if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.u8le || endsWith e ".u8le" then
    if e.getAppArgs.size ≥ 1 then
      match val env e.getAppArgs[e.getAppArgs.size - 1]! with
      | some value => some (.u8le value)
      | none => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.u16le || endsWith e ".u16le" then
    if e.getAppArgs.size ≥ 1 then
      match val env e.getAppArgs[e.getAppArgs.size - 1]! with
      | some value => some (.u16le value)
      | none => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.u32le || endsWith e ".u32le" then
    if e.getAppArgs.size ≥ 1 then
      match val env e.getAppArgs[e.getAppArgs.size - 1]! with
      | some value => some (.u32le value)
      | none => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.u64le || endsWith e ".u64le" then
    if e.getAppArgs.size ≥ 1 then
      match val env e.getAppArgs[e.getAppArgs.size - 1]! with
      | some v => some (.u64le v)
      | none => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.selfEntry then
    let args := e.getAppArgs
    if args.size ≥ 2 then
      match val env args[args.size - 2]! >>= natOfVal, strip args[args.size - 1]! with
      | some tag, .lit (.strVal authoritySeed) =>
          some (.selfEntry (UInt64.ofNat tag) authoritySeed)
      | _, _ => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.ascii || endsWith e ".ascii" then
    if e.getAppArgs.size ≥ 1 then
      match e.getAppArgs[e.getAppArgs.size - 1]! with
      | .lit (.strVal s) => some (.ascii s)
      | _ => none
    else none
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.programId || endsWith e ".programId" then
    some .programId
  else if isConstNamed e ``ProofForge.Svm.Runtime.CpiWord.accKey || endsWith e ".accKey" then
    if e.getAppArgs.size ≥ 1 then
      match val env e.getAppArgs[e.getAppArgs.size - 1]! >>= natOfVal with
      | some i => some (.accKey i)
      | none => none
    else none
  else none

/-- `#[a, b, …]` 展开成 `Array.mk [a, b, …]` / `List.cons`。 -/
private def asArrayElems (e : Expr) : Option (Array Expr) :=
  let rec fromList (fuel : Nat) (e : Expr) (acc : Array Expr) : Option (Array Expr) :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if isConstNamed e ``List.nil then some acc
      else if isConstNamed e ``List.cons && e.getAppArgs.size ≥ 2 then
        let args := e.getAppArgs
        fromList fuel' args[args.size - 1]! (acc.push args[args.size - 2]!)
      else none
  let e := strip e
  -- Keep a bounded decoder for compile-time payloads while allowing realistic event records.
  if isConstNamed e ``Array.mk && e.getAppArgs.size ≥ 1 then
    fromList 256 e.getAppArgs[e.getAppArgs.size - 1]! #[]
  else if isConstNamed e ``List.toArray && e.getAppArgs.size ≥ 1 then
    fromList 256 e.getAppArgs[e.getAppArgs.size - 1]! #[]
  else if isConstNamed e ``Array.empty || endsWith e ".empty" then
    some #[]
  else none

private def decodeMetasData (env : Environment) (metaE dataE : Expr) :
    Option (Array Ops.CpiMeta × Array Ops.CpiWord) :=
  match asArrayElems metaE, asArrayElems dataE with
  | some metaEs, some dataEs =>
    Id.run do
      let mut metas : Array Ops.CpiMeta := #[]
      for me in metaEs do
        match asCpiMeta env me with
        | none => return none
        | some m => metas := metas.push m
      let mut data : Array Ops.CpiWord := #[]
      for de in dataEs do
        match asCpiWord env de with
        | none => return none
        | some w => data := data.push w
      some (metas, data)
  | _, _ => none

private def asAsciiLit (e : Expr) : Option String :=
  match strip e with
  | .lit (.strVal s) => if s.isEmpty then none else some s
  | _ => none

private abbrev DecodedInvoke :=
  Nat × Array Ops.CpiMeta × Array Ops.CpiWord × Array Ops.PdaSeed × Option Ops.Val

/-- Extracted static program, metas, data, non-bump signer seeds, and optional bump. -/
private def decodeInvokeArgs (env : Environment) (e : Expr) :
    Option DecodedInvoke :=
  let e := strip e
  if isConstNamed e ``ProofForge.Svm.Runtime.invokeSignedSeeds ||
      endsWith e ".invokeSignedSeeds" then
    let args := e.getAppArgs
    if args.size < 5 then none
    else
      match val env args[args.size - 5]!,
          decodeMetasData env args[args.size - 4]! args[args.size - 3]!,
          asPdaSeeds args[args.size - 2]!,
          val env args[args.size - 1]! with
      | some progV, some (metas, data), some seeds, some bump =>
        match natOfVal progV with
        | some prog => some (prog, metas, data, seeds, some bump)
        | none => none
      | _, _, _, _ => none
  else if isConstNamed e ``ProofForge.Svm.Runtime.invokeSigned || endsWith e ".invokeSigned" then
    let args := e.getAppArgs
    if args.size < 5 then none
    else
      match val env args[args.size - 5]!,
          decodeMetasData env args[args.size - 4]! args[args.size - 3]!,
          asAsciiLit args[args.size - 2]!,
          val env args[args.size - 1]! with
      | some progV, some (metas, data), some seed, some bump =>
        match natOfVal progV with
        | some prog => some (prog, metas, data, #[.ascii seed], some bump)
        | none => none
      | _, _, _, _ => none
  else if isConstNamed e ``ProofForge.Svm.Runtime.invoke || endsWith e ".invoke" then
    let args := e.getAppArgs
    if args.size < 3 then none
    else
      match val env args[args.size - 3]!,
          decodeMetasData env args[args.size - 2]! args[args.size - 1]! with
      | some progV, some (metas, data) =>
        match natOfVal progV with
        | some prog => some (prog, metas, data, #[], none)
        | none => none
      | _, _ => none
  else none

/-- 体里任意深度的编译期 `invoke`。包装会 unfold 成这条。 -/
private def findInvoke (env : Environment) (fuel : Nat) (e : Expr) :
    Option DecodedInvoke :=
  let rec go (fuel : Nat) (e : Expr) : Option DecodedInvoke :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := e.consumeMData
      match decodeInvokeArgs env e with
      | some inv => some inv
      | none =>
        -- 非 irreducible 的 Runtime 包装展开成 invoke。
        let unfolded :=
          match e.getAppFn.constName? with
          | none => none
          | some n =>
            if n.getRoot != `ProofForge then none
            else
              match env.find? n with
              | some (.defnInfo info) =>
                -- 空参包装（invokeAcc1）直接取体；有参包装 β 展开。
                if e.getAppArgs.isEmpty then some info.value
                else some (info.value.beta e.getAppArgs)
              | _ => none
        match unfolded with
        | some u => go fuel' u
        | none =>
          match e with
          | .letE _ _ value body _ => go fuel' value <|> go fuel' body
          | .lam _ _ body _ => go fuel' body
          | .app f a => go fuel' f <|> go fuel' a
          | _ => none
  if mentionsSvmRuntime e then
    go fuel e
  else none

/-- Collect consecutive ignored CPI results without collapsing the final state transition. Every
ignored call needs explicit sequencing: recursive invoke search would otherwise retain the CPI
but silently discard a following state write. -/
private def leadingInvokes (env : Environment) (e : Expr) : Array DecodedInvoke × Expr :=
  let rec go (fuel : Nat) (e : Expr) (invokes : Array DecodedInvoke) :
      Array DecodedInvoke × Expr :=
    match fuel with
    | 0 => (invokes, e)
    | fuel' + 1 =>
      match strip e with
      | .letE _ _ value body _ =>
          if body.hasLooseBVar 0 then
            -- Preserve effect order while substituting a compile-time seed recipe used by a
            -- later signed CPI. Other dependent lets retain the established lowering path.
            match asPdaSeeds value with
            | some _ => go fuel' (body.instantiate1 value) invokes
            | none => (invokes, e)
          else
            match findInvoke env 16 value with
            | some invoke => go fuel' (body.instantiate1 value) (invokes.push invoke)
            | none => (invokes, e)
      | _ => (invokes, e)
  go 16 e #[]

private def substLetsPreservingInvokes (env : Environment) (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .letE n ty value body nd =>
      let scalarBinding := ty.consumeMData.getAppFn.constName? == some ``UInt64
      let value := substLetsPreservingInvokes env fuel' value
      let body := substLetsPreservingInvokes env fuel' body
      let structuredState :=
        (ty.consumeMData.getAppFn.constName?.map (isUserType env)).getD false &&
          ((unfoldUserHelper env value).isSome || (userCtorFields env value).isSome ||
            isIteExpr value)
      if (findInvoke env 16 value).isSome || structuredState || scalarBinding then
        .letE n ty value body nd
      else substLetsPreservingInvokes env fuel' (body.instantiate1 value)
    | .lam n ty body bi => .lam n ty (substLetsPreservingInvokes env fuel' body) bi
    | .app _ _ =>
      let rec goApp (n : Nat) (e : Expr) : Expr :=
        match n, strip e with
        | n + 1, .app f a => .app (goApp n f) (substLetsPreservingInvokes env fuel' a)
        | _, e => substLetsPreservingInvokes env fuel' e
      goApp 32 e
    | e => e

private def invokeOps
    (inv : DecodedInvoke)
    (ret : Ops.Val) : Array Ops.Op :=
  let (prog, metas, data, seeds, bump) := inv
  #[.invoke prog metas data seeds bump, .returnU64 ret]

private def invokeOp (inv : DecodedInvoke) : Ops.Op :=
  let (prog, metas, data, seeds, bump) := inv
  .invoke prog metas data seeds bump

/-- `.ok (state, ret)` 的第二元。找不到就 none。 -/
private def findOkRet (env : Environment) (e : Expr) : Option Ops.Val :=
  let rec go (fuel : Nat) (e : Expr) : Option Ops.Val :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if isConstNamed e ``Except.ok && e.getAppArgs.size ≥ 1 then
        let pair := strip e.getAppArgs[e.getAppArgs.size - 1]!
        if isConstNamed pair ``Prod.mk && pair.getAppArgs.size ≥ 2 then
          let ret := pair.getAppArgs[pair.getAppArgs.size - 1]!
          -- Constant evaluation of Runtime stubs must not turn a consumed CPI result into zero.
          if mentionsRuntime ret "invoke" || mentionsRuntime ret "invokeSigned" then none
          else val env ret
        else none
      else
        match e with
        | .letE _ _ value body _ => go fuel' (body.instantiate1 value)
        | .lam _ _ body _ => go fuel' body
        | .app f a => go fuel' f <|> go fuel' a
        | _ => none
  go 16 e

private def invokeRet
    (env : Environment) (e : Expr)
    (inv : DecodedInvoke) :
    Except String Ops.Val :=
  if let some ret := findOkRet env e then
    .ok ret
  else match inv with
  | (2, _, #[.u32le (.lit 2), .u64le amount], #[], none) => .ok amount
  | (2, _, #[.u32le (.lit 0), .u64le amount, .u64le _, .programId], #[], none) => .ok amount
  | (2, _, #[.u32le (.lit 0), .u64le amount, .u64le _, .programId], #[.ascii _], some _) =>
      .ok amount
  | (1, _, #[.u32le (.lit 1), .programId], #[], none) => .ok (.lit 0)
  | (1, _, #[.u32le (.lit 8), .u64le space], #[], none) => .ok space
  | (2, _, #[.u32le (.lit 9), .accKey 0, .u64le _, .ascii "vault", .u64le space, .programId], #[], none) => .ok space
  | (2, _, #[.u32le (.lit 3), .accKey 0, .u64le _, .ascii "vault", .u64le lamports, .u64le _, .programId], #[], none) => .ok lamports
  | (2, _, #[.u32le (.lit 10), .accKey 0, .u64le _, .ascii "vault", .programId], #[], none) => .ok (.lit 0)
  | (3, _, #[.u32le (.lit 11), .u64le lamports, .u64le _, .ascii "vault", .programId], #[], none) => .ok lamports
  | (2, _, #[.u8le (.lit 20), .u8le (.lit 6), .accKey 0, .u8le (.lit 0)], #[], none) => .ok (.lit 0)
  | (2, _, #[.u8le (.lit 17)], #[], none) => .ok (.lit 0)
  -- Statically indexed classic/Token-2022 TransferChecked wrappers return their modeled amount;
  -- the token program may occupy any authenticated external account index.
  | (_, _, #[.u8le (.lit 12), .u64le amount, .u8le _], #[], none) => .ok amount
  | (_, _, #[.u8le (.lit 12), .u64le amount, .u8le _], _, some _) => .ok amount
  | (3, _, #[.u8le (.lit 14), .u64le amount, .u8le _], #[], none) => .ok amount
  | (3, _, #[.u8le (.lit 15), .u64le amount, .u8le _], #[], none) => .ok amount
  | (3, _, #[.u8le (.lit 18), .accKey 0], #[], none) => .ok (.lit 0)
  | (3, _, #[.u8le (.lit 9)], #[], none) => .ok (.lit 0)
  | (4, _, #[.u8le (.lit 13), .u64le amount, .u8le _], #[], none) => .ok amount
  | (3, _, #[.u8le (.lit 10)], #[], none) => .ok (.lit 0)
  | (3, _, #[.u8le (.lit 11)], #[], none) => .ok (.lit 0)
  | (3, _, #[.u8le (.lit 6), .u8le (.lit 0), .u8le (.lit 1), .accKey 2], #[], none) => .ok (.lit 0)
  | (3, _, #[.u8le (.lit 5)], #[], none) => .ok (.lit 0)
  | (2, _, #[.u8le (.lit 21)], #[], none) => .ok .cpiReturn
  | (1, _, #[.ascii "ok"], #[], none) => .ok (.lit 0)
  | (6, _, #[.u8le (.lit 1)], #[], none) => .ok (.lit 0)
  | (programIx, _, _, _, _) =>
      .error s!"extract/unsupported: unknown CPI return semantics for program {programIx}"

private def invokeOpsWithRet
    (env : Environment) (e : Expr)
    (inv : DecodedInvoke) :
    Except String (Array Ops.Op) := do
  return invokeOps inv (← invokeRet env e inv)

private def forRangeEnd (e : Expr) : Option Nat :=
  let rec rangeEnd (fuel : Nat) (e : Expr) : Option Nat :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if endsWith e ".mk" || e.getAppFn.constName?.isSome then
        let rargs := e.getAppArgs
        if rargs.size ≥ 2 then
          match asLit 8 rargs[1]! with
          | some (.lit n) => some n.toNat
          | _ => rargs.findSome? (rangeEnd fuel')
        else rargs.findSome? (rangeEnd fuel')
      else e.getAppArgs.findSome? (rangeEnd fuel')
  rangeEnd 8 e

/-- `forAccum` / `forBody`：下标位的 `.arg` 是循环变量。不要改 payload。 -/
private partial def rewriteLoopIx : Ops.Val → Ops.Val
  | .indexGet b n i k off => .indexGet b n (rewriteLoopIx i) k off
  -- State-loop callbacks expose the mutable accumulator and index as their two innermost
  -- binders. Depending on zeta/proof reduction, the scalar index is decoded as either one;
  -- captured method parameters remain at indices ≥ 2 and are normalized later.
  | .arg 0 | .arg 1 => .loopIx
  | .field b n => .field (rewriteLoopIx b) n
  | .bitAnd l r => .bitAnd (rewriteLoopIx l) (rewriteLoopIx r)
  | .bitOr l r => .bitOr (rewriteLoopIx l) (rewriteLoopIx r)
  | .bitXor l r => .bitXor (rewriteLoopIx l) (rewriteLoopIx r)
  | .bitNot v => .bitNot (rewriteLoopIx v)
  | .shiftL l r => .shiftL (rewriteLoopIx l) (rewriteLoopIx r)
  | .shiftR l r => .shiftR (rewriteLoopIx l) (rewriteLoopIx r)
  | .select c l r t f =>
      .select c (rewriteLoopIx l) (rewriteLoopIx r) (rewriteLoopIx t) (rewriteLoopIx f)
  | .addU64 l r => .addU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .subU64 l r => .subU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .mulU64 l r => .mulU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .divU64 l r => .divU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .modU64 l r => .modU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .ext kind operands => .ext kind (operands.map rewriteLoopIx)
  | v => v

private partial def rewriteLoopOp : Ops.Op → Ops.Op
  | .letLocal i v => .letLocal i (rewriteLoopIx v)
  | .joinLocal i => .joinLocal i
  | .setLocal i v => .setLocal i (rewriteLoopIx v)
  | .checkedAddU64 l r => .checkedAddU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .checkedSubU64 l r => .checkedSubU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .checkedMulU64 l r => .checkedMulU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .checkedDivU64 l r => .checkedDivU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .checkedModU64 l r => .checkedModU64 (rewriteLoopIx l) (rewriteLoopIx r)
  | .ite c l r t f =>
      .ite c (rewriteLoopIx l) (rewriteLoopIx r)
        (t.map rewriteLoopOp) (f.map rewriteLoopOp)
  | .invoke prog metas data seed bump =>
      .invoke prog metas (data.map (·.map rewriteLoopIx)) seed (bump.map rewriteLoopIx)
  | .indexSetLeaf n i v k leaf =>
      .indexSetLeaf n (rewriteLoopIx i) (rewriteLoopIx v) k leaf
  | .indexSet n i v k off =>
      .indexSet n (rewriteLoopIx i) (rewriteLoopIx v) k off
  | .storeField n v => .storeField n (rewriteLoopIx v)
  | .okState v => .okState (rewriteLoopIx v)
  | .returnU64 v => .returnU64 (rewriteLoopIx v)
  | .returnState _ => .errorOverflow
  | .forAccum n v resultLocal => .forAccum n (rewriteLoopIx v) resultLocal
  | .forBody n body => .forBody n (body.map rewriteLoopOp)
  | op => op

/--
普通 accumulator / early-return 循环沿用原来的 callback 归一化：账户参数落到
`.arg 0`，动态索引就是 `loopIx`，而 `indexSet` payload 仍是外层方法参数。
State-carrying loop 不能用这条宽松规则，继续走上面的精确 binder 重写。
-/
private partial def rewritePlainLoopIx : Ops.Val → Ops.Val
  | .indexGet b n i k off =>
      let b' := match b with | .arg _ => .arg 0 | _ => rewritePlainLoopIx b
      let i' := match i with | .lit _ => i | _ => .loopIx
      .indexGet b' n i' k off
  | .field b n => .field (rewritePlainLoopIx b) n
  | .bitAnd l r => .bitAnd (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .bitOr l r => .bitOr (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .bitXor l r => .bitXor (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .bitNot x => .bitNot (rewritePlainLoopIx x)
  | .shiftL l r => .shiftL (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .shiftR l r => .shiftR (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .select c l r t f =>
      .select c (rewritePlainLoopIx l) (rewritePlainLoopIx r)
        (rewritePlainLoopIx t) (rewritePlainLoopIx f)
  | .addU64 l r => .addU64 (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .subU64 l r => .subU64 (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .mulU64 l r => .mulU64 (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .divU64 l r => .divU64 (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .modU64 l r => .modU64 (rewritePlainLoopIx l) (rewritePlainLoopIx r)
  | .ext kind operands => .ext kind (operands.map rewritePlainLoopIx)
  | v => v

private partial def rewritePlainLoopOp (op : Ops.Op) : Ops.Op :=
  let rv := rewritePlainLoopIx
  match op with
  | .letLocal i v => .letLocal i (rv v)
  | .joinLocal i => .joinLocal i
  | .setLocal i v => .setLocal i (rv v)
  | .checkedAddU64 l r => .checkedAddU64 (rv l) (rv r)
  | .checkedSubU64 l r => .checkedSubU64 (rv l) (rv r)
  | .checkedMulU64 l r => .checkedMulU64 (rv l) (rv r)
  | .checkedDivU64 l r => .checkedDivU64 (rv l) (rv r)
  | .checkedModU64 l r => .checkedModU64 (rv l) (rv r)
  | .ite c l r t f =>
      let l' := match l with | .arg _ => .loopIx | _ => rv l
      let r' := match r with | .arg _ => .loopIx | _ => rv r
      .ite c l' r' (t.map rewritePlainLoopOp) (f.map rewritePlainLoopOp)
  | .invoke prog metas data seed bump =>
      .invoke prog metas (data.map (·.map rv)) seed (bump.map rv)
  | .indexSetLeaf n i v k leaf =>
      let i' := match i with | .lit _ => i | _ => .loopIx
      let v' := match v with | .arg _ => .arg 0 | _ => v
      .indexSetLeaf n i' v' k leaf
  | .indexSet n i v k off =>
      let i' := match i with | .lit _ => i | _ => .loopIx
      let v' := match v with | .arg _ => .arg 0 | _ => v
      .indexSet n i' v' k off
  | .storeField n v => .storeField n v
  | .okState v => .okState (match v with | .arg _ => .arg 0 | _ => v)
  | .returnU64 v => .returnU64 (rv v)
  | .returnState _ => .errorOverflow
  | .forAccum n v resultLocal => .forAccum n (rv v) resultLocal
  | .forBody n body => .forBody n (body.map rewritePlainLoopOp)
  | op => op

private def findForIn (env : Environment) (e : Expr) : Option (Nat × Ops.Val) :=
  let rec go (fuel : Nat) (e : Expr) : Option (Nat × Ops.Val) :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := e.consumeMData
      if e.getAppFn.constName? == some ``Id.run || endsWith e ".run" then
        if e.getAppArgs.size ≥ 1 then go fuel' e.getAppArgs[e.getAppArgs.size - 1]!
        else none
      else if e.getAppFn.constName? == some ``ForIn.forIn || endsWith e ".forIn" then
        let args := e.getAppArgs
        let n? := args.findSome? forRangeEnd
        let rec findAdd (fuel : Nat) (e : Expr) : Option Ops.Val :=
          match fuel with
          | 0 => none
          | fuel' + 1 =>
            let e := strip e
            if isConstNamed e ``HAdd.hAdd && e.getAppArgs.size ≥ 2 then
              (asVal env 8 e.getAppArgs[e.getAppArgs.size - 1]!).map rewritePlainLoopIx
            else
              match e with
              | .lam _ _ body _ => findAdd fuel' body
              | .letE _ _ value body _ => findAdd fuel' value <|> findAdd fuel' body
              | _ => e.getAppArgs.findSome? (findAdd fuel')
        let addend? := args.findSome? (findAdd 16)
        match n?, addend? with
        | some n, some v =>
          if n = 0 || n > 64 then none else some (n, v)
        | _, _ => none
      else if isConstNamed e ``ite || isConstNamed e ``dite then none
      else
        match e with
        | .letE _ _ value body _ => go fuel' value <|> go fuel' body
        | .lam _ _ body _ => go fuel' body
        | .app f a => go fuel' f <|> go fuel' a
        | _ => none
  go 16 e

/-- `for i in [:n]` 里 `ForInStep.done` 提前返回。累加仍走 `findForIn`。 -/
private def findForBodyExpr (env : Environment) (e : Expr) : Option (Nat × Expr) :=
  let rec go (fuel : Nat) (e : Expr) : Option (Nat × Expr) :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := e.consumeMData
      if e.getAppFn.constName? == some ``Id.run || endsWith e ".run" then
        if e.getAppArgs.size ≥ 1 then go fuel' e.getAppArgs[e.getAppArgs.size - 1]!
        else none
      else if e.getAppFn.constName? == some ``ForIn.forIn || endsWith e ".forIn" then
        if (findForIn env e).isSome then none
        else
          let args := e.getAppArgs
          let n? := args.findSome? forRangeEnd
          -- `forIn xs init (fun i r => body)`：最后一个 λ 是循环体。
          let rec lastLam (fuel : Nat) (e : Expr) : Option Expr :=
            match fuel with
            | 0 => none
            | fuel' + 1 =>
              match strip e with
              | .lam _ _ body _ =>
                match strip body with
                | .lam _ _ body2 _ => some (peelLets body2)
                | _ => some (peelLets body)
              | .letE _ _ _ body _ => lastLam fuel' body
              | e => e.getAppArgs.findSome? (lastLam fuel')
          let bodyE? :=
            if args.size > 0 then lastLam 8 args[args.size - 1]! else none
          match n?, bodyE? with
          | some n, some bodyE =>
            if n = 0 || n > 64 then none else some (n, bodyE)
          | _, _ => none
      else if isConstNamed e ``ite || isConstNamed e ``dite then none
      else
        match e with
        | .letE _ _ value body _ => go fuel' value <|> go fuel' body
        | .lam _ _ body _ => go fuel' body
        | .app f a => go fuel' f <|> go fuel' a
        | _ => none
  go 16 e

/-- Conservatively detect a structured State binding before zeta reduction erases its sharing. -/
private def containsStructuredStateLet (env : Environment) : Nat → Expr → Bool
  | 0, _ => false
  | fuel + 1, e =>
      match strip e with
      | .letE _ type value body _ =>
          let userStructure :=
            (type.consumeMData.getAppFn.constName?.map (isUserType env)).getD false
          (userStructure && (isIteExpr value || (unfoldUserHelper env value).isSome)) ||
            containsStructuredStateLet env fuel value || containsStructuredStateLet env fuel body
      | .lam _ _ body _ => containsStructuredStateLet env fuel body
      | .app fn arg =>
          containsStructuredStateLet env fuel fn || containsStructuredStateLet env fuel arg
      | _ => false

/-- Detect a marked State transition below surrounding control/record syntax. -/
private def containsInlineStateTransition (env : Environment) : Nat → Expr → Bool
  | 0, _ => false
  | fuel + 1, e =>
      let e := strip e
      let here :=
        match unfoldUserHelper env e with
        | some (name, _) => inlineHelperPreservesUserType env name
        | none => false
      here || match e with
        | .letE _ _ value body _ =>
            containsInlineStateTransition env fuel value ||
              containsInlineStateTransition env fuel body
        | .lam _ _ body _ => containsInlineStateTransition env fuel body
        | .app fn arg =>
            containsInlineStateTransition env fuel fn ||
              containsInlineStateTransition env fuel arg
        | _ => false

/--
`do let mut st := s; for ... do st := ...; k st` 的 loop body 与 continuation。
真正是否为 state-carrying loop 由 body 解码出的显式 store 判定；普通 early-return
`forBody` 继续走旧路径。
-/
private def findForStateExpr (env : Environment) (e : Expr) :
    Option (Nat × Expr × Expr × Expr) :=
  let rec findForExpr (fuel : Nat) (e : Expr) : Option Expr :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if e.getAppFn.constName? == some ``ForIn.forIn || endsWith e ".forIn" then some e
      else if isConstNamed e ``ite || isConstNamed e ``dite then none
      else
        match e with
        | .letE _ _ value body _ =>
          findForExpr fuel' value <|> findForExpr fuel' (body.instantiate1 value)
        | .lam _ _ body _ => findForExpr fuel' body
        | _ => e.getAppArgs.findSome? (findForExpr fuel')
  let loopParts? := do
    let forExpr ← findForExpr 32 e
    let n ← forExpr.getAppArgs.findSome? forRangeEnd
    let rec lastLam (fuel : Nat) (e : Expr) : Option Expr :=
      match fuel with
      | 0 => none
      | fuel' + 1 =>
        match strip e with
        | .lam _ _ body _ =>
          match strip body with
          | .lam _ _ body2 _ => some (substLetsPreservingInvokes env 128 body2)
          | _ => some (substLetsPreservingInvokes env 128 body)
        | .letE _ _ _ body _ => lastLam fuel' body
        | e => e.getAppArgs.findSome? (lastLam fuel')
    let args := forExpr.getAppArgs
    if args.size < 2 then none else
    let initial := args[args.size - 2]!
    let body ← if h : args.size > 0 then lastLam 16 args[args.size - 1] else none
    if n = 0 || n > 64 then none else some (n, initial, body)
  let rec findContinuation (fuel : Nat) (e : Expr) : Option Expr :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if e.getAppFn.constName? == some ``Id.run || endsWith e ".run" then
        if e.getAppArgs.size ≥ 1 then
          findContinuation fuel' e.getAppArgs[e.getAppArgs.size - 1]!
        else none
      else if isConstNamed e ``ite || isConstNamed e ``dite then none
      else
        match e with
        | .letE _ _ value body _ => findContinuation fuel' (body.instantiate1 value)
        | _ =>
          if e.getAppFn.constName? == some ``Bind.bind || endsWith e ".bind" then
            let args := e.getAppArgs
            if args.any fun a => (findForExpr 16 a).isSome then
              match args.findRev? fun a => match strip a with | .lam .. => true | _ => false with
              | some continuation =>
                match strip continuation with
                | .lam _ _ continuationBody _ =>
                  if containsStructuredStateLet env 2048 continuationBody ||
                      containsInlineStateTransition env 2048 continuationBody then
                    some (strip continuationBody)
                  else
                    some (peelControl 16 (substLets 128 continuationBody))
                | _ => none
              | none => none
            else args.findSome? (findContinuation fuel')
          else
            e.getAppArgs.findSome? (findContinuation fuel')
  match loopParts?, findContinuation 32 e with
  | some (n, initial, bodyE), some continuation => some (n, initial, bodyE, continuation)
  | _, _ => none

/-- 收集 `xs.set … .set …` 整条链。先外层（旧向量），后内层（新写）。
一次 `set` 可以改多叶（`left` + `parent`）。 -/
private def collectIndexSets (env : Environment) (e : Expr)
    (deduplicate : Bool := false) (appliedBases : Array Expr := #[]) : Array Ops.Op :=
  let rec go (fuel : Nat) (e : Expr) (state : Array Expr × Array Ops.Op) :
      Array Expr × Array Ops.Op :=
    match fuel with
    | 0 => state
    | fuel' + 1 =>
      let e := strip e
      match e with
      | .letE _ _ value body _ => go fuel' (body.instantiate1 value) state
      | .lam _ _ body _ => go fuel' body state
      | _ =>
        if isConstNamed e ``Except.ok && e.getAppArgs.size ≥ 1 then
          go fuel' e.getAppArgs[e.getAppArgs.size - 1]! state
        else if isConstNamed e ``Prod.mk && e.getAppArgs.size ≥ 2 then
          go fuel' e.getAppArgs[e.getAppArgs.size - 2]! state
        else if isVectorSet e then
          -- `Vector.set α n xs i v h`：只沿 xs 追溯旧写。payload/下标里的
          -- vector reads 不是写；共享 record projections 也会重复引用同一个 set node。
          if deduplicate && state.1.contains e then state else
            let args := e.getAppArgs
            let state :=
              if h : args.size ≥ 4 then go fuel' args[args.size - 4] state else state
            match asIndexSets env e with
            | some ops =>
                let seen := if deduplicate then state.1.push e else state.1
                (seen, state.2 ++ ops)
            | none => state
        else
          let inheritedFromAppliedBase :=
            match e.getAppFn.constName? with
            | some projection =>
              match env.getProjectionFnInfo? projection with
              | some _ =>
                let args := e.getAppArgs
                (args[args.size - 1]?.map appliedBases.contains).getD false
              | none => false
            | none => false
          if inheritedFromAppliedBase then state
          else e.getAppArgs.foldl (init := state) fun state arg => go fuel' arg state
  (go 16 e (#[], #[])).2

private def findIndexSet (env : Environment) (e : Expr) : Option Ops.Op :=
  (collectIndexSets env e)[0]?

private def findRuntimeApp (fuel : Nat) (e : Expr) (want : Name) (suffix : String) :
    Option Expr :=
  let rec go (fuel : Nat) (e : Expr) : Option Expr :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := e.consumeMData
      if e.getAppFn.constName? == some want || endsWith e suffix then
        some e
      else
        match e with
        | .letE _ _ value body _ => go fuel' value <|> go fuel' body
        | .lam _ _ body _ => go fuel' body
        | .app f a => go fuel' f <|> go fuel' a
        | _ => none
  go fuel e

private def findUnaryRuntime (env : Environment) (want : Name) (suffix : String)
    (e : Expr) : Option Ops.Val :=
  if mentionsRuntime e suffix then
    match findRuntimeApp 16 e want suffix with
    | some app =>
      if app.getAppArgs.size ≥ 1 then
        match val env app.getAppArgs[app.getAppArgs.size - 1]! with
        | some v => some v
        | none => some (.arg 0)
      else some (.arg 0)
    | none => some (.arg 0)
  else none

private def nthFromEnd (args : Array Expr) (n : Nat) : Option Expr :=
  if args.size ≥ n + 1 then some args[args.size - 1 - n]! else none

private def valAtEnd (env : Environment) (args : Array Expr) (n : Nat) : Ops.Val :=
  match nthFromEnd args n with
  | some e => (val env e).getD (.arg n)
  | none => .arg n

private def findEvmDeposit (env : Environment) (e : Expr) : Option Ops.Val :=
  findUnaryRuntime env ``ProofForge.Evm.Runtime.evmDeposit ".evmDeposit" e

private def findEvmLogTipped (env : Environment) (e : Expr) : Option Ops.Val :=
  findUnaryRuntime env ``ProofForge.Evm.Runtime.evmLogTipped ".evmLogTipped" e

private def findEvmLogIncremented (env : Environment) (e : Expr) : Option Ops.Val :=
  findUnaryRuntime env ``ProofForge.Evm.Runtime.evmLogIncremented ".evmLogIncremented" e

private def findEvmLogTransfer (env : Environment) (e : Expr) : Option Ops.Val :=
  findUnaryRuntime env ``ProofForge.Evm.Runtime.evmLogTransfer ".evmLogTransfer" e

private def findEvmLogApproval (env : Environment) (e : Expr) : Option Ops.Val :=
  findUnaryRuntime env ``ProofForge.Evm.Runtime.evmLogApproval ".evmLogApproval" e

private def findEvmSendEth (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e "evmSendEth" then
    match findRuntimeApp 16 e ``ProofForge.Evm.Runtime.evmSendEth ".evmSendEth" with
    | some app =>
      let args := app.getAppArgs
      some (valAtEnd env args 3, valAtEnd env args 2, valAtEnd env args 1, valAtEnd env args 0)
    | none => some (.arg 0, .arg 1, .arg 2, .arg 3)
  else none

private def findBinaryRuntime (env : Environment) (want : Name) (suffix : String)
    (e : Expr) : Option (Ops.Val × Ops.Val) :=
  if mentionsRuntime e suffix then
    match findRuntimeApp 16 e want suffix with
    | some app =>
      let args := app.getAppArgs
      if args.size ≥ 2 then some (valAtEnd env args 1, valAtEnd env args 0)
      else some (.arg 0, .arg 1)
    | none => some (.arg 0, .arg 1)
  else none

private def findTernaryRuntime (env : Environment) (want : Name) (suffix : String)
    (e : Expr) : Option (Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e suffix then
    match findRuntimeApp 16 e want suffix with
    | some app =>
      let args := app.getAppArgs
      if args.size ≥ 3 then
        some (valAtEnd env args 2, valAtEnd env args 1, valAtEnd env args 0)
      else some (.arg 0, .arg 1, .arg 2)
    | none => some (.arg 0, .arg 1, .arg 2)
  else none

private def findEvmMapGetU64 (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val) :=
  findBinaryRuntime env ``ProofForge.Evm.Runtime.evmMapGetU64 ".evmMapGetU64" e

private def findEvmMapSetU64 (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val) :=
  findTernaryRuntime env ``ProofForge.Evm.Runtime.evmMapSetU64 ".evmMapSetU64" e

private def findEvmMapGetAddr (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e "evmMapGetAddr" then
    match findRuntimeApp 16 e ``ProofForge.Evm.Runtime.evmMapGetAddr ".evmMapGetAddr" with
    | some app =>
      let args := app.getAppArgs
      some (valAtEnd env args 3, valAtEnd env args 2, valAtEnd env args 1, valAtEnd env args 0)
    | none => some (.arg 0, .arg 1, .arg 2, .arg 3)
  else none

private def findEvmMapSetAddr (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e "evmMapSetAddr" then
    match findRuntimeApp 16 e ``ProofForge.Evm.Runtime.evmMapSetAddr ".evmMapSetAddr" with
    | some app =>
      let args := app.getAppArgs
      some (valAtEnd env args 4, valAtEnd env args 3, valAtEnd env args 2,
        valAtEnd env args 1, valAtEnd env args 0)
    | none => some (.arg 0, .arg 1, .arg 2, .arg 3, .arg 4)
  else none

private def findEvmMapGetPair (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e "evmMapGetPair" then
    match findRuntimeApp 16 e ``ProofForge.Evm.Runtime.evmMapGetPair ".evmMapGetPair" with
    | some app =>
      let args := app.getAppArgs
      some (valAtEnd env args 6, valAtEnd env args 5, valAtEnd env args 4,
        valAtEnd env args 3, valAtEnd env args 2, valAtEnd env args 1, valAtEnd env args 0)
    | none => some (.arg 0, .arg 1, .arg 2, .arg 3, .arg 4, .arg 5, .arg 6)
  else none

private def findEvmMapSetPair (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e "evmMapSetPair" then
    match findRuntimeApp 16 e ``ProofForge.Evm.Runtime.evmMapSetPair ".evmMapSetPair" with
    | some app =>
      let args := app.getAppArgs
      some (valAtEnd env args 7, valAtEnd env args 6, valAtEnd env args 5,
        valAtEnd env args 4, valAtEnd env args 3, valAtEnd env args 2,
        valAtEnd env args 1, valAtEnd env args 0)
    | none => some (.arg 0, .arg 1, .arg 2, .arg 3, .arg 4, .arg 5, .arg 6, .arg 7)
  else none

private def findEvmTokenTransfer (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val × Ops.Val) :=
  if mentionsRuntime e "evmTokenTransfer" then
    match findRuntimeApp 16 e ``ProofForge.Evm.Runtime.evmTokenTransfer ".evmTokenTransfer" with
    | some app =>
      let args := app.getAppArgs
      some (valAtEnd env args 6, valAtEnd env args 5, valAtEnd env args 4,
        valAtEnd env args 3, valAtEnd env args 2, valAtEnd env args 1, valAtEnd env args 0)
    | none => some (.arg 0, .arg 1, .arg 2, .arg 3, .arg 4, .arg 5, .arg 6)
  else none

private def findEvmTokenBalance (env : Environment) (e : Expr) :
    Option (Ops.Val × Ops.Val × Ops.Val) :=
  findTernaryRuntime env ``ProofForge.Evm.Runtime.evmTokenBalanceOfSelf
    ".evmTokenBalanceOfSelf" e

private def opOfRuntimeApp (env : Environment) (app : Expr) : Option Ops.Op :=
  let args := app.getAppArgs
  if isConstNamed app ``ProofForge.Evm.Runtime.evmDeposit || endsWith app ".evmDeposit" then
    some (.evmDeposit (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmSendEth || endsWith app ".evmSendEth" then
    some (.evmSendEth (valAtEnd env args 3) (valAtEnd env args 2)
      (valAtEnd env args 1) (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmLogTipped || endsWith app ".evmLogTipped" then
    some (.evmLog "Tipped" (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmLogIncremented ||
      endsWith app ".evmLogIncremented" then
    some (.evmLog "Incremented" (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmLogTransfer ||
      endsWith app ".evmLogTransfer" then
    some (.evmLog "Transfer" (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmLogApproval ||
      endsWith app ".evmLogApproval" then
    some (.evmLog "Approval" (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmMapSetU64 || endsWith app ".evmMapSetU64" then
    some (.mapSetU64 (valAtEnd env args 2) (valAtEnd env args 1) (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmMapSetAddr || endsWith app ".evmMapSetAddr" then
    some (.mapSetAddr (valAtEnd env args 4) (valAtEnd env args 3) (valAtEnd env args 2)
      (valAtEnd env args 1) (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmMapSetPair || endsWith app ".evmMapSetPair" then
    some (.mapSetPair (valAtEnd env args 7) (valAtEnd env args 6) (valAtEnd env args 5)
      (valAtEnd env args 4) (valAtEnd env args 3) (valAtEnd env args 2)
      (valAtEnd env args 1) (valAtEnd env args 0))
  else if isConstNamed app ``ProofForge.Evm.Runtime.evmTokenTransfer ||
      endsWith app ".evmTokenTransfer" then
    some (.evmTokenTransfer (valAtEnd env args 6) (valAtEnd env args 5) (valAtEnd env args 4)
      (valAtEnd env args 3) (valAtEnd env args 2) (valAtEnd env args 1) (valAtEnd env args 0))
  else none

private def collectEvmEffectOps (env : Environment) (e : Expr) : Array Ops.Op :=
  let specs : Array (Name × String) := #[
    (``ProofForge.Evm.Runtime.evmDeposit, ".evmDeposit"),
    (``ProofForge.Evm.Runtime.evmSendEth, ".evmSendEth"),
    (``ProofForge.Evm.Runtime.evmLogTipped, ".evmLogTipped"),
    (``ProofForge.Evm.Runtime.evmLogIncremented, ".evmLogIncremented"),
    (``ProofForge.Evm.Runtime.evmLogTransfer, ".evmLogTransfer"),
    (``ProofForge.Evm.Runtime.evmLogApproval, ".evmLogApproval"),
    (``ProofForge.Evm.Runtime.evmMapSetU64, ".evmMapSetU64"),
    (``ProofForge.Evm.Runtime.evmMapSetAddr, ".evmMapSetAddr"),
    (``ProofForge.Evm.Runtime.evmMapSetPair, ".evmMapSetPair"),
    (``ProofForge.Evm.Runtime.evmTokenTransfer, ".evmTokenTransfer")
  ]
  let rec walk (fuel : Nat) (e : Expr) (acc : Array Ops.Op) : Array Ops.Op :=
    match fuel with
    | 0 => acc
    | fuel' + 1 =>
      let e := e.consumeMData
      if specs.any (fun (want, suf) =>
          e.getAppFn.constName? == some want || endsWith e suf) then
        match opOfRuntimeApp env e with
        | some op => acc.push op
        | none => acc
      else
        match e with
        | .letE _ _ value body _ => walk fuel' body (walk fuel' value acc)
        | .lam _ _ body _ => walk fuel' body acc
        | .app f a => walk fuel' a (walk fuel' f acc)
        | _ => acc
  walk 24 e #[]

private def retOfEvmOps (ops : Array Ops.Op) : Ops.Val :=
  match ops.back? with
  | some (.evmDeposit v) => v
  | some (.evmSendEth _ _ _ v) => v
  | some (.evmLog _ v) => v
  | some (.mapSetU64 _ _ v) => v
  | some (.mapSetAddr _ _ _ _ v) => v
  | some (.mapSetPair _ _ _ _ _ _ _ v) => v
  | some (.evmTokenTransfer _ _ _ _ _ _ v) => v
  | _ => .arg 0

private def decodeEvmEffect (env : Environment) (e : Expr) : Option (Array Ops.Op) :=
  let writes := collectEvmEffectOps env e
  if writes.size ≥ 1 then
    some (writes.push (.returnU64 (retOfEvmOps writes)))
  else if let some amount := findEvmDeposit env e then
    some #[.evmDeposit amount, .returnU64 amount]
  else if let some (w0, w1, w2, amt) := findEvmSendEth env e then
    some #[.evmSendEth w0 w1 w2 amt, .returnU64 amt]
  else if let some amount := findEvmLogTipped env e then
    some #[.evmLog "Tipped" amount, .returnU64 amount]
  else if let some amount := findEvmLogIncremented env e then
    some #[.evmLog "Incremented" amount, .returnU64 amount]
  else if let some amount := findEvmLogTransfer env e then
    some #[.evmLog "Transfer" amount, .returnU64 amount]
  else if let some amount := findEvmLogApproval env e then
    some #[.evmLog "Approval" amount, .returnU64 amount]
  else if let some (b, k, v) := findEvmMapSetU64 env e then
    some #[.mapSetU64 b k v, .returnU64 v]
  else if let some (b, a0, a1, a2, v) := findEvmMapSetAddr env e then
    some #[.mapSetAddr b a0 a1 a2 v, .returnU64 v]
  else if let some (b, o0, o1, o2, s0, s1, s2, v) := findEvmMapSetPair env e then
    some #[.mapSetPair b o0 o1 o2 s0 s1 s2 v, .returnU64 v]
  else if let some (t0, t1, t2, d0, d1, d2, amt) := findEvmTokenTransfer env e then
    some #[.evmTokenTransfer t0 t1 t2 d0 d1 d2 amt, .returnU64 amt]
  else if let some (b, k) := findEvmMapGetU64 env e then
    some #[.mapGetU64 b k, .returnU64 k]
  else if let some (b, a0, a1, a2) := findEvmMapGetAddr env e then
    some #[.mapGetAddr b a0 a1 a2, .returnU64 a0]
  else if let some (b, o0, o1, o2, s0, s1, s2) := findEvmMapGetPair env e then
    some #[.mapGetPair b o0 o1 o2 s0 s1 s2, .returnU64 o0]
  else if let some (t0, t1, t2) := findEvmTokenBalance env e then
    some #[.evmTokenBalanceOfSelf t0 t1 t2, .returnU64 t0]
  else none

/-- A vector root is not a scalar slot. Mixed static/dynamic writeback can see an inline
helper's vector parameter as a changed structure field; discard that synthetic root store. -/
private def dropVectorRootStores (dynamic stores : Array Ops.Op) : Array Ops.Op :=
  let vectorNames := dynamic.filterMap fun
    | .indexSetLeaf name _ _ _ _ | .indexSet name _ _ _ _ => some name
    | _ => none
  stores.filter fun
    | .storeField name _ => !vectorNames.contains name
    | _ => true

private def qualifyStatePrefix (statePrefix name : String) : String :=
  if statePrefix.isEmpty || name == statePrefix || name.startsWith (statePrefix ++ "_") then name
  else s!"{statePrefix}_{name}"

private def qualifyDynamicStateOp (statePrefix : String) : Ops.Op → Ops.Op
  | .indexSetLeaf name index value len leaf =>
      .indexSetLeaf (qualifyStatePrefix statePrefix name) index value len leaf
  | .indexSet name index value len elemOff =>
      .indexSet (qualifyStatePrefix statePrefix name) index value len elemOff
  | op => op

private def qualifyNestedStateName (statePrefix : String) (fieldNames : Array String)
    (name : String) : String :=
  if statePrefix.isEmpty || name == statePrefix || name.startsWith (statePrefix ++ "_") then name
  else if fieldNames.any fun field => name == field || name.startsWith (field ++ "_") then
    s!"{statePrefix}_{name}"
  else name

private partial def qualifyNestedStateVal (statePrefix : String) (fieldNames : Array String) :
    Ops.Val → Ops.Val
  | .arg i => .arg i
  | .local i => .local i
  | .field base name =>
      .field (qualifyNestedStateVal statePrefix fieldNames base)
        (qualifyNestedStateName statePrefix fieldNames name)
  | .lit value => .lit value
  | .bitAnd lhs rhs => .bitAnd (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .bitOr lhs rhs => .bitOr (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .bitXor lhs rhs => .bitXor (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .bitNot value => .bitNot (qualifyNestedStateVal statePrefix fieldNames value)
  | .shiftL lhs rhs => .shiftL (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .shiftR lhs rhs => .shiftR (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .indexGet base name index len elemOff =>
      .indexGet (qualifyNestedStateVal statePrefix fieldNames base)
        (qualifyNestedStateName statePrefix fieldNames name)
        (qualifyNestedStateVal statePrefix fieldNames index) len elemOff
  | .loopIx => .loopIx
  | .select cmp lhs rhs thn els =>
      .select cmp (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
        (qualifyNestedStateVal statePrefix fieldNames thn)
        (qualifyNestedStateVal statePrefix fieldNames els)
  | .addU64 lhs rhs => .addU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .subU64 lhs rhs => .subU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .mulU64 lhs rhs => .mulU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .divU64 lhs rhs => .divU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .modU64 lhs rhs => .modU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
      (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .ext kind operands =>
      .ext kind (operands.map (qualifyNestedStateVal statePrefix fieldNames))

private partial def qualifyNestedStateOp (statePrefix : String) (fieldNames : Array String) :
    Ops.Op → Ops.Op
  | .letLocal i value => .letLocal i (qualifyNestedStateVal statePrefix fieldNames value)
  | .joinLocal i => .joinLocal i
  | .setLocal i value => .setLocal i (qualifyNestedStateVal statePrefix fieldNames value)
  | .checkedAddU64 lhs rhs =>
      .checkedAddU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .checkedSubU64 lhs rhs =>
      .checkedSubU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .checkedMulU64 lhs rhs =>
      .checkedMulU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .checkedDivU64 lhs rhs =>
      .checkedDivU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .checkedModU64 lhs rhs =>
      .checkedModU64 (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
  | .ite cmp lhs rhs thn els =>
      .ite cmp (qualifyNestedStateVal statePrefix fieldNames lhs)
        (qualifyNestedStateVal statePrefix fieldNames rhs)
        (thn.map (qualifyNestedStateOp statePrefix fieldNames))
        (els.map (qualifyNestedStateOp statePrefix fieldNames))
  | .forAccum n value resultLocal =>
      .forAccum n (qualifyNestedStateVal statePrefix fieldNames value) resultLocal
  | .forBody n body => .forBody n (body.map (qualifyNestedStateOp statePrefix fieldNames))
  | .indexSetLeaf name index value len leaf =>
      .indexSetLeaf (qualifyNestedStateName statePrefix fieldNames name)
        (qualifyNestedStateVal statePrefix fieldNames index)
        (qualifyNestedStateVal statePrefix fieldNames value) len leaf
  | .indexSet name index value len elemOff =>
      .indexSet (qualifyNestedStateName statePrefix fieldNames name)
        (qualifyNestedStateVal statePrefix fieldNames index)
        (qualifyNestedStateVal statePrefix fieldNames value) len elemOff
  | .storeField name value =>
      .storeField (qualifyNestedStateName statePrefix fieldNames name)
        (qualifyNestedStateVal statePrefix fieldNames value)
  | .okState value => .okState (qualifyNestedStateVal statePrefix fieldNames value)
  | .returnU64 value => .returnU64 (qualifyNestedStateVal statePrefix fieldNames value)
  | .returnState value => .returnState (qualifyNestedStateVal statePrefix fieldNames value)
  | op => op

/-- A nested state helper's success value is consumed by the enclosing record update. Its writes
remain observable, but its state terminal must not be interpreted as a root-schema commit. -/
private partial def dropNestedStateTerminals (ops : Array Ops.Op) : Array Ops.Op :=
  ops.filterMap fun op =>
    match op with
    | .okState _ | .returnState _ => none
    | .ite cmp lhs rhs thn els =>
        some (.ite cmp lhs rhs (dropNestedStateTerminals thn) (dropNestedStateTerminals els))
    | .forBody n body => some (.forBody n (dropNestedStateTerminals body))
    | op => some op

/-- Once a nested transition has been lowered, the enclosing record's projection of that
structure is inheritance, not a scalar write. Keep later scalar/vector continuation effects while
removing only the impossible whole-structure store. -/
private partial def dropNestedRootStores (statePrefix : String)
    (ops : Array Ops.Op) : Array Ops.Op :=
  ops.filterMap fun op =>
    match op with
    | .storeField name _ => if name == statePrefix then none else some op
    | .ite cmp lhs rhs thn els =>
        some (.ite cmp lhs rhs (dropNestedRootStores statePrefix thn)
          (dropNestedRootStores statePrefix els))
    | .forBody n body => some (.forBody n (dropNestedRootStores statePrefix body))
    | op => some op

/-- Zeta-reduce syntax-only aliases at the head of an expression.
Compiler intrinsics and loops stay explicit so later effect/control decoding still sees them. -/
private def zetaPureHeadLets (env : Environment) (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    match strip e with
    | .letE _ _ value body _ =>
        let effectful :=
          (findInvoke env 16 value).isSome || (decodeEvmEffect env value).isSome ||
            (findForIn env value).isSome || (findForBodyExpr env value).isSome
        -- A scalar captured before a CPI must remain a local: substituting its state-field read
        -- through the call can move that read after a later state write.
        let bodyHasInvoke := (findInvoke env 16 body).isSome
        let directAlias := match strip body with | .bvar 0 => true | _ => false
        if effectful || bodyHasInvoke || (!directAlias && !isIteExpr body) then e
        else zetaPureHeadLets env fuel' (body.instantiate1 value)
    | e => e

private def findYieldPayload (e : Expr) : Option Expr :=
  let rec go (fuel : Nat) (e : Expr) : Option Expr :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if isConstNamed e ``ForInStep.yield || endsWith e ".yield" then
        if e.getAppArgs.size ≥ 1 then
          -- The payload remains under the yielded state/control binder. Keep accumulator 0,
          -- and lower the loop index plus outer method arguments back to callback scope.
          some (e.getAppArgs[e.getAppArgs.size - 1]!.lowerLooseBVars 1 1)
        else none
      else
        match e with
        | .letE _ _ value body _ => go fuel' body <|> go fuel' value
        -- Yield can sit under a dependent branch proof lambda. Dropping that binder without
        -- lowering would turn the loop index and outer arguments into unrelated `.arg`s.
        | .lam _ _ body _ => go fuel' (body.lowerLooseBVars 1 1)
        | _ => e.getAppArgs.findSome? (go fuel')
  go 32 e

/--
Lean composes consecutive mutable-state assignments as a record update whose unchanged
fields project from the previous expression. When that base is a `pf_inline` State helper,
preserve the helper transition before lowering the outer update. This is target-neutral
structured-state normalization; backends only see the resulting stores.
-/
private def findProjectedInlineBase (env : Environment) (fuel : Nat) (e : Expr) : Option Expr :=
  match fuel with
  | 0 => none
  | fuel' + 1 =>
    let e := strip e
    let args := e.getAppArgs
    let projectedBase? :=
      match e.getAppFn.constName? with
      | some name =>
        match env.getProjectionFnInfo? name with
        | some _ =>
          if h : args.size > 0 then
            let base := args[args.size - 1]
            match unfoldUserHelper env base with
            | some (helper, _) =>
              if inlineHelperPreservesUserType env helper then some base else none
            | none => none
          else none
        | none => none
      | none => none
    projectedBase? <|> args.findSome? (findProjectedInlineBase env fuel')

/-- Collect the inline State expressions inherited through record projections. Once such an
expression has been lowered, later wrappers may still contain several projections of the same
result; retaining every applied ancestor prevents those transitions from being emitted again. -/
private def projectedInlineBases (env : Environment) (fuel : Nat) (e : Expr) : Array Expr :=
  let rec go (fuel : Nat) (e : Expr) (acc : Array Expr) : Array Expr :=
    match fuel with
    | 0 => acc
    | fuel' + 1 =>
      let e := strip e
      let args := e.getAppArgs
      let acc :=
        match e.getAppFn.constName? with
        | some name =>
          match env.getProjectionFnInfo? name with
          | some _ =>
            match args[args.size - 1]? with
            | some base =>
              match unfoldUserHelper env base with
              | some (helper, _) =>
                if inlineHelperPreservesUserType env helper && !acc.contains base then acc.push base
                else acc
              | none => acc
            | none => acc
          | none => acc
        | none => acc
      args.foldl (init := acc) fun acc arg => go fuel' arg acc
  go fuel e #[]

private def addAppliedBases (current extra : Array Expr) : Array Expr :=
  extra.foldl (init := current) fun result base =>
    if result.contains base then result else result.push base

/-- Find the mutable source underneath a composed State expression. -/
private def inlineStateSource (env : Environment) (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    let e := strip e
    if let .letE _ _ value body _ := e then
      inlineStateSource env fuel' (body.instantiate1 value)
    else if (isConstNamed e ``ite || isConstNamed e ``dite) && e.getAppArgs.size ≥ 2 then
      let args := e.getAppArgs
      let branch := args[args.size - 2]!
      let branch :=
        match strip branch with
        | .lam _ _ body _ => body.lowerLooseBVars 1 1
        | branch => branch
      inlineStateSource env fuel' branch
    else if (unfoldUserHelper env e).isSome then
      let args := e.getAppArgs
      if h : args.size > 0 then inlineStateSource env fuel' args[0] else e
    else
      let structureSource? :=
        match e.getAppFn.constName?, userCtorFields env e with
        | some ctor, some fields => Id.run do
          for h : i in [:fields.size] do
            let field := fields[i]
            if let some projection := (strip field).getAppFn.constName? then
              if let some info := env.getProjectionFnInfo? projection then
                let args := (strip field).getAppArgs
                if info.ctorName == ctor && info.i == i then
                  if h : args.size > 0 then return some args[args.size - 1]
          return none
        | _, _ => none
      let directProjectionBase? :=
        match e.getAppFn.constName? with
        | some name =>
          if !isUserName env name then none else match env.getProjectionFnInfo? name with
          | some _ =>
            let args := e.getAppArgs
            if h : args.size > 0 then some args[args.size - 1] else none
          | none => none
        | none => none
      match structureSource? <|> directProjectionBase? with
      | some base => inlineStateSource env fuel' base
      | none => e

private def isStateTransitionValue (env : Environment) : Nat → Bool → Expr → Bool
  | 0, _, _ => false
  | fuel + 1, underControl, e =>
      let e := strip e
      match e with
      | .letE _ _ value body _ =>
          isStateTransitionValue env fuel underControl (body.instantiate1 value)
      | _ =>
        if (isConstNamed e ``ite || isConstNamed e ``dite) && e.getAppArgs.size ≥ 2 then
          let args := e.getAppArgs
          let peelProofLam (branch : Expr) : Expr :=
            match strip branch with
            | .lam _ _ body _ => body.lowerLooseBVars 1 1
            | branch => branch
          isStateTransitionValue env fuel true (peelProofLam args[args.size - 2]!) ||
            isStateTransitionValue env fuel true (peelProofLam args[args.size - 1]!)
        else
          match unfoldUserHelper env e with
          | some (name, _) => inlineHelperPreservesUserType env name
          | none =>
            match e.getAppFn.constName? with
            | some name =>
              match env.find? name with
              | some (.ctorInfo ctor) =>
                  underControl && isUserType env ctor.induct && isStructure env ctor.induct
              | _ => false
            | none => false

/-- Sequential decoding is needed when substitution would duplicate dynamic structure writes or
erase a conditional State constructor behind later projections. Straight-line scalar-only helpers
retain the established zeta-normalized Core shape. Follow marked helpers recursively so wrappers
around `Vector.set` remain generic. -/
private def stateTransitionNeedsSequencing (env : Environment) : Nat → Expr → Bool
  | 0, _ => false
  | fuel + 1, e =>
      let e := strip e
      if isIteExpr e || !(collectIndexSets env e).isEmpty then true
      else
        match e with
        | .letE _ _ value body _ =>
            stateTransitionNeedsSequencing env fuel value ||
              stateTransitionNeedsSequencing env fuel body
        | .lam _ _ body _ => stateTransitionNeedsSequencing env fuel body
        | _ =>
          match unfoldUserHelper env e with
          | some (_, unfolded) => stateTransitionNeedsSequencing env fuel unfolded
          | none => e.getAppArgs.any (stateTransitionNeedsSequencing env fuel)

/-- Follow structure-preserving helpers to their source value without erasing a nested projection.
For a helper over `s.askBook`, the root-state source is `s` but the type-correct substitution source
is `s.askBook`; sequential nested lowering needs both facts. -/
private def inlineTypedStateSource (env : Environment) (fuel : Nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | fuel' + 1 =>
    let e := strip e
    if let .letE _ _ value body _ := e then
      inlineTypedStateSource env fuel' (body.instantiate1 value)
    else if (isConstNamed e ``ite || isConstNamed e ``dite) && e.getAppArgs.size ≥ 2 then
      let args := e.getAppArgs
      let branch := args[args.size - 2]!
      let branch :=
        match strip branch with
        | .lam _ _ body _ => body.lowerLooseBVars 1 1
        | branch => branch
      inlineTypedStateSource env fuel' branch
    else if (unfoldUserHelper env e).isSome then
      let args := e.getAppArgs
      if h : args.size > 0 then inlineTypedStateSource env fuel' args[0] else e
    else
      let structureSource? :=
        match e.getAppFn.constName?, userCtorFields env e with
        | some ctor, some fields => Id.run do
          for h : i in [:fields.size] do
            let field := fields[i]
            if let some projection := (strip field).getAppFn.constName? then
              if let some info := env.getProjectionFnInfo? projection then
                let args := (strip field).getAppArgs
                if info.ctorName == ctor && info.i == i then
                  if h : args.size > 0 then return some args[args.size - 1]
          return none
        | _, _ => none
      match structureSource? with
      | some source => inlineTypedStateSource env fuel' source
      | none => e

/--
A let-bound user structure rooted at a method state argument is a sequential State transition,
not a pure value alias. Decoding it before the continuation avoids substituting an ever-growing
record expression through every later projection. Nested structures have a separate typed-source
path below; this boundary owns only transitions of the declared root state type.
-/
private def sequentialStateSource? (env : Environment) (type value : Expr)
    (stateType? : Option Name := none) : Option Expr := do
  let typeName ← type.consumeMData.getAppFn.constName?
  if !isUserType env typeName then none else
  if stateType?.any (· != typeName) then none else
  let value := strip value
  let source := inlineStateSource env 64 value
  if source == value then none else
  let directRecordUpdate :=
    match value.getAppFn.constName?, userCtorFields env value with
    | some ctor, some _ =>
        match env.find? ctor with
        | some (.ctorInfo info) => info.induct == typeName
        | _ => false
    | _, _ => false
  if !directRecordUpdate && !isStateTransitionValue env 64 false value then none else
  if !stateTransitionNeedsSequencing env 64 value then none else
  match strip source with
  | .bvar _ => some source
  | source =>
      if isConstNamed source ``methodArgRef || isConstNamed source ``localRef then
        some source
      else none

private structure NestedStateTransition where
  transition : Expr
  typedSource : Expr
  nestedType : Name
  fieldPrefix : String
  /-- Composed outer state, its mutable source, and the outer state type. -/
  outerOwner? : Option (Expr × Expr × Name) := none

private structure NestedStateNormalization where
  prior : Array Ops.Op
  transition : Expr
  typedSource : Expr
  outerState : Expr

/-- Find a structure-valued field transition embedded directly in an outer record update. Lean's
zeta reduction commonly turns `let book := update s.book; { s with book }` into exactly this shape.
Lowering the nested transition first prevents every leaf projection from independently expanding
the same helper, while retaining a target-neutral flattened field prefix. -/
private def nestedSequentialTransition? (env : Environment) (state : Expr)
    (statePrefix : String) : Option NestedStateTransition := Id.run do
  let state := strip state
  let some fields := userCtorFields env state | return none
  let some ctor := state.getAppFn.constName? | return none
  let some (.ctorInfo info) := env.find? ctor | return none
  let names := getStructureFields env info.induct
  for h : i in [:fields.size] do
    if i < names.size then
      let some fieldType := fieldTypeExpr env info.induct names[i]! | continue
      let some fieldTypeName := fieldType.consumeMData.getAppFn.constName? | continue
      if fieldTypeName != info.induct && isUserType env fieldTypeName &&
          isStructure env fieldTypeName then
        let transition := strip fields[i]
        if isStateTransitionValue env 64 false transition &&
            stateTransitionNeedsSequencing env 64 transition then
          let typedSource := inlineTypedStateSource env 64 transition
          if typedSource != transition then
            let fieldName := names[i]!.toString
            let pathPrefix :=
              if statePrefix.isEmpty then fieldName else s!"{statePrefix}_{fieldName}"
            let outerOwner? :=
              match typedSource.getAppFn.constName? with
              | some projection =>
                match env.getProjectionFnInfo? projection with
                | some projectionInfo =>
                  let args := typedSource.getAppArgs
                  if h : args.size > 0 then
                    let owner := args[args.size - 1]
                    let root := inlineStateSource env 64 owner
                    if owner == root then none else
                    match env.find? projectionInfo.ctorName with
                    | some (.ctorInfo ownerCtor) => some (owner, root, ownerCtor.induct)
                    | _ => none
                  else none
                | none => none
              | none => none
            return some {
              transition := transition
              typedSource := typedSource
              nestedType := fieldTypeName
              fieldPrefix := pathPrefix
              outerOwner? := outerOwner?
            }
  return none

private def stateNamesAlias (left right : String) : Bool :=
  left == right || left.startsWith (right ++ "_") || right.startsWith (left ++ "_")

private partial def valReadsWritten (written : Array String) : Ops.Val → Bool
  | .arg _ | .local _ | .lit _ | .loopIx => false
  | .field base name => written.any (stateNamesAlias name) || valReadsWritten written base
  | .indexGet base name index _ _ =>
      written.any (stateNamesAlias name) ||
        valReadsWritten written base || valReadsWritten written index
  | .bitNot value => valReadsWritten written value
  | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
  | .shiftL lhs rhs | .shiftR lhs rhs
  | .addU64 lhs rhs | .subU64 lhs rhs | .mulU64 lhs rhs
  | .divU64 lhs rhs | .modU64 lhs rhs =>
      valReadsWritten written lhs || valReadsWritten written rhs
  | .select _ lhs rhs thn els =>
      valReadsWritten written lhs || valReadsWritten written rhs ||
        valReadsWritten written thn || valReadsWritten written els
  | .ext _ operands => operands.any (valReadsWritten written)

private structure SnapshotState where
  written : Array String := #[]
  bindings : Array (Ops.Val × Nat) := #[]
  prelude : Array Ops.Op := #[]

private def SnapshotState.snapshot (base : Nat) (state : SnapshotState)
    (value : Ops.Val) : SnapshotState × Ops.Val :=
  match state.bindings.find? (·.1 == value) with
  | some (_, localIx) => (state, .local localIx)
  | none =>
    let localIx := base + state.bindings.size
    ({ state with
        bindings := state.bindings.push (value, localIx)
        prelude := state.prelude.push (.letLocal localIx value) },
      .local localIx)

/--
Lean record-update RHS expressions all observe the pre-update value. Keep flat write Ops, but
snapshot only expressions that a preceding write in this same source update would invalidate.
-/
private def snapshotStateUpdate (base : Nat) (ops : Array Ops.Op) : Array Ops.Op := Id.run do
  let mut state : SnapshotState := {}
  let mut body : Array Ops.Op := #[]
  for op in ops do
    match op with
    | .indexSetLeaf name index value len leaf =>
      let (next, index) :=
        if valReadsWritten state.written index then state.snapshot base index else (state, index)
      state := next
      let (next, value) :=
        if valReadsWritten state.written value then state.snapshot base value else (state, value)
      state := { next with written := next.written.push name }
      body := body.push (.indexSetLeaf name index value len leaf)
    | .indexSet name index value len offset =>
      let (next, index) :=
        if valReadsWritten state.written index then state.snapshot base index else (state, index)
      state := next
      let (next, value) :=
        if valReadsWritten state.written value then state.snapshot base value else (state, value)
      state := { next with written := next.written.push name }
      body := body.push (.indexSet name index value len offset)
    | .storeField name value =>
      let (next, value) :=
        if valReadsWritten state.written value then state.snapshot base value else (state, value)
      state := { next with written := next.written.push name }
      body := body.push (.storeField name value)
    | .okState value =>
      let (next, value) :=
        if valReadsWritten state.written value then state.snapshot base value else (state, value)
      state := next
      body := body.push (.okState value)
    | op => body := body.push op
  return state.prelude ++ body

private def decodeYieldState (env : Environment) (fuel localDepth : Nat) (state : Expr)
    (appliedBases : Array Expr := #[]) (stateType? : Option Name := none)
    (statePrefix : String := "") (deepScalars : Bool := false) :
    Except String (Array Ops.Op) :=
  match fuel with
  | 0 => .error "extract/unsupported: inline state depth"
  | fuel' + 1 =>
    let raw := strip state
    let sequential? : Option (Expr × Expr × Expr) :=
      match raw with
      | .letE _ type value body _ =>
          (sequentialStateSource? env type value stateType?).map fun source =>
            (value, source, body)
      | _ => none
    let ordinaryLet? : Option (Expr × Expr × Expr) :=
      match raw with
      | .letE _ type value body _ => some (type, value, body)
      | _ => none
    match sequential?, ordinaryLet? with
    | some (value, source, body), _ =>
      match decodeYieldState env fuel' localDepth value appliedBases stateType? statePrefix deepScalars,
          decodeYieldState env fuel' localDepth (body.instantiate1 source) appliedBases
            stateType? statePrefix deepScalars with
      | .ok prior, .ok continuation => .ok (prior ++ continuation)
      | .error reason, _ =>
          .error s!"extract/unsupported: sequential inline state binding: {reason}"
      | _, .error reason => .error reason
    | none, some (type, value, body) =>
      let scalarType := type.consumeMData.getAppFn.constName?
      if scalarType == some ``UInt64 then
        match localScalarValue? env (if deepScalars then 128 else 32) value with
        | some localValue =>
          if shouldMaterializeLocal type localValue then
            let marker := mkApp (mkConst ``localRef) (mkNatLit localDepth)
            match decodeYieldState env fuel' (localDepth + 1)
                (body.instantiate1 marker) appliedBases stateType? statePrefix deepScalars with
            | .ok continuation => .ok (#[.letLocal localDepth localValue] ++ continuation)
            | .error reason => .error reason
          else
            decodeYieldState env fuel' localDepth (body.instantiate1 value) appliedBases stateType?
              statePrefix deepScalars
        | none =>
            decodeYieldState env fuel' localDepth (body.instantiate1 value) appliedBases stateType?
              statePrefix deepScalars
      else
        decodeYieldState env fuel' localDepth (body.instantiate1 value) appliedBases stateType?
          statePrefix deepScalars
    | none, none =>
      let state0 := raw
      let appliedBases := addAppliedBases #[] <|
        appliedBases.map fun base => strip (substLets 256 base)
      if appliedBases.contains state0 then
        .ok #[]
      else if let some (name, unfolded) := unfoldUserHelper env state0 then do
        let args := state0.getAppArgs
        let (prior, normalized, bodyAppliedBases) ←
          if h : args.size > 0 then
            let base := args[0]
            let source :=
              if statePrefix.isEmpty then inlineStateSource env 64 base
              else inlineTypedStateSource env 64 base
            if source == base then
              .ok (#[], unfolded, appliedBases)
            else do
              let prior ← decodeYieldState env fuel' localDepth base appliedBases stateType?
                statePrefix deepScalars
              let normalized := unfolded.replace fun e => if e == base then some source else none
              let bodyAppliedBases := addAppliedBases appliedBases #[base]
              let bodyAppliedBases :=
                addAppliedBases bodyAppliedBases (projectedInlineBases env 64 base)
              .ok (prior, normalized, bodyAppliedBases)
          else
            .ok (#[], unfolded, appliedBases)
        match decodeYieldState env fuel' localDepth normalized bodyAppliedBases stateType?
            statePrefix deepScalars with
        | .ok ops => .ok (prior ++ ops)
        | .error reason => .error s!"extract/unsupported: inline state {name}: {reason}"
      else if (isConstNamed state0 ``ite || isConstNamed state0 ``dite) &&
          state0.getAppArgs.size ≥ 2 then
        let args := state0.getAppArgs
        let peelProofLam (e : Expr) : Expr :=
          match strip e with
          | .lam _ _ body _ => body.lowerLooseBVars 1 1
          | e => e
        let thn := peelProofLam args[args.size - 2]!
        let els := peelProofLam args[args.size - 1]!
        match args.findSome? (asCondition env),
            decodeYieldState env fuel' localDepth thn appliedBases stateType? statePrefix deepScalars,
            decodeYieldState env fuel' localDepth els appliedBases stateType? statePrefix deepScalars with
        | some (cmp, lhs, rhs), .ok thnOps, .ok elsOps =>
          .ok #[.ite cmp lhs rhs thnOps elsOps]
        | none, _, _ =>
          .error s!"extract/unsupported: inline state condition: {args[args.size - 4]!}"
        | _, .error reason, _ => .error s!"extract/unsupported: inline state then: {reason}"
        | _, _, .error reason => .error s!"extract/unsupported: inline state else: {reason}"
      else if let some nested := nestedSequentialTransition? env state0 statePrefix then do
        let normalized : NestedStateNormalization ←
          match nested.outerOwner? with
          | none => .ok (NestedStateNormalization.mk #[] nested.transition
              nested.typedSource state0)
          | some (owner, root, ownerType) => do
            let prior ← decodeYieldState env fuel' localDepth owner appliedBases
              (some ownerType) "" deepScalars
            -- The composed owner may itself contain the nested transition whose result is also
            -- referenced by a scalar argument of the later helper (for example an allocated
            -- address read from a just-pruned tree). That transition has already run as part of
            -- `prior`; rewrite the exact same-typed value to its normalized projection as well.
            let appliedNested? := nestedSequentialTransition? env owner ""
            let rewriteApplied (e : Expr) : Expr :=
              let e := e.replace fun candidate => if candidate == owner then some root else none
              match appliedNested? with
              | none => e
              | some applied =>
                let source := applied.typedSource.replace fun candidate =>
                  if candidate == owner then some root else none
                let appliedSourceVal := val env applied.typedSource
                e.replace fun candidate =>
                  let candidateSource := inlineTypedStateSource env 64 candidate
                  let sameTypedSource := candidateSource == applied.typedSource ||
                    (appliedSourceVal.isSome && val env candidateSource == appliedSourceVal)
                  if candidate == applied.transition || (sameTypedSource &&
                      isStateTransitionValue env 64 false candidate) then
                    some source
                  else none
            let transition :=
              rewriteApplied nested.transition
            let typedSource :=
              rewriteApplied nested.typedSource
            let outerState := state0.replace fun e => if e == owner then some root else none
            .ok (NestedStateNormalization.mk prior transition typedSource outerState)
        let nestedOps ←
          match decodeYieldState env fuel' localDepth normalized.transition appliedBases
              (some nested.nestedType) nested.fieldPrefix deepScalars with
          | .ok ops =>
              let fieldNames := (getStructureFields env nested.nestedType).map (·.toString)
              .ok (dropNestedStateTerminals
                (ops.map (qualifyNestedStateOp nested.fieldPrefix fieldNames)))
          | .error reason =>
              .error s!"extract/unsupported: nested sequential state field: {reason}"
        let continuationState :=
          normalized.outerState.replace fun e =>
            if e == normalized.transition then some normalized.typedSource else none
        match decodeYieldState env fuel' localDepth continuationState appliedBases stateType?
            statePrefix deepScalars with
        | .ok continuation =>
            .ok (dropNestedRootStores nested.fieldPrefix
              (normalized.prior ++ nestedOps ++ continuation))
        | .error reason => .error reason
      else do
        let priorBase? := findProjectedInlineBase env 64 state0
        let prior ←
          match priorBase? with
          | none => .ok #[]
          | some base =>
            if appliedBases.contains base then .ok #[] else match unfoldUserHelper env base with
            | some (name, _) =>
              -- Keep the helper application intact here. Its normal decode path sequences the
              -- state argument before β-expanded scalar lets; decoding the body directly would
              -- read the pre-transition state and duplicate those lets through every projection.
              match decodeYieldState env fuel' localDepth base appliedBases stateType?
                  statePrefix deepScalars with
              | .ok ops => .ok ops
              | .error reason =>
                .error s!"extract/unsupported: projected inline state {name}: {reason}"
            | none => .error "extract/unsupported: projected inline state"
        -- The prior transition has now run. Rewrite outer projections of its result back to
        -- the helper's source state expression; state-loop normalization interprets those
        -- projections against the current mutable state, preserving the sequential semantics.
        let outerState :=
          match priorBase? with
          | none => state0
          | some base =>
            let args := base.getAppArgs
            if h : args.size > 0 then
              let sourceState := args[0]
              state0.replace fun e => if e == base then some sourceState else none
            else state0
        let outerAppliedBases :=
          match priorBase? with
          | some base =>
            let bases := addAppliedBases appliedBases #[base]
            addAppliedBases bases (projectedInlineBases env 64 base)
          | none => appliedBases
        let dynamic := (collectIndexSets env outerState (deduplicate := true)
          (appliedBases := outerAppliedBases)).map (qualifyDynamicStateOp statePrefix)
        let static := (flattenLeaves env statePrefix outerState outerAppliedBases).map fun p =>
          (.storeField p.1 p.2 : Ops.Op)
        let update := snapshotStateUpdate localDepth
          (dynamic ++ dropVectorRootStores dynamic static)
        .ok (prior ++ update)

/-- State loop 的 `yield newState` 只写账户并继续，不生成 commit/exit。 -/
private def asYieldStores (env : Environment) (e : Expr) (localDepth : Nat)
    (stateType? : Option Name := none) (deepScalars : Bool := false) :
    Option (Except String (Array Ops.Op)) :=
  match findYieldPayload e with
  | none => none
  | some state => some (decodeYieldState env 128 localDepth state (stateType? := stateType?)
      (deepScalars := deepScalars))

/-- An inline State helper used as the state component of `.ok (state, ret)` still owns a real
transition. Decode that transition before returning the pair's explicit scalar result. -/
private def asInlineStateSuccess (env : Environment) (e : Expr) (localDepth : Nat)
    (stateType? : Option Name := none) (deepScalars : Bool := false) :
    Option (Except String (Array Ops.Op)) :=
  let e := peelControl 8 (dropUnusedHeadLets 32 e)
  if !isConstNamed e ``Except.ok || e.getAppArgs.size < 1 then none else
  let pair := strip e.getAppArgs[e.getAppArgs.size - 1]!
  if !isConstNamed pair ``Prod.mk || pair.getAppArgs.size < 2 then none else
  let args := pair.getAppArgs
  let state := args[args.size - 2]!
  let result := args[args.size - 1]!
  if (unfoldUserHelper env state).isNone then none else
  some do
    let value ←
      match val env result with
      | some value => .ok value
      | none => .error "extract/unsupported: inline state success result"
    let stores ← decodeYieldState env 128 localDepth state (stateType? := stateType?)
      (deepScalars := deepScalars)
    return stores.push (.okState value)

private def decodePlain (env : Environment) (e : Expr) (stateful : Bool)
    (localDepth : Nat) (stateType? : Option Name := none) (deepScalars : Bool := false) :
    Except String (Array Ops.Op) :=
  -- 必须在 peelLets 之前找效应：剥掉 `have sent := …` 后调用就没了。
  if let some inv := findInvoke env 16 e then
    invokeOpsWithRet env e inv
  else if let some ops := decodeEvmEffect env e then
    .ok ops
  else if let some (n, addend) := findForIn env e then
    .ok #[.forAccum n addend localDepth, .returnU64 (.local localDepth)]
  else if let some result := asYieldStores env e localDepth stateType? deepScalars then
    result
  else if let some result := asInlineStateSuccess env e localDepth stateType? deepScalars then
    result
  else
  -- Record updates repeat one shared constructor through every unchanged projection. Emit each
  -- exact Vector.set node once; separate branch/set expressions remain distinct.
  let isets := collectIndexSets env e (deduplicate := true)
  if isets.size ≥ 1 then
    match asStoreFields env e true with
    | some stores =>
      .ok (snapshotStateUpdate localDepth (isets ++ dropVectorRootStores isets stores))
    | none =>
      match isets[isets.size - 1]! with
      | .indexSetLeaf _ _ v _ _ | .indexSet _ _ v _ _ =>
        -- `.ok ({ state with xs := xs.set i value }, ret)` returns its explicit second
        -- component, which need not be `value`. Loop yields have no public return and keep
        -- the written value as their internal fallback.
        let ret := if isForInStep e then v else (findOkRet env e).getD v
        .ok (snapshotStateUpdate localDepth (isets.push (.okState ret)))
      | _ => .ok isets
  else if let some op := findIndexSet env e then
    match op with
    | .indexSetLeaf _ _ v _ _ | .indexSet _ _ v _ _ =>
      let ret := if isForInStep e then v else (findOkRet env e).getD v
      .ok (snapshotStateUpdate localDepth #[op, .okState ret])
    | _ => .ok #[op]
  else
  let e := peelControl 8 e
  if isErrorOverflow e then
    .ok #[.errorOverflow]
  else if let some name := errorCtorName e then
    .ok #[.errorNamed name]
  else if let some v := asOkNoop env e then
    .ok #[if stateful then .okState v else .returnU64 v]
  else if let some ops := asStoreFields env e stateful then
    .ok (snapshotStateUpdate localDepth ops)
  else if let some v := asOkState env e then
    .ok #[.okState v]
  else if let some v := asOkScalar env e then
    .ok #[.okState v]
  else if let some vs := asStateFields env e then
    .ok (returnStatesOf vs)
  else if let some v := asStateMk env e then
    .ok #[.returnState v]
  else if isConstNamed e ``Prod.mk && e.getAppArgs.size ≥ 2 then
    match val env e.getAppArgs[e.getAppArgs.size - 2]!,
          val env e.getAppArgs[e.getAppArgs.size - 1]! with
    | some a, some b => .ok #[.returnU64 a, .returnU64 b]
    | _, _ => .error "extract/unsupported: pair return"
  else if let some v := val env e then
    match v with
    | .field _ _ => .ok #[.returnU64 v]
    | .arg _ => .ok #[.returnU64 v]
    | .local _ => .ok #[.returnU64 v]
    | .lit _ => .ok #[.returnU64 v]
    | .clockSlot | .clockEpoch | .unixTime | .slotsPerEpoch | .signerKey0 | .accLamports0 | .accOwner0 | .accDataLen0
    | .accN | .isSigner0 | .isWritable0 | .isExecutable0
    | .accLamports1 | .accOwner1 | .accDataLen1
    | .isSigner1 | .isWritable1 | .isExecutable1 | .findPda _
    | .checkPda _ _ | .rentExemption _ | .cpiReturn | .sha256Lit _ | .keccak256Lit _
    | .accKeyWord _ _ | .accOwnerWord _ _
    | .accLamportsN _ | .accDataLenN _ | .isSignerN _ | .isWritableN _ | .isExecutableN _
    | .signerKeyN _ | .ownerIsSelf _ | .findPdaSeeds _ | .checkPdaSeeds _ _ =>
        .ok #[.returnU64 v]
    | .indexGet .. => .ok #[.returnU64 v]
    | .addU64 .. | .subU64 .. | .mulU64 .. | .divU64 .. | .modU64 .. =>
        .ok #[.returnU64 v]
    | .bitAnd .. | .bitOr .. | .bitXor .. | .bitNot .. | .shiftL .. | .shiftR .. =>
        .ok #[.returnU64 v]
    | v =>
      if Ops.hasEvmLeaf #[.returnU64 v] || Ops.isLangLeaf v then .ok #[.returnU64 v]
      else .error "extract/unsupported: body"
  else
    .error "extract/unsupported: body"

private def findBy (args : Array Expr) (p : Expr → Bool) : Option Expr :=
  args.find? p

private def lastNamedBin (env : Environment) (want : Name) (e : Expr) : Option (Ops.Val × Ops.Val) :=
  let rec go (fuel : Nat) (e : Expr) : Option (Ops.Val × Ops.Val) :=
    match fuel with
    | 0 => none
    | fuel' + 1 =>
      let e := strip e
      if isConstNamed e want then
        match binArgs e with
        | some (l, r) =>
          match val env l, val env r with
          | some lv, some rv => some (lv, rv)
          | _, _ => none
        | none => none
      else
        match e with
        | .letE _ _ value body _ => go fuel' value <|> go fuel' body
        | .lam _ _ body _ => go fuel' body
        | _ => e.getAppArgs.findSome? (go fuel')
  go 16 e

/--
Turn the terminal successes of a scalar `Except` producer into assignments to one join slot.
Checked arithmetic already branches to the enclosing error exit, so operations after a terminal
success are unreachable and must not be copied into the joined path.
-/
private partial def lowerBindProducer (slot : Nat) (ops : Array Ops.Op) :
    Option (Array Ops.Op × Bool × Bool) := Id.run do
  let mut lowered := #[]
  let mut hadSuccess := false
  for op in ops do
    match op with
    | .okState value | .returnU64 value =>
        return some (lowered.push (.setLocal slot value), true, true)
    | .errorOverflow | .errorNamed _ =>
        return some (lowered.push op, hadSuccess, true)
    | .ite cmp lhs rhs thn els =>
        let some (thn', thnSuccess, thnTerminates) := lowerBindProducer slot thn
          | return none
        let some (els', elsSuccess, elsTerminates) := lowerBindProducer slot els
          | return none
        lowered := lowered.push (.ite cmp lhs rhs thn' els')
        hadSuccess := hadSuccess || thnSuccess || elsSuccess
        if thnTerminates && elsTerminates then
          return some (lowered, hadSuccess, true)
    | .letLocal .. | .joinLocal .. | .setLocal ..
    | .checkedAddU64 .. | .checkedSubU64 .. | .checkedMulU64 ..
    | .checkedDivU64 .. | .checkedModU64 .. =>
        lowered := lowered.push op
    | _ => return none
  return some (lowered, hadSuccess, false)

/-- A bind enclosing a loop belongs to the surrounding monadic control flow and must be decoded
before loop discovery. Binds inside the callback body are part of that iteration and do not hide
the state loop itself. -/
private def loopUnderBind (fuel : Nat) (e : Expr) (underBind : Bool := false) : Bool :=
  match fuel with
  | 0 => false
  | fuel' + 1 =>
    let e := strip e
    if e.getAppFn.constName? == some ``ForIn.forIn || endsWith e ".forIn" then underBind
    else if isConstNamed e ``Bind.bind || endsWith e ".bind" then
      let args := e.getAppArgs
      if h : args.size ≥ 2 then
        let producer := args[args.size - 2]
        let continuation := args[args.size - 1]
        -- `forIn ... >>= continuation` is the loop's own sequencing bind. A loop in the
        -- producer is therefore not hidden by this bind; a loop in the continuation is.
        loopUnderBind fuel' producer underBind || loopUnderBind fuel' continuation true
      else
        args.any (loopUnderBind fuel' · true)
    else
      e.getAppArgs.any (loopUnderBind fuel' · underBind)

private def decodeExpr (env : Environment) (fuel : Nat) (e : Expr)
    (stateful : Bool := false) (preserveLocals : Bool := false)
    (localDepth : Nat := 0) (stateType? : Option Name := none)
    (deepScalars : Bool := false) :
    Except String (Array Ops.Op) :=
  match fuel with
  | 0 => .error "extract/unsupported: ite depth"
  | fuel' + 1 => Id.run do
    let (invokes, continuation) := leadingInvokes env e
    if !invokes.isEmpty then
      match decodeExpr env fuel' continuation (stateful := stateful)
          (preserveLocals := preserveLocals) (localDepth := localDepth)
          (stateType? := stateType?) (deepScalars := deepScalars) with
      | .ok decodedOps =>
          let continuationOps :=
            if Ops.hasStoreField decodedOps || Ops.hasIndexSet decodedOps then decodedOps
            else (asStoreFields env continuation true).getD decodedOps
          return .ok (invokes.map invokeOp ++ continuationOps)
      | .error reason =>
          return .error s!"extract/unsupported: invoke sequence continuation: {reason}"
    let stripped := strip e
    if isConstNamed stripped ``Id.run then
      if let some guarded := guardedRunBody? 64 stripped then
        return decodeExpr env fuel' guarded (stateful := stateful)
          (preserveLocals := preserveLocals) (localDepth := localDepth)
          (stateType? := stateType?) (deepScalars := deepScalars)
    match strip e with
    | .letE _ ty value body _ =>
      let effectful :=
        (findInvoke env 16 value).isSome || (decodeEvmEffect env value).isSome ||
          (findForIn env value).isSome || (findForBodyExpr env value).isSome
      if !effectful then
        if let some source := sequentialStateSource? env ty value stateType? then
          match decodeYieldState env 128 localDepth value (stateType? := stateType?)
              (statePrefix := "") (deepScalars := deepScalars),
              decodeExpr env fuel' (body.instantiate1 source) (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars) with
          | .ok prior, .ok continuation => return .ok (prior ++ continuation)
          | .error reason, _ =>
            return .error s!"extract/unsupported: sequential state binding: {reason}"
          | _, .error reason => return .error reason
        else if ty.consumeMData.getAppFn.constName? == some ``UInt64 then
          match localScalarValue? env (if deepScalars then 128 else 32) value with
          | some localValue =>
            if preserveLocals && shouldMaterializeLocal ty localValue then
              let marker := mkApp (mkConst ``localRef) (mkNatLit localDepth)
              match decodeExpr env fuel' (body.instantiate1 marker)
                  (stateful := stateful) (preserveLocals := preserveLocals)
                  (localDepth := localDepth + 1) (stateType? := stateType?)
                  (deepScalars := deepScalars) with
              | .ok ops => return .ok (#[.letLocal localDepth localValue] ++ ops)
              | .error reason => return .error reason
            else
              return decodeExpr env fuel' (body.instantiate1 value)
                (stateful := stateful) (preserveLocals := preserveLocals)
                (localDepth := localDepth) (stateType? := stateType?)
                (deepScalars := deepScalars)
          | _ =>
            return decodeExpr env fuel' (body.instantiate1 value)
              (stateful := stateful) (preserveLocals := preserveLocals)
              (localDepth := localDepth) (stateType? := stateType?)
              (deepScalars := deepScalars)
        else
          return decodeExpr env fuel' (body.instantiate1 value)
            (stateful := stateful) (preserveLocals := preserveLocals)
            (localDepth := localDepth) (stateType? := stateType?)
            (deepScalars := deepScalars)
    | _ => pure ()
    -- Branch decoders normalize their arms independently. Zeta-reducing the entire branch here
    -- duplicates let-bound State transitions into every projection before the sequential-state
    -- boundary can consume them, making composed record updates exponential.
    let structured := strip e
    let fullySubstituted :=
      if isConstNamed structured ``ite || isConstNamed structured ``dite then e
      else substLets 256 e
    let controlled := peelControl 16 fullySubstituted
    let e :=
      if (unfoldUserHelper env fullySubstituted).isSome then fullySubstituted
      else if (unfoldUserHelper env controlled).isSome then controlled
      else e
    let e0 := strip e
    if (isConstNamed e0 ``Bind.bind || endsWith e0 ".bind") && e0.getAppArgs.size ≥ 2 then
      let args := e0.getAppArgs
      let producer := args[args.size - 2]!
      let continuation := args[args.size - 1]!
      match strip continuation with
      | .lam _ ty body _ =>
        if ty.consumeMData.getAppFn.constName? == some ``UInt64 then
          match decodeExpr env fuel' producer (preserveLocals := preserveLocals)
              (localDepth := localDepth + 1) (stateType? := stateType?)
              (deepScalars := deepScalars) with
          | .error reason =>
              return .error s!"extract/unsupported: bind producer: {reason}"
          | .ok producerOps =>
            match lowerBindProducer localDepth producerOps with
            | some (joinedProducer, true, true) =>
              let marker := mkApp (mkConst ``localRef) (mkNatLit localDepth)
              match decodeExpr env fuel' (body.instantiate1 marker) (stateful := stateful)
                  (preserveLocals := preserveLocals) (localDepth := localDepth + 1)
                  (stateType? := stateType?) (deepScalars := deepScalars) with
              | .ok continuationOps =>
                  return .ok (#[.joinLocal localDepth] ++ joinedProducer ++ continuationOps)
              | .error reason =>
                  return .error s!"extract/unsupported: bind continuation: {reason}"
            | _ =>
                return .error "extract/unsupported: bind producer is not a scalar control value"
        else
          pure ()
      | _ => pure ()
    let stateLoop? : Option (Except String (Array Ops.Op)) :=
      -- State-loop callbacks capture scalar outer lets by value, while their mutable state binder
      -- must remain visible so `findForStateExpr` can distinguish them from ordinary loops.
      match if loopUnderBind 64 e then none else findForStateExpr env e with
      | none => none
      | some (n, initial, bodyE, continuation) =>
        if isForInDone bodyE then none else
        match decodeYieldState env 128 localDepth initial (stateType? := stateType?),
            decodeExpr env fuel' bodyE (stateful := true)
              (preserveLocals := preserveLocals) (localDepth := localDepth)
              (stateType? := stateType?) (deepScalars := n > 4) with
        | .error reason, _ =>
            some (.error s!"extract/unsupported: state loop initial value: {reason}")
        | _, .error reason => some (.error s!"extract/unsupported: state loop body: {reason}")
        | .ok initialOps, .ok bodyOps =>
          if Ops.hasStoreField bodyOps || Ops.hasIndexSet bodyOps then
            match decodeExpr env fuel' continuation (stateful := true)
                (preserveLocals := preserveLocals)
                (localDepth := localDepth) (stateType? := stateType?)
                (deepScalars := n > 4) with
            | .error reason =>
              some (.error s!"extract/unsupported: state loop continuation: {reason}")
            | .ok continuationOps =>
              some (.ok (initialOps ++ #[.forBody n (bodyOps.map rewriteLoopOp)] ++
                continuationOps))
          else none
    if let some result := stateLoop? then
      return result
    else if (isConstNamed e0 ``ite || isConstNamed e0 ``dite) && e0.getAppArgs.size ≥ 5 then
      -- 已经是比较 / dite，不要再往下搜 forIn（循环体自己就是 ite）。
      pure ()
    else if let some inv := findInvoke env 16 e then
      return invokeOpsWithRet env e inv
    else if let some ops := decodeEvmEffect env e then
      return .ok ops
    else if let some (n, addend) := findForIn env e then
      return .ok #[.forAccum n addend localDepth, .returnU64 (.local localDepth)]
    else if let some (n, bodyE) := findForBodyExpr env e then
      match decodeExpr env fuel' bodyE (preserveLocals := preserveLocals)
          (localDepth := localDepth) (stateType? := stateType?)
          (deepScalars := deepScalars) with
      | .ok ops => return .ok #[.forBody n (ops.map rewritePlainLoopOp), .errorOverflow]
      | .error r => return .error r
    let e := strip e
    if (isConstNamed e ``ite || isConstNamed e ``dite) && e.getAppArgs.size ≥ 5 then
      let args := e.getAppArgs
      let rec peelProofLam (fuel : Nat) (lower : Bool) (e : Expr) : Expr :=
        match fuel with
        | 0 => e
        | fuel' + 1 =>
          match strip e with
          -- 先代入 `have __src`，再降 proof λ。反过来会把 `h` 叠到 `__src` 上。
          | .lam _ _ body _ =>
            let body := substIteLets 16 body
            let body := if lower then body.lowerLooseBVars 1 1 else body
            peelProofLam fuel' lower body
          | e => e
      -- 不在这里 peelLets：`let debit := evmMapSetAddr …` 必须留给 decodeEvmEffect。
      -- 只代 then / else：入口代整个 ite 会把 `have y` 塞进 `y ≠ 0`，asCmp 认不出。
      let tRaw := args[args.size - 2]!
      let fRaw := args[args.size - 1]!
      let lower :=
        stateful ||
          (!(collectIndexSets env tRaw).isEmpty &&
            !isForInStep tRaw && !isForInStep fRaw)
      let t := peelProofLam 4 lower tRaw
      let f := peelProofLam 4 stateful fRaw
      let t := if containsStructuredStateLet env 64 t then t else substIteLets 64 t
      let f := if containsStructuredStateLet env 64 f then f else substIteLets 64 f
      let checkedSubMatches (candidate : Expr) : Bool :=
        match asCheckedSubGuard env candidate with
        | none => false
        | some (guardLhs, guardRhs) =>
          let directResult :=
            match strip t with
            | .letE _ _ value _ _ => val env value
            | _ => asOkState env t
          let directMatch :=
            match directResult with
            | some (.subU64 bodyLhs bodyRhs) =>
                guardLhs == bodyLhs && guardRhs == bodyRhs
            | _ => false
          let nestedMatch :=
            match lastNamedBin env ``HSub.hSub t with
            | some (bodyLhs, bodyRhs) =>
                guardLhs == bodyLhs && guardRhs == bodyRhs
            | none => false
          directMatch || nestedMatch
      let rec hasNestedIte (fuel : Nat) (e : Expr) : Bool :=
        match fuel with
        | 0 => false
        | fuel' + 1 =>
          let e := strip e
          if isConstNamed e ``ite || isConstNamed e ``dite then true
          else
            match e with
            | .letE _ _ value body _ =>
                hasNestedIte fuel' value || hasNestedIte fuel' body
            | .lam _ _ body _ => hasNestedIte fuel' body
            | .app fn arg => hasNestedIte fuel' fn || hasNestedIte fuel' arg
            | _ => false
      -- A recursive invoke search must not erase an intervening branch or a sequence of ignored
      -- invokes followed by a state transition. `decodeExpr` owns the latter so it can preserve
      -- every effect and the continuation.
      let (leading, invokeContinuation) := leadingInvokes env t
      let sequencedState := !leading.isEmpty &&
        (containsStructuredStateLet env 2048 invokeContinuation ||
          containsInlineStateTransition env 2048 invokeContinuation)
      let directInvoke :=
        if hasNestedIte 64 t || sequencedState then none
        else findInvoke env 8 t
      if isErrorOverflow f && !isForInYield f then
        if let some condE := findBy args (fun a =>
            (asCmp env a).isSome &&
              (asCheckedAddGuard env a).isNone &&
              (asCheckedMulGuard env a).isNone &&
              !checkedSubMatches a &&
              -- 真支再套 ite 时，`y ≠ 0` 是比较，不是除法守卫。
              ((asNeZero env a).isNone ||
                isConstNamed (peelLets (strip t)) ``ite ||
                  isConstNamed (peelLets (strip t)) ``dite)) then
          let decodedThen := decodeExpr env fuel' t (stateful := stateful)
            (preserveLocals := preserveLocals) (localDepth := localDepth)
            (stateType? := stateType?) (deepScalars := deepScalars)
          let structuredThen := containsStructuredStateLet env 2048 t ||
            containsInlineStateTransition env 2048 t
          if let .ok thn := decodedThen then
            let rec invokeCount (fuel : Nat) (ops : Array Ops.Op) : Nat :=
              match fuel with
              | 0 => 0
              | fuel' + 1 => ops.foldl (init := 0) fun count op =>
                  count + match op with
                  | .invoke .. => 1
                  | .ite _ _ _ nestedThen nestedElse =>
                      invokeCount fuel' nestedThen + invokeCount fuel' nestedElse
                  | .forBody _ body => invokeCount fuel' body
                  | _ => 0
            if 1 < invokeCount 8 thn then
              match asCmp env condE with
              | some (.ne, .lit 0, .lit 1) | some (.ne, .lit 1, .lit 0) =>
                  return .ok thn
              | some (cmp, lv, rv) =>
                  return .ok #[.ite cmp lv rv thn #[.errorOverflow]]
              | none => pure ()
            if thn.any fun | .letLocal .. => true | _ => false then
              match asCmp env condE with
              | some (cmp, lv, rv) =>
                return .ok #[.ite cmp lv rv thn #[.errorOverflow]]
              | none => pure ()
          match asCmp env condE, directInvoke, decodeEvmEffect env t, asIndexSet env t,
              asStoreFields env t true, asOkState env t, decodedThen with
          | some (.ne, .lit 0, .lit 1), some inv, _, _, _, _, _ =>
            return invokeOpsWithRet env t inv
          | some (.ne, .lit 1, .lit 0), some inv, _, _, _, _, _ =>
            return invokeOpsWithRet env t inv
          | some (cmp, lv, rv), some inv, _, _, _, _, _ =>
            match invokeOpsWithRet env t inv with
            | .ok ops => return .ok #[.ite cmp lv rv ops #[.errorOverflow]]
            | .error reason => return .error reason
          | some (cmp, lv, rv), none, some evmOps, _, _, _, _ =>
            return .ok #[.ite cmp lv rv evmOps #[.errorOverflow]]
          | some (cmp, lv, rv), none, none, some iset, _, _, _ =>
            if structuredThen || hasNestedIte 64 t then
              match decodeExpr env fuel' t (stateful := stateful)
                  (preserveLocals := preserveLocals) (localDepth := localDepth)
                  (stateType? := stateType?) (deepScalars := deepScalars) with
              | .ok thn => return .ok #[.ite cmp lv rv thn #[.errorOverflow]]
              | .error r => return .error r
            else
              let isets := collectIndexSets env t
              let ops := if isets.size ≥ 1 then isets else #[iset]
              match asStoreFields env t true with
              | some stores =>
                return .ok #[.ite cmp lv rv
                  (ops ++ dropVectorRootStores ops stores) #[.errorOverflow]]
              | none =>
                match ops[ops.size - 1]! with
                | .indexSetLeaf _ _ v _ _ | .indexSet _ _ v _ _ =>
                  -- 多叶 set 的返回值是 `.ok (_, y)`。循环体不要用 findOkRet。
                  let ret :=
                    if isForInStep t then v else (findOkRet env t).getD v
                  return .ok #[.ite cmp lv rv (ops.push (.okState ret)) #[.errorOverflow]]
                | _ => return .ok #[.ite cmp lv rv ops #[.errorOverflow]]
          | some (cmp, lv, rv), none, none, none, some stores, _, _ =>
            return .ok #[.ite cmp lv rv (snapshotStateUpdate localDepth stores) #[.errorOverflow]]
          | some (cmp, lv, rv), none, none, none, none, some v, _ =>
            return .ok #[.ite cmp lv rv #[.okState v] #[.errorOverflow]]
          | some (cmp, lv, rv), none, none, none, none, none, .ok thn =>
            match decodeExpr env fuel' f (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars) with
            | .ok els => return .ok #[.ite cmp lv rv thn els]
            | .error _ => return .ok #[.ite cmp lv rv thn #[.errorOverflow]]
          | some _, none, none, none, none, none, .error reason =>
            return .error s!"extract/unsupported: comparison continuation: {reason}"
          | _, _, _, _, _, _, _ => return .error "extract/unsupported: ite then/cmp"
        else if let some condE := findBy args (fun a => (asCheckedAddGuard env a).isSome) then
          match asCheckedAddGuard env condE, directInvoke, decodeEvmEffect env t,
              decodeExpr env fuel' t (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars), asStoreFields env t,
              asOkState env t with
          | some (lhs, rhs), some inv, _, _, some stores, _ =>
            return .ok (#[.checkedAddU64 lhs rhs, invokeOp inv] ++ stores)
          | some _, none, some evmOps, _, _, _ =>
            let some (cmp, lv, rv) := asCmp env condE
              | return .error "extract/unsupported: ite then"
            return .ok #[.ite cmp lv rv evmOps #[.errorOverflow]]
          | some (lhs, rhs), none, none, .ok thn, _, _ =>
            -- then 支可以再套比较 / CPI。先做 checked-add，再跑内层。
            -- 内层若只是 okState，仍压成旧的三连。
            match thn.toList with
            | [.okState v] =>
              let dest := match lhs with | .field .. => lhs | _ => v
              return .ok #[.checkedAddU64 lhs rhs, .okState dest, .errorOverflow]
            | _ =>
              return .ok (#[.checkedAddU64 lhs rhs] ++ thn)
          | some (lhs, rhs), none, none, .error _, some stores, _ =>
            return .ok (#[.checkedAddU64 lhs rhs] ++ stores)
          | some (lhs, rhs), none, none, .error _, none, some v =>
            let dest := match lhs with | .field .. => lhs | _ => v
            return .ok #[.checkedAddU64 lhs rhs, .okState dest, .errorOverflow]
          | some _, none, none, .error reason, none, none =>
            return .error s!"extract/unsupported: checked-add continuation: {reason}"
          | _, _, _, _, _, _ => return .error "extract/unsupported: ite then/add"
        else if let some condE := findBy args (fun a =>
            (asCheckedMulGuard env a).isSome && (collectIndexSets env t).isEmpty) then
          match asCheckedMulGuard env condE,
              decodeExpr env fuel' t (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars),
              asStoreFields env t, asOkState env t with
          | some (lhs, rhs), _, some stores, _ =>
            match stores.toList with
            | [.okState v] =>
              let dest := match lhs with | .field .. => lhs | _ => v
              return .ok #[.checkedMulU64 lhs rhs, .okState dest, .errorOverflow]
            | _ =>
              return .ok (#[.checkedMulU64 lhs rhs] ++ stores ++ #[.errorOverflow])
          | some (lhs, rhs), .ok thn, none, _ =>
            match thn.toList with
            | [.okState v] =>
              let dest := match lhs with | .field .. => lhs | _ => v
              return .ok #[.checkedMulU64 lhs rhs, .okState dest, .errorOverflow]
            | _ =>
              return .ok (#[.checkedMulU64 lhs rhs] ++ thn ++ #[.errorOverflow])
          | some (lhs, rhs), .error _, none, some v =>
            let dest := match lhs with | .field .. => lhs | _ => v
            return .ok #[.checkedMulU64 lhs rhs, .okState dest, .errorOverflow]
          | _, _, _, _ => return .error "extract/unsupported: ite then/mul"
        else if let some condE := findBy args (fun a =>
            checkedSubMatches a && (collectIndexSets env t).isEmpty) then
          match asCheckedSubGuard env condE, directInvoke, decodeEvmEffect env t,
              decodeExpr env fuel' t (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars),
              decodeExpr env fuel' f (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars), asStoreFields env t,
              asOkState env t with
          | some _, some inv, _, _, _, _, _ =>
            let some (cmp, lv, rv) := asCmp env condE
              | return .error "extract/unsupported: ite then"
            match invokeOpsWithRet env t inv with
            | .ok ops => return .ok #[.ite cmp lv rv ops #[.errorOverflow]]
            | .error reason => return .error reason
          | some _, none, some evmOps, _, _, _, _ =>
            let some (cmp, lv, rv) := asCmp env condE
              | return .error "extract/unsupported: ite then"
            return .ok #[.ite cmp lv rv evmOps #[.errorOverflow]]
          | some (lhs, rhs), none, none, _, .ok #[.errorOverflow], _, some v =>
            let dest := match lhs with | .field .. => lhs | _ => v
            return .ok #[.checkedSubU64 lhs rhs, .okState dest, .errorOverflow]
          | some _, none, none, .ok thn, .ok els, _, _ =>
            let some (cmp, lv, rv) := asCmp env condE
              | return .error "extract/unsupported: ite then"
            return .ok #[.ite cmp lv rv thn els]
          | some (lhs, rhs), none, none, _, _, some stores, _ =>
            return .ok (#[.checkedSubU64 lhs rhs] ++ stores)
          | some (lhs, rhs), none, none, _, _, none, some v =>
            let dest := match lhs with | .field .. => lhs | _ => v
            return .ok #[.checkedSubU64 lhs rhs, .okState dest, .errorOverflow]
          | _, _, _, _, _, _, _ => return .error "extract/unsupported: ite then/sub"
        else if let some condE := findBy args (fun a =>
            (asNeZero env a).isSome && (collectIndexSets env t).isEmpty) then
          match asNeZero env condE with
          | none => return .error "extract/unsupported: ite then"
          | some den =>
            let v := (asOkState env t).getD (.arg 0)
            let fallback := (.field (.arg 1) "value", den)
            if (lastNamedBin env ``HMod.hMod t).isSome then
              let (lhs, rhs) := (lastNamedBin env ``HMod.hMod t).getD fallback
              return .ok #[.checkedModU64 lhs (if rhs == den then rhs else den), .okState v, .errorOverflow]
            else if (lastNamedBin env ``UInt64.mod t).isSome then
              let (lhs, rhs) := (lastNamedBin env ``UInt64.mod t).getD fallback
              return .ok #[.checkedModU64 lhs (if rhs == den then rhs else den), .okState v, .errorOverflow]
            else
              let (lhs, rhs) := (lastNamedBin env ``HDiv.hDiv t).getD fallback
              return .ok #[.checkedDivU64 lhs (if rhs == den then rhs else den), .okState v, .errorOverflow]
        else
          let condE := args[args.size - 4]!
          match asCondition env condE,
              decodeExpr env fuel' t (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars) with
          | some (cmp, lv, rv), .ok thn =>
            return .ok #[.ite cmp lv rv thn #[.errorOverflow]]
          | _, _ => return .error "extract/unsupported: ite cond"
      else
        let isValueCmp (a : Expr) : Bool :=
          (asCmp env a).isSome &&
            (asCheckedAddGuard env a).isNone &&
            (asCheckedMulGuard env a).isNone &&
            !checkedSubMatches a
        if isForInYield f && !stateful then
          let some condE := findBy args isValueCmp <|> findBy args (fun a => (asCmp env a).isSome)
            | return .error s!"extract/unsupported: ite cond: {args[args.size - 4]!}"
          let some (cmp, lv, rv) := asCmp env condE
            | return .error s!"extract/unsupported: ite cond: {condE}"
          match decodeExpr env fuel' t (stateful := stateful)
              (preserveLocals := preserveLocals) (localDepth := localDepth)
              (stateType? := stateType?) (deepScalars := deepScalars) with
          | .ok thn => return .ok #[.ite cmp lv rv thn #[]]
          | .error r => return .error s!"extract/unsupported: forBody then {r}"
        let some condE := findBy args isValueCmp <|> findBy args (fun a => (asCmp env a).isSome)
          | match asCondition env args[args.size - 4]! with
            | some condition =>
              match decodeExpr env fuel' t (stateful := stateful)
                    (preserveLocals := preserveLocals) (localDepth := localDepth)
                    (stateType? := stateType?) (deepScalars := deepScalars),
                  decodeExpr env fuel' f (stateful := stateful)
                    (preserveLocals := preserveLocals) (localDepth := localDepth)
                    (stateType? := stateType?) (deepScalars := deepScalars) with
              | .ok thn, .ok els => return .ok #[.ite condition.1 condition.2.1 condition.2.2 thn els]
              | .error r, _ =>
                return .error (if stateful then s!"state loop then: {r}" else s!"ite then: {r}")
              | _, .error r =>
                return .error (if stateful then s!"state loop else: {r}" else s!"ite else: {r}")
            | none => return .error s!"extract/unsupported: ite cond: {args[args.size - 4]!}"
        let some (cmp, lv, rv) := asCmp env condE
          | return .error s!"extract/unsupported: ite cond: {condE}"
        match decodeExpr env fuel' t (stateful := stateful)
              (preserveLocals := preserveLocals) (localDepth := localDepth)
              (stateType? := stateType?) (deepScalars := deepScalars),
            decodeExpr env fuel' f (stateful := stateful)
              (preserveLocals := preserveLocals) (localDepth := localDepth)
              (stateType? := stateType?) (deepScalars := deepScalars) with
        | .ok thn, .ok els => return .ok #[.ite cmp lv rv thn els]
        | .error r, _ =>
          return .error (if stateful then s!"state loop then: {r}" else s!"ite then: {r}")
        | _, .error r =>
          return .error (if stateful then s!"state loop else: {r}" else s!"ite else: {r}")
    else if let some ops := decodeEvmEffect env e then
      return .ok ops
    else if let some inv := decodeInvokeArgs env e <|> findInvoke env 8 e then
      return invokeOpsWithRet env e inv
    else if let some (name, unfolded) := unfoldUserHelper env e then
      match decodeExpr env fuel' (substIteLets 256 unfolded) (stateful := stateful)
          (preserveLocals := preserveLocals) (localDepth := localDepth)
          (stateType? := stateType?) (deepScalars := deepScalars) with
      | .ok ops => return .ok ops
      | .error reason => return .error s!"extract/unsupported: inline {name}: {reason}"
    else if let some reduced := reduceUInt64NewtypeMatch? env e then
      return decodeExpr env fuel' reduced (stateful := stateful)
        (preserveLocals := preserveLocals) (localDepth := localDepth)
        (stateType? := stateType?) (deepScalars := deepScalars)
    else if isUInt64VariantMatcher env e then
      let args := e.getAppArgs
      let some matcherName := e.getAppFn.constName?
        | return .error "extract/unsupported: variant matcher name"
      let some info := Lean.Meta.getMatcherInfoCore? env matcherName
        | return .error "extract/unsupported: variant matcher metadata"
      let some variantName := matcherDiscrTypeName? env e
        | return .error "extract/unsupported: variant discriminant type"
      let some payloadWidth := uint64VariantPayloadWidth? env variantName
        | return .error "extract/unsupported: variant payload layout"
      let some disc := args[info.getFirstDiscrPos]?
        | return .error "extract/unsupported: variant discriminant"
      let tag :=
        match val env disc with
        | some (.field base name) =>
          if name.endsWith "_tag" then .field base name else .field base s!"{name}_tag"
        | some base => .field base "variant_tag"
        | none => .field (.arg 0) "variant_tag"
      let payloads : Array Ops.Val := Id.run do
        let mut payloads : Array Ops.Val := #[]
        for index in [:payloadWidth] do
          let payload :=
            match tag with
            | .field base name =>
              let root := if name.endsWith "_tag" then name.dropEnd 4 |>.copy else name
              .field base s!"{root}_p{index}"
            | _ => .field (.arg 0) s!"variant_p{index}"
          payloads := payloads.push payload
        return payloads
      let alternativesResult : Except String (Array (Array Ops.Op)) := Id.run do
        let mut alternatives : Array (Array Ops.Op) := #[]
        for index in [:info.numAlts] do
          let some altInfo := info.altInfos[index]?
            | return .error "extract/unsupported: variant alternative metadata"
          let some altExpr := args[info.getFirstAltPos + index]?
            | return .error "extract/unsupported: variant alternative"
          if altInfo.numFields > payloads.size then
            return .error "extract/unsupported: variant alternative exceeds payload layout"
          let altBody? : Option Expr := Id.run do
            let mut body := altExpr
            for fieldIndex in [:altInfo.numFields] do
              match strip body with
              | .lam _ _ lamBody _ =>
                let marker := mkApp (mkConst ``localRef) (mkNatLit (localDepth + fieldIndex))
                body := lamBody.instantiate1 marker
              | _ => return none
            return some body
          let some altBody := altBody?
            | return .error "extract/unsupported: variant alternative binders"
          -- Lean represents a nullary matcher branch as `Unit → result`; payload alternatives
          -- have already consumed their source-field binders above.
          let altBody := peelMatcherLams 8 altBody
          match decodeExpr env fuel' altBody (stateful := stateful)
              (preserveLocals := preserveLocals)
              (localDepth := localDepth + altInfo.numFields) (stateType? := stateType?)
              (deepScalars := deepScalars) with
          | .ok ops =>
            let mut withPayloads : Array Ops.Op := #[]
            for fieldIndex in [:altInfo.numFields] do
              withPayloads := withPayloads.push
                (.letLocal (localDepth + fieldIndex) payloads[fieldIndex]!)
            alternatives := alternatives.push (withPayloads ++ ops)
          | .error reason => return .error reason
        return .ok alternatives
      match alternativesResult with
      | .error reason => return .error reason
      | .ok alternatives =>
        let mut chain : Array Ops.Op := #[.errorNamed "invalidVariant"]
        for offset in [:alternatives.size] do
          let index := alternatives.size - 1 - offset
          chain := #[.ite .eq tag (.lit (UInt64.ofNat index)) alternatives[index]! chain]
        return .ok chain
    else if isOptionLikeMatcher env e && e.getAppArgs.size ≥ 3 then
      -- `match opt with | none => a | some n => b` → ite (eq tag 0) a b。
      let args := e.getAppArgs
      let disc := args[args.size - 3]!
      let noneE := peelLets args[args.size - 2]!
      let someE := peelLets args[args.size - 1]!
      let tag :=
        match val env disc with
        | some (.field b n) =>
          if n.endsWith "_tag" then .field b n else .field b s!"{n}_tag"
        | some b => .field b "slot_tag"
        | none => .field (.arg 0) "slot_tag"
      let payload :=
        match tag with
        | .field b n =>
          let base := if n.endsWith "_tag" then n.dropEnd 4 |>.copy else n
          .field b s!"{base}_p0"
        | _ => .field (.arg 0) "slot_p0"
      let noneBody := peelMatcherLams 8 noneE
      let someBody := peelMatcherLams 8 someE
      match decodeExpr env fuel' noneBody (stateful := stateful)
          (preserveLocals := preserveLocals) (localDepth := localDepth)
          (stateType? := stateType?) (deepScalars := deepScalars) with
      | .error r => return .error r
      | .ok noneOps =>
        let someOps :=
          match strip someBody with
          | .bvar _ => #[.returnU64 payload]
          | _ =>
            match decodeExpr env fuel' someBody (stateful := stateful)
                (preserveLocals := preserveLocals) (localDepth := localDepth)
                (stateType? := stateType?) (deepScalars := deepScalars) with
            | .ok ops =>
              match ops with
              | #[.returnU64 (.arg _)] => #[.returnU64 payload]
              | #[.returnState (.arg _)] => #[.returnU64 payload]
              | _ => ops
            | .error _ => #[.returnU64 payload]
        return .ok #[.ite .eq tag (.lit 0) noneOps someOps]
    else
      return decodePlain env e stateful localDepth stateType? deepScalars

def decodeBody (env : Environment) (e : Expr) (preserveLocals : Bool := false)
    (stateType? : Option Name := none) :
    Except String (Array Ops.Op) :=
  let (_, body) := peelLams e
  -- Canonicalize syntax-only aliases around control flow before shape decoding.
  -- A method with structured-State sequencing also retains adjacent scalar lets so `decodeExpr`
  -- can materialize bounded lookups instead of duplicating them through every later projection.
  -- Ordinary mutating methods keep their established zeta-normalized Core identity.
  let hasStructuredState := containsStructuredStateLet env 128 body
  let retainLets := hasStructuredState
  let fullySubstituted := if retainLets then body else substLets 256 body
  let body :=
    if (unfoldUserHelper env fullySubstituted).isSome then fullySubstituted
    else if retainLets then body else zetaPureHeadLets env 32 body
  let body := if retainLets then body else substIteLets 256 body
  decodeExpr env 128 body (preserveLocals := preserveLocals) (stateType? := stateType?)

private def writesOptionLeaf (fuel : Nat) (ops : Array Ops.Op) : Bool :=
  match fuel with
  | 0 => false
  | fuel' + 1 =>
    ops.any fun
      | .okState (.field _ n) => n.endsWith "_tag" || n.endsWith "_p0"
      | .okState (.lit _) => true
      | .okState (.arg _) => true
      | .storeField n _ => n.endsWith "_tag" || n.endsWith "_p0"
      | .ite _ _ _ t f => writesOptionLeaf fuel' t || writesOptionLeaf fuel' f
      | _ => false

private def hasIte (ops : Array Ops.Op) : Bool :=
  ops.any fun | .ite .. => true | _ => false

/-- 可变入口必须有 checked 算术、Option 双叶，或比较 ite（窄宽上界）。 -/
def decodeMutating (env : Environment) (e : Expr) (stateType? : Option Name := none) :
    Except String (Array Ops.Op) := do
  let ops ← decodeBody env e true stateType?
  if Ops.hasCheckedArith ops || writesOptionLeaf 8 ops || hasIte ops ||
      Ops.hasInvoke ops || Ops.hasEvmEffect ops || Ops.hasLangOp ops ||
        Ops.hasForAccum ops || Ops.hasIndexSet ops || Ops.hasStoreField ops then
    return ops
  else
    throw "extract/unsupported: mutating method missing checked arith"

private def widthOfType (e : Expr) : Option Nat :=
  match e.consumeMData.getAppFn.constName? with
  | some ``UInt8 => some 1
  | some ``UInt16 => some 2
  | some ``UInt32 => some 4
  | some ``UInt64 => some 8
  | _ => none

/-- 用户参数宽。init 全算；mutate/view 丢掉第一个 state。 -/
private def inferParamWidths (_env : Environment) (e : Expr) (kind : Core.IR.MethodKind) :
    Array Nat :=
  let rec collect (fuel : Nat) (e : Expr) (acc : Array Nat) : Array Nat :=
    match fuel with
    | 0 => acc
    | fuel' + 1 =>
      match strip e with
      | .lam _ ty body _ =>
        collect fuel' body (acc.push ((widthOfType ty).getD 8))
      | .letE _ _ _ body _ => collect fuel' body acc
      | _ => acc
  let widths := collect 32 e #[]
  match kind with
  | .init => widths
  | .increment | .get => if widths.isEmpty then #[] else widths.extract 1 widths.size

private def markMethodArgs (kind : Core.IR.MethodKind) (count : Nat) (body : Expr) : Expr :=
  let marker (index : Nat) := mkApp (mkConst ``methodArgRef) (mkNatLit index)
  let abiIndex (dbIndex : Nat) : Nat :=
    match kind with
    | .init => count - 1 - dbIndex
    | .increment | .get =>
      if dbIndex + 1 == count then count - 1 else count - 2 - dbIndex
  let rec go (depth : Nat) (e : Expr) : Expr :=
    match e with
    | .bvar index =>
      if depth ≤ index && index - depth < count then marker (abiIndex (index - depth)) else e
    | .app fn arg => .app (go depth fn) (go depth arg)
    | .lam name type body info => .lam name (go depth type) (go (depth + 1) body) info
    | .forallE name type body info => .forallE name (go depth type) (go (depth + 1) body) info
    | .letE name type value body nondep =>
      .letE name (go depth type) (go depth value) (go (depth + 1) body) nondep
    | .mdata data body => .mdata data (go depth body)
    | .proj type index value => .proj type index (go depth value)
    | e => e
  go 0 body

def extractMethod (env : Environment) (kind : Core.IR.MethodKind) (n : Name) :
    Except String IR.Method := do
  let some info := env.find? n
    | throw s!"extract/unsupported: unknown {n}"
  let some e := info.value?
    | throw s!"extract/unsupported: no value {n}"
  let sketch := sketchOfExpr e
  let stateType? :=
    match kind, strip e with
    | .init, _ => none
    | _, .lam _ type _ _ => type.consumeMData.getAppFn.constName?
    | _, _ => none
  let (nLams, sourceBody) := peelLams e
  let sourceBody := markMethodArgs kind nLams sourceBody
  let ops0 ←
    match kind with
    | .increment => decodeMutating env sourceBody stateType?
    | _ => decodeBody env sourceBody (stateType? := stateType?)
  let lean := Core.IR.lastName n.toString
  -- Inline entry helpers can own the source loop, so the entry body itself need not expose
  -- `ForIn.forIn`. Explicit stores in the decoded loop distinguish state-carrying loops from
  -- accumulator/early-return loops and are the authoritative post-inline signal.
  let rec hasStateLoop (fuel : Nat) (ops : Array Ops.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 =>
      ops.any fun
        | .forBody _ body =>
            Ops.hasStoreField body || Ops.hasIndexSet body || hasStateLoop fuel' body
        | .ite _ _ _ thn els => hasStateLoop fuel' thn || hasStateLoop fuel' els
        | _ => false
  let stateLoop := hasStateLoop 16 ops0
  let rec capturedStateArg (fuel : Nat) (v : Ops.Val) : Nat :=
    match fuel with
    | 0 => 0
    | fuel' + 1 =>
      let max2 l r := max (capturedStateArg fuel' l) (capturedStateArg fuel' r)
      match v with
      | .field (.arg i) _ => i
      | .field base _ | .bitNot base | .checkPda _ base => capturedStateArg fuel' base
      | .indexGet base _ index _ _ => max2 base index
      | .bitAnd l r | .bitOr l r | .bitXor l r | .shiftL l r | .shiftR l r
      | .addU64 l r | .subU64 l r | .mulU64 l r | .divU64 l r | .modU64 l r
      | .mapGetU64 l r => max2 l r
      | .select _ l r t f => max (max2 l r) (max2 t f)
      | _ => 0
  let normalizeStateLoopVal (fuel : Nat) (v : Ops.Val) : Ops.Val :=
    let expectedStateArg := nLams + 1
    let captured := capturedStateArg fuel v
    let binderShift := if captured > expectedStateArg then captured - expectedStateArg else 0
    let rec go (fuel : Nat) (v : Ops.Val) : Ops.Val :=
      match fuel with
      | 0 => v
      | fuel' + 1 =>
        let state := .arg (nLams - 1)
        match v with
        -- Loop body binders are accumulator 0 and index 1. A dependent branch can insert
        -- additional proof binders; a captured source-state projection witnesses that shift.
        | .arg i =>
            let i := if i ≥ binderShift then i - binderShift else i
            if i ≥ 2 then .arg (i - 2) else .arg i
        | .field _ name => .field state name
        | .indexGet _ name index len off => .indexGet state name (go fuel' index) len off
        | .checkPda seed bump => .checkPda seed (go fuel' bump)
        | .bitAnd l r => .bitAnd (go fuel' l) (go fuel' r)
        | .bitOr l r => .bitOr (go fuel' l) (go fuel' r)
        | .bitXor l r => .bitXor (go fuel' l) (go fuel' r)
        | .bitNot x => .bitNot (go fuel' x)
        | .shiftL l r => .shiftL (go fuel' l) (go fuel' r)
        | .shiftR l r => .shiftR (go fuel' l) (go fuel' r)
        | .select c l r t f => .select c (go fuel' l) (go fuel' r) (go fuel' t) (go fuel' f)
        | .addU64 l r => .addU64 (go fuel' l) (go fuel' r)
        | .subU64 l r => .subU64 (go fuel' l) (go fuel' r)
        | .mulU64 l r => .mulU64 (go fuel' l) (go fuel' r)
        | .divU64 l r => .divU64 (go fuel' l) (go fuel' r)
        | .modU64 l r => .modU64 (go fuel' l) (go fuel' r)
        | v => v
    go fuel v
  let rec normalizeStateLoopOp (fuel : Nat) (op : Ops.Op) : Ops.Op :=
    match fuel with
    | 0 => op
    | fuel' + 1 =>
      let nv := normalizeStateLoopVal fuel'
      match op with
      | .letLocal i v => .letLocal i (nv v)
      | .joinLocal i => .joinLocal i
      | .setLocal i v => .setLocal i (nv v)
      | .checkedAddU64 l r => .checkedAddU64 (nv l) (nv r)
      | .checkedSubU64 l r => .checkedSubU64 (nv l) (nv r)
      | .checkedMulU64 l r => .checkedMulU64 (nv l) (nv r)
      | .checkedDivU64 l r => .checkedDivU64 (nv l) (nv r)
      | .checkedModU64 l r => .checkedModU64 (nv l) (nv r)
      | .ite cmp l r t f =>
          .ite cmp (nv l) (nv r) (t.map (normalizeStateLoopOp fuel'))
            (f.map (normalizeStateLoopOp fuel'))
      | .invoke prog metas data seed bump =>
          .invoke prog metas (data.map (·.map nv)) seed (bump.map nv)
      | .forAccum bound addend resultLocal => .forAccum bound (nv addend) resultLocal
      | .forBody bound body => .forBody bound (body.map (normalizeStateLoopOp fuel'))
      | .indexSetLeaf name index value len leaf =>
          .indexSetLeaf name (nv index) (nv value) len leaf
      | .indexSet name index value len off => .indexSet name (nv index) (nv value) len off
      | .storeField name value => .storeField name (nv value)
      | .okState value => .okState (nv value)
      | .returnU64 value => .returnU64 (nv value)
      | .returnState value => .returnState (nv value)
      | op => op
  let ops0 := if stateLoop then ops0.map (normalizeStateLoopOp 32) else ops0
  -- Resolve entry-parameter markers only after nested callback binders have been normalized.
  let rec flipVal (fuel : Nat) (v : Ops.Val) : Ops.Val :=
    match fuel with
    | 0 => v
    | fuel' + 1 =>
      match v with
      | .arg _ => v
      | .local i =>
        if methodArgLocalBase ≤ i then .arg (i - methodArgLocalBase) else v
      | .field b n => .field (flipVal fuel' b) n
      | .lit _ => v
      | .clockSlot | .clockEpoch | .unixTime | .slotsPerEpoch | .signerKey0 | .accLamports0 | .accOwner0 | .accDataLen0
      | .accN | .isSigner0 | .isWritable0 | .isExecutable0
      | .accLamports1 | .accOwner1 | .accDataLen1
      | .isSigner1 | .isWritable1 | .isExecutable1 | .findPda _
      | .rentExemption _ | .cpiReturn | .sha256Lit _ | .keccak256Lit _
      | .accKeyWord _ _ | .accOwnerWord _ _
      | .accLamportsN _ | .accDataLenN _ | .isSignerN _ | .isWritableN _ | .isExecutableN _
      | .signerKeyN _ | .ownerIsSelf _ | .findPdaSeeds _ | .checkPdaSeeds _ _ => v
      | .checkPda s b => .checkPda s (flipVal fuel' b)
      | .bitAnd l r => .bitAnd (flipVal fuel' l) (flipVal fuel' r)
      | .bitOr l r => .bitOr (flipVal fuel' l) (flipVal fuel' r)
      | .bitXor l r => .bitXor (flipVal fuel' l) (flipVal fuel' r)
      | .bitNot v => .bitNot (flipVal fuel' v)
      | .shiftL l r => .shiftL (flipVal fuel' l) (flipVal fuel' r)
      | .shiftR l r => .shiftR (flipVal fuel' l) (flipVal fuel' r)
      | .indexGet b n i k off =>
          .indexGet (flipVal fuel' b) n (flipVal fuel' i) k off
      | .loopIx => v
      | .select c l r t f =>
          .select c (flipVal fuel' l) (flipVal fuel' r) (flipVal fuel' t) (flipVal fuel' f)
      | .addU64 l r => .addU64 (flipVal fuel' l) (flipVal fuel' r)
      | .subU64 l r => .subU64 (flipVal fuel' l) (flipVal fuel' r)
      | .mulU64 l r => .mulU64 (flipVal fuel' l) (flipVal fuel' r)
      | .divU64 l r => .divU64 (flipVal fuel' l) (flipVal fuel' r)
      | .modU64 l r => .modU64 (flipVal fuel' l) (flipVal fuel' r)
      | .mapGetU64 b k => .mapGetU64 (flipVal fuel' b) (flipVal fuel' k)
      | .mapGetAddr b a0 a1 a2 =>
          .mapGetAddr (flipVal fuel' b) (flipVal fuel' a0) (flipVal fuel' a1) (flipVal fuel' a2)
      | .mapGetPair b a0 a1 a2 c0 c1 c2 =>
          .mapGetPair (flipVal fuel' b) (flipVal fuel' a0) (flipVal fuel' a1)
            (flipVal fuel' a2) (flipVal fuel' c0) (flipVal fuel' c1) (flipVal fuel' c2)
      | v => v
  let rec flipOp (fuel : Nat) (op : Ops.Op) : Ops.Op :=
    match fuel with
    | 0 => op
    | fuel' + 1 =>
      match op with
      | .letLocal i v => .letLocal i (flipVal fuel' v)
      | .joinLocal i => .joinLocal i
      | .setLocal i v => .setLocal i (flipVal fuel' v)
      | .returnState v => .returnState (flipVal fuel' v)
      | .returnU64 v => .returnU64 (flipVal fuel' v)
      | .storeField n v => .storeField n (flipVal fuel' v)
      | .okState v => .okState (flipVal fuel' v)
      | .checkedAddU64 l r => .checkedAddU64 (flipVal fuel' l) (flipVal fuel' r)
      | .checkedSubU64 l r => .checkedSubU64 (flipVal fuel' l) (flipVal fuel' r)
      | .checkedMulU64 l r => .checkedMulU64 (flipVal fuel' l) (flipVal fuel' r)
      | .checkedDivU64 l r => .checkedDivU64 (flipVal fuel' l) (flipVal fuel' r)
      | .checkedModU64 l r => .checkedModU64 (flipVal fuel' l) (flipVal fuel' r)
      | .ite c l r t f =>
        .ite c (flipVal fuel' l) (flipVal fuel' r)
          (t.map (flipOp fuel')) (f.map (flipOp fuel'))
      | .invoke prog metas data seed bump =>
        .invoke prog metas (data.map (·.map (flipVal fuel')))
          seed (bump.map (flipVal fuel'))
      | .evmDeposit v => .evmDeposit (flipVal fuel' v)
      | .evmSendEth a b c d =>
          .evmSendEth (flipVal fuel' a) (flipVal fuel' b) (flipVal fuel' c) (flipVal fuel' d)
      | .evmLog n v => .evmLog n (flipVal fuel' v)
      | .forAccum n v resultLocal => .forAccum n (flipVal fuel' v) resultLocal
      | .forBody n body => .forBody n (body.map (flipOp fuel'))
      | .indexSetLeaf n i v k leaf =>
          .indexSetLeaf n (flipVal fuel' i) (flipVal fuel' v) k leaf
      | .indexSet n i v k off =>
          .indexSet n (flipVal fuel' i) (flipVal fuel' v) k off
      | .mapGetU64 b k => .mapGetU64 (flipVal fuel' b) (flipVal fuel' k)
      | .mapSetU64 b k v =>
          .mapSetU64 (flipVal fuel' b) (flipVal fuel' k) (flipVal fuel' v)
      | .mapGetAddr b a0 a1 a2 =>
          .mapGetAddr (flipVal fuel' b) (flipVal fuel' a0) (flipVal fuel' a1) (flipVal fuel' a2)
      | .mapSetAddr b a0 a1 a2 v =>
          .mapSetAddr (flipVal fuel' b) (flipVal fuel' a0) (flipVal fuel' a1)
            (flipVal fuel' a2) (flipVal fuel' v)
      | .mapGetPair b a0 a1 a2 c0 c1 c2 =>
          .mapGetPair (flipVal fuel' b) (flipVal fuel' a0) (flipVal fuel' a1)
            (flipVal fuel' a2) (flipVal fuel' c0) (flipVal fuel' c1) (flipVal fuel' c2)
      | .mapSetPair b a0 a1 a2 c0 c1 c2 v =>
          .mapSetPair (flipVal fuel' b) (flipVal fuel' a0) (flipVal fuel' a1)
            (flipVal fuel' a2) (flipVal fuel' c0) (flipVal fuel' c1)
            (flipVal fuel' c2) (flipVal fuel' v)
      | .evmTokenTransfer a b c d e f g =>
          .evmTokenTransfer (flipVal fuel' a) (flipVal fuel' b) (flipVal fuel' c)
            (flipVal fuel' d) (flipVal fuel' e) (flipVal fuel' f) (flipVal fuel' g)
      | .evmTokenBalanceOfSelf a b c =>
          .evmTokenBalanceOfSelf (flipVal fuel' a) (flipVal fuel' b) (flipVal fuel' c)
      | .errorOverflow => .errorOverflow
      | .errorNamed n => .errorNamed n
  let ops := ops0.map (flipOp 128)
  let paramCount :=
    match kind with
    | .init => if nLams = 0 then 1 else nLams
    | .increment | .get => if nLams ≤ 1 then 0 else nLams - 1
  let paramWidths := inferParamWidths env e kind
  let retCount :=
    match kind with
    | .get =>
      let nRet := ops.foldl (init := 0) fun acc op =>
        match op with | .returnU64 _ => acc + 1 | _ => acc
      if nRet = 0 then 1 else nRet
    | _ => 1
  return {
    kind, name := n.toString, ixName := Core.IR.ixNameOfLean lean
    paramCount, paramWidths, retCount, sketch, ops
  }

private def isUInt64Type (e : Expr) : Bool :=
  e.consumeMData.getAppFn.constName? == some ``UInt64

private structure SchemaFragment where
  leaves : Array Core.Leaf := #[]
  vectors : Array Core.VectorLayout := #[]

private def SchemaFragment.byteWidth (fragment : SchemaFragment) : Nat :=
  fragment.leaves.foldl (init := 0) fun width leaf => width + leaf.width

private def scalarFragment (name : String) (place : Core.Place)
    (ty : Core.ScalarTy) : SchemaFragment :=
  { leaves := #[{ place, name, ty }] }

private def optionFragment (name : String) (place : Core.Place) : SchemaFragment :=
  { leaves := #[
      { place := place.push .optionTag, name := s!"{name}_tag", ty := .optionTag },
      { place := place.push .optionPayload, name := s!"{name}_p0", ty := .uint 64 }
    ] }

private def variantFragment (typeName name : String) (place : Core.Place)
    (payloadWidth : Nat) : SchemaFragment := Id.run do
  let mut leaves : Array Core.Leaf :=
    #[{ place := place.push .variantTag, name := s!"{name}_tag", ty := .variantTag typeName }]
  for index in [:payloadWidth] do
    leaves := leaves.push {
      place := place.push (.variantPayload index)
      name := s!"{name}_p{index}"
      ty := .uint 64
    }
  return { leaves }

private def leafSchema (env : Environment) (fuel : Nat) (name : String)
    (place : Core.Place) (ty : Expr) : Except String SchemaFragment :=
  match fuel with
  | 0 => .error s!"extract/unsupported: field {name} nest depth"
  | fuel' + 1 =>
    let ty := ty.consumeMData
    if ty.getAppFn.constName? == some ``UInt64 then
      .ok (scalarFragment name place (.uint 64))
    else if ty.getAppFn.constName? == some ``UInt32 then
      .ok (scalarFragment name place (.uint 32))
    else if ty.getAppFn.constName? == some ``UInt16 then
      .ok (scalarFragment name place (.uint 16))
    else if ty.getAppFn.constName? == some ``UInt8 then
      .ok (scalarFragment name place (.uint 8))
    else if ty.getAppFn.constName? == some ``Option then
      let args := ty.getAppArgs
      if args.size ≥ 1 && args[args.size - 1]!.consumeMData.getAppFn.constName? == some ``UInt64 then
        .ok (optionFragment name place)
      else
        .error s!"extract/unsupported: field {name} is not Option UInt64"
    else if ty.getAppFn.constName? == some ``Vector then
      let args := ty.getAppArgs
      if args.size ≥ 2 then
        match asLit 8 args[args.size - 1]! with
        | some (.lit n) =>
          if n.toNat = 0 then
            .error s!"extract/unsupported: field {name} Vector length 0"
          else
            Id.run do
              let mut leaves : Array Core.Leaf := #[]
              let mut vectors : Array Core.VectorLayout := #[]
              let mut elementBytes : Nat := 0
              let mut elementLeaves : Nat := 0
              for i in List.range n.toNat do
                let itemPlace := place.push (.index i)
                match leafSchema env fuel' s!"{name}_{i}" itemPlace args[args.size - 2]! with
                | .error reason => return .error reason
                | .ok item =>
                    if i == 0 then
                      elementBytes := item.byteWidth
                      elementLeaves := item.leaves.size
                    leaves := leaves ++ item.leaves
                    vectors := vectors ++ item.vectors
              let vector : Core.VectorLayout := {
                place, name, length := n.toNat, elementBytes, elementLeaves
              }
              return .ok { leaves, vectors := #[vector] ++ vectors }
        | _ => .error s!"extract/unsupported: field {name} Vector length is not a literal"
      else
        .error s!"extract/unsupported: field {name} is not Vector UInt64 n"
    else if ty.getAppFn.constName? == some ``Array then
      .error s!"extract/unsupported: field {name} Array is not fixed-length; use Vector"
    else if ty.getAppFn.constName? == some ``Bool then
      .ok (scalarFragment name place .bool)
    else if let some tyName := ty.getAppFn.constName? then
      if isEnumLeaf env tyName then
        .ok (scalarFragment name place (.enum tyName.toString))
      else if isUInt64Newtype env tyName then
        .ok (scalarFragment name place (.newtype tyName.toString 64))
      else if isOptionLikeInductive env tyName then
        .ok (optionFragment name place)
      else if let some payloadWidth := uint64VariantPayloadWidth? env tyName then
        .ok (variantFragment tyName.toString name place payloadWidth)
      else if isUserName env tyName && isStructure env tyName &&
          !(isEnumLeaf env tyName) && !(isOptionLikeInductive env tyName) then
        if !(getStructureParentInfo env tyName).isEmpty then
          .error s!"extract/unsupported: field {name} record inheritance"
        else
          let fields := getStructureFields env tyName
          if fields.isEmpty then
            .error s!"extract/unsupported: field {name} record has no fields"
          else
            Id.run do
              let mut acc : SchemaFragment := {}
              let mut ordinal : Nat := 0
              for f in fields do
                if (isSubobjectField? env tyName f).isSome then
                  return .error s!"extract/unsupported: field {name} record inheritance"
                let some fty := fieldTypeExpr env tyName f
                  | return .error s!"extract/unsupported: field {name}.{f} has no type"
                let childPlace := place.push (.field tyName.toString ordinal f.toString)
                match leafSchema env fuel' s!"{name}_{f}" childPlace fty with
                | .error r => return .error r
                | .ok fragment =>
                    acc := {
                      leaves := acc.leaves ++ fragment.leaves
                      vectors := acc.vectors ++ fragment.vectors
                    }
                ordinal := ordinal + 1
              return .ok acc
      else if match env.find? tyName with | some (.inductInfo _) => true | _ => false then
        .error s!"extract/unsupported: field {name} enum has payload"
      else
        .error s!"extract/unsupported: field {name} is not a supported leaf"
    else
      .error s!"extract/unsupported: field {name} is not a supported leaf"

/-- `Examples.Counter.init` → `Counter`。 -/
def programNameOfInit (n : Name) : String :=
  match n with
  | .str (.str _ mod) "init" => mod
  | .str _ "init" => "Program"
  | _ => "Program"

/-- 从 `init` 返回类型收 typed state schema。无 `extends`。 -/
def inferSchema (env : Environment) (initName : Name) : Except String Core.Schema := do
  let some info := env.find? initName
    | throw s!"extract/unsupported: unknown {initName}"
  let some structName := (peelForalls info.type).getAppFn.constName?
    | throw "extract/unsupported: init return is not a structure"
  unless isStructure env structName do
    throw s!"extract/unsupported: init return is not a structure {structName}"
  unless (getStructureParentInfo env structName).isEmpty do
    throw "extract/unsupported: record inheritance"
  let names := getStructureFields env structName
  if names.isEmpty then
    throw "extract/unsupported: structure has no fields"
  let mut leaves : Array Core.Leaf := #[]
  let mut vectors : Array Core.VectorLayout := #[]
  let mut ordinal : Nat := 0
  for n in names do
    if (isSubobjectField? env structName n).isSome then
      throw "extract/unsupported: record inheritance"
    let some ty := fieldTypeExpr env structName n
      | throw s!"extract/unsupported: field {n} has no type"
    let place : Core.Place := {
      steps := #[.field structName.toString ordinal n.toString]
    }
    let fragment ← leafSchema env 8 n.toString place ty
    leaves := leaves ++ fragment.leaves
    vectors := vectors ++ fragment.vectors
    ordinal := ordinal + 1
  return { rootType := structName.toString, leaves, vectors }

/-- Target-neutral physical slots are a derived view of the typed schema. -/
def inferSlots (env : Environment) (initName : Name) : Except String (Array Core.IR.Slot) := do
  return Core.IR.slotsOfSchema (← inferSchema env initName)

def inferFields (env : Environment) (initName : Name) : Except String (Array String) := do
  return (← inferSlots env initName).map (·.name)

private def valFields : Ops.Val → Array String
  | .field _ n => #[n]
  | .arg _ => #[]
  | .local _ => #[]
  | .lit _ => #[]
  | .clockSlot | .clockEpoch | .unixTime | .slotsPerEpoch | .signerKey0 | .accLamports0 | .accOwner0 | .accDataLen0
  | .accN | .isSigner0 | .isWritable0 | .isExecutable0
  | .accLamports1 | .accOwner1 | .accDataLen1
  | .isSigner1 | .isWritable1 | .isExecutable1 | .findPda _
  | .rentExemption _ | .cpiReturn | .sha256Lit _ | .keccak256Lit _
  | .accKeyWord _ _ | .accOwnerWord _ _
  | .accLamportsN _ | .accDataLenN _ | .isSignerN _ | .isWritableN _ | .isExecutableN _
  | .signerKeyN _ | .ownerIsSelf _ | .findPdaSeeds _ | .checkPdaSeeds _ _ => #[]
  | .checkPda _ b => valFields b
  | .bitAnd l r | .bitOr l r | .bitXor l r | .shiftL l r | .shiftR l r =>
      valFields l ++ valFields r
  | .bitNot v => valFields v
  | .indexGet b _ i _ => valFields b ++ valFields i
  | .loopIx => #[]
  | .select _ l r t f => valFields l ++ valFields r ++ valFields t ++ valFields f
  | .addU64 l r | .subU64 l r | .mulU64 l r | .divU64 l r | .modU64 l r =>
      valFields l ++ valFields r
  | .mapGetU64 b k => valFields b ++ valFields k
  | .mapGetAddr b a0 a1 a2 =>
      valFields b ++ valFields a0 ++ valFields a1 ++ valFields a2
  | .mapGetPair b a0 a1 a2 c0 c1 c2 =>
      valFields b ++ valFields a0 ++ valFields a1 ++ valFields a2 ++
        valFields c0 ++ valFields c1 ++ valFields c2
  | v => if Ops.hasEvmLeaf #[.returnU64 v] then #[] else #[]

private def opFields : Ops.Op → Array String
  | .letLocal _ v => valFields v
  | .joinLocal _ => #[]
  | .setLocal _ v => valFields v
  | .checkedAddU64 l r => valFields l ++ valFields r
  | .checkedSubU64 l r => valFields l ++ valFields r
  | .checkedMulU64 l r => valFields l ++ valFields r
  | .checkedDivU64 l r => valFields l ++ valFields r
  | .checkedModU64 l r => valFields l ++ valFields r
  | .ite _ l r t f =>
      valFields l ++ valFields r ++ t.flatMap opFields ++ f.flatMap opFields
  | .invoke _ _ data _ bump =>
      (data.flatMap fun word => word.value?.map valFields |>.getD #[]) ++
        (match bump with | some v => valFields v | none => #[])
  | .evmDeposit v => valFields v
  | .evmSendEth a b c d => valFields a ++ valFields b ++ valFields c ++ valFields d
  | .evmLog _ v => valFields v
  | .forAccum _ v _ => valFields v
  | .forBody _ body => body.flatMap opFields
  | .indexSetLeaf _ i v _ _ | .indexSet _ i v _ _ => valFields i ++ valFields v
  | .storeField n v => #[n] ++ valFields v
  | .mapGetU64 b k => valFields b ++ valFields k
  | .mapSetU64 b k v => valFields b ++ valFields k ++ valFields v
  | .mapGetAddr b a0 a1 a2 => valFields b ++ valFields a0 ++ valFields a1 ++ valFields a2
  | .mapSetAddr b a0 a1 a2 v =>
      valFields b ++ valFields a0 ++ valFields a1 ++ valFields a2 ++ valFields v
  | .mapGetPair b a0 a1 a2 c0 c1 c2 =>
      valFields b ++ valFields a0 ++ valFields a1 ++ valFields a2 ++
        valFields c0 ++ valFields c1 ++ valFields c2
  | .mapSetPair b a0 a1 a2 c0 c1 c2 v =>
      valFields b ++ valFields a0 ++ valFields a1 ++ valFields a2 ++
        valFields c0 ++ valFields c1 ++ valFields c2 ++ valFields v
  | .evmTokenTransfer a b c d e f g =>
      valFields a ++ valFields b ++ valFields c ++ valFields d ++
        valFields e ++ valFields f ++ valFields g
  | .evmTokenBalanceOfSelf a b c => valFields a ++ valFields b ++ valFields c
  | .okState v => valFields v
  | .errorOverflow => #[]
  | .errorNamed _ => #[]
  | .returnU64 v => valFields v
  | .returnState v => valFields v

private def vectorLeafOffset? (schema : Core.Schema) (name leaf : String) : Option Nat :=
  match schema.vector? name with
  | none => none
  | some vector => Id.run do
      let mut offset := 0
      for item in schema.vectorElementLeaves vector do
        if vector.relativeLeafName item == leaf then return some offset
        offset := offset + item.width
      return none

/-- Resolve logical dynamic-vector leaves exactly once, against the typed source schema. -/
private def resolveVectorLeaves (p : IR.Program) : Except String IR.Program := do
  let resolve (name leaf : String) : Except String Nat :=
    match vectorLeafOffset? p.schema name leaf with
    | some offset => pure offset
    | none => throw s!"extract/unsupported: vector {name} has no leaf {leaf}"
  let rec goVal (fuel : Nat) (v : Ops.Val) : Except String Ops.Val :=
    match fuel with
    | 0 => throw "extract/unsupported: value nesting exceeds schema resolution limit"
    | fuel' + 1 =>
      match v with
      | .arg _ | .local _ | .lit _ | .loopIx => pure v
      | .field (.indexGet b n i k _) leaf =>
          return .indexGet (← goVal fuel' b) n (← goVal fuel' i) k (← resolve n leaf)
      | .field b n => return .field (← goVal fuel' b) n
      | .bitAnd l r => return .bitAnd (← goVal fuel' l) (← goVal fuel' r)
      | .bitOr l r => return .bitOr (← goVal fuel' l) (← goVal fuel' r)
      | .bitXor l r => return .bitXor (← goVal fuel' l) (← goVal fuel' r)
      | .bitNot value => return .bitNot (← goVal fuel' value)
      | .shiftL l r => return .shiftL (← goVal fuel' l) (← goVal fuel' r)
      | .shiftR l r => return .shiftR (← goVal fuel' l) (← goVal fuel' r)
      | .indexGet b n i k off =>
          return .indexGet (← goVal fuel' b) n (← goVal fuel' i) k off
      | .select c l r t f =>
          return .select c (← goVal fuel' l) (← goVal fuel' r)
            (← goVal fuel' t) (← goVal fuel' f)
      | .addU64 l r => return .addU64 (← goVal fuel' l) (← goVal fuel' r)
      | .subU64 l r => return .subU64 (← goVal fuel' l) (← goVal fuel' r)
      | .mulU64 l r => return .mulU64 (← goVal fuel' l) (← goVal fuel' r)
      | .divU64 l r => return .divU64 (← goVal fuel' l) (← goVal fuel' r)
      | .modU64 l r => return .modU64 (← goVal fuel' l) (← goVal fuel' r)
      | .ext kind operands => return .ext kind (← operands.mapM (goVal fuel'))
  let normalizeVal := goVal 128
  let rec goOp (fuel : Nat) (op : Ops.Op) : Except String Ops.Op :=
    match fuel with
    | 0 => throw "extract/unsupported: control-flow nesting exceeds schema resolution limit"
    | fuel' + 1 =>
      match op with
      | .letLocal i v => return .letLocal i (← normalizeVal v)
      | .joinLocal i => pure (.joinLocal i)
      | .setLocal i v => return .setLocal i (← normalizeVal v)
      | .checkedAddU64 l r => return .checkedAddU64 (← normalizeVal l) (← normalizeVal r)
      | .checkedSubU64 l r => return .checkedSubU64 (← normalizeVal l) (← normalizeVal r)
      | .checkedMulU64 l r => return .checkedMulU64 (← normalizeVal l) (← normalizeVal r)
      | .checkedDivU64 l r => return .checkedDivU64 (← normalizeVal l) (← normalizeVal r)
      | .checkedModU64 l r => return .checkedModU64 (← normalizeVal l) (← normalizeVal r)
      | .indexSetLeaf n i v k leaf =>
          return .indexSet n (← normalizeVal i) (← normalizeVal v) k (← resolve n leaf)
      | .indexSet n i v k off =>
          return .indexSet n (← normalizeVal i) (← normalizeVal v) k off
      | .ite c l r t f =>
          return .ite c (← normalizeVal l) (← normalizeVal r)
            (← t.mapM (goOp fuel')) (← f.mapM (goOp fuel'))
      | .forAccum n v resultLocal => return .forAccum n (← normalizeVal v) resultLocal
      | .forBody n body => return .forBody n (← body.mapM (goOp fuel'))
      | .storeField n v => return .storeField n (← normalizeVal v)
      | .okState v => return .okState (← normalizeVal v)
      | .errorOverflow => pure .errorOverflow
      | .errorNamed n => pure (.errorNamed n)
      | .returnU64 v => return .returnU64 (← normalizeVal v)
      | .returnState v => return .returnState (← normalizeVal v)
      | .invoke programIx metas data seed bump =>
          return .invoke programIx metas (← data.mapM fun word =>
            match word.value? with
            | some value => do
                let normalized ← normalizeVal value
                pure (word.map fun _ => normalized)
            | none => pure (word.map id)) seed (← bump.mapM normalizeVal)
      | .evmDeposit v => return .evmDeposit (← normalizeVal v)
      | .evmSendEth a b c d =>
          return .evmSendEth (← normalizeVal a) (← normalizeVal b)
            (← normalizeVal c) (← normalizeVal d)
      | .evmLog n v => return .evmLog n (← normalizeVal v)
      | .mapGetU64 b k => return .mapGetU64 (← normalizeVal b) (← normalizeVal k)
      | .mapSetU64 b k v =>
          return .mapSetU64 (← normalizeVal b) (← normalizeVal k) (← normalizeVal v)
      | .mapGetAddr b a0 a1 a2 =>
          return .mapGetAddr (← normalizeVal b) (← normalizeVal a0)
            (← normalizeVal a1) (← normalizeVal a2)
      | .mapSetAddr b a0 a1 a2 v =>
          return .mapSetAddr (← normalizeVal b) (← normalizeVal a0)
            (← normalizeVal a1) (← normalizeVal a2) (← normalizeVal v)
      | .mapGetPair b a0 a1 a2 c0 c1 c2 =>
          return .mapGetPair (← normalizeVal b) (← normalizeVal a0) (← normalizeVal a1)
            (← normalizeVal a2) (← normalizeVal c0) (← normalizeVal c1) (← normalizeVal c2)
      | .mapSetPair b a0 a1 a2 c0 c1 c2 v =>
          return .mapSetPair (← normalizeVal b) (← normalizeVal a0) (← normalizeVal a1)
            (← normalizeVal a2) (← normalizeVal c0) (← normalizeVal c1) (← normalizeVal c2)
            (← normalizeVal v)
      | .evmTokenTransfer a b c d e f g =>
          return .evmTokenTransfer (← normalizeVal a) (← normalizeVal b) (← normalizeVal c)
            (← normalizeVal d) (← normalizeVal e) (← normalizeVal f) (← normalizeVal g)
      | .evmTokenBalanceOfSelf a b c =>
          return .evmTokenBalanceOfSelf (← normalizeVal a) (← normalizeVal b) (← normalizeVal c)
  return { p with methods := ← p.methods.mapM fun m => do
    return { m with ops := ← m.ops.mapM (goOp 128) } }

/-- Make state writeback explicit once, after source schema and normalized Ops are both available. -/
private def evaluateProgram (p : IR.Program) : Except String IR.Program := do
  let mut methods := #[]
  for method in p.methods do
    let evaluation ←
      match Core.evaluate p.schema method.ops with
      | .ok evaluation => pure evaluation
      | .error reason => throw s!"{method.ixName}: {reason}"
    methods := methods.push { method with evaluation }
  return { p with methods }

private def checkUsedFields (p : IR.Program) : Except String Unit := do
  for m in p.methods do
    for op in m.ops do
      for name in opFields op do
        if (Core.IR.fieldWidth p name).isNone then
          throw s!"{m.ixName}: extract/unsupported: unknown field {name}"

/-- Typed initializers must account for every leaf; backends must never invent missing zeros. -/
private def checkInitCoverage (p : IR.Program) : Except String Unit := do
  for method in p.methods do
    if method.kind == .init then
      let count := method.ops.foldl (init := 0) fun total op =>
        match op with | .returnState _ => total + 1 | _ => total
      unless count == p.schema.leaves.size do
        throw (s!"extract/unsupported: {method.ixName} initializes {count} state leaves, " ++
          s!"schema requires {p.schema.leaves.size}")

private partial def valEscapedArg (limit : Nat) : Ops.Val → Option Nat
  | .arg i => if i < limit then none else some i
  | .field b _ | .bitNot b | .checkPda _ b => valEscapedArg limit b
  | .bitAnd l r | .bitOr l r | .bitXor l r | .shiftL l r | .shiftR l r
  | .addU64 l r | .subU64 l r | .mulU64 l r | .divU64 l r | .modU64 l r
  | .mapGetU64 l r => #[l, r].findSome? (valEscapedArg limit)
  | .indexGet b _ i _ => #[b, i].findSome? (valEscapedArg limit)
  | .select _ l r t f => #[l, r, t, f].findSome? (valEscapedArg limit)
  | .mapGetAddr a b c d => #[a, b, c, d].findSome? (valEscapedArg limit)
  | .mapGetPair a b c d e f g =>
      #[a, b, c, d, e, f, g].findSome? (valEscapedArg limit)
  | _ => none

private partial def opEscapedArg (limit : Nat) : Ops.Op → Option Nat
  | .letLocal _ v => valEscapedArg limit v
  | .joinLocal _ => none
  | .setLocal _ v => valEscapedArg limit v
  | .checkedAddU64 l r | .checkedSubU64 l r | .checkedMulU64 l r
  | .checkedDivU64 l r | .checkedModU64 l r =>
      #[l, r].findSome? (valEscapedArg limit)
  | .ite _ l r t f =>
      #[l, r].findSome? (valEscapedArg limit) <|>
        t.findSome? (opEscapedArg limit) <|> f.findSome? (opEscapedArg limit)
  | .invoke _ _ data _ bump =>
      (data.findSome? fun word => word.value?.bind (valEscapedArg limit)) <|>
        bump.bind (valEscapedArg limit)
  | .evmDeposit v | .evmLog _ v | .forAccum _ v _ => valEscapedArg limit v
  | .evmSendEth a b c d => #[a, b, c, d].findSome? (valEscapedArg limit)
  | .forBody _ body => body.findSome? (opEscapedArg limit)
  | .indexSetLeaf _ i v _ _ | .indexSet _ i v _ _ | .mapGetU64 i v =>
      #[i, v].findSome? (valEscapedArg limit)
  | .mapSetU64 a b c => #[a, b, c].findSome? (valEscapedArg limit)
  | .mapGetAddr a b c d => #[a, b, c, d].findSome? (valEscapedArg limit)
  | .mapSetAddr a b c d e => #[a, b, c, d, e].findSome? (valEscapedArg limit)
  | .mapGetPair a b c d e f g =>
      #[a, b, c, d, e, f, g].findSome? (valEscapedArg limit)
  | .mapSetPair a b c d e f g h =>
      #[a, b, c, d, e, f, g, h].findSome? (valEscapedArg limit)
  | .evmTokenTransfer a b c d e f g =>
      #[a, b, c, d, e, f, g].findSome? (valEscapedArg limit)
  | .evmTokenBalanceOfSelf a b c =>
      #[a, b, c].findSome? (valEscapedArg limit)
  | .storeField _ v | .okState v | .returnU64 v | .returnState v => valEscapedArg limit v
  | .errorOverflow | .errorNamed _ => none

/-- Reject decoder binder leaks before a backend can mistake one for calldata or state. -/
private def checkArgBounds (p : IR.Program) : Except String Unit := do
  for method in p.methods do
    let limit := method.paramCount + if method.kind == .init then 0 else 1
    for op in method.ops do
      if let some i := opEscapedArg limit op then
        (throw (s!"extract/unsupported: {method.ixName} escaped arg {i} " ++
          s!"(paramCount {method.paramCount})") : Except String Unit)
  return ()

/-- Extract three named declarations directly into the extensible source dialect. -/
def extractProgramIR (env : Environment)
    (initName incrementName getName : Name)
    (programName : Option String := none)
    (fields? : Option (Array String) := none) :
    Except String IR.Program := do
  match Profile.checkAll env #[initName, incrementName, getName] with
  | .reject reason => throw reason
  | .accept => pure ()
  let schema ← inferSchema env initName
  let inferred := Core.IR.slotsOfSchema schema
  let slots ←
    match fields? with
    | none => pure inferred
    | some fs =>
      if fs == inferred.map (·.name) then pure inferred
      else throw s!"extract/unsupported: fields {fs} != inferred {inferred.map (·.name)}"
  let initM ← extractMethod env .init initName
  let incM ← extractMethod env .increment incrementName
  let getM ← extractMethod env .get getName
  let program : IR.Program := {
    name := programName.getD (programNameOfInit initName)
    slots
    schema
    methods := #[initM, incM, getM]
  }
  unless Core.IR.isProgramShape program do
    throw "extract/unsupported: not three-method shape"
  unless Core.IR.schemaMatchesSlots program do
    throw "extract/unsupported: schema does not match slots"
  checkInitCoverage program
  let program ← resolveVectorLeaves program
  checkArgBounds program
  let program ← evaluateProgram program
  checkUsedFields program
  return program

def extractCounterIR := extractProgramIR

private def isExceptType (e : Expr) : Bool :=
  e.consumeMData.getAppFn.constName? == some ``Except

/-- `Except` → mutate；`UInt64` → view；其它用户 structure → init。
`UInt64` 本身也是 structure，必须先判。 -/
def inferKind (env : Environment) (n : Name) : Except String Core.IR.MethodKind := do
  let some info := env.find? n
    | throw s!"extract/unsupported: unknown {n}"
  let ret := peelForalls info.type
  if isExceptType ret then
    return .increment
  if isUInt64Type ret || (widthOfType ret).isSome then
    return .get
  if ret.getAppFn.constName? == some ``Prod then
    return .get
  if let some structName := ret.getAppFn.constName? then
    if isStructure env structName && structName != ``UInt64 &&
        structName != ``Prod then
      return .init
  throw s!"extract/unsupported: cannot classify {n}"

private def sortNames (ns : Array Name) : Array Name :=
  ns.qsort (·.toString < ·.toString)

/-- 收同一名字空间下 `@[pf_entry]` 的根，直接生成 extensible IR。 -/
def extractModuleIR (env : Environment) (ns : Name)
    (fields? : Option (Array String) := none) :
    Except String IR.Program := do
  let tagged := sortNames (Attr.entriesIn env ns)
  if tagged.isEmpty then
    throw "extract/unsupported: no pf_entry"
  let mut inits : Array Name := #[]
  let mut muts : Array Name := #[]
  let mut views : Array Name := #[]
  for n in tagged do
    match Profile.check env n with
    | .reject reason => throw reason
    | .accept => pure ()
    match ← inferKind env n with
    | .init => inits := inits.push n
    | .increment => muts := muts.push n
    | .get => views := views.push n
  if inits.isEmpty then
    throw "extract/unsupported: missing init method"
  if muts.isEmpty then
    throw "extract/unsupported: missing mutating method"
  if views.isEmpty then
    throw "extract/unsupported: missing view method"
  let initName :=
    match inits.find? (fun n => Core.IR.lastName n.toString == "init") with
    | some n => n
    | none => inits[0]!
  let schema ← inferSchema env initName
  let inferred := Core.IR.slotsOfSchema schema
  let slots ←
    match fields? with
    | none => pure inferred
    | some fs =>
      if fs == inferred.map (·.name) then pure inferred
      else throw s!"extract/unsupported: fields {fs} != inferred {inferred.map (·.name)}"
  let mut methods : Array IR.Method := #[]
  let mut seen : Array String := #[]
  for n in inits do
    let m ←
      match extractMethod env .init n with
      | .ok method => pure method
      | .error reason => throw s!"{n}: {reason}"
    if seen.contains m.ixName then
      throw s!"extract/unsupported: duplicate ixName {m.ixName}"
    seen := seen.push m.ixName
    methods := methods.push m
  for n in muts do
    let m ←
      match extractMethod env .increment n with
      | .ok method => pure method
      | .error reason => throw s!"{n}: {reason}"
    if seen.contains m.ixName then
      throw s!"extract/unsupported: duplicate ixName {m.ixName}"
    seen := seen.push m.ixName
    methods := methods.push m
  for n in views do
    let m ←
      match extractMethod env .get n with
      | .ok method => pure method
      | .error reason => throw s!"{n}: {reason}"
    if seen.contains m.ixName then
      throw s!"extract/unsupported: duplicate ixName {m.ixName}"
    seen := seen.push m.ixName
    methods := methods.push m
  let program : IR.Program := {
    name := programNameOfInit initName
    slots
    schema
    methods
  }
  unless Core.IR.isProgramShape program do
    throw "extract/unsupported: not program shape"
  unless Core.IR.schemaMatchesSlots program do
    throw "extract/unsupported: schema does not match slots"
  checkInitCoverage program
  let program ← resolveVectorLeaves program
  checkArgBounds program
  let program ← evaluateProgram program
  checkUsedFields program
  return program

end ProofForge.Extract
