# Unified Contract Authoring Cutover

Date: 2026-07-14

## Decision

`Examples/Product/*.lean` is the only authored product source tree. A product
must remain target-neutral and use the `contract_source` syntax. Target choice
changes materialization only; it must not select a second handwritten contract.

`ProofForge.Frontend.Surface` is an internal normalization AST. Users and
product examples must not import it, construct `SurfaceContract`, or depend on
its constructors. `Canonical Core` is also compiler-owned output, not a second
authoring language.

There is one current source format. Public diagnostics and artifact metadata
must not advertise `v1`, `v2`, `legacyV1`, `surfaceV2`, or `surface-v2` after
the cutover.

## Verified Current State

- `contract_source` expands to `ContractSpec` and `IR.Module` in
  `ProofForge/Contract/Source.lean`.
- Production `Frontend.ContractSpec.normalize` still calls
  `IR.Legacy.Adapter.adaptLegacy`.
- The former `Examples/Product/Canonical` handwritten Surface duplicates have
  been isolated as temporary tests in `TestFixtures/SurfaceProducts`.
  They are not product sources and remain only until A-CUT3 reaches feature
  parity from the single authored contracts.
- The temporary EVM fixture route still compiles those internal AST values,
  while NEAR and Solana compile the original product source.
- `Compiler.LoadedContractSource` and `Cli.ContractLoader` retain two internal
  input shapes during migration: authored `ContractSpec` and temporary Surface
  fixtures. They no longer expose those shapes as public source versions.
- Backend goldens have been removed from `Examples/Product`; live expectations
  now reside under `Examples/Backend/<Target>`.

## Required Sequence

### A-CUT1 - Internal frontend boundary

- Keep `Frontend.Surface` compiler-internal.
- Move helper modules out of public `Contract.SurfaceV2` ownership.
- Add an import-boundary gate: files below `Examples/Product` and public
  `ProofForge.Contract.Source*` modules may not import `Frontend.Surface`.
- Keep direct Surface values only in explicit compiler test fixtures, never in
  the Product tree.

Acceptance: the boundary gate passes and no new public Surface authoring path is
introduced.

### A-CUT1c - Optional formal-library ownership

- Keep target-independent executable refinement interfaces in
  `ProofForge/Backend/Refinement` and target-owned, mathlib-free refinement
  seams in `ProofForge/Backend/<Target>/Refinement`.
- Keep proofs that import powdr EVM semantics or solanalib in the independent
  `ProofForgeFormalEvm` and `ProofForgeFormalSolana` Lake libraries, under the
  shared module root `ProofForgeFormal/{Evm,Solana}`.
- Do not place these heavyweight proof modules inside the default `ProofForge`
  library, and do not restore unrelated top-level roots named
  `EvmRefinement` or `SolanaRefinement`.

Acceptance: the default compiler library imports neither optional formal
library, while both focused formal targets build independently.

Status (2026-07-14): done at `52742ff5`. This ownership cleanup precedes
A-CUT2; it does not change portable IR or public contract authoring.

### A-CUT2 - Direct `contract_source` frontend

- Preserve the existing user syntax, including the Counter source exactly as a
  target-neutral business contract.
- Change macro output from `ContractSpec`/`IR.Module` to one compiler-owned
  authored-contract value that normalizes directly to checked Canonical Core.
- Preserve invariants, liveness declarations, entrypoint mutability, ABI
  overrides, constructor declarations, intents, mixin composition, and target
  extension HostOps without constructing Legacy IR.
- Replace the public `ProofForge.Contract.Surface` helper name with Source DSL
  operations owned by the single authoring API. `Surface` must name only the
  compiler-internal normalization representation, never contract code.
- Resolve target ABI selectors during target planning, not in product source.

Acceptance: `Examples/Product/Counter.lean` reaches EVM, Solana, and NEAR Core
plans without importing or invoking `IR.Legacy.Adapter`.

Checkpoint (2026-07-14): the helper namespace replacement is complete. Public
authors import only `ProofForge.Contract.Source`; implementation helpers live
under `Contract.Source.Internal`, Solana helpers under
`Contract.Source.Solana.Internal`, and direct AST materializers under
`Frontend.Materialize`. The direct Canonical Core normalization and removal of
the remaining Legacy adapter call are still pending in A-CUT2.

### A-CUT3 - Product migration

- Migrate every `catalog.json` source through the direct frontend.
- Product files remain chain-neutral. EVM/ERC, NEAR/NEP, and Solana SDK details
  live in intent materializers, target HostOps, target profiles, or backend
  fixtures.
- Collection abstractions such as Queue and Set become public DSL/stdlib
  features used from the product source, not standalone handwritten Surface
  products.
- Migrate every Product caller away from the transitional
  `ProofForge.Contract.Surface` namespace before deleting that compatibility
  module.

Acceptance: the complete catalog compiles from `Examples/Product/<file>` for
every advertised target; focused target gates preserve existing behavior.

### A-CUT4 - Delete duplicate source and version split

- Delete the temporary `TestFixtures/SurfaceProducts` values and their
  allowlist entries.
- Repoint EVM product gates to `Examples/Product`.
- Replace `LoadedContractSource.legacyV1/surfaceV2` with one current source
  variant, then remove dual-source ambiguity diagnostics.
- Replace public `surface-v2` and `contract_source-v1/v2` metadata with one
  stable `contract-source` identity. Versioning, if later needed, belongs in a
  schema field and must not create two production compiler routes.

Acceptance: repository search finds no Product/Canonical route and no public
V1/V2 source branch.

Checkpoint (2026-07-14): the public version split is removed. Loader cases are
named `authored` and `surfaceFixture`, SDK/source metadata uses the single
`contract-source` identity, and diagnostics describe Surface values as internal
migration fixtures. Deleting `TestFixtures/SurfaceProducts` remains blocked on
A-CUT3 feature parity, so A-CUT4 is not yet complete.

### A-CUT5 - Delete Legacy production code

- Delete `Frontend.ContractSpec.Normalize`, production `adaptLegacy` callers,
  Legacy backend plan modules, compatibility constructors, and freeze
  allowlists after caller count reaches zero.
- Move any historical parity fixture that remains useful out of production
  imports; delete obsolete dual-run gates.
- Keep target backends consuming only checked Canonical Core plus target-owned
  plans/HostOps.

Acceptance: production `ProofForge/**` contains no `IR.Legacy` import or
`adaptLegacy` call, the CLI cannot select a Legacy pipeline, and primary-triad
product gates pass from the single author source.

## Commit Discipline

Commit each A-CUT task after targeted verification. Do not start NEAR-R2 until
A-CUT1 through A-CUT5 are complete. Do not solve a failing product by copying
its logic into a target-specific or Canonical product directory.
