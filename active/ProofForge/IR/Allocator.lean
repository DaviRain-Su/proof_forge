/-! Allocator abstraction for the ProofForge IR.

The IR is target-agnostic; how composite values (arrays, structs, path
temporaries) are allocated in the target's address space is modeled once as a
chain-neutral `AllocatorModel` (strategy / region / release triple), then bound
per target. Every backend reads `Module.allocator` and lowers the matching
allocator helpers.

See `docs/rfcs/0008-allocator-abstraction.md` for the full design and per-target
bindings (EVM bump-over-call-scratch, Solana heap, NEAR/CosmWasm Wasm linear
memory).

## Strategy families

* `bump` / `bumpReset` — no-free deployment strategies. `dealloc` is a no-op.
  These are useful when a module has no explicit `release` statements.
  - `bump`      — linear frontier, no reset.
  - `bumpReset` — bump + reset the frontier to the region base at each
    entrypoint boundary.

* `freeList` — reuse-capable deployment strategy. Supports `Statement.release`
  by returning memory to a free list. NEAR's `nearWeeModel` and the direct-WAT
  `minimalMalloc` both bind to this family; they differ only in historical
  naming, not in the abstract model.

* `hostImport` — chain or host provides an allocator ABI. CosmWasm's exported
  `allocate`/`deallocate` region ABI binds here; offline experiments also use
  host-provided allocators, distinguished by `hostProvided = true`.

## Release semantics

* `none`  — `Statement.release` is rejected by the backend.
* `noop`  — `Statement.release` is allowed but lowers to nothing. EVM uses this
  once ownership soundness (FV-3) justifies it; Solana uses it today.
* `reuse` — `Statement.release` lowers to a real deallocator (free-list, host
  import, etc.).

## Out of scope (intentionally chain-specific)

Persistent-state models (EVM storage, Solana accounts, NEAR storage) are not
part of the allocator abstraction. -/

namespace ProofForge.IR

/-- Semantic allocation family. -/
inductive AllocatorStrategy where
  | bump
  | bumpReset
  | freeList
  | hostImport
  deriving Repr, BEq, DecidableEq, Inhabited

def AllocatorStrategy.id : AllocatorStrategy → String
  | .bump => "bump"
  | .bumpReset => "bump_reset"
  | .freeList => "free_list"
  | .hostImport => "host_import"

/-- Address-space region facts. `size?` is the fixed bound when known; `growable`
allows `memory.grow`/page expansion. -/
structure AllocatorRegion where
  base : Nat := 60000
  size? : Option Nat := none
  growable : Bool := true
  deriving Repr, BEq, DecidableEq, Inhabited

/-- What `Statement.release` means for this module/target binding. -/
inductive AllocatorRelease where
  | none
  | noop
  | reuse
  deriving Repr, BEq, DecidableEq, Inhabited

def AllocatorRelease.id : AllocatorRelease → String
  | .none => "none"
  | .noop => "noop"
  | .reuse => "reuse"

/-- Chain-neutral allocator model: strategy × region × release. `hostProvided`
is true when `alloc`/`dealloc` come from a host import (offline experiments);
chain-deployed bindings are wasm-internal or chain-exported and set this to
false. -/
structure AllocatorModel where
  strategy : AllocatorStrategy
  region : AllocatorRegion
  release : AllocatorRelease
  hostProvided : Bool := false
  deriving Repr, BEq, DecidableEq, Inhabited

def AllocatorModel.id (model : AllocatorModel) : String :=
  let base := s!"base={model.region.base}"
  let host := if model.hostProvided then ";host" else ""
  s!"alloc.{model.strategy.id}.{model.release.id};{base}{host}"

/-- Per-module allocator configuration. Backends read `model` and the derived
helpers below to emit the matching alloc/dealloc helpers. -/
structure AllocatorConfig where
  model : AllocatorModel := { strategy := .bump, region := {}, release := .none }
  deriving Repr, BEq, DecidableEq, Inhabited

/-- Default configuration: a plain bump allocator at offset 60000. -/
def defaultAllocator : AllocatorConfig := { model := { strategy := .bump, region := {}, release := .none } }

-- Preset constructors that map the old Wasm-flavored enum names onto the shared
-- strategy/region/release triple. These keep existing target profiles and test
-- fixtures compiling while expressing the same facts in the unified model.

def AllocatorConfig.bump (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .bump,
      region := { base := heapBase, growable := true },
      release := .none
    } }

def AllocatorConfig.bumpReset (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .bumpReset,
      region := { base := heapBase, growable := true },
      release := .none
    } }

def AllocatorConfig.nearWeeModel (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .freeList,
      region := { base := heapBase, growable := true },
      release := .reuse
    } }

def AllocatorConfig.minimalMalloc (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .freeList,
      region := { base := heapBase, growable := true },
      release := .reuse
    } }

def AllocatorConfig.cosmWasmRegion (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .hostImport,
      region := { base := heapBase, growable := true },
      release := .reuse
    } }

def AllocatorConfig.hostBump (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .bump,
      region := { base := heapBase, growable := true },
      release := .none,
      hostProvided := true
    } }

def AllocatorConfig.hostJemallocShape (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .freeList,
      region := { base := heapBase, growable := true },
      release := .reuse,
      hostProvided := true
    } }

def AllocatorConfig.hostMimallocShape (heapBase : Nat := 60000) : AllocatorConfig :=
  { model := {
      strategy := .freeList,
      region := { base := heapBase, growable := true },
      release := .reuse,
      hostProvided := true
    } }

/-- EVM binding: bump over call-scratch memory, release rejected until FV-3. -/
def AllocatorConfig.evm (scratchBase : Nat := 0) : AllocatorConfig :=
  { model := {
      strategy := .bump,
      region := { base := scratchBase, growable := false },
      release := .none
    } }

-- Backward-compatible accessors derived from the unified model.

def AllocatorConfig.heapBase (cfg : AllocatorConfig) : Nat :=
  cfg.model.region.base

def AllocatorConfig.requiresHost (cfg : AllocatorConfig) : Bool :=
  cfg.model.hostProvided

def AllocatorConfig.isWasmInternal (cfg : AllocatorConfig) : Bool :=
  !cfg.model.hostProvided

def AllocatorConfig.usesEntryReset (cfg : AllocatorConfig) : Bool :=
  cfg.model.strategy == .bumpReset

def AllocatorConfig.usesMinimalMallocShape (cfg : AllocatorConfig) : Bool :=
  cfg.model.strategy == .freeList && !cfg.model.hostProvided

def AllocatorConfig.isCosmWasmRegion (cfg : AllocatorConfig) : Bool :=
  cfg.model.strategy == .hostImport

def AllocatorConfig.isOfflineJemallocShape (cfg : AllocatorConfig) : Bool :=
  cfg.model.hostProvided && cfg.model.strategy == .freeList

/-- Human-readable id for diagnostics / config output. Preserves the historical
IDs for the preset constructors where possible. -/
def AllocatorConfig.id (cfg : AllocatorConfig) : String :=
  match cfg.model.strategy, cfg.model.release, cfg.model.hostProvided with
  | .bump, .none, false => "alloc.bump"
  | .bumpReset, .none, false => "alloc.bump_reset"
  | .freeList, .reuse, false => "alloc.near_wee_model"
  | .hostImport, .reuse, false => "alloc.cosmwasm_region"
  | .bump, .none, true => "alloc.offline.host_bump"
  | .freeList, .reuse, true => "alloc.offline.host_jemalloc_shape"
  | _, _, _ => cfg.model.id

end ProofForge.IR
