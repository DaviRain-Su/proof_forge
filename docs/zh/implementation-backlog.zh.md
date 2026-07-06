> **注意：** 公共验证命令的更改必须同时更新
> 同一更改中的 [validation-gates.md](validation-gates.md)。

# 实现待办事项

此待办事项将多链设计转化为可评审的工程切片。
它被有意限定在本地编译器、制品和冒烟测试工作范围内。
云平台应等到至少两个实质上不同的目标在本地正常工作后再开始。

相关文档：

- [设计决策](decisions.md)
- [可移植合约 IR](portable-ir.md)
- [能力注册表](capability-registry.md)
- [共享场景：Counter](shared-scenario.md)
- [RFC 0002](rfcs/0002-target-implementation-design.md)
- [目标说明](targets/README.md)
- [验证门禁](validation-gates.md)

## 主三链完成规约（D-045）

在为更多链增加实现范围之前，ProofForge 必须先按以下顺序完成三个优先链：

1. `solana-sbpf-asm` —— Solana 直接 sBPF 汇编后端。
2. `evm` —— Ethereum/EVM 后端和部署通道。
3. `wasm-near` —— 基于 Wasm 家族后端的 NEAR。

这不是普通的研究路线图偏好，而是产品前置条件，作为 Gate P0 记录在
[gate-status.md](gate-status.md) 中。“完成”意味着三条链分别具备 target-first
构建/发射、本地执行或部署冒烟、制品/部署元数据、能力诊断、资源预算、CI 覆盖
以及同步维护的文档。新链实现工作现在不再被 D-045 阻塞。CLI M3 target-first
迁移已经为 executable callers 落地；Tier-1 M3/M4 的推进仍需要显式排期，
不应把旧 research notes 当作隐式实现范围。

## 评审处置（2026-07-04）

2026 年 7 月的架构/产品评审提出了六项风险。当前 backlog 的处置如下：

| 评审项 | 当前处置 | Backlog 动作 |
|---|---|---|
| R1：RFC 0009 和 D-039 滞后于已经落地的 CLI M1 工作 | 当前 `main` 已关闭：RFC 0009 已标记为 Accepted，并说明 M1/M3 已落地；D-039 也已经改为追认 compatibility-layer 实现，而不是宣称代码前冻结 | 随着 M4 legacy-alias removal 被排期，持续同步 RFC 0009 和 CLI 迁移文档 |
| R2：同时存在过多半成品工作流 | 接受为排期风险 | Gate P0 已关闭，CLI M3 已由 `just cli-target-first` 守住；M4 alias removal 继续放在兼容窗口之后，Tier-1 M3/M4 不应隐式打开 |
| R3：尚无端到端证明把用户不变量连接到生成制品 | 部分接受：已有源级证明、FV-2 aggregate/storage/map/control-flow/event-log IR traces、第一批基于 IR 语义的 FV-8 ValueVault accounting/net-value invariant anchors、NEAR trace obligations 加 Counter 和 ValueVault EmitWat artifact-surface/offline-host execution-surface obligations、NEAR ValueVault backend-invariant state bridge、NEAR host import-signature、entrypoint input-frame、context-frame、storage-read-key-frame、storage-write-key-value-frame、host-call frame、memory-layout、return-payload-byte、per-step storage-snapshot、storage-byte 和 log-payload-byte obligations，以及 EVM FV-4 可执行 Yul trace anchors；但完整 IR-to-artifact 语义保持还没有完成。EVM map/storage/aggregate/control-flow/event 切片现在已经把覆盖到的 FV-2 IR traces 接到可执行 Yul obligations。 | 将 NEAR FV-4 从新的 backend-invariant/import/input-frame/context-frame/storage-read-key-frame/storage-write-key-value-frame/frame/memory-layout/return-payload-byte/storage-byte/log-payload-byte bridge 继续扩展到更丰富的 Wasm/offline-host 语义边界，再证明超出当前 state/IO、host-ABI、entrypoint input-frame、context-frame、storage-read-key-frame、storage-write-key-value-frame、host-call-frame、memory-layout、return-payload-byte、storage-snapshot、storage-byte 和 log-payload-byte anchors 的语义保持 |
| R4：capability 粒度太粗 | 当前阶段不 churn capability id；storage 已经拆成 scalar/map/array/PDA，Solana account 语义也已与 storage pattern 分离建模 | 把跨目标运行时差异交给预算和诊断义务：每个 target 必须显式拒绝不支持形状，并为支持形状锁定资源预算 |
| R5：docs-first target notes 形成隐藏沉没成本 | 排期层面已关闭：D-045 和 target roadmap 在 Gate P0 关闭前把产品硬化限制在 `solana-sbpf-asm`、`evm`、`wasm-near` | 保留 research notes 作为库存；显式排期 Tier-1 M3/M4，而不是让旧 research notes 自动变成实现范围 |
| R6：Lean/工具链入门摩擦 | 部分关闭：`docs/onboarding.md` 已存在并列出核心工具链和各目标工具；但 editor workspace config、templates 和 scaffolding 仍是开放 DX 工作 | 补 VS Code/Cursor workspace recommendations 和最小项目模板 |

因此，这次评审之后的直接工程顺序是：

1. ~~关闭 NEAR/Wasm P0-3：补齐 target-first 本地执行和部署元数据证据。~~ ✅ 已由 Gate P0 签署关闭。
2. ~~完成 CLI M3：把 executable callers 从 legacy flags 迁移到
   target-first 调用。~~ ✅ 已落地；`just cli-target-first` 会扫描可执行调用面，
   并运行 target-first 映射回归测试。M4 legacy flag removal 仍按 RFC 0009
   的兼容窗口延后。
3. 继续形式化验证：FV-2 已具备 aggregate/storage executable traces、
   state-threaded map insert/set lifecycle traces、`ifElse`/`boundedFor`
   control-flow traces、observable event-log traces，以及 determinism 和
   bounded-loop measure anchors；覆盖到的 EVM
   map/storage/aggregate/control-flow/event obligations 现在会把这些 IR traces
   与可执行 emitted Yul 对比。NEAR 现在有 Counter 和 ValueVault EmitWat AST
   artifact-surface obligations，并新增 offline-host execution-surface obligations，
   用来固定 Borsh 输入字节、确定性的 host return/log observations、
   storage-key 计数和累计 log 计数。artifact surface 现在还会在 Wasm AST
   边界检查 NEAR host import ABI：对用到的 `input`、`read_register`、
   `storage_read`、`storage_write`、`value_return`、`log_utf8` 和
   `block_index` 固定 module name 以及参数/返回签名。NEAR artifact surface
   还会固定 `u64` storage read/write helpers、`value_return` 和 `log_utf8`
   的 host-call frames，包括传给 host 的常量和内存缓冲区。offline-host
   surface 现在还会记录每一步的 storage snapshot 以及对应的 little-endian/Borsh
   storage bytes，所以 Counter 和 ValueVault 必须在每个被检查的 entrypoint
   之后同时匹配语义层 storage 内容和 host storage 字节串，而不只是匹配最终
   storage 或 key count。offline-host surface 现在还会固定标量返回值的
   byte-level `value_return` payload hex bytes，以及 ValueVault 事件的 byte-level
   `log_utf8` payload hex fragments，把 host payload bytes 和便于阅读的 return/log
   line fragments 分开检查。FV-8 现在也有第一个 ValueVault IR invariant anchor，
   覆盖共享 11 步场景的 return trace、accounting、final storage 和 net-value
   检查。最新的 NEAR FV-4 切片新增了可由 `native_decide` 检查的
   backend-invariant state/import/input-frame/context-frame/storage-read-key-frame/storage-write-key-value-frame/frame/memory-layout/return-payload-byte/storage-byte/log-payload-byte bridge：ValueVault offline-host
   输入序列从 FV-8 场景输入派生，返回片段会对齐 FV-8 expected returns，最终
   offline-host state 会对齐 FV-8 scenario state 以及 accounting/final-storage
   predicates，标量 `value_return` payload bytes 会从 FV-8 expected returns 派生，
   ValueVault 事件日志 JSON 片段会从 invariant final state 派生，
   每个 `log_utf8` payload hex fragment 都会从同一个 invariant event stream 派生，
   每一步 offline-host storage snapshot 和 storage-byte snapshot 都被固定，Wasm
   memory declaration 会被固定，并且固定 host buffers（`KEY_BUF`、`RET_BUF`、
   `EVENT_BUF`、`EVT_KEY_PTR`、`INPUT_BUF`）会被检查为落在第一页且互不重叠。
   host import signatures、entrypoint `input`/`read_register` frames、从
   `INPUT_BUF` 读取标量 u64 参数的 offset loads、传给 `__pf_read_u64` 的
   storage-read key pointer/length frames、传给 `__pf_write_u64` 的
   storage-write key/value frames、ValueVault `block_index` context reads 写入
   `checkpoint`，以及 helper host-call frames 都会在 WAT 打印前被固定。
   下一步把这条 bridge 从 state/IO、host-ABI、entrypoint input-frame、
   context-frame、storage-read-key-frame、storage-write-key-value-frame、
   host-call-frame、memory-layout、return-payload-byte、storage-snapshot、
   storage-byte、log-payload-byte equality 扩展到更丰富的 Wasm memory/host
   语义边界。
4. 处理剩余 DX 项：`.vscode` recommendations、项目模板和脚手架；前提是它们不与 P0 关闭抢资源。

## 工作流 1：目标注册表

目标：在添加更多后端之前使目标选择显式化。

任务：

- 添加目标 id：`evm`, `wasm-near`, `wasm-cosmwasm`,
  `solana-sbpf-asm`, `solana-sbpf-linker` (已取代), `solana-zig-fork`,
  `move-sui`, `move-aptos`, `psy-dpn`。
- 定义目标家族、制品种类、所需工具和能力集
  （参见 [capability-registry.md](capability-registry.md)）。
- 为 CLI 和脚本添加目标查找函数。
- 已完成：为部署元数据添加 EVM 兼容链的 profile 层，
  从 `evm` 编译器目标下的 `robinhood-chain-testnet` 开始。
- 为未知目标和不支持的能力添加诊断信息。

验收标准：

- `evm` 可以表示为目标 profile，而无需更改当前的 EVM 行为。
- EVM 兼容链的 profile 可以重用 `evm` 编译器目标，而不会被目标 id 查找返回。
- 目标 profile 可以声明外部工具需求。
- 不支持的能力错误应包括目标 id、能力 id 以及可用的源位置。

## 工作流 1.5：可移植 IR 和共享场景

目标：在非 EVM spike 之前定义合约 IR 和 Counter 场景。

任务：

- 根据 [portable-ir.md](portable-ir.md) 实现 IR 节点类型。
- 根据 [shared-scenario.md](shared-scenario.md) 表达 Counter。
- 将 Counter IR 降级到 EVM（直接或通过 EmitYul 适配器）。
- 将能力检查器连接到 [capability-registry.md](capability-registry.md)。

验收标准：

- Counter 模块可以在 IR 中表示，且 IR 层中不包含 EVM 操作码。
- 从 IR 构建的 EVM 版本与现有的 Counter 行为一致。
- 至少有一个不支持的能力被拒绝，并带有清晰的诊断信息。
- 发射时，IR 版本出现在制品元数据中。

## 工作流 1.6：Quint 模型生成与 MBT 回放

目标：将 Quint 作为上游设计验证层，从 portable IR 生成状态机模型，
对其进行模型检查，并生成可在 ProofForge IR 语义上回放的 MBT 追踪。

任务：

- 已完成：添加 `ProofForge.Backend.Quint` 库，包括 AST（`Model.lean`）、
  美化打印（`Emit.lean`）、IR 到 Quint 的降级（`Lower.lean`）、
  场景 TOML 解析（`Scenario.lean`）、不变式推导（`Invariants.lean`）、
  ITF 追踪解析（`ITF.lean`）以及 IR 语义回放（`Replay.lean`）。
- 已完成：将 `proof-forge emit --target quint --fixture counter` 接入 CLI
  和 `Fixture.lean`。
- 已完成：添加端到端测试 `Tests/Quint/CounterReplay.lean`，对 Counter 进行降级、
  运行 `quint run --mbt --out-itf`、解析 ITF 追踪，并通过
  `ProofForge.IR.Semantics` 回放每个转换。
- 已完成：在 `docs/capability-registry.md` 中注册工具链能力
  `model.quint`、`verify.model_check`、`verify.simulation` 和
  `test.mbt_trace`。
- 已完成：扩展 `ProofForge.Contract.Spec.Json.render`，添加 `verification.quint`
  元数据块（模型路径、不变式、验证命令、检查器）。
- 已完成：添加 `scripts/quint/model-check-gate.sh` 和
  `scripts/quint/mbt-replay-gate.sh`，当 `quint` 或 Java 17+ 不可用时优雅跳过；
  并通过 `just quint-model-gate` 和 `just quint-mbt-gate` 暴露。
- 添加 ValueVault IR 固定装置，并扩展生成器/回放门以覆盖它。
- 从场景 TOML 的 `[invariants]` 下解析手动不变式，并将其作为 Quint `val` 定义发射。
- 随着相应 IR 语义覆盖范围的扩大，将支持的 IR 子集扩展到 map、数组、结构体和有界循环。
- 当构建环境中可用 Java 17+ 时，考虑将 `quint verify` 加入默认 CI 路径。

验收标准：

- `lake env proof-forge emit --target quint --fixture counter` 写出有效的
  `build/quint/Counter.qnt` 模型。
- `quint run build/quint/Counter.qnt` 未找到不变式违反。
- `just quint-mbt-gate` 生成 ITF 追踪并通过 IR 语义回放，测试通过。
- `just quint-model-gate` 执行 `quint verify`，并在缺少 Java 17+ 时优雅跳过。

## 工作流 2：制品元数据

有关当前和计划中的验证命令，请参阅 [validation-gates.md](validation-gates.md)。

目标：每次构建都应产生机器可读的结果，以便后续提供给 CI 和云平台。

任务：- 已完成 EVM 部分：为 EVM 字节码构建添加 `proof-forge-artifact.json` schema。
- 已完成 EVM 部分：为 `--evm-bytecode` 和可移植 IR EVM 字节码 fixture 构建发射元数据。
- 已完成 EVM 部分：包含源模块、target id、制品路径、SHA-256、字节大小、solc 路径/版本、选择器/签名元数据以及验证状态。
- 已完成 EVM 部分：在 `abi.methods[].signature` 中为 `proof-forge-artifact.json` 和 `proof-forge-deploy.json` 保留 SDK `.evm-methods` Solidity 签名；验证器检查选择器形状、重复的方法选择器/函数/签名、生成的 Yul 函数名称以及签名/参数计数的一致性，且 SDK 示例门控要求提供签名。
- 已完成 EVM 部分：为每个 EVM 字节码构建发射并验证 ProofForge 部署清单，记录运行时字节码输入、ABI 选择器、可部署的 initcode 以及当前的 `not-generated` 交易广播状态。
- 已完成 EVM 部分：为每个 EVM 字节码构建生成一个制品链接的 `.init.bin` 创建字节码文件，并将其记录在 `proof-forge-artifact.json` 和 `proof-forge-deploy.json` 中，同时验证 initcode 头部是否复制并返回了引用的运行时字节码。
- 已完成 EVM 部分：添加 `--evm-chain-profile <id>`，使字节码构建可以在 `proof-forge-deploy.json` 中记录已知的 EVM 链 profile（例如 `robinhood-chain-testnet` 或 `anvil-local`）；验证器在不广播的情况下检查 profile id、链 id、RPC URL、浏览器、验证器以及部署区块的一致性。
- 已完成 EVM 部分：添加 `--evm-constructor-args-hex <hex>`，使字节码构建可以将显式的 ABI 编码构造函数参数追加到生成的 `.init.bin` 中，在 `proof-forge-deploy.json` 中记录标准化的十六进制/字节大小/SHA-256 构造函数元数据，并验证 initcode 尾部是否与清单匹配。
- 已完成 EVM 部分：添加 `--evm-constructor-param <name:type>`，使字节码构建可以在制品元数据和部署清单中记录静态字构造函数 ABI schema，验证支持的 schema 类型，并验证显式 ABI 编码的构造函数参数 blob 是否具有预期的 32 字节字长。
- 已完成 EVM 部分：添加 `--evm-constructor-arg <name=value>`，使字节码构建可以为 `uint256`、`uint64`、`uint32`、`bool`、`bytes32` 和 `address` 进行类型化构造函数值 ABI 编码，记录构造函数参数是来自类型化值还是原始十六进制，拒绝缺失/重复/超出范围的值，并根据元数据和部署清单验证生成的 initcode 尾部。
- 已完成 EVM 部分：在 `abi.entrypoints` 中记录结构化的可移植 IR 面向选择器的入口 ABI 元数据，包括 Solidity 风格的选择器签名、IR 类型名称、ABI 参数/返回类型、扁平化的 calldata 字类型/计数以及扁平化的返回字类型/计数；验证器检查与 `cast sig` 的选择器/签名一致性，且 `EvmAbiAggregateProbe` 通过 `--expect-entrypoint-abi` 锁定聚合字布局。
- 已完成 EVM 部分：在 `abi.events` 中记录可移植 IR 事件 ABI 元数据，包括 Solidity 风格的事件签名、`topic0`、索引/数据字段、扁平化的 ABI 字类型以及 topic/数据编码；EventProbe 使用 `--expect-event` 和 `cast keccak` 验证每个发射的事件。
- 已完成 EVM 部分：扩展 `scripts/evm/diagnostic-smoke.sh` 以锁定构造函数 CLI 诊断，针对不支持的动态构造函数 ABI 类型、缺失或重复的类型化值、混合的类型化/原始构造函数参数源、溢出以及格式错误的静态字值（如短地址）。
- 已完成 EVM 部分：添加一个 Anvil 部署冒烟测试，使用 `cast send --create` 发送生成的 Counter `.init.bin`，记录构造函数 ABI schema 和类型化构造函数参数以及一个 `proof-forge-deploy-run.json` 制品，记录 `eth_getTransactionByHash` 创建交易 JSON，验证 `anvil-local` 链 profile、收据/部署地址/运行时代码匹配以及交易输入 initcode，并通过 JSON-RPC 演练 Counter 生命周期。
- 从第一天起保持 schema 的版本化。

验收标准：- EVM 字节码构建会将运行时字节码、可部署的 initcode、元数据和部署清单并排写入。
- 元数据和部署清单可以由 CI 脚本独立解析。
- 可移植 IR 字节码元数据和部署清单可以描述面向 ABI 的入口，包括选择器签名、扁平化的 calldata 字布局以及扁平化的返回数据字布局。
- 可移植 IR 字节码元数据和部署清单可以描述面向 ABI 的事件，包括索引 topic 编码和非索引数据字编码。
- 部署清单可以携带来自目标注册表的可选 EVM 链 profile 元数据，同时保持交易广播制品显式为 `not-generated`。
- 本地 Anvil 部署可以消耗生成的部署清单和 initcode，生成经过验证的 deploy-run 制品，并证明部署的运行时代码与生成的字节码匹配，即使 initcode 包含带有记录的静态构造函数 ABI 模式的类型化或原始 ABI 编码的构造函数参数尾部；deploy-run 制品还会链接观察到的创建交易 JSON，并验证其输入是否等于生成的 initcode，以及部署 profile 的链 id 是否与实际本地链匹配。
- EVM 元数据可以将缺失的可选版本数据表示为 `null`，而不是格式错误的元数据。

## 工作流 3：EVM 基线加固

有关当前和计划中的验证命令，请参阅 [validation-gates.md](validation-gates.md)。

目标：在引入目标模型时保持 EVM 稳定。

