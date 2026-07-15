# 可移植能力、目标 Plan 与拼装代码生成 — 架构共识纪要

Status: **Current orientation note (2026-07-15)**  
English: [2026-07-15-portable-capability-plan-assembly-model.md](2026-07-15-portable-capability-plan-assembly-model.md)  
关联决策：**D-057**、**D-058**、**D-050**、**D-054**；证据扫描见
[solana-wasm-coverage-scan-2026-07-15.md](../../targets/solana-wasm-coverage-scan-2026-07-15.md)。

本文把阶段性架构讨论固化为仓库内共识，回答：我们在拼什么、和官方 SDK 差什么、
如何用高层抽象与 Plan 物化、以及如何用差分把「表达能力 / 生态完备度」做实。

---

## 1. 产品一句话

**ProofForge 是 experimental 的多目标合同编译器：** 用 Lean 写可移植（及可选链扩展）业务，经 **Canonical Core / CapabilityPlan** 与 **目标 Plan**，**拼出** Yul / sBPF 文本 / WAT，交给 **solc / sbpf / wat2wasm**，最终由 **链上 VM** 执行。

**不是：**

- Solana 官方 Rust SDK / Pinocchio / Anchor / NEAR near-sdk 的平替；  
- 在 Lean 里当生产运行时执行合同；  
- 用 Lean 实现完整 EVM / Wasm / sBPF **生产虚拟机** 作为部署路径。

---

## 2. 「拼装」= 代码生成，不是实现 VM

```text
Lean 作者面
    → Canonical Core + 能力需求
    → 各链 ModulePlan
    → 打印 Yul / .s / .wat
    → 外部工具 → 二进制
    → 官方/生态 VM 执行
```

| 角色 | 谁负责 |
|---|---|
| 业务语义 | Lean + Canonical Core |
| 链形态计划 | 各链 Plan |
| 指令文本 | Lean 打印机 |
| 打包二进制 | solc / sbpf / wat2wasm |
| 生产执行 | 链上 VM |

仓库内 sBPF/Wasm **解释器** 多为测试/形式化影子，不是产品执行主线。

**Solana 与 Wasm 的差别：** 都是「编译到别人的 VM」；指令集与主机模型不同（寄存器+syscall vs 栈+import）。

**不要**把「Lean 直接写」理解成默认手写三套完整 ISA；那只会更痛，且解决不了跨链语义。

---

## 3. 公共能力 vs 链独有能力

### 3.1 公共（portable）层

多链共享的业务语义：状态形状、运算与控制流、断言、事件意图、部分跨调意图、校验与能力需求等。  
应称 **portable / 共享语义**，不是「Public AI」。

### 3.2 链独有层

- Solana：账户图、PDA、CPI、sysvar、allocator、SPL 助手…  
- NEAR：promise、JSON/Borsh 主机形状、account-id…  
- EVM：selector/ABI、CREATE2、fallback、packing…  

按 **D-027 / D-050 / D-054**，独有能力在 **扩展 / Source.\<Chain\> / HostOp**，不永久污染共享 Core。

### 3.3 同名公共能力也会「分叉实现」

例如同一「存 u64 / 读调用者 / 发事件」，在 slot、账户 data、KV 上物化不同。  
完善时既要补 **独有能力**，也要保证 **公共能力在各链上的真实物化**。

---

## 4. 高层抽象 → Plan → 拼装

正确流水线：

```text
作者高层 API（PDA/CPI/promise…，不是 mov64）
  → 规范化语义记录（扩展、HostOp、材料化元数据）
  → 目标 Plan（账户、布局、入口、host 调用…）
  → 拼装 AST/文本
  → 外部工具 → 部署物
```

**Plan 吃结构化语义；拼装只实现 Plan。**  
独有能力必须 **先高层抽象再进该链 Plan**，最后才变指令——这是「物化好用」的关键。

---

## 5. 与官方 SDK「同一水平」意味着什么

### 5.1 不是同一产品

差在 **表达切片 + 生态接缝**，不是「我们 Lean VM 比官方弱」——生产上几乎不用自研 VM 执行。

### 5.2 两个可提升指标

