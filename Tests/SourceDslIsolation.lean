import Lean
import Lean.Elab.Command
import ProofForge.Contract.Source
open Lean Parser Elab Command
open ProofForge.Contract.Source

/-!
# Source DSL Isolation Test (portable import only)

Verifies that Solana-specific grammar productions are NOT visible through
the portable `Contract.Source` import. Before the syntax move, Solana
forms are visible and the test fails. After the move, they are invisible
and the test passes.

Uses `runParserCategory` with both qualified and unqualified category names.
The namespace is opened so portable scoped syntax is active; Solana productions
remain absent because this module imports only `ProofForge.Contract.Source`.
`Tests/SourceDslSolanaAcceptance.lean` pins the positive Solana side.
-/

def parsesOk (env : Environment) (catName : Name) (input : String) : Bool :=
  match runParserCategory env catName input with
  | .ok _ => true
  | .error _ => false

def ciCats : List Name := [`contractItem, `ProofForge.Contract.Source.contractItem]
def esCats : List Name := [`entryStmt, `ProofForge.Contract.Source.entryStmt]

def parsesOkAny (env : Environment) (cats : List Name) (input : String) : Bool :=
  cats.any (parsesOk env · input)

def collectFailures (env : Environment) : List String :=
  let fails (cats : List Name) (input : String) (label : String) : Option String :=
    if parsesOkAny env cats input then some s!"FAIL: `{label}` visible in portable import" else none
  let oks (cats : List Name) (input : String) (label : String) : Option String :=
    if parsesOkAny env cats input then none else some s!"FAIL: `{label}` not visible in portable import"
  [
    fails ciCats "allocator bump" "allocator bump",
    fails ciCats "account vault readonly" "account readonly",
    fails ciCats "pda vault seeds [literal_seed \"x\"] bump b account a signer" "pda declaration",
    fails ciCats "cpi c system_transfer(a, b, c)" "cpi system_transfer",
    fails ciCats "cpi c memo(x)" "cpi memo",
    fails esCats "derive pda vault seeds [literal_seed \"x\"] bump b account a signer;" "derive pda",
    fails esCats "invoke c system_transfer(a, b, c);" "invoke system_transfer",
    fails esCats "invoke c memo(x);" "invoke memo",
    fails esCats "realloc vault to 256;" "realloc",
    fails esCats "init_transfer_hook_extra_meta(vault, extra);" "init_transfer_hook_extra_meta",
    oks ciCats "state count : .u64" "state declaration",
    fails ciCats "mapping balances from .u64 to .u64" "unmigrated mapping declaration",
    fails ciCats "event Transfer" "untyped Legacy event declaration",
    fails ciCats "remote callee \"peer.callee\" \"remote_call\";" "Legacy remote",
    fails ciCats "external_token usdc \"usdc.peer\";" "Legacy external_token",
    oks esCats "let n : .u64 := count;" "let binding",
    oks esCats "return x;" "return"
  ].filterMap id

#eval show CommandElabM Unit from do
  let env ← getEnv
  let failures := collectFailures env
  if !failures.isEmpty then
    for f in failures do IO.eprintln f
    throwError "source-dsl-isolation: FAIL"

def main : IO UInt32 := do
  IO.println "source-dsl-isolation: ok"
  return 0