任务：- 保持 `proof-forge --evm-bytecode` 正常工作。
- EVM 语义计划迁移 TODO：
  - 已完成：使 `ModulePlan` 变为目标驱动，以便在 Yul 生成之前从 `Target.resolveModule/resolveSpec Target.evm` 派生 helper 规划。
  - 将 `ProofForge.Backend.Evm.IR` 拆分为 `Validate`、`Lower`、`ToYul` 和 `Metadata` 模块，同时保留 `IR.lean` 作为兼容性外观，直到调用方完成迁移。
  - 已完成：将标量和映射存储槽的 Yul 构建移动到 `StorageSlotPlan -> ToYul`，从存储路径使用的映射值/存在槽开始。
  - 已完成：将 `StorageSlotPlan -> ToYul` 扩展到数组槽和结构体数组字段槽。`IR.lean` 现在通过 plan-to-Yul 边界路由存储数组和结构体数组字段槽降级，同时为现有调用方保留兼容性外观函数。
  - 已开始：`Lower.buildEntrypointPlan` 现在会用结构化 `ExprPlan`/`StmtPlan` 节点填充 `EntrypointPlan.body`，表示入口 IR 主体，同时 `IR.lean` 仍作为兼容性 Yul 组装外观保留。
  - 已开始：selector-dispatch case 组装现在会消费 `ToYul` 里的 `EntrypointPlan` surface helper，unit/static ABI-word dispatcher return-data encoding 以及 dynamic `bytes`/`string` dispatcher return-data encoding 也会通过同一边界消费 `ReturnPlan`。dispatch-block setup 现在会消费 `DispatchPlan`：entrypoint parameter plans 会在 selector switch 前为 dynamic ABI 参数初始化 free-memory pointer，`DispatchDefaultPlan` 会在 `ToYul` 中降低普通 revert 与 UUPS proxy fallback case。ABI validation/decode 语句和 dispatcher function-call 参数现在会通过 `ToYul` 消费 `AbiParamPlan`，并由 `AbiParamPlan.headWordIndex` 承载 calldata head layout。planned dispatcher call expression 和 internal entrypoint function naming 现在也已经位于 `ToYul`。`AbiParamPlan.localNames` 现在会承载 planned internal Yul parameter names，`ToYul` 会从 `EntrypointPlan` 发射 internal entrypoint `funcDef` shell。`ReturnPlan.localNames` 现在会承载 planned return variable names，`ToYul.returnTypedNames` 会从 `ReturnPlan` 发射 function return typed names。body statements 仍来自 `IR.lean` 兼容外观，直到更完整的 lowering 移动到 `EntrypointPlan -> Yul` 后面。完整计划在正常 lowering 中会走这条路径；不完整的 best-effort diagnostic plans 会回退到兼容 lowering，避免用户可见 validation errors 被 plan-shape errors 遮蔽。
  - 已开始：标量局部绑定初始化现在会在受支持的标量子集上消费语义计划路径：`IR Expr -> Lower.buildExprPlan -> ToYul.exprPlanExpr -> Yul.Expr`。Counter、expression 和 context 冒烟测试证明生成的字节码仍可运行；尚不支持的聚合/crosscall plan 节点继续留在兼容性外观路径上，直到对应迁移切片补齐验证覆盖。
  - 已开始：标量 `let` 和 `let mut` 的 statement 组装现在总是先消费 `Lower.buildExprPlan`，再调用 `ToYul.scalarBindingStmtPlanStatements`，从 `StmtPlan.letBind`/`StmtPlan.letMutBind` 生成 Yul `varDecl`。已无调用的标量 binding `varDecl` 兼容 fallback 已删除。
  - 已开始：标量 `assert` 和 `assertEq` 的 statement 组装现在总是先消费 `Lower.buildExprPlan`，再调用 `ToYul.scalarAssertStmtPlanStatements`。EVM 运行时错误 payload 的选择仍留在 `IR.lean` 兼容外观中，并以 revert-body callback 的形式传给 `ToYul`。已无调用的 `lowerAssertStmt` 兼容 helper 已删除。
  - 已开始：标量 `return` 的 statement 组装现在总是先消费 `Lower.buildExprPlan`，再调用 `ToYul.scalarReturnExprPlanStatements`，覆盖分支内返回需要追加 Yul `leave` 的情况。本地 dynamic `bytes`/`string`/array 返回总是走 `ToYul.dynamicReturnStmtPlanStatements`，聚合返回继续走 `lowerReturnAssignments`，非本地 dynamic return 会显式失败。本地、literal，以及 storage-backed fixed-array/struct 聚合返回现在会走 `Lower.returnValueWordPlan? -> ReturnValueWordPlan -> ToYul` 来组装返回 ABI word assignment。旧的 `lowerReturnWords` dynamic return word fallback 已经删除。更广的聚合/crosscall 返回路径继续通过各自的计划级切片迁移。旧的 IR-local fixed-array/struct return word fallback helper 已经删除；聚合返回的成功路径现在必须经过 `ReturnValueWordPlan` 或聚合 crosscall return planning。`lowerReturnWords` 中剩余的标量 return-word fallback 以及最后一个 `lowerScalarPlanExprOrFallback` helper 已删除；当 aggregate crosscall return planning 和 `ReturnValueWordPlan` 都不适用时，`lowerReturnAssignments` 现在会显式失败。
  - 已开始：直接标量 local 赋值和复合赋值的 statement 组装现在总是先消费 `Lower.buildExprPlan`，再调用 `ToYul.scalarAssignmentStmtPlanStatements`。静态与动态本地 fixed-array element、struct-field，以及 struct-array field assignment target 现在统一通过 `lowerAggregateScalarAssignmentStmt` 降级：静态 target 走 `ToYul.scalarAssignmentStmtPlanStatements`，动态 target 走 `ToYul.dynamicAggregateScalarAssignmentStmtPlanStatements`（`buildStaticAggregateScalarTargetPlan? -> StmtPlan.assign/assignOp -> ToYul`）。基于 `lowerAssignTargetName` + `lowerAssignmentValueExpr` 的静态聚合 fallback 已删除。用于一维与嵌套 path switch frame 组装的 IR-local dynamic assignment helper 已删除；`lowerAssignStmt` 和 `lowerAssignOpStmt` 对非整本地聚合 target 现在走统一 planned 路径。整聚合赋值、非标量 storage effect 写入仍留在现有兼容路径上，直到对应迁移切片补齐覆盖。整本地 struct 赋值现在总是消费 `Lower.structAssignmentSourcePlans -> ToYul.wholeStructAssignStmtFromPlan`；用 `lowerExpr` fallback 重复 planned source 展开的 IR-local `lowerStructAssignmentSourceExprs` 兼容 helper 已删除。整聚合 fixed-array 和 struct-array 赋值早已只走 planned source 路径。
  - 已开始：标量 `ifElse` 兼容降级现在总是先对 condition 表达式消费 `Lower.buildExprPlan`，再调用 `ToYul.ifElseStmtPlanStatements`；基于 `lowerScalarPlanExprOrFallback` 的旧 `switchStmt` fallback 已删除。
  - 已开始：标量 `storageScalarRead`、`storageScalarWrite` 和 `storageScalarAssignOp` 降级现在会对非 struct 标量状态总是消费 `Lower.buildEffectPlan` 产出的 `ScalarStorageTargetPlan` 变体。该 plan 会携带 storage slot 以及 packed byte offset/width，direct `EffectPlan -> ToYul` helper 负责最终 packed read/write/assign-op frame。struct-valued scalar storage write 现在总是通过 `Lower.storageStructWriteFieldPlans` 和 `ToYul.storageStructWriteFieldPlanStatements` 降级。已无调用的 `lowerScalarStorageWriteStmt` 兼容 helper 已删除；标量 storage write 成功路径现在必须经过 target `EffectPlan -> ToYul` helper。
  - 已开始：direct `storageMapInsert`/`storageMapSet` 写入组装现在会对受支持的标量 map key/value 表达式消费 `Lower.buildEffectPlan` 产出的 `MapWriteTargetPlan` 变体。statement 位置写入和 expression 位置的返回旧值写入现在都会通过 direct `EffectPlan -> ToYul` / `ExprPlan -> ToYul` helper 消费 planned map root slot，不再在兼容外观里做 late lookup。direct `storageMapContains` 和 `storageMapGet` 读现在也会消费 `MapReadTargetPlan` 以及 `ToYul.mapContainsTargetExpr` / `ToYul.mapGetTargetExpr`，负责最终的 presence/value slot 读取。storage-path map 读写继续走各自专用的 `StorageSlotPlan` / `StoragePathWriteTargetPlan` surface，直到 typed map path-expression planning 被拓宽。已无调用的 `lowerMapSetReturnExpr` helper 已删除；expression 位置 map insert/set 返回旧值 effect 仍走 target effect-plan 路径。
  - 已开始：direct `storageArrayRead`/`storageArrayWrite` 组装现在会对受支持的标量 index/value 表达式消费 `Lower.buildEffectPlan` 产出的 `ArrayReadTargetPlan`/`ArrayWriteTargetPlan` 变体。这些 plan 会携带数组 root slot 和 length，direct `ExprPlan -> ToYul` / `EffectPlan -> ToYul` helper 现在负责最终的 `__proof_forge_array_slot(root, length, index)` 组装，不再通过兼容外观 callback 做 late lookup。struct-array field 读写和 storage-path array 读写仍留在现有 helper/target surface 上，直到它们的元数据被拓宽成 explicit semantic-plan node。
  - 已开始：direct `storageStructFieldWrite` 和 `storageArrayStructFieldWrite` 组装现在会对受支持的标量 field value 与 struct-array index 消费 `Lower.buildEffectPlan` 产出的 `StructFieldWriteTargetPlan`/`StructArrayFieldWriteTargetPlan` 变体。这些 plan 会携带 struct field slot，或 struct-array root slot/length/field 元数据；direct `EffectPlan -> ToYul` helper 现在负责最终的 `sstore(fieldSlot, value)` 以及 `__proof_forge_struct_array_slot(root, length, fieldCount, fieldOffset, index)` 组装，不再通过兼容外观 callback 做 late lookup。direct `storageStructFieldRead` 现在也会消费 `StructFieldReadTargetPlan` 和 `ToYul.structFieldReadTargetExpr`，负责最终的 `sload(fieldSlot)` 组装。direct `storageArrayStructFieldRead` 现在会消费 `StructArrayFieldReadTargetPlan` 和 `ToYul.structArrayFieldReadTargetExpr`，负责最终的 `sload(__proof_forge_struct_array_slot(root, length, fieldCount, fieldOffset, index))` 组装。storage-path struct/array field surface 仍走专用 storage-path target 路径，直到 typed path expression planning 被拓宽。
  - 已开始：整体结构体 `storageScalarWrite` 组装现在总是会对 local struct source、storage-struct read source 和 struct literal 先消费 `Lower.buildEffectPlan`，再消费 `Lower.storageStructWriteFieldPlans` 和 `ToYul.storageStructWriteFieldPlanStatements`。从 storage scalar struct read 读取单个字段的 struct-literal 字段表达式现在会通过 `Lower.buildExprPlan` 降级为 planned `storageLoad` slot。已无调用的 `lowerStorageStructWriteSourceExprs`、`lowerStorageStructWriteStmt` 和 `storageStructWriteSupportsPlan` 兼容 helper 已删除。
  - 已开始：statement 位置的 map/array/struct-field/struct-array-field 以及非 struct 标量 storage write/assign-op effect 现在总是先消费 `Lower.buildEffectPlan`，再调用 target `EffectPlan -> ToYul` helper。已无调用的 `lowerMapWriteStmt`、`lowerArrayWriteStmt`、`lowerStructFieldWriteStmt`、`lowerStructArrayFieldWriteStmt`、`lowerMapScalarPlanExprOrFallback`、`lowerArraySlotExpr` 和 `lowerStructArrayFieldSlotExpr` 兼容 helper 已删除；active write 成功路径现在必须经过 target `EffectPlan -> ToYul` helper。
  - 已开始：expression 位置的 `storagePathRead` 组装现在会消费 `Lower.buildEffectPlan` 产出的 planned typed `StorageSlotExprPlan` target。direct map、嵌套 map、array、struct-field 和 struct-array-field storage-path read 都会通过 `ToYul.storagePathReadExprFromExprPlan` 负责最终的 `sload` slot 表达式，不再只在兼容外观末端重新计算 slot。active path segment 表达式现在会通过 `Lower.buildStoragePathPlan` 变成携带 `ExprPlan` 的 `StoragePathPlanSegment`。兼容性的 `lowerStoragePathReadExprTarget` helper 现在也会先构造 `Lower.buildStoragePathPlan`，再通过 `StorageSlotExprPlan -> ToYul` 降级，因此 raw path segment 表达式不再通过 `ValuePlan` wrapper 进入 read fallback。旧 `ValuePlan` slot helper 只保留给直接 `StorageSlotPlan` helper surface 和 legacy compatibility test。已无调用的兼容性 `lowerStoragePathReadExpr` wrapper 已删除；raw planned effect 仍暂时使用 `lowerStoragePathReadExprTarget`，直到剩余 diagnostic-only caller 不再需要这个 target callback。
  - 已开始：statement 位置的 `storagePathWrite` 和 `storagePathAssignOp` 组装现在会消费 `Lower.buildEffectPlan` 产出的 planned `StoragePathWriteExprTargetPlan` 变体，并在 direct `mapKey`、`index`、`field`、`index`+`field` 以及连续嵌套 `mapKey` 路径中，对受支持的标量写入/复合赋值 RHS value 使用 direct `EffectPlan -> ToYul` helper。当前 active statement 路径现在总是进入 `Lower.buildEffectPlan -> StoragePathWriteExprTargetPlan -> ToYul`；raw path segment 表达式不再通过 `ValuePlan` wrapper 进入 write/assign 降级。兼容性的 `lowerStoragePathWriteTarget`、`lowerStoragePathWriteStmt` 和 `lowerStoragePathAssignOpStmt` helper 已删除，raw `ToYul.storagePathWriteEffect*` 与 `ToYul.storagePathAssignOpEffect*` callback surface 也已删除。direct 调用方和诊断路径现在必须使用 target-plan 或 expr-target-plan helper。
  - 已开始：标量 `ifElse` 和 `boundedFor` 的 control-flow frame 组装现在会消费窄 `StmtPlan -> ToYul` helper。if 条件和合成的 bounded-loop 守卫会消费 `ExprPlan -> ToYul`；受支持的分支/循环 body 语句现在会递归消费 planned 标量绑定、标量/local aggregate-scalar 赋值、断言、返回、revert、标量 storage 写入、map 写入以及 map contains/get 读表达式、array 写入与 array 读表达式、struct-field 写入以及 struct/struct-array field 读表达式、storage-path 写入/复合赋值以及 storage-path 读表达式、静态/动态标量本地 fixed-array 读表达式、静态/动态本地 struct-array 字段读表达式、标量非索引/索引事件 emit、memory-array set effect、memory-array length/get expression（包括对 planned memory-array allocation 取 length），以及受支持 body 语句里的标量 crosscall/create helper-call 表达式。受支持分支/循环 body 的语句排序现在会通过 `ToYul.stmtPlanBodyStatements`，由它负责 planned 标量 body 的语句顺序、环境传递以及分支局部 `leaveAfterReturn` 传播。planned `revert`/`revertWithError` statement frame 现在会通过 `ToYul.revertStmtPlanStatements`，包括空 revert、message revert，以及 callback 提供的 `ErrorRef` payload。暂不支持的 body 形状仍留在 `IR.lean` 兼容外观中，直到完整递归的 `StmtPlan -> Yul` 降级被抽出。
  - 已开始：标量事件数据字和标量索引事件 topic 现在也会消费同一个 `ExprPlan -> ToYul` 表达式边界。聚合事件打平和索引聚合 topic 哈希仍留在兼容外观中，直到事件组装被抽到 `EventPlan -> Yul` 后面。
  - 已开始：最终事件 block 组装现在会消费 `EventPlan -> ToYul` helper，用于签名 topic 设置、索引 topic 语句、非索引数据存储，以及最终 `log1`-`log4` 语句选择。`Lower` 现在会在 ToYul 运行前，把 `AbiValuePlan` source 转成 per-field `ExprPlan` word 序列，并以 `EffectPlan.eventEmitWords` / `eventEmitIndexedWords` 作为 active lowering surface。完整 semantic-plan 构造现在会直接从 `Lower.buildEffectPlan` 返回这些 word-effect 变体；完整 module assembly 现在会对已支持的 planned-body 子集、per-word `ExprPlan` 已受支持的聚合事件 word effects、动态本地返回、聚合 local/literal 返回字赋值、storage-backed struct scalar 返回字赋值、planned aggregate crosscall return assignment，以及 crosscall 参数字使用 local/storage source plan 的标量 planned-body return 消费 `ModulePlan` entrypoint body，遇到不支持的形状再回退到 portable IR body 路径。IR facade 转换只保留在这个 planned-body 子集之外的兼容 event statement 路径上。planned-body event effect 现在会通过 `ToYul.eventEffectStmtPlanStatements`，因此 `StmtPlan.effect` 会在 ToYul 后面选择 word-effect event block 构造，并且 ToYul 会拥有字段/值数量检查、word-plan-to-Yul 表达式降级以及 indexed-topic/data 路由，而 IR 只提供字段 word plan。普通 event statement 现在也使用同一个 `StmtPlan.effect` helper，IR-local indexed-topic/data-word wrapper helper 已经移除。早期的 Yul-expression callback helper 和字段 word provider callback helper 形状也已经从 active ToYul surface 移除。
  - 已补充：兼容 `lowerEventEmitCoreStmt` 入口现在会从 portable event effect 调用 `Lower.buildEffectPlan`，并且只接受 word-planned 的 `eventEmitWords`/`eventEmitIndexedWords` 后再交给 `ToYul.eventEffectStmtPlanStatements`；事件 plan 和字段值 source planning 不再由 `IR.lean` 手工重建。
  - 已开始：事件数据字存储组装以及标量/聚合索引 topic 组装现在会消费 `EventFieldPlan -> ToYul` helper。字段表达式求值和聚合打平仍使用兼容外观，直到完整事件降级路径表达为 `EventPlan`。
  - 已开始：helper 发现结果现在会在完整的 plan-driven module lowering 中从 `ModulePlan` 消费。`lowerModuleWithPlan` 会从语义计划字段发射 checked arithmetic helper、crosscall helper（包括已规划的 plain native transfer）、create/create2 helper 以及 local-array getter helper。不完整的 best-effort diagnostic plan 现在也会使用同一套 `Lower`/`Validate` helper 发现来源，而不是回退到 `IR.lean` 内的重新发现逻辑；这样 validation diagnostics 不会被 plan-shape 错误遮蔽，同时最终 helper ownership 仍留在 `IR.lean` 之外。
  - 已开始：crosscall helper 命名和函数体构造现在位于 `CrosscallHelperSpec -> ToYul` 边界之后。`CrosscallHelperSpec.wordTypes` 会承载已规划的返回 ABI 字布局，因此标量 helper、聚合返回 helper 和 plain native transfer helper 都可以在完整 plan-driven lowering 中直接从语义计划发射，而不需要在发射阶段重新从模块发现返回布局。完整的 `ModulePlan` 构造现在会从已经构造好的 `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree 中发现 crosscall helper specs，包括已规划的参数 word arity、返回字布局以及 native-transfer 识别；`IR.buildSemanticPlan` 会保留这些由 Lower 发现的 specs，而不是重新扫描模块。旧的 IR-local fallback discovery scanner 已经移除；fallback helper discovery 只会在 incomplete/legacy plan surface 上调用 raw-IR 兼容 scanner `Lower.buildCrosscallHelperPlans`。
  - 已开始：create/create2 helper 命名和函数体构造现在位于 `CreateHelperSpec -> ToYul` 边界之后。已规划的 create specs 可以直接发射确定性的 init-code `mstore` frame、`create`/`create2` opcode 调用、零地址失败 revert guard，以及 helper 函数名，而不需要再转换回 `IR.lean` 的兼容 helper spec。完整的 `ModulePlan` 构造现在会在 `Lower.buildFullModulePlan` 和 `Lower.buildFullModulePlanWithTargetPlan` 中，从已经构造好的 `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree 发现 create/create2 helper specs；`IR.buildSemanticPlan` 会保留这些由 Lower 发现的 specs，而不是重新扫描模块。旧的 IR-local discovery scanner 和兼容 helper spec facade 已经移除；fallback helper discovery 只会在 incomplete/legacy plan surface 上调用 raw-IR 兼容 scanner `Lower.buildCreateHelperPlans`，并通过 `ToYul.createHelperFunction` 发射。
  - 已开始：checked-arithmetic 和本地 fixed-array getter helper 的需求现在会在 `Lower.buildFullModulePlan` 和 `Lower.buildFullModulePlanWithTargetPlan` 中，从已经构造好的 `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree 发现。checked-arithmetic discovery 覆盖 planned `.checkedArith` 表达式以及 planned `assignOp`/storage assign-op 节点。本地数组 discovery 覆盖 planned dynamic `ExprPlan.localArrayGet` 路径、nested local-array shapes，以及 dynamic array-literal getter；这会避免 legacy raw scanner 在 nested helper 已覆盖同一访问时，额外近似出 standalone row helper。`IR.buildSemanticPlan` 会保留 Lower 拥有的 `usesCheckedArithmetic`、`localArrayGetLengths` 和 `nestedLocalArrayGetShapes` 字段，而不是在 plan 构造后重新扫描模块。不完整 plan 的 fallback lowering 仍会调用 `Validate.moduleUsesCheckedArithmetic`、`Lower.buildLocalArrayGetLengths` 和 `Lower.buildNestedLocalArrayGetShapes`。完整 `ModulePlan` 构造现在也会用 planned entrypoint body 中发现的 helper 需求，替换来自 capability 的粗粒度 memory-array helper 需求；单独的 `memoryArrayLength` 不再发射 allocation/get helper，`ToYul` 也可以分别发射 memory-array new/get helper。同一个 planned helper scanner 现在也会替换来自 capability 的粗粒度 hash helper 需求：`hash(x)` 只发射 `hashWord`，`hashTwoToOne(a,b)` 只发射 `hashPair`，`ToYul` 也可以分别发射 hash word/pair helper。它现在还会替换 complete plan 中来自 state shape 的 storage-array helper 需求，因此未使用的 fixed-array、dynamic-array 或 struct-array state 声明不再发射 `arraySlot`、`dynamicArraySlot` 或 `structArraySlot` helper，除非 planned entrypoint body 实际引用了这些 storage slot plan。完整 plan 现在也会替换来自 state shape 的粗粒度 map helper：未使用的 map state 不再发射 map helper；contains-only 读取只发射 `mapPresenceSlot`；value 读取只发射 `mapSlot`；statement 写入发射 `mapWrite` 及其 slot/presence 依赖；expression 位置的 insert/set 发射 `mapSetReturn` 及其依赖；map assign-op helper 会从最终 helper set 回填 `ModulePlan.mapAssignOps`。
  - 已开始：`ModulePlan.contextOps` 现在也会在 `Lower.buildFullModulePlan` 和 `Lower.buildFullModulePlanWithTargetPlan` 中，从已经构造好的 `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree 发现。planned scanner 覆盖 `ExprPlan.context`、`EffectPlan.contextRead`、嵌套的 `blockHash` 参数表达式、event words、crosscall/create 参数、storage target expression slot，以及 control-flow body，并按 `ContextField.name` 去重。`IR.buildSemanticPlan` 会保留这些由 Lower 拥有的 context summary；raw `Plan.contextOpsFromModule` scanner 只作为 base/best-effort 兼容 surface 保留。
  - 已开始：标量 expression 位置的 crosscall helper-call 组装以及 create/create2 helper-call 组装现在位于 `ToYul` 后面。标量 `call`、带值 `call`、native value transfer、`staticcall`、`delegatecall`、`create` 和 `create2` 的 `ExprPlan` 节点可以直接使用与 helper body 发射相同的 helper 名称选择逻辑降级为 helper call。`ToYul.crosscallExprPlanExpr` 现在负责标量 crosscall expression 的 target/method/call-value 降级、provider-backed crosscall argument source 展开、helper-call 名称选择以及最终参数顺序。planned scalar return frame 现在会调用与 expression lowering 相同的 `lowerExprPlanExpr` callback，因此 local/storage aggregate crosscall argument source plan 可以先由 provider 展开，再由 `ToYul` 选择 helper-call 形状。旧版 untyped `.crosscallInvoke` expression lowering 现在也会进入同一条 `Lower.buildExpressionExprPlan` -> `ExprPlan.crosscall` -> `ToYul.crosscallExprPlanExpr` 路径，而不是继续在 `IR.lowerExpr` 里直接组装标量 helper-call。旧版 `crosscallCreate` 和 `crosscallCreate2` expression lowering 现在也会进入 `Lower.buildExpressionExprPlan` -> `ExprPlan.create` -> `ToYul.exprPlanExpr`，旧的 IR-local create helper-call 分支已经移除。`hashValue`、`hash` 和 `hashTwoToOne` expression lowering 现在也会进入 `Lower.buildExpressionExprPlan` -> `ExprPlan.hashValue`/`ExprPlan.hash`/`ExprPlan.hashTwoToOne` -> `ToYul.exprPlanExpr`，旧的 IR-local hash pack/helper-call 分支已经移除。标量算术、除法/取模、位运算、移位和指数 expression lowering 现在也会进入 `Lower.buildExpressionExprPlan` -> `ExprPlan.checkedArith` 或 `ExprPlan.builtin` -> `ToYul.exprPlanExpr`，checked helper 选择、builtin opcode 名称和移位参数顺序不再属于 `IR.lowerExpr`。comparison、boolean、cast 和 native-value expression lowering 现在也会进入 `Lower.buildExpressionExprPlan` -> `ExprPlan.builtin`/`ExprPlan.cast`/`ExprPlan.nativeValue` -> `ToYul.exprPlanExpr`，又从 `IR.lowerExpr` 移除了一组直接标量 expression frame。标量 literal 和 local expression leaf 现在也会进入 `Lower.buildExpressionExprPlan` -> `ExprPlan.literalWord`/`ExprPlan.local` -> `ToYul.exprPlanExpr`，其中 `hash4` limb packing 复用同一条 `Lower.literalPlan` validation 路径。expression 位置的 storage/context read effect 现在也会进入 `Lower.buildEffectPlan` -> target `EffectPlan`/`EffectPlan.contextRead` -> `lowerPlanEffectExpr`/`ToYul`，而不是继续从 `IR.lowerEffectExpr` 直接分发。raw 兼容 `EffectPlan.storageMapContains` 和 `EffectPlan.storageMapGet` expression frame 现在也会使用 `ToYul.mapContainsExpr` 和 `ToYul.mapGetExpr`；`IR.lean` 对这些 legacy plan variant 只保留 map state/root-slot 查询。raw 兼容 `EffectPlan.storageArrayRead` expression frame 现在也会使用 `ToYul.arrayReadExpr`；`IR.lean` 对这个 legacy plan variant 只保留 array state root-slot 和 length 查询。raw 兼容 `EffectPlan.storageStructFieldRead` expression frame 现在也会使用 `ToYul.structFieldReadExpr`；`IR.lean` 对这个 legacy plan variant 只保留 struct state/field slot 查询。expression 位置的 map insert/set return effect 现在也会进入 `Lower.buildEffectPlan` -> target `EffectPlan.storageMapInsertTarget`/`EffectPlan.storageMapSetTarget` -> `lowerPlanEffectExpr`/`ToYul.mapSetReturnTargetExpr`。statement 位置的 scalar storage write 和 assign-op effect 现在会先消费 `Lower.buildEffectPlan` target effect，再调用 `ToYul.scalarStorageTargetEffectStmtPlanStatements`，因此 scalar slot、packing 和 fixed-slot target 决策不再来自 IR-local target 重新构造。statement 位置的 map insert/set write effect 现在也会先消费 `Lower.buildEffectPlan` target effect，再调用 `ToYul.mapWriteTargetEffectStmtPlanStatements`，因此 map root-slot target 决策以及 key/value expression planning 不再来自 IR-local target 重新构造。statement 位置的 fixed-array storage write effect 现在也会先消费 `Lower.buildEffectPlan` target effect，再调用 `ToYul.arrayWriteTargetEffectStmtPlanStatements`，因此 array root-slot、length、index 和 value planning 不再来自 IR-local target 重新构造。statement 位置的 storage struct-field write effect 现在也会先消费 `Lower.buildEffectPlan` target effect，再调用 `ToYul.structFieldWriteTargetEffectStmtPlanStatements`，因此 struct-field slot 和 value planning 不再来自 IR-local target 重新构造。statement 位置的 storage struct-array-field write effect 现在也会先消费 `Lower.buildEffectPlan` target effect，再调用 `ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements`，因此 struct-array field root-slot、length、field offset、index 和 value planning 不再来自 IR-local target 重新构造。statement 位置的 dynamic-array push/pop effect 现在也会先消费 `Lower.buildEffectPlan`，再调用 `ToYul.dynamicArrayPushEffectStmtPlanStatements`/`ToYul.dynamicArrayPopEffectStmtPlanStatements`，因此 push value expression planning 和 pop effect validation 不再来自 IR-local effect 重新构造。兼容性的 `IR.lean` 表达式降级仍为 source plan 提供 local/storage provider callback。
  - 已开始：direct map get/contains、fixed-array read、dynamic-array read 和 struct-array field read 的旧 read compatibility helper 已经从 `IR.lean` 移除；direct storage read expression 现在通过 `lowerEffectExprThroughPlan` 和 `lowerPlanEffectExpr -> ToYul` 边界进入。
  - 已开始：旧的 `lowerMapPathReadExpr` nested-map read helper 已在 storage-path read 迁移到共享 `StorageSlotExprPlan -> ToYul` frame 后移除。
  - 已开始：raw 兼容 `EffectPlan.storageArrayStructFieldRead` expression frame 现在也会使用 `ToYul.structArrayFieldReadExpr`；`IR.lean` 对这个 legacy plan variant 只保留 struct-array root-slot、length、field count 和 field offset 查询。
  - 已开始：statement 位置的 storage-path write 和 assign-op effect 现在总是先通过 `Lower.buildEffectPlan`，再进入最终 `ToYul` 组装；`IR.lean` 不再为这些路径选择 fallback storage-path target 或 scalar RHS 表达式。
  - 已开始：旧的 `lowerMapPathWriteStmt` nested-map writeback helper 已在 storage-path write fallback 迁移到共享 `ToYul` frame 后移除。
  - 已开始：旧的 `lowerStoragePathWriteTarget`、`lowerStoragePathWriteStmt` 和 `lowerStoragePathAssignOpStmt` 兼容 helper，以及 raw `ToYul.storagePathWriteEffect*` / `ToYul.storagePathAssignOpEffect*` callback surface 已删除；active storage-path write-like 降级必须使用 target-plan 或 expr-target-plan helper。
  - 已开始：dynamic-array push/pop 的成功路径现在会消费携带 root slot 的 `DynamicArrayTargetPlan` target variant，再调用 `ToYul.dynamicArrayPushTargetEffectStmtPlanStatements` / `ToYul.dynamicArrayPopTargetEffectStmtPlanStatements`。因此 root-slot 选择和最终 dynamic-array slot helper 组装不再通过 `IR.lean` callback 重建。`Lower.buildEffectPlan` 现在会直接拒绝无效 dynamic-array target，而不是返回 raw `storageDynamicArrayPush` / `storageDynamicArrayPop` fallback plan；已无调用的 raw dynamic-array ToYul helper/callback surface 也已移除。entrypoint body-plan 完整性现在与 dispatch-plan 完整性分开判断，因此带 EVM fallback/receive entrypoint 的模块仍能消费完整 body plan，而 dispatch 继续只覆盖 selector 可寻址函数；空 body 的 surface plan 也不会再擦掉 fallback/receive lowering。
  - 已开始：已无调用的 `lowerDynamicArrayWriteStmt` 和 `lowerDynamicArrayPopStmt` fallback helper 已删除；dynamic-array write-like 行为继续位于 storage-path write plan 路径，dynamic-array pop 成功路径必须经过 target effect planning。
  - 已开始：expression 位置的本地 fixed-array getter、本地 struct-field getter，以及标量 array-literal indexing 组装现在都对本地标量叶子位于 `ExprPlan -> ToYul` 后面。`Lower` 会在 `ExprPlan.localArrayGet` 中记录本地 fixed-array 路径维度，`ToYul` 负责静态 local 名称选择、本地 struct-field 名称选择、struct literal field 选择、数组字面量元素选择，以及标量数组、标量数组字面量和 struct-array field 的一维/嵌套动态 helper-call 参数 frame。direct `IR.lowerExpr` 本地 fixed-array read 现在会在 `Lower.buildExprPlan` 产出 `.localArrayGet` 时优先消费该计划；direct 本地 struct-field read 现在也会在 `Lower.buildExprPlan` 为本地 struct 值、struct literal 或本地 struct-array leaf 产出受支持 `.structField` plan 时优先消费该计划；direct 标量 array-literal read 现在也会在 `Lower.buildExprPlan` 产出 `.arrayGet (.arrayLit ..)` 时优先消费该计划。storage-backed struct read、聚合数组值，以及不支持的聚合 local-array leaf 仍通过兼容外观 fallback。
  - 已开始：整体本地聚合赋值的 snapshot block 现在位于 `ToYul` 后面。本地 fixed-array 和扁平 struct 整体赋值 source 现在会先进入 `Lower.fixedArrayAssignmentSourcePlans` 或 `Lower.structAssignmentSourcePlans`，因此本地聚合 source 以及数组/结构体字面量里的标量表达式会先表示为 `ExprPlan`，再由 `ToYul.*AssignStmtFromPlan` 发射 snapshot block。storage-backed scalar struct 赋值 source 现在也会进入 `Lower.structAssignmentSourcePlans`，并表示为 `ExprPlan.storageLoad` word 表达式。嵌套 fixed-array 整体赋值 source 现在会进入 `Lower.nestedFixedArrayAssignmentSourcePlans`，并通过 `ToYul.wholeNestedFixedArrayAssignStmtFromPlan` 降级；IR-local `NestedFixedArraySourceExpr` 展开 helper 已移除。struct-array 整体赋值 source 现在会进入 `Lower.structArrayAssignmentSourcePlans`，并通过 `ToYul.wholeStructArrayAssignStmtFromPlan` 降级；IR-local `lowerStructArrayAssignmentSourceExprs` helper 已移除。最终的临时变量声明、目标 local 名称以及 assignment block 构造会委托给 `ToYul` helper，使兼容外观不再拥有已支持整体本地聚合 source 的最终 Yul statement frame。
  - 已开始：动态本地聚合赋值的 switch frame 现在位于 `ToYul` 后面。`IR.lean` 仍负责解析动态本地 fixed-array 与 struct-array 路径，但动态 index/value snapshot expression 现在会先进入 `Lower.buildExprPlan`，再由 `ToYul` helper 发射共享的 snapshot local、switch default case、checked-assignment RHS、一维 switch frame 和嵌套路径 switch frame。
  - 已开始：聚合 crosscall helper-call 组装以及入口多字返回 assignment 现在位于 `ToYul` 后面。expression 位置的聚合 crosscall return 诊断现在来自 `Lower.buildExpressionExprPlan`，聚合 crosscall return assignment 的判断现在来自 `Lower.aggregateCrosscallReturnAssignmentPlan?`。该 plan 会记录 call mode、target/method/call-value expression plans、已规划的 crosscall argument words，以及 `ReturnPlan` 的 local-name/word-layout 数据；`IR.lean` 消费这些已规划的 `ExprPlan`，并把最终 helper-call 函数名选择、参数顺序以及多返回 Yul assignment 构造委托给 `ToYul`。entrypoint return、indexed event 和 event data 的聚合 ABI word 展开现在使用 `AbiValuePlan` source nodes，而不是 `ExprPlan.localAbiWords`/`ExprPlan.storageAbiWords` 这种 expression marker。`ReturnValueWordPlan.source`、planned event data fields 和 planned event indexed fields 现在会携带 `AbiValuePlan.expr`、`AbiValuePlan.local`、`AbiValuePlan.storage`、`AbiValuePlan.arrayLit` 或 `AbiValuePlan.structLit`。`Lower.returnValueWordPlans`、`Lower.eventFieldDataWordPlans` 与 `Lower.eventFieldsDataWordPlans` 会把这些 ABI value plans 展开为标量 word `ExprPlan`。本地聚合会通过 `Lower.localAbiWordPlans` 降为显式 `.local` word plans；storage-backed 聚合会通过 `Lower.storageAbiWordPlans` 降为显式 `ExprPlan.storageLoad` word plans；fixed-array/struct literal 会在 `Lower.abiValueWordPlans` 中递归降为标量 word plans。`IR.lean` 现在消费这些已规划的 word，把每个 word plan 降为 Yul，并且只把最终 return assignment frame 委托给 `ToYul.returnValueWordAssignments`，把最终 event topic/log frame 委托给 `ToYul.eventIndexedTopicStatements` 与 `ToYul.eventEmitCoreStatement`。兼容性的 return 以及显式 local/storage word helper 仍保留给直接测试和旧调用方，但 active IR facade 不再依赖 provider callback 或 expression-level aggregate source marker 来完成 return/event 聚合 ABI word 展开；event provider-callback `ToYul.*FromPlan` helper 已经从 semantic-plan surface 移除。crosscall helper-call 组装现在使用专门的 `CrosscallArgWordPlan` source nodes，而不是继续把 crosscall 参数来源塞进 expression-level marker。`ExprPlan.crosscall.args` 和 `CrosscallReturnAssignmentPlan.args` 会携带已规划的 crosscall argument word source：标量、literal、storage-load word、本地聚合 struct/fixed-array word 以及已展开的 storage-backed 聚合 word 使用 `CrosscallArgWordPlan.expr`；本地聚合会在 `Lower` 中展开为 `.local` word plans，storage-backed 聚合会在 `Lower` 中展开为 `.storageLoad` word plans，provider-backed source marker 只保留给 direct/legacy helper surface。旧的 `ExprPlan.localAbiWords`、`ExprPlan.storageAbiWords`、`ExprPlan.localCrosscallWords` 和 `ExprPlan.storageCrosscallWords` constructor 已经从 `ExprPlan` 退役；直接 `ToYul.*Words` helper 只作为显式 local/source word 展开的 helper API 保留。`Lower.buildCrosscallArgWordPlansMany` 现在返回这些 source plan，`ToYul.crosscallArgWordPlanExprs` 负责最终遍历和 word 拼接；`ToYul.crosscallExprPlanExpr` 会在此基础上组装 target/method/call-value 降级和标量 helper-call 选择。`IR.lean` 仍只会为 direct/legacy local/storage crosscall source plan surface 提供 ToYul provider callback；旧版 untyped scalar expression crosscall lowering 现在会先进入 `Lower.buildExpressionExprPlan` -> `ExprPlan.crosscall`，再进入该 ToYul 边界。旧的 IR-local 标量 helper-call 分支和 `lowerCrosscall*ArgWords` 展开树已经删除。
  - 已完成：active 聚合 crosscall return assignment 现在进入 `ToYul.crosscallAggregateReturnAssignmentExpandedPlanStatement`，由 ToYul 负责 target/method/call-value 降级、已展开 planned argument word 遍历、helper 名选择、参数顺序以及多返回 assignment 组装；provider-backed `ToYul.crosscallAggregateReturnAssignmentPlanStatement` 以及 `ToYul.crosscallArgWordPlanExprs` / `ToYul.crosscallExprPlanExpr` / `ToYul.localCrosscallWords` 和对应 IR 兼容 helper 已退役。
  - 已补充：local aggregate struct/fixed-array crosscall argument 现在会在 `Lower` 中展开成显式的 `CrosscallArgWordPlan.expr (.local ...)` word plans；storage-backed aggregate struct/fixed-array crosscall argument 也会在 `Lower` 中展开成显式的 `CrosscallArgWordPlan.expr (.storageLoad ...)` word plans；active path 不再保留 provider-backed 的 local 或 storage source marker。
  - 已完成：active expression crosscall 现在只通过 `ToYul.crosscallExpandedArgWordPlanExprs` 与 `ToYul.crosscallExpandedExprPlanExpr` 消费已展开的 `.expr` word plans；semantic-plan 测试改为只覆盖 `Lower -> expanded word plans -> ToYul` 路径。
  - 为选择器分发、calldata 守卫、ABI 字打平、返回数据编码和制品元数据选择器布局添加 `EntrypointPlan`。
  - 为事件签名 topic、索引 topic 哈希、非索引数据打平以及制品元数据事件布局添加 `EventPlan`。
  - 为类型化的 `call`、带值的 `call`、`staticcall`、`delegatecall`、`create` 和 `create2` helper 添加 `CrosscallPlan`。
  - 添加 `MetadataPlan` 和部署制品规划，以便从同一个语义计划生成字节码元数据、initcode、部署清单和链 profile 引用。
  - 仅在每个迁移的能力都被计划级诊断、黄金 Yul、solc 字节码生成、Foundry 冒烟测试、制品元数据验证和 EVM IR 覆盖清单覆盖后，才删除旧的自定义语义 `IR.lean -> Yul` 降级。
  - 保留 `ProofForge.Compiler.Yul.AST` 和 `ProofForge.Compiler.Yul.Printer`；迁移替换的是后端语义降级，而不是目标 AST/打印机边界。
