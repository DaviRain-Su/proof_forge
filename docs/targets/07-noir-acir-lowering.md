---
id: TARGET-NOIR-ACIR
title: Noir ACIR / circuit IR lowering plan (ProgramV1 → ACIR authority)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Noir ACIR 层落地规划

状态：`draft`（规划输入；**实现未开始**）  
目标：在 **不改变 ProgramV1 可移植业务语义** 的前提下，把 Noir target 的权威物化从 **Noir 源包（`.nr` relations）** 切向官方 **电路中间表示（ACIR 及相关编译产物）**，并评估 admit 面覆盖。

与 Psy / Aleo 对照：

| | Psy | Aleo | Noir（本规划） |
|---|---|---|---|
| 旧 sole 权威 | `.psy` 文本 | Leo 源 | **Noir source package**（`main.nr` + Nargo.toml） |
| 新 sole 权威 | DPN package JSON | Aleo Instructions | **ACIR / nargo compile 电路产物**（精确形态 IR-1 冻结） |
| 工具 pin | dargo 0.1.0 | Leo 4.0.2 | **nargo 1.0.0-beta.26**（Tool Lock 已有） |
| 作者语言 | ProgramV1 | ProgramV1 | ProgramV1 |

权威上游（规划 pin；IR-1 实测冻结）：

| 项 | 值 |
|---|---|
| 工具 | locked **nargo 1.0.0-beta.26** |
| 官方语言 | Noir → **ACIR**（Abstract Circuit IR）→ backend prove |
| 工程现状 | 产品 emit `relations/*/src/main.nr`；`NoirCompileAcceptance` / host-optional `nargo compile`；**无** ACIR 产品制品 |
| 非本阶段 | Barretenberg prove/verify、CRS、VK 产品绑定、formal |

**非目标：**

- 把完整 Noir 语言手册变成作者语言。
- 默认 product Finalize 调 prove/verify。
- unconstrained / oracle / foreign call。
- 声称 “ACIR 生成 = circuit proof 完成”。

---

## 1. 动机

当前 Noir 路径：

```text
ProgramV1 → Semantic → NoirPlan → relation IR → Noir source package (.nr)
                              └─ 可选：nargo compile（compile-only 验收，无 ACIR 入库）
```

问题（与 Psy `.psy` / Aleo Leo 同构）：

1. **脆性**：与 Noir 源语法 / nargo 版本耦合。  
2. **双重真相**：可证明的电路形状在 ACIR/backend；`.nr` 是第三方言。  
3. **覆盖 KPI 失真**：易写成 “能吐 Noir 源”。正确 KPI = **admit 面在 ACIR 上诚实编码**。  
4. **已有 compile 门**：locked nargo 可作金样抓取，却未成为产品权威。

目标路径：

```text
ProgramV1 → Semantic → NoirPlan → NoirAcirIR / ACIR bytes|JSON
                │                      │
                │                      ├─ ≡ nargo compile 产物（金样）
                │                      ├─ 可选：调试 .nr（非权威）
                │                      └─ 后续：prove backend 消费 ACIR
                └─ 现有 .nr 发射在 ACIR 主路径稳定前保留为过渡
```

---

## 2. 目标模型（实现必须对齐）

### 2.1 先冻结 “金样是什么”

IR-1 **必须** 用 locked nargo 对产品 Counter package 实测：

- `nargo compile` 输出目录中的 **ACIR / circuit artifact** 文件名、编码（JSON vs binary）、是否含 Brillig。  
- 选定 **sole 金样形态**（优先：可稳定 round-trip 的 ACIR 序列化；若 nargo 只产 opaque 目录，则 pin **规范化文件集 + 内容 hash** 并文档化）。

**禁止** 在未打开真实 artifact 前假设 schema。

### 2.2 与 NoirPlan 关系

- 保留 `NoirPlan` / relation IR 为 target-owned 中间层。  
- 新增 `Plan → ACIR`（或 `Plan → nargo-input + 我们自己的 ACIR encoder` 若与 nargo 对齐）。  
- 短期诚实路径：**产品 dual-write** — primary ACIR（或 compile extras）+ debug `.nr`。  
- 若无法在无 nargo 的情况下 pure-Lean 编码 ACIR：IR-2 可为 **capability 内调用 locked nargo 仅抓 ACIR**（host-heavy / Finalize 可选），Lean 侧做 validate/hash/pin——须在 IR-1 决策并写清 **非 hermetic**。

