---
id: ADR-0008
title: 分离 Circuit zkVM 与 ZK Application Chain
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0008：分离 Circuit、zkVM 与 ZK Application Chain

- 状态：`proposed`
- 日期：2026-07-15

## 背景

“都使用零知识证明”不能说明执行、状态和结算相同。Noir、OpenVM、Aleo、Psy 处在不同层次
（`CLM-TAX-001`）；Psy 的状态/聚合模型仍依据 provisional `CLM-PSY-001/002`。

## 决定

- Noir：circuit compiler，状态连续性/结算 external。
- OpenVM：zkVM guest execution，状态/结算 external。
- Aleo：带 records/mappings 和 proof/final contexts 的 ZK application chain。
- Psy：带用户分区状态与网络证明聚合的 ZK application chain，当前 provisional。

四者拥有独立 Plan；不建立 `ZkPlan`。

## 后果

制品角色诚实区分 circuit workload、zkVM workload 与 chain transaction/deployment；wire
deployability 只使用 `SPEC-COMMON-001` 的 `ArtifactDeployability`，其中可验证工作负载为
`verifiable-workload`，且不得暗示已部署合约。共享只限披露词汇、proof provenance 和密码类型。

## 否决方案

- 按 proof system/field 把它们放入同一后端。

## 验证

Noir/OpenVM 无 exact adapter 时最多使用
`ArtifactDeployability=verifiable-workload`，不得宣称 deployable contract；Aleo/Psy dossier 明确
chain settlement。