- 已完成：添加 EVM IR 诊断冒烟测试，使不支持的可移植 IR 形状在 Yul 生成之前失败并显示稳定的消息。
- 已完成：添加 EVM IR 覆盖清单门控，使每个可移植 IR 构造函数必须针对 EVM 后端被分类为已降级、已验证、不支持或结构化。
- 已完成：为 `U64`、`U32` 和 `Bool` 上的可移植 IR EVM 标量 ABI 参数解码添加 `AbiScalarProbe`，并包含黄金 Yul、solc 字节码和 Foundry 畸形 calldata 验证。
- 已完成：将 EVM IR `assert` 和 `assert_eq` 降级添加为 Yul revert 守卫，并包含 `AssertProbe` 黄金 Yul、solc 字节码和 Foundry 成功/revert 验证。
- 已完成：添加 EVM IR 可变标量局部绑定和局部赋值降级，并包含 `AssignmentProbe` 黄金 Yul、solc 字节码和 Foundry 成功/revert 验证。
- 已完成：为所有可移植 `AssignOp` 变体添加 EVM IR 局部和标量存储复合赋值降级，并包含 `EvmAssignOpProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始槽验证、元数据能力验证以及针对畸形目标/类型的显式诊断。
- 已完成：将 EVM IR 语句级 `if/else` 降级添加为 Yul `switch` 块，并包含 `ConditionalProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证，以及通过 `EvmLoopProbe` 进行的 EVM 特定分支局部 early-return 验证。
- 已完成：将 EVM IR `boundedFor` 降级添加为具有静态边界的 Yul `for` 循环，并包含 `EvmLoopProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始存储验证、元数据能力验证、通过 Yul `leave` 进行的分支局部和循环局部 early-return 降级，以及显式的无效范围诊断。
- 已完成：为 `userId`、`contractId` 和 `checkpointId` 添加 EVM IR 上下文读取降级，对应为 Yul `caller()`、`address()` 和 `number()`，并包含 `ContextProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证和元数据能力验证。
- 已完成：将 EVM IR `nativeValue` 降级添加为 Yul `callvalue()`，并包含 `ContextProbe` 黄金 Yul、solc 字节码、Foundry 带值调用验证和 `value.native` 元数据能力验证。- 已完成：添加 EVM IR `eventEmit` 到 Yul `log1` 的降级，包含 `keccak256(Solidity-style event signature)` topic0 和 32 字节字数据字段，以及 `EventProbe` 黄金 Yul、solc 字节码、Foundry 记录日志验证、元数据能力验证和显式格式错误事件诊断。
- 已完成：添加 EVM IR `eventEmitIndexed` 到 Yul `log2`/`log3`/`log4` 的降级，支持最多三个标量索引字段，包含签名 topic0、索引 topic、非索引 32 字节字数据、`EventProbe` 黄金 Yul、solc 字节码、Foundry 记录日志验证、元数据能力验证和显式索引事件诊断。
- 已完成：弥补多 topic 标量索引事件的 EventProbe 验证差距。`IndexedTwoValues(uint64,uint64,uint64)` 和 `IndexedThreeValues(uint64,uint64,uint64,uint64)` 现在证明生成的 Yul 会发射 `log3` 和 `log4`，保留有序标量索引 topic，验证元数据选择器，使用 `solc` 编译，并通过 Foundry 记录日志断言。
- 已完成：弥补有类型标量事件字段的 EventProbe 验证差距。`TypedScalarEvent(bool,uint32,bytes32)` 和 `IndexedTypedScalar(bool,uint32,bytes32,uint64)` 现在证明 Bool、U32 和 Hash 事件数据字及索引 topic 正确降级，包含 Bool/U32 调度器守卫、黄金 Yul、元数据选择器检查、`solc` 和 Foundry 记录日志断言。
- 已完成：扩展 EVM IR 事件数据降级，使其超出标量字范围，从而使非索引扁平结构体字段、标量固定数组字段和扁平结构体的固定数组发射 ABI 风格的扁平化数据字，包含规范的 Solidity 风格事件签名（如 `PairEvent((uint64,uint64))`、`ArrayEvent(uint64[2])` 和 `PairArrayEvent((uint64,uint64)[2])`）、`EventProbe` 黄金 Yul、solc 字节码、Foundry 记录日志验证、元数据选择器验证，以及针对不支持的聚合索引字段的显式诊断。
- 已完成：扩展 EVM IR `eventEmitIndexed` 降级，使扁平结构体索引字段以及元素为扁平结构体的固定数组索引字段将其 ABI 风格的扁平化字哈希为索引 topic。`EventProbe` 现在涵盖了 `IndexedPair((uint64,uint64),uint64)` 和 `IndexedPairArray((uint64,uint64)[2],uint64)`，包含黄金 Yul、solc 字节码、元数据选择器验证、Foundry 记录日志 topic 哈希检查，以及针对嵌套/不支持的聚合索引形状的诊断。
- 已完成：通过添加 `IndexedArray(uint64[2],uint64)` 黄金 Yul、元数据选择器验证、solc 字节码生成和 Foundry 记录日志 topic 哈希检查，弥补标量固定数组索引 topic 的 EventProbe 验证差距。
- 已完成：扩展 EventProbe 嵌套固定数组事件聚合覆盖范围。`MatrixEvent(uint64[2][2])` 和 `PairMatrixEvent((uint64,uint64)[2][2])` 证明了标量和扁平结构体叶子节点的递归非索引数据扁平化，而 `IndexedMatrix(uint64[2][2],uint64)` 和 `IndexedPairMatrix((uint64,uint64)[2][2],uint64)` 证明了对递归扁平化的 ABI 风格字进行索引聚合 topic 哈希。冒烟测试现在锁定了新的选择器、事件 ABI 元数据、黄金 Yul、`solc` 字节码和 Foundry 记录日志断言；具有不支持或非扁平叶子节点的嵌套数组仍保持显式诊断。
- 已完成：为存储支持的扁平结构体事件数据和索引聚合 topic 添加 EventProbe 覆盖。`StoragePairEvent((uint64,uint64))` 和 `IndexedStoragePair((uint64,uint64),uint64)` 现在证明整个标量存储结构体写入可以通过 `storageScalarRead` 读回，扁平化为事件数据字，哈希为索引 topic，在黄金 Yul 中验证，在元数据选择器中检查，由 `solc` 编译，并由 Foundry 记录日志解码。
- 已完成：为存储支持的固定数组事件聚合添加 EventProbe 覆盖。`StorageArrayEvent(uint64[2])`、`StoragePairArrayEvent((uint64,uint64)[2])`、`IndexedStorageArray(uint64[2],uint64)` 和 `IndexedStoragePairArray((uint64,uint64)[2],uint64)` 现在证明存储数组读取和存储数组结构体字段读取可以用于非索引事件数据扁平化和索引聚合 topic 哈希，包含黄金 Yul、元数据选择器检查、`solc` 和 Foundry 记录日志验证。
- 已完成：添加 EVM IR `crosscallInvoke` 到同步 EVM `call` 辅助函数的降级，包含选择器打包、字参数、单字返回、失败调用以及短返回 revert，包含 `EvmCrosscallProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证、元数据能力验证，以及显式的畸形跨调用类型诊断。
- 已完成：为通过 `Bool`、`U32`、`U64` 和 `Hash` 进行的类型化标量字跨调用添加 EVM IR `crosscallInvokeTyped` 降级，包含返回类型特定的 Yul 辅助函数、Bool/U32 返回数据守卫、`EvmCrosscallProbe` 黄金 Yul、solc 字节码、Foundry 有效/无效类型化返回验证、元数据入口验证、针对该阶段未涵盖的聚合参数/返回形状的诊断，以及显式的 Psy 不支持诊断。
- 已完成：将 EVM IR 普通 `crosscallInvokeTyped` 返回降级扩展到标量字之外，以支持扁平结构体和标量固定数组的直接入口返回，包含 ABI 字形状特定的 Yul 辅助函数、多字返回数据大小检查、聚合返回字间的 Bool/U32 范围守卫、`EvmCrosscallProbe` 黄金 Yul、solc 字节码、Foundry 聚合结构体/数组返回验证、元数据选择器验证，以及针对该阶段未涵盖的聚合返回形状的显式诊断。
- 已完成：将 EVM IR 类型化跨调用参数降级扩展到标量字之外，使普通、带值、静态和委托类型化调用可以将扁平结构体和标量固定数组参数扁平化为 ABI 字。`EvmCrosscallProbe` 现在通过黄金 Yul、solc 字节码、Foundry 运行时检查、元数据选择器验证以及针对该阶段未涵盖的聚合参数形状的显式诊断，涵盖了普通结构体和固定数组参数，以及带值/静态/委托结构体参数。
- 已完成：为带值的类型化跨调用添加 EVM IR `crosscallInvokeValueTyped` 降级，通过值特定的 Yul 辅助函数转发显式的 U64 调用值表达式，用于标量返回以及扁平结构体和标量固定数组入口聚合返回，包含 `EvmCrosscallProbe` 黄金 Yul、solc 字节码、Foundry `msg.value`/被调用者余额验证、聚合 Bool/U32 畸形返回守卫、元数据入口验证、EVM 畸形值/返回诊断，以及显式的 Psy 不支持诊断。
- 已完成：为类型化静态调用添加 EVM IR `crosscallInvokeStaticTyped` 降级，使用不带值的 Yul `staticcall` 辅助函数进行选择器/标量/扁平聚合参数打包、标量返回、扁平结构体和标量固定数组入口聚合返回以及 Bool/U32 返回守卫，包含 `EvmCrosscallProbe` 黄金 Yul、solc 字节码、Foundry U64 只读返回、Bool/U32/Hash 静态类型化返回、聚合返回验证、无效类型化返回、静态上下文状态写入失败验证、元数据入口验证、EVM 畸形嵌套聚合诊断，以及显式的 Psy 不支持诊断。
- 已完成：为类型化委托调用添加 EVM IR `crosscallInvokeDelegateTyped` 降级，使用不带值的 Yul `delegatecall` 辅助函数进行选择器/标量/扁平聚合参数打包、标量返回、扁平结构体和标量固定数组入口聚合返回以及 Bool/U32 返回守卫，包含 `EvmCrosscallProbe` 黄金 Yul、solc 字节码、Foundry 调用者存储读/写验证、Bool/U32/Hash 委托类型化返回验证、聚合返回验证、无效类型化返回验证、元数据入口验证、EVM 畸形嵌套聚合诊断，以及显式的 Psy 不支持诊断。
- 已完成：将 EVM IR 类型化跨调用聚合覆盖范围扩展到普通、带值、静态和委托类型化调用参数以及直接入口返回中的扁平结构体固定数组。`EvmCrosscallProbe` 现在验证了所有四种调用模式下的 `RemotePair[2]` ABI 字扁平化、Bool/U32 字段返回守卫、黄金 Yul、solc 字节码、Foundry 运行时行为以及元数据选择器。
- 已完成：将 EVM IR 类型化跨调用聚合覆盖范围扩展到普通、带值、静态和委托类型化调用中的嵌套标量固定数组参数和直接入口返回。`EvmCrosscallProbe` 现在验证 `uint64[2][2]` ABI 字打平、黄金 Yul、solc 字节码、元数据选择器、Foundry 运行时行为、值转发、staticcall 行为以及所有四种调用模式下的 delegatecall 行为。在该里程碑，诊断程序仍然拒绝结构体和其他非标量嵌套固定数组叶节点；扁平结构体叶节点现在由下面的后续项涵盖。
- 已完成：将 EVM IR 类型化跨调用聚合覆盖范围扩展到叶节点为扁平结构体的嵌套固定数组。`EvmCrosscallProbe` 现在验证 `RemotePair[2][2]` 在普通、带值、静态和委托类型化调用中的参数和直接入口返回，包括 ABI 字打平、Bool/U32 字段保护、黄金 Yul、solc 字节码、元数据选择器、Foundry 运行时行为、值转发、staticcall 行为以及 delegatecall 行为。诊断程序仍然拒绝其结构体为非扁平或以其他方式不受支持的嵌套固定数组叶节点。
- 已完成：为固定 init-code 十六进制添加 EVM IR `crosscallCreate` 和 `crosscallCreate2` 降级。创建辅助程序将 init code 写入内存，调用 Yul `create`/`create2`，在零地址失败时 revert，返回部署的地址字，并验证黄金 Yul、solc 字节码、元数据选择器、Foundry 部署的运行时调用、确定性 CREATE2 地址推导、EVM 畸形创建诊断以及 Psy 不受支持诊断。
- 已完成：为 `U64`/`U32` 算术、`U64` 幂运算、`U64`/`U32` 位操作和移位、谓词、布尔运算符、字面量、不可变局部变量、受支持的转换、单字返回、分发器保护和断言保护添加 EVM IR 直接标量表达式验证，并包含 `EvmExpressionProbe` 黄金 Yul、solc 字节码、Foundry 运行时/畸形 calldata 验证、元数据能力验证以及 CI 覆盖。
- 已完成：添加 EVM IR `Hash` 字降级、`hash4`/`hashValue` 打包，以及通过 Yul `keccak256` 辅助程序进行的 `hash`/`hash_two_to_one` 降级，并包含 `EvmHashProbe` 黄金 Yul、solc 字节码、Foundry ABI/存储验证、元数据能力验证以及显式的 Hash/U64 不匹配诊断。
- 已完成：通过 Solidity 风格的 `keccak256(key, slot)` 映射槽位添加 EVM IR `Map<U64, U64, N>` 存储降级，并包含 `EvmMapProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始槽位验证、元数据能力验证，以及针对不受支持的映射形状和语句位置误用的显式诊断。
- 已完成：在 `Map<U64, U64, N>` 之上添加 EVM IR 单分段 `mapKey` 存储路径复合赋值，并包含 `EvmMapProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始槽位验证、元数据能力验证，以及针对表达式位置和嵌套路径误用的显式诊断。
- 已完成：将 EVM IR 存储映射泛化为 `U32`、`U64`、`Bool` 和 `Hash` 之上的字键/值形状，复用 Solidity 风格的 `keccak256(key, slot)` 映射槽位，并包含 `EvmTypedMapProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始槽位验证、`U32`/`Bool` calldata 保护、元数据能力验证、CI 覆盖以及针对非字映射形状的显式诊断。
- 已完成：通过以 `keccak256(slot || PROOF_FORGE_MAP_PRESENCE)` 为根的 ProofForge 管理的存在槽位添加 EVM IR `storage.map.contains` 降级，并包含 `EvmMapProbe` 和 `EvmTypedMapProbe` 黄金 Yul、solc 字节码、针对 U64/U32/Bool/Hash 映射的 Foundry 值/存在槽位验证、零值存在键覆盖、元数据验证以及针对语句位置误用的显式诊断。
- 已完成：在连续的 `mapKey` 分段上添加 EVM IR 嵌套映射存储路径，折叠用于值存储的 Solidity 风格映射槽位和用于最终键的 ProofForge 管理的存在槽位，并包含 `EvmMapProbe` 和 `EvmTypedMapProbe` 黄金 Yul、solc 字节码、Foundry 原始槽位验证，- U32 调度器守卫覆盖、元数据验证，以及针对混合 map/聚合存储路径的显式诊断。
- 已完成：添加 EVM IR `U64` 固定存储数组降级，将其作为带有运行时边界检查的连续存储插槽，并包含 `EvmStorageArrayProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始插槽验证、元数据能力验证，以及针对不支持的数组元素类型的显式诊断。
- 已完成：在 `U64` 固定存储数组上添加 EVM IR 单分段 `index` 存储路径读/写/复合赋值，复用有界数组插槽辅助程序并扩展 `EvmStorageArrayProbe` 验证。
- 已完成：将 EVM IR 字存储泛化为 `Bool` 标量存储和 `U32`/`Bool`/`Hash` 固定存储数组，复用有界数组插槽辅助程序，并包含 `EvmTypedStorageProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始插槽验证、`U32` calldata 范围守卫、元数据能力验证、CI 覆盖，以及针对不支持的非字存储元素类型的显式诊断。
- 已完成：为具有静态字面量索引的 `U64`、`U32`、`Bool` 和 `Hash` 元素添加 EVM IR 不可变局部固定数组值降级，支持直接固定数组字面量索引，并包含 `EvmArrayValueProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证、元数据能力验证，以及针对静态越界索引的显式诊断。
- 已完成：将 EVM IR 局部固定数组降级扩展到可变聚合局部变量，包括静态元素赋值、数值元素复合赋值以及 `U32`/`Bool`/`Hash` 元素写入，并包含 `EvmArrayValueProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证、元数据入口验证、CI 覆盖，以及针对不可变元素赋值的显式诊断。
- 已完成：通过在表达式中传递降级环境，将 EVM IR 局部固定数组降级扩展到动态局部/字面量索引，为动态读取生成特定长度的 Yul getter 辅助程序，将动态局部元素赋值和数值复合赋值降级为 `switch` 代码块，并通过 `EvmArrayValueProbe` 黄金 Yul、元数据入口、solc 字节码和 Foundry 运行时检查验证动态入界/越界行为。
- 已完成：添加来自局部值和字面量的 EVM IR 整体局部固定数组赋值，在写入目标元素之前将 RHS 元素快照到临时 Yul 局部变量中，并通过 `EvmArrayValueProbe` 黄金 Yul、元数据入口、solc 字节码和 Foundry 运行时检查验证局部源和自引用字面量 RHS 行为。
- 已完成：将 EVM IR 局部固定数组降级扩展到静态嵌套标量数组，包括不可变读取、可变叶节点赋值、数值叶节点复合赋值、嵌套整体局部赋值以及 RHS 快照，并包含 `EvmArrayValueProbe` 黄金 Yul、元数据入口、solc 字节码和 Foundry 运行时检查。扁平结构体嵌套叶节点由 `EvmStructArrayValueProbe` 覆盖；其他不支持的聚合叶节点仍保持显式诊断。
- 已完成：将 EVM IR 局部固定数组降级扩展到动态嵌套标量数组索引，包括用于读取的嵌套 getter 辅助程序、用于可变叶节点赋值和复合赋值的嵌套 `switch` 降级、混合静态/动态路径覆盖、运行时越界 revert、`EvmArrayValueProbe` 黄金 Yul、元数据入口、solc 字节码和 Foundry 运行时检查。
- 已完成：为 `U64`、`U32`、`Bool` 和 `Hash` 字段添加 EVM IR 扁平不可变局部结构体值降级，支持直接结构体字面量字段访问，并包含 `EvmStructValueProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证、元数据能力验证，以及针对整体结构体存储误用和嵌套字段的显式诊断。
- 已完成：将 EVM IR 扁平局部结构体降级扩展到可变聚合局部变量，包括静态字段赋值、数值字段复合赋值，以及`U32`/`Bool`/`Hash` 字段写入，包含 `EvmStructValueProbe` 黄金 Yul、solc 字节码、Foundry 运行时验证、制品元数据入口验证、CI 覆盖率，以及针对不可变字段赋值的显式诊断。
- 已完成：添加 EVM IR 从本地值和字面量进行整体本地结构体赋值的功能，在写入目标字段前将 RHS 字段快照到临时 Yul 本地变量中，并通过 `EvmStructValueProbe` 黄金 Yul、制品元数据入口、solc 字节码和 Foundry 运行时检查验证本地源和自引用字面量 RHS 行为。
- 已完成：添加扁平结构体的 EVM IR 本地固定数组，将每个元素字段展开为确定性的 Yul 本地变量，支持静态和动态 `field(arrayGet(localArray, index), name)` 读取、可变字段赋值、数值字段复合赋值、从本地数组和自引用数组字面量进行整体本地赋值（带 RHS 快照）、`U64`/`U32`/`Bool`/`Hash` 字段覆盖、动态越界回滚、`EvmStructArrayValueProbe` 黄金 Yul、制品元数据入口/能力验证、solc 字节码生成、Foundry 运行时检查以及 CI 覆盖率。
- 已完成：将 EVM IR 嵌套本地固定数组扩展到扁平结构体叶节点，将每个嵌套元素字段展开为确定性的 Yul 本地变量，支持静态和动态嵌套字段读取、嵌套可变字段赋值、数值嵌套字段复合赋值、从本地数组和自引用嵌套数组字面量进行整体嵌套本地赋值（带 RHS 快照）、动态越界回滚、更新后的 `EvmStructArrayValueProbe` 黄金 Yul、制品元数据入口验证、solc 字节码生成、Foundry 运行时检查以及覆盖率清单更新。
- 已完成：为标量存储结构体和扁平结构体的固定存储数组添加 EVM IR 扁平存储结构体降级，包括直接结构体字段副作用、标量 `field` 存储路径、数组 `index`+`field` 存储路径、数值字段复合赋值、带 RHS 快照的整体标量存储结构体读/写、存储后端支持的 ABI 结构体返回、`Bool`/`U32`/`Hash` 字段覆盖、`EvmStorageStructProbe` 黄金 Yul、solc 字节码、Foundry 运行时/原始插槽验证、制品元数据能力验证、CI 覆盖率，以及针对缺失字段和非扁平存储结构体的显式诊断。
- 已完成：通过在存储数组元素读取上扩展带 `return_values()` 的 `EvmStorageArrayProbe`，以及在固定结构体存储数组字段读取上扩展带 `return_points()` 的 `EvmStorageStructProbe`，验证 EVM IR 的存储后端聚合 ABI 返回，包括黄金 Yul、solc 字节码、制品元数据选择器验证、Foundry ABI 解码和原始插槽检查。
- 已完成：为固定数组和结构体参数/返回添加 EVM IR 静态聚合 ABI 降级，包括嵌套标量固定数组和扁平结构体的固定数组，具有 calldata 字扁平化、`U32`/`Bool` 聚合字保护、多字返回数据编码、`EvmAbiAggregateProbe` 黄金 Yul、solc 字节码、Foundry 运行时/畸形 calldata 验证、制品元数据能力验证、结构化 `abi.entrypoints` 选择器/calldata/返回字布局验证、CI 覆盖率，以及针对 Unit、零长度数组、非扁平结构体字段和仅限 crosscall 的不支持嵌套固定数组叶形状的显式诊断。
- 已完成：填补 `Hash` 叶节点的 EVM 聚合 ABI 验证空白。`HashPair(bytes32,bytes32)`、`pick_hash(bytes32[2])` 和 `make_hash_array(bytes32,bytes32)` 现在证明 `Hash`/`bytes32` 字段和固定数组通过 calldata 和返回数据编码进行扁平化，并包含黄金 Yul、制品元数据选择器检查、`solc`、Foundry ABI 解码以及短 `bytes32[2]` calldata 拒绝。
- 已完成：为 SDK EVM 示例（`Counter`、`ArrayExample`、`SimpleToken`、`ERC20`、`Ownable`、`Pausable` 和 `VerifiedVault`）添加黄金 Yul 输出，并使 `scripts/evm/build-examples.sh` 在验证制品元数据之前将生成的 Yul 与这些固定装置进行差异对比。- 已完成：围绕当前的 `solc --strict-assembly` 流程，为 SDK 和可移植 IR EVM 字节码构建添加制品元数据发射与验证。
- 保留 Foundry 冒烟测试作为成熟的 EVM 冒烟测试。

验收标准：

- `lake build` 通过。
- `scripts/evm/diagnostic-smoke.sh` 通过。
- `scripts/evm/check-ir-coverage-manifest.py` 通过。
- `scripts/evm/build-examples.sh` 在装有 `solc` 的机器上成功运行。
- `scripts/evm/foundry-smoke.sh` 在装有 Foundry 的机器上成功运行。
- 生成的元数据指向字节码制品并记录 `target: evm`。

## 工作流 4：Wasm 宿主运行时拆分

目标：使 Wasm 宿主适配器由目标驱动，而不是假设每个 Wasm 合约都是 NEAR。

任务：

- 将链 extern 声明移出通用的 EmitZig 运行时 extern。
- 添加一个由目标选择的宿主桥接列表。
- 保留 NEAR 桥接作为参考实现。
- 添加一个带有分配器和 region ABI 的 CosmWasm 桥接骨架。

验收标准：

- Wasm 构建可以显式选择 NEAR 或 CosmWasm 桥接。
- 通用 Wasm 运行时不会强制链接 NEAR 宿主函数。
- `wasm-near` 和 `wasm-cosmwasm` 可以拥有不同的必需导出。

## 工作流 5：CosmWasm Spike

目标：证明 ProofForge 可以针对 NEAR 之外的其他 Wasm 宿主。

任务：

- 添加 `Lean.CosmWasm` SDK 骨架（参见 [wasm-family.md](targets/wasm-family.md)）。
- 添加 `zigc-cosmwasm` 包装器。
- 添加 `cosmwasm_contract_root.zig`。
- 导出 `interface_version_8`、`allocate`、`deallocate`、`instantiate`、`execute` 和 `query`。
- 添加使用 JSON 支持的消息的 Counter 示例。
- 添加 `cosmwasm-check` 冒烟测试。

验收标准：

- Counter Wasm 通过 `cosmwasm-check`。
- `instantiate`、`execute` 和 `query` 存在于导出中。
- 冒烟测试可以增加并查询计数器状态。

## 工作流 6：Solana sBPF 汇编工具链集成（阶段 0）

目标：端到端验证直接汇编路线 —— 一个预制的 `.s` 文件通过 blueshift-gg/sbpf 工具链往返转换成可加载的 ELF。取代旧的 sbpf-linker spike (D-026)。

任务：

- 通过 `cargo install --git https://github.com/blueshift-gg/sbpf.git` 安装 `sbpf`。
- 在 `proof-forge` 中添加 `--emit-sbpf-asm` CLI 模式，用于写入预制的 `entrypoint.s`（返回成功，无账户解析）。
- 在预制的 `.s` 上运行 `sbpf build`；验证是否生成了有效的 eBPF ELF。
- 验证 `sbpf disassemble` 对 ELF 进行往返转换。
- 在制品元数据中记录工具链版本。

