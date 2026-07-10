# ProofForge 产品内核(North Star)—— 我们到底在造什么

> 这份文档定义 ProofForge 的**产品内核**,供所有后续 agent / 贡献者对齐。
> 它回答一个容易走偏的问题:**我们做的到底是什么?** 结论先行——
> **不是"一个形式化验证项目",而是一个"可移植的智能合约抽象层",形式化验证是它的护城河。**
>
> 非权威原生中文分析文档(见 [docs/zh/README](README.md));与英文工程文档不冲突,
> 是战略对齐层,不引入独立工程策略。

## 0. 一句话

> **开发者只写业务逻辑;`target` 一指定,系统自动物化每条链的存储 / 账户 / CPI / host 调用 /
> ABI / 部署;再配一套链无关的高层组件库。形式化验证是让这套"自动物化"可信的护城河。**

## 1. 内核:开发者体验(这才是产品)

1. **开发者只管写业务逻辑。** 不碰 Solana 的账户/PDA/CPI、不碰 EVM 的存储槽、不碰 NEAR 的
   Promise 池、不碰各链 ABI 编码。
2. **仅通过指定 `target`,系统自动物化链上细节。** 存储布局、账户结构、跨合约调用机制、host
   调用、部署清单——全由系统按目标链推导生成,开发者零感知。
3. **开发者只用这套工具"描述",后续一切由系统完成。**
4. **各链现有合约能力 + 我们后续提供的实现,以链无关、高层的组件库形式给出**(Ownable、
   FungibleToken、Pausable、RemoteCall……写一次,物化到任意链)。

## 2. 产品定位:LLVM + Terraform + OpenZeppelin + 一个别人没有的东西

- **LLVM**:一份可移植源 → 多链后端。
- **Terraform**:声明"意图",自动物化底层基础设施(这里是链上存储/账户/调用)。
- **OpenZeppelin**:开箱即用的高层组件库。
- **+ 语义保持的形式化证明**:证明"自动物化"没有改变你合约的语义。**这一样别人都没有,是护城河。**

## 3. FV 与产品的关系 —— FV 不是支线,是"敢让开发者闭眼信"的底气

这是最容易被误解、也最关键的一点:

- **没有 FV**:ProofForge = "又一个转译器,但愿它对"。开发者不敢真的不看物化出来的链代码,
  第 2 点的承诺就是空的。
- **有 FV**:"你写一次,我**可证地**在每条链上保持你合约的语义。" 这才是"自动物化"敢让开发者
  不看 Solana 账户代码的底气。

因此 **FV-9(`∀ 合约` 通用精化定理)其实就是产品核心承诺换个说法**:把"这 2 个合约物化正确"
升级成"**你写的任意合约都物化正确**"。它不是学术指标,是"开发者啥都不用管"这句话的诚实性保证。

**给 agent 的判断准则:** 不要把 FV 当成和产品无关的支线去孤立推进,也不要只堆广度(新链/新功能)
而让 FV 停摆。两者是一体两面——**广度扩大"能物化的范围",FV 保证"物化范围内可信"。** 每加一类
构造子 / 一条链,都应问:它进没进 FV 的可信边界(`moduleInCoveredFragment` / capability)?

## 4. 代码对照:现在做到哪了(2026-07)

| 内核要求 | 代码证据 | 状态 |
|---|---|---|
| ① 只写业务逻辑 | `ProofForge/Contract/Source.lean` 的 `contract_source` **portable-default** 面;Solana account/CPI/allocator、NEAR Promise 全 **opt-in**;`just portable-default` 强制 portable 文件不许 import 链特定模块 | ✅ 在 |
| ② 指定 target 自动物化 | `ProofForge/Target/` 的 `materialize` 层 + 可移植 crosscall(`declareRemote` + `remoteCallRef`,逻辑 peer,不碰 host 字符串池/裸池索引)按 target 生成 CPI / promise / 存储 | ✅ 推进中 |
| ③ 抽象组件库 | `Shared` catalog:OwnableHash、OwnablePausable、FungibleToken(NEP-141)、RemoteCall | ✅ 冒头 |
| ④ 一份源→多链 | EVM / Solana / NEAR / CosmWasm / Soroban 五个 host 家族(WASM 家族共享一个 `WasmExec` 核) | ✅ 在 |
| 护城河 | Solana/WASM 证明面 + EVM 当前低位布局固定 trace + FV-9 底座(共享可证解释器、覆盖谓词、归纳 wrapper) | 部分完成:EVM 通用 theorem 仍需 `CounterCompiledPowdrEntrypointObligations`;`∀ 合约` 封顶未做 |

