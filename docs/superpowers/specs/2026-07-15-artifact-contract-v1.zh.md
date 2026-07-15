# 制品契约 v1（草稿）

状态：**接缝 B（证据层）契约草稿**  
父设计：[Lean / Rust 边界](2026-07-15-lean-rust-boundary-design.zh.md)  
字段冻结前的权威：**已入库的 Lean 发射器 + 本文**；
若二者冲突，以代码为准，并在同一次变更中更新本草稿。

英文原文：[2026-07-15-artifact-contract-v1.md](2026-07-15-artifact-contract-v1.md)

这是 Phase 0 的交付形态：写清 Rust harness 与差分脚本可以依赖什么。
**不**引入 Rust 编译路径。

## 目的

消费者（testkit harness、compare bench、CI 脚本）必须把
`proof-forge-artifact.json` 及相关 sidecar 当作版本化 API：

- 必选顶层字段
- 类型化输出清单（`artifactBundle`）
- runner 加载文件的 path/hash 条目
- 诚实性规则（工具缺失时不能标绿）

## Schema 身份

| 项 | 值 |
|---|---|
| 文档 schema | `proof-forge-artifact` 消费者契约 |
| 当前 `schemaVersion` | `1`（CLI 可能发整数或字符串 `"1"`；消费者应两者都接受） |
| 嵌套 bundle kind | `proof-forge-artifact-bundle`，自有 `schemaVersion: "1"` |
| 破坏性变更规则 | 顶层 `schemaVersion` bump；可能时保留一个发布版本的 dual-read |

相关但**独立**的契约（不要混为一谈）：

| 契约 | 身份 | 说明 |
|---|---|---|
| SDK schema | `proof-forge.sdk-schema.v0` / `SdkSchema.schemaVersion = 0` | 客户端生成 |
| Deploy manifest | 如 `proof-forge-evm-deploy-manifest` | 链上部署辅助 |
| Benchmark result | `proof-forge.benchmark-result.v1` | 成本/行为 bench |
| Core export | `core.v0`（experimental） | 接缝 A；[草稿](2026-07-15-core-export-v0-draft.zh.md) |
| Observation / scenario | testkit scenario + harness trace | 独立版本 |

## 文件布局（典型产品构建）

确切文件名随 CLI 标志变化；有 metadata 指针时 harness 应优先用指针，
而不是硬编码路径。

```text
build/<target>/<Module>/
  proof-forge-artifact.json          # 必选元数据入口
  proof-forge-deploy.json            # 可选 deploy sidecar（EVM 常见）
  *.yul | *.s | *.wat                # 中间产物（按目标）
  *.bin | *.so | *.wasm              # 最终可部署物（按目标）
  proof-forge-sdk.json               # 可选 SDK schema
  proof-forge-client.ts              # 可选 client 包装
```

默认元数据文件名助手在 `ProofForge.Cli.Artifact`
（`defaultArtifactOutput`、`defaultDeployManifestOutput`）。

## 顶层字段（消费者最低集）

观察自主三链 CLI 制品（如 EVM ValueVault），并由
`ProofForge.Target.ArtifactBundle` 诚实性检查在精神上约束。

| 字段 | runner 是否必选 | 含义 |
|---|---|---|
| `schemaVersion` | **是** | 契约主版本（`1`） |
| `target` | **是** | 公开目标 id（`evm`、`solana-sbpf-asm`、`wasm-near` 等） |
| `targetFamily` | 建议 | 家族分组（`evm` 等） |
| `artifactKind` | **是** | 主声明（`evm-bytecode`、`solana-elf` 等） |
| `sourceModule` | **是** | 模块 / 产品身份字符串 |
| `sourceKind` | 建议 | 如 `contract-sdk`、`portable-ir`、fixture 类 |
| `fixture` | 可选 | 非自由产品路径时的 fixture id |
| `irVersion` | 可选 | portable-IR fixture 可设；SDK 源可为 null |
| `capabilities` | 建议 | 使用/声明的 capability id 列表 |
| `abi` | 随目标 | entrypoint/constructor/events（EVM 重；其他目标可不同） |
| `artifacts` | 加载文件时 **是** | 命名文件引用的 map 或 list（path + sha256 + bytes） |
| `artifactBundle` | 诚实性 **是** | 类型化多输出 bundle（PF-P1-03） |
| `toolchain` | 建议 | 工具路径/版本观察 |
| `validation` | 建议 | 命名校验结果 |
| `storageBinding` / `materialization` / `preflight` / `crosscallMaterialization` | 多数 runner 可选 | 规划元数据；勿仅凭这些发明运行时行为 |
| `sdkSchema` | 可选 | SDK schema 文件相对/路径指针 |
| `storageLayout` | 可选 | 目标存储描述 |

### 文件引用形状

凡供消费的文件引用，优先：

```json
{
  "path": "relative/or/absolute",
  "sha256": "<64 hex>",
  "bytes": 1234
}
```

校验完整性的 harness 须在字段存在时重算文件 hash，并与 `sha256` / `bytes`
比较（testkit 已支持嵌套 `[[artifact.file]]` 对照 metadata）。

