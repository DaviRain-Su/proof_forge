# Development Log

This log records engineering milestones for ProofForge. It is not a replacement
for Git history. Use it to understand what changed, what was validated, and what
the next engineering step is.

## Format

Each entry should include:

- date
- commit or work range
- summary
- validation run
- known limitations
- next step

## 2026-07-06

### EVM Fixed-Array Assignment Source Plans

Work range: `codex/evm-dynamic-array-target-plan`

Summary:

- Added `FixedArrayAssignmentSourcePlan` so whole local fixed-array assignment
  sources can be represented as semantic `ExprPlan`s before Yul emission.
- Added `Lower.fixedArrayAssignmentSourcePlans` for local fixed-array sources
  and array-literal element sources.
- Added `ToYul.wholeFixedArrayAssignStmtFromPlan`, then routed the active
  fixed-array whole-assignment path through `Lower -> Plan -> ToYul`.
- Removed the now-unused IR-local
  `lowerFixedArrayAssignmentSourceExprs` source-to-Yul helper.
- Added semantic-plan tests that inspect the Lower source plan and the ToYul
  snapshot block.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
```

Known limitations:

- Nested fixed-array, struct-array, and whole-struct assignment source expansion
  still lives in `IR.lean` before delegating final block assembly to `ToYul`.

Next step:

- Move the next aggregate assignment source expansion slice into `Lower`,
  prioritizing nested fixed-array sources because the final Yul frame is
  already behind `ToYul`.

### EVM Storage-Path Expr-Target Plan Closure

Work range: `codex/evm-dynamic-array-target-plan`

Summary:

- Routed statement-position `storagePathWrite` and `storagePathAssignOp`
  unconditionally through `Lower.buildEffectPlan` and the
  `StoragePathWriteExprTargetPlan -> ToYul` boundary.
- Removed the IR compatibility helpers that still chose fallback storage-path
  targets and scalar RHS expressions:
  `lowerStoragePathWriteTarget`, `lowerStoragePathWriteStmt`, and
  `lowerStoragePathAssignOpStmt`.
- Removed the raw storage-path write/assign-op ToYul callback surface:
  `storagePathWriteEffectPlanStatements`,
  `storagePathWriteEffectStmtPlanStatements`,
  `storagePathAssignOpEffectPlanStatements`, and
  `storagePathAssignOpEffectStmtPlanStatements`.
- Updated semantic-plan tests so storage-path write/assign-op helper coverage
  uses expr-target plans directly.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
! rg -n "storagePathWriteEffectStmtPlanStatements|storagePathWriteEffectPlanStatements|storagePathAssignOpEffectStmtPlanStatements|storagePathAssignOpEffectPlanStatements|lowerStoragePathWriteStmt\\b|lowerStoragePathAssignOpStmt\\b|lowerStoragePathWriteTarget\\b|lowerStoragePathAssignOpTargetStatement|lowerStoragePathWriteStmtPlanOrFallback|lowerStoragePathAssignOpStmtPlanOrFallback" ProofForge Tests
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-plan
just evm-semantic-plan
just evm-all
scripts/i18n/check-sync.sh
git diff --check
just ci
```

Known limitations:

- Struct-valued scalar storage writes still keep compatibility field expansion
  in `IR.lean`.
- Other non-storage-path write helpers still retain `PlanOrFallback` naming
  until their unsupported aggregate/diagnostic paths are narrowed.

Next step:

- Continue shrinking remaining storage write fallback surfaces or move the next
  recursive body lowering gap behind `StmtPlan -> ToYul`.

### EVM Dynamic-Array Target-Plan Closure

Work range: `codex/evm-dynamic-array-target-plan`

Summary:

- Made `Lower.buildEffectPlan` require `DynamicArrayTargetPlan` for
  statement-position dynamic-array push/pop.
- Removed the raw dynamic-array push/pop fallback branches from `IR.lean`.
- Removed the now-unused raw dynamic-array ToYul helper/callback surface.
- Added semantic-plan coverage proving invalid dynamic-array targets fail in
  `Lower` before any raw fallback plan can be produced.
- Split entrypoint body-plan completeness from dispatch-plan completeness, and
  guarded against surface plans with empty bodies erasing fallback/receive body
  lowering.
- Added semantic-plan coverage for `EvmFallbackProbe` so selector entrypoints,
  fallback, and receive bodies cannot silently lower to empty Yul functions.
- Aligned EVM golden Yul for array ABI and dynamic-array probes with the
  helper set emitted after target-plan lowering.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
! rg -n "dynamicArrayPushEffect|dynamicArrayPopEffect|dynamicArrayTargetPlan\\?|lowerDynamicArrayPushStmt\\b" ProofForge/Backend/Evm Tests/EvmSemanticPlan.lean
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-plan
just evm-semantic-plan
just evm-all
scripts/i18n/check-sync.sh
git diff --check
just ci
```

Known limitations:

- Dynamic-array storage-path write-like behavior still uses the broader
  storage-path write target surface.
- Other storage write fallback surfaces remain in `IR.lean` for unsupported
  aggregate or diagnostic-only shapes.

Next step:

- Continue shrinking storage write fallback callbacks, prioritizing helpers
  that can now be proven unused by the semantic-plan tests.

### EVM Dead Write Fallback Helper Removal

Commit: f610632

Summary:

- Removed now-unused `IR.lean` write/return fallback helpers:
  `lowerScalarStorageWriteStmt`, `lowerMapSetReturnExpr`,
  `lowerDynamicArrayWriteStmt`, and `lowerDynamicArrayPopStmt`.
- Kept active scalar storage writes, map insert/set return effects, and
  dynamic-array pop behavior on their existing `Lower.buildEffectPlan ->
  ToYul` target-effect paths.
- Left dynamic-array write-like behavior on storage-path write plans.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
rg -n "\blowerScalarStorageWriteStmt\b|\blowerMapSetReturnExpr\b|\blowerDynamicArrayWriteStmt\b|\blowerDynamicArrayPopStmt\b" ProofForge/Backend/Evm/IR.lean Tests/EvmSemanticPlan.lean docs/implementation-backlog.md docs/zh/implementation-backlog.zh.md docs/development-log.md
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Struct-valued scalar storage writes still keep compatibility field expansion
  in `IR.lean`.
- Storage-path write and assign-op fallback target selection still keeps
  compatibility callbacks in `IR.lean`.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue shrinking write/assign fallback callback surfaces after each helper
  is demonstrably unused.

### EVM Legacy Storage-Path Read Wrapper Removal

Commit: 11a7e10

Summary:

- Removed the now-unused `lowerStoragePathReadExpr` compatibility wrapper from
  `IR.lean`.
- Kept `lowerStoragePathReadExprTarget` because raw planned effects and
  diagnostic-only paths still need a typed storage-path target callback.
- Left expression-position storage-path reads on the existing
  `Lower.buildEffectPlan` / `StorageSlotExprPlan -> ToYul` path.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
rg -n "\blowerStoragePathReadExpr\b|\blowerStoragePathReadExprTarget\b" ProofForge/Backend/Evm/IR.lean Tests/EvmSemanticPlan.lean docs/implementation-backlog.md docs/zh/implementation-backlog.zh.md docs/development-log.md
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `lowerStoragePathReadExprTarget` remains as a compatibility target callback
  for raw planned effects and diagnostic-only paths.
- Storage-path write and assign-op fallback target selection still keeps
  compatibility callbacks in `IR.lean`.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue auditing storage-path callback surfaces and remove helpers once they
  are demonstrably unused.

### EVM Dead Storage Read Helper Removal

Commit: 053b83f

Summary:

- Removed dead direct read compatibility helpers from `IR.lean` for map
  get/contains, fixed-array read, dynamic-array read, and struct-array field
  read.
- Kept slot helpers that are still used by storage-path write and assign-op
  fallback target selection.
- Left direct storage read expressions on the existing
  `lowerEffectExprThroughPlan` and `lowerPlanEffectExpr -> ToYul` boundary.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
rg -n "lowerMapGetExpr|lowerMapContainsExpr|lowerArrayReadExpr|lowerDynamicArrayReadExpr|lowerStructArrayFieldReadExpr|lowerMapSlotExpr" ProofForge/Backend/Evm/IR.lean Tests/EvmSemanticPlan.lean docs/implementation-backlog.md docs/zh/implementation-backlog.zh.md docs/development-log.md
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Slot helpers for array, dynamic-array, struct-array, and map path targets
  remain because write and assign-op fallback target selection still uses them.
- Storage-path target selection callbacks still exist until direct callers and
  diagnostic-only paths no longer need them.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue auditing storage-path callback surfaces and remove helpers once they
  are demonstrably unused.

### EVM Legacy Map-Path Read Helper Removal

Commit: 603a330

Summary:

- Removed the now-unused `lowerMapPathReadExpr` helper from `IR.lean`.
- Kept nested-map storage-path read behavior on the shared
  `StorageSlotExprPlan -> ToYul` path introduced by the earlier storage-path
  read migration.
- Confirmed `lowerMapPathReadExpr` no longer has code references after the
  storage-path read fallback migration.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
rg -n "lowerMapPathReadExpr" ProofForge/Backend/Evm/IR.lean Tests/EvmSemanticPlan.lean docs/implementation-backlog.md docs/zh/implementation-backlog.zh.md
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Map-path value and presence slot helpers remain because write and assign-op
  fallback target selection still uses them.
- Storage-path target selection callbacks still exist until direct callers and
  diagnostic-only paths no longer need them.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue auditing storage-path callback surfaces and remove helpers once they
  are demonstrably unused.

### EVM Legacy Map-Path Write Helper Removal

Commit: 2b042ba

Summary:

- Removed the now-unused `lowerMapPathWriteStmt` helper from `IR.lean`.
- Kept nested-map storage-path write fallback behavior on the shared
  `ToYul.storagePathWriteTargetStatements` frame added in the previous slice.
- Confirmed `lowerMapPathWriteStmt` no longer has code references after the
  storage-path write fallback migration.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
rg -n "lowerMapPathWriteStmt" ProofForge/Backend/Evm/IR.lean Tests/EvmSemanticPlan.lean docs/implementation-backlog.md docs/zh/implementation-backlog.zh.md
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Other generic non-storage-path map/array/struct write compatibility helpers
  remain in `IR.lean`.
- Storage-path target selection callbacks still exist until direct callers and
  diagnostic-only paths no longer need them.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue auditing storage-path callback surfaces and remove helpers once they
  are demonstrably unused.

### EVM Storage-Path Write Fallback ToYul Slice

Commit: 7fb513b

Summary:

- Reused `ToYul.storagePathWriteTargetStatements` from
  `IR.lowerStoragePathWriteStmt` fallback paths.
- Kept `IR.lean` responsible for choosing the fallback storage-path target and
  scalar RHS expression, while moving the final map write helper, single-slot
  `sstore`, and nested-map value/presence writeback frame behind `ToYul`.
- Added a fallback semantic-plan test that forces a non-plan scalar RHS shape
  and verifies the generated array storage-path write still uses the array slot
  helper and lowered scalar value.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `IR.lean` still owns fallback target selection and scalar RHS lowering for
  storage-path write compatibility paths.
- Generic non-storage-path map/array/struct write fallback helpers still keep
  their existing compatibility frames.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue deleting legacy storage-path callback/fallback surfaces once direct
  callers and diagnostic-only paths no longer need them.

### EVM Storage-Path Assign-Op Fallback ToYul Slice

Commit: 788f637

Summary:

- Reused `ToYul.storagePathAssignOpTargetStatements` from
  `IR.lowerStoragePathAssignOpStmt` fallback paths.
- Kept `IR.lean` responsible for choosing the fallback storage-path target and
  scalar RHS expression, while moving the final map helper, single-slot `_slot`
  block, and nested-map value/presence writeback frame behind `ToYul`.
- Added a fallback semantic-plan test that forces a non-plan scalar RHS shape
  and verifies the generated array storage-path assign-op block still declares
  `_slot` and writes through the checked assignment frame.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `IR.lean` still owns fallback target selection and scalar RHS lowering for
  storage-path assign-op compatibility paths.
- Storage-path write fallback surfaces still have compatibility logic in
  `IR.lean` while direct target paths continue to use `Lower -> Plan -> ToYul`.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue reducing storage-path write fallback surfaces, then delete legacy
  callback surfaces once direct callers and diagnostics no longer need them.

### EVM Raw Struct-Array Field Read ToYul Slice

Commit: 7b5697c

Summary:

- Moved raw compatibility `EffectPlan.storageArrayStructFieldRead` expression
  frame construction from `IR.lean` into
  `ToYul.structArrayFieldReadExpr`.
- Kept `IR.lowerPlanEffectExpr` responsible only for validating the
  struct-array state and looking up its root slot, length, field count, and
  field offset before delegating the Yul expression frame.
- Made `structArrayFieldReadTargetExpr` reuse the same raw metadata helper, so
  raw and target struct-array field reads share the final
  `sload(__proof_forge_struct_array_slot(...))` frame.
- Added semantic-plan tests that call the raw ToYul struct-array field read
  helper directly in addition to existing target-plan and IR facade coverage.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `IR.lean` still owns the struct-array state/root-slot/length/field metadata
  lookup for the raw compatibility plan variant; only the final struct-array
  field read Yul expression frame moved behind `ToYul`.
- Storage-path read/write fallback surfaces still keep compatibility logic in
  `IR.lean` while typed path expression planning continues to broaden.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by reducing the remaining
  storage-path read/write fallback surface in `IR.lean`.

### EVM Raw Struct Field Read ToYul Slice

Commit: 5c45e07

Summary:

- Moved raw compatibility `EffectPlan.storageStructFieldRead` expression frame
  construction from `IR.lean` into `ToYul.structFieldReadExpr`.
- Kept `IR.lowerPlanEffectExpr` responsible only for validating the struct
  state and looking up the field slot before delegating the Yul expression
  frame.
- Kept `structFieldReadTargetExpr` on the generic target-slot path while the
  raw helper owns the numeric-slot frame.
- Added semantic-plan tests that call the raw ToYul struct-field read helper
  directly in addition to existing target-plan and IR facade coverage.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `IR.lean` still owns the struct state/field-slot lookup for the raw
  compatibility plan variant; only the final struct-field read Yul expression
  frame moved behind `ToYul`.
- Raw struct-array read expression frames still have an IR-local compatibility
  branch.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the raw struct-array read
  expression frame from `IR.lean` into `ToYul`.

### EVM Raw Array Read ToYul Slice

Commit: 4479430

Summary:

- Moved raw compatibility `EffectPlan.storageArrayRead` expression frame
  construction from `IR.lean` into `ToYul.arrayReadExpr`.
- Kept `IR.lowerPlanEffectExpr` responsible only for validating the storage
  array state and looking up its root slot plus static length before delegating
  the Yul expression frame.
- Made `arrayReadTargetExpr` reuse the same raw root-slot/length helper.
- Added semantic-plan tests that call the raw ToYul array read helper directly
  in addition to existing target-plan and IR facade coverage.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `IR.lean` still owns the storage array state/root-slot/length lookup for the
  raw compatibility plan variant; only the final array read Yul expression
  frame moved behind `ToYul`.
- Raw struct and struct-array read expression frames still have IR-local
  compatibility branches.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small raw storage
  read expression frame from `IR.lean` into `ToYul`.

### EVM Raw Map Read ToYul Slice

Commit: e6eca8c

Summary:

- Moved raw compatibility `EffectPlan.storageMapContains` and
  `EffectPlan.storageMapGet` expression frame construction from `IR.lean` into
  `ToYul.mapContainsExpr` and `ToYul.mapGetExpr`.
- Kept `IR.lowerPlanEffectExpr` responsible only for validating the map state
  and looking up its root slot before delegating the Yul expression frame.
- Made the planned target helpers `mapContainsTargetExpr` and
  `mapGetTargetExpr` reuse the same raw root-slot helpers.
- Added semantic-plan tests that call the raw ToYul map read helpers directly in
  addition to the existing target-plan and IR facade coverage.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `IR.lean` still owns the map state/root-slot lookup for raw compatibility
  plan variants; only the final map read Yul expression frame moved behind
  `ToYul`.
- Other raw storage read expression frames, such as array and struct reads,
  still have IR-local compatibility branches.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small
  compatibility expression or statement frame from raw `IR.lean` into
  `Lower -> Plan -> ToYul`.

### EVM Planned Map Helper Discovery Slice

Commit: d837d0a

Summary:

- Extended the complete-plan helper scanner to detect map slot, presence,
  statement write, expression set-return, and map assign-op helper
  requirements from planned `EntrypointPlan.body` trees.
- Replaced broad state-shape-derived map helpers for complete module plans, so
  unused map state no longer emits map helpers and narrow map reads/writes emit
  only the helper subset they actually call.
- Split `ToYul` map base helper definitions so `mapSlot`, `mapPresenceSlot`,
  `mapWrite`, and `mapSetReturn` can be emitted independently while
  map assign-op helper emission stays driven by `ModulePlan.mapAssignOps`.
- Recomputed `ModulePlan.mapAssignOps` from the final helper set after complete
  plan helper replacement.
- Added semantic-plan tests for unused-map, contains-only, get-only,
  statement-write-only, expression set-return-only, and map assign-op-only
  modules.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Base and incomplete/best-effort plans still use the raw helper scanner; the
  complete-plan override now covers memory-array, hash, storage-array, and map
  helper subsets.
- This slice moves helper discovery and helper emission precision, not the
  remaining raw compatibility paths for all EVM statement/expression lowering.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small
  compatibility boundary from raw `IR.lean` into `Lower -> Plan -> ToYul`.

### EVM Planned Storage-Array Helper Discovery Slice

Commit: 0f30959

Summary:

- Extended the complete-plan helper scanner to detect storage fixed-array,
  dynamic-array, and struct-array slot helper requirements from planned
  `EntrypointPlan.body` trees.
- Replaced state-shape-derived helper requirements for complete module plans, so
  unused storage array declarations no longer emit `arraySlot`,
  `dynamicArraySlot`, or `structArraySlot` helpers.
- Added semantic-plan tests for unused fixed-array, dynamic-array, and
  struct-array state plus positive coverage for existing storage array fixtures.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Known limitations:

- Base and incomplete/best-effort plans still use the raw helper scanner; the
  complete-plan override now covers memory-array, hash, and storage-array
  helper subsets.
- Map helper discovery is still broader and remains a separate follow-up slice.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small
  compatibility boundary from raw `IR.lean` into `Lower -> Plan -> ToYul`.

### EVM Planned Hash Helper Discovery Slice

Commit: e5b14f3

Summary:

- Generalized the planned helper scanner so complete EVM module plans can
  discover helper requirements from planned `EntrypointPlan.body` trees.
- Replaced broad capability-derived hash helper requirements in complete module
  plans with planned-body discovery: `hash(x)` requires only `hashWord`, and
  `hashTwoToOne(a,b)` requires only `hashPair`.
- Split `ToYul` hash helper definitions so hash word and hash pair helpers can
  be emitted independently.
- Added semantic-plan tests for hash-word-only and hash-pair-only modules,
  including raw-plan over-emission contrasts and target-plan parity checks.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Known limitations:

- Base and incomplete/best-effort plans still use the capability/raw helper
  scanner; complete module plans now replace the memory-array and hash helper
  subsets precisely.
- This slice moves helper discovery and helper emission precision, not the
  remaining aggregate statement compatibility paths in `IR.lean`.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small
  compatibility boundary from raw `IR.lean` into `Lower -> Plan -> ToYul`.

### EVM Planned Memory-Array Helper Discovery Slice

Commit: bb9ef6f

Summary:

- Replaced broad complete-plan memory-array helper requirements with helper
  requirements discovered from planned `EntrypointPlan.body` trees.
- Split `ToYul` memory-array helper definitions so `memoryArrayNew` and
  `memoryArrayGet` can be emitted independently.
- Kept base/best-effort module plans on the raw capability helper surface while
  making `Lower.buildFullModulePlan` and
  `Lower.buildFullModulePlanWithTargetPlan` own complete-plan memory-array
  helper precision.
- Added semantic-plan tests for length-only, new-only, and get-only memory-array
  modules, including a raw-plan over-emission contrast for `memoryArrayLength`.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Known limitations:

- Base and incomplete/best-effort plans still use the capability/raw helper
  scanner; complete module plans now replace only the memory-array helper subset.
- This slice moves helper discovery and helper emission precision, not the full
  memory-array lifecycle or remaining aggregate statement compatibility paths.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small
  compatibility boundary from raw `IR.lean` into `Lower -> Plan -> ToYul`.

### EVM Planned Memory-Array Expression Body Slice

Commit: 00e8306

Summary:

- Added planned-body support for `ExprPlan.memoryArrayNew`,
  `ExprPlan.memoryArrayLength`, and `ExprPlan.memoryArrayGet` when their nested
  expressions are already supported.
- Let supported control-flow branch bodies lower memory-array length/get
  expressions through the existing `ExprPlan -> ToYul` expression boundary.
- Added semantic-plan coverage for memory-array length over an existing local
  buffer, length over a planned memory-array allocation, and memory-array get
  helper calls inside planned `ifElse` bodies.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Known limitations:

- Memory-array expressions are now eligible inside supported planned bodies, but
  array-typed local bindings and wider memory-array lifecycle orchestration
  still remain outside the planned-body subset.
- This slice expands expression eligibility only; broader recursive
  `StmtPlan -> Yul` extraction still needs to continue incrementally.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue shrinking the `IR.lean` compatibility facade by moving the next
  statement/effect boundary into `Lower -> Plan -> ToYul`.

### EVM Planned Memory-Array Set Body Slice

Commit: 7c24232

Summary:

- Added `EffectPlan.memoryArraySet` to the planned-body support predicate for
  EVM statement bodies.
- Let supported `ifElse`/`boundedFor` planned-body lowering consume
  memory-array set effects directly through
  `ToYul.memoryArraySetEffectStmtPlanStatements`.
- Added semantic-plan coverage that proves memory-array set effects inside
  control-flow branches lower as direct planned `mstore` frames instead of
  falling back to the older block-wrapped compatibility statement path.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Known limitations:

- Memory-array set itself is now eligible for planned-body lowering, but broader
  memory-array lifecycle and unsupported aggregate statement shapes still remain
  on their existing compatibility surfaces.
- This slice only expands the planned-body support predicate and tests the
  control-flow path; broader recursive `StmtPlan -> Yul` extraction still needs
  to continue incrementally.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue shrinking the `IR.lean` compatibility facade by moving the next
  statement/effect boundary into `Lower -> Plan -> ToYul`.

### EVM Planned Context Ops Discovery Slice

Commit: eb062af

Summary:

- Moved `ModulePlan.contextOps` discovery for complete EVM module plans from
  the base raw-IR scanner to the already-built `EntrypointPlan.body`
  `StmtPlan`/`ExprPlan` tree.
- Added planned traversal for `ExprPlan.context`, `EffectPlan.contextRead`,
  nested `blockHash` arguments, event word plans, crosscall/create arguments,
  storage target expression slots, and supported control-flow bodies.
- Preserved `Plan.contextOpsFromModule` as the base/best-effort compatibility
  scanner while making `buildFullModulePlan` and
  `buildFullModulePlanWithTargetPlan` own the complete-plan summary.
- Added `ContextOpsPlanProbe` semantic-plan coverage plus injected planned-body
  coverage for nested `blockHash(.context timestamp)` discovery.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Known limitations:

- `contextOps` is now planned for complete module plans, but fallback/base plans
  still use the raw-IR compatibility scanner by design.
- This slice only moves the context operation summary; remaining EVM semantic
  migration work still needs to continue through the next compatibility
  boundaries in `IR.lean`.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue the EVM semantic-plan migration by moving the next small
  compatibility boundary from raw `IR.lean` into `Lower -> Plan -> ToYul`.

## 2026-07-05

### Quint Integration Phase 3 v1

Commit range: 046d93d..98c6d50

Summary:

- Implemented a first-class Quint state-machine model generator from portable IR.
- Added `ProofForge.Backend.Quint` library with AST, pretty-printer, IR-to-Quint
  lowering, scenario TOML parsing, invariant derivation, ITF trace parsing, and
  an IR-semantics replay harness.
- Wired `proof-forge emit --target quint --fixture counter` into the CLI and
  `Fixture.lean`.
- Added `Tests/Quint/CounterReplay.lean` end-to-end test: lowers Counter, runs
  `quint run --mbt --out-itf`, parses the ITF trace, and replays every step
  against `ProofForge.IR.Semantics`.
- Added toolchain capabilities `model.quint`, `verify.model_check`,
  `verify.simulation`, and `test.mbt_trace` to the capability registry.
- Extended `ProofForge.Contract.Spec.Json.render` to emit a `verification.quint`
  metadata block.
- Added `scripts/quint/model-check-gate.sh` and
  `scripts/quint/mbt-replay-gate.sh` with graceful skips when `quint` or Java
  17+ are unavailable, plus `just quint-model-gate` and `just quint-mbt-gate`.
- Updated Chinese translations and i18n manifest.

Validation run:

```sh
just check
just quint-model-gate
just quint-mbt-gate
lake env lean --run Tests/Quint/CounterModel.lean
lake env lean --run Tests/Quint/CounterLower.lean
lake env lean --run Tests/Quint/Scenario.lean
lake env lean --run Tests/Quint/ITF.lean
lake env lean --run Tests/Quint/CounterReplay.lean
```

Known limitations:

- Only the bounded scalar IR subset is supported (scalars, maps, arrays, structs,
  bounded loops, basic arithmetic). Crosscalls, unbounded loops, floating point,
  and complex bitwise ops are out of scope for v1.
- `quint verify` requires Java 17+; the model-check gate skips on this machine
  because only Java 11 is installed.
- Invariants are auto-derived for unsigned scalar non-negativity only; manual
  scenario invariants are planned but not yet parsed from TOML.
- The replay harness trusts Quint `init` states and verifies subsequent
  entrypoint transitions.
- ValueVault IR fixture does not exist yet, so only Counter is covered end-to-end.

Next step:

- Add a ValueVault IR fixture, lower it to Quint, and extend the MBT replay gate
  to cover it; then consider wiring `quint verify` into the default CI path once
  Java 17+ is available.

### EVM Dynamic-Array EffectPlan Routing

Commit: 5fda3c4

Summary:

- Routed statement-position dynamic-array push/pop effects through
  `Lower.buildEffectPlan` before final ToYul statement lowering.
- Removed IR-local push value expression planning from the plan-supported
  dynamic-array push statement path.
- Reused `ToYul.dynamicArrayPushEffectStmtPlanStatements` and
  `ToYul.dynamicArrayPopEffectStmtPlanStatements` for planned dynamic-array
  effects.
- Added semantic-plan coverage for direct dynamic-array push/pop statement
  lowering, including planned checked-add push values and planned root-slot
  length loads.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Dynamic-array push still keeps the existing fallback error path for expression
  shapes that are not yet covered by planned scalar Yul lowering.
- Dynamic-array write through storage paths and some aggregate statement paths
  still keep compatibility helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue by moving storage-path dynamic-array writes or another aggregate
  statement boundary from compatibility helpers into
  `Lower -> EffectPlan -> ToYul`.

### EVM Struct-Array-Field Write Statement EffectPlan Routing

Commit: c9f358c

Summary:

- Routed statement-position storage struct-array-field write effects through
  `Lower.buildEffectPlan` before final ToYul statement lowering.
- Removed IR-local reconstruction of struct-array-field write target plans and
  index/value expression plans from the plan-supported struct-array-field write
  statement path.
- Reused `ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements` for planned
  struct-array-field write target effects.
- Strengthened semantic-plan coverage for direct struct-array-field write
  statement lowering by checking planned root slot, length, and field offset.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Struct-array-field write statements still keep the existing fallback path for
  expression shapes that are not yet covered by planned scalar Yul lowering.
- Dynamic-array push/pop and some aggregate statement paths still keep
  per-effect compatibility helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint.Scenario`, `Quint.Lower`, and `Cli`.

Next step:

- Continue by moving the next dynamic-array or aggregate statement boundary from
  compatibility helpers into `Lower -> EffectPlan -> ToYul`.

### EVM Struct-Field Write Statement EffectPlan Routing

Commit: afc5284

Summary:

- Routed statement-position storage struct-field write effects through
  `Lower.buildEffectPlan` before final ToYul statement lowering.
- Removed IR-local reconstruction of struct-field write target plans and value
  expression plans from the plan-supported struct-field write statement path.
- Reused `ToYul.structFieldWriteTargetEffectStmtPlanStatements` for planned
  struct-field write target effects.
- Strengthened semantic-plan coverage for direct struct-field write statement
  lowering by checking the planned storage slot.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Struct-field write statements still keep the existing fallback path for
  expression shapes that are not yet covered by planned scalar Yul lowering.
- Struct-array-field, dynamic-array, memory-array, and storage-path statement
  writes still keep their per-effect compatibility fallback helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build` still reports pre-existing unused-variable warnings in
  `ConstructorInit` and `Cli`.

Next step:

- Continue by moving struct-array-field statement-position storage write effects
  from compatibility helpers into `Lower -> EffectPlan -> ToYul`.

### EVM Array Write Statement EffectPlan Routing

Commit: ab599c8

Summary:

- Routed statement-position fixed-array `storageArrayWrite` effects through
  `Lower.buildEffectPlan` before final ToYul statement lowering.
- Removed IR-local reconstruction of array write target plans and index/value
  expression plans from the plan-supported array write statement path.
- Reused `ToYul.arrayWriteTargetEffectStmtPlanStatements` for planned array
  write target effects.
- Strengthened semantic-plan coverage for direct array write statement lowering
  with a checked index expression.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Array write statements still keep the existing fallback path for expression
  shapes that are not yet covered by planned scalar Yul lowering.
- Struct-array-field, struct-field, dynamic-array, memory-array, and
  storage-path statement writes still keep their per-effect compatibility
  fallback helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue by moving struct-field or struct-array-field statement-position
  storage write effects from compatibility helpers into
  `Lower -> EffectPlan -> ToYul`.

### EVM Map Write Statement EffectPlan Routing

Commit: 62f4f98

Summary:

- Routed statement-position `storageMapInsert` and `storageMapSet` effects
  through `Lower.buildEffectPlan` before final ToYul statement lowering.
- Removed IR-local reconstruction of map write target plans and key/value
  expression plans from the plan-supported map write statement path.
- Reused `ToYul.mapWriteTargetEffectStmtPlanStatements` for planned map write
  target effects.
- Added semantic-plan coverage for statement-position map insert lowering.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Map write statements still keep the existing fallback path for expression
  shapes that are not yet covered by planned scalar Yul lowering.
- Array, struct-array-field, struct-field, dynamic-array, memory-array, and
  storage-path statement writes still keep their per-effect compatibility
  fallback helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue by moving array or struct-field statement-position storage write
  effects from compatibility helpers into `Lower -> EffectPlan -> ToYul`.

### EVM Scalar Storage Statement EffectPlan Routing

Commit: 3c9ff1a

Summary:

- Routed statement-position scalar storage write and assign-op effects through
  `Lower.buildEffectPlan` before final ToYul statement lowering.
- Removed IR-local reconstruction of scalar storage target plans and value
  expression plans from the plan-supported write/assign-op statement path.
- Kept the existing fallback path for expression shapes that are not yet covered
  by planned scalar Yul lowering.
- Added semantic-plan coverage for fixed-slot scalar storage write target
  planning, including the EIP-1967 implementation slot.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Struct scalar storage writes still use the struct-specific compatibility
  helper until that aggregate source path is fully planned.
- Map, array, struct-field, dynamic-array, memory-array, and storage-path
  statement writes still keep their per-effect compatibility fallback helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue by moving map or array statement-position storage write effects from
  compatibility helpers into `Lower -> EffectPlan -> ToYul`.

### EVM Map Return EffectPlan Routing

Commit: 978dfb9

Summary:

- Routed expression-position `storageMapInsert` and `storageMapSet` return
  effects through `Lower.buildEffectPlan`, target
  `EffectPlan.storageMapInsertTarget`/`EffectPlan.storageMapSetTarget`, and
  `lowerPlanEffectExpr`.
- Reused `ToYul.mapSetReturnTargetExpr` for the value-return map helper instead
  of dispatching directly from `IR.lowerEffectExpr`.
- Added semantic-plan coverage for direct `lowerEffectExpr` map set-return and
  insert-return paths, including planned checked arithmetic on key/value words.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Statement-position storage write effects still keep their per-effect
  compatibility fallback helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue by moving a statement-position storage write boundary from
  compatibility helpers into `Lower -> EffectPlan -> ToYul`.

### EVM Read Effect EffectPlan Routing

Commit: c3d2a17

Summary:

- Routed expression-position storage and context read effects through
  `Lower.buildEffectPlan`, target `EffectPlan`/`EffectPlan.contextRead`, and
  `lowerPlanEffectExpr` before final ToYul lowering.
- Added a shared `lowerEffectExprThroughPlan` entry in `IR.lean` for scalar
  storage reads, map contains/get, storage array reads, struct-array field
  reads, struct field reads, storage path reads, and context reads.
- Added semantic-plan coverage for direct `lowerEffectExpr` read/context paths
  so the compatibility expression facade exercises the planned effect route.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Expression-position map insert/set still use the existing value-return helper
  path until write-return semantics are moved behind an `EffectPlan` facade.
- Statement-position write effects still keep their per-effect compatibility
  fallback helpers.
- Some aggregate expression, statement, storage, and event paths still pass
  through the compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue by moving a write-return effect or a statement-position storage
  effect boundary from compatibility helpers into `Lower -> EffectPlan -> ToYul`.

### EVM Scalar Leaf ExprPlan Routing

Commit: 299d6de

Summary:

- Routed scalar literal and local expression leaves through
  `Lower.buildExpressionExprPlan`, `ExprPlan.literalWord`/`ExprPlan.local`, and
  `ToYul.exprPlanExpr`.
- Removed direct numeric, boolean, address, `hash4`, and local identifier
  assembly from `IR.lowerExpr`.
- Added semantic-plan coverage for direct literal/local plan shapes, direct IR
  expression lowering results, and `hash4` limb packing through the shared
  `Lower.literalPlan` validation path.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still owns direct aggregate expression/error paths and compatibility
  callbacks for local/storage source plans.
- Some statement, storage, event, and aggregate paths still pass through the
  compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue with the next meaningful statement, storage, or event semantic
  boundary now that scalar expression leaves are mostly behind `ExprPlan`.

### EVM Scalar Predicate ExprPlan Routing

Commit: df0fbbf

Summary:

- Routed comparison, boolean, cast, and native-value expression lowering through
  `Lower.buildExpressionExprPlan`, `ExprPlan.builtin`/`ExprPlan.cast`/
  `ExprPlan.nativeValue`, and `ToYul.exprPlanExpr`.
- Removed direct `eq`/`iszero`/comparison/boolean/cast/callvalue assembly from
  `IR.lowerExpr`.
- Added semantic-plan coverage for direct predicate, boolean, cast, and native
  value plan shapes plus direct IR expression lowering results.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still owns direct literal/local expression handling and some aggregate
  expression branches that can be migrated through planned expressions or kept as
  trivial facade leaves by a later cleanup decision.
- Some statement, storage, event, and aggregate paths still pass through the
  compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue by either routing the remaining trivial literal/local expression leaves
  through `ExprPlan`, or by switching to the next narrow statement/storage/event
  shape with meaningful IR-local assembly.

### EVM Arithmetic ExprPlan Routing

Commit: 8e8a2a5

Summary:

- Routed scalar arithmetic, division/modulo, bitwise, shift, and exponent
  expression lowering through `Lower.buildExpressionExprPlan`,
  `ExprPlan.checkedArith` or `ExprPlan.builtin`, and `ToYul.exprPlanExpr`.
- Removed the corresponding direct helper-call and builtin assembly branches from
  `IR.lowerExpr`, including checked add/sub/mul selection and shift operand
  ordering.
- Added semantic-plan coverage for direct arithmetic/bitwise plan shapes and
  direct IR expression lowering results.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still owns direct comparison, boolean, cast, context/native, literal,
  local, and some aggregate expression branches that can be migrated through
  planned expressions in later slices.
- Some statement, storage, event, and aggregate paths still pass through the
  compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving another simple expression family, likely comparison/boolean or
  context/native expressions, from `IR.lean` compatibility lowering into the
  `Lower -> Plan -> ToYul` path.

### EVM Hash ExprPlan Routing

Commit: 673deed

Summary:

- Routed `hashValue`, `hash`, and `hashTwoToOne` expression lowering through
  `Lower.buildExpressionExprPlan`, their corresponding `ExprPlan` hash nodes, and
  `ToYul.exprPlanExpr` instead of assembling hash pack/helper-call expressions
  directly in `IR.lowerExpr`.
- Added semantic-plan coverage for direct hash plan shapes and direct IR
  expression lowering results.
- Kept hash helper-call selection on the same ToYul helper API used by planned
  helper discovery.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still owns several direct scalar arithmetic, comparison, boolean, and
  context expression branches that can be migrated through planned expressions in
  later slices.
- Some statement, storage, event, and aggregate paths still pass through the
  compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving another simple expression family or a narrow statement shape
  from `IR.lean` compatibility lowering into the `Lower -> Plan -> ToYul` path.

### EVM Create ExprPlan Routing

Commit: d3fc0b9

Summary:

- Routed legacy `crosscallCreate` and `crosscallCreate2` expression lowering
  through `Lower.buildExpressionExprPlan`, `ExprPlan.create`, and
  `ToYul.exprPlanExpr` instead of assembling create helper calls directly in
  `IR.lowerExpr`.
- Added semantic-plan coverage for direct create/create2 plan shapes and direct
  IR expression lowering results.
- Kept create/create2 helper-call naming aligned with the same ToYul helper-name
  selection used for helper body emission.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still supplies validation-backed provider callbacks for local and
  storage crosscall source plans.
- Some non-create expression, statement, storage, event, and aggregate paths still
  pass through the compatibility facade until their own semantic-plan slices land.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving the next expression or statement shape from the compatibility
  facade into the `Lower -> Plan -> ToYul` path, with direct semantic-plan tests
  before removing additional IR-local assembly.

### EVM Untyped Crosscall ExprPlan Routing

Commit: f91338f

Summary:

- Routed legacy untyped `crosscallInvoke` expression lowering through
  `Lower.buildExpressionExprPlan`, `ExprPlan.crosscall`, and
  `ToYul.crosscallExprPlanExpr` instead of assembling its scalar helper call
  directly in `IR.lowerExpr`.
- Added semantic-plan coverage for the untyped crosscall plan shape and direct IR
  lowering result.
- Kept typed, value-bearing, static, and delegate crosscall routing on the same
  planned expression path.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still supplies validation-backed provider callbacks for local and
  storage crosscall source plans.
- `crosscallCreate` and `crosscallCreate2` still have direct `IR.lowerExpr`
  compatibility branches; they remain candidates for the same planned-expression
  routing cleanup.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving another create, storage, event, or crosscall expression/statement
  shape from the compatibility facade into the `Lower -> Plan -> ToYul` path.

### EVM Provider-Aware Crosscall ExprPlan Lowering

Commit: cb8242f

Summary:

- Added `ToYul.crosscallExprPlanExpr`, a provider-aware crosscall expression
  helper that owns target/method/call-value lowering, source-plan argument
  expansion, scalar helper-call selection, and final argument ordering.
- Routed the generic `ExprPlan.crosscall` ToYul path through the new helper while
  preserving the existing explicit diagnostic for unexpanded local/storage source
  plans.
- Simplified `IR.lowerExprPlanExpr` so the compatibility facade now supplies only
  local/storage crosscall word providers instead of assembling the crosscall
  helper-call frame itself.
- Added direct semantic-plan coverage for `ToYul.crosscallExprPlanExpr` with
  mixed local, scalar, and storage-backed argument source plans.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still supplies validation-backed provider callbacks for local and
  storage crosscall source plans.
- Generic `ToYul.exprPlanExpr` still requires already-expanded crosscall
  argument words unless the caller uses `ToYul.crosscallExprPlanExpr` directly.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving another storage, event, or crosscall statement shape from the
  compatibility facade into the planned-body `Lower -> Plan -> ToYul` path.

### EVM Planned Storage Crosscall Argument Sources

Commit: 221f486

Summary:

- Preserved storage-backed aggregate crosscall arguments as
  `CrosscallArgWordPlan.storage` source plans instead of pre-expanding them to
  per-field `ExprPlan.storageLoad` words in `Lower`.
- Kept storage source validation by reusing `Lower.storageCrosscallWordPlans`
  before emitting the storage source plan.
- Added semantic-plan coverage showing active `buildExprPlan` output records
  storage-backed aggregate crosscall arguments as storage source plans while
  ToYul provider expansion still emits the same helper-call argument words.
- Added module-level altered-plan coverage proving `lowerModuleWithPlan`
  consumes storage aggregate crosscall argument source plans.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Storage crosscall source planning currently covers struct scalar storage reads;
  unsupported storage source shapes still fail validation or fall back through
  existing compatibility paths.
- Already-expanded scalar storage-load words still use
  `CrosscallArgWordPlan.expr`.
- `lake build proof-forge` still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving another storage, event, or crosscall statement shape from the
  compatibility facade into the planned-body `Lower -> Plan -> ToYul` path.

### EVM Planned Aggregate Crosscall Arguments

Commit: 1c38854

Summary:

- Added `ToYul.scalarReturnExprPlanStatements`, a scalar return frame helper
  that accepts a `lowerPlanExpr` callback instead of forcing generic
  `ExprPlan -> Yul` lowering.
- Routed scalar return plan lowering through `lowerExprPlanExpr`, so planned
  returns can consume crosscall/create expressions with provider-expanded
  aggregate argument sources.
- Allowed planned-body crosscall argument gates to accept
  `CrosscallArgWordPlan.local` and `.storage`; lower-time providers still own
  validation and expansion.
- Added altered-plan coverage proving `lowerModuleWithPlan` consumes a scalar
  return whose crosscall argument is a local aggregate source plan.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- This expands planned-body consumption for scalar returns; aggregate crosscall
  argument sources inside broader non-return statement shapes still depend on
  each statement shape being accepted by the planned-body gate.
- `CrosscallArgWordPlan.storage` is admitted by the gate, but unsupported
  storage source shapes still fall back when lower-time provider validation
  rejects them.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving another storage, event, or crosscall statement shape from the
  compatibility facade into the planned-body `Lower -> Plan -> ToYul` path.

### EVM Planned Body Lowering Boundary

Commit: f7dec52

Summary:

- Renamed the misleading `scalarBody` / `SupportsScalarBody` helper layer to
  the clearer `plannedBody` / `SupportsPlannedBody` boundary.
- Kept scalar-specific checks explicit as `plannedBodyScalarTypeSupported`
  while allowing the planned-body gate to describe dynamic returns, aggregate
  return words, event word effects, and aggregate crosscall returns.
- Updated direct semantic-plan tests to call the renamed planned-body helpers.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- This is a naming and ownership cleanup; it intentionally does not expand the
  supported planned-body shape set.
- The ToYul helper names for scalar binding, assignment, and assertion still
  describe their scalar statement fragments because those helpers are genuinely
  scalar-specific.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue broadening planned-body coverage by moving another return, storage,
  or crosscall shape from the compatibility facade into `Lower -> Plan ->
  ToYul`.

### EVM Planned Aggregate Crosscall Returns

Commit: 706bf97

Summary:

- Added `Lower.aggregateCrosscallReturnAssignmentPlanFromExprPlan?` so planned
  aggregate `ExprPlan.crosscall` returns can become
  `CrosscallReturnAssignmentPlan`s.
- Routed planned aggregate crosscall returns through
  `lowerCrosscallReturnAssignmentPlan` before falling back to ABI return word
  plans.
- Added direct planned-crosscall return coverage and altered-plan coverage
  proving `lowerModuleWithPlan` consumes the aggregate crosscall return
  `ModulePlan` body.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Planned aggregate crosscall return consumption currently depends on
  target/method/call value and argument word plans being inside the supported
  planned-body expression subset.
- Aggregate crosscall arguments using local/storage ABI sources still remain
  outside this planned body support gate unless already expanded to supported
  word plans.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Rename or extract the current `scalar-body` helper layer into a clearer
  supported planned-body lowering boundary before broadening more return and
  storage shapes.

### EVM Planned Storage Struct Returns

Commit: 2f54a48

Summary:

- Broadened planned aggregate return lowering so
  `ExprPlan.effect (EffectPlan.storageScalarRead stateId)` can become a
  storage-backed ABI return word plan for struct scalar state.
- Allowed complete module assembly to consume planned storage struct return
  bodies instead of falling back to the portable IR body path.
- Added altered-plan coverage for `EvmStorageStructProbe.whole_struct_return`
  proving the planned body emits only storage-backed return word loads and does
  not re-run the original storage writes.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Planned storage struct return consumption covers struct scalar state reads.
- Storage-backed fixed-array/struct-array return bodies are still represented
  as supported array/struct literal word reads rather than direct storage source
  plans.
- Aggregate crosscall returns still use existing compatibility paths.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Rename or extract the current `scalar-body` helper layer into a clearer
  supported planned-body lowering boundary before broadening more return and
  storage shapes.

### EVM Planned Aggregate Returns

Commit: 45e928c

Summary:

- Added `Lower.returnValueWordPlanFromExprPlan` so planned aggregate return
  expressions can be converted into existing ABI return word plans.
- Broadened planned entrypoint body consumption to aggregate local and literal
  return word assignments.
- Added altered-plan coverage for `EvmAbiAggregateProbe.make_pair` proving
  `lowerModuleWithPlan` consumes planned aggregate return words.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Planned aggregate return body consumption is limited to local values and
  literal fixed-array/struct values whose scalar leaves are already in the
  supported `ExprPlan -> ToYul` subset.
- Storage-backed aggregate returns and aggregate crosscall returns still use
  existing compatibility paths.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue reducing the planned body compatibility surface, either by handling
  storage-backed aggregate returns or by renaming/extracting the current
  `scalar-body` helpers into a clearer supported planned-body lowering layer.

### EVM Planned Dynamic Returns

Commit: 8a95fb8

Summary:

- Broadened planned entrypoint body consumption to dynamic local returns.
- Routed supported planned dynamic returns through
  `ToYul.dynamicReturnStmtPlanStatements`.
- Added altered-plan coverage proving `lowerModuleWithPlan` consumes a planned
  dynamic return body rather than rebuilding the portable IR body.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Planned dynamic return body consumption is limited to local dynamic values.
- Aggregate return shapes still use portable IR fallback lowering.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Broaden planned entrypoint body consumption to aggregate return word
  assignments.

### EVM Planned Aggregate Event Words

Commit: 740aa7e

Summary:

- Broadened planned entrypoint body consumption for event word effects so
  aggregate event fields are accepted once they have already been expanded into
  supported per-word `ExprPlan`s.
- Kept the conservative field-type gate on legacy `AbiValuePlan` event effect
  variants.
- Added altered-plan coverage for a fixed-array event that proves
  `lowerModuleWithPlan` consumes aggregate planned event words.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Planned body support still depends on each statement's lowered word plans
  being inside the supported `ExprPlan -> ToYul` subset.
- Dynamic and broader aggregate return shapes still use portable IR fallback
  lowering.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue broadening planned entrypoint body consumption toward aggregate
  return paths and the remaining event shapes that still need compatibility
  fallback.

### EVM Planned Entrypoint Body Consumption

Commit: 08527f5

Summary:

- Added `lowerEntrypointBodyWithPlan?` so full EVM assembly can consume
  `ModulePlan` entrypoint bodies for the existing scalar-body supported subset.
- Kept unsupported entrypoint body shapes on the portable IR fallback path.
- Added semantic-plan coverage that mutates an event entrypoint's planned body
  and verifies `lowerModuleWithPlan` consumes that planned event word effect.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Planned entrypoint body consumption is currently gated by
  `stmtPlansSupportScalarBody`; aggregate/dynamic entrypoint shapes still use
  portable IR fallback lowering.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Broaden planned entrypoint body consumption beyond the scalar-body subset,
  starting with aggregate event and return shapes that still rely on
  compatibility lowering.

### EVM Semantic Plans Emit Event Word Effects

Commit: fd31bea

Summary:

- Changed `Lower.buildEffectPlan` so portable event effects lower directly to
  `EffectPlan.eventEmitWords` / `eventEmitIndexedWords`.
- Added semantic-plan body coverage proving `buildSemanticPlan` now stores
  event word effects in entrypoint bodies.
- Updated aggregate event tests to assert Lower-owned per-field word plans
  directly instead of re-expanding `AbiValuePlan` in tests.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- The compatibility event statement path in `IR.lean` still constructs an
  initial ABI event effect and immediately converts it through Lower before
  ToYul.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Start consuming planned `ModulePlan` entrypoint bodies in full EVM assembly so
  ordinary event statement lowering can stop rebuilding event effects in the IR
  facade.

### EVM Event Word Planning Ownership

Commit: c70e5fb

Summary:

- Moved event word-effect conversion from the IR facade into
  `Lower.eventEffectWordPlan`.
- Kept active event lowering on `EffectPlan.eventEmitWords` and
  `eventEmitIndexedWords`, with ToYul consuming per-field `ExprPlan` word
  sequences directly.
- Added semantic-plan coverage for the Lower-owned event word conversion.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Full semantic-plan construction still initially produces `eventEmit` /
  `eventEmitIndexed`; the IR facade now calls Lower's conversion helper before
  ToYul.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Make full semantic-plan construction produce word-effect variants directly.

### EVM Planned Event Word Effects

Commit: e65e2eb

Summary:

- Added `EffectPlan.eventEmitWords` and `eventEmitIndexedWords` so event
  effects can carry per-field `ExprPlan` word sequences.
- Converted ordinary and scalar-body event lowering through those word-effect
  constructors before entering ToYul.
- Removed the active ToYul field-word provider callback surface; ToYul now
  consumes event word plans directly and owns word-plan-to-Yul expression
  lowering plus event block construction.
- Updated semantic-plan tests, backlog docs, Chinese backlog docs, and the i18n
  manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- The `AbiValuePlan -> ExprPlan` event field word expansion still happens in
  the IR facade; the next step is moving that conversion into full semantic-plan
  construction.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Move event field word expansion into full semantic-plan construction so the
  active event path is fully `EventPlan/EffectPlan -> ToYul`.

### EVM Event Facade Through StmtPlan

Commit: 4060c5c

Summary:

- Routed ordinary event statements through `StmtPlan.effect` and
  `ToYul.eventEffectStmtPlanStatements`, matching the scalar-body event path.
- Removed IR-local indexed-topic and event data-word expression wrapper helpers.
- Updated semantic-plan coverage for the facade path to verify indexed aggregate
  topics are hashed through the complete event block.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `Lower` still provides event field word plans; the ordinary facade now shares
  ToYul frame ownership, but the provider itself has not been eliminated.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue narrowing the event provider until the complete event lowering path
  can be expressed as `EventPlan -> ToYul`.

### EVM Event Effect Helper Canonicalization

Commit: d568c8e

Summary:

- Renamed the word-plan-provider event effect helper to the canonical
  `ToYul.eventEffectStmtPlanStatements` entrypoint.
- Removed the obsolete Yul-expression callback variant so the scalar-body event
  path has one ToYul surface for `StmtPlan.effect`.
- Updated IR/test call sites, backlog docs, Chinese backlog docs, and the i18n
  manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Event field word plan construction still comes from the provider callback;
  this slice removed the stale Yul-expression callback shape.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue narrowing the event provider until the complete event lowering path
  can be expressed as `EventPlan -> ToYul`.

### EVM Event Word Plan Lowering

Commit: 82ab8f3

Summary:

- Changed the scalar-body event provider boundary so `IR.lean` supplies
  `Lower.eventFieldDataWordPlans` output as `ExprPlan` word plans instead of
  pre-lowered Yul expressions.
- Moved word-plan-to-Yul expression lowering into
  `ToYul.eventEffectStmtPlanStatementsFromProvider`.
- Kept event field/value count checks, indexed-topic routing, data-word stores,
  and final log frame ownership in ToYul.
- Updated semantic-plan tests, backlog docs, Chinese backlog docs, and the i18n
  manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `Lower` still owns ABI value expansion into event word plans; this slice moved
  the final word-plan-to-Yul expression step behind ToYul.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue narrowing the event provider until the complete event lowering path
  can be expressed as `EventPlan -> ToYul`.

### EVM Event Field Provider Routing

Commit: 3e5ee25

Summary:

- Added ToYul-level event field provider helpers for planned event data words,
  indexed-topic statements, and scalar-body event effects.
- Replaced the `IR.lean` indexed event loop and separate data/topic callbacks
  with a single field-word provider passed into
  `ToYul.eventEffectStmtPlanStatementsFromProvider`.
- Added direct semantic-plan coverage proving the helper routes provider
  outputs into both indexed topic declarations and event data stores.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Event field word expression construction still comes from a provider callback;
  this slice moved count checks and indexed/data routing behind ToYul.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving event field word construction itself behind the
  `EventPlan -> ToYul` boundary.

### EVM StmtPlan Event Effect Frames

Commit: 930fe15

Summary:

- Added `ToYul.eventEffectStmtPlanStatements` for planned scalar-body
  `eventEmit` and `eventEmitIndexed` effects.
- Routed scalar control-flow event effect frame selection through ToYul while
  keeping event field word and indexed-topic evaluation as explicit callbacks.
- Added direct semantic-plan coverage for the event-effect helper.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Event field word and indexed-topic expression evaluation still run through
  callback-provided compatibility hooks until full `EventPlan -> Yul` lowering
  is extracted.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue extracting remaining event field evaluation and unsupported
  statement/body shapes from `IR.lean` into dedicated ToYul helpers.

### EVM StmtPlan Revert Frames

Commit: 90d5368

Summary:

- Added `ToYul.revertStmtPlanStatements` for planned `StmtPlan.revert` and
  `StmtPlan.revertWithError` frames.
- Routed planned scalar body reverts and ordinary IR revert statements through
  the new ToYul helper instead of assembling empty/message/ErrorRef reverts
  directly in `IR.lean`.
- Kept ErrorRef payload construction as a callback so target-specific error
  encoding remains outside the generic statement-frame helper.
- Added direct semantic-plan tests for empty revert, message revert, and
  callback-provided ErrorRef revert lowering.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/errors-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- ErrorRef payload memory layout still lives in the EVM compatibility facade
  callback; only the `StmtPlan` frame selection moved behind ToYul.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving remaining planned scalar body frames and unsupported statement
  shapes from `IR.lean` into dedicated ToYul helpers.

### EVM StmtPlan Body Sequencing

Commit: 50d2c4a

Summary:

- Added `ToYul.stmtPlanBodyStatements` as the shared sequencing helper for
  planned scalar `StmtPlan` bodies.
- Moved supported scalar body statement ordering, type-environment threading,
  and branch-local `leaveAfterReturn` propagation out of the `IR.lean`
  hand-written loop.
- Updated scalar control-flow semantic-plan tests with direct coverage for
  statement sequencing and leave propagation.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/ir-counter-smoke.sh
scripts/evm/expression-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Unsupported body shapes still use the `IR.lean` compatibility facade until
  full recursive `StmtPlan -> Yul` lowering is extracted.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue extracting the remaining unsupported statement/body shapes from the
  compatibility facade into plan-level ToYul helpers.

### EVM ExprPlan Word Marker Retirement

Commit: 7f8acce

Summary:

- Removed `ExprPlan.localAbiWords`, `ExprPlan.storageAbiWords`,
  `ExprPlan.localCrosscallWords`, and `ExprPlan.storageCrosscallWords` from the
  EVM semantic expression plan.
- Removed the now-unreachable generic `ExprPlan -> Yul` unsupported branches
  for those aggregate word marker constructors.
- Kept direct `ToYul.localAbiWords`, `ToYul.storageAbiWords`, and
  `ToYul.localCrosscallWords` helper APIs for explicit word expansion tests and
  provider-backed local/source expansion.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest to state
  that active aggregate word sources now live in `AbiValuePlan` and
  `CrosscallArgWordPlan`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Direct `ToYul.*Words` helpers still exist for explicit local/source word
  expansion and direct tests; they are no longer represented as `ExprPlan`
  nodes.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving remaining active statement/body assembly from the IR
  compatibility facade into `EntrypointPlan`/`StmtPlan` and dedicated ToYul
  helpers.

### EVM Crosscall Argument Word Planning

Commit: 31ea080

Summary:

- Added `CrosscallArgWordPlan` so crosscall aggregate argument sources no
  longer have to be represented as `ExprPlan.localCrosscallWords` or
  `ExprPlan.storageCrosscallWords`.
- Changed `ExprPlan.crosscall.args` and `CrosscallReturnAssignmentPlan.args` to
  carry dedicated crosscall argument word plans.
- Routed scalar, literal, and storage-load crosscall words through
  `CrosscallArgWordPlan.expr`, local aggregate crosscall sources through
  `CrosscallArgWordPlan.local`, and compatibility storage sources through
  `CrosscallArgWordPlan.storage`.
- Updated active Lower/IR/ToYul crosscall lowering and semantic-plan tests to
  consume the dedicated crosscall word plan layer.
- Updated backlog docs, Chinese backlog docs, and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `ExprPlan.localCrosscallWords` and `ExprPlan.storageCrosscallWords` still
  exist for compatibility helpers and unsupported generic `ExprPlan -> Yul`
  diagnostics; active Lower crosscall arguments no longer emit them.
- Direct `ToYul.localCrosscallWords` compatibility helpers still exist until
  older direct tests and callers are migrated.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue retiring compatibility `ExprPlan.*Words` constructors and direct
  `ToYul.*Words` helpers once all active paths consume dedicated source plans.

### EVM ABI Value Source Planning

Commit: 32c2291

Summary:

- Added `AbiValuePlan` so return/event aggregate ABI sources no longer have to
  be represented as `ExprPlan.localAbiWords` or `ExprPlan.storageAbiWords`.
- Changed `ReturnValueWordPlan.source`, planned event data fields, and planned
  indexed event fields to carry `AbiValuePlan` values.
- Routed local, storage-backed, fixed-array literal, and struct literal ABI
  sources through `Lower.buildAbiValuePlan` and `Lower.abiValueWordPlans`
  before scalar word lowering.
- Kept `ExprPlan.localAbiWords` and `ExprPlan.storageAbiWords` only for
  compatibility helpers and older direct ToYul tests, not for active
  return/event Lower output.
- Updated semantic-plan tests, backlog docs, Chinese backlog docs, and the i18n
  manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake build proof-forge
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/array-abi-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `ExprPlan.localAbiWords` and `ExprPlan.storageAbiWords` still exist for
  direct `ToYul` compatibility helpers; those helpers can be retired after
  downstream direct tests and older callers are migrated.
- Crosscall aggregate argument sources still use `ExprPlan.localCrosscallWords`
  and `ExprPlan.storageCrosscallWords`; those are a separate migration slice.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Move crosscall aggregate source markers out of `ExprPlan` into a dedicated
  crosscall ABI value/source plan, mirroring the return/event `AbiValuePlan`
  split.

### EVM Aggregate ABI Word Planning

Commit: 49ab2a9

Summary:

- Added Lower-owned ABI word planning for return/event aggregates through
  `Lower.abiValueWordPlans`, `Lower.returnValueWordPlans`,
  `Lower.eventFieldDataWordPlans`, and `Lower.eventFieldsDataWordPlans`.
- Planned local aggregate ABI words as explicit `.local` word plans and
  storage-backed aggregate ABI words as explicit `ExprPlan.storageLoad` word
  plans before final Yul lowering.
- Routed active `IR.lean` return/event lowering through those planned word
  arrays and delegated only the final return assignment and event topic/log
  frames to `ToYul`.
- Left the older `ToYul.*FromPlan` provider helpers available for direct tests
  and legacy callers, but removed their use from the active IR facade.
- Updated semantic-plan tests, the backlog, the Chinese backlog translation,
  and the i18n manifest.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake build proof-forge
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/array-abi-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `ToYul.returnValueWordPlanAssignments`,
  `ToYul.eventFieldsDataWordsFromPlan`, and
  `ToYul.eventIndexedTopicStatementsFromPlans` remain as compatibility
  helpers for direct tests and older call sites outside the active IR facade.
- `ExprPlan.localAbiWords` and `ExprPlan.storageAbiWords` still exist as source
  markers in `ReturnValueWordPlan` and event field plans until richer plan
  nodes replace those aggregate source markers directly.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue replacing aggregate source marker nodes with richer plan-level
  return/event ABI value nodes so `ExprPlan.localAbiWords` and
  `ExprPlan.storageAbiWords` can be retired from active Lower output.

### EVM Storage ABI Word Planning

Commit: 28b588b

Summary:

- Added `Lower.storageAbiWordPlans` and `Lower.storageArrayAbiWordPlans` so
  storage-backed return/event ABI word providers lower to explicit
  `ExprPlan.storageLoad` word plans.
- Routed `IR.lowerStorageAbiWords` and return/event ABI provider callbacks
  through the new Lower planner before final Yul lowering.
- Added semantic-plan coverage for storage fixed-array and storage struct-array
  ABI word plans.
- Updated the backlog and i18n manifest to record the narrower storage ABI
  compatibility surface.

Validation run:

```sh
lake build proof-forge
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/array-abi-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
```

Known limitations:

- Storage ABI values still enter `ToYul` through compatibility provider
  callbacks for `ExprPlan.storageAbiWords`, but those callbacks now consume
  Lower-planned `storageLoad` words.
- Local ABI word emission still reaches `ToYul.localAbiWords` through
  compatibility wrappers until those call sites consume richer semantic-plan
  nodes directly.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue replacing compatibility provider callbacks for aggregate
  return/event ABI emission with richer plan-level surfaces.

### EVM Local ABI Word Plan Validation

Commit: c283ec7

Summary:

- Added `Lower.localAbiStructFieldIds`, `Lower.localAbiStructFields`, and
  `Lower.validateLocalAbiWordPlan` so local ABI word validation and struct-field
  discovery are owned by the EVM Lower layer.
- Routed the compatibility `IR.localAbiStructFieldIds`,
  `IR.localAbiStructFields`, and `IR.lowerLocalAbiWords` helpers through the
  new Lower helpers before final `ToYul.localAbiWords` emission.
- Added semantic-plan coverage for Lower-owned local ABI struct field
  discovery, local/type validation, and unknown-local diagnostics.
- Updated the backlog and i18n manifest to record the narrower local ABI
  compatibility surface.

Validation run:

```sh
lake build proof-forge
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/array-abi-ir-smoke.sh
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
```

Known limitations:

- Local ABI word emission still reaches `ToYul.localAbiWords` through
  compatibility wrappers until those call sites consume richer semantic-plan
  nodes directly.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue replacing compatibility `ToYul.localAbiWords` call sites with
  explicit plan-level surfaces for return/event aggregate ABI word emission.

### EVM Storage Crosscall Word Planning

Commit: bbe22b6

Summary:

- Added `Lower.storageCrosscallWordPlans` so storage scalar struct crosscall
  arguments lower to explicit `ExprPlan.storageLoad` word plans in the EVM
  semantic plan.
- Routed storage scalar struct reads in `Lower.buildCrosscallStructArgWordPlans`
  through the new storage word planner instead of emitting
  `ExprPlan.storageCrosscallWords`.
- Kept the `IR.lean` storage provider callback as a compatibility fallback for
  existing `ExprPlan.storageCrosscallWords` inputs, but made it delegate through
  `Lower.storageCrosscallWordPlans` before final Yul lowering.
- Updated semantic-plan coverage to assert that storage-backed aggregate
  crosscall arguments are planned as per-field `storageLoad` words.

Validation run:

```sh
lake build proof-forge
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
test -z "$(rg -n "storageCrosscallWords" ProofForge/Backend/Evm/Lower.lean || true)"
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
```

Known limitations:

- Compatibility `ExprPlan.storageCrosscallWords` inputs still exist so older
  facade paths can be lowered, but active Lower-produced storage-backed
  crosscall arguments now use explicit `storageLoad` word plans.
- Related local aggregate ABI compatibility paths still call
  `ToYul.localAbiWords` directly until they are represented in the semantic
  plan.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue migrating local aggregate ABI compatibility paths that still call
  `ToYul.localAbiWords` directly into explicit `Lower`/`Plan` surfaces.

### EVM Local Crosscall Word Plan Validation

Commit: 72ae37d

Summary:

- Added `Lower.localCrosscallStructFieldIds` and
  `Lower.validateLocalCrosscallWordPlan` so local crosscall word validation and
  struct-field discovery are owned by the EVM Lower layer.
- Removed the IR-local `localCrosscallStructFieldIds` helper and routed
  `IR.lowerLocalCrosscallWords` plus planned crosscall argument word expansion
  through the new Lower helpers before final `ToYul.localCrosscallWords`
  emission.
- Added semantic-plan coverage for Lower-owned local crosscall struct field
  discovery, local/type validation, and unknown-local diagnostics.
- Updated the backlog to record that storage-backed crosscall provider
  expansion is now the remaining compatibility helper in this slice.

Validation run:

```sh
lake build proof-forge
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
```

Known limitations:

- Storage-backed crosscall word-provider expansion still depends on
  compatibility helpers in `IR.lean`.
- Related local aggregate ABI compatibility paths still call
  `ToYul.localAbiWords` directly until they are represented in the semantic
  plan.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Move storage-backed crosscall provider expansion behind explicit
  `Lower`/`Plan` helpers, then continue the same treatment for the remaining
  local aggregate ABI compatibility paths.

### EVM Crosscall Return Diagnostic Planning

Commit: 50eabcd

Summary:

- Added `Lower.buildExpressionExprPlan` as the expression-position wrapper
  around `buildExprPlan`.
- Moved typed/value/static/delegate aggregate crosscall return diagnostics out
  of `IR.lean` and into the Lower expression wrapper.
- Kept `buildExprPlan` valid for return statement planning so aggregate
  crosscall return assignments can still be planned by
  `Lower.aggregateCrosscallReturnAssignmentPlan?`.
- Added semantic-plan coverage for Lower-level diagnostics and IR facade
  propagation.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Local/storage crosscall word-provider callbacks still depend on compatibility
  type-env helpers.
- Related compatibility paths still call `ToYul.localAbiWords` directly until
  they are represented in the semantic plan.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue migrating local/storage word-provider validation and remaining
  aggregate ABI compatibility paths behind explicit `Lower`/`Plan` surfaces.

### EVM Crosscall Argument Word Planning

Commit: 83dabe8

Summary:

- Routed scalar expression fallback crosscall argument lowering through
  `Lower.buildCrosscallArgWordPlansMany` before the `ToYul` argument-word
  boundary.
- Removed the old IR-local `lowerCrosscall*ArgWords` expansion tree from
  `IR.lean`.
- Tightened `Lower` so unsupported non-literal aggregate crosscall argument
  sources fail with explicit diagnostics instead of falling through to scalar
  expression planning.
- Added semantic-plan coverage for the IR compatibility facade consuming
  planned local struct crosscall argument words.

Validation run:

```sh
test -z "$(rg -n "lowerCrosscallStructArgWords|lowerCrosscallStructArrayArgWords|lowerCrosscallFixedArrayArgWords|lowerCrosscallArgWords\\b" ProofForge/Backend/Evm/IR.lean ProofForge/Backend/Evm/Lower.lean Tests || true)"
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still owns scalar expression fallback return-type checks for
  aggregate crosscall returns.
- Local/storage crosscall word-provider callbacks still depend on compatibility
  type-env helpers.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue migrating remaining expression-position aggregate crosscall return
  diagnostics and local/storage word-provider validation behind explicit
  `Lower`/`Plan` surfaces.

### EVM Crosscall Argument Word Plan Delegation

Commit: becf9d8

Summary:

- Added `ToYul.crosscallArgWordPlanExprs` to own traversal and concatenation of
  planned crosscall argument word groups.
- Routed `IR.lowerCrosscallArgWordPlanExprs` through that helper, leaving
  `IR.lean` responsible only for local/storage word-provider callbacks that
  still depend on compatibility type-env helpers.
- Added semantic-plan coverage for mixed local aggregate, scalar, and
  storage-backed crosscall word groups.
- Updated the implementation backlog and Chinese translation sync metadata to
  record the narrower crosscall compatibility surface.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- `IR.lean` still owns non-literal aggregate crosscall argument source
  validation outside local aggregate values and storage scalar struct reads.
- Some expression-position aggregate crosscall diagnostics still live in the
  compatibility facade.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue migrating aggregate crosscall argument source validation and
  diagnostics into explicit `Lower`/`Plan` surfaces.

### EVM Dynamic Return Fallback Removal

Commit: 2746617

Summary:

- Removed the stale `lowerReturnWords` dynamic local data-pointer success path
  from `IR.lean`.
- Made dynamic return fallback fail explicitly if a `bytes`/`string`/array
  return bypasses `Lower.buildExprPlan -> StmtPlan.return ->
  ToYul.dynamicReturnStmtPlanStatements`.
- Updated the implementation backlog and Chinese translation sync metadata so
  the remaining return fallback surface reflects the new ownership boundary.

Validation run:

```sh
test -z "$(rg -n "bytes/string returns in IR EVM v0 support local references only|Non-local dynamic returns still use the compatibility fallback|非本地动态返回仍走兼容 fallback" ProofForge/Backend/Evm/IR.lean docs/implementation-backlog.md docs/zh/implementation-backlog.zh.md || true)"
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/dynamic-abi-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Non-local dynamic return expressions remain unsupported and fail before
  successful lowering.
- Some expression-position aggregate crosscall diagnostics and aggregate
  argument expansion still live in `IR.lean`.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving expression-position crosscall fallback decisions and
  aggregate argument expansion behind explicit `Lower`/`Plan` surfaces.

### EVM Aggregate Return Fallback Removal

Commit: 65b8a1c

Summary:

- Removed the stale IR-local fixed-array, struct-array, and struct return word
  fallback helpers from `IR.lean`.
- Made aggregate return fallback in `lowerReturnWords` fail explicitly if a
  fixed-array or struct return ever bypasses `ReturnValueWordPlan` or aggregate
  crosscall return planning.
- Updated the implementation backlog and Chinese translation sync metadata to
  record that aggregate return success paths must now pass through the
  semantic-plan return surfaces.

Validation run:

```sh
test -z "$(rg -n "lowerStructArrayReturnWords|lowerFixedArrayReturnWords|lowerStructReturnWords" ProofForge/Backend/Evm/IR.lean || true)"
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Non-local dynamic returns still use the compatibility fallback and diagnostic
  path.
- Some aggregate argument expansion and unsupported expression-position
  aggregate crosscall diagnostics still live in `IR.lean`.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue migrating the remaining expression-position crosscall and non-local
  dynamic return fallback decisions behind explicit `Lower`/`Plan` surfaces.

### EVM Scalar Return Name Plan Ownership

Commit: 68c16f3

Summary:

- Routed scalar `return` statement lowering through
  `Lower.returnPlan.localNames` before calling
  `ToYul.scalarReturnStmtPlanStatements`.
- Removed one more IR-facade dependency on local return-name calculation for
  the supported scalar return plan path.
- Kept generated Yul behavior unchanged; this is an ownership cleanup toward
  `Lower -> Plan -> ToYul`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/expression-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Aggregate and non-local dynamic return fallback paths still have compatibility
  facade work remaining.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving return and crosscall fallback decisions behind explicit
  `Lower`/`Plan` surfaces before deleting more IR-local compatibility code.

### EVM Dynamic Local Return ToYul Slice

Commit: 2d72dc8

Summary:

- Added `ToYul.dynamicReturnStmtPlanStatements` for dynamic `bytes`/`string`/
  array return statements that return a local ABI value.
- Routed `IR.lowerReturnStmt` through `Lower.buildExprPlan ->
  StmtPlan.return -> ToYul.dynamicReturnStmtPlanStatements` for dynamic local
  returns, so `IR.lean` no longer owns the final `name__data_ptr` assignment
  frame for that supported shape.
- Added semantic-plan coverage for the direct ToYul helper and the integrated
  `EvmDynamicAbiProbe.echo_bytes` return path.
- Updated the implementation backlog and Chinese translation sync metadata to
  reflect the narrower remaining compatibility surface.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/dynamic-abi-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- This slice only covers local dynamic return values. Non-local dynamic returns
  still fall back to the existing compatibility path and diagnostic behavior.
- Broader aggregate/crosscall return paths still need their own plan-level
  migration slices.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue shrinking the remaining EVM compatibility facade around aggregate
  crosscall return assignment and non-local dynamic return-data boundaries.

### EVM Local Array Helper Discovery Delegation

Commit: c0600b2

Summary:

- Removed the stale IR-local local fixed-array getter and nested local-array
  getter discovery scanners from `IR.lean`.
- Kept the compatibility facade entrypoints `moduleLocalArrayGetLengths` and
  `moduleNestedLocalArrayGetShapes`, but made them delegate to
  `Lower.buildLocalArrayGetLengths` and `Lower.buildNestedLocalArrayGetShapes`.
- Aligned helper requirement discovery with the existing `ModulePlan` ownership
  model so fallback lowering and complete plan lowering consume the same
  lower/plan source.

Validation run:

```sh
test -z "$(rg -n "localArrayGetLengthsExpr|localArrayGetLengthsEffect|localArrayGetLengthsStatement|localArrayGetLengthsForDynamicExprTarget|nestedLocalArrayGetShapesExpr|nestedLocalArrayGetShapesEffect|nestedLocalArrayGetShapesStatement|nestedLocalArrayGetShapesForDynamicExprTarget|mergeNatSets|mergeNatArraySets|arrayNatEq" ProofForge/Backend/Evm/IR.lean || true)"
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- This slice removes duplicate local-array helper discovery only; aggregate
  crosscall argument/return expansion and bytes/string return encoding still
  have compatibility-facade work left.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue shrinking the remaining EVM compatibility facade around aggregate
  crosscall argument/return paths and dynamic return-data encoding.

### EVM Create Helper Discovery Delegation

Commit: aaba7b2

Summary:

- Removed the stale IR-local create/create2 helper discovery scanner from
  `IR.lean`.
- Kept the compatibility facade entrypoints `moduleCreateHelperSpecs` and
  `createHelperFunctions`, but made helper discovery delegate to
  `Lower.buildCreateHelperPlans` while helper body emission remains in
  `ToYul.createHelperFunction`.
- Aligned the code with the backlog's planned ownership model: create helper
  facts are discovered in the lower/plan layer and emitted by ToYul, not
  re-scanned in the compatibility facade.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
test -z "$(rg -n "createHelperSpecsExpr|createHelperSpecsEffect|createHelperSpecsStatement|pushCreateHelperSpecIfMissing|mergeCreateHelperSpecs|createHelperSpecsStoragePathSegment" ProofForge/Backend/Evm/IR.lean || true)"
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- This slice removes duplicate create helper discovery only; aggregate
  crosscall argument/return expansion and bytes/string return encoding still
  have compatibility-facade work left.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue shrinking the remaining EVM compatibility facade around aggregate
  crosscall argument/return paths and dynamic return-data encoding.

### EVM Crosscall Helper Discovery Delegation

Commit: eac0b95

Summary:

- Removed the stale IR-local crosscall helper discovery scanner and helper-body
  assembly definitions from `IR.lean`.
- Kept the compatibility facade entrypoints
  `moduleCrosscallHelperSpecs` and `crosscallHelperFunctions`, but made them
  delegate directly to `Lower.buildCrosscallHelperPlans` and
  `ToYul.crosscallHelperFunction`.
- Preserved the public wrapper shape while ensuring crosscall helper discovery
  has a single semantic source of truth in the plan/lower layer.

Validation run:

```sh
test -z "$(rg -n "crosscallHelperSpecsExpr|crosscallHelperSpecsEffect|crosscallHelperSpecsStatement|pushCrosscallHelperSpecIfMissing|mergeCrosscallHelperSpecs|crosscallArgName|crosscallFunctionParams|crosscallReturnGuardStatements|def crosscallHelperFunction \\(" ProofForge/Backend/Evm/IR.lean || true)"
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/crosscall-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- This slice removes duplicate discovery logic; it does not migrate the
  remaining `IR.lean` aggregate crosscall argument expansion or bytes/string
  return paths.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue moving the remaining crosscall aggregate argument/return and dynamic
  return encoding decisions behind explicit plan surfaces before deleting more
  compatibility fallback code.

### EVM Aggregate Return ABI Word Plans

Commit: 26a8453

Summary:

- Generalized `ToYul.returnValueWordPlanAssignments` so return ABI word
  assignment uses the shared `abiValueWordsFromPlan` path instead of accepting
  only local aggregate word plans.
- Extended `Lower.returnValueWordPlan?` from local fixed-array/struct returns
  to literal aggregate returns and storage-backed fixed-array/struct aggregate
  returns.
- Taught the `IR.lean` compatibility facade to supply expression, local struct,
  storage struct, and storage array word callbacks while the final assignment
  frame lives in `ToYul`.
- Added semantic-plan tests for literal struct returns, storage fixed-array
  returns, and storage fixed-array-of-struct returns, including the expected
  Yul assignment targets and slot helper calls.
- Updated the implementation backlog and Chinese translation state so the
  documented EVM migration status matches the code.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Dynamic `bytes`/`string` returns remain on their existing compatibility path.
- Aggregate crosscall return helpers still need a separate migration slice.
- Storage aggregate return recognition is limited to complete contiguous
  literal-index arrays that match the declared fixed-array return shape.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue shrinking the EVM compatibility facade around the remaining aggregate
  return/crosscall helper boundaries, with coverage before deleting old paths.

### EVM Storage Array Event ABI Word Plans

Commit: a20bd8b

Summary:

- Extended `ExprPlan.storageAbiWords` from scalar storage structs to fixed
  storage arrays and fixed storage struct arrays.
- Taught `Lower.buildEventFieldValuePlan` to recognize whole storage-array
  event fields expressed as contiguous literal-index reads and record them as
  `storageAbiWords` instead of opaque aggregate literals.
- Added `ToYul.storageAbiWords` support for fixed-array storage expansion via a
  storage-array callback, with the `IR.lean` facade supplying the concrete
  `arraySlot` / `structArraySlot` backed `sload` words.
- Added semantic-plan coverage for `StorageArrayEvent` and
  `StoragePairArrayEvent`, asserting their planned storage state ids, ABI
  types, word counts, and slot helper calls.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Storage-array ABI word planning recognizes complete literal-index arrays
  only: indexes must be `0..N-1` and the event fixed-array length must match
  the storage array length.
- Partial slices, dynamic indexes, and mixed storage/literal aggregates still
  remain ordinary planned aggregate literals.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Look for the next remaining EVM compatibility-facade boundary where
  aggregate storage semantics still enter as expression fallback rather than an
  explicit `ExprPlan` / `StmtPlan` node.

### EVM Legacy Event Data Word Helper Removal

Commit: 423fa63

Summary:

- Deleted the old `lowerEventDataWords`, `lowerEventStructDataWords`, and
  `lowerEventFixedArrayDataWords` compatibility helpers from `IR.lean`.
- Reworked local aggregate event data coverage to validate
  `Lower.buildEffectPlan -> ToYul.eventFieldsDataWordsFromPlan` directly for
  local structs, fixed arrays, and struct arrays.
- Kept the existing emitted data-word assertions, but made the scalar fallback
  in the test fail fast so local aggregates cannot silently bypass ABI word
  plans.

Validation run:

```sh
rg -n "lowerEvent(Struct|FixedArray|DataWords)|testLocalAggregateEventDataWordsToYul" ProofForge Tests
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Storage fixed-array and storage struct-array event fields still enter as
  planned aggregate literals rather than first-class storage-array ABI word
  plans.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Decide whether storage-array aggregate event fields need their own
  first-class ABI word plan nodes, or whether planned aggregate literals are the
  right stable representation for EVM.

### EVM Event Data Fields via Planned ABI Words

Commit: 8975edb

Summary:

- Routed `lowerEventEmitCoreStmt` data-field value expansion through
  `Lower.buildEventFieldValuePlan` and
  `ToYul.eventFieldsDataWordsFromPlan`.
- Removed the event emit facade's direct dependency on `lowerEventDataWords`
  for data fields, matching the indexed aggregate topic path's
  `Lower -> Plan -> ToYul` boundary.
- Added facade-level coverage for a storage-backed struct event data field,
  asserting that the planned path still emits two `sload`-backed data words.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- `lowerEventDataWords` and related literal-specific helpers still remain in
  `IR.lean` for direct helper coverage and future cleanup.
- Storage fixed-array and storage struct-array event fields still enter as
  planned aggregate literals rather than first-class storage-array ABI word
  plans.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Confirm whether the remaining event data-word helpers are dead outside tests,
  then delete or shrink them in a separate cleanup commit.

### EVM Indexed Aggregate Event Topics via ABI Word Plans

Commit: d78c562

Summary:

- Routed indexed aggregate event topic word expansion through
  `Lower.buildEventFieldValuePlan` and `ToYul.eventFieldDataWordsFromPlan`.
- Extended planned ABI word lowering so aggregate `arrayLit` and `structLit`
  values can still flatten through the planned path; this preserves existing
  storage-array and storage-struct-array event behavior while moving the topic
  hash input assembly out of the `IR.lean` facade.
- Added focused coverage for storage-backed indexed struct topics using
  `storageAbiWords`, including the direct facade path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Some legacy event data-word literal fallback code still lives in `IR.lean`
  for non-planned statement lowering paths.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Continue shrinking the `IR.lean` compatibility facade by migrating remaining
  event data-word literal flattening and storage-array aggregate paths into
  reusable plan/ToYul helpers.

### EVM Storage Aggregate Event ABI Word Plan

Commit: c35886f

Summary:

- Added a `storageAbiWords` expression-plan node for storage-backed ABI word
  expansion.
- Taught `Lower.buildEffectPlan` to record local aggregate event fields as
  `localAbiWords` and scalar storage struct event fields as `storageAbiWords`.
- Extended `ToYul.eventFieldsDataWordsFromPlan` so planned event data words can
  consume aggregate ABI word expansion plans instead of only scalar
  expressions.
- Routed scalar storage struct event data lowering in the `IR.lean`
  compatibility facade through `Lower -> Plan -> ToYul`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Storage fixed-array and storage struct-array event data still enter through
  array literals of scalar storage reads.
- Indexed aggregate storage topics still have their hashing path in the
  `IR.lean` compatibility facade.

Next step:

- Move indexed aggregate topic word expansion and hashing behind the same
  planned ABI word boundary.

### EVM Local Aggregate Event Data Words via ABI Words

Commit: 4ccf8de

Summary:

- Routed local struct, fixed-array, and struct-array event data-word lowering
  through the shared `lowerLocalAbiWords` path instead of duplicating aggregate
  local flattening inside `IR.lean`.
- Kept literal and storage-backed aggregate event paths unchanged; this commit
  narrows only the local value boundary that already has reusable ABI word
  planning behavior.
- Restored EVM plan/test runtime after the deploy metadata merge by rebuilding
  affected examples, tightening helper/context comparison boundaries, and
  splitting oversized semantic-plan smoke sections without changing their
  assertions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmPlan.lean
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-diagnostics
scripts/evm/event-ir-smoke.sh
lake build proof-forge
git diff --check
```

Known limitations:

- Literal aggregate event data-word flattening and storage-backed aggregate
  event reads still live in the `IR.lean` compatibility facade.
- `lake build proof-forge` still reports pre-existing unused-variable warnings
  in `ConstructorInit`, `SbpfAsm`, and `Cli`.

Next step:

- Move storage-backed aggregate event data-word planning behind an explicit
  `Lower -> Plan -> ToYul` boundary.

### EVM IR Indexed Event Topic Assembly Cleanup

Commit: bf98fcb

Summary:

- Removed the remaining `IR.lean` wrapper for event data-store statements.
- Routed entrypoint-level indexed event topic statements through
  `ToYul.eventIndexedTopicStatements` for both scalar topics and aggregate topic
  hashing.
- Preserved the `IR.lean` compatibility facade's explicit unsupported indexed
  field diagnostic before field value flattening.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- `IR.lean` still owns event field value evaluation and aggregate data-word
  flattening before it hands words to `ToYul`.

Next step:

- Move aggregate event field value/data-word planning behind an explicit
  `EventFieldPlan`-owned boundary.

### EVM ToYul Planned Event Field Lowering

Commit: cd35c6c

Summary:

- Added `ToYul.eventFieldsDataWordsFromPlan` and
  `ToYul.eventIndexedTopicStatementsFromPlans` so planned scalar event field
  data words and indexed topics are assembled on the `ToYul` side.
- Removed the duplicate planned scalar event field helper implementations from
  `IR.lean`; the compatibility facade now only supplies the `ExprPlan` lowering
  callback.
- Extended `Tests/EvmSemanticPlan.lean` with direct coverage for the new
  `EventFieldPlan -> ToYul` helpers and kept the existing scalar event
  integration checks.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Entrypoint-level aggregate event data-word flattening and indexed aggregate
  topic hashing still live in `IR.lean`.

Next step:

- Extract aggregate event data-word planning or indexed aggregate topic hashing
  behind an explicit event-field plan boundary.

### EVM IR Event Signature Validation Cleanup

Commit: e00e657

Summary:

- Removed duplicate event-name and event signature field typing validation from
  `IR.lean`.
- Routed `IR.eventSignature`, indexed-event field validation, aggregate event
  data-word guards, and CLI event ABI metadata through
  `Validate.validateEventName` and `Validate.eventSignatureFieldType`.
- Kept event aggregate data-word lowering and indexed aggregate topic hashing
  in the `IR.lean` compatibility facade until the full event field planning path
  moves behind `EventPlan -> ToYul`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Validate ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Cli
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- `IR.lean` still owns aggregate event data-word lowering and indexed aggregate
  topic hashing. Those should move after event field value planning is complete.

Next step:

- Continue the event migration by extracting event field value/data-word and
  indexed aggregate topic hashing behind explicit `EventPlan -> ToYul` helpers.

### EVM IR Event Validation Facade Cleanup

Commit: 8352240

Summary:

- Removed duplicate event field-name and duplicate-field validation wrappers
  from `IR.lean`.
- Removed the duplicate indexed-event field-count validator from `IR.lean`.
- Routed the remaining compatibility event-signature and indexed-event type
  checks through `Validate.validateDistinctEventFieldName` and
  `Validate.validateIndexedEventFieldCount`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Validate ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- `IR.lean` still owns `eventSignatureFieldType`, aggregate event data-word
  lowering, and indexed aggregate topic hashing. Those remain compatibility
  facade work until event field planning is fully expressed behind
  `EventPlan -> ToYul`.

Next step:

- Move the next event boundary: either route event signature field typing
  through `Validate` after confirming diagnostic compatibility, or extract
  aggregate topic/data word lowering into explicit plan-owned helpers.

### EVM IR Event Helper Facade Cleanup

Commit: 51cd4ba

Summary:

- Removed pure `ToYul` forwarding wrappers for UTF-8 word packing, event
  signature topic statements, indexed event topic names, and event log builtin
  names from `IR.lean`.
- Routed the remaining indexed-event topic local-name use directly through
  `ToYul.eventIndexedTopicName`.
- Updated the EVM refinement scaffold to compute event signature topics through
  `ToYul.packedUtf8Words` instead of the IR compatibility facade.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Refinement
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Event signature field typing and indexed aggregate topic lowering still live
  in `IR.lean`; this slice only removes wrappers that were already pure ToYul
  forwarding surface.

Next step:

- Continue extracting event lowering by moving field typing, topic planning, or
  aggregate topic hashing behind explicit event semantic-plan nodes.

### EVM IR Hash Packing Facade Cleanup

Commit: 7730f6a

Summary:

- Removed duplicate hash literal packing constants and validation helpers from
  `IR.lean`.
- Routed hash literal packing through `Validate.packedHashLiteral`, so fallback
  lowering uses the same validation source as the semantic-plan path.
- Routed `hashValue` Yul expression packing through `ToYul.hashPackExpr`,
  keeping the final expression frame on the ToYul-owned side.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- `IR.lean` still owns broad scalar fallback expression lowering. Hash packing
  now delegates validation and final expression construction, but surrounding
  fallback expression dispatch remains in the compatibility facade.

Next step:

- Continue shrinking scalar fallback ownership by moving another narrow helper
  frame or ABI/calldata helper boundary behind `Lower -> Plan -> ToYul`.

### EVM IR Crosscall Facade Cleanup

Commit: 8bc8a87

Summary:

- Removed the dead `IR.lean` crosscall helper naming facade for scalar and
  aggregate call/value/static/delegate helper names.
- Removed the duplicate IR-local plain native-transfer detector.
- Routed scalar fallback's plain native-transfer check through
  `Lower.plainValueTransferCall?`, matching the helper discovery source used by
  semantic-plan construction.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- `IR.lean` still owns broad scalar fallback lowering and validation facade
  logic. The next semantic-plan slice should inspect whether any remaining
  helper wrappers can be deleted, or whether the next useful boundary is moving
  more scalar fallback lowering behind `StmtPlan -> ToYul`.

Next step:

- Search remaining `IR.lean` wrappers around hash literal validation,
  entrypoint calldata/ABI helpers, and scalar fallback body assembly, then pick
  another narrow cleanup or plan-owned lowering slice.

### EVM IR Create Facade Cleanup

Commit: f91e22e

Summary:

- Removed the dead `IR.lean` create helper compatibility facade, including the
  IR-local `CreateMode`, `CreateHelperSpec`, helper name, helper parameter, and
  init-code store wrappers.
- Routed the remaining create/create2 type-checking validation points directly
  through `Validate.normalizeInitCodeHex`.
- Routed assertion error payload hex chunking directly through `ToYul` instead
  of keeping duplicate IR-local hex helper aliases.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Crosscall naming compatibility wrappers still remain in `IR.lean`; the next
  cleanup should verify which are still used by scalar fallback lowering before
  deleting or narrowing them.

Next step:

- Continue reducing compatibility-only wrapper surface in `IR.lean`, starting
  with crosscall naming wrappers and scalar helper-call fallback ownership.

### EVM IR Local Array Discovery Cleanup

Commit: 1e54791

Summary:

- Removed the legacy local fixed-array helper discovery scanners from
  `IR.lean` after incomplete-plan fallback routing moved to
  `Lower.buildLocalArrayGetLengths`.
- Removed the legacy nested local-array helper discovery scanners from
  `IR.lean` after fallback routing moved to
  `Lower.buildNestedLocalArrayGetShapes`.
- Removed the duplicate IR-local checked-arithmetic scanner because fallback
  and full-plan lowering now both use `Validate.moduleUsesCheckedArithmetic`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Several compatibility wrappers and type aliases still remain in `IR.lean`.
  They should be reviewed case-by-case so the public facade stays stable while
  final lowering ownership continues moving to `Lower -> Plan -> ToYul`.

Next step:

- Inspect the remaining compatibility-only wrappers in `IR.lean` and either
  delete dead surface area or keep narrow facade aliases for downstream callers.

### EVM IR Crosscall/Create Discovery Cleanup

Commit: 21893a0

Summary:

- Removed the legacy crosscall helper discovery scanner from `IR.lean` after
  incomplete-plan fallback routing moved to `Lower.buildCrosscallHelperPlans`.
- Removed the legacy create helper discovery scanner from `IR.lean` after
  incomplete-plan fallback routing moved to `Lower.buildCreateHelperPlans`.
- Removed the obsolete legacy crosscall/create plan-conversion helpers that
  only existed to bridge those old IR-local scanner result types.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- Local-array helper discovery cleanup remains separate; the fallback path
  already routes through `Lower.buildLocalArrayGetLengths` and
  `Lower.buildNestedLocalArrayGetShapes`, but dead compatibility scanners still
  remain in `IR.lean`.

Next step:

- Remove the remaining dead local-array helper discovery scanners from
  `IR.lean`, or continue reducing compatibility-only helper wrappers toward
  `Lower -> Plan -> ToYul`.

### EVM Fallback Helper Discovery Through Lower

Commit: d7b1b2d

Summary:

- Routed incomplete-plan fallback helper discovery in `lowerModuleWithPlan`
  through `Lower.buildCrosscallHelperPlans`,
  `Lower.buildCreateHelperPlans`, `Lower.buildLocalArrayGetLengths`, and
  `Lower.buildNestedLocalArrayGetShapes`.
- Routed fallback checked-arithmetic detection through
  `Validate.moduleUsesCheckedArithmetic`, matching the source used by
  `Lower.buildFullModulePlan`.
- Added semantic-plan regression coverage that lowers intentionally incomplete
  base plans and verifies the fallback path emits the same discovered
  crosscall, create, checked-arithmetic, local-array, and nested-local-array
  helpers.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
lake build proof-forge
git diff --check
```

Known limitations:

- The old compatibility discovery functions still exist in `IR.lean` as dead
  code after this routing change. They should be deleted in a focused cleanup
  once no downstream compatibility callers need them.

Next step:

- Remove the now-unused `IR.lean` helper discovery scanners or continue moving
  the remaining compatibility-only helper wrappers toward `Lower -> Plan ->
  ToYul`.

### EVM ToYul Local Array Helpers

Commit: dffa0e2

Summary:

- Moved local fixed-array dynamic getter helper bodies from the `IR.lean`
  compatibility facade into `ToYul.lean`, including single-dimension and
  nested local-array switch helpers.
- Moved local-array helper parameter naming and path-value naming utilities to
  `ToYul`, where the generated helper function bodies now live.
- Updated plan-driven and fallback module helper emission to call
  `ToYul.localArrayGetHelperFunctions` and
  `ToYul.nestedLocalArrayGetHelperFunctions`.
- Extended semantic-plan coverage to verify helper discovery, ToYul helper
  emission, and plan-driven module lowering for local and nested local-array
  getters.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
just evm-diagnostics
git diff --check
```

Known limitations:

- Discovery of local-array helper requirements still lives in the compatibility
  facade until the broader helper discovery pass is moved out of `IR.lean`.

Next step:

- Continue Phase 0 by moving remaining compatibility-only helper wrappers or
  helper discovery passes from `IR.lean` toward `Lower -> Plan -> ToYul`.

### EVM ToYul Map Helpers

Commit: c679a55

Summary:

- Moved map slot, map presence slot, map write, map set-return, and map
  compound-assignment helper function bodies from the `IR.lean` compatibility
  facade into `ToYul.lean`.
- Moved the ProofForge-managed map presence domain constant to `ToYul`, where
  the helper body that uses it now lives.
- Routed remaining raw fallback map writes, set-return expressions, and direct
  map storage-path compound assignment calls through `ToYul.helperCall` with
  `Plan.Helper` variants.
- Added semantic-plan regression coverage that verifies `EvmMapProbe`
  discovers all map helper families and emits the matching ToYul helper set,
  including representative map assign helpers.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
just evm-diagnostics
git diff --check
```

Known limitations:

- `IR.lean` still owns local-array value helper bodies and several
  compatibility-only helper discovery passes. This slice only moves map helper
  function bodies and helper naming to the ToYul-owned side.

Next step:

- Continue Phase 0 by moving local fixed-array value helper bodies or
  crosscall/create compatibility wrappers behind explicit ToYul ownership.

### EVM ToYul Array Slot Helpers

Commit: cb2f6b7

Summary:

- Moved fixed-array, dynamic-array, and struct-array storage slot helper
  function bodies from the `IR.lean` compatibility facade into `ToYul.lean`.
- Removed duplicate IR-local array helper name constants and routed remaining
  raw fallback slot calls through `ToYul.helperCall` with `Plan.Helper`
  variants.
- Updated planned helper emission for `arraySlot`, `dynamicArraySlot`, and
  `structArraySlot` so final helper bodies are owned by `ToYul`.
- Added semantic-plan regressions that prove fixed storage arrays, dynamic
  storage arrays, and struct storage arrays discover the expected helper and
  emit the matching ToYul helper body.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/dynamic-array-ir-smoke.sh
just evm-diagnostics
git diff --check
```

Known limitations:

- Local fixed-array value helper functions still live in `IR.lean`; this slice
  only moves storage-slot helper families that already map directly to
  `Plan.Helper` variants.

Next step:

- Continue Phase 0 by moving the remaining map helper bodies or local-array
  value helper bodies out of the compatibility facade behind explicit ToYul
  ownership.

### EVM ToYul Hash Helpers

Commit: 50b6eaa

Summary:

- Moved EVM `hash` and `hashTwoToOne` helper function bodies from the
  `IR.lean` compatibility facade into `ToYul.lean`.
- Removed the duplicate IR-local hash helper name constants and routed raw
  fallback hash calls through `ToYul.helperCall` with `Plan.Helper.hashWord`
  and `Plan.Helper.hashPair`.
- Updated planned hash helper emission so helper function bodies are owned by
  `ToYul`, matching the already-planned `ExprPlan` hash lowering path.
- Added a semantic-plan regression using `EvmHashProbe` to verify hash helper
  discovery and planned helper emission both use the ToYul helper set.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/hash-ir-smoke.sh
just evm-diagnostics
git diff --check
```

Known limitations:

- Hash helper discovery still flows through module capability analysis; this
  slice moves helper body ownership, not the broader helper discovery pipeline.

Next step:

- Continue Phase 0 by moving the remaining map/array helper bodies out of
  `IR.lean`, starting with a narrow helper family that has an existing smoke
  fixture and planned helper coverage.

### EVM ToYul Checked Arithmetic Helpers

Commit: d2649e5

Summary:

- Moved checked-arithmetic helper names, max-word overflow constant, revert
  guard construction, and helper function bodies from the `IR.lean`
  compatibility facade into `ToYul.lean`.
- Kept the public `IR.lean` checked-add/sub/mul expression helpers as thin
  delegations to `ToYul.checkedArithExpr`, preserving existing callers while
  making final Yul helper ownership explicit.
- Updated planned checked-arithmetic helper emission and incomplete-plan
  fallback emission to use the `ToYul` helper definitions.
- Added semantic-plan regression coverage that locks the ToYul helper set and
  verifies planned checked-arithmetic helpers are emitted from the plan path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
scripts/evm/expression-ir-smoke.sh
scripts/evm/assign-op-ir-smoke.sh
scripts/evm/context-ir-smoke.sh
just evm-diagnostics
git diff --check
```

Known limitations:

- Fallback discovery for whether a best-effort module uses checked arithmetic
  still lives in `IR.lean`; this slice only moves the emitted helper bodies and
  planned helper ownership to `ToYul`.

Next step:

- Continue Phase 0 by moving the next helper-body boundary out of the
  compatibility facade, likely map/array/hash helper bodies or the remaining
  revert/error-reference helper frame.

### EVM Planned Context Expressions

Commit: e1a8608

Summary:

- Added `ContextExprPlan` so plan-level context reads no longer carry raw
  `ContextField.blockHash` arguments through to final Yul lowering.
- Routed `Lower.buildEffectPlan` for `contextRead` through context expression
  planning, including recursive `ExprPlan` construction for
  `blockHash(blockNumber)`.
- Moved raw and planned context Yul construction behind explicit `ToYul`
  helpers, and removed the stale `IR.lean` context expression helper.
- Added a semantic-plan regression proving `blockHash(local + 1)` lowers to a
  planned checked-add argument before `ToYul` emits the `blockhash` builtin.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
scripts/evm/context-ir-smoke.sh
git diff --check
```

Known limitations:

- `ModulePlan.contextOps` remains a summary of source-level context usage. This
  slice moves expression lowering and `blockHash` arguments onto the
  `Lower -> Plan -> ToYul` path, but does not turn the summary list into a
  dedicated metadata/codegen source.

Next step:

- Continue Phase 0 by moving the next remaining compatibility-only Yul frame
  from `IR.lean` into `ToYul`, preferably another narrow boundary with an
  existing smoke fixture.

### EVM Planned Storage-Path Expressions

Commit: e2eb7ff

Summary:

- Added `StorageSlotExprPlan` and `StoragePathWriteExprTargetPlan`, a
  storage-path target surface whose map keys, fixed-array indexes,
  struct-array indexes, and dynamic-array indexes are first-class `ExprPlan`
  values instead of `ValuePlan` wrappers around raw IR expressions.
- Added `StoragePathPlanSegment` and routed `Lower.buildEffectPlan` for
  `storagePathRead`, `storagePathWrite`, and `storagePathAssignOp` through
  raw path segment planning before slot/target resolution.
- Added `ToYul` lowering helpers for the new planned read/write/assign target
  surface and wired expression-position reads, statement-position writes, and
  scalar control-flow bodies through the new variants.
- Kept the existing `StorageSlotPlan` / `StoragePathWriteTargetPlan`
  compatibility surface for direct plan tests and fallback callers.

Validation run:

```sh
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/dynamic-array-ir-smoke.sh
git diff --check
```

Known limitations:

- Direct compatibility helpers still expose the older `ValuePlan`-based
  storage slot target surface. They are intentionally retained until remaining
  fallback callers and direct plan tests move to the new ExprPlan surface.

Next step:

- Move more storage-path direct plan tests and fallback-only callers to the
  ExprPlan target surface, then retire the `ValuePlan` storage-path surface
  once no supported lowering path depends on it.

### EVM Storage-Path Write Lower-Plan Routing

Commit: 9ecd2a0

Summary:

- Routed statement-position `storagePathWrite` lowering through
  `Lower.buildEffectPlan`, so the `IR.lean` compatibility facade consumes the
  planned `StoragePathWriteTargetPlan` variant instead of rebuilding the value
  plan and target plan independently.
- Routed statement-position `storagePathAssignOp` lowering through the same
  `Lower.buildEffectPlan -> EffectPlan -> ToYul` boundary.
- Preserved the existing fallback path for value expressions outside the
  supported scalar plan subset.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
git diff --check -- ProofForge/Backend/Evm/IR.lean
```

Known limitations:

- Storage-path key/index expressions still live inside `ValuePlan` wrappers
  around IR expressions. They are now routed through the lower-plan boundary
  for statement writes, but they are not yet first-class `ExprPlan` nodes inside
  `StorageSlotPlan` / `StoragePathWriteTargetPlan`.

Next step:

- Widen storage-path target planning so map keys, array indexes, and
  struct-array indexes can be represented as planned expression nodes before
  final Yul assembly.

### EVM Planned Storage-Path Read Targets

Commit: 3b9d33b

Summary:

- Added a planned `storagePathReadTarget` effect so `Lower.buildEffectPlan`
  carries the resolved `StorageSlotPlan` for storage-path reads instead of
  leaving state-id/path lookup to the final compatibility facade.
- Routed raw `.effect (.storagePathRead ...)` expression lowering through the
  planned target path first, preserving the existing fallback path for
  compatibility and diagnostics.
- Updated `EffectPlan -> ToYul` scalar lowering to consume the planned storage
  slot directly through `ToYul.storagePathReadExprFromPlan`.
- Extended semantic-plan coverage with map and array storage-path read target
  assertions plus raw expression lowering coverage.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- `StorageSlotPlan` still carries path segment expressions as `ValuePlan`
  wrappers around IR expressions; typed path-expression planning remains
  follow-up work.

Next step:

- Continue widening storage-path expression planning so map keys, array indexes,
  and struct-array indexes can be fully represented as `ExprPlan` nodes before
  final Yul assembly.

### EVM Planned Map Read Targets

Commit: 8643ec0

Summary:

- Added `MapReadTargetPlan` so direct `storageMapContains` and
  `storageMapGet` effects carry the planned map root slot after
  `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned map read target variants while
  preserving the legacy state-id variants for fallback and compatibility paths.
- Added `ToYul.mapContainsTargetExpr` and `ToYul.mapGetTargetExpr`, moving final
  map presence/value slot `sload` assembly behind the planned target instead of
  late root-slot lookup in the compatibility facade.
- Updated direct expression lowering and scalar-body expression support so both
  `ExprPlan` recursion and raw `.effect (.storageMapContains ...)` /
  `.effect (.storageMapGet ...)` lowering consume the planned target path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/map-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Storage-path map reads and writes still use their dedicated
  `StorageSlotPlan` / `StoragePathWriteTargetPlan` surfaces; typed map
  path-expression planning remains follow-up work.

Next step:

- Continue with storage-path typed expression planning and remaining map path
  surfaces.

### EVM Planned Struct-Array Field Read Targets

Commit: 0e87338

Summary:

- Added `StructArrayFieldReadTargetPlan` so direct
  `storageArrayStructFieldRead` effects carry the planned struct-array root
  slot, array length, field count, and field offset after
  `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned struct-array field read target
  variants while preserving the legacy state-id/field/index variant for
  fallback and compatibility paths.
- Added `ToYul.structArrayFieldReadTargetExpr`, moving final
  `sload(__proof_forge_struct_array_slot(root, length, fieldCount,
  fieldOffset, index))` assembly behind the planned target instead of late
  lookup in the compatibility facade.
- Updated direct expression lowering and scalar-body expression support so both
  `ExprPlan` recursion and raw `.effect (.storageArrayStructFieldRead ...)`
  lowering consume the planned target path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-struct-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Storage-path struct/array field reads and writes still use their dedicated
  storage-path target surfaces; typed path expression planning remains follow-up
  work.

Next step:

- Continue with the remaining storage-path expression planning surfaces and map
  contains/get target metadata.

### EVM Planned Struct Field Read Targets

Commit: 9d743a9

Summary:

- Added `StructFieldReadTargetPlan` so direct `storageStructFieldRead`
  effects carry the planned struct field storage slot after
  `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned struct field read target
  variants while preserving the legacy state-id/field variant for fallback and
  compatibility paths.
- Added `ToYul.structFieldReadTargetExpr`, moving final `sload(fieldSlot)`
  assembly behind the planned target instead of late field-slot lookup in the
  compatibility facade.
- Updated direct expression lowering and scalar-body expression support so both
  `ExprPlan` recursion and raw `.effect (.storageStructFieldRead ...)` lowering
  consume the planned target path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-struct-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- This slice only moved direct scalar struct field reads; struct-array field
  read metadata is tracked by the next entry.

Next step:

- Move struct-array field read metadata behind a planned target.

### EVM Planned Struct-Array Field Write Targets

Commit: 82d0faf

Summary:

- Added `StructArrayFieldWriteTargetPlan` so direct
  `storageArrayStructFieldWrite` effects carry the planned struct-array root
  slot, array length, field count, and field offset after
  `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned struct-array field write
  target variants while preserving the legacy state-id/field variant for
  fallback and compatibility paths.
- Added direct `ToYul` helpers for planned struct-array field writes, moving
  final `__proof_forge_struct_array_slot(root, length, fieldCount,
  fieldOffset, index)` assembly behind the planned target instead of a late
  `IR.lean` callback.
- Extended semantic-plan tests with `Lower -> Plan` assertions and direct
  planned-target `ToYul` coverage for checked index/value expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-struct-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Struct field reads and struct-array field reads still use their existing
  state-id/field lookup paths.

Next step:

- Move struct and struct-array field read metadata behind planned targets, then
  continue with the remaining storage-path expression planning surfaces.

### EVM Planned Struct Field Write Targets

Commit: c56729e

Summary:

- Added `StructFieldWriteTargetPlan` so direct `storageStructFieldWrite`
  effects carry the planned struct field storage slot after
  `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned struct field write target
  variants for scalar struct fields while preserving the legacy state-id/field
  variant for fallback and compatibility paths.
- Added direct `ToYul` helpers for planned struct field write statements,
  moving final `sstore(fieldSlot, value)` assembly behind the planned target
  instead of a late `IR.lean` slot callback.
- Extended semantic-plan tests with `Lower -> Plan` assertions and direct
  planned-target `ToYul` coverage for checked RHS expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-struct-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- This slice only moved direct scalar struct field writes; struct-array field
  write metadata is tracked by the next entry.
- Struct field reads still use their existing state-id/field lookup path.

Next step:

- Move struct-array field write metadata behind its own planned target.

### EVM Planned Array Read Targets

Commit: c05a06d

Summary:

- Added `ArrayReadTargetPlan` so direct `storageArrayRead` effects carry the
  planned array root slot and length after `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned array read target variants for
  valid fixed-size storage arrays while preserving legacy state-id variants for
  fallback and compatibility paths.
- Added `ToYul.arrayReadTargetExpr`, moving final
  `sload(__proof_forge_array_slot(root, length, index))` assembly behind the
  planned target instead of late root-slot/length lookup in the compatibility
  facade.
- Updated direct expression lowering and scalar-body expression support so both
  `ExprPlan` recursion and raw `.effect (.storageArrayRead ...)` lowering can
  consume the planned target path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/typed-storage-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Struct-array field reads/writes and storage-path array reads/writes continue
  on their own helper/target surfaces until their metadata can be widened into
  explicit semantic-plan nodes.

Next step:

- Continue extracting struct/struct-array field target metadata and the
  remaining storage-path expression planning surfaces from the compatibility
  facade.

### EVM Planned Array Write Targets

Commit: 23421a0

Summary:

- Added `ArrayWriteTargetPlan` so direct `storageArrayWrite` effects carry the
  planned array root slot and length after `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned array write target variants
  for valid fixed-size storage arrays while preserving legacy state-id variants
  for fallback and compatibility paths.
- Added direct `ToYul` helpers for planned array write statements, moving final
  `__proof_forge_array_slot(root, length, index)` assembly behind the planned
  target instead of a late `IR.lean` callback.
- Extended semantic-plan tests with `Lower -> Plan` assertions and direct
  planned-target `ToYul` coverage for checked index/value expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-array-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- `storageArrayRead` still uses its existing state-id lookup path; this slice
  only moves direct array write targets.
- Struct-array field writes and storage-path array writes continue on their own
  helper/target surfaces until their metadata can be widened into explicit
  semantic-plan nodes.

Next step:

- Continue extracting remaining storage target metadata, especially array reads
  and struct/struct-array field write targets, out of the compatibility facade.

### EVM Planned Map Write Targets

Commit: 43a1d32

Summary:

- Added `MapWriteTargetPlan` so direct `storageMapInsert` and `storageMapSet`
  effects carry the planned map root slot after `Lower.buildEffectPlan`.
- Routed `Lower.buildEffectPlan` to emit planned map insert/set target variants
  for valid map states while preserving legacy state-id variants for fallback
  and compatibility paths.
- Added direct `ToYul` helpers for statement-position planned map writes and
  expression-position return-old-value map writes, so the final Yul helper call
  consumes the planned target instead of doing late root-slot lookup.
- Extended semantic-plan tests with `Lower -> Plan` assertions and direct
  planned-target `ToYul` coverage for both map write statements and
  set-return expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/map-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- `storageMapContains` and `storageMapGet` still use their existing state-id
  lookup path; this slice only moves direct map write targets.
- Storage-path map writes already use their own `StoragePathWriteTargetPlan`
  path, but broader typed map path-expression planning remains follow-up work.

Next step:

- Continue moving remaining map read and array write target metadata out of the
  compatibility facade and into explicit semantic-plan nodes.

### EVM Planned Scalar Storage Read Targets

Commit: 7b519f5

Summary:

- Added a planned scalar storage read effect variant so non-struct scalar reads
  carry the same `ScalarStorageTargetPlan` metadata as scalar writes.
- Routed `Lower.buildEffectPlan` to produce planned read targets for regular
  scalar states while preserving legacy `storageScalarRead stateId` for
  struct-valued scalar storage compatibility paths.
- Added `ToYul.scalarStorageTargetReadExpr`, reusing the planned slot plus
  packed byte offset/width to lower reads without a late state-layout callback.
- Updated scalar control-flow body support and semantic-plan tests so Counter
  reads, `Lower -> Plan`, and direct planned-target read lowering are covered.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/ir-counter-smoke.sh
scripts/evm/packed-storage-ir-smoke.sh
scripts/evm/typed-storage-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Struct-valued scalar storage reads still use the existing compatibility path,
  because they are consumed by struct local binding, field access, and aggregate
  return expansion paths rather than a scalar packed-read expression.

Next step:

- Continue replacing remaining storage effect callback helpers with planned
  target nodes, especially map/array/struct-field slot metadata surfaces.

### EVM Planned Scalar Storage Write Targets

Commit: 9aaa34f

Summary:

- Added `ScalarStorageTargetPlan` so non-struct scalar storage writes carry the
  planned slot plus packed storage byte offset/width before Yul assembly.
- Added planned scalar storage write/assign-op effect variants and routed
  `Lower.buildEffectPlan` to produce them for regular scalar states while
  leaving whole-struct scalar storage writes on the legacy compatibility path.
- Refactored `ToYul` scalar storage write packing into shared helpers and added
  direct planned-target lowering for scalar write and assign-op effects.
- Updated scalar control-flow body lowering and statement-position scalar
  storage lowering to consume the planned target variants.
- Extended semantic-plan tests with `Lower -> Plan` assertions and direct
  planned-target `ToYul` helper coverage for packed scalar write/assign-op
  effects.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/ir-counter-smoke.sh
scripts/evm/packed-storage-ir-smoke.sh
scripts/evm/typed-storage-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Struct-valued scalar storage writes still use the whole-struct compatibility
  path because they expand to field-level stores instead of one scalar target.
- Scalar storage reads still lower through the existing storage-load path; this
  slice only moves write and assign-op targets.

Next step:

- Continue replacing storage effect callback helpers with planned target nodes,
  or move scalar storage reads behind the same explicit target metadata.

### EVM Planned Storage Path Write Targets

Commit: 1cc75cf

Summary:

- Added planned storage-path write effect variants so `storagePathWrite` and
  `storagePathAssignOp` carry a `StoragePathWriteTargetPlan` after
  `Lower.buildEffectPlan`.
- Added direct `ToYul` helpers for planned storage-path write and assign-op
  targets, reusing the existing planned target-to-Yul conversion instead of a
  late callback from the `IR.lean` facade.
- Routed scalar-body support and statement-position storage-path write lowering
  through the planned target variants while keeping the older callback helpers
  available for compatibility paths.
- Extended `Tests/EvmSemanticPlan.lean` with `Lower -> Plan` assertions and
  direct planned-target `ToYul` helper coverage for array storage path writes
  and assign-ops.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/map-ir-smoke.sh
lake build
git diff --check
```

Known limitations:

- Path segment expressions inside `StoragePathWriteTargetPlan` still use
  `ValuePlan.irExpr`; typed path-expression planning and the remaining
  storage-path validation/diagnostic surfaces are still follow-up work.
- The legacy storage-path write and assign-op effect variants remain for
  compatibility/fallback paths until the broader statement lowering migration is
  complete.

Next step:

- Continue extracting typed storage-path expression planning and diagnostics, or
  move another compatibility-facade storage effect behind `Lower -> Plan ->
  ToYul`.

### EVM Storage Path Read Slot Plan Slice

Commit: b37765d

Summary:

- Added `Plan.storagePathReadSlotPlan` so `storagePathRead` resolves direct map,
  array, struct field, struct-array field, and nested-map paths to a
  `StorageSlotPlan` before Yul expression assembly.
- Added `ToYul.storagePathReadExprFromPlan`, reusing the existing
  `StorageSlotPlan -> Yul` lowering and wrapping the planned slot in `sload`.
- Replaced the `IR.lean` storage-path read `match` with a thin
  `Plan.storagePathReadSlotPlan -> ToYul.storagePathReadExprFromPlan`
  compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` with direct read-slot plan coverage for
  map, array, struct field, struct-array field, and nested-map storage paths.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-diagnostics
just evm-build-examples
just evm-foundry
just evm-semantic-plan
lake build
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- This slice plans read slots only. Broader recursive `StmtPlan -> Yul` body
  lowering and some storage-path type/shape validation responsibilities still
  remain in compatibility facades.

Next step:

- Continue extracting recursive statement-body lowering or move remaining
  storage-path validation/metadata surfaces behind semantic-plan boundaries.

### EVM Storage Path Target Plan Slice

Commit: 929fb30

Summary:

- Added `StoragePathWriteTargetPlan` so direct map writes, array element writes,
  struct field writes, struct-array field writes, and nested map
  value/presence writes have an explicit semantic-plan target before Yul
  statement assembly.
- Added `ToYul.storagePathWriteTargetFromPlan`, reusing `StorageSlotPlan -> Yul`
  lowering for array, struct-array, nested-map value, and nested-map presence
  targets.
- Replaced the `IR.lean` storage-path write-target `match` with a thin
  `Plan.storagePathWriteTargetPlan -> ToYul.storagePathWriteTargetFromPlan`
  compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` with direct target-plan coverage for
  map, array, struct field, struct-array field, and nested-map storage paths.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-build-examples
just evm-diagnostics
just evm-foundry
just evm-semantic-plan
lake build
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- This slice plans storage-path write targets only. Storage-path reads,
  recursive body lowering, and full storage-path type/shape diagnostics still
  retain compatibility-facade responsibilities.

Next step:

- Move the read-side storage path target planning, or continue extracting
  recursive `StmtPlan -> Yul` body lowering, while keeping unsupported shapes
  covered by explicit diagnostics.

### EVM Packed Storage Layout Consumer Alignment

Commit: e83767f

Summary:

- Routed the EVM `IR.lean` and `Validate.lean` state lookup facades through
  `Plan.stateInfo?`, making the packed `storageLayout` the single slot source
  for lowering and validation consumers.
- Kept the fixed EIP-1967 implementation slot out of scalar address packing so
  UUPS proxy fallback reads and implementation writes agree on the same raw
  slot.
- Made `scripts/evm/build-examples.sh` fail on golden Yul mismatches instead of
  only printing the diff in an `errexit`-suppressed conditional context.
- Refreshed EVM golden Yul fixtures after the packed-storage layout alignment.

Validation run:

```sh
lake build
just evm-semantic-plan
just evm-diagnostics
just evm-build-examples
just evm-foundry
just evm-ir-smokes
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- This was a layout-consumer fix, not a broader storage-path planning
  extraction. Several compatibility-facade storage helpers remained in
  `IR.lean` after this commit.

Next step:

- Continue moving storage path planning behind `Plan -> ToYul` boundaries.

### EVM Local Aggregate Return Plan Slice

Commit: this commit

Summary:

- Added `ReturnValueWordPlan` so local fixed-array and struct entrypoint
  returns can carry their `ReturnPlan` layout and planned local ABI word source
  through the EVM semantic plan.
- Added `Lower.returnValueWordPlan?` for supported local aggregate returns,
  moving the source-local and expected-type check out of the final
  compatibility return assembly path.
- Added `ToYul.returnValueWordPlanAssignments` so final multi-word return
  assignment frames are owned by `ToYul`, while unsupported return shapes keep
  using the existing compatibility fallback.
- Extended `Tests/EvmSemanticPlan.lean` with direct `ToYul` coverage plus
  `Lower -> IR facade -> ToYul` integration checks for local struct and
  fixed-array return plans.
- Added the missing `DynamicConstructorProbe.golden.yul` fixture so
  `scripts/evm/build-examples.sh` can keep enforcing golden Yul coverage for
  every EVM contract-source example.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-build-examples
```

Known limitations:

- This slice only moves local fixed-array and struct return word assignment.
  Bytes/string returns, literal aggregate returns, storage aggregate returns,
  and broader recursive `StmtPlan -> Yul` body lowering still use compatibility
  paths.

Next step:

- Continue moving non-local aggregate return sources or metadata/deploy
  planning behind semantic-plan boundaries before deleting any legacy
  `IR.lean -> Yul` lowering.

### Wasm-NEAR Diagnostics Capability Alignment

Commit: this commit

Summary:

- Updated `Tests/WasmNearDiagnostics.lean` so the diagnostic baseline matches
  the current `wasm-near` target profile: capability-gated cases that now reach
  Rust sourcegen assert the backend-specific unsupported diagnostics instead of
  stale target-profile errors.
- Changed the fixed-array and struct cases to trigger unsupported ABI shapes
  explicitly, and moved `nativeValue` to a positive Rust sourcegen check for
  `env::attached_deposit()`.
- Updated WasmNear coverage notes, target docs, and the capability registry so
  NEAR partial capabilities distinguish the EmitWat path from Rust sourcegen v0.
- Installed `wabt` in the main CI `build-test` job so unified testkit NEAR
  artifact metadata can keep asserting `validation.wat2wasm = "passed"`.

Validation run:

```sh
lake env lean --run Tests/WasmNearDiagnostics.lean
scripts/near/diagnostic-smoke.sh
lake build ProofForge.Target ProofForge.Backend.WasmNear.IR
just testkit
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
lake build
```

Known limitations:

- Rust sourcegen v0 still rejects `if/else`, bounded loops, fixed-array ABI,
  struct ABI, and storage arrays even though the broader `wasm-near` target
  profile carries partial support through EmitWat.

Next step:

- Either route Rust sourcegen through the same planned lowering surfaces as
  EmitWat, or split backend-subpath capability reporting if the product keeps
  both NEAR codegen routes long term.

### EVM Crosscall Return Assignment Plan Slice

Commit: this commit

Summary:

- Added `CrosscallReturnAssignmentPlan` so aggregate crosscall return
  assignment shape is represented in the semantic plan.
- Added `Lower.aggregateCrosscallReturnAssignmentPlan?`, which now owns the
  aggregate-return decision, call/return type check, target/method/call-value
  expression planning, crosscall argument word planning, and return word/local
  layout.
- Simplified `IR.lowerAggregateCrosscallReturnAssignment?` so it consumes the
  planned assignment, lowers the contained `ExprPlan`s, and delegates final
  multi-return Yul assignment construction to `ToYul`.
- Added semantic-plan coverage for the `RemotePair` aggregate crosscall return
  assignment plan.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
lake build proof-forge
lake build
```

Known limitations:

- Final multi-return assignment construction still lives in `ToYul`; this
  slice moves the assignment decision and operand planning into `Lower`, not
  the full recursive `StmtPlan -> Yul` return path.
- The remaining compatibility surface is mostly around non-literal aggregate
  sources and broader recursive return statement lowering.

Next step:

- Move the remaining return statement assembly behind `StmtPlan`/`ReturnPlan`,
  or introduce semantic-plan nodes for the remaining non-literal aggregate
  crosscall argument sources.

### EVM Crosscall Return Plan Slice

Commit: this commit

Summary:

- Added `Lower.crosscallReturnPlan` so aggregate crosscall return local names
  and word layout are planned outside the `IR.lean` compatibility facade.
- Routed `lowerAggregateCrosscallReturnAssignment?` through the planned
  `ReturnPlan` before delegating final multi-return Yul assignment construction
  to `ToYul.crosscallAggregateReturnAssignment`.
- Added semantic-plan coverage for the planned `RemotePair` aggregate return
  word layout and generated return local names.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
lake build proof-forge
lake build
```

Known limitations:

- Aggregate crosscall return assignment still lives in the `IR.lean`
  compatibility facade; this slice only moves return local-name and word-layout
  discovery behind `Lower`.
- Aggregate crosscall argument expansion still uses compatibility helpers for
  the remaining non-literal aggregate sources.

Next step:

- Move the remaining return statement assembly behind `StmtPlan`/`ReturnPlan`,
  or continue introducing semantic-plan nodes for the remaining non-literal
  aggregate crosscall argument sources.

### EVM Storage Crosscall Arg Plan Slice

Commit: this commit

Summary:

- Added `ExprPlan.storageCrosscallWords` as an explicit semantic-plan node for
  storage-backed aggregate crosscall arguments.
- Extended `Lower.buildExprPlan` so `storage.scalar.read` of a struct state
  used as a typed/value/static/delegate crosscall argument is represented as
  `ExprPlan.storageCrosscallWords` instead of an opaque aggregate expression.
- Updated `IR.lowerExprPlanExpr` to consume the planned storage-backed word
  node by expanding the struct storage slots before selecting the scalar
  crosscall helper-call arity.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
lake build proof-forge
lake build
```

Known limitations:

- Storage-backed aggregate crosscall argument planning currently covers scalar
  struct storage reads only; other non-literal aggregate sources still lower
  through the compatibility facade.
- `ToYul.exprPlanExpr` remains scalar-only for standalone word-expansion nodes;
  crosscall expression lowering expands planned words before selecting the
  helper-call constructor.

Next step:

- Move aggregate crosscall return assignment decision itself behind a
  statement/return plan, or introduce semantic-plan nodes for the remaining
  non-literal aggregate crosscall argument sources.

### EVM Literal Crosscall Arg Plan Slice

Commit: this commit

Summary:

- Extended `Lower.buildExprPlan` so struct literal and fixed-array literal
  typed/value/static/delegate crosscall arguments are flattened into scalar
  word `ExprPlan`s instead of opaque aggregate expressions.
- Covered scalar fixed-array literals, nested fixed-array literals, struct
  literals, and struct-array literals at the semantic-plan boundary.
- Kept local aggregate crosscall arguments on `ExprPlan.localCrosscallWords` so
  final local identifier word construction still goes through
  `ToYul.localCrosscallWords`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
lake build proof-forge
lake build
```

Known limitations:

- Storage-backed scalar struct crosscall argument sources are handled by the
  later semantic-plan slice; other non-literal aggregate crosscall argument
  sources still lower through the compatibility facade.
- `ToYul.exprPlanExpr` remains scalar-only for standalone aggregate
  expression plans; crosscall expression lowering expands planned words before
  selecting the helper-call constructor.

Next step:

- Move aggregate crosscall return assignment decision itself behind a
  statement/return plan, or introduce semantic-plan nodes for the remaining
  non-literal aggregate crosscall argument sources.

### EVM Local Crosscall Arg Plan Slice

Commit: this commit

Summary:

- Extended `Lower.buildExprPlan` so local aggregate typed/value/static/delegate
  crosscall arguments are represented as `ExprPlan.localCrosscallWords`
  instead of opaque aggregate expressions.
- Updated `IR.lowerExprPlanExpr` to consume `ExprPlan.localCrosscallWords` by
  expanding it through `ToYul.localCrosscallWords` before selecting the scalar
  crosscall helper-call arity.
- Added semantic-plan coverage proving a local `Point` struct crosscall
  argument becomes a `localCrosscallWords` plan node and lowers to the
  two-word `__proof_forge_crosscall_2` helper call.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/crosscall-ir-smoke.sh
```

Known limitations:

- Literal aggregate crosscall argument sources are handled by the later
  semantic-plan slice; storage-backed and other non-literal aggregate
  crosscall argument sources still lower through the compatibility facade.
- `ToYul.exprPlanExpr` remains scalar-only for word-expansion nodes; the
  compatibility plan consumer expands local crosscall words before calling the
  existing helper-call constructor.

Next step:

- Introduce semantic-plan nodes for storage-backed aggregate crosscall argument
  sources, or move aggregate crosscall return word-layout discovery out of
  `IR.lean`.

### EVM Local Crosscall Words To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.localCrosscallWords` / `localCrosscallWordsAt` so local
  crosscall argument word expansion for scalar leaves, fixed arrays, structs,
  and nested arrays owns final Yul identifier construction behind the
  plan-to-Yul boundary.
- Routed `IR.lowerLocalCrosscallWords` through the new `ToYul` helper while
  keeping local binding lookup, expected-type checks, crosscall word
  validation, and struct field eligibility checks in the compatibility facade.
- Extended semantic-plan tests with direct `ToYul.localCrosscallWords` coverage
  and compatibility facade coverage for local struct and fixed-array crosscall
  argument words.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- Crosscall argument flattening for struct literals, array literals, and
  storage-backed aggregate values still uses the compatibility facade.
- Struct field metadata is still supplied by `IR.lean` until aggregate
  crosscall argument planning carries field ids directly.

Next step:

- Move aggregate crosscall argument source planning into `Lower`/`ModulePlan`
  so local and non-local aggregate sources share one semantic-plan boundary.

### EVM Local ABI Words To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.localAbiWords` / `localAbiWordsAt` so local ABI word expansion
  for scalar leaves, fixed arrays, structs, nested arrays, and dynamic
  top-level `bytes`/`string` locals owns final Yul identifier/data-pointer
  construction behind the plan-to-Yul boundary.
- Routed `IR.lowerLocalAbiWords` through the new `ToYul` helper while keeping
  local binding lookup, expected-type checks, ABI word validation, and struct
  field eligibility checks in the compatibility facade.
- Extended semantic-plan tests with direct `ToYul.localAbiWords` coverage and
  compatibility facade coverage for local struct and fixed-array ABI return
  words.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- Aggregate crosscall argument-word expansion and crosscall-specific local word
  expansion still use the existing compatibility path.
- Struct field metadata is still supplied by `IR.lean` until aggregate ABI word
  planning carries field ids directly.

Next step:

- Move crosscall argument-word expansion or return word-layout discovery into
  the semantic plan so aggregate crosscall lowering depends less on the
  compatibility facade.

### EVM Aggregate Crosscall Return To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.crosscallAggregateHelperCallExpr` and
  `ToYul.crosscallAggregateReturnAssignment` so aggregate typed `call`,
  value-bearing `call`, `staticcall`, and `delegatecall` entrypoint returns use
  the same helper-name selection and argument ordering as planned crosscall
  helper bodies.
- Routed the `IR.lean` aggregate crosscall return compatibility path through
  the new `ToYul` helper while keeping return type checks, ABI return-name
  lookup, and aggregate argument word expansion in place.
- Extended semantic-plan tests for direct aggregate return assignment lowering
  and the compatibility `lowerReturnAssignments` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Known limitations:

- Aggregate crosscall argument word expansion is still owned by `IR.lean` until
  the plan layer can represent fully expanded crosscall argument words.
- Return word-layout discovery still flows through the compatibility facade for
  this path.

Next step:

- Move aggregate crosscall argument-word planning into `Lower`/`ModulePlan`, or
  continue extracting return layout discovery so aggregate crosscall return
  lowering no longer depends on `IR.lean`.

### EVM Crosscall/Create ExprPlan To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.crosscallScalarHelperCallExpr` so scalar `call`,
  value-bearing `call`, native value transfer, `staticcall`, and `delegatecall`
  expression helper calls share the same helper-name selection used by planned
  crosscall helper bodies.
- Added `ToYul.createHelperCallExpr` so expression-position `create` and
  `create2` helper calls share the same normalized init-code helper naming used
  by planned create helper bodies.
- Routed `ExprPlan.crosscall` and `ExprPlan.create` lowering through those new
  `ToYul` helpers.
- Updated the `IR.lean` compatibility expression lowering to keep type-env
  validation and aggregate crosscall argument word expansion in place while
  delegating final helper-call names and argument ordering to `ToYul`.
- Extended semantic-plan tests for direct `ExprPlan -> ToYul` scalar
  crosscall/native-transfer/create/create2 lowering and for the compatibility
  `lowerExpr` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Known limitations:

- Aggregate crosscall return assignment/copy construction still goes through the
  `IR.lean` compatibility facade.
- Aggregate crosscall argument word expansion is still owned by `IR.lean` until
  the plan layer can represent fully expanded crosscall argument words.

Next step:

- Move aggregate crosscall return assignment/copy construction behind `ToYul`,
  or introduce a typed crosscall argument-word plan node so aggregate argument
  expansion is no longer coupled to `IR.lean`.

### EVM Create Helper To-Yul Slice

Commit: this commit

Summary:

- Added plan-to-Yul create/create2 helper construction in
  `ProofForge.Backend.Evm.ToYul`.
- Moved create helper naming, init-code `mstore` frame construction,
  `create`/`create2` opcode invocation, and zero-address revert guards behind
  `CreateHelperSpec -> ToYul`.
- Kept `IR.lean` compatibility wrappers for create helper names, params,
  init-code store statements, and helper functions while complete
  `lowerModuleWithPlan` consumes planned create specs directly.
- Extended semantic-plan coverage for planned create/create2 specs, direct
  ToYul helper names, helper parameter counts, emitted Yul opcodes, and
  plan-only create helper emission.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- Expression-position create/create2 helper-call assembly still goes through
  the `IR.lean` compatibility facade.
- Scalar and aggregate crosscall expression call construction still go through
  the `IR.lean` compatibility facade.

Next step:

- Move expression-position create/create2 helper-call assembly, or scalar
  crosscall expression call construction, behind a narrower `ToYul` boundary.

### EVM Crosscall Helper To-Yul Slice

Commit: this commit

Summary:

- Added `CrosscallHelperSpec.wordTypes` to the EVM semantic plan so planned
  crosscall helpers carry their return ABI word layout.
- Moved crosscall helper name selection, calldata packing helper body
  construction, return-data guard construction, and plain native transfer
  helper body construction behind `CrosscallHelperSpec -> ToYul`.
- Kept `IR.lean` responsible for return word layout discovery and compatibility
  wrapper functions while complete `lowerModuleWithPlan` consumes planned
  crosscall helper specs directly.
- Extended semantic-plan coverage for planned aggregate return word layouts,
  direct ToYul helper naming, planned native transfer return words, and
  plan-only crosscall helper emission.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- Scalar and aggregate crosscall expression call construction still go through
  the `IR.lean` compatibility facade.

Next step:

- Move scalar crosscall expression call construction, or create/create2 helper
  construction, behind a narrower `ToYul` boundary.

### EVM ModulePlan Helper Discovery Consumption Slice

Commit: this commit

Summary:

- Added `CrosscallHelperSpec.plainTransfer` to the EVM semantic plan so plain
  native value-transfer helpers survive the plan boundary.
- Routed complete `lowerModuleWithPlan` helper emission through `ModulePlan`
  fields for checked arithmetic, crosscall, create/create2, local-array getter,
  and nested local-array getter helpers.
- Preserved best-effort diagnostic behavior by falling back to compatibility
  helper rediscovery when the entrypoint plan is incomplete.
- Added semantic-plan coverage for planned native transfer helpers, crosscall
  helper emission, create helper emission, and plan-driven module helper
  emission.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- Crosscall expression and helper body construction still live in `IR.lean`;
  this slice only makes helper discovery and module helper emission consume the
  semantic plan fields for complete plans.

Next step:

- Move crosscall helper naming/body construction behind a `CrosscallPlan ->
  ToYul` boundary, then migrate scalar crosscall expression calls off the
  compatibility facade.

## 2026-07-04

### EVM ReturnPlan Typed Names To-Yul Slice

Commit: this commit

Summary:

- Added `ReturnPlan.localNames`, `Plan.abiReturnName`, and
  `Plan.returnLocalNames`.
- Populated planned return names from `Lower.returnPlan`, using `result` for
  scalar/dynamic returns and `__proof_forge_return_<n>` for aggregate ABI
  words.
- Added `ToYul.returnTypedNames` and routed
  `ToYul.entrypointFunctionDefinition` through `ReturnPlan`.
- Kept `IR.abiReturnName`, `IR.abiReturnNames`, and
  `IR.abiReturnTypedNames` as compatibility aliases around the planned return
  path.
- Extended `Tests/EvmSemanticPlan.lean` to cover planned return local names and
  direct `ReturnPlan -> TypedName` lowering.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
just evm-diagnostics
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- Entrypoint body statements still come from `IR.lean`; broader
  `EntrypointPlan.body -> Yul` lowering remains staged.

Next step:

- Continue migrating supported entrypoint body statement sequences behind
  `StmtPlan -> Yul` helpers.

### EVM EntrypointPlan Function Shell To-Yul Slice

Commit: this commit

Summary:

- Added `AbiParamPlan.localNames` and populated it from `Lower`, covering
  static ABI-flattened parameter names and dynamic `bytes`/`string`
  `<name>__length` / `<name>__data_ptr` locals.
- Added `ToYul.entrypointParamTypedNames` and
  `ToYul.entrypointFunctionDefinition`, so the internal entrypoint `funcDef`
  shell is emitted from an `EntrypointPlan`.
- Routed `IR.lowerEntrypointParams` and `IR.lowerEntrypointWithPlan` through
  these plan-to-Yul helpers while keeping body statement lowering in the
  compatibility facade.
- Routed `lowerModuleWithPlan` through `lowerEntrypointsWithPlan`, so module
  lowering consumes the same planned entrypoints used by dispatch lowering.
- Preserved diagnostic priority by falling back to compatibility lowering when
  best-effort diagnostic plans do not contain a complete entrypoint list.
- Extended `Tests/EvmSemanticPlan.lean` to cover planned dynamic parameter
  local names, typed params, and direct entrypoint function shell output.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
just evm-diagnostics
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- Entrypoint body statements still come from `IR.lean`; broader
  `EntrypointPlan.body -> Yul` lowering remains staged.
- Incomplete best-effort diagnostic plans still fall back to compatibility
  lowering so user-facing diagnostics are not masked by plan-shape errors.

Next step:

- Continue migrating supported entrypoint body statement sequences behind
  `StmtPlan -> Yul` helpers.

### EVM EntrypointPlan Call Wrapper To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.entrypointFunctionName`,
  `ToYul.entrypointPlanFunctionName`, and `ToYul.entrypointCallExpr`.
- Kept `IR.yulFunctionName` as a compatibility alias while routing planned
  dispatcher call expression construction through `ToYul`.
- Added a plan-name consistency check in `IR.entrypointCallExprWithPlan`.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct planned entrypoint call
  expression generation for the dynamic ABI probe.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- Full entrypoint function definition and body lowering still live in the
  `IR.lean` compatibility facade.

Next step:

- Continue moving supported `StmtPlan -> Yul` body lowering out of the
  compatibility facade.

### EVM AbiParamPlan Calldata Decode To-Yul Slice

Commit: this commit

Summary:

- Added `AbiParamPlan.headWordIndex`, plus `AbiParamPlan.isDynamic` and
  `AbiParamPlan.headWordCount` helpers, so the semantic plan carries calldata
  head layout for entrypoint parameters.
- Updated `Lower.entrypointParamPlans` to compute head-word indices while
  building entrypoint parameter plans.
- Added `ToYul.entrypointCallArgs` and
  `ToYul.abiParamValidationAndDecodeStatements`, moving dispatcher call
  arguments and calldata validation/decode statement assembly behind
  `AbiParamPlan -> Yul`.
- Removed the temporary `IR.lean` `AbiParamLayout` path; the compatibility
  facade now obtains parameter plans and delegates call-arg/decode generation
  to `ToYul`.
- Extended `Tests/EvmSemanticPlan.lean` to check head-word indices, direct
  planned call args, and dynamic `bytes` decode statement shape.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- `IR.lean` still wraps the planned call args in the final internal function
  call expression.
- Full entrypoint body lowering still uses the compatibility facade while the
  staged `StmtPlan -> Yul` migration continues.

Next step:

- Move the final dispatch call wrapper or broader entrypoint body lowering
  behind `EntrypointPlan -> Yul`.

### EVM DispatchPlan Default-Case To-Yul Slice

Commit: this commit

Summary:

- Added `DispatchDefaultPlan` and `DispatchPlan` to the EVM semantic plan.
- Filled `ModulePlan.dispatch` from `Lower.buildFullModulePlan`, including the
  ordinary revert default case and UUPS proxy fallback case.
- Moved revert and UUPS default-case Yul AST construction into `ToYul`, with
  `IR.lean` keeping compatibility aliases for existing callers.
- Routed `lowerModuleWithPlan` through `IR.dispatchBlockWithPlan`, so module
  lowering consumes `plan.dispatch` instead of re-selecting proxy/default
  behavior from the raw IR module.
- Extended `Tests/EvmSemanticPlan.lean` to cover Counter dispatch defaults,
  direct `DispatchPlan -> Yul` output, and UUPS proxy fallback dispatch output.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- ABI validation/decode statements and function-call argument assembly still
  live in the `IR.lean` compatibility facade.
- `dispatchBlockWithPlan` still zips raw IR entrypoints with planned
  entrypoints by order while the full dispatch body lowering remains staged.

Next step:

- Move calldata validation/decode behind an ABI decode plan consumed by
  `ToYul`.

### EVM EntrypointPlan Dispatch Block To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.abiParamPlanIsDynamic`,
  `ToYul.entrypointPlanHasDynamicParams`, and
  `ToYul.dispatchBlockStatement`.
- Moved dynamic ABI free-memory-pointer initialization into `ToYul`, keyed from
  `EntrypointPlan.params` before emitting the selector switch.
- Routed `IR.dispatchBlock` through `dispatchCaseWithPlan`, so it carries the
  same surface plans used to assemble dispatch cases into the final dispatch
  block helper.
- Kept ABI validation/decode statements, function-call argument assembly, and
  proxy fallback selection in the compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct static and dynamic
  dispatch-block helper output plus the integrated Counter and dynamic ABI
  dispatch block shapes.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json
git diff --check
lake build
```

Known limitations:

- ABI validation/decode and function-call argument assembly still live in
  `IR.lean`.
- Proxy fallback selection still happens before the `ToYul` dispatch-block
  helper receives the default case.

Next step:

- Move calldata validation/decode or proxy/default-case planning behind
  `EntrypointPlan -> Yul`.

### EVM EntrypointPlan Dynamic Dispatch Return To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.dynamicDispatchReturnStatements` for dynamic `bytes`/`string`
  dispatcher return-data encoding from a `ReturnPlan`.
- Routed dynamic `IR.dispatchReturnStatements` through the helper, alongside
  the existing static return helper.
- Kept ABI validation/decode statements, function-call argument assembly,
  dynamic-param free-memory-pointer initialization, and proxy fallback behavior
  in the compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct dynamic return helper
  output and the integrated dynamic ABI dispatch block shape.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/dynamic-abi-ir-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ABI validation/decode and function-call argument assembly still live in
  `IR.lean`.
- Dynamic-parameter free-memory-pointer setup still lives in `dispatchBlock`.

Next step:

- Move calldata validation/decode or full dispatch-block setup behind
  `EntrypointPlan -> Yul`.

### EVM EntrypointPlan Static Dispatch Return To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.staticDispatchReturnStatements`, `ToYul.dispatchResultName`,
  and `ToYul.dispatchResultNames` for unit and static ABI-word dispatcher
  return-data encoding.
- Routed non-dynamic `IR.dispatchReturnStatements` through the helper using the
  `ReturnPlan` from `Lower.buildEntrypointSurfacePlan`.
- Preserved existing ABI validation/decode statements, function-call argument
  assembly, dynamic `bytes`/`string` return encoding, dynamic-param memory
  initialization, and proxy fallback behavior in the compatibility facade.
- Removed the old duplicate dispatcher result-name helper from `IR.lean`.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct unit and static
  ABI-word return helper output plus the integrated Counter dispatch path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/ir-counter-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ABI validation/decode and function-call argument assembly still live in
  `IR.lean`.
- Dynamic `bytes`/`string` dispatch return encoding still uses the
  compatibility path.

Next step:

- Move calldata validation/decode or dynamic return encoding behind
  `EntrypointPlan -> Yul`.

### EVM EntrypointPlan Dispatch Case To-Yul Slice

Commit: this commit

Summary:

- Added `Lower.buildEntrypointSurfacePlan` for selector/ABI entrypoint surfaces
  without requiring the entrypoint body to lower into `StmtPlan`.
- Added `ToYul.dispatchSelectorExpr`, `ToYul.entrypointDispatchCase`, and
  `ToYul.dispatchSwitchStatement` for the selector switch frame.
- Routed `IR.dispatchCase` and `IR.dispatchBlock` through those helpers while
  preserving the existing ABI validation, function-call argument assembly,
  return encoding, dynamic-parameter memory initialization, and proxy fallback
  behavior.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct dispatch-case helper
  output and the integrated Counter dispatch switch shape.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/ir-counter-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Dispatch return encoding and ABI decode/validation statements still live in
  the compatibility facade.
- The surface helper intentionally avoids body-plan validation; full
  `EntrypointPlan -> Yul` dispatch lowering remains a later slice.

Next step:

- Move calldata guard/decode or return-data encoding helpers behind
  `EntrypointPlan -> Yul`, or continue with `CrosscallPlan` extraction.

### EVM EventPlan Core Block To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.eventEmitCoreStatement` to assemble the final event Yul block
  from an `EventPlan`, already-lowered indexed-topic statements, and
  non-indexed data words.
- Moved signature topic setup, indexed-topic statement placement, data-word
  `mstore` placement, and final `log1`-`log4` selection behind that helper.
- Kept event field expression evaluation, aggregate flattening, and indexed
  aggregate topic word derivation in the `IR.lean` compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerEventEmitCoreStmt` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/event-ir-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Field expression evaluation and aggregate/event-field flattening still live
  in the compatibility facade.
- The helper starts from pre-lowered indexed-topic statements and data words;
  full event lowering is not yet a pure `EventPlan -> Yul` path.

Next step:

- Move event data-word and indexed-topic expression lowering fully behind
  `EventPlan -> Yul`, or continue with `EntrypointPlan` / `CrosscallPlan`
  extraction.

### EVM Scalar Control Flow StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.ifElseStmtPlanStatements`,
  `ToYul.boundedForStmtPlanStatements`, and `ToYul.boundedForConditionPlan` for
  scalar control-flow frame assembly.
- Routed scalar `ifElse` frames through the helper when the condition is in the
  supported scalar plan subset.
- Routed `boundedFor` frames through the helper with a synthesized
  `index < stopExclusive` condition plan.
- Kept branch/loop body lowering and environment sequencing in the `IR.lean`
  compatibility facade; the helpers own the final Yul `switch` and `for`
  frames.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerStatement` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/conditional-ir-smoke.sh
scripts/evm/loop-ir-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Branch/loop body lowering and statement sequencing still live in the
  compatibility facade.
- Unsupported `ifElse` condition shapes still use the compatibility fallback.

Next step:

- Move recursive `StmtPlan -> Yul` body lowering into `ToYul`, or continue
  extracting event and expression assembly paths.

### EVM Whole Struct Storage Write StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.StorageStructWriteField`,
  `ToYul.storageStructWriteEffectPlanStatements`, and
  `ToYul.storageStructWriteEffectStmtPlanStatements` for whole-struct
  `storageScalarWrite` assembly.
- Routed whole-struct storage writes through the helper for supported local
  struct sources, storage-struct read sources, and struct literals whose field
  expressions are in the scalar plan subset.
- Kept struct metadata lookup, source validation, and field source expansion in
  the `IR.lean` compatibility facade, while `ToYul` owns the final snapshot
  temp declarations and field-slot `sstore` block.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerEffectStmt` path for struct-literal whole-struct writes.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/storage-struct-ir-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Struct literals with field expressions outside the scalar plan subset still
  use the compatibility fallback.
- Struct metadata lookup and field source expansion still live in `IR.lean`.

Next step:

- Move another aggregate statement shape behind `StmtPlan.effect` /
  `EffectPlan -> ToYul`, or start deeper storage slot/path planning.

### EVM Storage Path AssignOp Effect StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.storagePathAssignOpEffectPlanStatements` and
  `ToYul.storagePathAssignOpEffectStmtPlanStatements` for statement-position
  `storagePathAssignOp` assembly.
- Routed `storagePathAssignOp` through the helper when the assign RHS is in the
  supported scalar plan subset, while preserving the existing output shapes for
  direct map-key compound assignment, direct slot updates, and nested-map
  value/presence updates.
- Reused the IR facade storage-path target selection from the
  `storagePathWrite` slice, so path slot computation and path-shape diagnostics
  remain in `IR.lean` while `ToYul` owns the final compound-update assembly.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerEffectStmt` path for direct map, array, struct field,
  struct-array field, and nested-map storage paths.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Storage-path slot computation still lives in the `IR.lean` compatibility
  facade.
- Whole-struct storage writes still use their existing compatibility path.

Next step:

- Move whole-struct storage write assembly or storage-path slot planning deeper
  behind semantic-plan/ToYul boundaries.

### EVM Storage Path Write Effect StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.StoragePathWriteTarget`,
  `ToYul.storagePathWriteEffectPlanStatements`, and
  `ToYul.storagePathWriteEffectStmtPlanStatements` for statement-position
  `storagePathWrite` assembly.
- Routed `storagePathWrite` through the helper when the write value is in the
  supported scalar plan subset, while preserving the existing output shapes for
  direct `mapKey`, array `index`, struct `field`, struct-array `index`+`field`,
  and nested consecutive-`mapKey` paths.
- Kept path slot computation and path-shape diagnostics in the `IR.lean`
  compatibility facade, with `ToYul` owning the final helper call,
  `sstore(slot, value)`, or nested-map value/presence block assembly.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerEffectStmt` path for array and nested-map storage paths.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `storagePathAssignOp` still uses the existing compatibility facade for
  statement assembly.
- Whole-struct storage writes still use their existing compatibility path.

Next step:

- Move `storagePathAssignOp` assembly or whole-struct storage write assembly
  behind `StmtPlan.effect` / `EffectPlan -> Yul` helpers.

### EVM Struct Field Write Effect StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.structFieldWriteEffectPlanStatements` and
  `ToYul.structFieldWriteEffectStmtPlanStatements` for statement-position
  `storageStructFieldWrite` and `storageArrayStructFieldWrite` assembly.
- Routed direct storage struct field writes through the helper when the value is
  in the supported scalar plan subset.
- Routed storage struct-array field writes through the helper when both index
  and value are in the supported scalar plan subset.
- Kept direct struct field slot lookup and struct-array field slot metadata in
  the `IR.lean` compatibility facade, while the helper owns the final
  `sstore(slot, value)` assembly.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerEffectStmt` path for both struct field write shapes.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice covers direct field-write effects only. Whole-struct storage
  writes and storage-path field writes still use their existing compatibility
  paths.

Next step:

- Move storage-path write assembly or whole-struct storage write assembly behind
  `StmtPlan.effect` / `EffectPlan -> Yul` helpers.

### EVM Array Write Effect StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.arrayWriteEffectPlanStatements` and
  `ToYul.arrayWriteEffectStmtPlanStatements` for statement-position
  `storageArrayWrite` assembly.
- Routed statement-position fixed storage array writes through the helper when
  both index and value are in the supported scalar plan subset.
- Kept array state root slot and length lookup in the `IR.lean` compatibility
  facade, with the final slot expression still assembled through the existing
  array slot helper boundary.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct `StmtPlan.effect`
  helper output, planned array index lowering, planned value lowering, and the
  integrated `lowerEffectStmt` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice covers direct fixed storage array writes only. Storage-path array
  writes and struct-array field writes still use their existing compatibility
  paths.

Next step:

- Move storage-path write assembly or struct-array field write assembly behind a
  `StmtPlan.effect` / `EffectPlan -> Yul` helper.

### EVM Map Write Effect StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.mapWriteEffectPlanStatements` and
  `ToYul.mapWriteEffectStmtPlanStatements` for statement-position
  `storageMapInsert` / `storageMapSet` assembly.
- Routed statement-position map writes through the helper when both key and
  value are in the supported scalar plan subset.
- Kept map root slot lookup, expression-position set-return map writes, and
  storage-path map writes in the `IR.lean` compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct `StmtPlan.effect`
  helper output and the integrated `lowerEffectStmt` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice covers statement-position direct map writes only.
  Expression-position return-old-value map writes and storage-path map writes
  still use their existing compatibility paths.

Next step:

- Move storage array writes or storage-path write assembly behind a
  `StmtPlan.effect` / `EffectPlan -> Yul` helper.

### EVM Scalar Storage Effect StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.scalarStorageEffectPlanStatements` and
  `ToYul.scalarStorageEffectStmtPlanStatements` for scalar
  `storageScalarWrite` / `storageScalarAssignOp` statement assembly.
- Routed non-struct scalar storage writes and scalar storage compound
  assignments through the helper when their value expression is in the
  supported scalar plan subset.
- Kept state-layout slot resolution and struct storage writes in the `IR.lean`
  compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct `StmtPlan.effect`
  helper output and the integrated `lowerEffectStmt` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice covers scalar storage effects only. Struct storage writes, array
  writes, map writes, storage paths, and event effects still need separate
  `StmtPlan -> Yul` / `EffectPlan -> Yul` extraction slices.

Next step:

- Move one of the remaining storage-path or map/array storage effect assembly
  shapes behind a plan-to-Yul helper.

### EVM Scalar Assignment StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.scalarAssignmentStmtPlanStatements` for narrow direct scalar
  local `StmtPlan.assign` and `StmtPlan.assignOp` assembly.
- Routed direct scalar local assignment and compound assignment through the
  helper when the RHS is in the supported scalar plan subset.
- Kept aggregate locals, static/dynamic array element targets, struct fields,
  and other assignable path forms on the compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output and the
  integrated `lowerAssignStmt` / `lowerAssignOpStmt` paths.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice covers direct scalar local assignment only. Array elements, struct
  fields, nested aggregate paths, and storage writes still need their own
  `StmtPlan -> Yul` extraction slices.

Next step:

- Move a storage-effect or path-assignment assembly shape behind a
  `StmtPlan -> Yul` helper, or start extracting control-flow statement assembly.

### EVM Scalar Return StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.scalarReturnStmtPlanStatements` for the narrow scalar
  `StmtPlan.return` assembly path.
- Routed scalar single-word returns for `U32`, `U64`, `Bool`, `Hash`, and
  `Address` through the helper when the returned value is in the supported
  scalar plan subset.
- Kept return ABI name selection and aggregate/dynamic return handling in the
  `IR.lean` compatibility facade.
- Extended `Tests/EvmSemanticPlan.lean` to cover direct helper output, returned
  storage reads, and `leaveAfterReturn` appending a Yul `leave`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice covers only single-word scalar return statement assembly.
  Bytes/string, fixed-array, struct, and aggregate crosscall returns still use
  the compatibility facade.

Next step:

- Move direct scalar assignment or scalar compound assignment behind a
  `StmtPlan -> Yul` helper.

### EVM Scalar Assert StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added `ToYul.scalarAssertStmtPlanStatements` for the narrow scalar
  `StmtPlan.assert` / `StmtPlan.assertEq` assembly path.
- Kept EVM runtime error payload selection in the `IR.lean` compatibility
  facade and passed the chosen revert body into `ToYul`, so target-neutral
  statement assembly does not learn EVM error ABI details.
- Routed scalar `assert` and `assertEq` statements through the helper when their
  operands are in the supported scalar plan subset; unsupported aggregate or
  field shapes remain on the compatibility path.
- Extended `Tests/EvmSemanticPlan.lean` to cover both direct helper output and
  integrated `lowerStatement` output for `assert` and `assertEq`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- This slice moves scalar assertion statement assembly only. Assignment,
  return, storage-effect, control-flow, and event statement assembly still need
  broader `StmtPlan -> Yul` extraction.

Next step:

- Move the next statement assembly shape, likely scalar return assignment or
  direct scalar assignment, behind a `StmtPlan -> Yul` helper.

### EVM Scalar Binding StmtPlan-To-Yul Slice

Commit: this commit

Summary:

- Added a narrow `ToYul.scalarBindingStmtPlanStatements` helper that lowers
  `StmtPlan.letBind` and `StmtPlan.letMutBind` into Yul `varDecl` statements.
- Routed scalar `let` and `let mut` statement assembly through that helper for
  supported scalar initializer expressions.
- Kept unsupported aggregate or field initializer shapes on the compatibility
  facade until broader `StmtPlan -> Yul` lowering exists.
- Extended `Tests/EvmSemanticPlan.lean` to assert both the direct helper output
  and the integrated `lowerStatement` path for checked arithmetic and
  storage-read initializers.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
```

Known limitations:

- Only scalar binding statement assembly uses the `StmtPlan -> ToYul` helper.
  Assignments, returns, control flow, storage effects, and event effects remain
  in the compatibility facade.

Next step:

- Move the next scalar statement assembly shape, such as assert/assertEq or
  return assignment, behind a `StmtPlan -> Yul` helper.

### EVM Whole-Struct Storage Write Plan-To-Yul Slice

Commit: this commit

Summary:

- Routed whole-struct `storageScalarWrite` struct-literal field values through
  `ExprPlan -> ToYul` for supported scalar field expressions.
- Preserved the existing field temporary snapshot before storage writes, so
  self-referential struct storage rewrites keep their current behavior.
- Extended `Tests/EvmSemanticPlan.lean` to assert plan-lowered checked
  arithmetic and storage-read field values for whole-struct storage writes.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/storage-struct-ir-smoke.sh
```

Known limitations:

- Local struct sources, storage-struct read sources, and statement-level
  storage-struct write assembly still use the compatibility facade.

Next step:

- Move another statement assembly shape behind `StmtPlan -> Yul`.

### EVM Storage-Path Write Plan-To-Yul Slice

Commit: this commit

Summary:

- Routed nested map `storagePathWrite` value lowering through
  `ExprPlan -> ToYul` for supported scalar RHS expressions.
- Routed `storagePathAssignOp` key/value lowering through the same boundary
  for direct `mapKey`, `index`, `field`, `index`+`field`, and nested
  consecutive-`mapKey` paths.
- Kept path slot assembly on the existing direct slot helpers and
  `StorageSlotPlan -> ToYul` boundary.
- Extended `Tests/EvmSemanticPlan.lean` to assert plan-lowered checked
  arithmetic and storage-read RHS expressions across the storage-path write
  and assign-op branches.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/map-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
```

Known limitations:

- Whole-struct storage writes and statement-level storage-path assembly still
  use the compatibility facade.

Next step:

- Move another statement assembly shape behind `StmtPlan -> Yul`, or migrate
  whole-struct storage write values through a dedicated plan-level slice.

### EVM Struct-Field Write Plan-To-Yul Slice

Commit: this commit

Summary:

- Routed `storageStructFieldWrite` value lowering through `ExprPlan -> ToYul`
  for supported scalar field values.
- Routed `storageArrayStructFieldWrite` value lowering through the same
  boundary while keeping struct-array slot assembly on `StorageSlotPlan ->
  ToYul`.
- Extended `Tests/EvmSemanticPlan.lean` to assert plan-lowered checked
  arithmetic values for scalar struct fields and storage-read values for
  struct-array fields.
- Updated `just evm-semantic-plan` to prebuild `EvmStorageStructProbe` for
  clean checkout reliability.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/storage-struct-ir-smoke.sh
```

Known limitations:

- Storage-path field writes and whole-struct writes still use the compatibility
  path.

Next step:

- Move storage-path write values through `ExprPlan -> ToYul`.

### EVM Array Write Plan-To-Yul Slice

Commit: this commit

Summary:

- Routed `storageArrayWrite` value lowering through `ExprPlan -> ToYul` for
  supported scalar write values.
- Kept array slot assembly on the existing `StorageSlotPlan -> ToYul` boundary.
- Extended `Tests/EvmSemanticPlan.lean` to assert plan-lowered checked
  arithmetic values and storage-read values for array writes.
- Updated `just evm-semantic-plan` to prebuild `EvmStorageArrayProbe` for clean
  checkout reliability.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/storage-array-ir-smoke.sh
```

Known limitations:

- Storage-path array writes and struct-array field writes still use the
  compatibility path.

Next step:

- Move struct-field writes or storage-path writes through `ExprPlan -> ToYul`.

### EVM Map Write Plan-To-Yul Slice

Commit: this commit

Summary:

- Routed `storageMapInsert`/`storageMapSet` statement writes through
  `ExprPlan -> ToYul` for supported scalar key/value expressions before calling
  the EVM map write helper.
- Routed return-old-value map writes through the same boundary before calling
  the EVM map set-return helper.
- Extended `Tests/EvmSemanticPlan.lean` to assert plan-lowered checked
  arithmetic keys, storage-read values, and checked arithmetic set-return
  values.
- Updated `just evm-semantic-plan` to prebuild `EvmMapProbe` for clean
  checkout reliability.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake build ProofForge.Backend.Evm
just evm-semantic-plan
scripts/evm/map-ir-smoke.sh
scripts/evm/typed-map-ir-smoke.sh
```

Known limitations:

- Storage-path map writes still use the compatibility path. Array writes,
  struct-field writes, and storage-path writes remain separate migration
  slices.

Next step:

- Move array write or storage-path write value lowering through
  `ExprPlan -> ToYul`.

### EVM Example CI Import Prebuild Fix

Commit: this commit

Summary:

- Fixed `scripts/evm/build-examples.sh` so a clean checkout prebuilds the
  `ProofForge.*` modules imported by EVM example contracts before invoking the
  `proof-forge` frontend.
- Moved the ERC-20 `Transfer`/`Approval` event ABI compatibility override into
  the plan-side validation path so `EventPlan` keeps standard
  `address,address,uint256` signatures instead of silently deriving `uint64`
  topics from the portable scalar type.
- Added a semantic-plan regression covering ERC-20 standard event field ABI
  mapping and the default non-ERC20 `U64 -> uint64` event mapping.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Validate
just evm-semantic-plan
scripts/evm/build-examples.sh
```

Known limitations:

- This does not remove the duplicate compatibility implementation in
  `ProofForge.Backend.Evm.IR`; it only keeps the new `Validate`/`Lower` path
  semantically aligned while the facade still exists.

Next step:

- Continue the EVM semantic-plan migration by moving another storage write
  shape, such as map or array writes, through `ExprPlan -> ToYul`.

### EVM Scalar Storage Effect Plan-To-Yul Slice

Commit: this commit

Summary:

- Routed scalar `storageScalarWrite` value lowering through
  `ExprPlan -> ToYul` for supported scalar RHS expressions.
- Routed scalar `storageScalarAssignOp` RHS lowering through the same boundary
  before applying the existing checked arithmetic assignment operator.
- Extended `Tests/EvmSemanticPlan.lean` to assert Yul AST shapes for
  plan-driven scalar storage writes and storage compound assignments.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/ir-counter-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- This slice only moves scalar storage effect values. Struct storage writes,
  map writes, array writes, struct-field writes, storage-path writes, and
  aggregate snapshots remain on the compatibility facade.

Next step:

- Migrate another storage write shape through `ExprPlan -> ToYul`, or continue
  extracting event field value planning.

### EVM EventFieldPlan-To-Yul Topic Assembly Slice

Commit: this commit

Summary:

- Added `EventPlan.indexedFields` and `EventPlan.dataFields` helpers so event
  lowering can consume planned field views instead of re-deriving them from
  raw IR arrays.
- Moved event data-word `mstore` assembly and indexed scalar/aggregate topic
  assembly into `ProofForge.Backend.Evm.ToYul`.
- Routed indexed event topic lowering through `EventFieldPlan -> ToYul`, while
  preserving the compatibility facade for field expression evaluation and
  aggregate flattening.
- Extended `Tests/EvmSemanticPlan.lean` to assert scalar indexed-topic and
  aggregate indexed-topic Yul statement shapes.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/event-ir-smoke.sh
```

Known limitations:

- Field expression evaluation and aggregate flattening still happen in
  `IR.lean`. The full event path is not yet a standalone `EventPlan -> Yul`
  lowering pass.

Next step:

- Continue extracting field value planning/flattening, or switch to the next
  high-impact semantic-plan slice such as storage effect writes.

### EmitWat Coverage Manifest CI Fix

Commit: this commit

Summary:

- Added explicit `Tests/EmitWatCoverage.tsv` entries for the expanded
  `ContextField` constructors that direct EmitWat does not lower today.
- Classified the EVM-only block/gas/origin/coinbase/block-hash context reads
  as `unsupported` for EmitWat, preserving the existing direct-WAT host surface
  of `userId`, `contractId`, and `checkpointId`.

Validation run:

```sh
scripts/near/check-ir-coverage-manifest.py --manifest Tests/EmitWatCoverage.tsv --label emitwat-ir-coverage
```

Known limitations:

- This only fixes manifest completeness. It does not add new EmitWat context
  lowering.

Next step:

- Keep CI green before continuing backend migration slices.

### EVM EventPlan-To-Yul Topic Assembly Slice

Commit: this commit

Summary:

- Added `ToYul` helpers for event signature topic construction, indexed topic
  names, indexed field counting, and final `log1`-`log4` statement selection.
- Routed `IR.lean` event emission through `Lower.eventPlanForFields` so the
  signature topic and final log statement are driven by `EventPlan`.
- Kept compatibility wrappers for existing `IR.packedUtf8Words`,
  `IR.eventSignatureTopicStatements`, `IR.eventIndexedTopicName`, and
  `IR.eventLogBuiltinName` callers.
- Extended `Tests/EvmSemanticPlan.lean` to assert the plan-to-Yul topic0 and
  indexed log statement shapes.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Event data word evaluation and indexed aggregate hashing still use the
  compatibility facade after `EventPlan` determines the event shape. Full
  `EventPlan -> Yul` extraction remains a later slice.

Next step:

- Move event data-word and indexed aggregate topic assembly behind explicit
  `EventPlan -> Yul` inputs, or migrate storage effect write values through
  `ExprPlan -> ToYul`.

### EVM Scalar Event Field Plan-To-Yul Assembly Slice

Commit: this commit

Summary:

- Routed scalar event data word lowering through the supported
  `ExprPlan -> ToYul` expression boundary.
- Routed scalar indexed event topic lowering through the same boundary before
  emitting the existing `log1`-`log4` Yul shape.
- Extended `Tests/EvmSemanticPlan.lean` to lock Yul AST shapes for plan-driven
  event data expressions and indexed storage-backed topic expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- This slice only moves scalar event word expressions. Aggregate event
  flattening, indexed aggregate topic hashing, event statement sequencing,
  crosscalls, creates, metadata planning, and full `EventPlan -> Yul` assembly
  extraction remain later semantic-plan slices.

Next step:

- Extract event signature topic, indexed topic, and data-word assembly behind
  `EventPlan -> Yul`, or continue migrating storage effect writes through
  `ExprPlan -> ToYul`.

### EVM Scalar Control-Flow Condition Plan-To-Yul Assembly Slice

Commit: this commit

Summary:

- Routed scalar `ifElse` conditions through the supported
  `ExprPlan -> ToYul` expression boundary before emitting the existing Yul
  `switch` shape.
- Routed synthesized `boundedFor` loop guards through the same expression
  boundary by building the scalar predicate `index < stopExclusive`.
- Extended `Tests/EvmSemanticPlan.lean` to lock Yul AST shapes for plan-driven
  conditional and loop guard expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/conditional-ir-smoke.sh
scripts/evm/loop-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- This slice only moves control-flow condition expressions. Statement
  sequencing, branch and loop body assembly, early-return handling, dynamic
  aggregate helper snapshots, storage effect writes, events, crosscalls, and
  create paths still move over in later semantic-plan slices.

Next step:

- Start extracting narrow `StmtPlan -> Yul` assembly helpers, or migrate event
  field/value expression lowering through `ExprPlan -> ToYul`.

### EVM Scalar Assignment Plan-To-Yul Assembly Slice

Commit: this commit

Summary:

- Routed direct scalar `assign` RHS lowering through the supported
  `ExprPlan -> ToYul` expression boundary.
- Routed direct scalar `assignOp` RHS lowering through the same boundary before
  applying the existing checked arithmetic / bitwise assignment operator.
- Extended `Tests/EvmSemanticPlan.lean` to lock Yul AST shapes for scalar
  assignment and compound-assignment RHS expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assign-op-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- This slice covers direct scalar assignment and direct scalar compound
  assignment RHS expressions. Whole-aggregate assignment, dynamic aggregate
  helper snapshots, storage effect writes, branch conditions, events,
  crosscalls, and create paths still move over in later semantic-plan slices.

Next step:

- Move scalar `ifElse` and `boundedFor` condition lowering through
  `ExprPlan -> ToYul`, or start extracting statement-plan to Yul assembly
  helpers outside the compatibility facade.

### EVM Scalar Return Plan-To-Yul Assembly Slice

Commit: this commit

Summary:

- Routed single-word EVM IR return expressions for `U32`, `U64`, `Bool`, and
  `Hash` through the supported scalar `ExprPlan -> ToYul` expression boundary.
- Kept aggregate return flattening and aggregate crosscall return helper
  assignment on the existing compatibility paths for later plan-level slices.
- Extended `Tests/EvmSemanticPlan.lean` to lock scalar return assignment Yul AST
  shapes for checked arithmetic returns and scalar storage reads.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/expression-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
```

Known limitations:

- This slice covers only single-word scalar return expressions. ABI aggregate
  returns, dispatch return-data encoding, assignment RHS lowering, branch
  conditions, event data, crosscalls, and create paths still move over in later
  semantic-plan slices.

Next step:

- Move another scalar statement expression path, likely assignment RHS or
  `ifElse` / `boundedFor` conditions, to consume `ExprPlan` directly.

### EVM Scalar Assert Plan-To-Yul Assembly Slice

Commit: this commit

Summary:

- Reused the supported scalar `ExprPlan -> ToYul` expression boundary for EVM
  IR `assert` and `assertEq` guard expressions.
- Renamed the scalar plan support predicate and lowering helper to reflect
  their broader use beyond local-binding initializers.
- Extended `Tests/EvmSemanticPlan.lean` to lock the Yul AST shape for scalar
  assertion guards lowered through the plan-to-Yul path.
- Fixed `just evm-semantic-plan` to build the imported Counter and EventProbe
  example modules before `lean --run`, removing the gate's dependence on
  preexisting `.olean` files.

Validation run:

```sh
just evm-semantic-plan
lake build ProofForge.Backend.Evm.IR
```

Known limitations:

- This slice only moves scalar assertion guard expressions through
  `ExprPlan -> ToYul`. Statement sequencing, returns, assignments, aggregate
  expressions, crosscalls, creates, event emission, dispatch, ABI flattening,
  and metadata layout still move over in later semantic-plan slices.
- Unsupported aggregate/crosscall plan nodes continue to fail explicitly or use
  the compatibility facade where their migration has not started.

Next step:

- Move the next narrow statement path, likely scalar `return` or assignment
  RHS lowering, to consume `ExprPlan` directly with golden Yul and runtime
  smoke coverage.

### EVM Scalar Let Plan-To-Yul Assembly Slice

Commit: this commit

Summary:

- Added `ProofForge.Backend.Evm.ToYul.exprPlanExpr`, a semantic-plan to Yul
  expression adapter for the supported scalar expression subset.
- Routed scalar `let` / `let mut` initializer lowering through
  `Lower.buildExprPlan -> ToYul.exprPlanExpr` when the initializer is inside
  that supported scalar subset.
- Added an explicit `IR.lean` compatibility boundary from the existing
  `TypeEnv`/`LowerError` facade types to the newer `Validate`/`Lower` types.
- Extended `Tests/EvmSemanticPlan.lean` to lock Counter scalar storage reads
  and checked addition through the plan-to-Yul path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-semantic-plan
scripts/evm/ir-counter-smoke.sh
scripts/evm/expression-ir-smoke.sh
scripts/evm/context-ir-smoke.sh
```

Known limitations:

- This slice intentionally covers scalar local-binding initialization only.
  Aggregate, crosscall, create, return, assertion, assignment, and full
  statement lowering still use the `IR.lean` compatibility assembly path until
  their own migration slices add plan-level coverage.
- `ToYul.exprPlanExpr` returns explicit unsupported diagnostics for plan nodes
  that are not valid in this scalar expression path.

Next step:

- Move the next statement path, likely scalar `assert`/`assertEq` or scalar
  `return`, to consume `ExprPlan` directly and add the corresponding golden
  Yul / Foundry smoke coverage.

### EVM Entrypoint Body Semantic Plans

Commit: this commit

Summary:

- Added structural IR-to-`ExprPlan` / `StmtPlan` lowering in
  `ProofForge.Backend.Evm.Lower`.
- `Lower.buildEntrypointPlan` now validates and stores each entrypoint body in
  `EntrypointPlan.body` instead of leaving the body empty.
- Extended `Tests/EvmSemanticPlan.lean` to lock Counter's planned
  `initialize`, `increment`, and `get` bodies, including storage scalar
  effects and checked addition.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower
just evm-plan
just evm-semantic-plan
```

Known limitations:

- Final Yul AST assembly still runs through the compatibility lowering in
  `IR.lean`; this slice only makes the semantic plan carry the structured body
  needed for the next migration step.
- Storage path segments are still carried in their portable IR form inside
  `EffectPlan.storagePath*` nodes.

Next step:

- Move a narrow expression or statement assembly path from `IR.lean` to consume
  the new `ExprPlan` / `StmtPlan` nodes directly, with golden Yul and Foundry
  smokes proving behavior is unchanged.

### EVM Storage Slot Plan Array Coverage

Commit: this commit

Summary:

- Extended `StorageSlotPlan` with storage array and struct-array field slot
  shapes.
- Added `ToYul.storageSlotExpr` lowering for `__proof_forge_array_slot` and
  `__proof_forge_struct_array_slot` helper calls.
- Routed `IR.lean` storage array and struct-array field slot lowering through
  the plan-to-Yul boundary while keeping compatibility facade functions.
- Extended `Tests/EvmPlan.lean` to lock the new slot plans, helper
  requirements, and rendered Yul expressions.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan ProofForge.Backend.Evm.ToYul
lake env lean --run Tests/EvmPlan.lean
lake build ProofForge.Backend.Evm.IR
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
```

Known limitations:

- `IR.lean` is still the compatibility facade for expression/statement
  lowering; the semantic-plan migration is not complete until `ExprPlan`,
  `StmtPlan`, entrypoint, event, crosscall, and metadata planning own the
  remaining lowering decisions.

Next step:

- Continue the EVM semantic-plan migration with `ExprPlan`/`StmtPlan` or
  entrypoint dispatch planning, keeping golden Yul and Foundry smokes as the
  behavior lock.

### EVM Example Stdlib Build Gate Fix

Commit: this commit

Summary:

- Added the new `ProofForge.Contract.Stdlib.*` modules to
  `ProofForge/Contract.lean` so a package-level contract build owns the stdlib
  import surface.
- Updated `scripts/evm/build-examples.sh` to build `ProofForge.Contract` in
  addition to the `proof-forge` executable before loading example sources. This
  fixes clean-checkout failures where stdlib example imports had no generated
  `.olean` files.

Validation run:

```sh
rm -rf build/evm
scripts/evm/build-examples.sh
```

Known limitations:

- The script still requires Foundry `cast` and `solc`; this change only fixes
  the Lean module availability side of the EVM example gate.

Next step:

- Re-run CI and continue EVM target-note/RFC cleanup once the build-examples
  step is green.

### EVM Target Note Unified Pipeline Cleanup

Commit: this commit

Summary:

- Rewrote `docs/targets/evm.md` and its zh mirror around the current
  `contract_source` / `ContractSpec` -> portable IR -> EVM semantic plan ->
  Yul AST/printer -> `solc` pipeline.
- Replaced the `.evm-methods` product workflow with ABI/selector derivation
  from `ContractSpec`; legacy sidecar support is now described only as an RFC
  0009 compatibility-window behavior.
- Updated the EVM module layout, example workflow, metadata source-kind text,
  and gate description to match the unified backend.
- Marked CS-6.1 complete in the Workstream 34 backlog.

Validation run:

```sh
scripts/i18n/check-sync.sh
python3 scripts/translate-docs.py --check
git diff --check
```

Known limitations:

- Historical RFCs still contain old EVM/LCNF narrative as project history; CS-6.3
  owns the broader decision/RFC cleanup.

Next step:

- Continue CS-6.3 by aligning RFC 0004 / decision text with the now-current EVM
  product pipeline, or move to CS-3 SDK capability blockers.

### Development Standards EVM Legacy Cleanup

Commit: this commit

Summary:

- Updated `docs/development-standards.md` to list the current Lake roots from
  `lakefile.lean` instead of the removed `ProofForge.Evm` /
  `ProofForge.Compiler.LCNF.EmitYul` roots.
- Clarified that `ProofForge.Backend.Evm` is compiler implementation code, not a
  product authoring SDK.
- Updated authoring guidance so new `Examples/` files use `contract_source`,
  while backend-only probes live under `Tests/` or `ProofForge/IR/Examples/`.
- Synchronized the zh mirror and backlog status for CS-6.2.

Validation run:

```sh
scripts/i18n/check-sync.sh
python3 scripts/translate-docs.py --check
git diff --check
```

Known limitations:

- Broader stale references remain in historical RFCs and target notes; those are
  tracked by CS-6.1 and CS-6.3 rather than this standards-only cleanup.

Next step:

- Continue CS-6.1 by rewriting `docs/targets/evm.md` around the
  `contract_source` -> portable IR -> EVM semantic plan -> Yul pipeline.

### Portable Counter Template Target-First Build

Commit: this commit

Summary:

- Made `templates/portable-counter/Counter.lean` directly consumable by the
  `ContractLoader` by aligning its namespace with the file basename, so the
  generated `Counter.spec` is found without an explicit `--module` override.
- Rewrote the template README to use real
  `proof-forge build --target evm|solana-sbpf-asm|wasm-near` commands against
  the template `.lean` source instead of fixture-only `emit` commands.
- Documented how to run the existing `portable-counter-multi-target` smoke with
  `PORTABLE_COUNTER_SOURCE=templates/portable-counter/Counter.lean`.

Validation run:

```sh
lake env lean templates/portable-counter/Counter.lean
lake env proof-forge build --target evm --root . --cast build/tools/cast-shim \
  -o build/portable-counter-template/Counter.bin \
  --yul-output build/portable-counter-template/Counter.yul \
  --artifact-output build/portable-counter-template/Counter.proof-forge-artifact.json \
  templates/portable-counter/Counter.lean
lake env proof-forge build --target solana-sbpf-asm --root . \
  -o build/portable-counter-template/Counter.s \
  --artifact-output build/portable-counter-template/Counter.solana-artifact.json \
  templates/portable-counter/Counter.lean
lake env proof-forge build --target wasm-near --root . \
  -o build/portable-counter-template/near \
  --artifact-output build/portable-counter-template/Counter.near-artifact.json \
  templates/portable-counter/Counter.lean
PORTABLE_COUNTER_SOURCE=templates/portable-counter/Counter.lean \
PORTABLE_COUNTER_OUT=build/portable-counter-template \
CAST=build/tools/cast-shim \
just portable-counter-multi-target
scripts/i18n/check-sync.sh
python3 scripts/translate-docs.py --check
git diff --check
```

Known limitations:

- The checked EVM build still needs Foundry `cast`; the local validation command
  can use the repository's ignored `build/tools/cast-shim` when Foundry is not
  installed.
- A public `proof-forge init` command is still open; this slice only makes the
  checked-in starter template executable by the current target-first build path.

Next step:

- Continue CS-4 by adding a standalone project scaffold or keep moving through
  CS-6 stale EVM-native documentation cleanup if DX docs remain the larger
  source of confusion.

### Source-Backed Testkit Shared Scenarios

Commit: this commit

Summary:

- Added optional `scenario.source` support to the Rust testkit manifest model.
- Switched Counter and ValueVault testkit scenarios to
  `Examples/Shared/Counter.lean` and `Examples/Shared/ValueVault.lean`.
- Updated the EVM, Solana, and NEAR harnesses so those scenarios build
  target-first artifacts from shared `.lean contract_source` modules before
  executing behavior traces.
- Extended scenario artifact assertions for `contract-sdk` metadata, NEAR
  metadata, Solana source/IDL/client outputs, Solana IDL JSON embedding, and
  metadata file references.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target evm --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target wasm-near --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target wasm-near --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target solana-sbpf-asm --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm --trace
just testkit
lake build
scripts/i18n/check-sync.sh
python3 scripts/translate-docs.py --check
git diff --check
```

Known limitations:

- EVM `contract_source` builds still need Foundry `cast` or the local ignored
  test shim for selector hydration.
- Live deploy gates remain separate from deterministic testkit parity.

Next step:

- Continue CS-5/CS-3 by broadening the `contract_source` surface beyond
  Counter/ValueVault while keeping the three primary target scenarios green.

### Shared Contract Source Equivalence Gate

Commit: this commit

Summary:

- Added `Tests/SharedContractSource.lean` to compare the product-facing shared
  `.lean contract_source` examples against their canonical `ContractSpec`
  modules and paired legacy `.learn` fixtures.
- Covered both Counter and ValueVault module equivalence. ValueVault also
  checks that the Solana package manifest rendered from shared `.lean` source
  matches the manifest rendered from the legacy `.learn` fixture.
- Added `just shared-contract-source` and wired the gate into `just
  solana-lean`, so the default CI-safe Solana/authoring path now protects this
  shared-source boundary.

Validation run:

```sh
just shared-contract-source
```

Known limitations:

- This gate compares the current shared Counter/ValueVault portable surface; it
  does not yet prove equivalence for future Token-2022 or richer account/PDA
  authoring extensions.

Next step:

- Continue CS-1/CS-5 by making the unified testkit consume the shared
  `contract_source` files directly for all three primary targets.

### Shared ValueVault Contract Source Multi-Target Smoke

Commit: this commit

Summary:

- Added `Examples/Shared/ValueVault.lean` as the application-facing
  chain-neutral ValueVault `contract_source` module.
- Switched `scripts/portable/value-vault-smoke.sh` from the legacy
  `Examples/Learn/ValueVault.learn` fixture to the shared `.lean` source.
- The smoke now builds the same source file for EVM, Solana sBPF, and
  NEAR/Wasm. Solana contract_source builds now emit IDL and TS client files
  alongside assembly, manifest, and metadata.
- NEAR EmitWat metadata now records `sourceKind: contract-sdk` for
  contract_source builds while preserving `portable-ir` for direct IR fixtures.

Validation run:

```sh
lake env lean Examples/Shared/ValueVault.lean
lake build proof-forge
scripts/portable/value-vault-smoke.sh
```

Known limitations:

- Solana ELF assembly/linking remains optional through
  `PROOF_FORGE_VALUE_VAULT_ELF=1`.
- The legacy `.learn` ValueVault source remains useful for parser equivalence,
  but it is no longer the product-facing smoke input.

Next step:

- Extend the unified testkit and docs so contract_source-authored Counter and
  ValueVault are the default examples for Solana, EVM, and NEAR review.

### FV-8 ValueVault IR Invariant Anchor

Commit: this commit

Summary:

- Added `ProofForge.Contract.Examples.ValueVaultInvariant` as the first
  user-facing contract-invariant proof surface over the executable IR
  semantics.
- The module runs the chain-neutral ValueVault `contract_source` module through
  the shared 11-step scenario and checks the observable return trace.
- Added decide-checkable accounting and net-value invariants over the final IR
  state: `balance + released + fees` equals externally supplied value, final
  storage matches the scenario inputs, and `get_net_value` equals
  `balance - fees`.
- Wired the new FV-8 theorem anchors into `Tests/NearWasmFormal.lean`.

Validation run:

```sh
lake build ProofForge.Contract.Examples.ValueVaultInvariant
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- This is a concrete executable-trace invariant for the ValueVault worked
  example, not yet a source-level invariant DSL or a universally quantified
  theorem over all valid inputs.
- It proves the invariant against the FV-2 IR semantics. It does not yet
  transport the invariant to emitted EVM, Solana, or NEAR artifacts.

Next step:

- Generalize the FV-8 shape so `contract_source` authors can state reusable
  invariants near the contract and then connect those invariants to the FV-4
  backend obligations.

### FV-4 NEAR Offline-Host Execution Surface Anchor

Commit: this commit

Summary:

- Added a decide-checkable NEAR/Wasm offline-host execution-surface obligation
  for Counter and ValueVault.
- The obligation derives each exported call's Borsh/little-endian input bytes
  and expected `runtime/offline-host` return-line fragment from the same IR
  trace boundary used by the formal anchors.
- Extended `scripts/near/emitwat-ci-smoke.sh` so CI now emits the ValueVault
  WAT fixture and executes the full 11-step ValueVault sequence through
  `runtime/offline-host`, checking typed inputs, return words, event logs, and
  fuel-based `near_gas` observations.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
scripts/near/emitwat-ci-smoke.sh
git diff --check
```

Known limitations:

- This is an execution-surface anchor, not a full Wasm semantics proof and not
  a proof about Wasmtime or the NEAR runtime.
- Aggregate Borsh input values remain outside this small obligation shape.

Next step:

- Deepen the NEAR FV-4 boundary from host-observed IO fragments toward a
  focused Wasm/offline-host semantics model.

### FV-4 NEAR ValueVault Artifact Surface Anchor

Commit: this commit

Summary:

- Extended the NEAR/Wasm artifact-surface obligation from Counter to
  ValueVault.
- The ValueVault obligation inspects the `Compiler.Wasm.AST` emitted by
  `EmitWat.lowerModule` and checks all seven exported entrypoints:
  `initialize`, `deposit`, `charge_fee`, `release`, `snapshot`,
  `get_balance`, and `get_net_value`.
- The check pins the host-boundary shape for storage reads/writes, block
  context reads, value returns, event logging, memory export, storage-key data
  segments, and event-name data segments.
- Wired `value_vault_emitwat_artifact_surface_ok` into
  `Tests/NearWasmFormal.lean`.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- This is still an AST-level obligation, not a full Wasm evaluator or a proof
  about `wat2wasm`, Wasmtime, or the NEAR runtime.
- It proves the emitted artifact surface for the shared ValueVault scenario;
  the next NEAR FV-4 step is to relate offline-host execution observations to
  the same IR trace boundary.

Next step:

- Add an executable offline-host trace obligation shape for the NEAR Counter
  and ValueVault scenarios, then align it with the existing IR observable
  traces.

### FV-4 NEAR EmitWat Artifact Surface Anchor

Commit: this commit

Summary:

- Added a decide-checkable NEAR/Wasm artifact-surface obligation in
  `ProofForge.Backend.WasmNear.Refinement`.
- The new obligation inspects the `Compiler.Wasm.AST` produced by
  `EmitWat.lowerModule` instead of matching WAT text. It pins the Counter
  artifact's required host imports, exported entrypoint call sequences,
  helper-function calls into NEAR storage/return host functions, memory export,
  and the `count` storage-key data segment.
- Wired `counter_emitwat_artifact_surface_ok` into
  `Tests/NearWasmFormal.lean`, advancing the NEAR FV-4 path beyond export-name
  coverage while keeping the claim below full Wasm semantic preservation.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- This is an AST-level artifact-surface proof, not a full Wasm evaluator or a
  theorem about `wat2wasm`, Wasmtime, or the NEAR runtime.
- It covers the Counter artifact first. Richer EmitWat fixtures beyond
  ValueVault still need their own NEAR FV-4 obligations.

Next step:

- Connect the offline-host execution trace shape to the same observable IR
  trace boundary.

### FV-2 IR Semantics Metatheory Anchors

Commit: this commit

Summary:

- Added deterministic-result theorems for the executable IR semantics:
  `evalExpr_deterministic`, `execStatements_deterministic`, and
  `runEntrypointWithArgs_deterministic`.
- Added `boundedForRemaining` and `boundedForRemaining_decreases`, a Nat
  measure anchor for `boundedFor` execution. This records the structurally
  decreasing loop argument that the FV-2 roadmap calls out as the bounded-loop
  termination basis.
- Wired the new theorem anchors into `Tests/NearWasmFormal.lean` so the
  existing formal anchor gate checks them alongside the IR trace obligations.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- These are metatheory anchors over the current executable interpreter, not a
  full progress/preservation proof for every typed IR node.
- `execBoundedFor` remains in the existing partial mutual interpreter; this
  slice proves the decreasing measure used by the bounded loop step.

Next step:

- Continue FV-2 with progress/preservation for the validated typed subset, or
  deepen FV-4 on the NEAR side toward artifact-level execution obligations.

### FV-1 Target Capability Routing Anchors

Commit: this commit

Summary:

- Added theorem-friendly target checker helpers:
  `firstUnsupportedCapability?`, `allCapabilitiesSupported`,
  `firstSolanaMetadataCall?`, and `targetExtensionMetadataAllowed`.
- Routed `defaultResolve` through `requireCapabilityPlan`, so capability
  support and Solana target-extension isolation share one checked boundary.
- Added `ProofForge.Target.Formal` with Lean theorems proving that a
  successfully checked `CapabilityPlan` satisfies the FV-1 `checkedBy`
  predicate.
- Added `Tests/TargetFormal.lean` to exercise representative `resolveSpec`
  boundaries: EVM ValueVault success, Solana rejection of generic
  `crosscall.invoke`, and EVM rejection of Solana extension metadata.

Validation run:

```sh
lake build ProofForge.Target.Formal ProofForge.Target
lake env lean --run Tests/TargetFormal.lean
git diff --check
```

Known limitations:

- This proves the local checked boundary used by `resolveSpec`; it does not
  yet prove a full induction over every future adapter implementation.
- The executable `Tests/TargetFormal.lean` smoke is intentionally not a new
  public `just` gate yet, to avoid changing the validation surface before the
  current documentation sync state is cleaned up.

Next step:

- Extend FV-1 from the default adapter boundary to any non-default target
  adapter once those adapters expose custom resolution logic, then continue the
  formal roadmap toward NEAR artifact-level execution obligations.

### Solana Token-2022 Direct CPI Live Gate

Commit: this commit

Summary:

- Added target-first CLI fixture support for
  `--fixture spl-token-2022-cpi --format s|elf`, backed by the existing
  `ProofForge.Solana.Examples.SplToken2022Cpi` spec.
- Added `Tests/solana/spl_token_2022_cpi_web3_smoke.mjs`, which deploys the
  generated program on Surfpool and exercises Token-2022 transfer-fee direct
  CPI behavior: initialize transfer-fee config, transfer with fee, withdraw
  withheld fees from accounts, harvest withheld fees to mint, withdraw from
  mint, and update transfer-fee parameters.
- Added `scripts/solana/spl-token-2022-cpi-web3-smoke.sh` and the
  `just solana-spl-token-2022-cpi-web3` entrypoint. The shell gate validates
  generated artifact metadata before deploying the ELF.

Validation run:

```sh
lake build ProofForge.Cli ProofForge.Cli.Fixture ProofForge.Solana.Examples.SplToken2022Cpi
lake build proof-forge
lake env proof-forge check --target solana-sbpf-asm --fixture spl-token-2022-cpi --format s
lake env proof-forge check --target solana-sbpf-asm --fixture spl-token-2022-cpi --format elf
lake env lean --run Tests/SolanaCpiPacking.lean
node --check Tests/solana/spl_token_2022_cpi_web3_smoke.mjs
just solana-spl-token-2022-cpi-web3
git diff --check
```

Known limitations:

- This live gate covers the Token-2022 transfer-fee direct-CPI program path.
  The generated `initialize_non_transferable_mint` direct CPI remains covered
  by static packing/artifact checks; its generated-program live behavior should
  be split into a separate mint-initialization smoke.

Next step:

- Continue Solana-first validation expansion with either the non-transferable
  direct-CPI live smoke or the next ecosystem CPI target from the P1 gap list.

### Solana Lean Gate Example Build

Commit: this commit

Summary:

- Made `just solana-lean` explicitly build `ProofForge.Solana.Examples`
  before running tests that import individual Solana example modules.
- This fixes clean CI caches where `lake env lean --run
  Tests/SolanaAccountRealloc.lean` could fail before the imported
  `ProofForge.Solana.Examples.AccountRealloc` `.olean` existed.

Validation run:

```sh
just solana-lean
git diff --check
```

Known limitations:

- This is a CI/build-order fix only; it does not change generated contracts.

Next step:

- Re-run CI, then continue Solana direct Token-2022 live validation.

### Solana Token-2022 Direct CPI Lowering

Commit: this commit

Summary:

- Added direct Solana SDK helpers for Token-2022 transfer-fee and
  non-transferable CPI paths, including typed `Surface` wrappers.
- Lowered Token-2022 instruction data for
  `initialize_transfer_fee_config`, `transfer_checked_with_fee`,
  `withdraw_withheld_tokens_from_mint`,
  `withdraw_withheld_tokens_from_accounts`, `harvest_withheld_tokens_to_mint`,
  `set_transfer_fee`, and `initialize_non_transferable_mint`.
- Added the built-in Token-2022 program id
  `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb` to direct CPI program-id
  packing, so these calls no longer fall back to placeholder program ids.
- Extended Solana manifest and IDL metadata with fee source, transfer-fee
  authorities, basis points, maximum fee, and withheld-account count fields.
- Added `ProofForge.Solana.Examples.SplToken2022Cpi` and expanded
  `Tests/SolanaCpiPacking.lean` to check Token-2022 tags, data lengths,
  value bindings, program id packing, manifest fields, IDL fields, and
  entrypoint helper calls.

Validation run:

```sh
lake build ProofForge.Solana ProofForge.Solana.Surface ProofForge.Backend.Solana.Extension ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Idl ProofForge.Solana.Examples.SplToken2022Cpi
lake env lean --run Tests/SolanaCpiPacking.lean
scripts/i18n/check-sync.sh
just solana-lean
just solana-light
```

Known limitations:

- This closes the static SDK/backend lowering side of the Token-2022 P0 for
  transfer-fee and non-transferable flows. A live Surfpool/Web3.js gate for
  generated direct-CPI programs, plus a Pinocchio/reference equivalence fixture,
  remains a validation expansion.
- `contract_source` shorthand syntax is still limited to the older SPL Token
  helpers; Token-2022 direct CPI is currently available through the builder API
  and typed `Surface` wrappers.

Next step:

- Continue Solana-first SDK hardening with direct Token-2022 live validation,
  then move to the next primary-chain SDK P0 backlog item.

### Solana Account Realloc API

Commit: this commit

Summary:

- Added Solana account reallocation as a target-specific account action rather
  than a portable IR node.
- Added `ProofForge.Solana.reallocAccount`, typed
  `ProofForge.Solana.Surface.reallocAccount`, and `contract_source`
  `realloc account to N;` syntax for static account-data growth/shrink targets.
- Realloc actions now emit `solana.account_realloc` metadata, automatically
  require a writable program-owned account constraint, and appear in
  `manifest.toml` plus the generated Solana IDL under `accountReallocs`.
- Lowered the action to an sBPF helper that checks
  `current_data_len + MAX_PERMITTED_DATA_INCREASE >= new_size` and writes the
  serialized account `data_len` field, with a dedicated `error_realloc` path.
- Added `ProofForge.Solana.Examples.AccountRealloc` and
  `Tests/SolanaAccountRealloc.lean`, wired into `just solana-lean`.

Validation run:

```sh
lake build ProofForge.Solana ProofForge.Solana.Surface ProofForge.Contract.Source ProofForge.Backend.Solana.Extension ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Idl ProofForge.Solana.Examples.AccountRealloc
lake env lean --run Tests/SolanaAccountRealloc.lean
```

Known limitations:

- This closes the static source/lowering/API side of the realloc P0. Dynamic
  target lengths, zero-initialization semantics, and a dedicated
  Surfpool/Web3.js behavior gate remain follow-up validation expansions.

Next step:

- Continue Solana-first SDK P0 hardening with Token-2022 direct sBPF CPI
  lowering for transfer-fee and non-transferable flows.

### Solana SPL Token Close-Account Lowering

Commit: this commit

Summary:

- Added SPL Token `close_account` CPI helpers to the Solana builder API and
  typed source surface.
- Added `contract_source` and legacy `.learn` syntax for
  `spl_token_close_account(...)` declarations and invocations.
- Lowered `spl-token.close_account` instruction data to the standard one-byte
  SPL Token tag `9` and preserved token-account data-size metadata for the
  closed account.
- Added `ProofForge.Solana.Examples.SplTokenCloseAccountCpi`,
  `Examples/Learn/SplTokenCloseAccountCpi.learn`, and package-rendering checks
  for manifest account schemas, data-layout metadata, data length, instruction
  tag store, and helper calls.
- Added legacy and target-first CLI fixture routes for
  `spl-token-close-account-cpi` in sBPF assembly and ELF formats.

Validation run:

```sh
lake build ProofForge.Solana ProofForge.Solana.Surface ProofForge.Contract.Source ProofForge.Contract.Learn ProofForge.Backend.Solana.SbpfAsm ProofForge.Solana.Examples.SplTokenCloseAccountCpi
lake env lean --run Tests/SolanaCpiPacking.lean
lake env lean --run Tests/LearnSource.lean
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-close-account-cpi --format s -o /tmp/proof-forge-spl-token-close-account.s --artifact-output /tmp/proof-forge-spl-token-close-account.json
```

Known limitations:

- This closes the source/lowering side of the close-account P0. A dedicated
  Surfpool/Web3.js behavior gate and Pinocchio reference-equivalence gate for
  close-account are still follow-up validation expansions.

Next step:

- Continue Solana-first SDK P0 hardening with the user-facing realloc API, then
  Token-2022 direct sBPF CPI lowering.

### Solana Owner Constraint Lowering

Commit: this commit

Summary:

- Extended the Solana sBPF account-validation prologue beyond signer/writable
  and current-program owner checks.
- Added executable-account owner validation for `owner = "executable"` using
  the serialized account executable flag.
- Added named owner-account validation: arbitrary owner strings now resolve to
  another declared account in the same Solana account schema and compare the
  target account owner pubkey against that owner account key.
- Added an explicit lowering diagnostic for unknown owner-account references
  instead of silently skipping the check.
- Added `Tests/SolanaAccountConstraints.lean` and wired it into
  `just solana-lean`.

Validation run:

```sh
lake build ProofForge.Backend.Solana.SbpfAsm
lake env lean --run Tests/SolanaAccountConstraints.lean
```

Known limitations:

- This closes the signer/writable/owner account-constraint row. The broader
  Solana SDK P0 still has user-facing realloc API work open.

Next step:

- Continue Solana-first SDK P0 hardening with realloc ergonomics, then
  Token-2022 direct sBPF CPI lowering.

### Solana Compute-Budget Transaction Advice

Commit: this commit

Summary:

- Added a Solana SDK `ComputeBudgetAdvice` path that routes through
  `runtime.compute_units` capability metadata without adding a portable IR
  node or pretending the contract can raise its own transaction budget.
- Extended Solana package metadata so `manifest.toml`, the generated IDL, and
  generated TypeScript clients expose per-entrypoint compute-unit limit and
  priority-fee advice.
- Added generated client helpers that prepend `ComputeBudgetProgram`
  instructions before the ProofForge program instruction for the selected
  entrypoint.
- Added `Tests/SolanaComputeBudgetInstruction.lean` and wired it into
  `just solana-lean`.

Validation run:

```sh
lake build ProofForge.Backend.Solana.Extension ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Idl ProofForge.Backend.Solana.Client ProofForge.Solana
lake env lean --run Tests/SolanaComputeBudgetInstruction.lean
```

Known limitations:

- This closes the transaction-side ComputeBudgetInstruction blocker. The
  existing in-program `runtime.compute_units` syscall coverage remains the
  separate path for reading/logging remaining compute units.
- The generated client emits budget pre-instructions from metadata; live
  Surfpool/Web3 transaction-budget behavior can be added as a follow-up smoke
  once the broader SDK client ergonomics pass starts.

Next step:

- Continue Solana-first SDK P0 hardening with account constraint ergonomics
  (`close`/`realloc`) or Token-2022 direct sBPF CPI lowering.

### FV-4 EVM Event-Log Trace Obligations

Commit: this commit

Summary:

- Extended `ProofForge.IR.Semantics.State` with observable event logs, so
  `eventEmit` and `eventEmitIndexed` now record evaluated indexed/data fields
  instead of acting only as field-evaluation no-ops.
- Extended the focused EVM/Yul executable model so `log0` through `log4`
  record topic and memory data words while preserving the existing selector
  execution API for older obligations.
- Added EVM refinement log comparison for ValueVault business events and
  EventProbe scalar, typed scalar, multi-topic indexed, struct-data, and
  hashed aggregate-indexed event cases, including signature-derived `topic0`
  under the focused interpreter's deterministic pseudo-keccak model.
- Added a CI-visible theorem anchor for the EventProbe IR trace.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Known limitations:

- The focused Yul model compares emitted log topics/data against the IR trace,
  including signature-derived `topic0`, but it still uses the existing
  deterministic pseudo-keccak surrogate rather than claiming cryptographic EVM
  `keccak256` correctness.
- Event declarations remain represented through `eventEmit` effects rather
  than a richer first-class event schema in the portable IR.

Next step:

- Deepen the Wasm/NEAR side from export coverage toward artifact-level
  execution obligations, then move FV-2 from executable traces toward
  determinism/progress statements.

### FV-4 EVM Control-Flow Obligations

Commit: this commit

Summary:

- Extended `ProofForge.IR.Semantics` with executable `ifElse` and
  `boundedFor` semantics, including branch-local early-return propagation and
  loop-index binding.
- Extended the focused EVM/Yul executable model with bounded `for` execution,
  preserving `leave`/`return` control propagation through loop bodies and
  updates.
- Added EVM refinement obligations for `ConditionalProbe` and `EvmLoopProbe`
  so IR traces and emitted-Yul executable traces now agree for if/else storage
  updates, bounded loops, branch-local early returns, and loop-body early
  returns.
- Added CI-visible theorem anchors for the new control-flow obligations and
  updated the formal backlog to leave observable event-log traces as the next
  FV-2/FV-4 slice.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Refinement
```

Known limitations:

- Event effects are still evaluated for field expressions and executable Yul
  `log0`-`log4` calls are still accepted, but event logs are not yet modeled as
  first-class observable trace items.
- The Yul model remains a focused interpreter for generated ProofForge Yul, not
  a general EVM/Yul semantics.

Next step:

- Add observable event-log traces to the IR semantics and EVM/Yul executable
  obligation, then use EventProbe to compare emitted log topics/data against
  the IR trace.

### CLI M3 Target-First Gate Consolidation

Commit: this commit

Summary:

- Moved `Tests/CliTargetFirst.lean` into the `just cli-target-first` gate so
  the CLI M3 check now covers both executable caller scanning and target-first
  compatibility mapping parity.
- Removed the CLI mapping smoke from the Solana-only Lean gate; the same test
  now lives under the CLI product-surface gate where regressions belong.
- Expanded `Tests/CliTargetFirst.lean` across representative EVM, Solana,
  NEAR/Wasm, Psy/DPN, Aleo, Aptos, and Cloudflare target-first mappings.
- Updated RFC 0009, the RFC index, and the implementation backlog to record
  M3 as landed for executable callers while keeping M4 legacy flag removal
  deferred until the compatibility window.

Validation run:

```sh
just cli-target-first
```

Known limitations:

- This does not remove the legacy `EmitMode` parser. RFC 0009 keeps that as
  M4 work after one compatibility window.
- Historical design notes can still mention legacy aliases when they are
  documenting migration history.

Next step:

- Continue FV-2/FV-4 formal work over control-flow and observable event traces,
  or explicitly schedule the RFC 0009 M4 legacy flag removal window.

### FV-4 EVM IR-Backed Aggregate/Storage Obligations

Commit: this commit

Summary:

- Rechecked the architecture review disposition against current `main`. R1 is
  already closed by RFC 0009/D-039, and R5 is already handled by D-045/Gate P0
  plus the target roadmap, so this slice focuses on the still-valid R3 proof
  gap.
- Connected the covered FV-2 IR map/storage/aggregate traces to EVM refinement
  obligations for `EvmMapProbe`, `EvmTypedStorageProbe`,
  `EvmStorageStructProbe`, and `EvmAbiAggregateProbe`.
- Added aggregate observable-return expansion for IR arrays and structs in
  `ProofForge.Backend.Evm.Refinement`, and fixed whole-struct storage writes in
  `ProofForge.IR.Semantics` so direct field keys stay consistent after a full
  struct overwrite.
- Added CI-visible theorem anchors for the new EVM `*_ir_observable_trace_ok`
  checks through `Tests/NearWasmFormal.lean`.
- Synchronized the formal roadmap, backlog, gate notes, and the Chinese
  gate-status page so they no longer describe this EVM wiring as future work.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake build ProofForge.Backend.Evm.Refinement
lake env lean --run Tests/NearWasmFormal.lean
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- This is still an executable trace obligation, not a full proof about `solc`,
  EVM bytecode, or chain runtime execution.
- FV-2 still needs control-flow and observable-event trace semantics, and
  NEAR/Wasm still needs deeper artifact-level execution obligations beyond the
  existing export/trace anchors.

Next step:

- Extend FV-2 over `ifElse`, `boundedFor`, and observable events, then connect
  user-level invariants such as ValueVault solvency to the covered IR semantics.

### FV-2 State-Threaded Map Lifecycle Semantics

Commit: this commit

Summary:

- Refactored `ProofForge.IR.Semantics.evalExpr` so expression evaluation
  returns both the next `State` and the computed `Value`, preserving left-to-right
  effects through arrays, structs, storage path keys, assertions, events,
  `let` bindings, and returns.
- Made `storageMapInsert` and `storageMapSet` in expression position mutate
  storage while returning the previous value, matching the IR fixtures that
  model map upsert/set lifecycles.
- Added decide-checked theorem anchors for `EvmMapProbe.mapLifecycle`,
  `containsLifecycle`, and a parameterized insert/read/set/read sequence.
- Updated the formal roadmap, gate notes, and backlog so FV-2 now records
  state-threaded map lifecycle semantics as landed.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake env lean Tests/NearWasmFormal.lean
lake build ProofForge.Backend.Evm.Refinement
```

Known limitations:

- FV-2 still does not execute `ifElse` or `boundedFor` statements, and events
  are checked for field evaluation only rather than emitted as observable trace
  items.
- The EVM FV-4 aggregate/map obligations still compare Yul execution against
  expected return words; they are not yet wired to compare directly against the
  newly expanded IR traces.

Next step:

- Connect the covered FV-2 map/aggregate/storage traces to the EVM refinement
  obligations, then extend FV-2 statement execution over control flow and
  observable events.

### FV-2 Aggregate/Storage IR Semantics Slice

Commit: this commit

Summary:

- Reviewed the six-item architecture review disposition against current `main`.
  R1 and R5 are already aligned in the accepted RFC 0009 / D-039 docs and the
  primary-chain target scope, so this slice focuses on R3 rather than reopening
  capability ids or target portfolio policy.
- Extended `ProofForge.IR.Semantics` beyond scalar values with executable
  fixed-array, struct, storage-array, storage-struct-field, nested storage-path,
  and aggregate ABI value traces.
- Added decide-checked FV-2 theorem anchors for `ArrayProbe`,
  `EvmMapProbe`, `EvmStorageStructProbe`, and `EvmAbiAggregateProbe`, and wired
  them into `Tests/NearWasmFormal.lean`.
- Updated the formal roadmap/backlog/gate notes to say the first FV-2
  aggregate/storage slice has landed, while full IR-to-artifact semantic
  preservation remains open.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake env lean Tests/NearWasmFormal.lean
lake build ProofForge.Backend.Evm.Refinement
```

Known limitations:

- `storageMapInsert` / `storageMapSet` in expression position still return the
  old value without threading state through nested expression evaluation. Full
  map insert/set lifecycle traces need a state-threaded expression evaluator.
- The new FV-2 traces are not yet connected to the EVM FV-4 Yul obligations;
  they only establish the IR-side executable semantics slice.

Next step:

- Add state-threaded expression evaluation for effectful expressions, then
  wire covered aggregate/storage IR traces into the EVM/NEAR artifact
  obligations.

### Review Disposition Docs Tightening

Commit: this commit

Summary:

- Rechecked the July 2026 review disposition against current `main`: RFC 0009
  and D-039 are already aligned with the landed CLI M1 work, so this slice did
  not reopen that decision.
- Tightened public docs around the Gate P0 boundary: `docs/INDEX.md`, Chinese
  root README, and target-note indexes now agree that the primary-chain
  covenant is closed and the next active lane is CLI M3/M4 target-first
  migration before Tier-1 M3/M4 work.
- Continued the CLI M3 documentation pass by moving public EVM, Solana, NEAR,
  Psy/DPN, Aleo, and Cloudflare examples to
  `proof-forge build|emit --target ...` forms while retaining legacy aliases
  only as compatibility-window notes.

Validation run:

```sh
rg -n -- '--evm-bytecode|--emit-counter-ir|--emit-pure-math-ir|--solana-elf|--emit-counter-emitwat' README.md AGENTS.md Examples docs/INDEX.md docs/zh/INDEX.zh.md docs/targets docs/zh/targets docs/zh/examples-evm-README.zh.md docs/zh/README-root.zh.md
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Historical design/background notes still mention legacy aliases where the
  alias itself is the topic.
- `docs/validation-gates.md` was not rewritten in this slice because the
  current gate table already includes the target-first NEAR lane and the
  Chinese validation-gates translation has unrelated in-progress edits.

Next step:

- Finish executable CLI M3/M4 migration, then schedule FV-2 semantic
  preservation work before opening Tier-1 M3/M4 implementation.

### CLI M3 Target-First Regression Guard

Commit: this commit

Summary:

- Added a `cli-target-first` check that scans executable caller surfaces
  (`justfile`, `scripts/`, `testkit/`, and `Tests/`) and rejects direct
  `proof-forge --legacy-flag` invocations. The check intentionally excludes
  docs and generated build artifacts so it enforces runtime callers without
  blocking historical notes.
- Migrated the TypeScript / Cloudflare Workers Counter smoke from
  `--emit-counter-ir-ts` to
  `emit --target wasm-cloudflare-workers --fixture counter --format ts`.
- Added the target-first Cloudflare Counter mapping to the CLI compatibility
  layer and covered it in `Tests/CliTargetFirst.lean`.

Validation run:

```sh
just cli-target-first
lake build ProofForge.Cli
lake env lean Tests/CliTargetFirst.lean
scripts/ts/counter-ir-smoke.sh
```

Known limitations:

- This guard proves executable caller migration discipline; it does not delete
  the legacy parser or rewrite historical documentation examples.

Next step:

- Continue the M3 pass by migrating remaining examples/docs and only then
  prepare the M4 legacy flag removal plan.

### CLI M3 Target-First Solana Slice

Commit: this commit

Summary:

- Added target-first mapping for the portable ValueVault Solana ELF path:
  `emit --target solana-sbpf-asm --fixture value-vault --format elf` now routes
  to the existing ValueVault ELF builder instead of requiring
  `--value-vault-solana-elf`.
- Migrated the Solana PDA Web3.js smoke to the target-first SDK fixture command:
  `emit --target solana-sbpf-asm --fixture solana-sdk --format s`.
- Migrated the optional Solana ELF branch in the portable ValueVault smoke to
  target-first CLI and extended the CLI mapping smoke so this does not regress.

Validation run:

```sh
lake build ProofForge.Cli
lake env lean Tests/CliTargetFirst.lean
scripts/solana/pda-web3-smoke.sh
PROOF_FORGE_VALUE_VAULT_ELF=1 scripts/portable/value-vault-smoke.sh
```

Known limitations:

- This is an M3 migration slice, not the full M3/M4 cleanup. Two example files
  still show legacy commands, and the legacy parser remains during the
  compatibility window.

Next step:

- Continue migrating remaining examples/docs and then retire legacy flag
  aliases after the compatibility window defined by RFC 0009.

### Primary-Chain Gate P0 Sign-off

Commit: this commit

Summary:

- Closed Gate P0 after the final NEAR/Wasm target-first smoke landed and the
  remote CI run for commit `466b320` completed successfully.
- Recorded P0-3 as met: `wasm-near` now has target-first local execution,
  artifact metadata, deploy metadata, diagnostics, budget baselines, offline
  host execution, and CI coverage.
- Updated the roadmap/backlog boundary so the next active implementation lane
  is CLI M3/M4 migration before scheduling Tier-1 M3/M4 work.

Validation run:

```sh
just check
gh run view 28677055773 --json status,conclusion,headSha,url,jobs
```

Known limitations:

- Gate P0 is a production-hardening sign-off for the three primary local
  backends. It does not mean every target is fully feature-complete, and it
  does not remove the need for CLI M3/M4 cleanup or FV-2 semantic preservation
  work.

Next step:

- Migrate scripts and testkit callers from legacy flags to
  `proof-forge build|emit|check --target ...` before advancing CosmWasm/Aptos
  M3/M4.

### Wasm-NEAR Target-First Metadata Smoke

Commit: this commit

Summary:

- Fixed the target-first Wasm-NEAR `check` path so WAT fixtures are validated by
  the actual EmitWat backend instead of a generic fixture capability table.
- Extended target-first `build --target wasm-near --fixture ... --format wat`
  so it honors the selected fixture for Counter, ErrorRef, Context, Hash, and
  Map probes.
- Added EmitWat artifact and deploy metadata for target-first WAT output,
  including ABI entrypoints, capability ids, WAT/optional Wasm hashes, and the
  local offline-host deployment mode.
- Added `just near-target-first`, which checks Counter and Context target-first
  paths, validates metadata/deploy manifests, and runs the generated Counter WAT
  through `runtime/offline-host`.

Validation run:

```sh
lake build ProofForge.Cli
lake build proof-forge
just near-target-first
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build
```

Known limitations:

- The deploy manifest records a local offline-host execution mode; it does not
  create a live `near-sandbox` account deployment, public NEAR deployment, or
  wallet/key-management flow.
- Gate P0-3 should only be signed off after the GitHub Actions run for this
  commit is observed green.

Next step:

- Observe the remote CI run, then update gate status and the target roadmap to
  close NEAR/Wasm P0-3 if the new mandatory smoke stays green.

### EVM FV-4 Aggregate/Storage Trace Expansion

Commit: `3b2719a`

Summary:

- Extended `ProofForge.Backend.Evm.YulSemantics` with a deterministic
  memory-sensitive `keccak256` surrogate so the focused FV-4 interpreter can
  execute generated map value and presence-slot helpers without collapsing every
  hashed storage slot to `0`.
- Extended `ProofForge.Backend.Evm.Refinement` with decide-checked executable
  EVM/Yul obligations for `EvmMapProbe`, `EvmTypedStorageProbe`,
  `EvmStorageStructProbe`, and `EvmAbiAggregateProbe`.
- Added observable multi-word return support for aggregate ABI returns, covering
  flat struct and fixed-array return data in the executable Yul subset.

Validation run:

```sh
lake build ProofForge.Backend.Evm.YulSemantics
lake build ProofForge.Backend.Evm.Refinement
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build
```

Known limitations:

- These new obligations are EVM/Yul executable checks against expected
  observable return words. They do not yet prove map/array/struct IR semantics,
  because `ProofForge.IR.Semantics` remains scalar-only; that is still FV-2.

Next step:

- Extend FV-2 IR semantics for maps, arrays, structs, and aggregate values so
  the new EVM-only obligations can be connected back to IR traces.

## 2026-07-03

### Solana Pinocchio Live CI Lane

Commit: `a9437c1`..`3b2719a`

Summary:

- Added a mandatory GitHub Actions `solana-pinocchio-live` job for the P0
  Solana hardening lane.
- Added `scripts/solana/install-pinocchio-live-ci-tools.sh` to install/check
  Agave/Solana CLI `v3.1.12`, SBF platform-tools `v1.52`, pinned `sbpf`,
  Surfpool `v0.10.8`, and Node/npm before running the aggregate live suite.
- Hardened the Pinocchio live helper so it can fall back to Agave
  platform-tools rust/cargo with `--no-rustup-override` when rustup
  `+toolchain` dispatch is unavailable.
- Updated Gate P0 evidence so P0-1 now records the new mandatory CI lane,
  while keeping the gate open until a remote run is observed and the broader
  Solana production sign-off is complete.

Validation run:

```sh
bash -n scripts/solana/install-pinocchio-live-ci-tools.sh \
  scripts/solana/pinocchio-live-common.sh \
  scripts/solana/pinocchio-live-equivalence.sh \
  scripts/solana/pinocchio-*-live-equivalence.sh
CARGO_BUILD_SBF_BIN=cargo-build-sbf \
  SOLANA_RUSTUP_TOOLCHAIN=1.89.0-sbpf-solana-v1.52 \
  bash -c '. scripts/solana/pinocchio-live-common.sh; platformToolsRustBin'
```

Known limitations:

- The local installer self-check was interrupted after entering the SBF
  platform-tools install path because the command produced no progress output
  for over 90 seconds on this machine. The CI job covers the fresh-install path
  with a 15-minute timeout around `cargo-build-sbf --install-only`.
- This entry predates the remote sign-off run; P0-1 is closed by the follow-up
  entry below.

Next step:

- Keep the mandatory live lane green while the remaining Gate P0 work moves to
  NEAR/Wasm P0-3.

### Solana P0-1 Production Sign-off

Commit: this commit

Summary:

- Marked Solana direct sBPF backend P0-1 as signed off in
  `docs/gate-status.md`.
- Synchronized the target portfolio roadmap and implementation backlog so
  Solana P0-1 and EVM P0-2 are both treated as complete, leaving NEAR/Wasm
  P0-3 as the remaining Gate P0 blocker.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build
gh run view 28675037861 --json status,conclusion,headSha,url,jobs
```

Known limitations:

- Gate P0 is still open until NEAR/Wasm has target-first local execution and
  deploy metadata sign-off.

Next step:

- Start the NEAR/Wasm P0-3 hardening slice.

### Solana Target-First v0 ELF Live Deploy Fix

Commit: feature commit for Solana target-first ELF arch propagation

Summary:

- Fixed the target-first CLI compatibility layer so
  `proof-forge emit --target solana-sbpf-asm --format elf
  --solana-sbpf-arch v0` forwards the requested architecture into the legacy
  Solana ELF builder instead of silently falling back to the default v3 build.
- Confirmed the fixed target-first path now emits the same loader-compatible
  v0 ELF shape as the direct legacy flag: `e_flags = 0`, valid section table,
  and Agave `solana-sbpf 0.13.1` parse/load success.
- Re-ran the full local ProofForge-vs-Pinocchio live dual-deploy suite. All
  five Surfpool scenarios deployed both generated ProofForge and Pinocchio
  reference programs and matched observable state.

Validation run:

```sh
lake build proof-forge
lake env lean Tests/CliTargetFirst.lean
lake env proof-forge emit --target solana-sbpf-asm --fixture system-cpi \
  --format elf --solana-sbpf-arch v0 \
  -o build/solana-compat-check-fixed/new-v0.so \
  --artifact-output build/solana-compat-check-fixed/new-v0.json
cargo run --manifest-path /tmp/proofforge-elf-check-013/Cargo.toml -- \
  build/solana-compat-check-fixed/new-v0.so
just solana-pinocchio-system-transfer-live-equivalence
just solana-pinocchio-live-equivalence
```

Known limitations:

- This resolves the local Agave loader compatibility blocker, but Gate P0 is
  still open. The live Pinocchio suite is not yet mandatory in CI, and broader
  Solana production-grade sign-off remains tracked under Gate P0.

Next step:

- Promote the live Pinocchio suite into a reliable CI lane once Solana
  rustc/platform-tools, Surfpool, Node/npm, and port isolation are stable
  enough for mandatory remote execution.

### Solana Pinocchio Live Deploy Blocker Triage

Commit: documentation commit for Solana live deploy blocker triage

Summary:

- Ran the aggregate Pinocchio live dual-deploy gate locally with Surfpool,
  Agave `solana-cli 3.1.12`, `cargo-build-sbf 3.1.12`, and `sbpf 0.2.2`
  available.
- Confirmed the live suite does not currently fail because of missing tools:
  all five child gates build the ProofForge ELF and Pinocchio reference ELF,
  start Surfpool, then fail at ProofForge `solana program deploy --use-rpc`
  with `Failed to parse ELF file: invalid file header`.
- Triage against Agave's embedded `solana-sbpf 0.13.1` showed the generated
  ProofForge ELF is not Solana CLI loader-compatible: blueshift `sbpf build
  --arch v0` emits a one-segment bare ELF with no section table and
  `e_flags = 3`, which makes Agave use its strict v3 parser. That parser
  requires `EM_SBPF`, four program headers, a valid section-header index, and
  function-start markers. Reflagging the bytecode as v0 is also invalid because
  the v3/static-call bytecode then fails relocation with
  `RelativeJumpOutOfBounds`.
- Recorded the blocker in Gate P0 and Workstream 7 so Solana P0 does not read
  as a generic CI/toolchain-install task.

Validation run:

```sh
just solana-pinocchio-live-equivalence
cargo run --manifest-path /tmp/proofforge-elf-check-013/Cargo.toml -- \
  build/solana-pinocchio-system-transfer-live/proofforge-system-transfer-live-sbpf-project/deploy/proofforge-system-transfer-live.so \
  build/solana-pinocchio-system-transfer-live/pinocchio-system-transfer-reference.so
```

Known limitations:

- This is a blocker triage and documentation pass. It does not yet add the
  Solana loader-compatible ELF packaging path, and the live dual-deploy suite
  remains non-mandatory for CI.

Next step:

- Implement an explicit Solana CLI loader-compatibility path: either emit and
  package through the standard Solana platform-tools format, or extend the
  direct assembler pipeline to produce the strict v3 headers and function-start
  markers accepted by Agave.

### Review Follow-up: RFC, Portfolio, and Gate State Alignment

Commit: feature commit for review follow-up documentation alignment

Summary:

- Reconciled the post-review assessment with the current repository state:
  RFC 0009/D-039 already reflect CLI M1 as landed, and D-045/Gate P0 already
  freeze non-primary target advancement.
- Updated the platform gap analysis so CLI and budget work no longer read as
  unplanned or unimplemented after RFC 0009 M1, D-040, RFC 0010, and Gate G0.
- Updated the implementation backlog so Gate G0 is treated as closed and the
  remaining work is correctly scoped to Gate P0 production hardening and CLI
  M3/M4 migration.

Validation run:

```sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- This is a documentation alignment pass. It does not implement new FV-4
  storage/aggregate trace obligations or change target capability ids.

Next step:

- Continue P0 hardening in priority order, with the next EVM FV-4 slice focused
  on map/fixed-array storage obligations unless Solana live-equivalence work
  takes priority.

### EVM Expression Assertion Executable Yul Trace Obligation

Commit: feature commit for FV-4 EVM expression/assertion executable trace
obligation

Summary:

- Extended `ProofForge.IR.Semantics` with predicate expressions, boolean
  operators, casts, bitwise/shift operators, exponentiation, and assertion /
  assertion-equality statement execution for the focused scalar subset.
- Extended `ProofForge.Backend.Evm.YulSemantics` with `exp`, matching the Yul
  emitted for EVM expression probes.
- Added `expression_evm_yul_executable_trace_ok`, which runs
  `EvmExpressionProbe` through the generated selector-dispatched Yul subset and
  compares observable return words against the IR trace.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake build ProofForge.Backend.Evm.YulSemantics
lake build ProofForge.Backend.Evm.Refinement
lake build ProofForge.Backend.Evm
scripts/i18n/check-sync.sh
git diff --check
just check
```

Known limitations:

- This covers successful assertion/expression paths only. Revert/error traces,
  maps, arrays, structs, aggregate returns, and full EVM word overflow semantics
  are still future FV-4 slices.

Next step:

- Extend executable obligations to map storage and fixed-array storage probes,
  then move into struct and aggregate return/state shapes.

### EVM ValueVault Executable Yul Trace Obligation

Commit: feature commit for FV-4 ValueVault executable Yul trace obligation

Summary:

- Extended `ProofForge.IR.Semantics` with entrypoint argument binding, U32/U64
  `sub`/`mul`/`div`/`mod`, `checkpointId`, and event field evaluation as a
  no-op state effect.
- Extended `ProofForge.Backend.Evm.YulSemantics` with calldata argument words,
  calldata size, `number`, `keccak256`, and `log0` through `log4` execution as
  focused FV-4 primitives.
- Added `value_vault_evm_yul_executable_trace_ok`, which runs the shared
  ValueVault scenario through the generated selector-dispatched Yul subset and
  compares observable return words against the scalar IR trace.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake build ProofForge.Backend.Evm.YulSemantics
lake env lean ProofForge/Backend/Evm/Refinement.lean
lake build ProofForge.Backend.Evm
scripts/i18n/check-sync.sh
git diff --check
just check
```

Known limitations:

- This is still a focused FV-4 slice, not a full EVM or libyul semantics. Event
  logs are modeled as no-op after field evaluation, block number is fixed at
  zero, `keccak256` returns a deterministic placeholder for the non-observable
  log/topic paths used here, and assertions/maps/arrays/aggregates are not
  covered yet.

Next step:

- Extend executable obligations from scalar storage to assertion, map, array,
  struct, and aggregate probes, then connect ValueVault user invariants to the
  IR semantics.

### EVM Counter Executable Yul Trace Obligation

Commit: feature commit for FV-4 executable Yul trace obligation

Summary:

- Added `ProofForge.Backend.Evm.YulSemantics`, a narrow executable model for
  the Counter-shaped generated Yul subset.
- Covered selector calldata decoding, dispatcher `switch`, internal function
  calls, local variables, `sstore`, `sload`, scalar arithmetic, `mstore`, and
  EVM `return` words.
- Extended `ProofForge.Backend.Evm.Refinement` with
  `counter_evm_yul_executable_trace_ok`, which runs
  `initialize -> get -> increment -> get` through the generated Yul dispatcher
  and compares observable return words against the scalar IR trace.

Validation run:

```sh
lake build ProofForge.Backend.Evm.YulSemantics
lake env lean ProofForge/Backend/Evm/Refinement.lean
lake build ProofForge.Backend.Evm
scripts/i18n/check-sync.sh
git diff --check
just check
```

Known limitations:

- This is still a focused FV-4 slice, not a full EVM or libyul semantics. The
  interpreter fails explicitly for unsupported Yul constructs and currently
  covers the Counter path only.

Next step:

- Extend the Yul-subset interpreter and trace obligations toward ValueVault:
  multi-entry scalar storage behavior first, then assertions, maps, arrays, and
  aggregate return/state shapes.

### EVM Counter Formal Trace Surface Obligation

Commit: feature commit for FV-4 EVM surface obligation

Summary:

- Added `ProofForge.Backend.Evm.Refinement` with a `TraceObligation` for the
  Counter `initialize -> get -> increment -> get` scenario.
- Reused the scalar IR executable semantics to prove the expected observable
  trace (`0` then `1`) with `native_decide`.
- Added an EVM/Yul surface obligation that checks generated Yul has the
  selector-dispatched top-level functions required by the same trace.
- Imported the module from `ProofForge.Backend.Evm`, so the theorem is checked
  by the existing `just build` CI path.

Validation run:

```sh
lake env lean ProofForge/Backend/Evm/Refinement.lean
```

Known limitations:

- This is the first FV-4 EVM anchor, not a full EVM refinement theorem. It does
  not yet interpret Yul storage operations or return words.

Next step:

- Add a tiny Yul-subset interpreter for Counter-shaped Yul (`sstore`, `sload`,
  `add`, selector-dispatched calls, `return`) and compare its observable trace
  against the IR trace.

### Review Alignment: CLI RFC And Primary-Chain Portfolio Freeze

Commit: feature commit for review alignment

Summary:

- Accepted RFC 0009 as the durable target-first CLI surface and recorded that
  M1 has already landed through the compatibility layer; M3/M4 remain open.
- Corrected D-039 so it no longer reads as a pre-code freeze after code already
  exists, and added an explicit superseded-position note for that old wording.
- Tightened the target portfolio wording: current product implementation is
  limited to `solana-sbpf-asm` -> `evm` -> `wasm-near`; `psy-dpn`,
  `aleo-leo`, and `wasm-cloudflare-workers` are maintenance-only inventory
  until Gate P0 closes.

Validation run:

```sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- This is a documentation and governance correction. It does not implement the
  missing end-to-end proof link between source-level invariants and generated
  EVM/Wasm artifacts.

Next step:

- Start FV-4 as a separate implementation slice: add an EVM trace obligation
  patterned after the existing NEAR trace obligation, then connect it to a
  concrete generated Yul/bytecode fixture and CI gate.

### Solana Pinocchio Live Equivalence Aggregate Gate

Commit: feature commit for Pinocchio live aggregate gate

Summary:

- Added `scripts/solana/pinocchio-live-equivalence.sh` as one aggregate entrypoint
  for the five ProofForge-vs-Pinocchio live dual-deploy gates.
- Added `just solana-pinocchio-live-equivalence` so local and future profiled CI
  lanes can run the full live suite through one command.
- The aggregate gate runs every child harness, summarizes pass/skip/fail counts,
  fails on any real child failure, and returns skip code `2` when prerequisites
  are missing unless `PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP=1` is explicitly set
  for a probe lane.

Validation run:

```sh
bash -n scripts/solana/pinocchio-live-equivalence.sh scripts/solana/pinocchio-*-live-equivalence.sh
SURFPOOL=/nonexistent-proof-forge-surfpool scripts/solana/pinocchio-live-equivalence.sh
PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP=1 SURFPOOL=/nonexistent-proof-forge-surfpool scripts/solana/pinocchio-live-equivalence.sh
```

Known limitations:

- This creates the suite entrypoint and strict skip semantics; it does not yet
  install the Solana SBF toolchain in GitHub Actions or make live dual-deploy
  mandatory in default CI.

Next step:

- Add a profiled CI job that installs/checks Surfpool, Solana CLI,
  `cargo-build-sbf`, `sbpf`, Node, and npm, then runs the aggregate live suite
  without `PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP`.

### Solana Pinocchio Live Harness Shared Helper

Commit: feature commit for Pinocchio live harness hardening

Summary:

- Added a shared `scripts/solana/pinocchio-live-common.sh` helper for the five
  Pinocchio live dual-deploy harnesses.
- Centralized Solana rustup/toolchain detection, `cargo-build-sbf` invocation,
  SBF repair hints, Pinocchio ELF discovery, skip/fail handling, and Surfpool
  cleanup.
- Kept each harness-specific fixture, port, deployment, Web3.js scenario, and
  result comparison local to the existing live script.

Validation run:

```sh
bash -n scripts/solana/pinocchio-live-common.sh scripts/solana/pinocchio-*-live-equivalence.sh
just solana-pinocchio-reference-equivalence
SURFPOOL=/nonexistent-proof-forge-surfpool scripts/solana/pinocchio-system-transfer-live-equivalence.sh
```

Known limitations:

- This hardens the live harness implementation path but does not make the live
  dual-deploy gates mandatory in CI yet; that still depends on stable Solana
  rustc/platform-tools, Surfpool, Solana CLI, `sbpf`, Node, and npm
  availability in the runner.

Next step:

- Add a CI/profiled live-equivalence lane once the Solana SBF toolchain install
  path is deterministic enough for GitHub Actions, then extend reference
  coverage toward Token-2022.

### Gate G0 Closed

Commit: documentation sign-off commit

Summary:

- Closed Gate G0 in the gate ledger after recording the successful current
  remote CI run for commit `0c52fb8`.
- Clarified that Gate G0 closes only the shared behavior/resource-budget slice;
  Gate P0 remains open for the production-grade Solana, EVM, and NEAR/Wasm
  completion covenant.
- Updated the target roadmap so Tier-1/new-chain advancement stays frozen on
  Gate P0, not the now-closed G0 slice.

Validation run:

```sh
gh run watch 28658576786 --exit-status
```

Known limitations:

- P0 is still open. Solana live dual-deploy equivalence, EVM semantic-plan
  migration, and NEAR/Wasm target-first local execution/deploy metadata
  sign-off remain the next production-hardening tracks.

Next step:

- Continue P0 in implementation order: Solana live Pinocchio dual-deploy
  hardening first, then EVM semantic-plan migration, then NEAR/Wasm
  target-first deploy metadata sign-off.

### Solana Pinocchio Reference Equivalence In CI Light Gate

Commit: feature commit for Solana Pinocchio reference equivalence

Summary:

- Added source-only target-first emission for the Solana ContractSpec CPI
  fixtures (`system-cpi`, `system-create-account-cpi`, SPL Token transfer,
  ops, and authority) so reference-equivalence checks can validate artifact
  ABI/CPI metadata without requiring `sbpf`.
- Added `just solana-pinocchio-reference-equivalence` and included it in
  `just solana-light`, which is the default CI Solana gate.
- Added a CLI mapping regression test for the new target-first `--format s`
  routes and the existing `--format elf` routes.
- Updated Pinocchio reference manifests with source fixture ids while keeping
  ELF fixture ids for live dual-deploy gates.

Validation run:

```sh
lake build proof-forge
lake env lean Tests/CliTargetFirst.lean
just solana-pinocchio-reference-equivalence
```

Known limitations:

- This closes the CI-safe source/reference half of the Pinocchio track only.
  Live dual-deploy equivalence still depends on Surfpool, Solana CLI, `sbpf`,
  and stable `cargo-build-sbf`/Solana rustc platform tools.

Next step:

- Continue Workstream 7 by hardening the live Pinocchio dual-deploy harnesses
  for reproducible local/CI toolchain installation.

### ValueVault Solana Budget Baselines

Commit: feature commit for ValueVault Solana budget baselines

Summary:

- Added `--trace` to the unified testkit runner so budget work can print the
  raw per-call harness lines already stored in `CallOutcome.raw_line`.
- Fixed the EVM ValueVault testkit harness so the `CAST` environment override
  is passed through to `proof-forge emit --cast`, matching the availability
  check that decides whether the EVM branch can run locally.
- Fixed the target-first `proof-forge emit --target evm --fixture ... --format
  bytecode` compatibility mapper so it forwards `--cast` to the legacy EVM
  bytecode flags instead of silently falling back to `cast`.
- Pinned Counter `near_gas` baselines and all ValueVault `solana_cu`,
  `evm_gas`, and `near_gas` baselines in the testkit scenarios.
- Updated the Gate G0 ledger to reflect the repaired remote CI baseline and
  the now-implemented budget acceptance criteria; formal closure still waits
  for the current commit's remote CI/sign-off record.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- --help
.lake/build/bin/proof-forge emit --target evm --fixture value-vault --format bytecode --cast build/tools/cast-shim --yul-output /tmp/pf-vv.yul --artifact-output /tmp/pf-vv.json -o /tmp/pf-vv.bin
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm --trace
CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --trace
```

Known limitations:

- The testkit budget baselines are deterministic harness baselines; live-chain
  budget gates remain a separate Solana/Foundry hardening concern.

Next step:

- Run the current commit through CI, then record Gate G0 sign-off or continue
  the non-blocking Tier-0 hardening items: Solana Pinocchio CI equivalence and
  EVM semantic-plan migration.

### Unified Testkit Deploy Manifest Schema Checks

Commit: feature commit for unified testkit deploy manifest schema checks

Summary:

- Added `exists`, `kind`, and `non_empty` assertions to nested
  `[[artifact.json]]` and `[[artifact.toml]]` checks, so scenario TOML can
  express presence, absence, type, and non-empty schema constraints without
  fixture-specific scripts.
- Updated Counter and ValueVault scenarios to validate EVM deploy manifests as
  first-class artifacts, including init-code mode, absent chain profile,
  not-generated broadcast status, ABI/capability counts, and deploy manifest
  file references back to generated Yul, bytecode, and init-code artifacts.
- Added targeted type/non-empty checks for key EVM and Solana metadata/manifest
  paths that were previously only implicitly checked by equality or script
  validators.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
CAST="$PWD/build/tools/cast-shim" just testkit
```

Known limitations:

- `kind` and `non_empty` validate schema shape only; semantic relations across
  artifacts still use `[[artifact.file]]` and `[[artifact.jsonArtifact]]`.

Next step:

- Continue moving script-only artifact metadata validators into scenario TOML,
  then remove redundant script assertions once the unified testkit owns the same
  artifacts.

### Unified Testkit Structured Length Checks

Commit: feature commit for unified testkit structured length checks

Summary:

- Added `length` assertions to nested `[[artifact.json]]` and
  `[[artifact.toml]]` scenario checks for arrays, objects/tables, and strings.
- Updated Counter and ValueVault scenarios to pin generated ABI entrypoint,
  event, capability, artifact, Solana manifest instruction, Solana metadata
  instruction, and IDL instruction counts declaratively.
- Extended the structured artifact unit test so JSON and TOML length checks are
  covered in `proof-forge-testkit-core`.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
CAST="$PWD/build/tools/cast-shim" just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `length` asserts collection/string shape, not the semantic meaning of each
  item; per-entry checks still need explicit `equals` or `contains` assertions.

Next step:

- Keep migrating old schema validators into scenario TOML, then remove duplicate
  script-only assertions once the testkit owns the same generated artifacts.

### Unified Testkit JSON Artifact Equality Checks

Commit: feature commit for unified testkit JSON artifact equality checks

Summary:

- Added nested `[[artifact.jsonArtifact]]` scenario checks that compare a JSON
  value embedded in one artifact with another harness-produced JSON artifact.
- Updated the Solana ValueVault scenario so metadata must embed the same IDL
  JSON as the generated `idl` artifact.
- Moved ValueVault Solana IDL/client shape checks into scenario TOML through
  structured JSON assertions and text contains checks.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
CAST="$PWD/build/tools/cast-shim" just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- JSON equality checks currently compare JSON values only; non-JSON artifacts
  still use `matches_file`, `contains`, structured TOML checks, or file-reference
  metadata checks.

Next step:

- Continue migrating duplicate per-target schema checks into scenario-declared
  artifact expectations where the harness already exposes the generated files.

### Unified Testkit Artifact File Metadata Checks

Commit: feature commit for unified testkit artifact file metadata checks

Summary:

- Added nested `[[artifact.file]]` scenario checks that validate JSON metadata
  file entries against harness-produced artifacts by path, byte size, and
  SHA-256 hash.
- Extended the EVM testkit harness to expose generated `init-code` and
  `deploy-manifest` artifacts alongside Yul, bytecode, and metadata, so EVM
  metadata references can be asserted declaratively.
- Updated Counter and ValueVault scenarios so EVM and Solana metadata now prove
  their generated artifact references through the shared testkit runner.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
CAST="$PWD/build/tools/cast-shim" just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `[[artifact.file]]` currently validates JSON metadata entries; TOML file
  reference validation can be added if a target manifest needs the same
  path/bytes/hash relation.

Next step:

- Use the shared metadata file-reference checks to retire more duplicated
  per-target artifact hash validation from fixture-specific scripts where the
  testkit already owns the generated artifacts.

### Unified Testkit EVM ValueVault Golden

Commit: feature commit for unified testkit EVM ValueVault golden

Summary:

- Added `Examples/Evm/ValueVault.golden.yul` as the reviewed Yul source
  snapshot for the portable ValueVault scenario.
- Upgraded the `evm` Yul artifact in `testkit/scenarios/value-vault.toml` to
  check full generated-file equality through `matches_file`, while retaining
  focused substring checks for the contract object, entrypoints, logs, and
  block context access.
- ValueVault now has scenario-declared source equality for `wasm-near` WAT,
  `evm` Yul, and `solana-sbpf-asm` assembly/manifest.

Validation run:

```sh
.lake/build/bin/proof-forge --emit-value-vault-ir-yul --cast build/tools/cast-shim -o build/testkit/evm/value-vault/ValueVault.yul
solc --strict-assembly build/testkit/evm/value-vault/ValueVault.yul --bin
CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Local `just testkit` skips the ValueVault EVM runtime branch unless Foundry
  `cast` or a compatible `CAST` override is available; CI covers that branch
  with Foundry installed.

Next step:

- Move the remaining Workstream 26 M4 declarative coverage toward metadata
  hardening and retiring duplicate per-target script checks.

### Unified Testkit Solana ValueVault Golden

Commit: feature commit for unified testkit Solana ValueVault golden

Summary:

- Added `Examples/Solana/ValueVault.golden.s` and
  `Examples/Solana/ValueVault.manifest.toml` as the reviewed Solana
  source/manifest snapshots for the portable ValueVault scenario.
- Upgraded `testkit/scenarios/value-vault.toml` so the `solana-sbpf-asm`
  assembly and manifest artifacts check full generated-file equality through
  `matches_file`, while retaining focused substring checks for event lowering,
  syscall usage, storage layout, instruction names, and argument encodings.
- ValueVault now has scenario-declared source equality for `wasm-near` WAT and
  `solana-sbpf-asm` assembly/manifest. At this point, EVM Yul remained the
  only ValueVault source artifact still using source-shape checks.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- At this point, ValueVault EVM Yul still used scenario-declared source-shape
  checks instead of complete golden equality.
- Local `just testkit` skips the ValueVault EVM runtime branch when Foundry
  `cast` is unavailable; CI covers that branch with Foundry installed.

Next step:

- Add a full ValueVault EVM Yul golden once selector hydration is available in
  the validation environment used to refresh the snapshot.

### Unified Testkit Wasm ValueVault Golden

Commit: feature commit for unified testkit Wasm ValueVault golden

Summary:

- Added `Examples/WasmNear/ValueVault.golden.wat` as the portable ValueVault
  WAT golden for the `wasm-near` EmitWat path.
- Upgraded `testkit/scenarios/value-vault.toml` so its `wasm-near` artifact
  checks full generated-source equality through `matches_file`, while keeping
  focused substring checks for important imports, exports, and event logging.
- ValueVault now has scenario-declared Wasm/NEAR WAT source equality in the
  unified testkit; its EVM Yul and Solana sBPF/manifest artifacts still use
  source-shape checks until their full golden snapshots are reviewed.

Validation run:

```sh
lake env lean --run Tests/EmitWatValueVault.lean
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target wasm-near
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ValueVault EVM Yul and Solana sBPF/manifest comparisons were still
  scenario-declared source-shape checks instead of complete golden equality.
- Local `just testkit` skips the ValueVault EVM runtime branch when Foundry
  `cast` is unavailable; CI covers that branch with Foundry installed.

Next step:

- Add full ValueVault source goldens for EVM Yul and Solana sBPF/manifest once
  their emitted artifacts are stable enough to review as snapshots.

### Unified Testkit Wasm Counter Golden

Commit: feature commit for unified testkit Wasm Counter golden

Summary:

- Added `Examples/WasmNear/Counter.golden.wat` as the portable IR Counter WAT
  golden for the `wasm-near` EmitWat path.
- Moved the `wasm-near` Counter WAT equality check into
  `testkit/scenarios/counter.toml` through a scenario-declared
  `[[artifact]]` `matches_file` expectation.
- Counter now has target-source golden equality in the unified testkit for all
  three priority targets: `wasm-near` WAT, `evm` Yul, and
  `solana-sbpf-asm` assembly plus manifest.

Validation run:

```sh
lake env lean --run Tests/EmitWatSmoke.lean
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target wasm-near
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ValueVault still uses scenario-declared WAT/Yul substring checks because it
  does not yet have committed portable-source goldens.

Next step:

- Add source goldens for ValueVault once its cross-target emitted source shape
  is stable enough to review as a snapshot.

### Unified Testkit EVM Counter Golden

Commit: feature commit for unified testkit EVM Counter golden

Summary:

- Added `Examples/Evm/Counter.golden.yul` as the portable IR Counter Yul
  golden, separate from the older Lean SDK contract golden under
  `Examples/Evm/Contracts/`.
- Moved the EVM Counter Yul equality check into
  `testkit/scenarios/counter.toml` through a scenario-declared
  `[[artifact]]` `matches_file` expectation.
- Kept EVM runtime behavior in `testkit/harness-evm`; the harness now only
  publishes the generated `yul` artifact and the common scenario validator owns
  the source snapshot comparison.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target evm
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ValueVault still uses scenario-declared Yul substring checks because it does
  not yet have a committed portable-source golden.

Next step:

- Add portable-source goldens for the remaining stable testkit fixtures, then
  decide which old golden-only shell checks can be retired or moved to
  scheduled chain-authentic gates.

### Unified Testkit Unsupported Capability Diagnostics

Commit: feature commit for unified testkit diagnostic scenarios

Summary:

- Added `[[diagnostic]]` scenario expectations so testkit can run
  diagnostic-only scenarios without pretending they have runtime steps.
- Added `testkit/scenarios/unsupported-crosscall.toml`, which asserts that
  `solana-sbpf-asm` rejects the portable `crosscall.invoke` capability with
  the expected target/capability diagnostic.
- Added `Tests/TestkitSolanaCapabilityDiagnostic.lean` as the Lean-side
  diagnostic driver and wired `testkit/harness-solana` to execute it.
- Updated runner target filtering and summary output so diagnostic-only
  scenarios participate in `just testkit` but do not interfere with positive
  target runs.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
lake env lean --run Tests/TestkitSolanaCapabilityDiagnostic.lean
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario unsupported-crosscall
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target evm
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- The diagnostic scenario surface currently has one Solana capability case.
  More target/compiler diagnostics can move in as each harness exposes a
  small target-owned diagnostic driver.

Next step:

- Continue migrating deterministic artifact/source checks into scenario
  declarations, then decide which existing standalone diagnostic smokes should
  become additional `[[diagnostic]]` scenarios.

### Unified Testkit EVM Metadata Expectations

Commit: feature commit for unified testkit EVM metadata expectations

Summary:

- Added scenario-declared EVM metadata checks for Counter and ValueVault,
  covering target identity, artifact kind, fixture/source kind, declared
  capabilities, ABI entrypoint names, and bytecode-generation validation
  status.
- Removed the duplicated EVM harness metadata identity checks for
  `target`/`sourceKind`; `testkit/harness-evm` now reads metadata only for
  runtime selector dispatch.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target evm
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Local ValueVault EVM execution still skips when Foundry `cast` is not on
  `PATH`; CI covers the full path where Foundry is installed.

Next step:

- Continue migrating the remaining shell-only golden/source checks that are
  deterministic into scenario declarations, while keeping live Foundry/Anvil
  deployment gates separate.

### Unified Testkit Scenario Target Validation

Commit: feature commit for unified testkit scenario target validation

Summary:

- Tightened scenario discovery so `testkit/core` rejects empty target ids,
  duplicate target ids, and artifact expectations that reference a target not
  declared in the scenario's `targets` list.
- Added a negative unit test proving stale or mistyped artifact target
  expectations fail during `discover_scenarios`, before any target harness
  runs.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
```

Known limitations:

- This only validates scenario configuration. Harness availability still
  depends on optional target tools such as `cast`, `sbpf`, and
  `solana-keygen`.

Next step:

- Continue moving pure artifact assertions out of target harnesses and into
  scenario declarations until the remaining M4 shell-gate duplication is
  isolated to live/network-authentic smoke tests.

### Unified Testkit Solana Harness Thinning

Commit: feature commit for Solana testkit artifact validation thinning

Summary:

- Removed duplicated Solana harness metadata and manifest semantic validators
  after their checks were moved into scenario-declared
  `[[artifact.json]]`/`[[artifact.toml]]` expectations.
- Kept Solana harness parsing of `manifest.toml` instruction tags because that
  is runtime dispatch data, not a review-only artifact expectation.
- Dropped the direct `serde_json` dependency from `testkit/harness-solana`.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo check --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana
cargo test --manifest-path testkit/Cargo.toml --workspace
scripts/i18n/check-sync.sh
git diff --check
just testkit
lake build
```

Known limitations:

- The scenario still needs optional `sbpf` and `solana-keygen` before Solana
  artifact expectations execute.
- Duplicated shell gates still exist; this only removes duplicated Solana
  harness-internal artifact semantics.

Next step:

- Continue moving pure artifact assertions out of target harnesses and then
  thin duplicated shell-only golden gates once `just testkit` covers them.

### Unified Testkit Structured Artifact Assertions

Commit: feature commit for unified testkit structured artifact assertions

Summary:

- Extended `testkit/core` artifact expectations with nested
  `[[artifact.json]]` and `[[artifact.toml]]` checks.
- Structured checks support dot paths plus array indexes, for example
  `validation.manifestGeneration` and `instruction[1].tag`.
- Added scenario-declared structured checks for Solana Counter and ValueVault
  artifact metadata, manifest target/program fields, instruction names, tags,
  capabilities, and manifest-generation validation status.
- Kept the Solana harness runtime parsing in place for instruction dispatch and
  metadata loading while moving the reviewable expectations into scenario TOML.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
just testkit
```

Known limitations:

- Structured checks currently support equality and containment for JSON/TOML
  values. They do not yet provide unordered array matching or predicate filters
  such as `instruction[name=deposit]`.
- Target harnesses still own runtime-critical parsing and some semantic
  validation until those checks can be represented safely in the scenario
  language.

Next step:

- Migrate the remaining metadata/manifest semantic checks out of target
  harnesses where they are pure artifact expectations, then begin thinning
  duplicated shell-only golden gates.

### Unified Testkit M4 Artifact Expectations

Commit: feature commit for unified testkit artifact expectations

Summary:

- Added top-level `[[artifact]]` scenario expectations to `testkit/core`,
  with `target`, `name`, `matches_file`, and `contains` checks.
- Wired all three harnesses to publish named artifacts back into the common
  validator: `wat` for `wasm-near`, `yul`/`bytecode`/`metadata` for `evm`,
  and `sbpf-asm`/`manifest`/`metadata`/`idl`/`client` for
  `solana-sbpf-asm`.
- Moved the Solana Counter golden assembly and manifest comparisons into
  `testkit/scenarios/counter.toml`.
- Moved ValueVault's WAT/Yul/sBPF/manifest/metadata source-shape checks into
  `testkit/scenarios/value-vault.toml`, reducing hardcoded per-fixture
  behavior in the harnesses.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
just testkit
```

Known limitations:

- Artifact expectations currently cover whole-file equality and substring
  checks only. Structured JSON/TOML assertions still live in target harnesses
  and external validators.
- The local EVM ValueVault artifact checks run only when Foundry `cast` is
  available; CI covers that path.

Next step:

- Add structured artifact assertions for metadata and manifest fields, then
  migrate more of `scripts/portable/value-vault-smoke.sh` and
  `scripts/solana/counter-smoke.sh` into scenario-declared checks.

### Unified Testkit ValueVault Scenario

Commit: feature commit for unified testkit ValueVault scenario

Summary:

- Added typed scalar scenario args to `testkit/core`, so one TOML scenario can
  describe portable `u64`/`u32`/`bool` call parameters while each target
  harness performs its own ABI encoding.
- Extended `runtime/offline-host` with `--inputs-hex`, allowing the
  deterministic NEAR/Wasm host to run a stateful call sequence whose calls use
  different Borsh input payloads.
- Added `testkit/scenarios/value-vault.toml` covering
  `initialize -> deposit -> charge_fee -> release -> snapshot` plus balance
  and net-value queries.
- Wired ValueVault into `wasm-near` through `Tests/EmitWatValueVault.lean`,
  into `solana-sbpf-asm` through the existing ValueVault sBPF emitter plus
  Mollusk, and into `evm` through the revm harness when Foundry `cast` is
  available for selector hydration.

Validation run:

```sh
lake env lean --run Tests/EmitWatValueVault.lean
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target wasm-near
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm
```

Known limitations:

- ValueVault's EVM branch still depends on `cast` because the current
  Contract SDK EVM path hydrates ABI selectors through Foundry; when `cast` is
  absent, the harness reports a target skip instead of hiding the dependency.
- Testkit validates call order and portable return values. Event payloads,
  account/log traces, gas/compute budgets, and live deployment remain in the
  existing target-specific gates.

Next step:

- Start M4 by migrating more golden-source and artifact checks into scenario
  fixtures while keeping Foundry/Anvil, Surfpool, near-sandbox, dargo, and leo
  as chain-authentic gates.

### Unified Testkit M3 Solana Harness

Commit: feature commit for unified testkit Solana harness

Summary:

- Added `testkit/harness-solana`, backed by `mollusk-svm`, as the third RFC
  0007 target harness for the portable Counter scenario.
- The Solana harness emits Counter sBPF assembly, checks the tracked golden
  assembly, validates `manifest.toml` and `proof-forge-artifact.json`, builds
  a standard `sbpf` ELF project, and executes the stateful
  `initialize -> get -> increment -> get` scenario through Mollusk.
- Extended the testkit runner with explicit harness skip reporting so
  optional chain toolchains such as `sbpf`/`solana-keygen` can be absent
  without masking failures in always-available targets.
- Extended `testkit/scenarios/counter.toml` so Counter now targets
  `wasm-near`, `evm`, and `solana-sbpf-asm`, with normalized trace parity
  across all executed targets.

Validation run:

```sh
scripts/solana/counter-smoke.sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo check --manifest-path testkit/Cargo.toml
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana
just testkit
SBPF=/nonexistent-proof-forge-sbpf just testkit
```

Known limitations:

- The Solana testkit harness currently supports the portable IR Counter
  fixture only.
- `solana-sbpf-asm` is skipped with a clear reason when `sbpf` or
  `solana-keygen` is unavailable.
- This is a Mollusk in-process runtime gate, not a Surfpool/Web3 live
  deployment gate.

Next step:

- Add the portable ValueVault scenario to the testkit and run it across the
  targets whose capability plans support the fixture.

### Unified Testkit M2 Trace Parity

Commit: feature commit for unified testkit trace parity

Summary:

- Added a normalized observable trace comparison layer to `testkit/core`.
- The runner now executes every selected target for a scenario, validates each
  target's declared expectations, then asserts cross-target parity for call
  order and portable return values.
- EVM ABI return words and NEAR typed host returns are compared through the
  scenario's expected portable type, so target-specific hex encodings do not
  become false parity failures.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run
```

Known limitations:

- Trace parity currently covers call order and return values only; scenario
  state reads, events, errors, and resource budgets are still follow-up schema
  work before testkit M3/M4.
- `solana-sbpf-asm` is not yet wired into testkit; it remains the M3 harness.

Next step:

- Add `harness-solana` on top of the existing Mollusk templates so the Counter
  scenario runs across `evm`, `wasm-near`, and `solana-sbpf-asm`.

### Unified Testkit M2 EVM Harness

Commit: feature commit for unified testkit EVM harness

Summary:

- Added `testkit/harness-evm`, backed by `revm`, as the second target harness
  for RFC 0007.
- Extended `testkit/scenarios/counter.toml` so the same portable Counter
  scenario runs against both `wasm-near` and `evm`.
- The EVM harness emits portable IR Counter runtime bytecode and artifact
  metadata, loads selectors from metadata, installs the runtime bytecode into
  an in-memory EVM account, and executes each scenario call as a committed EVM
  transaction with sequential nonces.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target evm
just testkit
```

Known limitations:

- The EVM harness currently covers the portable IR Counter fixture only.
- It validates scenario-level behavior through `revm`; Foundry and Anvil remain
  the mature EVM runtime/deploy gates for broader contracts and live local
  chain behavior.
- Cross-target comparison is still implicit through shared expectations; an
  explicit trace-diff layer should be added next.

Next step:

- Add a target trace comparison report so `wasm-near` and `evm` outcomes are
  compared directly for the shared scenario, then wire the first Solana/Mollusk
  or sBPF runner into the same testkit interface.

### Unified Testkit M1 Skeleton

Commit: feature commit for unified testkit M1 skeleton

Summary:

- Added the RFC 0007 `testkit/` Rust workspace with core scenario parsing,
  NEAR harness wiring, and the `proof-forge-testkit` runner.
- Added `testkit/scenarios/counter.toml` as the first declarative scenario.
- Wired `just testkit`, `just testkit-list`, and the GitHub Actions
  `build-test` job.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
just testkit
```

Known limitations:

- This is the M1 `wasm-near` slice only. It wraps the existing deterministic
  `runtime/offline-host`; EVM/revm and Solana/Mollusk are not wired yet.
- Cross-target equivalence assertions start in M2 after the EVM harness lands.

Next step:

- Add `harness-evm` on revm, load emitted runtime bytecode plus
  `.evm-methods`, and compare the Counter observable trace against
  `wasm-near`.

## 2026-07-02

### EVM StorageSlotPlan ToYul Slice

Commit: feature commit for `StorageSlotPlan -> ToYul`

Summary:

- Added `ProofForge.Backend.Evm.ToYul` as the first plan-to-Yul module in the
  EVM semantic-plan migration.
- Moved scalar storage slot expressions and map value/presence slot expressions
  through `StorageSlotPlan -> ToYul` while keeping the existing `IR.lean`
  facade and generated Yul behavior stable.
- Recorded the remaining EVM semantic-plan migration TODO in the implementation
  backlog, including `Validate`, `Lower`, `ToYul`, `Metadata`,
  `EntrypointPlan`, `EventPlan`, `CrosscallPlan`, and `MetadataPlan` stages.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-plan
just evm-smoke map
just evm-smoke typed-map
just evm-smoke typed-storage
just check
just diff-check
```

Known limitations:

- Array slots, struct-array field slots, expression plans, statement plans,
  entrypoint planning, events, crosscalls, and artifact metadata still need to
  move behind semantic plan boundaries.
- `ProofForge.Backend.Evm.IR` remains the public compatibility facade until the
  migrated plan paths have complete validation coverage.

Next step:

- Extend `StorageSlotPlan -> ToYul` to array and struct-array slot plans, then
  begin extracting expression and statement planning out of `IR.lean`.

### Target-Driven EVM Module Plan

Commit: feature commit for EVM capability-aware module planning

Summary:

- Extended `ProofForge.Backend.Evm.Plan` with a target-driven `ModulePlan`
  that preserves the resolved `Target.CapabilityPlan` for the EVM compiler
  target.
- Moved EVM storage/helper planning behind `buildModulePlan`, so the backend
  can consume target-resolved capabilities instead of rediscovering helper
  requirements directly during final Yul lowering.
- Added `lowerModuleWithPlan` in the EVM backend. The public `lowerModule`
  path now builds an EVM module plan first, then renders through the existing
  Yul AST path.
- Extended `Tests/EvmPlan.lean` to verify target id, supported and unsupported
  capabilities, helper requirements, storage layout, map assign-op helper
  requirements, and explicit rejection of a non-EVM target plan.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmPlan.lean
```

Known limitations:

- ABI dispatch, event plans, crosscall plans, constructor metadata, and artifact
  metadata still need to move behind `ModulePlan`.
- The generated Yul is intentionally unchanged in this slice.

Next step:

- Move storage-path Yul expression construction to consume `StorageSlotPlan`
  directly, then promote ABI/event/crosscall metadata into `ModulePlan`.

### Solana sBPF And SDK PR Merge

Commit: merge commit for PR #2 (`Solana supprot`)

Summary:

- Merged the Solana sBPF assembly backend work into the current EVM-focused
  mainline.
- Added Solana backend modules for sBPF assembly AST/printer, state layout,
  register allocation, syscalls, manifests, packages, and SDK extension
  artifacts.
- Added CLI modes for emitting Solana sBPF assembly, Solana ELF artifacts,
  Solana SDK assembly, and Solana-focused fixture artifacts.
- Added Solana examples, diagnostics, SDK tests, target-routing tests, and
  Solana smoke scripts.
- Resolved RFC numbering against the existing EVM semantic plan RFC: EVM keeps
  RFC 0004, Solana sBPF is RFC 0005, and the multi-chain Token SDK is RFC 0006.

Validation run:

```sh
just solana-light
just docs-check
just check
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Solana Mollusk/Surfpool runtime smoke scripts remain gated on local external
  tools such as Mollusk, Surfpool, Node, and npm.
- The merge preserves EVM semantic-plan work; deeper integration between the
  new Solana SDK route and the portable multi-chain planning layer remains
  follow-up work.

Next step:

- Run the available Solana smoke scripts on a machine with the Solana/sBPF
  toolchain installed, then decide which Solana surface should be promoted from
  research to CI-tracked baseline.

### EVM Semantic Plan Storage Slice

Commit: feature commit for the first EVM semantic plan slice

Summary:

- Added `ProofForge.Backend.Evm.Plan` as the first explicit semantic planning
  layer between portable IR and target-specific Yul lowering.
- Modeled storage layout entries, scalar storage slot plans, map value slot
  plans, nested map value slot plans, map presence slot plans, and helper
  requirements without changing generated Yul output.
- Added `Tests/EvmPlan.lean` to lock scalar/map/nested-map slot planning
  against the existing `EvmMapProbe` and `EvmTypedMapProbe` fixtures.
- Added `just evm-plan` and a GitHub Actions step so the plan slice is checked
  independently before broader EVM smokes.

Validation run:

```sh
just evm-plan
```

Known limitations:

- The existing Yul generator still owns actual rendering; this slice creates
  the semantic structures and tests that later lowering can migrate onto.
- The first plan slice covers scalar slots and consecutive `mapKey` paths only.
  Arrays, structs, ABI dispatch, event/crosscall helpers, and artifact metadata
  planning remain follow-up work.

Next step:

- Refactor the current EVM storage path lowering to consume plan nodes while
  preserving golden Yul output, then broaden the plan to arrays and flat
  storage structs.

### EVM Nested Map Storage Paths

Commit: feature commit for EVM nested map storage paths

Summary:

- Extended EVM portable IR storage-path type checking so map-backed state
  accepts one or more consecutive `mapKey` segments when every key expression
  matches the map key type.
- Lowered nested map value slots by folding the existing Solidity-style
  mapping helper, for example `keccak256(inner || keccak256(outer || slot))`.
- Lowered nested map write and compound assignment paths so the final key's
  ProofForge-managed presence slot is marked alongside the value slot.
- Extended `EvmMapProbe` with U64 nested map path lifecycle and dynamic-key
  coverage, and extended `EvmTypedMapProbe` with U32 nested map path coverage
  plus dispatcher range-guard checks.
- Kept mixed map/aggregate storage paths as explicit diagnostics rather than
  silently lowering partial paths.

Validation run:

```sh
lake build proof-forge
just evm-smoke map
just evm-smoke typed-map
just evm-diagnostics
just evm-coverage
just docs-check
just diff-check
```

Known limitations:

- Nested map paths currently model EVM nested mapping slots over a single
  declared `Map<K, V, N>` state by using consecutive keys of the same key type.
- Mixed map/array/struct aggregate paths and non-word or aggregate map
  key/value shapes remain explicit unsupported surfaces.

Next step:

- Continue shrinking the remaining EVM storage surface around aggregate storage
  paths and broader ABI-facing storage-backed values.

### EVM Nested Fixed-Array Event Aggregates

Commit: feature commit for EVM nested fixed-array event aggregates

Summary:

- Extended portable IR EVM event signature generation so nested fixed arrays are
  rendered recursively as Solidity-style event types such as `uint64[2][2]` and
  `(uint64,uint64)[2][2]`.
- Extended event data-word lowering so nested fixed-array event fields flatten
  recursively into ABI-style words when their leaves are scalar words or flat
  structs.
- Added `EventProbe` entrypoints for `MatrixEvent(uint64[2][2])`,
  `PairMatrixEvent((uint64,uint64)[2][2])`,
  `IndexedMatrix(uint64[2][2],uint64)`, and
  `IndexedPairMatrix((uint64,uint64)[2][2],uint64)`.
- Tightened diagnostics so nested fixed arrays whose leaves are unsupported or
  non-flat still fail before Yul generation with explicit errors.

Validation run:

```sh
just evm-smoke event
```

- Generated reproducible EventProbe Yul and runtime bytecode with
  `solc --strict-assembly`.
- Validated new selector/event ABI metadata through
  `scripts/evm/validate-artifact-metadata.py`.
- Foundry ran 24 EventProbe recorded-log tests, including nested scalar and
  nested flat-struct fixed-array data flattening plus indexed aggregate topic
  hashing.

Known limitations:

- Aggregate event fields with unsupported leaves, non-flat struct leaves, or
  richer first-class event declarations remain explicit unsupported surfaces for
  portable IR EVM.

Next step:

- Continue shrinking the EVM aggregate surface around remaining storage and ABI
  edge cases while keeping unsupported shapes diagnostic-first.

### EVM Entrypoint ABI Artifact Metadata

Commit: `feat: record EVM entrypoint ABI metadata`

Summary:

- Portable IR EVM bytecode artifacts and deploy manifests now include
  structured `abi.entrypoints` metadata for selector-facing entrypoints.
- Entrypoint metadata records the Solidity-style selector signature, parameter
  ABI types, flattened calldata word types/counts, return ABI type, flattened
  return word types/counts, and preserves the original IR type names.
- `scripts/evm/validate-artifact-metadata.py` now validates entrypoint
  selectors with `cast sig`, while `scripts/evm/abi-aggregate-ir-smoke.sh`
  locks aggregate calldata/return word layouts through
  `--expect-entrypoint-abi`.

Validation run:

```sh
lake build proof-forge
scripts/evm/abi-aggregate-ir-smoke.sh
```

Known limitations:

- The metadata describes the current static ABI-word surface. Dynamic ABI
  values remain an explicit unsupported surface for portable IR EVM.

Next step:

- Continue tightening metadata validation around deployment-facing manifests
  and expand first-class ABI schema coverage as the portable IR grows.

### EVM Event ABI Artifact Metadata

Commit: `feat: record EVM event ABI metadata`

Summary:

- Portable IR EVM bytecode artifacts and deploy manifests now include
  `abi.events` entries for emitted events.
- Event metadata records the Solidity-style event signature, `topic0`, indexed
  fields, non-indexed data fields, flattened ABI word types, and per-field
  topic/data encoding.
- `scripts/evm/validate-artifact-metadata.py` validates event topics with
  `cast keccak`, and `scripts/evm/event-ir-smoke.sh` now locks all EventProbe
  event signatures through `--expect-event`.

Validation run:

```sh
lake build proof-forge
scripts/evm/event-ir-smoke.sh
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
```

Known limitations:

- Event metadata is emitted for portable IR modules; richer first-class event
  declarations remain an explicit unsupported surface.

Next step:

- Continue promoting ABI-facing metadata from smoke fixtures into a stable
  target manifest schema shared by EVM deployment tooling.

### EVM Anvil Chain Profile Deploy-Run Validation

Commit: `feat: validate Anvil chain profiles`

Summary:

- Added `anvil-local` as a lookup-only EVM chain profile for local Foundry
  Anvil deployments on chain id `31337`.
- `scripts/evm/anvil-deploy-smoke.sh` now regenerates Counter with
  `--evm-chain-profile anvil-local` by default when using the default Anvil
  chain id.
- `proof-forge-deploy-run.json` now links the deploy manifest chain profile,
  and `scripts/evm/validate-deploy-run.py` validates that the profile,
  deployment chain id, actual Anvil chain id, and creation transaction evidence
  agree.

Validation run:

```sh
lake build ProofForge.Target.Registry
lake env lean --run Tests/TargetRegistry.lean
python3 -m py_compile scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
scripts/evm/anvil-deploy-smoke.sh
```

Known limitations:

- `anvil-local` is intentionally a local validation profile; it does not imply
  public RPC broadcast support.

Next step:

- Promote profile-aware deploy-run generation into a first-class deploy command
  that can consume any supported EVM chain profile.

### EVM Creation Transaction Deploy-Run Artifact

Commit: `feat: record EVM creation transactions`

Summary:

- Anvil deploy smoke now records the `eth_getTransactionByHash` creation
  transaction JSON alongside the `cast send --create` receipt.
- `proof-forge-deploy-run.json` links that creation transaction artifact with
  path, byte size, and SHA-256 metadata.
- `scripts/evm/validate-deploy-run.py` now validates that the creation
  transaction hash, sender, null `to`, block metadata, and initcode `input`
  match the deploy receipt and generated `.init.bin`.

Validation run:

```sh
python3 -m py_compile scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
scripts/evm/anvil-deploy-smoke.sh
just evm-all
```

Known limitations:

- This records a local Anvil creation transaction and receipt, not a signed raw
  transaction artifact or public RPC broadcast workflow.

Next step:

- Promote the deploy-run artifact shape into a first-class deploy/broadcast
  command that consumes `proof-forge-deploy.json`.

### EVM ABI Method Signature Metadata

Commit: `feat: record EVM method signatures`

Summary:

- SDK `.evm-methods` sidecars now preserve the original Solidity method
  signature in `abi.methods[].signature` for EVM artifact metadata and deploy
  manifests.
- Manual `--method selector:fn:argc:view|update` specs remain supported; those
  method entries use `null` signature metadata.
- EVM metadata validators now check selector shape, duplicate method and
  entrypoint selectors, generated Yul function names, signature syntax, and
  signature/arg-count consistency.
- SDK example builds and the Anvil deploy smoke now require method signatures
  in metadata validation.

Validation run:

```sh
lake build proof-forge
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
bash -n scripts/evm/build-examples.sh
bash -n scripts/evm/anvil-deploy-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/anvil-deploy-smoke.sh
```

Known limitations:

- The validators check selector format and method signature metadata, while the
  selector derivation itself still comes from Foundry `cast sig` during
  compilation.

Next step:

- Continue strengthening ABI-facing artifact checks and close remaining
  deploy/broadcast metadata gaps.

### EVM Constructor Diagnostic Coverage

Commit: `test: cover EVM constructor CLI diagnostics`

Summary:

- Extended `scripts/evm/diagnostic-smoke.sh` beyond portable IR diagnostics to
  cover EVM constructor artifact-boundary CLI diagnostics.
- The gate now locks unsupported dynamic constructor ABI types, missing
  constructor values, duplicate typed values, mixed typed/raw constructor
  sources, integer overflow, and malformed address-width inputs.
- This turns the constructor value negative cases from one-off manual checks
  into CI-tracked `just evm-diagnostics` coverage.

Validation run:

```sh
bash -n scripts/evm/diagnostic-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Constructor value encoding is still intentionally limited to static one-word
  ABI types; dynamic constructor ABI values remain unsupported with explicit
  diagnostics.

Next step:

- Continue closing the remaining EVM ABI/backend gaps, especially dynamic ABI
  surfaces and deploy/broadcast artifacts.

### EVM Typed Constructor Value Encoding

Commit: `feat: encode EVM constructor values`

Summary:

- Added `--evm-constructor-arg <name=value>` for EVM bytecode modes.
- Typed constructor args are ABI-encoded from the declared
  `--evm-constructor-param <name:type>` schema and support `uint256`, `uint64`,
  `uint32`, `bool`, `bytes32`, and `address`.
- Constructor arg metadata now records whether the ABI blob came from typed CLI
  args or raw `--evm-constructor-args-hex`.
- Validators accept and can assert constructor arg source, and Anvil deploy
  smoke now defaults to typed `initial=123` input for Counter.
- CLI validation rejects missing typed values, duplicate typed values,
  out-of-range integer values, and mixing typed values with raw constructor hex.

Validation run:

```sh
lake build proof-forge
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
lake env proof-forge --evm-bytecode --root . --module contract --evm-constructor-param initial:uint256 --evm-constructor-arg initial=123 ...
python3 scripts/evm/validate-artifact-metadata.py --expect-constructor-args-source=--evm-constructor-arg ...
python3 scripts/evm/validate-deploy-manifest.py --expect-constructor-args-source=--evm-constructor-arg ...
```

Known limitations:

- Constructor value encoding is limited to static one-word ABI types; dynamic
  constructor ABI types are still unsupported.
- This still emits deployable initcode and local Anvil deploy-run artifacts,
  not signed transaction/broadcast artifacts for public RPC networks.

Next step:

- Add first-class EVM deploy/broadcast commands that consume the deploy
  manifest, or continue closing remaining non-dynamic EVM backend gaps.

### EVM Constructor ABI Schema Metadata

Commit: `feat: record EVM constructor ABI schema`

Summary:

- Added `--evm-constructor-param <name:type>` for EVM bytecode modes.
- Constructor params are recorded under `abi.constructor.params` in both
  `proof-forge-artifact.json` and `proof-forge-deploy.json` using static
  32-byte ABI-word metadata.
- Validators now check constructor ABI schema shape, supported static-word
  types, expected parameters, and constructor-argument byte length.
- The Anvil deploy smoke now regenerates Counter with
  `--evm-constructor-param initial:uint256`, records `constructorAbi` in
  `Counter.proof-forge-deploy-run.json`, and validates it against the deploy
  manifest.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
lake env proof-forge --evm-bytecode --root . --module contract --evm-constructor-param initial:uint256 --evm-constructor-args-hex 0x000000000000000000000000000000000000000000000000000000000000007b ...
scripts/evm/anvil-deploy-smoke.sh
just check
just evm-all
just psy-golden-sources
git diff --check
```

Known limitations:

- ProofForge records and validates static constructor ABI schema, but does not
  yet parse typed constructor values or ABI-encode them from CLI inputs.
- Dynamic constructor ABI types remain out of scope for the current EVM schema
  slice.

Next step:

- Add typed constructor value parsing/encoding or move to a first-class EVM
  deploy/broadcast command that consumes the deploy manifest.

### Just-Based CI Command Entry

Commit: feature commit for just-based CI command entry

Summary:

- Kept target-specific implementation logic in `scripts/`, but made the root
  `justfile` the shared developer and CI command entrypoint.
- Installed pinned `just` 1.48.0 in GitHub Actions and replaced duplicated CI
  command blocks with existing recipes such as `just build`,
  `just target-registry`, `just docs-check`, `just psy-golden-sources`, and
  `just evm-smoke <fixture>`.
- Preserved separate GitHub Actions steps for EVM/Psy gates so CI failures stay
  easy to locate.
- Updated README, development standards, validation gates, and Chinese mirrors
  to document the split between `just` orchestration and underlying scripts.

Validation run:

```sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "workflow yaml ok"'
just --list
just check
just psy-golden-sources
just --dry-run <each CI-tracked just recipe>
git diff --check
```

Known limitations:

- CI now requires `just` installation before invoking common gate recipes.
- Direct scripts remain supported because they are still the target-specific
  implementation surface.

Next step:

- Consider grouping future target recipes by imported `just` modules if the
  root `justfile` becomes hard to scan.

### EVM Constructor Args Initcode Tail

Commit: feature commit for EVM constructor args initcode tail

Summary:

- Added `--evm-constructor-args-hex <hex>` to EVM bytecode modes.
- The CLI now normalizes ABI-encoded constructor args, appends them to
  generated `.init.bin` creation bytecode, and records the argument blob in
  `proof-forge-deploy.json` with hex, byte size, SHA-256, and source metadata.
- Updated EVM metadata, deploy-manifest, and deploy-run validators so they
  parse the initcode header as `header + runtime + constructorArgs` instead of
  assuming the initcode ends at the runtime bytecode.
- Extended `scripts/evm/anvil-deploy-smoke.sh` so CI deploys Counter initcode
  with a deterministic non-empty constructor-argument tail by default and
  records those args in `Counter.proof-forge-deploy-run.json`.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py scripts/evm/validate-deploy-run.py
scripts/evm/build-examples.sh
scripts/evm/anvil-deploy-smoke.sh
```

Result:

- No-argument SDK example builds still emit valid metadata and deploy
  manifests.
- Counter Anvil deploy smoke regenerated `Counter.init.bin` with a 32-byte
  constructor argument blob (`0x...007b`), deployed it with `cast send
  --create`, and validated that the deployed runtime code still matches
  `Counter.bin`.
- The deploy-run artifact records the constructor args and the Counter
  lifecycle still returned `0`, then `99`, `100`, and `99`.

Known limitations:

- Constructor args are accepted as an explicit ABI-encoded hex blob; ProofForge
  does not yet generate constructor ABI schemas or encode named constructor
  parameters from IR.
- This still validates on local Anvil, not a live public RPC broadcast.

Next step:

- Add a first-class deployment command or broadcast artifact that consumes the
  deploy manifest, selected chain profile, private-key/wallet configuration,
  and constructor args without shell-script-specific glue.

### EVM Anvil Deploy-Run Smoke

Commit: `feat: validate EVM initcode deployment on Anvil`

Summary:

- Added `scripts/evm/anvil-deploy-smoke.sh`, which starts a local Anvil chain
  and deploys generated `Counter.init.bin` with `cast send --create`.
- The smoke records the creation transaction receipt, deployed address, local
  Anvil network id, referenced deploy manifest, initcode, runtime bytecode, and
  Counter lifecycle call results in
  `build/anvil-deploy-smoke/Counter.proof-forge-deploy-run.json`.
- Added `scripts/evm/validate-deploy-run.py` to validate deploy-run artifacts,
  including receipt status, transaction/deployer consistency, deployed runtime
  code hash/size, and `get`/`set`/`increment`/`decrement` JSON-RPC behavior.
- Wired the new smoke into `just evm-anvil-deploy`, `just evm-all`, and CI.

Validation run:

```sh
python3 -m py_compile scripts/evm/validate-deploy-run.py
scripts/evm/anvil-deploy-smoke.sh
```

Result:

- Anvil chain id `31337` started locally.
- `Counter.init.bin` deployed to
  `0x5fbdb2315678afecb367f032d93f642f64180aa3` with a successful creation
  receipt.
- The on-chain deployed code matched `build/evm/Counter.bin`.
- Counter JSON-RPC lifecycle returned `0`, then `99`, `100`, and `99`.

Known limitations:

- This is a local Anvil deploy-run artifact, not a live public RPC broadcast.
- Constructor arguments remain empty.
- Explorer verification and wallet UX are still future work.

Next step:

- Extend deploy-run generation toward chain-profile-aware live RPC deployment
  and constructor argument encoding, while keeping Anvil as the deterministic
  CI smoke.

### EVM Chain Profile Deploy Metadata

Commit: `feat: record EVM chain profile deploy metadata`

Summary:

- Added `--evm-chain-profile <id>` for EVM bytecode modes.
- Resolved EVM chain profiles from the target registry and recorded the selected
  profile in `proof-forge-deploy.json`, including profile id, chain id, RPC
  URLs, native gas symbol, explorer, verifier, and notes.
- Extended the deploy `deployment` block with profile id, chain id, network
  name, RPC URLs, explorer/verifier metadata, and explicit
  `broadcastArtifact: null`.
- Strengthened EVM metadata/deploy validators so selected profiles must match
  deployment fields and unselected profiles remain explicit `null`/empty
  fields.
- Updated `AbiScalarProbe` EVM smoke to validate
  `robinhood-chain-testnet` and chain id `46630`.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture AbiScalarProbe --expect-source-kind portable-ir --expect-chain-profile robinhood-chain-testnet --expect-chain-id 46630 build/ir/AbiScalarProbe.proof-forge-deploy.json
```

Result:

- `AbiScalarProbe.proof-forge-deploy.json` records
  `chainProfile.id: robinhood-chain-testnet`, `deployment.profileId:
  robinhood-chain-testnet`, and `deployment.chainId: 46630`.
- Foundry ABI scalar smoke still ran 2 runtime tests successfully.

Known limitations:

- The manifest is still a deployment plan only.
- Transaction signing, Foundry/Anvil broadcast JSON, deployed address recording,
  and explorer verification remain future work.

Next step:

- Generate a Foundry script or broadcast-oriented artifact from the deploy
  manifest, then validate it against Anvil without relying on live RPC.

### EVM Deploy Initcode Artifacts

Commit: `feat: emit EVM deploy initcode artifacts`

Summary:

- Extended every EVM bytecode build to emit a sibling `.init.bin` deployable
  creation bytecode artifact in addition to the existing runtime `.bin`.
- Updated `proof-forge-artifact.json` and `proof-forge-deploy.json` so EVM
  metadata records the initcode artifact, `creation.mode: init-code`, and
  `validation.initCodeGeneration: passed`.
- Strengthened both EVM metadata validators to parse the initcode
  `PUSH/CODECOPY/RETURN` header and prove it copies and returns the exact
  referenced runtime bytecode artifact.
- Refreshed English/Chinese EVM metadata docs, validation gates, and backlog
  notes to distinguish deployable initcode from future transaction broadcast
  manifests.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/build-examples.sh
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture AbiScalarProbe --expect-source-kind portable-ir build/ir/AbiScalarProbe.proof-forge-deploy.json
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture Counter.lean --expect-source-kind lean-sdk build/evm/Counter.proof-forge-deploy.json
scripts/evm/foundry-smoke.sh
```

Result:

- `AbiScalarProbe` generated `AbiScalarProbe.init.bin` and passed Foundry
  scalar ABI runtime checks.
- SDK examples generated `.init.bin` artifacts for Counter, ArrayExample,
  SimpleToken, ERC20, Ownable, Pausable, and VerifiedVault; the validator
  accepted both small and multi-byte-length runtimes.
- Foundry ran 5 runtime smoke tests, including deploying the generated Counter
  `.init.bin` through EVM `create` and then running the Counter lifecycle.

Known limitations:

- Constructor arguments are still empty.
- Chain profile selection, signed/raw transaction generation, broadcast JSON,
  deployed address recording, and explorer verification remain future work.
- Most Foundry smoke coverage still installs runtime bytecode with `vm.etch`
  for fast runtime checks; Counter now also has a real initcode `create` path.

Next step:

- Continue toward real deployment manifests by adding chain-profile selection
  and a Foundry/Anvil broadcast artifact, or return to the remaining EVM IR
  unsupported surfaces such as dynamic ABI values.

### EVM IR Hash Aggregate ABI Leaves

Commit: `test: cover EVM hash aggregate ABI leaves`

Summary:

- Extended `EvmAbiAggregateProbe` with `HashPair` and `Hash` fixed-array ABI
  entrypoints:
  `echo_hash_pair((bytes32,bytes32))`,
  `make_hash_pair(bytes32,bytes32)`, `pick_hash(bytes32[2])`, and
  `make_hash_array(bytes32,bytes32)`.
- Validated that `Hash` leaves flatten as Solidity `bytes32` words inside flat
  structs and fixed arrays for ABI-facing calldata and return data.
- Refreshed the `EvmAbiAggregateProbe` golden Yul, selector metadata checks,
  Foundry ABI decode checks, coverage table, English/Chinese EVM target docs,
  validation gates, and backlog notes.

Validation run:

```sh
scripts/evm/abi-aggregate-ir-smoke.sh
```

Result:

- `EvmAbiAggregateProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 3 ABI aggregate tests, including `HashPair` calldata/return-data,
  `bytes32[2]` calldata/return-data, and short `bytes32[2]` calldata rejection.

Known limitations:

- Dynamic ABI values remain outside the portable IR EVM v0 surface.
- Rich ABI tuples beyond flat word aggregates remain explicit future work.
- Storage-backed aggregate ABI returns stay covered only by the fixed word-array
  and flat struct-array cases in the dedicated storage probes.

Next step:

- Continue shrinking aggregate ABI/crosscall gaps, or decide whether richer
  dynamic ABI values require a portable IR extension first.

## 2026-07-01

### EVM IR Typed Scalar Event Fields

Commit: feature commit for EVM IR typed scalar event fields

Summary:

- Extended `EventProbe` with typed scalar event entrypoints:
  `emit_typed_scalar_event(bool,uint32,bytes32)` and
  `emit_indexed_typed_scalar_event(bool,uint32,bytes32,uint256)`.
- Validated `Bool`, `U32`, and `Hash` event data fields and indexed topics,
  including `Bool`/`U32` calldata range guards before the event lowering runs.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English/Chinese EVM target docs, validation
  gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 20 EventProbe tests, including typed scalar data/topic checks and
  malformed `Bool`/`U32` calldata rejection.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Multi-Topic Indexed Events

Commit: feature commit for EVM IR multi-topic indexed events

Summary:

- Extended `EventProbe` with two scalar indexed-event entrypoints:
  `emit_two_indexed_event(uint256,uint256,uint256)` and
  `emit_three_indexed_event(uint256,uint256,uint256,uint256)`.
- Validated that `eventEmitIndexed` generates `log3` for two indexed fields and
  `log4` for three indexed fields, with ordered scalar topics and one
  non-indexed data word.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English/Chinese EVM target docs, validation
  gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 17 EventProbe tests, including `log3` and `log4` scalar indexed
  event coverage.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Storage-Backed Event Fixed Arrays

Commit: feature commit for EVM IR storage-backed event fixed arrays

Summary:

- Extended `EventProbe` with `storedValues` and `storedPairs` fixed storage
  arrays plus four entrypoints:
  `emit_storage_array_event(uint256,uint256)`,
  `emit_storage_pair_array_event(uint256,uint256,uint256,uint256)`,
  `emit_indexed_storage_array_event(uint256,uint256,uint256)`, and
  `emit_indexed_storage_pair_array_event(uint256,uint256,uint256,uint256,uint256)`.
- Validated that storage array reads and storage array struct field reads can
  feed scalar fixed-array and fixed-array-of-flat-struct event aggregates.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English/Chinese EVM target docs, validation
  gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 15 EventProbe tests, including storage-backed fixed-array data
  flattening and storage-backed fixed-array indexed topic hashing.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Storage-Backed Event Aggregates

Commit: feature commit for EVM IR storage-backed aggregate events

Summary:

- Extended `EventProbe` with a flat scalar storage struct state and two
  entrypoints:
  `emit_storage_pair_event(uint256,uint256)` and
  `emit_indexed_storage_pair_event(uint256,uint256,uint256)`.
- Validated the existing storage-backed event lowering path where a whole flat
  struct is written with `storageScalarWrite`, read with `storageScalarRead`,
  flattened into non-indexed event data words, or flattened and hashed into an
  indexed aggregate topic.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English target docs, Chinese target docs,
  validation gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 11 EventProbe tests, including `StoragePairEvent` data flattening
  from storage reads and `IndexedStoragePair` topic hashing from storage reads.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Indexed Aggregate Event Topics

Commit: feature commit for EVM IR indexed aggregate event topics

Summary:

- Extended `eventEmitIndexed` lowering so supported aggregate indexed fields no
  longer pretend to be scalar topics. Flat structs and fixed arrays whose
  elements are flat structs now flatten to ABI-style 32-byte words and use
  `keccak256` over those words as the indexed topic.
- Preserved direct scalar indexed topics for `U32`, `U64`, `Bool`, and `Hash`.
- Extended `EventProbe` with `emit_indexed_pair_event`,
  `emit_indexed_array_event`, and `emit_indexed_pair_array_event`, covering
  `IndexedPair((uint64,uint64),uint64)` and
  `IndexedArray(uint64[2],uint64)` and
  `IndexedPairArray((uint64,uint64)[2],uint64)`.
- Replaced the old flat-aggregate indexed diagnostic with a nested aggregate
  indexed diagnostic, so unsupported event shapes still fail explicitly instead
  of lowering partially.
- Refreshed golden Yul, artifact metadata selector checks, Foundry recorded-log
  checks, EVM diagnostics, coverage, English target docs, Chinese target docs,
  and implementation backlog notes.

Validation run:

```sh
lake build
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 9 EventProbe tests, including scalar indexed topics, flat struct
  indexed topic hashes, scalar fixed-array indexed topic hashes,
  fixed-array-of-flat-struct indexed topic hashes,
  aggregate data flattening, selector dispatch, and unknown-selector revert
  behavior.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to the next uncovered EVM capability surface.

### EVM IR Nested Local Struct Arrays

Commit: feature commit for EVM IR nested local struct arrays

Summary:

- Extended portable IR EVM local fixed-array lowering so nested fixed arrays can
  use flat struct leaves, expanding every nested element field into
  deterministic Yul locals such as `grid[1][0].age`.
- Added static and dynamic nested struct field reads through nested local-array
  getter helpers, plus nested mutable field assignment and numeric compound
  assignment through bounds-checked `switch` lowering.
- Added nested whole-local assignment from another local array and from
  self-referential nested array literals, preserving RHS snapshot semantics.
- Extended `EvmStructArrayValueProbe` with `nested_struct_array_sum`,
  `nested_struct_array_dynamic_pick`, `nested_struct_array_update`,
  `nested_struct_array_whole_assign`, and `nested_struct_array_self_assign`.
- Refreshed golden Yul, artifact metadata selector checks, Foundry smoke tests,
  EVM coverage manifest entries, English target docs, Chinese target docs, and
  implementation backlog notes.

Validation run:

```sh
lake build
scripts/evm/struct-array-value-ir-smoke.sh
```

Result:

- `EvmStructArrayValueProbe` generated reproducible Yul and runtime bytecode
  through `solc --strict-assembly`.
- Foundry ran 14 StructArrayValueProbe tests, including nested flat-struct
  field reads, nested field mutation, nested whole assignment, RHS snapshotting,
  dynamic out-of-bounds reverts, and unknown-selector revert behavior.

Known limitations:

- Nested local fixed arrays are still limited to scalar word leaves or flat
  struct leaves. Non-flat struct leaves and other unsupported aggregate leaves
  remain explicit diagnostics.

Next step:

- Continue shrinking the EVM aggregate gap around unsupported nested aggregate
  leaves, richer event schemas, or broader cross-call return data.

### EVM IR Nested Struct Crosscall Fixed Arrays

Commit: feature commit for EVM IR nested struct crosscall arrays

Summary:

- Extended typed crosscall aggregate word-shape validation so nested fixed
  arrays can use flat struct leaves such as `RemotePair[2][2]`, while non-flat
  struct leaves still fail with explicit diagnostics.
- Added `EvmCrosscallProbe` entrypoints for `RemotePair[2][2]` arguments and
  direct entrypoint returns across normal, value-bearing, static, and delegate
  typed calls.
- Refreshed `EvmCrosscallProbe.golden.yul`, metadata selector expectations, and
  the Foundry smoke harness with `Pair[2][2]` callee helpers.
- Updated the EVM coverage manifest and target/validation docs to distinguish
  supported flat struct leaves from unsupported non-flat struct leaves.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
git diff --check
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 73 CrosscallProbe tests, including nested fixed-array
  flat-struct arguments and returns in normal, value-bearing, static, and
  delegate modes.

Known limitations:

- Dynamic ABI values, nested local fixed-array mutation beyond the current
  local-array surface, nested crosscall fixed arrays with non-flat or
  unsupported leaves, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM aggregate gap around dynamic ABI data, richer
  cross-call return data, or unsupported nested aggregate leaves.

### EVM IR Storage-Backed Aggregate ABI Returns

Commit: feature commit for EVM IR storage-backed aggregate ABI returns

Summary:

- Extended `EvmStorageArrayProbe` with `return_values()`, which writes U64
  storage-array elements, reads them back through `storageArrayRead`, and
  encodes those reads as a fixed-array ABI return.
- Extended `EvmStorageStructProbe` with `return_points()`, which writes fields
  in a fixed storage array of flat structs, reads them back through
  `storageArrayStructFieldRead`, and encodes those reads as a
  fixed-array-of-struct ABI return.
- Refreshed both storage probe golden Yul snapshots and metadata selector
  expectations.
- Added Foundry ABI decoding checks for `uint256[3]` and `Point[2]` returns,
  while still validating the raw storage slots with `vm.load`.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
git diff --check
```

Result:

- `EvmStorageArrayProbe` generated reproducible Yul and runtime bytecode, and
  Foundry ran 7 tests including the new storage-backed fixed-array return.
- `EvmStorageStructProbe` generated reproducible Yul and runtime bytecode, and
  Foundry ran 12 tests including the new storage-backed fixed-array-of-struct
  return.

Known limitations:

- This covers fixed-size word arrays and fixed arrays of flat structs assembled
  from storage reads. Dynamic ABI values, richer storage-backed aggregate
  shapes, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM ABI/storage gap around dynamic ABI data, richer
  aggregate storage shapes, or return data that cannot be represented as a
  static word sequence.

### EVM IR Nested Crosscall Fixed Arrays

Commit: `fb0828b` (`feat: support nested EVM crosscall arrays`)

Summary:

- Extended typed crosscall aggregate lowering so nested scalar fixed arrays such
  as `Array<Array<U64,2>,2>` flatten to ABI words for normal, value-bearing,
  static, and delegate typed calls.
- Added `EvmCrosscallProbe` entrypoints for nested scalar fixed-array arguments
  and direct entrypoint returns across all four call modes.
- At this milestone, kept nested fixed arrays with struct or other non-scalar
  leaves as explicit unsupported diagnostics; flat struct leaves were covered by
  a later follow-up.
- Refreshed `EvmCrosscallProbe.golden.yul`, metadata selector expectations, and
  the Foundry smoke harness with `uint64[2][2]` callee helpers.

Validation run:

```sh
lake build
lake env lean --run Tests/TargetRegistry.lean
scripts/i18n/check-sync.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
git diff --check
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 65 CrosscallProbe tests, including nested scalar fixed-array
  arguments and returns in normal, value-bearing, static, and delegate modes.
- GitHub Actions run `28514575022` passed on `main`.

Known limitations:

- Dynamic ABI values, nested local fixed-array mutation beyond the current
  local-array surface, nested crosscall fixed arrays with non-flat or
  unsupported leaves, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM aggregate gap around dynamic ABI data, storage
  backed aggregate ABI surfaces, or richer cross-call return data.

### EVM IR Nested Fixed-Array ABI

Commit: feature commit for EVM IR nested fixed-array ABI

Summary:

- Extended EVM ABI word flattening for entrypoint parameters and returns from
  flat fixed arrays to nested scalar fixed arrays such as
  `Array<Array<U64,2>,2>`.
- Added deterministic flattened Yul local names for nested ABI array words and
  static nested index reads such as `matrix[0][1]`.
- Extended `EvmAbiAggregateProbe` with `sum_matrix`, `make_matrix`, and
  `sum_small_matrix` entrypoints covering nested `U64`/`U32` ABI calldata,
  return-data encoding, and range guards.
- Kept typed crosscall nested aggregate arrays explicitly unsupported with
  crosscall-specific diagnostics instead of silently inheriting ABI entrypoint
  support.

Validation run:

```sh
lake build
scripts/evm/diagnostic-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
```

Result:

- `EvmAbiAggregateProbe` generated reproducible Yul and runtime bytecode
  through `solc --strict-assembly`.
- Foundry validated nested fixed-array parameters, nested fixed-array returns,
  malformed nested calldata length checks, and nested `U32` range guards.
- EVM diagnostics now keep zero-length arrays, non-flat struct fields, nested
  crosscall aggregate arrays, and malformed crosscall surfaces explicit.

Known limitations:

- Nested fixed-array support is currently ABI-entrypoint focused.
- Dynamic ABI values, nested local fixed-array mutation, nested crosscall
  aggregate arrays, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM aggregate gap around nested crosscall aggregates
  or dynamic ABI data.

### EVM IR Contract Creation

Commit: feature commit for EVM IR contract creation

Summary:

- Added portable IR `crosscallCreate` and `crosscallCreate2` expressions for
  EVM contract creation from fixed init-code hex.
- Lowered creation expressions to deterministic Yul helpers that write init
  code into memory, call `create(value, offset, length)` or
  `create2(value, offset, length, salt)`, revert on zero-address failure, and
  return the deployed address word.
- Extended `EvmCrosscallProbe` with `deploy_create` and `deploy_create2`
  entrypoints using tiny init code that deploys a runtime returning U256 `42`.
- Kept non-EVM target behavior explicit by adding Psy unsupported diagnostics
  for both creation expressions.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmCrosscallProbe
scripts/evm/diagnostic-smoke.sh
scripts/psy/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 57 CrosscallProbe tests, including `create` deployment,
  deterministic `create2` address validation, and calls into the deployed
  runtime.
- EVM diagnostics now cover bad creation value type, malformed init-code hex,
  and bad `create2` salt type; Psy diagnostics cover unsupported creation
  nodes.

Known limitations:

- Creation init code is currently embedded as fixed hex in the IR expression.
- Dynamic constructor arguments, artifact-linked init code, creation manifests,
  live transaction broadcasting, and variable-length cross-call return data
  remain future EVM IR work.

Next step:

- Continue closing EVM call-surface gaps around artifact-linked creation or
  variable-length ABI data.

### EVM IR Struct-Array Crosscall Aggregates

Commit: feature commit for EVM IR struct-array crosscall aggregates

Summary:

- Extended the existing typed crosscall aggregate path to fixed arrays of flat
  structs.
- Added `EvmCrosscallProbe` entrypoints for fixed-array-of-flat-struct typed
  arguments and direct aggregate returns across normal, value-bearing, static,
  and delegate call modes.
- Reused the ABI-static flattening policy: `RemotePair[2]` lowers to four ABI
  words, preserving Bool and U32 return guards for every decoded element field.
- Refreshed golden Yul, artifact metadata entrypoint expectations, Foundry
  callee fixtures, and coverage/target validation docs.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmCrosscallProbe
scripts/evm/crosscall-ir-smoke.sh
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 55 CrosscallProbe tests, including fixed-array-of-flat-struct
  arguments and returns in normal/value/static/delegate modes.
- Metadata validation now checks all new struct-array crosscall selectors.

Known limitations:

- Aggregate crosscall arguments and returns remain limited to ABI-static flat
  shapes.
- Nested dynamic arrays, variable-length return data, and artifact-linked
  creation remain future EVM IR work.

Next step:

- Continue closing the remaining EVM call-surface gaps around artifact-linked
  creation or variable-length ABI data.

### EVM IR Aggregate Crosscall Arguments

Commit: feature commit for EVM IR aggregate crosscall arguments

Summary:

- Extended typed crosscall argument lowering beyond scalar words for normal,
  value-bearing, static, and delegate typed calls.
- Reused the EVM ABI flattening rules for flat struct and scalar fixed-array
  arguments, so helper arity now reflects the ABI word count rather than the
  surface IR argument count.
- Made crosscall helper discovery type-env aware, allowing let-bound local
  structs and fixed arrays to request the correct generated helper.
- Extended `EvmCrosscallProbe` with normal struct and fixed-array arguments,
  value-bearing struct arguments, static struct arguments, and delegate struct
  arguments.
- Kept nested aggregate crosscall argument shapes as explicit unsupported
  diagnostics.

Validation run:

```sh
lake build
scripts/evm/diagnostic-smoke.sh
scripts/evm/crosscall-ir-smoke.sh
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 35 CrosscallProbe tests, including aggregate argument calldata
  packing for normal/value/static/delegate typed calls.
- EVM diagnostics ran 55 cases, including nested aggregate argument rejection.

Known limitations:

- Aggregate crosscall arguments are limited to ABI-static flat structs and
  scalar fixed arrays.
- Value-bearing, static, and delegate typed crosscalls still return scalar
  words only.
- Contract creation and variable-length return data remain future work.

Next step:

- Continue closing EVM call-surface gaps around aggregate returns for
  value/static/delegate calls or contract creation manifests.

### EVM IR Aggregate Crosscall Returns

Commit: feature commit for EVM IR aggregate crosscall returns

Summary:

- Extended normal `crosscallInvokeTyped` returns beyond scalar words when the
  expression is returned directly from an ABI-facing entrypoint.
- Lowered flat struct and scalar fixed-array crosscall return data through
  arity- and ABI-word-shape-specific Yul helpers such as
  `__proof_forge_crosscall_0_abi_bool_u32`, assigning multiple helper results
  directly to the entrypoint's ABI return words.
- Preserved scalar behavior for value-bearing, static, and delegate typed
  crosscalls, and kept unsupported nested aggregate return shapes as explicit
  diagnostics.
- Extended `EvmCrosscallProbe` with `call_remote_pair` and
  `call_remote_array`, refreshed golden Yul, metadata selector checks, Foundry
  aggregate struct/array return tests, malformed Bool/U32 aggregate return
  guard tests, coverage manifests, validation gates, target docs, backlog, and
  Chinese docs.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/foundry-smoke.sh
```

Known limitations:

- Aggregate crosscall support is limited to normal typed calls returned
  directly from entrypoints.
- Aggregate crosscall arguments, value/static/delegate aggregate returns,
  nested aggregate return data, contract creation, and variable-length return
  data remain future EVM IR work.

Next step:

- Continue shrinking EVM cross-call gaps around aggregate arguments,
  value/static/delegate aggregate returns, or create/create2.

### EVM IR Typed Delegatecalls

Commit: feature commit for EVM IR typed delegatecalls

Summary:

- Added portable IR `crosscallInvokeDelegateTyped` for EVM delegate calls that
  return one scalar word.
- Lowered delegate calls to arity- and return-type-specific Yul helpers using
  `delegatecall(gas(), target, ...)`, sharing selector packing, scalar-word
  argument encoding, short-return checks, and Bool/U32 return guards with the
  other crosscall helper modes.
- Kept delegate semantics explicit across backends: Psy IR v0 rejects delegate
  typed crosscalls with a stable unsupported diagnostic.
- Extended `EvmCrosscallProbe` with U64/Bool/U32/Hash delegate entrypoints,
  refreshed golden Yul, Foundry caller-storage read/write checks, typed-return
  guard checks, metadata selector checks, EVM/Psy diagnostics, coverage
  manifests, target docs, validation gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/i18n/check-sync.sh
```

Known limitations:

- Delegate crosscalls are currently limited to scalar word arguments and one
  scalar word return (`U32`, `U64`, `Bool`, or `Hash`).
- Contract creation, aggregate crosscall arguments/returns, and
  variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking EVM cross-call gaps around create/create2 or aggregate
  calldata/return-data.

### EVM IR Typed Staticcalls

Commit: feature commit for EVM IR typed staticcalls

Summary:

- Added portable IR `crosscallInvokeStaticTyped` for read-only EVM
  cross-contract calls that return one scalar word.
- Lowered typed static calls to arity- and return-type-specific Yul helpers
  using `staticcall(gas(), target, ...)`, sharing selector packing, scalar-word
  argument encoding, short-return checks, and Bool/U32 return guards with the
  existing call helpers.
- Kept target semantics explicit across backends: Psy IR v0 rejects static
  typed crosscalls with a stable unsupported diagnostic rather than silently
  lowering them to the existing Felt-returning `__invoke_sync` form.
- Extended `EvmCrosscallProbe` with `call_remote_static` plus Bool/U32/Hash
  static typed variants, refreshed golden Yul, Foundry read-only return,
  typed-return guard, and static-context state-write failure checks, metadata
  selector checks, EVM/Psy diagnostics, coverage manifests, target docs,
  validation gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
```

Known limitations:

- Static crosscalls are currently limited to scalar word arguments and one
  scalar word return (`U32`, `U64`, `Bool`, or `Hash`).
- `delegatecall`, contract creation, aggregate crosscall arguments/returns, and
  variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking EVM cross-call gaps around `delegatecall`, create/create2,
  aggregate calldata/return-data, or richer artifact metadata for deployment.

### EVM IR Aggregate Event Data

Commit: feature commit for EVM IR aggregate event data

Summary:

- Extended EVM `eventEmit` / `eventEmitIndexed` lowering so non-indexed event
  data fields can be scalar words, flat structs, scalar fixed arrays, or fixed
  arrays of flat structs.
- Added canonical Solidity-style event signature generation for flat aggregate
  event fields, including `PairEvent((uint64,uint64))`,
  `ArrayEvent(uint64[2])`, and `PairArrayEvent((uint64,uint64)[2])`.
- Flattened aggregate event data into ABI-style 32-byte words before `log1`
  through `log4`, preserving scalar indexed topics for `eventEmitIndexed`.
- At the time of this entry, aggregate indexed fields still failed with a
  diagnostic instead of lowering. That limitation is resolved by the later
  "EVM IR Indexed Aggregate Event Topics" entry for flat supported aggregates.
- Extended `EventProbe` with `emit_pair_event`, `emit_array_event`, and
  `emit_pair_array_event`, refreshed golden Yul, Foundry recorded-log checks,
  metadata selector checks, EVM diagnostics, coverage, target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- At the time of this entry, indexed event fields were scalar-only (`U32`,
  `U64`, `Bool`, or `Hash`) and limited to three indexed fields after the
  signature topic. Flat supported aggregate indexed fields are covered by the
  later "EVM IR Indexed Aggregate Event Topics" entry.
- Richer first-class event declarations are still not represented in the
  portable IR.

Next step:

- Continue shrinking EVM gaps around richer cross-call return data,
  `staticcall`/`delegatecall`/creation call kinds, nested aggregate lowering,
  or real creation/broadcast manifests.

### EVM IR Indexed Event Topics

Commit: feature commit for EVM IR indexed events

Summary:

- Added portable IR `eventEmitIndexed` for EVM-style events with scalar indexed
  fields and non-indexed data fields.
- Lowered indexed events to Yul `log2`/`log3`/`log4`: topic0 is the
  Solidity-style event signature hash, indexed fields become topics, and
  non-indexed fields remain ABI-style 32-byte data words.
- Kept indexed events explicit on non-EVM targets: Psy IR v0 rejects the new
  node with a diagnostic instead of silently dropping topic semantics.
- Extended `EventProbe` with `emit_indexed_event`, refreshed golden Yul,
  Foundry recorded-log checks, metadata selector checks, EVM/Psy diagnostics,
  coverage manifests, target docs, validation gates, backlog, capability
  registry entries, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/i18n/check-sync.sh
```

Known limitations:

- Indexed event fields are limited to scalar EVM word values (`U32`, `U64`,
  `Bool`, or `Hash`) and at most three indexed fields after the signature
  topic.
- Aggregate event payloads and richer event declarations remain future work.

Next step:

- Continue shrinking EVM gaps around aggregate event payloads, richer
  cross-call return data, contract-creation call kinds, or nested aggregate
  lowering.

### EVM IR Solidity-Style Event Signatures

Commit: feature commit for EVM IR event signature topics

Summary:

- Changed portable IR `eventEmit` topic0 derivation from the raw event-name
  hash to `keccak256(Solidity-style event signature)`.
- Added EVM ABI type names for supported event scalar fields:
  `U32 -> uint32`, `U64 -> uint64`, `Bool -> bool`, and `Hash -> bytes32`.
- Reworked the Yul event topic preimage writer to pack arbitrary-length UTF-8
  signature strings into memory before hashing, removing the old 32-byte event
  name packing limit.
- Updated `EventProbe` golden Yul, Foundry recorded-log assertion, coverage
  manifest, EVM target docs, validation gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/i18n/check-sync.sh
```

Known limitations:

- Portable IR event payload fields remain limited to scalar word values:
  `U32`, `U64`, `Bool`, or `Hash`.
- Richer event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking event gaps around aggregate event payloads or richer event
  declarations, or move to another EVM surface such as richer cross-call return
  data or nested aggregate lowering.

### EVM IR Whole Storage Struct Read/Write

Commit: feature commit for EVM IR whole storage struct read/write

Summary:

- Allowed `storageScalarRead` and `storageScalarWrite` to operate on flat
  scalar storage structs by expanding the struct into declaration-ordered EVM
  field slots.
- Added aggregate-only lowering for struct storage reads: struct local
  bindings, struct field access, whole local struct assignment, and struct
  returns can consume `storageScalarRead` without treating the struct as a
  single EVM word.
- Lowered whole scalar storage struct writes from local structs, struct
  literals, and storage struct reads with RHS field snapshotting before writing
  target slots.
- Extended `EvmStorageStructProbe` with whole write/read-into-local, direct
  ABI struct return from storage, and self-referential storage write snapshot
  coverage.
- Refreshed golden Yul, artifact metadata entrypoint checks, Foundry smoke
  tests, diagnostics, coverage manifest, target docs, validation gates, backlog,
  and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Whole storage struct operations are limited to flat scalar storage structs
  whose fields lower to EVM words (`U32`, `U64`, `Bool`, or `Hash`).
- Nested struct fields, non-flat struct storage, nested arrays, and dynamic or
  nested aggregate ABI values remain explicit diagnostics or documented gaps.

Next step:

- Continue shrinking the EVM aggregate unsupported surface around nested local
  aggregate shapes, broader storage-backed aggregate ABI values, richer
  cross-call return data, or event schema fidelity.

### EVM IR Struct Array Whole Local Assignment

Commit: feature commit for EVM IR struct-array whole local assignment

Summary:

- Allowed `assign (.local name) value` for mutable local fixed arrays whose
  element type is a flat struct.
- Lowered whole local struct-array assignment from another local struct array
  or a struct-array literal by snapshotting every RHS element field into
  temporary Yul locals before writing the expanded target fields.
- Extended `EvmStructArrayValueProbe` with `whole_struct_array_assign()` and
  `self_struct_array_assign()` to validate local-source assignment and
  self-referential literal RHS snapshot semantics.
- Refreshed the golden Yul, artifact metadata entrypoint checks, Foundry smoke
  harness, EVM coverage manifest, target docs, validation gates, backlog, and
  Chinese docs.

Validation run:

```sh
lake build
scripts/evm/struct-array-value-ir-smoke.sh
```

Known limitations:

- Struct-array whole assignment is limited to fixed arrays whose element type is
  a flat struct over EVM word fields (`U32`, `U64`, `Bool`, or `Hash`).
- Nested arrays, nested local structs, whole-struct storage reads/writes, and
  dynamic or nested aggregate ABI values remain explicit diagnostics.

Next step:

- Continue shrinking the remaining EVM aggregate unsupported surface, likely
  around nested aggregate locals, richer cross-call return data, or event schema
  fidelity.

### EVM IR Storage Map Contains

Commit: feature commit for EVM IR storage map contains

Summary:

- Lowered `storage.map.contains` for EVM portable IR through
  ProofForge-managed presence slots instead of treating nonzero map values as
  presence.
- Added `__proof_forge_map_presence_slot(slot, key)`, rooted at
  `keccak256(slot || PROOF_FORGE_MAP_PRESENCE)`, while preserving the existing
  Solidity-style value slot `keccak256(key || slot)`.
- Updated map insert/set, map statement writes, and map storage-path compound
  assignment helpers to mark key presence whenever ProofForge writes a map key.
- Extended `EvmMapProbe` with U64 contains coverage, including a zero-valued
  present key, and extended `EvmTypedMapProbe` with U32/Bool/Hash contains
  entrypoints.
- Updated diagnostics so statement-position `storage.map.contains` fails with
  an expression-only diagnostic instead of an unsupported-capability error.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/map-ir-smoke.sh
scripts/evm/typed-map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Presence tracks keys written through ProofForge-generated map helpers; raw
  external storage mutation outside those helpers can still bypass the
  presence mapping.
- Nested map paths and aggregate/non-word map key/value shapes remain explicit
  diagnostics.

Next step:

- Continue shrinking the remaining EVM aggregate unsupported surface, likely
  around nested aggregate locals, richer event schemas, or broader cross-call
  return data.

### EVM IR Whole Local Aggregate Assignment

Commit: feature commit for EVM IR whole local aggregate assignment

Summary:

- Allowed `assign (.local name) value` for mutable local fixed-array and flat
  local struct values.
- Lowered whole local fixed-array assignment from another local fixed-array or a
  fixed-array literal by snapshotting RHS element words into temporary Yul
  locals before assigning expanded target elements.
- Lowered whole local struct assignment from another local struct or a struct
  literal by snapshotting RHS field words into temporary Yul locals before
  assigning expanded target fields.
- Extended `EvmArrayValueProbe` with `whole_array_assign()` and
  `EvmStructValueProbe` with `whole_struct_assign()` to validate local-source
  assignment and self-referential literal RHS snapshot semantics.
- Updated EVM diagnostics, coverage manifests, target docs, validation gates,
  backlog, and Chinese docs to remove the stale whole-local-aggregate
  assignment limitation.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Whole local aggregate assignment is limited to flat fixed-array and flat
  struct locals whose elements/fields lower to EVM words.
- Nested arrays, nested local structs, and whole-struct storage reads/writes
  remain explicit diagnostics.
- Dynamic or nested aggregate ABI values remain out of scope for the current
  flat ABI lowering.

Next step:

- Continue shrinking the EVM aggregate unsupported surface around nested
  aggregate locals, richer cross-call return data, or event schema fidelity.

### EVM IR Dynamic Local Fixed-Array Indexes

Commit: feature commit for EVM IR dynamic local fixed-array indexing

Summary:

- Threaded the EVM IR lowering environment through expression, effect,
  aggregate binding, return, and statement lowering so local aggregate shape is
  available during code generation.
- Added dynamic `arrayGet` lowering for local fixed-array values and fixed-array
  literals using length-specific Yul getter helpers with default revert cases.
- Added dynamic mutable local fixed-array element assignment and numeric
  compound assignment lowering with Yul `switch` blocks over expanded local
  elements.
- Extended `EvmArrayValueProbe` with `dynamic_pick(uint256)` and
  `dynamic_update(uint256)`, refreshed golden Yul, metadata entrypoint
  validation, and Foundry assertions for in-bounds values and out-of-bounds
  reverts.
- Updated EVM diagnostics, coverage manifests, target docs, validation gates,
  backlog, and Chinese docs to remove the stale dynamic-local-index limitation.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Dynamic fixed-array indexing is limited to local fixed-array values and
  fixed-array literals whose elements lower to EVM words.
- Whole local aggregate assignment is handled by the later
  "EVM IR Whole Local Aggregate Assignment" entry.
- Nested arrays, nested local structs, and whole-struct storage reads/writes
  remain explicit diagnostics.
- Dynamic or nested aggregate ABI values remain out of scope for the current
  flat ABI lowering.

Next step:

- Continue shrinking the EVM aggregate unsupported surface, most likely around
  nested aggregate locals or richer cross-call return data.

### EVM Deploy Manifest Metadata

Commit: feature commit for EVM deploy manifest metadata

Summary:

- Extended EVM bytecode modes to emit a ProofForge EVM deploy manifest next to
  each `proof-forge-artifact.json` metadata file.
- The manifest records source kind/module, portable IR version when present,
  capabilities, ABI entrypoints or SDK methods, Yul/source inputs, runtime
  bytecode hash/size, and `creation.mode: runtime-bytecode`.
- EVM artifact metadata now records the deploy manifest artifact and requires
  `validation.deployManifest: passed`.
- Added a standalone `scripts/evm/validate-deploy-manifest.py` validator and
  extended `scripts/evm/validate-artifact-metadata.py` to validate the
  referenced deploy manifest against metadata.
- Updated EVM target docs, validation gates, backlog, and Chinese docs to
  distinguish ProofForge runtime-bytecode manifests from future broadcast or
  creation-transaction manifests.

Validation run:

```sh
lake build ProofForge.Cli proof-forge
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/build-examples.sh
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture AbiScalarProbe --expect-source-kind portable-ir build/ir/AbiScalarProbe.proof-forge-deploy.json
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture Counter.lean --expect-source-kind lean-sdk build/evm/Counter.proof-forge-deploy.json
```

Known limitations:

- The deploy manifest describes runtime bytecode deployment inputs only.
- It does not yet generate constructor initcode, Foundry broadcast JSON, chain
  id, deployed address, or a signed/raw transaction.
- Foundry smokes still install runtime bytecode with `vm.etch`.

Next step:

- Either extend EVM manifests toward creation/broadcast artifacts, or continue
  shrinking the remaining EVM IR unsupported surface around dynamic aggregates
  and richer cross-call returns.

### EVM IR Mutable Local Aggregates

Commit: feature commit for EVM IR mutable local aggregate lowering

Summary:

- Extended EVM IR lowering for local fixed-array and flat struct values from
  immutable-only bindings to mutable aggregate locals.
- Added static local fixed-array element assignment and numeric compound
  assignment over expanded Yul locals.
- Added static local struct field assignment and numeric compound assignment
  over expanded Yul locals.
- Extended `EvmArrayValueProbe` and `EvmStructValueProbe` with mutable
  `U64`/`U32`/`Bool`/`Hash` write paths, metadata entrypoint validation,
  refreshed golden Yul, and Foundry runtime assertions.
- Updated EVM diagnostics so immutable aggregate element/field assignment still
  fails explicitly while mutable aggregate locals now lower successfully.
- Updated EVM coverage, target docs, validation gates, backlog, and Chinese
  docs to remove stale mutable-local aggregate limitations.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmArrayValueProbe ProofForge.IR.Examples.EvmStructValueProbe proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Dynamic local fixed-array indexing is handled by the later
  "EVM IR Dynamic Local Fixed-Array Indexes" entry.
- Whole local aggregate assignment remains an explicit diagnostic; update
  elements or fields directly for now.
- Nested arrays, nested local structs, and whole-struct storage reads/writes
  remain explicit diagnostics.

Next step:

- Continue shrinking the EVM aggregate unsupported surface around nested
  aggregate locals or richer cross-call return data.

### EVM IR Scalar Expression Probe

Commit: feature commit for EVM IR scalar expression validation

Summary:

- Added `ProofForge.IR.Examples.EvmExpressionProbe` to validate scalar
  expression lowering directly, separate from storage or assignment side
  effects.
- Covered `U64` and `U32` arithmetic (`add`, `sub`, `mul`, `div`, `mod`),
  `U64` exponentiation, `U64`/`U32` bitwise operators and shifts, predicates,
  boolean `and`/`or`/`not`, scalar literals, immutable local reads, supported
  `U32`/`U64`/`Bool` casts, one-word scalar returns, and assertion guards.
- Added CLI emission modes, golden Yul, Foundry smoke coverage, artifact
  metadata validation, and CI.
- Updated EVM coverage, target docs, validation gates, backlog, and Chinese
  docs so the scalar expression family now has runtime validation evidence
  instead of only structural lowering notes.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmExpressionProbe proof-forge
scripts/evm/expression-ir-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- EVM arithmetic still follows raw EVM word semantics; checked overflow,
  signed arithmetic, and target-specific numeric policies remain future
  design work.
- Aggregate expression behavior remains covered by the array, struct, and ABI
  probes rather than this scalar expression probe.

Next step:

- Continue converting remaining `lowered` coverage rows into validated probes
  or explicit diagnostics, especially around target-specific artifact/deploy
  surfaces and any residual statement/effect validation gaps.

### EVM IR Typed Storage Maps

Commit: feature commit for EVM IR typed storage maps

Summary:

- Generalized portable EVM storage maps from `Map<U64, U64, N>` to word
  key/value maps over `U32`, `U64`, `Bool`, and `Hash`.
- Reused the existing Solidity-style `keccak256(key, slot)` mapping slot helper
  for all supported word map shapes, preserving one declared storage slot per
  map state.
- Added `ProofForge.IR.Examples.EvmTypedMapProbe`, CLI emission modes, golden
  Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Covered ABI dispatcher guards for `U32` and `Bool` map parameters,
  expression-position previous-value returns, statement-position writes,
  `Hash`/`bytes32` map values, raw mapping slots, and single-segment `mapKey`
  storage-path read/write/compound assignment.
- Updated EVM diagnostics, coverage, target docs, validation gates, and Chinese
  docs so unsupported map diagnostics now target non-word map shapes while
  `storage.map.contains` remains explicitly unsupported.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.IR.Examples.EvmTypedMapProbe proof-forge
scripts/evm/typed-map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- EVM storage maps still support only single-word key/value shapes. Aggregate,
  nested, dynamic, or non-word map key/value shapes remain explicit diagnostics.
- `storage.map.contains` remains unsupported because EVM mappings do not track
  key presence without an auxiliary bitmap.
- Nested map storage paths remain unsupported; `mapKey` paths are currently
  single-segment only.

Next step:

- Continue reducing the remaining EVM IR unsupported surface, likely around
  richer ABI/cross-call surfaces or target-specific deployment artifacts, with
  the same golden Yul, metadata, Foundry, diagnostics, and CI pattern.

### EVM IR Typed Storage Words

Commit: feature commit for EVM IR typed storage word arrays

Summary:

- Generalized portable EVM storage arrays from `U64`-only arrays to word-scalar
  arrays over `U32`, `U64`, `Bool`, and `Hash`.
- Enabled `Bool` scalar storage in the portable EVM backend; scalar storage
  still rejects unsupported non-word shapes explicitly.
- Reused the existing contiguous `__proof_forge_array_slot(base, length,
  index)` helper for typed word arrays, preserving runtime out-of-bounds
  checks and deterministic slot layout.
- Added `ProofForge.IR.Examples.EvmTypedStorageProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Updated EVM diagnostics, coverage, target docs, validation gates, and Chinese
  docs so `Unit` storage remains the explicit unsupported case while
  `Bool`/`U32`/`Hash` storage arrays are validated behavior.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/typed-storage-ir-smoke.sh
```

Known limitations:

- Typed storage arrays are still fixed-size word arrays. Nested arrays, dynamic
  storage arrays, and non-word storage elements remain future work.

Next step:

- Continue reducing the remaining EVM IR unsupported surface, likely either
  richer map shapes or the next ABI/control/cross-call gap, with the same
  golden Yul, metadata, Foundry, diagnostics, and CI pattern.

### EVM IR Flat Storage Structs

Commit: feature commit for EVM IR flat storage struct lowering

Summary:

- Added EVM portable IR lowering for flat scalar storage structs and fixed
  storage arrays of flat structs. Scalar storage structs reserve one slot per
  field; struct arrays reserve `length * field_count` slots.
- Added direct lowering for `storageStructFieldRead`/`Write` and
  `storageArrayStructFieldRead`/`Write`, plus generic storage paths using
  scalar `field` and array `index`+`field` segments.
- Added the `__proof_forge_struct_array_slot` Yul helper with runtime
  out-of-bounds checks and deterministic
  `base + index * field_count + field_offset` slot derivation.
- Added `ProofForge.IR.Examples.EvmStorageStructProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Updated EVM diagnostics and coverage so whole-struct storage reads/writes and
  missing fields fail explicitly before Yul generation.

Validation run:

```sh
lake build proof-forge
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- Storage struct support is flat and field-based only. Whole-struct storage
  reads/writes, nested struct fields, map values shaped as structs, and dynamic
  storage arrays remain explicit future work.

Next step:

- Continue EVM portable IR support toward richer storage element types or the
  next unsupported ABI/control surface, keeping the same golden Yul, metadata,
  Foundry, diagnostics, and CI pattern.

### EVM IR Flat Aggregate ABI

Commit: feature commit for EVM IR flat aggregate ABI lowering

Summary:

- Added EVM portable IR ABI flattening for flat static fixed-array and struct
  parameters. Fixed arrays lower to one calldata word per element, and structs
  lower to fields in declaration order.
- Added dispatcher range guards for `U32` and `Bool` words inside aggregate
  ABI parameters.
- Added multi-word return-data lowering for flat fixed-array and struct return
  values, including local fixed-array returns and struct literal returns.
- Added `ProofForge.IR.Examples.EvmAbiAggregateProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Updated EVM diagnostics so Unit ABI values, zero-length ABI arrays, and
  nested aggregate ABI values fail explicitly before Yul generation.

Validation run:

```sh
lake build
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- Aggregate ABI support is flat/static only. Nested aggregate ABI values,
  dynamic arrays, storage structs, mutable local structs, and struct arrays
  remain future work.

Next step:

- Continue the EVM backend toward storage struct layout or richer ABI/event
  schemas, using the same fixture, golden, metadata, Foundry, and CI pattern.

### CI ContextProbe Target Split

Commit: bugfix commit for CI fixture isolation

Summary:

- Split `ContextProbe` target usage so the shared Psy fixture keeps only
  target-portable context reads.
- Added `ProofForge.IR.Examples.EvmContextProbe` for EVM-only `nativeValue`
  coverage while preserving the existing `ContextProbe` Yul object name,
  selectors, golden Yul, and Foundry smoke behavior.
- Updated EVM context CLI emission to use the EVM-specific fixture, while
  `--emit-context-ir-psy` continues to use the Psy-compatible fixture.
- Fixed the GitHub Actions failure where the Psy golden source step attempted
  to lower `nativeValue`, which Psy IR v0 intentionally rejects.
- Made `scripts/evm/build-examples.sh` explicitly build `ProofForge.Evm` before
  compiling SDK examples so clean CI environments have the SDK `.olean` needed
  by the Lean frontend.

Validation run:

```sh
lake build
# Full Check Psy golden sources block from .github/workflows/ci.yml
scripts/evm/context-ir-smoke.sh
scripts/evm/build-examples.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- Psy still rejects `nativeValue` by design; EVM owns the current
  `callvalue()` lowering and runtime validation.

Next step:

- Re-run GitHub Actions on `main` and continue the EVM aggregate ABI work after
  CI is green.

### EVM IR Local Struct Values

Commit: feature commit for EVM IR local struct values

Summary:

- Added EVM portable IR lowering for flat immutable local struct values by
  expanding each supported field into an internal Yul local.
- Added direct field-access lowering for local struct values and struct
  literals over `U64`, `U32`, `Bool`, and `Hash` fields.
- Registered partial `data.struct` support in the EVM target profile and
  metadata capability flow.
- Added explicit diagnostics for struct storage, mutable local structs, nested
  struct fields, ABI-facing structs, duplicate/empty struct declarations, and
  unsupported field shapes.
- Added `ProofForge.IR.Examples.EvmStructValueProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.

Validation run:

```sh
lake build
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- This feature supports flat immutable local struct values only. Mutable local
  structs, nested structs, storage structs, struct arrays, ABI structs, and
  struct assignment paths remain future work.

Next step:

- Continue EVM aggregate coverage toward ABI aggregate values or storage
  struct layout once the target-specific EVM ABI/storage policy is specified.

### EVM IR Local Fixed-Array Values

Commit: feature commit for EVM IR local fixed-array values

Summary:

- Added EVM portable IR lowering for immutable local fixed-array values by
  expanding each array element into an internal Yul local.
- Added static `arrayGet` lowering for local fixed-array values and direct
  fixed-array literals over `U64`, `U32`, `Bool`, and `Hash` elements.
- Added explicit diagnostics for mutable fixed-array locals, dynamic local
  fixed-array indexes, and static out-of-bounds indexes.
- Added `ProofForge.IR.Examples.EvmArrayValueProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.

Validation run:

```sh
lake build proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- This feature supports immutable local fixed-array values with static indexes.
  Dynamic local indexes, mutable local arrays, nested arrays, aggregate ABI
  arrays, and storage arrays beyond the existing `U64` path remain future work.

Next step:

- Continue EVM aggregate coverage toward structs or ABI aggregate values, using
  the same fixture/golden/smoke/metadata pattern.

### EVM IR Array Index Storage Paths

Commit: feature commit for EVM IR array index storage paths

Summary:

- Added EVM portable IR lowering for single-segment `StoragePathSegment.index`
  paths over `U64` fixed storage arrays.
- Reused `__proof_forge_array_slot(base, length, index)` for generic
  `storagePathRead`, `storagePathWrite`, and `storagePathAssignOp` so direct
  array effects and storage paths share bounds-checking behavior.
- Extended `EvmStorageArrayProbe` with `path_lifecycle()` and
  `path_assign_lifecycle()`.
- Extended `scripts/evm/storage-array-ir-smoke.sh` to validate path read,
  write, compound assignment, metadata selectors, and raw storage slots.
- Kept nested index paths, struct paths, and non-`U64` arrays explicitly
  rejected.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-storage-array-ir-yul -o build/ir/EvmStorageArrayProbe.yul
diff -u Examples/Evm/EvmStorageArrayProbe.golden.yul build/ir/EvmStorageArrayProbe.yul
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- This feature supports exactly one `index` path segment over `U64` storage
  arrays. Nested array paths, struct fields, local fixed-array values, and
  aggregate ABI arrays remain future work.

Next step:

- Move from storage-array paths toward local fixed-array values or flat structs,
  depending on which aggregate surface is needed first.

### EVM IR U64 Storage Arrays

Commit: feature commit for EVM IR U64 storage array lowering

Summary:

- Added EVM target-profile support for `storage.array` and partial
  `data.fixed_array`.
- Added state-slot span accounting so fixed storage arrays reserve one EVM
  storage slot per element and later state starts after the full array span.
- Added portable IR lowering for `storageArrayRead` and `storageArrayWrite`
  over `U64` storage arrays.
- Lowered array access through `__proof_forge_array_slot(base, length, index)`,
  which reverts when the runtime index is out of bounds before `sload` or
  `sstore`.
- Added `ProofForge.IR.Examples.EvmStorageArrayProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Kept local fixed-array values, aggregate ABI arrays, generic index storage
  paths, structs, and non-`U64` storage arrays explicitly rejected.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-storage-array-ir-yul -o build/ir/EvmStorageArrayProbe.yul
diff -u Examples/Evm/EvmStorageArrayProbe.golden.yul build/ir/EvmStorageArrayProbe.yul
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- This feature covers `U64` storage arrays only. `U32`, `Hash`, `Bool`,
  struct arrays, local fixed-array values, ABI arrays, and generic index
  storage paths remain follow-up work.

Next step:

- Extend EVM aggregate support toward local fixed-array values or generic index
  storage paths, then move into structs once the array layout is stable.

### EVM IR Native Value

Commit: feature commit for EVM IR native value lowering

Summary:

- Added EVM portable IR lowering for expression-position `nativeValue` as Yul
  `callvalue()`.
- Extended `ProofForge.IR.Examples.ContextProbe` with `native_value()` and
  selector `0xf0eba40f`.
- Extended `scripts/evm/context-ir-smoke.sh` so Foundry calls
  `native_value()` with attached value and verifies the returned word.
- Updated EVM artifact metadata validation to require `value.native` and the
  `native_value:f0eba40f` entrypoint.
- Moved `Expr.nativeValue` in `Tests/EvmCoverage.tsv` from unsupported to
  validated and removed the old unsupported diagnostic case.

Validation run:

```sh
lake build
lake env proof-forge --emit-context-ir-yul -o build/ir/ContextProbe.yul
diff -u Examples/Evm/ContextProbe.golden.yul build/ir/ContextProbe.yul
scripts/evm/context-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- `nativeValue` is exposed as the raw EVM call value word. Higher-level native
  asset accounting remains a target/runtime policy layer above this IR node.

Next step:

- Continue expanding EVM portable IR coverage one small capability at a time,
  with fixture, smoke, coverage, docs, commit, and push for each feature.

### EVM IR Map Path Compound Assignment

Commit: feature commit for EVM IR map path compound assignment

Summary:

- Added EVM portable IR lowering for statement-position `storagePathAssignOp`
  on single-segment `mapKey` paths over `Map<U64, U64, N>`.
- Lowered map path compound assignment through generated Yul helpers named
  `__proof_forge_map_assign_<op>`.
- Kept mapping slot calculation inside the helper so the key expression is
  evaluated once and the computed storage slot is reused for `sload` and
  `sstore`.
- Added type validation so storage path compound assignment requires matching
  numeric path/value types.
- Kept nested map paths, array paths, and struct paths explicitly rejected
  until those storage layouts are implemented.
- Extended `ProofForge.IR.Examples.EvmMapProbe` with
  `path_assign_lifecycle()`, updated `Examples/Evm/EvmMapProbe.golden.yul`,
  and extended `scripts/evm/map-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-map-ir-yul -o build/ir/EvmMapProbe.yul
diff -u Examples/Evm/EvmMapProbe.golden.yul build/ir/EvmMapProbe.yul
scripts/evm/map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmMapProbe Yul includes selector dispatch for
  `path_assign_lifecycle()` and map assign helpers for all `AssignOp`
  variants.
- Foundry verifies `path_assign_lifecycle()` returns `58`, the raw mapping
  slot for key `3003` is `58`, and existing map get/set/path behavior still
  passes.
- EVM artifact metadata records and validates `storage.scalar`, `storage.map`,
  and `assertions.check`.
- Diagnostics reject expression-position `storagePathAssignOp` and nested
  storage-path compound assignment.

Known limitations at the time of this entry:

- EVM IR storage path compound assignment supported only a single `mapKey` over
  `Map<U64, U64, N>`.
- Array index paths, struct field paths, nested paths, and non-`U64` map shapes
  remained explicit diagnostics.

Next step:

- Continue EVM portable IR support toward storage arrays, structs, aggregate
  ABI values, or checked arithmetic semantics.

### EVM IR Compound Assignment

Commit: feature commit for EVM IR compound assignment

Summary:

- Added EVM portable IR lowering for `Statement.assignOp` on mutable local
  `U32`/`U64` bindings.
- Added EVM portable IR lowering for statement-position
  `storageScalarAssignOp` on numeric scalar storage.
- Lowered arithmetic/bitwise compound assignment to Yul
  `add/sub/mul/div/mod/and/or/xor`, and lowered shifts with EVM operand order
  through `shl(shift, value)` and `shr(shift, value)`.
- Added type validation so compound assignment requires matching `U32` or
  `U64` operands, mutable local targets, and scalar numeric storage targets.
- Kept aggregate assignment targets and storage path compound assignment
  outside this local/scalar feature; the following map path entry closes the
  single-segment `mapKey` subset.
- Added `ProofForge.IR.Examples.EvmAssignOpProbe`,
  `--emit-evm-assign-op-ir-yul`, `--emit-evm-assign-op-ir-bytecode`,
  `Examples/Evm/EvmAssignOpProbe.golden.yul`, and
  `scripts/evm/assign-op-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-assign-op-ir-yul -o build/ir/EvmAssignOpProbe.yul
diff -u Examples/Evm/EvmAssignOpProbe.golden.yul build/ir/EvmAssignOpProbe.yul
scripts/evm/assign-op-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmAssignOpProbe Yul includes selector dispatch, local compound
  assignment, scalar storage `sstore(slot, op(sload(slot), value))`, and U32
  ABI range guards.
- Foundry verifies `compound_assignment(uint256)` returns `58`, raw storage
  slot `0` is `58`, `compound_u32(uint32)` returns `11`, and unknown selectors
  revert.
- EVM artifact metadata records and validates `storage.scalar`.
- Diagnostics reject non-local compound assignment targets, non-numeric
  compound operands, and expression-position scalar storage compound
  assignment.

Known limitations:

- EVM IR compound assignment in this entry supports only mutable local scalars
  and scalar storage; aggregate locals remain out of scope.
- Operations use raw EVM word semantics and do not add checked-overflow
  behavior.

Next step:

- Continue EVM portable IR support toward storage arrays, structs, aggregate
  ABI values, or storage-path compound updates.

### EVM IR Bounded Loops

Commit: feature commit for EVM IR bounded loops

Summary:

- Added EVM target support for `control.bounded_loop`.
- Added EVM portable IR lowering for statement-position `boundedFor`.
- Lowered bounded loops to Yul `for` loops with a static `let` index prelude,
  `lt(index, stopExclusive)` condition, and `index := add(index, 1)` post
  block.
- Added type validation for loop bodies with the loop index available as an
  immutable `U32` local.
- Added explicit diagnostics for invalid loop ranges and loop-local returns.
- Added `ProofForge.IR.Examples.EvmLoopProbe`,
  `--emit-evm-loop-ir-yul`, `--emit-evm-loop-ir-bytecode`,
  `Examples/Evm/EvmLoopProbe.golden.yul`, and
  `scripts/evm/loop-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-loop-ir-yul -o build/ir/EvmLoopProbe.yul
diff -u Examples/Evm/EvmLoopProbe.golden.yul build/ir/EvmLoopProbe.yul
scripts/evm/loop-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmLoopProbe Yul includes selector dispatch and a Yul `for` loop
  that increments scalar storage three times.
- Foundry verifies the returned value and raw storage slot are both `3`, plus
  unknown-selector revert behavior.
- EVM artifact metadata records and validates `control.bounded_loop`.
- Diagnostics reject invalid bounded-loop ranges and loop-local returns.

Known limitations:

- EVM IR bounded loops currently require static natural-number bounds from the
  portable IR node.
- Loop-local `return`, `break`, and `continue` are not modeled yet.

Next step:

- Continue expanding EVM portable IR support for aggregate values, storage
  arrays, structs, or compound assignment.

### EVM IR Crosscalls

Commit: feature commit for EVM IR crosscalls

Summary:

- Added EVM portable IR lowering for expression-position `crosscallInvoke`.
- Defined the EVM IR v0 crosscall policy: target is an address word, method is
  a low-32-bit selector, arguments are 32-byte words, the call uses zero ETH
  value, and the result is one 32-byte return word.
- Added arity-specific Yul helpers that pack calldata, call
  `call(gas(), target, 0, ...)`, revert on failed calls or short returns, and
  decode the returned word.
- Added type validation so crosscall target, method, and every argument must be
  `U64`.
- Added `ProofForge.IR.Examples.EvmCrosscallProbe`,
  `--emit-evm-crosscall-ir-yul`, `--emit-evm-crosscall-ir-bytecode`,
  `Examples/Evm/EvmCrosscallProbe.golden.yul`, and
  `scripts/evm/crosscall-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-crosscall-ir-yul -o build/ir/EvmCrosscallProbe.yul
diff -u Examples/Evm/EvmCrosscallProbe.golden.yul build/ir/EvmCrosscallProbe.yul
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmCrosscallProbe Yul includes selector dispatch, calldata size
  guards, zero/one/two-argument crosscall helpers, failed-call reverts,
  short-return reverts, and one-word return decoding.
- Foundry verifies a Solidity callee for zero/one/two argument calls, callee
  reverts, short returns, and unknown-selector reverts.
- EVM artifact metadata records and validates `crosscall.invoke`.
- Diagnostics reject malformed crosscall target, method, and argument types.

Known limitations at this slice:

- This first crosscall slice modeled only synchronous zero-value `call`.
- Later slices below add typed scalar returns and value-bearing typed scalar
  calls; `staticcall`, `delegatecall`, create/create2, aggregate
  arguments/returns, and variable-length return data remain future IR work.

Next step:

- Continue expanding the EVM portable IR surface toward typed scalar returns,
  aggregate ABI values, arrays, structs, or richer call semantics.

### EVM IR Typed Scalar Crosscalls

Commit: feature commit for EVM IR typed scalar crosscalls

Summary:

- Added portable IR `crosscallInvokeTyped` as a typed scalar-word crosscall
  expression while preserving the existing `crosscallInvoke` U64 behavior and
  helper names.
- Extended EVM lowering so typed crosscalls accept `Bool`, `U32`, `U64`, and
  `Hash` word arguments and return `Bool`, `U32`, `U64`, or `Hash`.
- Generated return-type-specific Yul helpers such as
  `__proof_forge_crosscall_1_bool`, `__proof_forge_crosscall_1_u32`, and
  `__proof_forge_crosscall_1_hash`; Bool and U32 helpers reject out-of-range
  return words after `returndatacopy`.
- Extended `EvmCrosscallProbe` with `call_remote_bool`, `call_remote_u32`, and
  `call_remote_hash`, plus Foundry callee methods for valid typed returns and
  malformed Bool/U32 return words.
- Added explicit EVM diagnostics for unsupported typed crosscall aggregate
  arguments/returns and an explicit Psy diagnostic because Psy IR v0 still only
  supports untyped Felt-returning `crosscallInvoke`.
- Updated golden Yul, EVM/Psy coverage manifests, validation gates, EVM target
  docs, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-crosscall-ir-yul -o build/ir/EvmCrosscallProbe.yul
diff -u Examples/Evm/EvmCrosscallProbe.golden.yul build/ir/EvmCrosscallProbe.yul
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/psy/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
```

Result:

- Generated EvmCrosscallProbe Yul includes selector dispatch for the typed
  entrypoints, Bool/U32 calldata guards, typed crosscall helper names, and
  Bool/U32 return-data guards.
- Foundry verifies U64 zero/one/two-argument calls, Bool/U32/Hash typed return
  calls, callee reverts, short returns, invalid Bool/U32 return words, and
  unknown-selector reverts.
- EVM artifact metadata validates all six CrosscallProbe entrypoints and
  records `crosscall.invoke`.
- Diagnostics reject unsupported typed crosscall aggregate arguments/returns,
  while Psy rejects typed crosscalls explicitly instead of silently lowering
  them as Felt calls.

Known limitations:

- Portable IR EVM crosscalls still model only synchronous `call`.
- Aggregate arguments/returns, multi-word return data, `staticcall`,
  `delegatecall`, and create/create2 remain future IR work.

Next step:

- Continue closing EVM backend gaps around richer call semantics, ABI aggregate
  storage-backed surfaces, and unsupported-node diagnostics.

### EVM IR Value-Bearing Typed Crosscalls

Commit: feature commit for EVM IR value-bearing typed crosscalls

Summary:

- Added portable IR `crosscallInvokeValueTyped` for synchronous EVM calls that
  forward an explicit `U64` call-value expression while returning a typed
  scalar word.
- Extended EVM lowering with value-specific Yul helpers named like
  `__proof_forge_crosscall_value_0`; these helpers keep the same selector and
  calldata packing as scalar crosscalls but pass `call_value` into the EVM
  `call(gas(), target, call_value, ...)` value slot.
- Extended `EvmCrosscallProbe` with `call_remote_value`, implemented using
  `.nativeValue` so the entrypoint forwards the ETH received by the probe to a
  payable callee.
- Added Foundry coverage that calls the probe with value, asserts the payable
  callee receives `msg.value`, checks the callee balance, and verifies the probe
  does not retain the forwarded value.
- Added explicit EVM diagnostics for malformed call-value type and unsupported
  aggregate return type, plus an explicit Psy unsupported diagnostic for
  value-bearing typed crosscalls.
- Updated golden Yul, coverage manifests, validation gates, EVM target docs,
  backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/psy/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
```

Result:

- `EvmCrosscallProbe` now has seven metadata-validated entrypoints, including
  `call_remote_value:365f4a44`.
- Generated Yul includes `__proof_forge_crosscall_value_0(target, selector,
  call_value)` and passes the helper value parameter to the `call` opcode.
- Foundry verifies 12 crosscall runtime paths, including ETH forwarding through
  `probe.call{value: 1234}` to a payable callee.
- EVM and Psy diagnostics cover the new portable IR node instead of relying on
  missing-pattern or silent lowering behavior.

Known limitations:

- Value-bearing crosscalls are currently limited to synchronous EVM `call` and
  single scalar-word return data.
- `staticcall`, `delegatecall`, create/create2, aggregate arguments/returns,
  and multi-word or variable-length return data remain future IR work.

Next step:

- Continue closing EVM cross-contract gaps around richer call kinds and richer
  return-data encoding.

### EVM IR Events

Commit: feature commit for EVM IR events

Summary:

- Added EVM portable IR lowering for statement-position `eventEmit`.
- Defined the EVM IR v0 event policy:
  `topic0 = keccak256(Solidity-style event signature)` and log data is the
  sequence of 32-byte field words.
- Added event name and field validation: event names must be non-empty; event
  fields must be `U32`, `U64`, `Bool`, or `Hash`; event emission remains
  statement-only.
- Added `--emit-evm-event-ir-yul`, `--emit-evm-event-ir-bytecode`,
  `Examples/Evm/EventProbe.golden.yul`, and
  `scripts/evm/event-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-event-ir-yul -o build/ir/EventProbe.yul
diff -u Examples/Evm/EventProbe.golden.yul build/ir/EventProbe.yul
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EventProbe Yul includes selector dispatch, calldata size guards,
  event signature hashing, field data writes, and `log1(0, 32, topic0)`.
- Foundry verifies recorded logs for emitter address, topic0, decoded data,
  and unknown-selector reverts.
- EVM artifact metadata records and validates `events.emit`.
- Diagnostics reject expression-position events and malformed event names.

Known limitations:

- Event data fields are limited to scalar word values.
- Indexed fields are now covered by `eventEmitIndexed`; aggregate event
  payloads and richer event declarations remain future work.

Next step:

- Extend aggregate event payloads or richer event declarations, or start
  cross-contract call lowering for the EVM portable IR backend.

### EVM IR Hash Words

Commit: feature commit for EVM IR hash words

Summary:

- Added EVM portable IR lowering for `Hash` as a one-word EVM `bytes32`
  representation across locals, ABI parameters, ABI returns, and scalar
  storage.
- Added `hash4` literal packing and dynamic `hashValue` packing from four
  `U64` limbs into one 256-bit word.
- Added Yul helper lowering for `hash` and `hash_two_to_one` using
  `keccak256(0, 32)` and `keccak256(0, 64)`.
- Added lightweight EVM IR type validation for the currently supported scalar
  and Hash subset so Hash/U64 mismatches fail before Yul generation.
- Added `ProofForge.IR.Examples.EvmHashProbe`,
  `--emit-evm-hash-ir-yul`, `--emit-evm-hash-ir-bytecode`,
  `Examples/Evm/EvmHashProbe.golden.yul`, and
  `scripts/evm/hash-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-hash-ir-yul -o build/ir/EvmHashProbe.yul
diff -u Examples/Evm/EvmHashProbe.golden.yul build/ir/EvmHashProbe.yul
scripts/evm/hash-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmHashProbe Yul includes selector dispatch, ABI calldata size
  guards, Hash literal packing, dynamic Hash packing, `keccak256` helpers,
  Hash scalar storage reads/writes, and one-word return encoding.
- Foundry verifies `bytes32` ABI params/returns, single-word and pair hashing,
  dynamic packing, Hash scalar storage, raw slot reads through `vm.load`, and
  unknown-selector reverts.
- EVM artifact metadata records and validates `crypto.hash` and
  `storage.scalar`.
- Diagnostics now treat Hash as supported in the EVM scalar subset and reject
  malformed Hash/U64 usage with explicit type mismatch messages.

Known limitations:

- EVM portable IR Hash currently uses a target-specific one-word `bytes32`
  representation; Psy still uses four Felt limbs.
- Hash map key/value shapes are still unsupported; EVM map support remains
  limited to `Map<U64, U64, N>`.
- Aggregate hashing inputs, arrays, structs, and events remain future work.

Next step:

- Extend EVM maps to additional scalar key/value shapes, or add event emission
  lowering with indexed topic/data metadata.

### EVM IR Storage Maps

Commit: feature commit for EVM IR storage maps

Summary:

- Added EVM portable IR lowering for `Map<U64, U64, N>` storage state.
- Added Solidity-style mapping slot helpers:
  `mstore(0, key)`, `mstore(32, slot)`, `keccak256(0, 64)`.
- Added EVM lowering for `storageMapGet`, `storageMapInsert`, and
  `storageMapSet`; expression-position set/insert return the previous value.
- Added single-segment `storagePathRead`/`storagePathWrite` support for
  `.mapKey` paths over `Map<U64, U64, N>`.
- Kept `storageMapContains` explicitly unsupported because EVM mappings do not
  track key presence without an auxiliary bitmap.
- Added `ProofForge.IR.Examples.EvmMapProbe`, `--emit-evm-map-ir-yul`,
  `--emit-evm-map-ir-bytecode`, `Examples/Evm/EvmMapProbe.golden.yul`, and
  `scripts/evm/map-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-map-ir-yul -o build/ir/EvmMapProbe.yul
diff -u Examples/Evm/EvmMapProbe.golden.yul build/ir/EvmMapProbe.yul
scripts/evm/map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmMapProbe Yul includes selector dispatch, scalar ABI calldata
  guards, map helper functions, map get/set/insert calls, assertion guards, and
  `keccak256(0, 64)` slot hashing.
- Foundry verifies lifecycle behavior, parameterized read/write behavior,
  single-segment `mapKey` storage paths, unknown-selector reverts, and raw
  mapping slots with `vm.load`.
- EVM artifact metadata records and validates `storage.scalar`, `storage.map`,
  and `assertions.check`.
- Diagnostics reject unsupported Hash map shapes, `storage.map.contains`, and
  malformed map storage paths.

Known limitations:

- EVM portable IR map support is currently limited to `Map<U64, U64, N>`.
- `storage.map.contains` remains unsupported until the IR models an EVM
  presence bitmap or a different target-specific presence policy.
- Nested map/struct/array storage paths are still rejected.

Next step:

- Extend maps to more scalar key/value shapes, or add EVM `crypto.hash`
  lowering with a clear Keccak-vs-portable-Hash semantic boundary.

### EVM IR Context Reads

Commit: feature commit for EVM IR context reads

Summary:

- Added EVM portable IR lowering for `contextRead` expressions:
  `userId -> caller()`, `contractId -> address()`, and
  `checkpointId -> number()`.
- Added an EVM selector to `ContextProbe` while preserving the existing Psy
  context fixture.
- Added `--emit-context-ir-yul` and `--emit-context-ir-bytecode` CLI modes.
- Added `Examples/Evm/ContextProbe.golden.yul` plus
  `scripts/evm/context-ir-smoke.sh`.
- Updated EVM capability metadata so `ContextProbe` validates
  `caller.sender`, `account.explicit`, and `env.block`.
- Updated EVM diagnostics, coverage manifest, CI, target docs, validation
  gates, backlog, and capability registry docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-context-ir-yul -o build/ir/ContextProbe.yul
diff -u Examples/Evm/ContextProbe.golden.yul build/ir/ContextProbe.yul
scripts/evm/context-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated ContextProbe Yul contains selector dispatch for
  `sum_context(uint256,uint256)`, ABI calldata size guarding, and direct EVM
  context opcodes.
- Foundry verifies `caller()` via `vm.prank`, `number()` via `vm.roll`, and
  `address()` via an etched runtime address.
- EVM artifact metadata records and validates the three context capabilities.
- Statement-position context reads remain rejected with an explicit diagnostic.

Known limitations:

- The current portable `ContextField` set covers only user id, contract id, and
  checkpoint id.
- EVM context values are emitted as 256-bit words; address-width and narrower
  integer normalization are still future type-validation work.

Next step:

- Add EVM `crypto.hash` lowering with a clear Keccak-vs-portable-Hash semantic
  boundary, or start EVM storage map slot hashing.

### EVM Artifact Metadata

Commit: feature commit for EVM artifact metadata

Summary:

- Added EVM `proof-forge-artifact.json` emission to `proof-forge`
  bytecode-producing modes, covering both `--evm-bytecode` SDK builds and
  portable IR EVM bytecode fixtures.
- Added `--artifact-output` to override the metadata path; without an override,
  bytecode modes write `proof-forge-artifact.json` next to the bytecode output.
- Added metadata fields for schema version, target id/family, artifact kind,
  source kind/module, portable IR version, capability ids, selector-facing ABI,
  `solc` path/version, Yul/bytecode/source artifact hashes and byte sizes, and
  validation status.
- Added `scripts/evm/validate-artifact-metadata.py` for machine validation of
  EVM metadata files.
- Updated EVM IR smoke scripts and `scripts/evm/build-examples.sh` so generated
  metadata is validated in CI.
- Updated EVM target docs, validation gates, backlog, portable IR docs, and
  Chinese docs.

Validation run:

```sh
lake build
PATH="$HOME/.foundry/bin:$PATH" lake env proof-forge --evm-bytecode --root . --module contract \
  --artifact-output build/evm/Counter.proof-forge-artifact.json \
  -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean
python3 scripts/evm/validate-artifact-metadata.py --root . \
  --expect-fixture Counter.lean \
  --expect-source-kind lean-sdk \
  build/evm/Counter.proof-forge-artifact.json
bash -n scripts/evm/*.sh
python3 -m py_compile scripts/evm/validate-artifact-metadata.py
scripts/evm/conditional-ir-smoke.sh
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- SDK EVM bytecode builds emit validated metadata with source, Yul, bytecode,
  method selectors, and `solc` validation status.
- Portable IR EVM bytecode builds emit validated metadata with fixture name,
  source module, `irVersion: portable-ir-v0`, capability ids, ABI selectors,
  Yul/bytecode hashes, and validation status.
- Each EVM IR smoke now writes a fixture-specific metadata file to avoid
  parallel-run overwrite races.
- `scripts/evm/build-examples.sh` validates metadata for every SDK example with
  a sibling `.evm-methods` file.

Known limitations:

- EVM metadata is still build metadata, not a full deploy manifest.
- `capabilities` are populated for portable IR fixtures; SDK builds currently
  record method metadata but not inferred SDK capability ids.

Next step:

- Add EVM context or hashing lowering as the next isolated capability slice, or
  turn metadata into a unified target manifest when more targets share the
  schema.

### EVM IR Conditionals

Commit: feature commit for EVM IR conditionals

Summary:

- Added `control.conditional` to the EVM target profile.
- Extended `ProofForge.Backend.Evm.IR` to lower portable IR `if/else` into Yul
  `switch condition case 0 { else } default { then }` blocks.
- Kept branch-local `return` statements explicitly rejected because EVM IR
  `return` currently assigns the generated function result and does not yet
  emit Yul `leave` for early return semantics.
- Added an EVM selector to `ConditionalProbe` while preserving Psy output.
- Added `--emit-conditional-ir-yul` and
  `--emit-conditional-ir-bytecode` CLI modes.
- Added `Examples/Evm/ConditionalProbe.golden.yul` and
  `scripts/evm/conditional-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics, coverage manifest, capability registry, validation
  docs, EVM target docs, and Chinese documentation.

Validation run:

```sh
lake build
lake env proof-forge --emit-conditional-ir-yul -o build/ir/ConditionalProbe.yul
diff -u Examples/Evm/ConditionalProbe.golden.yul build/ir/ConditionalProbe.yul
lake env proof-forge --emit-conditional-ir-psy -o build/psy/ConditionalProbe.psy
diff -u Examples/Psy/ConditionalProbe.golden.psy build/psy/ConditionalProbe.psy
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/conditional-ir-smoke.sh
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated ConditionalProbe Yul matches the checked-in golden fixture and
  contains Yul `switch` blocks for both then and else paths.
- Psy ConditionalProbe output remains unchanged after adding target-specific
  selector metadata.
- `scripts/evm/conditional-ir-smoke.sh` compiles ConditionalProbe to bytecode
  and passes Foundry tests for the expected conditional lifecycle result and
  unknown-selector revert behavior.
- EVM diagnostics now cover the remaining conditional boundary: branch-local
  return statements.

Known limitations:

- Conditional branch early returns are not supported until EVM IR return
  lowering grows Yul `leave`.
- The EVM IR backend still has minimal expression type validation.

Next step:

- Add EVM artifact metadata or scalar context/hash lowering as the next isolated
  feature slice.

### EVM IR Local Assignment

Commit: feature commit for EVM IR local assignment

Summary:

- Treated the capability-complete EVM backend prompt as an incremental
  validation contract: every portable IR node must either gain a positive EVM
  fixture or retain a documented diagnostic.
- Extended `ProofForge.Backend.Evm.IR` so mutable scalar local bindings lower
  to Yul `let` declarations.
- Extended EVM IR assignment lowering for local targets as Yul `:=`
  assignments, while keeping non-local assignment targets and compound
  assignment statements explicitly rejected.
- Added `ProofForge.IR.Examples.AssignmentProbe` with
  `reassignment(uint256)`, covering mutable `U64` and `Bool` locals plus a
  bool guard that depends on assignment.
- Added `--emit-assignment-ir-yul` and
  `--emit-assignment-ir-bytecode` CLI modes.
- Added `Examples/Evm/AssignmentProbe.golden.yul` and
  `scripts/evm/assignment-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics, coverage manifest, validation docs, and the EVM
  target docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-assignment-ir-yul -o build/ir/AssignmentProbe.yul
diff -u Examples/Evm/AssignmentProbe.golden.yul build/ir/AssignmentProbe.yul
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated AssignmentProbe Yul matches the checked-in golden fixture and
  contains `let total := seed`, `total := add(total, 7)`, and
  `matched := eq(total, 12)`.
- `scripts/evm/assignment-ir-smoke.sh` compiles AssignmentProbe to bytecode and
  passes Foundry tests for the successful assignment path and the bool-guard
  revert path.
- EVM diagnostics now cover the remaining assignment boundaries: non-local
  assignment targets and compound assignment statements.

Known limitations:

- Local assignment support is scalar-only (`U32`, `U64`, `Bool`).
- Compound assignment, aggregate assignment paths, storage assignment paths,
  and artifact metadata remain separate EVM work items.

Next step:

- Add EVM IR statement-level conditional lowering or EVM artifact metadata as
  the next isolated feature slice.

### EVM IR Assertions

Commit: feature commit for EVM IR assertions

Summary:

- Added `assertions.check` to the EVM target profile and capability registry.
- Extended `ProofForge.Backend.Evm.IR` to lower portable IR `assert` into
  `if iszero(condition) { revert(0, 0) }`.
- Extended EVM IR `assertEq` lowering into
  `if iszero(eq(lhs, rhs)) { revert(0, 0) }`.
- Added an EVM selector to `AssertProbe` while preserving Psy's selector-ignore
  behavior.
- Added `--emit-assert-ir-yul` and `--emit-assert-ir-bytecode` CLI modes.
- Added `Examples/Evm/AssertProbe.golden.yul` and
  `scripts/evm/assert-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics and coverage manifest to treat assertions as lowered
  instead of unsupported.

Validation run:

```sh
lake build
lake env proof-forge --emit-assert-ir-yul -o build/ir/AssertProbe.yul
diff -u Examples/Evm/AssertProbe.golden.yul build/ir/AssertProbe.yul
lake env proof-forge --emit-assert-ir-psy -o build/psy/AssertProbe.psy
diff -u Examples/Psy/AssertProbe.golden.psy build/psy/AssertProbe.psy
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated EVM AssertProbe Yul matches the checked-in golden fixture.
- Psy AssertProbe output remains unchanged after adding target-specific selector
  metadata.
- `scripts/evm/assert-ir-smoke.sh` compiles AssertProbe to bytecode and passes
  Foundry tests for both successful assertion execution and assertion-failure
  revert behavior.
- Existing EVM ABI scalar, IR Counter, SDK example build, and Foundry smoke
  gates still pass.

Known limitations:

- EVM assertions currently revert with empty revert data.
- Expression type validation is still minimal in the EVM IR backend.

Next step:

- Add EVM IR statement-level assignment or conditional lowering so larger
  portable IR fixtures can move from unsupported diagnostics to Foundry-backed
  positive coverage.

### EVM IR Scalar ABI Parameters

Commit: feature commit for EVM IR scalar ABI parameters

Summary:

- Added `ProofForge.IR.Examples.AbiScalarProbe` with `mix(uint256,uint32,bool)`
  and `same(uint256,uint256)` portable IR entrypoints.
- Extended `ProofForge.Backend.Evm.IR` so `U64`, `U32`, and `Bool` entrypoint
  parameters lower to Yul function parameters and dispatcher `calldataload`
  arguments.
- Added dispatcher ABI guards for short calldata, out-of-range `uint32`
  values, and invalid `bool` encodings.
- Added CLI modes:
  `--emit-abi-scalar-ir-yul` and `--emit-abi-scalar-ir-bytecode`.
- Added `Examples/Evm/AbiScalarProbe.golden.yul` and
  `scripts/evm/abi-scalar-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics to reject only non-scalar ABI parameter types instead
  of rejecting every parameterized entrypoint.

Validation run:

```sh
lake build
lake env proof-forge --emit-abi-scalar-ir-yul -o build/ir/AbiScalarProbe.yul
diff -u Examples/Evm/AbiScalarProbe.golden.yul build/ir/AbiScalarProbe.yul
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated Yul includes selector dispatch for `mix` and `same`, calldata size
  guards, `uint32` range validation, and `bool` encoding validation.
- `scripts/evm/abi-scalar-ir-smoke.sh` compiles the fixture to bytecode,
  verifies the golden Yul snapshot, and passes Foundry tests for valid calls
  and malformed calldata reverts.
- EVM diagnostic smoke passes after replacing the obsolete all-parameter
  rejection with Unit/Hash ABI parameter diagnostics.
- Existing EVM SDK examples still build and the Foundry smoke suite passes all
  four tests.

Known limitations:

- This only covers scalar word ABI parameters and one-word returns.
- Aggregate ABI values, dynamic data, events, and artifact metadata remain
  pending.

Next step:

- Add the next EVM IR positive fixture for either assertions/reverts or
  statement-level assignment before expanding storage layout.

### EVM IR Coverage And Diagnostics Baseline

Commit: feature commit for EVM IR coverage and diagnostics

Summary:

- Added `Tests/EvmCoverage.tsv`, tracking every portable IR constructor as
  `lowered`, `validated`, `unsupported`, or `structural` for the current EVM
  IR backend.
- Added `scripts/evm/check-ir-coverage-manifest.py` so new portable IR nodes
  must be classified for EVM before CI passes.
- Added `Tests/EvmDiagnostics.lean` and `scripts/evm/diagnostic-smoke.sh`,
  covering explicit diagnostics for missing selectors, unsupported ABI
  parameters, missing returns, unsupported aggregate/control/storage/context
  surfaces, events, crosscalls, native value, and Hash expressions.
- Fixed the EVM IR backend to reject non-Unit entrypoints that do not end with
  a return statement instead of emitting an unassigned `result`.
- Wired the new EVM diagnostic and coverage gates into CI.

Validation run:

```sh
lake build
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- `scripts/evm/diagnostic-smoke.sh` passes 25 diagnostic cases.
- `scripts/evm/check-ir-coverage-manifest.py` confirms 91 portable IR
  constructor entries match `ProofForge/IR/Contract.lean`.
- The EVM IR Counter smoke still compiles to bytecode and passes Foundry.
- The existing EVM SDK examples still build and the Foundry smoke suite passes
  all four tests.

Known limitations:

- This feature does not expand EVM lowering support; unsupported surfaces remain
  explicit until implemented with Yul golden, solc, and Foundry coverage.
- EVM artifact metadata is still pending.

Next step:

- Start replacing selected `unsupported` EVM coverage rows with Dapp-style
  Yul/Foundry-backed positive fixtures, one feature at a time.

### Psy Fixed Array Equality

Commit: feature commit for Psy fixed-array equality

Summary:

- Allowed Psy IR equality validation for fixed-array value types after a Dargo
  probe confirmed Psy supports `assert_eq(xs, ys)`, `xs == ys`, and `xs != zs`
  for fixed arrays.
- Extended `ArrayProbe` with `array_predicates`, covering fixed-array
  `assert_eq`, equality, and inequality over `[Felt; 3]` locals.
- Updated `scripts/psy/array-smoke.sh` to compile and execute
  `array_predicates`, record `result_vm: [1]`, and include it in artifact
  metadata validation.

Validation run:

```sh
lake build
lake env proof-forge --emit-array-ir-psy -o build/psy/ArrayProbe.psy
diff -u Examples/Psy/ArrayProbe.golden.psy build/psy/ArrayProbe.psy
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/array-smoke.sh
git diff --check
```

Result:

- Generated ArrayProbe source includes `array_predicates`, using
  `assert_eq(xs, ys, ...)`, `xs == ys`, and `xs != zs`.
- `scripts/psy/array-smoke.sh` validates `sum_literal`,
  `storage_lifecycle`, and `array_predicates` through Dargo test, compile,
  execute, ABI generation, deploy manifest, and artifact metadata checks.
- Dargo execution returns `result_vm: [1]` for `array_predicates`.

Known limitations:

- This feature covers same-typed fixed-array equality only; mismatched element
  types and lengths still fail through the existing type checker.

Next step:

- Commit and push this single feature before starting the next Psy surface area.

### Psy Native U32 Storage Struct Paths

Commit: feature commit for Psy native U32 storage struct paths

Summary:

- Fixed Psy `storagePathWrite` so U32 paths only cast to Felt for the validated
  Felt-backed U32 storage-array representation.
- Allowed native U32 storage struct field paths to use Psy's own `u32` storage
  reference idiom for path writes, reads, and compound assignment.
- Extended `StorageNestedAggregateProbe` with a native `Profile.rank: u32`
  storage field across scalar struct and storage-array paths.
- Removed the obsolete diagnostic that rejected non-array U32 storage-path
  compound assignment.

Validation run:

```sh
lake build
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/storage-nested-aggregate-smoke.sh
```

Result:

- Generated StorageNestedAggregateProbe source emits native `pub rank: u32`,
  native U32 path writes such as `c.person.profile.rank = 9u32`, and native
  U32 path compound assignment such as `c.person.profile.rank += 4u32`.
- `scripts/psy/diagnostic-smoke.sh` passes all 48 diagnostic cases after
  removing the obsolete unsupported U32 path case.
- `scripts/psy/storage-nested-aggregate-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [252]` for `storage_nested_lifecycle`.

Known limitations:

- Direct Psy `[u32; N]` contract storage arrays remain avoided because current
  `psyup` 0.1.0 rejects them with an `ArrayRef<u32, N>` mismatch.
- Map value compound assignment remains outside the supported storage-path
  surface.

Next step:

- Continue shrinking storage and ABI edge cases into Dargo-backed fixtures, one
  committed feature at a time.

### Psy U32 Storage Path Assignment

Commit: feature commit for Psy U32 storage path assignment

Summary:

- Extended Psy lowering for Felt-backed U32 storage arrays so
  `storagePathAssignOp` emits typed read/update/write code instead of raw Felt
  compound assignment.
- Covered all `AssignOp` variants in `U32StorageArrayProbe`: arithmetic,
  modulo, bitwise, and shifts.
- Kept non-array U32 storage-path compound assignment rejected with an explicit
  ProofForge diagnostic until that storage representation is validated.
- Updated the golden Psy source, Dargo smoke expected result, coverage matrix,
  and validation docs.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Generated U32StorageArrayProbe source rewrites U32 storage-path compound
  assignment as `.get() as u32`, typed operation, then `as Felt` writeback.
- `scripts/psy/diagnostic-smoke.sh` passes all 49 diagnostic cases, including
  the remaining unsupported non-array U32 storage-path assignment boundary.
- `scripts/psy/u32-storage-array-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [28]` for `storage_lifecycle`.

Known limitations:

- Direct Psy `[u32; N]` contract storage arrays remain avoided because current
  `psyup` 0.1.0 rejects them with an `ArrayRef<u32, N>` mismatch.
- U32 storage-path compound assignment is supported only for the validated
  Felt-backed storage-array representation, not arbitrary U32 struct paths.
  This struct-path limitation is superseded by the native U32 storage struct
  path entry above.

Next step:

- Continue closing one Psy storage or expression gap per feature branch, with
  Dargo-backed smoke coverage before each commit.

### Psy Hash Storage Coverage

Commit: feature commit for Psy Hash storage coverage

Summary:

- Added `HashStorageProbe` as a portable IR fixture for native Psy scalar
  `Hash` storage and `[Hash; N]` storage arrays.
- Extended Psy state validation so `StateDecl.kind = .scalar` with
  `type = .hash` lowers to `pub root: Hash`.
- Added CLI emission through `--emit-hash-storage-ir-psy` plus a checked
  golden source fixture.
- Added `scripts/psy/hash-storage-smoke.sh` to validate `dargo test`,
  `dargo compile`, two `dargo execute` entrypoints, `dargo generate-abi`,
  deploy manifest generation, and artifact metadata validation.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-hash-storage-ir-psy -o build/psy/HashStorageProbe.psy
diff -u Examples/Psy/HashStorageProbe.golden.psy build/psy/HashStorageProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/hash-storage-smoke.sh
git diff --check
```

Result:

- Generated HashStorageProbe source lowers `pub root: Hash`,
  `pub roots: [Hash; 2]`, scalar Hash read/write, indexed Hash array read/write,
  and generic storage-path read/write.
- Dargo execution validates `result_vm: [5, 6, 7, 8]` for scalar storage and
  `result_vm: [55, 66, 77, 88]` for storage-array access.

Known limitations:

- This does not change U32 storage arrays, which remain Felt-backed because
  Dargo v0.1.0 rejects direct `[u32; N]` contract storage arrays.

Next step:

- Continue replacing explicit unsupported storage diagnostics with
  Dargo-validated Psy storage idioms where the upstream toolchain accepts the
  shape.

### Psy Bool Storage Array Coverage

Commit: feature commit for Psy Bool storage array coverage

Summary:

- Added `BoolStorageArrayProbe` as a portable IR fixture for native Psy
  `[bool; N]` fixed arrays and `bool` storage arrays.
- Extended Psy state validation so `StateDecl.kind = .array N` with
  `type = .bool` lowers to `pub flags: [bool; N]`.
- Added CLI emission through `--emit-bool-storage-array-ir-psy` plus a checked
  golden source fixture.
- Replaced the previous unsupported bool storage-array diagnostic with an
  unsupported Unit storage-array diagnostic.
- Added `scripts/psy/bool-storage-array-smoke.sh` to validate `dargo test`,
  `dargo compile`, two `dargo execute` entrypoints, `dargo generate-abi`,
  deploy manifest generation, and artifact metadata validation.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-bool-storage-array-ir-psy -o build/psy/BoolStorageArrayProbe.psy
diff -u Examples/Psy/BoolStorageArrayProbe.golden.psy build/psy/BoolStorageArrayProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bool-storage-array-smoke.sh
git diff --check
```

Result:

- Generated BoolStorageArrayProbe source lowers local `[bool; 3]` arrays,
  `pub flags: [bool; 3]` storage arrays, indexed storage read/write, generic
  storage-path read/write, and `bool as Felt` return casts.
- Dargo execution validates `result_vm: [2]` for both `local_flags_sum` and
  `storage_lifecycle`.

Known limitations:

- This does not change the existing U32 storage-array representation; U32
  arrays remain Felt-backed because Dargo v0.1.0 rejects direct `[u32; N]`
  contract storage arrays.

Next step:

- Continue shrinking explicit unsupported diagnostics into Dargo-validated Psy
  support where the upstream toolchain accepts the target shape.

### Psy Bool Scalar Storage Coverage

Commit: feature commit for Psy Bool scalar storage coverage

Summary:

- Added `BoolStorageScalarProbe` as a portable IR fixture for native Psy
  `bool` scalar storage.
- Added CLI emission through `--emit-bool-storage-scalar-ir-psy` plus a
  checked golden source fixture.
- Added `scripts/psy/bool-storage-scalar-smoke.sh` to validate `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  generation, and artifact metadata validation.
- Extended Psy coverage evidence, validation docs, and CI golden checks.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-bool-storage-scalar-ir-psy -o build/psy/BoolStorageScalarProbe.psy
diff -u Examples/Psy/BoolStorageScalarProbe.golden.psy build/psy/BoolStorageScalarProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bool-storage-scalar-smoke.sh
git diff --check
```

Result:

- Generated BoolStorageScalarProbe source lowers scalar storage to
  `pub flag: bool`, native Bool reads/writes, and `bool as Felt` return casts.
- Dargo execution validates `result_vm: [1]`.

Known limitations:

- This entry covered native scalar `bool` storage only. The later
  BoolStorageArrayProbe entry supersedes the previous bool storage-array
  limitation.

Next step:

- Continue filling the Psy scalar/aggregate storage matrix one feature at a
  time, with Dargo execution backing each newly enabled shape.

### Psy Map Set Expression Return Coverage

Commit: feature commit for Psy map set expression returns

Summary:

- Added Psy lowering and type validation for `storageMapSet` when used as an
  expression, matching upstream `MapRef::set` returning the previous `Hash`.
- Extended `MapProbe` with `set_return_lifecycle` and
  `insert_return_lifecycle` to cover absent-key zero returns, previous-value
  returns, and latest-value reads.
- Updated the MapProbe generated test to bind side-effectful method results
  before assertion, avoiding Dargo repeated-evaluation behavior for direct
  calls inside `assert_eq`.
- Extended the MapProbe smoke to execute the new methods and validate artifact
  metadata against all returned results.

Validation run:

```sh
lake build
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
diff -u Examples/Psy/MapProbe.golden.psy build/psy/MapProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/map-smoke.sh
```

Result:

- `set_return_lifecycle` returns `result_vm: [31, 32, 33, 34]`.
- `insert_return_lifecycle` returns `result_vm: [5, 6, 7, 8]`.

Known limitations:

- Psy map support remains deliberately limited to `Map<Hash, Hash, N>` until
  non-Hash map value semantics are modeled explicitly in the portable IR.

Next step:

- Continue converting upstream Psy map/storage semantics into fixture-backed
  ProofForge IR coverage.

### Psy Generic Test Fallback

Commit: feature commit for generic Psy fallback tests

Summary:

- Replaced the Psy backend's fixture-only test generation failure with a
  generic fallback test that instantiates `<Module>Ref`.
- Added `GenericEntrypointProbe` as a valid non-whitelisted portable IR fixture
  to prove that arbitrary supported modules can render `.psy` source.
- Added a Dargo-backed smoke script, golden source, CI golden check, deploy
  manifest generation, and artifact metadata validation for the new fixture.
- Added an explicit empty-state diagnostic because Dargo v0.1.0 rejects empty
  `#[derive(Storage)]` contracts.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-generic-entrypoint-ir-psy -o build/psy/GenericEntrypointProbe.psy
diff -u Examples/Psy/GenericEntrypointProbe.golden.psy build/psy/GenericEntrypointProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/generic-entrypoint-smoke.sh
git diff --check
```

Result:

- Dargo accepts the generic generated test and executes
  `GenericEntrypointProbe.answer` with `result_vm: [42]`.
- Psy diagnostic smoke now covers 49 malformed or unsupported IR cases.

Known limitations:

- The generic fallback only proves source/package validity and ref
  instantiation. Fixture-specific behavior still needs dedicated assertions
  and smoke scripts when a feature has semantic expectations.

Next step:

- Continue closing expression and storage coverage gaps with one fixture-backed
  feature at a time.

### Psy Identifier Diagnostics

Commit: feature commit for Psy identifier validation

Summary:

- Added Psy backend validation for module, struct, field, state, entrypoint,
  parameter, local, and loop-index identifiers before source generation.
- Added duplicate declaration checks for struct names, state ids, entrypoint
  names, struct field ids, and entrypoint parameter names.
- Added diagnostic fixtures for invalid module identifiers, duplicate state
  ids, duplicate entrypoint names, and reserved local names.

Validation run:

```sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake build
git diff --check
```

Result:

- Psy diagnostic smoke now covers 48 malformed or unsupported IR cases.
- Invalid or ambiguous names fail in ProofForge before Dargo parsing or
  typechecking.

Known limitations:

- The reserved-word list covers Psy keywords and builtin names used by current
  generated source. If Psy adds new reserved identifiers upstream, this list
  should be updated with the toolchain bump.

Next step:

- Continue reducing Dargo-discovered failures into ProofForge diagnostics.

### Psy U32 Scalar Storage Coverage

Commit: feature commit for Psy U32 scalar storage coverage

Summary:

- Added `U32StorageScalarProbe` as a portable IR fixture for native Psy
  `u32` scalar storage.
- Added CLI emission through `--emit-u32-storage-scalar-ir-psy` plus a checked
  golden source fixture.
- Added `scripts/psy/u32-storage-scalar-smoke.sh` to validate `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  generation, and artifact metadata validation.
- Extended Psy coverage evidence, validation docs, and CI golden checks.

Validation run:

```sh
DARGO_STD_PATH=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/lib/psy-std/std.psy \
  /tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  test --file /tmp/proof_forge_probe/u32_scalar_storage.psy
lake build
bash -n scripts/psy/*.sh
lake env proof-forge --emit-u32-storage-scalar-ir-psy -o build/psy/U32StorageScalarProbe.psy
diff -u Examples/Psy/U32StorageScalarProbe.golden.psy build/psy/U32StorageScalarProbe.psy
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-scalar-smoke.sh
git diff --check
```

Result:

- Generated U32StorageScalarProbe source lowers scalar storage to
  `pub value: u32`, native U32 reads/writes, and scalar `+=`.
- Dargo execution validates `result_vm: [12]`.

Known limitations:

- This covers native scalar `u32` storage only. U32 storage arrays still use the
  existing Felt-backed representation because current `psyup` 0.1.0 rejects
  direct `[u32; N]` contract storage arrays.

Next step:

- Continue broadening Psy storage and ABI validation while keeping unsupported
  storage forms explicit.

### Psy Entrypoint Selector Diagnostic

Commit: feature commit for Psy selector rejection

Summary:

- Added a Psy backend validation rule that rejects `Entrypoint.selector?`
  before source generation.
- Documented that Psy/DPN entrypoints are addressed by contract method name via
  Dargo and the generated Psy ABI, so EVM-style selectors are target-invalid
  rather than ignored.
- Added a `Tests/PsyDiagnostics.lean` case to lock the diagnostic text.

Validation run:

```sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake build
git diff --check
```

Result:

- Malformed Psy IR modules with entrypoint selectors now fail with an explicit
  diagnostic instead of silently dropping selector metadata.

Known limitations:

- This does not add a Psy-native selector concept. If Psy later exposes stable
  selector metadata, the backend should model it separately from EVM selectors.

Next step:

- Continue expanding non-fixture-specific Psy package generation and deployment
  validation.

### Psy Shared Dargo Package Writer

Commit: feature commit for shared Psy Dargo package generation

Summary:

- Added `scripts/psy/write-dargo-package.py` as the shared package writer for
  Dargo-backed Psy smoke fixtures.
- Replaced repeated shell `rm`/`mkdir`/`cp`/`Dargo.toml` heredocs across all
  Dargo-backed smoke scripts with a single writer invocation.
- Kept a smoke-directory guard in the writer so it only rewrites `dargo-*`
  package directories.

Validation run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  scripts/psy/write-dargo-package.py \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py \
  scripts/psy/check-ir-coverage-manifest.py
bash -n scripts/psy/*.sh
scripts/psy/check-ir-coverage-manifest.py
lake build
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Both representative Dargo smokes generate packages through the shared writer,
  then pass `dargo test`, `dargo compile`, `dargo execute`, `dargo generate-abi`,
  deploy-manifest validation, and artifact metadata validation.
- Existing metadata source/package-source parity and `Dargo.toml` manifest
  validation continue to pass.

Known limitations:

- This factors local Dargo package creation only; upstream compressed genesis
  deploy JSON and live node/prover smoke remain separate deployment work.

Next step:

- Continue toward upstream genesis deploy JSON/local node research.

### Psy Dargo Package Source Metadata

Commit: feature commit for Psy Dargo package source metadata

Summary:

- Extended Psy artifact metadata to record the Dargo package source copy
  (`src/main.psy`) used by every Dargo-backed smoke fixture.
- Updated metadata validation to check the package source path, byte size,
  SHA-256 hash, and hash parity with the generated `.psy` source.
- Updated all Dargo-backed Psy smoke scripts to pass
  `"$PROJECT_DIR/src/main.psy"` into `write-artifact-metadata.py`.

Validation run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py \
  scripts/psy/check-ir-coverage-manifest.py
bash -n scripts/psy/*.sh
lake build
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Counter and U32StorageArrayProbe smoke metadata now include
  `artifacts.packageSource`.
- The metadata validator accepts the updated schema and proves the package
  source copy has the same SHA-256 hash as the generated source file.

Known limitations:

- This validates the generated Dargo package source copy, not upstream
  compressed genesis deploy JSON or live node/prover state.

Next step:

- Continue toward upstream genesis deploy JSON/local node research, or factor
  the repeated Dargo package generation into a reusable package writer.

### Psy Dargo Package Manifest Metadata

Commit: feature commit for Psy Dargo package manifest metadata

Summary:

- Extended Psy artifact metadata to record the generated Dargo package manifest
  (`Dargo.toml`) for every Dargo-backed smoke fixture.
- Updated metadata validation to check the manifest path, byte size, SHA-256
  hash, `[package]` section, `type = "bin"`, and `[dependencies]` section.
- Updated all Dargo-backed Psy smoke scripts to pass the generated
  `"$PROJECT_DIR/Dargo.toml"` into `write-artifact-metadata.py`.

Validation run:

```sh
python3 -m py_compile \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py
bash -n scripts/psy/*.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
```

Result:

- Counter smoke metadata now includes `artifacts.dargoManifest` with a checked
  hash and package manifest shape.
- The metadata validator accepts the updated schema after Dargo `test`,
  `compile`, `execute`, `generate-abi`, deploy manifest validation, and package
  manifest validation.

Known limitations:

- This records the generated Dargo package manifest, not Psy upstream compressed
  genesis deploy JSON or live node/prover state.

Next step:

- Continue toward upstream genesis deploy JSON/local node research, or factor
  the repeated Dargo package generation into a reusable package writer.

### Psy IR Coverage Manifest Gate

Commit: feature commit for Psy IR coverage manifest validation

Summary:

- Added `Tests/PsyCoverage.tsv` as a constructor-level coverage manifest for
  the portable IR surface used by the Psy backend.
- Added `scripts/psy/check-ir-coverage-manifest.py`, which parses
  `ProofForge/IR/Contract.lean` and fails if any tracked constructor is missing
  from the manifest or if the manifest contains stale/duplicate entries.
- Added CI and validation docs for the new gate so future IR expansion must
  classify each constructor as lowered, validated, unsupported, or structural.

Validation run:

```sh
python3 -m py_compile scripts/psy/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
```

Result:

- The checker reports 88 constructor entries matching
  `ProofForge/IR/Contract.lean`.

Known limitations:

- The manifest is a structural guard, not behavioral proof. Supported rows still
  require fixture, golden, Dargo, and metadata validation when they describe
  runtime behavior.

Next step:

- Continue closing behavioral Psy gaps and use the manifest as a tripwire when
  extending the portable IR.

### Psy U32 Storage Array Lowering

Commit: feature commit for Psy U32 storage array coverage

Summary:

- Added `U32StorageArrayProbe` as a dedicated portable IR fixture for U32
  storage-array reads and writes.
- Extended Psy sourcegen so portable U32 storage arrays lower to Felt-backed
  Psy storage arrays. Writes use `u32 as Felt`; reads use `.get() as u32`.
- Reused the same representation for generic storage-path read/write effects
  over U32 array elements.
- Kept U32 storage-path compound assignment explicitly rejected, because direct
  Felt storage `+=` would not preserve a clear U32 storage arithmetic boundary.
- Added CLI, golden source, CI golden coverage, diagnostic coverage, Dargo
  smoke coverage, and validation docs for the new fixture.

Validation run:

```sh
lake build
lake env proof-forge --emit-u32-storage-array-ir-psy -o build/psy/U32StorageArrayProbe.psy
diff -u Examples/Psy/U32StorageArrayProbe.golden.psy build/psy/U32StorageArrayProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Generated U32StorageArrayProbe source matches the checked-in golden fixture.
- `scripts/psy/diagnostic-smoke.sh` passes all 43 diagnostic cases.
- `scripts/psy/u32-storage-array-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [48]` for `storage_lifecycle`.

Known limitations:

- Direct Psy `[u32; N]` contract storage arrays remain avoided because current
  `psyup` 0.1.0 rejects them with an `ArrayRef<u32, N>` mismatch.
- U32 storage-path compound assignment is still unsupported; use explicit
  read/update/write.

Next step:

- Move the Psy deployment track toward upstream compressed genesis deploy JSON
  and local node/prover smoke work, or continue broadening Lean-to-IR extraction
  into the now-supported Psy surface.

### Psy Storage Compound Assignment Effects

Commit: feature commit for Psy storage-reference compound assignment effects

Summary:

- Added portable IR storage effects for scalar storage compound assignment and
  generic storage-path compound assignment.
- Extended Psy sourcegen to lower storage refs such as `c.total += 3`,
  `c.person.profile.age += 2`, and `c.people[1].score -= 9` to native Psy
  assignment operators.
- Kept EVM IR v0 behavior explicit by rejecting the new storage compound
  effects with target-specific diagnostics.
- Extended `StorageNestedAggregateProbe` to validate scalar storage compound
  assignment, nested scalar storage paths, and storage-array scalar paths under
  Dargo execution.
- Added Psy diagnostics for storage compound effects used as expressions and
  malformed storage compound assignment value types.

Validation run:

```sh
lake build
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/storage-nested-aggregate-smoke.sh
```

Result:

- Generated StorageNestedAggregateProbe source matches the checked-in golden
  fixture.
- `scripts/psy/diagnostic-smoke.sh` passes all 42 diagnostic cases.
- `scripts/psy/storage-nested-aggregate-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [229]` for `storage_nested_lifecycle`.

Known limitations:

- Map storage values remain excluded from compound assignment because the
  current supported map shape uses `get`/`set` over `Map<Hash, Hash, N>`.
- U32 storage arrays remain explicitly rejected until a stable Dargo-compatible
  storage idiom is identified.

Next step:

- Continue with U32 storage-array research or move toward upstream genesis
  deploy JSON/local node smoke work.

### Psy Compound Assignment Lowering

Commit: feature commit for Psy compound assignment lowering

Summary:

- Added first-class `AssignOp` and `Statement.assignOp` nodes to the portable
  IR for `+=`, `-=`, `*=`, `/=`, `%=`, `|=`, `&=`, `^=`, `<<=`, and `>>=`.
- Lowered compound assignments to native Psy assignment operators for mutable
  local, array-index, and field-path assignment targets.
- Kept EVM IR v0 explicit by rejecting compound assignment statements with a
  dedicated diagnostic.
- Extended `U32ArithmeticProbe` with arithmetic compound assignment coverage
  and `BitwiseProbe` with Felt/U32 bitwise and shift compound assignment
  coverage.
- Added Psy diagnostics for malformed compound assignment value types and
  immutable compound assignment targets.

Validation run:

```sh
lake build
lake env proof-forge --emit-u32-arithmetic-ir-psy -o build/psy/U32ArithmeticProbe.psy
diff -u Examples/Psy/U32ArithmeticProbe.golden.psy build/psy/U32ArithmeticProbe.psy
lake env proof-forge --emit-bitwise-ir-psy -o build/psy/BitwiseProbe.psy
diff -u Examples/Psy/BitwiseProbe.golden.psy build/psy/BitwiseProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-arithmetic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bitwise-smoke.sh
```

Result:

- Generated U32ArithmeticProbe and BitwiseProbe sources match the checked-in
  golden fixtures.
- `scripts/psy/diagnostic-smoke.sh` passes all 39 diagnostic cases.
- Dargo validates the updated U32ArithmeticProbe and BitwiseProbe sources with
  `test`, `compile`, `execute`, `generate-abi`, deploy manifest validation, and
  artifact metadata validation.

Known limitations:

- Compound assignment currently targets mutable local/aggregate assignment
  paths. Storage-reference compound assignment remains a separate design item
  because portable storage writes are modeled as effects.
- U32 storage arrays remain explicitly rejected until a stable Dargo-compatible
  storage idiom is identified.

Next step:

- Continue with U32 storage-array research or add storage-reference compound
  assignment effects if that becomes the next Psy surface to close.

### Psy Map Storage Path Lowering

Commit: feature commit for Psy map storage path coverage

Summary:

- Added `StoragePathSegment.mapKey` to the portable IR so generic storage path
  effects can target supported `Map<Hash, Hash, N>` state.
- Extended Psy storage path type resolution, validation, and source lowering so
  `storagePathRead "balances" #[.mapKey key]` lowers to `c.balances.get(key)`
  and `storagePathWrite "balances" #[.mapKey key] value` lowers to
  `c.balances.set(key, value)`.
- Added map path key validation and explicit diagnostics for malformed map
  paths or wrong key types.
- Extended `MapProbe` with `path_lifecycle`, updated its golden `.psy`, and
  updated `scripts/psy/map-smoke.sh` to execute both direct map effects and the
  generic map storage path entrypoint.

Validation run:

```sh
lake build
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
diff -u Examples/Psy/MapProbe.golden.psy build/psy/MapProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/map-smoke.sh
```

Result:

- Generated MapProbe source matches the checked-in golden fixture.
- `scripts/psy/diagnostic-smoke.sh` passes all 37 diagnostic cases.
- `scripts/psy/map-smoke.sh` passes `dargo test`, `dargo compile`,
  `dargo execute`, `dargo generate-abi`, deploy manifest validation, and
  artifact metadata validation.
- Dargo execution returns `result_vm: [55, 66, 77, 88]` for `map_lifecycle`
  and `result_vm: [77, 88, 99, 111]` for `path_lifecycle`.

Known limitations:

- Map storage paths currently support direct `Map<Hash, Hash, N>` key access.
  Nested map value traversal remains unsupported because Psy IR v0 only accepts
  Hash map values.
- U32 storage arrays remain explicitly rejected until a stable Dargo-compatible
  storage idiom is identified.

Next step:

- Continue with U32 storage-array research or decide whether compound
  assignment should become IR sugar.

### Psy Deploy Manifests For All Dargo Smokes

Commit: feature commit for broad Psy deploy manifest coverage

Summary:

- Added `scripts/psy/write-smoke-deploy-manifest.sh` as the shared smoke helper
  for deploy manifest generation and validation.
- Updated every Dargo-backed Psy smoke script to write
  `target/proof-forge-deploy.json`, validate it, and record it as `deployJson`
  inside `target/proof-forge-artifact.json`.
- Restored each smoke's deploy-oriented `dargo compile` artifact after
  `dargo execute` and `dargo generate-abi`, so deploy manifests describe the
  compile method set rather than an execution trace.
- Kept `scripts/psy/diagnostic-smoke.sh` separate because it validates
  pre-codegen diagnostics and does not produce Dargo artifacts.
- Updated validation docs, target notes, and backlog so the remaining deployment
  gap is specifically upstream compressed genesis deploy JSON plus local
  node/prover execution.

Validation run:

```sh
python3 -m py_compile \
  scripts/psy/write-deploy-manifest.py \
  scripts/psy/validate-deploy-manifest.py \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py
git diff --check
lake build
export PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy
export DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo
for script in scripts/psy/*-smoke.sh; do
  case "$script" in
    scripts/psy/diagnostic-smoke.sh) ;;
    *) "$script" ;;
  esac
done
scripts/psy/diagnostic-smoke.sh
```

Result:

- All Dargo-backed Psy smokes generated DPN circuit JSON, ABI JSON, execute
  logs, `proof-forge-deploy.json`, and `proof-forge-artifact.json`.
- Artifact metadata validation now checks deploy-manifest file hashes whenever
  `deployJson` is present.
- Deploy manifests record the restored compile method set for each fixture.
- `scripts/psy/diagnostic-smoke.sh` still passes all 35 diagnostic cases.

Known limitations:

- `proof-forge-deploy.json` remains ProofForge-owned metadata, not the upstream
  compressed genesis deploy JSON consumed by Psy node setup.
- The local node/prover deployment smoke is still not implemented.

Next step:

- Research whether to vendor or wrap Psy's `gen_deploy_json` path, then add the
  smallest local node/prover smoke that consumes the resulting deployment
  package.

### Psy Counter Deploy Manifest Metadata

Commit: feature commit for Psy Counter deploy manifest coverage

Summary:

- Added `scripts/psy/write-deploy-manifest.py` to produce
  `proof-forge-deploy.json` from the Counter `.psy` source, Dargo circuit JSON,
  and Dargo ABI JSON.
- Added `scripts/psy/validate-deploy-manifest.py` to verify manifest schema,
  deployer format, state-tree height, source/circuit/ABI hashes, function
  whitelist ordering, and upstream genesis JSON status.
- Updated `scripts/psy/counter-smoke.sh` so the Counter Dargo smoke now writes
  and validates `target/proof-forge-deploy.json`.
- Re-runs `dargo compile` after `dargo execute` so deploy metadata points at
  the deploy-oriented compile artifact rather than the method-sequence
  execution trace.
- Extended Psy artifact metadata to optionally record `deployJson` and require
  `validation.deployManifest = "passed"` whenever that artifact is present.
- Documented that this is a ProofForge deploy manifest, not Psy's upstream
  compressed genesis deploy JSON from `gen_deploy_json`.

Validation run:

```sh
python3 -m py_compile \
  scripts/psy/write-deploy-manifest.py \
  scripts/psy/validate-deploy-manifest.py \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py
git diff --check
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
```

Result:

- Counter generated source still matches `Examples/Psy/Counter.golden.psy`.
- Dargo `test`, `compile`, `execute`, and `generate-abi` passed.
- `dargo execute` returned `result_vm: [2]` after initialize plus two
  increments.
- `proof-forge-deploy.json` and `proof-forge-artifact.json` were generated and
  validated.

Known limitations:

- The manifest is ProofForge-owned metadata, not the upstream compressed
  genesis deploy JSON consumed by Psy node setup.
- The upstream `psy-dargo-cli/examples/gen_deploy_json.rs` path still requires
  Rust workspace internals; current released `dargo` does not expose it as a
  subcommand.
- Only the Counter smoke emits deploy manifest metadata so far.

Next step:

- Either extend deploy manifest generation to the broader Psy fixture set, or
  research the smallest stable upstream boundary for genesis deploy JSON plus a
  local Psy node/prover smoke.

### Psy U32HashPackingProbe Dynamic Hash Construction

Commit: feature commit for Psy U32 hash packing coverage

Summary:

- Added portable IR `Expr.hashValue` for dynamic `Hash` construction from four
  Felt-backed limbs.
- Extended Psy type validation so each dynamic Hash part must be `U64`/Felt and
  malformed Hash construction fails before `.psy` generation.
- Kept EVM IR v0 explicit by rejecting dynamic Hash value construction with a
  clear diagnostic.
- Added `ProofForge.IR.Examples.U32HashPackingProbe`, aligned with the
  `[u32; 8]` limb packing idioms in the deposit-tree and mining-rewards
  precompiles.
- Covered both local `[u32; 8]` literals and U32 ABI parameters packed into Psy
  `Hash` values through `lo + hi * 2^32`.
- Added an explicit rejection diagnostic for U32 storage arrays after Dargo
  validation showed current `psyup` 0.1.0 rejects direct `[u32; N]` contract
  storage arrays with an `ArrayRef<u32, N>` type mismatch.
- Added CLI support:

```sh
lake env proof-forge --emit-u32-hash-packing-ir-psy -o build/psy/U32HashPackingProbe.psy
```

- Added `Examples/Psy/U32HashPackingProbe.golden.psy`.
- Added `scripts/psy/u32-hash-packing-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, two
  `dargo execute` checks, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the U32HashPackingProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-u32-hash-packing-ir-psy -o build/psy/U32HashPackingProbe.psy
diff -u Examples/Psy/U32HashPackingProbe.golden.psy build/psy/U32HashPackingProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-hash-packing-smoke.sh
```

Result:

- Generated U32HashPackingProbe source matches the checked-in golden fixture.
- `scripts/psy/u32-hash-packing-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned the expected four-Felt Hash values for both
  `pack_literal` and `pack_params`.
- `scripts/psy/diagnostic-smoke.sh` passed all 35 diagnostic cases.

Known limitations:

- This adds Hash value construction and U32 limb packing, not Psy deploy JSON
  or live node/prover execution.
- U32 storage arrays are explicitly rejected until a stable Psy storage idiom is
  validated against Dargo.
- Compound assignment operators remain represented as explicit assignment plus
  expression nodes.
- Map storage paths remain rejected until a stable Psy idiom is identified.

Next step:

- Decide whether to add compound assignment as IR sugar or leave it to a future
  source normalizer, then continue with map storage paths or deploy JSON.

### Psy BitwiseProbe Native Bitwise Expressions

Commit: feature commit for Psy bitwise expression coverage

Summary:

- Added portable IR expression nodes for `&`, `|`, `^`, `<<`, and `>>`.
- Extended Psy source generation for Felt-backed `U64` and `U32` bitwise
  expressions, with same-width numeric validation before `.psy` generation.
- Added EVM IR lowering for the same pure bitwise/shift nodes through Yul
  `and`, `or`, `xor`, `shl`, and `shr` builtins.
- Added explicit diagnostics for malformed bitwise and shift operands.
- Added `ProofForge.IR.Examples.BitwiseProbe`, aligned with upstream
  `psy-compiler/tests/opcode_test.psy`,
  `tests/storage_u32_assign_ops_test.psy`, and precompile Merkle path idioms.
- Added CLI support:

```sh
lake env proof-forge --emit-bitwise-ir-psy -o build/psy/BitwiseProbe.psy
```

- Added `Examples/Psy/BitwiseProbe.golden.psy`.
- Added `scripts/psy/bitwise-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the BitwiseProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-bitwise-ir-psy -o build/psy/BitwiseProbe.psy
diff -u Examples/Psy/BitwiseProbe.golden.psy build/psy/BitwiseProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bitwise-smoke.sh
```

Result:

- Generated BitwiseProbe source matches the checked-in golden fixture.
- `scripts/psy/bitwise-smoke.sh` generated DPN JSON, ABI JSON, execute log,
  and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [16]` for `bitwise_mix`.
- `scripts/psy/diagnostic-smoke.sh` passed all 33 diagnostic cases.

Known limitations:

- Compound assignment operators such as `|=`, `&=`, `^=`, `<<=`, and `>>=`
  are still represented as explicit assignment plus expression nodes.
- This does not yet add u32 storage arithmetic probes or map storage paths.

Next step:

- Add storage-heavy U32/Hash limb packing probes from the deposit-tree and
  mining-rewards precompiles, then decide whether compound assignment sugar
  belongs in the portable IR or only in sourcegen normalization.

### Psy U32ArithmeticProbe Native U32 Arithmetic

Commit: feature commit for Psy U32 arithmetic coverage

Summary:

- Added portable IR `ValueType.u32` and `Literal.u32`.
- Added portable IR expression nodes for division, modulo, exponentiation, and
  explicit casts.
- Extended Psy source generation for `u32`, `Nu32` literals, `/`, `%`, `**`,
  and casts such as `z as bool` and `bb as Felt`.
- Updated bounded-loop typing so generated `for i in 0u32..Nu32` loop indices
  are tracked as `U32`.
- Extended numeric type validation so `U32` arithmetic remains type-consistent
  and malformed mixed-width arithmetic fails before source generation.
- Added EVM IR lowering for the new pure arithmetic/cast nodes through Yul
  builtins or no-op casts.
- Added `ProofForge.IR.Examples.U32ArithmeticProbe`, mirroring the core
  executable shape of upstream `psy-compiler/tests/u32_test.psy`.
- Added CLI support:

```sh
lake env proof-forge --emit-u32-arithmetic-ir-psy -o build/psy/U32ArithmeticProbe.psy
```

- Added `Examples/Psy/U32ArithmeticProbe.golden.psy`.
- Added `scripts/psy/u32-arithmetic-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, `dargo execute
  --parameters 2,3`, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the U32ArithmeticProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-u32-arithmetic-ir-psy -o build/psy/U32ArithmeticProbe.psy
diff -u Examples/Psy/U32ArithmeticProbe.golden.psy build/psy/U32ArithmeticProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-arithmetic-smoke.sh
```

Result:

- Generated U32ArithmeticProbe source matches the checked-in golden fixture.
- `scripts/psy/u32-arithmetic-smoke.sh` generated DPN JSON, ABI JSON, execute
  log, and `proof-forge-artifact.json`.
- `dargo execute --parameters 2,3` returned `result_vm: [1]` for
  `u32_arithmetic`.
- `scripts/psy/diagnostic-smoke.sh` passed all 31 diagnostic cases.

Known limitations:

- This does not yet add bitwise shifts, bitwise and/or, u32 storage probes, or
  the full cast matrix used by the token/deposit-tree precompiles.
- Cast lowering is intentionally explicit and rejects unsupported source/target
  pairs before `.psy` source generation.

Next step:

- Add bitwise operations and u32 array/hash-packing probes, since the Psy
  precompiles use `u32` limbs heavily for token addresses and tree roots.

### Psy ArithmeticProbe Sub/Mul Expressions

Commit: feature commit for Psy arithmetic expression coverage

Summary:

- Added portable IR expression nodes for subtraction and multiplication.
- Added Psy source generation for `-` and `*`, including parentheses around
  nested arithmetic operands where precedence would otherwise change meaning.
- Added sourcegen diagnostics for malformed subtraction and multiplication
  operand types.
- Added EVM IR lowering for the same pure arithmetic nodes through Yul builtins.
- Added `ProofForge.IR.Examples.ArithmeticProbe`, covering subtraction,
  multiplication, and nested arithmetic precedence.
- Added CLI support:

```sh
lake env proof-forge --emit-arithmetic-ir-psy -o build/psy/ArithmeticProbe.psy
```

- Added `Examples/Psy/ArithmeticProbe.golden.psy`.
- Added `scripts/psy/arithmetic-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the ArithmeticProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-arithmetic-ir-psy -o build/psy/ArithmeticProbe.psy
diff -u Examples/Psy/ArithmeticProbe.golden.psy build/psy/ArithmeticProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/arithmetic-smoke.sh
```

Result:

- Generated ArithmeticProbe source matches the checked-in golden fixture.
- `scripts/psy/arithmetic-smoke.sh` generated DPN JSON, ABI JSON, execute log,
  and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [60]` for `arithmetic_mix`.
- `scripts/psy/diagnostic-smoke.sh` passed all 29 diagnostic cases.

Known limitations:

- This adds subtraction and multiplication, not division, modulo,
  exponentiation, cast-heavy `u32` arithmetic, or compound assignment operators.
- The IR still represents these values as `U64` mapped to Psy `Felt`; a
  dedicated `U32` surface should be added before copying upstream `u32_test`
  semantics directly.

Next step:

- Add division/modulo only after deciding whether they belong to Felt-backed
  `U64`, a new `U32` value type, or target-specific checked arithmetic helpers.

### Psy ConditionalProbe Statement If/Else

Commit: feature commit for Psy conditional statement coverage

Summary:

- Added portable IR `Statement.ifElse` with a new `control.conditional`
  capability.
- Added Psy source generation for `if condition { ... } else { ... };`, aligned
  with upstream `.psy` conditional syntax.
- Added sourcegen diagnostics for non-Bool if conditions and branch-local
  bindings escaping their branch.
- Kept EVM IR v0 explicit by rejecting statement-level if/else.
- Added `ProofForge.IR.Examples.ConditionalProbe`, covering then and else branch
  execution over scalar storage.
- Added CLI support:

```sh
lake env proof-forge --emit-conditional-ir-psy -o build/psy/ConditionalProbe.psy
```

- Added `Examples/Psy/ConditionalProbe.golden.psy`.
- Added `scripts/psy/conditional-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the ConditionalProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-conditional-ir-psy -o build/psy/ConditionalProbe.psy
diff -u Examples/Psy/ConditionalProbe.golden.psy build/psy/ConditionalProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/conditional-smoke.sh
```

Result:

- Generated ConditionalProbe source matches the checked-in golden fixture.
- `scripts/psy/conditional-smoke.sh` generated DPN JSON, ABI JSON, execute log,
  and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [10]` for `conditional_lifecycle`.
- `scripts/psy/diagnostic-smoke.sh` passed all 27 diagnostic cases.

Known limitations:

- This adds statement-level if/else, not else-if syntax sugar.
- Non-unit entrypoints still need an explicit final top-level return statement;
  return coverage through both conditional branches is not analyzed yet.

Next step:

- Continue broadening Psy expression/arithmetic coverage or add map storage path
  support once a stable upstream Psy idiom is identified.

### Psy ExpressionPredicateProbe Boolean Predicates

Commit: feature commit for Psy predicate expression coverage

Summary:

- Added portable IR expression nodes for equality, inequality, ordering
  comparisons, boolean conjunction, boolean disjunction, and boolean negation.
- Added Psy lowering using upstream `.psy` idioms: `==`, `!=`, `<`, `<=`, `>`,
  `>=`, `&&`, `||`, and `!`.
- Added sourcegen type diagnostics for malformed equality, comparison, and
  boolean operator operands.
- Added EVM IR lowering for the same pure predicate nodes through Yul builtins.
- Added `ProofForge.IR.Examples.ExpressionPredicateProbe`, covering predicate
  locals and assertion predicates.
- Added CLI support:

```sh
lake env proof-forge --emit-expression-predicate-ir-psy -o build/psy/ExpressionPredicateProbe.psy
```

- Added `Examples/Psy/ExpressionPredicateProbe.golden.psy`.
- Added `scripts/psy/expression-predicate-smoke.sh`, which generates a
  temporary Dargo package, runs `dargo test --file`, `dargo compile`,
  `dargo execute`, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the ExpressionPredicateProbe Psy golden source
  snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-expression-predicate-ir-psy -o build/psy/ExpressionPredicateProbe.psy
diff -u Examples/Psy/ExpressionPredicateProbe.golden.psy build/psy/ExpressionPredicateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/expression-predicate-smoke.sh
```

Result:

- Generated ExpressionPredicateProbe source matches the checked-in golden
  fixture.
- `scripts/psy/expression-predicate-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [16]` for `predicate_sum`.
- `scripts/psy/diagnostic-smoke.sh` passed all 25 diagnostic cases.

Known limitations:

- This adds expression predicates, not statement-level `if/else` lowering.
- Fixed-array equality was outside this original expression fixture; it is now
  covered separately by the Dargo-backed `ArrayProbe`.

Next step:

- Add statement-level conditional lowering or broaden arithmetic expression
  coverage with upstream/Dargo fixtures.

### Psy Sourcegen Type Diagnostics

Commit: feature commit for Psy expression and statement type diagnostics

Summary:

- Added a lightweight Psy backend type environment for entrypoint parameters,
  local bindings, mutable locals, and bounded-loop indices.
- Added sourcegen-time type inference and validation for literals, locals,
  fixed arrays, struct literals, field access, addition, hash operations,
  storage effects, context reads, assignment targets, assertions, and returns.
- Added diagnostics for unknown locals, local/array/struct/hash type
  mismatches, immutable assignment, missing non-unit returns, and storage write
  type mismatches.
- Kept existing lowering behavior unchanged for valid fixtures; this feature
  blocks malformed IR before `.psy` source is emitted.
- Extended `Tests/PsyDiagnostics.lean` from 12 to 22 explicit rejection cases.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-counter-ir-psy -o build/psy/Counter.psy
diff -u Examples/Psy/Counter.golden.psy build/psy/Counter.psy
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/{counter,context,hash,map,assert,loop,array,struct,struct-array,abi-aggregate,nested-aggregate,storage-nested-aggregate}-smoke.sh
```

Result:

- `scripts/psy/diagnostic-smoke.sh` passed all 22 diagnostic cases.
- All checked Psy golden source snapshots remain unchanged.
- All Psy Dargo smokes passed and revalidated source snapshots, DPN JSON, ABI
  JSON, execute logs, and `proof-forge-artifact.json`.

Known limitations:

- This is a sourcegen validation layer, not a formal type system for every
  future portable IR extension.
- Assignment mutability is enforced for local/index/field paths rooted in local
  bindings; storage mutation continues to use explicit storage effects.

Next step:

- Continue closing Psy valid-surface gaps with either Dargo-backed fixtures or
  explicit diagnostics before adding new IR nodes.

### Psy StorageNestedAggregateProbe Storage Paths

Commit: feature commit for storage nested aggregate Psy IR coverage

Summary:

- Added generic storage path read/write effects to the portable IR.
- Added `StructField.isRef` so the IR can explicitly model Psy `#[ref]`
  fields for nested storage references.
- Added Psy lowering for storage paths such as `c.person.profile.age` and
  `c.people[1].profile.age`, plus validation for empty paths and missing
  nested `#[ref]` markers.
- Kept EVM IR v0 behavior explicit by rejecting storage path effects.
- Added `ProofForge.IR.Examples.StorageNestedAggregateProbe`, covering scalar
  struct storage and fixed storage arrays of structs.
- Added CLI support:

```sh
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
```

- Added `Examples/Psy/StorageNestedAggregateProbe.golden.psy`.
- Added `scripts/psy/storage-nested-aggregate-smoke.sh`, which generates a
  temporary Dargo package, runs `dargo test --file`, `dargo compile`,
  `dargo execute`, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Extended `Tests/PsyDiagnostics.lean` with invalid storage path cases.
- Added CI coverage for the StorageNestedAggregateProbe Psy golden source
  snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/storage-nested-aggregate-smoke.sh
scripts/psy/diagnostic-smoke.sh
```

Result:

- Generated StorageNestedAggregateProbe source matches the checked-in golden
  fixture.
- `scripts/psy/storage-nested-aggregate-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [220]` for
  `storage_nested_lifecycle`.
- `scripts/psy/diagnostic-smoke.sh` passed all 12 diagnostic cases.

Known limitations:

- Storage path lowering intentionally rejects map storage paths until a stable
  Psy idiom is identified and covered by an upstream-style fixture.
- This does not yet produce deploy JSON or exercise a live Psy node/prover.

Next step:

- Research deploy JSON/live node execution for Psy artifacts, or continue
  expanding expression/path coverage behind diagnostic gates.

### Psy NestedAggregateProbe Mixed Aggregate Updates

Commit: feature commit for nested aggregate Psy IR coverage

Summary:

- Added portable IR statements for mutable local bindings and assignment.
- Added Psy lowering for `let mut` and nested assignment targets made from
  local names, array indexes, and field paths.
- Kept EVM IR v0 behavior explicit by rejecting mutable local bindings and
  assignment statements.
- Added `ProofForge.IR.Examples.NestedAggregateProbe`, covering a mutable
  `[Family; 2]` value whose `Family.children` field is `[Member; 2]`.
- Added CLI support:

```sh
lake env proof-forge --emit-nested-aggregate-ir-psy -o build/psy/NestedAggregateProbe.psy
```

- Added `Examples/Psy/NestedAggregateProbe.golden.psy`.
- Added `scripts/psy/nested-aggregate-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Extended `Tests/PsyDiagnostics.lean` with an invalid assignment target case.
- Added CI coverage for the NestedAggregateProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-nested-aggregate-ir-psy -o build/psy/NestedAggregateProbe.psy
diff -u Examples/Psy/NestedAggregateProbe.golden.psy build/psy/NestedAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/nested-aggregate-smoke.sh
scripts/psy/diagnostic-smoke.sh
```

Result:

- `lake build` passed.
- Generated NestedAggregateProbe source matches the checked-in golden fixture.
- `scripts/psy/nested-aggregate-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [51]` for `nested_update_sum`.
- `scripts/psy/diagnostic-smoke.sh` passed all 10 diagnostic cases.

Known limitations:

- This feature covers local nested aggregate mutation, not storage-backed
  nested aggregate mutation.
- Assignment targets are intentionally limited to local/index/field paths.

Next step:

- Add storage-backed nested aggregate updates or deploy JSON metadata.

### Psy Unsupported Diagnostic Gate

Commit: feature commit for Psy diagnostic regression coverage

Summary:

- Added `Tests/PsyDiagnostics.lean`, a runnable Lean diagnostic regression
  suite for Psy IR rejection paths.
- Added `scripts/psy/diagnostic-smoke.sh`.
- Covered explicit diagnostics for:
  - Unit entrypoint parameters
  - zero-length ABI fixed arrays
  - unknown ABI struct types
  - unsupported map key/value shapes
  - structs used in storage without `deriveStorage`
  - empty struct declarations
  - invalid bounded loop ranges
  - storage writes used as expressions
  - storage reads used as statements
  - invalid assignment targets
- Added the diagnostic smoke to CI.
- Documented the gate in README, validation gates, and `psy-dpn` target notes.

Validation run:

```sh
scripts/psy/diagnostic-smoke.sh
lake build
```

Result:

- `scripts/psy/diagnostic-smoke.sh` passed all 10 diagnostic cases.
- `lake build` passed.

Known limitations:

- This is a regression gate for representative unsupported shapes, not an
  exhaustive formal proof over every impossible IR construction.
- Cross-target capability rejection matrices still need broader coverage.

Next step:

- Expand diagnostics as new Psy IR nodes are added, then continue with deeper
  mixed aggregate update coverage or deploy JSON metadata.

### Psy AbiAggregateProbe ABI Aggregates

Commit: feature commit for ABI aggregate Psy IR coverage

Summary:

- Added entrypoint ABI type validation for Psy IR parameters and returns.
- Rejected Unit parameters before source generation, while keeping Unit returns
  valid for void methods.
- Validated entrypoint fixed-array ABI types as non-empty and struct ABI types
  as declared.
- Added `ProofForge.IR.Examples.AbiAggregateProbe`, covering a struct
  parameter, fixed-array parameter, and struct return value.
- Added CLI support:

```sh
lake env proof-forge --emit-abi-aggregate-ir-psy -o build/psy/AbiAggregateProbe.psy
```

- Added `Examples/Psy/AbiAggregateProbe.golden.psy`.
- Added `scripts/psy/abi-aggregate-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, three
  `dargo execute` calls, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the AbiAggregateProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-abi-aggregate-ir-psy -o build/psy/AbiAggregateProbe.psy
diff -u Examples/Psy/AbiAggregateProbe.golden.psy build/psy/AbiAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/abi-aggregate-smoke.sh
```

Result:

- `lake build` passed.
- Generated AbiAggregateProbe source matches the checked-in golden fixture.
- `scripts/psy/abi-aggregate-smoke.sh` generated DPN JSON, ABI JSON, execute
  log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [15]` for `sum_pair`.
- `dargo execute` returned `result_vm: [6]` for `sum_array`.
- `dargo execute` returned `result_vm: [9, 4]` for `make_pair`.

Known limitations:

- Dargo CLI aggregate execution is flattened to Felt vectors.
- This feature validates flat struct and one-dimensional fixed-array ABI
  shapes, not deeply nested mixed aggregate ABI shapes.

Next step:

- Add deeper nested mixed aggregate update and ABI coverage from the upstream
  Psy syntax corpus, then continue toward deploy JSON metadata.

### Psy StructArrayProbe Struct Arrays

Commit: feature commit for struct-array Psy IR coverage

Summary:

- Extended portable IR storage effects with indexed storage array struct field
  read/write nodes.
- Extended Psy sourcegen to lower storage arrays of structs, whole struct array
  element writes, and indexed struct field reads through `.get()`.
- Extended Psy state validation so fixed storage arrays can use `deriveStorage`
  struct element types.
- Kept EVM IR v0 behavior explicit by rejecting storage array struct field
  effects.
- Added `ProofForge.IR.Examples.StructArrayProbe`, covering local `[Person; 2]`
  struct arrays plus fixed storage arrays of structs.
- Added CLI support:

```sh
lake env proof-forge --emit-struct-array-ir-psy -o build/psy/StructArrayProbe.psy
```

- Added `Examples/Psy/StructArrayProbe.golden.psy`.
- Added `scripts/psy/struct-array-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, two `dargo execute`
  calls, `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the StructArrayProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-struct-array-ir-psy -o build/psy/StructArrayProbe.psy
diff -u Examples/Psy/StructArrayProbe.golden.psy build/psy/StructArrayProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/struct-array-smoke.sh
```

Result:

- `lake build` passed.
- Generated StructArrayProbe source matches the checked-in golden fixture.
- `scripts/psy/struct-array-smoke.sh` generated DPN JSON, ABI JSON, execute
  log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [100]` for
  `local_struct_array_sum`.
- `dargo execute` returned `result_vm: [102]` for
  `storage_struct_array_lifecycle`.

Known limitations:

- This feature covers one-dimensional arrays of flat structs.
- Deeply nested mixed aggregate updates still need dedicated coverage.
- EVM IR v0 explicitly rejects struct-array storage field effects.

Next step:

- Add ABI-facing entrypoint aggregate parameters or return-shape validation,
  then continue toward deployment/deploy JSON metadata.

### Psy StructProbe Struct Values And Storage

Commit: feature commit for struct Psy IR coverage

Summary:

- Extended portable IR with struct declarations, struct value types, struct
  literals, and field access expressions.
- Registered `data.struct` as a target capability for struct values and field
  access.
- Extended portable IR storage effects with scalar storage struct field
  read/write nodes.
- Extended Psy sourcegen to emit `#[derive(Storage)]` struct declarations,
  `new Struct { ... }` literals, local field access, scalar storage struct
  assignment, and storage struct field reads through `.get()`.
- Kept EVM IR v0 behavior explicit by rejecting struct literals, field access,
  struct typed let bindings, struct returns, and storage struct field effects.
- Added `ProofForge.IR.Examples.StructProbe`, covering local struct literals
  plus scalar storage struct read/write behavior.
- Added CLI support:

```sh
lake env proof-forge --emit-struct-ir-psy -o build/psy/StructProbe.psy
```

- Added `Examples/Psy/StructProbe.golden.psy`.
- Added `scripts/psy/struct-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, two `dargo execute`
  calls, `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the StructProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-struct-ir-psy -o build/psy/StructProbe.psy
diff -u Examples/Psy/StructProbe.golden.psy build/psy/StructProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/struct-smoke.sh
```

Result:

- `lake build` passed.
- Generated StructProbe source matches the checked-in golden fixture.
- `scripts/psy/struct-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [30]` for `local_sum`.
- `dargo execute` returned `result_vm: [26]` for `storage_lifecycle`.

Known limitations:

- This feature covers flat struct values and scalar storage structs.
- Struct arrays, nested structs, and methods on structs still need dedicated
  coverage.
- EVM IR v0 explicitly rejects struct IR nodes.

Next step:

- Combine structs with fixed arrays in a follow-up fixture aligned with
  upstream `array_test.psy` and `array_ref_struct_index_test.psy`.

### Psy ArrayProbe Fixed Arrays

Commit: feature commit for fixed-array Psy IR coverage

Summary:

- Extended portable IR types with fixed arrays, represented as `[T; N]` in Psy.
- Added `data.fixed_array` for fixed-size array values and `storage.array` for
  fixed array storage fields.
- Extended portable IR expressions with fixed array literals and index reads.
- Extended portable IR storage effects with fixed array index read/write nodes.
- Extended Psy sourcegen to lower local array literals, index reads, storage
  array writes, and storage array reads through `.get()` when used as values.
- Kept EVM IR v0 behavior explicit by rejecting fixed-array literals, index
  access, storage array effects, and fixed-array returns.
- Added `ProofForge.IR.Examples.ArrayProbe`, covering local `[Felt; 3]`
  literals plus fixed storage array read/write behavior.
- Added CLI support:

```sh
lake env proof-forge --emit-array-ir-psy -o build/psy/ArrayProbe.psy
```

- Added `Examples/Psy/ArrayProbe.golden.psy`.
- Added `scripts/psy/array-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, three `dargo execute`
  calls, `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the ArrayProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-array-ir-psy -o build/psy/ArrayProbe.psy
diff -u Examples/Psy/ArrayProbe.golden.psy build/psy/ArrayProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/array-smoke.sh
```

Result:

- `lake build` passed.
- Generated ArrayProbe source matches the checked-in golden fixture.
- `scripts/psy/array-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [60]` for `sum_literal`.
- `dargo execute` returned `result_vm: [31]` for `storage_lifecycle`.
- `dargo execute` returned `result_vm: [1]` for `array_predicates`.

Known limitations:

- This feature covers one-dimensional fixed arrays over `Felt` and `Hash`
  storage elements. Struct arrays and nested arrays still need dedicated
  coverage.
- Dynamic arrays and unbounded indexing are still unsupported.
- EVM IR v0 explicitly rejects fixed-array IR nodes.

Next step:

- Add struct coverage next, then combine structs with arrays in a follow-up
  fixture aligned with upstream `array_test.psy`.

### Psy LoopProbe Bounded Loops

Commit: feature commit for bounded-loop Psy IR coverage

Summary:

- Extended portable IR statements with a static `boundedFor` node.
- Registered `control.bounded_loop` as a target capability and enabled it for
  `psy-dpn`.
- Extended Psy sourcegen to lower `boundedFor` to Psy fixed-range `for` loops
  such as `for _i in 0u32..3u32`.
- Kept EVM IR v0 behavior explicit by rejecting bounded loops with a diagnostic.
- Added `ProofForge.IR.Examples.LoopProbe`, which resets scalar storage, runs a
  three-iteration loop, and returns the final count.
- Added CLI support:

```sh
lake env proof-forge --emit-loop-ir-psy -o build/psy/LoopProbe.psy
```

- Added `Examples/Psy/LoopProbe.golden.psy`.
- Added `scripts/psy/loop-smoke.sh`, which generates a temporary Dargo package,
  runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the LoopProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-loop-ir-psy -o build/psy/LoopProbe.psy
diff -u Examples/Psy/LoopProbe.golden.psy build/psy/LoopProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/loop-smoke.sh
```

Result:

- `lake build` passed.
- Generated LoopProbe source matches the checked-in golden fixture.
- `scripts/psy/loop-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [3]` for `count_to_three`.

Known limitations:

- Loop lowering is deliberately static and bounded; dynamic or unbounded loops
  are still unsupported.
- The portable IR still lacks array and struct coverage.
- EVM IR v0 explicitly rejects bounded loops.

Next step:

- Add array coverage next, because upstream Psy tests and precompiles use
  fixed arrays heavily alongside bounded loops.

### Psy AssertProbe IR Assertions

Commit: feature commit for dynamic nested EVM local arrays

Summary:

- Extended portable IR with statement-level `assert` and `assertEq` nodes.
- Registered the `assertions` capability for target profiles and artifact
  metadata.
- Extended Psy sourcegen to lower assertion statements into method bodies as
  `assert(condition, "message")` and `assert_eq(lhs, rhs, "message")`.
- Added basic string escaping for generated Psy assertion messages.
- Added `ProofForge.IR.Examples.AssertProbe`, which validates assertions inside
  a contract method body.
- Added CLI support:

```sh
lake env proof-forge --emit-assert-ir-psy -o build/psy/AssertProbe.psy
```

- Added `Examples/Psy/AssertProbe.golden.psy`.
- Added `scripts/psy/assert-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the AssertProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-assert-ir-psy -o build/psy/AssertProbe.psy
diff -u Examples/Psy/AssertProbe.golden.psy build/psy/AssertProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/assert-smoke.sh
```

Result:

- `lake build` passed.
- Generated AssertProbe source matches the checked-in golden fixture.
- `scripts/psy/assert-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [12]` for `checked_sum(5,7)`.

Known limitations:

- Assertion conditions still depend on the currently narrow expression subset.
- EVM IR v0 rejects assertion statements through capability diagnostics.

Next step:

- Add bounded-loop coverage next, because loops are heavily used by Psy
  precompiles and are required for array/tree-style contracts.

### Psy MapProbe Storage Map Coverage

Commit: `427a0ec feat: support dynamic nested EVM local arrays`

Summary:

- Extended portable IR with fixed-capacity map state and `storage.map` effects:
  `contains`, `get`, `insert`, and `set`.
- Extended Psy sourcegen to lower the supported map shape to
  `Map<Hash, Hash, Nu32>` and to reject unsupported map key/value types with an
  explicit diagnostic.
- Added `ProofForge.IR.Examples.MapProbe` with scalar fields adjacent to the
  map to mirror upstream Psy storage-layout regression tests.
- Added CLI support:

```sh
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
```

- Added `Examples/Psy/MapProbe.golden.psy`.
- Added `scripts/psy/map-smoke.sh`, which generates a temporary Dargo package,
  runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the MapProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
diff -u Examples/Psy/MapProbe.golden.psy build/psy/MapProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/map-smoke.sh
```

Result:

- `lake build` passed.
- Generated MapProbe source matches the checked-in golden fixture.
- `scripts/psy/map-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [55, 66, 77, 88]` for
  `map_lifecycle`.

Known limitations:

- Psy map lowering currently supports only `Map<Hash, Hash, N>`.
- The portable IR still lacks first-class assertions, bounded loops, arrays,
  and structs.
- EVM IR v0 explicitly rejects portable map storage.

Next step:

- Add IR-level assertions or bounded-loop coverage next, then validate the new
  node through Psy golden output and Dargo smoke.

### Psy HashProbe And Experimental Target Slice

Commit: test commit for EVM SDK example golden Yul fixtures

Summary:

- Extended portable IR with `Hash`, four-Felt hash literals, typed `let`
  bindings, `hash`, and `hash_two_to_one` expressions.
- Extended Psy sourcegen to lower hash values through upstream Psy idioms:
  `Hash`, `[a, b, c, d]`, `hash(data)`, and `hash_two_to_one(left, right)`.
- Added `ProofForge.IR.Examples.HashProbe` with two contract methods:
  `poseidon_hash` and `poseidon_pair_hash`.
- Added CLI support:

```sh
lake env proof-forge --emit-hash-ir-psy -o build/psy/HashProbe.psy
```

- Added `Examples/Psy/HashProbe.golden.psy`.
- Added `scripts/psy/hash-smoke.sh`, which generates a temporary Dargo package,
  runs `dargo test --file`, `dargo compile`, two `dargo execute` calls,
  `dargo generate-abi`, and writes `proof-forge-artifact.json`.
- Added `scripts/psy/validate-artifact-metadata.py`; the Counter, ContextProbe,
  and HashProbe smokes now validate artifact hashes, byte sizes, capability
  records, validation flags, and expected execution results.
- Added CI coverage for Psy golden source generation without requiring Dargo on
  GitHub Actions.

Validation run:

```sh
lake build
lake env proof-forge --emit-hash-ir-psy -o build/psy/HashProbe.psy
diff -u Examples/Psy/HashProbe.golden.psy build/psy/HashProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/context-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/hash-smoke.sh
```

Result:

- `lake build` passed.
- Generated HashProbe source matches the checked-in golden fixture.
- `scripts/psy/hash-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- All three Psy smoke scripts validated `proof-forge-artifact.json` against the
  generated files and expected execution output.
- `dargo execute` returned the expected four-Felt output for `poseidon_hash`.
- `dargo execute` returned the expected four-Felt output for
  `poseidon_pair_hash`.

Known limitations:

- Hash support is deliberately narrow: fixed four-Felt `Hash` values only.
- Psy storage maps, bounded loops, and deploy JSON are still not implemented.
- EVM IR v0 explicitly rejects Hash values and hash expressions.

Next step:

- Add map/storage-map coverage from upstream `psy-compiler/tests` and
  `psy-precompiles`, then factor the repeated Dargo package generation logic.

### Psy ContextProbe Fixture And Artifact Metadata

Commit: pending

Summary:

- Extended portable IR with `context.read` effects for `userId`, `contractId`,
  and `checkpointId`.
- Extended Psy sourcegen to lower entrypoint parameters and context reads.
- Added `ProofForge.IR.Examples.ContextProbe`, the first non-Counter Psy IR
  fixture.
- Added CLI support:

```sh
lake env proof-forge --emit-context-ir-psy -o build/psy/ContextProbe.psy
```

- Added `Examples/Psy/ContextProbe.golden.psy`.
- Added `scripts/psy/context-smoke.sh`, which mirrors the Counter Dargo smoke:
  `dargo test --file`, `dargo compile`, `dargo execute`, and
  `dargo generate-abi`.
- Added `scripts/psy/write-artifact-metadata.py` and wired both Psy smoke
  scripts to emit `proof-forge-artifact.json` with hashes for source, circuit
  JSON, ABI JSON, and execute logs.

Validation run:

```sh
lake build
lake env proof-forge --emit-context-ir-psy -o build/psy/ContextProbe.psy
diff -u Examples/Psy/ContextProbe.golden.psy build/psy/ContextProbe.psy
scripts/psy/context-smoke.sh
scripts/psy/counter-smoke.sh
git diff --check
```

Result:

- `lake build` passed.
- ContextProbe emits reviewable Psy source with parameters and context reads.
- Generated ContextProbe source matches the checked-in golden fixture.
- `scripts/psy/context-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [15]` for `sum_context(2,3)`.
- `scripts/psy/counter-smoke.sh` now also emits `proof-forge-artifact.json`.

Known limitations:

- ContextProbe uses `_proof_forge_marker` storage because Dargo v0.1.0 panics on
  an empty `#[contract] #[derive(Storage)]` struct.
- The IR still lacks maps, fixed arrays, assertions, hashes, bounded loops, and
  reusable package generation.
- Dargo does not expose a `--version` flag, so metadata records the Dargo path
  and leaves the version null for now.

Next step:

- Add a curated upstream syntax regression subset from `psy-compiler/tests`,
  then expand the IR/sourcegen surface toward maps, arrays, assertions, and
  hashes.

## 2026-06-30

### Psy Counter IR Sourcegen And Smoke

Commit: pending

Summary:

- Added `ProofForge.Backend.Psy.IR`, a strict v0 source generator for the
  hand-written portable Counter IR fixture.
- Added CLI support:

```sh
lake env proof-forge --emit-counter-ir-psy -o build/psy/Counter.psy
```

- Added `Examples/Psy/Counter.golden.psy` as the reviewed source snapshot.
- Added `scripts/psy/counter-smoke.sh`, which:
  - regenerates Counter Psy source
  - compares it against the golden fixture
  - runs `dargo test --file`
  - creates a temporary Dargo package
  - runs `dargo compile --contract-name Counter --method-names initialize increment get`
  - checks the Dargo JSON artifact is non-empty
  - runs `dargo execute --contract-name Counter --method-names initialize increment increment get`
  - checks the local execution log contains `result_vm: [2]`
  - runs `dargo generate-abi --contract-name Counter --output-dir target --pretty`
  - checks the ABI JSON artifact is non-empty
- Verified `psyup install 0.1.0` as a working macOS arm64 toolchain path for
  this smoke.
- Recorded the upstream syntax/CI corpus: `psy-precompiles`, `tests`, and
  `psy-compiler`'s Makefile `build`/`ci` targets.

Validation run:

```sh
lake build
lake env proof-forge --emit-counter-ir-psy -o build/psy/Counter.psy
diff -u Examples/Psy/Counter.golden.psy build/psy/Counter.psy
psyup install 0.1.0
scripts/psy/counter-smoke.sh
```

Result:

- `lake build` passed.
- Counter IR emits reviewable Psy source.
- Generated Psy source matches the checked-in golden fixture.
- `scripts/psy/counter-smoke.sh` generated `build/psy/Counter.psy`, ran
  `dargo test --file`, ran `dargo compile`, produced
  `build/psy/dargo-counter/target/proof_forge_counter.json`, ran
  `dargo execute`, and verified `get` returned `result_vm: [2]` after two
  increments in the same local execution session.
- The same smoke generated non-empty ABI output at
  `build/psy/dargo-counter/target/Counter.json`.
- Direct `cargo install --git https://github.com/PsyProtocol/psy-compiler dargo`
  fetched `psy-compiler` but failed while Cargo updated the `psy-node`
  `psy-contracts` submodule URL.
- `psyup` v0.1.1 currently has only a Linux x86_64 release asset; macOS arm64
  was validated by pinning `psyup install 0.1.0`.

Known limitations:

- The generator supports only the current no-argument Counter IR subset:
  `u64` scalar state, scalar read/write, `add`, let-bind, and return.
- No deploy JSON, artifact metadata, or live Psy node smoke exists yet.
  `dargo execute` covers local user/contract execution, not network deployment.

Next step:

- Add `proof-forge-artifact.json` metadata to the Psy smoke, then decide
  whether CI should pin `psyup` v0.1.0 or wait for a newer macOS release asset.

### Psy/DPN SDK Skeleton

Commit: `feat: add Psy DPN SDK skeleton`

Summary:

- Added `ProofForge.Psy` as the first Lean SDK surface for the `psy-dpn` ZK
  target.
- Added primitive types and helpers:
  - `Felt`
  - `U32`
  - `Hash`
  - `ContractMetadata`
- Added context, storage, IMT map, hash, and deferred invocation externs under
  the `lean_psy_*` naming convention.
- Added a small `Examples/Psy/Counter.lean` SDK example.

Validation run:

```sh
lake build
lake env lean Examples/Psy/Counter.lean
```

Result:

- Passed.

Notes:

- The example uses `initCounter` instead of `initialize` because `initialize`
  is a Lean command keyword.

Known limitations:

- The SDK is a source-generation boundary only; no Psy backend lowers these
  externs yet.
- There is no Dargo package generation or `.psy` output yet.

Next step:

- Add a `psy-dpn` source generator for the hand-written Counter IR fixture.

### Portable IR Counter Runtime Dispatch

Commit: `824f5f8 feat: add IR counter EVM runtime smoke`

Summary:

- Added EVM selector metadata to the hand-written Counter IR fixture.
- Extended IR-to-Yul lowering to emit runtime selector dispatch for:
  - `initialize()`
  - `increment()`
  - `get()`
- Added `proof-forge --emit-counter-ir-bytecode`, which compiles Counter IR
  through runtime Yul and `solc --strict-assembly`.
- Added a dedicated Foundry smoke script for the IR Counter path:

```sh
scripts/evm/ir-counter-smoke.sh
```

Validation run:

```sh
lake build
lake env proof-forge --emit-counter-ir-yul -o build/ir/Counter.yul
lake env proof-forge --emit-counter-ir-bytecode -o build/ir/Counter.bin --yul-output build/ir/Counter.bytecode.yul
solc --strict-assembly build/ir/Counter.yul --bin
scripts/evm/ir-counter-smoke.sh
```

Result:

- `lake build` passed.
- Counter IR emits selector-dispatch Yul.
- Counter IR emits non-empty EVM bytecode.
- `solc --strict-assembly` accepts the generated runtime Yul.
- Foundry smoke passes for `initialize`/`increment`/`get` and unknown-selector
  revert behavior.

Known limitations:

- The IR fixture is still hand-written; there is no Lean-source-to-IR extractor.
- Only no-argument entrypoints are supported in the IR EVM dispatcher.

Next step:

- Promote the IR Counter path into CI once external tool gating is in place, and
  generalize the dispatcher beyond no-argument entrypoints.

### Portable IR Counter Lowering

Commit: `787d437 feat: add portable IR counter lowering`

Summary:

- Added the first target registry modules:
  - `ProofForge.Target.Capability`
  - `ProofForge.Target.Registry`
  - `ProofForge.Target.Check`
- Added the first portable contract IR:
  - `ValueType`
  - `StateDecl`
  - `Expr`
  - `Effect`
  - `Statement`
  - `Entrypoint`
  - `Module`
- Added a hand-written Counter IR fixture in `ProofForge.IR.Examples.Counter`.
- Added an EVM/Yul lowering path for the Counter-shaped IR subset.
- Added CLI smoke command:

```sh
lake env proof-forge --emit-counter-ir-yul -o build/ir/Counter.yul
```

Validation run:

```sh
lake build
lake env proof-forge --emit-counter-ir-yul -o build/ir/Counter.yul
solc --strict-assembly build/ir/Counter.yul --bin
```

Result:

- `lake build` passed.
- Counter IR lowers to Yul.
- `solc --strict-assembly` accepts the generated Yul.

Known limitations:

- The IR-generated Yul currently contains function definitions only.
- It does not yet generate EVM calldata selector dispatch.
- `solc` emits `00` for this debug object because no runtime dispatcher calls
  the generated functions yet.
- Existing `--evm-bytecode` smoke still requires Foundry `cast`; it was not
  revalidated locally because `cast` was not on `PATH`.

Next step:

- Generate an EVM dispatcher/runtime wrapper from IR entrypoints so the IR path
  can produce callable bytecode and run through Foundry smoke.

### Psy DPN Target Research

Commit: `ce5ab3e docs: add Psy DPN target research`

Summary:

- Added `psy-dpn` as a Research-stage target.
- Classified Psy as a ZK circuit source-generation target.
- Documented why the first integration path should generate `.psy` source and
  call Dargo instead of directly emitting DPN internals.
- Added `zk.circuit` and `zk.proof` capability ids.
- Added Chinese analysis for the Psy/DPN target.

Validation run:

```sh
git diff --check
```

Result:

- Documentation whitespace check passed before commit.

Known limitations:

- No Psy source generator exists yet.
- No Dargo smoke exists in this repository.

Next step:

- Reuse the portable Counter IR fixture once the IR-to-sourcegen path exists.

### Portable IR And Target Planning Docs

Commit: `9b7fce3 docs: add portable IR, capability registry, validation gates, and dev standards`

Summary:

- Added the first portable IR spec.
- Added canonical capability ids.
- Added shared Counter scenario.
- Added validation gates and development standards.
- Added implementation backlog slices for target registry, IR, metadata, EVM
  hardening, Wasm, Solana, Move, CI, and Psy.

Validation run:

```sh
git diff --check
```

Result:

- Documentation whitespace check passed before commit.

Known limitations:

- These were planning docs only; no IR code existed yet.

Next step:

- Implement the Target registry and Counter-shaped IR v0 in Lean.

### Multi-Chain Target Design

Commit: `a5555e5 docs: add multichain target design`

Summary:

- Added the first multi-chain platform RFCs and Chinese feasibility/technical
  analysis.
- Established the direction: Lean business logic plus target-specific adapters.
- Documented EVM, Solana, Wasm-family, Move-family, and cloud platform tracks.

Validation run:

```sh
git diff --check
```

Result:

- Documentation whitespace check passed before commit.

Known limitations:

- Design-only milestone.

Next step:

- Split the design into concrete target registry, IR, and validation tasks.

### EVM Baseline

Commits:

- `34b1708 Initial ProofForge EVM backend`
- `b7a5343 Add EVM examples and Foundry smoke tests`
- `a97dd21 Add CI and integrate EVM bytecode CLI`

Summary:

- Added the initial EVM SDK and Yul backend.
- Added EVM examples and Foundry smoke tests.
- Added bytecode compilation through `solc --strict-assembly`.
- Added CI around the baseline build and EVM smoke path.

Current role:

- EVM remains the first working target.
- New IR work should use EVM as the first executable backend to validate
  semantics before adding more chains.

### EVM Nested Local Fixed Arrays

Commit: pending

Summary:

- Extended portable IR EVM local fixed-array lowering to static nested scalar
  arrays.
- Added deterministic Yul locals for nested leaves such as `matrix[1][0]`.
- Covered static nested reads, mutable leaf assignment, numeric leaf compound
  assignment, nested whole-local assignment, and RHS snapshotting.
- Extended nested local scalar fixed arrays to dynamic index paths, including
  nested getter helpers for reads and nested `switch` blocks for mutable leaf
  assignment and compound assignment.
- Added `nested_dynamic_pick`, `nested_dynamic_row_pick`,
  `nested_dynamic_update`, and `nested_dynamic_row_update` coverage to
  `EvmArrayValueProbe`.

Validation run:

```sh
lake build
scripts/evm/array-value-ir-smoke.sh
```

Result:

- Lean build passed.
- Array value smoke produced reproducible golden Yul, compiled bytecode with
  `solc --strict-assembly`, validated metadata, and passed 17 Foundry tests.

Known limitations:

- Nested local arrays with unsupported aggregate or non-flat leaves remain
  explicit unsupported surfaces; flat struct leaves are covered by
  `EvmStructArrayValueProbe`.

### EVM SDK Example Golden Yul

Commit: pending

Summary:

- Added tracked golden Yul fixtures for SDK EVM examples:
  `ArrayExample`, `Counter`, `SimpleToken`, `ERC20`, `Ownable`, `Pausable`,
  and `VerifiedVault`.
- Updated `scripts/evm/build-examples.sh` to emit generated SDK Yul into
  `build/evm`, diff it against each sibling `.golden.yul`, compile bytecode,
  and validate ProofForge artifact metadata.
- Updated EVM validation docs and example README files so changing an SDK
  example now includes updating its golden Yul fixture.

Validation run:

```sh
scripts/evm/build-examples.sh
```

Result:

- All seven SDK examples produced reproducible Yul matching the new golden
  fixtures.
- All seven SDK examples compiled with `solc --strict-assembly` and validated
  EVM artifact/deploy metadata.

Known limitations:

- Runtime behavior remains covered by `scripts/evm/foundry-smoke.sh`.

### CI Baseline Repair + Upgrade Policy Resolver

Commit: pending

Summary:

- Fixed the root `target/` ignore rule so `ProofForge/Target/HostBridge.lean`
  is no longer silently ignored on case-insensitive filesystems, while keeping
  Rust build output ignored in known target directories.
- Replaced the missing GitHub Actions Rust setup action with
  `dtolnay/rust-toolchain@stable`, then pinned the CosmWasm smoke job to
  Rust `1.88.0` and `cosmwasm-check 2.2.9 --locked` after latest
  `cosmwasm-check` failed to link against newer Rust/Wasmer probestack symbols.
- Wired `ContractSpec.upgradePolicy?` into target resolution so unsupported
  target/policy combinations fail before code generation, and supported
  policies emit `upgrade.policy.*` metadata.
- Added a focused upgrade-policy smoke covering EVM, Solana, NEAR, Psy, JSON
  serialization, and escaping.
- Corrected the Gate G0 ledger so it no longer claims `just check` is green
  before CI and docs sync evidence are actually green.

Validation run:

```sh
lake build ProofForge.Target.Adapter
lake env lean --run Tests/UpgradePolicy.lean
lake build ProofForge.Target
```

Result:

- Target adapter build, upgrade-policy smoke, and target library build passed
  locally before the full repo validation pass.

### Testkit Runtime Error Expectations

Commit: pending

Summary:

- Added `testkit/scenarios/error-ref-user-code.toml`, a focused EVM +
  Wasm-NEAR scenario that reuses the portable `error-ref` fixture and asserts
  exact `assertion_id` plus `user_code` values for both failing entrypoints.
- Kept Solana in the existing three-target `error-ref` scenario as
  assertion-id-only, matching its runtime encoding as
  `ProgramError::Custom(assertion_id)`.
- Updated the Workstream 33 backlog status so M3 is recorded as implemented
  with testkit evidence.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario error-ref-user-code --trace
```

Result:

- EVM and Wasm-NEAR both reported and matched `Counter::Overflow` and
  `Counter::ExactMatch` user codes.
- The two-target normalized trace parity check passed.

### Portable Starter Authoring Boundary

Commit: pending

Summary:

- Clarified that new starter contracts should import
  `ProofForge.Contract.Source` and stay chain-neutral.
- Moved `ProofForge.Evm` / `Lean.Evm` wording to the EVM-native legacy/example
  path instead of presenting it as the default contract authoring surface.
- Updated the Chinese README and development-standards translations plus the
  i18n manifest hashes.

Validation run:

```sh
lake env lean templates/portable-counter/Counter.lean
scripts/i18n/check-sync.sh
git diff --check
```

Result:

- The portable starter template loaded successfully.
- Translation sync and whitespace checks passed.

### ContractSpec Error Catalogue

Commit: pending

Summary:

- Added a target-neutral `errors` catalogue to `ContractSpec` JSON output.
  Entries are derived from portable IR `assert` / `assertEq` `ErrorRef`
  metadata and include `assertionId`, optional `userCode`, fallback `message`,
  and owning `entrypoints`.
- Added `Tests/ContractSpecJson.lean` for Counter's empty error catalogue,
  ErrorRefProbe's two user-code entries, and nested control-flow assertions.
- Added `just contract-spec-json` and wired it into CI before backend-specific
  semantic-plan checks.
- Marked Workstream 33 M4 as partially implemented while keeping client
  wrapper consumption open.

Validation run:

```sh
lake build ProofForge.Contract.Spec.Json
lake env lean --run Tests/ContractSpecJson.lean
just contract-spec-json
```

Result:

- ContractSpec JSON schema tests passed locally.

### Contract Client Error Catalogue Helpers

Commit: pending

Summary:

- Embedded the target-neutral ContractSpec `ERRORS` catalogue into generated
  EVM and NEAR TypeScript wrapper sketches.
- Added `errorByAssertionId` to both wrappers, `decodeProofForgeRevert` for
  the EVM ABI-encoded `(uint32,string)` revert payload, and
  `parseProofForgePanic` for NEAR's `PF:{id}:{code}` panic prefix.
- Added `Tests/ContractClient.lean`, `just contract-client`, and a CI step for
  generated wrapper checks.
- Updated Workstream 33 M4 status to show EVM/NEAR wrapper consumption as
  implemented while keeping Solana IDL/client consumption open.

Validation run:

```sh
lake build ProofForge.Contract.Client
lake env lean --run Tests/ContractClient.lean
just contract-client
```

Result:

- Generated client wrapper checks passed locally.

### Solana Client Error Catalogue

Commit: pending

Summary:

- Added the portable `errors` catalogue to Solana IDL output, reusing the
  target-neutral ContractSpec error schema.
- Exported `ERRORS`, `errorByAssertionId`, and `errorBySolanaCustomCode` from
  the generated Solana TypeScript client.
- Extended `Tests/SolanaSdkManifest.lean` so package IDL/client output exposes
  empty error catalogues for contracts without `ErrorRef`, and ErrorRefProbe
  exposes the two portable assertion errors.
- Marked Workstream 33 M4 implemented at the client-schema/sketch boundary.

Validation run:

```sh
lake build ProofForge.Backend.Solana.Idl ProofForge.Backend.Solana.Client
lake env lean --run Tests/SolanaSdkManifest.lean
```

Result:

- Solana IDL/client error catalogue checks passed locally.

### NEAR ValueVault Backend-Invariant State Bridge

Commit: pending

Summary:

- Extended the decide-checkable NEAR FV-4 bridge from the ValueVault FV-8
  invariant scenario to the EmitWat/offline-host execution surface.
- Derived the ValueVault offline-host input sequence from
  `ValueVaultInvariant.defaultInputs` and checked return fragments against
  `ValueVaultInvariant.expectedReturns`.
- Added storage-key counts and cumulative log counts to each offline-host IO
  expectation.
- Checked the final offline-host state against the FV-8 scenario state plus
  the ValueVault accounting and final-storage predicates.
- Derived the ValueVault event log JSON fragments from the invariant final
  state, covering `VaultInitialized`, `ValueDeposited`, `ValueCharged`,
  `ValueReleased`, and `ValueSnapshot`.
- Wired the new `value_vault_emitwat_backend_invariant_bridge_ok` theorem into
  the formal smoke entrypoint.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR ValueVault backend-invariant state bridge checks passed locally.

### NEAR EmitWat Host Import Signatures

Commit: pending

Summary:

- Added `WasmImportExpectation` to the NEAR refinement artifact surface so
  obligations can check host import module names plus Wasm parameter/result
  signatures, not only imported function names.
- Pinned the Counter and ValueVault NEAR host-call ABI for `input`,
  `read_register`, `storage_read`, `storage_write`, `value_return`,
  `log_utf8`, and `block_index` where those imports are part of the checked
  surface.
- Added decide-checkable `counter_emitwat_host_import_signatures_ok` and
  `value_vault_emitwat_host_import_signatures_ok` anchors and wired both into
  the formal smoke entrypoint.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat host import signature checks passed locally.

### NEAR EmitWat Host Call Frames

Commit: pending

Summary:

- Added `WasmTraceOp` and `WasmHostFrameExpectation` to the NEAR refinement
  artifact surface so obligations can check contiguous Wasm AST instruction
  frames around host calls, not only call names.
- Pinned the `u64` storage read/write helper frames for `storage_read`,
  `read_register`, and `storage_write`, including the key/value buffer
  constants passed to the NEAR host ABI.
- Pinned the `u64` return helper frame for `value_return` and the ValueVault
  event-log frame for `log_utf8`.
- Added decide-checkable `counter_emitwat_host_frames_ok` and
  `value_vault_emitwat_host_frames_ok` anchors and wired both into the formal
  smoke entrypoint.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat host call-frame checks passed locally.

### NEAR Offline-Host Storage Snapshots

Commit: pending

Summary:

- Added per-step `storageSnapshot` data to NEAR offline-host IO expectations.
- Extended the offline-host trace runner so each checked Counter and ValueVault
  entrypoint records the full IR storage contents after execution, not only the
  number of storage keys.
- Added `OfflineHostExecutionObligation.storageSnapshotsOk` plus
  decide-checkable Counter and ValueVault storage-snapshot anchors.
- Folded the ValueVault storage-snapshot check into the existing
  backend-invariant bridge so the FV-8 scenario now constrains every checked
  intermediate storage state as well as final storage.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host storage snapshot checks passed locally.

### NEAR Offline-Host Storage Bytes

Commit: pending

Summary:

- Added byte-level `storageHexSnapshot` data to NEAR offline-host IO
  expectations.
- Derived storage bytes from the same Borsh/little-endian scalar encoder used
  for offline-host inputs and return observations.
- Pinned Counter and ValueVault storage byte strings after every checked
  entrypoint, connecting the semantic storage snapshots to the byte strings
  that the NEAR host storage boundary would persist.
- Added decide-checkable Counter and ValueVault storage-byte anchors and folded
  the ValueVault storage-byte check into the backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host storage byte checks passed locally.

### NEAR Offline-Host Log Payload Bytes

Commit: pending

Summary:

- Added byte-level `logPayloadHexFragments` data to NEAR offline-host IO
  expectations for ValueVault event logs.
- Split ValueVault event formatting into the host `log_utf8` payload and the
  human-readable offline-host log-line fragment, so obligations can check the
  actual UTF-8 payload bytes separately from console text.
- Derived expected `log_utf8` payload hex fragments from the same FV-8
  ValueVault invariant event stream that produces the semantic event logs.
- Added decide-checkable ValueVault log-payload-byte anchors and folded the
  log payload hex check into the backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host log payload byte checks passed locally.

### NEAR Offline-Host Return Payload Bytes

Commit: pending

Summary:

- Added byte-level `returnPayloadHex` data to NEAR offline-host IO
  expectations.
- Derived `returnPayloadHex` from the same scalar Borsh/little-endian encoder
  used by `value_return` observations, rather than relying only on the
  human-readable `returnLineFragment`.
- Added decide-checkable Counter and ValueVault return-payload-byte anchors.
- Folded the ValueVault return payload hex check into the backend-invariant
  bridge so FV-8 expected returns now constrain both semantic return values and
  the host `value_return` payload bytes.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host return payload byte checks passed locally.

### NEAR EmitWat Memory Layout Surface

Commit: pending

Summary:

- Added a memory-surface check to NEAR artifact obligations so Counter and
  ValueVault pin the emitted Wasm memory declaration, not only the memory export
  name.
- Added fixed host-buffer memory region expectations for `KEY_BUF`, `RET_BUF`,
  `EVENT_BUF`, `EVT_KEY_PTR`, and `INPUT_BUF`.
- Checked that those host buffers have nonzero size, fit in the first Wasm
  memory page, and do not overlap.
- Wired the new memory-surface anchors into the formal smoke entrypoint and the
  ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat memory layout surface checks passed locally.

### NEAR EmitWat Entrypoint Input Frames

Commit: pending

Summary:

- Added artifact-surface host-frame expectations for entrypoint input
  prologues.
- Pinned the `input(0)` plus `read_register(0, INPUT_BUF)` sequence used by
  Counter and ValueVault exported entrypoints before parameter decoding.
- Pinned scalar u64 parameter loads from `INPUT_BUF` for ValueVault's
  `initialize`, `deposit`, `charge_fee`, and `release` entrypoints, including
  the second `charge_fee` parameter at offset 8.
- Wired the new Counter and ValueVault input-frame anchors into the formal
  smoke entrypoint and the ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat entrypoint input-frame checks passed locally.

### NEAR EmitWat Context Host Frames

Commit: pending

Summary:

- Added ValueVault context host-frame expectations for `checkpointId`
  lowering.
- Pinned the `block_index` host call followed by `local.set checkpoint` in both
  `initialize` and `snapshot`.
- Wired the new context-frame anchor into the formal smoke entrypoint and the
  ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat context host-frame checks passed locally.

### NEAR EmitWat Storage Read Key Frames

Commit: pending

Summary:

- Added artifact-surface host-frame expectations for scalar storage reads.
- Pinned the Counter `count` key pointer/length passed into `__pf_read_u64`
  for `increment` and `get`.
- Pinned the ValueVault `balance`, `released`, `fees`, and `operations` key
  pointer/length pairs passed into `__pf_read_u64` for `deposit`,
  `charge_fee`, `release`, `snapshot`, `get_balance`, and `get_net_value`.
- Wired the new storage-read-key-frame anchors into the formal smoke entrypoint
  and the ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat storage read key-frame checks passed locally.

### NEAR EmitWat Storage Write Key/Value Frames

Commit: pending

Summary:

- Added artifact-surface host-frame expectations for scalar storage writes.
- Pinned Counter `count` writes passed into `__pf_write_u64` for `initialize`
  and `increment`, including the `n + 1` value expression.
- Pinned ValueVault `balance`, `released`, `fees`, `last_value`,
  `last_checkpoint`, and `operations` write key/value frames for `initialize`,
  `deposit`, `charge_fee`, `release`, and `snapshot`.
- Wired the new storage-write-key-value-frame anchors into the formal smoke
  entrypoint and the ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat storage write key/value-frame checks passed locally.

### Contract Source Target Capability Diagnostics

Commit: pending

Summary:

- Added source-aware unsupported-capability diagnostics at the target resolver
  boundary.
- Routed `wasm-near` contract_source builds through `Target.resolveSpec` before
  EmitWat lowering.
- Added a plan-backed EmitWat render path for contract_source builds.
- Added a negative contract_source fixture and `just
  contract-source-diagnostics` CLI smoke for target id, capability id,
  operation, and source-marker diagnostics.

Validation run:

```sh
lake build ProofForge.Target.Formal
lake build ProofForge.Backend.WasmNear.EmitWat
lake build proof-forge
scripts/contract-source/diagnostic-smoke.sh
lake env proof-forge build --target wasm-near --root . -o build/contract-source-diagnostics/near-positive --artifact-output build/contract-source-diagnostics/Counter.near-artifact.json Examples/Shared/Counter.lean
```

Result:

- Contract source target capability diagnostics and the NEAR contract_source
  positive build passed locally.

### EVM Helper Discovery Lower Plan Slice

Commit: a6a31b9

Summary:

- Moved complete-plan crosscall helper discovery into
  `Lower.buildFullModulePlan`, including planned return ABI word layouts.
- Moved complete-plan create/create2 helper discovery into
  `Lower.buildFullModulePlan`.
- Stopped `IR.buildSemanticPlan` from re-scanning crosscall/create helper specs
  after `Lower` has already built the complete semantic plan.
- Kept the existing `IR.lean` discovery helpers for incomplete/best-effort
  fallback lowering so unsupported-shape diagnostics still render through the
  compatibility path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Result:

- EVM semantic-plan helper discovery now comes from `Lower.buildFullModulePlan`
  for complete plans, while the public plan and ToYul helper behavior remain
  unchanged.

### EVM Local Array Helper Lower Plan Slice

Commit: b87d53a

Summary:

- Moved complete-plan local fixed-array getter helper discovery into
  `Lower.buildFullModulePlan`.
- Moved complete-plan nested local fixed-array getter shape discovery into
  `Lower.buildFullModulePlan`.
- Moved the checked-arithmetic flag into Lower-owned complete `ModulePlan`
  construction.
- Stopped `IR.buildSemanticPlan` from re-scanning those helper fields after
  Lower has already built the complete semantic plan.
- Kept the existing `IR.lean` discovery helpers for incomplete/best-effort
  fallback lowering.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-semantic-plan
just evm-diagnostics
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
lake build
```

Result:

- EVM semantic-plan local-array helper discovery and checked-arithmetic
  discovery now come from `Lower.buildFullModulePlan` for complete plans.
- Full `lake build` passed locally with the existing `ProofForge/Cli.lean`
  unused-variable warning.

### EVM Local Array ExprPlan-to-Yul Slice

Commit: `033c6a2 feat: move evm local array reads to toyul`

Summary:

- Added `ExprPlan.localArrayGet` dimensions so Lower can represent local
  fixed-array reads as semantic expression plans.
- Moved static, dynamic one-dimensional, and nested dynamic local scalar-array
  getter expression assembly into `ToYul`.
- Kept array literals, struct leaves, and aggregate array values on the
  compatibility fallback path.
- Reused the same `ToYul` naming/path helpers for local-array getter calls and
  the existing helper bodies to prevent naming drift.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-semantic-plan
just evm-diagnostics
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
lake build
```

Result:

- EVM local fixed-array getter expression plans lower through `ToYul`, and the
  array-value/struct-array-value Foundry smokes still pass.
- Full `lake build` passed locally with the existing `ProofForge/Cli.lean`
  unused-variable warning.

### EVM Aggregate Assignment ToYul Slice

Commit: `061956b feat: move evm aggregate assignments to toyul`

Summary:

- Added `ToYul` helpers for whole local aggregate assignment snapshot blocks,
  including scalar fixed arrays, nested fixed arrays, arrays of flat structs,
  and flat structs.
- Moved aggregate assignment temp-name selection, target local naming, and final
  Yul block construction out of the `IR.lean` compatibility facade.
- Kept aggregate assignment validation and source expansion in `IR.lean` for
  now, so this slice only moves the final statement-frame assembly behind the
  target ToYul boundary.
- Added semantic-plan tests for direct `ToYul` aggregate assignment helpers and
  an integration path through `lowerAssignStmt`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-semantic-plan
just evm-diagnostics
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
lake build
```

Result:

- Whole local aggregate assignment snapshot blocks now lower through `ToYul`.
- Array-value and struct-array-value Foundry smokes still pass.
- Full `lake build` passed locally with the existing `ProofForge/Cli.lean`
  unused-variable warning.

### EVM Dynamic Aggregate Assignment ToYul Slice

Commit: `b753bab feat: move evm dynamic aggregate assignment frames to toyul`

Summary:

- Added `ToYul` helpers for dynamic local aggregate assignment frames:
  shared index/value snapshot locals, switch cases and default revert case,
  checked-assignment RHS construction, one-dimensional switch blocks, nested
  path switch blocks, and outer value-snapshot blocks.
- Updated the `IR.lean` dynamic local fixed-array, nested fixed-array path, and
  struct-array field assignment paths to delegate the final Yul frame assembly
  to `ToYul` while keeping validation and path recursion in the compatibility
  facade.
- Added semantic-plan tests for direct `ToYul` dynamic assignment frames plus
  `lowerAssignStmt` integration for dynamic local fixed-array assignment.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-semantic-plan
just evm-diagnostics
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
lake build
```

Result:

- Dynamic local aggregate assignment switch/value snapshot frames now lower
  through `ToYul`.
- Array-value and struct-array-value Foundry smokes still pass.
- Full `lake build` passed locally with the existing `ProofForge/Cli.lean`
  unused-variable warning.

### EVM Static Local Array Assignment ToYul Slice

Commit: `d4e547d feat: move evm static array assignments to toyul`

Summary:

- Extended `ToYul.scalarAssignmentStmtPlanStatements` so
  `StmtPlan.assign`/`StmtPlan.assignOp` can target static
  `ExprPlan.localArrayGet` nodes, not only scalar locals.
- Added validation that local-array assignment targets must have a fully static
  path before `ToYul` converts them to local Yul identifiers.
- Updated `IR.lean` static local fixed-array element assignment and compound
  assignment paths to try the plan-backed target lowering first, while keeping
  the old compatibility fallback for unsupported RHS expressions.
- Added semantic-plan tests for direct `ToYul` static local-array targets plus
  `lowerAssignStmt` and `lowerAssignOpStmt` integration.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
just evm-semantic-plan
just evm-diagnostics
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-array-value-ir-smoke.sh
lake build
```

Result:

- Static local fixed-array element assignment targets now lower through
  `StmtPlan.assign`/`StmtPlan.assignOp -> ToYul`.
- Array-value and struct-array-value Foundry smokes still pass.
- Full `lake build` passed locally with the existing `ProofForge/Cli.lean`
  unused-variable warning.

### EVM Static Struct Field Assignment ToYul Slice

Commit: feature commit for EVM static struct-field assignment ToYul

Summary:

- Extended `ToYul.scalarAssignmentStmtPlanStatements` so
  `StmtPlan.assign`/`StmtPlan.assignOp` can target static local struct fields
  and static local struct-array fields, not only scalar locals and scalar
  local-array leaves.
- Generalized the static assignment target planner in `IR.lean` so compatible
  local struct-field and struct-array field assignments build
  `ExprPlan.structField` targets before final Yul emission.
- Kept dynamic aggregate field assignment frames and whole-aggregate assignment
  blocks on their existing `ToYul` helpers; this slice only moves scalar field
  targets through the narrow scalar assignment helper.
- Added semantic-plan tests for direct `ToYul` struct-field targets and
  `lowerAssignStmt` / `lowerAssignOpStmt` integration for local struct and
  static struct-array fields.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Result:

- Static local struct-field and static local struct-array field assignment
  targets now lower through `StmtPlan.assign`/`StmtPlan.assignOp -> ToYul`.
- Targeted EVM semantic-plan build and test passed locally.

### EVM Local Struct Field ExprPlan ToYul Slice

Commit: this commit

Summary:

- Added `ToYul.localStructFieldExpr` so `ExprPlan.structField` can lower local
  struct-field reads and local struct-array field reads without returning to
  the compatibility facade.
- Routed validated local struct, one-dimensional struct-array, and nested
  struct-array field read paths in `IR.lean` through
  `ExprPlan.structField -> ToYul`.
- Kept struct literals, storage-backed struct reads, and unsupported
  aggregate-value reads on their existing compatibility paths.
- Added semantic-plan tests for direct `ExprPlan.structField -> ToYul`
  lowering and `lowerExpr` integration for local struct fields and dynamic
  local struct-array fields.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Result:

- Local struct-field and local struct-array field reads now lower through
  `ExprPlan.structField -> ToYul`.
- Targeted EVM semantic-plan build and test passed locally.

### EVM Array Literal ExprPlan ToYul Slice

Commit: this commit

Summary:

- Added `ToYul.arrayGetExpr` so `ExprPlan.arrayGet` can lower scalar
  array-literal indexing directly, including static element selection and
  dynamic helper-call frames.
- Routed `IR.lean` array-literal indexing through
  `ExprPlan.arrayGet -> ToYul`, while retaining the existing out-of-bounds
  diagnostic text.
- Kept local fixed-array indexing on `ExprPlan.localArrayGet` and unsupported
  aggregate array values on compatibility/error paths.
- Added semantic-plan tests for direct static/dynamic array-literal
  `ExprPlan.arrayGet` lowering and `lowerExpr` integration.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Result:

- Scalar array-literal indexing now lowers through
  `ExprPlan.arrayGet -> ToYul`.
- Targeted EVM semantic-plan build and test passed locally.

### EVM Struct Literal Field ExprPlan ToYul Slice

Commit: this commit

Summary:

- Extended `ToYul.localStructFieldExpr` so `ExprPlan.structField` can select
  fields from `ExprPlan.structLit` bases.
- Routed `IR.lean` struct-literal field access through
  `ExprPlan.structField -> ToYul`, preserving the existing missing-field
  diagnostic text.
- Kept standalone struct literal values and storage-backed struct reads on
  their existing compatibility paths.
- Added semantic-plan tests for direct struct-literal field plans and
  `lowerExpr` integration.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
```

Result:

- Struct-literal field reads now lower through
  `ExprPlan.structField -> ToYul`.
- Targeted EVM semantic-plan build and test passed locally.

### EVM Scalar Control-Flow Body Plan Slice

Commit: cbdf5af

Summary:

- Added a planned scalar control-flow body lowering path in `IR.lean` for
  supported `StmtPlan` bodies.
- Routed `ifElse` and `boundedFor` lowering through planned bodies when every
  nested statement is in the supported scalar subset: scalar local bindings,
  local assignments, scalar storage writes/assign-ops, assertions, reverts,
  nested control flow, and scalar returns.
- Kept aggregate, map/path, crosscall, create, event, and unsupported body
  shapes on the existing compatibility fallback.
- Added semantic-plan tests that directly validate planned if/loop body
  lowering and plan construction from IR control-flow statements.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
just evm-semantic-plan
just evm-diagnostics
just evm-build-examples
just evm-foundry
lake build
git diff --check
```

Result:

- Scalar branch and bounded-loop bodies can now consume `StmtPlan` bodies
  before `ToYul`.
- EVM semantic-plan, diagnostics, example bytecode generation, Foundry smoke
  tests, full Lake build, and whitespace checks passed locally.

### EVM Aggregate Scalar Control-Flow Body Plan Slice

Commit: e149ef7

Summary:

- Extended planned scalar control-flow body lowering so static local aggregate
  scalar reads and assignment targets can stay in `StmtPlan` bodies.
- Allowed supported planned body expressions and targets for static local fixed
  array elements, local struct fields, and static local struct-array fields
  that `ToYul.scalarAssignmentStmtPlanStatements` already knows how to print.
- Added a validation guard before planned body construction so invalid
  assignment mutability/type cases fall back to the existing diagnostic path
  instead of bypassing statement validation.
- Added semantic-plan tests for planned branch bodies that assign local struct
  fields and static local-array elements, plus a guard check for immutable
  struct-field assignment.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
just evm-semantic-plan
just evm-diagnostics
just evm-build-examples
just evm-foundry
just evm-coverage
just evm-ir-smokes
lake build
git diff --check
```

Result:

- Static aggregate scalar assignments inside planned control-flow bodies now
  lower through `StmtPlan.assign` / `StmtPlan.assignOp -> ToYul`.
- EVM semantic-plan, diagnostics, example bytecode generation, Foundry smoke,
  coverage manifest, IR smokes, full Lake build, and whitespace checks passed
  locally.

### EVM Refinement Packed Storage Semantics Fix

Commit: be6695e

Summary:

- Restored the EVM refinement anchors for typed packed-storage traces by adding
  `ObservableReturn.u8` and `ObservableReturn.u128` constructors used by the
  EVM observable-return conversion path.
- Added Yul semantic support for the `not` builtin so masked packed-storage
  writes generated by `ToYul` can be replayed by the refinement interpreter.
- Kept the fix scoped to the formal-semantics anchor failure path without
  changing EVM code generation.

Validation run:

```sh
lake build ProofForge.Backend.Evm.YulSemantics ProofForge.Backend.Evm.Refinement ProofForge.Contract.Examples.ValueVaultInvariant
lake env lean --run Tests/NearWasmFormal.lean
lake build
git diff --check
```

Result:

- EVM refinement anchors, ValueVault invariant build, NEAR formal anchors, full
  Lake build, and whitespace checks passed locally.

### EVM Planned Storage Effects In Control-Flow Bodies

Commit: 40f2c96

Summary:

- Extended planned scalar control-flow body support beyond scalar storage
  writes so branch and bounded-loop bodies can lower supported map writes,
  array writes, struct-field writes, and storage-path writes/assign-ops through
  existing `EffectPlan -> ToYul` helpers.
- Added storage-path segment support checks so path keys and indexes only enter
  the planned body route when their expressions are already in the supported
  scalar-plan subset.
- Added semantic-plan tests that build real IR `ifElse`/`boundedFor` statements,
  verify they produce planned body nodes, and check map/path helper calls plus
  array/path storage write frames in the emitted Yul AST.

Validation run:

```sh
lake env lean --run Tests/EvmSemanticPlan.lean
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
just evm-semantic-plan
just evm-diagnostics
just evm-build-examples
just evm-foundry
just evm-ir-smokes
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover the storage write effects already
  represented by `StmtPlan.effect` / `EffectPlan`.
- EVM semantic-plan, diagnostics, example bytecode generation, Foundry smoke,
  IR smokes, full Lake build, and whitespace checks passed locally.

### EVM Planned Scalar Events In Control-Flow Bodies

Commit: c96bae1

Summary:

- Extended planned scalar control-flow body support so non-indexed and indexed
  scalar event emits can stay inside `StmtPlan.effect` / `EffectPlan` bodies.
- Added scalar event field support checks for `U8`/`U32`/`U64`/`U128`/`Bool`/
  `Hash`/`Address`, while keeping aggregate event flattening and indexed
  aggregate topic hashing on the existing compatibility path.
- Added semantic-plan tests that build a real IR `ifElse` with `eventEmit` and
  `eventEmitIndexed`, verify planned construction, and check the emitted Yul
  AST ends in the expected `log1`/`log2` statements.

Validation run:

```sh
lake env lean --run Tests/EvmSemanticPlan.lean
lake build ProofForge.Backend.Evm.IR ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.ToYul
just evm-semantic-plan
just evm-diagnostics
scripts/evm/event-ir-smoke.sh
just evm-ir-smokes
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover scalar event effects already represented
  by `EventPlan`.
- EVM semantic-plan, diagnostics, event IR smoke, full IR smokes, full Lake
  build, and whitespace checks passed locally.

### EVM Planned Scalar Crosscalls In Control-Flow Bodies

Commit: 07ebc5c

Summary:

- Extended planned scalar control-flow body support so scalar expression-position
  crosscalls can stay inside supported branch/loop body statements.
- Reused the existing `ExprPlan.crosscall` boundary for target, method,
  call-value, argument, and scalar return-type validation, while keeping
  aggregate crosscall argument expansion on the compatibility path.
- Added a semantic-plan regression that builds an IR `ifElse`, binds the result
  of `crosscallInvokeTyped`, assigns it back to a mutable local, verifies planned
  body construction, and checks that the lowered Yul AST calls the expected
  `__proof_forge_crosscall_1` helper.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover scalar crosscall helper-call expressions
  already represented by `ExprPlan.crosscall`.
- EVM semantic-plan, diagnostics, crosscall IR smoke, full Lake build, and
  whitespace checks passed locally.

### EVM Planned Scalar Creates In Control-Flow Bodies

Commit: 38af94d

Summary:

- Extended planned scalar control-flow body support so `crosscallCreate` and
  `crosscallCreate2` helper-call expressions can stay inside supported
  branch/loop body statements.
- Reused the existing `ExprPlan.create -> ToYul.createHelperCallExpr` boundary
  for create/create2 call-value and salt expression lowering, while leaving
  create helper discovery in `ModulePlan`.
- Added a semantic-plan regression that builds an IR `ifElse`, binds both
  `crosscallCreate` and `crosscallCreate2` results in branch bodies, verifies
  planned construction, and checks that the lowered Yul AST calls the expected
  `__proof_forge_create_*` and `__proof_forge_create2_*` helpers.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/crosscall-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover scalar create/create2 helper-call
  expressions already represented by `ExprPlan.create`.
- EVM semantic-plan, diagnostics, crosscall/create IR smoke, full Lake build,
  and whitespace checks passed locally.

### EVM Planned Map Reads In Control-Flow Bodies

Commit: 92d5bad

Summary:

- Extended plan-effect expression lowering so `EffectPlan.storageMapContains`
  and `EffectPlan.storageMapGet` can lower from planned keys inside scalar
  control-flow bodies.
- Added planned map read slot construction using `__proof_forge_map_slot` and
  `__proof_forge_map_presence_slot`, keeping key lowering on the
  `ExprPlan -> ToYul` path.
- Added a semantic-plan regression that builds an IR `ifElse`, binds
  `storageMapContains` in one branch and `storageMapGet` in the other, verifies
  planned body construction, and checks the emitted Yul AST uses the expected
  map slot helpers.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/map-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover expression-position map contains/get
  reads already represented by `EffectPlan`.
- EVM semantic-plan, diagnostics, map IR smoke, full Lake build, and whitespace
  checks passed locally.

### EVM Planned Array Reads In Control-Flow Bodies

Commit: de192b9

Summary:

- Extended plan-effect expression lowering so `EffectPlan.storageArrayRead` can
  lower from a planned index inside scalar control-flow bodies.
- Added planned array element slot construction using `__proof_forge_array_slot`,
  keeping index lowering on the `ExprPlan -> ToYul` path.
- Added a semantic-plan regression that builds an IR `ifElse`, binds
  `storageArrayRead` results in both branches, verifies planned body
  construction, and checks the emitted Yul AST uses the expected array slot
  helper under `sload`.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-array-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover expression-position storage array reads
  already represented by `EffectPlan`.
- EVM semantic-plan, diagnostics, storage-array IR smoke, full Lake build, and
  whitespace checks passed locally.

### EVM Planned Struct Reads In Control-Flow Bodies

Commit: d5bf94f

Summary:

- Extended plan-effect expression lowering so `EffectPlan.storageStructFieldRead`
  and `EffectPlan.storageArrayStructFieldRead` can lower inside scalar
  control-flow bodies.
- Added planned struct-array field slot construction using
  `__proof_forge_struct_array_slot`, keeping struct-array index lowering on the
  `ExprPlan -> ToYul` path; scalar struct field reads continue to lower to the
  resolved field slot.
- Added a semantic-plan regression that builds an IR `ifElse`, binds a scalar
  struct field read in one branch and a struct-array field read in the other,
  verifies planned body construction, and checks the emitted Yul AST uses the
  expected `sload` / struct-array slot shape.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-struct-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover expression-position struct storage reads
  already represented by `EffectPlan`.
- EVM semantic-plan, diagnostics, storage-struct IR smoke, full Lake build, and
  whitespace checks passed locally.

### EVM Planned Storage Path Reads In Control-Flow Bodies

Commit: 6e348b9

Summary:

- Extended plan-effect expression lowering so `EffectPlan.storagePathRead` can
  lower inside scalar control-flow bodies.
- Routed storage-path reads through `Plan.storagePathReadSlotPlan` and
  `ToYul.storagePathReadExprFromPlan`, while keeping the path segment
  expressions on the existing raw path value-plan boundary until a deeper typed
  path-plan slice is added.
- Added a semantic-plan regression that builds an IR `ifElse`, binds direct
  struct-field and struct-array field `storagePathRead` values in branches,
  verifies planned body construction, and checks the emitted Yul AST uses the
  expected `sload` / struct-array slot shape.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/map-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover expression-position storage path reads
  already represented by `EffectPlan`.
- EVM semantic-plan, diagnostics, storage-struct/storage-array/map IR smokes,
  full Lake build, and whitespace checks passed locally.

### EVM Planned Dynamic Local-Array Reads In Control-Flow Bodies

Commit: 713cf16

Summary:

- Extended planned scalar control-flow body support so `ExprPlan.localArrayGet`
  can lower dynamic local fixed-array reads when every path expression is in the
  scalar body subset.
- Kept static local-array reads on the direct local identifier path and routed
  dynamic reads through the existing `__proof_forge_local_array_get_N` helper
  call generated by `ExprPlan -> ToYul`.
- Added a semantic-plan regression that builds an IR `ifElse`, binds a dynamic
  local fixed-array read in one branch and a static local fixed-array read in
  the other, verifies planned body construction, and checks the emitted Yul AST
  uses the expected helper/local source.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
just evm-semantic-plan
just evm-diagnostics
scripts/evm/array-value-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover dynamic scalar local fixed-array reads
  already represented by `ExprPlan.localArrayGet`.
- EVM semantic-plan, diagnostics, array-value IR smoke, full Lake build, and
  whitespace checks passed locally.

### EVM Planned Local Struct-Array Field Reads In Control-Flow Bodies

Commit: 8ac6c8c

Summary:

- Extended `Lower.buildExprPlan` so IR expressions shaped as
  `field(arrayGet(localStructArray, index), fieldName)` lower directly to
  `ExprPlan.structField (.localArrayGet ...)` when the fixed-array leaf is a
  flat local struct.
- Reused the existing `ExprPlan -> ToYul` local struct-array field lowering:
  static indexes still read the direct field local and dynamic indexes route
  through the length-specific `__proof_forge_local_array_get_N` helper.
- Added a semantic-plan regression that builds an IR `ifElse`, binds a dynamic
  local struct-array field read in one branch and a static local struct-array
  field read in the other, verifies planned body construction, and checks the
  emitted Yul AST uses the expected helper/local source.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Lower ProofForge.Backend.Evm.IR
just evm-semantic-plan
just evm-diagnostics
scripts/evm/struct-array-value-ir-smoke.sh
lake build
git diff --check
```

Result:

- Planned control-flow bodies now cover local struct-array field reads already
  representable as `ExprPlan.structField (.localArrayGet ...)`.
- EVM semantic-plan, diagnostics, struct-array value IR smoke, full Lake build,
  and whitespace checks passed locally.

### EVM Whole Struct Storage Write EffectPlan Slice

Commit: 056eafa

Summary:

- Routed whole-struct `storageScalarWrite` statement lowering through
  `Lower.buildEffectPlan` before handing the resulting `EffectPlan` to the
  existing `ToYul.storageStructWriteEffectStmtPlanStatements` helper.
- Kept struct metadata lookup and per-field source expansion in the
  `IR.lean` compatibility facade for this slice, while removing the local
  `buildExprPlan` + manual `.storageScalarWrite` construction from the
  successful planned path.
- Added a semantic-plan regression that checks `Lower.buildEffectPlan` produces
  a `storageScalarWrite` plan for supported struct literals, including checked
  arithmetic fields and planned scalar storage reads.
- Updated the implementation backlog and Chinese backlog note to describe the
  new `Lower.buildEffectPlan -> EffectPlan -> ToYul` path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Result:

- Whole-struct storage writes now enter the same `Lower.buildEffectPlan`
  boundary as scalar, map, array, struct-field, struct-array-field, dynamic
  array, and storage-path write slices.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit` and `Cli`.

### EVM Planned Create Helper Discovery Slice

Commit: cfa8241

Summary:

- Added planned-body create/create2 helper discovery over `EntrypointPlan.body`
  `StmtPlan`/`ExprPlan` trees, including nested expression traversal through
  call values, create2 salts, storage expression targets, event word plans, and
  crosscall argument expressions.
- Routed complete `Lower.buildFullModulePlan` and
  `Lower.buildFullModulePlanWithTargetPlan` create helper specs through the
  planned entrypoint-body scanner instead of re-scanning raw portable IR
  statements.
- Kept the raw-IR `Lower.buildCreateHelperPlans` scanner available for
  incomplete/legacy plan surfaces.
- Added semantic-plan coverage proving complete plans preserve planned-body
  create helper discovery and that injected planned `create`/`create2`
  expressions are discovered even when the raw Counter IR has no create
  helpers.
- Updated the implementation backlog and Chinese backlog note to document the
  planned-body create helper discovery boundary.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Result:

- Complete EVM `ModulePlan.creates` now comes from planned
  `EntrypointPlan.body` traversal; raw IR create helper scanning is retained
  only for fallback/legacy plan surfaces.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Storage Struct Assignment Source Plan Slice

Commit: feature commit for EVM storage struct assignment source plans

Summary:

- Extended `Lower.structAssignmentSourcePlans` to accept storage-backed scalar
  struct reads and expand them into explicit `ExprPlan.storageLoad` word
  expressions using the same `Plan.requireStructState` layout source as ABI and
  crosscall storage aggregate expansion.
- Routed whole local struct assignment from `.effect (.storageScalarRead ...)`
  through the source-plan boundary before `ToYul.wholeStructAssignStmtFromPlan`
  emits the snapshot block.
- Added semantic-plan coverage for the Lower source plan, direct ToYul helper,
  and integrated `lowerAssignStmt` path.
- Updated the implementation backlog and Chinese backlog note to record that
  storage-backed scalar struct assignment sources no longer stay in the
  `IR.lean` direct-Yul compatibility path.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke storage-struct
```

Result:

- Storage-backed scalar struct assignment now enters ToYul as planned
  storage-load word expressions instead of direct `IR.lean`-assembled `sload`
  expressions on the active whole local struct assignment path.
- EVM semantic-plan tests, EVM plan tests, storage-struct IR smoke, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Struct Assignment Source Plan Slice

Commit: feature commit for EVM struct assignment source plans

Summary:

- Added `StructAssignmentSourcePlan` so flat struct whole-assignment sources can
  enter the EVM semantic-plan layer before final Yul AST construction.
- Added `Lower.structAssignmentSourcePlans` for local struct sources and struct
  literals, preserving existing validation messages and representing field
  source expressions as `ExprPlan`s.
- Added `ToYul.wholeStructAssignStmtFromPlan` and routed compatible
  `IR.lean` whole local struct assignment through that boundary.
- Kept storage-backed struct assignment sources in the compatibility facade for
  a later storage-source migration slice.
- Updated semantic-plan coverage for direct Lower source planning, direct
  ToYul snapshot-block construction from plans, and real `lowerAssignStmt`
  whole struct assignment integration.
- Updated the implementation backlog and Chinese backlog note to document the
  new struct assignment source-plan boundary.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke struct-value
```

Result:

- Local struct and struct-literal whole assignment sources now enter ToYul as
  planned field expressions instead of direct Yul expressions assembled by the
  compatibility facade.
- EVM semantic-plan tests, EVM plan tests, struct-value IR smoke, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Planned Local-Array Helper Discovery Slice

Commit: 387e6d0

Summary:

- Added planned-body local fixed-array helper discovery over
  `EntrypointPlan.body` `StmtPlan`/`ExprPlan` trees.
- Routed complete `Lower.buildFullModulePlan` and
  `Lower.buildFullModulePlanWithTargetPlan` `localArrayGetLengths` and
  `nestedLocalArrayGetShapes` through the planned entrypoint-body scanner
  instead of re-scanning raw portable IR statements.
- Covered planned dynamic `ExprPlan.localArrayGet` paths, nested local-array
  shapes, dynamic array-literal getters, event word plans, storage expression
  targets, and crosscall/create argument expressions.
- Kept `Lower.buildLocalArrayGetLengths` and
  `Lower.buildNestedLocalArrayGetShapes` as incomplete/legacy plan fallback
  sources used by `lowerModuleWithPlan`.
- Tightened the complete plan helper set for `EvmArrayValueProbe`: planned
  discovery now emits the nested `[2, 2]` helper without the legacy raw
  scanner's extra standalone length-2 row helper.
- Updated the implementation backlog and Chinese backlog note to document the
  planned-body local-array helper discovery boundary.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Result:

- Complete EVM `ModulePlan.localArrayGetLengths` and
  `ModulePlan.nestedLocalArrayGetShapes` now come from planned
  `EntrypointPlan.body` traversal; raw IR local-array helper scanning is
  retained only for fallback/legacy plan surfaces.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Planned Checked Arithmetic Discovery Slice

Commit: cade659

Summary:

- Added planned-body checked-arithmetic discovery over `EntrypointPlan.body`
  `StmtPlan`/`ExprPlan` trees, including nested expression traversal,
  planned `.checkedArith` expressions, planned `assignOp` nodes, storage
  assign-op effects, storage expression targets, event word plans, and
  crosscall/create argument expressions.
- Routed complete `Lower.buildFullModulePlan` and
  `Lower.buildFullModulePlanWithTargetPlan` `usesCheckedArithmetic` through
  the planned entrypoint-body scanner instead of re-scanning raw portable IR
  statements.
- Kept `Validate.moduleUsesCheckedArithmetic` as the incomplete/legacy plan
  fallback source used by `lowerModuleWithPlan`.
- Added semantic-plan coverage proving complete plans preserve planned-body
  checked-arithmetic discovery and that injected planned `.checkedArith` and
  `assignOp` bodies are detected even when the raw native-transfer IR has no
  checked arithmetic.
- Updated the implementation backlog and Chinese backlog note to document that
  local fixed-array getter discovery remains a separate follow-up slice.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Result:

- Complete EVM `ModulePlan.usesCheckedArithmetic` now comes from planned
  `EntrypointPlan.body` traversal; raw IR checked-arithmetic scanning is
  retained only for fallback/legacy plan surfaces.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Dynamic Local Assignment ExprPlan Slice

Commit: f5e6c00

Summary:

- Routed dynamic local aggregate assignment snapshot expressions through
  `Lower.buildExprPlan -> ExprPlan -> ToYul` before emitting the shared
  `ToYul` switch frames.
- Covered dynamic fixed-array assignment, dynamic fixed-array compound
  assignment, dynamic struct-array field assignment, and dynamic struct-array
  field compound assignment.
- Kept path resolution and local aggregate target validation in the `IR.lean`
  compatibility facade for this slice, while moving dynamic index/value
  expression lowering out of direct `IR.lowerExpr` calls.
- Updated the implementation backlog and Chinese backlog note to record the
  planned snapshot-expression boundary.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Result:

- Dynamic local aggregate assignment switch frames now consume planned
  index/value snapshot expressions before `ToYul` emits the snapshot locals,
  switch default, checked-assignment RHS, and case bodies.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Local Array Getter ExprPlan Slice

Commit: bb013e9

Summary:

- Routed direct expression-position local fixed-array reads through
  `Lower.buildExprPlan` when the plan is a `.localArrayGet`, then reused the
  existing `ExprPlan -> ToYul` lowering for static and dynamic local-array
  helper-call assembly.
- Kept unsupported aggregate local-array leaves and array-literal fallback
  behavior on the existing compatibility path, preserving the current explicit
  diagnostics for struct-array element reads that require field access.
- Added a semantic-plan regression for a direct local-array read with a
  checked-add dynamic index, proving the direct `IR.lowerExpr` entrypoint now
  consumes the planned index expression before helper-call emission.
- Updated the implementation backlog and Chinese backlog note so the documented
  local-array getter boundary matches the active lowering path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Result:

- Direct local fixed-array reads now use the same `Lower.buildExprPlan ->
  ExprPlan.localArrayGet -> ToYul` route as planned control-flow and helper
  discovery paths.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Struct Field Getter ExprPlan Slice

Commit: 0782c9d

Summary:

- Routed direct expression-position local struct-field reads through
  `Lower.buildExprPlan` when the plan is a supported `.structField`, then reused
  the existing `ExprPlan -> ToYul` lowering for local structs, struct literals,
  and local struct-array leaves.
- Preserved storage-backed struct reads, nested local fixed-array struct leaves,
  and unsupported aggregate fallback behavior on the compatibility path.
- Added semantic-plan regressions for direct local struct-field planning and a
  dynamic local struct-array field read whose checked-add index must lower
  through `ExprPlan` before helper-call emission.
- Updated the implementation backlog and Chinese backlog note so the documented
  struct-field getter boundary matches the active lowering path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Result:

- Direct local struct-field reads now use the same `Lower.buildExprPlan ->
  ExprPlan.structField -> ToYul` route as planned control-flow and local-array
  getter paths.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Array Literal Getter ExprPlan Slice

Commit: b211189

Summary:

- Routed direct expression-position scalar array-literal reads through
  `Lower.buildExprPlan` when the plan is `.arrayGet (.arrayLit ..) index`, then
  reused the existing `ExprPlan -> ToYul` lowering for static selection and
  dynamic helper-call assembly.
- Added an isolated semantic-plan regression that asserts the complete
  array-literal get expression lowers to an `ExprPlan.arrayGet` with an
  `ExprPlan.arrayLit` base and a checked-add index before `IR.lowerExpr`
  delegates helper-call emission to `ToYul`.
- Kept aggregate array values and unsupported local-array leaf fallbacks on the
  compatibility path.
- Updated the implementation backlog and Chinese backlog note so the documented
  array-literal getter boundary matches the active lowering path.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Result:

- Direct scalar array-literal reads now use the same `Lower.buildExprPlan ->
  ExprPlan.arrayGet/arrayLit -> ToYul` route as the local-array and struct-field
  getter paths.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Storage Path Target ExprPlan Slice

Commit: 07c1534

Summary:

- Routed the compatibility `lowerStoragePathWriteTarget` helper through
  `Lower.buildStoragePathPlan -> StoragePathWriteExprTargetPlan -> ToYul`
  instead of the older `StoragePathWriteTargetPlan`/`ValuePlan` path.
- Added a semantic-plan regression that asserts a raw map storage path segment
  becomes a typed `StoragePathPlanSegment.mapKey` carrying a checked-add
  `ExprPlan`, then verifies the compatibility target helper lowers that typed
  target to the expected checked-add Yul key.
- Updated the implementation backlog and Chinese backlog note so the documented
  storage-path boundary reflects the active typed path-segment planning route.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
scripts/i18n/check-sync.sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Result:

- Compatibility storage-path write target lowering now consumes the same typed
  path-segment `ExprPlan` route as planned storage-path write/assign-op effects.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Storage Path Read ExprPlan Slice

Commit: dbdae98

Summary:

- Routed the compatibility `lowerStoragePathReadExprTarget` helper through
  `Lower.buildStoragePathPlan -> StorageSlotExprPlan -> ToYul` instead of the
  older `StorageSlotPlan`/`ValuePlan` path.
- Updated expression-position `storagePathRead` handling in `lowerPlanEffectExpr`
  so raw path segment expressions are typed as `StoragePathPlanSegment` values
  before final `sload` assembly.
- Added semantic-plan regressions proving a raw map-key read path carries a
  checked-add `ExprPlan` key and that raw expression/effect read compatibility
  paths lower that key through the planned `__pf_checked_add` Yul helper.
- Updated the implementation backlog and Chinese backlog note so read and write
  storage-path compatibility routes both document the typed path-segment
  boundary.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
lake build
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
just evm-diagnostics
git diff --check
```

Result:

- Compatibility storage-path read lowering now consumes the same typed
  path-segment `ExprPlan` route as planned storage-path read/write effects.
- EVM semantic-plan tests, EVM plan tests, event/counter IR smokes, EVM
  diagnostics, i18n sync, JSON validation, full Lake build, and whitespace
  checks passed locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Dynamic Array TargetPlan Slice

Commit: eac5609

Summary:

- Added `DynamicArrayTargetPlan` and target `EffectPlan` variants for
  dynamic-array push/pop root-slot planning.
- Routed successful `Lower.buildEffectPlan` dynamic-array push/pop effects
  through `DynamicArrayTargetPlan -> ToYul` helpers, so root-slot selection and
  dynamic slot helper assembly no longer come from `IR.lean` callbacks.
- Kept the old callback helpers for legacy/fallback variants while planned body
  lowering and direct effect statements consume the target helper path.
- Added semantic-plan regressions for Lower target variants and direct ToYul
  target helper assembly.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
```

Result:

- Dynamic-array push/pop success paths now use target semantic plans for
  root-slot and slot-helper assembly.
- EVM semantic-plan tests, i18n sync, JSON validation, EVM IR build, and
  whitespace checks passed locally.

### EVM Event Statement Lower Plan Slice

Commit: fb5a58e

Summary:

- Routed the compatibility `lowerEventEmitCoreStmt` facade through
  `Lower.buildEffectPlan` for portable `eventEmit`/`eventEmitIndexed` effects
  instead of reconstructing `EventPlan` and field value source plans in
  `IR.lean`.
- Restricted that facade to the word-planned `eventEmitWords` and
  `eventEmitIndexedWords` effects before delegating final event block assembly
  to `ToYul.eventEffectStmtPlanStatements`.
- Added semantic-plan regressions proving ordinary and indexed portable event
  statements lower to word-planned event effects before the compatibility facade
  emits Yul.
- Updated the implementation backlog and Chinese backlog note to reflect the
  new event statement entrypoint boundary.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmPlan.lean
scripts/evm/event-ir-smoke.sh
just evm-diagnostics
git diff --check
```

Result:

- Ordinary and indexed event statements now enter the same
  `Lower.buildEffectPlan -> event word plans -> ToYul` path as planned-body
  event effects.
- EVM semantic-plan tests, EVM plan tests, event IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Aggregate Crosscall Return Plan Slice

Commit: edd45b1

Summary:

- Added `ToYul.crosscallAggregateReturnAssignmentPlanStatement` so aggregate
  crosscall return plans own target/method/call-value lowering, planned argument
  word traversal, helper-call selection, argument ordering, and multi-return
  assignment construction behind the ToYul plan boundary.
- Routed `IR.lowerCrosscallReturnAssignmentPlan` through that helper, leaving
  `IR.lean` responsible only for local/storage crosscall word-source provider
  callbacks.
- Added semantic-plan coverage for provider-backed aggregate crosscall return
  assignment plans with local aggregate argument words plus scalar literal
  argument words.
- Updated the implementation backlog and Chinese backlog note to record the new
  aggregate crosscall return assignment boundary.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
just evm-smoke crosscall
git diff --check
```

Result:

- Aggregate crosscall return assignment now flows through
  `CrosscallReturnAssignmentPlan -> ToYul` for helper-call and assignment frame
  construction.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Storage Crosscall WordPlan Slice

Commit: 4a5c5bd

Summary:

- Changed storage-backed struct crosscall arguments so `Lower` preserves the
  already computed storage word plans as explicit
  `CrosscallArgWordPlan.expr (.storageLoad ...)` entries.
- Removed the active-path need to carry a provider-backed
  `CrosscallArgWordPlan.storage` source marker for storage-backed struct
  crosscall arguments.
- Updated semantic-plan coverage for planned-body crosscall returns and direct
  scalar expression crosscalls to assert storage-backed aggregate arguments
  carry concrete storage-load word plans.
- Updated the implementation backlog and Chinese backlog note to record the
  storage crosscall source boundary change.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
just evm-smoke crosscall
git diff --check
```

Result:

- Storage-backed aggregate struct crosscall arguments now enter ToYul as
  planned storage-load word expressions instead of storage source callbacks on
  the active Lower path.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Local Crosscall WordPlan Slice

Commit: 374d5fb

Summary:

- Added `Lower.localCrosscallWordPlans` so local aggregate crosscall arguments
  expand into explicit planned local word expressions before ToYul.
- Routed local struct and fixed-array crosscall argument lowering through
  `CrosscallArgWordPlan.expr (.local ...)` word plans instead of active-path
  `CrosscallArgWordPlan.local` provider markers.
- Updated semantic-plan coverage for planned-body crosscall returns and direct
  scalar expression crosscalls to assert local aggregate arguments carry
  concrete local word plans.
- Updated the implementation backlog and Chinese backlog note to record the
  local crosscall source boundary change.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake build
lake env lean --run Tests/EvmPlan.lean
just evm-diagnostics
just evm-smoke crosscall
git diff --check
```

Result:

- Local aggregate crosscall arguments now enter ToYul as planned local word
  expressions instead of local source callbacks on the active Lower path.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.

### EVM Storage Fixed-Array Crosscall WordPlan Slice

Commit: ad2602a

Summary:

- Extended `Lower.storageCrosscallWordPlans` so storage-backed fixed arrays can
  expand into explicit planned storage-load word expressions before ToYul.
- Routed crosscall fixed-array arguments that are assembled from storage array
  reads through the same storage-backed source recognition used by ABI return
  and event planning.
- Added semantic-plan coverage for scalar storage arrays and struct storage
  arrays as typed crosscall arguments, including concrete `arraySlot` and
  `structArrayFieldSlot` word plans.
- Updated the implementation backlog and Chinese backlog note to record that
  storage-backed struct and fixed-array crosscall arguments are now expanded on
  the active Lower path.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
git diff --check
```

Result:

- Storage-backed fixed-array and struct-array crosscall arguments now enter
  ToYul as planned storage-load word expressions instead of per-element storage
  read expressions or provider-backed source markers on the active Lower path.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The first concurrent validation attempt hit a transient empty
  `.lake/build/ir/ProofForge/Cli.setup.json`; the sequential `lake build`
  rerun passed. The full Lake build still reports pre-existing unused-variable
  warnings in `ConstructorInit`, `Quint`, and `Cli`.

### EVM Planned Crosscall Helper Discovery Slice

Commit: 5df7ae0

Summary:

- Added planned-body crosscall helper discovery over `EntrypointPlan.body`
  `StmtPlan`/`ExprPlan` trees, including nested expression traversal,
  planned argument word arity, return word layout, and native-transfer
  detection.
- Routed complete `Lower.buildFullModulePlan` crosscall helper specs through
  the planned entrypoint-body scanner instead of re-scanning raw portable IR
  statements.
- Kept the raw-IR `Lower.buildCrosscallHelperPlans` scanner available for
  incomplete/legacy plan surfaces.
- Added semantic-plan coverage proving complete plans preserve the planned-body
  crosscall helper scan and that an injected planned entrypoint crosscall is
  discovered even when the raw IR has no crosscall.
- Updated the implementation backlog and Chinese backlog note to document the
  planned-body helper discovery boundary.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmSemanticPlan.lean
lake env lean --run Tests/EvmPlan.lean
lake build
just evm-diagnostics
just evm-smoke crosscall
```

Result:

- Complete EVM `ModulePlan.crosscalls` now comes from planned
  `EntrypointPlan.body` traversal; raw IR crosscall helper scanning is retained
  only for fallback/legacy plan surfaces.
- EVM semantic-plan tests, EVM plan tests, crosscall IR smoke, EVM diagnostics,
  i18n sync, JSON validation, full Lake build, and whitespace checks passed
  locally.
- The full Lake build still reports pre-existing unused-variable warnings in
  `ConstructorInit`, `Quint`, and `Cli`.
