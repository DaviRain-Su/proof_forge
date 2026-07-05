# JAR PVM Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a docs-first path, then a gated spike path, for a JAR/Jarchain `jar-pvm` target that lowers ProofForge portable IR into JAR PVM2/JAVM artifacts.

**Architecture:** Treat JAR as a new PVM-family contract-execution candidate, not an EVM-compatible profile, not a Wasm host, and not a ZK circuit target. The intended implementation pipeline is `ContractSpec / portable IR -> JAR capability plan -> JAR PVM2 semantic plan -> RV64E/PVM2 AST -> assembly/bytes + image manifest -> optional JAVM runner smoke`.

**Tech Stack:** Lean 4/Lake, ProofForge portable IR and target registry, JAR Lean spec modules (`Jar.PVM2.*`, `Jar.Cap`, `Jar.Kernel`, `Jar.SubVM`, `Jar.JAVM`) as research reference, JAR Rust workspace (`javm`, `javm-exec`, `javm-transpiler`) as optional spike/runtime tooling.

## Global Constraints

- Start docs-first: do not add `jar-pvm` to `ProofForge.Target.Registry` until the target note and decision entry classify the target and name the spike exit criteria.
- Keep target semantics staged: do not emit opaque bytes directly from IR; preserve `IR -> plan -> AST/assembly -> printer/artifact` boundaries.
- Do not require a JAR full node or KVM `nub` path for the first ProofForge spike; the first executable validation must use an interpreter/transpiler path or skip gracefully.
- Do not add JAR-only effects to `ProofForge.IR.Contract` unless at least two target families share the same semantic shape; use target extensions/capability metadata first.
- Capability ids are append-only. Candidate `jar.*`, `cap.*`, `pvm.*`, and `artifact.*` ids stay docs-only until the registry task is explicitly scheduled.
- If English docs change, update `scripts/i18n/manifest.json` and the matching zh docs or mark the new doc with an explicit translation plan consistent with existing repo practice.
- Validation commands for any public `just` recipe must also be recorded in `docs/validation-gates.md`.

---

## Current Repo Shape

Files already present and relevant:

- `ProofForge/Target/Registry.lean`: defines `TargetFamily`, `ArtifactKind`, `TargetProfile`, existing profiles, and target lookup.
- `ProofForge/Target/Capability.lean`: owns canonical capability ids.
- `ProofForge/Target/Adapter.lean`: converts a `ContractSpec` or `IR.Module` into a `CapabilityPlan` and rejects unsupported capabilities.
- `ProofForge/IR/Contract.lean`: defines `Module`, `Entrypoint`, `Statement`, `Expr`, `Effect`, and capability derivation.
- `ProofForge/Backend/Solana/SbpfAsm.lean`: closest direct-assembly backend precedent.
- `ProofForge/Backend/WasmNear/EmitWat.lean`: closest `IR -> AST -> printer` precedent.
- `ProofForge/Backend/Psy/*` and `ProofForge/Compiler/Psy/*`: closest recent plan/AST/sourcegen split.
- `ProofForge/Cli/Fixture.lean`: target-first fixture/format whitelist.
- `docs/targets/README.md`, `docs/decisions.md`, `docs/capability-registry.md`, `docs/target-roadmap.md`, `docs/implementation-backlog.md`: docs-first target intake surfaces.

Files to create when implementation is scheduled:

- `docs/targets/jar-pvm.md`: research target note and spike acceptance criteria.
- `docs/zh/targets/jar-pvm.zh.md`: Chinese mirror if this doc is included in the i18n manifest.
- `ProofForge/Compiler/JarPvm/AST.lean`: typed PVM2/RV64E assembly-level AST.
- `ProofForge/Compiler/JarPvm/Printer.lean`: renders PVM2 assembly text or byte listing from the AST.
- `ProofForge/Compiler/JarPvm.lean`: compiler namespace aggregator.
- `ProofForge/Backend/JarPvm/Plan.lean`: JAR-specific semantic plan for state layout, endpoints, cap slots, and host-call/yield operations.
- `ProofForge/Backend/JarPvm/Lower.lean`: portable IR to plan lowering and validation.
- `ProofForge/Backend/JarPvm/IR.lean`: plan to AST builder and public render functions.
- `ProofForge/Backend/JarPvm/Metadata.lean`: artifact/deploy metadata for image hash placeholder, endpoint table, cap slots, and required tools.
- `ProofForge/Backend/JarPvm.lean`: backend namespace aggregator.
- `Tests/JarPvmTarget.lean`: target registry/profile smoke after registry admission.
- `Tests/JarPvmPrinter.lean`: AST/printer unit tests.
- `Tests/JarPvmCounter.lean`: Counter lowering smoke.
- `scripts/jar-pvm/counter-smoke.sh`: optional local command wrapping CLI and, when available, JAR runtime tooling.

## Task 1: Docs-First JAR Classification

