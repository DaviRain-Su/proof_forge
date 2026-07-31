import ProofForgeV2.Targets.Evm.ValidatePlanV1

/-!
# Evm EmitIRV1 — Plan → IR (Yul + ABI) emission

Target-owned Yul/ABI renderer and capability-internal `lower`/`emitFromIR`.
-/

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

structure IR where
  objectName : String
  yul : String
  abi : String
  deriving BEq, Inhabited, Repr
/-- Nested Yul expression form (no intermediate lets). Used for for-loop
    condition/update slots that require expression positions. Storage loads
    and checked overflow guards are not nested here — callers pre-render
    loop-invariant subtrees with the statement form. -/
private partial def renderExprNested (paramPrefix : String) : Expr → String
  | .literal value => toString value
  | .param wordIndex => s!"{paramPrefix}{wordIndex}"
  | .temp tempIndex => s!"t{tempIndex}"
  | .storageLoad slot => s!"sload({slot})"
  | .checkedAdd lhs rhs =>
      s!"add({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .add lhs rhs =>
      s!"add({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .checkedSub lhs rhs =>
      s!"sub({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .compare op lhs rhs =>
      let l := renderExprNested paramPrefix lhs
      let r := renderExprNested paramPrefix rhs
      match op with
      | .eq => s!"eq({l}, {r})"
      | .ne => s!"iszero(eq({l}, {r}))"
      | .lt => s!"lt({l}, {r})"
      | .le => s!"iszero(gt({l}, {r}))"
      | .gt => s!"gt({l}, {r})"
      | .ge => s!"iszero(lt({l}, {r}))"
  | .checkedMul lhs rhs =>
      s!"mul({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .checkedDiv lhs rhs =>
      s!"div({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .checkedMod lhs rhs =>
      s!"mod({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .bitNot operand => s!"and(not({renderExprNested paramPrefix operand}), 0xffffffffffffffff)"
  | .boolNot operand => s!"iszero({renderExprNested paramPrefix operand})"
  | .bitAnd lhs rhs =>
      s!"and({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .bitOr lhs rhs =>
      s!"or({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .bitXor lhs rhs =>
      s!"xor({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  -- Nested form omits count/overflow guards (same discipline as checkedAdd).
  | .shl lhs rhs =>
      s!"shl({renderExprNested paramPrefix rhs}, {renderExprNested paramPrefix lhs})"
  | .shr lhs rhs =>
      s!"shr({renderExprNested paramPrefix rhs}, {renderExprNested paramPrefix lhs})"
  | .logicalAnd lhs rhs =>
      s!"and({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .logicalOr lhs rhs =>
      s!"or({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .callFn fnIndex args =>
      let argsJoined := String.intercalate ", "
        (args.toList.map (renderExprNested paramPrefix))
      s!"pf_fn{fnIndex}({argsJoined})"
private structure RenderedExpr where
  code : String
  value : String
  next : Nat
  deriving Inhabited