验收标准：

- [x] `sbpf build` 生成被识别为 `ELF 64-bit LSB ... eBPF` 的 `.so`。
- [x] `sbpf disassemble` 生成与输入匹配的汇编。
- [x] `--emit-sbpf-asm` 写入有效的 `.s` 且无汇编错误。
- [x] `proof-forge-artifact.json` 记录 `target: "solana-sbpf-asm"`。
- [x] `sbpf` 通过 `cargo install` 安装到 PATH。

参考：[solana-sbpf-asm 设计文档](targets/solana-sbpf-asm.md)，[RFC 0005](rfcs/0005-solana-sbpf-assembly-backend.md)。

## 工作流 7：Solana sBPF 汇编 Counter 源代码生成（阶段 1）

目标：将可移植 IR Counter 模块降级为 sBPF 汇编并通过 `sbpf test`。这是汇编路线的第一个真实源代码生成后端。

任务：

- 实现 `ProofForge.Backend.Solana.StateLayout` —— 从指令清单计算每个账户的字段偏移量；发射 `.equ` 常量。
- 实现 `ProofForge.Backend.Solana.SbpfAsm` —— 将 `IR.Module` 降级为 `.s`：
  - 入口适配器：解析序列化的账户，根据指令判别式进行分发。
  - 账户验证：根据清单进行签名者、可写性、所有者检查。
  - 表达式降级：字面量、局部变量、加/减、比较、转换。
  - 语句降级：letBind、赋值、赋值操作、ifElse、返回、断言。
  - Effect 降级：在账户数据偏移处进行 storageScalar 读/写。
- 添加 `--solana-elf` CLI 模式：发射 `.s` 然后调用 `sbpf build`。
- 在生成 `.s` 的同时生成指令清单 (`manifest.toml`)。
- 创建 `Examples/Solana/Counter.lean` + 清单。
- 运行 `sbpf test` (Mollusk) 以及 Surfpool/Web3.js 实时部署冒烟测试。

验收标准：- Counter 场景（初始化、增加、获取）通过 `sbpf test`。
- Surfpool/Web3.js 实时冒烟测试通过（可选，取决于工具可用性）。
- 能力检查器拒绝使用不支持的能力的 IR 模块，并提供引用目标 id 和能力 id 的清晰诊断信息。
- 同一个可移植 IR Counter 模块降级到 EVM 和 Solana。
- 制品元数据记录 `target: "solana-sbpf-asm"`、`irVersion`、入口以及使用的能力。

超出范围（阶段 2+）：map、结构体类型、事件、有界循环、Borsh 序列化、完整的 SPL Token 数据布局、完整的实时 CPI 矩阵覆盖以及 Rust/Pinocchio 等效性。CPI 和 PDA 保持 Solana 特定 (D-027)：SDK 通过目标能力调用和 sBPF 辅助操作路由它们，而不是将它们添加到可移植 IR 中。

参考：[solana-sbpf-asm design doc](targets/solana-sbpf-asm.md) § 分阶段实施计划。

### 阶段 1 进展（增量子项）

工作流 7 阶段 1 后端 (`ProofForge.Backend.Solana.SbpfAsm`) 增量落地。每个子项都带有自己的可运行验证门禁，以便在完整验收标准关闭之前看到部分进展：- [x] IR → sBPF AST → 文本流水线；入口适配器根据第一个指令数据字节进行分发 (V-GATE-SOLANA-01/02; Phase 0 baseline)。
- [x] Counter 源代码生成 (字面量, 局部变量, `add`, 标量存储读/写/`assignOp`, `letBind`/`letMutBind`, `assign`, `return`)；Mollusk 冒烟测试覆盖 initialize / increment 0→1 / increment 5→6 / get→return_data (V-GATE-SOLANA-03)。
- [x] 控制流 + 断言覆盖：比较表达式 (`.eq`/`.ne`/`.lt`/`.le`/`.gt`/`.ge`)，布尔表达式 (`.boolAnd`/`.boolOr`/`.boolNot`)，带有新的命名标签的语句级 `.ifElse` then/else 降级，`.assert` 和 `.assertEq` 降级到共享的 `assert_fail` (exit 2) / `assert_eq_fail` (exit 3) 标签。测试夹具：`ProofForge.IR.Examples.ControlFlowAssertProbe` (三个入口：`lifecycle`, `guarded_increment`, `equality_guard`)；CLI 模式 `--emit-control-ir-sbpf`；确定性发射门控 `scripts/solana/emit-control-smoke.sh` (不需要 `sbpf`)；Mollusk 运行时门控 `scripts/solana/control-smoke.sh` (六项检查：lifecycle x2, guarded_increment 成功 + assert revert, equality_guard 成功 + assertEq revert) (V-GATE-SOLANA-08)。
- [x] 指令清单 (`manifest.toml`) 与 `.s` 一同生成。`ProofForge.Backend.Solana.SbpfAsm.renderManifest` 发射一个包含目标、程序占位符 id 以及使用 Phase 1 默认账户惯例 (writable, signer=false, owner=program) 的每个入口指令表的 TOML。`--emit-counter-ir-sbpf` 和 `--emit-control-ir-sbpf` 在 `.s` 旁边写入 `manifest.toml` 并将其作为制品包含在内。
- [x] `--solana-elf` CLI 模式：发射 `.s`，写入 `manifest.toml`，脚手架化一个 `sbpf` 项目，调用 `sbpf build`，将生成的 `.so` 复制到请求的输出，并在制品元数据中记录 `sbpfBuild: passed`。
- [x] 账户验证：根据清单进行 signer / writable / owner 检查。每个入口发射一段序言，检查账户头部偏移量 10 处的 `is_writable`，并验证账户所有者等于序列化的程序 id。失败退出码为 4 (`error_not_writable`), 5 (`error_signer`), 和 6 (`error_owner`)。Phase 1 Mollusk 运行时门控禁用了直接账户映射 ABI，因此遗留的嵌入式账户数据布局得到了测试。
- [x] `Examples/Solana/Counter.lean` + 清单作为一个自包含示例。包括一个被追踪的 `Counter.golden.s` 和 `Counter.manifest.toml`，以及一个可在 CI 运行的、进行发射和差异对比的 `scripts/solana/build-examples.sh`。
- [x] 能力检查器拒绝不支持的能力/目标组合，并提供引用目标 id 和能力 id 的清晰诊断信息。作为 V-GATE-SOLANA-05 的基础；通过 `Tests/SolanaDiagnostics.lean` 和 `scripts/solana/diagnostic-smoke.sh` 进行测试。
- [x] Solana SDK 目标扩展通过能力计划元数据路由 `ProofForge.Solana` PDA/CPI API，发射 `manifest.toml` 扩展定义以及入口动作部分，并在 IR 主体之前注入处理程序级辅助调用 (`sol_pda_derive_<name>`, `sol_cpi_<name>`)，同时在 `r1` 中保留 Solana 输入指针。由 `Tests/SolanaSdk.lean`, `Tests/SolanaSdkManifest.lean` 以及可用时的 `scripts/solana/sdk-smoke.sh` 与 `sbpf build` 覆盖。
- [x] Surfpool/Web3.js 线上部署冒烟测试 (V-GATE-SOLANA-04)。可选的 `scripts/solana/surfpool-web3-smoke.sh` 门控构建 Counter ELF，启动 Surfpool，使用 Solana CLI 进行部署，通过 `@solana/web3.js` 创建一个程序所有的 counter 账户，调用 initialize/increment/get，检查账户数据 0→1→2，并验证 `get` 返回数据。该脚本传递 `--solana-sbpf-arch v0` 以直接生成与 Solana CLI 部署兼容的 ELF，并为 Surfpool 使用 `--use-rpc`。
- [x] `--solana-elf` 暴露了 `--solana-sbpf-arch v0|v3` 并在 `proof-forge-artifact.json` 中记录选择的架构。默认保持为 `v3`；Surfpool 线上部署使用 `v0`，直到部署的 CLI/运行时堆栈在没有 `--skip-feature-verify` 的情况下接受较新的 sbpf 特性集。- [x] PDA 辅助运行时打包现在在调用 `sol_create_program_address` 之前发射静态 ASCII 种子字节缓冲区、Solana `Slice { ptr, len }` 种子表、动态 program-id 指针计算以及一个 32 字节 PDA 结果缓冲区。由 `Tests/SolanaSdkManifest.lean` 和 `scripts/solana/sdk-smoke.sh` 覆盖。
- [x] PDA 类型化种子降级现在保留兼容性 `seeds` 字段，同时为字面量/UTF-8 字节、账户 pubkeys、bump 种子和标量指令数据种子添加面向目标的类型化描述符。Solana 目标扩展处理这些描述符，将 `bump?` 追加到有效 syscall 种子列表，在 manifest/制品元数据中发射 `typed_seeds`/`typedSeeds`，并在 `account?` 存在时根据声明的账户验证派生的 PDA pubkey。由 `Tests/SolanaSdk.lean`、`Tests/SolanaSdkManifest.lean`、`Tests/SolanaPdaSeeds.lean`、`scripts/solana/sdk-smoke.sh` 和 `scripts/solana/pda-web3-smoke.sh` 覆盖。
- [x] 标准 Solana 协议 SDK 辅助程序现在涵盖系统程序 (System Program) 转账/创建账户以及 SPL Token transfer_checked/mint_to/burn/approve/revoke/close_account/set_authority。它们通过带有 `solana.cpi.protocol`、规范 `data_layout`、账户元数据 (account metas)、签名者种子和指令数据源名称的目标能力元数据进行路由，并包含在生成的 manifest 以及制品 JSON 中。由 `Tests/SolanaSdk.lean`、`Tests/SolanaSdkManifest.lean`、`Tests/SolanaCpiPacking.lean` 和 `scripts/solana/sdk-smoke.sh` 覆盖。
- [x] 运行时分配器目标扩展现在建模 Solana 默认的向下增长 bump 分配器 (`heap_start = "0x300000000"`, `heap_bytes = 32768`)，以及一个与 Pinocchio 风格无堆入口对齐的 `noAllocator`/deny-dynamic 选项。所选分配器通过 `runtime.allocator` 能力元数据路由，并出现在 `manifest.toml`、`proof-forge-artifact.json` 和汇编元数据中。由 `Tests/SolanaAllocator.lean`、`Tests/SolanaSdk.lean`、`Tests/SolanaSdkManifest.lean` 和 `scripts/solana/sdk-smoke.sh` 覆盖。
- [x] 运行时内存目标扩展现在通过 `runtime.memory` 能力元数据路由仅限 Solana 的 SDK 操作，并将入口操作降级为基于生成的状态账户偏移量的 `sol_memcpy_`、`sol_memcmp_` 和 `sol_memset_` 辅助程序。生成的 manifest 和制品 JSON 记录 `[[solana.entrypoint_memory]]` / `memoryActions`；Web3.js 在程序拥有的账户上验证复制的字节、比较结果和填充模式。由 `Tests/SolanaMemory.lean` 和 `scripts/solana/memory-web3-smoke.sh` 覆盖。
- [x] 返回数据和计算预算目标扩展现在通过 `runtime.return_data` 和 `runtime.compute_units` 能力元数据路由仅限 Solana 的 SDK 操作。返回数据操作将状态支持的字节切片降级为 `sol_set_return_data`，并可以通过 `sol_get_return_data` 读取最近的 CPI 返回数据缓冲区/程序 id；计算预算操作降级受特性门控的 `sol_remaining_compute_units` syscall 并将观察到的剩余 CU 值写入状态，分析操作则降级 `sol_log_compute_units_`。生成的 manifest 记录 `[[solana.entrypoint_return_data]]` 和 `[[solana.entrypoint_compute_units]]`。由 `Tests/SolanaReturnDataCompute.lean` 覆盖。
- [x] 生成的 Solana SDK 指令 schema 现在使用模块范围的多账户列表，而不是旧的单账户 manifest。该 schema 包含状态账户、PDA 账户、CPI 账户和可执行 CPI 程序账户，且 sBPF 后端根据相同的 schema 计算 `INSTRUCTION_DATA` 偏移量。生成的 prologue 根据 schema 验证签名者/可写约束以及程序拥有的账户。账户列表在 `manifest.toml` 和 `proof-forge-artifact.json` 中均被发射。由 `Tests/SolanaSdkManifest.lean`、`Tests/SolanaCpiPacking.lean` 和 `scripts/solana/sdk-smoke.sh` 覆盖。
- [x] 系统程序 (System Program) 转账/创建账户和 SPL Token CPI 指令数据打包将标准指令字节发射到 C `SolInstruction` 负载中。系统转账/创建账户使用 bincode 风格的 `u32` 鉴别器以及 `u64` lamports/space 和所有者 pubkey 字段；SPL Token `transfer_checked`、`mint_to`、`burn`、`approve` 和 `revoke` 使用标准代币指令标签和金额/精度布局，`close_account` 封装指令标签 `9`，而 `set_authority` 封装了指令标签 `6`、权限类型 `MintTokens` 以及源自只读输入账户的新权限公钥。值源可以绑定到生成的标量状态偏移量、数字字面量或解码后的标量入口参数。CPI 助手还封装了程序 id 字节、绑定到生成的多账户输入布局的 C `SolAccountMeta[]`、`SolAccountInfo[]` 条目、签名者种子表以及系统调用寄存器设置。由 `Tests/SolanaCpiPacking.lean`、`Tests/SolanaSdkManifest.lean` 和 `scripts/solana/sdk-smoke.sh` 覆盖。
- [x] System Program transfer CPI 现在具有活跃的 Surfpool/Web3.js 行为门控。`ProofForge.Solana.Examples.SystemCpi` 构建了一个生成的 `--solana-system-cpi-elf` fixture，其入口读取标量 `lamports` 指令参数，执行 System Program transfer CPI，并将转账金额记录在程序拥有的状态账户中。`scripts/solana/system-cpi-web3-smoke.sh` 验证制品架构，使用 Solana CLI 在 Surfpool 上部署 ELF，通过 `@solana/web3.js` 调用它，并检查接收者的 lamport 增量和状态数据。sBPF 降级在直接账户映射下从序列化的账户布局计算指令数据指针，并将其保留在 `r9` 中，以便内部助手调用不会在被调用者堆栈帧之间丢失它。覆盖范围：`just solana-system-cpi-web3` / V-GATE-SOLANA-10。
- [x] System Program `create_account` CPI 现在具有活跃的 Surfpool/Web3.js 行为门控。`ProofForge.Solana.Examples.SystemCreateAccountCpi` 构建了一个生成的 `--solana-system-create-account-cpi-elf` fixture，其入口读取标量 `lamports` 和 `space` 指令参数，使用付款人和新账户签名者执行 System Program `create_account` CPI，创建一个程序拥有的账户，并将这两个值记录在现有的程序拥有的状态账户中。Web3.js harness 检查新账户所有者、数据长度、lamports 和记录的状态值。覆盖范围：`just solana-system-create-account-cpi-web3` / V-GATE-SOLANA-11。
- [x] SPL Token `transfer_checked` CPI 现在具有活跃的 Surfpool/Web3.js 行为门控。`ProofForge.Solana.Examples.SplTokenTransferCheckedCpi` 构建了一个生成的 `--solana-spl-token-transfer-cpi-elf` fixture，其入口读取标量 `amount` 指令参数，使用源权限签名者执行 SPL Token `transfer_checked` CPI，并将金额记录在程序拥有的状态中。Web3.js harness 通过 `@solana/spl-token` 创建一个 mint 以及源/目标代币账户，检查代币余额增量，并检查状态记录。sBPF 降级现在在每个入口/助手堆栈帧中构建一个运行时账户指针表，因此可变大小的 SPL Token 账户数据不会使内部助手调用之间的账户偏移量失效。覆盖范围：`just solana-spl-token-transfer-cpi-web3` / V-GATE-SOLANA-12。
- [x] 入口指令数据解码现在将第 0 字节视为入口标签，并将来自 `instruction_data+1` 的封装标量参数解码为堆栈局部变量。初始标量 ABI 支持 `U64`、`U32` 和 `Bool`，在 `manifest.toml`/`proof-forge-artifact.json` 中发射每个入口的参数架构和最小指令数据长度，使用 `error_instruction_data` 拒绝短有效载荷，并向 CPI 值绑定公开相同的固定输入偏移量，因此诸如 SPL Token `transfer_checked` 之类的 SDK 调用可以从用户指令参数而不是占位符中获取 `amount`。由 `Tests/SolanaCpiPacking.lean`、`Tests/SolanaSdkManifest.lean` 和 `scripts/solana/sdk-smoke.sh` 覆盖。

### Solana SDK 完成路线图

推动此路线图的参考文档：- Solana CPI 和 PDA 文档：
  <https://solana.com/docs/core/cpi> 和
  <https://solana.com/docs/core/pda>。
- Anchor CPI/账户约束文档：
  <https://www.anchor-lang.com/docs/basics/cpi> 和
  <https://www.anchor-lang.com/docs/references/account-constraints>。
- Pinocchio 无依赖 / no-std 程序模型：
  <https://docs.rs/pinocchio> 和
  <https://github.com/anza-xyz/pinocchio>。

基准：截至 2026-07-02，Solana 路径已具备直接 sBPF 汇编发射能力，通过 Surfpool/Web3.js 进行 Counter 部署、SDK 能力元数据、生成的 manifest/制品输出、模块级多账户 schema、标准 System/SPL Token CPI 数据打包、bump-allocator 元数据、标量入口参数解码、类型化 PDA seed 降级、实时 System Program 转账及 create-account CPI 验证、实时 SPL Token `transfer_checked` CPI 验证、实时 SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI 验证，以及实时 SPL Token `set_authority` CPI 验证，加上通过 `sol_log_64_` 进行的实时标量 `events.emit` 日志验证、通过 `sol_log_pubkey` 进行的实时账户公钥日志验证、通过 `sol_log_data` 进行的实时状态支持数据日志验证，以及针对 `contextRead checkpointId` 的实时 `Clock.slot` sysvar 验证，加上通过 `sol_memcpy_`、`sol_memmove_`、`sol_memcmp_` 和 `sol_memset_` 进行的实时 `runtime.memory` 验证，加上通过 `sol_sha256`、`sol_keccak256` 和特性门控的 `sol_blake3` 进行的实时仅限 Solana 的 `crypto.hash` 验证，以及通过 `sol_get_rent_sysvar` 进行的实时 `Rent.lamports_per_byte_year` sysvar 验证。它还涵盖了通过 `sol_get_epoch_schedule_sysvar` 对所有当前 RPC 暴露的 `EpochSchedule` 字段的实时验证：`slots_per_epoch`、`leader_schedule_slot_offset`、`warmup`、`first_normal_epoch` 和 `first_normal_slot`，加上通过 `sol_get_epoch_rewards_sysvar` 对 `distribution_starting_block_height`、`num_partitions`、`parent_blockhash_word0..3`、`total_points_low/high`、`total_rewards`、`distributed_rewards` 和 `active` 进行的实时 `EpochRewards` 验证，加上通过带有 `SysvarLastRestartS1ot1111111111111111111111` sysvar id 的 `sol_get_sysvar` 进行的特性门控实时 `LastRestartSlot.last_restart_slot` 验证。实时 SDK 覆盖范围现在包括将 `runtime.return_data` 降级为 `sol_set_return_data` 和 `sol_get_return_data`，并带有空读取、设置返回模拟以及同指令设置/获取往返检查，以及将 `runtime.compute_units` 降级为特性门控的 `sol_remaining_compute_units` 状态写入，并通过 `sol_log_compute_units_` 进行分析日志记录。以下预估假设有一名工程师在该分支上工作，当前的直接汇编架构保持稳定，且本地 `sbpf`/Surfpool/Solana CLI 工具链持续可用。

| 级别 | 预估工作量 | 完成标准 |
|---|---:|---|
| SDK alpha：可用的 Solana 程序 | 3-5 个专注工程日 | 简单程序可以使用状态、PDA seed、标量指令参数、System Program CPI、SPL Token CPI、日志/返回数据，并进行 Web3.js 行为测试，无需手动编写汇编补丁。 |
| SDK beta：可参照的 Solana 后端 | 2-3 个专注周 | ProofForge 输出与相同账户 schema 的 Rust/Pinocchio fixtures 进行对比，涵盖关键 syscall，验证实时 CPI 行为，并支持每个入口的账户 schema。 |
| Anchor/Pinocchio 级别的开发者界面 | beta 之后 4-6 个专注周 | SDK 提供账户约束、类型化账户/数据辅助工具、IDL/客户端生成、更丰富的 SPL/Token-2022 覆盖，以及可与框架级工作流相媲美的稳定诊断。 |

已完成的 alpha 切片：- 指令 ABI 硬化：参数有效载荷长度边界检查、`manifest.toml` 和 `proof-forge-artifact.json` 中每个入口的参数 schema 以及稳定的标量参数元数据现已就绪。
- PDA 类型化种子降级：`literalSeed`/`utf8Seed`、`accountSeed`、`bumpSeed` 和 `paramSeed` 描述符现在降级为 Solana 种子切片，`bump?` 参与有效种子列表，并且可以根据派生的公钥检查声明的 PDA 账户。
- PDA/Web3.js 派生测试固件：`scripts/solana/pda-web3-smoke.sh` 读取生成的 SDK Vault `typedSeeds` 制品数据，并根据 `PublicKey.findProgramAddressSync` 和 `PublicKey.createProgramAddressSync` 验证字面量/账户/bump 描述符语义；该 harness 还涵盖了 UTF-8 和指令参数解析器行为。
- 实时 System Program 转账 CPI 测试固件：`scripts/solana/system-cpi-web3-smoke.sh` 在 Surfpool 上构建并部署生成的转账 CPI 程序，通过 Web3.js 调用它，并证明 lamport 转移和状态写入。
- 实时 System Program 创建账户 CPI 测试固件：`scripts/solana/system-create-account-cpi-web3-smoke.sh` 在 Surfpool 上构建并部署生成的创建账户 CPI 程序，通过 Web3.js 调用它，并证明新账户的所有者/空间/lamports 以及状态写入。
- 实时 SPL Token transfer-checked CPI 测试固件：`scripts/solana/spl-token-transfer-cpi-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 transfer_checked CPI 程序，使用 `@solana/spl-token` 创建 SPL Token 测试账户，通过 Web3.js 调用它，并证明源/目标代币余额增量以及状态写入。
- 实时 SPL Token 操作 CPI 测试固件：`scripts/solana/spl-token-ops-cpi-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 `mint_to`/`burn`/`approve`/`revoke` CPI 程序，验证生成的四入口制品 schema，使用 `@solana/spl-token` 创建 SPL Token 测试账户，通过 Web3.js 调用所有四个生成的入口，并证明供应量/余额/委托更改以及状态写入。
- 实时 SPL Token 权限 CPI 测试固件：`scripts/solana/spl-token-authority-cpi-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 `set_authority` CPI 程序，验证生成的单入口制品 schema，通过 `@solana/spl-token` 创建 SPL Token mint，通过 Web3.js 调用生成的入口，并证明铸币权限已转移到请求的新权限以及标记状态写入。
- 实时标量事件、公钥日志和数据日志测试固件：`scripts/solana/log-event-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 `events.emit` 程序，通过 Web3.js 调用它，验证生成的 `sol_log_64_` 交易日志包含稳定的 `AmountEvent` 标签和标量 `amount` 字段，并证明程序拥有的状态账户记录了相同的值。同一测试固件现在还验证仅限 Solana 的 `logAccountPubkey` 元数据，调用生成的 `log_state_pubkey` 入口，并证明 `sol_log_pubkey` 记录了状态账户的 base58 公钥。它还验证仅限 Solana 的 `logStateData` 元数据，调用 `log_state_data`，并证明 `sol_log_data` 为状态支持的 `amount` 字节发射一个 base64 `Program data:` 有效载荷。
- 实时 Clock sysvar 测试固件：`scripts/solana/clock-sysvar-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 `contextRead checkpointId` 程序，将其降级为 `sol_get_clock_sysvar`，通过 Web3.js 调用它，并证明记录的 `Clock.slot` 与观察到的交易槽位匹配。
- 实时内存系统调用测试固件：`scripts/solana/memory-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 `runtime.memory` 程序，通过 Web3.js 调用它，并通过从程序拥有的状态中读取复制的值、移动的值、比较结果和填充字节，证明 `sol_memcpy_`、`sol_memmove_`、`sol_memcmp_` 和 `sol_memset_` 的效果。
- 返回数据/计算单元 SDK 测试固件：`Tests/SolanaReturnDataCompute.lean` 证明 `runtime.return_data` 和 `runtime.compute_units` 通过仅限 Solana 的能力元数据路由，在 EVM 上拒绝，并为 `sol_set_return_data`、`sol_get_return_data`、特性门控的 `sol_remaining_compute_units` 和 `sol_log_compute_units_` 渲染清单部分以及 sBPF 辅助调用。 `scripts/solana/return-data-compute-web3-smoke.sh` 在 Surfpool 上构建并部署生成的 `--solana-return-data-compute-elf` 测试固件，验证制品 action 元数据，验证无数据的 `sol_get_return_data` 读取，
  通过 Web3.js 模拟 returnData 确认 `sol_set_return_data`，检查一个
  包含 program id 字的同指令 set/get 往返，记录一个
  非零的 remaining-compute-units 值，并确认 compute-unit 日志记录。
