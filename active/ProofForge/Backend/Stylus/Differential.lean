import ProofForge.Backend.Stylus.DirectWasm.Dispatch
import ProofForge.Backend.Stylus.Semantics

namespace ProofForge.Backend.Stylus.Differential

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.DirectWasm
open ProofForge.Backend.Stylus.Semantics

structure DifferentialReport where
  scenarios : Array String
  allMatched : Bool
  deriving Repr, BEq

private def methodCalldata (plan : StylusPlan) (name : String) : Except String Bytes := do
  let some method := plan.abi.methods.find? (fun method => method.name == name)
    | throw s!"Counter plan has no `{name}` method"
  pure method.selector

private def directCounter (plan : StylusPlan) (state : HostState) (calldata : Bytes) : HostState :=
  match resolveMethod plan.abi calldata with
  | .error error => revert { state with calldata, result := #[], revertData := #[], trace := #[] } error.bytes
  | .ok method =>
      let state := { state with calldata, result := #[], revertData := #[], trace := #[] }
      match method.name with
      | "initialize" => finish (storageFlush (storageCache state slotZero (encodeU64 0))) #[]
      | "increment" =>
          let (state, word) := storageLoad state slotZero
          let value := decodeU64 word
          if value == 2 ^ 64 - 1 then revert state overflowBytes
          else finish (storageFlush (storageCache state slotZero (encodeU64 (value + 1)))) #[]
      | "get" =>
          let (state, word) := storageLoad state slotZero
          finish state (encodeU64 (decodeU64 word))
      | _ => revert state AbiError.unknownSelector.bytes

private def equivalent (lhs rhs : HostState) : Bool :=
  lhs.storage == rhs.storage && lhs.cache == rhs.cache && lhs.result == rhs.result &&
    lhs.revertData == rhs.revertData && lhs.trace == rhs.trace

def runCounterDifferential (plan : StylusPlan) : Except String DifferentialReport := do
  let initial : HostState := {}
  let getData <- methodCalldata plan "get"
  let incrementData <- methodCalldata plan "increment"
  let abstractInitial <- executeCounter plan initial .get
  let directInitial := directCounter plan initial getData
  let largeState := { initial with storage := #[(slotZero, encodeU64 (2 ^ 63 + 17))] }
  let abstractLarge <- executeCounter plan largeState .get
  let directLarge := directCounter plan largeState getData
  let abstractIncrement <- executeCounter plan largeState .increment
  let directIncrement := directCounter plan largeState incrementData
  let overflowState := { initial with storage := #[(slotZero, encodeU64 (2 ^ 64 - 1))] }
  let abstractOverflow <- executeCounter plan overflowState .increment
  let directOverflow := directCounter plan overflowState incrementData
  let unknown := directCounter plan initial #[0xff, 0xff, 0xff, 0xff]
  let malformed := directCounter plan initial #[0x81, 0x29, 0xfc]
  let errorsMatch := unknown.revertData == AbiError.unknownSelector.bytes &&
    malformed.revertData == AbiError.truncatedCalldata.bytes && unknown.cache.isEmpty && malformed.cache.isEmpty
  pure {
    scenarios := #["initial-read", "large-set", "increment", "unknown-selector", "malformed-calldata", "overflow"]
    allMatched := equivalent abstractInitial directInitial && equivalent abstractLarge directLarge &&
      equivalent abstractIncrement directIncrement && equivalent abstractOverflow directOverflow && errorsMatch
  }

end ProofForge.Backend.Stylus.Differential

namespace ProofForge.Backend.Stylus

export Differential (DifferentialReport runCounterDifferential)

end ProofForge.Backend.Stylus
