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
    `Tests.Core.CommonRemaining,
    `Tests.Core.CommonScalars,
    `Tests.Core.Unicode,
    `Tests.Core.Semantics,
    `Tests.Compiler.Pipeline,
    `Tests.Compiler.TypedNameIndex,
    `Tests.Language.AggregateDeclarations,
    `Tests.Language.BytesTypes,
    `Tests.Language.ConstDeclarations,
    `Tests.Language.EventErrorDeclarations,
    `Tests.Language.ExtensionRequirements,
    `Tests.Language.FieldDeclarations,
    `Tests.Language.FnDeclarations,
    `Tests.Language.IntegerWidthDeclarations,
    `Tests.Language.OptionDeclarations,
    `Tests.Language.PrincipalDeclarations,
    `Tests.Language.UnitReturnTypes,
    `Tests.Language.InvariantDeclarations,
    `Tests.Language.ProofReferences,
    `Tests.Language.ProgramSyntax,
    `Tests.Language.PrimitiveDeclarations,
    `Tests.Language.StateVisibility,
    `Tests.Language.SourceIdentity,
    `Tests.Language.SourceSpan,
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