private partial def renderExpr (indent paramPrefix : String) (next : Nat) : Expr → RenderedExpr
  | .literal value =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {value}\n", value := name, next := next + 1 }
  | .param wordIndex =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {paramPrefix}{wordIndex}\n", value := name, next := next + 1 }
  | .temp tempIndex =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := t{tempIndex}\n", value := name, next := next + 1 }
  | .storageLoad slot =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := sload({slot})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if gt({lhs.value}, sub(0xffffffffffffffff, {rhs.value})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .add lhs rhs =>
      -- Unchecked add: only for bounded-for induction `i + 1` (cannot overflow).
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .checkedSub lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if lt({lhs.value}, {rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := sub({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .compare op lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let yul := match op with
        | .eq => s!"eq({lhs.value}, {rhs.value})"
        | .ne => s!"iszero(eq({lhs.value}, {rhs.value}))"
        | .lt => s!"lt({lhs.value}, {rhs.value})"
        | .le => s!"iszero(gt({lhs.value}, {rhs.value}))"
        | .gt => s!"gt({lhs.value}, {rhs.value})"
        | .ge => s!"iszero(lt({lhs.value}, {rhs.value}))"
      { code := lhs.code ++ rhs.code ++ s!"{indent}let {name} := {yul}\n",
        value := name, next := rhs.next + 1 }
  | .checkedMul lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      -- Overflow guard: the mathematical product of two UInt64 words is
      -- below 2^128, so a 256-bit Yul `mul` cannot wrap; checking the
      -- result against the UInt64 ceiling is exact. (A round-trip
      -- `div(product, lhs) == rhs` guard could never fire and silently
      -- admitted e.g. 2^32 * 2^32 = 2^64.)
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := mul({lhs.value}, {rhs.value})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := rhs.next + 1 }
  | .checkedDiv lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := div({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .checkedMod lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := mod({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .bitNot operand =>
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      -- Yul `not` flips all 256 bits; mask back to the UInt64 word so
      -- `~x = (2^64 - 1) - x` matches the reference semantics.
      { code := operand.code ++
          s!"{indent}let {name} := and(not({operand.value}), 0xffffffffffffffff)\n",
        value := name, next := operand.next + 1 }
  | .boolNot operand =>
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      { code := operand.code ++
          s!"{indent}let {name} := iszero({operand.value})\n",
        value := name, next := operand.next + 1 }
  | .bitAnd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .bitOr lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := or({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .bitXor lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := xor({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .shl lhs rhs =>
      -- Yul `shl(k, x)`: count first. Count ≥ 64 → invalidShift; result ≥ 2^64
      -- → arithmeticOverflow. Inputs are already UInt64/UInt32-bounded words.
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, 64)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := shl({rhs.value}, {lhs.value})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := rhs.next + 1 }
  | .shr lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, 64)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := shr({rhs.value}, {lhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .logicalAnd lhs rhs =>
      -- Strict: both sides already materialised; 0/1 bitwise and == logical and.
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .logicalOr lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := or({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .callFn fnIndex args => Id.run do
      let mut code := ""
      let mut next := next
      let mut argValues : Array String := #[]
      for arg in args do
        let rendered := renderExpr indent paramPrefix next arg
        code := code ++ rendered.code
        next := rendered.next
        argValues := argValues.push rendered.value
      let name := s!"expr{next}"
      let argsJoined := String.intercalate ", " argValues.toList
      { code := code ++ s!"{indent}let {name} := pf_fn{fnIndex}({argsJoined})\n",
        value := name, next := next + 1 }

private def renderStores (indent paramPrefix : String) (stores : Array Store) : String := Id.run do
  let mut output := ""
  let mut next := 0
  for store in stores do
    let rendered := renderExpr indent paramPrefix next store.value
    output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
    next := rendered.next
  return output

private structure RenderedBody where
  code : String
  next : Nat
  deriving Inhabited

/-- Render a statement list. `returnVar = none` is the contract path
    (`mstore` + `return`); `some r` is a Yul function path that assigns `r`. -/
private structure PeeledForCondV1 where
  code : String
  cond : String
  next : Nat
  deriving Inhabited

/-- Peel `compare op (.temp varTemp) endExpr` so the end bound is evaluated once
    (with overflow guards) before the Yul for; otherwise nest the full cond. -/
private def peelForCondV1 (indent paramPrefix : String) (next varTemp : Nat)
    (cond : Expr) : PeeledForCondV1 :=
  match cond with
  | .compare op (.temp t) endExpr =>
      if t == varTemp then
        let endR := renderExpr indent paramPrefix next endExpr
        let yul := match op with
          | .eq => s!"eq(t{varTemp}, {endR.value})"
          | .ne => s!"iszero(eq(t{varTemp}, {endR.value}))"
          | .lt => s!"lt(t{varTemp}, {endR.value})"
          | .le => s!"iszero(gt(t{varTemp}, {endR.value}))"
          | .gt => s!"gt(t{varTemp}, {endR.value})"
          | .ge => s!"iszero(lt(t{varTemp}, {endR.value}))"
        { code := endR.code, cond := yul, next := endR.next }
      else
        { code := "", cond := renderExprNested paramPrefix cond, next }
  | _ =>
      { code := "", cond := renderExprNested paramPrefix cond, next }

private partial def renderBody (indent paramPrefix : String) (next : Nat)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (returnVar : Option String)
    (body : Array Statement) : RenderedBody := Id.run do
  let mut output := ""
  let mut next := next
  for statement in body do
    match statement with
    | .store store =>
        let rendered := renderExpr indent paramPrefix next store.value
        output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
        next := rendered.next
    | .assert condition =>
        let rendered := renderExpr indent paramPrefix next condition
        output := output ++ rendered.code ++
          s!"{indent}if iszero({rendered.value}) \{ revert(0, 0) }\n"
        next := rendered.next
    | .returnValue value =>
        let rendered := renderExpr indent paramPrefix next value
        match returnVar with
        | none =>
            output := output ++ rendered.code ++
              s!"{indent}mstore(0, {rendered.value})\n{indent}return(0, 32)\n"
        | some r =>
            output := output ++ rendered.code ++
              s!"{indent}{r} := {rendered.value}\n"
        next := rendered.next
    | .returnNone =>
        -- Valid only as the constructor body's final statement (validated);
        -- falling off the body reaches the deployment epilogue on this path.
        pure ()
    | .emitEvent eventIndex args =>
        let binding := events[eventIndex]!
        let signature := Keccak.signature binding.name
          (Array.replicate binding.fieldCount "uint64")
        let topic0 := Keccak.keccak256Hex signature.toUTF8
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}log1(0, {32 * args.size}, 0x{topic0})\n"
    | .revertError errorIndex args =>
        let binding := errors[errorIndex]!
        let selector := Keccak.selector binding.name
          (Array.replicate binding.fieldCount "uint64")
        let padded := selector ++ String.ofList (List.replicate 56 '0')
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({4 + 32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}mstore(0, 0x{padded})\n"
        output := output ++ s!"{indent}revert(0, {4 + 32 * args.size})\n"
    | .ifThenElse condition thenBody elseBody =>
        let rendered := renderExpr indent paramPrefix next condition
        output := output ++ rendered.code
        let thenRendered := renderBody (indent ++ "  ") paramPrefix rendered.next
          events errors returnVar thenBody
        output := output ++ s!"{indent}if {rendered.value} \{\n" ++
          thenRendered.code ++ s!"{indent}}\n"
        next := thenRendered.next
        if !elseBody.isEmpty then
          let elseRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar elseBody
          output := output ++ s!"{indent}if iszero({rendered.value}) \{\n" ++
            elseRendered.code ++ s!"{indent}}\n"
          next := elseRendered.next
    | .switchOn scrutinee cases defaultBody =>
        let rendered := renderExpr indent paramPrefix next scrutinee
        let scrutName := s!"expr{rendered.next}"
        output := output ++ rendered.code ++
          s!"{indent}let {scrutName} := {rendered.value}\n"
        next := rendered.next + 1
        let mut guard : String := ""
        for (caseValue, caseBody) in cases do
          let caseRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar caseBody
          output := output ++
            s!"{indent}if eq({scrutName}, {caseValue}) \{\n" ++
            caseRendered.code ++ s!"{indent}}\n"
          next := caseRendered.next
          let eqExpr := s!"eq({scrutName}, {caseValue})"
          guard := if guard.isEmpty then eqExpr else s!"or({guard}, {eqExpr})"
        if !defaultBody.isEmpty then
          let defaultRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar defaultBody
          output := output ++ s!"{indent}if iszero({guard}) \{\n" ++
            defaultRendered.code ++ s!"{indent}}\n"
          next := defaultRendered.next
    | .forLoop varTemp counterTemp maxIterations initial cond update body =>
        -- Init and loop-invariant end bound are rendered once before the for.
        -- Condition uses nested expression form. Induction `i + 1` is unchecked
        -- (see Expr.add): body only runs while i < end ≤ UInt64.max.
        -- Back-edge post (after body, before next cond): bound check then
        -- counter++ then update — the (N+1)-th body runs, then reverts.
        let initR := renderExpr indent paramPrefix next initial
        output := output ++ initR.code
        next := initR.next
        let peeled := peelForCondV1 indent paramPrefix next varTemp cond
        output := output ++ peeled.code
        next := peeled.next
        let updateNested := renderExprNested paramPrefix update
        let bodyR := renderBody (indent ++ "  ") paramPrefix next
          events errors returnVar body
        let postIndent := indent ++ "  "
        let bound := toString maxIterations.toNat
        let tV := "t" ++ toString varTemp
        let tC := "t" ++ toString counterTemp
        output := output ++
          indent ++ "for { let " ++ tV ++ " := " ++ initR.value ++
          " let " ++ tC ++ " := 0 } " ++ peeled.cond ++ " {\n" ++
          postIndent ++ "if eq(" ++ tC ++ ", " ++ bound ++ ") { revert(0, 0) }\n" ++
          postIndent ++ tC ++ " := add(" ++ tC ++ ", 1)\n" ++
          postIndent ++ tV ++ " := " ++ updateNested ++ "\n" ++
          indent ++ "} {\n" ++
          bodyR.code ++
          indent ++ "}\n"
        next := bodyR.next
  return { code := output, next }

/-- Emit `function pf_fn{i}(...) -> r { ... }` definitions. Duplicated into both
    Yul objects because each object is self-contained. -/
private def renderFnDefs (indent : String) (plan : Plan) : String := Id.run do
  if plan.fns.isEmpty then
    return ""
  let mut output := ""
  for index in [0:plan.fns.size] do
    let fn := plan.fns[index]!
    let mut paramList := ""
    for i in [0:fn.params.size] do
      if i > 0 then paramList := paramList ++ ", "
      paramList := paramList ++ s!"arg{i}"
    let body := renderBody (indent ++ "  ") "arg" 0 plan.events plan.errors (some "r") fn.body
    output := output ++
      s!"{indent}function pf_fn{index}({paramList}) -> r \{\n" ++
      body.code ++
      s!"{indent}}\n"
  return output

private def renderConstructor (plan : Plan) : String := Id.run do
  let constructor := plan.constructor.getD { params := #[], stores := #[] }
  let argumentBytes := constructor.params.size * 32
  let mut output :=
    s!"    if callvalue() \{ revert(0, 0) }\n" ++
    s!"    let programSize := datasize(\"{plan.objectName}\")\n" ++
    s!"    if iszero(eq(codesize(), add(programSize, {argumentBytes}))) \{ revert(0, 0) }\n"
  if argumentBytes > 0 then
    output := output ++ s!"    codecopy(0, programSize, {argumentBytes})\n"
  for param in constructor.params do
    output := output ++
      s!"    let ctor_arg{param.wordIndex} := mload({param.wordIndex * 32})\n" ++
      s!"    if gt(ctor_arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  -- Store-only constructors keep body empty for byte-identical Yul via stores.
  output := output ++
    (if constructor.body.isEmpty then
      renderStores "    " "ctor_arg" constructor.stores
    else
      (renderBody "    " "ctor_arg" 0 plan.events plan.errors none constructor.body).code)
  return output ++
    s!"    datacopy(0, dataoffset(\"{plan.runtimeObjectName}\"), datasize(\"{plan.runtimeObjectName}\"))\n" ++
    s!"    return(0, datasize(\"{plan.runtimeObjectName}\"))\n"

private def renderEntry (plan : Plan) (entry : Entry) : String := Id.run do
  let calldataBytes := 4 + entry.params.size * 32
  let mut output :=
    s!"      case 0x{entry.selector} \{\n" ++
    s!"        if iszero(eq(calldatasize(), {calldataBytes})) \{ revert(0, 0) }\n"
  for param in entry.params do
    let offset := 4 + param.wordIndex * 32
    output := output ++
      s!"        let arg{param.wordIndex} := calldataload({offset})\n" ++
      s!"        if gt(arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  output := output ++
    (renderBody "        " "arg" 0 plan.events plan.errors none entry.body).code
  return output ++ "      }\n"

private def renderYul (plan : Plan) : String :=
  let entries := plan.entries.foldl (fun output entry => output ++ renderEntry plan entry) ""
  let ctorFns := renderFnDefs "    " plan
  let runtimeFns := renderFnDefs "      " plan
  s!"object \"{plan.objectName}\" \{\n  code \{\n" ++
    renderConstructor plan ++
    ctorFns ++
    s!"  }\n  object \"{plan.runtimeObjectName}\" \{\n    code \{\n" ++
    "      if callvalue() { revert(0, 0) }\n" ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    entries ++
    "      default { revert(0, 0) }\n" ++
    runtimeFns ++
    "    }\n  }\n}\n"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"uint64\"}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderConstructorAbi (constructor : Constructor) : String :=
  "{\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[" ++
    renderParamsJson constructor.params ++ "]}"

private def resultKindAbiType (kind : ResultKind) : String :=
  match kind with
  | .uint64 => "uint64"
  | .bool => "bool"

private def renderEntryAbi (entry : Entry) : String :=
  let mutability := match entry.mutability with
    | .nonpayable => "nonpayable"
    | .view => "view"
  let resultType := resultKindAbiType entry.resultKind
  "{\"type\":\"function\",\"name\":\"" ++ Targets.escapeJson entry.name ++
    "\",\"stateMutability\":\"" ++ mutability ++ "\",\"inputs\":[" ++
    renderParamsJson entry.params ++
    "],\"outputs\":[{\"name\":\"\",\"type\":\"" ++ resultType ++ "\"}]}"

private def renderInterfaceBindingAbi (kind : String) (binding : InterfaceBinding) : String :=
  let inputs := (List.range binding.fieldCount).map fun index =>
    "{\"name\":\"arg" ++ toString index ++ "\",\"type\":\"uint64\"}"
  "{\"type\":\"" ++ kind ++ "\",\"name\":\"" ++ Targets.escapeJson binding.name ++
    "\",\"inputs\":[" ++ String.intercalate "," inputs ++ "]}"

private def renderAbi (plan : Plan) : String :=
  let constructor := plan.constructor.map (fun value => #[renderConstructorAbi value]) |>.getD #[]
  let entries := plan.entries.map renderEntryAbi
  let events := plan.events.map (renderInterfaceBindingAbi "event")
  let errors := plan.errors.map (renderInterfaceBindingAbi "error")
  let items := constructor ++ entries ++ events ++ errors
  "[\n  " ++ String.intercalate ",\n  " items.toList ++ "\n]\n"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  return { objectName := plan.objectName, yul := renderYul plan, abi := renderAbi plan }

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) :=
  .ok #[
    { path := s!"{ir.objectName}.yul", mediaType := "text/yul", contents := ir.yul },
    { path := s!"{ir.objectName}.abi.json", mediaType := "application/json", contents := ir.abi }
  ]


/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

/-- Capability-gated public materialize entry. Sole path from the retained
    SemanticProgramV1-native EVM Plan body to emitted files for this target. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

end ProofForgeV2.Targets.Evm
