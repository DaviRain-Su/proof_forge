---
id: ADR-0030
title: pf.assets 词汇扩展波（token 绑定 + balanceOfSelf env-read + AMM 北极星）
status: proposed
owner: architecture
updated: 2026-08-06
normative: true
---

# ADR-0030：pf.assets 词汇扩展波

- 状态：`proposed`
- 日期：2026-08-05
- 前置：ADR-0029（L1 portable extension 层 + catalog 包装 + A→D 分期已收口）

## 背景

ADR-0029 建立了 L1 词汇层并完成 `pf.assets@1.0.0` 的 native 两 API 在五条 target
的绑定（Quint 模型 / EVM / Solana / CosmWasm / NEAR；Psy/Aleo 零绑定；Noir 永久 FC；
TON 冻结）。但 v1 只有 native deposit/transfer，**复杂应用（DEX/借贷/治理）做不了**。
本 ADR 以 **Uniswap V2 式 AMM** 为北极星，冻结下一波词汇扩展的范围与纪律。

关键事实：`pf.assets.token.transfer` / `token.transferAsync` **已在 v1.0.0 frozen
payload 中**（5 QN 之二），当前全 target fail closed 于 Plan——token 家族的开通
**不需要 payload 改版**，是纯 per-target binding 工作。只有全新能力（余额读取、
授权扣款、发行）才需要 payload bump 与有意的重新 opt-in（ADR-0029 准入治理第 1 条）。

## Uniswap V2 能力分解（北极星依据）

| AMM 需求 | portable 对应 | 本波处置 |
|---|---|---|
| 代币转入/转出池子 | `pf.assets.token.transfer`（已在 payload） | **E1：四条部署链绑定** |
| 读自身代币余额（reserves 模式） | `pf.assets.*.balanceOfSelf`（新 env-read） | **E2：payload v1.1.0** |
| 恒定乘积 x*y≥k | UInt128/256 宽算术 | 已有，不动 |
| LP 份额 | v1 内部记账（`Map Principal UInt64` state） | 已有；发行真资产（mint）**defer 至 custody/issuance v2** |
| LP 归属/权限 | `context.caller`（编码已冻结于 ADR-0025） | **E3：Plan 层开放（B-CTX-OPEN）** |
| TWAP | `context.unixTimeSeconds` + 累积器 | 已有，不动 |
| 授权扣款 transferFrom | 模型不通用（NEP-141 无 allowance） | **本波不做**（V2 reserves 模式已绕开） |
| flash swap（先发货+回调） | 动态 callee + 回调 | **本波不做**（破 static-QN 根基，见否决） |

**V2 的热路径刻意不用 transferFrom**（用户先转账、pair 读自身余额），所以 MVP AMM
只需要 transfer + balanceOfSelf + caller——不需要发明 allowance 抽象。

## E1：`pf.assets.token.transfer` per-target 绑定（payload 不变）

| Target | 绑定 | 关键设计点 |
|---|---|---|
| EVM | ERC-20 `transfer(address,uint256)` | **动态 callee**：token 合约地址来自 `mint` Principal 参数（exact wire shape `u32le(20)||addr20`，B2 dst 同纪律）；这是受控的动态地址 CALL，**仅允许 catalog token 家族**（非任意 dynamic callee）；返回值 quirks（无返回值/USDT 类）入 catalog predicate；失败（revert/false）传播 |
| Solana | classic SPL `transferChecked`（vault ATA → dst ATA） | 复用 ADR-0028 机器：fixed Token program id + 动态账户（无动态 callee 问题）；dst ATA 缺失先行 `createIdempotent`；decimals join 入 catalog |
| CosmWasm | CW20 `Transfer` execute（WasmMsg SubMsg 给 token 合约） | 动态 token 合约地址（bech32 编码契约同 C1 dst）；error-propagating SubMsg 同 C1 sync 纪律 |
| NEAR | NEP-141 `ft_transfer`（async） | **仅 `transferAsync` 可绑**（跨合约为 Promise）；sync `token.transfer` 永久 FC |
| Quint | 模型层 token vault（mint-keyed Map） | 可选；Q0 若能诚实建模 mint-keyed 余额则绑，否则保持 FC |
| Psy/Aleo/Noir/TON | 全 FC | 与 v1 结论一致 |