**Files:**
- Create: `docs/targets/jar-pvm.md`
- Modify: `docs/targets/README.md`
- Modify: `docs/decisions.md`
- Modify: `docs/capability-registry.md`
- Modify: `docs/target-roadmap.md`
- Modify: `docs/implementation-backlog.md`
- Modify: `scripts/i18n/manifest.json`
- Create or modify: `docs/zh/targets/jar-pvm.zh.md`, `docs/zh/targets-README.zh.md`, `docs/zh/decisions.zh.md`, `docs/zh/capability-registry.zh.md`, `docs/zh/target-roadmap.zh.md`, `docs/zh/implementation-backlog.zh.md`

**Interfaces:**
- Consumes: JAR upstream facts from `https://github.com/jarchain/jar` at commit `10b5b92e7661b1cc64b28dd3b4a0a237d8f34b2c`.
- Produces: A reviewable target note that classifies `jar-pvm` and blocks registry/backend work until the spike exit criteria are accepted.

- [ ] **Step 1: Write the target note**

Create `docs/targets/jar-pvm.md` with this content:

```markdown
# JAR PVM Target

Status: **Research (docs-first candidate)**

JAR (Join-Accumulate Refine) is a JAM-derived chain protocol with a Lean 4
formal specification and a Rust JAVM implementation path. Its execution target
is PVM2/JAVM: RV64E plus standard extensions, the `Xjar` custom extension, and
a JAR execution-environment interface. The kernel model is content-addressed,
by-value, and capability-threaded: Instances hold Images plus CNodes, state is
content-addressed values, and snapshot/revert is modeled through `MGMT_COPY`.

## Classification

`jar-pvm` is a candidate **PVM-family contract execution target**.

It is not:

- an EVM-compatible chain profile;
- a Wasm-host target;
- a ZK circuit sourcegen target;
- a full-node or consensus integration.

The ProofForge integration should start at contract execution: portable IR
entrypoints lower to a JAR Image, endpoint table, CNode/cap layout, and PVM2
code artifact. Safrole, GRANDPA, genesis scoring, and full `nub` KVM hosting
stay outside the first spike.

## Target Shape

```text
contract_source / ContractSpec
  -> portable IR
  -> JAR capability plan
  -> JAR PVM2 semantic plan
  -> RV64E/PVM2 AST
  -> assembly or byte listing + JAR image manifest
  -> optional JAVM interpreter/transpiler smoke
```

## Candidate Artifact Set

The first spike emits an inspection-friendly artifact set:

- `Counter.jar-pvm.s`: RV64E/PVM2 assembly text or byte listing.
- `Counter.jar-image.json`: ProofForge artifact metadata with endpoints,
  memory mappings, CNode slots, cap requirements, and required external tools.
- `Counter.jar-deploy.json`: optional deploy plan describing initial CNode and
  DataCap initialization. This may be deferred until runtime tooling is stable.

The spike must not require a JAR full node. Interpreter or transpiler validation
may be optional and must skip gracefully when JAR Rust tooling is unavailable.

## Initial Capability Mapping

| ProofForge capability | JAR mapping | Spike support |
|---|---|---|
| `storage.scalar` | CNode slot backed by DataCap/state bytes | yes for `U64` Counter |
| `caller.sender` | invocation payload or scratchpad context | docs-only until runner ABI is selected |
| `events.emit` | apply output `emits` or kernel yield | docs-only |
| `crosscall.invoke` | `CALL` through Instance cap | later |
| `crypto.hash` | PVM2 code, host call, or kernel service | later |
| `assertions.check` | fatal `trap`/panic path with artifact error metadata | yes for simple assertions |
| `control.conditional` | RV64E branches | yes |
| `control.bounded_loop` | RV64E branch loop with static bound | later |

## Candidate Capabilities Not Yet Registered

| Candidate id | Meaning | Why it is separate |
|---|---|---|
| `vm.pvm2` | Artifact executes under JAR PVM2/JAVM | JAR PVM2 has RV64E + Xjar + EEI semantics, not generic RISC-V |
| `cap.cnode` | Contract state is represented by CNode slots | More precise than generic storage layout |
| `cap.data` | Contract stores content-addressed Data caps | Needed for by-value state artifacts |
| `cap.instance_call` | Cross-call requires Instance caps | Different from EVM address calls and Solana CPI accounts |
| `cap.mgmt_copy` | Snapshot/revert through `MGMT_COPY` | JAR-specific capability operation |
| `artifact.jar_image` | Build emits a JAR Image/deploy manifest | Artifact-level requirement |
| `pvm.xjar_hostcall` | Lowering emits `Xjar` host/control ops | Custom-0 host operation surface |

Do not add these to `ProofForge.Target.Capability` until a spike branch needs
compile-time diagnostics and the target profile is reviewed.

## Research Exit Criteria

Research exits to Spike only when:

1. the target family and artifact kind names are accepted;
2. the Counter subset is stated exactly (`U64` scalar state, `increment`, `get`,
   simple assertion/trap support);
3. the artifact manifest schema is accepted;
4. the validation command is selected and can skip gracefully outside Linux/KVM;
5. registry changes are explicitly scheduled.
```

