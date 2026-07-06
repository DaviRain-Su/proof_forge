import ProofForge.Cli

namespace ProofForge.Tests.CliConstructor

open ProofForge.Cli

def require (cond : Bool) (msg : String) : IO Unit :=
  unless cond do throw <| IO.userError msg

def head64 (hex : String) : String := (hex.take 64).toString
def wordAt (hex : String) (idx : Nat) : String := ((hex.drop (idx * 64)).take 64).toString

/-- Test: encode a single string constructor arg with head-offset + tail. -/
def testStringOnly : IO Unit := do
  let params := #[{ name := "name", abiType := "string" : ConstructorParamSpec }]
  let values := #[{ name := "name", value := "hello" : ConstructorValueSpec }]
  match encodeConstructorValues params values with
  | .ok hex =>
    require (hex.length >= 128) s!"expected >= 128 hex chars (2 head words + tail), got {hex.length}"
    require (head64 hex == "0000000000000000000000000000000000000000000000000000000000000020")
      s!"expected head offset 0x20, got: {head64 hex}"
    require (hex.contains "0000000000000000000000000000000000000000000000000000000000000005")
      "expected length-5 word in tail"
    IO.println s!"cli-constructor: string-only ok ({hex.length} hex chars)"
  | .error e => throw <| IO.userError s!"encodeConstructorValues string failed: {e}"

/-- Test: encode a single uint256[] constructor arg. -/
def testUint256ArrayOnly : IO Unit := do
  let params := #[{ name := "amounts", abiType := "uint256[]" : ConstructorParamSpec }]
  let values := #[{ name := "amounts", value := "1,2,3" : ConstructorValueSpec }]
  match encodeConstructorValues params values with
  | .ok hex =>
    require (hex.length >= 320) s!"expected >= 320 hex chars, got {hex.length}"
    require (head64 hex == "0000000000000000000000000000000000000000000000000000000000000020")
      s!"expected head offset 0x20, got: {head64 hex}"
    require (wordAt hex 1 == "0000000000000000000000000000000000000000000000000000000000000003")
      s!"expected count=3, got: {wordAt hex 1}"
    IO.println s!"cli-constructor: uint256[]-only ok ({hex.length} hex chars)"
  | .error e => throw <| IO.userError s!"encodeConstructorValues uint256[] failed: {e}"

/-- Test: encode mixed static (uint256) + dynamic (string). -/
def testMixedStaticDynamic : IO Unit := do
  let params := #[
    { name := "initial", abiType := "uint256" : ConstructorParamSpec },
    { name := "name", abiType := "string" : ConstructorParamSpec }
  ]
  let values := #[
    { name := "initial", value := "42" : ConstructorValueSpec },
    { name := "name", value := "test" : ConstructorValueSpec }
  ]
  match encodeConstructorValues params values with
  | .ok hex =>
    require (hex.length >= 256) s!"expected >= 256 hex chars, got {hex.length}"
    require (head64 hex == "000000000000000000000000000000000000000000000000000000000000002a")
      s!"expected first word = 42 (0x2a), got: {head64 hex}"
    require (wordAt hex 1 == "0000000000000000000000000000000000000000000000000000000000000040")
      s!"expected second word = offset 0x40, got: {wordAt hex 1}"
    IO.println s!"cli-constructor: mixed static+dynamic ok ({hex.length} hex chars)"
  | .error e => throw <| IO.userError s!"encodeConstructorValues mixed failed: {e}"

/-- Test: missing value should error. -/
def testMissingValue : IO Unit := do
  let params := #[{ name := "name", abiType := "string" : ConstructorParamSpec }]
  let values := #[]
  match encodeConstructorValues params values with
  | .ok _ => throw <| IO.userError "expected error for missing value"
  | .error e =>
    require (e.contains "missing") s!"expected 'missing' in error, got: {e}"
    IO.println "cli-constructor: missing-value error ok"

def main : IO UInt32 := do
  testStringOnly
  testUint256ArrayOnly
  testMixedStaticDynamic
  testMissingValue
  IO.println "CliConstructor: all tests passed"
  pure 0

end ProofForge.Tests.CliConstructor

-- This test imports the executable CLI module, whose root `main` would otherwise
-- run after elaboration and print usage. Exit from the test result instead.
#eval (do
  let exitCode ← ProofForge.Tests.CliConstructor.main
  IO.Process.exit exitCode.toUInt8
  pure () : IO Unit)
