---
id: PLAN-ALEO-LOAD-DEV-TESTNET
title: Aleo Instructions → official load → Dev/Testnet (3 waves)
status: in_progress
owner: engineering
updated: 2026-08-10
normative: false
---

# Aleo：官方加载 → 本地解释 → Dev/Testnet（三波）

## 范围决策

| 网络 | 产品目标 |
|---|---|
| **Devnet** | Wave C 目标（operator opt-in） |
| **Testnet** | Wave C 目标（operator opt-in） |
| **Mainnet** | **不做产品路径**；仅人工/外部，永不默认 |

产品 finalize 在三波内保持 `deployable=false`。  
权威物化仍是 ADR-0035 sole path：

```text
ProgramV1 → AleoPlan → Aleo Instructions → {id}.aleo + query descriptor
```

不恢复 Leo source 为产品权威。官方工具只作为 **load / interpret / network operator** 层。

---

## Wave A — 官方工具加载 PF 产物（本切片）

**目标**：证明 PF emit 的 `.aleo` 能被官方 Leo 4.0.x 解析为合法 Instructions。

| 项 | 内容 |
|---|---|
| 入口 | `just aleo-instructions-load` → `scripts/aleo_instructions_load_acceptance.sh` |
| 正例 | 产品 build `StateCell` / `LoopSum` → `leo abi` |
| Golden | `counter.aleo` / `optionstate-admit.aleo` 必须 `leo abi` 成功 |
| 负例 | `accumulator.aleo` golden 因函数名 `add`（保留 opcode）被 `leo abi` 拒绝 |
| 产品 FC | `Examples/Accumulator` entry `add` 在 Aleo lower **fail closed**（不静默改名） |
| 非声称 | 无 VM run、无 proof、无 deploy、无 snarkOS |

**状态**：`done`（2026-08-10）— `just aleo-instructions-load` + `AleoInstructionsV1` 绿。

**实证（2026-08-10）**：

- `leo abi` 可直接吃 PF `statecell.aleo` / `loopsum.aleo` / golden `counter.aleo` / `optionstate-admit.aleo`
- `function add:` 触发 `'add' is a reserved opcode`；产品对 `Examples/Accumulator` FC
- 与 Leo 手写再 `leo build` 的 diff：init 用 `not` vs `is.eq`、increment 多一次 dropped-result `get.or_use` —— **文本不等价，但 abi 可加载**
- 验收输出：`ok (4 official loads + reserved FC)`

---

## Wave B — 本地解释（不上链）

**目标**：在 **不** 恢复 Leo source 产品路径的前提下，对已 load 的 Instructions 做本地 VM 调用。

**选定路径（2026-08-10）**：Leo runner shell + **PF bytecode import pin**。

```text
proof-forge-next build --target aleo
  → {id}.aleo
ephemeral leo package `runner` + `leo add --local` metadata dep
  → copy PF {id}.aleo → runner/build/imports/{id}.aleo   (must stay PF bytes)
leo run --offline {id}.aleo::{fn} …
  → VM loads statecell.aleo (local) from imports
post-run: sha256(imports) == sha256(PF emission)
```

| 项 | 内容 |
|---|---|
| 入口 | `just aleo-instructions-interpret` → `scripts/aleo_instructions_interpret_acceptance.sh` |
| Fixture | `Examples/StateCell`：`initialize 5u64`、`increment 3u64` |
| 完整性 | imports 保留 PF `not r1 into r2` 形态与 sha256（防 Leo 重编译替换） |
| 负例 | unknown function fail；Accumulator 产品 reserved-name FC（Wave A join） |
| 非声称 | 无 proof、无 durable ledger、无 Devnet/Testnet/Mainnet、`deployable=false` |

**为何不是 snarkVM CLI / 产品 `local`：**

- 本机无独立 snarkVM 二进制；不在 Wave B 引入新 Tool Lock 大依赖
- 产品 `local --target aleo` 仍 fail closed（ADR-0035）；Wave B 是 **host-optional acceptance**，不是产品 local lane
- 直接 `leo run` 同名 package 会 **重编译 src**，不能当 PF 权威；必须走 imports pin

**状态**：`done`（2026-08-10）— 本机 Leo 4.0.2：`ok (PF bytecode local VM + import integrity)`。

---

## Wave C — Devnet / Testnet tx materialization（opt-in broadcast）

**目标**：在 **不** 打开产品 `deployable=true` 的前提下，对 PF-equivalent Instructions
构造可提交的 deploy/execute 交易；默认 **只 save、不 broadcast**。

**选定路径（2026-08-10）**：

```text
PF build StateCell → statecell.aleo
Leo twin package (assert(!seen) + dropped re-read)
  leo build → build/main.aleo
  assert main.aleo == rewrite(PF, statecell→{freshId})   # exact bytes
leo deploy --save  (live endpoint for stateRoot; NO --broadcast by default)
leo execute --save initialize 5u64  (--skip-execute-proof; NO broadcast)
artifacts under build/v2/aleo-network-tx-{network}-{id}/
```

| 项 | 内容 |
|---|---|
| 入口 | `just aleo-instructions-network-tx` |
| 默认网络 | `testnet` + `https://api.explorer.provable.com/v1` |
| Devnet | `PROOF_FORGE_ALEO_NETWORK=devnet` + `PROOF_FORGE_ALEO_ENDPOINT=http://localhost:3030`（需自备 snarkOS） |
| Broadcast | 仅 `PROOF_FORGE_ALEO_BROADCAST=1` **且** `PROOF_FORGE_ALEO_PRIVATE_KEY`（拒绝 well-known dev key） |
| Mainnet | **exit 2 拒绝** |
| Twin 说明 | `leo deploy` 会重编译 src，不能直接塞 PF 文件；twin 经实证与 PF StateCell Instructions **字节全等**（id 改写后） |
| 非声称 | 默认不证明链上 inclusion；`deployable=false`；非 formal/hermetic；非 MCP 默认工具 |

**状态**：`done`（2026-08-10 engineering）— 本机对公共 testnet：

- twin exact-match PF
- deploy `.deployment.json` saved（含 `not r1 into r2` 程序体）
- execute `initialize` `.execution.json` saved
- `broadcast=0`

**Broadcast / 真上链**：operator 自备 funded key +（devnet 时）snarkOS；本仓库默认门禁不广播。

---

## 明确不做

- 恢复 `aleo-leo-4.0.2-*` source/compiler product profile
- Mainnet 产品门禁 / MCP 默认 broadcast
- 把 `leo abi` / tx-save 成功说成 formal / hermetic / mainnet / `deployable=true`
- 静默 rename 保留名（必须作者改名或 target FC）

---

## 击杀顺序

```text
A1–A2  load gate                         ← done
B1–B2  interpret gate                    ← done
C1     twin exact-match + deploy/execute --save (testnet)  ← done
C2     optional operator broadcast / local snarkOS devnet  ← operator
```
