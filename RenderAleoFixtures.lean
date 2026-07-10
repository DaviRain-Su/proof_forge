/-
Verification driver: render every Aleo feature shape to `.leo` and confirm the
INSTALLED `leo` (4.0.2) actually compiles each. Marker smokes only check
substrings; this is the real compile gate. The feature modules are inlined
(Tests/ is not an importable lake root).

Run: `lake env lean --run RenderAleoFixtures.lean`, then `leo build` each dir
under build/aleo/verify/<name>/.
-/
import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.PureMath
import ProofForge.IR.Examples.StructProbe

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

-- map storage
def ledgerState : StateDecl :=
  { id := "ledger", kind := .map .u64 8, type := .u64 }
def seed : Entrypoint :=
  { name := "seed", body := #[ .effect (.storageMapSet "ledger" (.literal (.u64 0)) (.literal (.u64 42))) ] }
def mapMod : Module :=
  { name := "Ledger", state := #[ledgerState], entrypoints := #[seed] }

-- context read
def ctxState : StateDecl :=
  { id := "lastHeight", kind := .scalar, type := .u32 }
def recordH : Entrypoint :=
  { name := "record_height",
    body := #[ .effect (.storageScalarWrite "lastHeight" (.effect (.contextRead .checkpointId))) ] }
def ctxMod : Module :=
  { name := "Ctx", state := #[ctxState], entrypoints := #[recordH] }

-- record mint
def tokenRec : StructDecl :=
  { name := "Token", fields := #[{ id := "owner", type := .address }, { id := "amount", type := .u64 }], isRecord := true }
def mint : Entrypoint :=
  { name := "mint", params := #[("amount", .u64)], returns := .structType "Token",
    body := #[ .return (.structLit "Token" #[("owner", .effect (.contextRead .userId)), ("amount", .local "amount")]) ] }
def recMod : Module :=
  { name := "Tok", structs := #[tokenRec], state := #[], entrypoints := #[mint] }

-- record transfer (consume)
def transfer : Entrypoint :=
  { name := "transfer", params := #[("input", .structType "Token"), ("receiver", .address)], returns := .structType "Token",
    body := #[ .return (.structLit "Token" #[("owner", .local "receiver"), ("amount", .field (.local "input") "amount")]) ] }
def xferMod : Module :=
  { name := "Tok2", structs := #[tokenRec], state := #[], entrypoints := #[transfer] }

-- hash
def hashU64 : Entrypoint :=
  { name := "hash_u64", params := #[("x", .u64)], returns := .hash, body := #[ .return (.hash (.local "x")) ] }
def hashMod : Module :=
  { name := "Zh", state := #[], entrypoints := #[hashU64] }

-- mixed (value, Final) return
def acct : StateDecl :=
  { id := "account", kind := .map .address 8, type := .u64 }
def withdraw : Entrypoint :=
  { name := "withdraw", params := #[("receiver", .address), ("amount", .u64)], returns := .structType "Token",
    body := #[
      .letBind "caller" .address (.effect (.contextRead .userId)),
      .letBind "current" .u64 (.effect (.storageMapGet "account" (.local "caller"))),
      .effect (.storageMapSet "account" (.local "caller") (.sub (.local "current") (.local "amount"))),
      .return (.structLit "Token" #[("owner", .local "receiver"), ("amount", .local "amount")])
    ] }
def mixedMod : Module :=
  { name := "Tok3", structs := #[tokenRec], state := #[acct], entrypoints := #[withdraw] }

-- crosscall (needs an external program; build will fail on missing import — expected)
def callMint : Entrypoint :=
  { name := "call_mint", params := #[("amount", .u64)], returns := .u64,
    body := #[ .return (.crosscallNamed "credits.aleo" "mint" #[.local "amount"] .u64) ] }
def ccMod : Module :=
  { name := "Caller", state := #[], entrypoints := #[callMint] }

def fixtures : Array (String × Module) := #[
  ("counter", Examples.Counter.module),
  ("puremath", Examples.PureMath.module),
  ("structprobe", Examples.StructProbe.module),
  ("mapledger", mapMod),
  ("context", ctxMod),
  ("recordmint", recMod),
  ("recordtransfer", xferMod),
  ("hash", hashMod),
  ("mixedreturn", mixedMod),
  ("crosscall", ccMod)
]

def main : IO UInt32 := do
  let dir := "build/aleo/verify"
  IO.FS.createDirAll dir
  for (name, m) in fixtures do
    match renderModule m with
    | .ok src => do
      IO.FS.writeFile s!"{dir}/{name}.leo" src
      IO.println s!"rendered {name}"
    | .error e => IO.println s!"RENDER FAIL {name}: {e.render}"
  return 0
