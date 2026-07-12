# Product Authoring Architecture

Status: **Accepted product direction; historical layer sketch (refreshed
2026-07-12).** The current intent/materializer boundary is defined by D-052.
Audience: product + compiler design  
Related: [authoring-model](authoring-model.md), [D-028](decisions.md),
[D-027](decisions.md), [D-050](decisions.md),
[RFC 0006 Token SDK](rfcs/0006-multichain-token-sdk.md),
[IR portability remediation](ir-portability-remediation.md).

This file retains the product thesis and earlier layer analysis. Where its
concrete types or phases conflict with the July 12 design, the newer design
wins.

## 1. Product thesis (north star)

**Ideal product path — the only thing the user must choose is `--target`.**

```text
  User writes:   business logic only
  User chooses:  --target solana-sbpf-asm | evm | wasm-near | …
  Platform does: everything chain-native (DSL, accounts, ABI, CPI, host, token standard)
```

Solana Account / PDA / CPI, NEAR Promise / host imports, EVM slots / selectors /
CREATE2, Move resource / object — these are **not authoring languages**. They
are **materialization backends** the compiler drives after target selection.

```text
  ┌─────────────────────────────────────────────────────────┐
  │  L1  Author: business intents ONLY                      │
  │      state · entry · rules · token features · roles     │
  │      (no account, no pda, no cpi, no promise, no slot)  │
  └───────────────────────────┬─────────────────────────────┘
                              │  contract_source / TokenSpec
                              ▼
  ┌─────────────────────────────────────────────────────────┐
  │  L2–L3  Compiler: portable IR + capabilities            │
  └───────────────────────────┬─────────────────────────────┘
                              │  --target <id>
                              ▼
  ┌─────────────────────────────────────────────────────────┐
  │  L4  Target materializer (automatic)                    │
  │      may *internally* emit Solana plan / CPI frames /   │
  │      EVM Yul / NEAR WAT — authors never write that DSL  │
  └─────────────────────────────────────────────────────────┘
```

**What this means for “native DSL”:**  
Today’s Solana `account` / `pda` / `cpi` syntax and similar chain DSLs are a
**temporary compiler / fixture surface**, not the product. They may remain as:

1. **Compiler-internal IR** (preferred end state): only target plans speak them; or  
2. **Research / pinocchio / live-gate fixtures**: engineers testing the backend; or  
3. **Advanced escape hatch** (discouraged): power users who accept non-portability.

They must **not** appear in Shared product tutorials. The SDK does not ask
users to “call the Solana DSL”; the Solana **adapter** calls it (or generates
equivalent plan data) when `--target solana-sbpf-asm` is set.

This is D-028 / RFC 0006 taken all the way: chain models are platform problems.

## 2. What authors should see (default surface)

| Allowed in portable source | Not allowed in portable source |
|---|---|
| State shape (`scalar` / `map` / …) | Storage slots, account metas, PDA seeds (unless policy seeds are pure business literals) |
| Entrypoints + business control flow | `fallback` / `receive` / 4-byte selectors as required author input |
| Checked vs wrapping arithmetic intent | Opcode names, syscalls |
| Roles / ownable / pause / reentrancy **policies** | ERC-1967 slots, Anchor `#[account]` macros |
| Token **business** features: mintable, burnable, capped, fee, soulbound, … | `erc20` / `spl-token` / `token-2022` as author-chosen standards |
| Structured events + portable errors | Topic indexing layout, log_utf8 encoding |
| Cross-contract **intent** (“call method X on peer Y”) | CPI account vectors, Promise chains, STATICCALL/DELEGATECALL |
| Upgrade **policy** (immutable / authority / governance) | UUPS vs transparent proxy implementation |

**Token example (desired):**

```text
token MyToken {
  name "Proof Token"
  symbol "PRF"
  decimals 9
  feature mintable
  feature burnable
  feature transfer_fee   -- business: charge fee on transfer
}
```