**动态 callee 纪律（新冻结）**：token 家族把 callee 从 static-QN 扩为「参数携带、
catalog 限定、exact wire shape 校验」的动态地址。这不是任意 dynamic call——EVM 的
generic dynamic callee 仍 FC；只有 catalog 声明的 token 接口形态允许参数化地址。

## E2：`balanceOfSelf` env-read（payload v1.1.0）

新增 QN（payload bump → 新 digest → 源码显式重新 opt-in）：

| QN | 语义 | 各 target 诚实性 |
|---|---|---|
| `pf.assets.native.balanceOfSelf() : UInt64` | 读 self vault 原生余额（view 可用；只读） | EVM `selfbalance` / Solana vault PDA lamports / CW `query_balance`（env）/ NEAR `account_balance` host——均 sync 可读 |
| `pf.assets.token.balanceOfSelf(mint : Principal) : UInt64` | 读 self 的 token 余额 | EVM 需 staticcall ERC-20 `balanceOf`（动态 callee + 只读）；Solana 读 vault ATA data（账户须传入）；CW smart query（WasmQuery——mock 可查）；**NEAR 跨合约 view 是 async → FC** |

**E2 设计冻结（2026-08-05，payload 先行；2026-08-05/06 已全波接线，见文末工程事实）**：

1. **env-read 是新的 Semantic op 家族**（不同于 `Op.ExternalCall`/`Op.Schedule`）：只读、
   **view 可用**、**不产生 effect**（不进 EffectId 序列）、结果为 `UInt64`、
   snapshot 语义取执行点值。它不是 `Op.ContextRead`（caller/time 等交易上下文）的
   复用——余额是账户状态观察，独立成族；两个成员统一建模
   （native vault / token vault(mint)），per-target 物化形态各异：EVM 原生=
   `SELFBALANCE`、token=`STATICCALL balanceOf(self)`（受控动态 callee 同 E1a 纪律）；
   Solana 两者均为**直接账户数据读**（vault PDA lamports / vault ATA amount 叶，无
   CPI；vault ATA 缺失 fail closed，不谎称 0）；CW=querier（bank query / WasmQuery
   smart query，均 sync）；NEAR 原生=host `account_balance`，token 永久 FC；Quint=
   模型 vault 读；Psy/Aleo/Noir/TON 维持 pf.assets 既有 disposition（FC/冻结）。
2. **结果承载的 catalog 调用形态**：env-read 家族是首个非 `Unit` 结果的 catalog
   成员，`sourceRestrictions.typedCallReturn` 由 v1.0.0 的 `false` 变为
   `"env-read-family-only"`——仅 env-read QN 可出现在**表达式位置**（typed call
   return）；语句位置裸调 result-bearing QN 仍 fail closed；既有五键 Unit 调用
   形态不变。这是前端/Normalize 的 scoped 开口，不是通用 typed-call-return。
3. **Reference 语义**：E2 接线时为 pf.assets 家族补最小 self-vault 解释器
   （native vault lamports 与 mint-keyed token vault 记账；deposit/transfer 写、
   balanceOfSelf 读），把 ADR-0029 的「Reference opaque void」caveat 对资产词汇
   闭合；env-read 在 Reference 为 O(1) 读，无 fuel 扩张。
4. **payload v1.1.0 已冻结（inert，未接线）**：
   [`pf-assets-extension-v1.1.json`](../specs/pf-assets-extension-v1.1.json)，
   raw SHA-256 `47f836c2dceaba1c6f93d8b682d451e8f75baab31fac29a511f23e3010a606f6`，
   domain digest `sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9`
   （同公式 `SHA-256("pf.extension-semantics.v1"||NUL||JCS)`）；七行 API = v1 五行
   byte-identical 超集 + 两个 env-read 行；`docs-check` 同构门已 pin 字节与 digest。
   **迁移纪律**：acceptance cutover 时源码 `requires extension` 声明须显式重 opt-in
   exact triple `pf.assets@1.1.0`；v1.0.0 digest 在 cutover 后 fail closed，全部既有
   fixture 同批扫换。**cutover 已完成（2026-08-05，commit `5c78d975c`）**：@1.1.0
   现为唯一被 acceptance 承认的 triple，v1.0.0 声明在 ContextExtensionCheck
   fail closed。

