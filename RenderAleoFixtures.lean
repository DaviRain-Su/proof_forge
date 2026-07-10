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

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

-- map storage
def ledgerState : StateDecl :=
  { id := "ledger", kind := .map .u64 8, type := .u64 }
def seed : Entrypoint :=
  { name := "seed", body := #[ .effect (.storageMapSet "ledger" (.literal (.u64 0)) (.literal (.u64 42))) ] }
def mapMod : Module :=
  { name := "Ledger", state := #[ledgerState], entrypoints := #[seed] }

-- Full Counter is intentionally rejected: Leo 4.0.2 cannot return a mapping
-- read from `get() -> U64`. The write-only fragment is executable evidence.
def counterWriteMod : Module :=
  { Examples.Counter.module with
    entrypoints := #[Examples.Counter.initializeEntrypoint, Examples.Counter.increment] }

-- context read
def ctxState : StateDecl :=
  { id := "lastHeight", kind := .scalar, type := .u32 }
def recordH : Entrypoint :=
  { name := "record_height",
    body := #[ .effect (.storageScalarWrite "lastHeight" (.effect (.contextRead .checkpointId))) ] }
def ctxMod : Module :=
  { name := "Ctx", state := #[ctxState], entrypoints := #[recordH] }

-- Address storage is valid when used write-only (no fallback identity needed).
def addressState : StateDecl :=
  { id := "recipient", kind := .scalar, type := .address }
def writeAddress : Entrypoint :=
  { name := "write_address", params := #[("receiver", .address)],
    body := #[.effect (.storageScalarWrite "recipient" (.local "receiver"))] }
def addressWriteMod : Module :=
  { name := "AddressWrite", state := #[addressState], entrypoints := #[writeAddress] }

-- Ordinary value-struct storage default without address remains executable.
def snapshotValue : StructDecl :=
  { name := "Snapshot", fields := #[
      { id := "amount", type := .u64 },
      { id := "enabled", type := .bool }
    ] }
def snapshotState : StateDecl :=
  { id := "snapshot", kind := .scalar, type := .structType "Snapshot" }
def updateSnapshot : Entrypoint :=
  { name := "update_snapshot", params := #[("amount", .u64)],
    body := #[.effect (.storageStructFieldWrite "snapshot" "amount" (.local "amount"))] }
def snapshotMod : Module :=
  { name := "SnapshotStore", structs := #[snapshotValue], state := #[snapshotState],
    entrypoints := #[updateSnapshot] }

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

-- Negative storage-default fixtures. These belong to the real Leo gate so a
-- regression that renders `none` as an address fails before package creation.
def readAddress : Entrypoint :=
  { name := "read_address", body := #[
      .letBind "stored" .address (.effect (.storageScalarRead "recipient"))
    ] }
def addressReadMod : Module :=
  { name := "AddressRead", state := #[addressState], entrypoints := #[readAddress] }

def contactValue : StructDecl :=
  { name := "Contact", fields := #[{ id := "account", type := .address }] }
def envelopeValue : StructDecl :=
  { name := "Envelope", fields := #[{ id := "contact", type := .structType "Contact" }] }
def readEnvelope : Entrypoint :=
  { name := "read_envelope", body := #[
      .letBind "stored" (.structType "Envelope") (.effect (.storageScalarRead "envelope"))
    ] }
def nestedAddressReadMod : Module :=
  { name := "NestedAddressRead", structs := #[contactValue, envelopeValue],
    state := #[{ id := "envelope", kind := .scalar, type := .structType "Envelope" }],
    entrypoints := #[readEnvelope] }

def fixtures : Array (String × Module) := #[
  ("address-write", addressWriteMod),
  ("counter-write", counterWriteMod),
  ("puremath", Examples.PureMath.module),
  ("mapledger", mapMod),
  ("context", ctxMod),
  ("recordmint", recMod),
  ("recordtransfer", xferMod),
  ("value-struct-default", snapshotMod),
  ("hash", hashMod),
  ("mixedreturn", mixedMod),
  ("crosscall", ccMod)
]

def rejectedFixtures : Array (String × Module × String) := #[
  ("address-default", addressReadMod, "Mapping::get_or_use"),
  ("nested-address-default", nestedAddressReadMod, "Envelope.contact.account")
]

def main : IO UInt32 := do
  let dir := "build/aleo/verify"
  IO.FS.createDirAll dir
  let mut failed := false
  for (name, m) in fixtures do
    match renderModule m with
    | .ok src => do
      IO.FS.writeFile s!"{dir}/{name}.leo" src
      IO.println s!"rendered {name}"
    | .error e =>
      failed := true
      IO.println s!"RENDER FAIL {name}: {e.render}"
  for (name, m, marker) in rejectedFixtures do
    match renderModule m with
    | .error e =>
      if e.message.contains "storage default" && e.message.contains marker then
        IO.println s!"rejected {name}: OK"
      else
        failed := true
        IO.println s!"REJECT DIAGNOSTIC FAIL {name}: {e.render}"
    | .ok _ =>
      failed := true
      IO.println s!"REJECT FAIL {name}: unexpectedly rendered"
  return if failed then 1 else 0
