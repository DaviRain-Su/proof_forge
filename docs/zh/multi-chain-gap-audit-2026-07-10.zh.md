# 多链愿景差距审查

状态：**当前修复工作的权威事实源** —— Delivery Wave 0（P0
正确性与声明诚实性门禁）已于 commit `1599f37d`（2026-07-11）**关闭**；下文
列出的每个 PF-P0-0N 门禁现在都运行在 `just check` 中。
finding 正文原样保留作可追溯的修复记录；其逐任务验收已对照 *Wave 0
closure* 小节列出的门禁重新核对。

日期：2026-07-10（审查）。Wave 0 关闭于 2026-07-11 验证。

本审查把产品愿景（只维护一份业务逻辑，在构建时选择 target）与 `main`
上的代码和可运行门禁进行对照。它是当前跨项目修复优先级的权威来源。
旧 backlog 和阶段计划仍可作为实现历史参考，但不能覆盖本文的发现和顺序。

长期执行入口：
[`多链修复 Agent 持久目标`](../agent-goal-prompt.md)。

官方通用业务逻辑接口是 `contract_source`，它会 elaboration 为
`ContractSpec` 和 portable IR；`TokenSpec` 仍是第一等的专项 token-intent
接口。自动编译任意 Lean 函数不在本审查目标内。主要产品 target
是 `evm`、`solana-sbpf-asm` 和 `wasm-near`；其他已注册 target
只审查行为是否诚实、晋级条件是否明确，不要求具备同等生产能力。

## 结论摘要

ProofForge 已经具有真实的多链纵向切片。同一份 Counter、ValueVault 和
RemoteCall 业务源码可以通过 portable 路径降低到三个主要 target，而且仓库
中存在大量运行时、制品和形式化检查。项目并不只是若干源码模板的集合。

但是，最终愿景对完整 target 组合尚未成立。最大风险是以下五个接口之间的
契约分裂：

1. `--list-targets` 宣称了什么；
2. target-first `build` 接受什么；
3. 后端实际降低了哪个输入；
4. 输出是中间产物还是可部署制品；以及
5. 元数据和文档声称验证了什么。

最严重的例子是静默替换输入：四个 target-first 构建接受
`Examples/Product/ValueVault.lean` 并返回成功，实际却生成内置 Counter。
在扩展更多 target 之前必须先修复这一问题。

## 审查证据

以下命令于 2026-07-10 在提交 `92e79867` 上运行：

| 检查 | 审查时结果 | 能够证明的事实 |
|---|---|---|
| `just product` | 通过，但有覆盖缺口 | `portable-default` 统计到 20 个 Product 源文件，但 `Tests/Product/Matrix.lean` 只导入 18 个；Counter 和 RemoteCall 会为主要 target 构建，RemoteCall 也会覆盖 Soroban |
| `lake env proof-forge --list-targets` | 通过，10 个 id | Registry 当前公开下方 target 矩阵中的十项 |
| `lake env lean --run Tests/TargetRegistry.lean` | 通过 | Registry 查找和已声明 profile 在内部一致 |
| `scripts/docs/audit-doc-code-sync.sh` | 通过，同时报告 7 项 advisory finding | 当前文档仍有一项 P1 和六项 P2 代码同步问题 |
| `scripts/i18n/check-sync.sh` | 失败 | 在本审查文档变更前，`README.md`、`docs/INDEX.md`、`docs/portable-ir.md` 和 `docs/targets/wasm-family.md` 已过期 |
| `just check` | 在 `docs-check` 停止 | 到 `scripts/i18n/check-sync.sh` 之前执行到的步骤通过；聚合命令因同样四份翻译过期而退出，后续 recipe 未运行 |

本审查集成完成后又执行了交付验证。过期翻译已同步；随后 `just check`
发现一项既有 testkit 期望落后于 `09e73553` 新增的、可操作的 Solana 空
peer 诊断。该场景已改为断言稳定的诊断前缀。针对性 testkit 检查和最终
完整 `just check` 均通过。这项基线修复不代表下方任何架构任务已经完成。

静默替换探针对五个 target 使用同一份源码：

```sh
lake env proof-forge build --target <target> --root . \
  -o build/audit-input-identity/<target> \
  Examples/Product/ValueVault.lean
```

观察结果：