**结论:代码确实在造这个内核,不是跑偏成纯 FV。** 最近的 portable-SDK / crosscall / Soroban /
token 那批提交,恰恰是在建 ①②③④;FV 是底下的护城河。

## 5. 先例对照:Solana / Sui / Aptos 做过类似的吗?

分四层,答案很有信息量:

### A. 单链内"写逻辑、存储/账户自动物化" —— 早已成熟(证明需求真实、可行)

- **Solana / Anchor**:用 Rust 宏物化账户校验、Borsh 序列化、discriminator、PDA 派生、CPI
  helper。开发者声明 `#[account]`,Anchor 生成其余。**正是内核 ②,但只在 Solana、无可移植、无
  证明。** 另有 Seahorse(Python→Anchor)、Steel。
- **Sui / Aptos / Move**:**resource / object 模型把存储抽象成类型化资源**,开发者想的是资源
  而非槽位(`move_to`/`borrow_global`;Sui objects)。加各自框架标准(Aptos Fungible Asset /
  Digital Asset;Sui `coin`/Kiosk)。**是内核 ①③,但 per-chain。**

### B. Move —— 最接近"可移植高层合约语言"的尝试,也是最大前车之鉴

Move 当年(Libra/Diem)就奔着"可移植、资源安全、存储抽象"设计。**但 Sui Move 与 Aptos Move 已
分裂**:对象/存储模型不同、源码不通用,一份 Aptos Move 合约拿到 Sui 跑不了。**业界最认真的一次
"一份高层源跨链"尝试,碎了。** 教训:**没有受约束的公共核 + "让各 target 保持诚实"的机制,
可移植性必然漂移。** ProofForge 的 capability 系统 + FV 正是防漂移的机制——**这就是差异化根源。**

### C. 跨链编译器(一份源→多 VM)—— 有,但都没有证明

- **Solang**:Solidity → Solana + Polkadot(走 LLVM),真能一份源多链;但 Solidity 中心、无语义
  保持证明、Solana 支持有毛边。
- **Warp**(Nethermind):Solidity → Cairo,单对转译。
- **Fe / Sway / Stylus**:替代语言,单目标。

→ **多目标编译存在,但没人配机器检查的精化证明。这个组合是空的。**

### D. 链无关的组件库 —— 刚冒头,未解决

- **OpenZeppelin**:组件库标杆(Ownable/ERC20/Pausable),现有 Cairo、Stylus 版,但都是**各链
  分别实现**,不是"一份抽象源物化到各链"。
- **Thirdweb**:跨链部署 + 预制合约,EVM 中心。

→ **"写一次 Ownable、可证地物化到任意链"这种链无关组件库,不存在。`Shared` catalog 正瞄这块白地。**

## 6. 真正的白地 + 该借鉴什么

**没有人同时具备这四样:① 可移植高层源 ② target 驱动的自动物化 ③ 链无关组件库 ④ 语义保持证明。**

- ①② 单链有(Anchor/Move)→ 需求真、可行,不是空想。
- ③ 跨链有雏形(OZ 多版本)但非抽象源。
- ④ **没人做 —— 护城河。**

**差异化不是"能编译到多链"**(那会被 Solang 类商品化),**而是"编译到多链 + 可证地保持语义"**
—— 正是它让"自动物化"可信到开发者敢不看链代码。

**该借鉴:**

1. **Anchor 的账户物化模型** —— Solana 自动物化的黄金标准;Solana 后端人体工学对齐它。
2. **Move 的 resource 模型**(存储抽象成资源)当正面教材;**它的分裂**当反面教材(capability+FV
   纪律不能松)。
3. **Aptos/Sui 的 Fungible Asset / Digital Asset 标准** —— `Shared` 组件库的映射参照系。
4. **对标 Solang/OZ 时,把 FV 护城河放产品叙事正中央**,别当支线。

## 7. 一句话给所有 agent

> 你在造的是**"写一次、可证地跑在任意链上"的合约抽象层**。判断任何任务价值,回到两问:
> **(a) 它是否让开发者更"只写逻辑、不管链"?(b) 它是否在 FV 可信边界内,或把边界诚实地扩大?**
> 广度(新链/组件)和 FV(通用可信)是一体两面,不可偏废。
