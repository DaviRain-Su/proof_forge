---
id: TRACE-EV-LEDGER-001
title: Alpha Evidence Ledger
status: draft
owner: quality
updated: 2026-07-16
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
| EV-20260715-0012 | post-commit `just v2-clean-room-alpha` | passed (development alpha) | commit `4c6756a4e83cd461520bcacc713a8b13a81cfe3b`、archive `2af10f30458bf98c261802632f1096b54ab015c767cec4f76dfa16d99bd0037b`；committed Stage-0/Host Profile v1 先输出 `eligible=false`，再从锁定 cache 物化 Lean/Lake/external closure，61-job clean build/test、四目标 19-file 复现、sandbox policy probes 与 EVM localhost runtime 全通过；临时 tool root 完整清理；host ineligible/allow-default/schema EV 仍未闭合，不关闭 TST-ISO-002/003 |
| EV-20260715-0013 | `just candidate-binding`; anchored post-commit `verify_isolation.sh --development ...` | passed (development candidate binding) | commit `7b143aa7e7043a4f93dab78fe168b5c518b15fa1`、tree `0dc77113aa2e63d45a21ee99f971b0e23d351329`、stable archive `5a18767e…c821a`；commit-object+pathspec tar 两次 byte-identical、embedded commit 反查、三项 external anchor、NUL-safe pre/post status、61-job clean build/test、四目标 19-file 复现及 EVM localhost runtime；旧 tree-object archive hash 是历史时点 observation，不可作为可重算 anchor；host ineligible/allow-default/schema EV 仍未闭合 |
| EV-20260715-0014 | `just evidence-core`; `just check`; independent exploit matrix | passed (development evidence-core slice) | commit `ac55da706c575f3d308e9bfa383797b89f05032c`、script `a16f16e8…ebb7a`；restricted PF JCS/schema/cross-field negatives、domain-separated artifact digest、global exact/casefold claim namespace、safe bundle inode/size/hash 与 1,024-file/64-MiB/256-MiB budgets、stable EIO、atomic no-clobber/staging-swap rejection 均通过；formal CLI publish 稳定 `PF-EVIDENCE-FORMAL-UNVERIFIED` 且无输出；尚无 gate catalog/freshness/revocation/private scan finalizer，不关闭 TST-EVIDENCE-001/ISO-002/003 |
| EV-20260715-0015 | `just sandbox-policy`；`just candidate-binding`；`just check`；anchored `verify_isolation.sh --development`（完整实参见实现日志） | passed (manual development alpha) | candidate `171f586fd48dbc7250d32124660452352f1e4b38`、tree `a393793293c4e8bfdf931522d068afcf288b5045`、archive `18fa2be…eaf2`（931840 bytes）；deny-default materialize/core 全断网，runtime 为 exact-local-port + Anvil `127.0.0.1` bind/LAN refusal；closed FD/bounded receipt/原 PGID cleanup、stage read/write/network/exec negatives、61-job clean build/test、四目标两轮复现与 EVM runtime 全通过；renderer `13bde90c…3bab`、launcher `e5209dc0…ea39`、engine `d1ee30db…6d42`；host ineligible、`setsid()` escape、formal handoff、exact-local-port schema/gate catalog/freshness/revocation/private scan/finalizer 未闭合，不关闭 TST-EVIDENCE-001/ISO-002/003 |
| EV-20260715-0016 | pinned Python py_compile/self-test；`just evidence-core`；`just check`；independent review | passed (manual development schema slice) | commit `aac4bbbffefda45d69e8e5527c44e5271dbc1c46`、script `06f739b2…a87e`；evidence v1 candidate 新增 exact-local-port 条件 `networkPort`，覆盖 current-reader legacy deny-all/loopback compatibility、1/65535 边界、缺失/禁用/越界/错误类型/unknown 字段与 failed/skipped probe negatives；旧 reader 对新 record fail closed，但未运行完整 old/new reader fixture matrix；未生成 immutable EV JSON，且 `networkPort` 与 rendered policy bytes/digest、retained launcher logs/receipts、required probes 的绑定、gate catalog、formal finalizer 未闭合，不关闭 TST-EVIDENCE-001/ISO-002/003 或 TST-VER-001 |
| EV-20260716-0017 | pinned Python py_compile/self-test；`just sandbox-policy`；`just check`；post-commit `just v2-clean-room-alpha`；independent review | passed (manual H1e-a invocation-receipt slice) | commit `799ad09d0b7928f01745346f4376e7af3acba2f2`、launcher `cc8fd88b…d591`；opt-in canonical contexts、policy/port/argv/env/terminal/raw-stream metadata、single-writer reservation 与 receipt-last publication 的 positive/attack matrix 通过，P0/P1=0。legacy alpha 回归 commit/tree/archive 为 `799ad09d…a2f2`/`7c22400e…790c`/`0bd7236c…c2e`，但 runner 尚未传 opt-in contexts 或 retained metadata；不关闭 TST-EVIDENCE-001/ISO-002/003 |
| EV-20260716-0018 | `lake build ProofForgeV2.Targets.Evm proof_forge_next_tests`；test binary；`just check`；`just evm-runtime`；independent review | passed (manual generic-EVM product slice) | commit `351104f08d0831c863d5c15a1c4d24c575750324`；非 Counter 的 Accumulator 从 Lean DSL 经 SemanticProgram、target-owned EvmPlan、动态 Keccak selector、Yul/ABI、锁定 solc 到隔离 Anvil，验证 init/add/read/nonpayable/UInt64 overflow rollback；full check、artifact validator 与独立复核 P0/P1=0。仅覆盖 Phase-1 UInt64 fragment；clean-room 中 Accumulator 只跑 core compile，runtime 仍为 Counter；frontend 尚无递归前 nesting/node preflight；无 immutable EV JSON，不关闭正式 D4 任务 |
| EV-20260716-0019 | focused Lean tests；`just target-smoke`；`just reproducibility`；`just check`；post-commit `just v2-clean-room-alpha`；independent review | passed (manual generic-Solana plan slice) | commit `4467a8450326288e64648b07825882877e53ba61`、tree `60c561145d85dc394ea20011a8f7a1c1486dac25`、archive `1f86533b…ae05`；Accumulator 经 target-owned account/handler Plan、exact descriptor/profile/error policy、layout-bound nonzero marker、zero-all-fields init、8-byte discriminator 与 exact Plan-bound typed IR，生成 non-executable `.sbpf-plan`/IDL；artifact/deep JSON、23-file repro、full check、clean-room core 与复核 P0/P1=0。没有 sBPF instructions/object/ELF/runtime，manifest=false；development host 仍 ineligible，无 immutable EV JSON，不关闭正式 D5 或 TST-SOL-004/005 |

Lean cache consumer、H0 development host observation、H1 candidate binding、strict development
evidence core、H1c deny-default continuation、H1d exact-local-port schema 与 H1e-a invocation
receipt producer slice 已闭合；因 host profile 不合格、formal Stage-0 handoff/process-session
containment，新 contexts/metadata receipts 尚未由真实 runner retained，且 gate catalog/
single-snapshot finalizer/freshness/revocation/private scan/formal EV 未闭合，`TASK-D0-03` 保持
`in_progress`。

早期 evidence 中的 “localhost-only” 是历史 application-level 命名，不证明 SBPL policy 只允许
loopback；H1c 起统一记录为 exact-local-port，并单独记录 `127.0.0.1` bind/LAN refusal negative。

未取得：Solana ELF/runtime、NEAR sandbox receipt、Noir ACIR/proof/VK/verify、任何公网部署。
