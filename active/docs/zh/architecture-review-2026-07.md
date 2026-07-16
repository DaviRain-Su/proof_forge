# ProofForge 架构评审（2026-07）

本文是一次面向仓库现状的架构评审，评审对象是"统一 SDK 输入 + 平台路由到多链"
这条主线，以及当前 main / Solana / NEAR 等分支的维护方式。定位与
[可行性分析](feasibility-analysis.md) 相同：原生中文分析文档，不是工程权威源。
落地到工程策略的结论应回写英文文档（`docs/decisions.md`、相关 RFC）。

## 一、总体结论

**架构方向是对的，不需要推翻。** "链中立的 Contract Intent API 作为唯一用户
输入 → ContractSpec / 可移植 IR → capability 路由与检查 → 各链 target adapter
产出工件"这一分层（D-028、RFC 0001/0003、[authoring-model](../authoring-model.md)）
是当前多链合约领域里合理的做法，且比 Reach / Solang 这类先例多了 Lean 证明
这一差异化能力。D-027（CPI/PDA 留在 Solana 扩展层，不进可移植 IR）和
"能力不支持就拒绝编译、不做静默降级"的原则也都是正确的取舍。

**当前真正的风险不在架构设计，而在架构正在被分支模式瓦解。** 统一 IR、
capability registry、target registry 是整个架构的"宪法"，但它们目前在
4 个以上长期分支里各自演进。如果不先收敛分支模式，后面每合并一条链，
都要在语义层面（而不只是文本层面）重新对齐一次 IR，代价会随分支数量
和存活时间超线性增长。

下面按优先级展开。

## 二、现状盘点（2026-07-02）

先修正一下口头模型与仓库实际状态的差异：

| 分支 | 口头模型 | 实际状态 |
|---|---|---|
| `main` | "EVM" | 已包含 EVM + Solana（sBPF asm 后端、Token SDK、Learn 路由）+ Psy/DPN。Solana 大部分工作已在 `4eab50e` 合入 |
| `DaviRain-Su/solana-supprot` | "正在更新的 Solana 分支" | 只剩 2 个未合并提交（Pinocchio 参考资料），基本已完成使命 |
| `DaviRain-Su/lookdown` | "Near 分支" | 领先 main 115 个提交、落后 40 个。包含整个 Wasm/NEAR 后端（EmitWat、near-sandbox 冒烟、offline host runtime），**并且修改了共享核心**：`ProofForge/IR/Contract.lean`（新增 `release` 语句）、新增 `IR/Allocator.lean`、`IR/Ownership.lean`、`IR/Semantics.lean`，修改 `Target/Registry.lean`（TargetProfile 增加 allocator 字段）、`docs/capability-registry.md`、`docs/decisions.md` |
| `DaviRain-Su/aleo-support` | — | 领先 104、落后 37。含 Leo 后端与 EVM chain-profile 元数据，同样改了 capability registry 与 decisions.md |
| `DaviRain-Su/cloudflare-support` | — | 领先 109、落后 3。含 TypeScript/Workers 后端，改了 `Target/Registry.lean` 与 capability registry |

由此得到两个观察：

1. "主分支 = EVM、每条链一个分支"的模型已经和事实不符：main 实际上已经是
   多目标主干（EVM + Solana + Psy）。这恰好说明主干化是可行的，Solana 的
   合入就是先例。
2. 共享核心文件（`ProofForge/IR/*`、`ProofForge/Target/*`、
   `docs/capability-registry.md`、`docs/decisions.md`、
   `scripts/i18n/manifest.json`）在每条链分支上都被独立修改。这些文件在
   development-standards 里被定义为"单一权威源"，但现实中存在多个互相
   分叉的版本。`lookdown` 与 `cloudflare-support` 都改了
   `Target/Registry.lean`，`lookdown` / `aleo` / `cloudflare` 三条分支都改了
   capability registry——这不是普通的合并冲突，而是架构契约本身在分叉。

## 三、判断 1：统一 SDK 输入的思路成立，但要把"三层"说死

