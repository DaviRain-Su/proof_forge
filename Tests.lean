import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.Semantics
import Tests.Compiler.Pipeline
import Tests.Compiler.TypedNameIndex
import Tests.Language.AggregateDeclarations
import Tests.Language.DeclarationAcceptance
import Tests.Language.ArrayTypes
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
import Tests.Language.EmitStatements
import Tests.Language.EventErrorDeclarations
import Tests.Language.ExtensionRequirements
import Tests.Language.FieldDeclarations
import Tests.Language.FnDeclarations
import Tests.Language.ForStatements
import Tests.Language.IfStatements
import Tests.Language.IntegerWidthDeclarations
import Tests.Language.LetStatements
import Tests.Language.OptionDeclarations
import Tests.Language.PrincipalDeclarations
import Tests.Language.UnitReturnTypes
import Tests.Language.InvariantDeclarations
import Tests.Language.ProofReferences
import Tests.Language.ProgramExports
import Tests.Language.ProgramExportAcceptance
import Tests.Language.ProgramCommandAcceptance
import Tests.Language.ProgramBindings
import Tests.Language.ProgramIdentities
import Tests.Language.ProgramPayloads
import Tests.Language.ProgramShortNames
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
import Tests.Language.LocalFnCalls
import Tests.Language.ConstructorExprs
import Tests.Language.IndexAccesses
import Tests.Language.RevertStatements
import Tests.Language.ValueLessReturns
import Tests.Language.PrimitiveDeclarations
import Tests.Language.StateVisibility
import Tests.Language.SourceIdentity
import Tests.Language.SourceSpan
import Tests.Language.SourceWireAcceptance
import Tests.Language.SourceBoundsAcceptance
import Tests.Language.SourceWireCodecV1
import Tests.Language.SourceWireDecodeV1
import Tests.Language.SourceNameComponentV1
import Tests.Language.SourceQualifiedNameV1
import Tests.Language.SourceAstLeafV1
import Tests.Language.SourceAstSupportV1
import Tests.Language.SourceAstPatternV1
import Tests.Language.SourceAstDeclV1
import Tests.Language.SourceAstSpineV1
import Tests.Language.SourceAstSpineCodecV1
import Tests.Language.SourceAstSpineDeclV1
import Tests.Language.SourceAstProgramItemV1
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
  Tests.Language.DeclarationAcceptance.run
  Tests.Language.AssertStatements.run
  Tests.Language.BitwiseNot.run
  Tests.Language.BoolLiterals.run
  Tests.Language.CheckedDiv.run
  Tests.Language.CheckedMod.run
  Tests.Language.CheckedMul.run
  Tests.Language.CheckedNeg.run
  Tests.Language.CheckedSub.run
  Tests.Language.EmitStatements.run
  Tests.Language.ForStatements.run
  Tests.Language.IfStatements.run
  Tests.Language.LetStatements.run
  Tests.Language.ProgramExports.run
  Tests.Language.ProgramExportAcceptance.run
  Tests.Language.ProgramCommandAcceptance.run
  Tests.Language.ProgramBindings.run
  Tests.Language.ProgramIdentities.run
  Tests.Language.ProgramPayloads.run
  Tests.Language.ProgramShortNames.run
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
  Tests.Language.LocalFnCalls.run
  Tests.Language.ConstructorExprs.run
  Tests.Language.IndexAccesses.run
  Tests.Language.RevertStatements.run
  Tests.Language.ValueLessReturns.run
  Tests.Language.run
  Tests.Language.SourceWireAcceptance.run
  Tests.Language.SourceBoundsAcceptance.run
  Tests.Language.SourceWireCodecV1.run
  Tests.Language.SourceWireDecodeV1.run
  Tests.Language.SourceNameComponentV1.run
  Tests.Language.SourceQualifiedNameV1.run
  Tests.Language.SourceAstLeafV1.run
  Tests.Language.SourceAstSupportV1.run
  Tests.Language.SourceAstPatternV1.run
  Tests.Language.SourceAstDeclV1.run
  Tests.Language.SourceAstSpineV1.run
  Tests.Language.SourceAstSpineCodecV1.run
  Tests.Language.SourceAstSpineDeclV1.run
  Tests.Language.SourceAstProgramItemV1.run
  Tests.Language.FrontendParity.run
  Tests.Language.Grouping.run
  Tests.Language.Loader.run
  Tests.Language.LogicalNot.run
  Tests.Materialization.run
  Tests.Materialization.NearHostModel.run
  Tests.Materialization.NoirRelationModel.run
  Tests.CLI.Emit.run
  IO.println "proof-forge-next-tests: ok"
