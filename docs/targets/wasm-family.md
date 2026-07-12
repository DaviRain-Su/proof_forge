# Wasm Family Targets

The Wasm family includes NEAR, CosmWasm, Stellar/Soroban, Internet Computer
canisters, later Polkadot/ink-style contracts, and Cloudflare Workers. They
share an executable format, but not a contract ABI. Cloudflare Workers is not a
blockchain, but it uses the same Wasm-host backend pattern: a generated Wasm
module plus a target-specific host bridge. ProofForge should share only the
parts that are genuinely common. See [Cloudflare Workers target](cloudflare-workers.md)
for the off-chain reinterpretation of capabilities.

## Spike honesty (U7)

- **NEAR (`wasm-near`)** is the primary Wasm product host (Experimental).
- **CosmWasm:** Counter MVP six-gate (`just cosmwasm-promotion`); portable remote
  still uses a WasmMsg-shaped `execute_msg` **stub**;
  Gate G1a (M3/M4) is **not started**.
- **Soroban:** Counter MVP host adapter (`PF-P3-02` six-gate); interpreter auth
  is always-authorised until real Env auth lands.
- **Cloudflare Workers:** research / off-chain only.

## Common Shape

The canonical Wasm-family backend is **`EmitWat`**, modeled on the in-repo
**portable-IR → Yul** renderer `ProofForge/Backend/Evm/IR.lean` (the path used
by every `--emit-*-ir-yul` CLI mode), *not* on the separate LCNF-based
`Compiler/LCNF/EmitYul.lean`. `Backend/Evm/IR.lean` lowers the portable IR
(`Module`/`Entrypoint`/`Statement`/`Expr`) to a `Yul.AST` which a `Printer`
renders to Yul text, then `solc` compiles. `EmitWat` does the same but targets
WAT: portable IR → `Wasm.AST` → WAT text → `wat2wasm`.

Because the portable IR already abstracts over Lean objects (it has only
`u32`/`u64`/`bool`/`hash` scalars, storage maps, and effects — no closures,
no arbitrary recursion, no Lean runtime objects), `EmitWat` needs **no Lean
runtime port, no object-model boxing, and no GC**. This is the key advantage
over both the Rust sourcegen (which couples to `near-sdk` macros) and the
prior `EmitZig` plan (which requires porting the full Lean runtime to Wasm)
([D-031](../decisions.md)).

```text
Portable IR (Module)
  -> EmitWat              (shared: portable IR -> Wasm AST, mirroring Backend/Evm/IR.lean)
  -> Wasm AST             (shared: Compiler/Wasm/AST.lean, like Compiler/Yul/AST.lean)
  -> WAT text             (shared: Compiler/Wasm/Printer.lean, like Yul/Printer.lean)
  -> wat2wasm / wabt      (shared toolchain)
  -> Wasm artifact        (imports the per-chain host functions)
  -> target-specific validation
```

**Shared layer (write once for the whole family):**

- `Compiler/Wasm/AST.lean` + `Compiler/Wasm/Printer.lean` — a Wasm/WAT AST and
  printer, parallel to `Compiler/Yul/AST.lean` + `Yul/Printer.lean`.
- The portable-IR → Wasm-AST lowering core lives in
  **`ProofForge/Backend/WasmHost/`** (package name; formerly `WasmNear` while
  NEAR was the only EmitWat host). Host differences are
  `ProofForge.Target.HostBridge` (`.near` / `.soroban` / …), not a separate
  backend package per chain. Validation/sourcegen history also in
  `Backend/WasmHost/IR.lean` (Rust v0) and `Backend/Evm/IR.lean`.
- WAT module scaffolding: memory, type/import/export sections, and the
  `wat2wasm` invocation + artifact metadata.

**Package tree (2026-07-09 — unified Wasm family):**

```text
ProofForge/Backend/WasmHost/          # one Wasm-family package
  EmitWat.lean                        # IR → WAT core (HostBridge.near / .soroban)
  NearHost.lean · SorobanHost.lean    # interpreter hosts
  CosmWasmHost.lean
  CosmWasm/                           # CosmWasm host adapter (Counter spike)
    EmitWat.lean · IR.lean
```

| Name | Meaning |
|------|---------|
| `Backend.WasmHost` | **Wasm-family package** (EmitWat + host adapters) |
| `WasmHost.EmitWat` | Shared lowering for NEAR + Soroban via `HostBridge` |
| `WasmHost.CosmWasm.*` | CosmWasm Counter-spike adapter (message exports) |
| `HostBridge.near` / `.soroban` / `.cosmWasm` | Host import materialization enum |
| Registry `wasm-near` | Product target id for **NEAR only** |
| Registry `wasm-stellar-soroban` | Product target id for **Soroban only** |
| Registry `wasm-cosmwasm` | Product target id for **CosmWasm only** |
| Registry `wasm-cloudflare-workers` | Off-chain Wasm host (TS/Workers path; not EmitWat core) |

