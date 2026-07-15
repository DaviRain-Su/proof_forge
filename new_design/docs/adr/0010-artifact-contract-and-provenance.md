---
id: ADR-0010
title: 所有输出遵循制品契约与来源证明
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0010：所有输出遵循制品契约与来源证明

- 状态：`proposed`
- 日期：2026-07-15

## 背景

不同 target 输出 bytecode、ELF、Wasm、circuit、proof 或 guest。统一 CLI 容易把“文件已生成”误说成“合约可部署”。

## 决定

每次构建输出版本化 manifest，记录 source/semantic/plan/IR/artifact hashes、三层 profile、toolchain/dependency digests、output media/purpose、deployability、support resolution、diagnostics、proof/evidence 与 reproducibility。

时间、绝对路径、随机 seed 和不稳定排序必须规范化。proof/VK 绑定 program/VM/config/I/O schema。

## 后果

用户可验证输出来源和能力；manifest schema 需要版本治理。

## 验证

重复构建 hash、路径迁移、tampered artifact/profile/proof negative tests。