| Target | 退出码 | 输出身份 |
|---|---:|---|
| `psy-dpn` | 0 | Counter `.psy` |
| `aleo-leo` | 0 | `program counter.aleo` |
| `wasm-cosmwasm` | 0 | 静态 CosmWasm Counter WAT |
| `move-aptos` | 0 | Counter Move package |
| `wasm-cloudflare-workers` | 1 | `unknown target 'wasm-cloudflare-workers'` |

生成文件位于被忽略的 `build/` 下，不是仓库源码。

## 当前 target 矩阵

本表中的成熟度表示已经被证据证明的行为，而不是 README 当前打印的标签。

| Target | 当前实际接受的产品输入 | 流水线与输出 | 验证证据 | 诚实的当前状态 | 晋级阻塞项 |
|---|---|---|---|---|---|
| `evm` | `contract_source`；专项 `TokenSpec` | 合约主体：`ContractSpec -> IR -> EVM Plan -> Yul AST -> solc -> bytecode`；token intent：`TokenSpec -> evm-erc20-contract` | Foundry、Anvil、元数据和可执行 Yul trace | 主要 Experimental；可部署 | 更广的产品场景与 proof fragment |
| `solana-sbpf-asm` | `contract_source`；专项 `TokenSpec` | 合约主体：`ContractSpec -> IR -> Asm AST -> .s`；token intent：`TokenSpec -> solana-spl-token-plan` 或 `solana-token-2022-plan`。`SolanaModulePlan` 已存在，但通用 CLI 路径不消费完整 plan，源码构建也不调用 `sbpf build` | 汇编、Pinocchio 等价性、可选/live ELF 门禁、可执行 sBPF 模型 | 主要 Experimental；最终制品路径不完整 | plan 驱动生产路径、通用源码到 ELF、诚实元数据 |
| `wasm-near` | `contract_source`；专项 `TokenSpec` | 合约主体：`ContractSpec -> IR -> 较小的 surface plan/lower context -> Wasm AST -> WAT`；token intent：`TokenSpec -> near-nep141-plan`。`NearModulePlan` 主要是旁路/测试路径，即使构建成功也可能没有 Wasm | offline host、WAT/Wasm 元数据、形式化制品/trace 锚点 | 主要 Experimental；存在 Wasm 时可本地执行 | 完整 plan 驱动生产路径、严格 Wasm 构建、通用异步/运行时和 sandbox 门禁 |
| `wasm-stellar-soroban` | `contract_source` | 共享 EmitWat + `HostBridge.soroban` -> WAT/Wasm | 产品 materialization smoke 和 Counter refinement | Host-adapter Spike | 错误的 NEAR capability plan、NEAR wrapper 命名、auth/contract-spec/runtime 缺口 |
| `wasm-cosmwasm` | 实际为 fixture | Counter 专用 WAT adapter；target-first 源码输入会被忽略 | Counter golden 和可选 `cosmwasm-check` | Counter Spike | fail-closed 输入、通用 plan/AST 路径、真实 submessage/runtime |
| `wasm-cloudflare-workers` | 仅 fixture emit | portable IR fixture -> TypeScript Worker | 安装工具时执行 TypeScript type-check 和 Wrangler dry-run | 链下 Research Spike | target-first build 缺少明确的 unsupported-command 路径；profile 错误标为 Wasm |
| `move-aptos` | 实际为 fixture | Counter -> 字符串渲染的 Move package | golden package 和可选 Aptos CLI smoke | Counter Spike | fail-closed 输入、通用 Move plan/AST、运行时场景 |
| `move-sui` | 显式 Counter fixture | Counter -> 字符串渲染的 Move package | package/layout/client 检查；安装工具时执行本地 Sui 门禁 | Counter MVP | 通用源码 lowering 和 typed Move 流水线 |
| `psy-dpn` | 实际为 fixture/sourcegen 子集 | 内置模块 -> Psy Plan/AST -> `.psy`，可选 Dargo circuit JSON | golden、diagnostics、元数据和可选 Dargo smoke | 受限 sourcegen 路径；不是通用 `contract_source` | fail-closed 输入与精确 supported-fragment 契约 |
| `aleo-leo` | 实际为 fixture/sourcegen 子集 | 内置模块 -> Leo AST/printer -> Leo source | golden/sourcegen smoke；Leo CLI 可选 | Research Spike | fail-closed 输入和不支持运算的 printer 错误 |

