---
id: TARGET-ALEO-NETWORK
title: Aleo network product path (deploy + execute)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Aleo 网络维（产品：deploy → execute）

状态：`draft`（2026-08-08）  
前置：[`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md)（Instructions 权威）  
本地解释：[`09b-aleo-local-sandbox.md`](09b-aleo-local-sandbox.md)（`just aleo-sandbox`；无链）  
入口：`just aleo-network` → `scripts/aleo_network.sh`

## 1. 产品定位

ProofForge 对 Aleo 的交付不是「单机解释样例」，而是 **目标链选定后的完整工程路径**：

```text
ProgramV1（admit 面内任意合法程序）
  → build --target aleo → Aleo Instructions + query-contract
  → [本地] leo package + offline run          （09b；无链）
  → [网络] deploy 上链 → execute 调用         （本文；需 endpoint）
```

**第一网络维** = 用户（或 CI host）提供的 Aleo **network + endpoint**（testnet / canary / mainnet / 自建 snarkOS devnet）。  
有网络则 **真实 deploy/execute**；无网络则 **稳定 `PF-TOOLCHAIN-MISSING` / `PF-NETWORK-MISSING`**，不假绿、不把 sandbox 说成已上链。

## 2. 程序复杂度（诚实）

| 说法 | 真相 |
|---|---|
| 不是只能 Counter 玩具 | **admit 面内**任意 ProgramV1：多 state、if/match/for、多叶 Map/Option/Array、窄宽 UInt、Bool/assert、const、Int64/Field/pureFn 等已开路径均可 materialize |
| 不是「任意 Solidity 级全语言」 | **未 admit** 的构造在 Normalize/Plan/IR **fail closed**（nested Map、emit、call/schedule、record custody、String interface、nonempty invariant 等见 §3.2） |
| 上链对象 | 产品权威仍是 **Aleo Instructions**；Leo 源为 package/debug 旁路；不支持的能力不会 silent 降级成错误字节码 |

结论：**链上程序可以复杂，但必须落在 Aleo admit 矩阵内**；扩面靠继续开 capability，不是口头「任意」。

## 3. 阶段阶梯

| 阶段 | 名称 | 条件 | 产物 / 行为 |
|---|---|---|---|
| **N0** | Local sandbox | locked Leo only | `just aleo-sandbox`：Instructions pin + offline run（**已交付**） |
| **N1** | Network deploy | locked Leo + **reachable** `ENDPOINT` + `NETWORK` + funded `PRIVATE_KEY` | `leo deploy --broadcast` → 链上 program id |
| **N2** | Network execute | N1 成功 + 同网络 | `leo execute --broadcast` initialize / entry；view 经 query-contract / `leo query` |
| **N3** | Product profile | 产品决策 | 新 codegen profile 或 Finalize 写入 deploy evidence；**才**考虑 `deployable=true` |
| **N4** | snarkVM package-only | Tool Lock pin | IR-7：Instructions 直喂（与 Leo package 路径并行；仍 MISSING） |

**本切片交付 N1 门禁脚本 + 文档**：有凭证则尝试 N1（及可选 N2）；无凭证 exit 2 说明缺什么。  
**默认产品 Finalize 仍 `deployable=false`**，直到 N3 产品决策。

## 4. 工具事实（Leo 4.0.2 实测）

- `leo deploy --offline --save` **仍请求** `{endpoint}/{network}/stateRoot/latest`；无可达 endpoint **不能**物化 deployment tx（RPT-024 一致）。
- `--skip-deploy-certificate` 可跳过 cert/VK 生成，**不能**跳过 stateRoot。
- `leo run --offline` ≠ 上链；仅 N0。
- `leo devnet` 需要外部 **snarkOS**（当前 Tool Lock **无** snarkOS asset）。
- 禁止 PATH fallback；仅 `$PROOF_FORGE_TOOL_ROOT/leo`。

## 5. 脚本契约 `scripts/aleo_network.sh`

### 5.1 环境 / 参数（显式 opt-in 上链）

| 变量 / flag | 作用 |
|---|---|
| `PROOF_FORGE_ALEO_NETWORK` / `--network` | `testnet` \| `mainnet` \| `canary`（必填才进 N1） |
| `PROOF_FORGE_ALEO_ENDPOINT` / `--endpoint` | REST base，如 `https://api.explorer.provable.com/v1` 或 `http://127.0.0.1:3030` |
| `PROOF_FORGE_ALEO_PRIVATE_KEY` / `--private-key` | 部署/执行密钥；**禁止**默认写入用户生产密钥 |
| `--broadcast` | 必须显式给出才 `--broadcast`（防误上链） |
| `--execute` | N1 成功后跑 N2（initialize + increment） |
| `--consensus-version N` | 可选；否则让 Leo 从 endpoint 探测 |
| `--skip-deploy-certificate` | 可选；开发网可加快，**非** mainnet 默认建议 |
| `--program-source PATH` | 默认 `Examples/Counter.lean`；可换 admit 面内任意源 |
| `--module NAME` | 默认 `Examples.Counter` |

缺 network/endpoint/key/`--broadcast` → **exit 2**  
`PF-NETWORK-MISSING: …`（产品尚未配置网络维，不是编译失败）。

### 5.2 成功路径（N1）

1. 与 09b 相同：product build（`PROOF_FORGE_ALEO_EMIT_LEO=1`）+ golden/Instructions pin + Leo package + `leo build`。
2. `leo deploy --network … --endpoint … --private-key … --broadcast --yes --disable-update-check --path <pkg>`（+ 可选 flags）。
3. 记录 stdout 摘要；若有 json-output 则保留。
4. 日志标签：`NETWORK-DEPLOY`、`NOT-LOCAL-SANDBOX-ONLY`。
5. 可选 N2：`leo execute --broadcast initialize 1u64` / `increment 2u64`。
6. exit 0 → `NETWORK-OK`。

### 5.3 失败

| 情况 | exit |
|---|---|
| locked Leo 缺失 | 2 `PF-TOOLCHAIN-MISSING` |
| 网络参数不全或未 `--broadcast` | 2 `PF-NETWORK-MISSING` |
| product/golden pin 失败 | 1 |
| deploy/execute 链上失败（余额、重名、endpoint） | 1 |

### 5.4 非目标

- 不在 ordinary `just ci` 里广播 testnet/mainnet。
- 不把 N0 重命名为 deploy。
- 不静默使用用户 ambient `PRIVATE_KEY` 做默认 broadcast（脚本只认显式 flag/env）。
- 本切片 **不** 改 Finalize `deployable=true`。

## 6. 与既有脚本

| 脚本 | 角色 |
|---|---|
| `aleo_local_sandbox.sh` | N0 本机解释 |
| `aleo_network.sh` | N1/N2 网络 deploy/execute 门禁 |
| `aleo_runtime_test.sh` | IR-7 snarkVM package-only honesty |
| `aleo_acceptance.sh` | compile-only |

## 7. 本地 DevNet 实证（2026-08-09）

| 项 | 值 |
|---|---|
| 启动 | `just aleo-devnet start` → `scripts/aleo_devnet.sh`（直接 4× snarkos validator，`features=test_network`，REST 3030–3033） |
| Endpoint | `http://127.0.0.1:3030` |
| 共识 | `CONSENSUS_VERSION_HEIGHTS=0,1,…,17`（V9 于 height 9、V18 于 17；**deploy 前必须等到 V18**，否则 ramp 期广播会在 inclusion 以 “missing program checksum” 被拒） |
| 密钥 | 官方 local-dev funded：`APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH`（**仅** local） |
| 产品 build | `Examples/Counter.lean --target aleo` → Instructions ≡ golden |
| N1/N2 权威 | **snarkos developer**（Leo 4.0.2 `leo deploy` 对 snarkOS 4.9 有 base-fee 低估；`--priority-fees 200000` 通过 V18 校验） |
| 集成 | `scripts/aleo_devnet_integration.sh`：devnet→build→deploy→execute→mapping `pf_state_0[0u8]=3u64` / `initialized=true` |
| snarkos 包 | `--path` 需要根目录 `main.aleo` + **leo-built** `program.json`（`description`/`license` 空字符串形态；自填模板会触发 “missing program checksum”） |

预编译 GitHub snarkOS **无** `test_network`，`leo devnet --dev` 会失败。需：

```bash
cargo install snarkos --version 4.9.0 --features test_network --locked \
  --root ~/.cache/proof-forge-v2/aleo-devnet/cargo-install
```

## 8. 后续（N3+）

1. Tool Lock pin snarkOS（test_network 构建）→ 可复现 local devnet。
2. 产品 profile `aleo-*-network-v1`：Finalize 附 deploy receipt / tx id（仍 fail closed 缺网）。
3. query-contract 驱动 live mapping 读。
4. CLI 子命令：`proof-forge-next network aleo …` 包装本脚本。
5. 扩 admit 面 = 更「复杂合约」的真实路径。
