import Lake
open Lake DSL

package proof_forge_next where
  version := v!"0.1.0"

@[default_target]
lean_lib ProofForgeV2 where
  roots := #[`ProofForgeV2, `Examples]

lean_lib ProofForgeV2Tests where
  roots := #[
    `Tests.Core.Semantics,
    `Tests.Compiler.Pipeline,
    `Tests.Language.ProgramSyntax,
    `Tests.Language.Loader,
    `Tests.Materialization.Targets,
    `Tests.Materialization.NearHostModel,
    `Tests.CLI.Emit
  ]

lean_exe proof_forge_next where
  exeName := "proof-forge-next"
  root := `ProofForgeV2.CLI.Main

lean_exe proof_forge_next_tests where
  exeName := "proof-forge-next-tests"
  root := `Tests