- 实时 SHA-256/Keccak-256/Blake3 syscall fixture：
  `scripts/solana/crypto-hash-web3-smoke.sh` 在 Surfpool 上构建并部署一个生成的
  仅限 Solana 的 `crypto.hash` 程序，通过 Web3.js 调用 `set_preimage`、
  `hash_preimage`、`keccak_preimage` 和 `blake3_preimage`，并
  证明账户存储的 32 字节摘要与相同小端序
  原像的 Node SHA-256 和 `@noble/hashes` Keccak-256/Blake3 参考值匹配。Blake3 action 在 manifest 和
  制品元数据中被记录为 feature-gated。
- 实时 Rent sysvar fixture：`scripts/solana/rent-sysvar-web3-smoke.sh` 在
  Surfpool 上构建并部署一个生成的仅限 Solana 的 `sysvar` 目标扩展程序，
  通过 Web3.js 调用 `record_rent`，并证明记录的
  `Rent.lamports_per_byte_year` 与 Rent sysvar 账户数据匹配。
- 实时 EpochSchedule sysvar fixture：
  `scripts/solana/epoch-schedule-sysvar-web3-smoke.sh` 在 Surfpool 上构建并部署一个
  生成的仅限 Solana 的 `sysvar` 目标扩展程序，通过 Web3.js 调用
  `record_epoch_schedule`，并证明记录的
  `EpochSchedule.slots_per_epoch`、
  `EpochSchedule.leader_schedule_slot_offset`、`EpochSchedule.warmup`、
  `EpochSchedule.first_normal_epoch` 和 `EpochSchedule.first_normal_slot`
  与 RPC `getEpochSchedule()` 字段匹配。
- 实时 EpochRewards sysvar fixture：
  `scripts/solana/epoch-rewards-sysvar-web3-smoke.sh` 在 Surfpool 上构建并部署一个
  生成的仅限 Solana 的 `sysvar` 目标扩展程序，通过 Web3.js 调用
  `record_epoch_rewards`，并证明
  `sol_get_epoch_rewards_sysvar` 将 `EpochRewards` 字段记录到状态中。
  `parent_blockhash` 被公开为四个小端序 `u64` 字视图，且
  `total_points` 被公开为低/高 `u64` 字视图，直到可移植
  标量层拥有一等宽值输出状态。
- 实时 LastRestartSlot sysvar fixture：
  `scripts/solana/last-restart-slot-sysvar-web3-smoke.sh` 在 Surfpool 上构建并部署一个
  生成的仅限 Solana 的 `sysvar` 目标扩展程序，通过 Web3.js 调用
  `record_last_restart_slot`，并证明 feature-gated
  `LastRestartSlot.last_restart_slot` 读取通过 `sol_get_sysvar` 降级并
  与 LastRestartSlot sysvar 账户数据匹配。该 action 在 manifest 和制品元数据中被标记为
  `feature_gated`。

已完成的 beta scaffolding 分片：- Pinocchio System 转账参考合约：
  `references/solana/pinocchio/system-transfer` 包含一个已签入的 no-allocator Pinocchio 参考，用于与 `ProofForge.Solana.Examples.SystemCpi` 相同的 System 转账账户 schema。Gate `scripts/solana/pinocchio-system-transfer-equivalence.sh` 发射 ProofForge System CPI 制品，并将其指令标签、参数 ABI、账户顺序、签名者/可写约束、CPI 协议/数据布局以及状态写入合约与参考清单/源代码进行比较。
- Pinocchio System 转账实时等效性测试框架：
  `scripts/solana/pinocchio-system-transfer-live-equivalence.sh` 被配置为构建 ProofForge ELF 和已签入的 Pinocchio 参考 ELF，将这两个程序部署到一个 Surfpool 实例，分别为每个程序调用相同的 Web3.js 转账场景，并比较接收者 lamport 增量以及状态写入。当 `cargo-build-sbf` 找不到 Solana rustc/platform-tools 时，该测试框架目前会跳过。
- Solana loader-compatible ELF packaging 阻塞：
  2026-07-03 本地运行 `just solana-pinocchio-live-equivalence` 时，Surfpool、
  Agave `solana-cli 3.1.12`、`cargo-build-sbf 3.1.12` 和 `sbpf 0.2.2`
  都已安装，但五个 live dual-deploy 子 gate 全部在 ProofForge 程序部署阶段失败。
  `solana program deploy --use-rpc` 在部署 Pinocchio 参考程序和执行 Web3.js 行为检查之前，
  就以 `Failed to parse ELF file: invalid file header` 拒绝生成的 ProofForge ELF。
  triage 显示，当前 blueshift `sbpf build --arch v0` 输出的是一个只有单个 segment、
  没有 section table、且 `e_flags = 3` 的裸 ELF；Agave 内置的
  `solana-sbpf 0.13.1` strict loader 需要 Solana-compatible 的 v3 layout：
  `EM_SBPF`、四个 program header、有效的 section-header index，以及 function-start markers。
  将这些字节硬改成 legacy v0 也不正确，因为字节码随后会在 relocation 阶段报
  `RelativeJumpOutOfBounds`。所以下一个实现切片必须是显式的 Solana CLI loader
  兼容路径：要么通过标准 Solana platform-tools 格式进行 emit/package，要么扩展当前
  direct assembler pipeline，生成 Agave 可接受的 strict v3 header 和 function markers。
- Pinocchio System 创建账户参考合约：
  `references/solana/pinocchio/system-create-account` 包含一个已签入的 no-allocator Pinocchio 参考，用于与 `ProofForge.Solana.Examples.SystemCreateAccountCpi` 相同的 System Program `create_account` 账户 schema。Gate `scripts/solana/pinocchio-system-create-account-equivalence.sh` 发射 ProofForge 创建账户 CPI 制品，并将其指令标签、双参数 ABI、账户顺序、签名者/可写约束、CPI 协议/数据布局、lamports/空间/所有者合约以及双字段状态写入合约与参考清单/源代码进行比较。通过 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`，同一个 gate 会根据 `pinocchio-system` 对参考进行类型检查。
- Pinocchio System 创建账户实时等效性测试框架：
  `scripts/solana/pinocchio-system-create-account-live-equivalence.sh` 被配置为构建 ProofForge ELF 和已签入的 Pinocchio 参考 ELF，将这两个程序部署到一个 Surfpool 实例，分别为每个程序调用相同的 Web3.js 创建账户场景，并比较 lamports/空间输入以及两者的状态写入。当 `cargo-build-sbf` 找不到 Solana rustc/platform-tools 时，该测试框架目前会跳过。
- Pinocchio SPL Token 转账参考合约：
  `references/solana/pinocchio/spl-token-transfer` 包含一个已签入的 no-allocator Pinocchio 参考，用于与 `ProofForge.Solana.Examples.SplTokenTransferCheckedCpi` 相同的 SPL Token `transfer_checked` 账户 schema。Gate `scripts/solana/pinocchio-spl-token-transfer-equivalence.sh` 发射 ProofForge SPL Token CPI 制品，并将其指令标签、参数 ABI、账户顺序、签名者/可写约束、CPI 协议/数据布局、精度/金额合约以及状态写入合约与参考清单/源代码进行比较。通过 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`，同一个 gate 会根据 `pinocchio-token` 对参考进行类型检查。
- Pinocchio SPL Token 转账实时等效性测试框架：
  `scripts/solana/pinocchio-spl-token-transfer-live-equivalence.sh` 被配置为构建 ProofForge ELF 和已签入的 Pinocchio Token 参考 ELF，将这两个程序部署到一个 Surfpool 实例，分别为每个程序调用相同的 Web3.js + `@solana/spl-token` transfer_checked 场景，并比较源/目标代币余额增量以及金额状态写入。当 `cargo-build-sbf` 找不到 Solana rustc/platform-tools 时，该测试框架目前会跳过。
- Pinocchio SPL Token 操作参考合约：
  `references/solana/pinocchio/spl-token-ops` 包含一个已签入的 no-allocator Pinocchio 参考，用于与 `ProofForge.Solana.Examples.SplTokenOpsCpi` 相同的 SPL Token `mint_to`/`burn`/`approve`/`revoke` 账户 schema。Gate `scripts/solana/pinocchio-spl-token-ops-equivalence.sh` 发射 ProofForge SPL Token 操作 CPI 制品，并将其四个指令标签、参数 ABI、账户顺序、签名者/可写约束、CPI 协议/数据布局、SPL Token 指令合约以及状态写入合约与参考清单/源代码进行比较。通过 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`，同一个 gate 会根据 `pinocchio-token` 对参考进行类型检查。
- Pinocchio SPL Token 操作实时等效性测试框架：
  `scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh` 被配置为构建 ProofForge ELF 和已签入的 Pinocchio Token 操作参考 ELF，将这两个程序部署到一个 Surfpool 实例，分别为每个程序调用相同的 Web3.js + `@solana/spl-token` mint/burn/approve/revoke 场景，并比较代币影响以及所有四个金额/标记状态写入。当 `cargo-build-sbf` 找不到 Solana rustc/platform-tools 时，该测试框架目前会跳过。- Pinocchio SPL Token authority 参考合约：
  `references/solana/pinocchio/spl-token-authority` 包含一个已签入的、针对与 `ProofForge.Solana.Examples.SplTokenAuthorityCpi` 相同的 SPL Token `set_authority` 账户 schema 的无分配器 Pinocchio 参考。gate `scripts/solana/pinocchio-spl-token-authority-equivalence.sh` 发射 ProofForge SPL Token authority CPI 制品，并将其指令 ABI、账户顺序、签名者/可写约束、CPI 协议/数据布局、`SetAuthority` 指令合约以及标记状态写入合约与参考清单/源代码进行对比。通过 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`，同一个 gate 针对 `pinocchio-token` 对参考进行类型检查。
- Pinocchio SPL Token authority 实时等效性测试 harness：
  `scripts/solana/pinocchio-spl-token-authority-live-equivalence.sh` 被配置为构建 ProofForge ELF 和已签入的 Pinocchio Token authority 参考 ELF，将这两个程序部署到一个 Surfpool 实例，分别为每个程序调用相同的 Web3.js + `@solana/spl-token` 铸币权限转移场景，并对比铸币权限以及标记状态写入。当 `cargo-build-sbf` 找不到 Solana rustc/platform-tools 时，该 harness 目前会跳过。

已完成的开发者层面切片：- 可移植 ValueVault 表面源代码：
  `ProofForge.Contract.Surface` 现在允许示例仅声明一次状态槽位、参数、方法和事件字段，然后通过类型化引用（`read`、`write`、`bind`、`emit`、`ret`）编写入口主体，而不是使用原始的 `ContractSpec` 字符串管道。`ProofForge.Contract.Examples.ValueVault`
  使用此层，并有意在源代码中保留 `selector? = none`。
- 基于声明派生的 IR 名称：
  `state_decl`、`binding_decl`、`method_decl`、`method_return_decl` 和
  `event_decl` 宏现在从 Lean 声明中派生 IR 名称，因此
  可移植的 Counter 和 ValueVault 源代码不再为状态槽位、输入、局部变量、方法名称或事件名称重复原始字符串。测试在将同一源代码路由到 EVM 和 Solana 之前，会断言派生的 snake-case 状态/参数/方法名称和 PascalCase 事件名称。
- 面向源代码的声明门面：
  `contract_decl Name do ...` 从 Lean 标识符派生模块名称，
  并将 `ContractSpec` 保留为编译器拥有的中间产物，而不是
  用户可见的编写模型。`ProofForge.Contract.Examples.Counter`
  和 `ProofForge.Contract.Examples.ValueVault` 现在使用此门面；较旧的
  `*_ref` 宏保留为旧版下游源代码的兼容性垫片。
- 合约源代码语法 v1：
  `ProofForge.Contract.Source` 为状态声明、事件、入口、查询、源本地绑定、
  状态赋值、事件发射、返回、类型化算术运算符，以及
  用于分配器、账户、PDA 派生和 SPL Token CPI 调用的 Solana 扩展声明添加了作用域内的 `contract_source` 语法。
  `ProofForge.Contract.Examples.Counter` 和
  `ProofForge.Contract.Examples.ValueVault` 现在通过此源代码块编写可移植逻辑，
  同时宏发射用于路由、EVM 选择器填充、Solana 指令标签、
  IDL 和客户端制品生成的相同 `ContractSpec`/可移植 IR 边界。
- 遗留 `.learn` 解析器/降级种子：
  `ProofForge.Contract.Learn` 现在将 `Examples/Learn/` 下检入的 `.learn` 文件
  词法分析并解析为可移植标量/事件子集的简单源 AST，
  将该 AST 降级为 `ContractSpec`/可移植 IR，并作为
  兼容性验证入口，而不是作为新的产品源代码语言。
  主要的编写界面仍然是 Lean `.lean` 文件和 Lean
  SDK 辅助工具。它证明了
  `Counter.learn` 和 `ValueVault.learn` 产生的 IR 模块与
  当前的 `contract_source` 示例相同。CLI 仍然通过 `--learn --target evm` 和 `--learn --target solana-sbpf-asm` 接受 `.learn` 文件，
  并保留 `--learn-yul`、`--learn-bytecode` 和 `--learn-sbpf` 作为低层级
  兼容性便利路径。
  `scripts/portable/value-vault-smoke.sh` 使用
  `Examples/Learn/ValueVault.learn` 作为遗留等效性固件，并证明
  该兼容性入口可以路由到 EVM Yul/字节码元数据和
  Solana sBPF 汇编/清单/IDL/客户端制品，而无需手动编写
  `ContractSpec`。
- Learn Solana 目标扩展语法：
  `ProofForge.Contract.Learn` 现在解析用于 `solana allocator`、`solana account`、`solana pda`、`solana cpi
  ... spl_token_transfer_checked(...)`, and entry-level `solana derive` /
  `solana invoke` 的 `SolanaVault.learn` 形式。降级重用了 `ProofForge.Solana` 构建器辅助工具，因此
  账户/PDA/CPI 元数据仍然流经现有的能力计划、
  清单、IDL、客户端和 sBPF 汇编路径。`Tests/LearnSource.lean`
  检查 Learn 降级的 SolanaVault 是否具有与 `ProofForge.Solana.Examples.Vault` 相同的 IR 模块和生成的清单。
- Learn System Program CPI 语法：
  `SystemCpi.learn` 和 `SystemCreateAccountCpi.learn` 现在涵盖了
  `solana cpi ... system_transfer(...)`、`solana cpi ...
  system_create_account(...) owner ...` 以及匹配的入口级
  `solana invoke` 语句。`Tests/LearnSource.lean` 证明这两个 Learn 文件
  降级后的 IR 模块和生成的清单与现有的 `ProofForge.Solana.Examples.SystemCpi` 和
  `ProofForge.Solana.Examples.SystemCreateAccountCpi` 源代码示例相同。
- Learn SPL Token 操作语法：
  `SplTokenOpsCpi.learn` 现在涵盖了带有选择器的 Learn 入口，以及
  `spl_token_mint_to`、`spl_token_burn`、`spl_token_approve` 和
  `spl_token_revoke` 的声明/调用。`Tests/LearnSource.lean` 证明
  Learn 文件降级后的 IR 模块和生成的清单与`ProofForge.Solana.Examples.SplTokenOpsCpi`，将字符串密集的 Builder 代码保留为内部预期 fixture，而不是面向用户的语法。
- Learn SPL Token close-account 语法：
  `SplTokenCloseAccountCpi.learn` 现在涵盖 `spl_token_close_account` 的声明/调用，
  并通过 `Tests/LearnSource.lean` 证明它和
  `ProofForge.Solana.Examples.SplTokenCloseAccountCpi` 具有相同的模块/manifest 边界。
- Learn log/return-data/compute-unit 语法：
  `LogEvent.learn` 和 `ReturnDataCompute.learn` 现在涵盖了 Solana pubkey/data
  日志辅助语句、return-data set/get 语句以及剩余的
  compute-unit 读取/日志语句。`Tests/LearnSource.lean` 证明了这两个 Learn
  文件降级为与 `ProofForge.Solana.Examples.LogEvent` 和
  `ProofForge.Solana.Examples.ReturnDataCompute` 相同的 IR 模块和生成的 manifest，
  将另一个面向 syscall 的 SDK 切片从仅限 Builder 的 fixture 移至面向用户的 Learn 源代码中。
- Learn memory/crypto/sysvar 语法：
  `Memory.learn`、`Crypto.learn`、`Rent.learn`、`EpochSchedule.learn`、
  `EpochRewards.learn`、`LastRestartSlot.learn` 和 `Clock.learn` 现在涵盖了
  面向用户的 Learn 源代码中的 Solana 内存辅助函数、SHA-256/Keccak-256/BLAKE3 辅助函数以及
  sysvar/context 读取。`Tests/LearnSource.lean`
  证明了这些 Learn 文件降级为与相应 `ProofForge.Solana.Examples.*` fixture 相同的 IR 模块和生成的
  manifest。
- Learn 引用诊断：
  `ProofForge.Contract.Learn` 现在在降级时构建声明引用索引，并
  拒绝未知或不匹配的 Solana CPI 调用、未知的
  PDA 派生、无效的签名者种子、使用未声明
  账户的 CPI 声明、不满足所需可写或
  签名者约束的 CPI 账户声明，以及引用未声明
  状态/账户名称的辅助语句。`Tests/LearnDiagnostics.lean` 固定了这些消息，以便
  Learn 的行为类似于经过检查的语言前端，而不是要求用户
  手动编写未经检查的 `ContractSpec` 数据。
- Solana 类型化账户界面：
  `ProofForge.Solana.Surface` 现在增加了 `account_ref`、`pda_ref` 和 `cpi_ref`
  声明，以及类型化 PDA 种子、账户约束和 SPL/System CPI
  辅助函数。`ProofForge.Solana.Examples.Vault` 现在使用专用的
  `contract_source` 项，例如 `allocator bump`、`account ... writable`、
  `pda ... seeds [...]`、`cpi ... spl_token_transfer_checked(...)`、`derive
  pda ...`, `invoke ... spl_token_transfer_checked(...)`，并且相同的
  一等源代码语法路径现在涵盖了 `spl_token_close_account(...)` 和
  `spl_token_set_authority(...)`，而不是原始账户/PDA/CPI 字符串或
  `use`/`do` 辅助管道。
  目标扩展将声明的账户约束发射到 `manifest.toml`、
  `proof-forge-artifact.json` (`solanaExtensions.accounts`) 以及生成的
  账户验证 schema 中。
- System create-account 源代码语法：
  `ProofForge.Contract.Source` 现在暴露了源代码级的
  `cpi ... system_create_account(...) owner ...` 和
  `invoke ... system_create_account(...) owner ...` 形式。
  `ProofForge.Solana.Examples.SystemCreateAccountCpi` 使用这些形式而不是
  低级 builder API，同时保留了现有的生成
  汇编、manifest、制品以及 Surfpool/Web3.js 行为门控。
- SPL Token 权限源代码语法：
  `ProofForge.Contract.Source` 现在暴露了源代码级的
  `cpi ... spl_token_set_authority(...) authority_type(...) signer_seeds [...]`
  和 `invoke ... spl_token_set_authority(...) authority_type(...) signer_seeds
  [...]` forms. `ProofForge.Solana.Examples.SplTokenAuthorityCpi` 在 Lean `.lean`
  fixture 中使用这些形式，并且生成的制品、Surfpool/Web3.js
  行为门控和 Pinocchio 引用门控都验证了相同的降级
  边界。
- SPL Token close-account 源代码语法：
  `ProofForge.Contract.Source` 现在暴露了源代码级的
  `cpi ... spl_token_close_account(...) signer_seeds [...]` 和
  `invoke ... spl_token_close_account(...) signer_seeds [...]` 形式。
  `ProofForge.Solana.Examples.SplTokenCloseAccountCpi` 在 Lean `.lean` fixture
  中使用这些形式；`Tests/SolanaCpiPacking.lean` 验证 manifest account schema、
  `spl-token.close_account` 元数据、指令标签 `9`、一字节 CPI data length 和生成的
  CPI helper 调用。该 fixture 可通过 target-first CLI
  `emit --target solana-sbpf-asm --fixture spl-token-close-account-cpi --format s|elf`
  以及对应 legacy 兼容 flag 发射。
  `scripts/solana/spl-token-close-account-cpi-web3-smoke.sh` 新增 live
  Surfpool/Web3.js 行为门控：它会部署生成的程序，创建空 SPL Token account，
  调用生成的 `close_account` CPI 路径，证明 token account 已被移除，验证租金
  lamports 转入 destination account，并检查 marker state 写入。该 SPL helper
  的 Pinocchio equivalence 仍是 reference-breadth 后续项。
- 目标阶段 ABI 选择器水合：
  Learn/ValueVault CLI 发射路径在 EVM
  Yul/字节码发射之前立即通过 `cast sig` 从每个
  入口的 Solidity ABI 签名中派生 EVM 选择器，根据派生
  值验证任何显式选择器，并通过继续使用目标
  指令标签保持 Solana 路由独立。`scripts/portable/value-vault-smoke.sh` 证明了相同的
  `.learn` 源代码发射了 EVM Yul/字节码元数据以及 Solana sBPF
  汇编/manifest/制品元数据。
- Solana IDL 和 TypeScript 客户端包输出：
  `ProofForge.Backend.Solana.Idl` 从 `manifest.toml` 和制品
  元数据使用的相同指令/账户/PDA/CPI schema 渲染 `proof-forge-idl.json`。`ProofForge.Backend.Solana.Client` 渲染
  `proof-forge-client.ts`，包含 Web3.js `TransactionInstruction` 辅助函数、
  指令数据编码和 account-meta 构建。Solana 包
  打印、`--emit-solana-sdk-sbpf`、`--emit-value-vault-ir-sbpf` 以及
  Solana ELF contract-sdk 路径现在都会发射并哈希这两个文件。

当前边界：- `ProofForge.Contract.Learn` 现在是旧版 `.learn` 兼容性解析器/降级种子，而不是新的产品源语言。它涵盖了可移植的 Counter/ValueVault 子集，以及 Vault 级别的 Solana account/PDA/SPL Token transfer CPI 子集、System Program transfer/create-account CPI、SPL Token mint/burn/approve/revoke CPI，以及 Solana log/return-data/compute-unit/memory/crypto/sysvar 辅助语句。在降级过程中，Solana CPI/PDA 声明和入口辅助语句会针对声明的引用进行交叉检查。CPI 账户操作数必须使用 `solana account ...` 声明；CPI 的 writable/signer 要求会根据这些声明进行检查，因此剩余的字符串名称是编译器拥有的标识符，而不是未经检查的用户编写的规范。`ProofForge.Contract.Source` 和 Lean SDK 辅助工具仍然是主要的编写前端；`.learn` 文件仅作为旧版兼容性和等效性测试装置保留，通过编译时目标 id 复用相同的降级边界。下一个编写差距是将 Lean `.lean` 界面扩展到 Token-2022、类型化账户/数据引用以及更丰富的 Pinocchio 风格账户验证人体工程学；旧版 `--learn` 包发射不是新语法工作的方向。

剩余优先级切片：

1. Rust/Pinocchio 等效性测试装置（2-4 天）：通过可靠地安装 Solana rustc/platform-tools，使 Pinocchio 实时等效性测试框架在 CI/本地环境中通过，然后将静态和实时引用覆盖范围扩展到 Token-2022 以及除已检查的 transfer/mint/burn/approve/revoke/set-authority 集合之外的剩余 SPL 辅助路径。关键对比点是账户顺序、signer/writable 检查、CPI 指令数据以及可观察的状态变化。
2. 更丰富的结构化日志、账户数据和类型化返回辅助工具（3-5 天）：将当前的标量 `sol_log_64_`/`sol_log_data` 事件路径扩展到字符串日志、Anchor 风格的鉴别器/Borsh 负载以及索引事件形式；添加除 `u64` 之外的类型化返回负载辅助工具、哈希语义与目标匹配的可移植 `Expr.hash` 路由，以及复用新 memory/syscall 路径的更广泛的账户/数据打包辅助工具，并进行 JavaScript 引用检查。
3. 运行时分配降级（1-2 天）：通过 `runtime.allocator` 路由基于堆的 SDK 结构，在需要时发射实际的向下增长的指针碰撞分配代码，并在 `noAllocator` 下拒绝使用分配的结构。
4. 动态每个入口账户模式（3-5 天）：在分派之前，用运行时账户解析替换当前的模块级固定模式，使指令数据偏移量不再依赖于每个入口共享相同的账户列表。
5. Token-2022 和更丰富的 SPL 覆盖（每次迭代 3-5 天）：添加经过检查的 Token-2022 扩展路由、关联代币账户设置流程，以及除已涵盖的 mint-authority `set_authority` 路径之外的剩余 SPL 变体，且不将这些细节移入可移植 IR。
6. 开发人员人体工程学和框架界面（每次迭代 3-5 天）：将新的界面层扩展到 Lean `.lean`/Lean SDK 合约语法，提供更丰富的类型化账户/数据包装器、更丰富的生成的客户端 API、更广泛的 SPL/Token-2022 辅助工具覆盖，以及将生成的汇编错误映射回 SDK 声明的诊断。

因此，通往更完整 SDK 的最快可靠路径是：alpha 可观察性基线现已就绪，接下来完成更丰富的 beta syscall 和 return-data 切片，然后在添加 Anchor/Pinocchio 级的人体工程学之前移除剩余的架构捷径。

## 工作流 8：Move 源代码生成 POC（Aptos 优先）

目标：避免假装 Move 是另一个 Lean 运行时目标。

任务：- 定义可移植 IR 的 Move 兼容子集。
- 生成一个 **Aptos** Move 计数器包（Sui 将在后续切片中跟进）。
- 运行 `aptos move compile/test`。
- 记录必须反馈到 IR 设计中的验证器限制。

验收标准：

- 生成的 Aptos Move 源代码可编译。
- 生成的包包含测试。
- 不支持的 Lean 结构在源代码生成前失败。
- 后续 Sui 对象 POC 已作为独立里程碑记录。

## 工作流 9：CI 扩展

参阅 [validation-gates.md](validation-gates.md) 了解当前和计划中的验证命令。

目标：保持 CI 的实用性，且无需在第一天就要求安装所有外部链工具。

任务：

- 将 `lake build` 保留为常驻 CI。
- 仅在 `solc` 和 Foundry 可用时添加 EVM 冒烟测试。
- 为 CosmWasm、Solana 和 Move 添加带有明确工具检查的可选作业。
- 将制品元数据验证添加为独立于工具的作业。

验收标准：

- 基础 CI 不会因为缺少可选链工具而失败。
- 当工具链存在但目标构建失败时，特定于目标的 CI 作业应显式报错。
- 元数据架构验证在无需链工具的情况下运行。

## 工作流 10：Psy DPN ZK 目标 spike

目标：在不将 ProofForge 与 Psy 编译器内部机制耦合的情况下，验证 ZK 电路源代码生成目标。