"把输入统一成一个 SDK，通过平台路由到各链"的思路与仓库现有设计
（D-028 的 Contract Intent API）是一致的，成立。需要固化的是三层边界，
避免任何一层越位：

```text
第 1 层  Contract Intent API（唯一的默认用户面）
         链中立：state / entry / query / event / 算术 / 断言 / caller / value
第 2 层  Target Extension SDK（显式选择进入，链原生语义）
         Solana 账户/PDA/CPI、未来的 Move resource、Wasm host 特性
第 3 层  ContractSpec / 可移植 IR（编译器私有边界，用户永远不直接写）
```

三条护栏：

- 第 1 层新增构造的门槛保持 D-027 的标准：至少两个目标家族共享相同语义
  形状才进可移植层，否则进第 2 层。
- 第 2 层必须是"显式引入"的（import / 声明可见），不能悄悄混进默认面。
  目前 `contract_source` 里 Solana 声明与可移植声明在同一语法块内，建议在
  文档和 lint 层面明确：出现目标扩展声明的合约，编译非该目标时报错信息
  要指向"这是 Solana 扩展"而不是一般性失败。
- 第 3 层的字符串化表示（ContractSpec）不对用户暴露，
  [authoring-model](../authoring-model.md) 已写明，维持即可。

### 命名问题必须尽早解决

现在仓库里同时存在三个高度易混的名字：

- **Lean**：语言本身；
- **`Lean.Evm`**：SDK 的 Lean 命名空间——与 Lean 编译器自身的 `Lean`
  核心命名空间冲突，README 也承认这是迁移遗留（"until a rename is
  scheduled"）。这个 rename 应该真正排期，建议统一到 `ProofForge.*`；
- **Learn**：遗留 `.learn` DSL 与 `--learn` / `--learn-token` CLI 路径。

如果对外把统一 SDK 命名为 "LEAN"，会同时撞上"Lean 语言"（搜索引擎和社区
沟通无法区分）和 "Learn"（内部一字之差）。建议：

1. 对外品牌用 **ProofForge SDK**（或另起一个不与 Lean/Learn 谐音的名字），
   文档中"用 Lean 语言编写"作为定语出现，而不是 SDK 名。
2. `.learn` 维持 authoring-model 已定的"遗留兼容层"定位，并真正冻结
   （见判断 5）。

## 四、判断 2（最高优先级）：分支模式必须从"每链一分支"改为主干开发

### 问题

长期链分支的成本结构：

- 架构契约分叉：可移植 IR 的构造子集合、capability id 集合、TargetProfile
  结构体字段在不同分支上各自演进。`lookdown` 给 IR 加了 allocator 抽象和
  `release` 语句，main 这边 Solana 工作给 ContractSpec/Token 层加了大量
  东西，两边都动了对方看不见的"共享地基"。合并时的冲突是语义级的：
  例如 allocator 抽象进入 `Target/Registry.lean` 后，Solana 的
  bump allocator 选择（main 已有 `Tests/Backend/Solana/SolanaAllocator.lean`）要不要收编
  到同一抽象下，这类问题在分支上无人裁决。
- 权威文档失真：decisions.md 声称是"settled decisions"，但 `lookdown` 上的
  D-029+（EmitWat canonical、冻结 Rust v0 等决策）main 上根本看不到。
  评审者在 main 上读到的"全局架构状态"是错的。
- i18n 摩擦放大：每条分支都会触碰 `scripts/i18n/manifest.json` 的 sha256
  和 `docs/zh/*.zh.md`，这些文件几乎保证合并冲突。

### 建议的目标模式

**"链"是目录和 target id，不是分支。** 仓库结构已经天然支持这一点：
`ProofForge/Backend/<Chain>/`、`docs/targets/<chain>.md`、
`scripts/<chain>/`、target registry 按 id 注册、capability 检查在编译期
拒绝不支持的目标。未完成的后端完全可以带着 Research/Experimental 生命周期
标签住在 main 上，不影响 EVM/Solana 的稳定性——Psy 后端已经是这么做的。

