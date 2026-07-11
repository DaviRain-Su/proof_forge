import ProofForge.Contract.Client
import ProofForge.Contract.Spec
import ProofForge.Cli.EvmAbi
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.EvmErrorsProbe
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmFallbackProbe
import ProofForge.Contract.Stdlib.NearFungibleToken
import Lean.Data.Json

namespace ProofForge.Tests.ContractClient

open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def renderEvm (spec : ContractSpec) (name : String) : IO String :=
  match ProofForge.Contract.Client.renderEvmAbiWrapper spec name with
  | .ok wrapper => pure wrapper
  | .error err => throw <| IO.userError s!"EVM client render failed: {err}"

def errorRefSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module

def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

def u64ParamEntrypoint : ProofForge.IR.Entrypoint := {
  name := "setValue"
  selector? := some "55241077"
  params := #[("value", .u64)]
  body := #[]
}

def u64ParamModule : ProofForge.IR.Module := {
  name := "U64ParamProbe"
  state := #[]
  entrypoints := #[u64ParamEntrypoint]
}

def u64ParamSpec : ContractSpec := ContractSpec.fromIR u64ParamModule

def addressOverrideEntrypoint : ProofForge.IR.Entrypoint := {
  name := "setOwner"
  selector? := some "13af4035"
  params := #[("owner", .u64)]
  paramAbiWords := #[some "address"]
  body := #[]
}

def addressOverrideSpec : ContractSpec := ContractSpec.fromIR {
  name := "AddressOverrideProbe"
  state := #[]
  entrypoints := #[addressOverrideEntrypoint]
}

def addressReturnOverrideEntrypoint : ProofForge.IR.Entrypoint := {
  name := "owner"
  selector? := some "8da5cb5b"
  mutability := .view
  «returns» := .u64
  returnAbiWord? := some "address"
  body := #[.return (.literal (.u64 1))]
}

def addressReturnOverrideSpec : ContractSpec := ContractSpec.fromIR {
  name := "AddressReturnOverrideProbe"
  state := #[]
  entrypoints := #[addressReturnOverrideEntrypoint]
}

def boolReturningCallParams : Array (String × ProofForge.IR.ValueType) :=
  #[("to", .u64), ("amount", .u64)]

def boolReturningCallEntrypoint : ProofForge.IR.Entrypoint := {
  name := "transfer"
  params := boolReturningCallParams
  «returns» := .bool
  body := #[.return (.literal (.bool true))]
}

def boolReturningCallSpec : ContractSpec := ContractSpec.fromIR {
  name := "BoolReturningCallProbe"
  state := #[]
  entrypoints := #[boolReturningCallEntrypoint]
}

def nearU64RoundTripEntrypoint : ProofForge.IR.Entrypoint := {
  name := "echo"
  mutability := .view
  params := #[("value", .u64)]
  «returns» := .u64
  body := #[.return (.local "value")]
}

def nearU64RoundTripSpec : ContractSpec := ContractSpec.fromIR {
  name := "NearU64RoundTrip"
  state := #[]
  entrypoints := #[nearU64RoundTripEntrypoint]
}

def testEvmWrapperErrors : IO Unit := do
  let wrapper ← renderEvm errorRefSpec "ErrorRefProbe"
  require (contains wrapper "export const ERRORS = [{\"assertionId\": 1")
    "EVM wrapper missing embedded ProofForge error catalogue"
  require (contains wrapper "\"userCode\": \"Counter::Overflow\"")
    "EVM wrapper missing Counter::Overflow error"
  require (contains wrapper "decodeProofForgeRevert")
    "EVM wrapper missing revert decoder"
  require (contains wrapper "ethers.AbiCoder.defaultAbiCoder().decode([\"uint32\", \"string\"], data)")
    "EVM wrapper missing ProofForge revert ABI decode"
  require (contains wrapper "errorByAssertionId")
    "EVM wrapper missing assertion-id lookup helper"

def testEvmCustomErrorArgDecoder : IO Unit := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.EvmErrorsProbe.module
  let wrapper ← renderEvm spec "EvmErrorsProbe"
  require (contains wrapper "\"solidityArgTypes\": [\"uint64\", \"uint64\"]")
    "EVM custom-error client missing static arg schema"
  require (contains wrapper "decodeProofForgeRevertDetails")
    "EVM custom-error client missing detailed decoder"
  require (contains wrapper "candidates.length !== 1")
    "EVM custom-error client must fail closed on selector collisions"
  require (contains wrapper "soliditySelector?.toLowerCase() === sel")
    "EVM custom-error client must normalize author-provided selector case"
  require (contains wrapper "AbiCoder.defaultAbiCoder().decode(argTypes")
    "EVM custom-error client must decode payload words from the revert data"
  require (contains wrapper "return decodeProofForgeRevertDetails(error)?.error;")
    "EVM custom-error client must preserve the legacy decoder API"
  require (!contains wrapper "solidityArgWords")
    "EVM custom-error client must not embed concrete compile-time words"
  require (!contains wrapper "9007199254740993")
    "EVM custom-error client must not serialize large words as JS numbers"

