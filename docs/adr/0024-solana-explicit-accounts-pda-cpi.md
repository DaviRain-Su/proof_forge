---
id: ADR-0024
title: Solana 显式账户、PDA/bump 与真实同步 CPI v1 合同
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# ADR-0024：Solana 显式账户、PDA/bump 与真实同步 CPI v1 合同

## 状态

`proposed`。本文是 issue #114 的 decision-complete 冻结候选；在 owner 按
[`document-status.md`](../document-status.md) 记录批准前，不得写成 `accepted`，也不得据此开启产品
sync capability。#115 的 pinned-runtime harness 与 #116 的 exact extension/inert profile membership
都不能绕过本文的 artifact-mint/sync deny 状态。

## 背景与范围

当前两个 legacy Solana profiles（`solana-sbpf-plan-v1`、`solana-sbpf-elf-v1`）只有 index-0 state
account。#111 已删除其 sync/async capability，并使 Plan/IR/SBPF 对 call/schedule 纵深 fail closed；
#112 把 Mollusk 绑定到 manifest/evidence exact bytes；#113 在任何固定偏移读取前检查 exact single-account
shape，并补齐 V1 安全负例。

本合同只冻结下一条 opt-in 产品能力：

1. 多账户模型；
2. current-program PDA 与 canonical bump；
3. `invoke` / `invoke_signed` 的真实同步 CPI；
4. 通过 frozen API 调用 companion、System、classic SPL Token 与 classic ATA，而不是重写后三个官方程序。

它不承诺覆盖整个 Solana program 生态。dynamic/arbitrary CPI、optional/remaining accounts、账户 alias、
multisig、Token-2022、Metaplex、staking/oracle/compression、transaction builder、typed call returns 与
`schedule` 均继续 fail closed，须另立 versioned contract。

## 决策摘要

1. 新 profile ID 固定为 **`solana-sbpf-cpi-elf-v1`**；legacy profiles 永不静默升级。
2. 源码继续使用现有 `requires extension … version … digest …` 与 `call QualifiedId(args)`；extension ID
   固定为 **`solana.cpi.accounts`**，SemVer 为 **`1.0.0`**。
3. portable call 仍降低为 generic void `Op.ExternalCall(effectId, QualifiedName, args)`。AccountMeta、PDA、
   bump、program ID、outer roles 与 signer groups 只进入 Solana-owned Plan/IR。
4. account-bound value 只可来自 direct callable 的 bare public `Principal` 参数；其 wire value由对应
   account key 合成。普通 `Principal` 继续是 opaque portable identity，不建立全局 Pubkey 转换。
5. outer role keys 全部不同；单一 CPI site 的 meta keys 全部不同。同一 role 可跨不同 CPI sites 重用，
   但不同 roles 不可借跨-site 使用而 alias。
6. current-program signer PDA 只支持 frozen recipe；显式 `UInt8` bump 必须等于 pinned Agave 4.0.0
   **255..1** search 的首个 off-curve 结果。bump 0 即使可由 explicit create 产生，也不是本 profile 的
   canonical bump。
7. 所有 CPI 使用 `sol_invoke_signed_c`；unsigned invocation 传零 signer groups。inner failure 立即传播且
   不可 catch；successful CPI 后立即把 return data 清为空。
8. caller writes 与 successful CPI effects 在 VM 内按 Semantic source order 立即可见；只有 top-level
   success 才对外提交，任何 later failure 回滚此前所有账户变化。

## 1. 唯一 carrier 分工

| 关注点 | 唯一 carrier | 禁止承载的内容 |
|---|---|---|
| opt-in Plan/ABI 版本 | `CodegenProfileId = solana-sbpf-cpi-elf-v1` | per-program ValueId 或动态账户 |
| portable 同步 effect | S2 `effect.synchronous-call` + generic `Op.ExternalCall` | AccountMeta、PDA、program-id bytes |
| typed API 与账户绑定语义 | closed extension `solana.cpi.accounts@1.0.0` | TargetId 分支、任意 plugin callback |
| exact extension request | `extension.solana-cpi-accounts@1.0.0` requirement row | 第二套 requirements freeze authority |
| physical roles/metas/seeds | target-owned `SolanaCpiPlanV1` / `SolanaCpiIRV1` | shared Semantic account graph |
| callee implementation identity | selected exact callee-catalog digest | 网络 lookup、QName hash fallback |

`RequirementsV1` 仍是 ProgramRequirements 的唯一 freeze authority。extension row 不加入 S2 七键
`s2CatalogIdsWireOrderV1`，而作为 wire-owned exact row在同一个 `ProgramRequirementsV1` 中 canonical
merge。target lowering 只能消费已冻结 row，禁止重新遍历 source 或推导 requirements。

## 2. Frozen identity payloads

以下三个文件必须保持 canonical JCS（UTF-8、无 BOM、无尾随换行、object keys 按 UTF-8 升序；本合同
只使用 I-JSON scalar）：

| 文件 | raw SHA-256 | domain-separated digest |
|---|---|---|
| [`solana-cpi-extension-v1.json`](../specs/solana-cpi-extension-v1.json) | `13078a4c60ecf85b9bc66124809782641328e6d0d6268855bfa9e66a55b3622d` | `sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020` |
| [`solana-cpi-callee-catalog-v1.json`](../specs/solana-cpi-callee-catalog-v1.json) | `513c268853e59e5b274457ef95e7b4007f499897d4db50116d43a6be54da1ead` | `sha256:41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351` |
| [`solana-cpi-profile-v1.json`](../specs/solana-cpi-profile-v1.json) | `609d7604cffbaaffbfbe10304015cbaea3d90387674e9c92cad7d616e2b9b307` | `sha256:0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1` |

Digest 公式固定为：

```text
extensionDigest = SHA-256("pf.extension-semantics.v1" || NUL || extensionJcs)
catalogDigest   = SHA-256("pf.solana.callee-catalog.v1" || NUL || catalogJcs)
profileDigest   = SHA-256("pf.solana.cpi-profile.v1" || NUL || profileJcs)
```

source declaration 使用 extension domain digest。Profile payload绑定 catalog schema/version/runtime equality
rule；每次 BuildIdentity、Plan、evidence 与 output manifest 还必须绑定实际 selected catalog digest。当前
catalog 中四个 package 均 `admittedForMaterialization=false`，是 exact deny，不是待运行时自动补值。

`scripts/docs_check.py` 必须重算 canonical bytes、raw/domain digests、ADR 表与 profile/catalog cross-link；
任一不一致使 ordinary `just docs-check` 失败。后续 contract revision 必须原子更新 payload、ADR digest 与
checker 可观察关系。