`quint` 是 CLI-only 形式化模型 target。它有意不属于 `Target.knownIds`，
不得被描述为可部署编译器 target。

## Wave 0 closure（2026-07-11 验证，commit `1599f37d`）

全部 8 个 P0（正确性与声明诚实性）任务已关闭：其验收 smoke 已接入
`just check`，相关产品行为已对照实时代码重新验证。P1 工作（统一的
编译器/target 契约）仍是当前活动队列 —— 见 `agent-goal-prompt.md`。

| 任务 | 验收门禁（现已接入 `just check`） | 状态 |
|---|---|---|
| PF-P0-01 target-first 构建静默替换 Counter | `just source-identity` | 已关闭 |
| PF-P0-02 注册表与可执行命令支持不一致 | `just registry-command` | 已关闭 |
| PF-P0-03 Solana 通用构建声明它未发射的最终制品 | `just solana-source-elf` | 已关闭 |
| PF-P0-04 Soroban 构建解析到错误的 target profile | `just soroban-profile` | 已关闭 |
| PF-P0-05 文档与翻译门禁不诚实 | `just doc-sync-audit-strict`（+ `scripts/i18n/check-sync.sh`） | 已关闭 |
| PF-P0-06 `near_gas` 被误标为累积 Wasmtime fuel | `just near-budget-honesty`；offline-host 现发射 `wasmtimeFuelCumulative`/`wasmtimeFuelDelta` 并拒绝 `near_gas` 作为产品名 | 已关闭 |
| PF-P0-07 `check` 不经后端验证即可通过 | `just check-l2-parity` | 已关闭 |
| PF-P0-08 Wasm 构建在未生成 Wasm 时成功 | `just wat2wasm-fail-closed` | 已关闭 |

下文的 finding 段落是 2026-07-10 的原始文本，仍作为修复理由保留；它们
未被重新打开。

## 发现与修复任务

### P0：正确性与声明诚实性

#### PF-P0-01 - Target-first build 静默替换成 Counter

**证据：**`ProofForge/Cli/TargetFirst.lean` 把 CosmWasm、Psy、Aleo 和 Aptos
的所有非 `.learn` build 映射到 Counter legacy flag，并未检查
`isLeanSource`。随后 `ProofForge/Cli/SourcegenCommands.lean` 直接降低
`IR.Examples.Counter`。上方探针确认了错误输出仍返回成功。

**必须修改：**fixture-only 路径必须拒绝任何源码参数。保留显式的
`emit --target ... --fixture ...` 接口。只有在 adapter 加载该输入对应的
`ContractSpec` 并把它传入 lowerer 后，target 才能接受 `contract_source`。
所有源码派生制品必须记录输入路径哈希和 `spec.name`。

**验收：**增加覆盖所有已注册 target 的源码身份 CLI smoke。
`ValueVault.lean` 必须生成 `ValueVault` 制品，或以
`source input is not supported` 非零退出；任何输出都不能包含 Counter。

#### PF-P0-02 - Registry 与可执行命令支持不一致

**证据：**`Target.knownIds` 包含 `wasm-cloudflare-workers`，但
`buildLegacyFlag` 没有对应 build 分支并返回 `unknown target`。同时，
target-first 行为由另一张 match 表实现，因此 registry membership 无法保证
命令可用。

**必须修改：**把普通 `--list-targets` 的成员语义明确定义为“至少支持一个
CLI 命令的已注册 target”，而不是支持 source build，并在 CLI help 中写明。
Cloudflare 已实现 fixture `emit`，因此保留在列表中；但 target 解析必须与
逐命令支持解耦，其 source `build`/`check` 应先解析 profile，再返回明确的
unsupported-command/input diagnostic，而不是 `unknown target`。PF-P1-02
必须把它诚实描述为 `inputModes = fixture`、`commands = emit`、
TypeScript-source output stage 的链下 Research；其 JSON 输出是权威的能力
发现接口。真实 `contract_source -> TypeScript Worker` adapter 是后续晋级
条件，不是诚实展示 fixture-only registry 项的前提。不得把 TypeScript
输出分类为 Wasm。

