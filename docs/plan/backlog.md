# Backlog

补全依据：[analysis/authority.md](analysis/authority.md)。
缺口阶段：[analysis/gap-vs-proofforge.md](analysis/gap-vs-proofforge.md)。

## 已做

- S0–S5：普通 Lean Counter 竖切到 Mollusk
- 多字段 UInt64；从 `init` 返回 structure 收字段；Pair `.so` / Mollusk 4/4
- Loader 偏移按 `dataLen` 算
- `@[pf_entry]` + `#pf_build`；按名 disc；Counter 同程序 decrement
- 任意 `ite`；checked mul/div/mod；`=` `≠` 比较；Counter scale/divide/modulo/nonzero
- `IR.digestHex`（FNV-1a 64）；`#pf_build` 抽出与 fixture 必须同一 digest
- 带类型字段表：`UInt8/16/32/64` + `Option UInt64` 双叶；Flag / Maybe Mollusk
- disc / layout marker 本机 SHA-256，不再挂名表
- 定长 `Vector UInt64 n` 展开成连续槽；Window Mollusk；不定长 Array fail closed
- 无 payload 枚举作 tag；Phase Mollusk；带 payload 仍 fail closed。Bool 已在 L4-034 开成 1 字节 u8-le
- 多个 init；`init` paramCount 按 λ 算；Pair `initBoth` / `getRight`
- `Option UInt64` match 读 payload；Maybe.getValue Mollusk
- 单字段用户 inductive 作 tag+payload；Choice Mollusk
- `clockSlot` + 账户 0 `signerKey0`；Clock Mollusk
- 封闭 `system.transfer`；三账户虚地址 walk + `sol_invoke_signed_c`；Transfer Mollusk
- 编译期钉死的 `invoke`；`systemTransfer` / `invokeAcc1` 共用发射器；Ping Mollusk
- 账户 0 AccountInfo 只读叶子（lamports / owner 首 u64 / data_len / NUM_ACCOUNTS / 三旗）；Info Mollusk
- 表层通用 `invoke`；`systemTransfer` / `invokeAcc1` 是普通包装；Call Mollusk
- `findPda` 一条 ASCII 种子 + 当前 program id；返回 bump；Pda Mollusk
- `invokeSigned` 一组 ASCII 种子 + bump；Signed Mollusk（错 bump 失败）
- `systemCreate` 普通包装；owner = 当前 program id；Create Mollusk
- `tokenTransferChecked` 普通包装；Token `TransferChecked`；TokenXfer Mollusk
- `ataCreateIdempotent` 普通包装；ATA CreateIdempotent；Ata Mollusk
- `rentExemption` 叶子；`sol_get_rent_sysvar` × `(128+n)`；Rent Mollusk
- `tokenMintToChecked` / `tokenBurnChecked`；TokenMint Mollusk
- `systemAssign` / `systemAllocate`；SysAlloc Mollusk
- `tokenInitAccount` / `tokenCloseAccount`；TokenAcc Mollusk
- `memoWrite`；Memo Mollusk
- `createPda`；CreatePda Mollusk
- `checkPda`；Pda Mollusk 验证 bump
- `tokenApproveChecked` / `tokenFreezeAccount` / `tokenThawAccount`；TokenApprove / TokenFreeze Mollusk
- `clockEpoch`；Clock Mollusk 两次 warp 跨 epoch
- `tokenSetMintAuthority` / `tokenRevoke`；TokenAuth Mollusk
- `slotsPerEpoch`；Epoch Mollusk 改 schedule
- `tokenAccountSize` / `cpiReturn`；TokenSize Mollusk 返回 165
- `systemAllocateWithSeed`；SysSeed Mollusk
- `systemCreateWithSeed`；SysSeed Mollusk 转 lamports
- `systemAssignWithSeed`；SysSeed Mollusk 改 owner
- `systemTransferWithSeed`；SysXfer Mollusk
- `tokenInitMint`；TokenMint2 Mollusk
- `tokenSyncNative`；TokenNative Mollusk
- 账户 1 只读叶子；Peer Mollusk
- `sha256Lit`；Hash Mollusk
- 32B key / owner 按字读；Keys Mollusk
- `keccak256Lit`；Keccak Mollusk
- 账户下标叶子收口；Trio Mollusk
- Bool / `unixTime` / nonce prelude / SetAuthority owner / Approve / Multisig2；Gate / Nonce / TokenOwner / TokenMs Mollusk
- Core control/schema 与 `Svm.Ops/IR/Runtime`、`Evm.Ops/IR/Runtime` 分层；Extract.IR 是唯一 typed target-extension 组合点
- 嵌套 structure / `Vector Nested n` 摊平；Nested / Tree Mollusk
- Phoenix bounded N=4 双边书、四 seat registry、逐 seat 结算、TIF、费用和 typed event batch
- SVM 异构 PDA seeds（ASCII/state key/account key）、完整 canonical key 校验和可续接 ignored CPI；Phoenix classic SPL Token 双 vault 全链路
- SVM packed u8/u16/u32/u64 CPI words 与 canonical PDA 签名 raw self-entry；SelfLog 覆盖 self-CPI、续段写回和认证失败矩阵
- Phoenix 官方形状 `AuditLogHeader` / Borsh event 通过 `"log"` PDA signed self-CPI 发布真实 `Program data`
- SVM 49 个 registry program 各有 runtime test 文件；EVM 12 个 registry program 全进 Anvil 总入口
- 审查修复：分支 fallthrough、state owner/marker、常量求值、Option identity、窄叶、Nat.sub、移位、EVM init、未知 CPI、solc 诊断
- GitHub CI 串行执行 Lake guards、49 个 SVM 构建 + Mollusk，以及 12 个 EVM 构建 + Anvil
- Core 显式 basic-block CFG 第一阶段：block arguments、显式 branch/checked/exit、完整 checker、local CSE、线性共享 block；Phoenix 全方法已通过 lowering/validation
- SVM/EVM emitter 已消费 target-owned Core CFG：SVM 用全局 block layout + 迭代 long-jump relay，EVM 用 Yul `pf_pc` dispatcher；当时 Phoenix 汇编由 4,109,725 B 降至 2,748,784 B（加入 trader topology 后当前为 3,314,430 B），全部 49 个 Mollusk 文件与 12 个 Anvil 程序通过
- Solanalib CFG correspondence：Counter add/sub/mul/div/mod 的 Core operands / physical slot / success-overflow edge 必须一致；typed guards、multiply zero-path jump、`r10-24` scratch handoff、static store 由上游 small-step semantics 执行。普通 eq/ne/lt/le/gt/ge branch 保留 cmp/operands/then/else identity，exact decoded pair theorem 证明 edge selection 与内存不变
- 通用 target registration：`Core.Target.Registration` 统一递归投影公共 Val/Op/Program，并携带 extension callbacks、arity、op well-formedness 和 CFG dialect；SVM/EVM conversion 已移回各自 IR，`Extract.IR` 不再含后端 projection case。Core-only 合成第三 target 证明新增公共语言后端无需修改抽取 IR，并继续 fail closed 拒绝 foreign extension
- Token-2022 classic-compatible `TransferChecked`：通用 `CpiMeta.expectedDataLen` 在 CPI 前约束 base Mint=82B / Account=165B；真实 base transfer 成功，transfer-fee / enabled transfer-hook mint 原子拒绝；Runtime CPI wrapper 改为按命名空间统一展开，不再维护 recipe 名白名单
- 独立 Tree N=4 删除切片：successor transplant、全部可达 delete-fixup、free-list 回收和精确地址复用；24 种插入顺序 × 4 个删除 key 的宿主不变量门，以及 black-leaf fixup/reuse Mollusk 链上门
- Phoenix trader tree 持久化 N=4 topology：root/left/right/parent/color、bounded 插入/删除修复和 exact address reuse；deposit 沿 links 查找并复用 parent，evict 先 detach 再回收。抽取器只增加 target-neutral 的 continuation/conditional-state/vector-write lowering，没有 Tree/Phoenix 名字或 emitter 特判
- Phoenix ask/bid order tree 持久化 N=4 topology：payload 地址稳定，撮合按中序 best/successor 遍历，fill/expiry/reduce/cancel detach，满书驱逐后 exact address reuse。通用抽取器增加 scalar let zeta-reduction 和 qualified nested-vector schema path；两个 target emitter、IR 与 Phoenix ABI 无需特判或改动