任务：- 已完成：从一个可移植 IR fixture 生成一个 Counter `.psy` 源文件。
- 已完成：在 `scripts/psy/counter-smoke.sh` 中添加一个临时的 Dargo 包生成器。
- 已完成：将 `dargo test --file` 记录为第一个本地冒烟测试运行器。
- 已完成：使用 `psyup` v0.1.0 macOS arm64 工具链运行 `dargo compile`，并捕获 DPN 电路 JSON。
- 已完成：作为本地用户/合约会话运行 `dargo execute`，并断言两次递增后的 Counter 结果。
- 已完成：调用 `dargo generate-abi` 并捕获非空的 ABI JSON。
- 已完成：为 Psy 冒烟测试制品发射带有目标 id `psy-dpn` 的 `proof-forge-artifact.json`。
- 已完成：添加 ContextProbe 作为非 Counter fixture，用于参数降级和上下文读取。
- 已完成：为 `Hash`、类型化哈希 let 绑定、`hash` 和 `hash_two_to_one` 添加 HashProbe，并与上游 Psy 哈希测试保持一致。
- 已完成：验证 Psy 制品元数据，包括哈希、字节大小、能力、验证标志和预期执行结果。
- 已完成：从上游 `psy-compiler/tests` 和 `psy-precompiles` 语料库中添加 map/storage-map、断言、有界循环、数组、结构体、聚合 ABI、嵌套聚合、存储嵌套聚合、U32 算术和位运算覆盖。
- 已完成：从上游 `psy-precompiles` 语料库中为本地数组和 ABI 参数添加 U32/Hash limb 打包覆盖。
- 已完成：发射并验证所有基于 Dargo 的 Psy 冒烟测试编译输出的 ProofForge 部署清单。
- 已完成：为 `Map<Hash, Hash, N>` 添加 map 存储路径覆盖，并进行 Dargo 编译/执行验证。
- 已完成：添加表达式位置 `storageMapSet` 降级和 MapProbe 覆盖，用于上游 map 边界语义，其中 `set` 和重复的 `insert` 返回前一个 `Hash` 值。
- 已完成：为标量存储和通用存储路径添加存储引用复合赋值覆盖，并进行 Dargo 编译/执行验证。
- 已完成：使用 Psy `pub value: u32` 存储加上标量 `+=` 赋值添加原生 U32 标量存储覆盖，并进行 Dargo 编译/执行验证。
- 已完成：使用 Psy `pub flag: bool` 存储加上 `bool as Felt` 返回类型转换添加原生 Bool 标量存储覆盖，并进行 Dargo 编译/执行验证。
- 已完成：使用 Psy `[bool; N]` 字面量/索引加上 `pub flags: [bool; N]` 存储添加原生 Bool 固定大小数组和存储数组覆盖，并进行 Dargo 编译/执行验证。
- 已完成：使用 Psy `pub root: Hash` 和 `pub roots: [Hash; N]` 添加原生 Hash 标量和存储数组覆盖，并进行 Dargo 编译/执行验证。
- 已完成：在 `[Felt; N]` 局部变量上使用 Psy `assert_eq`、`==` 和 `!=` 添加固定大小数组相等性覆盖，并进行 Dargo 编译/执行验证。
- 已完成：使用基于 Felt 的存储加上显式 U32 读/写类型转换添加 U32 存储数组覆盖，并进行 Dargo 编译/执行验证。
- 已完成：将基于 Felt 的 U32 存储数组路径复合赋值降级为显式读/更新/写类型转换，并进行 Dargo 编译/执行验证。
- 已完成：添加原生 U32 存储结构体字段路径写入、读取和复合赋值覆盖，并进行 Dargo 编译/执行验证。
- 已完成：添加一个 Psy IR 覆盖清单门控，使得每个可移植 IR 构造函数必须针对 Psy 后端被分类为已降级、已验证、不支持或结构化。
- 已完成：将 Dargo 冒烟测试包生成重构为一个共享写入器，使得每个 Psy 冒烟测试在元数据验证之前创建相同的 `src/main.psy` 和 `Dargo.toml` 布局。
- 已完成：在 Psy 后端允许将 EVM 风格的入口选择器作为特定于目标的 ABI 元数据；Psy 源代码生成仅使用方法名称，并可能在制品元数据中记录选择器以实现跨目标可追溯性。
- 已完成：在源代码生成之前验证 Psy 标识符和重复声明，以免无效名称导致 Dargo 解析器/类型检查器失败。
- 已完成：为没有特定于 fixture 断言的有效 Psy IR 模块添加一个通用的生成测试回退，由 `GenericEntrypointProbe` 支持。golden source、Dargo 编译/执行验证、ABI 生成、deploy manifest 生成以及制品元数据验证。
- 一旦 Psy 工具链公开了稳定的边界，就将 deploy manifest 路径转换为上游压缩的 genesis deploy JSON，然后执行本地节点/证明器部署冒烟测试。
- 一旦工具链公开了稳定值，就记录 Dargo/Psy 编译器版本或 commit。

验收标准：

- 生成的 `.psy` 源代码是可读的，并已检入黄金 fixture 或快照。
- `dargo compile` 在装有 Psy 工具链的机器上产生一个非空的 JSON 制品。
- `dargo execute` 为 Counter 生命周期返回 `result_vm: [2]`。
- `dargo execute` 为 ContextProbe 的 `sum_context(2,3)` 生命周期返回 `result_vm: [15]`。
- `dargo execute` 为 HashProbe 的 `poseidon_hash` 和 `poseidon_pair_hash` 入口返回确定的四个 Felt 输出。
- `dargo generate-abi` 产生一个非空的 ABI JSON 制品。
- `dargo execute` 为通用的非白名单 `GenericEntrypointProbe` 返回 `result_vm: [42]`。
- 制品元数据记录了目标 id、fixture id、使用的能力、制品路径、哈希、字节大小、Dargo 包源代码副本、Dargo 包 manifest 以及验证状态。
- 制品元数据由 Psy 冒烟测试脚本进行机器验证。
- 一旦可用，制品元数据会记录 Dargo/Psy 编译器版本或 commit。
- 不支持的非电路友好型 IR 节点在源代码生成之前失败。
- CI 要么固定一个已知良好的 `psyup` 版本，要么在匹配的工具链 tarball 不可用时明确跳过此 gate。

## 工作流 11: Kaspa Toccata Research 目标

目标：决定 ProofForge 是否以及如何支持 Kaspa 的 Toccata 可编程性堆栈，而不将其伪装成 EVM、账户状态或通用的 ZK 电路目标。

任务：

- 已完成：为候选 id `kaspa-toccata` 添加文档优先的目标说明。
- 将该目标分类为 UTXO covenant/based-app 研究，而非 `zk-circuit-sourcegen`。
- 审查 UTXO 状态、covenant 谱系、transaction v1、用户通道、计算预算和内联证明验证的候选能力。
- 决定第一个 spike 应该生成 Silverscript，还是仅围绕手动编写的 covenant 源代码生成目标 manifest。
- 定义一个带有后继输出验证的小型 L1 covenant Counter 类场景。
- 为 covenant 源代码、transaction v1 manifest、covenant 谱系 manifest 以及可选的证明验证器 manifest 定义最小制品元数据形状。
- 在 L1 covenant 制品形状明确之前，推迟对 based-app 的支持。

验收标准：

- `docs/targets/kaspa-toccata.md` 记录了目标分类和非目标。
- 能力候选方案保持文档化，但在审查通过前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可重复的本地验证命令或已记录的外部工具阻塞因素。
- 文档区分了内联 ZK 验证与 `psy-dpn` 风格的电路源代码生成。

## 工作流 12: Stellar Soroban Research 目标

目标：决定 ProofForge 是否以及如何支持 Stellar 智能合约，而不将所有 Wasm 合约链视为同一个目标。

任务：

- 已完成：为候选 id `wasm-stellar-soroban` 添加文档优先的目标说明。
- 将 Soroban 分类为 Wasm-host 候选，而非通用的 Wasm 制品目标。
- 决定第一个 spike 应该生成原生的 Rust/Soroban 包，还是等待直接的 Lean-to-Wasm 宿主桥接。
- 审查地址授权、合约账户授权、存储 TTL、合约规范元数据和 Stellar 资产的候选能力。
- 定义一个练习存储和事件输出的小型 Counter 类场景。
- 为 Wasm、合约规范、部署 manifest、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：`stellar contract build`、沙盒或测试网部署以及调用。

验收标准：- `docs/targets/stellar-soroban.md` 记录了目标分类和非目标。
- 能力候选方案保持文档化，但在经过评审前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已文档化的外部工具阻塞器。
- 尽管 Soroban、NEAR 和 CosmWasm 都使用 Wasm 制品，但文档将它们区分开来。

## 工作流 13：Internet Computer Research 目标

目标：决定 ProofForge 是否以及如何支持 Internet Computer canister，而不是将每个 Wasm 制品都视为相同的合约目标。

任务：

- 已完成：为候选目标 id `wasm-icp-canister` 添加文档优先的目标说明。
- 将 ICP canister 分类为 Wasm-host 候选目标，而非通用的 Wasm 制品目标。
- 决定第一个 spike 应该生成原生的 Motoko/Rust CDK 包，还是等待直接的 Lean-to-Wasm canister 桥接。
- 评审 Candid、update/query 方法模式、稳定内存、正交持久化、principal、cycle、异步 canister 间调用、canister 生命周期、认证数据和管理 canister API 的候选能力。
- 定义一个微小的类 Counter 场景，包含一个 update 方法和一个 query 方法。
- 为 Wasm、Candid、canister manifest、稳定状态或升级策略、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：本地副本、PocketIC 或 ICP CLI canister 安装/调用流程。

验收标准：

- `docs/targets/internet-computer.md` 记录了目标分类和非目标。
- 能力候选方案保持文档化，但在经过评审前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已文档化的外部工具阻塞器。
- 尽管 ICP canister、NEAR、CosmWasm 和 Soroban 都使用 Wasm 制品，但文档将它们区分开来。

## 工作流 14：TON TVM Research 目标

目标：决定 ProofForge 是否以及如何支持 TON 智能合约，而不是假装 TVM 合约是 EVM、Wasm-host、Move 或 ZK 目标。

任务：

- 已完成：为候选目标 id `ton-tvm` 添加文档优先的目标说明。
- 将 TON 分类为 TVM/Tolk 源代码生成候选目标。
- 决定第一个 spike 应该生成 Tolk 源代码/包制品，还是等待更低级别的 TVM/cell IR。
- 评审 cell、TL-B 元数据、入站消息、出站消息、get 方法、操作列表、`StateInit`、账户状态、TVM gas 以及 jetton/代币集成的候选能力。
- 定义一个微小的类 Counter 场景，包含一条内部消息和一个 get 方法。
- 为源代码、TVM/BOC 输出、接口元数据、初始状态、消息/操作 schema、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：Acton/Tolk 编译和本地测试或模拟器验证。

验收标准：

- `docs/targets/ton-tvm.md` 记录了目标分类和非目标。
- 能力候选方案保持文档化，但在经过评审前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已文档化的外部工具阻塞器。
- 文档将 TON TVM 与 Wasm-host、EVM、Move 和 ZK 目标区分开来。

## 工作流 15：Bitcoin Cash CashScript Research 目标

目标：决定 ProofForge 是否以及如何支持 Bitcoin Cash 智能合约，而不是假装 UTXO 支出路径是状态化的合约方法调用。

任务：- 已完成：为候选 id `bch-cashscript` 添加文档优先的目标说明。
- 将 BCH/CashScript 分类为 UTXO 脚本/covenant 源代码生成候选。
- 决定第一个 spike 是否应在任何底层 BCH Script 路径之前生成 CashScript 源代码/包制品。
- 审查 UTXO 状态、P2SH 脚本、unlockers、交易内省、covenants、本地状态、CashTokens、时间锁、签名检查、CashScript 制品以及交易构建器验证的候选能力。
- 定义一个微型 UTXO 花费场景，包含至少一个合约函数和交易构建器冒烟测试。
- 为 `.cash` 源代码、cashc 制品 JSON、字节码、构造函数/unlocker 清单、交易场景、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：`cashc`、CashScript SDK、`MockNetworkProvider` 以及可选的 chipnet/节点后端验证。

验收标准：

- `docs/targets/bitcoin-cash-cashscript.md` 记录目标分类和非目标。
- 能力候选保持文档化，但在审查前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻塞因素。
- 文档将 BCH/CashScript 与 EVM、Wasm-host、Move、通用 Bitcoin 以及 Kaspa/Toccata 目标区分开来。

## 工作流 16：Algorand AVM Research 目标

目标：决定 ProofForge 是否以及如何支持 Algorand 智能合约，而不将 AVM 应用伪装成 EVM、Wasm-host、Move、Solana、TVM、UTXO 或 ZK 电路目标。

任务：

- 已完成：为候选 id `algorand-avm` 添加文档优先的目标说明。
- 将 Algorand 分类为 AVM/TEAL 源代码或包生成候选。
- 决定第一个 spike 是否应在任何直接 TEAL 发射器路径之前生成 Algorand Python 或 Algorand TypeScript 包制品。
- 审查有状态应用、LogicSig 程序、ARC-4 ABI/应用规范、全局/本地/box 存储、交易组、资源引用、内部交易、Algorand 标准资产、AVM 预算以及 AlgoKit/Puya 制品的候选能力。
- 定义一个微型有状态 Counter 类应用，包含一个更新方法、一个读取/查询路径、显式存储模式以及 localnet 或模拟器后端验证。
- 为源代码、审批字节码、清除状态字节码、可选 LogicSig 字节码、ABI/应用规范、存储模式、资源引用、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：AlgoKit/Puya 编译加上 LocalNet 或模拟器后端的创建/调用/查询验证。

验收标准：

- `docs/targets/algorand-avm.md` 记录目标分类和非目标。
- 能力候选保持文档化，但在审查前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻塞因素。
- 文档将 Algorand AVM 与 Wasm-host、EVM、Move、Solana、TVM、UTXO 和 ZK 目标区分开来。

## 工作流 17：Cardano Plutus/Aiken Research 目标

目标：决定 ProofForge 是否以及如何支持 Cardano 智能合约，而不将 eUTXO 验证器伪装成有状态的方法调用合约。

任务：- 已完成：为候选目标 id `cardano-plutus-aiken` 添加文档优先的目标说明。
- 将 Cardano 分类为 eUTXO 验证器源代码生成候选目标。
- 决定第一个 spike 是否应在任何直接的 Plutus/UPLC 路径之前生成 Aiken 源代码。
- 审查 eUTXO 状态、验证器角色、datum、redeemer、脚本上下文、有效性范围、交易平衡、原生代币、执行单元以及 Plutus 蓝图的候选能力。
- 定义一个带有后继输出验证的微型类 Counter eUTXO 状态机场景。
- 为 Aiken 源代码、UPLC/Plutus 验证器、蓝图、datum/redeemer 模式、交易场景、执行单元、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟命令集：Aiken 编译/测试加模拟器、基于 SDK 的交易或基于 cardano-node 的验证。

验收标准：

- `docs/targets/cardano-plutus-aiken.md` 记录了目标分类和非目标。
- 能力候选者保持文档化，但在通过审查前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻碍因素。
- 文档将 Cardano 与 EVM、Wasm-host、Move、Solana、TVM、AVM、通用 Bitcoin、BCH/CashScript 以及 Kaspa/Toccata 目标区分开来。

## 工作流 18：Tezos Michelson/LIGO Research 目标

目标：决定 ProofForge 是否以及如何支持 Tezos 智能合约，而不将 Michelson 操作列表语义隐藏在通用合约调用之后。

任务：

- 已完成：为候选目标 id `tezos-michelson-ligo` 添加文档优先的目标说明。
- 将 Tezos 分类为 Michelson 源代码/制品目标，并将 LIGO 作为第一个源代码生成路径。
- 审查 Michelson 代码、入口、类型化 Micheline 存储、`big_map`、操作列表、视图、事件、票据、Sapling、委托、gas/存储销毁以及 LIGO 制品的候选能力。
- 定义一个具有一个入口、一个视图、类型化存储以及本地测试或沙盒验证流的微型类 Counter 合约。
- 为 LIGO 源代码、Michelson 输出、参数/存储模式、操作列表、视图/事件清单、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟命令集：LIGO 编译/测试加 Octez 沙盒或等效的 Tezos 本地验证。

验收标准：

- `docs/targets/tezos-michelson-ligo.md` 记录了目标分类和非目标。
- 能力候选者保持文档化，但在通过审查前不会添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻碍因素。
- 文档将 Tezos 与 EVM、Wasm-host、Move、Solana、TVM、AVM、UTXO 和 ZK 目标区分开来。

## 工作流 19：Starknet Cairo Research 目标

目标：决定 ProofForge 是否以及如何支持 Starknet 智能合约，而不将 Cairo 链上合约视为通用的 ZK 电路。

任务：

- 已完成：为候选目标 id `starknet-cairo` 添加文档优先的目标说明。
- 将 Starknet 分类为 Cairo/Sierra/CASM 源代码生成候选目标。
- 审查 Cairo 源代码、Sierra、CASM、类声明、类哈希、Starknet ABI、存储、账户抽象、系统调用、L1/L2 消息传递、Starknet 费用/资源限制以及 Starknet Foundry 验证的候选能力。
- 定义一个具有存储、一个 increment 外部函数、一个读取函数和一个事件的微型类 Counter 合约。
- 为 Cairo 源代码、Sierra/CASM 制品、ABI、选择器/类哈希元数据、部署清单、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟命令集：Scarb 构建加 `snforge` 或基于 devnet 的测试。

验收标准：- `docs/targets/starknet-cairo.md` 记录了目标分类和非目标。
- 能力候选者保持记录状态，但在经过评审前不会被添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻塞因素。
- 文档将 Starknet 与 EVM、Wasm-host、Move、Solana、TVM、AVM、UTXO 以及 `psy-dpn` 风格的 ZK 电路目标进行了区分。

## 工作流 22：Aleo Leo 研究目标

目标：决定 ProofForge 是否以及如何支持 Aleo 程序，而不将 Aleo 仅视为通用的 ZK 电路目标，或将 Aleo VM 与 Algorand AVM 混淆。

任务：

- 已完成：为候选者 id `aleo-leo` 添加文档优先的目标说明。
- 将 Aleo 分类为 ZK 应用源代码生成候选者，以 Leo 作为第一个源代码边界，Aleo Instructions 作为低级编译器目标，Aleo VM 字节码作为可部署的执行制品。
- 评审以下各项的能力候选者：Leo 源代码、Aleo Instructions、Aleo VM、AVM 字节码、ABI、证明者/验证者制品、transitions、finalization、records、mappings、存储、公有/私有输入和输出、程序导入/升级、执行/部署交易、Credits 费用、Leo 测试以及 devnet 验证。
- 定义一个微型的类 Counter 程序，包含一个入口 `fn`、一个公有 `mapping` 和一个 `final { }` 块。
- 定义第二个私有 record 场景，该场景消耗一个加密 record，创建一个后续 record，并仅在需要时记录公有/finalization 效应。
- 为 Leo 源代码、程序 id/导入、record/mapping 模式、finalization 清单、Aleo Instructions、Aleo VM 字节码、ABI、证明者/验证者制品、执行/部署交易元数据、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：`leo build`、`leo test`、可选的 `leo test --prove`、`leo execute --print`，以及基于 devnet/devnode 的部署或执行验证。

验收标准：

- `docs/targets/aleo-leo.md` 记录了目标分类和非目标。
- 能力候选者保持记录状态，但在经过评审前不会被添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻塞因素。
- 文档将 Aleo 与 `psy-dpn`、Zcash Shielded、Kaspa/Toccata 内联 ZK、Starknet Cairo、Algorand AVM 以及通用的源代码生成目标进行了区分。

## 工作流 20：Bitcoin Script/Miniscript 研究目标

目标：决定 ProofForge 是否以及如何支持比特币基础层支出策略，而不假装 Bitcoin Script 是通用的智能合约运行时。

任务：

- 已完成：为候选者 id `bitcoin-script-miniscript` 添加文档优先的目标说明。
- 将比特币分类为通过 Script、Miniscript、描述符、PSBT 和 Bitcoin Core 验证的受限 UTXO 支出策略目标。
- 评审以下各项的能力候选者：Bitcoin Script、Miniscript、描述符、SegWit、Taproot、Tapscript、witness 栈、sighash 模式、哈希锁、阈值多签、PSBT 流程、标准性、权重/费用限制以及 Bitcoin Core regtest 验证。
- 定义一个微型的支出策略场景，例如“A 可以立即支出，或者 B 可以在相对时间锁之后支出”。
- 为策略、描述符、输出脚本、witness 要求、PSBT/原始交易场景、权重/费用、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：Bitcoin Core regtest、描述符导入或地址派生、PSBT 签名/finalization，以及 `testmempoolaccept` 或等效的支出验证。

验收标准：- `docs/targets/bitcoin-script-miniscript.md` 记录了目标分类和非目标。
- 能力候选者保持文档记录，但在经过评审前不会被添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻塞因素。
- 文档将 Bitcoin Script/Miniscript 与 EVM、Wasm-host、Move、Solana、TVM、AVM、Cardano eUTXO、BCH/CashScript、Kaspa/Toccata 以及通用智能合约目标区分开来。

## 工作流 21：Zcash 屏蔽 Research 目标

目标：决定 ProofForge 是否以及如何支持 Zcash 屏蔽支付，而不将 Zcash 视为普通的 Bitcoin Script 或通用的 ZK 智能合约链。

任务：

- 已完成：为候选者 id `zcash-shielded` 添加文档优先的目标说明。
- 将 Zcash 分类为隐私 UTXO/ZK 支付候选者，包含透明 Zcash 流以及 Sapling/Orchard 屏蔽池。
- 评审以下各项的能力候选者：屏蔽隐私、透明池跨越、Sapling、Orchard、屏蔽票据、票据承诺、nullifiers、承诺树锚点、Zcash 协议证明、私有 witness、价值平衡约束、查看密钥、统一地址、隐私策略以及 zcashd/库验证。
- 定义一个微型屏蔽支付场景，例如“花费一个 Orchard 票据，创建一个 Orchard 票据，揭示一个 nullifier，保持价值平衡，并支付一笔透明手续费”。
- 定义类似 JDL-Z11 的脚本如何表达 `shield`、`spendNote`、`createNote`、`revealNullifier`、`selectAnchor` 和 `privacyPolicy`，同时拒绝全局可变屏蔽存储、方法调度和任意证明验证。
- 为透明输入/输出、屏蔽池、票据输入/输出模式、nullifiers、锚点、价值平衡、witness/证明需求、查看密钥披露、工具链版本和验证结果定义制品元数据。
- 确定本地冒烟测试命令集：zcashd RPC 或兼容的 Rust 钱包/协议库，如果本地证明对于 CI 过于沉重，则提供明确的备选阻塞因素。

验收标准：

- `docs/targets/zcash-shielded.md` 记录了目标分类和非目标。
- 能力候选者保持文档记录，但在经过评审前不会被添加到 `ProofForge.Target.Capability`。
- 第一个 spike 具有可复现的本地验证命令或已记录的外部工具阻塞因素。
- 文档将 Zcash 与 Bitcoin Script/Miniscript、BCH/CashScript、Kaspa/Toccata 内联 ZK、`psy-dpn` 电路源代码生成以及通用智能合约区分开来。

## 工作流 23：多链代币 SDK

目标：让用户仅需描述一次同质化代币意图，然后让 `--target` 选择在 EVM 上进行 ERC-20 合约生成，或在 Solana 上选择 SPL Token / Token-2022 方案，而无需在面向用户的 SDK 层暴露特定链的代码。

任务：- 已完成：添加 RFC 0006、`ProofForge.Contract.Token.TokenSpec`、目标代币计划以及 `Tests/TokenSpec.lean`。
- 已完成：添加遗留 Learn 代币意图源语法、`ProofForge.Contract.Token.Learn`、`Examples/Learn/ProofToken.learn`、`Examples/Learn/FeeToken.learn`、`Tests/TokenLearn.lean` 以及作为进入 `TokenSpec` 兼容路径的 `proof-forge --learn-token --target <id>` 计划发射。
- 已完成：为 Learn 代币源添加首个 EVM ERC-20 制品发射器：`ProofForge.Contract.Token.Evm`、`Tests/TokenEvm.lean`、元数据中的标准 ERC-20 选择器/事件、Yul 生成，以及通过 `--learn-token --target evm` 进行的 `solc --strict-assembly` 字节码验证。
- 已完成：添加 `scripts/portable/learn-token-smoke.sh` / `just learn-token-smoke` 以验证来自 Learn 源的 EVM ERC-20 代币制品路径和 Solana Token-2022 计划路径。
- 已完成：添加 `scripts/evm/learn-token-erc20-vm-smoke.sh` / `just learn-token-evm-vm` 以在 EthereumJS VM 中部署生成的 ERC-20 创建字节码，并验证标准 ERC-20 调用、Transfer/Approval 主题以及余额不足 revert 行为。
- 已完成：在 Lean `TokenSpec` 层实现 Solana SPL Token / Token-2022 部署计划渲染。`solanaTokenDeploymentPlan` 现在记录 mint 账户创建、关联代币账户、`mint_to`、`transfer_checked`、`approve`、`burn`、`revoke`、权限变更、Token-2022 扩展初始化、Solana 程序 id 以及源文档引用。
- 已完成：将 `transfer_fee`、`non_transferable`、`confidential_transfer` 和 `transfer_hook` 等 Token-2022 特性路由至 Token-2022 扩展元数据，而非自定义单代币程序。规划器会拒绝已记录的不兼容 `transfer_fee` + `non_transferable` 组合。
- 已完成：扩展 `scripts/portable/learn-token-smoke.sh`，使遗留 `.learn` 输入路径复用 Lean `TokenSpec` 计划，发射 SPL Token 和 Token-2022 结构化计划 JSON，并使用 `@solana/spl-token` / `@solana/web3.js` 指令构建器离线验证计划。
- 已完成：添加 `scripts/solana/token-plan-web3-smoke.sh` / `just solana-token-plan-web3` 以在 Surfpool 上执行结构化遗留 SPL Token 计划。实时运行器创建 mint 和关联代币账户，铸造初始供应量，执行计划的 `mint_to`、`transfer_checked`、`approve`、`burn`、`revoke` 和 mint-authority `set_authority` 操作，并通过 Web3.js 读取验证余额、供应量、代理状态和权限撤销。
- 已完成：添加 `scripts/solana/token-2022-transfer-fee-web3-smoke.sh` / `just solana-token-2022-transfer-fee-web3` 以在 Surfpool 上执行结构化 Token-2022 转账费用计划。实时运行器初始化 `TransferFeeConfig`，创建 Token-2022 关联代币账户，铸造初始供应量，执行 `TransferCheckedWithFee`，验证源余额、接收者净余额和接收者预留费用，直接从代币账户提取预留费用，然后运行第二次转账，将预留费用归集到 mint，从 mint 提取费用，并通过 Web3.js 读取验证费用接收者余额以及已清除的账户/mint 预留金额。
- 已完成：添加 `ProofForge.Contract.Token.Examples.SoulboundToken`、`Tests/TokenPlanEmit.lean`、`scripts/solana/token-2022-non-transferable-web3-smoke.sh` 以及在 Surfpool 上基于 TokenSpec 的 `just solana-token-2022-non-transferable-web3` to execute a Lean `.lean` Token-2022 不可转账计划。实时运行器初始化 `NonTransferable`，创建 Token-2022 关联代币账户，铸造初始供应量，验证 mint/账户扩展，证明 `TransferChecked` 被拒绝，然后销毁代币并通过 Web3.js 读取验证余额和供应量。
- 实现 EVM ERC-20 降级：ABI/选择器、余额/津贴存储、总供应量、transfer/approve/transferFrom、铸造/销毁选项、事件以及更广泛的 Foundry/Web3 行为测试。
- 继续对 Token-2022 扩展计划进行 Surfpool 实时验证，涵盖转账费用初始化、检查转账（checked-transfer）、直接提取和归集到 mint 提取路径以及不可转账的转账拒绝之外的内容：机密转账设置和转账钩子路由。
- 为自定义策略（如供应量上限或自定义转账限制）添加可选的 Solana wrapper/权限/转账钩子程序生成。- 待 Surfpool plan runner 上线后，使用实时部署账户、工具版本和验证运行结果扩展特定于代币的制品元数据。

验收标准：