## 3. Source、Typed、Semantic 与 requirement 合同

### 3.1 Extension declaration

```lean
requires extension solana.cpi.accounts version "1.0.0"
  digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"
```

规则：

- declaration 缺失、重复、unknown ID、wrong SemVer 或 wrong digest：fail closed；
- declaration 可无 call，但仍 mint exact extension row；任一 frozen API call 必须有该 declaration；
- 只有 extension JCS 中的 QN 可用；generic non-catalog `call` 与所有 `schedule` 继续拒绝；
- Source/Typed/Normalize 不 import TargetId 或 Solana target modules；
- extension row 的 `id/version/digest/predicates` 分别固定为
  `extension.solana-cpi-accounts`、`1.0.0`、extension domain digest、空数组；
- row 与 S2/ContextRead/Commit rows 共用 `(id, SemVer, digest)` canonical order，禁止 duplicate；
- requirement provenance origins 是 declaration node，加上每个 catalog call、callee 与 argument origin 的
  sorted-unique union；缺失任一 origin fail closed；
- generic call 仍独立贡献 `effect.synchronous-call` 与 rollback requirements，extension row不替代它们。

#116 已原子替换 `ContextExtensionCheckV1` 的 blanket deny：只承认上述 exact triple；unknown ID 返回
`PF-EXT-001`，known ID 的 wrong version/digest 返回 `PF-EXTENSION-VERSION`。Normalize 只从该
validated declaration mint row，Provenance 将 declaration node 绑定到 requirement entity；这不开放 call。

### 3.2 Account-bound Principal

当 API 参数 source 标为 `bare-direct-public-principal-parameter` 时：

1. expression 必须是当前 direct callable 的 bare parameter place；
2. parameter type 必须恰为 public `Principal`；
3. local、state、const、field/index、constructor、`context.caller` 与 computed expression 均拒绝；
4. 该参数不进入 instruction-data ABI；runtime value固定为 `u32le(32) || account_key[32]`；
5. Semantic 中仍是普通 Principal parameter/ValueId，eq/ne 仍比较 opaque wire bytes；
6. 未被 API account/seed slot 使用的 Principal parameter继续走既有 T12 ABI；
7. state/ordinary Principal 不可反向提取 pubkey，callee/program ID 也不可来自 Principal。

这是 extension-declared synthetic input precondition，不是全局 `Principal ↔ Pubkey` 同构。

## 4. Multi-account contract

### 4.1 Dense outer role construction

每个 direct handler 先静态构造唯一 role table：

1. 若 semantic logical state 非空，role 0 是 current-program-owned state；
2. 被任一 API account 或 seed slot引用的 account-bound Principal params，按 callable parameter declaration
   order，各建一个 role；
3. 按 Semantic callable/block/instruction source order扫描 CPI sites；每 site 先扫描 callee program，再按
   frozen meta order扫描 fixed program metas；同 package 复用其首次建立的 fixed role。

global role schema IDs 必须 dense `0..n-1`；每个 handler 的 local ABIv1 positions 另行 dense
`0..m-1` 且 `m≤16`。outer account 数量 exact 等于该 handler local role count；每个 role 都必须是
ABIv1 full marker `0xff`。extra、missing、duplicate marker、duplicate key、optional 与 remaining account
全部拒绝。每次 CPI 的 `SolAccountInfo[]` 固定为**该 handler 的全部 outer roles 按 local position order，
各一次**，其中 role ref仍是 global ID；禁止 emitter 按 global ID重排、自行过滤或去重。

### 4.2 Structural checks 与 site-local checks

在任何业务 op 前完成：exact count、full markers、checked virtual walk、trailing pointer table、role-key
pairwise distinct、fixed program key/executable/catalog binding、state owner/layout/init，以及 joined outer
signer/writable flags。

owner/data/init/PDA 等依赖某一 CPI 的 predicate 在该 CPI 前、基于当时账户状态再次检查。这允许 earlier
successful CPI 的修改被 later site观察，同时不会用 entry snapshot 覆盖 source-order semantics。任一
predicate failure 在调用 callee 前失败。

Extension JCS 对每个 meta/outer-only role冻结 exact constraint。主要 closed predicates 是：

- state：owner=current program、non-executable、exact generated layout；initializer 前为 uninitialized，其他
  handler 为 initialized；
- companion counter：owner=companion、non-executable、8-byte LE counter；
- System payer：System-owned、non-executable、zero data；create target：System-owned、zero lamports/data、
  canonical current-program PDA；
- classic Token source/destination：Token-owned 165-byte initialized non-frozen account、mint join；source 是
  single owner、无 delegate，owner join到 external authority 或 authority PDA；
- classic mint：Token-owned 82-byte initialized mint，TransferChecked 时 decimals join参数；
- ATA：canonical ATA key，且 pre-state 只能是 zero-lamport/zero-data System account或已存在、wallet/mint join
  正确的 classic Token account；
- fixed programs：exact package program ID、catalog execution class、executable=true、admitted binding；
- seed-only account：non-executable、data不读；signed APIs 的 `seedAuthority` 还必须是 outer signer。

### 4.3 Alias 与 privilege join

- 所有 outer roles pairwise distinct；每个 CPI site 的 ordered metas 也 pairwise distinct；
- 同一个 role 可在多个 sites 重用，跨-site 重用不是 alias；
- outer actual signer/writable 是该 role所有 uses 的 boolean OR，且输入 flags 必须 exact 等于结果；
- CPI signer/writable 是 per-site exact bits，不跨 sites union；outer writable role可在某 site de-escalate为
  readonly，outer signer也可在某 site作为 non-signer meta；
- CPI writable 必须有 outer writable；CPI signer 必须有 outer signer，唯一例外是 matched
  current-program signer group；
- PDA signer role的 outer signer固定 false。任何普通 role试图借 signer group、或 PDA role获得 outer signer
  都拒绝。

### 4.4 Product caps

| 项 | v1 cap | pinned runtime 上限/事实 |
|---|---:|---:|
| outer roles / CPI AccountInfos | 16 | CPI AccountInfos 255 |
| CPI metas | 16 | instruction metas 255 |
| CPI sites / handler | 32 | product cap |
| signer groups / CPI | 4 | runtime 16 |
| seed slices（含 bump） | 16 | runtime 16 |
| bytes / seed | 32 | runtime 32 |
| CPI instruction data | 1024 bytes | runtime 10 KiB |
| current-program PDA `space` | 4096 bytes | product cap |

超过 product cap 必须在 artifact mint 前拒绝；不得 fallback 到 runtime 的更大上限。

## 5. Closed API surface

Source-visible signatures：

