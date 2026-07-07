# Authoring Model

ProofForge 不应该要求应用开发者直接编写 `ContractSpec` 对象。
`ContractSpec` 是编译器内部边界：源码语法会降低到它，target routing 会消费它，
后端再从对应 IR 和 target-extension metadata 打印目标制品。

## 层次

当前栈里有三层 authoring layer：

| 层 | 状态 | 作用 |
|---|---|---|
| Lean embedded SDK / `contract_source` | 已实现的 v1 embedded source syntax | 当前 authoring surface。它让仓库能用 Lean 语法表达 portable state、entrypoint、event、arithmetic、SDK intent，以及 Solana account/PDA/CPI declaration，而不用手写 `ContractSpec` 字符串。 |
| Legacy `.learn` parser | 已实现 v0 standalone parser 与 CLI compatibility entrypoint | 兼容性/冒烟输入，会降低到同一个编译器内部 `ContractSpec` / `TokenSpec` 边界；它不应该继续长成第二套产品语言。 |
| `ContractSpec` / IR | 编译器内部制品 | 进入 target routing、capability check、backend lowering、AST/printer stage、manifest、IDL、client 和 deployable package 的稳定边界。 |

当前仓库的预期用户体验是 Lean-first：开发者使用 Lean 语法和 SDK helper，
编译器再把这些值降低到 `ContractSpec`、`TokenSpec`、portable IR 和
target-extension plan。独立 `.learn` parser 仍有价值，因为它能从文件输入验证同一个
lowering 边界，但新的 SDK 工作应该优先落在 Lean/SDK 层。
`proof-forge --learn --target <id>` 和 `proof-forge --learn-token --target <id>`
因此是 legacy CLI path：它们复用同一个编译器内部边界，而不是定义一套新的产品语言。

因此，带有较多字符串的 `ContractSpec` 与 Builder 示例应被看作编译器 fixture，
不是产品 surface。它们描述的是源码经过 parsing、capability routing 和
target-extension expansion 后交给编译器消费的同一个程序形状。应用开发者应越来越多
看到 Lean SDK 语法和 typed helper；测试可以继续保留 Builder 与 `.learn` fixture
作为已评审的等价输入。

编译器内部的 source AST 和 IR 边界在 parsing 之后用字符串保存 identifier 是正常的；
这不是 authoring model。产品方向是用户编写 Lean SDK 语法，typed helper 尽量先检查
名称和引用，然后编译器才把这些名称物化到 `ContractSpec`、manifest、IDL、client 和
backend AST 里。

## 源码原则

- Portable contract 应表达业务逻辑，而不是 target-specific deployment detail。
- Target-specific capability 应通过 typed SDK form 请求，而不是 raw string plumbing。
- Chain dispatch 属于 build configuration 和 target routing。只要某个 target
  能提供等价能力，源码就应该保持可复用。
- Solana account/PDA/CPI declaration 这类 target extension 可以出现在 source
  中，但前提是合约确实需要 chain-native semantics。这些 extension 会降低为
  target metadata 和 helper action；除非多个链家族共享同一语义形态，否则不进入
  portable IR constructor。
- 真实协议字节可以继续使用 literal string，例如 PDA literal seed。account、
  owner、capability name、method 或 deployment configuration 不应该主要靠字符串表达。

## 当前语法边界

`ProofForge.Contract.Source` 是当前可执行的 Lean syntax layer，覆盖：

- portable scalar state；
- 带 typed parameter 的 entrypoint 和 query；
- local binding、assignment、return、event emission 和 checked arithmetic syntax；
- Solana allocator selection；
- Solana account constraint，包括 writable 和 signer declaration；
- Solana PDA declaration 和 derivation statement；
- 带静态目标长度的 Solana account reallocation statement；
- Solana System Program `transfer` 与 `create_account` CPI declaration 和
  invocation statement；
- Solana SPL Token `transfer_checked`、`mint_to`、`burn`、`approve`、`revoke`、
  `close_account` 和 `set_authority` CPI declaration 和 invocation statement；
- Solana log、return-data、compute-unit、memory、crypto 和 sysvar helper
  statement。

ERC-style composition fixture 位于 `Examples/Evm/Contracts/`，因为它们有意覆盖
EVM stdlib 和 ABI 行为。Shared token 产品示例应使用更高层的 `TokenSpec` intent
边界；参见 `Examples/Shared/FungibleToken.lean`。

