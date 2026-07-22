# ProofForge V2 黑客松决赛演讲稿（中文）

配套 `presentation/slides.md` / `slides.pdf` 使用。总时长约 7 分钟，15 页，每页约 28 秒。已按比赛 5 个评审维度重新平衡，并加入了 Vitalik 关于 Lean 的推文作为外部趋势验证。

## 5 个评审维度 → 对应页码

| 维度 | 对应页码 | 说明 |
| --- | --- | --- |
| 技术创新 | 6、7、8 | 架构图、Technical differentiation 对比表、诚实证据 |
| 产品完成度 | 4、5、7、14 | 产品形态、用户流程、可演示命令、当前里程碑 |
| 商业与生态潜力 | 3、11、9、12 | 市场需求、商业模式、AI/Web3 趋势、竞争壁垒 |
| AI 与 Web3 技术应用 | 4、9、10 | Web3 多链/ZK 深度；Vitalik 推文验证；AI 上诚实互补定位 |
| 团队表达能力 | 13、14、15 | 清晰路线图、未来规划、收尾 |

---

## 第 1 页 · Title（0:00–0:30）

> 大家好，我是 DaviRain。今天带来的项目是 **ProofForge V2**。
> 一句话概括：我们想让作者只写一份业务逻辑，就能安全、受控地把它物化到多个链平台——EVM、Solana、NEAR、Noir 等等。
> 核心关键词是：**一份源码、目标中立、失败即拒绝**。

---

## 第 2 页 · Multi-chain today is expensive and risky（0:30–1:00）

> 现在做多链 dApp，团队通常要重复写 Solidity、Rust/NEAR、Rust/Solana、Noir 电路。
> 问题不只是工作量大：不同链的整数语义、状态回滚、调用顺序、权限模型都可能不一样。
> 结果呢？每上一个链就要重新审计、重新测试，还要给每个链单独维护工具链版本。这很贵，也很危险。

---

## 第 3 页 · A growing, real demand（1:00–1:30）

> 但这个需求是真实在增长的。ZK rollup、L2、应用链、跨链应用都在爆发。
> 用户在哪，团队就得部署到哪。可是目前市场上没有一个被普遍接受的“智能合约写一次、到处跑”的解决方案。
> 安全审计市场本身很大，而且是按链按次收的。如果能让多链审计回归成一次源代码审计，这里面就有明确的商业空间。

---

## 第 4 页 · Our product: a portable compiler（1:30–2:00）

> 我们的产品形态是一个基于 Lean 4 的编译器。
> 作者写的是这样一个 Counter：有 state、init、entry、view。注意源码里没有 “contract”、“circuit”、“zkVM” 这些顶层标记。
> 换目标只改 `--target` 参数，编译器负责证明这个业务语义在目标上能等价实现；如果不能，就直接报错，而不是偷偷降级。

---

## 第 5 页 · User flow: write, check, build, inspect（2:00–2:30）

> 用户流程很清晰：
> `check` 可以在不选目标的情况下做语义检查；
> `build --target evm` 生成 ABI、bytecode、manifest；
> `inspect` 查看诊断和支持决策；
> deploy、prove、verify 都是后续显式命令，build 本身不碰网络、不碰私钥。

---

## 第 6 页 · Architecture overview（2:30–3:00）

> 技术上，我们做了这么几层：前端用 Lean 解析允许的 DSL；Core 做类型和效果检查；然后归一化成目标无关的 `Semantic.Program`；
> 再由 Support Resolver 做精确能力匹配；最后进入各个 target 自己的 Materializer，生成 Plan、IR 和 OutputSet。
> 关键约束：Source、Typed、Semantic 三层**不根据 target 分支**。

---

## 第 7 页 · Technical differentiation（3:00–3:30）

> 和市面常见方案比，我们的差异在于：
> 别人做尽力而为的转译，我们做 exact requirement 匹配；
> 别人把源语言和目标耦合，我们用 target-neutral 语义层；
> 别人把计划做成字符串或 JSON，我们为每个目标保留类型化的 Plan 和 TargetIR；
> 别人遇到不支持就静默 fallback，我们 fail-closed；
> 别人依赖环境，我们追求可复现、clean-room 构建。

---

## 第 8 页 · What works now?（3:30–4:00）