```text
solana.companion.invoke(account: Principal, delta: UInt64) -> Unit
solana.companion.fail(account: Principal, delta: UInt64) -> Unit
solana.companion.invokeSigned(
  account: Principal, authorityPda: Principal, seedAuthority: Principal,
  seedTag: UInt64, bump: UInt8, delta: UInt64
) -> Unit
solana.system.transfer(payer: Principal, recipient: Principal, lamports: UInt64) -> Unit
solana.system.createPdaAccount(
  payer: Principal, pda: Principal, seedAuthority: Principal,
  seedTag: UInt64, bump: UInt8, lamports: UInt64, space: UInt64
) -> Unit
solana.token.transferChecked(
  source: Principal, mint: Principal, destination: Principal,
  authority: Principal, amount: UInt64, decimals: UInt8
) -> Unit
solana.token.transferCheckedPda(
  source: Principal, mint: Principal, destination: Principal,
  authorityPda: Principal, seedAuthority: Principal,
  seedTag: UInt64, bump: UInt8, amount: UInt64, decimals: UInt8
) -> Unit
solana.ata.createIdempotent(
  payer: Principal, ata: Principal, wallet: Principal, mint: Principal
) -> Unit
```

`seedTag` 只接受 UInt64 literal、const 或 bare public direct UInt64 parameter；`bump` 同理但为 UInt8。
`transferCheckedPda` 与 `companion.invokeSigned` 的 `seedAuthority` 必须 outer signer，形成 explicit business
authorization；不能仅因程序知道 PDA seeds 就授权转账。

### 5.1 Digest-bound instruction codecs 与 metas

以下内容同时完整存在于 extension JCS，ADR prose 不是第二 authority：

| API | exact CPI data | exact metas（顺序） |
|---|---|---|
| companion.invoke | `00 || delta:u64le` | account writable |
| companion.fail | `01 || delta:u64le` | account writable |
| companion.invokeSigned | `02 || delta:u64le` | account writable；authorityPda PDA-signer readonly |
| System.transfer | `02 00 00 00 || lamports:u64le` | payer writable+signer；recipient writable |
| System.createPdaAccount | `00 00 00 00 || lamports:u64le || space:u64le || currentProgramId[32]` | payer writable+signer；pda writable+PDA-signer |
| Token.transferChecked | `0c || amount:u64le || decimals:u8` | source writable；mint readonly；destination writable；authority signer |
| Token.transferCheckedPda | same Token bytes | source writable；mint readonly；destination writable；authorityPda PDA-signer |
| ATA.createIdempotent | `01` | payer writable+signer；ATA writable；wallet readonly；mint readonly；System readonly；classic Token readonly |

每个 site 另有 outer-only callee program role；ATA 的 System/Token 是 CPI metas，不可只作为 hidden fixed roles。
System encodings固定 pinned `SystemInstruction` bincode discriminants；Token tag 12来自
`solana-program/token program@v9.0.0`；ATA byte 1及六 metas来自
`solana-program/associated-token-account program@v8.0.0`。

## 6. PDA、bump 与 signer groups

### 6.1 Platform derivation

```text
SHA-256(seed0 || ... || seedN || programId[32] || "ProgramDerivedAddress")
```

marker exact hex为 `50726f6772616d4465726976656441646472657373`，结果必须 off Ed25519 curve。
Pinned `agave-syscalls 4.0.0` 的 `sol_try_find_program_address` 从 255 开始执行 255 次，候选恰为
`255,254,...,1`：

- canonical v1 bump 集合是 255..1；
- bump 0 不属于 canonical search；
- explicit bump 0 即使 `create_program_address` 可得 off-curve 地址，本 profile仍拒绝；
- runtime 若未来改变 search，必须新 profile/extension digest。

### 6.2 `current-program-tagged-v1`

```text
seed[0] = hex 70726f6f662d666f7267653a7064613a7631  // "proof-forge:pda:v1"
seed[1] = seedAuthority account key, 32 bytes
seed[2] = seedTag UInt64 little-endian, 8 bytes
seed[3] = bump UInt8, 1 byte
programId = current ProofForge Solana program ID
```

先独立求 canonical `(expectedKey, expectedBump)`，再同时验证 passed key与 supplied bump。signer seed slices
必须 byte-for-byte 重建上述四片。

Signer group IDs 在每个 CPI site 内按首次 signer meta顺序 dense `0..n-1`；一个 group只绑定一个 distinct
meta，一个 meta至多绑定一个 group，unused/duplicate group均拒绝。每个 `cpiSigner=true` 且
`outerSigner=false` 的 meta必须恰有一个 matched current-program group。

### 6.3 `ata-classic-v1`

```text
seed[0] = wallet account key
seed[1] = classic Token program ID
seed[2] = mint account key
programId = classic ATA program ID
```

只用于比较 ATA key；它不是 current-program signer group。

## 7. Pinned runtime 与 ABIv1 input

当前工程 oracle固定：

| component | version | Cargo.lock checksum / commit |
|---|---|---|
| `mollusk-svm` | 0.13.4 | `fad83a73c151ce703f9dbccf0500e654fc017f4b2467d35bbb3e528c971f7911` |
| `agave-syscalls` | 4.0.0 | `84debd4abe0cbab5a6aac2ee50e3969ef0e0961f7dff7e8f96bda0be7998bca2` |
| `solana-program-runtime` | 4.0.0 | `f6c7f89c89d5ff25f64a41c8cb00478b1d62f941f14a7dd8537c9e50bb2acc92` |
| `solana-transaction-context` | 4.0.0 | `ecefe8b30e334e2891ca82da35becd9a3f4c16021d9ca782e2a82adf31084fa3` |
| `solana-sbpf` | 0.14.4 | `733b3657a0fab205102b799dbe17f85d3972cf984232c1b0b108fa6ba438e382` |
| Agave source tag | v4.0.0 | `2a165e7a90af75c76426d1e031ed0284211d5d1e` |

Mollusk使用 `SVMFeatureSet::all_enabled()`、Loader V3、ABIv1，并固定
`virtual_address_space_adjustments=true`、`account_data_direct_mapping=true`、
`direct_account_pointers_in_program_input=true`。

### 7.1 Exact virtual layout

```text
u64 num_accounts
for each full role:
  u8  0xff
  u8  is_signer
  u8  is_writable
  u8  executable
  u32 original_data_len = 0
  key[32]
  owner[32]
  u64 lamports
  u64 data_len
  data[data_len]                    // direct-mapped region
  virtual reserve to data_len+10240
  align virtual cursor to 8
  u64 rent_epoch = UInt64.max
u64 instruction_data_len
instruction_data
current_program_id[32]
zero padding to 8
u64 account_marker_vm_address[num_accounts]
```