- [ ] **Step 2: Link the target note**

Add `JAR PVM` to the Docs-Only Parked Research table in `docs/targets/README.md`:

```markdown
| [JAR PVM](jar-pvm.md) | PVM-family contract execution | Parked until the JAR PVM2/JAVM spike is explicitly scheduled; starts docs-first with no registry/code changes. |
```

Add this bullet to the Documents list:

```markdown
- [JAR PVM target](jar-pvm.md)
```

- [ ] **Step 3: Record the design decision**

Append a new decision row after the current latest decision in `docs/decisions.md`:

```markdown
| D-050 | 2026-07-06 | Classify **`jar-pvm`** as a docs-first PVM-family contract-execution candidate | JAR exposes a Lean 4 spec plus Rust JAVM tooling for PVM2 (`RV64E + Xjar + EEI`) and a capability-threaded kernel. ProofForge should start with a Counter-level contract execution target note and artifact schema, not registry/code changes, full consensus, or `nub` KVM integration. |
```

Add this target-family row in the classification table:

```markdown
| PVM-family contract execution research | `jar-pvm` (candidate, docs only) | Portable IR -> JAR capability plan -> PVM2 semantic plan -> RV64E/PVM2 AST -> assembly/byte listing + JAR Image manifest -> optional JAVM interpreter/transpiler validation |
```

- [ ] **Step 4: Document candidate capabilities**

Add a `### JAR PVM` section under `## Candidate Capabilities Not Yet Registered` in `docs/capability-registry.md`:

```markdown
### JAR PVM

See [JAR PVM target](targets/jar-pvm.md).

| Candidate id | Portable meaning | Why it is separate |
|---|---|---|
| `vm.pvm2` | Artifact executes under JAR PVM2/JAVM | PVM2 is RV64E plus `Xjar` and a JAR EEI, not generic RISC-V |
| `cap.cnode` | Contract state and authority are represented through CNode slots | More precise than generic scalar/map storage |
| `cap.data` | Contract persistent values use content-addressed Data caps | Required by by-value JAR state artifacts |
| `cap.instance_call` | Cross-contract call uses Instance capability possession | Different from address-based EVM calls and account-meta Solana CPI |
| `cap.mgmt_copy` | Snapshot/revert uses `MGMT_COPY` | JAR-specific management operation |
| `artifact.jar_image` | Build emits a JAR Image/deploy manifest | Artifact metadata requirement, not runtime behavior |
| `pvm.xjar_hostcall` | Lowering emits `Xjar` custom-0 host/control operations | Custom host-call/control surface unique to JAR PVM2 |
```

- [ ] **Step 5: Place it in the roadmap**

Add JAR PVM to `docs/target-roadmap.md` as a Tier 2 conditional or Tier 3 parked target. Use Tier 2 only if the product lane explicitly wants a VM-backend proof after CLI M3/M4; otherwise use Tier 3.

Recommended Tier 3 row:

```markdown
| `jar-pvm` | PVM2/JAVM target note accepted + one scheduled VM-backend spike | New PVM2 AST/printer, JAR Image manifest, optional JAVM runner smoke | Parked research; strategic fit is high, but it should not displace explicitly scheduled Tier-1 work |
```

- [ ] **Step 6: Add backlog entry**

Add this workstream to `docs/implementation-backlog.md`:

```markdown
## Workstream: JAR PVM Research Target

Goal: decide whether ProofForge should add a JAR PVM2/JAVM contract execution
target and, if accepted, scope the smallest Counter-level spike.

Tasks:

- Done when scheduled: classify `jar-pvm` as a PVM-family contract-execution
  candidate in `docs/targets/jar-pvm.md`.
- Define the Counter subset: `U64` scalar state, `increment`, `get`, conditional
  branch, and assertion trap.
- Draft the artifact schema for `Counter.jar-pvm.s` and
  `Counter.jar-image.json`.
- Decide whether the spike validates through JAR `javm-transpiler`, a direct
  `javm-exec` interpreter harness, or a pure golden artifact until tooling
  stabilizes.

Acceptance criteria:

- No registry or code changes land before the target note and D-050 are reviewed.
- The spike command does not require a JAR full node or KVM.
- Unsupported JAR-specific capabilities remain docs-only until a reviewed
  target profile needs them.
```

- [ ] **Step 7: Update i18n and validate docs**

Run:

```bash
python3 -m json.tool scripts/i18n/manifest.json >/tmp/proof-forge-i18n-manifest.json
scripts/i18n/check-sync.sh
git diff --check
```

Expected:

```text
All translations up to date.
```

If the sync script reports new or stale docs, update the matching zh files and
manifest hashes in the same branch.

- [ ] **Step 8: Commit docs-first work**

Run:

