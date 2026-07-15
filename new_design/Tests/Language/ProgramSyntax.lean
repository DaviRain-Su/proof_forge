import ProofForgeV2.Examples.Counter
import ProofForgeV2.Examples.PrivateSum4
import ProofForgeV2.Compiler.Pipeline

namespace A

open ProofForgeV2.Language

program Counter where
  view get() : UInt64 do
    return 0

end A

namespace B

open ProofForgeV2.Language

program Counter where
  view get() : UInt64 do
    return 0

end B

namespace Tests.Language

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def isSha256Hex (value : String) : Bool :=
  value.length == 64 && value.toList.all fun char =>
    "0123456789abcdef".toList.contains char

def run : IO Unit := do
  expect (Crypto.sha256Hex "".toUTF8 ==
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    "SHA-256 must match the empty-message reference vector"
  expect (Crypto.sha256Hex "abc".toUTF8 ==
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    "SHA-256 must match the abc reference vector"
  expect (Examples.counter.name == "Counter") "program must preserve its source name"
  expect (Examples.counter.qualifiedName == "ProofForgeV2.Examples.Counter")
    "program must preserve its fully-qualified identity"
  expect (Examples.counter.entries.map (·.name) == #["increment", "get"]) "program entries must elaborate in source order"
  let counter ← match Compiler.compile Examples.counter with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let privateSum ← match Compiler.compile Examples.privateSum4 with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (counter.requirements.contains .persistentState) "requirements must be inferred from semantic state"
  expect (counter.requirements.contains .checkedArithmetic) "requirements must be inferred from checked semantic addition"
  expect (privateSum.requirements.contains .privateWitness) "private parameters must infer semantic disclosure requirements"
  expect (A.Counter.name == "Counter" && B.Counter.name == "Counter")
    "artifact names must remain short"
  expect (A.Counter.qualifiedName == "A.Counter" && B.Counter.qualifiedName == "B.Counter")
    "namespace must participate in program identity"
  expect (A.Counter.sourceHash != B.Counter.sourceHash)
    "fully-qualified identity must participate in source hashing"
  expect (isSha256Hex A.Counter.sourceHash && isSha256Hex B.Counter.sourceHash)
    "source hashes must be 64-character lower-case SHA-256 hex"

end Tests.Language
