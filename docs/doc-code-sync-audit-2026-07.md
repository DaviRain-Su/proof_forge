# Doc↔Code Sync Audit (2026-07)

Status: **Audit complete — fixes applied in same PR series**

This report records doc↔code drift found during the July 2026 sync audit.
Mechanical findings from `scripts/docs/audit-doc-code-sync.sh` are merged
with semantic review across backlog, RFC, gate, capability, SDK, and i18n docs.

**Truth-source order:** `ProofForge/Target/Registry.lean` → `ProofForge/Cli/*`
→ `justfile` / CI → `Examples/*` → English docs → `docs/zh/*` (translate only).

Re-run: `just doc-sync-audit` (writes `build/doc-sync-audit.md`).

---

## Summary

| Severity | Count (pre-fix) | Category |
|----------|-----------------|----------|
| P0 | 4 | Misstates missing backend or examples |
| P1 | 12 | Target inventory, gates, stage labels |
| P2 | 30+ | Capability matrix, SDK nuance, i18n lag |
| **Total** | **~50** | |

**Resolution:** Batch 1–4 doc updates in this change set; mechanical guard in
`development-standards.md` + `just doc-sync-audit`.

---

## Findings register

### P0 — Misleading absence claims

| ID | Type | Doc | Code anchor | Fix |
|----|------|-----|-------------|-----|
| DC-EX-COSMWASM | 已实现未更新 | `shared-scenario.md` CosmWasm Counter.lean Planned | `Examples/CosmWasm/Counter.golden.wat` | Path + Spike status |
| DC-EX-APTOS | 已实现未更新 | `shared-scenario.md` Move/Aptos path Planned | `Examples/Aptos/Counter/golden/` | Path + Spike status |
| DC-EX-CF | 已实现未更新 | `cloudflare-workers.md` Example Planned | `Examples/CloudflareWorkers/Counter/` | In repo (TS package) |
| DC-CF-BACKEND | 已实现未更新 | `cloudflare-workers.md` no local backend | `Compiler/TS/Emit.lean` | Stage Spike; TS pipeline |

### P1 — Target inventory and lifecycle

| ID | Type | Doc | Code anchor | Fix |
|----|------|-----|-------------|-----|
| DC-TGT-WASM_COSMWASM | 已实现未更新 | README Backend table omits target | Registry `wasm-cosmwasm` | Add Spike row |
| DC-TGT-MOVE_APTOS | 已实现未更新 | README Backend table omits target | Registry `move-aptos` | Add Spike row |
| DC-TGT-README-SUI | 已实现未更新 | `targets/README.md` Sui parked | `move-sui` Counter MVP | Maintenance-only inventory |
| DC-TGT-README-EVM-REG | 已实现未更新 | `targets/README.md` EVM lacks registry | `evm` in Registry | Remove stale note |
| DC-EVM-STAGE | 跨文档不一致 | README Baseline vs `evm.md` Experimental | Gate P0 closed | Lifecycle Experimental + maturity footnote |
| DC-README-CHECK | 已实现未更新 | README `just check` = EVM+Psy | `just check` recipe | Full static gate list |
| DC-GATE-COSMWASM | 已实现未更新 | validation-gates Planned CosmWasm | `just cosmwasm-counter-smoke` | Move to Current |
| DC-GATE-CLI_TARGET_FIRST | 已实现未更新 | validation-gates Planned build --target | `just cli-target-first` | Partial landing noted |
| DC-INDEX-BACKENDS | 已实现未更新 | `INDEX.md` backend list incomplete | 8 registry + spikes | Expand intro |

### P2 — Registry vs CLI, capability, SDK, i18n

| ID | Type | Doc | Code anchor | Fix |
|----|------|-----|-------------|-----|
| DC-CLI-ALEO_LEO | 边界说明 | `--list-targets` vs emit | CLI-only per D-025 | Document in README/AGENTS |
| DC-CLI-QUINT | 边界说明 | quint not in registry | MBT verification target | Document in AGENTS |
| DC-ZH-MOVE_SUI | i18n滞后 | zh README missing move-sui | English README | translate-docs sync |
| DC-CAP-* | 能力矩阵 | `capability-registry.md` vs Registry | Profile capabilities | Align Y/P/N (see below) |
| DC-SDK-UUPS | SDK语义 | UUPS Missing vs stdlib | `UUPSProxy.lean` | Partial (stdlib; policy limits) |
| DC-RFC-0002 | RFC历史 | wasm-near Researched in fork | EmitWat on main | Update status column |
| DC-RFC-0009-CHECK | 未实现 | RFC M3 check surface | check not in newCommandArgsToLegacy | Note M4 / legacy path |

### Capability matrix corrections (Registry wins)

| Capability | Target | Was | Now | Reason |
|------------|--------|-----|-----|--------|
| `crosscall.invoke` | NEAR | N | Y | Profile includes `crosscallInvoke` |
| `control.bounded_loop` | EVM | N | P | Profile + LoopProbe smoke |
| `assertions.check` | Sui | P | Y | Counter MVP uses assertions |
| `storage.map` | Sui | P | N | Counter MVP profile |
| `caller.sender` | Sui | Y | N | Not in move-sui profile |
| `value.native` | Sui | Y | N | Not in move-sui profile |
| `events.emit` | Sui | Y | N | Not in move-sui profile |
| `crosscall.invoke` | Sui | Y | N | Not in move-sui profile |
| `env.block` | Sui | P | N | Not in move-sui profile |
| `crypto.hash` | Sui | Y | N | Not in move-sui profile |
| `storage.array` | CF Workers | P | N | Not in profile |
| `account.explicit` | CF Workers | P | N | Not in profile |
| `runtime.allocator` | NEAR | Y | N | Offline bump only, not profile cap |
| `data.dynamic_bytes` | Solana | Y | N | Profile has `dataDynamicArray`, not bytes |

---

## Dimensions covered

| Dimension | Mechanical script | Semantic walk |
|-----------|-------------------|---------------|
| A. Target inventory | Yes | README, targets/README, target-roadmap |
| B. Examples/scenarios | Yes | shared-scenario Phase 2 criteria |
| C. Validation gates | Partial | validation-gates Planned vs justfile |
| D. Capability matrix | Partial | Registry profile per target |
| E. SDK/features | Partial | sdk-ecosystem-gaps vs Stdlib |
| F. Backlog/RFC/zh | No | implementation-backlog, RFC 0002/0009, zh |

---

## Out of scope (still accurate as Planned/Research)

- `proof-forge test --target <id>` unified command (RFC 0009 M4)
- Non-EVM/non-Psy artifact.json validation for all spike targets
- Sui beyond Counter MVP (object semantics expansion)
- CosmWasm/Aptos contract_source examples (golden fixtures only)
- EmitZig CF Workers route (superseded by TypeScript emit for D-033 spike)
- Tier-3 docs-only candidates (Stellar, ICP, Cardano, …) — correctly parked

---

## Maintenance

When changing any of:

- `ProofForge/Target/Registry.lean`
- `ProofForge/Cli/Fixture.lean`
- root `justfile` CI-tracked recipes
- `ProofForge/Contract/Stdlib/*`
- `Examples/*` shared scenarios

…update the nearest English source-of-truth doc in the same PR and run
`just doc-sync-audit`. See [development-standards.md](development-standards.md)
**Doc sync checklist**.