| 指标 | 含义 | 如何提升 |
|---|---|---|
| **表达能力** | 能写什么且语义为真 | 能力表 + 高层 API + Plan + lower + **运行时/差分** − 静默子集 |
| **生态完备度** | 工具与习惯是否接得上 | 产物/IDL/客户端/部署/示例/与官方程序互操作/可选 sourcegen |

「提供差不多的能力」作为总纲 **对**；落地必须是 **列表有、语义真、作者写得出**。

### 5.3 现状诚实结论

- **不能** 与官方 Solana Rust / near-sdk 开发体验与 API 全集对等。  
- **能** 做受支持切片上的多链 experimental 产品与对照。  
- 不继续扩能力表，就 **达不到** 官方 SDK 水平。

---

## 6. Solana / Wasm 覆盖诚实摘要

详见扫描文。要点：

| | Solana sBPF | Wasm-NEAR |
|---|---|---|
| 简单 portable 产品编译 | 较好 | 较好 |
| 官方 SDK 全集 | 否 | 否 |
| 最大风险 | **Hash Phase-1 limb0**；事件/CPI 深度 | 多参数 string/bytes、U128、memory array 等 |
| 失败风格 | fail-closed + **静默子集** | 多 fail-closed |

**编译绿 ≠ 生产语义完备。**

---

## 7. 如何把体系「完善」起来

### 7.1 Supported Surface 表（范围）

表内承诺、表外 fail-closed。

### 7.2 能力包毕业（表达）

```text
作者 API → Plan → 拼装 → 运行时断言 → 表上 verified
```

优先消灭静默子集（全宽 hash 或降级命名）。

### 7.3 差分（主验收）

每个能力包：

1. 固定场景；  
2. ProofForge 产物；  
3. 最小官方风格参考（Pinocchio / near-sdk / Solidity）；  
4. **事先声明** 观察维度（状态、成败、返回、归一化日志；一般不比二进制全文）；  
5. 门禁。  

差分是 **验收与驱动修复** 的方法；**写合同仍靠高层抽象**，不是对着差分写汇编。

差分 **不够单独完成完善**：还要能力表、fail-closed、金测、文档诚实、生态接缝。

### 7.4 生态杠杆

稳定 artifact、客户端、一键部署文档、与官方程序 CPI/跨合同示例、可选 **生成官方 crate**（D-058：无现成库则不做 Rust 重打 sBPF/WAT 打印机）。

### 7.5 明确不做

- 默认作者路径 = Lean 内三套完整 ISA；  
- 产品路径用 Lean 取代链上 VM；  
- 无决策的 Rust 机器 IR 产品 lower；  
- 仅凭 product smoke 宣称 SDK 平替。

---

## 8. Seam A（Lean/Rust）一句

实验性 Core **导出** + Rust **只读** inspect/sketch/observe（入口与 slot）。产品 lower 仍 Lean。契约是版本化包，不是第二编译器（D-057/D-058）。

---

## 9. 相关文档

| 主题 | 文档 |
|---|---|
| 决策 | [decisions.md](../../decisions.md) / [decisions.zh.md](../../zh/decisions.zh.md) |
| Lean/Rust 边界 | [lean-rust-boundary](2026-07-15-lean-rust-boundary-design.zh.md) |
| Core 导出 | [core-export-v0](2026-07-15-core-export-v0-draft.zh.md) |
| EVM selector | [evm-selectors.md](../../targets/evm-selectors.md) |
| 覆盖扫描 | [solana-wasm-coverage-scan-2026-07-15.md](../../targets/solana-wasm-coverage-scan-2026-07-15.md) |

---

## 10. 底线四句

1. **公共 portable 能力 + 链独有高层能力 → 目标 Plan 物化 → 拼装 → 外部工具 → 链上 VM。**  
2. **独有能力先高层抽象再进 Plan**，公共能力也会按链分叉物化。  
3. **提高「官方水平」= 能力表 + 真语义 + 差分毕业 + 生态接缝**，不是 Lean 实现三套 VM，也不是拼装打印机等于官方 SDK。  
4. **差分对比官方最小参考 = 主验收引擎；Supported Surface + fail-closed = 主范围引擎。**
