# Leo AST Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the Aleo Leo backend so that it lowers ProofForge portable IR into a structured Leo AST (mirroring `ProvableHQ/leo crates/ast/src/`) and then pretty-prints that AST to Leo 4.0.2 source, while keeping the existing smoke test output unchanged.

**Architecture:** Introduce `ProofForge/Compiler/Leo/` containing the AST definitions, a printer, and an IR emitter. The existing `ProofForge.Backend.Aleo.IR.renderModule` becomes a thin wrapper around `Emit.emitModule` followed by `Printer.printProgram`. The AST stays aligned with Leo 4.3.2 structures; the printer downgrades `async { }` / `Future<Fn(...)>` to Leo 4.0.2 `final { }` / `Final`.

**Tech Stack:** Lean 4 (`lake` build), official Leo AST as reference, existing `ProofForge.IR.Contract` as input.

---

## File map

| File | Responsibility |
|---|---|
| `ProofForge/Compiler/Leo.lean` | Public re-export of the Leo compiler namespace. |
| `ProofForge/Compiler/Leo/AST.lean` | Root re-export of AST submodules. |
| `ProofForge/Compiler/Leo/AST/Core.lean` | `Identifier`, `Symbol`, `Annotation`, `Mode`, `LowerError`, indentation helpers. |
| `ProofForge/Compiler/Leo/AST/Type.lean` | `IntegerType`, `Type`, `MappingType`, `FutureType`. |
| `ProofForge/Compiler/Leo/AST/Literal.lean` | `Literal` / `LiteralVariant`. |
| `ProofForge/Compiler/Leo/AST/Expression.lean` | `Expression`, `BinaryOperation`, `UnaryOperation`, `CallExpression`, `MemberAccess`. |
| `ProofForge/Compiler/Leo/AST/Statement.lean` | `Statement`, `Block`, `DefinitionStatement`, `AssignStatement`, etc. |
| `ProofForge/Compiler/Leo/AST/Function.lean` | `Function`, `Variant`, `Input`, `Output`. |
| `ProofForge/Compiler/Leo/AST/Composite.lean` | `Composite` (struct/record), `Member`. |
| `ProofForge/Compiler/Leo/AST/Mapping.lean` | `Mapping` declaration. |
| `ProofForge/Compiler/Leo/AST/Storage.lean` | `StorageVariable`. |
| `ProofForge/Compiler/Leo/AST/Program.lean` | `Program`, `ProgramScope`, `Import`, `Constructor`. |
| `ProofForge/Compiler/Leo/Printer.lean` | AST → Leo 4.0.2 source string. |
| `ProofForge/Compiler/Leo/Emit.lean` | `ProofForge.IR.Contract` → Leo AST. |
| `ProofForge/Backend/Aleo/IR.lean` | Refactored to use `Emit` + `Printer`. |

---

## Task 1: Create `ProofForge/Compiler/Leo/AST/Core.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Core.lean`

- [ ] **Step 1: Write the module**

```lean
import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Compiler.Leo.AST

/-- Identifiers are plain strings. -/
abbrev Identifier := String

/-- Program ids are strings like "credits.aleo". -/
abbrev ProgramId := String

/-- Function visibility/input mode (public/private/const). -/
inductive Mode where
  | public
  | private
  | const
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
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Core`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Core.lean
git commit -m "feat(leo-ast): add Core identifiers, annotations, and LowerError"
```

---

## Task 2: Create `ProofForge/Compiler/Leo/AST/Type.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Type.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core

namespace ProofForge.Compiler.Leo.AST

inductive IntegerType where
  | u8 | u16 | u32 | u64 | u128 | i8 | i16 | i32 | i64
  deriving BEq, Repr, Inhabited

structure MappingType where
  key : Type
  value : Type
  deriving Repr, Inhabited

structure FutureType where
  inputs : Array Type
  output : Type
  deriving Repr, Inhabited

structure ArrayType where
  element : Type
  length : Nat
  deriving Repr, Inhabited