```bash
git add docs/targets/jar-pvm.md docs/targets/README.md docs/decisions.md docs/capability-registry.md docs/target-roadmap.md docs/implementation-backlog.md scripts/i18n/manifest.json docs/zh
git commit -m "docs: classify jar pvm target"
```

## Task 2: Registry Admission Design

**Files:**
- Modify: `ProofForge/Target/Registry.lean`
- Modify: `ProofForge/Target/Capability.lean` only if accepted candidate capabilities become compile-time ids
- Modify: `Tests/TargetRegistry.lean`
- Create: `Tests/JarPvmTarget.lean`
- Modify: `lakefile.lean` only if the new test is wired as a separate executable target

**Interfaces:**
- Consumes: accepted `docs/targets/jar-pvm.md` exit criteria from Task 1.
- Produces: a `TargetProfile` named `jar-pvm` with a narrow capability set and target lookup smoke coverage.

- [ ] **Step 1: Write failing registry expectations**

Add these checks to `Tests/TargetRegistry.lean`:

```lean
  let jarProfile <- requireSome (find? "jar-pvm") "missing jar-pvm target profile"
  require (jarProfile.id == "jar-pvm") "jar-pvm target id mismatch"
  require (jarProfile.family.id == "pvm") "jar-pvm family mismatch"
  require (jarProfile.artifactKind.id == "jar-image") "jar-pvm artifact kind mismatch"
  require (knownIds.contains "jar-pvm") "jar-pvm id missing from known ids"
```

Run:

```bash
lake env lean --run Tests/TargetRegistry.lean
```

Expected:

```text
missing jar-pvm target profile
```

- [ ] **Step 2: Add target family and artifact kind**

Modify `ProofForge/Target/Registry.lean`:

```lean
inductive TargetFamily where
  | evm
  | wasmHost
  | solana
  | move
  | zkCircuitSourcegen
  | pvm
  deriving BEq, DecidableEq, Repr

def TargetFamily.id : TargetFamily -> String
  | .evm => "evm"
  | .wasmHost => "wasm-host"
  | .solana => "solana"
  | .move => "move"
  | .zkCircuitSourcegen => "zk-circuit-sourcegen"
  | .pvm => "pvm"

inductive ArtifactKind where
  | evmBytecode
  | yul
  | wasm
  | solanaElf
  | movePackage
  | psyCircuitJson
  | jarImage
  deriving BEq, DecidableEq, Repr

def ArtifactKind.id : ArtifactKind -> String
  | .evmBytecode => "evm-bytecode"
  | .yul => "yul"
  | .wasm => "wasm"
  | .solanaElf => "solana-elf"
  | .movePackage => "move-package"
  | .psyCircuitJson => "psy-circuit-json"
  | .jarImage => "jar-image"
```

- [ ] **Step 3: Add the narrow profile**

Add this profile before `all` in `ProofForge/Target/Registry.lean`:

```lean
def jarPvm : TargetProfile := {
  id := "jar-pvm"
  family := .pvm
  artifactKind := .jarImage
  capabilities := #[
    .storageScalar,
    .assertions,
    .controlConditional
  ]
  requiredTools := #["jar-javm"]
}
```

Add `jarPvm` to `all`:

```lean
def all : Array TargetProfile := #[
  evm,
  wasmNear,
  wasmCosmWasm,
  solanaSbpfAsm,
  wasmCloudflareWorkers,
  solanaSbpfLinker,
  solanaZigFork,
  moveAptos,
  moveSui,
  psyDpn,
  jarPvm
]
```

- [ ] **Step 4: Run target smoke**

Run:

```bash
lake build ProofForge.Target
lake env lean --run Tests/TargetRegistry.lean
```

Expected:

```text
target-registry: ok
```

- [ ] **Step 5: Commit registry admission**

Run:

```bash
git add ProofForge/Target/Registry.lean Tests/TargetRegistry.lean
git commit -m "feat: register jar pvm target profile"
```

## Task 3: JAR PVM2 AST And Printer

**Files:**
- Create: `ProofForge/Compiler/JarPvm/AST.lean`
- Create: `ProofForge/Compiler/JarPvm/Printer.lean`
- Create: `ProofForge/Compiler/JarPvm.lean`
- Create: `Tests/JarPvmPrinter.lean`
- Modify: `ProofForge.lean`

**Interfaces:**
- Consumes: none beyond Lean core and `String`.
- Produces: an AST/printer pair for a small RV64E/PVM2 subset that later lowering can target.

- [ ] **Step 1: Write the failing printer test**

Create `Tests/JarPvmPrinter.lean`:

