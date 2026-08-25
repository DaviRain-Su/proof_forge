# Projects.Phoenix

## Purpose

把 [phoenix-v1](https://github.com/Ellipsis-Labs/phoenix-v1) 的双边 IOC
语义放进当前 SVM 剖面。官方 bid/ask 记录摊成平行 `UInt64` 向量；两边订单树和
trader registry 都固定 N=4，把 root、left/right、parent、color、allocator 和 free-list
持久化到账户，执行 bounded 红黑插入、删除修复和稳定地址复用。

## 官方 `src/state` 对上了什么

| 官方类型 | 本仓槽 |
|---|---|
| `FIFOMarket.base_lots_per_base_unit` | `baseLotsPerBaseUnit` |
| `tick_size_in_quote_lots_per_base_unit` | `tickSize` |
| `order_sequence_number` | `sequence` |
| `taker_fee_bps` / collected / unclaimed | `takerFeeBps` / `collectedFees` / `unclaimedFees` |
| ask `FIFOOrderId` / order × 4 | `priceTicks` / `sequences` / `traders` / `sizes` / TIF |
| bid `FIFOOrderId` / order × 4 | 对应的 `bid*` 平行向量 |
| ask/bid tree topology | `askBook` / `bidBook` 的 root、links、parent、color |
| ask/bid tree allocator | 各自的 count、bump index、free head、next-free |
| traders tree key / address | `traderKey0..3` 四 limb Pubkey / 1-based `traders`、`bidTraders` |
| traders tree topology | `traderRoot` / `traderLeft` / `traderRight` / `traderParent` / `traderColor` |
| traders allocator | `traderCount` / `traderBumpIndex` / `traderFreeHead` / `traderNextFree` |
| 每-seat `TraderState` | 四个 `trader{Quote,Base}{Locked,Free}` 向量 |
| `Side` / `SelfTradeBehavior` | 无 payload 枚举（宿主） |
| `MatchingEngineResponse` | `match*` bounded-fold scratch |
| `PhoenixMarketEvent` | 官方 ordinal tag + 九个规范 payload 槽；instruction 内固定容量 5 的 batch |
| TIF 哨兵 0 | `expired`（严格 `<`；等于 deadline 仍有效） |

236 个 8-byte 叶，账户含 discriminator 共 1,896 bytes。`#pf_build Projects.Phoenix`
的 SVM digest 及构建物大小见下方构建快照。物理账户表固定为 market state、trader signer、trader
base/quote Token account、base/quote mint、base/quote vault 和 classic SPL Token program，
再加 executable current program 与 canonical `"log"` PDA，共 11 个账户。

`depositFunds` 从 account 1 读取 signer 的完整 32-byte Pubkey。已有 key 幂等复用 seat；
缺失 key 按 Sokoban 的 1-based bump allocator 注册，容量为四个 seat；base/quote 分别
加进该 seat 的 free 余额。全零 Pubkey 也合法，`traderUsed` 单独区分空槽。查找是
沿持久化 links 的 structured `forBody 4`；循环同时保留最后一个 parent，避免插入前
再次查找。注册、旋转、recolor 和余额更新都是通用动态 `Vector.set`，没有
Phoenix-specific IR 或 emitter 分支。`withdrawBase` / `withdrawQuote` 分别返回
`min(requested, free)`，
不混淆两种 lot 单位；`evictSeat` 只释放四类余额全零的 seat，并把 address 压回 LIFO
free-list。eviction 在回收 address 之前执行 successor transplant 和 delete-fixup；
后续注册精确复用该地址且 bump index 不回退。其余 scalar lookup 仍是 bounded 四槽
扫描；`Except UInt64` producer 汇合到 CFG join local，复合 key guard 由统一 Extract
lowering 承载。`postAsk` / `postBid` / `reduceAsk` / `reduceBid` 的链上入口不再接受可伪造的
trader 参数，而是按 account 1 signer 完整 Pubkey 解析内部 seat；reduce/cancel 同时
解锁该 seat 的 base/quote 余额。post 的普通锁仓和满书 eviction 也会原子更新 taker
与被驱逐 maker 的 TraderState；同 owner replacement 先解锁再重新锁仓。matching
现在也逐 event 更新 maker seat，并在 commit 原子更新 registered taker seat。旧的四个
聚合槽继续作为 registered seat 的 compatibility projection；未注册 take-only 的资产
直接经 vault 流动，不再伪造 taker 的内部余额。

base/quote vault 都是 `["vault", market key, mint key]` 的 canonical PDA。`depositFunds`
先比较两个目标账户的完整 32-byte canonical key，再分别执行 trader→vault 的
`TransferChecked`；`withdrawBase` / `withdrawQuote` 以同一异构 seed 列表和 canonical
bump 执行 PDA-signed vault→trader transfer，并在 CPI 后保留 state continuation。
这些能力落在通用 `PdaSeed`、SVM Ops/IR 和 emitter；没有 Phoenix 名字或字段偏移特判。

`postAsk` 是 signer-authenticated 链上 free-funds 挂单：检查 incoming TIF 和 sequence
上界，把 owner seat 的 `baseFree → baseLocked`，按 `(price, sequence)` 插入持久化
红黑树；书满时只有更低价 ask 能驱逐最差订单，并把旧 maker 的 base 解锁。payload
不再为排序而搬动；删除地址进入 LIFO free-list，下一次插入精确复用该地址。未注册 trader 只保留在宿主 reference helper 的
aggregate fallback，真实 instruction 先经过完整 Pubkey lookup，不能进入该分支。

`swapBuyAt` 是完整的 bounded N=4 宿主语义；链上 `swapBuy` 用 19-phase
state-carrying fold 实现相同扫描：reset 后，每档依次检查 slot TIF、time TIF、
撮合并推进档位。过期单清零、解锁 base 并继续；第一个超限有效价格停止；整档
成交继续，部分成交停止。无流动性或超限 IOC 成功返回 0，不伪装成 overflow。
`swapBuy` / `swapSell` 不再接受可伪造的 taker seat：都从 account 1 signer 的完整
Pubkey 查找 seat，未注册 signer 映射到 take-only sentinel，再按该身份执行 Abort /
CancelProvide / DecrementTake。自成交量不产生 fill、手续费或 transfer，ABI 也从
六个参数缩到五个。

quote 和费用先按整次撮合聚合再向上取整。每个 ask fill 执行 maker
`baseLocked → quoteFree`；过期和 self-cancel 执行 maker `baseLocked → baseFree`。
registered free-funds buy 从 taker `quoteFree` 扣成交额和费用，再把成交量加进
`baseFree`。这些 seat transition 和 aggregate compatibility projection 同步提交，
并增加 `unclaimedFees`；`collectFees` 原子地把它转进 lifetime `collectedFees`。
registered 路径不做 vault CPI；未注册 buy 把 quote+fee 从 trader 转入 quote vault，
并由 base-vault PDA 把 filled base 转给 trader。未注册 sell 对称地把 filled base 转入
base vault，再由 quote-vault PDA 转出扣费后的 quote。`reduceAsk` 按
signer seat + `(price, sequence)` 验 owner，减少 `min(requested, resting)`；缺失订单
成功返回 0。

bid-side 的持久化树按价格降序中序遍历，订单 ID 保存官方的 `~~~sequence` 编码，同价时编码
降序即时间 FIFO。`postBid` 同样按 signer seat 授权，按原价把 quote 从 free 锁入
locked，满书只允许更高价驱逐最差 bid，并在不同 maker/taker seat 间原子移动 collateral；
`reduceBid` / `cancelBid` 按原价解锁 owner seat 的 quote collateral。
`swapSell` 扫过期和跨档 bid，
按总成交 adjusted quote 收 taker fee；maker fill 执行 `quoteLocked → baseFree`，
registered taker 执行 `baseFree → quoteFree`，过期和 self-cancel 解锁 maker quote。
宿主递归规范和链上 structured fold 对逐 seat 余额及 aggregate 投影逐项一致。挂单
记录 `Evict` / `Place` / `TimeInForce`；
撮合逐档记录 `Fill` / `ExpiredOrder` / self-trade `Reduce`，最后记录
`FillSummary`；reduce 和收取费用分别记录 `Reduce` / `Fee`。事件 batch 的动态
variant-vector 写入通过 target-neutral typed layout 降到两个 target，不需要 emitter
认识 Phoenix。ordinal 对齐官方 wire enum：0 Uninitialized、1 Header、2 Fill、3 Place、
4 Reduce、5 Evict、6 FillSummary、7 Fee、8 TimeInForce、9 ExpiredOrder。每个实际事件
携带 instruction 内 index；maker-bearing Fill/Evict/ExpiredOrder 在构造前把内部 seat
解析成完整四 limb Pubkey。事件 batch 满 5 条时 instruction fail-closed（`.full` /
`0x1003`），不再静默丢事件仍返回成功。`Error` 现为 `overflow` / `unauthorized` /
`full` / `selfTrade`，链上分别是 `0x1001` / `0x1002` / `0x1003` / `0x1004`。`Place` / `FillSummary` 的 `u128 client_order_id` 继续用
little-endian `(lo, hi)` 两个 `UInt64` limb 完整保留。最宽事件现在是九 payload，测试
明确钉住动态 `events` 的 byte offset 72，防止抽取器静默漏掉尾叶。

每个成功路径还通过 signed self-CPI 发出官方形状的认证 audit record。93-byte
`AuditLogHeader` 包含 Log tag 15、Header tag 1、instruction origin、sequence、i64
timestamp bits、slot、market/signer Pubkey 与 u16 event count；payload 按官方 2..9
ordinal 及 u16 index 0 做 Borsh 窄编码。每个实际 event 是一个单-event batch，成功但
无 event 的路径发 header-only batch。raw handler 只接受当前 program id 下由 `"log"`
seed 导出的 readonly signer PDA。IR 门覆盖所有 header/event recipe，Mollusk 同时验证
真实 `Program data`、错 executable self program 与错 log PDA 的原子失败。

assembly 是带 local CSE/共享 basic block 的 target CFG 中间文本，不是部署文件。通用抽取器按 helper 的输入/输出类型区分 State transition 与纯结构 reader，
并去重嵌套 state-helper 的祖先 transition，避免组合更新和 reader projection 被重复发射；
完整 maker Pubkey 与 event/lastEvent 双写仍会展开 conditional values。
P0 的递归值树门把 `postAsk` 钉在 total `< 200,000`、largest `< 50,000`；当前测量为
90,604 / 24,840，单方法 assembly 3,755,860 bytes。完整 N=4 双边 topology 的全程序
assembly 暂设 `< 12,000,000` bytes 回归门，并拒绝重复 label，同时断言 maker/taker
ledger writes 和最宽 event leaf 都存在。该门防止重新膨胀，不是部署资格声明；ELF/IDL/
digest 必须从同一 checkout 的实际 `pf build` 产物记录。当前同一构建产生 assembly
11,815,636 bytes、ELF 3,550,888 bytes、IDL 19,626 bytes，SVM digest
`65fbdcc1cf643f02`；这个 ELF 大小尚未通过 P4 部署资格门。链上 buy / sell 都是 19 phase，挂单是 17 phase；要显著缩小文件应在通用
IR/CFG 做 local CSE 或共享 block，而不是在 Phoenix 或 target emitter 加事件特判。

## 支持边界与路线

- **已有（P1）**：固定 N=4 ask/bid/trader topology、双向 IOC、seat ledger、TIF、费用、
  typed event 与 classic SPL Token 双 vault 的 host/IR 语义。
- **部分支持（P0/P2/P3）**：Extract 资源/完整 commit 门和主要 Mollusk lifecycle/CPI/audit
  矩阵已有；仍需以当前产物重跑 Phoenix、Tree、全 SVM 与 EVM 回归。跨四档逐样本只作
  host reference↔source fold，不宣称完整 chain refinement。
- **未支持（P4/P5）**：当前 ELF 的部署资格、动态容量、runtime remaining accounts、
  Token-2022 extension 语义及完整 Phoenix-v1 账户兼容。

依赖顺序是 P0 抽取稳定 → P1 bounded 语义门 → P2 Mollusk 认证矩阵 → P3 Tree/EVM/
全仓回归 → P4 通用 CFG/产物资格；P5 动态模型另立 profile。任何 helper/state-loop
continuation、payload variant flatten、账户/PDA/owner/signer 校验不能完整解码时都必须
fail closed；不得用 scalar fallback、部分 state commit 或 Phoenix-specific emitter 特判
换取成功。动态容量和部署声明不是本轮 P0 的非显式扩展目标。

## 官方有、本仓没有

| 官方 | 为什么关 |
|---|---|
| bid/ask/trader 动态容量 `RedBlackTree` | 三棵树都已持久化完整 N=4 topology；运行时可变容量仍保持 fail closed |
| `_padding: [u64; 32]` | 不进账户 |
| `Ladder` / `Vec` | 不定长 |

这是完整的 bounded N=4 Phoenix IOC 模型，不是完整 Phoenix-v1 动态账户实现。
