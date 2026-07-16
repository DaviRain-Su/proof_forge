---
id: ADR-0005
title: 能力与扩展精确匹配并默认拒绝
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0005：能力与扩展精确匹配并默认拒绝

- 状态：`proposed`
- 日期：2026-07-15

## 背景

“支持 call/storage/privacy”这类布尔能力无法表达调用模式、失败边界、版本和前置条件，容易产生假兼容。

## 决定

前端推导正交 requirements；registry 使用 `SupportClaim` 以 exact version、semantics digest、preconditions 和 evidence grade 声明支持。扩展身份为 namespace + name + exact semver + semantics digest。

任何缺项、前置条件失败、版本或 digest 不匹配都失败。禁止近似版本、alias 猜测、evidence downgrade 和 fallback。

## 后果

增加 registry 维护成本，但支持声明可审计、可撤销、可精确诊断。

## 否决方案

- target capability bitset。
- “后端能打印就算支持”。

## 验证

每条 requirement 有 positive/negative/mismatch test，manifest 记录实际 resolution。
