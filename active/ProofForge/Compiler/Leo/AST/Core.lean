import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Compiler.Leo.AST

/-- Identifiers are plain strings. -/
abbrev Identifier := String

/-- Program ids are strings like "credits.aleo". -/
abbrev ProgramId := String

/-- Function visibility/input mode (public/private/constant). -/
inductive Mode where
  | public_
  | private_
  | constant_
  deriving BEq, Repr, Inhabited

/-- Annotation such as @noupgrade. -/
structure Annotation where
  name : Identifier
  deriving Repr, Inhabited

/-- Shared lowering/printer error. -/
structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String := err.message

/-- Indent a line by `level * 4` spaces. -/
def indent (level : Nat) (line : String) : String :=
  String.ofList (List.replicate (level * 4) ' ') ++ line

/-- Join an array of lines with newlines. -/
def lines (xs : Array String) : String :=
  String.intercalate "\n" xs.toList

end ProofForge.Compiler.Leo.AST
