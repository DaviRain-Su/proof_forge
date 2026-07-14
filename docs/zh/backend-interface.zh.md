# 规范后端接口

后端从已检查的 canonical contract 和解析后的 `CapabilityPlan` 开始。只有目标
语义计划可以选择物理存储、ABI 布局、host import/syscall 和目标 helper。渲染器
消费该计划，并输出现有目标制品格式。

目标计划模块不得导入 `Frontend.Surface`，canonical builder 不得导入
`IR.Contract`，目标计划类型声明不得嵌入原始 Yul、sBPF 或 Wasm AST 节点。
`just canonical-boundary` 会检查这些依赖约束。

## Host operation

每个 `HostOp` 都有精确的 id、版本与签名，包括参数类型、返回类型和 effect
类别。解析必须 fail-closed。以下任一情况都会在渲染前导致编译失败：

- id 或精确版本未知；
- 参数数量或任一参数类型不匹配；
- 声明的返回类型不匹配；
- operation 用在错误的 effect 位置；
- 所选目标没有该精确 operation 的 handler。

系统不支持版本范围、隐式类型转换、邻近版本查找或通用 fallback handler。
目标扩展只有在 capability 和精确 handler 都注册并通过测试后才能使用。

## Queue 与 Set 展开

Surface v2 的 `Queue` 和 `Set` 是有界编写结构。规范化要求显式容量，并将操作
展开为现有 canonical 状态与控制原语。后端不新增 Queue/Set 语法，渲染器也不
实现集合算法。非法容量、溢出、下溢，或目标无法物化展开后的原语时，必须在
制品发射前失败。

## 目标验收

主要公开路径仍是 `evm`、`solana-sbpf-asm` 和 `wasm-near`。Canonical builder
必须在冻结的 Legacy 共享子集上通过计划与制品 parity，再通过产品场景和架构
边界门禁。禁止平行 `*-core` id 和仅输出 skeleton 的路径。

外部语法与运行时工具是证据门禁，不是编译器语义 fallback：EVM 使用 `solc`、
Foundry 和 Anvil；Solana 使用 sBPF assembler/verifier，以及可选的
Mollusk/Surfpool/Pinocchio 套件；NEAR 使用 `wat2wasm` 和 offline host。需要缺失
工具的 live-network 套件保持可选，不进入默认 required CI。

另见[规范编译器架构](architecture.zh.md)和[验证门禁](validation-gates.zh.md)。
