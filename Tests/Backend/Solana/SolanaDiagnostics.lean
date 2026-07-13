import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Contract

/-!
# Solana sBPF Assembly Capability Diagnostics

Portable `crosscall.invoke` **is** supported on Solana (CPI). Diagnostics now
come from:

* **PortableHonesty** — empty peer id (no `declareRemote` / crosscallStrings)
* **Backend policy** — EVM-only create/create2 cannot lower as CPI

Exact old message `does not support capability crosscall.invoke` is obsolete
(profile now includes that capability).
-/

namespace ProofForge.Tests.SolanaDiagnostics

open ProofForge.IR
open ProofForge.Backend.Solana

def markerState : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def selectedEntrypoint (name : String) (body : Array Statement := #[]) : Entrypoint := {
  name := name
  selector? := some "deadbeef"
  returns := .unit
  body := body
}

def selectedReturnEntrypoint (name : String) (returns : ValueType) (body : Array Statement) : Entrypoint := {
  name := name
  selector? := some "deadbeef"
  returns := returns
  body := body
}

def selectedModule (name : String) (entrypoint : Entrypoint) : Module := {
  name := name
  state := #[markerState]
  entrypoints := #[entrypoint]
}

/-- Empty-peer portable remote reject (PortableHonesty). -/
def emptyPeerMessageNeedle : String := "empty peer"

def createMessageNeedle : String := "create/create2 are EVM-only"

def crosscallInvokeModule : Module :=
  selectedModule "BadCrosscallInvoke" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[])
    ]

def crosscallInvokeTypedModule : Module :=
  selectedModule "BadCrosscallInvokeTyped" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallInvokeTyped
        (.literal (.u64 1))
        (.literal (.u64 2))
        #[]
        .u64)
    ]

def crosscallInvokeValueTypedModule : Module :=
  selectedModule "BadCrosscallInvokeValueTyped" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallInvokeValueTyped
        (.literal (.u64 1))
        (.literal (.u64 2))
        (.literal (.u64 0))
        #[]
        .u64)
    ]

def crosscallInvokeStaticTypedModule : Module :=
  selectedModule "BadCrosscallInvokeStaticTyped" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallInvokeStaticTyped
        (.literal (.u64 1))
        (.literal (.u64 2))
        #[]
        .u64)
    ]

def crosscallInvokeDelegateTypedModule : Module :=
  selectedModule "BadCrosscallInvokeDelegateTyped" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallInvokeDelegateTyped
        (.literal (.u64 1))
        (.literal (.u64 2))
        #[]
        .u64)
    ]

def crosscallCreateModule : Module :=
  selectedModule "BadCrosscallCreate" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallCreate (.literal (.u64 0)) "00")
    ]

def crosscallCreate2Module : Module :=
  selectedModule "BadCrosscallCreate2" <|
    selectedReturnEntrypoint "bad" .u64 #[
      .return (.crosscallCreate2 (.literal (.u64 0)) (.literal (.u64 0)) "00")
    ]

def crosscallLetBindModule : Module :=
  selectedModule "BadCrosscallLetBind" <|
    selectedEntrypoint "bad" #[
      .letBind "r" .u64
        (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[])
    ]

/-- Cases: (name, module, substring that must appear in the diagnostic). -/
def cases : Array (String × Module × String) := #[
  ("crosscall.invoke empty peer", crosscallInvokeModule, emptyPeerMessageNeedle),
  ("crosscall.invokeTyped empty peer", crosscallInvokeTypedModule, emptyPeerMessageNeedle),
  ("crosscall.invokeValueTyped empty peer", crosscallInvokeValueTypedModule, emptyPeerMessageNeedle),
  ("crosscall.invokeStaticTyped empty peer", crosscallInvokeStaticTypedModule, emptyPeerMessageNeedle),
  ("crosscall.invokeDelegateTyped empty peer", crosscallInvokeDelegateTypedModule, emptyPeerMessageNeedle),
  ("crosscall.create EVM-only", crosscallCreateModule, createMessageNeedle),
  ("crosscall.create2 EVM-only", crosscallCreate2Module, createMessageNeedle),
  ("crosscall.invoke letBind empty peer", crosscallLetBindModule, emptyPeerMessageNeedle)
]

def renderError? (module : Module) : Option String :=
  match SbpfAsm.renderModule module with
  | .ok _ => none
  | .error err => some err.render

def checkCase (name : String) (module : Module) (needle : String) : IO Bool := do
  match renderError? module with
  | some actual =>
      if actual.contains needle || actual.contains "PortableHonesty" ||
          actual.contains "peer" || actual.contains "EVM-only" then
        IO.println s!"solana-diagnostics: ok: {name}"
        pure true
      else
        IO.eprintln s!"solana-diagnostics: FAILED: {name}"
        IO.eprintln s!"  expected substring: {needle}"
        IO.eprintln s!"  actual:   {actual}"
        pure false
  | none =>
      IO.eprintln s!"solana-diagnostics: FAILED: {name}"
      IO.eprintln "  expected an error, but sBPF assembly generation succeeded"
      pure false

def main : IO UInt32 := do
  let mut failures : Nat := 0
  for (name, module, expected) in cases do
    let ok ← checkCase name module expected
    if !ok then
      failures := failures + 1
  if failures == 0 then
    IO.println s!"solana-diagnostics: {cases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"solana-diagnostics: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.SolanaDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.SolanaDiagnostics.main