具体规则建议（可回写进 `docs/development-standards.md`）：

1. **共享核心只在 main 演进**：`ProofForge/IR/*`、`ProofForge/Target/*`、
   `ProofForge/Contract/*`（Spec/Intent/Source 层）、
   `docs/capability-registry.md`、`docs/decisions.md`、`docs/portable-ir.md`
   的任何修改，必须以独立小 PR 直接进 main，不允许搭在链功能分支里长期
   携带。链分支发现需要改 IR 时，先把 IR 改动拆出来单独合入。
2. **功能分支短命化**：分支只承载一个可合并的增量（一个 backend 里程碑、
   一个 capability、一组冒烟测试），以"落后 main 不超过一次日常 rebase 的
   量"为健康标准。像 lookdown 这种 115/40 的分叉不再出现。
3. **CI 目标矩阵按需触发**：main 上按改动路径触发对应链的冒烟
   （`ProofForge/Backend/Solana/**` → Solana 冒烟），保证多后端共存不拖慢
   EVM 迭代。
4. **i18n 同步只在 main 做**：翻译脚本与 manifest 更新作为 main 上的独立
   提交/定期任务，分支一律不碰 `docs/zh/` 与 manifest。

### 存量分支的收敛次序

1. `solana-supprot`：把剩余 2 个 Pinocchio 参考提交合入 main，关闭分支。
2. `lookdown`（NEAR）：**先拆核心、后拆后端**。
   a. 把 `IR/Allocator`、`IR/Ownership`、`IR/Semantics`、`IR/Contract` 的
      `release` 语句、`Target/Registry` 的 allocator 字段，作为一组
      "IR/registry 演进" PR 先行进 main（此时要顺带裁决：Solana 的
      allocator 选择是否收编到同一抽象）；同步把 lookdown 上的
      decisions/capability-registry 增量合回权威文档。
   b. 再把 EmitWat 后端、NEAR 冒烟、offline host runtime 作为
      `wasm-near`（Experimental）合入 main。
3. `aleo-support` / `cloudflare-support`：按同样"先核心后后端"的方式处理，
   或者如果暂不打算推进，至少把其中对 decisions.md / capability-registry
   的修改摘回 main，让权威文档恢复权威。

## 五、判断 3：目标数量需要收敛出一条"证明主线"

`docs/targets/` 下已有 15+ 个 docs-first research 目标，而真正有产出物的
后端是 EVM（成熟）、Solana（接近）、Psy（受限子集）、NEAR（在分支上）。
research 文档本身成本低、有价值，但要避免两个副作用：

- 每新增一个 research 目标都在 decisions.md / capability registry 里加行，
  放大上面的分支冲突面；
- 稀释"跨链可移植性已被证明"这一核心叙事。

建议：把 **EVM + Solana + NEAR 三个目标家族跑通同一个 shared scenario
（Counter，进而 ValueVault）** 定义为当前阶段的唯一"完成"标准（对应
Phase 4 的第一个实例），在此之前新的 research 目标只做文档、不动注册表
和 capability 文件。三家族覆盖了三种截然不同的执行模型（EVM 槽存储 /
Solana 账户 / Wasm host），足以证明 Intent API 抽象成立；证明成立之后再
铺第 4、第 5 个家族，边际成本会低得多。

## 六、判断 4：EVM 存在两条并行管线，需要给出归宿

当前 EVM 有两条到 Yul 的路径：

1. 历史路径：Lean 原生合约（`ProofForge.Evm` / `@[export]`）→ LCNF →
   `EmitYul` → Yul。这是 Phase 0 基线，也是 `--evm-bytecode` 的主路径。
2. 新路径：`contract_source` / Learn → ContractSpec → EVM Plan
   （`Backend/Evm/Plan.lean`，RFC 0004）→ Yul。

两条管线長期并存会让 "EVM 支持什么" 没有单一答案（能力集合、golden 文件、
冒烟脚本都要 ×2）。既然平台叙事的输入面是 Intent API，建议在 RFC 0004 里
明确：**ContractSpec → Plan → Yul 是产品管线，LCNF → EmitYul 降级为
"Lean 原生实验路径"**，它的存在理由（直接编译带证明的 Lean 函数体）单独
陈述，且不再要求与产品管线保持特性对齐。什么时候淘汰可以不急着定，
但"谁是产品路径"要先定。

