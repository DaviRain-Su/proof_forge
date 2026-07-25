import Lean
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ValidatedSourceV1
import Std.Data.HashSet

open Lean Parser Command
open ProofForgeV2

namespace ProofForgeV2.Language

declare_syntax_cat pfType
/-- Parse a leading identifier plus an optional same-line second atom that is
either an identifier (Field/Option) or a numeral (Bytes length). Line equality
prevents the following program item from becoming part of the type. -/
@[pfType_parser] def portableType := leading_parser
  withPosition (ident >> optional (checkLineEq >> (ident <|> numLit)))
@[pfType_parser default+1] def arrayFieldType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayBytesType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayOptionOptionFieldType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayOptionOptionBytesType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayOptionOptionType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayOptionBytesType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayOptionType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def arrayArrayFieldType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit >> checkLineEq >> numLit)
@[pfType_parser default+1] def arrayArrayType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLineEq >> numLit)
@[pfType_parser default+1] def arrayType := leading_parser
  withPosition (nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit)
@[pfType_parser default+1] def optionFieldType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident)
@[pfType_parser default+1] def optionOptionFieldType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident)
@[pfType_parser default+1] def optionOptionBytesType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit)
@[pfType_parser default+1] def optionOptionArrayFieldType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionOptionArrayBytesType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionOptionArrayType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionOptionOptionFieldType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident)
@[pfType_parser default+1] def optionOptionOptionBytesType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit)
@[pfType_parser default+1] def optionOptionOptionType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >> ident)
@[pfType_parser default+1] def optionOptionType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >> ident)
@[pfType_parser default+1] def optionBytesType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit)
@[pfType_parser default+1] def optionArrayType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionArrayFieldType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionArrayOptionType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionArrayBytesType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Bytes " (includeIdent := true) >> checkLineEq >> numLit >>
    checkLineEq >> numLit)
@[pfType_parser default+1] def optionArrayArrayFieldType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Field " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit >> checkLineEq >> numLit)
@[pfType_parser default+1] def optionArrayArrayType := leading_parser
  withPosition (nonReservedSymbol "Option " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> numLit >> checkLineEq >> numLit)

declare_syntax_cat pfParam
syntax ident " : " pfType : pfParam
syntax "public " ident " : " pfType : pfParam
syntax "private " ident " : " pfType : pfParam
syntax "commitment " ident " : " pfType : pfParam

declare_syntax_cat pfExpr
declare_syntax_cat pfPlace
syntax ident : pfPlace
syntax:max pfPlace "." ident : pfPlace
syntax:max pfPlace "[" pfExpr "]" : pfPlace
syntax num : pfExpr
syntax str : pfExpr
syntax pfPlace : pfExpr
syntax:max ident "(" pfExpr,* ")" : pfExpr
syntax:75 "-" pfExpr:75 : pfExpr
syntax:75 "~" pfExpr:75 : pfExpr
syntax:75 "!" pfExpr:75 : pfExpr
syntax:60 pfExpr:60 " << " pfExpr:61 : pfExpr
syntax:60 pfExpr:60 " >> " pfExpr:61 : pfExpr
syntax:50 pfExpr:51 " == " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " != " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " < " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " <= " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " > " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " >= " pfExpr:51 : pfExpr
syntax:45 pfExpr:45 " & " pfExpr:46 : pfExpr
syntax:40 pfExpr:40 " ^ " pfExpr:41 : pfExpr
/-- Bitwise-or keeps its original precedence (35, lhs 35, rhs 36) but rejects
the operator when a line break precedes it: `|` is also the match arm
delimiter, and without this guard an arm body like `return 0` absorbs the
next arm's bar as a bit-or continuation. All other infix tokens cannot start
an arm. -/
@[pfExpr_parser] def bitOrExpr := trailing_parser:35:35
  notFollowedBy (checkLinebreakBefore) "no line break" >> " | " >> categoryParser `pfExpr 36
syntax:30 pfExpr:30 " && " pfExpr:31 : pfExpr
syntax:25 pfExpr:25 " || " pfExpr:26 : pfExpr
syntax:65 pfExpr:65 " + " pfExpr:66 : pfExpr
syntax:65 pfExpr:65 " - " pfExpr:66 : pfExpr
syntax:70 pfExpr:70 " * " pfExpr:71 : pfExpr
syntax:70 pfExpr:70 " / " pfExpr:71 : pfExpr
syntax:70 pfExpr:70 " % " pfExpr:71 : pfExpr
/-- Primary parenthesized grouping. High-precedence outer result; inner uses min
precedence 0 so full `+`/`-`/`*` expressions remain legal inside. Desugars only. -/
syntax:max "(" pfExpr:0 ")" : pfExpr
/-- Exact bare `true` bool literal (contextual, not a host Lean keyword).
Higher priority than generic identifier; no low fallback. -/
@[pfExpr_parser default+1] def boolTrueExpr := leading_parser
  nonReservedSymbol "true" (includeIdent := true)
/-- Exact bare `false` bool literal (contextual, not a host Lean keyword).
Higher priority than generic identifier; no low fallback. -/
@[pfExpr_parser default+1] def boolFalseExpr := leading_parser
  nonReservedSymbol "false" (includeIdent := true)

declare_syntax_cat pfPattern
syntax "_" : pfPattern
syntax ident : pfPattern
syntax num : pfPattern
syntax str : pfPattern
/-- Constructor pattern: `QualifiedId(PatternList?)`. Max precedence leading form so
bare `ident` remains a bind pattern and call-like shapes route here only when followed
by `(`; empty argument lists decode to `#[]`. -/
syntax:max ident "(" pfPattern,* ")" : pfPattern
@[pfPattern_parser default+1] def boolTruePattern := leading_parser
  nonReservedSymbol "true" (includeIdent := true)
@[pfPattern_parser default+1] def boolFalsePattern := leading_parser
  nonReservedSymbol "false" (includeIdent := true)

declare_syntax_cat pfStmtMatchArm
/-- One match arm: `| Pattern => do` plus an indented nonempty block. Mirrors
ifStmt/forStmt indentation discipline; the bar column is owned by the enclosing
match, the body must be strictly deeper. -/
@[pfStmtMatchArm_parser default+1] def stmtMatchArm := leading_parser withPosition (
  "| " >> categoryParser `pfPattern 0 >> " => " >> "do" >>
  checkLinebreakBefore >> checkColGt >> many1Indent (categoryParser `pfStmt 0))

declare_syntax_cat pfStmt
syntax pfPlace " := " pfExpr : pfStmt
@[pfStmt_parser default+1] def returnValueStmt := leading_parser
  withPosition ("return " >> (checkLineEq <|> checkColGt) >> categoryParser `pfExpr 0)
syntax "return" : pfStmt
syntax "call " ident "(" pfExpr,* ")" : pfStmt
syntax "schedule " ident "(" pfExpr,* ")" : pfStmt
syntax "call " str : pfStmt
syntax "assert " pfExpr " else " ident : pfStmt
syntax "assert " pfExpr : pfStmt
syntax "revert " ident "(" pfExpr,* ")" : pfStmt
syntax "revert " ident : pfStmt
syntax "emit " ident "(" pfExpr,* ")" : pfStmt
@[pfStmt_parser default+1] def ifStmt := leading_parser withPosition (
    "if " >> categoryParser `pfExpr 0 >> " then" >> checkLinebreakBefore >> checkColGt >>
    many1Indent (categoryParser `pfStmt 0) >>
    optional (checkColEq >> "else" >> checkLinebreakBefore >> checkColGt >>
      many1Indent (categoryParser `pfStmt 0)))
@[pfStmt_parser default+1] def matchStmt := leading_parser withPosition (
  "match " >> categoryParser `pfExpr 0 >> " with" >>
  checkLinebreakBefore >> checkColEq >> many1Indent (categoryParser `pfStmtMatchArm 0))
@[pfStmt_parser default+1] def forStmt := leading_parser withPosition (
    "for " >> ident >> checkLineEq >> " in " >> checkLineEq >> categoryParser `pfExpr 0 >>
    checkLineEq >> " ..< " >> checkLineEq >> categoryParser `pfExpr 0 >> checkLineEq >>
    " bounded " >> checkLineEq >> numLit >> checkLineEq >> " do" >> checkLinebreakBefore >>
    checkColGt >> many1Indent (categoryParser `pfStmt 0))
/-- Same-line annotated let (contextual, not a host Lean keyword). No low fallback. -/
@[pfStmt_parser default+1] def letStmtAnnotated := leading_parser
  withPosition (
    nonReservedSymbol "let " (includeIdent := true) >>
    checkLineEq >> ident >>
    checkLineEq >> " : " >> checkLineEq >> categoryParser `pfType 0 >>
    checkLineEq >> " := " >> checkLineEq >> categoryParser `pfExpr 0)
/-- Same-line omitted-type let (contextual, not a host Lean keyword). No low fallback. -/
@[pfStmt_parser default+1] def letStmtOmitted := leading_parser
  withPosition (
    nonReservedSymbol "let " (includeIdent := true) >>
    checkLineEq >> ident >>
    checkLineEq >> " := " >> checkLineEq >> categoryParser `pfExpr 0)

declare_syntax_cat pfAggregateMember
/-- Field name, type introducer, optional same-line second type atom (ident or
numeral). Both arms keep checkLinebreakBefore so the next field starts cleanly. -/
@[pfAggregateMember_parser] def aggregateField := leading_parser
  withPosition (ident >> " : " >> ident >>
    (checkLinebreakBefore <|> checkLineEq >> (ident <|> numLit) >> checkLinebreakBefore))
@[pfAggregateMember_parser default+1] def arrayFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayOptionOptionFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayOptionOptionBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayOptionOptionAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayOptionBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayOptionAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayArrayFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayArrayAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >> checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def arrayAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionArrayFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionArrayBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionArrayAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionOptionFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionOptionBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionOptionAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> ident >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionOptionAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> ident >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionArrayAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionArrayFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionArrayOptionAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionArrayBytesAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Bytes " (includeIdent := true) >>
    checkLineEq >> numLit >> checkLineEq >> numLit >> checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionArrayArrayFieldAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Field " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLineEq >> numLit >>
    checkLinebreakBefore)
@[pfAggregateMember_parser default+1] def optionArrayArrayAggregateField := leading_parser
  withPosition (ident >> " : " >> nonReservedSymbol "Option " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> nonReservedSymbol "Array " (includeIdent := true) >>
    checkLineEq >> ident >> checkLineEq >> numLit >> checkLineEq >> numLit >>
    checkLinebreakBefore)
syntax "| " ident linebreak : pfAggregateMember
syntax "| " ident "(" sepBy(pfType, ", ") ")" linebreak : pfAggregateMember

declare_syntax_cat pfItem
@[pfItem_parser default+1] def bareErrorDecl := leading_parser
  withPosition (nonReservedSymbol "error " (includeIdent := true) >> checkLineEq >> ident >>
    checkLinebreakBefore)
syntax "state " ident " : " pfType : pfItem
syntax "state " "public " ident " : " pfType : pfItem
syntax "state " "private " ident " : " pfType : pfItem
syntax "state " "commitment " ident " : " pfType : pfItem
syntax ident ident "(" sepBy(pfParam, ", ") ")" : pfItem
syntax ident ident " where" ppLine manyIndent(pfAggregateMember) : pfItem
@[pfItem_parser default+1] def constDecl := leading_parser
  withPosition (nonReservedSymbol "const " (includeIdent := true) >> checkLineEq >> ident >>
    " : " >> categoryParser `pfType 0 >> " := " >> categoryParser `pfExpr 0)
