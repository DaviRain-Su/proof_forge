---
id: RPT-006
title: 安全与迁移研究
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# 安全与迁移研究

状态：`draft`
研究日期：2026-07-15

## 威胁目标

保护对象包括业务语义、目标解析、编译器/工具链供应链、制品来源、私有 witness、链上权限以及 V2 的架构独立性。攻击者可能提供恶意源码、扩展、配置、制品或外部工具输出。

## 主要风险

| 风险 | 失败方式 | 必需控制 |
|---|---|---|
| 语义漂移 | 不同 target 改变 overflow/rollback/effect 顺序 | 参考解释器、requirement resolution、差分测试 |
| 能力谎报 | backend 声称支持但遗漏前置条件 | exact SupportClaim、semantics digest、证据等级 |
| 扩展冲突 | 同名扩展在不同版本含义不同 | namespace + exact semver + digest；默认拒绝 |
| 工具链污染 | PATH/缓存命中旧工具 | lockfile、binary digest、清空环境的 archive gate |
| 父项目耦合 | import/copy/fallback 恢复旧架构 | 禁止路径清单、symlink/import/binary 扫描 |
| 私有数据泄漏 | witness 进入日志/manifest/public input | disclosure typecheck、日志脱敏、制品分类 |
| proof 未绑定 | 验证了另一程序/配置的 proof | 绑定 semantic/VM/config/I/O/VK hash |
| 资源耗尽 | 恶意程序导致编译或证明失控 | bounded loops、size limits、timeouts、quotas |
| 非确定构建 | path/time/randomness 改变制品 | canonical serialization、seed/profile 锁定 |

## 失败策略

稳定错误族包括：`PF-TARGET-UNKNOWN`、`PF-REQ-UNSUPPORTED`、`PF-REQ-PRECONDITION`、`PF-SEMANTICS-MISMATCH`、`PF-EXTENSION-VERSION`、`PF-PLAN-INVARIANT`、`PF-TOOLCHAIN-MISMATCH`、`PF-ARTIFACT-NONDEPLOYABLE`、`PF-SETTLEMENT-UNAVAILABLE`。

所有错误携带 phase、target、requirementId、span、expected 和 actual。禁止 target fallback、兼容路由、evidence downgrade 或“best effort”成功。

## 从父项目迁移

迁移单位不是旧模块，而是独立需求：

```text
parent commit/path observation
→ atomic requirement or failure scenario
→ V2 ADR/spec
→ V2-owned test oracle
→ independent implementation
→ target runtime/proof evidence
```

退役的旧源码入口名称只允许出现在本迁移说明和显式禁止清单中，不能成为 V2 alias。禁止引用父 Lake package、`ProofForge.*` import、父 scripts/fixtures/build outputs、父 executable、父 `.olean` cache，以及指向父路径的 symlink。

## Archive gate

1. 将 `new_design/` 复制为不含 `.git`、父目录和缓存的 archive。
2. 新建临时 HOME；清空 `LEAN_PATH`、Lake path、旧 binary PATH 和目标工具环境变量。
3. 仅按 lockfile 安装/发现允许工具。
4. 执行 docs、build、unit、negative、reproducibility 和 Phase 1 target gates。
5. 扫描 archive、manifest 和进程日志，确认不存在父绝对路径或旧命名空间。

## 迁移准入/回滚

- V2 不替换父产品路由；两者并存，直到 V2 独立发布门禁通过。
- 任一 target 未达到其 dossier 的 runtime/proof evidence，不得在 README 宣称 implemented。
- 发布失败通过撤回 V2 artifact/profile 完成，不回退到父实现继续返回成功。

## 开放风险

- 外部 proof backend 的供应链和 reproducible build 能力。
- 网络升级造成历史 profile 失效时的撤销与再验证流程。
- Psy pre-testnet 规范快速变化，当前仅可建立隔离研究 sandbox。