**验收：**普通列表的 help 明确“至少支持一个命令”的成员规则；Cloudflare
fixture emit 成功；其 source `build`/`check` 返回稳定的
unsupported-command/input diagnostic；任何已列出的 id 都不能落入
`unknown target`。生成命令矩阵的一致性在 PF-P1-02 下验收。

#### PF-P0-03 - Solana 通用构建宣称了并未生成的最终制品

**证据：**`compileContractSourceSbpf` 生成 `.s`、manifest、IDL 和 client，
但写入 `artifactKind = solana-elf` 和 `sbpfBuild = pending`，且没有 ELF
artifact entry。`compileSolanaSpecElf` 已能构建通用 `ContractSpec` package
并生成验证过的 ELF，但只接入 fixture 导向的命令。

**必须修改：**让通用 `build --target solana-sbpf-asm` 通过
`compileSolanaSpecElf` 生成 ELF。保留 `--format s` 作为明确的无工具链
中间输出。如果 `sbpf` 不可用，最终构建必须给出可操作诊断并失败；静态
product CI 显式请求 `--format s`。源码路径必须尊重 `--format elf`；
当前它会忽略 format 并始终选择汇编。

**验收：**Counter 和 ValueVault 源码构建生成 ELF，并具有匹配的 source
module、artifact hash 和 `sbpfBuild = passed`；`--format s` 只生成汇编，
并报告汇编 artifact kind。

#### PF-P0-04 - Soroban build 使用了错误的 target profile

**证据：**`compileContractSourceEmitWat` 保留所请求的 target id，并选择
Soroban host bridge，但无条件调用 `Target.resolveSpec Target.wasmNear`。
sidecar 仍使用 `proof-forge-near.ts` 文件名和 NEAR 导向的 schema。

**必须修改：**从所请求 target 解析唯一 `TargetProfile`，并在 capability
resolution、preflight、materialization、bridge selection、metadata 和 client
generation 中一致使用它。新增 Soroban 专属 sidecar；在真实 auth、Stellar
contract spec 和 runtime gate 存在之前保持 Spike。

**验收：**仅 NEAR 支持的 capability 会在 Soroban 上被拒绝；Soroban 制品
不包含 NEAR target id 或 NEAR-native wrapper 路径。

#### PF-P0-05 - 当前文档和翻译门禁不诚实

**证据：**机械审查报告七项未关闭 finding；README 遗漏 Soroban，并称 Aleo
不在 `--list-targets`；target notes 与 registry 状态不一致；
`docs/target-lowering-interface.md` 仍称 Solana 和 NEAR plan 不存在。
审查开始时还有四份过期翻译。

**必须修改：**关闭机械 finding，修正 target inventory 和流水线阶段，把旧审查
标成历史快照，并保持英文/中文索引同步。增加 strict 形式的机械审查，只要仍有
finding 就非零退出。PF-P1-02 落地后，再把 target 状态表迁移为由该支持契约
生成/校验。

**验收：**`just doc-sync-audit-strict` 报告零 finding，
`scripts/i18n/check-sync.sh` 通过，并且本任务新增/修改的本地链接全部可解析。
生成 target 表的一致性在 PF-P1-02 下验收，不属于本 P0 任务。

#### PF-P0-06 - `near_gas` 实际是标错名称的累计 Wasmtime fuel

**证据：**`runtime/offline-host/src/main.rs` 启用 Wasmtime fuel，在完整调用
序列之前只设置一次初始余额，并在每次调用后报告
`initial_fuel - remaining_fuel`，中间没有重置。testkit 把这一累计值存入
`near_gas`，但它既不是单次调用 delta，也不是 NEAR VM gas。

**必须修改：**把当前 observation 重命名为 `wasmtimeFuelCumulative`；如果
仍有价值，再增加单次调用 fuel delta；从 offline-host 场景移除 `near_gas`
产品声明。未来 `nearGas` budget 必须来自 NEAR VM/sandbox，并说明包含哪些
成本。

**验收：**Counter budget 输出明确区分累计和单次 Wasmtime fuel；
offline-host 字段不再命名为 NEAR gas；只有 sandbox/VM harness 才能提供
真实 NEAR gas 字段。

#### PF-P0-07 - `check` 可在未执行后端验证时通过

