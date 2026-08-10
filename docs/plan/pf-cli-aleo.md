---
id: PLAN-PF-CLI-ALEO
title: Rust Developer CLI `pf` — multi-target plan (Aleo-first → EVM/Solana)
status: draft
owner: engineering
updated: 2026-08-10
normative: false
---

# `pf` CLI 实现计划（Rust / Aleo-first → multi-target）

依据：[ADR-0037](../adr/0037-developer-cli-pf.md)、[SPEC-CLI-DEV-001](../specs/cli-developer.md)。

依赖模型（**冻结，不改**）：外部工程依赖 `proof-forge-next` 二进制 + `ProofForgeV2` source gate，
不是 Lake `require`。见 SPEC §3.0。

---

## 0. 一句话现状

| 层 | 状态 |
|---|---|
| Compiler | `proof-forge-next` 九 target 物化 |
| Developer CLI `pf` | **Aleo 闭环可用**（new/build/run/deploy-save/execute-save/clean/smoke） |
| EVM / Solana 在 `pf` 里 | **能 `build -t`**；local/test/deploy **尚未接线**（有明确 FC 文案） |
| 仓库内已有 runtime 门 | Solana Mollusk / EVM Anvil 等 **脚本+just 已有**，未统一进 `pf` |

---

## 1. 目录（当前）

```text
clients/pf-cli/
  Cargo.toml                 # package proof-forge-pf, bin pf
  README.md
  src/
    main.rs
    cmd/                     # new build check clean run deploy execute …
    targets/
      mod.rs                 # capability notes + require_aleo
      aleo/                  # local_run, network_tx, twin_statecell
    project.rs artifact.rs compiler.rs safety.rs tools_leo.rs
scripts/pf_cli_smoke.sh
just pf-cli-test | pf-cli-build | pf-cli-smoke
```

---

## 2. 切片进度

| ID | 交付 | 状态 |
|---|---|---|
| PF-D0 | ADR-0037 + SPEC + 本 plan | **done** |
| PF-D1 | crate 骨架、clap、doctor/build/inspect | **done** |
| PF-D2 | Aleo local run（Wave-B） | **done** |
| PF-D3 | Aleo deploy/execute save-only（Wave-C） | **done** |
| PF-D4 | just recipes + README + unit tests | **done** |
| PF-D5 | multi-target build + clean + capability notes | **done** |
| PF-D6 | quiet run + `pf_cli_smoke` | **done** |
| **PF-D7** | **EVM local + Solana verify/test 接入 `pf`** | **pending（下一主轴）** |
| PF-D8 | 统一 `pf test` 命令面（按 target 分派） | pending（D7 后） |
| PF-D9 | 分发：`pf` 与 compiler 并排 release / install 文档 | pending |
| PF-D10 | （可选）Aleo twin 扩到非 StateCell 程序 | pending |
| PF-D11 | （可选）Solana/EVM **network deploy** 产品决策后再做 | deferred |

---

## 3. 仓库里「已经能测」的东西（D7 的原料）

这些 **不要重写**；D7 的工作是 **薄 wrap 进 `pf`**，并保持 host-optional / 非 ordinary CI。

### 3.1 Solana

| 能力 | 现成入口 | 性质 |
|---|---|---|
| 产物校验 | `clients/solana-client` → `verify-artifacts` | 离线、无 RPC |
| 本地执行差分 | Mollusk（`just solana-runtime`、`scripts/solana_runtime_test.sh`） | host-heavy |
| TransferSol 本地 | `just solana-transfer-sol-local` | Mollusk + native System |
| Surfpool | `just solana-surfpool-*` | 更重、可选 |
| Devnet 写面 | **已产品删除**（历史有过，勿复活默认路径） | — |

**对开发者的含义**：Solana「测试」优先是 **verify + Mollusk**，不是起 validator 再 deploy。

### 3.2 EVM

| 能力 | 现成入口 | 性质 |
|---|---|---|
| solc 验收 | `scripts/evm_solc_acceptance.sh` | tool-lock |
| Anvil 差分 | `scripts/evm_*_anvil_smoke.sh`、`evm_anvil_differential.sh` | 本地节点 |
| corpus | `scripts/evm_corpus_*.sh` | 工程观测 |

**对开发者的含义**：EVM「测试」= **编出 bytecode 后在 Anvil 上跑差分**，不是主网。

### 3.3 Aleo（已在 `pf`）

| 能力 | `pf` 命令 |
|---|---|
| build | `pf build` |
| local VM | `pf run` |
| network tx save | `pf deploy` / `pf execute` |
| e2e smoke | `just pf-cli-smoke` |

### 3.4 其它 target（暂不进 D7）

NEAR / CosmWasm / TON / Noir / Quint：仓库各有 script 或 zero-tool 边界；**D7 不铺开**，避免 CLI 表面爆炸。

