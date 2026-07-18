import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.Semantics
import Tests.Compiler.Pipeline
import Tests.Compiler.TypedNameIndex
import Tests.Language.AggregateDeclarations
import Tests.Language.AssertStatements
import Tests.Language.BitwiseNot
import Tests.Language.BoolLiterals
import Tests.Language.BytesTypes
import Tests.Language.CheckedDiv
import Tests.Language.CheckedMod
import Tests.Language.CheckedMul
import Tests.Language.CheckedNeg
import Tests.Language.CheckedSub
import Tests.Language.ConstDeclarations
import Tests.Language.EventErrorDeclarations
import Tests.Language.ExtensionRequirements
import Tests.Language.FieldDeclarations
import Tests.Language.FnDeclarations
import Tests.Language.IntegerWidthDeclarations
import Tests.Language.LetStatements
import Tests.Language.OptionDeclarations
import Tests.Language.PrincipalDeclarations
import Tests.Language.UnitReturnTypes
import Tests.Language.InvariantDeclarations
import Tests.Language.ProofReferences
import Tests.Language.ProgramSyntax
import Tests.Language.ShiftLeft
import Tests.Language.ShiftRight
import Tests.Language.Equal
import Tests.Language.NotEqual
import Tests.Language.LessThan
import Tests.Language.LessEqual
import Tests.Language.GreaterThan
import Tests.Language.GreaterEqual
import Tests.Language.BitwiseAnd
import Tests.Language.BitwiseXor
import Tests.Language.BitwiseOr
import Tests.Language.LogicalAnd
import Tests.Language.LogicalOr
import Tests.Language.StringLiterals
import Tests.Language.PrimitiveDeclarations
import Tests.Language.StateVisibility
import Tests.Language.SourceIdentity
import Tests.Language.SourceSpan
import Tests.Language.FrontendParity
import Tests.Language.Grouping
import Tests.Language.Loader
import Tests.Language.LogicalNot
import Tests.Materialization.Targets
import Tests.Materialization.NearHostModel
import Tests.Materialization.NoirRelationModel
import Tests.CLI.Emit

unsafe def main : IO Unit := do
  Tests.Core.Common.run
  Tests.Core.CommonRemaining.run
  Tests.Core.CommonScalars.run
  Tests.Core.Unicode.run
  Tests.Core.run
  Tests.Compiler.run
  Tests.Compiler.TypedNameIndex.run
  Tests.Language.AggregateDeclarations.run
  Tests.Language.AssertStatements.run
  Tests.Language.BitwiseNot.run
  Tests.Language.BoolLiterals.run
  Tests.Language.BytesTypes.run
  Tests.Language.CheckedDiv.run
  Tests.Language.CheckedMod.run
  Tests.Language.CheckedMul.run
  Tests.Language.CheckedNeg.run
  Tests.Language.CheckedSub.run
  Tests.Language.ConstDeclarations.run
  Tests.Language.EventErrorDeclarations.run
  Tests.Language.ExtensionRequirements.run
  Tests.Language.FieldDeclarations.run
  Tests.Language.FnDeclarations.run
  Tests.Language.IntegerWidthDeclarations.run
  Tests.Language.LetStatements.run
  Tests.Language.OptionDeclarations.run
  Tests.Language.PrincipalDeclarations.run
  Tests.Language.UnitReturnTypes.run
  Tests.Language.InvariantDeclarations.run
  Tests.Language.ProofReferences.run
  Tests.Language.ShiftLeft.run
  Tests.Language.ShiftRight.run
  Tests.Language.Equal.run
  Tests.Language.NotEqual.run
  Tests.Language.LessThan.run
  Tests.Language.LessEqual.run
  Tests.Language.GreaterThan.run
  Tests.Language.GreaterEqual.run
  Tests.Language.BitwiseAnd.run
  Tests.Language.BitwiseXor.run
  Tests.Language.BitwiseOr.run
  Tests.Language.LogicalAnd.run
  Tests.Language.LogicalOr.run
  Tests.Language.StringLiterals.run
  Tests.Language.run
  Tests.Language.PrimitiveDeclarations.run
  Tests.Language.StateVisibility.run
  Tests.Language.SourceIdentity.run
  Tests.Language.SourceSpan.run
  Tests.Language.FrontendParity.run
  Tests.Language.Grouping.run
  Tests.Language.Loader.run
  Tests.Language.LogicalNot.run
  Tests.Materialization.run
  Tests.Materialization.NearHostModel.run
  Tests.Materialization.NoirRelationModel.run
  Tests.CLI.Emit.run
  IO.println "proof-forge-next-tests: ok"
