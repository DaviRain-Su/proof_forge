---
id: TRACE-EV-LEDGER-001
title: Alpha Evidence Ledger
status: draft
owner: quality
updated: 2026-07-15
normative: false
---

# Alpha Evidence Ledger

这些是未提交 worktree 上的开发证据，只证明当前 alpha 观察结果；release 前必须在候选
commit 重跑，生成符合 [`evidence-schema.md`](evidence-schema.md) 的不可变 JSON。

| ID | Gate / command | Result | Scope and limitation |
|---|---|---|---|
| EV-20260715-0001 | `python3 scripts/docs_check.py` | passed | schema、ID、状态、JSON、链接；不代表文档 accepted |
| EV-20260715-0002 | `lake build ...tests && proof-forge-next-tests` | passed | Core/DSL/materializer alpha unit tests |
| EV-20260715-0003 | `just target-smoke` | passed | 四目标相同 semantic hash；Solana/Noir non-deployable |
| EV-20260715-0004 | `bash scripts/smoke_evm.sh` | passed | Anvil init/increment/overflow rollback |
| EV-20260715-0005 | `just isolated-check` | passed | archive isolation smoke：临时目录重建/测试/docs-check；未隔离 HOME/cache/受控 PATH，不是完整 clean-room |
| EV-20260715-0006 | `just check` | passed | Lean Parser、Source/Typed/Semantic、四 target alpha、fail-closed target/tool、existing/source-output collision |
| EV-20260715-0007 | `just evm-runtime`; `just reproducibility`; `just isolated-check` | passed | Anvil Counter/rollback；四 target 19 文件两次一致；archive isolation smoke，仍非 hermetic clean-room |

未取得：Solana ELF/runtime、NEAR sandbox receipt、Noir ACIR/proof/VK/verify、任何公网部署。