```sh
proof-forge build --target evm ...
  → ERC-20 (+ fee logic in contract storage)

proof-forge build --target solana-sbpf-asm ...
  → SPL or Token-2022 plan (transfer_fee extension + CPI plan)
  → no hand-written Account/PDA/CPI in source

proof-forge build --target wasm-near ...
  → NEP-141 (+ fee policy) when NEAR token lane is ready
```

Authors never write `TokenStandard.erc20` or `splToken2022` for the
default path. `planForTarget` already starts this for TokenSpec; the
product rule is: **finish and expand that pattern everywhere.**

## 3. Layer contracts (who owns what)

| Layer | Owns | Must not own |
|---|---|---|
| **L1 Intent API** (`contract_source` portable subset) | Business state, methods, policies, token features | Chain APIs, Account/PDA/CPI syntax, Promise APIs |
| **L2 Portable IR** | Shape + effects + capability ids | `nearPromise*`, CREATE2, fallback/receive as default, object/resource owner |
| **L3 Capability + StorageBinding** | Support matrix; storage materialization enum | Author-visible chain types |
| **L4 Target adapter** | ABI, accounts, PDA derivation templates, CPI packing, host imports, Move object/resource emit, token standard choice | Changing portable business semantics |
| **L5 Chain materializer internals** | Solana plan/CPI packing, EVM Yul, NEAR EmitWat — **compiler-owned** | Author-facing “write CPI in Lean” as the default path |

**L5 rule (updated):** Chain DSL is **not** a second product language.  
`ProofForge.Contract.Source.Solana` exists today as a bridge for backend
fixtures; the product goal is that Shared contracts never need it because
L4 auto-materializes accounts/CPI from portable IR. Tutorials must never
require writing PDA/CPI.

## 4. Gap analysis (repo today)

| Area | Intended | Current gap |
|---|---|---|
| TokenSpec | Target picks ERC-20 vs SPL/2022 | Direction correct; NEAR/Move token lanes thin; some feature ids still Solana-shaped in docs |
| Stdlib ERC-20 | Should be “portable token mixin” routed by target | Named and lowered primarily as EVM ERC-20 |
| `contract_source` | Portable by default | Documents EVM guards, constructor ABI, Solana PDA/CPI in the same surface |
| Solana Surface | Extension only | Widely used in examples; easy to confuse with default product |
| Portable IR Expr | Chain-neutral | Still carries NEAR Promise + EVM create/static/delegate constructors |
| Storage | Target-resolved (`StorageBinding`) | ✅ Landed (D-050) |
| Context | Portable env vs EVM-only | ✅ Classified; Surface still exposes both |
| **Protocols (Layer B)** | Clients for on-chain programs/interfaces (SPL, IERC20, NEP-141 peers) | ✅ Indexed in [protocols-layer](protocols-layer.md); Solana packing deep; EVM IERC20 + NEAR FT thin clients landed |
| **Stdlib (Layer C)** | Deployable mixins (you *are* the ERC-20 / NEP-141) | ✅ `Contract/Stdlib/*`; must not be confused with Protocols clients |

## 5. Phased plan

### Phase A — Product default path (author experience)

**Goal:** A new developer can write Counter / Token / Vault **without** any
chain keyword in source, and build to `evm`, `solana-sbpf-asm`, `wasm-near`.

1. **Portable-only `contract_source` profile**
   - Document and lint: portable modules must not import Solana/NEAR
     extension helpers.
   - Diagnostics: “PDA/CPI is a Solana extension; omit it for portable
     authoring or pass `--target solana-sbpf-asm` with an explicit
     extension-enabled project.”
2. **Token feature vocabulary = business only**
   - Keep `mintable` / `burnable` / `capped` / `fee` / `non_transferable` /
     `pausable` as portable features.
   - Map at target time: EVM contract logic vs Token-2022 extension vs
     NEAR NEP-141 fields.
   - Deprecate author-facing `TokenStandard` selection for default CLI;
     keep as plan output only.
3. **Role / ownable / pause as portable policies**
   - Stdlib mixins stay portable IR; EVM/Solana/NEAR each lower guards
     and state layout via adapters (not separate ERC/Ownable copies per chain).