inductive Type where
  | address
  | array (t : ArrayType)
  | boolean
  | composite (name : Identifier)
  | field
  | future (t : FutureType)
  | group
  | integer (t : IntegerType)
  | mapping (t : MappingType)
  | scalar
  | signature
  | string
  | tuple (ts : Array Type)
  | unit
  | err
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Type`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Type.lean
git commit -m "feat(leo-ast): add Type, IntegerType, MappingType, FutureType"
```

---

## Task 3: Create `ProofForge/Compiler/Leo/AST/Literal.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Literal.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

inductive Literal where
  | address (value : String)
  | boolean (value : Bool)
  | field (value : String)
  | group (value : String)
  | integer (ty : IntegerType) (value : Nat)
  | none
  | scalar (value : String)
  | signature (value : String)
  | string (value : String)
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Literal`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Literal.lean
git commit -m "feat(leo-ast): add Literal"
```

---

## Task 4: Create `ProofForge/Compiler/Leo/AST/Statement.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Statement.lean`

- [ ] **Step 1: Write the module**

`Statement.lean` must be defined before `Expression.lean` because `Expression` references `Block`.

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

mutual
  inductive Statement where
    | assert (condition : Expression) (message? : Option Expression)
    | assign (place : Expression) (value : Expression)
    | block (b : Block)
    | conditional (condition : Expression) (thenBranch : Block) (elseBranch? : Option Statement)
    | constDecl (name : Identifier) (ty? : Option Type) (value : Expression)
    | definition (place : DefinitionPlace) (ty? : Option Type) (value : Expression)
    | expression (e : Expression)
    | iteration (var : Identifier) (ty? : Option Type) (start stop : Expression) (inclusive : Bool) (body : Block)
    | returnSt (value? : Option Expression)
    deriving Repr, Inhabited

  inductive DefinitionPlace where
    | single (name : Identifier)
    | multiple (names : Array Identifier)
    deriving Repr, Inhabited

  structure Block where
    statements : Array Statement
    deriving Repr, Inhabited
end

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Statement`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Statement.lean
git commit -m "feat(leo-ast): add Statement and Block"
```

---

## Task 5: Create `ProofForge/Compiler/Leo/AST/Expression.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Expression.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Literal
import ProofForge.Compiler.Leo.AST.Statement

namespace ProofForge.Compiler.Leo.AST

abbrev Path := Array Identifier

inductive BinaryOperation where
  | add | addWrapped | and | bitwiseAnd | div | divWrapped | eq | gte | gt | lte | lt
  | mod | mul | mulWrapped | nand | neq | nor | or | bitwiseOr | pow | powWrapped
  | rem | remWrapped | shl | shlWrapped | shr | shrWrapped | sub | subWrapped | xor
  deriving BEq, Repr, Inhabited

inductive UnaryOperation where
  | abs | absWrapped | double | inverse | negate | not | square | squareRoot
  | toXCoordinate | toYCoordinate
  deriving BEq, Repr, Inhabited

structure CallExpression where
  function : Path
  constArguments : Array Expression
  arguments : Array Expression
  deriving Repr, Inhabited

structure MemberAccess where
  inner : Expression
  name : Identifier
  deriving Repr, Inhabited

structure BinaryExpression where
  op : BinaryOperation
  left : Expression
  right : Expression
  deriving Repr, Inhabited

structure UnaryExpression where
  op : UnaryOperation
  receiver : Expression
  deriving Repr, Inhabited

structure CastExpression where
  value : Expression
  target : Type
  deriving Repr, Inhabited

mutual
  inductive Expression where
    | arrayAccess (e : ArrayAccess)
    | async (b : Block)
    | array (values : Array Expression)
    | binary (e : BinaryExpression)
    | call (e : CallExpression)
    | cast (e : CastExpression)
    | composite (name : Identifier) (fields : Array (Identifier × Expression))
    | err
    | identifier (name : Identifier)
    | literal (l : Literal)
    | memberAccess (e : MemberAccess)
    | repeat (value : Expression) (count : Nat)
    | ternary (cond : Expression) (thenExpr : Expression) (elseExpr : Expression)
    | tuple (values : Array Expression)
    | unary (e : UnaryExpression)
    | unit
    deriving Repr, Inhabited

  structure ArrayAccess where
    array : Expression
    index : Expression
    deriving Repr, Inhabited
