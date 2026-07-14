# ZK Target Promotion Analysis: PSy, Aleo, and OpenVM

## Status

Refreshed repository-grounded analysis. PSy and Aleo are existing research
targets. OpenVM is a future research candidate and requires a separately
sourced target brief before implementation estimates are accepted.

## Boundary With Portable Intent

ZK targets consume the same checked Canonical Core for shared semantics. They
do not automatically receive TokenSpec, NFTSpec, DAO, or Vault lanes.

Target-specific proof/circuit operations use typed, versioned HostOps. They do
not add PSy-, Aleo-, or OpenVM-specific constructors to Canonical Core.

```text
contract_source -> CheckedCanonicalContract -> CapabilityPlan
                                            -> PsyModulePlan
                                            -> future AleoModulePlan
                                            -> future OpenVMModulePlan
```

## PSy Baseline

Implemented:

- fixture build/emit routing;
- `PsyModulePlan` and plan-driven metadata;
- portable IR validation and Psy AST/printer;
- scalar/map/fixed-array/struct coverage;
- conditional and bounded-loop coverage;
- events, assertions, limited runtime-ID crosscall;
- coverage, diagnostics, metadata, golden, and optional Dargo gates.

Not implemented:

- canonical `buildFromCore`;
- strict canonical target gate;
- public `contract_source` product route;
- dynamic bytes/string/U128 and dynamic-memory features;
- typed/create crosscalls;
- protocol materializers and product lifecycle evidence.

### PSy Promotion Phase 1

Add `ProofForge.Backend.Psy.Plan.Core.buildFromCore` and a strict fixture gate.
Do not change registry maturity or public input modes.

Acceptance:

- Counter plan is produced from `CheckedCanonicalContract`.
- every consumed Core op is represented in the plan or explicitly rejected;
- target requirements match plan capabilities;
- legacy fixture and canonical plan metadata are compared;
- unsupported constructors fail with stable diagnostics;
- `psy-coverage`, metadata, diagnostics, and golden gates remain green.

### PSy Promotion Phase 2

Open a `contract_source` route only after Phase 1 has runtime or executable
oracle evidence for Counter and at least one stateful product fixture.

The route must produce source, metadata, SDK/artifact references, and maturity
claims consistent with the target registry. Optional Dargo availability must
not be presented as runtime validation when it was skipped.

## Aleo Baseline

Implemented:

- fixture-mode Leo/Aleo emission;
- portable IR validation and Leo AST/printer;
- scalar/map, structs, linear records, bounded control flow, assertions;
- named static crosscalls;
- metadata and source/printer gates.

Not implemented:

- a semantic `AleoModulePlan`;
- canonical `buildFromCore` and strict gate;
- public `contract_source` product route;
- event, dynamic storage/memory, while-loop, and general typed crosscall
  coverage;
- mandatory Leo runtime evidence in the default environment.

### Aleo Promotion Decision

Create `AleoModulePlan` before public promotion. Direct Core-to-Leo AST would
make capability, metadata, and refinement review inconsistent with the rest of
the compiler.

Phase 1 is plan-only and fixture-strict. Phase 2 may open `contract_source`
after a real Leo compile/execute gate is available in CI.

## OpenVM Research Boundary

Sourced brief: [openvm-research.md](../../targets/openvm-research.md)
(2026-07-15). Decision: **defer** backend and registry. The checklist below is
retained as the acceptance contract that brief satisfied; do not schedule
implementation from unpinned facts or from this analysis alone.

Before adding a registry entry or backend, the dated target brief must fix:

- supported OpenVM release/toolchain;
- guest ISA and executable format;
- proof and verifier artifact formats;
- host/guest I/O ABI;
- available execution and proving commands;
- licensing and distributability;
- exact Lean semantics dependency, version, and proof boundary;
- local/CI hardware and time budgets.

No effort estimate, audit claim, or Lean-refinement claim is considered an
accepted project fact until that brief is reviewed.

### Potential OpenVM Architecture

If accepted, OpenVM should use:

```text
CheckedCanonicalContract
  -> OpenVMModulePlan
  -> RV32 guest program/ELF artifact
  -> execution trace/proof artifact
  -> separately generated verifier integration
```

Cryptographic accelerators or chips are modeled as pure HostOps with typed
signatures and capability requirements. The verifier contract is a separate
cross-target artifact, not an implicit property of the guest compiler.

## ZK HostOps

Example future shape:

```lean
def verifyCommitmentSig : HostOpSig := {
  id := { namespace := "zk.commitment", name := "verify", version := ⟨1, 0, 0⟩ }
  params := #[.hash, .hash, .hash]
  results := #[.bool]
  effect := .pure
}
```

A HostOp is added only when at least one concrete target implementation and
one honest-reject test exist. Shared arithmetic/hash behavior remains Core.

## Promotion Policy

For each ZK target:

1. Keep docs/registry maturity unchanged during plan-only work.
2. Add `buildFromCore` with a strict supported-fragment test.
3. Add artifact and metadata determinism.
4. Add execution evidence before opening `contract_source`.
5. Add proving evidence before claiming proof generation.
6. Add Lean refinement only against a pinned, executable semantics contract.
7. Never treat skipped external tooling as a passing runtime/proof gate.

## Revised Order

1. PSy canonical plan and strict Counter gate.
2. Aleo semantic plan and strict Counter gate.
3. PSy stateful execution evidence, then consider `contract_source`.
4. Aleo compile/execute evidence, then consider `contract_source`.
5. Write and review the OpenVM target brief.
6. Only then decide whether OpenVM outranks further PSy/Aleo investment.
7. Add shared ZK HostOps only from demonstrated target requirements.

## Non-Goals

- Promoting research targets by changing registry labels alone.
- Replacing ZK toolchains with hand-written Lean assemblers.
- Adding speculative proof instructions to Canonical Core.
- Claiming protocol-wrapper compatibility without a real target protocol.
- Scheduling OpenVM implementation from unpinned external facts.
