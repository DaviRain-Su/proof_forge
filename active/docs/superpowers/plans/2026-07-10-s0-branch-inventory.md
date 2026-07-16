# S0.5 Local branch inventory (2026-07-10)

**Do not mass-delete without human approval.** This is an inventory only.

Snapshot: after S0.1 integrate (`main` ahead of `origin/main`, 0 behind).

## Keep

| Branch | Notes |
|--------|--------|
| `main` | Active trunk |

## Safe delete candidates (`[gone]` upstream — already merged or remote removed)

| Branch |
|--------|
| `DaviRain-Su/lookdown` |
| `DaviRain-Su/near-compare` |
| `DaviRain-Su/quint` |
| `DaviRain-Su/refactor` |
| `DaviRain-Su/refactor-rust-transfer` |
| `aptos-counter-signer-fix` |
| `codex/evm-dynamic-array-target-plan` |
| `cursor/agents-md-backend-status-sync` |
| `cursor/audit-semantic-divergence-and-fv-anchors` |
| `cursor/fv5-overflow-capability-gate` |
| `cursor/revert-aware-refinement` |
| `gate-prebuild-cli` |
| `ignore-nvimlog` |
| `pr-44` |
| `quint-testkit-gate-adjustments` |
| `rfc-0014-tier-split` |
| `zh-docs-i18n-update` |

Suggested (after human OK):

```sh
git branch -d DaviRain-Su/lookdown DaviRain-Su/near-compare ...   # or -D if unmerged leftovers
```

## Stale / far behind (review before delete)

| Branch | Track |
|--------|--------|
| `DaviRain-Su/quint-phase2-plan` | ahead 15, behind ~578 |
| `DaviRain-Su/evm-phase2` | ahead 10, behind ~749 |
| `tmp-main-test` | behind ~770 |
| `DaviRain-Su/batch2-rebase` | behind ~815 |
| `DaviRain-Su/plan-future` | no upstream |
| `DaviRain-Su/evm-remain` | no upstream |
| `DaviRain-Su/evm-full` | no upstream |
| `DaviRain-Su/quint-next` | no upstream |
| `cursor/ir-portability-ownership` | no upstream |
| `backup-e01836c` | local backup |
| `review/latest-main-20260710` | review snapshot |
| `pr-2-solana-support` | historical |
| `ci-fix-solana-supprot` | historical |

## Policy

- Chains are directories + target ids, not long-lived branches (architecture review).
- Prefer short feature branches off current `main` only.
