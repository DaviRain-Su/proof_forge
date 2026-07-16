import ProofForge.Contract.Token.EvmSpec

namespace ProofForge.Backend.Stylus.Token

open ProofForge.Contract.Token
open ProofForge.IR

private def stylusTokenState (state : StateDecl) : StateDecl :=
  if state.id == "balances" then
    match state.kind with
    | .map _ capacity => { state with kind := .map .address capacity }
    | _ => state
  else if state.id == "allowances" then
    match state.kind with
    | .map _ capacity => { state with
        kind := .map .address capacity
        keyPathTypes := #[.address, .address] }
    | _ => state
  else state

private def stylusTokenEntrypoint (entrypoint : Entrypoint) : Entrypoint :=
  let params := entrypoint.params.mapIdx fun index param =>
    match entrypoint.paramAbiWords[index]? with
    | some (some "address") => (param.1, ValueType.address)
    | _ => param
  let paramAbiWords := entrypoint.params.mapIdx fun index param =>
    match entrypoint.paramAbiWords[index]? with
    | some (some override) => some override
    | _ =>
        if param.1 == "amount" || param.1 == "value" then some "uint256" else none
  let returnAbiWord? := match entrypoint.name with
    | "totalSupply" | "balanceOf" | "allowance" => some "uint256"
    | "decimals" => some "uint8"
    | _ => entrypoint.returnAbiWord?
  let addressLocals := #["sender", "holder", "spender", "who"]
  let rewriteEventField := fun (field : String × Expr) =>
    if #["from", "to", "owner", "spender"].contains field.1 then
      match field.2 with
      | .literal (.u64 0) => (field.1, .literal (.address 0))
      | _ => field
    else field
  let rec rewriteStatement : Statement → Statement
    | .letBind name type value =>
        .letBind name (if addressLocals.contains name then .address else type) value
    | .letMutBind name type value =>
        .letMutBind name (if addressLocals.contains name then .address else type) value
    | .effect (.eventEmit name fields) =>
        .effect (.eventEmit name (fields.map rewriteEventField))
    | .effect (.eventEmitIndexed name indexed data) =>
        .effect (.eventEmitIndexed name (indexed.map rewriteEventField) (data.map rewriteEventField))
    | .ifElse condition thenBody elseBody =>
        .ifElse condition (thenBody.map rewriteStatement) (elseBody.map rewriteStatement)
    | .boundedFor index start stop body =>
        .boundedFor index start stop (body.map rewriteStatement)
    | .whileLoop condition body => .whileLoop condition (body.map rewriteStatement)
    | statement => statement
  { entrypoint with
    params := params
    paramAbiWords := paramAbiWords
    returnAbiWord? := returnAbiWord?
    body := entrypoint.body.map rewriteStatement }

/-- Materialize the shared token intent as the canonical ERC-20 contract body
for Stylus. Business functions stay owned by the shared ERC-20 stdlib; this
adapter only selects Solidity-compatible address-keyed storage shapes. -/
def specFor (token : TokenSpec) : ProofForge.Contract.ContractSpec :=
  let source := ProofForge.Contract.Token.EvmSpec.specFor token
  { source with module := { source.module with
      state := source.module.state.map stylusTokenState
      entrypoints := source.module.entrypoints.map stylusTokenEntrypoint } }

end ProofForge.Backend.Stylus.Token
