import ProofForge.Backend.WasmNear.IR
import ProofForge.IR.Contract

namespace ProofForge.Tests.WasmNearDiagnostics

open ProofForge.IR

/-!
# wasm-near IR diagnostics

Each error case constructs a portable `Module` and asserts that the
wasm-near Rust sourcegen backend rejects it with a specific diagnostic.
Positive cases assert that a valid module renders and that the generated
Rust source contains the expected near-sdk-rs constructs.
-/

-- ---------------------------------------------------------------------------
-- Shared state declarations
-- ---------------------------------------------------------------------------

def markerState : StateDecl := {
  id := "marker"
  kind := .scalar
  type := .u64
}

def countState : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def u64MapState : StateDecl := {
  id := "balances"
  kind := .map .u64 16
  type := .u64
}

-- ---------------------------------------------------------------------------
-- Entrypoint / module builders
-- ---------------------------------------------------------------------------

def unitEntrypoint (name : String) (body : Array Statement := #[]) : Entrypoint := {
  name := name
  returns := .unit
  body := body
}

def returnEntrypoint (name : String) (returns : ValueType) (body : Array Statement) : Entrypoint := {
  name := name
  returns := returns
  body := body
}

def paramEntrypoint (name : String) (params : Array (String × ValueType)) (returns : ValueType)
    (body : Array Statement) : Entrypoint := {
  name := name
  params := params
  returns := returns
  body := body
}

def module1 (name : String) (state : Array StateDecl) (entrypoint : Entrypoint) : Module := {
  name := name
  state := state
  entrypoints := #[entrypoint]
}

-- ---------------------------------------------------------------------------
-- Target/backend boundary cases.
-- ---------------------------------------------------------------------------

def conditionalModule : Module :=
  module1 "BadConditional" #[markerState] <|
    unitEntrypoint "bad" #[
      .ifElse (.literal (.bool true)) #[] #[]
    ]

def boundedLoopModule : Module :=
  module1 "BadLoop" #[markerState] <|
    unitEntrypoint "bad" #[
      .boundedFor "i" 0 1 #[]
    ]

def fixedArrayModule : Module :=
  module1 "BadFixedArray" #[markerState] <|
    paramEntrypoint "bad" #[("xs", .fixedArray .u64 1)] .unit #[]

def structModule : Module := {
  name := "BadStruct"
  structs := #[{ name := "Point", fields := #[{ id := "x", type := .u64 }] }]
  state := #[markerState]
  entrypoints := #[paramEntrypoint "bad" #[("point", .structType "Point")] .unit #[]]
}

def storageArrayModule : Module := {
  name := "BadStorageArray"
  state := #[{ id := "values", kind := .array 3, type := .u64 }]
  entrypoints := #[unitEntrypoint "bad"]
}

def crosscallBody : Array Statement := #[.return (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[])]

def crosscallModule : Module :=
  module1 "BadCrosscall" #[markerState] <|
    returnEntrypoint "bad" .u64 crosscallBody

def nearPromiseBody : Array Statement := #[.return .nearPromiseResultsCount]

def nearPromiseModule : Module :=
  module1 "BadNearPromise" #[markerState] <|
    returnEntrypoint "bad" .u64 nearPromiseBody

-- ---------------------------------------------------------------------------
-- State validation cases
-- ---------------------------------------------------------------------------

def unitScalarStateModule : Module := {
  name := "BadUnitScalar"
  state := #[{ id := "flag", kind := .scalar, type := .unit }]
  entrypoints := #[unitEntrypoint "bad"]
}

def zeroCapacityMapModule : Module := {
  name := "BadZeroCapacity"
  state := #[{ id := "balances", kind := .map .u64 0, type := .u64 }]
  entrypoints := #[unitEntrypoint "bad"]
}

def u32KeyMapModule : Module := {
  name := "BadMapShape"
  state := #[{ id := "balances", kind := .map .u32 16, type := .u64 }]
  entrypoints := #[unitEntrypoint "bad"]
}

