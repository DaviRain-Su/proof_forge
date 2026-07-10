import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo mixed `(value, Final)` return.

Leo 4.x lets a function return a value AND run on-chain finalize:
`fn f(...) -> (T, Final) { ...; return (value, final { <storage effects> }); }`
(verified against ProvableHQ/leo functions/transfer_inline). This is how real
Aleo tokens do public<->private conversions (e.g. transfer_public_to_private:
build a private record off-chain, then decrement a public mapping in `final`).

The lowering partitions conservatively: pure (non-storage) statements +
the pure return value run off-chain; storage read/write statements run in
`final {}` in source order. It is only used when the return value is pure
(functions whose return value reads state keep the plain `fn -> Final` shape). -/

namespace ProofForge.Tests.AleoLeoMixedReturnSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

def tokenRecord : StructDecl :=
  { name := "Token"
    fields := #[{ id := "owner", type := .address }, { id := "amount", type := .u64 }]
    isRecord := true }

def account : StateDecl :=
  { id := "account", kind := .map .address 8, type := .u64 }

/-- `fn withdraw(receiver: address, amount: u64) -> (Token, Final) {
--     let caller: address = self.caller;
--     return (Token { owner: receiver, amount: amount }, final {
--         let current: u64 = Mapping::get_or_use(account, caller, 0u64);
--         Mapping::set(account, caller, (current - amount));
--     });
--   }` -/
def withdraw : Entrypoint :=
  { name := "withdraw"
    params := #[("receiver", .address), ("amount", .u64)]
    returns := .structType "Token"
    body := #[
      .letBind "caller" .address (.effect (.contextRead .userId)),
      .letBind "current" .u64 (.effect (.storageMapGet "account" (.local "caller"))),
      .effect (.storageMapSet "account" (.local "caller") (.sub (.local "current") (.local "amount"))),
      .return (.structLit "Token" #[("owner", .local "receiver"), ("amount", .local "amount")])
    ] }

def mixedModule : Module :=
  { name := "Tok3", structs := #[tokenRecord], state := #[account], entrypoints := #[withdraw] }

def mixedLowersOk : Bool :=
  match renderModule mixedModule with
  | .ok _ => true
  | .error _ => false

theorem mixed_lowers_ok : mixedLowersOk = true := by native_decide

/-- The lowered Leo uses the mixed `(Token, Final)` return with off-chain record
build + on-chain finalize. -/
def mixedLeoHasMarkers : Bool :=
  match renderModule mixedModule with
  | .ok s =>
      s.contains "fn withdraw(receiver: address, amount: u64) -> (Token, Final)" &&
      s.contains "let caller: address = self.caller;" &&
      s.contains "return (Token { owner: receiver, amount: amount }, final {" &&
      s.contains "Mapping::get_or_use(account, caller, 0u64)" &&
      s.contains "Mapping::set(account, caller, (current - amount))" &&
      s.contains "});"
  | .error _ => false

theorem mixed_leo_has_markers : mixedLeoHasMarkers = true := by native_decide

example : True := by
  have _ := @mixed_lowers_ok
  have _ := @mixed_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoMixedReturnSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-mixed-return-smoke: (value, Final) return checked"
  return 0
