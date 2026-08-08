/-
  Aleo Instructions Schema V1 — engineering AST for the official Aleo
  Instructions register IR (Leo → Instructions → AVM).

  Authority (engineering):
  * Official docs: https://docs.aleo.org/build/aleo-instructions/overview
  * Grammar pointer: https://github.com/ProvableHQ/grammars (Aleo Instructions ABNF)
  * Golden authority: locked Leo 4.0.2 offline compile of product Counter
    (`aleo-leo-4.0.2-u64-compile-v1` → `{id}.compiled.aleo`)
  * Pin file: `testdata/golden/aleo-instructions-v1/counter.compiled.aleo`

  This module is **not** a full opcode surface, **not** snarkVM Program
  objects, and **not** formal semantics. Unknown opcodes/shapes fail closed
  at TextCodec decode. Plan→Instructions: Counter MVP = ALEO-IR-2;
  if/match/bounded-for control flow = ALEO-IR-3; multi-leaf Map/Option/Array
  + narrow UInt widths = ALEO-IR-4 (`LowerPlanV1`).
-/
namespace ProofForgeV2.Targets.Aleo.Instructions.SchemaV1

/-- Engineering schema id for this Instructions subset. -/
def schemaIdV1 : String := "proof-forge.aleo-instructions.v1"

/-- Tool Lock Leo version used as golden compiler pin. -/
def goldenLeoVersionV1 : String := "4.0.2"

/-- Visibility on typed register annotations (`as u64.public`).
    Constructors avoid Lean reserved words (`private`). -/
inductive VisibilityV1 where
  | public_
  | private_
  | constant_
  deriving DecidableEq, Repr, Inhabited

def VisibilityV1.render : VisibilityV1 → String
  | .public_ => "public"
  | .private_ => "private"
  | .constant_ => "constant"

def VisibilityV1.parse? : String → Option VisibilityV1
  | "public" => some .public_
  | "private" => some .private_
  | "constant" => some .constant_
  | _ => none

/-- Scalar / primitive base types admitted in the IR-1 subset. -/
inductive BaseTypeV1 where
  | u8 | u16 | u32 | u64 | u128
  | i8 | i16 | i32 | i64 | i128
  | boolean
  | field | group | address | scalar
  deriving DecidableEq, Repr, Inhabited

def BaseTypeV1.render : BaseTypeV1 → String
  | .u8 => "u8" | .u16 => "u16" | .u32 => "u32" | .u64 => "u64" | .u128 => "u128"
  | .i8 => "i8" | .i16 => "i16" | .i32 => "i32" | .i64 => "i64" | .i128 => "i128"
  | .boolean => "boolean"
  | .field => "field" | .group => "group" | .address => "address" | .scalar => "scalar"

def BaseTypeV1.parse? : String → Option BaseTypeV1
  | "u8" => some .u8 | "u16" => some .u16 | "u32" => some .u32
  | "u64" => some .u64 | "u128" => some .u128
  | "i8" => some .i8 | "i16" => some .i16 | "i32" => some .i32
  | "i64" => some .i64 | "i128" => some .i128
  | "boolean" => some .boolean
  | "field" => some .field | "group" => some .group
  | "address" => some .address | "scalar" => some .scalar
  | _ => none

/-- Type annotation on input/output / mapping key·value. Future types omit
    visibility (Leo 4.0.2 Counter golden: `as counter.aleo/initialize.future`). -/
inductive TypeAnnV1 where
  | base (ty : BaseTypeV1) (vis : VisibilityV1)
  | future (programId : String) (functionName : String)
  deriving DecidableEq, Repr, Inhabited

def TypeAnnV1.render : TypeAnnV1 → String
  | .base ty vis => s!"{ty.render}.{vis.render}"
  | .future programId functionName => s!"{programId}/{functionName}.future"

/-- Register `rN`. -/
structure RegisterV1 where
  index : Nat
  deriving DecidableEq, Repr, Inhabited

def RegisterV1.render (r : RegisterV1) : String :=
  s!"r{r.index}"

/-- Operand: register, typed literal spelling, or bare identifier (`edition`). -/
inductive OperandV1 where
  | register (r : RegisterV1)
  | literal (spelling : String)
  | identifier (name : String)
  deriving DecidableEq, Repr, Inhabited

def OperandV1.render : OperandV1 → String
  | .register r => r.render
  | .literal s => s
  | .identifier n => n

/-- Instruction subset: Counter golden (IR-1/2) + control-flow ops from
    locked Leo 4.0.2 compile of if/match/bounded-for (IR-3) + scalar cast
    for narrow shift counts (IR-4). Additional opcodes still require
    golden/test evidence. -/