@[pfItem_parser default+1] def invariantDecl := leading_parser
  withPosition (nonReservedSymbol "invariant " (includeIdent := true) >> checkLineEq >> ident >>
    " : " >> categoryParser `pfExpr 0)
@[pfItem_parser default+1] def extensionReq := leading_parser
  withPosition (nonReservedSymbol "requires " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "extension " (includeIdent := true) >> checkLineEq >> ident >> checkLineEq >>
    nonReservedSymbol "version " (includeIdent := true) >> checkLineEq >> strLit >> ppLine >>
    withPosition (nonReservedSymbol "digest " (includeIdent := true) >> checkLineEq >> strLit))
@[pfItem_parser default+1] def proofDecl := leading_parser
  withPosition (nonReservedSymbol "proof " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> nonReservedSymbol "using " (includeIdent := true) >> checkLineEq >> ident)
/-- Preserve invalid escaped/unknown contextual shapes long enough for the
shared decoder to emit the stable unsupported-item diagnostic. -/
@[pfItem_parser low] def unsupportedConstLikeDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> " : " >> categoryParser `pfType 0 >>
    " := " >> categoryParser `pfExpr 0)
@[pfItem_parser low] def unsupportedInvariantLikeDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> " : " >> categoryParser `pfExpr 0 >>
    checkLinebreakBefore)
@[pfItem_parser low] def unsupportedExtensionLikeReq := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLineEq >> ident >> checkLineEq >> ident >>
    checkLineEq >> strLit >> ppLine >> withPosition (ident >> checkLineEq >> strLit))
@[pfItem_parser low] def unsupportedProofIntroducer := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLineEq >>
    nonReservedSymbol "using " (includeIdent := true) >> checkLineEq >> ident)
@[pfItem_parser low] def unsupportedBareItemDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLinebreakBefore)
syntax ident ident "(" sepBy(pfParam, ", ") ")" (" : " pfType)? " do" ppLine manyIndent(pfStmt) : pfItem
syntax "init" "(" sepBy(pfParam, ", ") ")" " do" ppLine manyIndent(pfStmt) : pfItem
syntax "entry " ident "(" sepBy(pfParam, ", ") ")" (" : " pfType)? " do" ppLine manyIndent(pfStmt) : pfItem
syntax "view " ident "(" sepBy(pfParam, ", ") ")" (" : " pfType)? " do" ppLine manyIndent(pfStmt) : pfItem

syntax (name := programDecl) "program " ident " where" ppLine ppIndent(pfItem*) : command

/-- Maximum nodes in one portable decoder subtree, including its root. -/
def maxSyntaxNodes : Nat := 100000

/-- Maximum root-inclusive depth in one portable decoder subtree. -/
def maxSyntaxNesting : Nat := 256

/-- Count name components iteratively, returning `none` before exceeding `limit`. -/
def boundedNamePartCount (limit : Nat) (name : Name) : Option Nat := Id.run do
  let mut current := name
  let mut count := 0
  while current != .anonymous do
    if count >= limit then
      return none
    count := count + 1
    current := current.getPrefix
  return some count

/-- Iterative post-parser preflight over one portable Syntax subtree. This runs
before the recursive DSL decoder or macro expander; it does not protect Lean's
parser itself or impose an aggregate limit across multiple programs. -/
def preflightSyntax (root : Syntax) : CompileResult Unit := do
  let mut pending : Array (Syntax × Nat) := #[(root, 1)]
  let mut discovered := 1
  while !pending.isEmpty do
    let (current, nesting) := pending.back!
    pending := pending.pop
    if nesting > maxSyntaxNesting then
      throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
    match current with
    | .ident _ _ name _ =>
        if (boundedNamePartCount maxSyntaxNesting name).isNone then
          throw <| .resourceBound
            s!"portable identifier nesting exceeds limit {maxSyntaxNesting}"
    | _ => pure ()
    for child in current.getArgs do
      let childNesting := nesting + 1
      if childNesting > maxSyntaxNesting then
        throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
      if discovered >= maxSyntaxNodes then
        throw <| .resourceBound s!"portable syntax exceeds node limit {maxSyntaxNodes}"
      discovered := discovered + 1
      pending := pending.push (child, childNesting)

private def preflightForDecoder (stx : Syntax) : Except String Unit :=
  (preflightSyntax stx).mapError CompileError.render

/-- Decode the registered Lean syntax tree into the target-neutral source AST.
This function is also used by the non-elaborating CLI loader. -/
private def rawIdentifierText? : Syntax → Option String
  | .ident _ rawValue _ _ => some rawValue.toString
  | _ => none

private def decodePortableIdentifierName (name : String) : Except String String :=
  if name == "struct" || name == "enum" || name == "const" || name == "event" ||
      name == "error" || name == "fn" || name == "invariant" || name == "requires" ||
      name == "extension" || name == "version" || name == "digest" || name == "proof" ||
      name == "using" then
    .error s!"reserved portable identifier '{name}'"
  else
    .ok name

private def decodeIdentifier (stx : Syntax) : Except String String :=
  decodePortableIdentifierName stx.getId.toString

private def decodeExtensionId (stx : Syntax) : Except String String := do
  let id ← match rawIdentifierText? stx with
    | some value => pure value
    | none => throw "unsupported extension id"
  match ProofForgeV2.Core.Common.parseSchemaId id with
  | .ok _ => pure id
  | .error message => throw (message.replace "schema id" "extension id")

private def decodeExtensionVersion (stx : Syntax) : Except String String := do
  let value ← match stx.isStrLit? with
    | some value => pure value
    | none => throw "unsupported extension version literal"
  let parsed ← ProofForgeV2.Core.Common.parseSemVer value
  let canonical ← ProofForgeV2.Core.Common.renderSemVer parsed
  unless canonical == value do
    throw "extension version must use canonical exact SemVer"
  pure canonical

private def decodeExtensionDigest (stx : Syntax) : Except String String := do
  let value ← match stx.isStrLit? with
    | some value => pure value
    | none => throw "unsupported extension digest literal"
  let parsed ← ProofForgeV2.Core.Common.parseDigest value
  let canonical ← ProofForgeV2.Core.Common.renderDigest parsed
  unless canonical == value do
    throw "extension digest must use canonical sha256 spelling"
  pure canonical

private def decodeProofTheorem (stx : Syntax) : Except String (Array String) := do
  let mut components : Array String := #[]
  for component in stx.getId.components do
    match component with
    | .str .anonymous value =>
        components := components.push (← decodePortableIdentifierName value)
    | _ => throw "qualified-name component must use Lean identifier characters"
  let qualified ← ProofForgeV2.Core.Common.parseQualifiedName components
  let canonical ← ProofForgeV2.Core.Common.renderQualifiedNameComponents qualified
  unless canonical.size >= 2 do
    throw "proof theorem name must contain at least two components"
  pure canonical

private def decodeConstructorPath (stx : Syntax) : Except String (Array String) := do
  let mut components : Array String := #[]
  for component in stx.getId.components do
    match component with
    | .str .anonymous value => components := components.push (← decodePortableIdentifierName value)
    | _ => throw "qualified-name component must use Lean identifier characters"
  let qualified ← ProofForgeV2.Core.Common.parseQualifiedName components
  let canonical ← ProofForgeV2.Core.Common.renderQualifiedNameComponents qualified
  unless canonical.size >= 2 do throw "constructor path must contain at least two components"
  pure canonical

private def decodeTypeIdentifiers (first : Syntax) (second : Option Syntax) :
    Except String ProofForgeV2.Source.ValueType :=
  match rawIdentifierText? first, second.bind rawIdentifierText? with
  | some "UInt64", none => .ok .u64
  | some "Bool", none => .ok .bool
  | some "Field", some "bn254_fr" => .ok .field
  | some "UInt8", none => .ok .u8
  | some "UInt16", none => .ok .u16
  | some "UInt32", none => .ok .u32
  | some "UInt128", none => .ok .u128
  | some "UInt256", none => .ok .u256
  | some "Int8", none => .ok .i8
  | some "Int16", none => .ok .i16
  | some "Int32", none => .ok .i32
  | some "Int64", none => .ok .i64
  | some "Int128", none => .ok .i128
  | some "Int256", none => .ok .i256
  | some "Unit", none => .ok .unit
  | some "Principal", none => .ok .principal
  -- Alpha Option subset: same-line Option + one single-token primitive atom only.
  -- Reject Field, Named, nested Option, Array, Map, Bytes, missing/extra payloads.
  | some "Option", some "Bool" => .ok (.option .bool)
  | some "Option", some "UInt64" => .ok (.option .u64)
  | some "Option", some "UInt8" => .ok (.option .u8)
  | some "Option", some "UInt16" => .ok (.option .u16)
  | some "Option", some "UInt32" => .ok (.option .u32)
  | some "Option", some "UInt128" => .ok (.option .u128)
  | some "Option", some "UInt256" => .ok (.option .u256)
  | some "Option", some "Int8" => .ok (.option .i8)
  | some "Option", some "Int16" => .ok (.option .i16)
  | some "Option", some "Int32" => .ok (.option .i32)
  | some "Option", some "Int64" => .ok (.option .i64)
  | some "Option", some "Int128" => .ok (.option .i128)
  | some "Option", some "Int256" => .ok (.option .i256)
  | some "Option", some "Unit" => .ok (.option .unit)
  | some "Option", some "Principal" => .ok (.option .principal)
  | _, _ => .error "unsupported portable type"

/-- Collect type atoms: identifiers and numeral-literal nodes only. -/
private partial def collectTypeAtomSyntax (stx : Syntax) : Array Syntax :=
  if stx.isIdent then #[stx]
  else if stx.isOfKind numLitKind then #[stx]
  else stx.getArgs.flatMap collectTypeAtomSyntax

/-- Decode a Bytes length from a numLitKind node using only lexical spelling.
Never calls getNat/isNatLit before the length is proven in 0..4096. -/
private def decodeBytesLengthAtom (stx : Syntax) : Except String UInt32 := do
  unless stx.isOfKind numLitKind do
    throw "unsupported portable type"
  let spelling ← match stx.isLit? numLitKind with
    | some value => pure value
    | none => throw "unsupported portable type"
  if spelling.isEmpty || spelling.length > 4 then
    throw "unsupported portable type"
  if spelling.length > 1 && spelling.front == '0' then
    throw "unsupported portable type"
  let mut value : Nat := 0
  for c in spelling.toList do
    unless c.isDigit do
      throw "unsupported portable type"
    value := value * 10 + (c.toNat - '0'.toNat)
    if value > 4096 then
      throw "unsupported portable type"
  pure (UInt32.ofNat value)

private def decodeArrayValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  let (elementSyntax, lengthSyntax) ← match atoms with
    | #[element, length] => pure (element, length)
    | _ => throw "unsupported portable type"
  let element ← match rawIdentifierText? elementSyntax with
    | some _ => decodeTypeIdentifiers elementSyntax none
    | none => throw "unsupported portable type"
  let length := (← decodeBytesLengthAtom lengthSyntax).toNat
  let length : ProofForgeV2.Source.ArrayLength ←
    if h : length < 4097 then pure ⟨length, h⟩
    else throw "unsupported portable type"
  pure (.array element length)

private def decodeArrayFieldValueTypeFromAtoms :
    Array Syntax → Except String ProofForgeV2.Source.ValueType
  | #[fieldId, lengthSyntax] => do
      unless rawIdentifierText? fieldId == some "bn254_fr" do
        throw "unsupported portable type"
      let length := (← decodeBytesLengthAtom lengthSyntax).toNat
      if h : length < 4097 then pure (.array .field ⟨length, h⟩)
      else throw "unsupported portable type"
  | _ => throw "unsupported portable type"

private def decodeArrayOptionOptionFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayFieldValueTypeFromAtoms atoms with
  | .array .field length => pure (.array (.option (.option .field)) length)
  | _ => throw "unsupported portable type"

private def decodeArrayBytesValueTypeFromAtoms :
    Array Syntax → Except String ProofForgeV2.Source.ValueType
  | #[innerSyntax, outerSyntax] => do
      let inner ← decodeBytesLengthAtom innerSyntax
      let outer := (← decodeBytesLengthAtom outerSyntax).toNat
      if h : outer < 4097 then pure (.array (.bytes inner) ⟨outer, h⟩)
      else throw "unsupported portable type"
  | _ => throw "unsupported portable type"