## 七、判断 5：Learn 的"冻结"要执行到位

[authoring-model](../authoring-model.md) 已明确 `.learn` 是遗留兼容层、
"不应长成第二门产品语言"。但 main 最近的提交序列（Learn source CLI
emission、Learn token target plans、Learn signer/CPI 约束、Learn reference
diagnostics）显示新特性仍在 Learn 解析器上先行或同步扩张。这与文档的
定位相反，且每个 Learn 语法扩展都是未来要偿还的兼容债。

建议一条硬规则：**新能力必须先落在 Lean SDK（`contract_source` / Token
SDK helpers），`.learn` 只在需要等价性回归时跟进，且不再新增只有 Learn
才有的语法。** 如果 Learn 的真实用途是"给非 Lean 用户一个轻量入口"，
那它就不是遗留层而是第二产品面，需要用一篇 RFC 把这个定位变更说清楚——
二者取其一，不要维持现在的模糊状态。

## 八、小项清单

- `Lean.Evm` 命名空间与 Lean 核心 `Lean` 命名空间冲突，rename 到
  `ProofForge.*` 应排期（见判断 1）。
- `solana-supprot` 分支名拼写（supprot）——收敛该分支时顺带消灭。
- `docs/targets/solana-sbf.md` 已是历史别名，INDEX 已标注，保持即可；
  新文档不要再引用旧 id。
- TokenSpec 的多链 Token SDK（RFC 0006）方向正确：EVM 出 ERC-20 合约、
  Solana 出 SPL/Token-2022 计划而非伪 ERC-20 合约，这正是"路由到不同
  执行模型"而非"翻译语法"的正确示范，值得作为对外解释架构的样例。
- Cloudflare Workers 后端（TypeScript 目标）与"区块链目标"的注册表语义
  不同（无共识、无链上状态），若要保留，建议在 target registry 里给它
  一个独立 family 或明确标注为演示性目标，避免稀释 capability 语义。

## 九、行动清单（按优先级）

> 本清单已落入工程 backlog。P0 的分支收敛已于 2026-07-02 执行完成：
> `solana-supprot`、`lookdown`（NEAR）、`aleo-support`、`cloudflare-support`
> 已全部合入 main，决策撞号已重编号（NEAR → D-029/030/031，Aleo → D-032，
> Cloudflare → D-033），`release` 语义冲突已在 EVM/Leo/TS 消费者中修复。
> 剩余跟进见 [implementation-backlog.md 的 Workstream 24](../implementation-backlog.md)
> （Architecture Convergence Follow-ups），形式化验证任务见 Workstream 25 与
> [formal-verification.md](../formal-verification.md)。

1. **P0 收敛分支**：合入 `solana-supprot` 残余；按"先 IR/registry、后
   后端"两步合入 `lookdown`；把 aleo/cloudflare 分支上的 decisions /
   capability-registry 增量摘回 main。
2. **P0 立规**：在 `docs/development-standards.md` 增补"共享核心只在 main
   演进 + 功能分支短命化 + i18n 只在 main 同步"三条规则，并记入
   decisions.md。
3. **P1 定名**：确定对外 SDK 名称（建议 ProofForge SDK），排期
   `Lean.Evm` → `ProofForge.*` rename，冻结 Learn 语法面。
4. **P1 定管线**：RFC 0004 中明确 ContractSpec→Plan→Yul 为 EVM 产品管线。
5. **P2 定阶段目标**：以"EVM + Solana + NEAR 跑通同一 shared scenario"为
   当前阶段唯一完成标准；此前 research 目标只加文档、不动注册表。

以上第 1、2 项完成后，"统一 LEAN（ProofForge）SDK 输入 → 平台路由多链"
这条主线在组织层面才真正成立；第 3–5 项决定它对外是否讲得清楚。