-- ---------------------------------------------------------------------------
-- Entrypoint ABI cases
-- ---------------------------------------------------------------------------

def unitParameterModule : Module :=
  module1 "BadUnitParameter" #[markerState] <|
    paramEntrypoint "set" #[("value", .unit)] .unit #[]

-- ---------------------------------------------------------------------------
-- Identifier validation cases
-- ---------------------------------------------------------------------------

def invalidModuleName : Module :=
  module1 "1bad" #[markerState] (unitEntrypoint "bad")

def reservedEntrypointNameModule : Module :=
  module1 "BadReservedName" #[markerState] (unitEntrypoint "fn")

def reservedLocalNameModule : Module :=
  module1 "BadReservedLocal" #[markerState] <|
    unitEntrypoint "bad" #[
      .letBind "fn" .u64 (.literal (.u64 1))
    ]

def duplicateStateIdModule : Module := {
  name := "BadDuplicateState"
  state := #[countState, countState]
  entrypoints := #[unitEntrypoint "bad"]
}

-- ---------------------------------------------------------------------------
-- Type checking / lowering cases
-- ---------------------------------------------------------------------------

def missingReturnModule : Module :=
  module1 "BadMissingReturn" #[markerState] <|
    returnEntrypoint "bad" .u64 #[
      .letBind "x" .u64 (.literal (.u64 1))
    ]

def returnTypeMismatchModule : Module :=
  module1 "BadReturnMismatch" #[markerState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.literal (.u32 1))
    ]

def hashReturnMismatchModule : Module :=
  module1 "BadHashReturn" #[markerState] <|
    returnEntrypoint "bad" .hash #[
      .return (.literal (.u64 1))
    ]

def arithmeticMismatchModule : Module :=
  module1 "BadArith" #[markerState] <|
    unitEntrypoint "bad" #[
      .letBind "x" .u64 (.add (.literal (.u64 1)) (.literal (.u32 2)))
    ]

def castMismatchModule : Module :=
  module1 "BadCast" #[markerState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.cast (.literal (.hash4 1 2 3 4)) .u64)
    ]

def unknownLocalModule : Module :=
  module1 "BadUnknownLocal" #[markerState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.local "x")
    ]

def immutableAssignModule : Module :=
  module1 "BadImmutableAssign" #[markerState] <|
    unitEntrypoint "bad" #[
      .letBind "x" .u64 (.literal (.u64 1)),
      .assign (.local "x") (.literal (.u64 2))
    ]

def immutableAssignOpModule : Module :=
  module1 "BadImmutableAssignOp" #[markerState] <|
    unitEntrypoint "bad" #[
      .letBind "x" .u64 (.literal (.u64 1)),
      .assignOp (.local "x") .add (.literal (.u64 2))
    ]

def invalidAssignTargetModule : Module :=
  module1 "BadAssignTarget" #[markerState] <|
    unitEntrypoint "bad" #[
      .assign (.add (.literal (.u64 1)) (.literal (.u64 2))) (.literal (.u64 3))
    ]

-- ---------------------------------------------------------------------------
-- Effect expression/statement misuse cases
-- ---------------------------------------------------------------------------

def scalarWriteExprModule : Module :=
  module1 "BadScalarWriteExpr" #[countState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.effect (.storageScalarWrite "count" (.literal (.u64 1))))
    ]

def scalarReadStmtModule : Module :=
  module1 "BadScalarReadStmt" #[countState] <|
    unitEntrypoint "bad" #[
      .effect (.storageScalarRead "count")
    ]

def scalarAssignOpModule : Module :=
  module1 "BadScalarAssignOp" #[countState] <|
    unitEntrypoint "bad" #[
      .effect (.storageScalarAssignOp "count" .add (.literal (.u64 1)))
    ]

