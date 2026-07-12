import ProofForge.Contract.Intent.Registry
import ProofForge.Contract.Spec

/-!
# Intent Registry Test

Tests the target-neutral intent materializer contract:
- duplicate (targetId, family) keys are rejected
- exact lookup succeeds for registered materializers
- missing materializer produces a named diagnostic
- materialization errors are preserved (not swallowed)
-/

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def dummySpec : ContractSpec := { name := "TestToken", module := { name := "TestToken", state := #[], entrypoints := #[], structs := #[] } }

def okMaterializer (targetId : String) : IntentMaterializer := {
  targetId := targetId
  family := .fungibleToken
  materialize := fun intent => .ok {
    targetId := targetId
    standardId := s!"test-standard-{intent.name}"
    contractSpec := dummySpec
    evidence := #["test-materializer-called"]
  }
}

def errorMaterializer (targetId : String) : IntentMaterializer := {
  targetId := targetId
  family := .nonFungibleToken
  materialize := fun _ => .error "intentional-materializer-error"
}

def main : IO Unit := do
  -- Test 1: duplicate (targetId, family) keys are rejected
  let dupMaterializers : Array IntentMaterializer := #[
    okMaterializer "evm",
    { targetId := "evm", family := .fungibleToken,
      materialize := fun _ => .ok { targetId := "evm", standardId := "dup", contractSpec := dummySpec, evidence := #[] } }
  ]
  match IntentRegistry.create dupMaterializers with
  | .error e =>
    require (e.contains "duplicate") s!"duplicate rejection should mention 'duplicate', got: {e}"
  | .ok _ =>
    throw <| IO.userError "duplicate (targetId, family) was not rejected"

  -- Test 2: exact lookup succeeds
  let okMaterializers : Array IntentMaterializer := #[
    okMaterializer "evm",
    okMaterializer "solana-sbpf-asm"
  ]
  let registry ← match IntentRegistry.create okMaterializers with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"registry creation failed: {e}"

  match IntentRegistry.resolve registry "evm" .fungibleToken with
  | .ok m => require (m.targetId == "evm") "lookup returned wrong targetId"
  | .error e => throw <| IO.userError s!"lookup for evm/fungibleToken failed: {e}"

  match IntentRegistry.resolve registry "solana-sbpf-asm" .fungibleToken with
  | .ok m => require (m.targetId == "solana-sbpf-asm") "lookup returned wrong targetId"
  | .error e => throw <| IO.userError s!"lookup for solana/fungibleToken failed: {e}"

  -- Test 3: missing materializer produces a named diagnostic
  match IntentRegistry.resolve registry "wasm-near" .fungibleToken with
  | .ok _ => throw <| IO.userError "missing materializer should not resolve"
  | .error e => require (e.contains "no materializer") s!"missing materializer error should mention 'no materializer', got: {e}"

  -- Test 4: materialization errors are preserved
  let errRegistry ← match IntentRegistry.create #[errorMaterializer "evm"] with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"error registry creation failed: {e}"

  let intent : IntentContract := { family := .nonFungibleToken, name := "TestNFT" }
  match IntentRegistry.resolve errRegistry "evm" .nonFungibleToken with
  | .ok m =>
    match m.materialize intent with
    | .ok _ => throw <| IO.userError "error materializer should not succeed"
    | .error e => require (e == "intentional-materializer-error") s!"materializer error should be preserved, got: {e}"
  | .error e => throw <| IO.userError s!"lookup for evm/nft failed: {e}"

  -- Test 5: empty registry rejects all lookups
  match IntentRegistry.resolve IntentRegistry.empty "evm" .fungibleToken with
  | .ok _ => throw <| IO.userError "empty registry should not resolve"
  | .error e => require (e.contains "no materializer") s!"empty registry error should mention 'no materializer', got: {e}"

  IO.println "intent-registry: ok"