**Exit:** `just portable-counter-multi-target` + portable token smoke for
EVM + Solana without extension syntax in shared examples.

#### Phase A status (2026-07-09) — landed

| Item | Evidence |
|---|---|
| Shared portable-default lint | `just portable-default` → `scripts/portable/check-portable-default.py` + topology |
| No chain Surface / TokenStandard in `Examples/Product` | Gate rejects forbidden imports and `TokenStandard.*` |
| TokenSpec has no author `standard` field | Structure is features-only; `resolveTokenStandard` is adapter-only |
| Feature → standard is target-resolved | FungibleToken → erc20 / spl-token; FeeToken → spl-token-2022 on Solana |
| Unsupported features **reject** (no silent drop) | FeeToken / Soulbound on `evm` error citing `transfer_fee` / `non_transferable` |
| Product docs | `Examples/Product/README.md`, Token.lean module header |

**Phase B.1 (2026-07-09) — Solana Source opt-in:**

| Item | Evidence |
|---|---|
| Portable default import | `import ProofForge.Contract.Source` |
| Solana extension import | `import ProofForge.Contract.Source.Solana` (re-exports Source + Solana Surface/Builders) |
| Solana examples | `ProofForge/Solana/Examples/*` that use account/PDA/CPI import `Source.Solana` |
| Shared gate | `portable-default` forbids `Source.Solana` and Solana DSL keywords |

### Phase B — Automatic chain materialization (compiler)  ← **next product focus**

**Goal:** From **portable IR alone**, each target synthesizes everything that
today still tempts people to write chain DSL by hand.

| Pattern | EVM auto | Solana auto | NEAR auto |
|---|---|---|---|
| Scalar / map state | storage slots / layout | **one program data account** (default) + borsh/layout | host KV keys |
| Token balances | map in contract / ERC-20 | **mint + ATA + SPL/Token-2022 CPI plan** (TokenSpec already partial) | NEP-141 |
| Auth (ownable) | address + guard | signer/authority account checks synthesized | predecessor |
| Cross-call intent | CALL | **CPI frame from intent** (portable peer + protocol CPI; PDA signer seeds expanded; selective accounts; no silent empty ix data) | Promise create/then from intent |
| Events | LOG topics | sol_log / structured log | log_utf8 JSON |
| PDA (only if needed) | n/a | **derived from business ids** (vault id, mint, …) not author seed tables | n/a |

**User-visible success:**  

```lean
-- Shared/Counter.lean  (unchanged portable source)
import ProofForge.Contract.Source
contract_source Counter do
  state count : .u64
  entry initialize do ...
  entry increment do ...
  query get returns (.u64) do ...
```

```sh
proof-forge build --target solana-sbpf-asm ...   # no Source.Solana import
  → Solana.Plan synthesizes: data account, discriminators, entrypoint tags
  → sBPF asm + IDL + client — author never wrote `account` / `pda` / `cpi`
```

Implementation sketch:

1. **`Target.Materialize` / strengthen existing plans**
   - Input: portable `Module` + `CapabilityPlan` + target profile.
   - Output: `Evm.Plan` / `Solana.Plan` / Wasm plan (RFC 0014 stages).
2. **Solana auto-layout (B.2 priority)**
   - Portable scalar/map → single writable state account + payer/system as needed.
   - TokenSpec path already materializes mint/ATA/CPI — extend pattern to
     general `contract_source` modules (Counter, ValueVault, StakingVault).
   - PDA only when the **business** needs a deterministic address; seeds come
     from intent metadata, not author DSL.
3. **Retire author-facing chain DSL from the product story**
   - `Source.Solana` → document as **fixture/backend test only**.
   - Long term: generate Solana.Plan structures in Lean without expanding
     user-written `account` syntax at all.
4. **NEAR auto-host**
   - Materialize Promise from portable `crosscall.invoke` + async policy;
     remove author-facing `nearPromise*` from portable Expr (D-050 Slice 3).