inductive InstructionV1 where
  /-- `input rN as <typeAnn>;` -/
  | input (reg : RegisterV1) (ty : TypeAnnV1)
  /-- `output rN as <typeAnn>;` -/
  | output (reg : RegisterV1) (ty : TypeAnnV1)
  /-- `async <name> rA … into rD;` (zero or more register args) -/
  | asyncCall (name : String) (args : Array RegisterV1) (dest : RegisterV1)
  /-- Unary: `not src into dest;` (extend via golden) -/
  | unary (op : String) (src : OperandV1) (dest : RegisterV1)
  /-- Binary: `add`/`sub`/`gt`/`lt`/`lte`/`is.eq`/… `a b into dest;` -/
  | binary (op : String) (left : OperandV1) (right : OperandV1) (dest : RegisterV1)
  /-- Ternary select: `ternary cond thenV elseV into dest;` (IR-3) -/
  | ternary (cond thenV elseV : OperandV1) (dest : RegisterV1)
  /-- Scalar cast: `cast src into dest as <typeAnn>;` (IR-4 shift count).
      Constructor named `typeCast` to avoid clashing with Lean core `cast`. -/
  | typeCast (src : OperandV1) (dest : RegisterV1) (ty : TypeAnnV1)
  /-- `assert.eq left right;` -/
  | assertEq (left : OperandV1) (right : OperandV1)
  /-- `get.or_use mapping[key] default into dest;` -/
  | getOrUse (mapping : String) (key : OperandV1) (default : OperandV1) (dest : RegisterV1)
  /-- `set value into mapping[key];` -/
  | set (value : OperandV1) (mapping : String) (key : OperandV1)
  /-- Control: `branch.eq left right to label;` (IR-3; Leo 4.0.2 if/for) -/
  | branchEq (left right : OperandV1) (label : String)
  /-- Control: `position label;` (IR-3 branch target) -/
  | position (label : String)
  deriving DecidableEq, Repr, Inhabited

/-- Mapping declaration (public state table). -/
structure MappingDeclV1 where
  name : String
  keyType : TypeAnnV1
  valueType : TypeAnnV1
  deriving DecidableEq, Repr, Inhabited

/-- Transition / proof function (may contain `async` + `output` of future). -/
structure FunctionDeclV1 where
  name : String
  body : Array InstructionV1
  deriving DecidableEq, Repr, Inhabited

/-- On-chain finalize block paired with a transition. -/
structure FinalizeDeclV1 where
  name : String
  body : Array InstructionV1
  deriving DecidableEq, Repr, Inhabited

/-- Program constructor (edition assert in Leo 4.0.2). -/
structure ConstructorDeclV1 where
  body : Array InstructionV1
  deriving DecidableEq, Repr, Inhabited

/-- Top-level program item (source order preserved). -/
inductive ItemV1 where
  | mapping (m : MappingDeclV1)
  | function (f : FunctionDeclV1)
  | finalize (f : FinalizeDeclV1)
  | constructor (c : ConstructorDeclV1)
  deriving DecidableEq, Repr, Inhabited

/-- Aleo Instructions program (`.aleo` instructions text model).
    `name` includes the `.aleo` suffix (`counter.aleo`). -/
structure ProgramV1 where
  name : String
  items : Array ItemV1
  deriving DecidableEq, Repr, Inhabited

/-- Hand-built Counter Instructions program ≡ locked-leo product golden
    (`testdata/golden/aleo-instructions-v1/counter.compiled.aleo`). -/
def counterProgramV1 : ProgramV1 := {
  name := "counter.aleo"
  items := #[
    .mapping {
      name := "pf_state_0"
      keyType := .base .u8 .public_
      valueType := .base .u64 .public_
    },
    .mapping {
      name := "initialized"
      keyType := .base .u8 .public_
      valueType := .base .boolean .public_
    },
    .function {
      name := "initialize"
      body := #[
        .input ⟨0⟩ (.base .u64 .public_),
        .asyncCall "initialize" #[⟨0⟩] ⟨1⟩,
        .output ⟨1⟩ (.future "counter.aleo" "initialize")
      ]
    },
    .finalize {
      name := "initialize"
      body := #[
        .input ⟨0⟩ (.base .u64 .public_),
        .getOrUse "initialized" (.literal "0u8") (.literal "false") ⟨1⟩,
        .unary "not" (.register ⟨1⟩) ⟨2⟩,
        .assertEq (.register ⟨2⟩) (.literal "true"),
        .set (.register ⟨0⟩) "pf_state_0" (.literal "0u8"),
        .set (.literal "true") "initialized" (.literal "0u8")
      ]
    },
    .function {
      name := "increment"
      body := #[
        .input ⟨0⟩ (.base .u64 .public_),
        .asyncCall "increment" #[⟨0⟩] ⟨1⟩,
        .output ⟨1⟩ (.future "counter.aleo" "increment")
      ]
    },
    .finalize {
      name := "increment"
      body := #[
        .input ⟨0⟩ (.base .u64 .public_),
        .getOrUse "pf_state_0" (.literal "0u8") (.literal "0u64") ⟨1⟩,
        .binary "add" (.register ⟨1⟩) (.register ⟨0⟩) ⟨2⟩,
        .set (.register ⟨2⟩) "pf_state_0" (.literal "0u8"),
        .getOrUse "pf_state_0" (.literal "0u8") (.literal "0u64") ⟨3⟩
      ]
    },
    .constructor {
      body := #[
        .assertEq (.identifier "edition") (.literal "0u16")
      ]
    }
  ]
}

end ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