private def decodeArrayArrayFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match atoms with
  | #[fieldId, innerSyntax, outerSyntax] => do
      match ← decodeArrayFieldValueTypeFromAtoms #[fieldId, innerSyntax] with
      | .array .field innerLength =>
          let outer := (← decodeBytesLengthAtom outerSyntax).toNat
          if h : outer < 4097 then
            pure (.array (.array .field innerLength) ⟨outer, h⟩)
          else throw "unsupported portable type"
      | _ => throw "unsupported portable type"
  | _ => throw "unsupported portable type"

private def decodeArrayArrayValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match atoms with
  | #[elementSyntax, innerSyntax, outerSyntax] => do
      let element ← match rawIdentifierText? elementSyntax with
        | some _ => decodeTypeIdentifiers elementSyntax none
        | none => throw "unsupported portable type"
      let inner := (← decodeBytesLengthAtom innerSyntax).toNat
      let outer := (← decodeBytesLengthAtom outerSyntax).toNat
      if hInner : inner < 4097 then
        if hOuter : outer < 4097 then
          pure (.array (.array element ⟨inner, hInner⟩) ⟨outer, hOuter⟩)
        else throw "unsupported portable type"
      else throw "unsupported portable type"
  | _ => throw "unsupported portable type"

private def decodeArrayOptionValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayValueTypeFromAtoms atoms with
  | .array element length => pure (.array (.option element) length)
  | _ => throw "unsupported portable type"

private def decodeArrayOptionOptionValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayValueTypeFromAtoms atoms with
  | .array element length => pure (.array (.option (.option element)) length)
  | _ => throw "unsupported portable type"

private def decodeArrayOptionBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayBytesValueTypeFromAtoms atoms with
  | .array element length => pure (.array (.option element) length)
  | _ => throw "unsupported portable type"

private def decodeArrayOptionOptionBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayOptionBytesValueTypeFromAtoms atoms with
  | .array (.option (.bytes inner)) outer =>
      pure (.array (.option (.option (.bytes inner))) outer)
  | _ => throw "unsupported portable type"

private def decodeOptionFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType :=
  match atoms with
  | #[fieldId] =>
      match rawIdentifierText? fieldId with
      | some "bn254_fr" => .ok (.option .field)
      | _ => .error "unsupported portable type"
  | _ => .error "unsupported portable type"

private def decodeNestedOptionFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType :=
  match atoms with
  | #[fieldId] =>
      match rawIdentifierText? fieldId with
      | some "bn254_fr" => .ok (.option (.option .field))
      | _ => .error "unsupported portable type"
  | _ => .error "unsupported portable type"

private def decodeTripleOptionFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeNestedOptionFieldValueTypeFromAtoms atoms))

private def decodeNestedOptionValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  let elementSyntax ← match atoms with
    | #[element] => pure element
    | _ => throw "unsupported portable type"
  let element ← match rawIdentifierText? elementSyntax with
    | some _ => decodeTypeIdentifiers elementSyntax none
    | none => throw "unsupported portable type"
  pure (.option (.option element))

private def decodeTripleOptionValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeNestedOptionValueTypeFromAtoms atoms))

private def decodeOptionBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  let lengthSyntax ← match atoms with
    | #[length] => pure length
    | _ => throw "unsupported portable type"
  let length ← decodeBytesLengthAtom lengthSyntax
  pure (.option (.bytes length))

private def decodeNestedOptionBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeOptionBytesValueTypeFromAtoms atoms))

private def decodeTripleOptionBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeNestedOptionBytesValueTypeFromAtoms atoms))

private def decodeNestedOptionArrayValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayValueTypeFromAtoms atoms with
  | .array element length => pure (.option (.option (.array element length)))
  | _ => throw "unsupported portable type"

private def decodeOptionArrayValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  let arrayType ← decodeArrayValueTypeFromAtoms atoms
  pure (.option arrayType)

private def decodeOptionArrayFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayFieldValueTypeFromAtoms atoms with
  | .array .field length => pure (.option (.array .field length))
  | _ => throw "unsupported portable type"

private def decodeNestedOptionArrayFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeOptionArrayFieldValueTypeFromAtoms atoms))

private def decodeOptionArrayOptionValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeArrayOptionValueTypeFromAtoms atoms))

private def decodeOptionArrayBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeArrayBytesValueTypeFromAtoms atoms))

private def decodeOptionOptionArrayBytesValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeOptionArrayBytesValueTypeFromAtoms atoms))

private def decodeOptionArrayArrayFieldValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  match ← decodeArrayArrayFieldValueTypeFromAtoms atoms with
  | .array (.array .field innerLength) outerLength =>
      pure (.option (.array (.array .field innerLength) outerLength))
  | _ => throw "unsupported portable type"

private def decodeOptionArrayArrayValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType := do
  pure (.option (← decodeArrayArrayValueTypeFromAtoms atoms))

/-- Decode one or two type atoms into a ValueType (shared by pfType and fields). -/
private def decodeValueTypeFromAtoms (atoms : Array Syntax) :
    Except String ProofForgeV2.Source.ValueType :=
  match atoms with
  | #[first] =>
      match rawIdentifierText? first with
      | some _ => decodeTypeIdentifiers first none
      | none => .error "unsupported portable type"
  | #[first, second] =>
      match rawIdentifierText? first with
      | some "Bytes" => do
          let length ← decodeBytesLengthAtom second
          pure (.bytes length)
      | some _ =>
          match rawIdentifierText? second with
          | some _ => decodeTypeIdentifiers first (some second)
          | none => .error "unsupported portable type"
      | none => .error "unsupported portable type"
  | _ => .error "unsupported portable type"

private def decodeTypeUnchecked (stx : Syntax) : Except String ProofForgeV2.Source.ValueType :=
  if stx.isOfKind ``arrayFieldType then
    decodeArrayFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayBytesType then
    decodeArrayBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayOptionOptionFieldType then
    decodeArrayOptionOptionFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayOptionOptionBytesType then
    decodeArrayOptionOptionBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayOptionOptionType then
    decodeArrayOptionOptionValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayOptionBytesType then
    decodeArrayOptionBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayOptionType then
    decodeArrayOptionValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayArrayFieldType then
    decodeArrayArrayFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayArrayType then decodeArrayArrayValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionArrayOptionType then
    decodeOptionArrayOptionValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionArrayBytesType then
    decodeOptionArrayBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionArrayArrayFieldType then
    decodeOptionArrayArrayFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionArrayArrayType then
    decodeOptionArrayArrayValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionArrayType then
    decodeOptionArrayValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionArrayFieldType then
    decodeOptionArrayFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionBytesType then
    decodeOptionBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionFieldType then
    decodeNestedOptionFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionBytesType then
    decodeNestedOptionBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionArrayFieldType then
    decodeNestedOptionArrayFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionArrayBytesType then
    decodeOptionOptionArrayBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionArrayType then
    decodeNestedOptionArrayValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionOptionFieldType then
    decodeTripleOptionFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionOptionBytesType then
    decodeTripleOptionBytesValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionOptionType then
    decodeTripleOptionValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionOptionType then
    decodeNestedOptionValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``optionFieldType then
    decodeOptionFieldValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if stx.isOfKind ``arrayType then
    decodeArrayValueTypeFromAtoms (collectTypeAtomSyntax stx)
  else if !stx.isOfKind ``portableType then
    .error "unsupported portable type"
  else
    decodeValueTypeFromAtoms (collectTypeAtomSyntax stx)

def decodeType (stx : Syntax) : Except String ProofForgeV2.Source.ValueType := do
  preflightForDecoder stx
  decodeTypeUnchecked stx

private def decodeParamUnchecked : Syntax → Except String ProofForgeV2.Source.Param
  | `(pfParam| $name:ident : $type:pfType) => do
      return { name := ← decodeIdentifier name, type := ← decodeTypeUnchecked type }
  | `(pfParam| public $name:ident : $type:pfType) => do
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .verifierVisible
      }
  | `(pfParam| private $name:ident : $type:pfType) => do
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .proverWitness
      }
  | `(pfParam| commitment $name:ident : $type:pfType) => do
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .commitmentOnly
      }
  | _ => .error "unsupported portable parameter"

def decodeParam (stx : Syntax) : Except String ProofForgeV2.Source.Param := do
  preflightForDecoder stx
  decodeParamUnchecked stx

mutual

