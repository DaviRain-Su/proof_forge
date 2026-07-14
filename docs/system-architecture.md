# ProofForge System Architecture Map

Status: **Current orientation map (2026-07-15)**

**中文深拆版（分层 + 各组件内部）：**
[zh/system-architecture.zh.md](zh/system-architecture.zh.md).

This document is a **whole-repo architecture picture**: what every major
component is, how data flows at compile time, and how validation/runtime
evidence attaches. It is intentionally visual-first (Mermaid). Source of truth
for *scheduling* remains [AGENTS.md](../AGENTS.md) and the current plans;
source of truth for *behavior* remains code and gates. Section **§12** expands
per-layer internal structure.

Related deep dives:

| Topic | Document |
|---|---|
| Canonical Core route | [architecture.md](architecture.md) |
| Backend obligations | [backend-interface.md](backend-interface.md) |
| Product authoring thesis | [product-authoring-architecture.md](product-authoring-architecture.md) |
| Intent / materializer (D-052) | [Portable Intent design](superpowers/specs/2026-07-12-portable-intent-abstraction-design.md) |
| IR vs target extensions (D-054) | [IR Target Extension Boundary](superpowers/specs/2026-07-14-ir-target-extension-boundary-design.md) |
| Per-target notes | [targets/README.md](targets/README.md) |