**证据：**共享 preflight 只实现 L0/L1。`checkContractSource` 只为 NEAR
执行真实后端检查，而对 EVM、Solana 和次级 target 直接报告
`contractSource = passed`。因此 Cloudflare source 可以先通过 check，
再在 build 时报 unknown；四个静默替换 target 也会在未验证源码身份时通过。

**必须修改：**让 `check` 调用与 `build` 相同的 adapter L2 validation 和
input-mode 规则，但不生成制品。支持性判断只能有一份，不能存在乐观 check
表和另一份 build 表。

**验收：**每个负向 source-identity/build 用例都以相同类别和 target 专属
说明在 `check` 中失败。

#### PF-P0-08 - 未生成 Wasm 时 Wasm build 仍返回成功

**证据：**`writeWatPackage` 把 `wat2wasm` 失败或缺失转换为 `none`；
调用方仍返回 0 并写入 `artifactKind = wasm`，同时记录
`wat2wasm = skipped` 且没有 Wasm artifact。

**必须修改：**最终 Wasm build 必须在 `wat2wasm` 失败或不可用时失败。
增加显式 `--format wat` 中间模式，它可以只生成 WAT 并报告 WAT artifact kind。

**验收：**伪造失败的 `wat2wasm` 会使默认 build 非零退出且不写成功元数据；
`--format wat` 以诚实元数据成功。

### P1：统一编译器/target 契约

#### PF-P1-01 - Target-first CLI 只是 legacy flag 翻译层

**证据：**`ProofForge/Cli/TargetFirst.lean` 包含针对 target、input kind、
fixture、format 和 token mode 的大型 tuple match。`ProofForge/Cli.lean`
仍分派庞大的 `EmitMode` 清单。`TargetAdapter` 只有 `profile` 和
`resolve`，而 `ProofForge/Backend/Lowering.lean` 明确只是 design-only stage enum。

**必须修改：**引入 registry 驱动的 `TargetBackend` driver。每个 adapter
负责 validate、plan/lower、emit/build/package 和 artifact validation，同时
保留各自的 target-specific plan type。先迁移 EVM、Solana、NEAR，再迁移
fixture/sourcegen target。legacy alias 保留一个有文档说明的兼容发布周期，
随后删除 match facade。

**验收：**新增 target adapter 不需要编辑中央 target-id match；target-first
命令直接调用 adapter；兼容窗口结束后 legacy 删除检查通过。

#### PF-P1-02 - TargetProfile 无法表达真实支持范围

**证据：**`TargetProfile` 记录 family、单一 artifact kind、宽泛 capabilities、
tools 和可选 host bridge，但无法表达 maturity、source 与 fixture 输入、
command support、output stage、精确 lowerable fragment 或必需 validation。
因此部分 profile 宣称的能力远大于后端实际接受的能力。

**必须修改：**保留现有 `requiredTools`，增加机器可读的 `maturity`、
`inputModes`、`commands`、`outputStages`、`supportedFragment` 和
`validationLevel`，并把每项现有工具要求关联到需要它的阶段。通过
`--list-targets --json` 公开相同数据，并用它生成文档表和 CLI diagnostics。
保留 PF-P0-02 定义的普通列表语义；JSON 是权威支持矩阵。

**验收：**registry 无需 prose 例外即可区分主要 source build、fixture-only
spike、链下 sourcegen 和 CLI-only verification；生成的 target 状态表与
机器可读契约保持零差异，并且生成的命令矩阵覆盖每个已声明的
command/input/output 组合。

#### PF-P1-03 - 单一 ArtifactKind 混淆中间输出和最终输出

**证据：**registry 把 Solana 标为 ELF，而通用 build 生成汇编；把 Psy 标为
circuit JSON，而常见 CLI 路径生成 `.psy`；把 Cloudflare 标为 Wasm，而
已实现 spike 生成 TypeScript。

**必须修改：**引入 `ArtifactBundle`，包含 source identity、多种 typed
outputs、`primaryOutput`、可选 `finalOutput`、toolchain provenance 和
`notRun | passed | failed | unavailable` validation state。元数据不得把
未执行的 validation 标为 `passed`。

**验收：**schema validation 覆盖所有 target family 的仅中间产物、最终
可部署产物、缺少工具和工具链失败情况。

#### PF-P1-04 - Preflight 在后端验证前报告 ready