5. **Crosscall materialization (Phase B.3) — landed for primary chains**
   - Authors write portable `crosscall.invoke` only; never CPI metas / Promise
     chains / STATICCALL opcodes on the portable path.
   - **EVM:** CALL (STATICCALL/DELEGATECALL/create remain extension-shaped).
   - **Solana:** CPI-shaped sBPF lower (`Backend.Solana.PortableCrosscall` +
     `SbpfAsm` method+args → ix data; auto `callee_program` account;
     `sol_log_64_` + `sol_get_return_data` stub). `Source.Solana` CPI remains
     for hand-tuned account vectors.
   - **NEAR:** `promise_create` via `nearCrosscallStrings` address-literal
     indices; typed/STATIC/DELEGATE/create reject with honest diagnostics.
   - Map + gate: `Target.CrosscallMaterialize` + `just crosscall-materialize`.

#### Cross-contract form is target-native (not one “CPI” for all chains)

Portable intent is one: **call method on peer**. Each backend owns the native
frame — authors never write these frames:

| Family | Native call form | “Accounts / identities” surface | Product status |
|---|---|---|---|
| **EVM** | `CALL` / optional STATIC/DELEGATE/create | address + calldata + value | **Product** (closed for this phase) |
| **Solana** | `sol_invoke_signed_c` **CPI** | AccountMeta/Info vector (pack up to **64**) | **Product** (closed for this phase) |
| **NEAR** | `promise_create` (+ optional `promise_then`) | account id strings + method + gas/deposit | **Product** (closed for this phase) |
| **Soroban** | host contract invoke + `require_auth*` | Stellar addresses / auth context | **Next** host-adapter spike (not NEAR promise) |
| **CosmWasm** | `execute_msg` host stub (WasmMsg-shaped) | contract/method string pool + JSON args | **Spike** (portable peer remote; full WasmMsg later) |
| **Workers** | binding / fetch | off-chain service ids | **Deferred** |
| **Move** | entry/object call (sourcegen) | address / object handles | spike |

So “CPI 传参 / account metas” is **Solana-only materialization**, not portable
IR. NEAR string pool and EVM ABI words are the parallel artifacts for those
families.

#### Where Solana account checks live (Anchor / Pinocchio analogue)

Anchor `#[account(signer, mut, owner = …)]` and Pinocchio-style manual checks
are **not** author-facing portable IR. They are **Solana backend
materialization** of the account schema:

```text
portable Module + --target solana-sbpf-asm
  → Manifest.materialize accounts (state / payer / callee_program / …)
  → each entrypoint prologue: SbpfAsm.lowerAccountValidations
       signer / writable / owner=program|executable|named
  → body lowering (storage, portable CPI pack, …)
```

| Concern | Layer | Module |
|---|---|---|
| Business logic | Portable IR / `contract_source` | Shared sources |
| Account **roles** (state, payer, callee) | Solana materialize / manifest | `Manifest.ensurePortableCrosscallAccounts`, `Materialize` |
| Account **checks** (signer, mut, owner, executable) | Entrypoint **prologue** (codegen) | `SbpfAsm.lowerAccountValidationFor` → `error_signer` / `error_owner` / … |
| CPI **packing** (metas, infos, invoke) | Expression lower for portable invoke / Source.Solana CPI helpers | `PortableCrosscall`, `Extension/Cpi` |
| Hand-tuned constraints | Opt-in extension | `Source.Solana` account/PDA/CPI DSL |

**Answer:** yes — checks belong in **Solana materialization + entrypoint
lowering**, already emitted as `account.validation[…]` comments and trap
labels in generated sBPF (same place Anchor would inject constraint code).
They must **not** become portable IR constructors (that would re-EVM/Solana-bias
the authoring surface).

#### Do we validate on the IR? (protocol validate → materialize)

**Yes, but layered.** Not every check is “IR protocol validate”, and not every
check materializes into chain code.

