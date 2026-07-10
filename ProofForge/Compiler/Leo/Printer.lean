import ProofForge.Compiler.Leo.AST

namespace ProofForge.Compiler.Leo.Printer

open ProofForge.Compiler.Leo.AST

def unsupported (what : String) : Except LowerError String :=
  .error { message := s!"Leo printer does not yet support {what}" }

def printIdentifier (id : Identifier) : String := id

def printPath (path : Path) : String :=
  String.intercalate "::" path.toList

def printIntegerType : IntegerType → String
  | .u8 => "u8" | .u16 => "u16" | .u32 => "u32" | .u64 => "u64"
  | .u128 => "u128" | .i8 => "i8" | .i16 => "i16" | .i32 => "i32" | .i64 => "i64"

partial def printType : LeoType → Except LowerError String
  | .integer t => .ok (printIntegerType t)
  | .boolean => .ok "bool"
  | .unit => .ok "()"
  | .address => .ok "address"
  | .array element length => do
      let es ← printType element
      .ok s!"[{es}; {length}]"
  | .composite name => .ok name
  | .field => .ok "field"
  | .future _ _ => .ok "Final"  -- downgrade Future<Fn(...)> to Final for Leo 4.0.2
  | .group => .ok "group"
  | .mapping k v => do
      let ks ← printType k
      let vs ← printType v
      .ok s!"mapping[{ks}, {vs}]"
  | .scalar => .ok "scalar"
  | .signature => .ok "signature"
  | .string => .ok "string"
  | .tuple ts => do
      let parts ← ts.mapM printType
      .ok s!"({String.intercalate ", " parts.toList})"
  | .err => unsupported "error type"

def printLiteral : Literal → String
  | .boolean true => "true"
  | .boolean false => "false"
  | .integer ty value => s!"{value}{printIntegerType ty}"
  | .string s => s!"\"{s}\""
  | .address s => s
  | .field s => s
  | .group s => s
  | .none => "none"
  | .scalar s => s
  | .signature s => s

/-- PF-P1-06: never emit comment placeholders for unsupported ops — fail closed. -/
def printBinaryOp : BinaryOperation → Except LowerError String
  | .add => .ok "+" | .and => .ok "&&" | .bitwiseAnd => .ok "&"
  | .div => .ok "/" | .eq => .ok "==" | .gte => .ok ">=" | .gt => .ok ">"
  | .lte => .ok "<=" | .lt => .ok "<" | .mod => .ok "%" | .mul => .ok "*"
  | .neq => .ok "!="
  | .or => .ok "||" | .bitwiseOr => .ok "|" | .pow => .ok "**"
  | .shl => .ok "<<" | .shr => .ok ">>"
  | .sub => .ok "-" | .xor => .ok "^"
  | .addWrapped | .subWrapped | .mulWrapped | .divWrapped | .powWrapped
  | .shlWrapped | .shrWrapped | .remWrapped =>
      unsupported "wrapped operator outside expression method lowering"
  | .nand => unsupported "binary operator nand"
  | .nor => unsupported "binary operator nor"
  | .rem => unsupported "binary operator rem"

def printUnaryOp : UnaryOperation → Except LowerError String
  | .not => .ok "!"
  | .negate => .ok "-"
  | other => unsupported s!"unary operator {repr other}"

