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
| EV-20260715-0011 | authoritative `env -i ... verify_host_stage0.sh` development/formal；`just host-stage0-negative`；`just check` | passed (development attestation; expected formal rejection) | profile `darwin-arm64-25E253-xcode17C529-development`、host lock `0af42570…e0fa8`、launcher `95fdf6c5…fb095`、verifier `7d6000a3…032c9`；development observation 精确匹配 macOS `26.4.1/25E253`、native arm64、SIP/authenticated-root enabled、seal broken、Xcode `26.3/17C529` 且 pathname current-user-mutable；formal 稳定 `PF-HOST-INELIGIBLE`；bootstrap/host-lock/BASH_ENV negatives fail closed；仅为 local point-in-time evidence，不关闭 TST-ISO-002/003 |
| EV-20260715-0012 | `just host-h1-unit`；`just v2-clean-room-h1`；formal Stage-0 `--require-eligible` | passed (H1 development clean-room; formal host rejection expected) | commit `0298b19a…`、archive `2910c0a1…b726`、deny-default sandbox、candidate/archive binding、schema-complete immutable EV under `build/evidence/clean-room/EV-20260715-0012.json`（`sandboxPolicy=deny-default`，`eligibleForHermetic=false`）；formal Stage-0 稳定 `PF-HOST-INELIGIBLE`；关闭 `TASK-D0-03/H1`，**不**关闭 `TST-ISO-002`/`TASK-D0-04`/`TST-ISO-003` |

| EV-20260716-0013 | `lake env .lake/build/bin/proof-forge-next-tests`（incl. `Tests.Language.SourceIdentity`） | passed | `Source.Token`/`Span`/`NodeId`/`tokenize`/`Program.enumerateNodes`/`validateLimits`；NodeId = SHA-256(module,program,path)[:128]；token spans non-overlapping；node/nesting limit negatives → `PF-BOUND-001`；closes formal `TASK-D1-01` / `TST-SRC-001/002` only |
| EV-20260716-0014 | `proof-forge-next-tests` Loader/ProgramSyntax；`just dsl-negative` | passed | positive `program ... where` export；`program Invalid : contract where` rejected by loader + lean dsl-negative；closes `TASK-D1-02` / `TST-SRC-003` only |
| EV-20260716-0015 | `proof-forge-next-tests` + `Tests.Language.Declarations` | passed | state/init/entry/view structure；checkedAdd/return AST；duplicate init + UInt64 overflow reject；empty callables `PF-SRC-INVALID`；closes `TASK-D1-03/04` / `TST-SRC-004/005` |

Formal closed with matching TST/EV: `D0-01..03`, `D1-01..04`. Blocked: `D0-04`,
`D5-04/05`, `D6-05`, `D7-04/05`, `D8-04`.

未取得：formal hermetic、remaining formal D1–D8 closures、Solana ELF/runtime、NEAR
sandbox、Noir prove/verify、public release。
