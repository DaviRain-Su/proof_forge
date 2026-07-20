import Tests.Language.AggregateDeclarations
import Tests.Language.ArrayTypes
import Tests.Language.BytesTypes
import Tests.Language.ConstDeclarations
import Tests.Language.EventErrorDeclarations
import Tests.Language.ExtensionRequirements
import Tests.Language.FieldDeclarations
import Tests.Language.FnDeclarations
import Tests.Language.IntegerWidthDeclarations
import Tests.Language.OptionDeclarations
import Tests.Language.PrincipalDeclarations
import Tests.Language.UnitReturnTypes
import Tests.Language.InvariantDeclarations
import Tests.Language.ProofReferences
import Tests.Language.PrimitiveDeclarations
import Tests.Language.StateVisibility

namespace Tests.Language.DeclarationAcceptance

/-- Labeled TST-SRC-004 packaging: exact once each declaration suite, current aggregate order. -/
unsafe def run : IO Unit := do
  Tests.Language.AggregateDeclarations.run
  Tests.Language.ArrayTypes.run
  Tests.Language.BytesTypes.run
  Tests.Language.ConstDeclarations.run
  Tests.Language.EventErrorDeclarations.run
  Tests.Language.ExtensionRequirements.run
  Tests.Language.FieldDeclarations.run
  Tests.Language.FnDeclarations.run
  Tests.Language.IntegerWidthDeclarations.run
  Tests.Language.OptionDeclarations.run
  Tests.Language.PrincipalDeclarations.run
  Tests.Language.UnitReturnTypes.run
  Tests.Language.InvariantDeclarations.run
  Tests.Language.ProofReferences.run
  Tests.Language.PrimitiveDeclarations.run
  Tests.Language.StateVisibility.run

end Tests.Language.DeclarationAcceptance
