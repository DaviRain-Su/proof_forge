---
id: PLAN-PF-CLI-ALEO
title: Rust Developer CLI `pf` — Aleo-first implementation plan
status: draft
owner: engineering
updated: 2026-08-10
normative: false
---

# `pf` CLI 实现计划（Rust / Aleo-first）

依据：[ADR-0037](../adr/0037-developer-cli-pf.md)、[SPEC-CLI-DEV-001](../specs/cli-developer.md)。

## 目录

```text
clients/pf-cli/
  Cargo.toml                 # package proof-forge-pf, bin pf
  README.md
  src/
    main.rs
    cmd/                     # version doctor build check inspect local deploy execute
    targets/aleo/            # local_run network_tx twin_statecell
    artifact.rs compiler.rs safety.rs tools_leo.rs …
```

## 切片

| ID | 交付 | 状态 |
|---|---|---|
| PF-D0 | ADR-0037 + SPEC + 本 plan | **done** |
| PF-D1 | crate 骨架、clap、`version`/`list-targets`/`doctor`/`build`/`inspect` | **done** |
| PF-D2 | `local run`（Wave-B 逻辑 Rust 化） | **done** |
| PF-D3 | `deploy`/`execute` save-only（Wave-C + StateCell twin） | **done** |
| PF-D4 | just recipes + README 30s + unit tests | **done** |
| PF-D5 | EVM/Solana capability notes + `pf build -t` multi-target + `pf clean` | **done** |
| PF-D6 | quiet `pf run` + `scripts/pf_cli_smoke.sh` / `just pf-cli-smoke` | **done** |
| PF-D7 | （后）EVM local / Solana verify adapters 真正接线 | pending |

## 命令优先级

1. `pf build --target aleo` — 开发者每天用
2. `pf local run` — 替代手跑 interpret script
3. `pf deploy` / `pf execute` — save-only 默认
4. `pf doctor` / `setup` — onboarding

## 验收

```bash
cargo test --manifest-path clients/pf-cli/Cargo.toml --locked
cargo build --manifest-path clients/pf-cli/Cargo.toml --locked --release

# host（需 lake build proof_forge_next）
./clients/pf-cli/target/release/pf build Examples/StateCell.lean \
  --module Examples.StateCell --target aleo -o build/v2/pf-statecell

./clients/pf-cli/target/release/pf local run --target aleo \
  --artifact build/v2/pf-statecell -- initialize 5u64

./clients/pf-cli/target/release/pf deploy --target aleo \
  --artifact build/v2/pf-statecell --network testnet
# → save-only deployment json
```

与 scripts 对拍：相同 fixture 下 scripts gate 与 `pf` 不得一个绿一个红（save-only 路径）。

## 非目标

- Python `pf`
- 合并进 Lean CLI
- mainnet / 默认 broadcast
- 第一期多程序 twin 自动综合（仅 StateCell 登记）
