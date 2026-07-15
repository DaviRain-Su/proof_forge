---
id: ADR-0011
title: 使用静态且受审计的目标注册表
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0011：使用静态、受审计的目标注册表

- 状态：`proposed`
- 日期：2026-07-15

## 背景

动态插件可以扩展 target，但会把任意代码、能力声明和供应链引入编译器信任边界，且难以证明 requirements resolution 完整。

## 决定

V2 初期使用编译期静态 registry。target/profile/support claims 都来自已审查源码和 lockfile；CLI 不从当前目录、环境变量或网络动态加载 materializer。

未来若需要 out-of-process plugin，必须新增 ADR，定义签名、sandbox、协议版本、capability evidence 与撤销机制。

## 后果

增加 target 需发布新编译器版本，但安全与可重现边界清晰。

## 验证

unknown target、alias、动态库/配置注入、PATH spoof tests 必须失败。