mutual
  partial def printExpression (e : Expression) : Except LowerError String :=
    match e with
    | .literal l => .ok (printLiteral l)
    | .identifier name => .ok (printIdentifier name)
    | .binary b => do
        let l ← printExpression b.left
        let r ← printExpression b.right
        match b.op with
        | .addWrapped => .ok s!"{l}.add_wrapped({r})"
        | .subWrapped => .ok s!"{l}.sub_wrapped({r})"
        | .mulWrapped => .ok s!"{l}.mul_wrapped({r})"
        | .divWrapped => .ok s!"{l}.div_wrapped({r})"
        | .powWrapped => .ok s!"{l}.pow_wrapped({r})"
        | .shlWrapped => .ok s!"{l}.shl_wrapped({r})"
        | .shrWrapped => .ok s!"{l}.shr_wrapped({r})"
        | .remWrapped => .ok s!"{l}.rem_wrapped({r})"
        | op => do
            let token ← printBinaryOp op
            .ok s!"({l} {token} {r})"
    | .unary u => do
        let r ← printExpression u.receiver
        let op ← printUnaryOp u.op
        .ok s!"({op}{r})"
    | .call c => do
        let fn := printPath c.function
        let args ← c.arguments.mapM printExpression
        .ok s!"{fn}({String.intercalate ", " args.toList})"
    | .memberAccess m => do
        let inner ← printExpression m.inner
        .ok s!"{inner}.{m.name}"
    | .async b => do
        let bodyLines ← b.statements.mapM (printStatement 1)
        let body := String.intercalate "\n" bodyLines.toList
        .ok ("final {" ++ "\n" ++ body ++ "\n" ++ "}")
    | .cast c => do
        let v ← printExpression c.value
        let t ← printType c.target
        .ok s!"({v} as {t})"
    | .array values => do
        let vs ← values.mapM printExpression
        .ok s!"[{String.intercalate ", " vs.toList}]"
    | .composite name fields => do
        let fs ← fields.mapM (fun (n, e) => do let s ← printExpression e; .ok (n ++ ": " ++ s))
        .ok (name ++ " { " ++ String.intercalate ", " fs.toList ++ " }")
    | .ternary cond t e => do
        let c ← printExpression cond
        let tt ← printExpression t
        let ee ← printExpression e
        .ok s!"if {c} ? {tt} : {ee}"
    | .tuple values => do
        let vs ← values.mapM printExpression
        .ok s!"({String.intercalate ", " vs.toList})"
    | .repeat value count => do
        let v ← printExpression value
        .ok s!"[{v}; {count}]"
    | .arrayAccess a => do
        let arr ← printExpression a.array
        let idx ← printExpression a.index
        .ok s!"{arr}[{idx}]"
    | .unit => .ok "()"
    | .err => unsupported "error expression"

  partial def printBlock (indentLevel : Nat) (b : Block) : Except LowerError String := do
    if b.statements.isEmpty then
      .ok (indent indentLevel "{ }")
    else
      let header := indent indentLevel "{"
      let body ← b.statements.mapM (printStatement (indentLevel + 1))
      let footer := indent indentLevel "}"
      .ok (String.intercalate "\n" ([header] ++ body.toList ++ [footer]))

  partial def printStatement (indentLevel : Nat) : Statement → Except LowerError String
    | .definition place ty? value => do
        let name := match place with | .single n => n | .multiple ns => String.intercalate ", " ns.toList
        let val ← printExpression value
        let typeAnnot ← match ty? with
          | some t => do let s ← printType t; .ok (": " ++ s ++ " ")
          | none => .ok " "
        .ok (indent indentLevel s!"let {name}{typeAnnot}= {val};")
    | .assign place value => do
        let p ← printExpression place
        let v ← printExpression value
        .ok (indent indentLevel s!"{p} = {v};")
    | .block b => printBlock indentLevel b
    | .conditional cond thenBranch elseBranch? => do
        let c ← printExpression cond
        let thenBodyLines ← thenBranch.statements.mapM (printStatement (indentLevel + 1))
        let thenBody := String.intercalate "\n" thenBodyLines.toList
        let header := indent indentLevel ("if " ++ c ++ " {")
        let footer := indent indentLevel "}"
        match elseBranch? with
        | none =>
            .ok (header ++ "\n" ++ thenBody ++ "\n" ++ footer)
        | some (.block elseBranch) => do
            let elseBodyLines ← elseBranch.statements.mapM (printStatement (indentLevel + 1))
            let elseBody := String.intercalate "\n" elseBodyLines.toList
            let elseHeader := indent indentLevel "} else {"
            .ok (header ++ "\n" ++ thenBody ++ "\n" ++ elseHeader ++ "\n" ++ elseBody ++ "\n" ++ footer)
        | some elseSt => do
            let e ← printStatement (indentLevel + 1) elseSt
            let elseHeader := indent indentLevel "} else {"
            .ok (header ++ "\n" ++ thenBody ++ "\n" ++ elseHeader ++ "\n" ++ e ++ "\n" ++ footer)
    | .constDecl name ty? value => do
        let val ← printExpression value
        let typeAnnot ← match ty? with
          | some t => do let s ← printType t; .ok (": " ++ s ++ " ")
          | none => .ok " "
        .ok (indent indentLevel s!"const {name}{typeAnnot}= {val};")
    | .expression e => do
        let s ← printExpression e
        .ok (indent indentLevel s!"{s};")
    | .iteration var ty? start stop inclusive body => do
        let lo ← printExpression start
        let hi ← printExpression stop
        let range := if inclusive then s!"{lo}..={hi}" else s!"{lo}..{hi}"
        let tyStr ← match ty? with | some t => do let s ← printType t; .ok (": " ++ s) | none => .ok ""
        let bodyLines ← body.statements.mapM (printStatement (indentLevel + 1))
        let bodyStr := String.intercalate "\n" bodyLines.toList
        let header := indent indentLevel ("for " ++ var ++ tyStr ++ " in " ++ range ++ " {")
        let footer := indent indentLevel "}"
        .ok (header ++ "\n" ++ bodyStr ++ "\n" ++ footer)
    | .returnSt none => .ok (indent indentLevel "return;")
    | .returnSt (some e) => do
        match e with
        | .async b =>
            let bodyLines ← b.statements.mapM (printStatement (indentLevel + 1))
            let body := String.intercalate "\n" bodyLines.toList
            .ok (indent indentLevel "return final {" ++ "\n" ++ body ++ "\n" ++ indent indentLevel "};")
        | value => do
            let v ← printExpression value
            .ok (indent indentLevel ("return " ++ v ++ ";"))
    | .assert cond _ => do
        let c ← printExpression cond
        .ok (indent indentLevel s!"assert({c});")
end

def printAnnotation (a : Annotation) : String := s!"@{a.name}"