```lean
import ProofForge.Compiler.JarPvm.AST
import ProofForge.Compiler.JarPvm.Printer

namespace ProofForge.Tests.JarPvmPrinter

open ProofForge.Compiler.JarPvm

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO UInt32 := do
  let program : Program := {
    name := "Counter"
    text := #[
      .label "entry",
      .li .a0 1,
      .li .a1 2,
      .add .a0 .a0 .a1,
      .trap
    ]
  }
  let rendered := renderProgram program
  require (rendered.contains ".section .text") "missing text section"
  require (rendered.contains "entry:") "missing entry label"
  require (rendered.contains "li a0, 1") "missing li"
  require (rendered.contains "add a0, a0, a1") "missing add"
  require (rendered.contains ".insn r 0x0b, 0, 0, zero, zero, zero") "missing Xjar trap encoding"
  IO.println "jar-pvm-printer: ok"
  return 0

end ProofForge.Tests.JarPvmPrinter

def main : IO UInt32 :=
  ProofForge.Tests.JarPvmPrinter.main
```

Run:

```bash
lake env lean --run Tests/JarPvmPrinter.lean
```

Expected:

```text
unknown package 'ProofForge.Compiler.JarPvm.AST'
```

- [ ] **Step 2: Add AST types**

Create `ProofForge/Compiler/JarPvm/AST.lean`:

```lean
namespace ProofForge.Compiler.JarPvm

inductive Reg where
  | zero | ra | sp | gp | tp | t0 | t1 | t2 | s0 | s1 | a0 | a1 | a2 | a3 | a4 | a5
  deriving BEq, DecidableEq, Repr

def Reg.render : Reg -> String
  | .zero => "zero"
  | .ra => "ra"
  | .sp => "sp"
  | .gp => "gp"
  | .tp => "tp"
  | .t0 => "t0"
  | .t1 => "t1"
  | .t2 => "t2"
  | .s0 => "s0"
  | .s1 => "s1"
  | .a0 => "a0"
  | .a1 => "a1"
  | .a2 => "a2"
  | .a3 => "a3"
  | .a4 => "a4"
  | .a5 => "a5"

inductive Insn where
  | label (name : String)
  | comment (text : String)
  | li (rd : Reg) (imm : Int)
  | mv (rd rs : Reg)
  | add (rd rs1 rs2 : Reg)
  | addi (rd rs : Reg) (imm : Int)
  | ld (rd base : Reg) (offset : Int)
  | sd (rs base : Reg) (offset : Int)
  | beqz (rs : Reg) (label : String)
  | j (label : String)
  | trap
  | ecallJar
  | ecalli (selector : Int)
  | fallthrough
  deriving Repr

structure Program where
  name : String
  text : Array Insn
  deriving Repr

end ProofForge.Compiler.JarPvm
```

- [ ] **Step 3: Add the printer**

Create `ProofForge/Compiler/JarPvm/Printer.lean`:

```lean
import ProofForge.Compiler.JarPvm.AST

namespace ProofForge.Compiler.JarPvm

def renderInsn : Insn -> String
  | .label name => name ++ ":"
  | .comment text => "  # " ++ text
  | .li rd imm => s!"  li {rd.render}, {imm}"
  | .mv rd rs => s!"  mv {rd.render}, {rs.render}"
  | .add rd rs1 rs2 => s!"  add {rd.render}, {rs1.render}, {rs2.render}"
  | .addi rd rs imm => s!"  addi {rd.render}, {rs.render}, {imm}"
  | .ld rd base offset => s!"  ld {rd.render}, {offset}({base.render})"
  | .sd rs base offset => s!"  sd {rs.render}, {offset}({base.render})"
  | .beqz rs label => s!"  beqz {rs.render}, {label}"
  | .j label => s!"  j {label}"
  | .trap => "  .insn r 0x0b, 0, 0, zero, zero, zero"
  | .ecallJar => "  .insn r 0x0b, 1, 0, zero, zero, zero"
  | .ecalli selector => s!"  .insn i 0x0b, 2, zero, zero, {selector}"
  | .fallthrough => "  .insn r 0x0b, 4, 0, zero, zero, zero"

def renderProgram (program : Program) : String :=
  String.intercalate "\n" (
    [
      s!"# ProofForge JAR PVM2 program: {program.name}",
      "  .section .text"
    ] ++ (program.text.map renderInsn).toList
  ) ++ "\n"

end ProofForge.Compiler.JarPvm
```

- [ ] **Step 4: Add aggregators**

Create `ProofForge/Compiler/JarPvm.lean`:

```lean
import ProofForge.Compiler.JarPvm.AST
import ProofForge.Compiler.JarPvm.Printer
```

Add to `ProofForge.lean`:

```lean
import ProofForge.Compiler.JarPvm
```

- [ ] **Step 5: Run printer test**

Run:

```bash
lake env lean --run Tests/JarPvmPrinter.lean
lake build
```

Expected:

```text
jar-pvm-printer: ok
```

- [ ] **Step 6: Commit AST/printer**

Run:

```bash
git add ProofForge/Compiler/JarPvm ProofForge/Compiler/JarPvm.lean ProofForge.lean Tests/JarPvmPrinter.lean
git commit -m "feat: add jar pvm ast printer"
```

## Task 4: Counter-Level Plan And Lowering

