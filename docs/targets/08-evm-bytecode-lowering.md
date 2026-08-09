---
id: TARGET-EVM-BYTECODE
title: EVM bytecode authority research note (ProgramV1 → Yul → solc bytecode)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# EVM 更底层权威 — **研究暂停**（非 Active lane）

状态：`draft` / **research-only pause**  
**产品决策（2026-08-08）**：EVM **只停在研究**，**不**升为 Active 实现 lane，**不**开 EVM-BC-1.. 工程切片 workflow，**不**改产品 primary artifact。

## 研究问题（仅备忘）

对标 Psy DPN / Aleo Instructions / Noir ACIR 的模式，EVM 是否应把 **solc 产出的 bytecode 内容绑定** 提升为 sole 产品权威，而 Yul 降为 debug/对照。

| | 当前 EVM 工程事实 | 研究假说（未立项） |
|---|---|---|
| 产品主产物 | Yul / solc 工程路径 + 既有 solc/Anvil 门 | 可能：bytecode exact pin 为权威 |
| 中间 | Yul 文本 | 可能：Yul = debug（对标 `.nr`；Psy/Aleo 已采用 direct artifact） |
| 工具 | locked solc + Anvil 差分 | 已有，无需新发明 |
| 非目标 | 主网、formal hermetic | 不变 |

## 明确不做（暂停期间）

- 不创建 `EVM-BC-1` inventory 实现、不扩 golden 仓库为产品 cutover  
- 不改 Finalize dual-write / hard-require  
- 不把本文写成 “下一步必做” 或 AGENTS Active  
- workflow / 实现代理 **不得** 自动切到 EVM bytecode lane  

## 何时可重开

仅当用户 **显式** 说启动 EVM bytecode 实现（或等价决策）时，再扩展本文为完整 IR 规划并改 Active。

## 现状诚实（实现事实，非本笔记交付）

EVM 已有 retained Semantic Plan、Yul emit、solc 验收与 Anvil 差分工程门。  
**未**做与 Psy/Aleo/Noir 同构的 “更底层 sole 权威 cutover”。

## 建议阶段（冻结；未授权实施）

1. EVM-BC-0 — 研究笔记（本文）  
2. EVM-BC-1 — Counter solc bytecode 金样（**未开**）  
3. EVM-BC-2 — product primary bytecode（**未开**）  
4. EVM-BC-3 — hard-require（**未开**）
