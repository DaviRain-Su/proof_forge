import ProofForgeV2.Targets.Common

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2 Source

def descriptor : TargetDescriptor := {
  targetId := .solana
  artifactEncoding := .sbpfAssembly
  executionHost := .solanaRuntime
  commitModel := .instructionAtomic
  stateBinding := .explicitAccounts
  callModel := .cpi
  proofModel := .none
  settlementModel := .solana
  codegenProfile := "solana-sbpf-asm-v1"
  supportedRequirements := #[
    .persistentState, .checkedArithmetic, .transactionalRollback
  ]
}

structure Plan where
  source : SemanticProgram
  accountSize : Nat
  ownerRequired : Bool
  writableRequired : Bool
  deriving Inhabited, Repr

structure IR where
  name : String
  assembly : String
  idl : String
  deriving Inhabited, Repr

def makePlan (resolved : ResolvedProgram .solana) : CompileResult Plan := do
  unless Targets.isExactCounter resolved.source do
    throw <| .planInvariant .solana "v2alpha1 only plans the exact checked Counter semantics"
  return { source := resolved.source, accountSize := 8, ownerRequired := true, writableRequired := true }

def lower (plan : Plan) : CompileResult IR :=
  let assembly := s!"; NON-EXECUTABLE ProofForge V2 sBPF plan skeleton\n; program: {plan.source.name}\n; required account[0]: owner-checked, writable, data_len >= {plan.accountSize}\n; planned instruction 0 = initialize(u64)\n; planned instruction 1 = increment(u64), checked overflow\n; planned instruction 2 = get() -> return_data(u64)\n.text\n.globl entrypoint\nentrypoint:\n  ; no semantic lowering exists yet; manifest MUST remain deployable=false\n  exit\n"
  let idl := "{\n" ++
    "  \"version\": \"0.1.0\",\n" ++
    s!"  \"name\": \"{plan.source.name}\",\n" ++
    "  \"instructions\": [\n" ++
    "    {\"name\":\"initialize\",\"accounts\":[{\"name\":\"state\",\"isMut\":true,\"isSigner\":false}],\"args\":[{\"name\":\"initial\",\"type\":\"u64\"}]},\n" ++
    "    {\"name\":\"increment\",\"accounts\":[{\"name\":\"state\",\"isMut\":true,\"isSigner\":false}],\"args\":[{\"name\":\"delta\",\"type\":\"u64\"}]},\n" ++
    "    {\"name\":\"get\",\"accounts\":[{\"name\":\"state\",\"isMut\":false,\"isSigner\":false}],\"args\":[]}\n" ++
    "  ]\n}\n"
  .ok { name := plan.source.name, assembly, idl }

def emit (ir : IR) : CompileResult (Array OutputFile) := .ok #[
  { path := s!"{ir.name}.s", mediaType := "text/x-proof-forge-sbpf-plan", contents := ir.assembly },
  { path := s!"{ir.name}.idl.json", mediaType := "application/json", contents := ir.idl }
]

instance : Materializer .solana where
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

end ProofForgeV2.Targets.Solana