def testNearWrapperErrors : IO Unit := do
  let wrapper := ProofForge.Contract.Client.renderNearWrapper errorRefSpec
  require (contains wrapper "export const ERRORS = [{\"assertionId\": 1")
    "NEAR wrapper missing embedded ProofForge error catalogue"
  require (contains wrapper "\"userCode\": \"Counter::ExactMatch\"")
    "NEAR wrapper missing Counter::ExactMatch error"
  require (contains wrapper "parseProofForgePanic")
    "NEAR wrapper missing panic parser"
  require (contains wrapper "PF:(\\d+):([^\\s]+)")
    "NEAR wrapper missing ProofForge panic prefix parser"

def testCounterWrapperEmptyErrors : IO Unit := do
  let evmWrapper ← renderEvm counterSpec "Counter"
  let nearWrapper := ProofForge.Contract.Client.renderNearWrapper counterSpec
  require (contains evmWrapper "export const ERRORS = [] as const;")
    "EVM Counter wrapper should expose an empty errors catalogue"
  require (contains nearWrapper "export const ERRORS = [] as const;")
    "NEAR Counter wrapper should expose an empty errors catalogue"

def testEvmDeployHelpers : IO Unit := do
  let wrapper ← renderEvm counterSpec "Counter"
  require (contains wrapper "export const ARTIFACT_BASENAME = \"Counter\";")
    "EVM wrapper missing artifact basename"
  require (contains wrapper "runtimeBytecode: \"./Counter.bin\"")
    "EVM wrapper missing runtime bytecode path"
  require (contains wrapper "initCode: \"./Counter.init.bin\"")
    "EVM wrapper missing init code path"
  require (contains wrapper "deployFromArtifactDir")
    "EVM wrapper missing deployFromArtifactDir helper"
  require (contains wrapper "deployInitCode")
    "EVM wrapper missing deployInitCode helper"

def testEvmViewEntrypoints : IO Unit := do
  let wrapper ← renderEvm counterSpec "Counter"
  require (contains wrapper "export async function get(): Promise<bigint>")
    "EVM Counter wrapper should type get() as view call"
  require (contains wrapper "staticCall()")
    "EVM Counter wrapper should use staticCall for view entrypoints"
  require (contains wrapper "export async function increment(): Promise<void>")
    "EVM Counter wrapper should type increment() as mutating call"

def testEvmAbiUsesCanonicalU64Word : IO Unit := do
  let wrapper ← renderEvm u64ParamSpec "U64ParamProbe"
  require (contains wrapper "\"name\":\"value\",\"type\":\"uint256\"")
    "EVM client ABI must use the canonical dispatch type uint256 for IR U64"
  require (!contains wrapper "\"name\":\"value\",\"type\":\"uint64\"")
    "EVM client ABI must not diverge from dispatch with uint64"
  match ProofForge.Cli.entrypointSoliditySignature u64ParamModule u64ParamEntrypoint with
  | .error err => throw <| IO.userError s!"dispatch signature failed: {err}"
  | .ok signature =>
      require (signature == "setValue(uint256)")
        s!"dispatch signature diverged from generated client ABI: {signature}"

def testEvmAbiUsesCanonicalAggregateTypes : IO Unit := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.EvmAbiAggregateProbe.module
  let wrapper ← renderEvm spec "EvmAbiAggregateProbe"
  require (contains wrapper "\"name\":\"pair\",\"type\":\"tuple\",\"components\":[{\"name\":\"left\",\"type\":\"uint256\"},{\"name\":\"right\",\"type\":\"uint256\"}]")
    "EVM client ABI must render flat structs as tuple descriptors with named components"
  require (contains wrapper "\"name\":\"pairs\",\"type\":\"tuple[2]\",\"components\":[{\"name\":\"left\",\"type\":\"uint256\"},{\"name\":\"right\",\"type\":\"uint256\"}]")
    "EVM client ABI must retain tuple components on fixed arrays"
  require (!contains wrapper "\"type\":\"(uint256,uint256)\"")
    "EVM JSON ABI descriptor must not reuse the selector canonical tuple string"
  require (contains wrapper "\"name\":\"xs\",\"type\":\"uint256[3]\"")
    "EVM client ABI must render fixed arrays with canonical element words"

