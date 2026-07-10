# CLI M4 deletion checklist (U6.3 prep)

Status: **Compat window open — deletion deferred (P1.2)**
Date: 2026-07-09
Parent: [cli-m4-legacy-inventory.md](cli-m4-legacy-inventory.md), RFC 0009, D-039
Gate that must stay green: `just cli-target-first`

## Snapshot

| Item | Count |
|------|------:|
| `EmitMode` constructors | 157 |
| Distinct `--…` strings in `LegacyArgs` | ~177 |
| Executable callers of `--emit-*` outside allowlists | **0** (migration check green) |
| Intentional legacy samples | `Tests/CliTargetFirst.lean` (maps legacy → target-first) |

## P1.2 decision (2026-07-10)

**Do not execute bulk `EmitMode` deletion in this wave.**

Rationale:
1. `just cli-target-first` is green once meta flags (`--version`) are allowlisted.
2. Target-first maps still need legacy EmitMode constructors as **implementation** backends.
3. Deleting constructors requires collapsing `LegacyArgs` → target-first dispatch only — a dedicated epic after N1/E1/Z* scripts stabilize.
4. Checklist remains the SOT for the future delete window; inventory counts refreshed.

## Before deleting any alias

1. [ ] Product decision: compatibility window end date / version.
2. [ ] `just cli-target-first` green on `main`.
3. [ ] Every `just check` / CI smoke uses `build|emit|check --target` only.
4. [ ] Fixture registry covers remaining needed EmitMode cases as `--fixture` ids
      (or those fixtures are retired).
5. [ ] Docs no longer list `--emit-*-ir-*` as primary (validation-gates, tutorials).
6. [ ] Learn paths (`--learn` / `--learn-token`) either migrated or explicitly kept
      as a **separate** frozen surface with docs.

## Safe deletion order (when window closes)

1. Remove **docs** examples of legacy flags first.
2. Delete **script** allowlist exceptions (if any remain).
3. Shrink `LegacyArgs` flag parse arms that only serve EmitMode zoo.
4. Delete unused `EmitMode` constructors in batches with `cli-target-first` + `product`.
5. Finally remove `EmitMode` type if empty / unused.

## Must not delete in M4 (without separate epic)

- Target-first verbs: `build`, `emit`, `check`, `--list-targets`, `--list-fixtures`
- Peer map flags: `--peer`, `--peers-demo`
- Deploy-related: constructor args / chain profile (if still product)
- Solana arch: `--solana-sbpf-arch`

## Verification after each batch

```bash
just cli-target-first
just product
just versioning-policy
just client-schema-parity
# optional full
just check
```

## Note on `Tests/CliTargetFirst.lean`

This file **intentionally** lists legacy flag vectors to prove the mapping
layer. It is not an executable production caller. Do not treat those strings
as migration debt in scripts/CI.