> 当前完成度方面，我们必须诚实说：
> EVM 已经有 `solc` bytecode，并在 Anvil 本地跑通了 Counter 的 increment 和 overflow revert；
> Solana 目前只有 `.sbpf-plan` 和 IDL，**还没有 sBPF ELF 或 runtime**；
> NEAR 有 WAT/Wasm 通过 `wat2wasm` 结构验证，**但还没跑 sandbox receipt**；
> Noir 有 Plan 和关系 IR，能输出 `.nr` 包，**但还没有 ACIR、proof、VK**。
> 所有目标共享同一个 semantic hash，成熟度不人为升级。

---

## 第 9 页 · AI & Web3: where we fit（4:00–4:30）

> 关于 AI 和 Web3：我们是深度 Web3 的——多链账户、智能合约、ZK 电路都在范围内。
> 需要诚实说明的是，**AI 目前不在编译器核心**。
> 但我们提供的是**确定性验证层**：无论代码是人写的，还是 AI 辅助生成的，都需要被证明在目标平台上语义等价。这是 AI 没法替代的部分。

---

## 第 10 页 · Vitalik: the same direction（4:30–5:00）

> 这个方向也得到了外部验证。昨天晚上 Vitalik 发了一条推文，说我们应该尝试创建一种“高级编程语言”，它被编译到 Lean 或 HOL，专门让人类友好地阅读定义和定理。
> 他的场景是：AI 输出一大堆证明，但读者需要理解这些证明到底在说什么。
> 这和我们的底层判断一致：Lean 是可信的形式化骨干；人类可读的源码 + 机器可验证的语义，正是 AI 时代需要的那一层。

---

## 第 11 页 · Business model & ecosystem（5:00–5:30）

> 商业模式上，我们设想：核心编译器开源，建立社区信任和标准；
> 对团队提供企业级服务：多链审计、CI 门禁、SBOM 报告；
> 和 prover、SDK、部署 pipeline 做工具链集成；
> 最终生态价值是：更少审计次数、更快跨链上线、更低回归风险。

---

## 第 12 页 · Why us, not a transpiler or bridge?（5:30–6:00）

> 为什么不是 transpiler 或 bridge？
> Transpiler 通常是 best-effort，容易出现静默语义漂移；
> Bridge 是运行层的东西，管不了源码级语义；
> 我们是从源码出发做 fail-closed、exact-version、reproducible 构建；
> 目标只能决定形式，不能改变意义——这是我们的核心壁垒。

---

## 第 13 页 · Roadmap & target landscape（6:00–6:30）

> 路线图分两块：
> Phase 1 要实现 EVM、Solana、NEAR、Noir 四个目标，并且按成熟度阶梯推进；
> 设计/研究阶段还有 CosmWasm、Soroban、ICP、OpenVM、Aleo、Psy 等。
> 我们不会让不同平台共用一个虚假的通用 Plan，每个目标都保持自己的 Plan 和 IR。

---

## 第 14 页 · Team & next steps（6:30–6:55）

> 团队节奏上：D0 基本收尾，D0-10 在收尾 task qualification verifier；
> 下一步 D1 做完整 parser 和 type/effect 系统；D2 加 struct、event、函数调用、proof reference；
> 然后四个 Phase 1 目标要分别推向 runtime 或 proof 验证；
> 路线图和里程碑都已经文档化，可检查、可追踪。

---

## 第 15 页 · Closing（6:55–7:00）

> 总结一句话：ProofForge V2 想做多链智能合约的 **common source of truth**。
> 代码和文档都在 `github.com/DaviRain-Su/proof_forge`，推荐看 `docs/01-prd.md` 和 `docs/02-architecture.md`。
> 本地可以跑 `just build && just test` 验证。
> 谢谢大家，欢迎提问！

---

## 提示

- 如果评委对产品完成度追问，重点回到第 5 页用户流程和第 8 页诚实证据表。
- 如果评委问 AI 怎么结合，按第 9、10 页讲：不硬蹭 AI，强调我们是 AI 生成代码的确定性验证层，且 Vitalik 也看好这个方向。
- 如果评委问商业模式，按第 3 页市场需求 + 第 11 页企业服务的组合回答。
- 保持语速：每页大约 25–30 秒，Vitalik 页可以稍微慢一点，让评委看清推文内容。