---

## 4. D7 要不要做？——**要做，但拆成两档**

### 结论

| 问题 | 答案 |
|---|---|
| Solana 自己的测试要不要进 `pf`？ | **要**：先 **verify**，再可选 **test（Mollusk wrap）** |
| 以太坊本地节点要不要进 `pf`？ | **要**：`pf test -t evm` / `pf run -t evm` wrap Anvil 路径 |
| 要不要在 D7 做链上 deploy？ | **不要**（Solana 刻意无 Devnet 写面；EVM 主网更不） |
| 要不要重写 Mollusk/Anvil？ | **不要**：只 spawn 现有 binary/script，契约与 just 门对齐 |

### 为什么值得集成

1. 开发者心智：`pf build && pf test` 跨链一致，而不是记一堆 `just solana-runtime`。
2. 能力已在仓库里，缺的是 **统一命令面**，不是从零造 runtime。
3. Aleo 已证明 `pf` 编排模型可行；EVM/Solana 是同一模式的 adapter。

### 为什么不能「一次做完所有链测试」

- Mollusk / Anvil 都是 **host-heavy**，不能进 ordinary `just ci`。
- Solana client 与 runtime 是 **两条 lane**（verify ≠ execute）。
- 各 target 成熟度不同：乱统一会假装 Noir/Aleo 也有同类节点测试。

---

## 5. D7 详细设计（建议命令面）

### 5.1 新增 / 扩展命令

```text
# 已有
pf build [-t aleo|evm|solana|…]

# D7 扩展
pf verify [-t solana] [--artifact DIR] [--adapter transfer-sol-v1]
pf test   [-t aleo|evm|solana] [--artifact DIR]   # host-optional

# run 语义按 target 分派（保持一个动词）
pf run -t aleo  -- <fn> …     # 已有：Leo VM
pf run -t evm   -- <fn> …     # D7：Anvil call / 或映射到 test 子集
pf run -t solana -- …         # D7：默认指向 verify 或明确 FC→`pf verify`/`pf test`
```

**推荐默认动词表（开发者文档用）：**

| Target | `build` | `run` | `test` | `verify` | `deploy` |
|---|---|---|---|---|---|
| aleo | ✅ | local VM | （可 = run 烟测） | inspect 级 | save-only tx |
| solana | ✅ | 见下 | Mollusk wrap | solana-client | ❌ v0 |
| evm | ✅ | Anvil 单次 call（可选） | Anvil smoke wrap | artifact/manifest | ❌ v0 |

Solana `run` 建议 **不要** 假装成 `solana program deploy`；若实现，明确是 test harness 调用，或直接引导：

```text
error: solana: use `pf verify` (offline) or `pf test` (Mollusk); deploy not in pf v0
```

### 5.2 D7a — Solana verify（优先，风险最低）

**实现**

- `clients/pf-cli/src/targets/solana/verify.rs`
- spawn：
  ```bash
  cargo run --manifest-path clients/solana-client/Cargo.toml --locked -- \
    verify-artifacts --artifact-dir <build/solana> \
    [--program-adapter transfer-sol-v1]
  ```
- 或 release 后调用 `proof-forge-solana-client` 二进制（若 PATH/同目录存在）。

**验收**

```bash
pf new demo -t solana   # 或 pf.toml default-target=solana
cd demo && pf build
pf verify
# optional adapter when fixture is TransferSol-shaped
```

**非声称**：不是 formal；不是链上。

### 5.3 D7b — Solana test（Mollusk，host-optional）

**实现**

- `pf test -t solana` → 薄封装 `scripts/solana_runtime_test.sh` **或** 更窄的 focused recipe
  （优先 focused：TransferSol / Counter 一类，避免默认拉全量 19 programs）。
- 环境：继承 `PROOF_FORGE_TOOL_ROOT`；缺工具 skip-clean 或明确 fail（与 script 一致）。
- **不进** ordinary `just ci`；可加 `just pf-cli-solana-test` host-optional。

**验收**

```bash
pf build -t solana
pf test -t solana     # 需 Mollusk/runtime deps
```

### 5.4 D7c — EVM test / local（Anvil，host-optional）

**实现**

- `pf test -t evm` → wrap 一条 **最小** Anvil 路径：
  - 首选：对当前 `build/evm` 跑既有 differential 中与 StateCell/Counter 同形的子集；
  - 或：`scripts/evm_anvil_differential.sh` 的窄入口（新建 `scripts/pf_evm_test.sh` 以免全 corpus）。
- `anvil`/`cast`/`solc` 来自 Tool Lock（`PROOF_FORGE_TOOL_ROOT`），禁止 PATH 乱装进 lock。
- 起节点 → deploy bytecode → call → 断言 → 关节点；全在脚本/adapter 内，超时 fail closed。

**验收**