## 当前状态

- `lake build Tests` 当前 190 jobs；69 个 imported test modules 含 809 个 `#guard` / `#guard_msgs`。
- SVM registry 49 个程序 / 49 个 Mollusk integration 文件；这表示每个程序有门，不表示每个入口都已有链上矩阵。
- EVM registry 12 个程序；Counter / Pair / Flag / Maybe / Context / TipJar / Lang / Vault / Ownable / Token / Window / Phase 的 Anvil 总门 12/12。
- Phoenix Mollusk 已覆盖 ask/bid 挂单、reduce、双向撮合、费用收取、真实 base/quote deposit/withdraw、trader topology 删除后的 surviving root、ask/bid order topology 与满书 exact address reuse、未注册 take-only 双 Token 腿、严格 slot/time TIF、三种 self-trade、认证 audit `Program data`，及 vault/mint/Token program/self program/log PDA/writable/signer/owner 原子失败；跨四档逐样本 refinement 仍由 host/IR 门承担。
- `l5-003` 与 Phoenix 双 vault adapter 已完成：Seat 初始化和 Phoenix 同一入口的 canonical PDA 校验、classic SPL Token CPI 成功/失败路径都进 Mollusk。
- `l5-004` Token-2022 classic-compatible program-id 切片已完成；TLV extension 语义仍保持 fail closed。
- `l5-005` 已完成；任务状态已同步为 done。