```text
contract_source / IR.Module
  │
  ├─ L0  Portability          family-only constructors (CREATE2, nearPromise*, …)
  │                           ProofForge.IR.Portability
  ├─ L1  Capability resolve   does --target advertise needed caps?
  │                           Target.Adapter.resolveModule / Target.Preflight
  ├─ L2  Protocol IR validate per-backend still *on IR* (types, returns, …)
  │                           Evm.Validate · Solana plan · EmitWat diagnostics
  ├─ L3  Materialize          roles → accounts / CALL plan / Promise pool
  │                           Target.Materialize · Solana.Manifest · …
  └─ L4  Prologue + emit      signer/owner traps, Yul CALL, promise_create WAT
                              SbpfAsm.lowerAccountValidations · ToYul · EmitWat
```

| Question | Layer | Materialize? |
|---|---|---|
| Is this still portable / wrong family constructor? | L0 | No — hard reject |
| Can this target run this module at all? | L1 | Gates materialize |
| Are types / entrypoints well-formed for this protocol? | L2 | Feeds plan |
| What accounts / ABI / host strings do we need? | L3 | **Is** materialize |
| Runtime traps (signer, owner, executable) | L4 | Emit from L3 schema |

**Implications:**

1. **IR-based checks (L0–L2)** are chain-aware *routing and well-formedness*,
   not Solana account constraints written into portable IR.
2. **Protocol validate maps to materialize** when the result is *schema or
   plan* (account roles, string pool, ABI arity) — L2/L3.
3. **Protocol validate maps to emit traps** when the result is *runtime
   guard code* (Anchor-like) — L4 from L3 schema.
4. Shared helpers stay in `Backend.SharedValidate` only when diagnostics are
   truly identical; family rules stay in backends (RFC 0014).

API: `ProofForge.Target.Preflight.run profile module` = L0+L1 report
(`readyToMaterialize`). Full L2 remains backend-owned.

**Exit:** Shared RoleGatedToken / StakingVault / Counter compile to Solana
**without** `import Source.Solana` and without any `account`/`cpi` line, and
pass Solana light gates.

#### Implemented-target materialize table (landed)

| Target | `storageBinding` | `layoutKind` / host | Crosscall native form |
|---|---|---|---|
| `evm` | `contract-global` | `contract-global-slots` | `evm-call` |
| `solana-sbpf-asm` | `account-data` | `account-data` | `solana-cpi` |
| `wasm-near` | `host-key-value` | host `near` | `near-promise` |
| `wasm-cosmwasm` | `host-key-value` | host `cosmwasm` | `cosmwasm-msg` |
| `wasm-cloudflare-workers` | `host-key-value` | `workers-bindings` | `workers-binding` |
| `move-aptos` | `move-resource` | `move-resource` | `move-call` |
| `move-sui` | `move-object` | `move-object` | `move-call` |
| `psy-dpn` | `circuit-mapping` | `psy-circuit-storage` | `zk-circuit-call` |
| `aleo-leo` | `circuit-mapping` | `leo-mapping-storage` | `zk-circuit-call` |

- Shared API: `Target.Materialize.forImplementedProfile` / `reportsForAllImplemented`
- Crosscall map: `Target.CrosscallMaterialize.forProfile` (portable intent → native form)
- Artifact field **`materialization`** on primary emit paths; Solana keeps
  `solanaMaterialization` for account lists
- Gates: `just primary-materialize`, `just crosscall-materialize`

### Phase C — Clean portable IR (compiler hygiene)

Already partially tracked in [ir-portability-remediation](ir-portability-remediation.md):

1. Remove / quarantine family-only Expr constructors (NEAR Promise, CREATE2, …).
2. Neutral constructor / init params on `ContractSpec` (drop `evm*` prefixes).
3. Entrypoint kind portable default = `function` only.
4. Identity type remains one portable handle; ABI rename in adapter.

**Exit:** `isPortableCoreModule` true for all shared scenarios; family-only
constructors only appear in extension fixtures.

### Phase D — Explicit extensions (advanced)

