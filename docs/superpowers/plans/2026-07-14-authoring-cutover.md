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
- Production normalization is owned by `Frontend.Authored.Normalize` behind
  the single `Frontend.ContractSpec.normalize` facade. No production module
  imports `IR.Legacy.Adapter`, but the authored exchange value is still
  `ContractSpec` containing `IR.Module` and must be replaced before A-CUT2 is
  complete.
- The independent frontend type/syntax model is owned by
  `Frontend.Authored`. `Frontend.Surface.Type` and `.Syntax` now contain only
  temporary aliases for compiler fixtures and may not own new constructors.
- Validation and direct checked-Core normalization are owned by
  `Frontend.Authored.Validate` and `Frontend.Authored.Canonicalize`.
  `Frontend.Surface.Normalize` is only a temporary fixture facade.
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

### A-CUT1d - Optional formal namespace alignment

- Keep `ProofForgeFormal` as a sibling of `ProofForge`. This is intentional:
  the directory boundary mirrors the separate Lake libraries and prevents
  powdr, solanalib, mathlib, and their transitive dependencies from entering
  the default compiler/CLI library.
- Rename declarations owned by `ProofForgeFormal/Evm` from
  `ProofForge.Backend.Evm.*` to `ProofForgeFormal.Evm.*`.
- Rename declarations owned by `ProofForgeFormal/Solana` from
  `ProofForge.Backend.Solana.*` to `ProofForgeFormal.Solana.*`.
- Update focused proof tests, scripts, and documentation to use the new module
  namespaces. Do not add compatibility aliases under `ProofForge.Backend`.
- Enforce the dependency direction: optional formal libraries may import
  `ProofForge`, while the default `ProofForge` library may not import
  `ProofForgeFormal`.

Acceptance: `lake build ProofForgeFormalEvm ProofForgeFormalSolana` and the
focused EVM/Solana refinement smokes pass; a repository scan finds no
`ProofForge.Backend.Evm.*` or `ProofForge.Backend.Solana.*` namespace declared
inside `ProofForgeFormal/**`; the default compiler roots contain no
`import ProofForgeFormal.*`.

Status (2026-07-14): done. All optional proof declarations use their
`ProofForgeFormal` owner namespaces; the EVM and Solana focused proof targets
and runtime smokes pass, and the canonical boundary gate enforces the namespace
and one-way import rules. Continue with A-CUT2.

### A-CUT1e - Solana source and target ownership cutover

The old top-level `ProofForge/Solana*` placement has already been removed, but
the move is not an architectural cutover by itself. The public
`ProofForge.Contract.Source.Solana` module and its `Internal` implementation
still import `Source.Solana.Legacy`, whose values construct the old
`Contract.Builder` / `IR.Module` path. Complete this task before resuming the
remaining A-CUT2 builder work.

- Keep `ProofForge.Contract.Source.Solana` as the opt-in public syntax layer.
  It may define macros and author-facing references, but it must not own target
  planning, sBPF lowering, or compatibility builders.
- Add `ProofForge.Target.HostOps.Solana` as the stable Solana capability
  catalog. Host-operation identity, version, signature, and capability
  discovery belong here so both the frontend and backend depend on a neutral
  target protocol rather than importing each other.
- Encode Solana-only account, PDA, CPI, sysvar, return-data, allocator, and
  runtime operations as open authored HostOps. Do not add closed Solana
  constructors to the common Authored or Canonical Core expression/statement
  enums.
- Keep payload validation, account-layout resolution, plan construction, and
  sBPF materialization under `ProofForge.Backend.Solana.Extension` and the
  existing Solana plan modules.
- Remove imports of `Source.Solana.Legacy` from the public Source module and
  `Source.Solana.Internal`. Old fixtures and Learn compatibility may remain
  temporarily, but must import the Legacy module explicitly and are deleted in
  IR-B5/A-CUT5 after their caller count reaches zero.
- Keep `ProofForge.Runtime.Psy` unchanged. Psy externs are runtime intrinsics,
  not Solana authoring or backend code.

Acceptance: the public Solana Source module elaborates representative account,
PDA, and CPI fixtures into authored HostOps without constructing
`ContractSpec` or `IR.Module`; neither `Contract.Source.Solana` nor its
`Internal` module imports `Source.Solana.Legacy`; the Solana target catalog and
focused canonical boundary tests pass. This task establishes ownership and the
direct frontend seam; full deletion of every legacy Solana fixture remains
tracked by IR-B5 and A-CUT5.