- Lean 编写的 `TokenSpec` 具有确定性的 EVM 和 Solana 代币计划；旧版 Learn 代币源降级到相同的 `TokenSpec` 边界。
- EVM 输出发射 ERC-20 Yul/字节码，并使用标准 Web3/Foundry 调用通过 ERC-20 行为测试。
- Solana 输出渲染结构化的 SPL Token / Token-2022 计划，使用 `@solana/spl-token` 离线验证指令构建器，现在在 Surfpool 上执行旧版 SPL Token 计划以及 Token-2022 转账费用和不可转让计划，以创建 mints 和代币账户、铸造供应量、在允许的情况下转账代币、验证余额、校验预留的转账费用、通过直接账户提取和 harvest-to-mint 加 mint 提取两种方式收集这些费用、拒绝不可转让的 `TransferChecked`，并销毁不可转让的供应量。机密转账和转账钩子行为仍为后续工作。
- 文档明确说明 Solana 默认不使用每个代币独立的 SPL 合约；它根据计划和 CPI 使用 SPL Token / Token-2022 程序。

## 工作流 24：架构收敛后续工作（合并后）

2026-07 分支合并将 `solana-supprot`、`lookdown` (Wasm/NEAR)、`aleo-support` 和 `cloudflare-support` 合并到主干，解决了 D-025/D-026/D-027 决策 id 冲突（NEAR 决策重新编号为 D-029–D-031，Aleo 为 D-032，Cloudflare 为 D-033），统一了能力矩阵，并修复了 EVM 事件遍历器、Leo 发射器和 TS 发射器中的 `IR.Statement.release` 语义冲突。剩余后续工作：

任务：

- 在 `development-standards.md` 中记录分支策略：链是目录和目标 id，而不是分支；对 `ProofForge/IR/*`、`ProofForge/Target/*`、`ProofForge/Contract/{Spec,Intent,Source}*`、`docs/capability-registry.md`、`docs/decisions.md` 和 `docs/portable-ir.md` 的更改通过独立 PR 提交到 `main`。
- 记录 i18n 规则：特性分支不触碰 `docs/zh/*.zh.md` 或 `scripts/i18n/manifest.json`；翻译同步仅在 `main` 上运行。
- 在合并 PR 上线后，停用已合并的远程分支（`DaviRain-Su/solana-supprot`、`DaviRain-Su/lookdown`、`DaviRain-Su/aleo-support`、`DaviRain-Su/cloudflare-support`）。
- 重新生成由合并后清单标记的过时 `docs/zh` 翻译（手动合并的决策/能力表已同步；在自动合并下发生更改的叙述性文档应通过 `translate-docs.py` 重新运行）。
- 决定 Solana bump-allocator 选择是统一在合并后的 `TargetProfile.deploymentAllocator?` 抽象下，还是保持目标本地；在 `decisions.md` 中记录结果。
- 统一 CI 工作流：合并后的 `.github/workflows/ci.yml` 现在承载 EVM、Solana-light、NEAR 和 Psy 门控；一旦它们的工具链（`leo`、`tsc`/`wrangler`）固定，就将 Aleo 和 TS/Cloudflare 冒烟测试添加为可选作业。
- 命名清理：决定公开 SDK 名称，安排 `Lean.Evm` → `ProofForge.*` 命名空间重命名，并执行 Learn 冻结（[authoring-model](authoring-model.md)）。
- 在 RFC 0004 中宣布 `ContractSpec` → EVM Plan → Yul 为 EVM 产品流水线；将 LCNF → `EmitYul` 标记为 Lean-native Experimental 路径。
  ✅ 已完成（D-046 / CS-6.3）：LCNF `EmitYul` 已移除；RFC 0004 为 Accepted；
  `contract_source` 为产品入口。
- 决定 `wasm-cloudflare-workers` 是保留其在 `wasmHost` 下的注册表条目，还是移动到独立的离线宿主家族（无共识，无链上状态），以免稀释能力语义；与 D-033 一起记录在 `decisions.md` 中。
- 已完成：在 `decisions.md`、`target-roadmap.md` 和 `gate-status.md` 中记录 Gate G0 以及更严格的 Gate P0 主三链完成规约。Gate G0 关闭共享行为/预算切片；在 Gate P0 关闭前，新的和非主链目标保持 docs-only 或 maintenance-only——不得推进 registry、capability、testkit、CI 或产品范围。

验收标准：- `docs/decisions.md` 显示了一个线性决策日志（D-001…D-046，无重复 id），记录了分配器统一结果，并使 D-039/RFC 0009 以及 D-045/Gate P0 与代码库实际状态保持一致。
- 开发标准包含分支和 i18n 规则。
- 所有四个已合并的链分支均已删除或归档。

## 工作流 25：形式化验证路线图

目标：根据 [formal-verification.md](formal-verification.md)，将平台的核心承诺转换为机器检查的定理。

任务（完整说明请参见路线图）：

- FV-1：证明 `resolveSpec` 的能力路由稳健性、拒绝完备性以及 Solana 目标扩展隔离（将 D-027/D-028 作为定理）。
- FV-2：将 `ProofForge/IR/Semantics.lean` 扩展到标量子集之外。已完成：
  fixed arrays、struct values、aggregate ABI params/returns、storage arrays、
  storage struct fields、nested storage paths、覆盖 map insert/set lifecycle
  的 state-threaded effectful expressions、`ifElse`/`boundedFor`
  control-flow execution、observable event-log traces、deterministic-result
  anchors，以及 bounded-loop decreasing-measure anchor。剩余：
  为已验证的类型化子集证明 progress/preservation。
- FV-3：证明 `IR/Ownership.lean` 检查器相对于释放感知语义（无释放后使用、无重复释放）是稳健的，为三种不同的 `release` 降级（EmitWat 分配器、EVM/Psy 拒绝、TS no-op）提供依据。
- FV-4：已在 `Backend/Evm/Refinement.lean` 中落地 EVM Counter、ValueVault 和 EvmExpressionProbe 可执行追踪义务，并由 `Backend/Evm/YulSemantics.lean` 支撑。这些义务镜像 `Backend/WasmNear/Refinement.lean` 的 scalar IR trace，检查 selector-dispatched Yul surface，并执行聚焦的已发射 Yul 子集（`calldataload`、`calldatasize`、`sstore`、`sload`、标量算术、`exp`、bitwise/shift operators、comparisons、casts、assertions、`number`、确定性的 memory-sensitive `keccak256` surrogate、`log0`-`log4`、`mstore`、`return`、聚焦的 `switch` 和有界 `for`），将可观察 EVM return words 与 IR trace 对比。ValueVault 覆盖 calldata 参数、多入口标量存储更新、区块号上下文读取、事件字段求值以及 return words；EvmExpressionProbe 覆盖 assertion success paths、`assertEq`、predicate expressions、U32/U64 arithmetic、casts、bitwise operators 和 shifts。新增的可执行义务覆盖 `EvmMapProbe`（map value/presence slots 和嵌套 map paths）、`EvmTypedStorageProbe`（typed storage arrays 和 hash array reads）、`EvmStorageStructProbe`（storage structs 和 flat struct arrays）、`EvmAbiAggregateProbe`（aggregate ABI params/returns）、`ConditionalProbe`（if/else storage updates）以及 `EvmLoopProbe`（bounded loops 和 branch/loop early returns）。覆盖到的 FV-2 IR aggregate/storage/map/control-flow/event traces 现在已经通过显式 IR 调用参数和 `*_ir_observable_trace_ok` 定理锚点接入这些 EVM obligations，因此同一组 observable return words 会同时在 IR 侧和可执行 emitted-Yul 侧检查。NEAR 现在有基于 `EmitWat.lowerModule` 产出的 `Compiler.Wasm.AST` 的 Counter 和 ValueVault artifact-surface obligations，用来锁定 entrypoint/helper host-boundary calls、memory、storage-key data、ValueVault event data，以及 host import module/type signatures，先于 WAT 打印阶段检查。同一个 artifact surface 现在还会固定 Wasm memory declaration、key/return/event/event-key/input buffers 的固定 host buffer layout、entrypoint `input`/`read_register` prologues、从 `INPUT_BUF` 读取标量 u64 参数的 loads、传给 `__pf_read_u64` 的 storage-read key pointer/length frames、传给 `__pf_write_u64` 的 storage-write key/value frames，以及 ValueVault `block_index` checkpoint reads。NEAR 也新增 Counter 和 ValueVault offline-host execution-surface obligations，从同一个 IR trace 边界导出 Borsh/little-endian 输入字节、预期的确定性 host return fragments、storage/log 计数、最终 ValueVault state、标量 `value_return` payload bytes、per-step storage bytes、event-log fragments 和 byte-level `log_utf8` payload hex fragments；CI smoke 会通过 `runtime/offline-host` 执行生成的 WAT，并检查对应的 ValueVault returns/events。下一步：将 NEAR FV-4 从这些 execution surfaces 扩展到更丰富的 Wasm memory 与 host-call 语义边界；在解释器存在之前，让 Psy/Solana 保持在差异门控上。
- FV-5：在 IR 值域中统一陈述检查算术溢出/除法语义，并将溢出分支添加到后端义务中。
- FV-6：证明配对测试夹具子集的 `.learn` 与 `contract_source` 降级等价性（可判定的 `ContractSpec` 相等性）。
- FV-7：证明 Token SDK 计划不变性（全特性路由、已文档化的不兼容诊断、计划良构性）。
- FV-8：第一批 ValueVault worked-example invariants 已落在
  `ProofForge.Contract.Examples.ValueVaultInvariant`。这些 `decide` 可检查锚点
  会用 FV-2 IR 解释器执行链无关的 ValueVault `contract_source` 模块共享 11 步场景，
  然后检查 observable return trace、`balance + released + fees = externally supplied value`、
  final storage fields，以及 `get_net_value = balance - fees`。下一步：把这个
  具体模块推广成面向作者的 invariant pattern，并将已证明的 IR invariants 连接到
  FV-4 backend obligations。

验收标准：

- 每个已落地的 FV 项都是 `decide` 可检查的定理或接入 CI 的 Lean 测试，而不是外部工具依赖。
- 后端在没有其 FV-4 追踪义务和共享场景差异门控的情况下，不能从 Experimental 变更为 Supported。

## 工作流 26：统一 Rust 测试框架 (testkit)

目标：根据 [RFC 0007](rfcs/0007-unified-rust-test-framework.md)，用统一的声明式场景格式和 Rust 进程内执行器取代各链分散的 shell/Node 测试桩。

任务（每个实现分支一个里程碑）：- M1：创建 `testkit/` Cargo 工作区（`core` + 场景 TOML 模型、发现、报告）；将 `runtime/offline-host` 移植到 `harness-near`（wasmtime + NEAR 宿主 shim，保留分配器计数器）；Counter 场景在 `wasm-near` 上通过；添加 `just testkit` 和一个 CI 步骤。
- M2：在 revm 上的 `harness-evm` —— 加载发射的运行时字节码，通过 `.evm-methods` 选择器进行调度，解码返回字（return words）；Counter 在 `evm` 上通过；首次跨目标等效性断言（evm ↔ wasm-near 可观察追踪）。
- M3：在 mollusk-svm 上的 `harness-solana` —— 将 `Tests/solana/*_mollusk.rs.tpl` 逻辑吸收为库代码；Counter 在所有三个目标上通过。状态：Counter 现在通过 `testkit/harness-solana` 中的 `mollusk-svm` 连接，包括黄金汇编、manifest、制品元数据、sBPF ELF 构建、有状态场景执行，以及在 `sbpf` 和 `solana-keygen` 可用时的三目标追踪一致性。ValueVault 现在由 `testkit/scenarios/value-vault.toml`、类型化标量场景参数、`runtime/offline-host --inputs-hex`、NEAR/Wasm EmitWat fixture、Solana ValueVault sBPF/Mollusk harness 以及当 Foundry `cast` 可用于选择器填充时的 EVM/revm harness 覆盖。
- M4：将黄金文件比较和每个 fixture 的行为脚本迁移到场景步骤中；停用重复的 shell 脚本；将每个 fixture 的 CI 步骤合并到 testkit 运行中。实时/链上真实网关（Foundry, Anvil deploy, Surfpool, near-sandbox, dargo, leo）保持为独立的定时或标记任务。状态：第一个 M4 切片已通过场景声明的 `[[artifact]]` 预期就绪。Counter 的 Solana 黄金汇编/manifest 检查以及 ValueVault 的 WAT/Yul/sBPF/manifest/元数据源代码形态检查现在存在于场景 TOML 中，而不是硬编码的特定于 fixture 的 harness 分支。第二个切片添加了嵌套的 `[[artifact.json]]` 和 `[[artifact.toml]]` 检查，因此 Solana Counter 和 ValueVault 的元数据/manifest 字段、指令名称/标签、能力成员资格和验证状态由场景运行器声明式地断言。后续切片删除了重复的 Solana harness 内部元数据/manifest 语义验证器，仅在 `testkit/harness-solana` 中保留运行时调度解析。下一个切片收紧了场景发现，使得在任何 harness 运行之前，未声明目标的空或重复目标 id 以及制品预期都会失败。当前的 EVM 切片将 EVM 制品元数据标识、能力、验证和 ABI 入口名称预期移至场景声明的 `[[artifact.json]]` 检查中，使 `testkit/harness-evm` 仅负责选择器解析和运行时执行。当前的诊断切片添加了场景声明的 `[[diagnostic]]` 预期，以及一个仅用于诊断的 `unsupported-crosscall` 场景，该场景证明 `solana-sbpf-asm` 会以预期的目标/能力消息拒绝可移植的 `crosscall.invoke` 能力。当前的 EVM 黄金切片添加了 `Examples/Evm/Counter.golden.yul` 作为可移植 IR Counter Yul 黄金快照，并使 `testkit/scenarios/counter.toml` 通过 `matches_file` 断言生成的 EVM Yul；旧的 Lean SDK 合约黄金快照保留在 `Examples/Evm/Contracts/` 下。当前的 Wasm/NEAR 黄金切片添加了 `Examples/WasmNear/Counter.golden.wat`，并使相同的 Counter 场景通过 `matches_file` 断言生成的 EmitWat 输出，因此 Counter 现在对 `wasm-near`、`evm` 和 `solana-sbpf-asm` 具有场景声明的源代码等效性。当前的 ValueVault Wasm/NEAR 黄金切片添加了 `Examples/WasmNear/ValueVault.golden.wat`，并使 `testkit/scenarios/value-vault.toml` 通过 `matches_file` 断言生成的 EmitWat 输出。当前的 ValueVault Solana 黄金切片添加了 `Examples/Solana/ValueVault.golden.s` 和 `Examples/Solana/ValueVault.manifest.toml`，使相同的场景通过 `matches_file` 断言生成的 sBPF 汇编和 manifest 输出。当前的 ValueVault EVM 黄金切片添加了 `Examples/Evm/ValueVault.golden.yul` 并使相同的场景通过 `matches_file` 断言生成的 EVM Yul，因此 ValueVault 现在对 `wasm-near`、`solana-sbpf-asm` 和`evm`。当前的元数据文件引用切片增加了嵌套的 `[[artifact.file]]` 检查，使场景能够断言 JSON 元数据文件条目指向 harness 生成的制品，并匹配路径、字节大小和 SHA-256 哈希，同时将 EVM init-code/deploy-manifest 输出公开为 testkit 制品。当前的跨制品 JSON 切片增加了嵌套的 `[[artifact.jsonArtifact]]` 检查，验证 Solana ValueVault 元数据嵌入了与生成的 IDL 制品相同的 IDL JSON，并将 ValueVault IDL/客户端 schema 形状检查移至场景 TOML 中。当前的结构化长度切片为嵌套的 `[[artifact.json]]`/`[[artifact.toml]]` 检查增加了 `length` 断言，并使用它们以声明方式固定 Counter 和 ValueVault 的 ABI 入口、事件、能力、制品、manifest 指令、Solana 指令以及 IDL 指令计数。当前的结构化 schema 切片为嵌套的 JSON/TOML 制品断言增加了 `exists`、`kind` 和 `non_empty` 检查，然后使 Counter 和 ValueVault 将 EVM 部署 manifest 验证为一等场景制品，包括 init-code 模式、缺失的 chain profile、未生成的广播状态、ABI 和能力形状，以及指向生成的 Yul、bytecode 和 init-code 制品的文件引用。

验收标准：

- 当可选的 Solana 工具链可用时，一个场景文件可驱动所有三个优先级目标；添加涵盖的功能不需要新的脚本、recipe 或 CI 步骤。
- 使用不支持的能力的场景会断言带有诊断信息的编译时拒绝（绝不静默跳过目标）。
- Runner 默认是确定性且无网络的；`revm`、`mollusk-svm` 和 `wasmtime` 版本已固定。
- Lean 侧编译器测试（诊断信息、覆盖率清单、形式化锚点）保留在 `Tests/*.lean` 中，不进行移动。

## 工作流 27：分配器抽象统一

目标：根据 [RFC 0008](rfcs/0008-allocator-abstraction.md)，每个目标绑定一个链中立分配器模型；解决工作流 24 的分配器统一决策。

任务：

- M1：将 `ProofForge/IR/Allocator.lean` 泛化为 strategy/region/release 三元组（现有构造函数映射到其上；EmitWat 行为保持不变）；在 `decisions.md` 中记录该决策。
- M2：将 Solana 的 `RuntimeAllocator` (`Backend/Solana/Extension.lean`) 合并到共享模型中 —— `solana.allocator.*` 元数据键保留为 Solana 配置语法，但填充共享类型；IDL 从中渲染；更新了 `Tests/SolanaAllocator.lean`。
- M3：添加显式 EVM 绑定（在 call-scratch 内存上进行 bump；记录 EmitYul/EVM 计划已执行的操作）；定义将 EVM `release` 从拒绝移动到经过检查的 no-op 的标准（受阻于 FV-3 所有权稳健性）。
- M4：testkit（工作流 26）中跨三个 harness 的分配器行为场景；NEAR 断言分配器计数器，EVM/Solana 断言 `release` 作为 no-op 时的可观察追踪等价性。

验收标准：

- 一个 `AllocatorModel` 类型被 EmitWat、Solana 后端和 EVM 绑定使用；不再保留并行的分配器记录。
- 持久状态模型（EVM 存储、Solana 账户、NEAR 存储）明确超出范围且保持不变。
- 通过 `runtime.allocator` 进行的能力门控在针对不支持的 release/strategy 需求的诊断信息中引用 `alloc.*` id。

## 工作流 28：目标组合排序

目标：执行 [target-roadmap.md](target-roadmap.md) (D-034) 中的分层组合。是门控，而非日期；每个实现分支一个里程碑。

**Completion-first rule（D-044，2026-07-03）：** 先按实现优先级完成三个 Tier-0 target
—— `solana-sbpf-asm`、`evm`、`wasm-near` —— 达到完整 DoD（行为一致性以及
D-040 所要求的资源预算），然后才允许推进任何新链。逐项状态记录在
[gate-status.md](gate-status.md)。

### Tier-0 完成（当前最高优先级，阻塞下面所有内容）

- 已完成：NEAR budget reporting 已通过 testkit 以 wasmtime-fuel proxy 形式接入，
  Counter 和 ValueVault baseline 已与 Solana CU、EVM gas 一起锁定。更精确的
  NEAR host-gas 模型仍是 P0 hardening refinement，不再是 Gate G0 blocker。
- 已完成：ValueVault budget baselines 已在
  `testkit/scenarios/value-vault.toml` 中为三个主目标锁定 `solana_cu`、
  `evm_gas` 和 `near_gas`。
- 已完成：EVM semantic-plan migration（工作流 3 / P0-2）已签署。
  ExprPlan、StmtPlan、EntrypointPlan、EventPlan、CrosscallPlan 和 MetadataPlan
  现在驱动 plan-backed EVM lowering 以及 artifact/deploy metadata 路径；
  `just evm-plan`、`just evm-semantic-plan`、`just evm-all`、`just check`、
  Foundry、Anvil 以及 FV-4 可执行 EVM/Yul trace anchors 都已通过。剩余 EVM
  形式化工作是 FV-2 observable event-log semantics 以及更深的
  user-invariant-to-artifact obligations，不再阻塞 P0-2。
- 已完成：Solana Pinocchio CI equivalence（工作流 7 / P0-1）已签署。
  source/reference equivalence suite 已纳入 `just solana-light`；GitHub CI run
  `28675037861` 在 commit `3b2719a` 完成强制 `solana-pinocchio-live` job：
  安装 Agave/Solana CLI、SBF platform-tools、`sbpf`、Surfpool、Node/npm，构建
  ProofForge，并在不允许 skip 的情况下运行全部五个 live dual-deploy 场景。
- Gate P0 已关闭。已经落地的 Aptos/CosmWasm spike 现在可以显式排期 M3/M4，
  但旧的 docs-first research notes 不会自动打开实现范围。

任务：

- 已完成：Gate G0（Tier-0 behavior/budget slice）已关闭。证据记录在
  [gate-status.md](gate-status.md)。
- 已完成：Gate P0（主三链签署）已关闭。Gate G0 加上 D-045 中的生产级硬化，
  已对 Solana P0-1、EVM P0-2 和 NEAR/Wasm P0-3 签署。
- Tier 1a `wasm-cosmwasm`: M1 CosmWasm 宿主导入 + EmitWat 中的 region-allocator ABI (来自 RFC 0008 的 `cosmWasmRegion` 绑定); M2 Counter 制品通过 `cosmwasm-check`; M3 testkit `harness-cosmwasm` 场景通过，且与 `wasm-near` 具有跨目标等价性; M4 注册表阶段 → Experimental。
- Tier 1b `move-aptos` (与 1a 并行): M1 IR → 针对 Counter 子集的 Move 模块打印器; M2 `aptos move test` 门控 + 黄金固定装置; M3 testkit CLI 封装的执行器; M4 能力行已验证; `move-sui` 仅在 M4 之后。
- Tier 2 (每个都在其启用条件之后，见路线图): `wasm-stellar-soroban` 在 CosmWasm M4 之后; `wasm-icp-canister` 在任何代码之前额外需要一份 async/inter-canister 设计笔记; `starknet-cairo` 是 Aptos M4 之后第一个源代码生成路径选择; `ton-tvm`, `algorand-avm`, `cardano-plutus-aiken`, `tezos-michelson-ligo` 遵循“一次仅一个活跃的 sourcegen-spike”规则。
- Tier 3 Bitcoin 策略家族 (在 Gate G2 开启 = 两个 Tier-1 退出): M1 策略 IR (谓词树) + 注册表文档中的 `policy.*` 能力 id; M2 针对 2-of-3 + 时间锁恢复共享策略场景的 rust-miniscript/描述符发射; M3 PSBT/regtest testkit 门控; M4 Lean 策略属性检查 (路径可达性、参与者无遗漏) 作为 decide-checked 定理。`bch-cashscript`, `zcash-shielded` 和 `kaspa-toccata` 保持停留在 M4 之后。

验收标准:

- **主三链完成规约 (D-045)：** ✅ 已关闭。`solana-sbpf-asm`、`evm`、
  `wasm-near` 已达到生产级 DoD；Tier-1 推进现在必须经过显式排期，而不是从
  旧 research notes 隐式继承实现范围。
- 没有显式排期决策之前不落地 Tier-1 代码；在其列出的启用条件之前没有
  Tier-2 目标启动；任何时候最多只有一个 sourcegen spike 处于活跃状态。
- 策略家族目标永远不会出现在合约家族的能力行中; 当 Tier 3 开启时，它们在能力注册表中获得一个单独的 `policy.*` 章节。

## 工作流 29–33: 平台硬化 (规划优先)

这些来自 [2026-07 差距分析](platform-gaps-2026-07.md)。每一个都以 RFC 而非代码开始; 排序钩子列在差距文档中。

- **工作流 29 — CLI 产品界面。** RFC 0009 已接受，M1/M3 已落地：`proof-forge build|emit|check --target <id> --fixture <id>` 已通过兼容层存在，`check` 是真实验证动词，列表命令已接入，legacy flags 已具备 alias/deprecation metadata；`just cli-target-first` 现在会确保 executable callers 继续使用 target-first surface，并由 `Tests/CliTargetFirst.lean` 锁定代表性映射等价性。剩余工作是 M4：只在兼容窗口结束后删除 legacy flag zoo。
- **工作流 30 — 版本控制和兼容性策略。** 涵盖 IR 版本规则 (与 coverage-manifest 门控挂钩)、制品/部署 schema 稳定性、仅追加的能力 id 以及 SDK 弃用策略的 RFC。
- **工作流 31 — 资源预算作为门控。** ✅ 已实现。testkit 场景 schema 支持每步 `solana_cu`、`evm_gas` 和 `near_gas` baseline + tolerance band；runner 会报告 measured budgets 并在 regression 时失败。Gate G0 已在 Counter 和 ValueVault 上关闭三主目标的行为/预算切片。后续 P0 hardening 继续把预算作为回归门禁，并在 NEAR host-gas 模型更精确后替换当前 wasmtime-fuel proxy。
- **工作流 32 — 部署生命周期、升级、签名。** 针对升级策略意图 (`immutable | authority | governance`) 的 RFC，该意图根据每条链诚实地降级 (Solana 升级权限、EVM 不可变/代理、NEAR 账户密钥、Aleo `@noupgrade`) 或被拒绝; 未签名交易签名边界; live-gate 密钥约定。
  M1 已实现：`ContractSpec.upgradePolicy?` 会序列化进 ContractSpec JSON，target
  resolver 会在代码生成前拒绝不支持的 target/policy 组合，已解析 plan 会为支持的策略
  发出 `upgrade.policy.*` 制品 metadata。
- **工作流 33 — 运行时错误模型 + 客户端生成。** 具有每目标编码和 `expect.error` 场景词汇的可移植错误代码 (与工作流 31 的 schema 变更一起规划); 然后是一个客户端 schema 层，将 Solana IDL/TS 客户端生成推广到所有目标 (实现等待 testkit M3)。

  里程碑:

  - M1：向可移植 IR 的 `assert`/`assertEq` 构造加入 `ErrorRef`
    (`assertion_id` + 可选 `user_code`)，并更新所有后端 pattern match。
    `message` 保留为 fallback 文本。✅ 已实现。
  - M2：实现 EVM、Solana 和 NEAR 的每目标错误编码：EVM 以
    `abi.encode(uint32 assertion_id, string user_code)` revert；Solana 返回
    `ProgramError::Custom(assertion_id)`；NEAR panic 使用
    `PF:{id}:{code}` 前缀。✅ 已实现。
  - M3：扩展 testkit schema 和 harness 的 `expect.error`，让场景步骤可以在失败时断言精确
    `assertion_id`/`user_code`。✅ 已实现：`testkit/scenarios/error-ref.toml`
    跨 `wasm-near`、`evm` 和 `solana-sbpf-asm` 验证 assertion id；
    `error-ref-user-code` 场景额外断言 EVM/NEAR 的精确 `user_code`。Solana
    按设计保持 assertion-id only，因为其运行时编码是
    `ProgramError::Custom(assertion_id)`。
  - M4：定义目标中立的 `ContractSpec` JSON schema，并从它生成 Solana
    IDL/client、EVM ABI wrapper 和 NEAR wrapper 草图。
    ✅ 已在 client-schema / sketch 边界实现：`ContractSpec` JSON 现在会发射从
    可移植 `ErrorRef` assertions 派生的目标中立 `errors` catalogue，包含
    `assertionId`、可选 `userCode`、fallback `message` 和所属
    `entrypoints`；生成的 EVM 和 NEAR wrapper 草图会嵌入同一份 `ERRORS`
    catalogue，并暴露 assertion-id 查询和原生错误解析 helper
    (`decodeProofForgeRevert`, `parseProofForgePanic`)；Solana IDL/client
    输出会嵌入同一份错误 catalogue，并暴露 assertion-id / custom-error 查询
    helper。门禁：`Tests/ContractSpecJson.lean`、`Tests/ContractClient.lean`
    和 `Tests/SolanaSdkManifest.lean`。更深入的生产级客户端 ergonomics 移到
    SDK 生态完整性 backlog。