**证据：**`Target.Preflight` 只根据 L0 portability 和 L1 capability
resolution 设置 `readyToMaterialize`，并明确把 L2 protocol validation
留给后端。因此宽泛的 registry capability 可能对 lowerer 随后拒绝的形状
报告 ready。

**必须修改：**每个 adapter 公开真实 supported-fragment validator；
`check --target` 运行 L0、L1 和 L2，只有三者全部通过才报告 ready。
backend emit 必须消费已检查 plan，不能重复另一套分歧测试。

**验收：**代表性的不支持形状会在 `check` 阶段以与 `build` 相同的
diagnostic category 失败，并且不会写出任何制品。

#### PF-P1-05 - Authoring DSL 需要稳定的诊断边界

**证据：**`contract_source` macro 直接构建 `ContractSpec`/IR，只支持零到
四个 entrypoint 参数，并对不支持条目回退到 macro-level 错误。基础 source
模块还导入 Solana Surface，尽管文档称 chain extension 需要 opt-in。

**必须修改：**继续以 `contract_source` 作为产品语言，但增加携带源码位置的
authoring node 或 builder metadata，生成 variadic-parameter lowering，隔离
chain extension，并对 DSL surface 进行版本化。不要创建任意 Lean-to-IR
编译器。

**验收：**diagnostic 能定位源码条目和 operation；target ABI 允许时支持五个
以上标量参数；portable-default source 不加载链扩展模块。

#### PF-P1-06 - 后端阶段纪律与文档已经分离

**证据：**EVM、Solana、NEAR、Psy、Leo 和 Worker sourcegen 已具有有价值的
typed plan/AST 边界，但共享 lowering contract 仍是 design-only。CosmWasm
是 Counter 专用，Move emitter 是字符串 renderer，Leo printer 会打印
`/* nand */`、`/* unsupported unary */` 等注释，而不是拒绝不支持的运算。
lowering-interface 文档仍把已落地的 Solana 和 NEAR plan 描述为未来工作。

**必须修改：**把 `IR -> target Plan -> typed AST -> printer/package` 设为
晋级契约。不支持的 AST node 必须返回结构化错误。更新 lowering-interface
文档，使其描述当前 plan module 和剩余缺口，而不是 2026-07-06 Phase 0
快照。

**验收：**promotion test 向每个 renderer 注入一个不支持节点并断言非零结果；
plan golden test 和 emitted artifact 派生自同一 plan。

### P2：主要三链产品闭环

#### PF-P2-01 - Product 构建广度大于运行时一致性证据

**证据：**`Examples/Product` 有 20 个源码，而 `Tests/Product/Matrix.lean`
只导入 18 个，遗漏 `ERC4626Vault` 和 `ExternalVault`；它们的专项 recipe
不属于 `just product`。testkit 有十个 scenario manifest，但只有 Counter
和 ValueVault 在三个主要 target 上使用 Product 源码；RoleGatedToken 和
StakingVault 只使用 EVM。Product matrix 对导入集合证明了较广的静态
lowering，但没有证明每个 capability family 的运行时等价。安装必需工具时，
Counter 和 ValueVault 确实具有真实的三 target CI 执行；但本地缺少工具会被
记为 skip，即使实际执行 target 为零或一个，trace equivalence 仍可能报告成功。

**必须修改：**引入受检查的 Product catalog，为每个 Product 文件声明 authoring
kind（`contract_source`、`TokenSpec` 或 facade）、claimed target、预期输出
阶段和必需 gate；发现未登记文件即失败。把 harness 的 fixture-name dispatch
替换成 artifact-driven execution，校验 scenario capability 与 artifact
metadata，并增加单步 caller、native value、context、accounts 和 peer 输入。
对 `contract_source` 运行 CLI source build，对 `TokenSpec` 运行 plan/standard
conformance，对 facade 运行 body/runtime test。按 capability family 增加代表性
三链场景：scalar state、auth/policy、map/array、token/accounting、
events/errors 和 remote call。把门禁拆成快速静态 Product catalog 和必需
runtime 子集。CI 增加严格 `--deny-skip`/required-target policy；自适应本地
模式只能报告 `partial`，不能报告 parity success。

**验收：**主要三链宣称为 portable 的每个 capability 至少有一个共享语义场景，
claimed target 不能被静默跳过。

#### PF-P2-02 - 主要后端仍有生态特定缺口