Checkpoint (2026-07-14): A-CUT1e-a and A-CUT1e-b are complete. Canonical and Authored
materialization intents carry the open `CapabilityOperation` identity rather
than a closed target enum or untyped Canonical label. The initial typed Solana
catalog registers remaining-compute-units and the three Solana hash syscalls,
and `solana-sbpf-asm` advertises exact versioned IDs. A target-neutral operation
payload carrier now preserves typed fields without interpreting target names.
Solana owns versioned account-declare, PDA-derive, and CPI-invoke schemas with
strict decoders, and its internal direct Authored adapter emits those payloads
without importing `Contract.Builder`, `IR.Module`, Surface, or Solana Legacy.
Canonical validation rejects duplicate/empty payload fields; the checked Solana
parser rejects malformed schemas and never reinterprets them as legacy metadata.
Canonical and target-plan validation reject unknown or foreign operation IDs.
Switching the public/internal macro implementations off the legacy builder and
deleting their Legacy imports remain in A-CUT1e-c.

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

Checkpoint (2026-07-14): the helper namespace replacement and normalizer
ownership move are complete. Public
authors import only `ProofForge.Contract.Source`; implementation helpers live
under `Contract.Source.Internal`, Solana helpers under
`Contract.Source.Solana.Internal`, and direct AST materializers under
`Frontend.Materialize`. The production normalizer now lives under
`Frontend.Authored.Normalize`; `ProofForge.IR` no longer imports it and the
production Legacy import baseline is empty. The independent final source model
now lives under `Frontend.Authored.{Type,Syntax}`; the Surface type/syntax files
are compatibility aliases only, and `normalizeAuthored` reaches checked
Canonical Core without `IR.Contract`. A-CUT2e-a added explicit HostOp result
types and declared-error references with typed runtime arguments; Canonical
validation rejects signature and error-argument mismatches. A-CUT2e-b added
target-neutral logical storage paths, nested-map state, contains/remove/length/
resize operations, and explicit memory allocation/store/release. Replacing the
Source builder and the remaining `ContractSpec`/`IR.Module` authored exchange
value are still pending in A-CUT2. A-CUT2e-c completed the target-neutral
crosscall schema: direct Authored normalization now preserves invoke, static,
delegate, named, and continuation modes together with optional gas/value,
typed arguments, JSON argument names, and return type. ABI serialization and
receipt scheduling remain target-owned. A-CUT2e-d preserves structure field
ownership, record semantics, visibility/storage-layout metadata, and authored
Quint/Lean annotations instead of defaulting them during direct normalization.
A-CUT2f-a establishes `Frontend.Authored.Builder` as the direct compiler-owned
builder and proves a Counter-shaped contract reaches checked Canonical Core
without importing `Contract.Builder` or constructing `IR.Module`. A-CUT2f-b
adds the missing target-neutral Boolean Core operation so authored `boolAnd`
and `boolOr` no longer depend on the closed Legacy expression tree; all three
primary canonical plans consume it. A-CUT2f-c closes the event-schema gap: the
direct builder can attach field names, types, indexing, and interface ABI
metadata at emit sites; normalization infers one deterministic contract schema,
rejects conflicting emits, and emits matching Canonical Core and Interface event
declarations. Existing explicitly declared events remain supported for compiler
fixtures.

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

- Delete `Frontend.ContractSpec.Normalize`, the transitional
  `Frontend.Authored.Normalize` implementation,
  Legacy backend plan modules, compatibility constructors, and freeze
  allowlists after caller count reaches zero.
- Move any historical parity fixture that remains useful out of production
  imports; delete obsolete dual-run gates.
- Keep target backends consuming only checked Canonical Core plus target-owned
  plans/HostOps.

Acceptance: production `ProofForge/**` contains no `IR.Legacy` import or
compatibility-normalization call, the CLI cannot select a Legacy pipeline, and primary-triad
product gates pass from the single author source.

## Commit Discipline

Commit each A-CUT task after targeted verification. Do not start NEAR-R2 until
A-CUT1 through A-CUT5 are complete. Do not solve a failing product by copying
its logic into a target-specific or Canonical product directory.