## 工作流 34：Contract Source 产品化（统一 authoring 层）

目标：让 `contract_source` 成为 portable 智能合约的**唯一产品级 authoring 面**。
应用作者用 Lean SDK 语法写一次业务逻辑；**`proof-forge build --target <id>`**
选择链，编译器负责 capability routing、extension、ABI/layout 和制品发射。
应用模块里不应手写 `ContractSpec`、`.evm-methods` 或 target 特定的部署 plumbing。

相关文档：

- [Authoring model](authoring-model.md)
- [SDK ecosystem gaps (2026-07)](sdk-ecosystem-gaps-2026-07.md)
- [Shared scenario](shared-scenario.md)
- PR #11 统一 EVM 入口（legacy `Lean.Evm` / LCNF 已移除）

### 设计契约

```text
contract_source / Token SDK  (portable 业务逻辑 + typed capability intent)
  -> source AST
  -> ContractSpec / TokenSpec / portable IR
  -> target resolver + capability routing   <-- 由 --target 选择
  -> target semantic plan
  -> printer / assembler / package emitter
  -> artifacts (Yul/bytecode, sBPF, WAT, …) + manifests + clients
```

本工作流新工作的规则：

1. **Portable 优先：** state、entrypoint、event、算术和控制流在源码里保持 target 中立，
   除非某个 capability 确实没有共享形态。
2. **编译时选 target：** 链的选择在 CLI/config（`--target evm`、
   `--target solana-sbpf-asm` 等），而不是在 contract 模块里做 `#ifdef` 式复制。
3. **Extension 诚实降级：** Solana account/PDA/CPI、EVM payable/receive、
   NEAR promise 等通过 typed SDK 形式和 capability routing 挂接；
   不支持的组合必须给出显式 diagnostic。
4. **不要第二套产品语言：** Builder 字符串 fixture 和 `.learn` 仍是编译器/测试输入；
   新 SDK 能力首先落在 `ProofForge.Contract.Source`（或 `Token`）。

### 阶段 CS-0 — 统一编译器入口 ✅（PR #11 已落地）

| ID | 任务 | 状态 |
|---|---|---|
| CS-0.1 | 所有 EVM 示例构建走 `ContractLoader` + portable IR | ✅ |
| CS-0.2 | 移除 legacy `ProofForge.Evm`、LCNF `EmitYul`、`.evm-methods` | ✅ |
| CS-0.3 | 迁移 `Examples/Evm/Contracts/*` 到 `contract_source` / `ContractSpec` | ✅ |
| CS-0.4 | 刷新 CI 门禁（build-examples、Foundry、Anvil、docs-check） | ✅ |

### 阶段 CS-1 — Portable authoring 核心

重点：一套语法写跨 target 业务逻辑；收紧 `contract_source` 里 portable 与
target extension 的边界。

| ID | 任务 | 验收标准 |
|---|---|---|
| CS-1.1 | 在 `authoring-model.md` 文档化 portable 子集 vs target extension 形式，并给出 EVM/Solana/NEAR 示例 | 作者能区分哪些语句可在所有主 target 编译 vs 仅单一 target |
| CS-1.2 | 当 portable 语法使用了所选 `--target` 不支持的 capability 时给出 compiler diagnostic | 错误包含 target id、capability id 和源码位置 |
| CS-1.3 | 为共享场景（`Counter`、`ValueVault`）添加 `contract_source` 参考模块；把 Builder-only 示例降级到 `Tests/` 或 `ProofForge/Contract/Examples/` | `Examples/` 树只展示 `contract_source` 产品风格 |
| CS-1.4 | 扩展 Learn → `contract_source` 等价测试（FV-6），覆盖 portable entrypoint/state/event | 配对的 `.learn` 与 `contract_source` fixture 产出等价 `ContractSpec` |
| CS-1.5 | Target-first 项目布局约定：一个 `*.lean` contract 模块 + `proof-forge build --target <id>` 对应一个制品；不做 per-chain 源码分叉 | 写入 onboarding，并有一个多 target 示例：同一文件把 Counter 编译到 EVM + Solana + NEAR |

当前 CS-1.2 切片：`wasm-near` 的 contract_source build 现在会先把加载到的
`ContractSpec` 交给 `Target.resolveSpec`，再进入 EmitWat lowering。plan-backed
EmitWat 路径会在所选 target 不支持某 capability 时拒绝，并在诊断中包含 target
id、capability id、operation name 和 source marker；`just
contract-source-diagnostics` 用一个负向 `contract_source` fixture 锁住这条 CLI 行为。

当前 CS-1.3/CS-5.1 切片：ValueVault 现在有面向应用的共享
`contract_source` 模块：`Examples/Shared/ValueVault.lean`。`just
portable-value-vault` 会把同一个 `.lean` 文件构建到三条主 target：EVM
bytecode/Yul/metadata、Solana sBPF assembly 加 manifest/IDL/TS client
metadata，以及 NEAR/Wasm WAT 加 deploy metadata。legacy
`Examples/Learn/ValueVault.learn` 继续作为等价 fixture 保留，不再是推荐的产品
authoring 路径。

当前 CS-1.4 切片：`Tests/SharedContractSource.lean` 现在会通过产品级
`contract_source` loader 加载 `Examples/Shared/Counter.lean` 和
`Examples/Shared/ValueVault.lean`，把降级后的 IR module 与 canonical
`ProofForge.Contract.Examples.*` spec 对比，并把配对的 legacy `.learn`
fixture 与这些共享 module 对比。ValueVault 还会比较从共享 `.lean` 源和 legacy
`.learn` fixture 渲染出的 Solana package manifest，因此当前 shared scenario
的等价门禁覆盖 portable state、entrypoint、event 以及 package-facing metadata。

当前 CS-1.5/CS-4.1 starter template 切片：`templates/portable-counter`
现在是可直接 target-first build 的 `contract_source` starter。它的 namespace
与文件 basename 对齐，因此 `ContractLoader` 可以在不额外传 CLI flag 的情况下解析
生成的 `Counter.spec`；README 也改为直接用模板源文件运行
`proof-forge build --target ...`，分别生成 EVM、Solana sBPF assembly 和
NEAR/Wasm 制品。现有 `portable-counter-multi-target` smoke 可以通过设置
`PORTABLE_COUNTER_SOURCE=templates/portable-counter/Counter.lean` 来验证该模板。

### 阶段 CS-2 — EVM stdlib 的 `contract_source` 化

重点：用可 import 的 `contract_source` 模块替换 Builder 字符串 stdlib。
对应 SDK 生态 P0/P1 的 access pattern 和部分 token 工作。

| ID | 任务 | 验收标准 |
|---|---|---|
| CS-2.1 | 把 `Examples/Evm/Contracts/stdlib/Ownable.lean` 改写为 `contract_source` 模块，带 `onlyOwner` 风格 entry guard | `--target evm` 可构建；Foundry smoke 覆盖 owner transfer/renounce |
| CS-2.2 | 把 `Pausable.lean` 改写为 `contract_source`，含 pause/unpause + `whenNotPaused` guard | Foundry smoke 覆盖 paused/unpaused 路径 |
| CS-2.3 | 把 `ERC20.lean` 改写为 `contract_source` stdlib（不是 Builder map boilerplate） | 匹配规范 ERC-20 selector/event；Foundry 生命周期 smoke |
| CS-2.4 | 添加可复用 `ReentrancyGuard` 模块（`contract_source`） | `VerifiedVault` 使用 stdlib guard，而不是手写 lock state |
| CS-2.5 | 为 `contract_source` 补齐 `import`/`open` stdlib 模块的故事 | 两个示例合约可组合 Ownable + ERC20，无需 copy-paste |
| CS-2.6 | 统一 `TokenSpec` ERC-20 发射与 `contract_source` token 模块（单一 planning 边界） | 无论用 Token SDK 还是 contract 模块 authoring，token 语义一致 |

### 阶段 CS-3 — EVM capability 在 SDK 语法中的表面

重点：把已能 lower 的 IR 能力通过 typed `contract_source` 形式暴露出来，
让作者不必为常见 EVM 模式退回 Builder。交叉引用
[sdk-ecosystem-gaps-2026-07.md](sdk-ecosystem-gaps-2026-07.md) EVM P0/P1。

| ID | 任务 | 优先级 | 验收标准 |
|---|---|---|---|
| CS-3.1 | `payable` entry / `msg.value` 语法（`nativeValue` routing） | P0 | value-bearing entry 的 authoring 语法；Foundry value 测试 |
| CS-3.2 | Native ETH transfer helper（向 EOA/contract 的普通 transfer） | P0 | 示例里不再手写 `crosscallInvokeValueTyped(u64 0)` |
| CS-3.3 | Entry modifier / guard（`onlyOwner`、`whenNotPaused`、role guard） | P0 | 降级到 portable IR 检查；误用时给出 diagnostic |
| CS-3.4 | 构造函数动态 ABI（string、bytes、动态数组） | P0 | CLI + 制品 metadata；Anvil smoke 使用非空 constructor args |
| CS-3.5 | Custom errors（Solidity 风格 selector） | P1 | 结构化 revert surface + client decode helper |
| CS-3.6 | ERC-165 `supportsInterface` 模块 | P0 | Foundry interface probe 测试 |
| CS-3.7 | AccessControl roles（grant/revoke/hasRole） | P0 | `contract_source` 中带 role guard 的 entry |
| CS-3.8 | ERC-721 核心（ownerOf、transfer、safeTransferFrom、mint、burn） | P0 | Foundry NFT 生命周期 smoke |
| CS-3.9 | CREATE2 factory 模板模块 | P1 | 确定性部署示例 + metadata |
| CS-3.10 | Proxy/upgrade 模式（UUPS 或 transparent），对齐工作流 32 `upgradePolicy` | P1 | 诚实 lowering，或按 policy 显式 reject |
| CS-3.11 | ERC-1155 单项转账核心 | P1 | ✅ `Stdlib/ERC1155.lean` 覆盖 balance、operator approval、mint、burn、单项 `safeTransferFrom`；Foundry smoke 覆盖生命周期。批量转账和 receiver callback 仍未完成 |

### 阶段 CS-4 — 项目开发体验

重点：开发者打开仓库、写 `contract_source`、跑 build/test/deploy，
无需碰编译器内部。

| ID | 任务 | 验收标准 |
|---|---|---|
| CS-4.1 | `proof-forge init`（或文档化 template repo），含 `contract_source` stub + 多 target `justfile` | 新项目可在 `evm` 和至少一个其他主 target 上构建 Counter |
| CS-4.2 | Foundry workspace 集成：生成制品以稳定路径喂给 `forge test` / `forge script` | 文档化工作流；CI recipe |
| CS-4.3 | 产品化 EVM 的 `ContractClient`（来自 `ContractSpec` JSON 的 ABI wrapper + deploy helper） | 在制品旁生成 TypeScript 或 Rust client |
| CS-4.4 | 超越 metadata 的 deploy 命令：用 chain profile 做 RPC broadcast + tx/receipt 制品 | Anvil 本地 + 一个文档化 testnet profile |
| CS-4.5 | VS Code/Cursor workspace 推荐 + 从 `proof-forge check --target <id>`  surfaced diagnostic | 部分关闭 onboarding 摩擦项 R6 |

### 阶段 CS-5 — 跨 target 一致性与 testkit

重点：在三条主链上证明统一 authoring 故事。

| ID | 任务 | 验收标准 |
|---|---|---|
| CS-5.1 | 扩展 testkit 场景：`contract_source` 编写的 Counter/ValueVault 在 `evm`、`solana-sbpf-asm`、`wasm-near` 上 | `just testkit` 覆盖同一 scenario 文件、不同 `--target` 制品 |
| CS-5.2 | 为新 stdlib 合约建立 resource budget baseline（EVM gas、Solana CU） | ✅ 扩展工作流 31 budget；回归失败 CI |
| CS-5.3 | Authoring model 完整示例：一个业务模块、三个 target、零源码分叉 | ✅ docs 教程（EN + zh，经 translate pipeline 同步） |

当前 CS-5.1 testkit 切片：`testkit/scenarios/counter.toml` 和
`testkit/scenarios/value-vault.toml` 现在声明 `source =
"Examples/Shared/*.lean"`。EVM、Solana 和 NEAR harness 会消费这个字段，并
对 Counter/ValueVault 运行 target-first `proof-forge build --target ...
--root . <source>`，而不是只走 fixture 发射。场景断言现在会固定
`contract-sdk` 元数据、NEAR 制品元数据、Solana source/IDL/client 制品、
metadata 文件引用，以及已有的行为/预算追踪。fixture-only 路径继续保留给
`error-ref` 和 allocator probes 等专门的编译器/运行时场景。

当前 CS-5.2 budget 切片：`testkit/scenarios/counter.toml` 与
`testkit/scenarios/value-vault.toml` 为共享 `contract_source` 模块固定逐步
`evm_gas`、`solana_cu`、`near_gas` baseline。每个场景在
`[scenario.reference.toolchain]` 下记录参考 harness 工具链。
`just testkit-budget-gate` 通过统一 testkit 运行 Counter 与 ValueVault；CI
仍执行完整 `just testkit`，因此 budget 回归会阻断默认 pipeline。

当前 CS-5.3 教程切片：[tutorials/portable-contract-three-targets.md](../tutorials/portable-contract-three-targets.md)
逐步讲解 `Examples/Shared/Counter.lean` 与 ValueVault 的 build 命令、
`just portable-counter-multi-target`、testkit parity 与 budget gate。中文镜像位于
[docs/zh/tutorials/portable-contract-three-targets.zh.md](zh/tutorials/portable-contract-three-targets.zh.md)，
并由 translate manifest 跟踪。

### 阶段 CS-6 — 文档与 legacy 清理

| ID | 任务 | 验收标准 |
|---|---|---|
| CS-6.1 | 重写 `docs/targets/evm.md` pipeline 章节为统一入口（移除 EmitYul/Lean.Evm） | ✅ 当前 EVM target note 描述 `contract_source` / `ContractSpec` → portable IR → EVM semantic plan → Yul AST/printer → solc，并把旧 EVM/LCNF 路线标为 legacy/research |
| CS-6.2 | 更新 `development-standards.md` library root（去掉 `ProofForge.Evm`、`EmitYul`） | ✅ 当前 roots 与 `lakefile.lean` 对齐；authoring 指引使用 `contract_source`，并把旧 EVM/LCNF 路线标为 legacy/research |
| CS-6.3 | 关闭工作流 24 条目：声明 LCNF→EmitYul 已移除；记录 `contract_source` 为 EVM 产品 pipeline | ✅ decision log + RFC 0004 对齐（D-046） |
| CS-6.4 | `Examples/Evm/README.md` 变更时保持 `docs/zh/examples-evm-README.zh.md` 同步 | ✅ `just docs-check` 通过；translate manifest 跟踪 `Examples/Evm/README.md` |

当前 CS-6.2 切片：`docs/development-standards.md` 及其 zh 镜像现在列出
`lakefile.lean` 中的当前 Lake roots，从当前包规范里移除了 `ProofForge.Evm` 和
`ProofForge.Compiler.LCNF.EmitYul`，并明确 `ProofForge.Backend.Evm` 是编译器实现
代码，不是产品级 authoring SDK。`Examples/` 的新示例应优先使用
`contract_source`；backend-only probe 应放在 `Tests/` 或
`ProofForge/IR/Examples/` 下。

当前 CS-6.1 切片：`docs/targets/evm.md` 及其 zh 镜像现在描述当前统一的 EVM
产品流水线、从 `ContractSpec` 派生 selector/ABI、target-first 示例流程、当前 backend
模块布局、metadata source kind `contract-sdk`，以及 EVM 门禁。旧的 `.evm-methods`
和 `ProofForge.Evm` / `Lean.Evm` / LCNF `EmitYul` 路线只作为 legacy compatibility
或历史研究背景保留。

当前 CS-6.3 切片：[decisions.md](decisions.md) D-046 记录移除
`ProofForge.Evm`、LCNF `EmitYul` 和 `.evm-methods`；[RFC 0004](rfcs/0004-evm-semantic-plan.md)
为 **Accepted**，并将 `contract_source` → portable IR → EVM semantic plan →
Yul → solc 作为唯一 EVM 产品流水线。[INDEX.md](INDEX.md)、
[validation-gates.md](validation-gates.md) 和 [targets/evm.md](targets/evm.md)
不再把 LCNF 描述为 live compiler 路线。

当前 CS-6.4 切片：`Examples/Evm/README.md` 与
`docs/zh/examples-evm-README.zh.md` 在统一 `contract_source` 入口上保持一致；
translate manifest 条目使 English README 变更时 `just docs-check` 保持绿色。

### 建议排期（工作流 34）

1. **CS-1** portable 边界 + diagnostic（解锁诚实的 multi-target authoring）。
2. **CS-2** EVM stdlib 的 `contract_source` 化（开发者立刻可见的收益）。
3. **CS-3** EVM P0 SDK blocker（可与 CS-2 并行 CS-3.1–3.4）。
4. **CS-4** 项目 DX（stdlib + payable/constructor 落地后）。
5. **CS-5** 三条主 target 的 testkit 一致性证据。
6. **CS-6** 文档/decision 清理持续进行，而不是只在最后。

### 验收标准（工作流完成）

- `Examples/Evm/Contracts/` 下每个文件都用 `contract_source` 编写，或组合 stdlib
  `contract_source` 模块；Builder-only EVM 示例只存在于编译器 test/fixture 路径。
- 新开发者可写 portable contract 模块并运行
  `proof-forge build --target evm|solana-sbpf-asm|wasm-near`，无需编辑链特定源码。
- [sdk-ecosystem-gaps-2026-07.md](sdk-ecosystem-gaps-2026-07.md) 中的 EVM P0 SDK blocker
  要么通过 `contract_source` 实现，要么显式 reject 并给出 diagnostic。
- CI 覆盖 stdlib + 至少一个 multi-target 共享场景构建。

## 建议顺序

工作流 1, 1.5, 2–3, 6–7 (注册表、可移植 IR、EVM 制品元数据、Solana asm) 已基本完成; 剩余的每目标细节存在于每个工作流中。后续顺序遵循 [target-roadmap.md](target-roadmap.md) (D-034) 的层级门控:

0. 架构收敛后续工作 (工作流 24) 以及来自形式化验证路线图 (工作流 25) 的 FV-1/FV-2。与此同时，完成差距分析中的平台硬化后续：RFC 0009 兼容窗口之后的 CLI M4 legacy-alias removal、testkit runtime error vocabulary，以及版本控制 / 部署生命周期策略 (30/32，docs-agent 并行轨道)。
0b. **Contract Source 产品化（工作流 34）：** 统一 EVM 入口（CS-0 ✅）之后，先落地 portable authoring 边界（CS-1）、EVM stdlib 的 `contract_source` 化（CS-2），再推进 EVM SDK P0 surface（CS-3），然后才是 broader 项目 DX（CS-4）。这是 PR #11 之后的主产品轨道，并覆盖下方 SDK 生态完整性里的 EVM 条目。
1. **并行：** 统一 testkit (工作流 26) 和分配器统一 (工作流 27) —— testkit M1/M2 对分配器 M1/M2 没有依赖；分配器 M4 在 testkit M3 之后落地。
2. **CLI target-first 迁移：** M3 调用方迁移已经落地并由门禁保护；M4 只在兼容窗口结束后删除 legacy flags。
3. **并行第 1 层级（显式排期后）：** `wasm-cosmwasm` (工作流 5/28) 和 `move-aptos` (工作流 8/28)。
4. 每个赋能者的第 2 层级：CosmWasm 之后是 Soroban；Aptos 之后是 Sui 和源代码生成通道 (首选 Starknet)；ICP 额外排在异步设计笔记之后；一次进行一个源代码生成 spike (工作流 12–19/22, 28)。
5. Gate G2 的 Bitcoin 策略家族 (工作流 11/15/20/21, 28) —— 首先是 miniscript，然后是其后的 CashScript/Zcash/Kaspa。
6. 多链 Token SDK 后续工作 (工作流 23) 同步继续，剩余的实时门控 CI 矩阵 (工作流 9) 随每个目标而增长。
7. 云平台设计更新 (前提条件：两个以上处于 Experimental 状态且具有共享场景一致性的目标；D-010)。

## SDK 生态完整性（P0 后硬化）

Gate P0 关闭证明了三条主链的编译器正确性已经达到 production-grade：编译器、制品发射、部署清单、testkit 一致性和资源预算都已经具备门禁。但
“production-grade compiler” 不等于“开发者可以写任意合约并部署”。下一阶段硬化目标是
**SDK 生态完整性**：确保每条主链都能覆盖真实开发者的常见合约模式，而不仅是
Counter 和 ValueVault。完整差距分析见
[sdk-ecosystem-gaps-2026-07.md](sdk-ecosystem-gaps-2026-07.md)。

**原则：** Tier-1 targets（CosmWasm、Aptos）保持冻结，直到每条主链的 P0 SDK
blocker 关闭。这里的 “P0 SDK blocker” 指的是：缺失该能力就意味着真实开发者无法编写常见合约模式。

### EVM SDK blockers（1 个 P0 开放，4 个 P0 已关闭，10 个 P1）

详细跟踪见 **工作流 34 阶段 CS-2/CS-3**；实现必须落在
`contract_source` / Token SDK 语法，而不是 Builder fixture。

- ✅ P0：ERC-20 完整化 —— `Stdlib/ERC20.lean` mixin（transfer/approve/transferFrom/mint/burn + Lean 证明）+ golden Yul + compose 测试
- ✅ P0：ERC-721 NFT —— `Stdlib/ERC721.lean` mixin（ownerOf/transferFrom/safeTransferFrom/mint/burn）；**限制：** safeTransferFrom 不调 onERC721Received（降级为 P1）
- ✅ P0：ERC-165 supportsInterface —— `Stdlib/ERC165.lean` mixin + golden Yul
- ✅ P0：AccessControl roles —— `Stdlib/AccessControl.lean` mixin（grantRole/revokeRole/hasRole + guard_role）+ golden Yul
- P0：构造函数动态类型参数 —— CLI ABI 编码已实现（CS-3.4: string/bytes/uint256[] head+offset+tail）；**缺口：** 无 example 使用 cstring/cbytes/u256array、无正向 Foundry/Anvil smoke、runtime 不消费 constructor arg（无 Yul constructor body）
- P1：ERC-1155 批量转账 / receiver callback、ERC-4626 vault、ERC-2612 permit、custom errors、
  storage packing、batch operations、factory deployment template、AMM、
  Pausable auth、ERC-721 onERC721Received

### Solana SDK blockers（5 个已跟踪 P0，4 个已关闭，7 个 P1）

- ✅ P0：Account constraint enforcement。owner validation 现在已经把 `owner=program`、
  `owner=executable` 和具名 owner-account 引用降级到 sBPF prologue；未知 owner
  引用会产生显式诊断；`reallocAccount` 和 `contract_source` 里的
  `realloc account to N;` 语句现在会发射静态 account-data reallocation 元数据、
  manifest/IDL action 记录，以及带 `MAX_PERMITTED_DATA_INCREASE` 检查的 sBPF
  data-length store。Surfpool 行为验证仍作为后续验证扩展。
- ✅ P0：SPL Token close-account CPI 现在具备 builder helper、typed
  `contract_source` 语法、legacy Learn 语法、manifest/artifact 元数据，以及 tag `9`
  的 sBPF instruction-data packing，并由 `Tests/SolanaCpiPacking.lean` 和
  `Tests/LearnSource.lean`、`Tests/CliTargetFirst.lean` 覆盖。
  `just solana-spl-token-close-account-cpi-web3` 现在覆盖 live Surfpool/Web3.js
  验证路径：通过 CPI 关闭空 SPL Token account、验证 destination 租金 lamport
  回收，并记录 marker state。close-account 的 Pinocchio equivalence 仍作为
  reference-breadth 后续项。
- ✅ P0：ComputeBudgetInstruction（设置 compute unit limit、priority fees）已经作为交易侧 compute-budget
  建议落地到 Solana manifest、IDL、生成的 TypeScript client 和 package metadata。生成的 helper
  会根据所选 entrypoint 发射 `ComputeBudgetProgram` 前置指令；它有意不作为合约程序内部 syscall lowering。
- ✅ P0：Token-2022 direct sBPF CPI lowering 现在覆盖 Solana builder API、
  typed `Surface` wrapper、manifest/IDL 元数据以及 sBPF instruction-data
  packing 中的 transfer-fee、non-transferable、metadata-pointer、
  default-account-state、immutable-owner、permanent-delegate、
  interest-bearing、memo-transfer、transfer-hook 初始化以及 pausable 指令布局。已覆盖
  `initialize_transfer_fee_config`、`transfer_checked_with_fee`、费用
  withdraw/harvest、`set_transfer_fee`、`initialize_non_transferable_mint`、
  `initialize_metadata_pointer`、`initialize_default_account_state`、
  `initialize_immutable_owner`、`initialize_permanent_delegate`、
  `initialize_interest_bearing_mint`、`enable_required_memo_transfers`
  `initialize_transfer_hook`、`initialize_pausable_config`、`pause` 和 `resume`；
  生成程序的 Token-2022 direct-CPI Surfpool/Web3.js gate 会验证初始化后的扩展状态以及 Pausable 的 pause/resume 状态切换。
- ✅ P1：Token-2022 transfer-hook execute/extra-account-meta 路由现在具备生成的
  hook 程序 fixture、外部 `Execute` discriminator 调度、按 entrypoint 区分的账户约束、
  validation account 的 PDA signer seeds、静态 extra-account-meta TLV 序列化、
  manifest/IDL 元数据、target-first fixture 路由，以及
  `just solana-spl-token-2022-transfer-hook-web3` Surfpool/Web3.js 验证：初始化
  validation PDA、通过 Web3.js 路由两个静态 extra accounts、接受允许的转账，
  并拒绝超限转账。
- ✅ P1：Associated Token `create_idempotent` CPI 已具备 builder helper、
  typed `Surface` wrapper、`contract_source` 语法、target-first fixture 路由、
  manifest/IDL/artifact 元数据（包含所选 token program）、
  `associated-token.create_idempotent` 的 sBPF 数据打包、独立的 6-account
  CPI account-meta frame，以及 `just solana-associated-token-cpi-web3`
  Surfpool/Web3.js 验证：创建规范 ATA，并再次调用 idempotent 路径。
- P1：Memo/Stake/Vote CPI、confidential_transfer、
  Pinocchio reference ≥10、Metaplex NFT、Anchor-style derive macro、
  address lookup tables

### NEAR SDK blockers（6 个 P0，10 个 P1）

- P0：Promise API（promise_create、promise_then、promise_and、batch actions、
  promise_results、callback patterns）
- P0：NEP-141 fungible token（ft_transfer、ft_balance_of、storage deposit）
- P0：signer_account_id host import
- P0：attached_deposit / native value host import
- P0：Aggregate ABI（entrypoint 参数中的 structs、dynamic arrays）
- ✅ P1：block_timestamp（`block_timestamp` host import + `.contextRead .timestamp` 降级 + Surface/Source 辅助）
- ✅ P1：epoch_height（`epoch_height` host import + `.contextRead .epochHeight` 降级 + Surface/Source 辅助）
- ✅ P1：random_seed（`random_seed(register_id)` host import + `.contextRead .randomSeed` 降级 + Surface/Source 辅助，返回 `Hash`）
- ✅ P1：near-api-js client options（view 调用使用 `NearViewOptions`，function call 使用 gas/attached-deposit `NearCallOptions`）
- ✅ P1：NEP-145 storage-management starter（`storage_deposit`/`storage_balance_*` 的 U64 投影 + Hash map target-first/offline-host smoke）
- P1：完整 NEP-145 JSON balance objects/withdraw/refund/storage byte accounting、
  NEP-148 metadata、NEP-171 NFT、keccak256/crypto、storage_remove、
  gas accounting APIs、real NEAR broadcast smoke