`ProofForge.Contract.Token` 是当前 token SDK planning 边界。Lean-authored
`TokenSpec` 会在 EVM 上路由为 ERC-20，在 Solana 上路由为结构化 SPL Token /
Token-2022 deployment plan。Solana plan 会记录 mint account 创建、associated
token account、`mint_to`、`transfer_checked`、`approve`、`burn`、`revoke`、
authority change、Token-2022 extension 初始化、Token-2022 transfer-fee
collection flow（direct withheld-fee withdraw，以及 harvest-to-mint 后再从
mint withdraw），以及 non-transferable token 初始化（拒绝 `TransferChecked`，
但仍允许 burn），以及 Web3.js 或 client generation 需要的 Solana program id。

`ProofForge.Contract.Learn` 仍会解析 `Examples/Learn/` 下 checked-in 的
`.learn` 示例，生成一个小型 source AST，并将该 AST 降低到 `contract_source`
共用的 `ContractSpec`/portable IR 边界。CLI 可以通过 `--target evm` 把
`.learn` 输入路由到 EVM bytecode metadata，也可以通过
`--target solana-sbpf-asm` 路由到 Solana sBPF assembly package。parser 目前覆盖
portable scalar/event 子集，以及第一批 Solana
target-extension form：account、PDA derivation、System Program
transfer/create-account CPI，以及 SPL Token transfer、mint、burn、approve 和
revoke、close-account 和 set-authority CPI。它也支持带 selector 的 entrypoint，例如
`entry mint selector "04"(amount: u64)`，因此 Solana instruction tag 可以在
Learn 源码中表达，而不是只存在于 Builder fixture。Learn statement 现在也覆盖
Solana pubkey/data log、return-data set/get，以及 remaining-compute-unit read/log
helper。同一 source 层也覆盖 Solana memory helper、SHA-256、Keccak-256、BLAKE3
hash helper，以及 Clock、Rent、EpochSchedule、EpochRewards 和 LastRestartSlot
fixture coverage 所需的 sysvar/context read。
Learn lowering 也会在发射 `ContractSpec` 之前校验已声明的 Solana CPI/PDA
引用、已声明的 CPI account 引用、CPI writable/signer 要求、signer seed，以及 helper
state/account 引用，因此剩余带字符串的 identifier 属于被检查过的编译器数据，而不是未检查的
用户面对 spec plumbing。
`ProofForge.Contract.Token.Learn` 会单独解析
`Examples/Learn/ProofToken.learn` 与 `Examples/Learn/FeeToken.learn` 这样的
Learn token intent source。这些文件是 shared Lean token intent 的兼容 fixture，
不是 canonical 产品示例；canonical 示例位于 `Examples/Shared/FungibleToken.lean`
和 `Examples/Shared/FeeToken.lean`。`--learn-token --target evm` 现在会发射
ERC-20 Yul、bytecode 和 artifact metadata，并使用标准 ERC-20 selector 以及
Transfer/Approval topic；`--learn-token --target solana-sbpf-asm` 会发射 SPL
Token plan，并在 `transfer_fee` 这类功能需要 Token Extensions 时自动切到
Token-2022。这个 CLI path 复用 `TokenSpec`，因此输出的是和 Lean-authored token
spec 相同的结构化 SPL Token / Token-2022 plan。

`ProofForge.Contract.Examples.ValueVault` 这样的示例应被理解为 v1 Lean source
example，而不是第二套 `.learn` grammar 的过渡区。对应的 `.learn` 文件是 legacy
compatibility example，用于证明 lowering equivalence。

## Target Routing

构建 target 决定 lowering path：

```text
Lean SDK syntax / contract_source
  -> source AST
  -> ContractSpec / portable IR
  -> target resolver + capability routing
  -> target semantic AST
  -> printer / assembler / package emitter
```

对 Solana 来说，target extension 会挂接 account schema、PDA seed、CPI layout、
IDL、client 和 sBPF assembly helper。对 EVM 来说，routing 会派生 ABI selector、
Yul、bytecode、ABI metadata 和 deployment file。当合约本身是 portable 时，源码作者
不应该手动切换这些内部实现细节。

## 下一步实现

1. 执行 **工作流 34**（Contract Source 产品化）：portable authoring 边界、
   EVM stdlib 的 `contract_source` 化，以及 target 选择的 build/test/deploy UX。
   详见 [implementation-backlog.md](implementation-backlog.md) 工作流 34。
2. 新的 SDK Alpha/Beta 工作继续落在 Lean SDK 语法和编译器内部 planning layer；
   legacy `.learn` 输入只在兼容性测试有用时复用这些层。
3. 逐步用 typed account、owner、program 和 capability reference 替代 Lean helper
   中带字符串的 Solana declaration，同时只在编译器制品内部保留字符串名称。
4. 随着 Wasm、Move 和其他 target 后端从 routing plan 走到 package emitter，
   继续扩展 target package emission。