def mapContainsStmtModule : Module :=
  module1 "BadMapContainsStmt" #[u64MapState] <|
    unitEntrypoint "bad" #[
      .effect (.storageMapContains "balances" (.literal (.u64 1)))
    ]

def storagePathEmptyModule : Module :=
  module1 "BadPathEmpty" #[u64MapState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.effect (.storagePathRead "balances" #[]))
    ]

def storagePathNestedModule : Module :=
  module1 "BadPathNested" #[u64MapState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.effect (.storagePathRead "balances"
        #[.mapKey (.literal (.u64 1)), .mapKey (.literal (.u64 2))]))
    ]

def contextReadStmtModule : Module :=
  module1 "BadContextStmt" #[markerState] <|
    unitEntrypoint "bad" #[
      .effect (.contextRead .userId)
    ]

def eventExprModule : Module :=
  module1 "BadEventExpr" #[markerState] <|
    returnEntrypoint "bad" .u64 #[
      .return (.effect (.eventEmit "Seen" #[("value", .literal (.u64 1))]))
    ]

def eventEmptyNameModule : Module :=
  module1 "BadEventEmptyName" #[markerState] <|
    unitEntrypoint "bad" #[
      .effect (.eventEmit "" #[("value", .literal (.u64 1))])
    ]

def nativeValueModule : Module :=
  module1 "BadNativeValue" #[markerState] <|
    returnEntrypoint "bad" .u64 #[
      .return .nativeValue
    ]

def unknownScalarStateModule : Module :=
  module1 "BadUnknownScalar" #[] <|
    returnEntrypoint "bad" .u64 #[
      .return (.effect (.storageScalarRead "missing"))
    ]

-- ---------------------------------------------------------------------------
-- Positive (success) cases
-- ---------------------------------------------------------------------------

def incrementBody : Array Statement := #[
  .letBind "current" .u64 (.effect (.storageScalarRead "count")),
  .effect (.storageScalarWrite "count" (.add (.local "current") (.literal (.u64 1))))
]

def getBody : Array Statement := #[.return (.effect (.storageScalarRead "count"))]

def counterModule : Module := {
  name := "Counter"
  state := #[countState]
  entrypoints := #[
    unitEntrypoint "increment" incrementBody,
    returnEntrypoint "get" .u64 getBody
  ]
}

def mapSetBody : Array Statement := #[.effect (.storageMapSet "balances" (.local "k") (.local "v"))]

def mapGetBody : Array Statement := #[.return (.effect (.storageMapGet "balances" (.local "k")))]

def mapModule : Module := {
  name := "Ledger"
  state := #[u64MapState]
  entrypoints := #[
    paramEntrypoint "set" #[("k", .u64), ("v", .u64)] .unit mapSetBody,
    paramEntrypoint "get" #[("k", .u64)] .u64 mapGetBody
  ]
}

def callerBody : Array Statement := #[.return (.effect (.contextRead .userId))]

def commitBody : Array Statement := #[.return (.hash (.literal (.hash4 1 2 3 4)))]

def hashContextModule : Module := {
  name := "Hasher"
  state := #[markerState]
  entrypoints := #[
    returnEntrypoint "caller" .u64 callerBody,
    returnEntrypoint "commit" .hash commitBody
  ]
}

def tickBody : Array Statement := #[
  .letMutBind "acc" .u64 (.literal (.u64 0)),
  .assignOp (.local "acc") .mul (.literal (.u64 2)),
  .assert (.gt (.local "acc") (.literal (.u64 0))) "accumulator must be positive"
]

def mutableLocalModule : Module := {
  name := "Accum"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "tick" tickBody]
}

-- ---------------------------------------------------------------------------
-- Test harness
-- ---------------------------------------------------------------------------

def renderError? (module : Module) : Option String :=
  match ProofForge.Backend.WasmNear.IR.renderModule module with
  | .ok _ => none
  | .error err => some err.render

