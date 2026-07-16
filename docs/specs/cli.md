---
id: SPEC-CLI-001
title: CLI 契约
status: proposed
owner: cli
updated: 2026-07-15
normative: true
---

# CLI 契约

可执行文件固定 `proof-forge-next`。所有命令 non-interactive；JSON 输出 stdout，日志和
human diagnostics 到 stderr。

## Commands

```text
proof-forge-next check <source> [--program <qualified>] [--format human|json]
proof-forge-next build <source> --target <id> [--profile <id>]
  [--program <qualified>] --output <dir> [--force] [--format human|json]
proof-forge-next inspect <output-dir> [--format human|json]
proof-forge-next list-targets [--all] [--format human|json]
proof-forge-next prove <output-dir> --inputs <private-input-file>
  --proof-output <dir> [--format human|json]
proof-forge-next verify <output-dir> --proof <file> --public-inputs <file>
  [--format human|json]
proof-forge-next deploy <output-dir> --network <network-profile-id>
  --signer-fd <n> [--format human|json]
```

Phase 1 required：check/build/inspect/list-targets、Noir prove/verify；deploy 接口可存在但
仅对通过 target dossier network gate 的 profile 开放，其他返回 stable unavailable。

## Selection Rules

一个候选自动选择；零候选 `PF-EXPORT-003`；多个候选必须 exact `--program`，否则
`PF-EXPORT-002`。target/profile exact lookup；省略 profile 使用 registry 唯一 default。
build 禁止 `--network`；deploy 不接受 source/target/profile，而是信任并重验 OutputSet。

## JSON Results

成功 object：`schema`, `command`, `status:"ok"`, `result`。失败 object：同 schema、
`status:"error"`, `diagnostics:[...]`；不混入日志。输入/输出皆 UTF-8，JSON duplicate key
拒绝。human output 不作为稳定 API。

## Exit Codes

| Code | 类别 |
|---|---|
| 0 | success |
| 2 | CLI usage/config |
| 3 | source/type/effect/semantic |
| 4 | target/profile/requirement resolution |
| 5 | plan/lower invariant |
| 6 | toolchain/artifact/output |
| 7 | deploy/prove/verify/runtime |
| 70 | internal compiler error |

多个 diagnostics 取最高优先级：70 > 7 > 6 > 5 > 4 > 3 > 2。

## Secret、Inputs 与副作用

private witness 文件必须 mode 0600、regular file、非 symlink；prove 不复制到 bundle。
signer 只从已打开 FD 读取，CLI/env/JSON 禁止 key。check/build/inspect/list 不访问网络；
deploy 先验证 network chain identity、artifact/profile/hash，再请求明确确认策略（CI 使用
预批准 policy file，不使用 prompt）。

## 边界与验收

覆盖无/多 source、unknown flag、重复 flag、missing value、`--`、Unicode path/name、
多 program、unknown target/profile/network、build with network、output exists/force、JSON
broken pipe、TTY/non-TTY、private file permissions/symlink、bad signer FD、proof mismatch、
deploy non-deployable、signals、concurrent invocation。关联 `FR-008/010/011/014`、
`TST-CLI-001..004`；help/version/list JSON golden，所有失败 exit code 和 schema 固定。
