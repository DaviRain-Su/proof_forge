import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo Road 2 slice 2: record CONSUME / transfer.

In Leo 4.x a record-typed function parameter is a consumed (spent) proof input
(verified against ProvableHQ/leo data_types/record_update:
`fn top_up(base: Token) -> Token { return Token { amount: 100u64, ..base }; }`).
That means record consume/transfer is expressible through the EXISTING portable
IR — a record-typed `Entrypoint` parameter plus a record return — with no IR
changes:

  fn transfer(input: Token, receiver: address) -> Token {
      return Token { owner: receiver, amount: input.amount };
  }

`input` is consumed; a new record is created for `receiver`. (Leo enforces
record balance at execute time; this is valid sourcegen.) -/

namespace ProofForge.Tests.AleoLeoRecordTransferSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

def tokenRecord : StructDecl :=
  { name := "Token"
    fields := #[{ id := "owner", type := .address }, { id := "amount", type := .u64 }]
    isRecord := true }

def transfer : Entrypoint :=
  { name := "transfer"
    params := #[("input", .structType "Token"), ("receiver", .address)]
    returns := .structType "Token"
    body := #[ .return (.structLit "Token"
        #[("owner", .local "receiver"), ("amount", .field (.local "input") "amount")]) ] }

def transferModule : Module :=
  { name := "Tok2", structs := #[tokenRecord], state := #[], entrypoints := #[transfer] }

def transferLowersOk : Bool :=
  match renderModule transferModule with
  | .ok _ => true
  | .error _ => false

theorem transfer_lowers_ok : transferLowersOk = true := by native_decide

/-- The lowered Leo source consumes a record param and returns a new record. -/
def transferLeoHasMarkers : Bool :=
  match renderModule transferModule with
  | .ok s =>
      s.contains "program tok2.aleo" &&
      s.contains "record Token {" &&
      s.contains "fn transfer(input: Token, receiver: address) -> Token" &&
      s.contains "Token { owner: receiver, amount: input.amount }"
  | .error _ => false

theorem transfer_leo_has_markers : transferLeoHasMarkers = true := by native_decide

example : True := by
  have _ := @transfer_lowers_ok
  have _ := @transfer_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoRecordTransferSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-record-transfer-smoke: record consume/transfer checked"
  return 0
