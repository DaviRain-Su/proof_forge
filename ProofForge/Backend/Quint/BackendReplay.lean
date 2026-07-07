import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay

namespace ProofForge.Backend.Quint.BackendReplay

open ProofForge.IR.Semantics

/-- Shared error type for backend-specific Quint replay renderers. The renderers
still expose backend-named aliases, but they now share one message carrier. -/
structure BackendReplayError where
  message : String
deriving Repr

def BackendReplayError.render (err : BackendReplayError) : String := err.message

def BackendReplayError.fromReplay (err : Replay.ReplayError) : BackendReplayError :=
  { message := err.message }

def liftReplay (result : Except Replay.ReplayError α) : Except BackendReplayError α :=
  result.mapError BackendReplayError.fromReplay

def indent (n : Nat) (lines : List String) : String :=
  let pad := String.ofList (List.replicate n ' ')
  String.intercalate "\n" (lines.map (fun line => pad ++ line))

/-- Read a primary scalar state variable from an ITF state. C-diff renderers use
this to derive expected backend observations from the same MBT trace. -/
def itfNatValue (state : ITF.State) (varName : String) : Except BackendReplayError Nat :=
  match state.vars.find? (fun (k, _) => k == varName) with
  | some (_, .int n) => .ok n
  | some (_, v) => .error {
      message := s!"expected int for `{varName}` in ITF state {state.index}, got {repr v}" }
  | none => .error { message := s!"missing ITF field `{varName}` in state {state.index}" }

def traceActionName (module : ProofForge.IR.Module) (state : ITF.State) :
    Except BackendReplayError String :=
  liftReplay (Replay.resolveActionName module state.actionTaken state.nondetPicks)

def entrypointArgs (entrypoint : ProofForge.IR.Entrypoint)
    (picks : List (String × ITF.Value)) :
    Except BackendReplayError (Array ProofForge.IR.Semantics.Value) :=
  liftReplay (Replay.buildArgs entrypoint picks)

/-- Little-endian byte list for a bounded-width unsigned integer. -/
def leBytes (byteLen : Nat) (n : Nat) : Array Nat :=
  (List.range byteLen).map (fun i => (n / (256 ^ i)) % 256) |>.toArray

def hexChar (n : Nat) : Char :=
  match n % 16 with
  | 0 => '0'
  | 1 => '1'
  | 2 => '2'
  | 3 => '3'
  | 4 => '4'
  | 5 => '5'
  | 6 => '6'
  | 7 => '7'
  | 8 => '8'
  | 9 => '9'
  | 10 => 'a'
  | 11 => 'b'
  | 12 => 'c'
  | 13 => 'd'
  | 14 => 'e'
  | _ => 'f'

def byteHex (b : Nat) : String :=
  String.ofList [hexChar (b / 16), hexChar b]

def bytesHex (bytes : Array Nat) : String :=
  String.intercalate "" (bytes.toList.map byteHex)

def leHex (byteLen : Nat) (n : Nat) : String :=
  bytesHex (leBytes byteLen n)

def renderRustLeBytes (byteLen : Nat) (n : Nat) : String :=
  String.intercalate ", " ((leBytes byteLen n).toList.map toString)

/-- Encode scalar IR values in the portable little-endian argument format used
by the NEAR offline host and Solana instruction payloads. -/
def encodeScalarLeBytes (v : Value) : Except BackendReplayError (Array Nat) :=
  match v with
  | .u8 n => .ok (leBytes 1 n)
  | .u32 n => .ok (leBytes 4 n)
  | .u64 n => .ok (leBytes 8 n)
  | .u128 n => .ok (leBytes 16 n)
  | .bool b => .ok (leBytes 1 (if b then 1 else 0))
  | .address n => .ok (leBytes 8 n)
  | .hash a b c d => .ok (leBytes 8 a ++ leBytes 8 b ++ leBytes 8 c ++ leBytes 8 d)
  | .unit => .ok #[]
  | other => .error { message := s!"backend replay cannot encode scalar argument: {repr other}" }

def encodeScalarLeHex (v : Value) : Except BackendReplayError String := do
  pure (bytesHex (← encodeScalarLeBytes v))

end ProofForge.Backend.Quint.BackendReplay
