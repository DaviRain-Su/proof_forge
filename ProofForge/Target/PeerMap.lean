/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Deploy-time peer map (Phase C.6)

Authors declare **logical** peer / method ids in portable source
(`declareRemoteUnit "peer.callee" "remote_call"`). Host account names
(NEAR account id, Soroban contract address string, …) are **deployment
parameters**, applied here before Wasm host emit — never hand-written as
chain-specific APIs in Shared business logic.

```text
  Shared IR:   nearCrosscallStrings = #["peer.callee", "remote_call"]
  PeerMap:     peer.callee → callee.example.near
  After apply: nearCrosscallStrings = #["callee.example.near", "remote_call"]
```

Wasm-NEAR / Soroban materialize the pool into host call arguments. EVM (PF-P2-03)
also applies the map: host values that are `0x…` addresses become CALL targets
via `ProtocolMaterialize.resolveEvmTargetExpr`; method names still map through
`resolveEvmMethodExpr` / known selectors.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract

namespace ProofForge.Target.PeerMap

open ProofForge.IR

/-- Logical id → host identity string (account id, contract address, …). -/
structure Binding where
  logical : String
  host : String
  deriving BEq, Repr

structure Map where
  bindings : Array Binding := #[]
  deriving Repr

def empty : Map := {}

def ofList (pairs : List (String × String)) : Map :=
  { bindings := pairs.toArray.map fun (l, h) => { logical := l, host := h } }

/-- Parse one CLI binding `logical=host` (first `=` splits). -/
def parseBinding (spec : String) : Except String Binding :=
  match spec.splitOn "=" with
  | [logical, host] =>
      if logical.isEmpty || host.isEmpty then
        .error s!"invalid --peer '{spec}', expected non-empty logical=host"
      else
        .ok { logical := logical, host := host }
  | _ =>
      .error s!"invalid --peer '{spec}', expected logical=host"

def pushBinding (m : Map) (b : Binding) : Map :=
  -- Later bindings for the same logical override earlier ones.
  let rest := m.bindings.filter (fun x => x.logical != b.logical)
  { bindings := rest.push b }

def merge (base extra : Map) : Map :=
  extra.bindings.foldl pushBinding base

def lookup (m : Map) (logical : String) : Option String :=
  m.bindings.find? (fun b => b.logical == logical) |>.map (·.host)

/-- Rewrite one pool entry: bound logicals become host ids; others unchanged. -/
def rewriteId (m : Map) (id : String) : String :=
  match lookup m id with
  | some host => host
  | none => id

/-- Apply deploy map to `module.nearCrosscallStrings` (host string pool). -/
def applyToModule (module : Module) (m : Map) : Module :=
  if m.bindings.isEmpty then
    module
  else
    { module with
      nearCrosscallStrings := module.nearCrosscallStrings.map (rewriteId m) }

/-- NEAR demo map used by multi-target smokes / local deploy docs.
Logical peers in Shared.RemoteCall resolve to classic testnet-shaped names. -/
def nearDemo : Map :=
  ofList [
    ("peer.callee", "callee.example.near")
  ]

/-- Identity map: no rewrites (default for unit tests that assert logical ids). -/
def identity : Map := empty

def Map.json (m : Map) : String :=
  let pairs :=
    m.bindings.map fun b =>
      "{\"logical\":\"" ++ b.logical ++ "\",\"host\":\"" ++ b.host ++ "\"}"
  "[" ++ String.intercalate "," pairs.toList ++ "]"

end ProofForge.Target.PeerMap