def renderOk? (module : Module) : Option String :=
  match ProofForge.Backend.WasmNear.IR.renderModule module with
  | .ok src => some src
  | .error _ => none

def cases : Array (String × Module × String) := #[
  ("conditional sourcegen unsupported", conditionalModule,
    "conditional branches are not supported by wasm-near IR v0"),
  ("bounded loop sourcegen unsupported", boundedLoopModule,
    "bounded for loops are not supported by wasm-near IR v0"),
  ("fixed array ABI unsupported", fixedArrayModule,
    "entrypoint `bad` parameter `xs` uses `Array<U64,1>`; wasm-near IR v0 ABI parameters must use U32, U64, Bool, Hash, or Address"),
  ("struct ABI unsupported", structModule,
    "entrypoint `bad` parameter `point` uses `Point`; wasm-near IR v0 ABI parameters must use U32, U64, Bool, Hash, or Address"),
  ("storage array sourcegen unsupported", storageArrayModule,
    "state `values` is storage.array; wasm-near IR v0 does not lower portable array storage"),
  ("crosscall Rust sourcegen unsupported", crosscallModule,
    "cross-contract calls are not supported by wasm-near Rust sourcegen v0"),
  ("near promise Rust sourcegen unsupported", nearPromiseModule,
    "NEAR promise API is not supported by wasm-near Rust sourcegen v0"),
  ("unit scalar state unsupported", unitScalarStateModule,
    "state `flag` has unsupported wasm-near IR v0 scalar type `Unit`; only U32, U64, Bool, and Hash are supported"),
  ("zero capacity map unsupported", zeroCapacityMapModule,
    "map state `balances` must have non-zero capacity"),
  ("map shape unsupported", u32KeyMapModule,
    "map state `balances` has unsupported wasm-near IR v0 type `Map<U32, U64, 16>`; only Map<U64|Hash, U32|U64|Bool|Hash, N> is supported"),
  ("unit parameter unsupported", unitParameterModule,
    "entrypoint `set` parameter `value` uses `Unit`; wasm-near IR v0 ABI parameters must use U32, U64, Bool, Hash, or Address"),
  ("invalid module name", invalidModuleName,
    "module name `1bad` is not a valid Rust identifier; identifiers must start with an ASCII letter or `_` and contain only ASCII letters, digits, or `_`"),
  ("reserved entrypoint name", reservedEntrypointNameModule,
    "entrypoint name `fn` is a reserved Rust keyword"),
  ("reserved local name", reservedLocalNameModule,
    "local name in entrypoint `bad` `fn` is a reserved Rust keyword"),
  ("duplicate state id", duplicateStateIdModule,
    "duplicate state id `count`"),
  ("missing return", missingReturnModule,
    "entrypoint `bad` returns `U64` but does not end with a return statement"),
  ("return type mismatch", returnTypeMismatchModule,
    "return value expected `U64`, got `U32`"),
  ("hash return type mismatch", hashReturnMismatchModule,
    "return value expected `Hash`, got `U64`"),
  ("arithmetic operand type mismatch", arithmeticMismatchModule,
    "addition right operand expected `U64`, got `U32`"),
  ("cast type mismatch", castMismatchModule,
    "cast from `Hash` to `U64` is not supported by wasm-near IR v0"),
  ("unknown local", unknownLocalModule,
    "unknown local `x`"),
  ("immutable assignment", immutableAssignModule,
    "assignment target local `x` is not mutable"),
  ("immutable compound assignment", immutableAssignOpModule,
    "compound assignment target local `x` is not mutable"),
  ("invalid assignment target", invalidAssignTargetModule,
    "assignment target must be a local in wasm-near IR v0"),
  ("storage write used as expression", scalarWriteExprModule,
    "storage.scalar.write is a statement effect, not an expression"),
  ("storage read used as statement", scalarReadStmtModule,
    "storage.scalar.read must be used as an expression"),
  ("storage scalar assign_op unsupported", scalarAssignOpModule,
    "storage.scalar.assign_op is not supported by wasm-near IR v0"),
  ("storage map contains used as statement", mapContainsStmtModule,
    "storage.map.contains must be used as an expression"),
  ("storage path missing map key", storagePathEmptyModule,
    "storage path state `balances` is map storage; first segment must be a map key"),
  ("storage path nested map unsupported", storagePathNestedModule,
    "wasm-near IR v0 supports only single-segment mapKey storage paths"),
  ("context read used as statement", contextReadStmtModule,
    "context reads must be used as expressions"),
  ("event used as expression", eventExprModule,
    "event.emit is a statement effect, not an expression"),
  ("event empty name unsupported", eventEmptyNameModule,
    "event name must be non-empty for wasm-near IR v0"),
  ("unknown scalar state", unknownScalarStateModule,
    "unknown scalar state `missing`")
]

