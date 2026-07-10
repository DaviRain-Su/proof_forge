# CLI M4 legacy inventory (U6.2)

Status: **Inventory refreshed 2026-07-10 (P1.1) — do not delete aliases yet**
Date: 2026-07-10 (P1 re-count)
Related: RFC 0009 / D-039, [platform-gaps](platform-gaps-2026-07.md) Gap 1,
`just cli-target-first`, `ProofForge/Cli/EmitMode.lean`,
`ProofForge/Cli/LegacyArgs.lean`, `ProofForge/Cli/TargetFirst.lean`.

## Goal of M4

After the RFC 0009 compatibility window, **delete** the legacy flag zoo
(`EmitMode` + direct `--emit-*` / fixture flags) so the only supported surface is:

```text
proof-forge build|emit|check --target <id> [--fixture <id>] …
```

M3 (caller migration) is **already green**: `just cli-target-first` scans
executable callers and fails on direct legacy flags.

## Snapshot (2026-07-09)

| Surface | Count / note |
|---------|----------------|
| `EmitMode` constructors | **157** (`ProofForge/Cli/EmitMode.lean`) |
| `LegacyArgs` flag string literals | **177** distinct `--…` tokens |
| Target-first core | `ProofForge/Cli/TargetFirst.lean` (~414 lines) |
| Migration gate | `scripts/cli/check-target-first-migration.py` + `Tests/CliTargetFirst.lean` |

## 2026-07-10 delta (Z1/Z2/B1)

Added since prior inventory (do **not** delete; still target-first mapped):

- `--emit-counter-ir-dpn-json` / `counterIrDpnJson` (Psy DPN direct)
- `--emit-counter-ir-aleo` / `counterIrAleo` (Aleo Instructions direct)
- `--emit-solana-memo-cpi-sbpf`, `--solana-memo-cpi-elf` (L1 memo)
- Global meta: `--version` is **not** a legacy EmitMode alias (allowlisted in migration check)

## What stays until M4 delete

1. **Thin aliases** in `LegacyArgs` that map old flags → target-first options.
2. **EmitMode** as the internal routing enum for fixtures not yet expressed as
   `--fixture` ids.
3. **Learn** paths (`--learn` / `--learn-token`) as frozen compatibility.

## Delete criteria (M4 exit)

- [ ] Zero executable callers of legacy flags outside allowlisted docs/tests
      (already enforced by `cli-target-first` for scripts/just/testkit).
- [ ] Every CI / `just` smoke uses `build|emit|check --target`.
- [ ] Fixture registry covers all still-needed EmitMode constructors as
      `--fixture` ids (or fixtures retired).
- [ ] Docs (`validation-gates`, tutorials, README) no longer document
      `--emit-*-ir-*` as primary.
- [ ] Compatibility window closed by product decision (date or version).

## Non-goals of this inventory

- Deleting `EmitMode` or `LegacyArgs` in this change.
- Renaming public target ids.
- Changing artifact JSON shapes (see [RFC 0012](rfcs/0012-versioning-and-compatibility-policy.md)).

## Commands

```bash
just cli-target-first   # must stay green before and after M4
just cli-check
just product            # product path never depends on EmitMode zoo
```

Update this file when EmitMode count drops or fixtures are retired.