**Single entry:** `WasmHost.EmitWat.renderModule mod bridge` for all three
on-chain Wasm targets. CosmWasm still uses an in-package Counter **spike**
adapter (`WasmHost.CosmWasm.EmitWat`) for `cosmwasm-check` exports; full IR
lower for CosmWasm uses `HostBridge.cosmWasm` + `db_read`/`db_write` helpers.

**Per-chain layer (the only thing that differs between NEAR / CosmWasm / Soroban / ICP):**

- Host-import table: which Wasm imports the IR storage/crypto/context effects
  lower to (NEAR `env.storage_*`, CosmWasm `db.read`/`db.write`, Soroban host
  functions, …).
- **ABI serialization** of arguments and return values (NEAR JSON/Borsh,
  CosmWasm JSON, …) — the messiest per-chain concern and the main spike risk.
- Exported entrypoint names + deployment packaging.

The shared/per-chain split is the whole point: the Wasm AST + lowering +
`wat2wasm` are identical across the family; only the host imports and ABI
differ.

## Legacy paths

- **`EmitZig`** (prior canonical plan): `Lean → EmitZig → Zig → host bridge →
  Wasm`. Superseded by `EmitWat` because it requires porting the full Lean
  runtime to Wasm (libuv/threads/GC), which is the documented blocker.
- **Rust / CDK sourcegen** (e.g. NEAR `near-sdk-rs`): `Portable IR → Rust
  package → cargo wasm32`. Retained only as a **frozen v0 stopgap** to validate
  chain semantics; not to be expanded. See [Wasm-NEAR target](wasm-near.md).
  Its IR-lowering/validation logic is reusable by `EmitWat`; only the emission
  target (Rust strings) is discarded.

## NEAR

See [Wasm-NEAR target](wasm-near.md) for the full implementation design.

- **Canonical path:** `Portable IR → EmitWat → Wasm AST → WAT → wat2wasm →
  Wasm`, with a NEAR host bridge lowering portable IR effects to
  `env.storage_*` / `env.sha256` / `env.predecessor_account_id` /
  `env.block_height` / `env.log` imports.
- **Frozen v0 stopgap (in-repo, compiles):** Rust `near-sdk-rs` sourcegen via
  `ProofForge/Backend/WasmHost/IR.lean`. Validates NEAR semantics now; not
  expanded. Key risk for the canonical path: NEAR argument (de)serialization
  (JSON/Borsh), which the EVM backend does not face (EVM uses calldata).

Design cleanup before porting:

- Do not keep `lean_near_*` declarations in generic EmitZig extern lists.
- Do not force-link NEAR host code for every Wasm target.
- Move method metadata into the unified target manifest.

## CosmWasm

CosmWasm is also Wasm, but its ABI is message-oriented.

Expected exports:

- `interface_version_8`
- `allocate`
- `deallocate`
- `instantiate`
- `execute`
- `query`
- later: `migrate`, `reply`, `sudo`, `ibc_channel_open`,
  `ibc_channel_connect`, `ibc_channel_close`, `ibc_packet_receive`,
  `ibc_packet_ack`, `ibc_packet_timeout`

Expected imports include storage, address, crypto, debug, and chain query host
functions. Exact imports should be taken from the supported CosmWasm VM version
when implementation starts.

First adapter behavior:

- Keep messages as JSON strings.
- Return JSON responses.
- Represent events as attributes.
- Use string-keyed storage first.
- Add typed schema generation later.

## Stellar/Soroban

Stellar smart contracts are also Wasm artifacts, but Soroban has its own SDK,
host environment, storage lifecycle, authorization model, deployment flow, and
CLI tooling.

Candidate target id: `wasm-stellar-soroban`.

Current native path:

```text
Rust + soroban-sdk
  -> stellar contract build
  -> wasm32v1-none Wasm
  -> stellar contract deploy / invoke
```

Target-specific concerns:

- build flow uses Rust and Stellar CLI rather than `cosmwasm-check`;
- storage distinguishes instance, persistent, and temporary entries, with TTL
  and archival behavior;
- authorization is explicit and address-based through `require_auth`-style
  calls, not just a sender read;
- contract accounts can implement custom authorization;
- contract interface/spec metadata is part of the developer workflow;
- deployment separates Wasm upload/install from contract instantiation.

The first ProofForge spike may generate or wrap a native Soroban package before
attempting a direct Lean-to-Wasm host bridge. See
[Stellar Soroban target](stellar-soroban.md).

