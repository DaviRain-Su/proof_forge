# Authoring Model

ProofForge should not ask application developers to author `ContractSpec`
objects directly. `ContractSpec` is a compiler-owned boundary: source syntax
lowers into it, target routing consumes it, and backends print target artifacts
from the resulting IR and target-extension metadata.

## Layers

The current stack has three authoring layers:

| Layer | Status | Purpose |
|---|---|---|
| Lean embedded SDK / `contract_source` | Implemented v1 embedded source syntax | Current authoring surface. It lets the repo express portable state, entrypoints, events, arithmetic, SDK intents, and Solana account/PDA/CPI declarations in Lean syntax without hand-building `ContractSpec` strings. |
| Legacy `.learn` parser | Implemented v0 standalone parser and CLI compatibility entrypoint | Compatibility/smoke-test input that lowers into the same compiler-owned `ContractSpec` / `TokenSpec` boundary. It should not grow into a second product language. |
| `ContractSpec` / IR | Internal compiler artifact | Stable bridge into target routing, capability checks, backend lowering, AST/printer stages, manifests, IDL, clients, and deployable packages. |

The intended user experience is Lean-first for the current repo: developers use
Lean syntax and SDK helpers, and the compiler lowers those values into
`ContractSpec`, `TokenSpec`, portable IR, and target-extension plans. The
standalone `.learn` parser remains useful as a compatibility harness because it
exercises the same lowering boundary from files, but new SDK work should land in
the Lean/SDK layer first. `proof-forge --learn --target <id>` and
`proof-forge --learn-token --target <id>` are therefore legacy CLI paths that
reuse the same compiler-owned boundaries instead of defining a separate product
language.

The string-heavy `ContractSpec` and Builder examples should therefore be read
as compiler fixtures, not as the product surface. They describe the same
program shape that the compiler consumes after parsing, capability routing, and
target-extension expansion. Application authors should see Lean SDK syntax and
typed helpers; tests may keep Builder and `.learn` fixtures as reviewed
equivalence inputs.

It is still normal for the compiler-owned source AST and IR boundary to store
identifiers as strings after parsing. That representation is not the authoring
model. The product direction is that users write Lean SDK syntax, typed helpers
check names and references where possible, and only then does the compiler
materialize string names inside `ContractSpec`, manifests, IDL, clients, and
backend ASTs.

## Source Principles

- Portable contracts should express business logic without target-specific
  deployment details.
- Target-specific capabilities should be requested through typed SDK forms, not
  raw string plumbing.
- Chain dispatch belongs to build configuration and target routing. Source code
  should remain reusable when a target can provide equivalent capabilities.
- Target extensions, such as Solana account/PDA/CPI declarations, may appear in
  source when the contract intentionally needs chain-native semantics. Those
  extensions lower to target metadata and helper actions, not to portable IR
  constructors unless multiple chain families share the same semantic shape.
- Literal strings are acceptable for real protocol bytes, such as PDA literal
  seeds. They should not be the primary representation for accounts, owners,
  capability names, methods, or deployment configuration.

## Current Syntax Boundary

`ProofForge.Contract.Source` is the current executable Lean syntax layer and
covers:

- portable scalar state;
- entrypoints and queries with typed parameters;
- local bindings, assignment, return, event emission, and checked arithmetic
  syntax;
- EVM native-value entry markers (`accepts_callvalue;`), `nativeValue` reads, and
  plain native transfers (`sendto recipient amount;`);
- EVM entry guards (`guard_owner`, `guard_not_paused`, `guard_paused`,
  `guard_unlocked`, `acquire_lock`, `release_lock`) and fixed `u64` array locals
  (`fixedu64x3`, `array_get`);
- EVM constructor ABI schema declarations (`constructor_param name : .u64 | .u32 |
  .bool | cstring | cbytes | u256array`) that populate deploy metadata when CLI
  `--evm-constructor-param` flags are omitted;
- Solana allocator selection;
- Solana account constraints, including writable and signer declarations;
- Solana PDA declarations and derivation statements;
- Solana account reallocation statements with static target lengths;
- Solana System Program `transfer` and `create_account` CPI declarations and
  invocation statements;
- Solana SPL Token `transfer_checked`, `mint_to`, `burn`, `approve`, `revoke`,
  `close_account`, and `set_authority` CPI declarations and invocation
  statements;
- Solana log, return-data, compute-unit, memory, crypto, and sysvar helper
  statements;
- reusable mixin modules via `contract_mixin Name do ...`, which emit
  `def mixin : ModuleM Unit` for composition;
- stdlib composition via `import Module;` / `open Module;` inside
  `contract_source`, which splice another module's `mixin` action into the
  contract body;
- portable stdlib mixins under `ProofForge/Contract/Stdlib/` (`Ownable`,
  `Pausable`, `ERC20`, `ReentrancyGuard`) with thin EVM wrappers in
  `Examples/Evm/Contracts/stdlib/`.

