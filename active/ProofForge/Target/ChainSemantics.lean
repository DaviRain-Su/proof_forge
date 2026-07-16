import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target

/-- Target-specific interpretation of "native value".

The portable IR only carries a coarse `value.native` capability. Exact units and
width are chain properties: NEAR exposes attached deposits as yoctoNEAR/u128,
EVM exposes msg.value as wei/u256, and Solana uses lamports/u64. -/
inductive NativeAmountSemantics where
  | evmWeiU256
  | nearYoctoNearU128
  | cosmWasmFunds
  | solanaLamportsU64
  | moveCoinResources
  deriving BEq, DecidableEq, Repr

def NativeAmountSemantics.id : NativeAmountSemantics → String
  | .evmWeiU256 => "evm.wei.u256"
  | .nearYoctoNearU128 => "near.yoctonear.u128"
  | .cosmWasmFunds => "cosmwasm.funds"
  | .solanaLamportsU64 => "solana.lamports.u64"
  | .moveCoinResources => "move.coin_resources"

def NativeAmountSemantics.description : NativeAmountSemantics → String
  | .evmWeiU256 => "EVM msg.value in wei, conceptually U256"
  | .nearYoctoNearU128 => "NEAR attached_deposit in yoctoNEAR, encoded as U128"
  | .cosmWasmFunds => "CosmWasm message funds as a denomination-indexed coin list"
  | .solanaLamportsU64 => "Solana lamports as U64"
  | .moveCoinResources => "Move native value as coin resources"

def NativeAmountSemantics.exactBitWidth? : NativeAmountSemantics → Option Nat
  | .evmWeiU256 => some 256
  | .nearYoctoNearU128 => some 128
  | .solanaLamportsU64 => some 64
  | .cosmWasmFunds | .moveCoinResources => none

def NativeAmountSemantics.hasExactU64Projection : NativeAmountSemantics → Bool
  | .solanaLamportsU64 => true
  | _ => false

def NativeAmountSemantics.requiresWideAmountType (sem : NativeAmountSemantics) : Bool :=
  match sem.exactBitWidth? with
  | some width => width > 64
  | none => true

/-- Chain event indexing semantics. EVM topics are a different semantic object
than NEAR JSON logs, so indexed IR must not be lowered by assuming one model. -/
inductive IndexedEventSemantics where
  | unsupported
  | evmTopics (maxIndexedFields : Nat)
  | nearJsonLogNoTopics
  | cosmWasmAttributes
  | moveEvents
  deriving BEq, DecidableEq, Repr

def IndexedEventSemantics.id : IndexedEventSemantics → String
  | .unsupported => "unsupported"
  | .evmTopics n => s!"evm.topics.{n}"
  | .nearJsonLogNoTopics => "near.json_log.no_topics"
  | .cosmWasmAttributes => "cosmwasm.attributes"
  | .moveEvents => "move.events"

def IndexedEventSemantics.description : IndexedEventSemantics → String
  | .unsupported => "indexed events are not modeled for this target"
  | .evmTopics n => s!"EVM LOG topics with up to {n} indexed fields"
  | .nearJsonLogNoTopics => "NEAR events are logs; indexed fields have no native topic index"
  | .cosmWasmAttributes => "CosmWasm events expose attributes rather than EVM topics"
  | .moveEvents => "Move events are typed event resources"

/-- Cross-contract execution is chain-specific even when the portable IR uses a
single crosscall capability. -/
inductive CrosscallSemantics where
  | unsupported
  | evmCall
  | nearPromise
  | cosmWasmSubmessage
  | solanaCpi
  | moveEntryFunction
  deriving BEq, DecidableEq, Repr

def CrosscallSemantics.id : CrosscallSemantics → String
  | .unsupported => "unsupported"
  | .evmCall => "evm.call"
  | .nearPromise => "near.promise"
  | .cosmWasmSubmessage => "cosmwasm.submessage"
  | .solanaCpi => "solana.cpi"
  | .moveEntryFunction => "move.entry_function"

def CrosscallSemantics.description : CrosscallSemantics → String
  | .unsupported => "cross-contract execution is not modeled for this target"
  | .evmCall => "EVM CALL/STATICCALL/DELEGATECALL/create-family execution"
  | .nearPromise => "NEAR Promise-based asynchronous cross-contract execution"
  | .cosmWasmSubmessage => "CosmWasm messages and submessages"
  | .solanaCpi => "Solana CPI"
  | .moveEntryFunction => "Move entry-function invocation"

structure ChainSemantics where
  nativeAmount? : Option NativeAmountSemantics := none
  indexedEvents : IndexedEventSemantics := .unsupported
  crosscall : CrosscallSemantics := .unsupported
  notes : Array String := #[]
  deriving Repr

def ChainSemantics.hasNativeAmount (sem : ChainSemantics) : Bool :=
  sem.nativeAmount?.isSome

def ChainSemantics.requiresNativeAmountProjection (sem : ChainSemantics) : Bool :=
  match sem.nativeAmount? with
  | some amount => amount.requiresWideAmountType
  | none => false

end ProofForge.Target
