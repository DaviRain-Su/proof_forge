---
id: TRACE-EV-LEDGER-001
title: Alpha Evidence Ledger
status: draft
owner: quality
updated: 2026-07-15
normative: false
---

# Alpha Evidence Ledger

这些是 alpha 开发/候选提交上的观察证据；release 前必须在正式候选 commit 重跑，并生成
符合 [`evidence-schema.md`](evidence-schema.md) 的不可变 JSON。

| ID | Gate / command | Result | Scope and limitation |
|---|---|---|---|
| EV-20260715-0001 | `python3 scripts/docs_check.py` | passed | schema、ID、状态、JSON、链接；不代表文档 accepted |
| EV-20260715-0002 | `lake build ...tests && proof-forge-next-tests` | passed | Core/DSL/materializer alpha unit tests |
| EV-20260715-0003 | `just target-smoke` | passed | 四目标相同 semantic hash；Solana/Noir non-deployable |
| EV-20260715-0004 | `bash scripts/smoke_evm.sh` | passed | Anvil init/increment/overflow rollback |
| EV-20260715-0005 | `just isolated-check` | passed | archive isolation smoke：临时目录重建/测试/docs-check；未隔离 HOME/cache/受控 PATH，不是完整 clean-room |
| EV-20260715-0006 | `just check` | passed | Lean Parser、Source/Typed/Semantic、四 target alpha、fail-closed target/tool、existing/source-output collision |
| EV-20260715-0007 | `just evm-runtime`; `just reproducibility`; `just isolated-check` | passed | Anvil Counter/rollback；四 target 19 文件两次一致；archive isolation smoke，仍非 hermetic clean-room |
| EV-20260715-0008 | `just v2-clean-room-alpha` | passed (development alpha) | commit `e3b16063…06d5`、archive `c3bbb8db…bdc`；空 HOME/cache、`env -i`、父 repo deny、Core 断网、EVM localhost-only、61-job clean build/test、四目标 19 文件复现及 Anvil；当时 closure 未锁定，非 hermetic，未关闭 TST-ISO-003 |
| EV-20260715-0009 | toolchain v2 validate/provision/materialize/closure + exact-tree/DYLD negatives + `just evm-runtime` | passed (development slice) | official solc/WABT/OpenSSL/Foundry assets；strict schema、五 file hash/mode/link、Mach-O graph、actual dyld load、tamper/symlink/hardlink/writable/DYLD negatives、Counter runtime；Lean/eligible host/deny-default/EV JSON 未闭合，D0-03 in_progress |
| EV-20260715-0010 | `just v2-clean-room-alpha` | passed (development alpha) | commit `0b0aebda…643c8`、archive `05b5bda6…2115c`；official Lean ZIP `e8cd241b…e0656` 以 isolated/no-site Python、`env -i` 和 no-network sandbox 离线物化；15,194 entries / 2,761,381,330 bytes、Lean/Lake 5/6-node reachable closure 与 dyld 一致；61-job clean build/test、四目标 19-file 复现、EVM localhost runtime；host ineligible/deny-default/schema EV 未闭合，不关闭 TST-ISO-003 |

Lean cache consumer 的 development evidence 已闭合；因 host profile 不合格、deny-default
sandbox 与正式 schema EV 未闭合，`TASK-D0-03` 保持 `in_progress`。

未取得：Solana ELF/runtime、NEAR sandbox receipt、Noir ACIR/proof/VK/verify、任何公网部署。