Keep Solana PDA/CPI, custom syscalls, raw host imports as **opt-in**:

```lean
import ProofForge.Solana.Surface  -- opt-in; non-portable
```

Rules:

- Extension use → module marked non-portable for other families.
- `--target` mismatch → hard error with “this is a Solana extension.”
- Docs separate “Portable contracts” vs “Chain-native extensions.”

### Phase E — Breadth after parity

Only after portable Token + Vault + Counter parity on three primary
targets:

- NEAR NEP-141 full token lane from same TokenSpec
- Move token / object mapping from same portable token/state
- CosmWasm / Aptos advancement per existing gate schedule

Do **not** open new chains until Phase A–C are credible.

## 6. Token Extension specifically

Token-2022 “extensions” on Solana are **not** author-facing ProofForge
extensions. They are **target materializations** of portable features:

| Portable feature | EVM materialization | Solana materialization |
|---|---|---|
| `transfer_fee` | fee logic in contract | Token-2022 transfer_fee extension + CPI |
| `non_transferable` | transfer guard | Token-2022 non_transferable |
| `mintable` | minter role | mint authority |
| `pausable` | pause flag + guards | pausable extension or wrapper |
| `permit` | EIP-2612 if supported else reject | reject or wrapper (honest diagnostic) |

Author never writes `feature token_2022` or `extension transfer_fee_config`.
They write `feature transfer_fee`; Solana adapter chooses Token-2022.

## 7. Engineering order (next 4–6 slices)

| Order | Slice | Status / why |
|---|---|---|
| 1 | Portable-default lint + docs | ✅ Landed |
| 2 | TokenSpec feature-only; standard from target | ✅ Landed |
| 3 | Solana Source opt-in (stop default teaching CPI) | ✅ Landed (bridge) |
| 4 | **Solana auto-materialize portable IR → Plan/accounts** | ✅ B.2 landed (`Backend.Solana.Materialize`, artifact field) |
| 4b | **Unified primary-chain materialize (EVM·Solana·Wasm-NEAR)** | ✅ `Target.Materialize` + artifact `materialization` on all three; `just primary-materialize` |
| 4c | **Portable crosscall.invoke materialize (EVM CALL · Solana CPI · NEAR Promise)** | ✅ B.3; Solana `sol_invoke_signed_c` + AccountMeta/Info + return-data; NEAR `promise_create`; Shared `RemoteCall` |
| 5 | NEAR Promise constructors out of portable product path (D-050 Slice 3) | ✅ Partial: `Source.Near` opt-in + portable-default ban; full Expr inductive removal deferred |
| 5b | **Layered preflight (L0 portability + L1 capability) before materialize** | ✅ `Target.Preflight`; L2 stays backend; L3/L4 = materialize + prologue |
| 5c | Portable CPI pack up to **64** (heap infos + stack metas) | ✅ `HEAP_START_ADDRESS` infos; ptr table 64 |
| 5d | Wire Preflight into CLI artifact + `proof-forge check` | ✅ Solana/EVM/NEAR artifacts; Check preflight.failed |
| 5e | **Product close-out triad** EVM · Solana · NEAR | ✅ Shared.RemoteCall multi-target + preflight + crosscall map |
| 5f | **Soroban** portable crosscall → `invoke_contract` (not CosmWasm/Workers) | ✅ `soroban-invoke`; EmitWat + host stub; Promise extensions rejected |
| 5g | CosmWasm / Workers advancement | **Deferred** (explicit non-goals this phase) |

### Phase close-out — what is “done” vs “next”

**Closed for this product slice (authors write logic + `--target` only):**

| Target | Crosscall | Preflight | Multi-target demo |
|---|---|---|---|
| `evm` | CALL | yes | `Shared.RemoteCall` |
| `solana-sbpf-asm` | CPI ≤64 | yes | `Shared.RemoteCall` |
| `wasm-near` | `promise_create` | yes | `Shared.RemoteCall` |
| `wasm-stellar-soroban` (host bridge) | `invoke_contract` | form map | portable probe via EmitWat `.soroban` |

