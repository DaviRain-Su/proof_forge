# Development Standards

This page is the developer-facing standards index. It links existing
source-of-truth docs and states when they must be updated.

## Source of truth

| Topic | Authoritative doc |
|---|---|
| Documentation map | `docs/INDEX.md` |
| Settled architecture and roadmap decisions | `docs/decisions.md` |
| Accepted product / target direction | `docs/rfcs/0001-multichain-platform.md`, `docs/rfcs/0002-target-implementation-design.md` |
| Portable IR and runtime/capability lowering | `docs/portable-ir.md`, `docs/rfcs/0003-portable-ir-and-runtime.md` |
| Canonical capability ids and support matrix | `docs/capability-registry.md` |
| Target lifecycle and per-target notes | `docs/targets/README.md`, then the specific `docs/targets/*.md` note |
| EVM baseline details | `docs/targets/evm.md`, `Examples/Evm/README.md` |
| Shared cross-target Counter scenario | `docs/shared-scenario.md` |
| Execution backlog and acceptance criteria | `docs/implementation-backlog.md` |
| Validation commands and tool prerequisites | `docs/validation-gates.md` |
| Chinese narrative / strategy docs | `docs/zh/*.md`; they must align to English engineering docs and must not introduce independent engineering policy |

## RFC and decision policy

- RFCs start as `Draft`.
- RFCs become `Accepted` only when the decision is recorded in
  `docs/decisions.md` and linked docs are aligned, matching
  `docs/rfcs/README.md` lines 7-8.
- Superseded positions are recorded in `docs/decisions.md` under
  `Superseded Positions`.
- Do not change RFC status in this task unless the corresponding decision is
  already present in `docs/decisions.md`.

## Before changing code

1. Read `docs/INDEX.md`.
2. Read `docs/decisions.md` and the relevant RFC/target note.
3. If the change touches a public CLI flag, target id, capability id, artifact
   field, validation command, target lifecycle stage, or example contract
   behavior, update the nearest source-of-truth doc in the same change.
4. Run the narrow gate from `docs/validation-gates.md` that matches the touched
   boundary.

## Command runner conventions

- The root `justfile` is the developer-facing command catalog for common local
  workflows such as `just build`, `just check`, `just evm-smoke abi-scalar`,
  and `just evm-all`.
- Keep long target harnesses, generated test projects, validators, and
  target-specific shell logic in `scripts/`; `justfile` recipes should compose
  those scripts rather than inline their implementation.
- CI should invoke the same `just` recipes used locally for common gates,
  while keeping separate GitHub Actions steps where that helps locate failures.
- When adding a user-facing or CI-tracked smoke script, add or update the
  matching `just` recipe/list entry in the same change.
- Documentation may show `just` commands for common workflows, but target docs
  should still name the underlying script when that script is the authoritative
  implementation of a validation gate.

## Branch and target policy

- A target, chain, or backend spike is represented by directories and target
  ids, not by long-lived feature branches.
- Changes that touch the following source-of-truth files must land on `main`
  in standalone, reviewable PRs rather than being batch-carried on a chain
  branch:
  - `ProofForge/IR/*`
  - `ProofForge/Target/*`
  - `ProofForge/Contract/{Spec,Intent,Source}*`
  - `docs/capability-registry.md`
  - `docs/decisions.md`
  - `docs/portable-ir.md`
- After a chain branch is merged, retire its remote branch; the trunk owns the
  target from that point on.

## i18n rule

- Feature and chain branches must not modify `docs/zh/*.zh.md` or
  `scripts/i18n/manifest.json`.
- Translation sync (`scripts/translate-docs.py`) runs on `main` only, after the
  English source-of-truth docs are settled.

## Lean package conventions

- Lean toolchain is `leanprover/lean4:v4.31.0` from `lean-toolchain`.
- Base build gate is `lake build`.
- Current library roots are `ProofForge`, `ProofForge.Psy`,
  `ProofForge.Target`, `ProofForge.IR`, `ProofForge.Backend`,
  `ProofForge.Backend.Solana.SbpfAsm`, `ProofForge.Compiler.Yul.AST`,
  `ProofForge.Compiler.Yul.Printer`, `ProofForge.Compiler.Wasm.AST`,
  `ProofForge.Compiler.Wasm.Printer`, `ProofForge.Compiler.TS.AST`,
  `ProofForge.Compiler.TS.Printer`, and `ProofForge.Compiler.TS.Emit` from
  `lakefile.lean`.
- The executable is `proof-forge`, rooted at `ProofForge.Cli`, with
  `supportInterpreter := true` from `lakefile.lean`.
- New compiled Lean modules must be imported by an existing root or added to
  Lake roots before docs may claim they are part of the package.

## Authoring surface conventions

- New chain-neutral contracts use `ProofForge.Contract.Source` and lower to
  `ContractSpec` / portable IR. Do not add `ProofForge.Backend.Evm`, Solana,
  NEAR, or other target/backend imports to starter templates merely to select an
  output chain; target selection belongs to the CLI (`--target <id>`) or package
  metadata.
- `ProofForge.Backend.Evm` is compiler implementation code, not a product
  authoring SDK. New examples under `Examples/` should use `contract_source` or
  compose importable `contract_source` modules; backend-only probes belong under
  `Tests/` or `ProofForge/IR/Examples/`.
- The old `ProofForge.Evm` / `Lean.Evm` / LCNF `EmitYul` authoring route has
  been removed from the product surface. References to that route in historical
  RFCs or research notes must be labeled as legacy/research, not current
  authoring guidance.
- Capability names in EVM docs must reuse `docs/capability-registry.md` ids:
  `events.emit`, `crosscall.invoke`, `account.explicit`, `storage.pda`,
  `crosscall.cpi`. Do not introduce alternate ids such as `events.log`,
  `cross_call.contract`, or `account.container`.

## Planned behavior label

Unimplemented behavior must be labeled **Planned** or **Research**, not
described as current product behavior.

## Doc sync checklist

When a change touches any row below, update the listed docs in the **same PR**
and run `just doc-sync-audit` (advisory; writes `build/doc-sync-audit.md`).

| Code / config change | Update these docs |
|----------------------|-------------------|
| `ProofForge/Target/Registry.lean` (id, stage, capabilities) | README Backend Status, `docs/targets/<target>.md`, `docs/capability-registry.md`, `docs/targets/README.md` |
| `ProofForge/Cli/Fixture.lean` (supported targets/fixtures) | README emit examples, `docs/validation-gates.md`, AGENTS.md registry vs CLI table |
| Root `justfile` CI-tracked recipe | `docs/validation-gates.md`, AGENTS.md if in `just check` |
| `ProofForge/Contract/Stdlib/*` | `docs/sdk-ecosystem-gaps-2026-07.md`, README stdlib bullet if user-facing |
| `Examples/Shared/*` or portable scenario smokes | `docs/shared-scenario.md`, `docs/validation-gates.md` |
| Gate closure (G0/P0/G1) | `docs/gate-status.md`, `docs/implementation-backlog.md` |
| Accepted RFC / decision | RFC status line, `docs/decisions.md`, nearest target note |

Full audit register: [doc-code-sync-audit-2026-07.md](doc-code-sync-audit-2026-07.md).
Mechanical diff: `scripts/docs/audit-doc-code-sync.sh`.

Any command, target, artifact field, or validation path not implemented in this
repository must be labeled `Planned` or `Research`, not written as current
behavior.