def testEvmAbiRejectsUnknownStruct : IO Unit := do
  let badSpec := ContractSpec.fromIR {
    name := "BadClientAbi"
    state := #[]
    entrypoints := #[{
      name := "bad"
      params := #[("value", .structType "Missing")]
      body := #[]
    }]
  }
  match ProofForge.Contract.Client.renderEvmAbiWrapper badSpec "BadClientAbi" with
  | .ok _ => throw <| IO.userError "EVM client ABI accepted an unknown struct"
  | .error err =>
      require (err.contains "unknown struct `Missing`")
        s!"unexpected unknown-struct diagnostic: {err}"

def testNearViewAndCallEntrypoints : IO Unit := do
  let wrapper := ProofForge.Contract.Client.renderNearWrapper counterSpec
  require (contains wrapper "export type NearCallOptions")
    "NEAR Counter wrapper should expose call options"
  require (contains wrapper "export type NearViewOptions")
    "NEAR Counter wrapper should expose view options"
  require (contains wrapper "export async function get(options: NearViewOptions = {}): Promise<bigint>")
    "NEAR Counter wrapper should type get() as view call with options"
  require (contains wrapper "nearViewFunctionBorsh({")
    "NEAR Counter wrapper should use the planned Borsh view transport"
  require (contains wrapper "methodName: \"get\"")
    "NEAR Counter wrapper should pass the view method name"
  require (contains wrapper "...options")
    "NEAR Counter wrapper should forward view options"
  require (contains wrapper "export async function initialize(options: NearCallOptions = {}): Promise<void>")
    "NEAR Counter wrapper should type initialize() as mutating call with options"
  require (contains wrapper "export async function increment(options: NearCallOptions = {}): Promise<void>")
    "NEAR Counter wrapper should type increment() as mutating call with options"
  require (contains wrapper "nearFunctionCallBorsh({")
    "NEAR Counter wrapper should use the planned Borsh call transport"
  require (contains wrapper "gas: options.gas")
    "NEAR Counter wrapper should forward gas options"
  require (contains wrapper "attachedDeposit: options.attachedDeposit ?? options.deposit")
    "NEAR Counter wrapper should forward deposit options"

def testReturnValueDoesNotImplyView : IO Unit := do
  let evmWrapper ← renderEvm boolReturningCallSpec "BoolReturningCallProbe"
  require (contains evmWrapper "\"name\":\"transfer\",\"type\":\"function\"")
    "EVM wrapper missing transfer ABI"
  require (contains evmWrapper "\"stateMutability\":\"nonpayable\"")
    "call entrypoint with a Bool return must remain nonpayable"
  require (contains evmWrapper "export async function transfer(to: bigint, amount: bigint): Promise<ethers.ContractTransactionReceipt | null>")
    "mutating EVM call with a return value must expose receipt semantics"
  require (contains evmWrapper "return await tx.wait();")
    "mutating EVM call with a return value must return the transaction receipt"
  require (!contains evmWrapper "staticCall(")
    "mutating EVM call with a return value must never use staticCall"

  let some ftTransferCall := ProofForge.Contract.Stdlib.NearFungibleToken.spec.module.entrypoints.find?
      (fun entrypoint => entrypoint.name == "ft_transfer_call")
    | throw <| IO.userError "NEAR FT fixture missing ft_transfer_call"
  let nearWrapper := ProofForge.Contract.Client.nearEntrypointWrapper ftTransferCall
  require (contains nearWrapper "options: NearCallOptions = {}")
    "NEAR ft_transfer_call must expose call options despite returning U64"
  require (contains nearWrapper "nearFunctionCallBorsh({")
    "NEAR ft_transfer_call must use the Borsh call transport despite returning U64"
  require (contains nearWrapper "Promise<unknown>")
    "NEAR ft_transfer_call must return the real execution outcome"
  require (contains nearWrapper "return await nearFunctionCallBorsh({")
    "NEAR ft_transfer_call must return its functionCall execution outcome"
  require (!contains nearWrapper "nearViewFunctionBorsh({")
    "NEAR ft_transfer_call must never be emitted as a view"