**Files:**
- Create: `ProofForge/Backend/JarPvm/Plan.lean`
- Create: `ProofForge/Backend/JarPvm/Lower.lean`
- Create: `ProofForge/Backend/JarPvm/IR.lean`
- Create: `ProofForge/Backend/JarPvm.lean`
- Create: `Tests/JarPvmCounter.lean`
- Modify: `ProofForge.lean`

**Interfaces:**
- Consumes: `ProofForge.IR.Contract.Module`, `ProofForge.Target.resolveModule`, `ProofForge.Target.jarPvm`, `ProofForge.Compiler.JarPvm.Program`.
- Produces: `renderModule : IR.Module -> Except LowerError String`.

- [ ] **Step 1: Write the failing Counter smoke**

Create `Tests/JarPvmCounter.lean`:

```lean
import ProofForge.Backend.JarPvm.IR
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.JarPvmCounter

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO UInt32 := do
  match ProofForge.Backend.JarPvm.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .error err => throw <| IO.userError err.render
  | .ok asm =>
      require (asm.contains "# ProofForge JAR PVM2 program: Counter") "missing program header"
      require (asm.contains "entry_increment:") "missing increment endpoint"
      require (asm.contains "entry_get:") "missing get endpoint"
      require (asm.contains ".insn r 0x0b") "missing Xjar op"
      IO.println "jar-pvm-counter: ok"
      return 0

end ProofForge.Tests.JarPvmCounter

def main : IO UInt32 :=
  ProofForge.Tests.JarPvmCounter.main
```

Run:

```bash
lake env lean --run Tests/JarPvmCounter.lean
```

Expected:

```text
unknown package 'ProofForge.Backend.JarPvm.IR'
```

- [ ] **Step 2: Add lowering error and plan types**

Create `ProofForge/Backend/JarPvm/Plan.lean`:

```lean
import ProofForge.IR.Contract

namespace ProofForge.Backend.JarPvm

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String := err.message

structure EndpointPlan where
  name : String
  label : String
  returns : ProofForge.IR.ValueType
  deriving Repr

structure ModulePlan where
  name : String
  stateSlots : Array (String × Nat)
  endpoints : Array EndpointPlan
  deriving Repr

end ProofForge.Backend.JarPvm
```

- [ ] **Step 3: Add narrow validator/lowerer**

Create `ProofForge/Backend/JarPvm/Lower.lean`:

```lean
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.JarPvm.Plan

namespace ProofForge.Backend.JarPvm

open ProofForge.IR

def err (message : String) : Except LowerError α :=
  .error { message }

def validateCapabilities (module : Module) : Except LowerError Unit := do
  match ProofForge.Target.resolveModule ProofForge.Target.jarPvm module with
  | .ok _ => pure ()
  | .error diagnostic => err diagnostic.render

def requireCounterSubset (module : Module) : Except LowerError Unit := do
  if module.state.size != 1 then
    err "jar-pvm spike supports exactly one scalar state slot"
  let state <- match module.state[0]? with
    | some state => pure state
    | none => err "jar-pvm spike missing state slot"
  if state.kind != .scalar then
    err "jar-pvm spike supports only scalar state"
  if state.type != .u64 then
    err "jar-pvm spike supports only U64 state"

def lowerModule (module : Module) : Except LowerError ModulePlan := do
  validateCapabilities module
  requireCounterSubset module
  let endpoints := module.entrypoints.map fun entrypoint => {
    name := entrypoint.name
    label := "entry_" ++ entrypoint.name
    returns := entrypoint.returns
  }
  pure {
    name := module.name
    stateSlots := module.state.mapIdx fun idx state => (state.id, idx)
    endpoints := endpoints
  }

end ProofForge.Backend.JarPvm
```

- [ ] **Step 4: Add AST builder**

Create `ProofForge/Backend/JarPvm/IR.lean`:

```lean
import ProofForge.Backend.JarPvm.Lower
import ProofForge.Compiler.JarPvm.AST
import ProofForge.Compiler.JarPvm.Printer

namespace ProofForge.Backend.JarPvm.IR

open ProofForge.Compiler.JarPvm
open ProofForge.Backend.JarPvm

def endpointInsn (endpoint : EndpointPlan) : Array Insn :=
  #[
    .label endpoint.label,
    .comment s!"endpoint {endpoint.name}",
    .fallthrough,
    .trap
  ]

def buildProgram (plan : ModulePlan) : Program := {
  name := plan.name
  text := plan.endpoints.foldl (fun acc endpoint => acc ++ endpointInsn endpoint) #[]
}

def renderModule (module : ProofForge.IR.Module) : Except LowerError String := do
  let plan <- lowerModule module
  pure (renderProgram (buildProgram plan))

end ProofForge.Backend.JarPvm.IR
```

- [ ] **Step 5: Add aggregators**

Create `ProofForge/Backend/JarPvm.lean`:

