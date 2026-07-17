import Lake
open Lake DSL

package «proof-forge-next» where
  version := v!"0.1.0"

@[default_target]
lean_lib ProofForgeV2 where
  roots := #[`ProofForgeV2, `Examples]

lean_lib ProofForgeV2Tests where
  roots := #[
    `Tests.Core.Common,
    `Tests.Core.CommonScalars,
    `Tests.Core.Semantics,
    `Tests.Compiler.Pipeline,
    `Tests.Compiler.TypedNameIndex,
    `Tests.Language.ProgramSyntax,
    `Tests.Language.FrontendParity,
    `Tests.Language.Loader,
    `Tests.Materialization.Targets,
    `Tests.Materialization.NearHostModel,
    `Tests.Materialization.NoirRelationModel,
    `Tests.CLI.Emit
  ]

lean_exe proof_forge_next where
  exeName := "proof-forge-next"
  root := `ProofForgeV2.CLI.Main
  -- Parser / module loading pulls Init interpreter symbols (e.g. IO.getRandomBytes).
  supportInterpreter := true

lean_exe proof_forge_next_tests where
  exeName := "proof-forge-next-tests"
  root := `Tests
  supportInterpreter := true