## E3：`context.caller` Plan 层开放（B-CTX-OPEN 的 pf.assets 承接）

LP 份额/权限需要 caller。编码已冻结（ADR-0025：`u32le(20)||addr20` EVM；各 target
按各自 identity 长度另决策）。AMM 热路径只依赖 entry caller；若 target 宿主能诚实提供
view caller（EVM），可按 ADR-0031 view-safety 轴同时开放；NEAR/CW 等无 caller 的 view/query
必须 fail closed。per-target 原子 cutover 纪律不变。

## E4：MiniAMM 北极星里程碑

`Examples/MiniAmm.lean`（工作名）：add-liquidity（内部 LP 份额记账）+ swap
（reserves 模式：transfer + balanceOfSelf + 恒定乘积）+ remove-liquidity；
目标在 **EVM + Solana**（至少两条部署链）上经各自 runtime 门（Anvil/Mollusk）
验证成功/失败/回滚路径。这是词汇层正确性的应用级证据。

## 分期

| 期 | 内容 | 依赖 | 状态 |
|---|---|---|---|
| **E1** | token.transfer 四链绑定（EVM/Solana/CW/NEAR-async） | 无（payload 已含 QN） | **done（2026-08-05）**：E1a EVM / E1b Solana / E1-CW / E1-NEAR(async) 全绑 |
| **E2** | payload v1.1.0：balanceOfSelf env-read + Reference/Normalize 接线 | E1 可先并行 | **done（2026-08-05/06）**：核心/Reference vault、acceptance cutover（1.1.0 唯一承认）、EVM/Solana/CW 双键、NEAR/Quint native-only（token env-read 永久 FC）、Psy/Aleo/Noir/TON 维持既有 disposition |
| **E3** | context.caller Plan 开放（per-target 原子 cutover） | 独立（B-CTX-OPEN / ADR-0031 S1） | **in_progress**（2026-08-06：EVM CALLER→Principal + Anvil 已交付；Solana/NEAR/CW lanes 进行中） |
| **E4** | MiniAMM 北极星（EVM+Solana 双链 runtime 门） | E1+E2+E3 | pending |

并行纪律同 ADR-0029：shared payload/Normalize 变更串行于 main；per-target binding
lane 文件不重叠可隔离 worktree 并行；每期以对应 runtime 门收尾。