```lean
import ProofForge.Backend.JarPvm.Plan
import ProofForge.Backend.JarPvm.Lower
import ProofForge.Backend.JarPvm.IR
```

Add to `ProofForge.lean`:

```lean
import ProofForge.Backend.JarPvm
```

- [ ] **Step 6: Run lowering smoke**

Run:

```bash
lake build ProofForge.Backend.JarPvm
lake env lean --run Tests/JarPvmCounter.lean
```

Expected:

```text
jar-pvm-counter: ok
```

- [ ] **Step 7: Commit lowering smoke**

Run:

```bash
git add ProofForge/Backend/JarPvm ProofForge/Backend/JarPvm.lean ProofForge.lean Tests/JarPvmCounter.lean
git commit -m "feat: lower counter to jar pvm"
```

## Task 5: CLI And Optional Runner Gate

**Files:**
- Modify: `ProofForge/Cli/Fixture.lean`
- Modify: `ProofForge/Cli.lean`
- Create: `scripts/jar-pvm/counter-smoke.sh`
- Modify: `justfile`
- Modify: `docs/validation-gates.md`
- Modify: `Tests/CliTargetFirst.lean`

**Interfaces:**
- Consumes: `ProofForge.Backend.JarPvm.IR.renderModule`.
- Produces: `lake env proof-forge emit --target jar-pvm --fixture counter --format s -o build/jar-pvm/Counter.s`.

- [ ] **Step 1: Extend fixture format support**

Modify `ProofForge/Cli/Fixture.lean`:

```lean
def supportedTargetIds : Array String := #[
  "evm",
  "solana-sbpf-asm",
  "wasm-near",
  "wasm-cosmwasm",
  "psy-dpn",
  "aleo-leo",
  "move-aptos",
  "quint",
  "jar-pvm"
]

def defaultFormatFor (targetId fixtureId : String) : Option Format :=
  match targetId with
  | "jar-pvm" => some .s
  | "evm" =>
      if fixtureId == "counter" || fixtureId == "value-vault" then some .bytecode
      else some .yul
  | "solana-sbpf-asm" => some .s
  | "wasm-near" | "wasm-cosmwasm" => some .wat
  | "psy-dpn" => some .psy
  | "aleo-leo" => some .leo
  | "move-aptos" => some .aptos
  | "quint" => some .qnt
  | _ => none

def supportsFormat (targetId fixtureId : String) (format : Format) : Bool :=
  match targetId, fixtureId, format with
  | "jar-pvm", "counter", .s => true
  -- existing target cases remain unchanged below this new case
```

When editing, insert the `jar-pvm` case near the top of the existing
`supportsFormat` match and keep the current final catch-all as the last case.

- [ ] **Step 2: Add legacy mode and parser mapping**

In `ProofForge/Cli.lean`, import the backend:

```lean
import ProofForge.Backend.JarPvm.IR
```

Add an emit mode near the other Counter fixture modes:

```lean
  | counterIrJarPvm
```

Add this parser case near the other `--emit-counter-*` cases in `parseArgs`:

```lean
  | "--emit-counter-ir-jar-pvm" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrJarPvm }
```

Add this target-first mapping in `emitLegacyFlag`:

```lean
  | "jar-pvm", "counter", "s" => Except.ok "--emit-counter-ir-jar-pvm"
  | "jar-pvm", "counter", "" => Except.ok "--emit-counter-ir-jar-pvm"
```

Add this compile function near `compileCounterIrQuint`:

```lean
def compileCounterIrJarPvm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/jar-pvm/Counter.s")
  match ProofForge.Backend.JarPvm.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      let some parent := output.parent
        | throw <| IO.userError s!"invalid output path: {output}"
      IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render
```

Add this `compileFile` case:

```lean
  | .counterIrJarPvm => compileCounterIrJarPvm opts
```

- [ ] **Step 3: Add target-first regression case**

Add to `Tests/CliTargetFirst.lean`:

```lean
    ["emit", "--target", "jar-pvm", "--fixture", "counter", "--format", "s", "-o", "build/jar-pvm/Counter.s"]
```

Run:

```bash
lake env lean --run Tests/CliTargetFirst.lean
```

Expected output should include the existing target-first success line from the
test.

- [ ] **Step 4: Add smoke script**

Create `scripts/jar-pvm/counter-smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT="${PROOF_FORGE_JAR_PVM_OUT:-build/jar-pvm}"
mkdir -p "$OUT"

lake env proof-forge emit --target jar-pvm --fixture counter --format s -o "$OUT/Counter.s"
test -s "$OUT/Counter.s"
grep -q "ProofForge JAR PVM2 program: Counter" "$OUT/Counter.s"
grep -q "entry_increment:" "$OUT/Counter.s"
grep -q "entry_get:" "$OUT/Counter.s"

if command -v cargo >/dev/null 2>&1 && test -d "${JAR_REPO:-}"; then
  echo "jar-pvm: JAR_REPO set; runtime validation is intentionally not wired until the runner ABI is selected"
else
  echo "jar-pvm: emitted Counter.s; runtime validation skipped"
fi
```

