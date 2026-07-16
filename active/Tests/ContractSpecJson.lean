import ProofForge.Contract.Spec.Json
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.EvmErrorsProbe

namespace ProofForge.Tests.ContractSpecJson

open ProofForge.Contract
open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def testCounterHasEmptyErrors : IO Unit := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let json := ProofForge.Contract.Spec.Json.render spec
  require (contains json "\"schema\": \"proof-forge.contract-spec.v0\"")
    "ContractSpec JSON missing schema marker"
  require (contains json "\"errors\": []")
    s!"Counter ContractSpec JSON should expose an empty errors array: {json}"

def testErrorRefProbeCatalog : IO Unit := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
  let json := ProofForge.Contract.Spec.Json.render spec
  require (contains json "\"errors\": [")
    "ErrorRefProbe ContractSpec JSON missing errors array"
  require (contains json "\"assertionId\": 1")
    "ErrorRefProbe ContractSpec JSON missing assertion id 1"
  require (contains json "\"userCode\": \"Counter::Overflow\"")
    "ErrorRefProbe ContractSpec JSON missing Counter::Overflow user code"
  require (contains json "\"message\": \"count must be under five\"")
    "ErrorRefProbe ContractSpec JSON missing guarded_increment message"
  require (contains json "\"entrypoints\": [\"guarded_increment\"]")
    "ErrorRefProbe ContractSpec JSON missing guarded_increment entrypoint ownership"
  require (contains json "\"assertionId\": 2")
    "ErrorRefProbe ContractSpec JSON missing assertion id 2"
  require (contains json "\"userCode\": \"Counter::ExactMatch\"")
    "ErrorRefProbe ContractSpec JSON missing Counter::ExactMatch user code"
  require (contains json "\"message\": \"count must equal seven\"")
    "ErrorRefProbe ContractSpec JSON missing exact_increment message"
  require (contains json "\"entrypoints\": [\"exact_increment\"]")
    "ErrorRefProbe ContractSpec JSON missing exact_increment entrypoint ownership"

def nestedModule : Module := {
  name := "NestedErrorCatalog"
  state := #[]
  entrypoints := #[{
    name := "nested"
    returns := .unit
    body := #[
      .ifElse (.literal (.bool true))
        #[
          .assert (.literal (.bool true))
            "nested true branch"
            (some { assertionId := 9, userCode? := some "Nested::Then" })
        ]
        #[
          .boundedFor "i" 0 1 #[
            .assertEq (.literal (.u32 1)) (.literal (.u32 1))
              "nested loop branch"
              (some { assertionId := 10, userCode? := some "Nested::Loop" })
          ]
        ]
    ]
  }]
}

def testNestedCatalog : IO Unit := do
  let spec := ContractSpec.fromIR nestedModule
  let json := ProofForge.Contract.Spec.Json.render spec
  require (contains json "\"assertionId\": 9")
    "nested ContractSpec JSON missing if-branch assertion id"
  require (contains json "\"userCode\": \"Nested::Then\"")
    "nested ContractSpec JSON missing if-branch user code"
  require (contains json "\"assertionId\": 10")
    "nested ContractSpec JSON missing bounded-loop assertion id"
  require (contains json "\"userCode\": \"Nested::Loop\"")
    "nested ContractSpec JSON missing bounded-loop user code"
  require (contains json "\"entrypoints\": [\"nested\"]")
    "nested ContractSpec JSON missing nested entrypoint ownership"

def repeatedCustomErrorModule : Module := {
  name := "RepeatedCustomError"
  state := #[]
  entrypoints := #[
    {
      name := "first"
      body := #[.revertWithError {
        assertionId := 7
        userCode? := some "InsufficientBalance"
        soliditySelector? := some "9432a7ee"
        solidityArgTypes := #["uint64", "uint64"]
        solidityArgWords := #[10, 3]
      }]
    },
    {
      name := "second"
      body := #[.revertWithError {
        assertionId := 99
        userCode? := some "DifferentPortableLabel"
        soliditySelector? := some "9432A7EE"
        solidityArgTypes := #["uint64", "uint64"]
        solidityArgWords := #[9007199254740993, 5]
      }]
    }
  ]
}

def testCustomErrorCatalogStoresSchemaNotValues : IO Unit := do
  let catalog := ProofForge.Contract.Spec.Json.errorCatalog repeatedCustomErrorModule
  require (catalog.size == 1)
    s!"same custom-error signature should deduplicate across sites, got {catalog.size} entries"
  let some entry := catalog[0]?
    | throw <| IO.userError "missing deduplicated custom-error catalogue entry"
  require (entry.solidityArgTypes == #["uint64", "uint64"])
    "custom-error catalogue lost ABI arg schema"
  require (entry.entrypoints == #["first", "second"])
    "custom-error catalogue did not merge entrypoint ownership"
  let json := ProofForge.Contract.Spec.Json.render (ContractSpec.fromIR repeatedCustomErrorModule)
  require (contains json "\"solidityArgTypes\": [\"uint64\", \"uint64\"]")
    "custom-error ContractSpec JSON missing ABI arg schema"
  require (!contains json "solidityArgWords")
    "custom-error ContractSpec JSON must not expose concrete ABI words"
  require (!contains json "9007199254740993")
    "custom-error ContractSpec JSON must not serialize large concrete values"

def testEvmErrorsProbeCustomErrorSchema : IO Unit := do
  let json := ProofForge.Contract.Spec.Json.render <|
    ContractSpec.fromIR ProofForge.IR.Examples.EvmErrorsProbe.module
  require (contains json "\"soliditySelector\": \"9432a7ee\"")
    "EvmErrorsProbe ContractSpec JSON missing custom-error selector"
  require (contains json "\"solidityArgTypes\": [\"uint64\", \"uint64\"]")
    "EvmErrorsProbe ContractSpec JSON missing custom-error arg types"
  require (!contains json "solidityArgWords")
    "EvmErrorsProbe ContractSpec JSON leaked concrete ABI words"

def main : IO UInt32 := do
  testCounterHasEmptyErrors
  testErrorRefProbeCatalog
  testNestedCatalog
  testCustomErrorCatalogStoresSchemaNotValues
  testEvmErrorsProbeCustomErrorSchema
  IO.println "contract-spec-json: ok"
  return 0

end ProofForge.Tests.ContractSpecJson

def main : IO UInt32 :=
  ProofForge.Tests.ContractSpecJson.main