**Unified portable crosscall map (authors write one intent):**

| Native form id | Host call / packing |
|---|---|
| `evm-call` | EVM CALL |
| `solana-cpi` | `sol_invoke_signed_c` ≤64 accounts |
| `near-promise` | `promise_create` + string pool |
| `soroban-invoke` | `invoke_contract` + string pool (host bridge; not in `--list-targets` yet) |

### Phase C — Pure business authoring (in progress, 2026-07-09)

**Goal:** For EVM · Solana · NEAR · Soroban, authors never touch chain DSL;
`--target` (or host bridge) is the only chain choice.

| Order | Slice | Status |
|---|---|---|
| C.1 | **RemoteCall: no host string-pool APIs in Shared** | ✅ `declareRemoteUnit` / `peerHandle` / `remoteCall`; gate bans `registerNearCrosscallString` / `nearAddressLit` |
| C.2 | **Business checks → native fail on four hosts** | ✅ Ownable: EVM plan · Solana assert · NEAR/Soroban `unreachable`/`panic`; `Tests/PortableAuthMaterialize` |
| C.3 | **Auth policy materialize** (owner/signer) | ✅ Solana `ensurePortableAuthAccounts`: leading `authority` signer when `callerSender`; state data offset by name; **T3.2** + `ensurePortableNativeValueAccounts` (writable fee payer) + remote `callee_program` for transfer/remote intents (`AuthRemoteCall`) |
| C.4 | **Source.Solana fixture-only demotion** | ✅ module header + `Examples/Backend/Solana/README`; Shared already gated |
| C.5 | **Soroban in portable multi-target scripts** | ✅ `remote-call-multi-target` + `crosscall-materialize` run portable-auth (Soroban invoke) |
| C.6 | **Deploy-time peer map** (logical peer → account id) | ✅ `Target.PeerMap`; CLI `--peer` / `--peers-demo` (default **identity**, no silent rewrite) |
| P0 | **Explicit peers + named RemoteRef + honest Solana caller handle** | ✅ `--peer`; Shared `declareRemote`→`remoteCallRef`; Solana notes pubkey[0..8] u64-le limit |
| P0b | **Solana caller = sha256(full 32-byte pubkey)→u64** | ✅ full identity commit (not raw 8-byte slice) |
| P0c | **TokenFeature × target matrix** | ✅ `Token.featureSupportOnTarget` + `just token-feature-matrix` |
| P1a | **Soroban auth deny + invoke log** | ✅ `host.sorobanAuthDenied`; `sorobanInvokes` call log |
| C.7 | Promote `wasm-stellar-soroban` to `Registry.all` | ✅ in `knownIds` / `--list-targets`; full Stellar CLI/spec still follow-on |
| P1b | **`remote name "peer" "method";` DSL** | ✅ contract_source binds `RemoteRef` |
| P1c | **NEAR TokenSpec NEP-141 plan lane** | ✅ core features plan; extensions reject; token-intent-smoke step 9 |
| P1d | **OwnableHash (hash owner / callerHash)** | ✅ NEAR · EVM (`hashWord(caller)`) · Solana (limb0 + `hash4` zero); triad Ownable remains u64 |
| P1e | **CLI Soroban RemoteCall multi-target** | ✅ `--target wasm-stellar-soroban` + wat2wasm; no promise_* |
| C.8 | EmitWat storage remap off NEAR `storage_*` | ✅ Soroban bridge: scalar read/write → `_get`/`_put` |
| C.9 | Soroban `require_auth` for caller entrypoints | ✅ prologue `require_auth_for_args` when entry uses `callerSender` |

**Business-check + auth materialization (C.2–C.9):**

