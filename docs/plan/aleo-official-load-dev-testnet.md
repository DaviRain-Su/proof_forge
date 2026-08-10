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

**目标**：在 **不** 恢复 Leo source 产品路径的前提下，对已 load 的 Instructions 做本地状态迁移观察。

候选（择一，fail-closed）：

1. **Package interpret lane**（operator）：最小 Leo package 仅作 runner 壳，**业务权威仍是 PF `.aleo`**（需钉：`leo run` 是否重编译 src；当前实测 `run` 会走 package src）
2. **snarkVM CLI**（若 Tool Lock 可 pin）：直接 load `.aleo` 解释
3. **产品 `local --target aleo --mode interpret`**：仅在 1/2 稳定后薄封装；默认仍无 network

DoD：

- [ ] 固定 fixture：`initialize` → `increment` 可观察 mapping 效果（或明确等价观测）
- [ ] 缺工具 skip-clean；有工具失败 exit ≠ 0
- [ ] 文档钉：interpret ≠ proof ≠ on-chain

**状态**：`pending`（依赖 Wave A 关闭）

---

## Wave C — Devnet / Testnet deploy+execute（opt-in）

**目标**：operator 显式网络提交；**不进 ordinary CI**；MCP 默认仍无 broadcast。

前置：

- Wave A load 绿
- Wave B interpret 至少一条稳定路径
- Tool Lock：Leo 与/或 snarkOS **精确版本 + digest**（禁止 PATH 冒充产品 finalize）
- endpoint + network id + credits + key **全部显式**

DoD：

- [ ] `devnet`：deploy program → execute transition → query mapping（point-in-time）
- [ ] `testnet`：同上，独立证据目录
- [ ] 产品 CLI 若暴露：仅 `network --broadcast` 类显式 flag；拒绝默认 mainnet
- [ ] 证据只写 tx/program id/endpoint binding；**不**设 `deployable=true` 除非另开产品决策

**状态**：`pending`

---

## 明确不做

- 恢复 `aleo-leo-4.0.2-*` source/compiler product profile
- Mainnet 产品门禁 / MCP 默认 broadcast
- 把 `leo abi` 成功说成 formal / hermetic / mainnet
- 静默 rename 保留名（必须作者改名或 target FC）

---

## 击杀顺序

```text
A1. reserved-name FC + StateCell/LoopSum leo abi          ← 本切片
A2. just + docs + backlog 登记
B1. 选定 interpret 权威（snarkVM vs package shell）并 spike
B2. acceptance script + optional local mode
C1. Tool Lock snarkOS/Leo network pins
C2. opt-in devnet then testnet runbooks（host-optional）
```