### 2.3 验证阶梯

| 阶 | 门 | 完成标准 |
|---|---|---|
| G0 | 金样捕获 + pin | Counter nargo compile artifact 入库 + 文档 |
| G1 | Schema/codec 或 inventory hash | round-trip 或 exact multi-file pin |
| G2 | Plan→ACIR MVP | Counter ≡ 金样（结构或字节） |
| G3 | 控制流 / 聚合 admit 面 | 与现 Noir Plan 一致 |
| G4 | 产品 primary ACIR | `.nr` debug-only |
| G5 | admit 矩阵 | Y/P 有 ACIR 或 FC |
| G6 | prove lane | 独立 host-heavy；非 ordinary ci |

---

## 3. 覆盖目标

> ProgramV1 在 **Noir 已 admit** 的构造 → 确定性 ACIR 编码；不 admit → 稳定 FC。

**不是：** 全 Noir 语法、unconstrained、full prove pipeline、formal。

### 3.2 矩阵（初稿）

| 族 | 现 Noir 路径 | ACIR 目标 |
|---|---|---|
| UInt*/Field bn254 算术 | Y | **Y** |
| Bool / 比较 / 逻辑 | Y | **Y** |
| Array/Map/Bytes flatten | Y/P | **Y/P** |
| if/match/for | Y | **Y** |
| pureFn | Y | **Y** |
| call/schedule slots | P | **P/F**（诚实） |
| Option/String state | F | **F** |
| prove/VK | F | **F** 直至 G6 |

---

## 4. 分阶段实现

### NOIR-IR-0 — 规划（本文档）

- [x] 选定 ACIR/compile 产物为权威方向  
- [x] Tool Lock 注释：nargo pin 与 ACIR 权威关系（`docs/specs/toolchains.md` nargo 行）  

### NOIR-IR-1 — 金样 + schema 探路

- [ ] locked nargo 对 Counter 抓 compile 产物  
- [ ] 冻结 golden 路径 `testdata/golden/noir-acir-v1/`  
- [ ] Lean：最小 Schema/inventory codec **或** multi-file exact pin + 测试  

### NOIR-IR-2 — Plan→ACIR MVP

- [ ] Counter Plan 路径 ≡ 金样  
- [ ] 文档：nargo-assisted vs pure-Lean  

### NOIR-IR-3..5 — 控制流 / 聚合 / 诚实矩阵  

### NOIR-IR-6 — 产品 primary ACIR；`.nr` debug  

### NOIR-IR-7 — prove honesty（工具存在时）  

---

## 5. 与现有 Noir 工程的关系

| 现状 | 保留 |
|---|---|
| relation Plan + `.nr` emit | 过渡 |
| locked nargo compile-only | 金样 + 对照 |
| Finalize zero-tool / non-deployable | 直至产品决策 |
| NoirCompileAcceptance | 不删除；可扩 ACIR pin |

---

## 6. 风险

| 风险 | 缓解 |
|---|---|
| ACIR 格式随 nargo 漂移 | exact nargo pin；未知字段 fail closed |
| 无法 pure-Lean 编码 | nargo-assisted 诚实路径 + 非 hermetic |
| 范围膨胀到 prove | G6 独立；deployable=false |
| 与 Aleo/Psy 抢主线 | **本规划起 Active = Noir ACIR**；Aleo/Psy idle residual |

---

## 7. DoD

### MVP（IR-2）

- Counter ACIR（或冻结 artifact 集）与 locked-nargo 金样结构/字节相等。  
- 测试进 targets shard。  
- `.nr` 声明为过渡。

### 非完成

- prove/verify 产品门、CRS、formal、全 Noir 表面。

---

## 8. 下一步

1. **NOIR-IR-0 收尾**（本文 + AGENTS Active）。  
2. **NOIR-IR-1**：nargo 抓 Counter 金样 + pin 策略。  
3. **NOIR-IR-2**：Plan→ACIR 或 nargo-assisted 权威路径。

规划 owner：engineering。  
产品决策：Aleo 可工程队列空后 **切换 Noir 中间 IR（ACIR）**；先规划后实现。