## `artifactBundle`（类型化清单）

由 `ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson` 序列化：

| 字段 | 类型 | 说明 |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `kind` | string | `proof-forge-artifact-bundle` |
| `targetId` | string | 同一公开目标 id |
| `source` | object | `moduleName`、可选 `path`、`kind`、`leanElaborated` |
| `outputs` | array | 类型化输出（见下） |
| `primaryOutput` | string 或 null | 作为 primary 的输出 `kind` |
| `finalOutput` | string 或 null | 有最终可部署物时的 kind |
| `toolchain` | array | 工具溯源条目 |
| `validations` | array | 命名校验条目 |

### 类型化输出

| 字段 | 说明 |
|---|---|
| `kind` | 稳定 id：`yul`、`evm-bytecode`、`evm-initcode`、`sbpf-asm`、`solana-elf`、`wat`、`wasm` 等 |
| `role` | `intermediate` \| `primary` \| `final-deployable` \| `sidecar` |
| `path` | 可选路径字符串 |
| `sha256` | 可选 |
| `bytes` | 可选 |

### 工具溯源

| 字段 | 说明 |
|---|---|
| `tool` | 如 `lean`、`solc` |
| `stage` | 如 `source-elaboration`、编译/链接阶段 |
| `available` | bool |
| `version` / `declaredVersion` / `observedVersion` | 可选字符串 |

### 校验条目

| 字段 | 说明 |
|---|---|
| `name` | 稳定检查名 |
| `state` | `notRun` \| `passed` \| `failed` \| `unavailable` |
| `detail` | 可选 |

### 诚实性规则（须保持 fail-closed）

来自 `ArtifactBundle.validateHonesty`（对发射器规范）：

1. 若设置 `finalOutput`，须存在匹配 kind 的输出，且 role 为
   `final-deployable` 或 `primary`。
2. 若设置 `primaryOutput`，该 kind 须存在于 `outputs`。
3. `leanElaborated=true` 要求 Lean source-elaboration 工具溯源与
   `lean-toolchain` / 运行中 Lean 一致；不一致即错误。
4. `leanElaborated=false` 不得携带 source-elaboration 工具条目。
5. 不可用工具不得报告为 validation `passed`
   （只能用 `unavailable` 或 `failed`）。
6. 对必选门禁，`notRun` 永不可序列化为成功通过。

## 主三链最终 kind（runner 取向）

| 目标 id | 典型中间物 | 典型最终物 | 常见 runner 输入 |
|---|---|---|---|
| `evm` | `yul` | `evm-bytecode`（+ `evm-initcode` sidecar） | 按场景 runtime bytecode / initcode |
| `solana-sbpf-asm` | `sbpf-asm` | `sbpfBuild=passed` 时的 `solana-elf` | Mollusk/产品场景的 ELF |
| `wasm-near` | `wat` | `wasm` | offline-host / sandbox 的 wasm（+ metadata） |

若声明的 final kind 缺失或标为 failed/unavailable，runner 必须 fail-closed。

## Rust 可依赖的字段（Phase 0 白名单）

在不把可选规划字段当 ABI 的前提下，harness 可安全依赖：

1. `schemaVersion`、`target`、`sourceModule`、`artifactKind`
2. `artifactBundle.finalOutput` / `primaryOutput` + 匹配的 `outputs[]`
3. `artifacts` 下的文件引用 / 输出的 `path`+`sha256`
4. 目标特定 ABI/entrypoint 表——**仅**在 harness 已文档化编码处
   （EVM selector、Solana tag、NEAR method 名）
5. testkit TOML 中场景声明的 `[[artifact.*]]` 检查

避免硬编码：

- 不经 metadata 重解析的机器相关绝对路径前缀
- 假定跨 `solc` 版本 bytecode 相等
- 把 CanonicalEvidence 或诊断当作语义输入

## Dual-run / 证据比较

比较 Lean 产出与未来 Rust 产出时，门禁：

1. 运行时观察 parity（testkit traces）
2. 声明字段上的 entrypoint/ABI 面 parity
3. 匹配的 `target` + final output kind + 列出的最终文件内容 hash
4. 若定义了 normalizer，可选规范化中间文本

**不要**要求整份 artifact 文档 JSON 深度相等
（工具链路径字符串与自由 note 会漂移）。

## Phase 0 实现清单（未来分支）

- [ ] 对照本表盘点所有发射 `proof-forge-artifact.json` 的 CLI 路径
- [ ] 增加 Lean 或 golden 测试：必选消费者字段消失则失败
- [ ] 场景声明执行时，testkit core 拒绝缺失 `schemaVersion` / `target` / final output
- [ ] 在本契约旁文档化 observation JSON 字段（独立版本）
- [ ] 保持各 harness package 不跨链引入多链 SDK 依赖

## 本草稿的非目标

- 冻结 Core export（见 [core export v0](2026-07-15-core-export-v0-draft.zh.md)）
- 改变磁盘上的制品布局
- 宣称 Rust 后端生产就绪