Run:

```bash
chmod +x scripts/jar-pvm/counter-smoke.sh
scripts/jar-pvm/counter-smoke.sh
```

Expected:

```text
jar-pvm: emitted Counter.s; runtime validation skipped
```

- [ ] **Step 5: Add just recipe and validation docs**

Add to `justfile`:

```make
jar-pvm-counter:
    scripts/jar-pvm/counter-smoke.sh
```

Add to `docs/validation-gates.md`:

```markdown
### JAR PVM Counter Smoke

Command: `just jar-pvm-counter`

Scope: emits the Counter fixture as JAR PVM2 assembly and verifies stable
artifact markers. Runtime validation is skipped until the JAR runner ABI is
selected.
```

- [ ] **Step 6: Run final validation**

Run:

```bash
lake build
lake env lean --run Tests/TargetRegistry.lean
lake env lean --run Tests/JarPvmPrinter.lean
lake env lean --run Tests/JarPvmCounter.lean
lake env lean --run Tests/CliTargetFirst.lean
just jar-pvm-counter
git diff --check
```

Expected:

```text
target-registry: ok
jar-pvm-printer: ok
jar-pvm-counter: ok
jar-pvm: emitted Counter.s; runtime validation skipped
```

- [ ] **Step 7: Commit CLI smoke**

Run:

```bash
git add ProofForge/Cli.lean ProofForge/Cli/Fixture.lean Tests/CliTargetFirst.lean scripts/jar-pvm/counter-smoke.sh justfile docs/validation-gates.md
git commit -m "feat: expose jar pvm counter smoke"
```

## Task 6: Runner Selection Spike

**Files:**
- Modify: `docs/targets/jar-pvm.md`
- Create: `scripts/jar-pvm/runner-probe.sh`
- Optional create: `tools/jar-pvm-runner/README.md`

**Interfaces:**
- Consumes: emitted `build/jar-pvm/Counter.s`.
- Produces: a documented decision between `javm-transpiler`, `javm-exec` interpreter harness, or continued golden-only validation.

- [ ] **Step 1: Add runner probe script**

Create `scripts/jar-pvm/runner-probe.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${JAR_REPO:-}" ]]; then
  echo "runner-probe: skipped; set JAR_REPO=/path/to/jarchain/jar"
  exit 0
fi

if [[ ! -d "$JAR_REPO/rust" ]]; then
  echo "runner-probe: skipped; JAR_REPO does not contain rust workspace"
  exit 0
fi

(cd "$JAR_REPO/rust" && cargo test -p javm-guest-tests)
```

Run:

```bash
chmod +x scripts/jar-pvm/runner-probe.sh
scripts/jar-pvm/runner-probe.sh
```

Expected without `JAR_REPO`:

```text
runner-probe: skipped; set JAR_REPO=/path/to/jarchain/jar
```

- [ ] **Step 2: Record the selected runner boundary**

Update `docs/targets/jar-pvm.md` with one of these accepted runner outcomes:

```markdown
## Runner Boundary

Current decision: **golden artifact only**.

Reason: ProofForge can produce a stable JAR PVM2 assembly artifact before the
JAR runner ABI is committed. `scripts/jar-pvm/runner-probe.sh` checks whether
the upstream Rust guest tests are available, but does not execute ProofForge
artifacts yet.
```

or:

```markdown
## Runner Boundary

Current decision: **JAR Rust workspace probe**.

Reason: `JAR_REPO=/path/to/jarchain/jar scripts/jar-pvm/runner-probe.sh`
validates the upstream `javm-guest-tests` crate. ProofForge artifact execution
will be added only after the accepted artifact loader ABI is documented.
```

- [ ] **Step 3: Commit runner boundary**

Run:

```bash
git add scripts/jar-pvm/runner-probe.sh docs/targets/jar-pvm.md
git commit -m "docs: record jar pvm runner boundary"
```

## Self-Review

Spec coverage:

- JAR is classified as PVM-family contract execution, not EVM/Wasm/ZK.
- The plan keeps full node, consensus, and KVM `nub` out of the first spike.
- The backend is staged as `IR -> plan -> AST -> printer/artifact`.
- Capability mapping is docs-first and does not mutate canonical ids early.
- Counter is the first supported scenario.

Placeholder scan:

- No step relies on unspecified placeholder content.
- Runner uncertainty is represented as an explicit selection task with accepted outcomes.

Type consistency:

- `jar-pvm`, `.pvm`, `.jarImage`, `ProofForge.Compiler.JarPvm`, and `ProofForge.Backend.JarPvm` are used consistently across tasks.
- The public backend function is `ProofForge.Backend.JarPvm.IR.renderModule`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-06-jar-pvm-target.md`. Two execution options:

1. Subagent-Driven (recommended) - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. Inline Execution - execute tasks in this session using executing-plans, batch execution with checkpoints.