private partial def decodeLegacyPlaceExprUnchecked : Syntax → Except String ProofForgeV2.Source.Expr
  | `(pfPlace| $name:ident) => do
      return .variable (← decodeIdentifier name)
  | `(pfPlace| $base:pfPlace [$index:pfExpr]) => do
      match base with
      | `(pfPlace| $name:ident) => do
          unless name.getId.components.length == 1 do
            throw "index access base must be unqualified"
          return .indexAccess (← decodeIdentifier name) (← decodeExprUnchecked index)
      | _ => throw "unsupported portable expression"
  | _ => throw "unsupported portable expression"

private partial def decodeExprUnchecked : Syntax → Except String ProofForgeV2.Source.Expr
  | `(boolTrueExpr| true) => .ok (.boolLiteral true)
  | `(boolFalseExpr| false) => .ok (.boolLiteral false)
  | `(pfExpr| $value:num) =>
      let number := value.getNat
      if number > 18446744073709551615 then
        .error s!"UInt64 literal is out of range: {number}"
      else
        .ok <| .literal (UInt64.ofNat number)
  | `(pfExpr| $value:str) => .ok <| .stringLiteral value.getString
  | `(pfExpr| $callee:ident ($args:pfExpr,*)) => do
      if callee.getId.components.length == 1 then
        let callee ← decodeIdentifier callee
        return .localFnCall callee (← args.getElems.mapM decodeExprUnchecked)
      let path ← decodeConstructorPath callee
      return .constructorExpr path (← args.getElems.mapM decodeExprUnchecked)
  | `(pfExpr| $place:pfPlace) => decodeLegacyPlaceExprUnchecked place
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      return .checkedAdd (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr - $rhs:pfExpr) => do
      return .checkedSub (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr * $rhs:pfExpr) => do
      return .checkedMul (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr / $rhs:pfExpr) => do
      return .checkedDiv (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr % $rhs:pfExpr) => do
      return .checkedMod (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr << $rhs:pfExpr) => do
      return .shiftLeft (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr >> $rhs:pfExpr) => do
      return .shiftRight (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr == $rhs:pfExpr) => do
      return .equal (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr != $rhs:pfExpr) => do
      return .notEqual (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr < $rhs:pfExpr) => do
      return .lessThan (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr <= $rhs:pfExpr) => do
      return .lessEqual (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr > $rhs:pfExpr) => do
      return .greaterThan (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr >= $rhs:pfExpr) => do
      return .greaterEqual (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr & $rhs:pfExpr) => do
      return .bitwiseAnd (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr ^ $rhs:pfExpr) => do
      return .bitwiseXor (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr && $rhs:pfExpr) => do
      return .logicalAnd (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| $lhs:pfExpr || $rhs:pfExpr) => do
      return .logicalOr (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | `(pfExpr| - $operand:pfExpr) => do
      return .checkedNeg (← decodeExprUnchecked operand)
  | `(pfExpr| ~ $operand:pfExpr) => do
      return .bitwiseNot (← decodeExprUnchecked operand)
  | `(pfExpr| ! $operand:pfExpr) => do
      return .logicalNot (← decodeExprUnchecked operand)
  | `(pfExpr| ($inner:pfExpr)) => decodeExprUnchecked inner
  | stx =>
      if stx.getKind == `ProofForgeV2.Language.bitOrExpr then
        match stx.getArgs with
        | #[lhs, .atom _ "|", rhs] =>
            return .bitwiseOr (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
        | _ => .error "unsupported portable expression"
      else
        .error "unsupported portable expression"

end

def decodeExpr (stx : Syntax) : Except String ProofForgeV2.Source.Expr := do
  preflightForDecoder stx
  decodeExprUnchecked stx

private def decodeRevertName (stx : Syntax) : Except String String := do
  unless stx.getId.components.length == 1 do
    throw "revert error name must be unqualified"
  decodeIdentifier stx

private partial def decodeStatementUnchecked : Syntax → Except String ProofForgeV2.Source.Statement
  | `(letStmtAnnotated| let $name:ident : $type:pfType := $value:pfExpr) => do
      return .letDecl (← decodeIdentifier name) (some (← decodeTypeUnchecked type))
        (← decodeExprUnchecked value)
  | `(letStmtOmitted| let $name:ident := $value:pfExpr) => do
      return .letDecl (← decodeIdentifier name) none (← decodeExprUnchecked value)
  | `(pfStmt| $target:pfPlace := $value:pfExpr) => do
      match target with
      | `(pfPlace| $name:ident) =>
          return .assign (← decodeIdentifier name) (← decodeExprUnchecked value)
      | _ => throw "unsupported portable statement"
  | `(returnValueStmt| return $value:pfExpr) => do
      return .returnValue (← decodeExprUnchecked value)
  | `(pfStmt| return) => .ok .returnUnit
  | `(pfStmt| call $callee:str) => .ok <| .synchronousCall callee.getString
  | `(pfStmt| assert $condition:pfExpr else $errorName:ident) => do
      unless errorName.getId.components.length == 1 do
        throw "assert error name must be unqualified"
      let errorName ← decodeIdentifier errorName
      return .assertErrorStmt (← decodeExprUnchecked condition) errorName
  | `(pfStmt| assert $condition:pfExpr) => do
      return .assertStmt (← decodeExprUnchecked condition)
  | `(pfStmt| revert $errorName:ident ($args:pfExpr,*)) => do
      return .revertStmt (← decodeRevertName errorName)
        (← args.getElems.mapM decodeExprUnchecked)
  | `(pfStmt| revert $errorName:ident) => do
      return .revertStmt (← decodeRevertName errorName) #[]
  | `(pfStmt| emit $eventName:ident ($args:pfExpr,*)) => do
      unless eventName.getId.components.length == 1 do
        throw "emit event name must be unqualified"
      return .emitStmt (← decodeIdentifier eventName) (← args.getElems.mapM decodeExprUnchecked)
  | stx => do
      match stx.getKind, stx.getArgs with
      | `ProofForgeV2.Language.ifStmt, #[.atom _ "if", condition, .atom _ "then",
          .node _ `null thenSyntax, .node _ `null elseSyntax] => do
          unless !thenSyntax.isEmpty do throw "unsupported portable statement"
          let condition ← decodeExprUnchecked condition
          let thenBody ← thenSyntax.mapM decodeStatementUnchecked
          let elseBody ← match elseSyntax with
            | #[] => pure none
            | #[.atom _ "else", .node _ `null body] =>
                if body.isEmpty then throw "unsupported portable statement" else some <$> body.mapM decodeStatementUnchecked
            | _ => throw "unsupported portable statement"
          return .ifStmt condition thenBody elseBody
      | `ProofForgeV2.Language.forStmt, #[.atom _ "for", iterator, .atom _ "in", start,
          .atom _ "..<", stopExclusive, .atom _ "bounded", maxIterations, .atom _ "do",
          .node _ `null body] => do
          unless !body.isEmpty do throw "unsupported portable statement"
          let maxIterations ← match decodeBytesLengthAtom maxIterations with
            | .ok value => pure value.toNat
            | .error _ => throw "unsupported portable statement"
          let maxIterations : ProofForgeV2.Source.IterationBound ←
            if h : maxIterations < 4097 then pure ⟨maxIterations, h⟩
            else throw "unsupported portable statement"
          return .forStmt (← decodeIdentifier iterator) (← decodeExprUnchecked start)
            (← decodeExprUnchecked stopExclusive) maxIterations (← body.mapM decodeStatementUnchecked)
      | _, _ => throw "unsupported portable statement"

def decodeStatement (stx : Syntax) : Except String ProofForgeV2.Source.Statement := do
  preflightForDecoder stx
  decodeStatementUnchecked stx

private def decodeParams (params : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Param) :=
  params.mapM decodeParamUnchecked

private def decodeStatementsUnchecked (statements : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Statement) :=
  statements.mapM decodeStatementUnchecked

private def decodeStructFieldUnchecked (stx : Syntax) :
    Except String ProofForgeV2.Source.FieldDecl := do
  if stx.isOfKind ``arrayArrayFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayArrayFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayArrayAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayArrayValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayOptionOptionFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayOptionOptionFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayOptionOptionBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayOptionOptionBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayOptionOptionAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayOptionOptionValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayOptionBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayOptionBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayOptionAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayOptionValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionArrayAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionArrayValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionArrayFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionArrayFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionArrayOptionAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionArrayOptionValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionArrayBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionArrayBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionArrayArrayFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionArrayArrayFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionArrayArrayAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionArrayArrayValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeNestedOptionFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeNestedOptionBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionArrayFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeNestedOptionArrayFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionArrayBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionOptionArrayBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionArrayAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeNestedOptionArrayValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionOptionFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeTripleOptionFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionOptionBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeTripleOptionBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionOptionAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeTripleOptionValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionOptionAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeNestedOptionValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionBytesAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionBytesValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``optionFieldAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeOptionFieldValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  if stx.isOfKind ``arrayAggregateField then
    let atoms := collectTypeAtomSyntax stx
    let nameStx ← match atoms[0]? with
      | some name => pure name
      | none => throw "unsupported portable struct field"
    return {
      name := ← decodeIdentifier nameStx
      type := ← decodeArrayValueTypeFromAtoms (atoms.extract 1 atoms.size)
    }
  unless stx.isOfKind ``aggregateField do
    throw "unsupported portable struct field"
  -- Field name is the first atom; remaining atoms are the type (shared decoder).
  let atoms := collectTypeAtomSyntax stx
  let nameStx ← match atoms[0]? with
    | some name => pure name
    | none => throw "unsupported portable struct field"
  let typeAtoms := atoms.extract 1 atoms.size
  return {
    name := ← decodeIdentifier nameStx
    type := ← decodeValueTypeFromAtoms typeAtoms
  }

private def decodeEnumVariantUnchecked : Syntax → Except String ProofForgeV2.Source.EnumVariant
  | `(pfAggregateMember| | $name:ident
      ) => do
      return { name := ← decodeIdentifier name, payloadTypes := #[] }
  | `(pfAggregateMember| | $name:ident ($payloadTypes:pfType,*)
      ) => do
      let name ← decodeIdentifier name
      let payloadTypes := payloadTypes.getElems
      if payloadTypes.isEmpty then
        throw s!"enum variant '{name}' payload must contain at least one type"
      return { name, payloadTypes := ← payloadTypes.mapM decodeTypeUnchecked }
  | _ => .error "unsupported portable enum variant"

private def decodeItemUnchecked : Syntax → Except String ProofForgeV2.Source.Item
  | `(pfItem| state $name:ident : $type:pfType) => do
      return .stateDecl { name := ← decodeIdentifier name, type := ← decodeTypeUnchecked type }
  | `(pfItem| state public $name:ident : $type:pfType) => do
      return .stateDecl {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .verifierVisible
      }
  | `(pfItem| state private $name:ident : $type:pfType) => do
      return .stateDecl {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .proverWitness
      }
  | `(pfItem| state commitment $name:ident : $type:pfType) => do
      return .stateDecl {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .commitmentOnly
      }
  | `(constDecl| const $name:ident : $type:pfType := $value:pfExpr) => do
      let name ← decodeIdentifier name
      let type ← decodeTypeUnchecked type
      let value ← decodeExprUnchecked value
      return .constDecl { name, type, value }
  | `(unsupportedConstLikeDecl| $_kind:ident $_name:ident : $_type:pfType :=
        $_value:pfExpr) =>
      .error "unsupported portable program item"
  | `(invariantDecl| invariant $name:ident : $predicate:pfExpr) => do
      let name ← decodeIdentifier name
      let predicate ← decodeExprUnchecked predicate
      return .invariantDecl { name, predicate }
  | `(unsupportedInvariantLikeDecl| $_kind:ident $_name:ident : $_predicate:pfExpr
      ) =>
      .error "unsupported portable program item"
  | `(extensionReq| requires extension $id:ident version $version:str
        digest $digest:str) => do
      let id ← decodeExtensionId id
      let version ← decodeExtensionVersion version
      let digest ← decodeExtensionDigest digest
      return .extensionReq { id, version, digest }
  | `(unsupportedExtensionLikeReq| $_requires:ident $_extension:ident $_id:ident $_versionKeyword:ident $_version:str
        $_digestKeyword:ident $_digest:str) =>
      .error "unsupported portable program item"
  | `(proofDecl| proof $invariant:ident using $theoremName:ident) => do
      let invariant ← decodeIdentifier invariant
      let theoremComponents ← decodeProofTheorem theoremName
      return .proofDecl { invariant, «theorem» := theoremComponents }
  | `(unsupportedProofIntroducer| $_proof:ident $_invariant:ident using $_theoremName:ident) =>
      .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) : $result:pfType do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          let name ← decodeIdentifier name
          let params ← decodeParams params.getElems
          let result ← decodeTypeUnchecked result
          let body ← decodeStatementsUnchecked body
          return .fnDecl { name, params, result, body }
      | _ => .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          let name ← decodeIdentifier name
          let params ← decodeParams params.getElems
          let body ← decodeStatementsUnchecked body
          return .fnDecl { name, params, result := .unit, body }
      | _ => .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident where $members:pfAggregateMember*) =>
      match rawIdentifierText? kind with
      | some "struct" => do
          return .structDecl {
            name := ← decodeIdentifier name
            fields := ← members.mapM decodeStructFieldUnchecked
          }
      | some "enum" => do
          return .enumDecl {
            name := ← decodeIdentifier name
            variants := ← members.mapM decodeEnumVariantUnchecked
          }
      | _ => .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*)) =>
      match rawIdentifierText? kind with
      | some "event" => do
          return .eventDecl {
            name := ← decodeIdentifier name
            params := ← decodeParams params
          }
      | some "error" => do
          return .errorDecl {
            name := ← decodeIdentifier name
            params := ← decodeParams params
          }
      | _ => .error "unsupported portable program item"
  | `(bareErrorDecl| error $name:ident
      ) =>
      return .errorDecl { name := ← decodeIdentifier name, params := #[] }
  | `(unsupportedBareItemDecl| $_kind:ident $_name:ident
      ) =>
      .error "unsupported portable program item"
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      return .initializer {
        params := ← decodeParams params
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := ← decodeIdentifier name
        params := ← decodeParams params
        result := ← decodeTypeUnchecked type
        mode := .mutate
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| entry $name:ident ($params:pfParam,*) do $statements:pfStmt*) => do
      return .entry {
        name := ← decodeIdentifier name
        params := ← decodeParams params
        result := .unit
        mode := .mutate
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := ← decodeIdentifier name
        params := ← decodeParams params
        result := ← decodeTypeUnchecked type
        mode := .view
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| view $name:ident ($params:pfParam,*) do $statements:pfStmt*) => do
      return .entry {
        name := ← decodeIdentifier name
        params := ← decodeParams params
        result := .unit
        mode := .view
        body := ← decodeStatementsUnchecked statements
      }
  | _ => .error "unsupported portable program item"

def decodeItem (stx : Syntax) : Except String ProofForgeV2.Source.Item := do
  preflightForDecoder stx
  decodeItemUnchecked stx

private def hasDuplicate (values : Array String) : Bool := Id.run do
  let mut seen := Std.HashSet.emptyWithCapacity values.size
  for value in values do
    let (alreadyPresent, updated) := seen.containsThenInsert value
    if alreadyPresent then
      return true
    seen := updated
  return false