**状态（2026-07）：EVM 切片已关闭**（PF-P2-02 @7c4def9c 及后续）。
`docs/sdk-ecosystem-gaps-2026-07.md` 将 ERC-721 `onERC721Received`、ERC-1155
receiver + size-2 batch、以及 custom-error **4-byte selector** 表面标为
Covered（有限处另注）。仍开放的是 P1 深度（任意长度 ERC-1155 batch /
`onERC1155BatchReceived`、custom-error *参数* ABI），以及下方 Solana/NEAR
项——不是重新打开 EVM receiver/selector MVP。

**历史证据（关闭前）：** gap 文档与 target notes 记录了缺失的 EVM
receiver/batch/error 表面；PF-P0-03 显示通用 Solana 源码构建无 ELF；NEAR
deploy manifest 报告 local offline-host、无 sandbox。

**必须修改（剩余）：**完成已记录缺口，但不要把所有链原生特性都当成 portable：

- EVM（MVP 已完成）：custom-error **selector** 表面
  （`errors-ir-smoke` `test_revertCustomError_selector`）、ERC721
  `onERC721Received` Foundry 接受/拒绝、ERC1155 `onERC1155Received` +
  size-2 `safeBatchTransferFrom2` Foundry。开放：参数 ABI + 全长 batch。
- Solana：通用 source-to-ELF、部署级 runtime coverage 和剩余 ABI/长度限制
  （source-ELF 路径在 PF-P0-03 / `just solana-source-elf` 另有关闭项）；
- NEAR：把 async Promise/callback 从专项流程推广到通用路径，完成 storage
  accounting，并保持 sandbox peer 门禁（`just near-sandbox-peer`）。

不支持的链原生行为必须是显式 target extension 或 diagnostic，不能发明
portable semantic。

**验收：**EVM 为 custom-error ABI/client、ERC721 receiver、ERC1155
batch/callback 增加正向及拒绝 Foundry/Anvil 用例——**已满足**
（`just evm-foundry` / `foundry-smoke.sh` 的 `testERC721*`、`testERC1155*`，
以及 `errors-ir-smoke.sh` 的 `test_revertCustomError_selector`）；源码构建的
Solana ELF 通过严格 testkit 与边界 ABI fixture；NEAR 在 sandbox 中执行通用
caller/callee Promise callback 与 storage-accounting 场景。每项 capability
在对应门禁通过前都不能加入 portable profile。

#### PF-P2-03 - Crosscall 测试没有证明真实 peer 等价性

**证据：**可执行 IR 和 Quint 有意使用确定性的求和 stub。Materializer 会生成
CALL、CPI、Promise、Soroban invoke 或 CosmWasm stub，但当前 portable smoke
没有对真实 peer contract 建立丰富返回值等价性。

**必须修改：**增加带 peer oracle 的多合约 runtime scenario 和 portable
scalar return decoding。在跨 host ABI 被定义和测试前，aggregate/dynamic
return 和 CosmWasm submessage 不属于产品承诺。

**验收：**每个主要 target 执行同一个 caller/callee 场景，并在 state、return
和 failure observation 上匹配；仅 stub 的测试继续明确标为 model test。

### P3：target 晋级、形式化范围与平台加固

#### PF-P3-01 - 形式化编译器范围小于 codegen 范围

**证据：**EVM、Solana 和 Wasm 的 target-semantics record 当前都把
`fragmentAccepts` 和 `lowerableAccepts` 设置为 `isCounterModule`。
其他 ValueVault 和 storage trace obligation 很有价值，但它们没有把通用
lowering-total theorem 变成针对所有受支持合约的证明。

主要 target-semantics record 还保留默认 `irStateRel = True` 和
`initialMachineState = none`。更强的 Solana 和 Wasm Counter theorem 模拟
手写的抽象 core step；它们尚未证明 `lowerModule m` 生成的 machine 实现了
这些 step。