def testNearClientUsesContractBorshCodec : IO Unit := do
  let wrapper := ProofForge.Contract.Client.renderNearWrapper nearU64RoundTripSpec
  require (contains wrapper "encodeNearBorshArgs")
    "NEAR client must encode arguments with the contract codec plan"
  require (contains wrapper "decodeNearBorshU64")
    "NEAR client must decode scalar results with the contract codec plan"
  require (!contains wrapper "args: {\"value\": value}")
    "NEAR Borsh contract client must not send a JSON argument object"

  let unsupportedEntrypoint : ProofForge.IR.Entrypoint := {
    name := "echo_bytes"
    mutability := .view
    params := #[("value", ProofForge.IR.ValueType.bytes)]
    «returns» := ProofForge.IR.ValueType.bytes
    body := #[]
  }
  let unsupportedSpec := ProofForge.Contract.ContractSpec.fromIR {
    name := "UnsupportedDynamicNearClient"
    state := #[]
    entrypoints := #[unsupportedEntrypoint]
  }
  match ProofForge.Contract.Client.renderNearWrapperChecked unsupportedSpec with
  | .error message =>
      require (contains message "does not support dynamic")
        "unsupported NEAR client codec must report an actionable error"
  | .ok _ => throw <| IO.userError "unsupported NEAR client codec did not fail closed"

def testAbiWordControlsTypescriptParameterType : IO Unit := do
  let wrapper ← renderEvm addressOverrideSpec "AddressOverrideProbe"
  require (contains wrapper "\"name\":\"owner\",\"type\":\"address\"")
    "EVM ABI address override must encode the parameter as address"
  require (contains wrapper "export async function setOwner(owner: string): Promise<void>")
    "EVM ABI address override must expose a string TypeScript parameter"
  require (!contains wrapper "setOwner(owner: bigint)")
    "EVM ABI address override must not retain the underlying U64 TypeScript type"
  require (contains wrapper "contract.getFunction(\"setOwner\")(owner)")
    "EVM address override wrapper must forward the string value to ethers encoding"
  match ProofForge.Cli.entrypointSoliditySignature
      addressOverrideSpec.module addressOverrideEntrypoint with
  | .error err => throw <| IO.userError s!"address override signature failed: {err}"
  | .ok signature =>
      require (signature == "setOwner(address)")
        s!"address override selector signature diverged: {signature}"

def testAbiWordControlsTypescriptReturnType : IO Unit := do
  let wrapper ← renderEvm addressReturnOverrideSpec "AddressReturnOverrideProbe"
  require (contains wrapper "\"outputs\":[{\"type\":\"address\"}]")
    "EVM ABI address override must encode the return as address"
  require (contains wrapper "export async function owner(): Promise<string>")
    "EVM ABI address override must expose a string TypeScript return"
  require (!contains wrapper "owner(): Promise<bigint>")
    "EVM ABI address override must not expose the portable U64 carrier"

def testFallbackAndReceiveAbi : IO Unit := do
  let module := ProofForge.IR.Examples.EvmFallbackProbe.module
  let spec := ContractSpec.fromIR module
  let abi ← match ProofForge.Contract.Client.abiJson module with
    | .ok abi => pure abi
    | .error err => throw <| IO.userError s!"fallback ABI render failed: {err}"
  match Lean.Json.parse abi with
  | .ok _ => pure ()
  | .error err => throw <| IO.userError s!"fallback ABI is not valid JSON: {err}"
  require (contains abi "{\"type\":\"fallback\",\"stateMutability\":\"nonpayable\"}")
    "fallback ABI must use the standard fallback item shape"
  require (contains abi "{\"type\":\"receive\",\"stateMutability\":\"payable\"}")
    "receive ABI must use the standard payable receive item shape"
  require (!contains abi "\"name\":\"fallback\"")
    "fallback ABI must not contain a function name"
  require (!contains abi "\"name\":\"receive\"")
    "receive ABI must not contain a function name"
  let wrapper ← renderEvm spec "EvmFallbackProbe"
  require (!contains wrapper "export async function fallback(")
    "fallback must not generate a normal function wrapper"
  require (!contains wrapper "export async function receive(")
    "receive must not generate a normal function wrapper"

def main : IO UInt32 := do
  testEvmWrapperErrors
  testEvmCustomErrorArgDecoder
  testNearWrapperErrors
  testCounterWrapperEmptyErrors
  testEvmDeployHelpers
  testEvmViewEntrypoints
  testEvmAbiUsesCanonicalU64Word
  testEvmAbiUsesCanonicalAggregateTypes
  testEvmAbiRejectsUnknownStruct
  testNearViewAndCallEntrypoints
  testNearClientUsesContractBorshCodec
  testReturnValueDoesNotImplyView
  testAbiWordControlsTypescriptParameterType
  testAbiWordControlsTypescriptReturnType
  testFallbackAndReceiveAbi
  IO.println "contract-client: ok"
  return 0

end ProofForge.Tests.ContractClient

def main : IO UInt32 :=
  ProofForge.Tests.ContractClient.main
