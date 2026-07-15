---
id: DOC-GLOSSARY
title: 术语表
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# 术语表

| 术语 | 定义 |
|---|---|
| `program` | 唯一用户源码顶层声明；不表达部署类别 |
| `Lean Syntax` | Lean Parser 产生的语法树；负责语法结构，不是 ProofForge 业务 IR |
| `Source.Program` | ProofForge syntax decoder 产生的未解析领域 AST，保留源码名称 |
| `Typed.Program` | 已完成当前检查集且把名称解析为稳定 ID 的 checked source AST |
| `Semantic.Program` | 目标中立、规范化且供 materializer 消费的业务语义及其 `ProgramRequirements` |
| `ProgramRequirement` | 从源码推导的原子语义需求，带稳定 ID 与 source span |
| `Capability` | target 声明可保持的语义能力及精确版本、前置条件和证据等级 |
| `Extension` | 可选、命名空间化、版本化的非 portable 语义；使用后限制可编译目标 |
| `TargetId` | 执行/结算语义身份，如 `evm`；不包含编译器或网络版本 |
| `CodegenProfileId` | 代码生成、ABI 和外部工具链配置身份 |
| `NetworkProfileId` | 部署网络、chain ID、RPC 和费用策略身份；不影响编译语义 |
| `ResolvedProgram target` | requirements 已由指定 target 精确满足的类型化见证 |
| `Materializer` | 将 resolved semantics 转为 target-owned Plan 的组件 |
| `Plan` | ABI、状态布局、host imports、调用/证明接线和资源策略的目标专属结构 |
| `TargetIR` | target lowering 后、artifact encoding 前的类型化机器表示 |
| `OutputSet` | 制品、manifest、诊断和 provenance 的原子输出集合 |
| `ArtifactEncoding` | EVM bytecode、ELF、Wasm、ACIR 等编码，不等于执行语义 |
| `ExecutionHost` | 实际解释制品并提供 host API 的运行环境 |
| `CommitModel` | 状态成功、回滚和异步边界的提交模型 |
| `StateBinding` | logical state 到 storage/accounts/KV/witness 的映射方式 |
| `ProofModel` | 无证明、电路证明、zkVM 证明或链内证明/最终化模型 |
| `SettlementModel` | 状态和结果最终由何种 ledger/verifier 接受 |
| `SourceHash` | 规范化源码语义身份；排除绝对路径、注释和非语义 span |
| `SemanticHash` | 规范序列化 `SemanticProgram` 的哈希 |
| `PlanHash` | 规范序列化 target Plan 的哈希 |
| `EvidenceGrade` | `specified`、`artifact_validated`、`local_runtime`、`network_or_proof_validated` |
| fail closed | 缺少支持、版本、工具或证据时返回稳定错误，绝不降级为成功 |
| archive isolation smoke | 历史开发检查：把允许文件复制到临时目录并重建/测试；不等于完整 clean-room |
| network-denied clean-room alpha | 从 committed archive 在新 HOME/cache、受控 PATH 和网络沙箱中执行的开发门禁；外部动态库与宿主 harness closure 尚未锁定 |
| clean-room gate | 使用内容锁定的完整 tool/runtime closure，在新 HOME/cache、受控 PATH/工具根且不可发现父 Git/path 的独立构建和测试 |
| hermetic | 构建和运行依赖均被完整识别、内容寻址，或由明确受信 host profile 约束；只校验顶层 executable hash 不足以满足 |
| content-addressed tool | 由精确 archive/file SHA 标识、离线安全物化并验证完整非系统运行闭包的工具 |
| host profile | 对不可打包的 OS/Xcode/system runtime 记录精确 build、实现路径/hash、签名/行为与 hermetic 资格的信任边界 |

`private`/`public` 描述信息披露；authority 描述谁能授权；state custody 描述谁持有
状态。这三个维度不可互相替代。