**E1 工程事实（2026-08-05）**：`pf.assets.token.transfer`（v1.0.0 payload 既有 QN，
无 payload 变更）已绑定两条部署型 target。**EVM**（E1a，commits `77ff279f7` +
`cf64bf14e`）：ERC-20 `transfer(address,uint256)` CALL，mint Principal 参数经
exact wire shape `u32le(20)||addr20`（高肢清零）解码为 20 字节 token 合约地址——
受控动态 callee，仅 catalog token 家族准入，generic dynamic callee 仍 FC；calldata
exact（selector `0xa9059cbb` + 32B address + 32B amount）；返回值三分支 catalog
predicate（returndatasize 0 → USDT 式成功、32 → 首 word 非零、其余 revert），CALL
失败传播 revert；合约自身 ERC-20 余额即 vault，entry 保持 nonpayable。产品纵切
`TokenJarEvmV1`（solc 0.8.34 bytecode + exact closure）；Anvil 工程门真跑
（`scripts/evm_tokenjar_anvil_smoke.sh` 作为 `evm_anvil_differential.sh` companion
leg：mint 2000 → `tipToken(mint,dst,1000)` 精确 ±1000 余额差值、超额 revert 状态
保持、returnFalse 负例、USDT 无返回成功、mint/dst wire-shape 负例全过）。
**Solana**（E1b，commits `611d350da` + `c5d832d4b` + 本收口）：frozen composite
六步序——vault PDA find → vault ATA find+`createIdempotent` ensure → dst ATA
find+ensure → classic Token `transferChecked`（authority=vault PDA，单 signer group
`invoke_signed`）；ATA program 账户经 derive/Plan 补为 outer role（否则
NotEnoughAccountKeys）；**ADR-0028 §4.2 site-time 纪律修正**：两 ATA 的 165B/
initialized/mintEq/ownerEq/delegateNone 谓词从 pre-invoke siteChecks 过滤，改在每次
ensure 之后由 `emitPfAssetsAtaPostEnsure` 重查（fresh ATA 由 ensure 自身初始化，
pre-invoke 检查必假）；**ROLE_DATA_LEN 刷新**：fresh createIdempotent 把账户
realloc 为 165B，role slot 的 data_len 标量仍是 entry 快照 0（lamports/owner/data
为指向 live 输入区的指针，由 runtime `update_caller_account` 自动同步，唯
data_len 是值拷贝），不刷新则下一个 CPI 的 `update_callee_account` 比较 0 vs 165
以 `AccountDataSizeChanged` fail closed——ensure 后显式写回 165（幂等路径无害）。
产品纵切 `runtime-tests/solana/fixtures/TokenJarAssets.lean` 经真实 CLI
`build --profile solana-sbpf-cpi-elf-v1` → `TokenJarAssets.so`（37528 B）+
`inspect` exact closure；Mollusk 工程门真跑（`runtime-tests/solana` **16**
binaries / **338** active，`tipjar_token` **14/14**：pin 矩阵、init/get、既有双 ATA
精确 ±1000 余额差值、fresh dst ATA 创建+转账、underfunded 完整 snapshot rollback、
wrong-mint join、non-canonical dst ATA、多/零 signer 负例）。CW20（CosmWasm）与
NEP-141 `ft_transfer`（NEAR，仅 transferAsync 可绑）为 E1 第二波，未开。
**非** formal TASK/TST、**非** 主网/mainnet parity；Anvil/Mollusk 为工程
local_runtime 门，Reference 仍 opaque void（无 vault 解释器）。

**E1 第二波工程事实（2026-08-05，E1 全波收口）**：**CosmWasm**（E1-CW，commits
`df1ce458a` + `a52cd5329`）：`pf.assets.token.transfer` → CW20 `Transfer` execute
作 `WasmMsg::Execute` SubMsg `reply_on=never`（error-propagating 同 C1 纪律；CW20
调用失败打爆整笔交易）；mint/dst 均 `u32le(len)||utf8-bech32-bytes` 精确 wire
shape（受控动态 callee，仅 catalog token 家族）；funds 为空、entry 非 payable；
`token.transferAsync` 保持 FC。cosmwasm-vm mock 门真跑（`tokenjar.rs` 5 项：CW20
SubMsg shape + base64 解码 payload 断言、tips 状态、非 payable/畸形 wire-shape
trap、no-BankMsg 诚实门）；**安全加固**：`pf_dst_check` 补 lowercase bech32 charset
`[a-z0-9]` 门（C1 文档原称 "printable ASCII" 未实现且不足以防 JSON 注入——quote/
backslash 属 printable——现按构造排除引号/反斜线/控制字节，覆盖 C1 native dst 与
E1-CW mint/dst 三路，双套件注入负例全过）；诚实上限：mock 不分发 SubMsg 到真实
CW20（cw-multi-test 不能宿主裸 Wasm），余额差值属 wasmd rung 未声明。**NEAR**
（E1-NEAR，commit `777f26f61`）：`pf.assets.token.transferAsync` → fire-and-forget
NEP-141 `ft_transfer` Promise（`promise_batch_create(mint)` +
`promise_batch_action_function_call`，exact JSON args
`{"receiver_id":dst,"amount":"<decimal>"}`、30 Tgas 冻结 gas、**恰好 1 yoctoNEAR**
attached deposit——NEP-141 核心要求）；mint/dst account-id 语法门同 C2 dst
（2..64、lowercase a-z/digits/`_`/`-`/`.`、无首末点）；sync `token.transfer` 永久 FC。
lane 顺带修复 schedule pilot 潜在 ABI bug（`promise_batch_action_function_call`
import 误为 8 参 amount_low/high，真实 host ABI 为 7 参 amount_ptr→u128 LE；schedule
call site 同步修正，WAT pin 迁至 7 参形态）。near-sandbox 门真跑（7 suites 全 PASS）：
TokenJarAsync 部署最小 mock NEP-141（pinned `mock_token.wat` + locked wat2wasm，
其 `ft_transfer` **断言恰好 1 yoctoNEAR**）到带 key 子账户（near_rpc 新增
`create_subaccount_with_key`/`deploy_to`/signer override；AddKey FullAccess 为
Borsh variant 1），验证 jar SuccessValue、fire-and-forget 状态推进、mint 账户
SUCCESS receipt + `ft_transfer ok` 日志；诚实上限：mock 无账本记账，token 余额
差值未声明。**E1 至此四链全绑**（EVM/Solana/CW sync + NEAR async）；Quint 模型
token vault 维持 E1 可选未绑；**非** formal/mainnet parity。