end

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Expression`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Expression.lean
git commit -m "feat(leo-ast): add Expression, BinaryOperation, UnaryOperation"
```

---

## Task 6: Create `ProofForge/Compiler/Leo/AST/Function.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Function.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Statement

namespace ProofForge.Compiler.Leo.AST

inductive Variant where
  | fn
  | finalFn
  | entryPoint
  | view
  deriving BEq, Repr, Inhabited

structure Input where
  name : Identifier
  ty : Type
  mode : Mode := .public
  deriving Repr, Inhabited

structure Output where
  ty : Type
  mode : Mode := .public
  deriving Repr, Inhabited

structure Function where
  annotations : Array Annotation
  variant : Variant
  identifier : Identifier
  constParameters : Array Identifier
  input : Array Input
  output : Array Output
  outputType : Type
  block : Block
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Function`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Function.lean
git commit -m "feat(leo-ast): add Function, Variant, Input, Output"
```

---

## Task 7: Create `ProofForge/Compiler/Leo/AST/Composite.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Composite.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

structure Member where
  name : Identifier
  ty : Type
  deriving Repr, Inhabited

structure Composite where
  identifier : Identifier
  members : Array Member
  isRecord : Bool := false
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Composite`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Composite.lean
git commit -m "feat(leo-ast): add Composite and Member"
```

---

## Task 8: Create `ProofForge/Compiler/Leo/AST/Mapping.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Mapping.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

structure Mapping where
  identifier : Identifier
  keyType : Type
  valueType : Type
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Mapping`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Mapping.lean
git commit -m "feat(leo-ast): add Mapping declaration"
```

---

## Task 9: Create `ProofForge/Compiler/Leo/AST/Storage.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Storage.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

structure StorageVariable where
  identifier : Identifier
  ty : Type
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Storage`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Storage.lean
git commit -m "feat(leo-ast): add StorageVariable"
```

---

## Task 10: Create `ProofForge/Compiler/Leo/AST/Program.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST/Program.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Function
import ProofForge.Compiler.Leo.AST.Composite
import ProofForge.Compiler.Leo.AST.Mapping
import ProofForge.Compiler.Leo.AST.Storage

namespace ProofForge.Compiler.Leo.AST

structure Import where
  programId : ProgramId
  deriving Repr, Inhabited

structure Constructor where
  annotations : Array Annotation
  block : Block
  deriving Repr, Inhabited

structure Interface where
  identifier : Identifier
  parents : Array Type
  members : Array Function
  deriving Repr, Inhabited

structure ConstDeclaration where
  identifier : Identifier
  ty? : Option Type
  value : Expression
  deriving Repr, Inhabited

structure ProgramScope where
  programId : ProgramId
  parents : Array Type
  consts : Array (Identifier × ConstDeclaration)
  composites : Array (Identifier × Composite)
  mappings : Array (Identifier × Mapping)
  storageVariables : Array (Identifier × StorageVariable)
  functions : Array (Identifier × Function)
  interfaces : Array (Identifier × Interface)
  constructor : Option Constructor
  deriving Repr, Inhabited

structure Program where
  imports : Array Import
  scopes : Array (Identifier × ProgramScope)
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST.Program`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST/Program.lean
git commit -m "feat(leo-ast): add Program, ProgramScope, Import, Constructor"
```

---

## Task 11: Create `ProofForge/Compiler/Leo/AST.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/AST.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Literal
import ProofForge.Compiler.Leo.AST.Statement
import ProofForge.Compiler.Leo.AST.Expression
import ProofForge.Compiler.Leo.AST.Function
import ProofForge.Compiler.Leo.AST.Composite
import ProofForge.Compiler.Leo.AST.Mapping
import ProofForge.Compiler.Leo.AST.Storage
import ProofForge.Compiler.Leo.AST.Program

namespace ProofForge.Compiler.Leo.AST

end ProofForge.Compiler.Leo.AST
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.AST`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/AST.lean
git commit -m "feat(leo-ast): add AST root re-export module"
```

---

## Task 12: Create `ProofForge/Compiler/Leo/Printer.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/Printer.lean`

- [ ] **Step 1: Write the module**

