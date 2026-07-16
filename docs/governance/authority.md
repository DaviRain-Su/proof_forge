---
id: GOV-AUTH-001
title: 权威、角色与批准
status: proposed
owner: maintainers
updated: 2026-07-15
normative: true
---

# 权威、角色与批准

## 角色

| Role | 责任 | 不可单独批准 |
|---|---|---|
| Product Owner | Phase 0/1、范围和成功指标 | 安全豁免、语义兼容 |
| Architecture Owner | ADR、系统/模块边界 | 自己实现的发布证据 |
| Language/Semantics Owner | DSL、type/effect/Core | target maturity |
| Target Owner | descriptor/Plan/tool/runtime evidence | shared semantics 变更 |
| Quality Owner | tests、trace、EV、release gate | 删除失败测试 |
| Security Owner | threat model、finding、advisory | 自己唯一实现的安全修复 |
| Release Manager | candidate、签名、发布/回滚 | 绕过 required gates |

人员映射在仓库 CODEOWNERS/maintainers 文件落地前以 release report 的实名/账号记录为准；
角色可以同人兼任，但 security-critical 变更至少两位不同审阅者。

## 批准矩阵

- PRD：Product + Architecture。
- Architecture/ADR：Architecture + 受影响 owner；安全边界加 Security。
- DSL/Semantic schema breaking：Architecture + Semantics + Quality。
- Target promotion：Target + Quality + Security，有 runtime/proof evidence。
- Release：Release + Quality + Security；P0/P1 findings 为零。
- Emergency disable：Security + Release，可先禁用后在 24h 内补 ADR/记录。

批准必须记录 commit、日期、review link、开放 finding；聊天口头同意不算 accepted。
