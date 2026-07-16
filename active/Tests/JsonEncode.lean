/-
WasmHost.JsonEncode unit smoke: object/array schemas lower without hand putc.
-/
import ProofForge.Backend.WasmHost.JsonEncode
import ProofForge.Backend.WasmHost.Layout

namespace ProofForge.Tests.JsonEncode

open ProofForge.Backend.WasmHost.JsonEncode
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Compiler.Wasm

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

/-- Count putc of a specific byte immediate in insn stream. -/
def countPutc (insns : Array Insn) (byte : Nat) : Nat :=
  let needle := toString byte
  insns.foldl
    (fun n insn =>
      match insn with
      | .const .i32 v => if v == needle then n + 1 else n
      | _ => n)
    0

def hasCall (insns : Array Insn) (name : String) : Bool :=
  insns.any fun insn =>
    match insn with
    | .call n => n == name
    | _ => false

def main : IO UInt32 := do
  require (catalogId == "wasmhost.json_encode") "catalog id"
  require (crosscallSink.putcName == "__pf_crosscall_args_putc") "crosscall sink"
  require (eventSink.startName == "__pf_evt_start") "event sink"

  -- Static object: {"a":null,"b":true}
  match lower crosscallSink (.obj #[
      field "a" .null_,
      field "b" (.boolLit true)
    ]) with
  | .error e => throw (IO.userError s!"static obj: {e}")
  | .ok insns =>
      require (hasCall insns crosscallSink.startName) "starts buffer"
      require (hasCall insns crosscallSink.putcName) "uses putc"
      require (countPutc insns 0x7B >= 1) "opens {"
      require (countPutc insns 0x7D >= 1) "closes }"
      -- key 'a' and 'b' appear as putc sequences
      require (countPutc insns 'a'.toNat >= 1) "key a"
      require (countPutc insns 'b'.toNat >= 1) "key b"

  -- Empty object
  match lowerCrosscallArgs (.obj #[]) 47000 with
  | .error e => throw (IO.userError s!"empty obj: {e}")
  | .ok (insns, base, _) =>
      require (base == 47000) "buffer base"
      require (hasCall insns crosscallSink.startName) "empty starts"
      require (countPutc insns 0x7B == 1 && countPutc insns 0x7D == 1)
        "empty is {}"

  -- Array of static strings
  match lower crosscallSink (.arr #[.strLit "x", .strLit "y"]) with
  | .error e => throw (IO.userError s!"arr: {e}")
  | .ok insns =>
      require (countPutc insns 0x5B == 1) "open ["
      require (countPutc insns 0x5D == 1) "close ]"
      require (countPutc insns 0x2C >= 1) "comma between"

  -- NEP-141-shaped object with dynamic leaves (insns stubs)
  let idxStub : Array Insn := #[.i64Const 5]
  let amtStub : Array Insn := #[.i64Const 100]
  match lowerCrosscallArgs (.obj #[
      field "receiver_id" (.strPoolIdx idxStub),
      field "amount" (.u64Str amtStub),
      field "memo" .null_
    ]) 47000 with
  | .error e => throw (IO.userError s!"nep141 shape: {e}")
  | .ok (insns, _, _) =>
      require (hasCall insns "__pf_crosscall_pool_ptr") "pool ptr"
      require (hasCall insns "__pf_crosscall_pool_len") "pool len"
      require (hasCall insns crosscallSink.putu64Name) "putu64 for amount"
      require (hasCall insns crosscallSink.putstrName) "putstr for pool"
      -- receiver_id / amount / memo key fragments
      require (countPutc insns 'r'.toNat >= 1) "receiver key"
      require (countPutc insns 'm'.toNat >= 1) "memo/amount key"

  -- strPoolIdx without pool names fails on event sink
  match lower eventSink (.strPoolIdx #[.i64Const 0]) with
  | .ok _ => throw (IO.userError "event sink must reject strPoolIdx")
  | .error msg =>
      require (contains msg "poolPtr" || contains msg "strPoolIdx")
        "error names pool requirement"

  IO.println "json-encode: ok (object/array/nep141-shape/sink)"
  pure 0

end ProofForge.Tests.JsonEncode

def main : IO UInt32 :=
  ProofForge.Tests.JsonEncode.main