full prefix是 88 bytes；key/owner/lamports/data_len offsets 分别是 8/40/72/80，data virtual address为
marker+88。direct-mapping 时 10240-byte growth span不是普通 contiguous backing bytes；parser必须以 checked
SBPF virtual address cursor跳过它，不能按 host buffer连续加 pitch。尾部 SIMD-0449 table每 role 一项，必须
exact 指向该 role marker。任一 overflow、OOR、nonzero padding、wrong pointer、wrong `original_data_len`、
wrong rent epoch、short/trailing输入均拒绝。

本 profile拒绝 duplicate records，因此每个 marker均为 `0xff`；仍必须在读取 full fields前验证 marker。

## 8. `sol_invoke_signed_c` ABI、return data 与 rollback

custom assembly只构造 C ABI，不依赖 Rust `AccountInfo`/`StableInstruction` layout：

| struct | size/alignment | fields |
|---|---|---|
| `SolInstruction` | 40/8 | `program_id_addr@0, accounts_addr@8, accounts_len@16, data_addr@24, data_len@32` |
| `SolAccountMeta` | 16/8 | `pubkey_addr@0, is_writable@8, is_signer@9, zero-pad[6]` |
| `SolAccountInfo` | 56/8 | `key@0, lamports@8, data_len@16, data@24, owner@32, rent_epoch@40, signer@48, writable@49, executable@50, zero-pad[5]` |
| `SolSignerSeed` | 16/8 | `addr@0, len@8` |
| `SolSignerSeeds` | 16/8 | `addr@0, len@8` |

scratch structs/arrays必须位于 input region之外，所有 pointer fields使用经 §7.1 验证的 SBPF virtual
addresses；bool bytes只能 0/1，padding必须清零。`SolInstruction.accounts` 保留 frozen meta order；
`SolAccountInfo[]` 保留完整 outer role order。禁止 emitter猜测、去重或使用 QName hash program ID。

每次调用：

1. pinned runtime在 callee entry 前清除 stale return data；
2. syscall返回非零或抛出 runtime fault时立即使 outer instruction失败，不执行 clear或任何 later generated op；
3. syscall成功后，generated code立即调用 zero-length `sol_set_return_data`；clear fault同样传播；
4. successful top-level outcome的 return data必须为空；caller此前设置的 return data被有意销毁；
5. caller account writes 与 successful CPI updates立刻同步，later op可观察；top-level failure由 runtime回滚所有
   账户变化。日志、compute consumption等非账户观察不被误写成“回滚”。

## 9. Callee catalog

### 9.1 Fixed program IDs

| package | base58 presentation | raw 32-byte hex |
|---|---|---|
| companion-v1 | `5XZobBCgcyuBM4m1E1rZVei7Me6V8FzwSLexuU194KcN` | `4343434343434343434343434343434343434343434343434343434343434343` |
| System | `11111111111111111111111111111111` | `0000000000000000000000000000000000000000000000000000000000000000` |
| classic Token | `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA` | `06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9` |
| classic ATA | `ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL` | `8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859` |

Base58仅展示；Plan/IR/catalog authority是 raw bytes。

### 9.2 Interface pins and activation

| package | exact interface/source pin | current artifact state |
|---|---|---|
| companion-v1 | extension digest + three-op closed interface + fixed ID | `absent`，不可 materialize |
| System | `solana-system-interface 3.1.0` checksum + Agave v4.0.0 native runtime | runtime-native identity存在，但 profile仍 inert |
| classic Token | `solana-program/token program@v9.0.0`，annotated tag object `5c37ac99c248567bd7d50b965af8cbd45b6ced96` → peeled source commit `dfb260231c761be7d9c8b63728e770a102b86495`，interface 2.0.0 | `absent`，不可 materialize |
| classic ATA | `solana-program/associated-token-account program@v8.0.0`，annotated tag object `de77f367fdc0341879b1b9f0224c6b86107e1769` → peeled source commit `0b867b5340cd001e5980d8ca7928effc4e10015c`，interface 2.0.0 | `absent`，不可 materialize |

`absent` 是 closed fail state。Token/ATA/companion只有在 catalog新 instance提供 package-owned或 locked
reproducible exact ELF bytes、SHA-256、source/build identity与 runtime registration ID match后才能
`admitted=true`。若采用 cluster snapshot，还必须绑定 ProgramData address、slot、提取过程与 byte digest；
mutable mainnet dump永不成为隐式 authority。System是 runtime-native package，不伪造 ELF hash。

Token v1只开放 single-owner/no-delegate `TransferChecked`；multisig、mint/burn/close 与 Token-2022拒绝。
ATA只开放 `CreateIdempotent`，且 classic Token ID同时是 seed和第六个 meta。

## 10. Solana Plan / IR contract

新 Plan必须保留关联类型，至少含：

```text
SolanaCpiPlanV1 {
  schema = "proof-forge.solana.cpi-plan.v1",
  profileDigest,
  extensionRequirement,
  calleeCatalogDigest,
  accountSchemas[],
  pdaRules[],
  handlers[],
  cpiSites[],
  computeAssumptions
}
```

每个 `CpiSite` 绑定 Semantic callable/block/instruction/effectId、callee QN、package ref、instruction codec、
ordered metas、full ordered AccountInfo refs、dense signer groups、site predicates、return-data policy与 failure
policy。所有 arrays 使用 canonical source/Plan order；unknown/extra field、wrong digest、non-dense ID、same
effectId duplicate、unused role、role OOR、privilege conflict、predicate mismatch与 package not admitted均拒绝。

Plan/IR/IDL identities：

- `proof-forge.solana.cpi-plan.v1` / domain `pf.solana.cpi-plan.v1`；
- `proof-forge.solana.cpi-ir.v1` / domain `pf.solana.cpi-ir.v1`；
- `proof-forge.solana.cpi-idl.v1`。

所有 behaviorally relevant field必须进入 Plan canonical bytes/digest；assembler text、IDL或 runtime harness不能
成为隐藏的第二账户 authority。

## 11. Fail-closed and deletion gates

实现必须静态/反射禁止：

- Source/Typed/Semantic/Normalize import `TargetId` 或 Solana target modules；
- generic Semantic增加 AccountMeta/PDA/program-id variant；
- QName→SHA-256 program ID或 dynamic program address；
- Principal state/ordinary param→pubkey reinterpretation；
- legacy `externalCall`/`schedule` Plan node恢复可达；
- legacy profiles接纳 extension或 sync/async requirements；
- unknown catalog QN、remaining/optional account、role/meta alias；
- malformed direct-mapping ABI被按 contiguous buffer读取；
- Rust AccountInfo layout替代 frozen C ABI；
- package `artifactBinding=absent` 或 `admitted=false` 时生成 output；
- CPI failure后继续执行，或 top-level failure后保留任何账户变化；
- #125 composite gate前在 resolver advertise sync support。