/-- Validate declaration-scope invariants shared by the CLI Loader and Lean
command elaborator. Error order is part of the alpha frontend contract. -/
def validateDecodedProgram (sourceProgram : ProofForgeV2.Source.Program) : CompileResult Unit := do
  if sourceProgram.entries.isEmpty then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' must declare at least one entry or view"
  if hasDuplicate (sourceProgram.state.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate state declarations"
  if hasDuplicate (sourceProgram.entries.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate entry declarations"
  if hasDuplicate (sourceProgram.events.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate event declarations"
  if hasDuplicate (sourceProgram.errors.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate error declarations"
  if hasDuplicate (sourceProgram.structs.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate struct declarations"
  if hasDuplicate (sourceProgram.enums.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate enum declarations"
  if hasDuplicate (sourceProgram.consts.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate const declarations"
  if hasDuplicate (sourceProgram.functions.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate fn declarations"
  -- Entry/view (entries[]) and fn share one callable name namespace. Same-kind
  -- duplicates keep their dedicated diagnostics above; this check only fires for
  -- cross-kind collisions (linear HashSet via hasDuplicate, not nested scans).
  if hasDuplicate (
      sourceProgram.entries.map (·.name) ++ sourceProgram.functions.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate callable declarations"
  if hasDuplicate (sourceProgram.invariants.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate invariant declarations"
  if hasDuplicate (sourceProgram.extensionRequirements.map (·.id)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate extension requirements"
  if hasDuplicate (sourceProgram.proofReferences.map (·.invariant)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate proof references"
  for proofReference in sourceProgram.proofReferences do
    unless sourceProgram.invariants.any (fun invariant => invariant.name == proofReference.invariant) do
      throw <| .invalidProgram
        s!"proof reference names unknown invariant '{proofReference.invariant}'"
  match sourceProgram.initializer with
  | some initializer =>
      if hasDuplicate (initializer.params.map (·.name)) then
        throw <| .invalidProgram "initializer contains duplicate parameters"
  | none => pure ()
  for sourceStruct in sourceProgram.structs do
    if sourceStruct.fields.isEmpty then
      throw <| .invalidProgram s!"struct '{sourceStruct.name}' must declare at least one field"
    if hasDuplicate (sourceStruct.fields.map (·.name)) then
      throw <| .invalidProgram s!"struct '{sourceStruct.name}' contains duplicate fields"
  for sourceEnum in sourceProgram.enums do
    if sourceEnum.variants.isEmpty then
      throw <| .invalidProgram s!"enum '{sourceEnum.name}' must declare at least one variant"
    if hasDuplicate (sourceEnum.variants.map (·.name)) then
      throw <| .invalidProgram s!"enum '{sourceEnum.name}' contains duplicate variants"
  for sourceEvent in sourceProgram.events do
    if hasDuplicate (sourceEvent.params.map (·.name)) then
      throw <| .invalidProgram s!"event '{sourceEvent.name}' contains duplicate parameters"
  for sourceError in sourceProgram.errors do
    if hasDuplicate (sourceError.params.map (·.name)) then
      throw <| .invalidProgram s!"error '{sourceError.name}' contains duplicate parameters"
  for sourceEntry in sourceProgram.entries do
    if hasDuplicate (sourceEntry.params.map (·.name)) then
      throw <| .invalidProgram s!"entry '{sourceEntry.name}' contains duplicate parameters"
  for sourceFn in sourceProgram.functions do
    if hasDuplicate (sourceFn.params.map (·.name)) then
      throw <| .invalidProgram s!"fn '{sourceFn.name}' contains duplicate parameters"
    if sourceFn.body.isEmpty then
      throw <| .invalidProgram s!"fn '{sourceFn.name}' must declare at least one statement"

private def decodeProgramCommandUnchecked (currentNamespace : Name) : Syntax →
    Except String ProofForgeV2.Source.Program
  | `(program $name:ident where $items:pfItem*) => do
      let shortName ← decodeIdentifier name
      let qualifiedName := (currentNamespace ++ name.getId).toString
      let decodedItems ← items.mapM decodeItemUnchecked
      let initializerCount : Nat := decodedItems.foldl (fun count item =>
        match item with | .initializer .. => count + 1 | _ => count) 0
      if initializerCount > 1 then
        throw "program may declare at most one initializer"
      return ProofForgeV2.Source.Program.buildQualified
        qualifiedName shortName decodedItems
  | _ => .error "expected a program declaration"

/-- Bound the fully qualified identity before recursive `Name.toString`. -/
def preflightProgramIdentity (currentNamespace programName : Name) :
    CompileResult Unit := do
  let namespaceParts ←
    match boundedNamePartCount maxSyntaxNesting currentNamespace with
    | some count => .ok count
    | none => .error (.resourceBound
        s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")
  match boundedNamePartCount (maxSyntaxNesting - namespaceParts) programName with
  | some _ => .ok ()
  | none => .error (.resourceBound
      s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")

inductive ProgramNamespace where
  | bounded (name : Name)
  | overLimit
  deriving Inhabited

namespace ProgramV1Decoder

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def isReservedPortableIdentifierV1 (raw : String) : Bool :=
  #["program", "where", "state", "struct", "enum", "const", "event", "error",
    "init", "entry", "view", "fn", "invariant", "requires", "extension",
    "version", "digest", "proof", "using", "do", "let", "if", "then", "else",
    "match", "with", "for", "in", "bounded", "assert", "revert", "emit",
    "return", "call", "schedule", "public", "private", "commitment", "true",
    "false"].contains raw

private def decodeNameV1 (stx : Syntax) : Except String SourceNameComponentV1 := do
  unless stx.getId.components.length == 1 do
    throw "source name component must contain exactly one Lean Name component"
  let component ← sourceNameComponentV1FromLeanName stx.getId
  if isReservedPortableIdentifierV1 component.raw then
    throw s!"reserved portable identifier '{component.raw}'"
  pure component

/-- Collect every raw component of a (possibly dotted) source identifier in
root-to-leaf order, validating each component and rejecting reserved portable
identifiers at the first offending component. -/
private def decodeIdentComponentsV1 (stx : Syntax) :
    Except String (Array SourceNameComponentV1) := do
  let rec collectPureStrChain (name : Name) (remaining : Nat) :
      Except String (Array String) :=
    match name with
    | .anonymous => pure #[]
    | .str pre value => do
        if remaining == 0 then
          throw "source qualified name must contain 1..256 components"
        let preRaws ← collectPureStrChain pre (remaining - 1)
        pure (preRaws.push value)
    | .num _ _ => throw "source qualified name requires a pure .str Lean name chain"
  let raws ← collectPureStrChain stx.getId 256
  let mut components : Array SourceNameComponentV1 := #[]
  for raw in raws do
    let component ← parseSourceNameComponentV1 raw
    if isReservedPortableIdentifierV1 component.raw then
      throw s!"reserved portable identifier '{component.raw}'"
    components := components.push component
  if components.size == 0 then
    throw "source qualified name must contain 1..256 components"
  pure components

private def decodeIdentPlaceV1 (stx : Syntax) : Except String PlaceV1 := do
  let components ← decodeIdentComponentsV1 stx
  match components[0]? with
  | none => throw "source qualified name must contain 1..256 components"
  | some root =>
      let mut place : PlaceV1 := .name root
      for component in components.extract 1 components.size do
        place := .field place component
      pure place

private partial def decodePlaceV1With
    (decodeExpr : Syntax → Except String ExprV1) : Syntax → Except String PlaceV1
  | `(pfPlace| $name:ident) => decodeIdentPlaceV1 name
  | `(pfPlace| $base:pfPlace . $field:ident) => do
      let placeBase ← decodePlaceV1With decodeExpr base
      let components ← decodeIdentComponentsV1 field
      pure (components.foldl (fun place component => .field place component) placeBase)
  | `(pfPlace| $base:pfPlace [$index:pfExpr]) => do
      pure (.index (← decodePlaceV1With decodeExpr base) (← decodeExpr index))
  | _ => throw "unsupported portable place"

private def primitiveTypeV1 (raw : String) : Option TypeV1 :=
  match raw with
  | "Bool" => some .bool
  | "UInt8" => some (.uint 8)
  | "UInt16" => some (.uint 16)
  | "UInt32" => some (.uint 32)
  | "UInt64" => some (.uint 64)
  | "UInt128" => some (.uint 128)
  | "UInt256" => some (.uint 256)
  | "Int8" => some (.int 8)
  | "Int16" => some (.int 16)
  | "Int32" => some (.int 32)
  | "Int64" => some (.int 64)
  | "Int128" => some (.int 128)
  | "Int256" => some (.int 256)
  | "Unit" => some .unit
  | "Principal" => some .principal
  | _ => none

private def isTypeConstructorNameV1 (raw : String) : Bool :=
  (primitiveTypeV1 raw).isSome || #["Option", "Array", "Map", "Bytes", "Field"].contains raw

private def typeConstructorAtomTextV1? : Syntax → Option String
  | .atom _ value =>
      if #["Option", "Array", "Map", "Bytes", "Field"].contains value then
        some value
      else
        none
  | _ => none

private def typeTokenTextV1? (stx : Syntax) : Option String :=
  rawIdentifierText? stx <|> typeConstructorAtomTextV1? stx

/-- V1-only type token collector. Legacy decoding intentionally omits contextual
constructor atoms from `collectTypeAtomSyntax`; ProgramV1 needs them to preserve
prefix constructors parsed as `Syntax.atom` nodes. -/
private partial def collectTypeAtomSyntaxV1 (stx : Syntax) : Array Syntax :=
  if stx.isIdent || stx.isOfKind numLitKind || (typeConstructorAtomTextV1? stx).isSome then
    #[stx]
  else
    stx.getArgs.flatMap collectTypeAtomSyntaxV1

/-- Decode the prefix atom form of the recursive ProgramV1 type grammar. The
syntax parser has already bounded the tree; `fuel` additionally guarantees that
malformed constructor prefixes cannot recurse without consuming an atom. -/
private def decodeTypeV1At :
    (fuel : Nat) → (atoms : Array Syntax) → (index : Nat) →
      Except String (TypeV1 × Nat)
  | 0, _, _ => .error "unsupported portable type"
  | fuel + 1, atoms, index => do
      let atom ← match atoms[index]? with
        | some atom => pure atom
        | none => throw "unsupported portable type"
      let raw ← match typeTokenTextV1? atom with
        | some raw => pure raw
        | none => throw "unsupported portable type"
      match primitiveTypeV1 raw with
      | some type => pure (type, index + 1)
      | none =>
          match raw with
          | "Option" => do
              let (element, next) ← decodeTypeV1At fuel atoms (index + 1)
              pure (.option element, next)
          | "Array" => do
              let (element, next) ← decodeTypeV1At fuel atoms (index + 1)
              let lengthSyntax ← match atoms[next]? with
                | some length => pure length
                | none => throw "unsupported portable type"
              pure (.array element (← decodeBytesLengthAtom lengthSyntax), next + 1)
          | "Map" => do
              let (key, next) ← decodeTypeV1At fuel atoms (index + 1)
              let (value, finish) ← decodeTypeV1At fuel atoms next
              pure (.map key value, finish)
          | "Bytes" => do
              let lengthSyntax ← match atoms[index + 1]? with
                | some length => pure length
                | none => throw "unsupported portable type"
              pure (.bytes (← decodeBytesLengthAtom lengthSyntax), index + 2)
          | "Field" => do
              let fieldSyntax ← match atoms[index + 1]? with
                | some field => pure field
                | none => throw "unsupported portable type"
              unless rawIdentifierText? fieldSyntax == some "bn254_fr" do
                throw "unsupported portable type"
              pure (.field (← decodeNameV1 fieldSyntax), index + 2)
          | _ => do
              unless atom.getId.components.length == 1 do
                throw "unsupported portable type"
              let name ← decodeNameV1 atom
              if isTypeConstructorNameV1 name.raw then
                throw "unsupported portable type"
              pure (.named name, index + 1)

private def decodeTypeV1FromAtoms (atoms : Array Syntax) : Except String TypeV1 := do
  let (type, next) ← decodeTypeV1At (atoms.size + 1) atoms 0
  unless next == atoms.size do
    throw "unsupported portable type"
  pure type

private def decodeTypeV1Unchecked (stx : Syntax) : Except String TypeV1 :=
  decodeTypeV1FromAtoms (collectTypeAtomSyntaxV1 stx)

private def decodeParamV1Unchecked : Syntax → Except String ParamV1
  | `(pfParam| $name:ident : $type:pfType) => do
      pure {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | `(pfParam| public $name:ident : $type:pfType) => do
      pure {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | `(pfParam| private $name:ident : $type:pfType) => do
      pure {
        visibility := .private_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | `(pfParam| commitment $name:ident : $type:pfType) => do
      pure {
        visibility := .commitment
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | _ => throw "unsupported portable parameter"

private def qualifiedV1FromStrings (parts : Array String) : Except String SourceQualifiedNameV1 := do
  for part in parts do
    if isReservedPortableIdentifierV1 part then
      throw s!"reserved portable identifier '{part}'"
  parseSourceQualifiedNameV1 parts

private def decodeQualifiedIdV1 (stx : Syntax) : Except String SourceQualifiedNameV1 := do
  let qualified ← sourceQualifiedNameV1FromLeanName stx.getId
  validateSourceQualifiedIdV1 qualified
  pure qualified

private def decodePortableQualifiedIdV1
    (stx : Syntax) : Except String SourceQualifiedNameV1 := do
  let qualified ← decodeQualifiedIdV1 stx
  for component in NonEmptyArray.toArray qualified.components do
    if isReservedPortableIdentifierV1 component.raw then
      throw s!"reserved portable identifier '{component.raw}'"
  pure qualified

private partial def decodeExprV1Unchecked : Syntax → Except String ExprV1
  | `(boolTrueExpr| true) => pure (.literal (.bool true))
  | `(boolFalseExpr| false) => pure (.literal (.bool false))
  | `(pfExpr| $value:num) =>
      let number := value.getNat
      if number < 2 ^ 256 then pure (.literal (.integer number))
      else throw "integer literal exceeds UInt256"
  | `(pfExpr| $value:str) => pure (.literal (.string value.getString))
  | `(pfExpr| $callee:ident ($args:pfExpr,*)) => do
      if callee.getId.components.length == 1 then
        let callee ← decodeNameV1 callee
        pure (.localCall callee (← args.getElems.mapM decodeExprV1Unchecked))
      else
        let ctor ← decodePortableQualifiedIdV1 callee
        pure (.constructor ctor (← args.getElems.mapM decodeExprV1Unchecked))
  | `(pfExpr| $place:pfPlace) => do
      pure (.place (← decodePlaceV1With decodeExprV1Unchecked place))
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      pure (.binary .add (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr - $rhs:pfExpr) => do
      pure (.binary .sub (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr * $rhs:pfExpr) => do
      pure (.binary .mul (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr / $rhs:pfExpr) => do
      pure (.binary .div (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr % $rhs:pfExpr) => do
      pure (.binary .mod (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr << $rhs:pfExpr) => do
      pure (.binary .shl (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr >> $rhs:pfExpr) => do
      pure (.binary .shr (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr == $rhs:pfExpr) => do
      pure (.binary .eq (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr != $rhs:pfExpr) => do
      pure (.binary .ne (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr < $rhs:pfExpr) => do
      pure (.binary .lt (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr <= $rhs:pfExpr) => do
      pure (.binary .le (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr > $rhs:pfExpr) => do
      pure (.binary .gt (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr >= $rhs:pfExpr) => do
      pure (.binary .ge (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr & $rhs:pfExpr) => do
      pure (.binary .bitAnd (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr ^ $rhs:pfExpr) => do
      pure (.binary .bitXor (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr && $rhs:pfExpr) => do
      pure (.binary .logicalAnd (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr || $rhs:pfExpr) => do
      pure (.binary .logicalOr (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| - $operand:pfExpr) => do
      pure (.unary .neg (← decodeExprV1Unchecked operand))
  | `(pfExpr| ~ $operand:pfExpr) => do
      pure (.unary .bitNot (← decodeExprV1Unchecked operand))
  | `(pfExpr| ! $operand:pfExpr) => do
      pure (.unary .not (← decodeExprV1Unchecked operand))
  | `(pfExpr| ($inner:pfExpr)) => decodeExprV1Unchecked inner
  | stx =>
      if stx.getKind == `ProofForgeV2.Language.bitOrExpr then
        match stx.getArgs with
        | #[lhs, .atom _ "|", rhs] =>
            return (.binary .bitOr (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
        | _ => throw "unsupported portable expression"
      else
        throw "unsupported portable expression"

private def decodePlaceV1 (stx : Syntax) : Except String PlaceV1 :=
  decodePlaceV1With decodeExprV1Unchecked stx

private def decodeExternalCallV1Unchecked
    (calleeSyntax : Syntax) (argsSyntax : TSyntaxArray `pfExpr) :
    Except String ExternalCallExprV1 := do
  let callee ← decodePortableQualifiedIdV1 calleeSyntax
  pure {
    callee := callee
    args := ← argsSyntax.mapM decodeExprV1Unchecked
  }

private partial def decodePatternV1Unchecked : Syntax → Except String PatternV1
  | `(pfPattern| _) => pure .wildcard
  | `(boolTruePattern| true) => pure (.literal (.bool true))
  | `(boolFalsePattern| false) => pure (.literal (.bool false))
  | `(pfPattern| $value:num) =>
      let number := value.getNat
      if number < 2 ^ 256 then pure (.literal (.integer number))
      else throw "integer literal exceeds UInt256"
  | `(pfPattern| $value:str) => pure (.literal (.string value.getString))
  | `(pfPattern| $ctor:ident ($args:pfPattern,*)) => do
      let ctor ← decodePortableQualifiedIdV1 ctor
      pure (.constructor ctor (← args.getElems.mapM decodePatternV1Unchecked))
  | `(pfPattern| $name:ident) => do
      pure (.bind (← decodeNameV1 name))
  | _ => throw "unsupported portable pattern"

private partial def decodeStatementV1Unchecked : Syntax → Except String StmtV1
  | `(letStmtAnnotated| let $name:ident : $type:pfType := $value:pfExpr) => do
      pure (.let_ (← decodeNameV1 name) (some (← decodeTypeV1Unchecked type))
        (← decodeExprV1Unchecked value))
  | `(letStmtOmitted| let $name:ident := $value:pfExpr) => do
      pure (.let_ (← decodeNameV1 name) none (← decodeExprV1Unchecked value))
  | `(pfStmt| $target:pfPlace := $value:pfExpr) => do
      pure (.assign (← decodePlaceV1 target) (← decodeExprV1Unchecked value))
  | `(returnValueStmt| return $value:pfExpr) => do
      pure (.return_ (some (← decodeExprV1Unchecked value)))
  | `(pfStmt| return) => pure (.return_ none)
  | `(pfStmt| assert $condition:pfExpr else $errorName:ident) => do
      pure (.assert_ (← decodeExprV1Unchecked condition) (some (← decodeNameV1 errorName)))
  | `(pfStmt| assert $condition:pfExpr) => do
      pure (.assert_ (← decodeExprV1Unchecked condition) none)
  | `(pfStmt| revert $errorName:ident ($args:pfExpr,*)) => do
      pure (.revert (← decodeNameV1 errorName) (← args.getElems.mapM decodeExprV1Unchecked))
  | `(pfStmt| revert $errorName:ident) => do
      pure (.revert (← decodeNameV1 errorName) #[])
  | `(pfStmt| emit $eventName:ident ($args:pfExpr,*)) => do
      pure (.emit (← decodeNameV1 eventName) (← args.getElems.mapM decodeExprV1Unchecked))
  | `(pfStmt| call $callee:ident ($args:pfExpr,*)) => do
      pure (.call (← decodeExternalCallV1Unchecked callee args))
  | `(pfStmt| schedule $callee:ident ($args:pfExpr,*)) => do
      pure (.schedule (← decodeExternalCallV1Unchecked callee args))
  | `(pfStmt| call $_callee:str) =>
      throw "portable ProgramV1 calls require a qualified source identity"
  | stx => do
      match stx.getKind, stx.getArgs with
      | `ProofForgeV2.Language.ifStmt, #[.atom _ "if", condition, .atom _ "then",
          .node _ `null thenSyntax, .node _ `null elseSyntax] => do
          unless !thenSyntax.isEmpty do throw "unsupported portable statement"
          let condition ← decodeExprV1Unchecked condition
          let thenBlock := { statements := ← thenSyntax.mapM decodeStatementV1Unchecked }
          let elseBlock ←
            if elseSyntax.isEmpty then
              pure none
            else
              match elseSyntax with
              | #[.atom _ "else", .node _ `null body] => do
                  if body.isEmpty then throw "unsupported portable statement"
                  else pure (some { statements := ← body.mapM decodeStatementV1Unchecked })
              | _ => throw "unsupported portable statement"
          pure (.if_ condition thenBlock elseBlock)
      | `ProofForgeV2.Language.matchStmt, #[.atom _ "match", scrutinee, .atom _ "with",
          .node _ `null arms] => do
          unless !arms.isEmpty do throw "unsupported portable statement"
          let scrutinee ← decodeExprV1Unchecked scrutinee
          let decodedArms ← arms.mapM fun arm => do
            unless arm.getKind == `ProofForgeV2.Language.stmtMatchArm do
              throw "unsupported portable statement"
            match arm.getArgs with
            | #[.atom _ "|", pattern, .atom _ "=>", .atom _ "do", .node _ `null body] => do
                unless !body.isEmpty do throw "unsupported portable statement"
                let pattern ← decodePatternV1Unchecked pattern
                let statements ← body.mapM decodeStatementV1Unchecked
                pure ({ pattern, body := { statements } } : StmtMatchArmV1)
            | _ => throw "unsupported portable statement"
          pure (.match_ scrutinee decodedArms)
      | `ProofForgeV2.Language.forStmt, #[.atom _ "for", iterator, .atom _ "in", start,
          .atom _ "..<", stopExclusive, .atom _ "bounded", bound, .atom _ "do",
          .node _ `null body] => do
          unless !body.isEmpty do throw "unsupported portable statement"
          unless iterator.getId.components.length == 1 do
            throw "unsupported portable statement"
          let binder ← decodeNameV1 iterator
          let start ← decodeExprV1Unchecked start
          let stopExclusive ← decodeExprV1Unchecked stopExclusive
          let bound ← match decodeBytesLengthAtom bound with
            | .ok value => pure value
            | .error _ => throw "unsupported portable statement"
          pure (.for_ binder start stopExclusive bound
            { statements := ← body.mapM decodeStatementV1Unchecked })
      | _, _ => throw "unsupported portable statement"

private def decodeParamsV1 (params : Array Syntax) : Except String (Array ParamV1) :=
  params.mapM decodeParamV1Unchecked

private def decodeBlockV1 (statements : Array Syntax) : Except String BlockV1 := do
  pure { statements := ← statements.mapM decodeStatementV1Unchecked }

private def decodeStructFieldV1Unchecked (stx : Syntax) : Except String FieldDeclV1 := do
  let atoms := collectTypeAtomSyntaxV1 stx
  let nameSyntax ← match atoms[0]? with
    | some name => pure name
    | none => throw "unsupported portable struct field"
  let typeAtoms := atoms.extract 1 atoms.size
  unless !typeAtoms.isEmpty do
    throw "unsupported portable struct field"
  pure {
    name := ← decodeNameV1 nameSyntax
    type_ := ← decodeTypeV1FromAtoms typeAtoms
  }

private def decodeEnumVariantV1Unchecked : Syntax → Except String EnumVariantV1
  | `(pfAggregateMember| | $name:ident
      ) => do
      pure { name := ← decodeNameV1 name, payloadTypes := #[] }
  | `(pfAggregateMember| | $name:ident ($payloadTypes:pfType,*)
      ) => do
      let payloadTypes := payloadTypes.getElems
      if payloadTypes.isEmpty then
        throw s!"enum variant '{(← decodeNameV1 name).raw}' payload must contain at least one type"
      pure {
        name := ← decodeNameV1 name
        payloadTypes := ← payloadTypes.mapM decodeTypeV1Unchecked
      }
  | _ => .error "unsupported portable enum variant"

private def decodeItemV1Unchecked : Syntax → Except String ProgramItemV1
  | `(pfItem| state $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(pfItem| state public $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(pfItem| state private $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .private_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(pfItem| state commitment $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .commitment
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(constDecl| const $name:ident : $type:pfType := $value:pfExpr) => do
      pure (.const {
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
        value := ← decodeExprV1Unchecked value
      })
  | `(unsupportedConstLikeDecl| $_kind:ident $_name:ident : $_type:pfType :=
        $_value:pfExpr) =>
      throw "unsupported portable program item"
  | `(invariantDecl| invariant $name:ident : $predicate:pfExpr) => do
      pure (.invariant {
        name := ← decodeNameV1 name
        predicate := ← decodeExprV1Unchecked predicate
      })
  | `(unsupportedInvariantLikeDecl| $_kind:ident $_name:ident : $_predicate:pfExpr
      ) =>
      throw "unsupported portable program item"
  | `(extensionReq| requires extension $id:ident version $version:str
        digest $digest:str) => do
      let _ ← decodeExtensionId id
      pure (.extensionReq {
        id := ← decodeQualifiedIdV1 id
        version := ← decodeExtensionVersion version
        digest := ← decodeExtensionDigest digest
      })
  | `(unsupportedExtensionLikeReq| $_requires:ident $_extension:ident $_id:ident $_versionKeyword:ident $_version:str
        $_digestKeyword:ident $_digest:str) =>
      throw "unsupported portable program item"
  | `(proofDecl| proof $invariant:ident using $theoremName:ident) => do
      let theoremParts ← decodeProofTheorem theoremName
      pure (.proof {
        invariant := ← decodeNameV1 invariant
        theorem_ := ← qualifiedV1FromStrings theoremParts
      })
  | `(unsupportedProofIntroducer| $_proof:ident $_invariant:ident using $_theoremName:ident) =>
      throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) : $result:pfType do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          pure (.fn {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
            result := ← decodeTypeV1Unchecked result
            body := ← decodeBlockV1 body
          })
      | _ => throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          pure (.fn {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
            result := .unit
            body := ← decodeBlockV1 body
          })
      | _ => throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident where $members:pfAggregateMember*) =>
      match rawIdentifierText? kind with
      | some "struct" => do
          pure (.struct {
            name := ← decodeNameV1 name
            fields := ← members.mapM decodeStructFieldV1Unchecked
          })
      | some "enum" => do
          pure (.enum {
            name := ← decodeNameV1 name
            variants := ← members.mapM decodeEnumVariantV1Unchecked
          })
      | _ => throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*)) =>
      match rawIdentifierText? kind with
      | some "event" => do
          pure (.event {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
          })
      | some "error" => do
          pure (.error {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
          })
      | _ => throw "unsupported portable program item"
  | `(bareErrorDecl| error $name:ident
      ) => do
      pure (.error { name := ← decodeNameV1 name, params := #[] })
  | `(unsupportedBareItemDecl| $_kind:ident $_name:ident
      ) =>
      throw "unsupported portable program item"
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      pure (.init {
        params := ← decodeParamsV1 params
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do
        $statements:pfStmt*) => do
      pure (.entry {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := ← decodeTypeV1Unchecked type
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| entry $name:ident ($params:pfParam,*) do $statements:pfStmt*) => do
      pure (.entry {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := .unit
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do
        $statements:pfStmt*) => do
      pure (.view {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := ← decodeTypeV1Unchecked type
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| view $name:ident ($params:pfParam,*) do $statements:pfStmt*) => do
      pure (.view {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := .unit
        body := ← decodeBlockV1 statements
      })
  | _ => throw "unsupported portable program item"

private def leanNameComponentsV1 (name : Name) : Except String (Array SourceNameComponentV1) := do
  if name == .anonymous then
    pure #[]
  else
    pure (NonEmptyArray.toArray (← sourceQualifiedNameV1FromLeanName name).components)

private def decodeProgramV1Unchecked
    (moduleName : SourceQualifiedNameV1) (currentNamespace : Name) : Syntax →
    Except String ValidatedSourceV1
  | `(program $name:ident where $items:pfItem*) => do
      unless boundedNamePartCount 2 name.getId == some 1 do
        throw "program name must be unqualified"
      let shortName ← decodeNameV1 name
      let namespaceComponents ← leanNameComponentsV1 currentNamespace
      let moduleComponents := NonEmptyArray.toArray moduleName.components
      let identity ← sourceQualifiedNameV1OfComponents
        ((moduleComponents ++ namespaceComponents).push shortName)
      let sourceProgram : ProgramV1 := {
        name := shortName
        items := ← items.mapM decodeItemV1Unchecked
      }
      validateSourceV1 moduleName identity sourceProgram
  | _ => throw "expected a program declaration"

/-- Direct recovery frontend for the supported ProgramV1 product slice. It
constructs and validates ProgramV1 from Syntax without creating legacy source. -/
def decodeProgramCommandV1Checked
    (moduleName : SourceQualifiedNameV1) (currentNamespace : ProgramNamespace)
    (stx : Syntax) : CompileResult ValidatedSourceV1 := do
  preflightSyntax stx
  let namespaceName ← match currentNamespace with
    | .bounded name => pure name
    | .overLimit => .error (.resourceBound
        s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")
  match decodeProgramV1Unchecked moduleName namespaceName stx with
  | .ok source => pure source
  | .error message => .error (.invalidProgram message)

end ProgramV1Decoder

export ProgramV1Decoder (decodeProgramCommandV1Checked)

def decodeProgramCommandChecked (currentNamespace : ProgramNamespace) (stx : Syntax) :
    CompileResult ProofForgeV2.Source.Program := do
  preflightSyntax stx
  match stx with
  | `(program $name:ident where $_items:pfItem*) =>
      let namespaceName ← match currentNamespace with
        | .bounded namespaceName => .ok namespaceName
        | .overLimit => .error (.resourceBound
            s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")
      preflightProgramIdentity namespaceName name.getId
      match decodeProgramCommandUnchecked namespaceName stx with
      | .ok contractProgram => do
          validateDecodedProgram contractProgram
          return contractProgram
      | .error message => .error <| .invalidProgram message
  | _ => .error <| .invalidProgram "expected a program declaration"

def decodeProgramCommand (currentNamespace : Name) (stx : Syntax) :
    Except String ProofForgeV2.Source.Program :=
  (decodeProgramCommandChecked (.bounded currentNamespace) stx).mapError CompileError.render

private def quoteValueType : ProofForgeV2.Source.ValueType → MacroM (TSyntax `term)
  | .u64 => `(ProofForgeV2.Source.ValueType.u64)
  | .bool => `(ProofForgeV2.Source.ValueType.bool)
  | .field => `(ProofForgeV2.Source.ValueType.field)
  | .u8 => `(ProofForgeV2.Source.ValueType.u8)
  | .u16 => `(ProofForgeV2.Source.ValueType.u16)
  | .u32 => `(ProofForgeV2.Source.ValueType.u32)
  | .u128 => `(ProofForgeV2.Source.ValueType.u128)
  | .u256 => `(ProofForgeV2.Source.ValueType.u256)
  | .i8 => `(ProofForgeV2.Source.ValueType.i8)
  | .i16 => `(ProofForgeV2.Source.ValueType.i16)
  | .i32 => `(ProofForgeV2.Source.ValueType.i32)
  | .i64 => `(ProofForgeV2.Source.ValueType.i64)
  | .i128 => `(ProofForgeV2.Source.ValueType.i128)
  | .i256 => `(ProofForgeV2.Source.ValueType.i256)
  | .unit => `(ProofForgeV2.Source.ValueType.unit)
  | .principal => `(ProofForgeV2.Source.ValueType.principal)
  | .option element => do
      let elementExpr ← quoteValueType element
      `(ProofForgeV2.Source.ValueType.option $elementExpr)
  | .bytes length =>
      let n := length.toNat
      `(ProofForgeV2.Source.ValueType.bytes (UInt32.ofNat $(quote n)))
  | .array element length => do
      let elementExpr ← quoteValueType element
      `(ProofForgeV2.Source.ValueType.array $elementExpr $(quote length.val))

private def quoteVisibility : ProofForgeV2.Source.Visibility → MacroM (TSyntax `term)
  | .verifierVisible => `(ProofForgeV2.Source.Visibility.verifierVisible)
  | .proverWitness => `(ProofForgeV2.Source.Visibility.proverWitness)
  | .commitmentOnly => `(ProofForgeV2.Source.Visibility.commitmentOnly)

private def quoteParam (param : ProofForgeV2.Source.Param) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit param.name
  let typeExpr ← quoteValueType param.type
  let visibility ← quoteVisibility param.visibility
  `(ProofForgeV2.Source.Param.mk $name $typeExpr $visibility)

private def quoteParams (params : Array ProofForgeV2.Source.Param) : MacroM (TSyntax `term) := do
  let values ← params.mapM quoteParam
  `(#[$[$values],*])

private def quoteStateDecl (sourceState : ProofForgeV2.Source.StateDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceState.name
  let typeExpr ← quoteValueType sourceState.type
  let visibility ← quoteVisibility sourceState.visibility
  `(ProofForgeV2.Source.StateDecl.mk $name $typeExpr $visibility)

private def quoteState (states : Array ProofForgeV2.Source.StateDecl) : MacroM (TSyntax `term) := do
  let values ← states.mapM quoteStateDecl
  `(#[$[$values],*])

private def quoteFieldDecl (field : ProofForgeV2.Source.FieldDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit field.name
  let typeExpr ← quoteValueType field.type
  `(ProofForgeV2.Source.FieldDecl.mk $name $typeExpr)

private def quoteStructDecl (sourceStruct : ProofForgeV2.Source.StructDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceStruct.name
  let fields ← sourceStruct.fields.mapM quoteFieldDecl
  `(ProofForgeV2.Source.StructDecl.mk $name #[$[$fields],*])

private def quoteStructs (structs : Array ProofForgeV2.Source.StructDecl) : MacroM (TSyntax `term) := do
  let values ← structs.mapM quoteStructDecl
  `(#[$[$values],*])

private def quoteEnumVariant (variant : ProofForgeV2.Source.EnumVariant) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit variant.name
  let payloadTypes ← variant.payloadTypes.mapM quoteValueType
  `(ProofForgeV2.Source.EnumVariant.mk $name #[$[$payloadTypes],*])

private def quoteEnumDecl (sourceEnum : ProofForgeV2.Source.EnumDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceEnum.name
  let variants ← sourceEnum.variants.mapM quoteEnumVariant
  `(ProofForgeV2.Source.EnumDecl.mk $name #[$[$variants],*])

private def quoteEnums (enums : Array ProofForgeV2.Source.EnumDecl) : MacroM (TSyntax `term) := do
  let values ← enums.mapM quoteEnumDecl
  `(#[$[$values],*])

private def quoteEventDecl (sourceEvent : ProofForgeV2.Source.EventDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceEvent.name
  let params ← quoteParams sourceEvent.params
  `(ProofForgeV2.Source.EventDecl.mk $name $params)

private def quoteEvents (events : Array ProofForgeV2.Source.EventDecl) : MacroM (TSyntax `term) := do
  let values ← events.mapM quoteEventDecl
  `(#[$[$values],*])

private def quoteErrorDecl (sourceError : ProofForgeV2.Source.ErrorDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceError.name
  let params ← quoteParams sourceError.params
  `(ProofForgeV2.Source.ErrorDecl.mk $name $params)

private def quoteErrors (errors : Array ProofForgeV2.Source.ErrorDecl) : MacroM (TSyntax `term) := do
  let values ← errors.mapM quoteErrorDecl
  `(#[$[$values],*])

private partial def quoteExpr : ProofForgeV2.Source.Expr → MacroM (TSyntax `term)
  | .literal value =>
      let value := Syntax.mkNumLit (toString value.toNat)
      `(ProofForgeV2.Source.Expr.literal (UInt64.ofNat $value))
  | .stringLiteral value =>
      let value := Syntax.mkStrLit value
      `(ProofForgeV2.Source.Expr.stringLiteral $value)
  | .localFnCall callee args => do
      let callee := Syntax.mkStrLit callee
      let args ← args.mapM quoteExpr
      `(ProofForgeV2.Source.Expr.localFnCall $callee #[$[$args],*])
  | .constructorExpr path args => do
      let path := path.map Syntax.mkStrLit
      let args ← args.mapM quoteExpr
      `(ProofForgeV2.Source.Expr.constructorExpr #[$[$path],*] #[$[$args],*])
  | .indexAccess base index => do
      let base := Syntax.mkStrLit base
      let index ← quoteExpr index
      `(ProofForgeV2.Source.Expr.indexAccess $base $index)
  | .variable value =>
      let value := Syntax.mkStrLit value
      `(ProofForgeV2.Source.Expr.variable $value)
  | .state value =>
      let value := Syntax.mkStrLit value
      `(ProofForgeV2.Source.Expr.state $value)
  | .checkedAdd lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.checkedAdd $lhs $rhs)
  | .boolLiteral true => `(ProofForgeV2.Source.Expr.boolLiteral true)
  | .boolLiteral false => `(ProofForgeV2.Source.Expr.boolLiteral false)
  | .checkedSub lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.checkedSub $lhs $rhs)
  | .checkedMul lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.checkedMul $lhs $rhs)
  | .checkedDiv lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.checkedDiv $lhs $rhs)
  | .checkedMod lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.checkedMod $lhs $rhs)
  | .shiftLeft lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.shiftLeft $lhs $rhs)
  | .shiftRight lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.shiftRight $lhs $rhs)
  | .equal lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.equal $lhs $rhs)
  | .notEqual lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.notEqual $lhs $rhs)
  | .lessThan lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.lessThan $lhs $rhs)
  | .lessEqual lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.lessEqual $lhs $rhs)
  | .greaterThan lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.greaterThan $lhs $rhs)
  | .greaterEqual lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.greaterEqual $lhs $rhs)
  | .bitwiseAnd lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.bitwiseAnd $lhs $rhs)
  | .bitwiseXor lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.bitwiseXor $lhs $rhs)
  | .bitwiseOr lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.bitwiseOr $lhs $rhs)
  | .logicalAnd lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.logicalAnd $lhs $rhs)
  | .logicalOr lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.logicalOr $lhs $rhs)
  | .checkedNeg operand => do
      let operand ← quoteExpr operand
      `(ProofForgeV2.Source.Expr.checkedNeg $operand)
  | .bitwiseNot operand => do
      let operand ← quoteExpr operand
      `(ProofForgeV2.Source.Expr.bitwiseNot $operand)
  | .logicalNot operand => do
      let operand ← quoteExpr operand
      `(ProofForgeV2.Source.Expr.logicalNot $operand)

private def quoteConstDecl (sourceConst : ProofForgeV2.Source.ConstDecl) :
    MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceConst.name
  let typeExpr ← quoteValueType sourceConst.type
  let value ← quoteExpr sourceConst.value
  `(ProofForgeV2.Source.ConstDecl.mk $name $typeExpr $value)

private def quoteConsts (consts : Array ProofForgeV2.Source.ConstDecl) : MacroM (TSyntax `term) := do
  let values ← consts.mapM quoteConstDecl
  `(#[$[$values],*])

private def quoteStatement : ProofForgeV2.Source.Statement → MacroM (TSyntax `term)
  | .assign stateName value => do
      let stateName := Syntax.mkStrLit stateName
      let value ← quoteExpr value
      `(ProofForgeV2.Source.Statement.assign $stateName $value)
  | .returnValue value => do
      let value ← quoteExpr value
      `(ProofForgeV2.Source.Statement.returnValue $value)
  | .returnUnit => `(ProofForgeV2.Source.Statement.returnUnit)
  | .synchronousCall callee =>
      let callee := Syntax.mkStrLit callee
      `(ProofForgeV2.Source.Statement.synchronousCall $callee)
  | .letDecl name typeAnn value => do
      let name := Syntax.mkStrLit name
      let value ← quoteExpr value
      match typeAnn with
      | none =>
          `(ProofForgeV2.Source.Statement.letDecl $name (Option.none) $value)
      | some type => do
          let typeExpr ← quoteValueType type
          `(ProofForgeV2.Source.Statement.letDecl $name (Option.some $typeExpr) $value)
  | .assertStmt condition => do
      let condition ← quoteExpr condition
      `(ProofForgeV2.Source.Statement.assertStmt $condition)
  | .assertErrorStmt condition errorName => do
      let condition ← quoteExpr condition
      let errorName := Syntax.mkStrLit errorName
      `(ProofForgeV2.Source.Statement.assertErrorStmt $condition $errorName)
  | .revertStmt errorName args => do
      let errorName := Syntax.mkStrLit errorName
      let args ← args.mapM quoteExpr
      `(ProofForgeV2.Source.Statement.revertStmt $errorName #[$[$args],*])
  | .emitStmt eventName args => do
      let eventName := Syntax.mkStrLit eventName
      let args ← args.mapM quoteExpr
      `(ProofForgeV2.Source.Statement.emitStmt $eventName #[$[$args],*])
  | .ifStmt condition thenBody elseBody => do
      let condition ← quoteExpr condition
      let thenBody ← thenBody.mapM quoteStatement
      let elseBody ← match elseBody with
        | none => `(Option.none)
        | some body => do
            let body ← body.mapM quoteStatement
            `(Option.some #[$[$body],*])
      `(ProofForgeV2.Source.Statement.ifStmt $condition #[$[$thenBody],*] $elseBody)
  | .forStmt iterator start stopExclusive maxIterations body => do
      let iterator := Syntax.mkStrLit iterator
      let start ← quoteExpr start
      let stopExclusive ← quoteExpr stopExclusive
      let body ← body.mapM quoteStatement
      `(ProofForgeV2.Source.Statement.forStmt $iterator $start $stopExclusive
        $(quote maxIterations.val) #[$[$body],*])

private def quoteStatements (statements : Array ProofForgeV2.Source.Statement) :
    MacroM (TSyntax `term) := do
  let values ← statements.mapM quoteStatement
  `(#[$[$values],*])

private def quoteInitializer (initializer : ProofForgeV2.Source.Initializer) :
    MacroM (TSyntax `term) := do
  let params ← quoteParams initializer.params
  let body ← quoteStatements initializer.body
  `(ProofForgeV2.Source.Initializer.mk $params $body)

private def quoteInitializer? : Option ProofForgeV2.Source.Initializer → MacroM (TSyntax `term)
  | none => `(Option.none)
  | some initializer => do
      let initializer ← quoteInitializer initializer
      `(Option.some $initializer)

private def quoteEntryMode : ProofForgeV2.Source.EntryMode → MacroM (TSyntax `term)
  | .mutate => `(ProofForgeV2.Source.EntryMode.mutate)
  | .view => `(ProofForgeV2.Source.EntryMode.view)

private def quoteEntry (sourceEntry : ProofForgeV2.Source.Entry) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceEntry.name
  let params ← quoteParams sourceEntry.params
  let result ← quoteValueType sourceEntry.result
  let mode ← quoteEntryMode sourceEntry.mode
  let body ← quoteStatements sourceEntry.body
  `(ProofForgeV2.Source.Entry.mk $name $params $result $mode $body)

private def quoteEntries (entries : Array ProofForgeV2.Source.Entry) : MacroM (TSyntax `term) := do
  let values ← entries.mapM quoteEntry
  `(#[$[$values],*])

private def quoteFnDecl (sourceFn : ProofForgeV2.Source.FnDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceFn.name
  let params ← quoteParams sourceFn.params
  let result ← quoteValueType sourceFn.result
  let body ← quoteStatements sourceFn.body
  `(ProofForgeV2.Source.FnDecl.mk $name $params $result $body)

private def quoteFunctions (functions : Array ProofForgeV2.Source.FnDecl) :
    MacroM (TSyntax `term) := do
  let values ← functions.mapM quoteFnDecl
  `(#[$[$values],*])

private def quoteInvariantDecl (sourceInvariant : ProofForgeV2.Source.InvariantDecl) :
    MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceInvariant.name
  let predicate ← quoteExpr sourceInvariant.predicate
  `(ProofForgeV2.Source.InvariantDecl.mk $name $predicate)

private def quoteInvariants (invariants : Array ProofForgeV2.Source.InvariantDecl) :
    MacroM (TSyntax `term) := do
  let values ← invariants.mapM quoteInvariantDecl
  `(#[$[$values],*])

private def quoteExtensionReq (requirement : ProofForgeV2.Source.ExtensionReq) :
    MacroM (TSyntax `term) := do
  let id := Syntax.mkStrLit requirement.id
  let version := Syntax.mkStrLit requirement.version
  let digest := Syntax.mkStrLit requirement.digest
  `(ProofForgeV2.Source.ExtensionReq.mk $id $version $digest)

private def quoteExtensionRequirements (requirements : Array ProofForgeV2.Source.ExtensionReq) :
    MacroM (TSyntax `term) := do
  let values ← requirements.mapM quoteExtensionReq
  `(#[$[$values],*])

private def quoteProofDecl (proofReference : ProofForgeV2.Source.ProofDecl) :
    MacroM (TSyntax `term) := do
  let invariant := Syntax.mkStrLit proofReference.invariant
  let theoremComponents := proofReference.«theorem».map Syntax.mkStrLit
  `(ProofForgeV2.Source.ProofDecl.mk $invariant #[$[$theoremComponents],*])

private def quoteProofReferences (proofReferences : Array ProofForgeV2.Source.ProofDecl) :
    MacroM (TSyntax `term) := do
  let values ← proofReferences.mapM quoteProofDecl
  `(#[$[$values],*])

/-- Quote an already decoded source value without reinterpreting raw grammar. -/
private def quoteProgram (sourceProgram : ProofForgeV2.Source.Program) : MacroM (TSyntax `term) := do
  let qualifiedName := Syntax.mkStrLit sourceProgram.qualifiedName
  let name := Syntax.mkStrLit sourceProgram.name
  let stateExpr ← quoteState sourceProgram.state
  let structs ← quoteStructs sourceProgram.structs
  let enums ← quoteEnums sourceProgram.enums
  let consts ← quoteConsts sourceProgram.consts
  let events ← quoteEvents sourceProgram.events
  let errors ← quoteErrors sourceProgram.errors
  let initializer ← quoteInitializer? sourceProgram.initializer
  let entries ← quoteEntries sourceProgram.entries
  let functions ← quoteFunctions sourceProgram.functions
  let invariants ← quoteInvariants sourceProgram.invariants
  let extensionRequirements ← quoteExtensionRequirements sourceProgram.extensionRequirements
  let proofReferences ← quoteProofReferences sourceProgram.proofReferences
  `(ProofForgeV2.Source.Program.mk $qualifiedName $name $stateExpr $structs $enums $consts $events
      $errors $initializer $entries $functions $invariants $extensionRequirements $proofReferences)

elab_rules : command
  | `(program $name:ident where $items:pfItem*) => do
      let currentNamespace ← getCurrNamespace
      let commandStx ← `(program $name:ident where $items:pfItem*)
      let decoded ← match decodeProgramCommand currentNamespace commandStx with
      | .error message => throwError message
      | .ok decoded => pure decoded
      let programExpr ← Lean.Elab.liftMacroM <| quoteProgram decoded
      let expanded ← `(@[proof_forge_program] def $name : ProofForgeV2.Source.Program :=
          $programExpr)
      Lean.Elab.Command.elabCommand expanded

end ProofForgeV2.Language