**E2 工程事实（2026-08-05/06，E2 全波收口）**：env-read 双键
（`pf.assets.native.balanceOfSelf()` / `pf.assets.token.balanceOfSelf(mint)`）
已完成核心→acceptance→六 target 物化。**核心**（E2-1 commits `cd07af465` +
`277038aaf`）：`SemanticOpV1.envRead`（`.nativeVaultBalance`/`.tokenVaultBalance`）
+ string-tagged wire codec + checkOpTyping 精确契约（native 0 参、token 1
Principal 参、结果=唯一 UInt64 TypeId）+ `validateEnvReadRequirementsV1`（envRead
使用绑定 pf-assets 1.1.0 requirement 行）+ invariant root/closure pureFn 禁表 +
**Reference self-vault 解释器**（`ReferenceVaultSeedV1`：deposit checked 入账
（溢出 trap）、sync transfer 在 response 消费后扣账（不足 revert
`externalCallReverted`，cursor 纪律保持）、transferAsync 足则扣不足中立、envRead
O(1) 读（缺 mint=0）——ADR-0029 的 Reference opaque-void caveat 对资产词汇闭合）。
**前端/Normalize**（E2-2，commit `5c78d975c` 等）：env-read QN 以 `.constructor`
表达式解析、resolution 期经封闭表 `pfAssetsEnvReadQualifiedNamesV1` 判别；
TypeCheck 精确 UInt64/arity/Principal 并要求 1.1.0 声明；语句位置裸调 FC；
Disclosure public；RequirementsInfer 贡献 extension.pf-assets（非
effect.synchronous-call）；Normalize 降 `Op.envRead`。**per-target 物化矩阵**：

- **EVM**（E2-3-EVM，commit `8f12aaf99`）：native=`SELFBALANCE` + UInt64 range
  guard；token=只读 `STATICCALL balanceOf(address)`（selector `0x70a08231` + 32B
  self `ADDRESS`，mint 经 E1a 受控动态 callee wire shape；returndatasize==32 且高
  192 位清零，否则 revert）。Anvil 工程门 envread leg 真跑
  （`scripts/evm_envread_anvil_smoke.sh` companion leg + corpus manifest 同步）。
- **Solana**（E2-3-Solana，commit `74b50a67e`）：native=vault PDA lamports 经 live
  `ROLE_LAMPORTS` cell；token=canonical vault ATA derive
  （`sol_try_find_program_address` + key join）+ frozen coherence contract
  （System-owned 0/0 → 0；Token-owned 165B、`state[108]==1`、mint-join、
  owner==vault-PDA、zero-delegate → amount LE `data[64..72]`；其余 err_shape）；
  纯账户数据读、无 CPI；`CpiProductCapabilityV1` 调整为仅当 program 有 call sites
  时才要求 sync-call support（envRead-only 程序准入）。Mollusk
  `tipjar_assets`/`tipjar_token` legs 扩展真跑。
- **CosmWasm**（E2-4-CW，commit `aabf7c806`）：新增 `env.query_chain` host import
  （cosmwasm-vm 3.0.9 规范 raw-WASM querier 通道）；native=bank query
  `{"bank":{"balance":{"address":self,"denom":"stake"}}}`；token=CW20 smart query
  envelope `{"wasm":{"smart":{"contract_addr":mint,"msg":<base64>}}}`，其中
  `<base64>` 编码内层 `{"balance":{"address":self}}`（`WasmQuery::Smart.msg` 为
  Binary=base64 字符串，**非** inline JSON）；响应 envelope `{"ok":{"ok":"<b64>"}}`
  → 内层 base64 解码 → `"amount":"`/`"balance":"` 十进制扫描，Uint128→UInt64
  溢出 trap；needle 固定偏移表扩 11 根（3055..3240）；tokenVaultBalance
  resultTemp 按 ValueId→IR temp 分配 + localEnv 绑定（同 forLoop varTemp 纪律）。
  cw-vm mock `envreadjar.rs` 真跑（native 2000/3500/0 精确；token responder 断言
  msg 精确 + unknown-mint/畸形 wire-shape 负例）。