## 12. Required tests

### #115 feasibility exit

- exact multi-account ABIv1 virtual walk：0/1/16/17、short/truncated/overflow、full/duplicate marker、wrong
  original-data-len/rent/padding/pointer-table；
- caller + companion从 manifest-bound bytes双程序注册；
- real `invoke` success/failure和 `invokeSigned` success/failure；
- missing/wrong program account、wrong executable/key/order、signer/writable escalation；
- all-outer-role `SolAccountInfo[]` 与 frozen C struct offsets；
- stale return-data-at-entry、success clear、failure no-clear；
- full present/absent/lamports/data/owner/executable/rent_epoch rollback snapshot；
- SDK-independent `current-program-tagged-v1` golden，wrong/reordered/oversized seeds；
- canonical bump boundary 255/1与 bump 0 rejection；
- signer只授予 exact PDA group，seedAuthority business signer缺失时拒绝；
- product caps one-below/equal/one-above。

#### #115 engineering observation（2026-08-03）

上述 feasibility exit 已由 harness-only 双程序闭合，但**不改变产品 capability**：

- locked `sbpf 0.2.2` 产出 `companion.so` 1776 bytes / SHA-256
  `c8738f1220c49c309ffe820ca397ae25540d6be29c6153934abd8548fa08c4b9` 与 `caller.so`
  4968 bytes / SHA-256 `b00a7ba33248b73eb59f26824c65b099ea124a3ba8401aae63d5a02479f5c7e4`；
- `runtime-tests/solana/tests/abi_v1_layout.rs` 以独立 program-visible virtual image decoder覆盖
  0/1/16/17、truncation/overflow、full/duplicate marker、bool、original-data-len、rent、padding、pointer、
  trailing、真实 `repr(C)` size/offset 与 cap validator；真实 caller ELF另执行 pinned Loader 生成输入上的
  0/1/16/17 与 duplicate marker。malformed short/overflow/trailing 属独立 decoder 证据，**不**声称 caller ELF
  从裸 pointer 获得可信 input-end；后续 #118 已实现其可证明的 checked-walk/fail-closed preflight边界，
  但仍不发明可信 input-end或产品 artifact；
- SDK-independent SHA-256 + Ed25519 decompression oracle固定 PDA golden，再与 Solana SDK作第二 oracle；
- pinned Mollusk 双程序真实执行 unsigned/signed CPI success/callee-failure、canonical PDA preflight、matching
  noncanonical PDA+bump rejection、bump 0、business signer、PDA outer-signer、wrong key/order/executable、
  privilege escalation、stale/success/failure return-data与 exact account snapshot rollback；
- 7 ABI + 5 PDA + 25 CPI 聚焦测试全 active；构建脚本与测试进程均绑定 committed manifest，不接受仅替换
  自洽 sidecars；临时 deploy tree在退出时删除。

这只是 pinned-runtime engineering feasibility。#116 随后注册了 `solana-sbpf-cpi-elf-v1` membership
并接通 exact extension row，但 resolver仍不 advertise sync/async，capability→Plan 与 generic product build
在任何 OutputFile/输出目录前 fail closed；#117–#124 为 engineering test-preactivation；#125 与 formal D5/TST-SOL 状态不变。

#### #116 inert membership observation（2026-08-03）

- exact `solana.cpi.accounts@1.0.0` + frozen digest 通过 ContextExtension Check；unknown ID 与 wrong
  version/digest 分别稳定为 `PF-EXT-001` / `PF-EXTENSION-VERSION`；
- Normalize 在无 call 时也 canonical merge 单一 `extension.solana-cpi-accounts@1.0.0` row，且
  SemanticProvenance 的 requirement origin 精确落在 `ExtensionReq` declaration node；
- registry 的 Solana profiles 固定 ASCII 顺序 `cpi-elf < elf < plan`，default仍为 plan；support index为
  9 行，仅 CPI profile含 exact extension row，三个 Solana rows均不含 sync/async；
- `planFromCapability` / `irFromCapability` / `buildFromCapability` / aggregate materialize 与 CLI build
  对 CPI profile 均在 legacy Plan生成前返回 `PF-PLAN-INVARIANT`，CLI不创建输出目录；legacy plan/elf
  行为与制品保持不变。

该 observation 只证明可观察的 inert contract surface，不是 CPI Plan/IR、invoke、PDA product lowering，
也不提高 target maturity。

#### #117 structural Plan/IR/IDL observation（2026-08-03）

- `CpiContractV1` 投影 exact 32-byte pubkey、四 package/八 static APIs、两 PDA rules 与 closed account/
  privilege/alias policy；base58 仅 presentation，portable Principal identity不变。
- `CpiPlanV1` 将 global role schema 与 per-handler local uses分离，精确验证 dense/source order、
  handler-local AccountInfo全量顺序、site predicates、privilege join、caps与 package admission；只有
  private-constructor structural carrier持有 PF-JCS canonical bytes与 Plan digest。
- `CpiIRV1` 精确保留 Plan/profile/catalog identity、state schemas、PDA rules、compute assumptions、
  role key/constraint/alias/direct+effective privilege、Plan-owned AccountInfo role sequence、preflight-first
  operations，以及 extension中 Loader V3 direct-map/pointer-table与五个 C layout的 exact fields。
  `CpiIdlV1` 是同一 Plan的 inspect-only projection，包含 state、account privilege provenance、codec、
  metas、outer-only、PDA和site policy；两者均无 emitter、平台调用 surface或 `OutputFile` mint。
- 全八 API、mutation/phase order、IR digest recompute与 IDL projection 已注册 ordinary tests；legacy
  Counter Plan digest与 `.sbpf-plan`/`.idl.json` exact bytes保持 pre-#117 pins。IDL仅有 canonical
  inspect bytes，不另 mint domain digest；其内容由 retained Plan digest与 exact projection验证。
- extension 中 `all-outer-roles-in-dense-role-id-order` 在 global-schema/per-handler-use 模型下精确定义为
  **handler-local dense ABIv1 position order**；`accountInfoRoleIds` 是该顺序中的 global role references，
  不按 global numeric roleId重新排序。后续 #118 parser/emitter已直接消费该 Plan顺序。