To compose mixins, import the stdlib Lean module, `open` it for state ref
names, then inside `contract_source` write:

```lean
import ProofForge.Contract.Stdlib.Ownable;
import ProofForge.Contract.Stdlib.ERC20;
```

Each `import` expands to that module's `mixin` action. Standalone stdlib
contracts use `use mixin;` after defining the mixin in the same file. The
ERC-style composition fixtures live under `Examples/Evm/Contracts/` because
they intentionally exercise EVM stdlib and ABI behavior. Shared token product
examples should use the higher-level `TokenSpec` intent boundary instead; see
`Examples/Shared/FungibleToken.lean` and `Examples/Shared/FeeToken.lean`.

`ProofForge.Contract.Token` is the current token SDK planning boundary.
Lean-authored `TokenSpec` values route to ERC-20 on EVM or to structured Solana
SPL Token / Token-2022 deployment plans. The Solana plan records mint account
creation, associated token accounts, `mint_to`, `transfer_checked`, `approve`,
`burn`, `revoke`, authority changes, Token-2022 extension initialization, and
Token-2022 transfer-fee collection flows such as direct withheld-fee withdraw
and harvest-to-mint plus withdraw-from-mint, plus non-transferable token
initialization that rejects `TransferChecked` while still allowing burn. It
also records the Solana program ids needed by Web3.js or client generation.

`ProofForge.Contract.Learn` still parses the checked-in `.learn` examples under
`Examples/Learn/` into a small source AST and lowers that AST to the same
`ContractSpec`/portable IR boundary used by `contract_source`. The CLI can route
a `.learn` input through `--target evm` for EVM bytecode metadata or
`--target solana-sbpf-asm` for Solana sBPF assembly packages. The parser covers the
portable scalar/event subset plus the first Solana target-extension forms for
accounts, PDA derivation, System Program transfer/create-account CPI, and SPL
Token transfer, mint, burn, approve, revoke, close-account, and set-authority
CPI. It also accepts
selector-bearing entrypoints such as `entry mint selector "04"(amount: u64)`,
so Solana instruction tags can be represented in Learn source instead of only
in Builder fixtures. Learn statements now also cover the Solana log helpers for
pubkey/data logs, return-data set/get helpers, and remaining-compute-unit read
or log helpers. The same source layer covers Solana memory helpers, SHA-256,
Keccak-256, and BLAKE3 hash helpers, and sysvar/context reads for Clock, Rent,
EpochSchedule, EpochRewards, and LastRestartSlot fixture coverage.
Learn lowering also validates declared Solana CPI/PDA references, signer seeds,
declared CPI account references, CPI writable/signer requirements, and helper
state/account references before emitting `ContractSpec`, so the remaining
string-bearing identifiers are checked compiler data instead of unchecked
user-facing spec plumbing.
`ProofForge.Contract.Token.Learn` separately parses Learn token intent sources
such as `Examples/Learn/ProofToken.learn` and `Examples/Learn/FeeToken.learn`.
Those files are compatibility fixtures for the shared Lean token intents, not
the canonical product examples.
`--learn-token --target evm` now emits ERC-20 Yul, bytecode, and artifact
metadata with standard ERC-20 selectors and Transfer/Approval topics, while
`--learn-token --target solana-sbpf-asm` reuses `TokenSpec` to emit the same
structured SPL Token / Token-2022 plan used by Lean-authored token specs.

Examples such as `ProofForge.Contract.Examples.ValueVault` should be read as
v1 Lean source examples, not as a staging area for a second `.learn` grammar.
The matching `.learn` files are legacy compatibility examples used to prove
lowering equivalence.

## Target Routing

The build target chooses the lowering path:

```text
Lean SDK syntax / contract_source
  -> source AST
  -> ContractSpec / portable IR
  -> target resolver + capability routing
  -> target semantic AST
  -> printer / assembler / package emitter
```

For Solana, target extensions attach account schemas, PDA seeds, CPI layouts,
IDL, clients, and sBPF assembly helpers. For EVM, routing derives ABI selectors,
Yul, bytecode, ABI metadata, and deployment files. The source author should not
need to manually switch between these internals when the contract is portable.

## Next Implementation Steps

1. Execute **Workstream 34** (Contract Source productization): portable
   authoring boundary, EVM stdlib in `contract_source`, then target-selected
   build/test/deploy UX. See [implementation-backlog.md](implementation-backlog.md)
   Workstream 34.
2. Keep new SDK Alpha/Beta work in Lean SDK syntax and compiler-owned planning
   layers, then let legacy `.learn` inputs reuse those layers only when useful
   for compatibility tests.
3. Gradually replace string-bearing Solana declarations with typed account,
   owner, program, and capability references in Lean helpers while keeping
   string names inside compiler artifacts only.
4. Extend target package emission beyond EVM and Solana sBPF as Wasm, Move, and
   other target backends grow from routing plans into package emitters.