/-- Positive cases: (name, module, substring expected in generated src/lib.rs). -/
def okCases : Array (String × Module × String) := #[
  ("counter renders near-sdk struct", counterModule, "pub struct Counter {"),
  ("counter lowers scalar storage field", counterModule, "pub count: u64,"),
  ("counter lowers increment entrypoint", counterModule, "pub fn increment() {"),
  ("counter lowers get entrypoint", counterModule, "pub fn get() -> u64 {"),
  ("counter lowers scalar read/write", counterModule, "self.count"),
  ("map renders storage helper", mapModule, "__pf_map_set_u64"),
  ("map renders codec helper", mapModule, "__pf_decode_u64"),
  ("map lowers storage_read", mapModule, "env::storage_read"),
  ("hash context lowers sha256 account helper", hashContextModule, "__pf_account_id_hash_u64"),
  ("hash context lowers hash intrinsic", hashContextModule, "__pf_hash("),
  ("mutable local lowers compound assignment", mutableLocalModule, "acc *= 2u64;"),
  ("native value lowers attached deposit", nativeValueModule, "env::attached_deposit()")
]

def checkCase (name : String) (module : Module) (expected : String) : IO Bool := do
  match renderError? module with
  | some actual =>
      if actual == expected then
        IO.println s!"wasm-near-diagnostics: ok: {name}"
        pure true
      else
        IO.eprintln s!"wasm-near-diagnostics: FAILED: {name}"
        IO.eprintln s!"  expected: {expected}"
        IO.eprintln s!"  actual:   {actual}"
        pure false
  | none =>
      IO.eprintln s!"wasm-near-diagnostics: FAILED: {name}"
      IO.eprintln "  expected an error, but wasm-near IR generation succeeded"
      pure false

def checkOkCase (name : String) (module : Module) (expectedSubstring : String) : IO Bool := do
  match renderOk? module with
  | some src =>
      if src.contains expectedSubstring then
        IO.println s!"wasm-near-diagnostics: ok: {name}"
        pure true
      else
        IO.eprintln s!"wasm-near-diagnostics: FAILED: {name}"
        IO.eprintln s!"  expected substring: {expectedSubstring}"
        IO.eprintln s!"  in rendered source:\n{src}"
        pure false
  | none =>
      IO.eprintln s!"wasm-near-diagnostics: FAILED: {name}"
      IO.eprintln "  expected successful render, but wasm-near IR generation failed"
      pure false

def main : IO UInt32 := do
  let mut failures : Nat := 0
  for (name, module, expected) in cases do
    let ok ← checkCase name module expected
    if !ok then
      failures := failures + 1
  for (name, module, expectedSubstring) in okCases do
    let ok ← checkOkCase name module expectedSubstring
    if !ok then
      failures := failures + 1
  let total := cases.size + okCases.size
  if failures == 0 then
    IO.println s!"wasm-near-diagnostics: {total} cases passed"
    pure 0
  else
    IO.eprintln s!"wasm-near-diagnostics: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.WasmNearDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.WasmNearDiagnostics.main