- **Authority boundary**：本 #117 切片只做 caller DTO 的 exact structural validation，不把其中的
  Semantic anchor/ValueId声明为 retained-program事实。后续 #118 已由 exact resolved CPI capability与
  retained `SemanticProgramV1` sole-derive并逐 anchor/value/type join；任意 structural carrier仍不能授权
  emitter或 materialization，product profile仍在 legacy Plan前 fail closed。

#### #118 Semantic-bound multi-account preflight observation（2026-08-03）

- `ResolvedSolanaCpiPreflightV1` 只接受 exact CPI profile、exact extension row 与 deferred sync requirement；
  ordinary product resolver仍拒绝 sync。其 private carrier保留 selection + `CompiledSemanticV1` 并固定
  `activationDenied=true`。
- `deriveSolanaCpiPlanFromPreflightV1` 是 retained Semantic→CPI Plan 的 sole authority：逐
  `ExternalCall` join callable/block/instruction/effectId、ValueId、参数类型与 frozen QN API；每个 direct
  init/entry/view handler均进入 Plan，无 CPI 的 view也保留。nonempty state复用 legacy Solana
  `StateAccount` 的同一 layout SHA-256 前像，marker等于 digest前 8-byte BE，不建立第二 layout authority。
  Account-bound Principal只形成静态 `(callable,paramOrdinal,roleId,localIndex)` binding；runtime wire值由
  物理 role key合成，不伪造第二份 Principal bytes 比较。
- `ResolvedSolanaCpiPreflightIRV1` 的 private mint只消费上述 authority carrier；structural inspection Plan/IR
  不能喂给 emitter。IR把 Loader V3/native loader owner、exact key/owner/data/lamports/state header、
  signer/writable/executable、pairwise distinct与 handler-local role count具体化为闭合 op。PDA、signer
  groups、System create provisioning、classic Token/ATA data predicates与 `schedule` 在此阶段精确 fail
  closed，分别留给 #120–#123。
- `EmitCpiPreflightSbpfV1` 只生成 1088-byte frame 的 ABIv1 role-table walker与 preflight checks；所有 cursor
  add先做 u64 wrap guard并保留 alignment/padding live registers。测试 probe只接受 exact 8-byte LE
  handlerId，且无 `sol_invoke*`、PDA或业务写。构建门另以同一锁定 `sbpf 0.2.2 disassemble` 解码最终
  ELF并要求零 `call` 指令，而非只扫描源汇编。返回 carrier明确
  `isProductArtifact=false`/`isTestPreactivation=true`，没有 `OutputFile` mint。
- `AccountRoles.lean` 经真实 Loader→compile→preflight→Plan→IR→emitter生成 36,416-byte assembly
  （SHA-256 `d3c8d34885b1c8cec9372bc501b1b1332ec261618c3c588f83aa0dca79e9e11a`），locked
  `sbpf 0.2.2` 产出 14,640-byte ELF（SHA-256
  `3388c71cc28a63b6c563e5d9a83af59709ee7b47191d7489f6be819f15b87066`）。committed strict manifest同时
  绑定 source/profile/extension/boundary/text/ELF；Mollusk覆盖 init/route/view正向、0/16/17 walker、exact-8
  dispatch，以及 33 个 single-mutation role/key/owner/data/header/privilege/order/count negatives（全部相邻
  swap及 leading/middle/trailing missing/extra），每例 `Custom(1)` 且完整 exact account snapshot不变。
  独立 raw-image decoder覆盖普通 `AccountMeta` API不能构造的 marker/bool/original-data-len/rent/padding/
  pointer-table/trailing/truncation/overflow；不把模型负例冒充真实 VM raw-input 注入。
- 该 ELF 的准确称谓是 **production-code-generated test-preactivation ELF**。它不是
  `proof-forge.output.v1`、不是产品 artifact，也不调用任何 callee。#119 unsigned invoke、#120 PDA/bump/
  `invoke_signed` 与 #121–#124 forcing gates 已在 test-preactivation lane 闭合；#125 前 resolver support 和产品 artifact mint 继续关闭。

#### #119 unsigned companion CPI observation（2026-08-04）

- 在仍为 `activationDenied`/test-preactivation 的 opt-in `solana-sbpf-cpi-elf-v1` lane 中，
  新增独立 authority-bound 模块 `CpiUnsignedIRV1` + `EmitCpiUnsignedSbpfV1`；**不**原地把
  #118 preflight emitter 改成 invoke。唯一 emitter authority 来自
  `ResolvedSolanaCpiPreflightIRV1` → `ResolvedSolanaCpiUnsignedIRV1` 的 retained Semantic
  private chain；public structural Plan/IR 仍不能授权发射。
- 首切片只支持 `solana.companion.invoke` / `.fail`；System、PDA/nonempty signer groups、
  Token、ATA、schedule、dynamic CPI 与 typed returns 继续 fail closed。CFG gate 要求
  single-block straight-line callable。数字 CPI arg 只接受 direct public UInt64 param 或
  canonical UInt64 literal；Principal 为 direct public Principal param→handler-local role
  key，并从 probe instruction data 省略。
- 执行 IR 在同一 ordered body 中至少支持 narrow public UInt64
  `param/literal/stateLoad/checkedAdd/stateStore/externalCall/returnU64|returnNone`，以证明
  caller state write → CPI → post-call op 的 source order。site predicates 在每个 invoke 前
  以 `siteChecks` 立即执行（不永久 hoist）。失败时原样 exit syscall status，不 clear、不执行
  后续 op；成功后 `sol_set_return_data(0,0)` 再继续。`sol_invoke_signed_c` 零 signer ABI 精确
  为 r1 SolInstruction*、r2 full handler-local `SolAccountInfo[]`、r3 localRoleCount、r4=0、r5=0。
- `CompanionCpi.lean` 经真实链生成 assembly/ELF；committed
  `runtime-tests/solana/unsigned/manifest.json` 绑定 source/profile/extension/boundary、
  #115 companion program ID 与 harness companion ELF pin。locked `sbpf 0.2.2` disassemble
  证明 final ELF 含 exact `sol_invoke_signed_c`/`sol_set_return_data` 且无 `0xec01` stub。
  Mollusk 双程序覆盖 success 单次 companion 修改 + caller pre/post state commit、
  companion.fail 全量 snapshot rollback 且保留 `fail:v1!`、以及 missing writable / unexpected
  signer / program substitution / permutation / alias / high-byte delta 等 negatives。
- 准确称谓是 **production-code-generated test-preactivation unsigned-CPI ELF**。不是
  `OutputFile` / `proof-forge.output.v1`，ordinary resolver 仍拒 sync，#120+ 与 formal D5 仍 pending。

#### #122 classic Token CPI engineering observation（2026-08-04）