| Author surface | EVM | Solana | NEAR | Soroban |
|---|---|---|---|---|
| `require*` / `assert` / `guard_owner` | revert | assert trap + **authority signer @0** | `unreachable`/`panic` | same + **require_auth** prologue |
| `caller` / `userId` | `CALLER` | account[0] pubkey (`authority`) | predecessor | host auth stub + assert |
| `callerHash` / `userIdHash` | `hashWord(caller)` = keccak of padded address | sha256(full pubkey) **limb0** handle (Phase-1) | predecessor → sha256 Hash | host auth + hash path where lowered |
| `remoteCall` + logical peer | CALL | CPI | `promise_create` + **PeerMap** | `invoke_contract` + PeerMap |
| storage scalar | slots | account data | `storage_read/write` | **`_get`/`_put`** |
| TokenSpec (core FT) | ERC-20 artifact | SPL / Token-2022 plan | NEP-141 plan (+ `NearFungibleToken` body) | **no lane** |
| `Pausable` / `OwnablePausable` | revert guards | assert | panic/unreachable | same + auth when caller used |

**When to use Ownable vs OwnableHash**

| Policy | Owner type | Prefer when |
|--------|------------|-------------|
| `Stdlib.Ownable` | `.u64` handle | Triad product path; EVM address-width / Solana digest handle / NEAR u64 projection |
| `Stdlib.OwnableHash` | `.hash` | Identity-width owner (NEAR account hash; EVM keccak(caller); Solana limb0 of pubkey digest) |
| `Stdlib.OwnablePausable` | u64 owner + pause | Owner-gated pause without composing unauthenticated `Pausable` alone |

**Deferred (new chains):**

- CosmWasm WasmMsg full lower  
- Cloudflare Workers binding/fetch product path  

Gates: `just crosscall-materialize`, `just portable-remote-call-multi-target`,
`just primary-materialize`, `just ir-portability-smoke`,
`lake env lean --run Tests/PortableAuthMaterialize.lean`.

| Order | Slice | Status / why |
|---|---|---|
| 6 | Mark `Source.Solana` fixture-only; demote from product docs | ✅ Phase C.4 |
| 7 | Stdlib portable policies → multi-target lowering | ✅ Phase C.2–C.3 (Ownable); **next:** Pausable/Roles — see task plan below |
| 8 | Spec/Builder de-EVM naming | ✅ partial: `ConstructorParam` / `constructorParams` / `ConstructorInit*` / `abiWord?` / `defaultParamAbiWords`; historical `Evm*` + CLI `--evm-constructor-*` kept as aliases / host flags |

### Next backlog (task plan)

Concrete multi-wave tasks (policy multi-target → Token three-host loop →
remote/clients → author polish), acceptance criteria, and PR slices:

**[docs/superpowers/plans/2026-07-09-portable-sdk-unification.md](superpowers/plans/2026-07-09-portable-sdk-unification.md)**

Default execution order: **PR-A** (Pausable four-host) → PR-B → PR-C → PR-D
(NEAR NEP-141 emit). No new chains in that plan.

## 8. Success metrics

- Shared examples under `Examples/Product/` import **no** chain Surface modules.
- `TokenSpec` → EVM + Solana (+ later NEAR) without author-selected standard.
- New contributor tutorial: “write logic → pick target → deploy” with zero
  account/PDA/CPI mentions until the Extension chapter.
- Capability diagnostics remain the only “you can’t do that on this chain”
  feedback — never silent semantic change.

## 9. Non-goals (this phase)

- Replacing Solana’s token program with a custom per-token program by default.
- Full formal refinement of every materialization path before product default
  is usable.
- Unifying all chain economics (gas vs CU vs yocto) into one number for authors
  (budgets stay target-side, D-040).

## 10. Decision needed (product)

When a portable feature cannot be realized on a target:

1. **Reject at compile time** with capability id (default, preferred), or  
2. **Degrade** with a forced opt-in flag (e.g. `--allow-feature-drop`).

Recommendation: **(1) only.** Matches existing platform promise.

---

**Summary line for the team:**  
ProofForge is not “a multi-chain SDK where you write Solana in Lean.”  
It is **a business-intent compiler** where Solana Account/PDA/CPI, NEAR
Promise, EVM ABI/slots, and Move objects are **backend materializations** of
the same intent under `--target`.
