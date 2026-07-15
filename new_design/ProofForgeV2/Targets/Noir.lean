import ProofForgeV2.Targets.Common

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2 Source

def descriptor : TargetDescriptor := {
  targetId := .noir
  artifactEncoding := .noirSource
  executionHost := .circuit
  commitModel := .externalStateTransition
  stateBinding := .proofInputs
  callModel := .none
  proofModel := .circuitProof
  settlementModel := .externalVerifier
  codegenProfile := "noir-acir-bb-v1"
  supportedRequirements := #[
    .persistentState, .checkedArithmetic, .transactionalRollback, .privateWitness
  ]
}

inductive Shape where
  | stateTransition
  | privateSum4
  deriving Inhabited, Repr

structure Plan where
  source : SemanticProgram
  shape : Shape
  stateContinuity : String
  publicInputs : Array String
  privateInputs : Array String
  deriving Inhabited, Repr

structure IR where
  name : String
  source : String
  package : String
  prover : String
  deriving Inhabited, Repr

def makePlan (resolved : ResolvedProgram .noir) : CompileResult Plan := do
  if Targets.isExactCounter resolved.source then
    return {
      source := resolved.source
      shape := .stateTransition
      stateContinuity := "external"
      publicInputs := #["old_count", "delta", "new_count"]
      privateInputs := #[]
    }
  else if Targets.isExactPrivateSum4 resolved.source then
    return {
      source := resolved.source
      shape := .privateSum4
      stateContinuity := "none"
      publicInputs := #["result"]
      privateInputs := #["a", "b", "c", "d"]
    }
  else
    throw <| .planInvariant .noir "v2alpha1 supports Counter transition or four-input private sum"

def lower (plan : Plan) : CompileResult IR :=
  let source := match plan.shape with
    | .stateTransition =>
        "fn main(old_count: pub Field, delta: pub Field, new_count: pub Field) {\n" ++
        "    assert(old_count < 18446744073709551616);\n" ++
        "    assert(delta < 18446744073709551616);\n" ++
        "    assert(old_count + delta == new_count);\n" ++
        "    assert(new_count < 18446744073709551616);\n}\n"
    | .privateSum4 =>
        "fn main(a: Field, b: Field, c: Field, d: Field, result: pub Field) {\n" ++
        "    assert(a < 18446744073709551616);\n" ++
        "    assert(b < 18446744073709551616);\n" ++
        "    assert(c < 18446744073709551616);\n" ++
        "    assert(d < 18446744073709551616);\n" ++
        "    assert(a + b + c + d == result);\n" ++
        "    assert(result < 18446744073709551616);\n}\n"
  let package := s!"[package]\nname = \"{plan.source.name.toLower}\"\ntype = \"bin\"\nauthors = [\"ProofForge V2\"]\ncompiler_version = \">=1.0.0\"\n"
  let prover := match plan.shape with
    | .stateTransition => "old_count = \"7\"\ndelta = \"5\"\nnew_count = \"12\"\n"
    | .privateSum4 => "a = \"1\"\nb = \"2\"\nc = \"3\"\nd = \"4\"\nresult = \"10\"\n"
  .ok { name := plan.source.name, source, package, prover }

def emit (ir : IR) : CompileResult (Array OutputFile) := .ok #[
  { path := "src/main.nr", mediaType := "text/x-noir", contents := ir.source },
  { path := "Nargo.toml", mediaType := "text/toml", contents := ir.package },
  { path := "Prover.toml", mediaType := "text/toml", contents := ir.prover }
]

instance : Materializer .noir where
  Plan := Plan
  TargetIR := IR
  makePlan := makePlan
  lower := lower
  emit := emit

def materialize (program : SemanticProgram) : CompileResult OutputSet := do
  let resolved ← Targets.resolve descriptor program
  let plan ← makePlan resolved
  let ir ← lower plan
  let files ← emit ir
  return Targets.makeOutput descriptor program false files

end ProofForgeV2.Targets.Noir