- 在仍为 `activationDenied`/test-preactivation 的 opt-in `solana-sbpf-cpi-elf-v1` lane 中，
  新增独立 private authority-bound 模块 `CpiTokenIRV1` + `EmitCpiTokenSbpfV1`；**不**原地把
  #118–#121 emitter 改成 Token 面。唯一 emitter authority 来自 retained Semantic → private
  preflight/token IR 链；public structural Plan/IR 仍不能授权发射。
- 首切片只冻结 `solana.token.transferChecked` / `.transferCheckedPda`（tag 12、data
  `0c||amount:u64le||decimals:u8`=10B）；Token Account **165** / Mint **82** exact site-time
  predicates（owner/initialized/non-frozen/mint join/decimals join 等）在 invoke 前执行。
  真实 LoaderV3 `sol_invoke_signed_c`：unsigned 零 signer groups；PDA 路径复用 canonical
  `current-program-tagged-v1` + `sol_try_find_program_address` 单 signer group。multisig、
  mint/burn/close、Token-2022、ATA、schedule、dynamic CPI 与 typed returns 继续 fail closed。
- classic Token callee 为 vendored **source-built** official
  `solana-program/token program@v9.0.0` ELF（**94960** bytes，SHA-256
  `a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9`）；annotated tag object
  `5c37ac99c248567bd7d50b965af8cbd45b6ced96` → peeled commit
  `dfb260231c761be7d9c8b63728e770a102b86495`；same-host clean **repeat=2**，recipe digest
  `4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063`。catalog
  `token-classic-v1` digest corrected 为
  `0da1837ec10f7acc716c1151bee23a04e019174f99b1fedde635c7d75b4055f5`，但
  **`artifactBinding=absent` / `admittedForMaterialization=false` 保持不变**——vendored ELF 只服务
  test-preactivation，不是 package-owner-published / tracked Tool Lock / product materialize
  authority。
- caller 经真实 production Token authority/emitter + locked `sbpf 0.2.2`：assembly **160129**
  SHA-256 `3cf744e36b5a91a441dbb06a33050613fcc366b57a03ad2b970f78cbe131e9fd`、ELF **67608**
  SHA-256 `4c7a10cc7dc5e411a9eec3109722e2080a48ac7a64868c34d4a60f7a813464c7`。committed
  `runtime-tests/solana/token/manifest.json` 绑定 source/profile/extension/boundary/token
  ELF/caller pins。Mollusk focused **31/31**（success balance delta、PDA canonical bump、
  then-overflow full snapshot rollback、inner Token failure、Account/Mint/privilege/alias/role
  /Token-2022 负例等）。full `just solana-runtime` 现为 **11 binaries / 221 active**。
- 准确称谓是 **production-code-generated test-preactivation classic-Token CPI ELF**。不是
  `OutputFile` / `proof-forge.output.v1` / activated sync；**不是** mainnet parity、tracked Tool
  Lock、cross-host、hermetic、formal、release 或 package-owner-published。ordinary resolver 与
  legacy profiles 仍 fail closed；#123/#124 见下；#125 前不 advertise/mint。
  可声称门：`just docs-check`、SBOM refresh/check **187**、`just test-targets`（clean
  repo-local exact tool root）、`just solana-runtime`、focused、`just dev-check`、ordinary
  `just ci` 全 exit 0；独立审计无 P0/P1。

#### #123 classic ATA CPI engineering observation（2026-08-04）

- 在仍为 `activationDenied`/test-preactivation 的 opt-in `solana-sbpf-cpi-elf-v1` lane 中，
  新增独立 private authority-bound 模块 `CpiAtaIRV1` + `EmitCpiAtaSbpfV1`；**不**原地把
  #118–#122 emitter 改成 ATA 面。唯一 emitter authority 来自 retained Semantic → private
  preflight/ATA IR 链；public structural Plan/IR 仍不能授权发射。
- 首切片只冻结 `solana.ata.createIdempotent`（data byte exact `01`；六 ordered metas：
  payer writable+signer、ATA writable、wallet/mint/native System/classic Token readonly；
  零 caller signer groups）。真实 LoaderV3 `sol_invoke_signed_c`；ATA callee 自行嵌套
  System/Token signed CPI。canonical ATA address check：seeds
  `wallet || classic Token program id || mint` under classic ATA program，经
  `sol_try_find_program_address` 与 supplied ATA role key 全 32B 相等；返回 bump **不是**
  caller signer group。atomic closed prestate：ATA 账户必须是 **fresh**
  zero-lamport/zero-data System-owned **或 existing** classic Token-owned 165B
  initialized（exact mint+wallet joins）。Token-2022、dynamic CPI、schedule、multisig 与
  typed returns 继续 fail closed。
- classic ATA callee 为 vendored **source-built** official
  `solana-program/associated-token-account program@v8.0.0` ELF（**111136** bytes，SHA-256
  `d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519`）；annotated tag object
  `de77f367fdc0341879b1b9f0224c6b86107e1769` → peeled commit
  `0b867b5340cd001e5980d8ca7928effc4e10015c`；same-host clean **repeat=2**，recipe digest
  `f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2`。依赖 classic Token
  vendored ELF pin 不变。callee catalog raw SHA-256
  `513c268853e59e5b274457ef95e7b4007f499897d4db50116d43a6be54da1ead` / domain digest
  `sha256:41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351`（相对 #122 的
  `0da183…` 因 ATA interface 补齐 tagObject/peeled commit 字段而更新），但
  **`artifactBinding=absent` / `admittedForMaterialization=false` 保持不变**——vendored ELF
  只服务 test-preactivation，不是 package-owner-published / tracked Tool Lock / product
  materialize authority。
- caller 经真实 production ATA authority/emitter + locked `sbpf 0.2.2`：assembly **108322**
  SHA-256 `80ea42196a9a37a13012d4bcc720b50d97d6167e42dde88da501ef928d6364b9`、ELF **46872**
  SHA-256 `9902eb1e8a251b3352a08b4469e32003d7f82b980bc0f33b8557f0cf37d13e37`。committed
  `runtime-tests/solana/ata/manifest.json` 绑定 source/profile/extension/boundary/ATA+Token
  ELF/caller pins 与 forcing 矩阵。final ELF call surface 仅
  `sol_try_find_program_address` / `sol_invoke_signed_c` / `sol_set_return_data`。
- Mollusk focused **25/25** active：fresh exact **2,039,280** rent+layout、full-result
  replay/payer unchanged、real Token TransferChecked usability、underfunded native System
  exact log+Custom(1)+empty return+full snapshot、post-CPI overflow ordered logs+full
  rollback、独立 SHA256+curve oracle、完整 single-mutation matrix（见 committed
  `runtime-tests/solana/tests/cpi_ata.rs` 与 manifest `forcingMatrix`）。