## Internet Computer Canisters

Internet Computer canisters are Wasm modules plus persistent canister state and
Candid interfaces. They have their own message model, lifecycle, cycles
accounting, stable memory, and management canister APIs.

Candidate target id: `wasm-icp-canister`.

Current native paths:

```text
Motoko or Rust CDK
  -> Wasm canister module
  -> Candid .did interface
  -> local replica / PocketIC / ICP CLI validation
```

Target-specific concerns:

- update, query, and composite query methods have different semantics;
- Candid service metadata is part of the public contract interface;
- caller and canister identities are principals;
- persistent state may rely on canister memory, stable memory, or
  CDK-managed stable structures;
- inter-canister calls are asynchronous message flows;
- cycles are the resource-accounting unit, not ordinary native value;
- deployment and upgrades go through canister lifecycle and management canister
  APIs.

The first ProofForge spike may generate or wrap a native Motoko/Rust CDK
canister before attempting a direct Lean-to-Wasm host bridge. See
[Internet Computer target](internet-computer.md).

## Runtime Profile

Because `EmitWat` lowers the **portable IR** (not Lean LCNF), there is no Lean
runtime to port at all — the IR has only `u32`/`u64`/`bool`/`hash` scalars and
storage effects, which map directly to Wasm `i32`/`i64` values and host-import
calls. The remaining target concerns are real and selected per target:

- threads — none (single-threaded, atomic per call)
- POSIX filesystem / process environment / libuv — none
- native GMP — none (hash is a fixed 4×u64 limb tuple, lowered directly)
- chain-agnostic force-linking of host bridges — none

| Option | NEAR | CosmWasm | Stellar/Soroban | ICP canister | Cloudflare Workers |
|---|---|---|---|---|---|
| Scalar lowering | shared `EmitWat` (IR u32/u64/bool/hash → Wasm i32/i64) | shared | shared | shared | TypeScript sourcegen today; shared `EmitWat` planned |
| Hash lowering | shared `EmitWat` (4×u64 tuple in linear memory) | shared | shared | shared | TypeScript bigint today |
| Host bridge | `near` (`env.*`) | `cosmwasm` (`db.*`) | `stellar-soroban` | `icp-canister` | `cloudflare-workers` (fetch/KV) |
| Args ABI | JSON / Borsh | JSON | Soroban XDR / native | Candid | JSON over HTTP |
| Validation | NEAR VM/MVP checks | `cosmwasm-check` | Stellar CLI or sandbox | Local replica, PocketIC, or ICP CLI | `wrangler dev` / Miniflare |

## CosmWasm Counter Spike

Minimal Lean surface:

```lean
namespace CosmWasm

opaque inputJson : IO String
opaque storageRead : String -> IO (Option String)
opaque storageWrite : String -> String -> IO Unit
opaque storageRemove : String -> IO Unit
opaque returnJson : String -> IO Unit
opaque logAttribute : String -> String -> IO Unit
opaque queryChain : String -> IO String

end CosmWasm
```

Expected user contract shape:

```lean
def instantiate : CosmWasm.Entrypoint := do
  CosmWasm.storageWrite "count" "0"
  CosmWasm.returnJson "{\"ok\":true}"

def execute : CosmWasm.Entrypoint := do
  let msg <- CosmWasm.inputJson
  if msg == "{\"increment\":{}}" then
    ...

def query : CosmWasm.Entrypoint := do
  ...
```

Acceptance criteria:

- Wasm exports all required functions.
- `cosmwasm-check` accepts the artifact.
- Counter can instantiate, increment, and query.
- Artifact metadata records `target: wasm-cosmwasm`.

## Open Questions

- **[NEAR spike gate]** Can NEAR argument (de)serialization (JSON/Borsh) be
  lowered cleanly under `EmitWat`? This is the highest-risk unknown and must be
  de-risked before scaling the lowering.
- Should `EmitWat` emit WAT text (→ `wat2wasm`) or Wasm binary directly? WAT
  text is the default (mirrors `Backend/Evm/IR.lean` → Yul text → `solc`);
  binary is a later optimization to drop the `wabt` dependency.
- How much of the IR-lowering / validation logic in `Backend/WasmHost/IR.lean`
  (Rust v0) and `Backend/Evm/IR.lean` can be shared by `EmitWat`?
- Should CosmWasm compile through `wasm32-freestanding` or a WASI route with
  import stripping?
- Should schema generation (CosmWasm JSON schema, Soroban spec, ICP `.did`)
  come from Lean types or a separate manifest?
- Should Soroban / ICP start as native Rust/Motoko package sourcegen before a
  direct `EmitWat` host bridge?