```lean
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

partial def printType : Type → Except LowerError String
  | .integer t => .ok (printIntegerType t)
  | .boolean => .ok "bool"
  | .unit => .ok "()"
  | .address => unsupported "address type"
  | .array _ => unsupported "array type"
  | .composite name => .ok name
  | .field => unsupported "field type"
  | .future _ => .ok "Final"  -- downgrade Future<Fn(...)> to Final for Leo 4.0.2
  | .group => unsupported "group type"
  | .mapping t => do
      let k ← printType t.key
      let v ← printType t.value
      .ok s!"mapping[{k}, {v}]"
  | .scalar => unsupported "scalar type"
  | .signature => unsupported "signature type"
  | .string => .ok "string"
  | .tuple _ => unsupported "tuple type"
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

mutual
  partial def printExpression (e : Expression) : Except LowerError String :=
    match e with
    | .literal l => .ok (printLiteral l)
    | .identifier name => .ok (printIdentifier name)
    | .binary b => do
        let l ← printExpression b.left
        let r ← printExpression b.right
        .ok s!"({l} {printBinaryOp b.op} {r})"
    | .unary u => do
        let r ← printExpression u.receiver
        .ok s!"({printUnaryOp u.op}{r})"
    | .call c => do
        let fn := printPath c.function
        let args ← c.arguments.mapM printExpression
        .ok s!"{fn}({String.intercalate ", " args.toList})"
    | .memberAccess m => do
        let inner ← printExpression m.inner
        .ok s!"{inner}.{m.name}"
    | .async b => do
        let body ← printBlock 1 b
        .ok s!"final {body.trim}"  -- downgrade async to final for Leo 4.0.2
    | .cast c => do
        let v ← printExpression c.value
        let t ← printType c.target
        .ok s!"({v} as {t})"
    | .array values => do
        let vs ← values.mapM printExpression
        .ok s!"[{String.intercalate ", " vs.toList}]"
    | .composite name fields => do
        let fs ← fields.mapM (fun (n, e) => do let s ← printExpression e; .ok s!"{n}: {s}")
        .ok s!"{name} {{ {String.intercalate ", " fs.toList} }}"
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

  partial def printBinaryOp : BinaryOperation → String
    | .add => "+" | .addWrapped => "+" | .and => "&&" | .bitwiseAnd => "&"
    | .div => "/" | .divWrapped => "/" | .eq => "==" | .gte => ">=" | .gt => ">"
    | .lte => "<=" | .lt => "<" | .mod => "%" | .mul => "*" | .mulWrapped => "*"
    | .nand => unsupported' "nand" | .neq => "!=" | .nor => unsupported' "nor"
    | .or => "||" | .bitwiseOr => "|" | .pow => "**" | .powWrapped => "**"
    | .rem => unsupported' "rem" | .remWrapped => unsupported' "remWrapped"
    | .shl => "<<" | .shlWrapped => "<<" | .shr => ">>" | .shrWrapped => ">>"
    | .sub => "-" | .subWrapped => "-" | .xor => "^"

  partial def printUnaryOp : UnaryOperation → String
    | .not => "!" | .negate => "-"
    | other => "/* unsupported unary */"

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
        let suffix := match ty? with | some t => do let s ← printType t; .ok s!": {s} " | none => .ok " "
        .ok (indent indentLevel s!"let {name}{suffix.trimRight}= {val};")
    | .assign place value => do
        let p ← printExpression place
        let v ← printExpression value
        .ok (indent indentLevel s!"{p} = {v};")
    | .block b => printBlock indentLevel b
    | .conditional cond thenBranch elseBranch? => do
        let c ← printExpression cond
        let t ← printBlock indentLevel thenBranch
        match elseBranch? with
        | none => .ok (indent indentLevel s!"if {c} {t.trim}")
        | some elseSt => do
            let e ← printStatement indentLevel elseSt
            .ok (indent indentLevel s!"if {c} {t.trim} else {e.trim}")
    | .constDecl name ty? value => do
        let val ← printExpression value
        let suffix := match ty? with | some t => do let s ← printType t; .ok s!": {s} " | none => .ok " "
        .ok (indent indentLevel s!"const {name}{suffix.trimRight}= {val};")
    | .expression e => do
        let s ← printExpression e
        .ok (indent indentLevel s!"{s};")
    | .iteration var ty? start stop inclusive body => do
        let lo ← printExpression start
        let hi ← printExpression stop
        let range := if inclusive then s!"{lo}..={hi}" else s!"{lo}..{hi}"
        let tyStr := match ty? with | some t => do let s ← printType t; .ok s!": {s}" | none => .ok ""
        let b ← printBlock indentLevel body
        .ok (indent indentLevel s!"for {var}{tyStr} in {range} {b.trim}")
    | .returnSt none => .ok (indent indentLevel "return;")
    | .returnSt (some value) => do
        let v ← printExpression value
        .ok (indent indentLevel s!"return {v};")
    | .assert cond msg? => do
        let c ← printExpression cond
        match msg? with
        | none => .ok (indent indentLevel s!"assert({c});")
        | some msg => do
            let m ← printExpression msg
            .ok (indent indentLevel s!"assert_eq({c}, {m});")
end

def printAnnotation (a : Annotation) : String := s!"@{a.name}"

def printInput (i : Input) : Except LowerError String := do
  let ty ← printType i.ty
  .ok s!"{i.name}: {ty}"

def printFunction (indentLevel : Nat) (f : Function) : Except LowerError String := do
  let keyword := match f.variant with
    | .fn => "fn"
    | .finalFn => "final fn"
    | .entryPoint => "fn"
    | .view => "view fn"
  let params ← f.input.mapM printInput
  let paramsStr := String.intercalate ", " params.toList
  let ret ← printType f.outputType
  let annos := f.annotations.map printAnnotation
  let header := if annos.isEmpty then
    s!"{keyword} {f.identifier}({paramsStr}) -> {ret} {{"
  else
    String.intercalate "\n" annos.toList ++ "\n" ++ s!"{keyword} {f.identifier}({paramsStr}) -> {ret} {{"
  let body ← printBlock 0 f.block
  -- Replace the leading '{' of the body block with the header to keep indentation.
  let bodyLines := body.split (· == '\n')
  let combined := String.intercalate "\n" ([indent indentLevel header] ++ bodyLines.tail)
  .ok combined
  where
    split (p : Char → Bool) (s : String) : List String :=
      let rec loop (i : Nat) (acc : List String) (cur : String) : List String :=
        if h : i < s.length then
          let c := s.get ⟨i, h⟩
          if p c then
            loop (i + 1) (cur :: acc) ""
          else
            loop (i + 1) acc (cur.push c)
        else
          cur :: acc
      loop 0 [] ""

def printMapping (indentLevel : Nat) (m : Mapping) : Except LowerError String := do
  let k ← printType m.keyType
  let v ← printType m.valueType
  .ok (indent indentLevel s!"mapping {m.identifier}: {k} => {v};")

def printConstructor (indentLevel : Nat) (c : Constructor) : Except LowerError String := do
  let annos := c.annotations.map printAnnotation
  let header := if annos.isEmpty then
    "constructor() {"
  else
    String.intercalate "\n" annos.toList ++ "\n" ++ "constructor() {"
  let body ← printBlock 0 c.block
  let bodyLines := body.split (· == '\n')
  let combined := String.intercalate "\n" ([indent indentLevel header] ++ bodyLines.tail)
  .ok combined
  where
    split (p : Char → Bool) (s : String) : List String :=
      let rec loop (i : Nat) (acc : List String) (cur : String) : List String :=
        if h : i < s.length then
          let c := s.get ⟨i, h⟩
          if p c then
            loop (i + 1) (cur :: acc) ""
          else
            loop (i + 1) acc (cur.push c)
        else
          cur :: acc
      loop 0 [] ""

def printProgramScope (indentLevel : Nat) (scope : ProgramScope) : Except LowerError String := do
  let mappingLines ← scope.mappings.mapM (fun (_, m) => printMapping indentLevel m)
  let functionLines ← scope.functions.mapM (fun (_, f) => printFunction indentLevel f)
  let constructorLines ← match scope.constructor with
    | none => .ok #[]
    | some c => do let s ← printConstructor indentLevel c; .ok #[s]
  let all := mappingLines ++ constructorLines ++ functionLines
  let body := String.intercalate "\n\n" all.toList
  .ok s!"program {scope.programId} {{\n{body}\n{indent indentLevel "}"}"

def printProgram (p : Program) : Except LowerError String := do
  if p.scopes.size != 1 then
    .error { message := "Leo printer currently supports exactly one program scope" }
  else
    let (_, scope) := p.scopes[0]!
    printProgramScope 0 scope

def printProgramToString (p : Program) : Except LowerError String := printProgram p

end ProofForge.Compiler.Leo.Printer
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.Printer`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/Printer.lean
git commit -m "feat(leo-ast): add AST to Leo 4.0.2 source printer"
```

---

## Task 13: Create `ProofForge/Compiler/Leo/Emit.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo/Emit.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.IR.Contract
import ProofForge.Compiler.Leo.AST
import ProofForge.Compiler.Leo.Printer