- full `just solana-runtime` exit 0：**12** integration binaries / **246** active tests，
  `cpi_ata` 25/25（Mollusk **不属于** ordinary `just ci`，为单独运行）。strict ATA build
  manifest 现在逐值绑定 provenance，并有 **4** mutation self-tests。
- 已通过 `just docs-check`、SBOM refresh/check **189**、focused Lean/Rust、
  `just test-targets`（clean repo-local exact tool root）、`just dev-check`、ordinary
  `just ci` 全 exit 0；两轮独立审计最终无 P0/P1。
- 准确称谓是 **production-code-generated test-preactivation classic-ATA CPI ELF**。不是
  `OutputFile` / `proof-forge.output.v1` / activated sync；**不是** mainnet parity、tracked
  Tool Lock、cross-host、hermetic、formal、release 或 package-owner-published。ordinary
  resolver 与 legacy profiles 仍 fail closed；**#123 工程切片已闭合**；**#111–#123 closed**（历史 Active
  曾为 #124；见下 #124 闭合）。catalog domain 当前 requalification 为
  `41ace268…`（#122 历史 `0da183…` 保留为当时事实）。

#### #124 composite escrow CPI engineering observation（2026-08-04）

- 在仍为 `activationDenied`/test-preactivation 的 opt-in `solana-sbpf-cpi-elf-v1` lane 中，
  新增独立 private authority-bound 模块 `CpiEscrowIRV1` + `EmitCpiEscrowSbpfV1`；**不**原地
  把 #118–#123 emitter 改成 composite escrow 面。唯一 emitter authority 来自 retained
  Semantic → private preflight/escrow IR 链；public structural Plan/IR 仍不能授权发射。
- composite forcing golden 发射真实 **System → ATA → Token** CPI 序：native System
  createPdaAccount、classic ATA `createIdempotent`、classic Token
  `transferChecked`/`transferCheckedPda`；真实 `sol_try_find_program_address` +
  `sol_invoke_signed_c` + 成功路径 `sol_set_return_data`。canonical PDA/ATA 与
  #120–#123 既有 recipe/prestate 约束复用；Token-2022/dynamic/remaining/multisig 继续
  fail closed。
- final fixture `runtime-tests/solana/fixtures/EscrowCpi.lean`：**5378** bytes，SHA-256
  `0424045e7cdc7e3c57b79d95c144e6047819db91b46c39607e42bf256b7c33bf`。caller assembly
  **366006** SHA-256 `577f40646abb0a355bedebb76dd6b208ff39ae802bea1dab21ce4795ba5d102b`、
  caller ELF **158536** SHA-256
  `28744d799b9a58208a54066d730a97a45e4363ae4f407132cf49c0bc7782b5f9`。final ELF **37**
  calls 仅 `sol_try_find_program_address` / `sol_invoke_signed_c` /
  `sol_set_return_data`。frame budget：**maxScratch 793 → reserve 800 → CPI_BASE 2024
  → 2824** bytes。
- Mollusk focused **36/36** active（success initialize/deposit/release/refund 序、
  post-CPI overflow ordered logs+full snapshot rollback、inner System/Token failure
  full snapshot、one-mutation matrix、independent PDA/ATA oracles；见
  `runtime-tests/solana/tests/cpi_escrow.rs` 与 `escrow/manifest.json` `forcingMatrix`）。
- full `just solana-runtime` exit 0：**13** integration binaries / **282** active tests，
  `cpi_escrow` 36/36（Mollusk **不属于** ordinary `just ci`，为单独运行）。SBOM package-file
  pin 当前 **191** files。
- **sequential world overlay**：同 world 内 source-order CPI 状态叠加与 failure full
  snapshot rollback；**不是** 多顶层 transaction atomicity。
- ATA/Token catalog **`artifactBinding=absent` / `admittedForMaterialization=false`
  保持不变**。准确称谓是 **production-code-generated test-preactivation composite-escrow
  CPI ELF**。不是 `OutputFile` / `proof-forge.output.v1` / activated sync；**不是**
  mainnet parity、tracked Tool Lock、cross-host、hermetic、formal、release 或
  package-owner-published。ordinary resolver 与 legacy profiles 仍 fail closed；
  **#124 工程切片已闭合**；**#111–#124 closed**；**Active #125** activation；#125 前不
  advertise/mint。formal 状态与 GitHub issue 状态不因本工程收口而改变。


### Schema mutation obligations

profile/extension/catalog/Plan每个 behavior field至少有一个 one-field mutation改变 digest，并在最早正确边界
失败。特别覆盖 role order、alias、owner/data/init、outer/CPI signer/writable、program ID、seed bytes/order、
bump policy、signer-group ID/scope、package source/artifact、codec bytes、ATA第 5/6 metas、return-data、
source-order visibility与 rollback policy。

## 13. Consequences and sequencing

1. #115 可在 harness-only code验证 ABI，不注册产品 profile。
2. #116 接入 exact extension/requirement/provenance 与 profile membership，但 profile仍不可 mint artifact，
   resolver仍不 advertise sync。
3. #117–#120 实现 target Plan/IR、multi-account parser、invoke与 PDA/invoke_signed。
4. #121–#123 按 package生成新的 exact catalog instance；缺 artifact/admission的 package继续拒绝。
5. #124 escrow forcing golden 已工程闭合（test-preactivation）；#125 才增加新 profile 的 exact sync support claim。
6. ordinary CI/Mollusk是工程证据；formal D5、Stage-0、hermetic/mainnet parity仍 pending。

## 14. Rejected alternatives

- **静默升级 legacy profiles**：破坏既有 ABI/claim。
- **把 accounts/PDA 塞进 generic Semantic**：违反 target-neutral invariant。
- **profile-only猜 metas**：账户合同必须由 digest-bound extension/Plan承载。
- **全局 Principal=Pubkey**：破坏 portable opaque identity。
- **支持 alias/remaining accounts**：v1安全面和测试状态空间过大。
- **仅让 PDA 知道 seeds 即可转 Token**：缺 business authorization；signed APIs要求 seedAuthority outer signer。
- **使用 Rust CPI layout**：custom assembly无法安全依赖 Rust `AccountInfo`/`StableInstruction` ABI。
- **把 direct-mapped input当 contiguous bytes**：会跨未映射 growth span并误读 pointer table。
- **从 mainnet临时 dump Token/ATA ELF**：可变部署观察不能成为 package authority。
- **canonical bump 255..0**：与 pinned Agave 4.0.0 syscall不一致。