> **How to read the diagrams:** GitHub, many IDEs, and common Markdown
> renderers display Mermaid natively. No Excalidraw export is required for
> docs. If you want a free-form whiteboard copy, paste a diagram into
> [Excalidraw](https://excalidraw.com) as a sketch; keep this file as the
> checked-in truth.

---

## 1. One-sentence model

**ProofForge is a Lean 4 multi-target smart-contract compiler:** authors write
portable business logic once; the compiler lowers it through a checked
semantic core into **target-owned plans**, then into chain artifacts (Yul/sBPF/
WAT/…), and proves honesty with capability diagnostics, offline hosts, and
optional formal/differential gates.

```text
  business source  →  checked meaning  →  target plan  →  artifact  →  evidence
     (Lean DSL)         (Canonical Core)   (per chain)     (bin/wat)    (tests)
```

---

## 2. Bird's-eye: whole system

```mermaid
flowchart TB
  subgraph Authors["Authoring surfaces"]
    P["Examples/Product<br/>contract_source · TokenSpec · NFTSpec"]
    B["Examples/Backend<br/>chain fixtures / goldens"]
    T["Tests · TestFixtures"]
  end

  subgraph CLI["proof-forge CLI (ProofForge.Cli)"]
    TF["TargetFirst / Options"]
    TD["TargetDriver registry"]
    CL["ContractLoader · TokenLoader · NftLoader"]
  end

  subgraph Frontend["Frontend / normalization"]
    AU["Authored<br/>Syntax · Builder · Canonicalize"]
    CS["ContractSpec facade<br/>Legacy adapter path"]
    SU["Surface fixtures<br/>migration-only"]
    IT["Intent · Token · NFT materializers"]
  end

  subgraph Core["Checked meaning"]
    CC["IR.Core<br/>Syntax · Type · Validate · Semantics"]
    CP["CanonicalPipeline<br/>normalize → validate → capabilities"]
    CAP["Target.CapabilityPlan"]
  end

  subgraph TargetLayer["Target ownership"]
    REG["Target.Registry / knownIds"]
    HOP["HostOp catalogs<br/>Evm · Near · Solana · …"]
    MAT["Materialize · StorageBinding · Crosscall"]
  end

  subgraph Backends["Backend plans + renderers"]
    EVM["Backend.Evm<br/>Plan → Yul → solc"]
    SOL["Backend.Solana<br/>Plan → sBPF → ELF"]
    WH["Backend.WasmHost<br/>NearModulePlan → EmitWat"]
    STY["Backend.Stylus"]
    PSY["Backend.Psy · Aleo · Quint"]
  end

  subgraph Artifacts["Artifacts + clients"]
    ART["*.bin · *.yul · *.s · *.wat · *.wasm<br/>artifact JSON · deploy metadata · SDK schema"]
  end

  subgraph Evidence["Validation / runtime"]
    JK["just product · just check · focused gates"]
    TK["testkit Rust harnesses"]
    RT["Anvil · Mollusk · near-vm / offline host"]
    FV["ProofForgeFormalEvm / FormalSolana<br/>optional Lake libs"]
    DIFF["differential native oracles<br/>testkit/differential"]
  end

  P --> CL
  B --> CL
  T --> CL
  CL --> TF
  TF --> TD
  TD --> Frontend
  AU --> CP
  CS --> CP
  SU --> CP
  IT --> CS
  IT --> AU
  CP --> CC
  CP --> CAP
  CAP --> REG
  REG --> HOP
  HOP --> MAT
  CP --> Backends
  MAT --> Backends
  Backends --> ART
  ART --> Evidence
  JK --> ART
  TK --> ART
  RT --> ART
  FV -.-> CC
  DIFF --> ART
```

---

## 3. Repository / package layout

```mermaid
flowchart LR
  subgraph Lake["Lake packages"]
    PF["lean_lib ProofForge<br/>default compiler"]
    EXE["lean_exe proof-forge<br/>root: ProofForge.Cli"]
    TF["lean_lib TestFixtures"]
    FE["lean_lib ProofForgeFormalEvm<br/>powdr-backed, opt-in"]
    FS["lean_lib ProofForgeFormalSolana<br/>solanalib-backed, opt-in"]
  end

  subgraph Tree["Top-level trees"]
    SRC["ProofForge/<br/>Cli Frontend Contract IR<br/>Compiler Backend Target Runtime …"]
    EX["Examples/Product · Backend"]
    TS["Tests/"]
    SCR["scripts/ + justfile"]
    TK["testkit/ (Rust)"]
    TOOLS["tools/"]
    DOCS["docs/"]
  end

  PF --> EXE
  PF --> SRC
  FE -.-> PF
  FS -.-> PF
  EXE --> EX
  SCR --> EXE
  SCR --> TK
  TS --> PF
```

| Path | Role |
|---|---|
| `ProofForge/Cli/` | CLI parsing, loaders, target-first dispatch, emit/build/check, deploy helpers |
| `ProofForge/Frontend/` | Authored DSL normalize, Surface fixtures, ContractSpec facade |
| `ProofForge/Contract/` | Product-facing Source DSL, Stdlib, Token/NFT, Intent, SdkSchema |
| `ProofForge/IR/` | Portable/Legacy IR modules + **Canonical Core** (`IR/Core`) |
| `ProofForge/Compiler/` | Shared pipelines: CanonicalPipeline, Yul/Wasm/Psy printers |
| `ProofForge/Backend/` | Per-target plans and lowerers (Evm, Solana, WasmHost, Stylus, Psy, Aleo, Quint) |
| `ProofForge/Target/` | Registry, capabilities, HostOps, materialization, honesty |
| `ProofForge/Runtime/` | Runtime helpers (e.g. Psy) |
| `ProofForge/Protocols/` | Protocol peer contracts |
| `ProofForge/Util/` | Shared utilities |
| `Examples/Product/` | **Portable product sources** (business logic + `--target`) |
| `Examples/Backend/` | Chain-specific fixtures / goldens |
| `Tests/` | Lean unit/integration smoke |
| `scripts/` + `justfile` | Gate catalog (CI + local) |
| `testkit/` | Rust multi-backend compare / harnesses |
| `ProofForgeFormal/` | Heavyweight optional proofs (not default library) |

**Rule of thumb:** product authors live in `Examples/Product`. Chain plumbing
lives under `Backend/` + `Target/`. Formal proofs never gate the default build.

---

## 4. End-to-end compile pipeline (primary triad)

Public beta product compilers: **`evm`**, **`solana-sbpf-asm`**, **`wasm-near`**.

```mermaid
flowchart TB
  A["Lean product module<br/>Examples/Product/X.lean"] --> B["contract_source / AuthoredContract<br/>or TokenSpec / NFTSpec"]
  B --> C{"Input kind"}
  C -->|direct Authored<br/>cutover path| D["Frontend.Authored.Canonicalize"]
  C -->|ContractSpec<br/>compatibility| E["Frontend.ContractSpec.normalize"]
  C -->|Surface fixture| F["Frontend.Surface.normalize"]
  D --> G["Checked Canonical Core<br/>IR.Core contract + evidence"]
  E --> G
  F --> G
  G --> H["Validate Core<br/>types · effects · host calls"]
  H --> I["CapabilityPlan<br/>from target profile + HostOps"]
  I --> J{"--target"}
  J -->|evm| K["Backend.Evm.Plan.Core<br/>ModulePlan"]
  J -->|solana-sbpf-asm| L["Backend.Solana.Plan.Core<br/>SolanaModulePlan"]
  J -->|wasm-near| M["Backend.WasmHost NearModulePlan<br/>buildFromCore"]
  K --> K2["ToYul / Printer → .yul<br/>solc → bytecode + metadata"]
  L --> L2["sBPF Asm / BpfEncode<br/>→ .s / ELF + manifest"]
  M --> M2["EmitWat → .wat<br/>wat2wasm → .wasm + near metadata"]
  K2 --> N["Artifact JSON + deploy map<br/>+ optional SDK schema"]
  L2 --> N
  M2 --> N
```

### CLI shape (how a command runs)

```mermaid
sequenceDiagram
  participant U as User / CI
  participant C as proof-forge CLI
  participant L as ContractLoader
  participant P as CanonicalPipeline
  participant T as TargetDriver
  participant B as Backend plan
  participant X as External tool

  U->>C: build --target evm -o out Product/Counter.lean
  C->>L: load Lean product source
  L->>P: authored / ContractSpec / surface
  P->>P: normalize + Core validate + capabilities
  C->>T: resolve native driver for target
  T->>B: buildFromCore(checked, capabilityPlan)
  B->>B: target plan + render
  B->>X: solc / wat2wasm / sBPF tools as needed
  X-->>B: binary / diagnostics
  B-->>C: artifacts + metadata
  C-->>U: files under build/… + exit code
```

Typical local command:

```bash
lake env proof-forge build --target evm --root . \
  -o build/evm/Counter.bin Examples/Product/Counter.lean
```

---

## 5. Layer inventory (every major component)

### 5.1 Authoring / product layer (`Contract` + `Examples`)

```mermaid
flowchart TB
  subgraph DSL["ProofForge.Contract.Source"]
    SRC["portable ops: state, entry, assert,<br/>events, arithmetic, memory arrays…"]
    SOL["Source.Solana<br/>account / PDA / CPI grammar<br/>target-owned, not portable"]
    NEAR["Source.Near helpers<br/>facade over HostOps"]
  end

  subgraph Product["Examples/Product"]
    CTR["Counter · ValueVault · Tokens<br/>Vaults · Ownable · NFT · …"]
    CAT["catalog.json product matrix"]
  end

  subgraph Stdlib["Contract.Stdlib"]
    ERC["ERC-20/721/1155/165 · Ownable<br/>Pausable · AccessControl · UUPS…"]
    SPL["Solana / Metaplex candidates"]
    NFT["Near NFT / FT helpers"]
  end

  subgraph Intent["Intent family"]
    TOK["TokenSpec → materializers"]
    NFTS["NFTSpec → materializers"]
    REGI["Intent materializer registry<br/>(target, family) → Contract"]
  end

  CTR --> SRC
  CTR --> TOK
  CTR --> NFTS
  ERC --> SRC
  TOK --> REGI
  NFTS --> REGI
  REGI --> SRC
  SOL -.->|only after --target solana| SRC
```

| Component | Responsibility |
|---|---|
| `contract_source` macro | Product-facing Lean DSL → `AuthoredContract` (migration still has ContractSpec paths) |
| `TokenSpec` / `NFTSpec` | Intent-level product APIs; materializers produce contracts per target |
| `Stdlib/*` | Reusable patterns (often EVM-shaped standards with portable cores) |
| `Examples/Product` | **Only** shared business sources for multi-target demos |
| `Examples/Backend` | Target-specific fixtures (not product authoring) |

### 5.2 Frontend normalization

| Module | Input | Output | Notes |
|---|---|---|---|
| `Frontend.Authored.*` | `AuthoredContract` | Canonical Core | Direct cutover path (PR #104 direction) |
| `Frontend.ContractSpec.*` | `ContractSpec` / Legacy IR | Canonical Core | Compatibility facade during migration |
| `Frontend.Surface.*` | Temporary Surface AST fixtures | Canonical Core | Not product; deletion after A-CUT parity |
| `Frontend.Materialize` | Intent contracts | Concrete contracts | Registry-driven, no frontend `targetId` switch for portable ops |

**Non-negotiable:** portable normalization must not branch on `targetId`.
Target choice happens at the CLI / materializer boundary.

### 5.3 Canonical Core (`IR/Core`)

```mermaid
flowchart LR
  SYN["Syntax<br/>types · ops · blocks"] --> TY["Type"]
  TY --> VAL["Validate"]
  VAL --> SEM["Semantics / fuel<br/>reference interpreter"]
  VAL --> H["HostOp calls<br/>ids only, no chain code"]
  SEM --> CAP["feeds CapabilityPlan"]
  H --> CAP
```

Core owns **logical** meaning only:

- scalars / maps / arrays / control flow / asserts / events as semantic ops;
- `hostCall` carriers with versioned ids;
- **no** EVM slots, Solana account layouts, NEAR promise constructors in the
  long-term shared inductive (migration: IR-B* / D-054).

Physical layout is always a **target plan** concern.

### 5.4 Target layer (`ProofForge.Target`)

```mermaid
flowchart TB
  REG["Registry.knownIds<br/>list-targets"] --> PROF["per-target profile"]
  PROF --> CAP["Capability catalog"]
  PROF --> HOP["HostOp catalog + handlers"]
  PROF --> BIND["StorageBinding"]
  PROF --> XC["Crosscall / PeerMap<br/>ProtocolMaterialize"]
  CAP --> PRE["Preflight / honesty diagnostics"]
  HOP --> PRE
  PRE --> PLAN["Backend buildFromCore"]
```

| Piece | Role |
|---|---|
| `Registry` | Declares target ids and maturity-facing metadata |
| `Capability` | Open stable capability ids required by a program |
| `HostOp` / `HostOps/*` | Typed, versioned chain ops (EVM protocol, NEAR host, Solana syscalls…) |
| `StorageBinding` | Logical state → chain storage model |
| `Materialize` / `Crosscall*` | Peers, protocols, remote-call shapes |
| `PortableHonesty` | Fail-closed “we do not pretend” diagnostics |

### 5.5 Backends (plans → artifacts)

```mermaid
flowchart TB
  CORE["Checked Core + CapabilityPlan"] --> EVM
  CORE --> SOL
  CORE --> WH
  CORE --> OTHER

  subgraph EVM["evm"]
    EP["Plan.Core → ModulePlan"] --> EY["ToYul / Yul AST"]
    EY --> ES["solc → bytecode"]
    EP --> EM["Metadata · ABI · constructor"]
  end

  subgraph SOL["solana-sbpf-asm"]
    SP["Plan.Core → SolanaModulePlan"] --> SA["Asm / LabeledSbpf"]
    SA --> SB["BpfEncode → ELF"]
    SP --> SM["Manifest · IDL-ish client"]
  end

  subgraph WH["Wasm host family"]
    NP["NearModulePlan / WasmHost plan"] --> EW["EmitWat → WAT"]
    EW --> WW["wat2wasm"]
    NP --> HB["HostBridge<br/>near · cosmWasm · soroban"]
  end

  subgraph OTHER["Secondary / research"]
    ST["StylusPlan → HostIO Wasm or Rust oracle"]
    PS["Psy Plan → .psy → Dargo"]
    AL["Aleo → Leo source"]
    QU["Quint emit / model-check lane"]
  end
```

| Target id | Plan owner | Artifact path | Evidence tools |
|---|---|---|---|
| `evm` | `Backend.Evm.Plan` | Yul → `solc` bytecode | Foundry, Anvil |
| `solana-sbpf-asm` | `Backend.Solana.Plan` | sBPF asm → ELF | Mollusk, Surfpool, Pinocchio |
| `wasm-near` | `Backend.WasmHost` Near plan | WAT → Wasm | offline host, `near-vm-runner` |
| `wasm-cosmwasm` | WasmHost + CosmWasm bridge | WAT → Wasm | cosmwasm-check, offline host |
| `wasm-stellar-soroban` | WasmHost + Soroban bridge | WAT → Wasm | custom offline host only |
| `wasm-arbitrum-stylus` | `Backend.Stylus` | HostIO Wasm / Rust | stylus gates, Nitro later |
| `psy-dpn` | `Backend.Psy` | `.psy` + Dargo | dargo execute |
| `aleo-leo` | `Backend.Aleo` | Leo package | leo build (restricted) |
| `quint` | CLI-only | Quint models | model-check lane |

### 5.6 CLI surface (`ProofForge.Cli`)

| Area | Modules (representative) | Job |
|---|---|---|
| Entry | `Cli.lean` `main` | Parse argv, exit codes |
| Target-first | `TargetFirst`, `TargetDriver`, `Options` | Map user flags → native ops |
| Loaders | `ContractLoader`, `TokenLoader`, `NftLoader` | Resolve Lean product sources |
| Emit/build | `EvmArtifacts`, `SolanaArtifacts`, `EmitWatArtifacts`, `StylusArtifacts`, `PsyArtifacts` | Write files under `build/` |
| Metadata | `Metadata`, `Artifact`, `ConstructorAbi`, `EvmAbi` | JSON / deploy / ABI honesty |
| Deploy helpers | `Deploy`, `SolanaCommands`, `WasmNearCommands` | Local deploy smoke wrappers |
| Check | `Check` | Static check routes |

### 5.7 Validation, testkit, formal, differential

```mermaid
flowchart TB
  subgraph Gates["just gates"]
    JP["just product"]
    JC["just check / check-fast"]
    JT["target recipes<br/>evm-all · near-* · solana-*"]
  end

  subgraph Testkit["testkit/ Rust"]
    SC["scenarios/"]
    CMP["compare/near · …"]
    HV["harness-evm · harness-solana · harness-near"]
    DIFF["differential/ v1 schemas + pilots"]
  end

  subgraph Formal["Optional formal"]
    FE["ProofForgeFormalEvm + powdr"]
    FS["ProofForgeFormalSolana + solanalib"]
  end

  JP --> ART["compiler artifacts"]
  JC --> ART
  JT --> ART
  SC --> HV
  ART --> HV
  ART --> DIFF
  FE -.->|does not import into default ProofForge| CORE["IR.Core"]
  FS -.-> CORE
```

| Layer | What it proves |
|---|---|
| `just product` | Portable product catalog still builds for required targets |
| `just check` | Large parallel static/smoke matrix |
| testkit compare | Size/fuel/offline equivalence vs native references |
| differential pilots | Fail-closed multi-dimension semantic match vs independent Solidity/Pinocchio/near-sdk |
| Formal libs | Deeper refinement against external ISA/semantics (opt-in, heavy) |

---

## 6. Data objects that cross boundaries

```mermaid
classDiagram
  class AuthoredContract {
    name
    state
    entrypoints
    events
  }
  class ContractSpec {
    "legacy / compatibility exchange"
    module IR.Module?
  }
  class CheckedCanonicalContract {
    core program
    evidence
  }
  class CapabilityPlan {
    required capabilities
    host ops
  }
  class ModulePlan {
    "EVM physical plan"
  }
  class SolanaModulePlan {
    "accounts · CPI · sBPF shape"
  }
  class NearModulePlan {
    "Wasm host layout · imports"
  }
  class ArtifactBundle {
    bytes
    metadata JSON
    deploy map
  }

  AuthoredContract --> CheckedCanonicalContract : Canonicalize
  ContractSpec --> CheckedCanonicalContract : normalize
  CheckedCanonicalContract --> CapabilityPlan : resolve
  CheckedCanonicalContract --> ModulePlan : buildFromCore
  CheckedCanonicalContract --> SolanaModulePlan : buildFromCore
  CheckedCanonicalContract --> NearModulePlan : buildFromCore
  ModulePlan --> ArtifactBundle
  SolanaModulePlan --> ArtifactBundle
  NearModulePlan --> ArtifactBundle
```

**Evidence vs meaning:** diagnostics / spans / migration traces must not change
capability selection, plan layout, or artifact hashes
([architecture.md](architecture.md)).

---

## 7. Worked example: Counter across three targets

```mermaid
flowchart LR
  S["Examples/Product/Counter.lean<br/>initialize · increment · get"] --> N["normalize → Core"]
  N --> E["--target evm<br/>ModulePlan → Yul → solc"]
  N --> SO["--target solana-sbpf-asm<br/>SolanaModulePlan → sBPF"]
  N --> W["--target wasm-near<br/>NearModulePlan → WAT"]
  E --> ER["Anvil / Foundry"]
  SO --> SR["Mollusk / Pinocchio"]
  W --> WR["offline host / near-vm"]
  ER --> EQ["same logical steps<br/>different gas/CU units"]
  SR --> EQ
  WR --> EQ
```

Same source, three plans, three runtimes. Resources (gas, CU, fuel) stay
**target-local** and are never averaged into a fake cross-chain score.

---

## 8. Migration / dual-path honesty (read this)

The architecture is **converging** to one production path:

```text
Authored / Intent → checked Canonical Core → target plan → artifact
```

Still present during migration (do not treat as product features forever):

| Residual | Why it exists | Exit |
|---|---|---|
| `ContractSpec` + Legacy IR adapters | Parity and gradual cutover | A-CUT / legacy-replacement D* |
| Surface fixtures | Temporary frontend tests | A-CUT4 |
| NEAR `NearSpec` product FT entry | Historical TokenSpec path | NEAR-R3–R5 |
| Shared IR target leakage | Pre-D-054 constructors | IR-B* allowlist → empty |
| Secondary hosts (Soroban/CosmWasm) | Counter MVP bridges | depth after D-056 / #104 |

PR **#104** (direct authoring cutover + native differential) is the active
merge that rewrites the authoring spine; secondary host depth waits on it
(D-056).

---

## 9. Component checklist (inventory)

Use this as a “have I understood every box?” list.

### Compiler core
- [ ] `Cli` entry + TargetDriver
- [ ] Loaders (contract / token / NFT)
- [ ] Authored / ContractSpec / Surface frontends
- [ ] CanonicalPipeline
- [ ] IR.Core syntax/type/validate/semantics
- [ ] CapabilityPlan
- [ ] HostOp open catalogs
- [ ] StorageBinding + crosscall materialize
- [ ] EVM / Solana / WasmHost plans
- [ ] Yul / Wasm / Psy printers
- [ ] Artifact + metadata writers

### Product surfaces
- [ ] `Examples/Product` catalog
- [ ] Stdlib families
- [ ] TokenSpec / NFTSpec materializers
- [ ] Solana grammar ownership under `Source.Solana`

### Evidence
- [ ] `just product` / `just check*`
- [ ] scripts under `scripts/{evm,near,solana,portable,canonical,differential}`
- [ ] testkit harnesses + scenarios
- [ ] optional formal Lake libs
- [ ] differential reference corpus

### Non-product but real
- [ ] Stylus hybrid backend
- [ ] Psy / Aleo research sourcegen
- [ ] Quint CLI verification lane
- [ ] OpenVM **docs-only** brief (no code path)

---

## 10. How to explore the code safely

1. Start at `ProofForge/Cli.lean` (`main`) and `Cli/TargetDriver.lean`.
2. Follow one product: `Examples/Product/Counter.lean` → frontend normalize →
   `Compiler/CanonicalPipeline.lean`.
3. Open one backend plan: `Backend/Evm/Plan`, `Backend/Solana/Plan`, or
   `Backend/WasmHost`.
4. Run a focused gate, not the whole matrix:

```bash
just product          # product-first CI gate
just check-fast       # affected-path inner loop
just portable-counter-multi-target
```

5. Read target notes under `docs/targets/` for maturity honesty before
   assuming a route is production-ready.

---

## 11. Document maintenance

When a **layer boundary** moves (new frontend owner, deleted Legacy path, new
target plan), update **this map** in the same change as the design/plan
update. Do not let this file advertise a path that `rg` and `just` gates no
longer implement.

---

## 12. Layer-deep internals

Chinese deep-dive (same diagrams, full narrative):
[system-architecture.zh.md](zh/system-architecture.zh.md).

### 12.1 CLI internals (`ProofForge/Cli`)

```mermaid
flowchart TB
  MAIN["Cli.lean main"] --> OPT["Options · Usage · LegacyArgs"]
  MAIN --> TF["TargetFirst"]
  TF --> TD["TargetDriver<br/>native vs legacy dispatch"]
  TD --> NB["NativeBuildOp"]
  MAIN --> LD["ContractLoader · TokenLoader · NftLoader"]
  LD --> PIPE["CanonicalPipeline / frontend"]
  TD --> ART["EvmArtifacts · SolanaArtifacts<br/>EmitWatArtifacts · StylusArtifacts<br/>PsyArtifacts · LearnArtifacts"]
  ART --> META["Metadata · Artifact · ConstructorAbi · EvmAbi"]
  MAIN --> CHK["Check"]
  MAIN --> DEP["Deploy · SolanaCommands · WasmNearCommands"]
  MAIN --> UTIL["Process · FileUtil · HexUtil · JsonUtil · ArrayUtil"]
```

### 12.2 Frontend internals

```mermaid
flowchart TB
  subgraph Authored["Frontend.Authored"]
    AS["Syntax · Type · Builder"]
    AV["Validate · Classification"]
    AN["Normalize Expr/Stmt/Env"]
    AC["Canonicalize Expr/Stmt/Env"]
  end
  subgraph Spec["Frontend.ContractSpec"]
    CSN["Normalize facade"]
  end
  subgraph Surface["Frontend.Surface"]
    SS["Syntax · Type · Validate"]
    SN["Normalize · Semantics · Protocol"]
    SC["Collections Queue/Set"]
    SH["Host.Near fixtures"]
  end
  subgraph Mat["Frontend.Materialize"]
    ME["Evm Token · NFT · ERC4626 · ContextProducts"]
  end
  AS --> AV --> AN --> AC --> CORE["IR.Core"]
  CSN --> CORE
  SS --> SN --> CORE
  Mat --> AS
  Mat --> CSN
```

### 12.3 Canonical Core internals (`IR/Core`)

```mermaid
flowchart LR
  ID["Id"] --> SYN["Syntax"]
  SYN --> TY["Type"]
  TY --> VAL["Validate"]
  VAL --> HOP["HostOp references"]
  VAL --> ST["Storage logical shape"]
  VAL --> SEM["Semantics · Semantics/* · fuel"]
  ERR["Error"] --> VAL
```

### 12.4 Target layer internals

```mermaid
flowchart TB
  REG["Registry · BackendRegistry"] --> CAP["Capability"]
  REG --> HOPI["HostOp · HostOpRegistry"]
  HOPI --> HOPS["HostOps/Evm · Near · Solana"]
  CAP --> PRE["Preflight · PortableHonesty · Check"]
  HOPS --> PRE
  REG --> BIND["StorageBinding"]
  REG --> XC["CrosscallMaterialize · PeerMap<br/>ProtocolMaterialize"]
  PRE --> MAT["Materialize · Plan"]
  BIND --> MAT
  XC --> MAT
  MAT --> ART["ArtifactBundle"]
  HB["HostBridge · HostRuntime"] --> MAT
```

### 12.5 EVM backend internals

```mermaid
flowchart LR
  C["Core + caps"] --> P["Plan / Plan.Core · Storage"]
  P --> V["Validate/*"]
  P --> L["Lower/*"]
  L --> Y["ToYul/*"]
  Y --> YA["Compiler.Yul.AST"]
  YA --> YP["Compiler.Yul.Printer"]
  YP --> SOLC["solc"]
  P --> M["Metadata · AbiEncode · ConstructorInit"]
  P --> R["Refinement · YulSemantics · optional Formal"]
```

### 12.6 Solana backend internals

```mermaid
flowchart LR
  C["Core + caps"] --> P["Plan / Plan.Core"]
  P --> E["Extension · Syscalls · StateLayout"]
  P --> A["Asm · LabeledSbpf · SbpfAsm"]
  A --> B["BpfEncode · BinaryLayout"]
  B --> ELF["ELF + Manifest · Package · Idl · Client"]
  P --> X["PortableCrosscall · Materialize"]
  A --> EX["SbpfExec / Interpreter smoke"]
```

### 12.7 WasmHost backend internals

```mermaid
flowchart TB
  C["Core + caps"] --> NP["NearModulePlan / ModulePlan / Plan"]
  NP --> LAY["Layout · Memory · Locals · StructPlan · ArrayHeap"]
  NP --> ABI["NearAbiPlan · HostABI · Imports · Params · Return"]
  NP --> LOW["Statement · Scalar · Map · Event · Assert · Crosscall · Promise"]
  LOW --> EW["EmitWat · ModuleAssembly"]
  EW --> WAT["Compiler.Wasm.AST + Printer"]
  WAT --> W2W["wat2wasm"]
  NP --> BR["NearHost · CosmWasmHost · SorobanHost"]
  NP --> JR["JsonReturn · JsonEncode"]
  NP --> RF["Refinement · WasmExec / Interpreter"]
```

### 12.8 Validation stack internals

```mermaid
flowchart TB
  JUST["justfile recipes"] --> SCR["scripts/{portable,canonical,evm,near,solana,differential,…}"]
  SCR --> CLI["proof-forge / lake env lean --run"]
  SCR --> TK["testkit Cargo workspace"]
  TK --> H["harness-evm · harness-solana · harness-near · harness-quint"]
  TK --> CMP["compare/* native references"]
  TK --> D["differential schemas + pilots"]
  F["ProofForgeFormalEvm / FormalSolana"] -.->|opt-in Lake| CORE["IR.Core anchors"]
```