**必须修改：**为每个后端分别定义真实 lowerable predicate 和 proved predicate。
在简单增加更多 IR constructor 之前，先把降低后的 plan/AST/machine semantics
连接到现有 simulation relation，并提供非平凡 initial state。随后按产品切片
扩大 proved fragment：scalar/auth、map/array、error/event，以及具有 peer
semantics 后的 remote call。用 typed/elaborated invariant registration
替换字符串对形式的 `lean_invariant` metadata，在 gate 中自动发现其 scenario，
证明每个受支持 entrypoint 都保持 invariant，然后才能通过 backend refinement
提升。当前 invariant 证据继续明确限定为 scenario-bound。solc、sbpf、
wat2wasm 和链运行时继续作为明确的 trusted/differential boundary。

通用 Track 1.4 theorem schema 当前把目标 lowering 或 subset fact 当作参数，
后端 instance 也只 discharge canonical Counter。在完成上述结构桥接前，应把
它们视为 scaffolding/Counter witness，而不是通用 compiler correctness。

**验收：**对结构化 predicate 证明
`forall m, proved m -> lowerable m` 和
`forall m, lowerable m -> lowering m succeeds`，并提供至少一个满足
`lowerable m && !proved m` 的已检查 witness。结果不能只针对 canonical
Counter constant。

#### PF-P3-02 - 次级 target 缺少统一晋级定义

按以下顺序一次晋级一个 target：Soroban、CosmWasm、Aptos、Sui、
Cloudflare Workers、Psy、Aleo。每次晋级必须同时满足：

1. 声明的输入确实被加载；
2. 存在精确的 supported-fragment validator；
3. lowering 遵循 Plan -> typed AST -> printer/package；
4. 最终输出由 target toolchain 检查；
5. 至少一个 runtime semantic scenario 通过；以及
6. registry、CLI、README、target note 和中文文档一致。

在六项全部通过之前，target 保持当前 Spike/MVP/Research 范围，并必须拒绝
实际未实现的每一种输入或输出阶段。已有源码路径（例如 Soroban host-adapter
路径）本身不构成晋级。

#### PF-P3-03 - 托管编译和制品可复现性尚未就绪

**证据：**`ContractLoader` 会 elaboration 并执行本地 Lean constant，同时
启用 initializer。这对可信本地源码是合理的，但不是未来云编译器的隔离边界。
部分外部工具链版本和依赖 revision 也没有固定在制品中。

**必须修改：**在提供托管编译前，在带 CPU/memory/time 限制的隔离 worker 中
执行源码加载。固定 target toolchain，记录版本和哈希，增加确定性重建检查，
并保留可审计的 artifact provenance chain。

**验收：**恶意源码测试无法突破 worker 限制；clean rebuild 要么复现 artifact
hash，要么解释每一个已声明的非确定性输入。

## 交付波次与依赖

| 波次 | 任务 | 退出条件 |
|---|---|---|
| 0 - 停止错误成功 | PF-P0-01 到 PF-P0-08 | 不再发生错误输入/check/build 成功；registry/CLI/artifact/docs/budget 标签一致 |
| 1 - 统一 target driver | PF-P1-01 到 PF-P1-04 | registry 驱动的命令矩阵和诚实 ArtifactBundle 驱动主要三链 |
| 2 - Author 与 backend 边界 | PF-P1-05、PF-P1-06 | 稳定 DSL diagnostic 和 plan/AST 晋级契约 |
| 3 - 可部署三链 | PF-P2-01 到 PF-P2-03 | EVM、Solana、NEAR 的共享 runtime 场景和最终制品 |
| 4 - 有意晋级 | PF-P3-02 | 次级 target 逐一通过六项晋级门禁 |
| 5 - Proof 与平台 | PF-P3-01、PF-P3-03 | 结构化 proof fragment、可复现制品和托管隔离 |

Wave 1 依赖 Wave 0，因为通用 driver 不能保留静默替换。Wave 3 依赖 Wave 1
提供的 artifact/support 契约。次级 target 晋级不阻塞主要产品闭环。

## 全局完成定义

每个修复 PR 都要运行其边界对应的窄测试，以及：

```sh
just product
just check
just doc-sync-audit-strict  # PF-P0-05 落地后可用
scripts/i18n/check-sync.sh
git diff --check
```

需要 Surfpool、Sui、Leo、Dargo、Wrangler 或链 CLI 的 live gate，在未安装
工具时仍保持 conditional；但 target 不能晋级到其必需门禁被跳过的成熟等级。

在 source identity、最终制品、runtime scenario、failure diagnostic 和文档
没有于同一 revision 全部通过前，不得提高 target maturity 标签。
