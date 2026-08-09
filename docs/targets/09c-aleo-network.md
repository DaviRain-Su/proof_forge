---
id: TARGET-ALEO-NETWORK
title: Aleo network path (explicit deploy + execute + separate receipt)
status: draft
owner: engineering
updated: 2026-08-09
normative: false
---

# Aleo 网络维：显式 deploy / execute 与独立 receipt

状态：`draft`（2026-08-09）
前置：[`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md)（Instructions 权威）
本地解释：[`09b-aleo-local-sandbox.md`](09b-aleo-local-sandbox.md)（`just aleo-sandbox`；无链）
入口：`just aleo-network` → `/usr/bin/python3 -I -S scripts/aleo_network_receipt.py`；
`./scripts/aleo_network.sh` 是固定 `/bin/bash -p` + absolute Python 的薄适配器。

## 1. 架构边界（已纠正）

`build`、target materializer 和 Aleo `FinalizeV1` 必须继续 **无网络、无 signer**。网络部署是显式的
post-build 动作，不得在 Finalize 中偷偷广播，也不得回写或追加 build OutputSet：

```text
ProgramV1
  → build --target aleo --profile aleo-leo-4.0.2-u64-compile-v1
  → proof-forge.output.v1（仍 deployable=false；exact disk closure）
  → explicit aleo_network_receipt.py --broadcast
       · 将 OutputSet 全树 stable-read 到 private snapshot
       · proof-forge-next inspect --output-dir <private-snapshot>
       · 从该 exact snapshot 读取 compiled Instructions + leo-program metadata
       · snarkOS exact bytes → private executable snapshot → developer deploy [可选 execute]
  → <receipt-dir>/receipt.json（独立原子发布）
```

因此：

- network、endpoint、signer 不进入 Source/Semantic/Plan/hash，也不改变 codegen profile；
- deployment receipt **不是** `FinalizedArtifactsV1` extra，也不进入 `manifest.json`；
- N3 将来应实现正式 `NetworkProfileV1` resolve/compatible-build join + canonical `deploy` 命令，仍然
  产生独立 deploy receipt；**不是**“让 Finalize 负责部署”。

## 2. DevNet / Testnet 与 credits

| 环境 | credits/token | 当前策略 |
|---|---|---|
| **本地 DevNet** | 不需要公共 Faucet；`snarkos --dev-key 0..3` 使用本地预资助 validator key | 已支持；REST 仅 loopback；每次 fresh ledger |
| **公共 Testnet** | **需要 Testnet credits 支付 deployment/execution fee**；没有余额不能部署 | 工具路径已支持；需用户自行从官方 Faucet 获得测试 credits，并提供安全 key file |
| **Mainnet** | 真实资产/费用 | **明确拒绝**，在工具/网络 I/O 前 exit 2 |
| **Canary** | 非本次产品范围 | **明确拒绝** |

Testnet 的“token”是测试网 credits，不是主网资产，但部署仍有基础费用；`--priority-fee` 只是额外
microcredits，默认 `0`，不能替代基础费用。余额不足、program id 已存在或 endpoint 不兼容都会真实失败，
不会假绿。

## 3. 阶段阶梯

| 阶段 | 名称 | 条件 | 产物 / 行为 |
|---|---|---|---|
| **N0** | Local sandbox | locked Leo | Instructions pin + offline run；无链 |
| **N1-E** | Engineering network deploy | inspected Aleo compile OutputSet + reachable DevNet/Testnet endpoint + explicit `--broadcast` + signer | 真实 `snarkos developer deploy --wait` + REST program visibility |
| **N2-E** | Engineering execute | N1-E 成功 + 同网络 | 可选 Counter `initialize 1u64` / `increment 2u64` + mapping observation |
| **N3** | Product NetworkProfile/deploy | registry/product decision | formal `NetworkProfileIdentity`、compatible BuildIdentity、canonical signer-FD CLI 与 receipt；**pending** |
| **N4** | Locked snarkOS/snarkVM | Tool Lock pin | 当前 snarkOS 仍在 Tool Lock 外；**pending** |

N1-E/N2-E 是真实网络行为和独立工程 receipt，但不是 formal N3、hermetic、release 或主网资格。
Aleo build profiles仍 `deployable=false`。

## 4. 输入契约

### 4.1 必需 build 输入

`--output-dir` 必须是已经发布的 Aleo compile-profile OutputSet：

- `schemaVersion = proof-forge.output.v1`；
- `target = aleo`；
- `codegenProfile = aleo-leo-4.0.2-u64-compile-v1`；
- exactly one base `*.aleo`、one finalized `*.compiled.aleo`、one finalized
  `*.leo-program.json`；
- base Instructions 与 locked-Leo compiled Instructions exact-byte 相等；
- wrapper 先把完整 OutputSet stable-read 到 owner-private snapshot，再让 product CLI
  `inspect --output-dir <snapshot>` 重验 exact disk closure；部署只消费该 snapshot 的 exact bytes。

网络脚本不再接受 source/module，也不再执行 `build` 或 `leo build`。`--output-dir` 与
`--receipt-dir` 必须完全分离（不得相等或互为祖先/后代）。

### 4.2 网络与 signer

| flag | 契约 |
|---|---|
| `--output-dir DIR` | 已有 compile-profile OutputSet |
| `--receipt-dir DIR` | 新目录；父目录须预先存在、当前用户拥有且不可被 group/other 写；禁止与 OutputSet 重叠；成功/partial receipt 由 retained parent/staging FD 原子 rename |
| `--network devnet\|testnet` | `mainnet`/`canary` fail closed |
| `--endpoint URL` | DevNet：`http[s]://localhost|loopback[:port]`；Testnet：HTTPS；拒绝 userinfo/query/fragment |
| `--broadcast` | 必须显式出现，永不隐式广播 |
| `--dev-key 0..3` | 仅 DevNet；不读 private-key file |
| `--private-key-file ABS` | 仅 Testnet；regular、single-link、owner、无 group/other 权限、无 symlink path component、1..4096 B |
| `--snarkos-sha256 HEX` | Testnet 必需，因为 snarkOS 尚不在 Tool Lock；exact-byte pin |
| `--priority-fee N` | 非负 microcredits；默认 0 |
| `--execute-counter` | 可选 N2-E：固定 initialize/increment + mapping 观察 |

**禁止** `--private-key <raw>`、`--fee-record <raw>` 与 `PROOF_FORGE_ALEO_PRIVATE_KEY`。Testnet key file 由 wrapper 只做
metadata/open 检查，不读取内容；初次验证冻结 device/inode/owner/mode/link/size/mtime/ctime identity，
真正 spawn 前重新 open/fstat 并要求 exact identity，再通过继承 FD 交给 snarkOS（Linux
`/proc/self/fd/N`，Darwin `/dev/fd/N`）。真实 key path/descriptor/key bytes 不进入 JSON、日志或
receipt；private-key signer 路径不渲染 raw snarkOS output tail，只公开 bytes/hash 与可解析 transaction id。
产品 CLI 对 local/network signer-bearing argv/env（含当前尚未开放的 `--signer-fd` capability）
在 CWD script spawn 前拒绝；host-heavy human/JSON stream 仍做 defense-in-depth redaction。

当前 top-level `proof-forge-next network` 仍按 CWD 发现 package script，因此它在 spawn 前**拒绝**
所有 signer-bearing argv 与已知 signer env，仅允许无 secret 的 DevNet `--dev-key` 路径。公共 Testnet
必须由操作者从可信仓库根显式运行 `just aleo-network …` 或 `scripts/aleo_network.sh …`；formal
`deploy --signer-fd` 落地后才能把 key-bearing deploy 收回 canonical CLI。

## 5. snarkOS 与 receipt

当前 N1-E/N2-E 权威为 `snarkos 4.9.0`：

- DevNet 要求 `--version` 明示 `features=[...,test_network,...]`；
- Testnet 额外要求单 hard-link、非 group/other-writable、当前用户拥有及显式 SHA-256 pin；
- 不搜索 PATH；仅绝对 `--snarkos` / `PROOF_FORGE_ALEO_SNARKOS` 或约定 cache 绝对路径；
- wrapper 通过 no-follow FD 流式复制并 hash 到 private executable snapshot；version probe、deploy、execute
  全部执行该同一 snapshot，receipt 记录 captured digest，不再次信任原 pathname；
- deploy/execute 使用 `--wait --timeout`，并有额外进程 wall/output 上限；任意异常（含 interrupt）均
  终止并 reap 独立 process group；
- DevNet-only V18 ramp gate 不再错误应用于公共 Testnet；同一 accelerated
  `CONSENSUS_VERSION_HEIGHTS=0,1,…,17` 会同时注入 validators 与 deployment client，避免 client 用旧
  consensus cost 算出偏低 base fee 后被 V18 node 拒绝；公共 endpoint REST 路径沿传入 base（官方
  explorer 当前示例为 `/v2`）。

独立 receipt schema：`proof-forge.aleo-deployment-receipt.engineering.v1`。它绑定：

- OutputSet/build/plan/source/semantic/Instructions digests；
- network environment、normalized endpoint + digest；
- program id、deploy/execute transaction id（若 snarkOS 输出可解析）、program visibility/mapping；
- snarkOS version/content digest，并明确 `lockStatus=outside-tool-lock`；
- signer public projection（永不含 key/path/FD）；
- `networkProfile.registrationStatus=unregistered-engineering`，不伪造 formal NetworkProfile digest；
- receipt 自身 domain-separated SHA-256。

若 deploy 已成功、后续 execute/observation 失败，脚本尽力发布 `confirmed-partial` receipt；若 deploy
process 已启动但被拒、超时、中断或结果不确定，则尽力发布 `attempted-unobserved`。成功与失败 action
均绑定 status、tool exit code、output bytes/SHA-256 与可解析 transaction id，但 receipt 不保存 raw output。
两者均避免“可能已有链上副作用但本地完全无记录”；preflight 失败不会创建 receipt。

## 6. DevNet 生命周期安全

`just aleo-devnet start|stop|status|wait` 现由 `scripts/aleo_devnet.py` 管理：

- 每次 `start` 使用新的 `build/aleo-devnet/run.*` ledger/data 目录，避免 program-id 重名污染复跑；
- 4 个 REST listener 固定 `127.0.0.1:3030..3033`（可用 port-base env 调整），不再绑定 `0.0.0.0`；
- 每个 validator 独立 process group；`active.json` 原子记录 exact PIDs/run-dir/tool path；
- `stop` 在 signal 前逐 PID 校验 executable + `--dev` + ledger/data path；拒绝不匹配 PID；
- 禁止 `pgrep -x snarkos | kill` 或任何全局按名称清理；run logs/ledger 默认保留供诊断。

真实集成入口 `just aleo-devnet-integration`：fresh DevNet → network-free compile-profile build →
显式 post-build deploy/execute → receipt/mapping 断言 → EXIT trap 仅停止 owned PIDs。集成使用
`--dev-key 0`，仓库不再硬编码 local private key。

2026-08-09 本机实测通过：compile OutputSet `deployable=false`；deployment
`at1qee7jmxqvstw9r2slm377cnk7fg7ujvsauh9cexw8crymw64wq8srqz2j8`、initialize
`at1nyh2q49l8ha6zcj0sk3ggtcvll465v0qlm6pl9jt4egm5pxkqyrsnh8yex`、increment
`at1lzr7a8lqajr6h7rqyj6tkugu4vhhn6d9ztargwa2s4u2xcqs6spq2q2h0z` 均经 `--wait`
confirmed；receipt schema/digest 字段断言通过；mapping `pf_state_0[0u8]="3u64"`、
`initialized[0u8]="true"`；结束后 exact 4 个 owned PID 清理。该事实仅是 local DevNet engineering
observation，不代表 public Testnet、formal N3 或 release。

## 7. 运行方式

### DevNet（无需公共 credits）

```bash
just aleo-devnet start
just aleo-devnet wait

PROOF_FORGE_ALEO_EMIT_LEO=1 lake env .lake/build/bin/proof-forge-next build \
  Examples/Counter.lean --module Examples.Counter --target aleo \
  --profile aleo-leo-4.0.2-u64-compile-v1 -o build/v2/aleo-counter-deploy

mkdir -p build/v2/aleo-network-receipts
chmod 700 build/v2/aleo-network-receipts
just aleo-network \
  --output-dir build/v2/aleo-counter-deploy \
  --receipt-dir build/v2/aleo-network-receipts/aleo-counter-devnet \
  --network devnet --endpoint http://127.0.0.1:3030 \
  --dev-key 0 --broadcast --execute-counter --priority-fee 1000000

just aleo-devnet stop
```

### Public Testnet（需要 Faucet credits）

```bash
# 先把已审计 snarkos 复制到 single-link、仅 owner 可写的绝对路径，再计算 exact pin。
SNARKOS=/absolute/private/tool-root/snarkos
SNARKOS_SHA256="$(sha256sum "$SNARKOS" | cut -d' ' -f1)"

mkdir -p build/v2/aleo-network-receipts
chmod 700 build/v2/aleo-network-receipts
just aleo-network \
  --output-dir build/v2/<unique-program-output> \
  --receipt-dir build/v2/aleo-network-receipts/<unique-program-testnet> \
  --network testnet --endpoint https://api.explorer.provable.com/v2 \
  --private-key-file /absolute/private/account.key \
  --snarkos "$SNARKOS" --snarkos-sha256 "$SNARKOS_SHA256" \
  --broadcast --priority-fee 0
```

公共 Testnet program id 必须尚未被部署；通常应在源码中使用唯一 program 名再 build。不要把 key
内容粘贴到 shell history、聊天、环境变量或 JSON。

## 8. 门禁与诚实限制

- ordinary `just ci` 只运行 no-network self-test/CLI smoke；绝不广播，也不起 DevNet；
- host-heavy `just aleo-devnet-integration` 独立运行；
- public Testnet 实际部署需要用户提供有测试 credits 的账户，本仓库/agent 不持有 key；
- 当前没有 formal NetworkProfile payload/digest、genesis pin、compatible-build registry join、locked
  snarkOS、network UPS、mainnet、formal deploy/execute；
- N1-E/N2-E 不能把 registry maturity 或 build `deployable` 改成 network validated。

聚焦门：

```bash
just aleo-network-self-test
just aleo-devnet-self-test
just local-network-smoke
just aleo-devnet-integration   # host-heavy, explicit
```