def printInput (i : Input) : Except LowerError String := do
  let ty ← printType i.ty
  -- Leo's no-keyword default is `private` (proof-context); only `public` and
  -- `constant` inputs get a prefix. Verified against ProvableHQ/leo
  -- functions/transfer_inline (`public amount: u64`).
  let mode := match i.mode with
    | .public_ => "public "
    | .constant_ => "constant "
    | .private_ => ""
  .ok s!"{mode}{i.name}: {ty}"

def printFunction (indentLevel : Nat) (f : Function) : Except LowerError String := do
  let keyword := match f.variant with
    | .fn => "fn"
    | .finalFn => "final fn"
    | .entryPoint => "fn"
    | .view => "view fn"
  let params ← f.input.mapM printInput
  let paramsStr := String.intercalate ", " params.toList
  let ret ← printType f.outputType
  let header := keyword ++ " " ++ f.identifier ++ "(" ++ paramsStr ++ ") -> " ++ ret ++ " {"
  let bodyLines ← f.block.statements.mapM (printStatement (indentLevel + 1))
  let body := String.intercalate "\n" bodyLines.toList
  let footer := indent indentLevel "}"
  let annoLines := f.annotations.map printAnnotation
  let prefixed :=
    if annoLines.isEmpty then
      indent indentLevel header ++ "\n" ++ body ++ "\n" ++ footer
    else
      let annos := String.intercalate "\n" (annoLines.map (indent indentLevel)).toList
      annos ++ "\n" ++ indent indentLevel header ++ "\n" ++ body ++ "\n" ++ footer
  .ok prefixed

def printMapping (indentLevel : Nat) (m : Mapping) : Except LowerError String := do
  let k ← printType m.keyType
  let v ← printType m.valueType
  .ok (indent indentLevel s!"mapping {m.identifier}: {k} => {v};")

/-- Print a composite as a Leo `record` (when `isRecord`) or `struct`.
Verified against ProvableHQ/leo migration/transitions_to_fn (`record Token {…}`)
and data_types/struct_update (`struct Point {…}`). Records carry their fields
(`owner: address`, …) inline. -/
def printComposite (indentLevel : Nat) (c : Composite) : Except LowerError String := do
  let keyword := if c.isRecord then "record" else "struct"
  let fieldStrs ← c.members.mapM fun mem => do
    let ty ← printType mem.ty
    .ok (indent (indentLevel + 1) s!"{mem.name}: {ty}")
  let fields := String.intercalate ",\n" fieldStrs.toList
  let header := indent indentLevel (keyword ++ " " ++ c.identifier ++ " {")
  let footer := indent indentLevel "}"
  .ok (header ++ "\n" ++ fields ++ "\n" ++ footer)

def printConstructor (indentLevel : Nat) (c : Constructor) : Except LowerError String := do
  let annoLines := c.annotations.map printAnnotation
  let annos := if annoLines.isEmpty then "" else String.intercalate "\n" (annoLines.map (indent indentLevel)).toList ++ "\n"
  if c.block.statements.isEmpty then
    .ok (annos ++ indent indentLevel "constructor() {}")
  else
    let header := "constructor() {"
    let body ← printBlock (indentLevel + 1) c.block
    let footer := indent indentLevel "}"
    .ok (annos ++ indent indentLevel header ++ "\n" ++ body ++ "\n" ++ footer)

def printProgramScope (indentLevel : Nat) (scope : ProgramScope) : Except LowerError String := do
  let compositeLines ← scope.composites.mapM (fun (_, c) => printComposite (indentLevel + 1) c)
  let mappingLines ← scope.mappings.mapM (fun (_, m) => printMapping (indentLevel + 1) m)
  let functionLines ← scope.functions.mapM (fun (_, f) => printFunction (indentLevel + 1) f)
  let constructorLines ← match scope.constructor with
    | none => .ok #[]
    | some c => do let s ← printConstructor (indentLevel + 1) c; .ok #[s]
  let blank := "\n" ++ indent (indentLevel + 1) "" ++ "\n"
  let decls := compositeLines ++ mappingLines ++ constructorLines
  let declsStr := String.intercalate blank decls.toList
  let functionsStr := String.intercalate "\n" functionLines.toList
  let body :=
    if functionLines.isEmpty then
      declsStr
    else if decls.isEmpty then
      functionsStr
    else
      declsStr ++ blank ++ functionsStr
  .ok ("program " ++ scope.programId ++ " {\n" ++ body ++ "\n" ++ indent indentLevel "}")

def printImport (i : Import) : String :=
  "import " ++ i.programId ++ ";"

def printProgram (p : Program) : Except LowerError String := do
  match p.scopes with
  | #[(_, scope)] =>
      let importLines := p.imports.map printImport
      let header := String.intercalate "\n" importLines.toList
      let body ← printProgramScope 0 scope
      .ok (if importLines.isEmpty then body else header ++ "\n\n" ++ body)
  | _ => .error { message := "Leo printer currently supports exactly one program scope" }

def printProgramToString (p : Program) : Except LowerError String := printProgram p

end ProofForge.Compiler.Leo.Printer