- **NEAR**（E2-NEAR，commit `4e94b405e`）：native=host `account_balance`（ABI 同
  `attached_deposit`：balance_ptr→u128 LE）+ hi64-zero-else-trap range guard，
  条件 import 由结构扫描驱动；token 永久 FC（NEP-141 `ft_balance_of` 为跨合约
  view，NEAR 异步 promise 模型无法在表达式内同步完成——诚实边界非债务）。
  near-sandbox 门第 8 套件 EnvReadJar 真跑（子账户部署隔离 master gas 混淆；
  真实余额 ~10^24 yocto ≫ 2^64 → trap 分支真实触发；acceptNative deposit 精确
  落账、wrong-deposit 状态保持）。**实用性 caveat**：2^64 yocto ≈ 0.0000184 NEAR，
  真实账户余额几乎总使该绑定 trap——UInt64 结果纪律与 u128 yocto 面额的已知
  产品级张力，不阻塞 E2（E4 北极星不依赖 NEAR）。
- **Quint**（E2-Quint，同 commit `4e94b405e`）：native=模型 `vaultNative` 读
  （与 deposit/transfer 同一 Int vault）；`usesVaultNative` 覆盖 env-read-only
  程序（ValidatePlan exact join：nonempty assetOps 或 vaultNative 表达式）；
  token 永久 FC（mint-keyed Map + Principal identity 超出 Q0 Int vault）；
  pureFn/initializer/invariant 禁 envRead。
- **Psy/Aleo/Noir/TON**：维持 ADR-0029 既有 disposition（Psy/Aleo 零绑定、
  Noir 永久 FC、TON owner 决策冻结）。

env-read 的非法使用（未声明 1.1.0、语句位置裸调 result-bearing QN、
invariant/pureFn 上下文、非 UInt64 结果）在各层 fail closed。门禁：
Anvil envread leg、Mollusk、cw-vm mock、near-sandbox 8 suites、
`proof-forge-next-tests` 全绿、`just dev-check`（含 docs-check）exit 0、
SBOM 239 files。**非** formal/mainnet parity；Anvil/Mollusk/cw-vm/near-sandbox
均为工程 local_runtime 门。

## 否决方案

- **transferFrom/allowance 抽象**：NEP-141 无 allowance（transfer_call 回调模型），
  强抽象则 NEAR 必假；V2 reserves 模式不需要它。后续若做借贷再单独立项。
- **flash swap / 动态回调**：callee 来自运行时输入 + 回调入口，打破 static-QN 与
  Reference 的 response-cursor 模型；非简单 lane 工作，需专门 ADR。
- **现在就发行 LP 真资产（mint/burn）**：EVM 内置记账 vs Solana create-mint+PDA
  authority vs CW20 instantiate vs NEP-141 独立部署——发行语义分歧大，defer 至
  custody/issuance v2（与 Aleo record custody v2 同一设计波）。
- **把 token transfer 留在 static-QN**：token 合约地址必须来自业务参数，static-QN
  无法表达；受控动态 callee（catalog 限定）是诚实的最小扩面。

## 验证

1. E1：每链 Plan/IR/emitter 钉测 + 产品纵切 + 对应 runtime 门（Anvil ERC-20 mock /
   Mollusk Token fixture / cw-vm CW20 mock / near-sandbox NEP-141）。
2. E2：payload digest 重 pin（docs-check 同构门）、旧 digest FC、env-read Reference
   钉测、per-target accept/FC 矩阵。
3. E4：MiniAMM 双链 runtime 门（成功/滑点失败/流动性回滚）。
4. 全波：Quint 模型层优先验证语义（若绑）；不声称 formal/mainnet。
