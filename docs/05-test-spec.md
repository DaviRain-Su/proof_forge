# 05 测试规格

## S0（现在）

| ID | 类型 | 输入 | 期望 |
|---|---|---|---|
| T-S0-01 | happy | `increment {0} 1` | `.ok ({1}, 1)` |
| T-S0-02 | boundary | `increment {0} 0` | `.ok ({0}, 0)` |
| T-S0-03 | boundary | `increment {max} 0` | `.ok ({max}, max)` |
| T-S0-04 | error | `increment {max} 1` | `.error .overflow` |
| T-S0-05 | error | `increment {max-1} 2` | `.error .overflow` |
| T-S0-06 | happy | `increment {max-1} 1` | `.ok ({max}, max)` |
| T-S0-07 | happy | `init 7` / `get` | value 7 |
| T-S0-08 | theorem | overflow 情况 | `increment` 不是 `.ok` |
| T-S0-09 | ir | 手工 program | 含 init/increment/get |

用 `#guard` / `example` 钉在 Examples 或 Tests 里，随 `lake build` 检查。

## S1 / S2

| ID | 类型 | 输入 | 期望 |
|---|---|---|---|
| T-S1-01 | happy | `#pf_check` Counter 三根 | accept |
| T-S1-02 | error | `usesNat` | `Nat in root type` |
| T-S1-03 | error | `partial` / `sorry` / `IO` / `extern` / `implemented_by` | 对应 reject |
| T-S2-01 | happy | `#pf_extract` Counter | 抽出；increment sketch 含 `u64Max` |
| T-S2-02 | error | extract 夹带 `usesNat` | fail closed |
| T-S3-01 | happy | `#pf_extract` 后发射 | 含 entrypoint / overflow / disc / return data |
| T-S3-03 | error | 空 ops 的 `counterProgram` | 缺 `returnState` / `checkedAddU64` |
| T-S3-02 | error | 空 IR | `not counter shape` |
| T-S4-01 | happy | Mollusk init(5) | 账户 count=5 |
| T-S4-02 | happy | increment 5+3 | return 8，写回 8 |
| T-S4-03 | happy | get | return 8，不改账户 |
| T-S4-04 | error | increment max+1 | `0x1001`，状态保持 |
| T-S5-01 | happy | extract increment | ops 含 `checkedAddU64` |
| T-S5-02 | error | `wrappingAdd` | `increment not ite` |
| T-S5-03 | happy | 抽出 Counter | increment 先 load 账户再 load ix |
| T-S5-04 | happy | 对调 checkedAdd 左右 | 先 load ix 再 load 账户 |
| T-S5-05 | happy | extract decrement | ops 含 `checkedSubU64` |
| T-S5-06 | error | wrappingSub | mutating 缺 checked arith |
| T-F-01 | happy | Pair fields left/right | right 偏移 16；data_len 24 |
| T-F-02 | happy | extract Pair.creditLeft | ops 含 `field left` |
| T-F-03 | happy | 无 `with` 抽 Pair | fields = left, right |
| T-F-04 | happy | structure 含 `Bool` 字段 | 一字节 u8-le 叶，false/true 为 0/1 |
| T-F-05 | happy | Pair Mollusk init(7) | left=7，right=0，data_len 24 |
| T-F-06 | happy | creditLeft 5+3，right=99 | left=8，right 保持 99 |
| T-F-07 | happy | getLeft | return left，不改账户 |
| T-F-08 | error | creditLeft max+1 | `0x1001`，两字段保持 |
| T-L1-01 | happy | `#pf_build Examples.Counter` | 四方法；decrement 有独立 disc |
| T-L1-02 | error | 无 entry 的名字空间 | `extract/unsupported: no pf_entry` |
| T-L1-03 | happy | Pair Mollusk | disc 为 creditLeft / getLeft |
| T-L1-04 | happy | decrement 8-3 | return 5，写回 5 |
| T-L1-05 | error | decrement 2-3 | `0x1001`，状态保持 |
| T-L1-06 | happy | scale 5×3 | 15 |
| T-L1-07 | happy | scale 5×0 | 0 |
| T-L1-08 | error | scale max×2 | `0x1001` 保持 |
| T-L1-09 | happy | divide 8/3 | 2 |
| T-L1-10 | error | divide n/0 | `0x1001` 保持 |
| T-L1-11 | happy | modulo 8%3 | 2 |
| T-L1-12 | happy | nonzero 0 / 7 | return 1 / 0 |
| T-L1-13 | happy | 同一 Program 两次 digest | 相等 |
| T-L1-14 | happy | 改一个 op | digest 变 |
| T-L1-15 | happy | 发射文本 | 含 `digest=` |
| T-L2-01 | happy | Flag slots | flag 偏移 8 宽 1；count 偏移 9 宽 8 |
| T-L2-02 | happy | Maybe slots | slot_tag 8、slot_p0 16 |
| T-L2-03 | happy | 嵌套 structure / Bool | 递归摊平；Bool 为一字节 u8-le |
| T-L2-04 | happy | Flag Mollusk init | flag=0，count=7 |
| T-L2-05 | happy | Maybe none | 两叶清零 |
| T-L2-06 | happy | Maybe some 77 | tag=1，payload=77 |
| T-L2-07 | happy | SHA-256 `""` / `abc` | FIPS 向量 |
| T-L2-08 | happy | 未挂过的 `neverSeen(u64,u64)` | 算出 disc，不必改表 |
| T-L2-09 | happy | Window slots | cells_0=8、cells_1=16；data_len 24 |
| T-L2-10 | error | 不定长 Array 字段 | `use Vector` |
| T-L2-11 | happy | Window Mollusk + Anvil init(7) | head=7，tail=0 |
| T-L2-12 | happy | Window setTail 9 | 两个 target runtime 都验证 head 保持 7，tail=9 |
| T-L2-13 | happy | Phase slots | mode 偏移 8 |
| T-L2-14 | happy | 固定布局多构造子 UInt64 variant | tag + 最大 payload；短构造子补零 |
| T-L2-15 | happy | Phase Mollusk + Anvil init | mode=0 |
| T-L2-16 | happy | Phase setLive / setIdle / isLive | 两个 target runtime 都验证 tag 往返 0→1→0 |
| T-L3-01 | happy | Pair.initBoth 3 9 | left=3，right=9 |
| T-L3-02 | happy | getRight | return right，不改账户 |
| T-L3-03 | happy | Maybe.getValue none | return 0 |
| T-L3-04 | happy | Maybe.getValue some 77 | return 77 |
| T-L3-05 | happy | Choice slots | pick_tag 8、pick_p0 16 |
| T-L3-06 | happy | getHeld empty / hold 77 | 0 / 77 |
| T-L5-01 | happy | state-carrying bounded `forBody` | loop index 与外层 payload 身份不混淆 |
| T-L5-02 | happy | `Vector MarketEvent 4` 动态写 | root `pf_inline` State helper 的 tag + payload、计数与 lastEvent 同时写入；SVM/EVM 都可发射 |
| T-L5-03 | happy | Phoenix 跨四档 buy/sell | host reference 与 source structured fold 的 `#guard` 逐样本一致；不宣称链上逐样本 refinement |
| T-L5-04 | happy | Phoenix event batch（host / IR） | 官方 ordinal、instruction index、四-limb maker Pubkey 及 Fill/Expired/Reduce/Evict/Place/TIF/Fee/Summary 顺序正确；最宽 payload offset 72 进入 IR |
| T-L5-05 | happy / fail | Phoenix trader registry（host） | 四-limb Pubkey、幂等注册、容量上限、per-seat deposit 与溢出 |
| T-L5-06 | happy / fail | Phoenix seat lifecycle（host） | base/quote partial withdraw、非空拒绝 eviction、LIFO address reuse |
| T-L5-07 | happy / fail | Phoenix authenticated order lifecycle（host / IR） | post/reduce 由完整 signer Pubkey 解析 owner；ask/base 与 bid/quote per-seat reduce 同步解锁；伪造 seat 参数已从 ABI 删除 |
| T-L5-08 | happy / fail | Phoenix per-seat posting（host / IR） | 普通 ask/bid 锁仓及跨 owner 满书 eviction 原子更新两边 TraderState；抽取 IR 保留动态 index writes |
| T-L5-09 | happy / fail | Phoenix per-seat matching（host / fold） | signer-derived self-trade；ask/bid fill、TIF expiry、self-cancel 原子更新 maker/taker 四类余额；逐 seat 一致；不足 maker ledger fail closed |
| T-L5-10 | happy | inline scalar / record projection | `pf_inline` UInt64/Bool helper 与 updated-record projection 在 variant payload 中归一化；不泄漏未知 state leaf |
| T-L5-11 | happy / fail | Phoenix Mollusk lifecycle matrix | ask/bid post+reduce+swap、collect/withdraw/evict、严格 slot/time TIF、Abort/CancelProvide/DecrementTake、缺 signer 与伪造 state owner 原子失败 |
| T-L5-12 | happy / fail | Seat Mollusk CPI matrix | canonical seat PDA 创建；base/quote vault 写入不同 mint 与同一 owner；缺 payer signer / vault writable 原子失败 |
| T-L5-13 | happy / fail | Phoenix 双 vault CPI matrix | canonical base/quote vault；真实 deposit/withdraw；未注册 buy/sell 两个 Token 腿；错 vault/mint/Token program/writable 全部原子失败 |
| T-L5-14 | happy / fail | 通用 raw self-CPI recorder | packed u16/u64 payload；当前 program id；canonical `"log"` PDA readonly signer；续段状态写回；错 PDA、缺 signer、writable、错 tag 全部拒绝 |
| T-L5-15 | happy / fail | Phoenix authenticated audit recorder | initialize、资金、订单、撮合、TIF、费用与 seat 路径的 Header/event Borsh IR；当前 program + `"log"` PDA signed self-CPI；Mollusk 实收 `Program data`；错 self program / log PDA 原子失败 |
| T-L5-16 | happy / fail | Phoenix persisted trader topology | 24 种 key 插入顺序 × 每个删除 key 的 host 红黑不变量；抽取 IR 钉住动态 links/color/allocator writes；Mollusk 验证删除 root 后 surviving root/seat 与 address reuse |
| T-L5-17 | happy / fail | Phoenix persisted order topology | ask/bid 各 24 种插入顺序、24×4 单点删除/复用及 24×24 完整删除顺序 host 红黑不变量；抽取 IR 钉住 qualified nested-vector links/color/allocator writes；Mollusk 验证两边 root、best traversal 与满书 eviction 的 exact address reuse |
| T-L5-18 | perf / fail | Phoenix Extract P0 资源门 | `postAsk` 全部嵌套 op 的 `IR.Val` 总节点 `< 200,000`、最大单树 `< 50,000`；单方法与全程序发射成功；state-loop continuation 解码失败不得只返回 scalar 或部分 commit |

T-L5-11 已覆盖主要单档链上生命周期；T-L5-03 的跨四档逐样本 host↔chain
refinement 仍未宣称。P0 探针口径递归统计 `select` 四个分支和 extension operands；当前
`postAsk` 为 total 90,604 / largest 24,840，单方法 assembly 3,755,860 bytes，完整程序
assembly 设 `< 12,000,000` bytes 的有限回归门。完整 ELF/IDL/digest 只以当次
`pf build --target svm Phoenix` 产物记录为准；当前为 assembly 11,815,636 bytes、ELF
3,550,888 bytes、IDL 19,626 bytes、digest `65fbdcc1cf643f02`，不从旧 topology 快照外推。