namespace ProofForge.Compiler.Leo.Emit

open ProofForge.IR
open ProofForge.Compiler.Leo.AST

/-- Map a portable IR value type to a Leo type. -/
def valueType (t : ValueType) : Except LowerError Type :=
  match t with
  | .unit => .ok .unit
  | .bool => .ok .boolean
  | .u32 => .ok (.integer .u32)
  | .u64 => .ok (.integer .u64)
  | .hash => .error { message := "Leo emitter does not support Hash" }
  | .fixedArray _ _ => .error { message := "Leo emitter does not support fixed arrays" }
  | .structType name => .ok (.composite name)

/-- Map a portable IR literal to a Leo literal. -/
def literal : Literal → Leo.AST.Literal
  | .u32 value => .integer .u32 value
  | .u64 value => .integer .u64 value
  | .bool value => .boolean value
  | .hash4 _ _ _ _ => .none

mutual
  /-- Map a portable IR expression to a Leo expression. -/
  partial def expr : Expr → Except LowerError Expression
    | .literal lit => .ok (.literal (literal lit))
    | .local name => .ok (.identifier name)
    | .add lhs rhs => do .binary ⟨.add, ← expr lhs, ← expr rhs⟩
    | .sub lhs rhs => do .binary ⟨.sub, ← expr lhs, ← expr rhs⟩
    | .mul lhs rhs => do .binary ⟨.mul, ← expr lhs, ← expr rhs⟩
    | .div lhs rhs => do .binary ⟨.div, ← expr lhs, ← expr rhs⟩
    | .mod lhs rhs => do .binary ⟨.mod, ← expr lhs, ← expr rhs⟩
    | .eq lhs rhs => do .binary ⟨.eq, ← expr lhs, ← expr rhs⟩
    | .ne lhs rhs => do .binary ⟨.neq, ← expr lhs, ← expr rhs⟩
    | .lt lhs rhs => do .binary ⟨.lt, ← expr lhs, ← expr rhs⟩
    | .le lhs rhs => do .binary ⟨.lte, ← expr lhs, ← expr rhs⟩
    | .gt lhs rhs => do .binary ⟨.gt, ← expr lhs, ← expr rhs⟩
    | .ge lhs rhs => do .binary ⟨.gte, ← expr lhs, ← expr rhs⟩
    | .boolAnd lhs rhs => do .binary ⟨.and, ← expr lhs, ← expr rhs⟩
    | .boolOr lhs rhs => do .binary ⟨.or, ← expr lhs, ← expr rhs⟩
    | .boolNot value => do .unary ⟨.not, ← expr value⟩
    | .cast value target => do .cast ⟨← expr value, ← valueType target⟩
    | .effect (.storageScalarRead stateId) =>
        .ok (.call ⟨#["Mapping", "get_or_use"], #[], #[.identifier stateId, .literal (.integer .u64 0), .literal (.integer .u64 0)]⟩)
    | .effect ef =>
        .error { message := s!"Leo emitter does not support effect: {repr ef}" }
    | other =>
        .error { message := s!"Leo emitter does not support expression: {repr other}" }

  /-- Map a portable IR statement to Leo statements. -/
  partial def statement : Statement → Except LowerError (Array Statement)
    | .letBind name ty value => do
        let v ← expr value
        .ok #[.definition (.single name) (some (← valueType ty)) v]
    | .letMutBind name ty value => do
        let v ← expr value
        .ok #[.definition (.single name) (some (← valueType ty)) v]
    | .effect (.storageScalarWrite stateId value) => do
        let v ← expr value
        .ok #[.expression (.call ⟨#["Mapping", "set"], #[], #[.identifier stateId, .literal (.integer .u64 0), v]⟩)]
    | .effect ef =>
        .error { message := s!"Leo emitter does not support effect statement: {repr ef}" }
    | .«return» value => do
        let v ← expr value
        .ok #[.returnSt (some v)]
    | other =>
        .error { message := s!"Leo emitter does not support statement: {repr other}" }
end

def statements (body : Array Statement) : Except LowerError (Array Statement) := do
  let mut result := #[]
  for stmt in body do
    let ss ← statement stmt
    result := result ++ ss
  .ok result

/-- Build a Leo mapping from a scalar U64 state declaration. -/
def stateMapping (state : StateDecl) : Except LowerError Mapping :=
  match state.kind with
  | .scalar =>
      match state.type with
      | .u64 => .ok { identifier := state.id, keyType := .integer .u64, valueType := .integer .u64 }
      | other => .error { message := s!"Leo emitter scalar state only supports U64, got {other.name}" }
  | .map _ _ => .error { message := s!"Leo emitter does not support map state `{state.id}`" }
  | .array _ => .error { message := s!"Leo emitter does not support array state `{state.id}`" }

/-- Build the @noupgrade constructor required by Leo 4.0.2. -/
def constructor : Constructor :=
  { annotations := #[{ name := "noupgrade" }], block := { statements := #[] } }

/-- Build an entrypoint function that returns a future and wraps its body in async. -/
def entrypointFunction (ep : Entrypoint) : Except LowerError Function := do
  let bodyStmts ← statements ep.body
  let asyncBlock : Block := { statements := bodyStmts }
  let retExpr : Expression := .async asyncBlock
  let returnStmt : Statement := .returnSt (some retExpr)
  let block : Block := { statements := #[returnStmt] }
  .ok {
    annotations := #[],
    variant := .entryPoint,
    identifier := ep.name,
    constParameters := #[],
    input := #[],
    output := #[],
    outputType := .future { inputs := #[], output := .unit },
    block := block
  }

/-- Emit a full IR module as a Leo Program AST. -/
def emitModule (module : Module) : Except LowerError Program := do
  let mappings ← module.state.mapM stateMapping
  let functions ← module.entrypoints.mapM entrypointFunction
  let scope : ProgramScope := {
    programId := module.name.toLower ++ ".aleo",
    parents := #[],
    consts := #[],
    composites := #[],
    mappings := mappings.map (fun m => (m.identifier, m)),
    storageVariables := #[],
    functions := functions.map (fun f => (f.identifier, f)),
    interfaces := #[],
    constructor := some constructor
  }
  .ok {
    imports := #[],
    scopes := #[(module.name.toLower, scope)]
  }

/-- Convenience: emit and print in one step. -/
def renderModule (module : Module) : Except LowerError String := do
  let p ← emitModule module
  ProofForge.Compiler.Leo.Printer.printProgram p

end ProofForge.Compiler.Leo.Emit
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo.Emit`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo/Emit.lean
git commit -m "feat(leo-ast): add IR to Leo AST emitter"
```

---

## Task 14: Create `ProofForge/Compiler/Leo.lean`

**Files:**
- Create: `ProofForge/Compiler/Leo.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.Compiler.Leo.AST
import ProofForge.Compiler.Leo.Printer
import ProofForge.Compiler.Leo.Emit

namespace ProofForge.Compiler.Leo
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Compiler.Leo`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/Leo.lean
git commit -m "feat(leo-ast): add Leo compiler namespace root"
```

---

## Task 15: Refactor `ProofForge/Backend/Aleo/IR.lean`

**Files:**
- Modify: `ProofForge/Backend/Aleo/IR.lean`

- [ ] **Step 1: Replace the file contents**

```lean
import ProofForge.IR.Contract
import ProofForge.Compiler.Leo.Emit

namespace ProofForge.Backend.Aleo.IR

open ProofForge.IR

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String := err.message

def capabilityError (err : ProofForge.Target.CapabilityError) : LowerError :=
  { message := err.render }

/-- Render the full module by lowering to the Leo AST and printing it. -/
def renderModule (module : Module) : Except LowerError String :=
  match ProofForge.Compiler.Leo.Emit.renderModule module with
  | .ok s => .ok s
  | .error e => .error { message := e.message }

end ProofForge.Backend.Aleo.IR
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.Backend.Aleo.IR`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Backend/Aleo/IR.lean
git commit -m "refactor(aleo): use Leo AST pipeline instead of direct string emission"
```

---

## Task 16: Verify the full build and smoke test

**Files:**
- Test: `./scripts/aleo/counter-smoke.sh`

- [ ] **Step 1: Build the project**

Run: `lake build`

Expected: `Build completed successfully`.

- [ ] **Step 2: Run the Counter smoke test**

Run: `./scripts/aleo/counter-smoke.sh`

Expected:
- Diff against `Examples/Backend/Aleo/Counter.golden.leo` passes.
- `leo build` succeeds.
- `leo test` reports `1 / 1 tests passed`.
- Artifact metadata validates.

- [ ] **Step 3: Commit (only if smoke passes)**

```bash
git commit -m "test(aleo): verify Leo AST pipeline with counter-smoke"
```

---

## Task 17: Update documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-07-01-aleo-leo-design.md` (Section 5.2, Section 6.2)
- Modify: `docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md` (corresponding sections)

- [ ] **Step 1: Update Section 5.2 architecture in the English spec**

Replace the current pipeline paragraph with:

```text
ProofForge.IR.Examples.Counter.module
  -> ProofForge.Compiler.Leo.Emit.emitModule
  -> ProofForge.Compiler.Leo.Printer.printProgram
  -> Counter.leo
  -> scripts/aleo/write-leo-package.py
  -> build/aleo/counter/{leo.toml, src/main.leo}
  -> leo build
  -> .aleo instructions + ABI JSON
  -> leo test
  -> proof-forge-artifact.json
```

- [ ] **Step 2: Update Section 6.2 lowering rules in the English spec**

Add the following note after the existing table:

> The actual lowering is implemented via `ProofForge.Compiler.Leo.Emit`, which first translates the IR into a structured Leo AST (`ProofForge.Compiler.Leo.AST`) and then uses `ProofForge.Compiler.Leo.Printer` to emit Leo 4.0.2 compatible source. The AST mirrors `ProvableHQ/leo crates/ast/src/` (v4.3.2) while the printer downgrades `async { }` / `Future<Fn(...)>` to `final { }` / `Final` for the local toolchain.

- [ ] **Step 3: Apply the same updates to the Chinese spec**

Translate the two changes above into Chinese and edit `docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md`.

- [ ] **Step 4: Verify docs render correctly**

Run: `git diff --stat docs/superpowers/specs docs/zh/superpowers/specs`

Expected: two spec files show the expected changes.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-07-01-aleo-leo-design.md docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md
git commit -m "docs(aleo): document Leo AST pipeline in spike specs"
```

---

## Plan self-review

### Spec coverage
- Section 3 AST structure → Tasks 1–11.
- Section 4.2 IR → AST rules → Task 13.
- Section 4.2 AST → String rules → Task 12.
- Section 5 file changes → Tasks 1–15.
- Section 6 acceptance criteria → Task 16.
- Section 9 doc updates → Task 17.

### Placeholder scan
- No TBD/TODO.
- Every step contains exact file paths and full code.
- Every task ends with a verification command and a commit command.

### Type consistency
- `LowerError` defined in `AST.Core.lean` and used consistently across `Printer`, `Emit`, and `Backend.Aleo.IR`.
- `Expression.call` uses `CallExpression` with a `Path` (`Array Identifier`).
- `Function.outputType` is `Type`.
- `Program.scopes` and `ProgramScope` fields match the definitions in Tasks 10 and 11.