```bash
pf build -t evm
pf test -t evm        # 需 anvil+cast
```

**非声称**：不是 mainnet；不是 forge 全套框架替代。

### 5.5 D7 不做清单

- Solana Devnet/RPC deploy（产品曾删除写面）
- EVM 主网 / 默认广播
- 把 Mollusk/Anvil 拉进 ordinary CI
- Noir prove、NEAR sandbox、CW wasmd 一并塞进 D7
- 在 `proof-forge-next` 内实现节点

---

## 6. D7 之后（D8–D11）

### D8 — 统一 `pf test`

```text
pf test                  # 使用 pf.toml default-target
pf test -t aleo,evm      # 多 target 顺序跑；单个 fail → 非零
```

内部：`TargetAdapter::test(artifact) -> Report`。

### D9 — 分发

- GitHub Release 附 `pf` + `proof-forge-next` 同平台二进制
- `pf setup`：doctor + 指引设置 `PROOF_FORGE_CLI`（Aleo 仍 zero-tool；EVM/Solana 可触发 install targets）
- 文档：30 秒安装（非 formal Stage-0）

### D10 — Aleo twin 扩展

- 今天 deploy packaging 仅 StateCell 形 exact twin
- 按需登记更多模板（或生成器），禁止 silent 近似

### D11 — 网络 deploy（产品决策门）

仅当产品明确要：

- Solana：本地 validator 或显式 operator 网络（仍默认非 Devnet 自动水龙头）
- EVM：显式 RPC + key，默认 save/unsigned

在此之前 **`pf deploy` 保持 Aleo-only**。

---

## 7. 建议击杀顺序（从现在开始）

```text
现在 ──► D7a Solana verify 接入 pf          # 1–2 天，价值高、风险低
      ──► D7c EVM Anvil 最小 test wrap     # 2–3 天，对标「本地节点」
      ──► D7b Solana Mollusk focused test  # 2–3 天，host-heavy
      ──► D8  pf test 统一入口 + smoke 扩  # 1 天
      ──► D9  分发/安装体验                 # 按 release 节奏
```

**并行建议**

| 并行轨 | 内容 | 冲突面 |
|---|---|---|
| A | `targets/solana/verify.rs` + clap `verify` | pf-cli only |
| B | `scripts/pf_evm_test.sh` 最小 Anvil + `targets/evm/test.rs` | scripts + pf-cli |
| C | 文档 catalog：更新 chain-client-catalog localModes | docs only |

A∥B∥C 文件几乎不重叠，可多 agent。

---

## 8. 验收总表（D7 done 定义）

- [ ] `pf build -t solana && pf verify` 在 monorepo 示例或 `pf new` 模板上绿
- [ ] `pf build -t evm && pf test -t evm` host-optional 绿（缺 anvil skip 或明确错误）
- [ ] `pf test -t solana` host-optional 绿（或明确「需 just solana-runtime 依赖」）
- [ ] `pf run -t evm|solana` 行为有文档：实现或稳定 FC 文案（禁止含糊）
- [ ] `just pf-cli-smoke` 仍绿；新增 `pf-cli-solana-verify-smoke` / `pf-cli-evm-test` **不**绑 ordinary ci
- [ ] catalog / README 更新 local 能力表
- [ ] 无 Devnet 自动写、无 mainnet、无 `deployable=true` 改写

---

## 9. 非目标（整条 CLI 线）

- Python `pf`
- 合并进 Lean `proof-forge-next`
- mainnet / 默认 broadcast
- ordinary CI 跑 Mollusk/Anvil/snarkOS
- 第一期多程序 Aleo twin 自动综合
- 用 `pf` 取代 forge/anchor 完整框架

---

## 10. 对你问题的直接回答

1. **后续规划是啥？**  
   见上：D7（Solana verify → EVM Anvil test → Solana Mollusk test）→ D8 统一 `pf test` → D9 分发 → D10/D11 可选。

2. **Solana 自己的测试要做吗？**  
   **要。** 仓库已有 Mollusk + solana-client verify；应 **wrap 进 `pf verify` / `pf test -t solana`**，不是再发明一套。

3. **以太坊本地节点要做吗？**  
   **要。** 仓库已有 Anvil smokes；应 **wrap 成 `pf test -t evm`**（最小路径），不是在 `pf` 里重写 geth。

4. **这些就是 D7 吗？**  
   **对。** D7 = 把 EVM/Solana **本地验证与测试** 接到 `pf`；**不是** 链上部署。部署仍是 Aleo save-only（或更后的 D11 产品决策）。

---

## 11. 当前开发者命令速查（Aleo）

```bash
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
just pf-cli-build

pf new hello && cd hello
pf build
pf run -- initialize 5u64
pf deploy                 # testnet tx save-only
just pf-cli-smoke         # monorepo gate
```