## Phoenix / Solana P0–P5 路线

| 阶段 | 状态 | 依赖 | 验收门 |
|---|---|---|---|
| P0 抽取收口 | 进行中 | 通用 Extract state-loop/helper sequencing；SVM CFG/local 布局 | `postAsk` 值树预算、单方法发射、PhoenixSpec、可复现的 wall/RSS/assembly 数据；continuation 解码失败必须 fail closed，不能退化成部分 state commit |
| P1 bounded 产品语义 | 已有 | P0；固定 N=4 账户布局 | ask/bid/trader 三棵持久化树的 N=4 host/IR 门、24 种 topology、双向 IOC、TIF/self-trade/fee/事件与 exact address reuse 全绿 |
| P2 链上认证矩阵 | 部分支持 | 可组装 Phoenix ELF；classic SPL Token 与 signed self-CPI | Phoenix Mollusk lifecycle/CPI/authenticated audit 矩阵全绿；跨四档逐样本 chain refinement 补齐前不得宣称 host↔chain 完整 refinement |
| P3 横向回归 | 部分支持 | P0/P2 产物稳定 | Tree Mollusk、全 SVM registry Mollusk、全 EVM registry Anvil 及 `lake build Tests` 全绿，无 target-specific Phoenix 特判 |
| P4 产物资格/压缩 | 未支持 | P0 的稳定 CFG 和可测基线 | 在独立 milestone 中确定部署上限，做通用 CFG/shared-block/CSE；assembly/ELF 预算和 digest 更新后才能作部署体积声明 |
| P5 动态 Phoenix-v1 | 未支持、非当前目标 | 账户容量/profile、bounded CFG 策略与变长协议类型设计 | 明确账户上限和资源模型后另立规格；在此之前动态容量、remaining accounts、完整 Phoenix-v1 账户兼容均 fail closed |

P0–P4 不把 Phoenix 名字或字段偏移加入 Extract/IR/emitter。固定长度 32-byte / u128 /
Borsh protocol types 可在 P4/P5 前置设计；当前 Pubkey 与 client id 仍以 `UInt64` limbs
表达。P5 不是把运行时变长账户偷偷放进现有 profile，也不是 P0 的验收条件。

## 明确保持 fail closed

- 搬 PF 前端 / `HandlerIR.mk` 私有构造、新 DSL、无约束 Lean、FFI→asm。
- `.so` / loader / 全 SVM refinement 与公网部署声明。
- 运行时 program id、变长 data、运行时 remaining accounts；编译期钉死的 CPI 已开。
- Token-2022 transfer hook / fee / TLV extension 语义，直到对应账户模型落地；当前 base-layout
  wrapper 用精确 data length 在 CPI 前拒绝全部 extension-bearing mint/account。
- feature-gated blake3 / poseidon / curve25519 / alt_bn128 / `sol_get_sysvar`。
- 把完整 32B key 当作现有 8B return-data ABI 的单一返回值。

历史 SDK 清单和阶段分析保留作设计记录，不再当当前 backlog：
[sdk-surface.md](analysis/sdk-surface.md)、[gap-vs-proofforge.md](analysis/gap-vs-proofforge.md)、
[remaining-surface.md](analysis/remaining-surface.md)。
