---
id: RPT-008
title: EVM 与 Solana 系统能力全景调研
status: draft
owner: research
updated: 2026-08-05
normative: false
---

# EVM 与 Solana 系统能力全景调研

> 调研日期：2026-08-05
> 范围：EVM（以太坊）与 Solana 两个平台
> 方法：基于官方/权威资料（EIP、execution-specs、evm.codes、Solana 官方 syscall-reference、anza-xyz/agave 源码、docs.rs）

---

## 第一部分：EVM（以太坊）

### 1. 环境/区块类 Opcodes

| 名称 | Hex | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|-----|------|---------|--------|------------|
| BLOCKHASH | 0x40 | 高度/历史 | 取最近 256 个已完成区块（不含当前块）之一的 hash；越界返回 0。gas=20 | ✅ | ✅ |
| COINBASE | 0x41 | 身份 | 当前块的受益人/提议者地址（fee recipient）。gas=2 | ✅ | ✅ |
| TIMESTAMP | 0x42 | 时间 | 当前块的 Unix 时间戳（秒）。gas=2 | ✅ | ✅ |
| NUMBER | 0x43 | 高度 | 当前块高度。gas=2 | ✅ | ✅ |
| PREVRANDAO | 0x44 | 随机 | PoS 后的前一个 beacon block 的 RANDAO mix（原 DIFFICULTY）。**有偏、可预测，非安全随机**。gas=2 | ✅ | ✅ |
| GASLIMIT | 0x45 | 资源 | 当前块的 gas limit。gas=2 | ✅ | ✅ |
| CHAINID | 0x46 | 身份 | 当前链 ID（EIP-1344，重放保护）。gas=2 | ✅ | ✅ |
| SELFBALANCE | 0x47 | 余额 | 当前合约自身余额（等价 `BALANCE(ADDRESS)` 但更便宜）。gas=5 | ✅ | ✅ |
| BASEFEE | 0x48 | 资源 | 当前块的 EIP-1559 base fee per gas（wei）。gas=2 | ✅ | ✅ |
| BLOBHASH | 0x49 | 其他 | 本交易的第 `index` 个 blob 的 versioned hash（EIP-4844）；越界返回 0。gas=3 | ✅ | ✅ |
| BLOBBASEFEE | 0x4A | 资源 | 当前块的 blob base fee per blob gas（EIP-7516）。gas=2 | ✅ | ✅ |

**说明**：所有环境/区块 opcode 均只读，均可在 `view`/`pure`（STATICCALL）上下文执行。TIMESTAMP 对应项目已抽象的 `context.unixTimeSeconds`。

### 2. 账户/余额类 Opcodes

| 名称 | Hex | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|-----|------|---------|--------|------------|
| ADDRESS | 0x30 | 身份 | 当前执行合约地址 `address(this)`。gas=2 | ✅ | ✅ |
| BALANCE | 0x31 | 余额 | 指定地址的 wei 余额；不存在账户返回 0。gas=100 warm / 2600 cold | ✅ | ✅ |
| ORIGIN | 0x32 | 身份 | 交易原始发起者 `tx.origin`（总是 EOA）。gas=2 | ✅ | ✅ |
| CALLER | 0x33 | 身份 | 当前调用者 `msg.sender`。gas=2 | ✅ | ✅ |
| CALLVALUE | 0x34 | 余额 | 本次调用携带的 wei 值 `msg.value`。gas=2 | ✅ | ✅ |
| GASPRICE | 0x3A | 资源 | 交易的 gas price（EIP-1559 下为 `min(maxFee, baseFee+priorityFee)`）。gas=2 | ✅ | ✅ |
| EXTCODESIZE | 0x3B | 身份 | 指定地址的代码字节长度。gas=100 warm / 2600 cold | ✅ | ✅ |
| EXTCODECOPY | 0x3C | 身份 | 将指定地址代码复制到 memory。gas=100/2600 + 3×words + mem | ✅ | ✅ |
| EXTCODEHASH | 0x3F | 身份 | 指定地址代码的 keccak256 hash；不存在=0，空代码=`0xc5d2...`。gas=100 warm / 2600 cold | ✅ | ✅ |
| SELFBALANCE | 0x47 | 余额 | 当前合约自身余额。gas=5 | ✅ | ✅ |

**说明**：CALLER 对应 `context.caller`；SELFBALANCE/BALANCE 对应 `envRead nativeVaultBalance`。以上全部只读，view 可读。

### 3. 预编译合约（Precompiles）

| 地址 | 名称 | 类别 | 功能 | 引入 |
|------|------|------|------|------|
| 0x01 | ecrecover | 密码学 | ECDSA 公钥恢复（hash, v, r, s → address） | Frontier |
| 0x02 | sha256 | 密码学 | SHA-256 哈希 | Frontier |
| 0x03 | ripemd160 | 密码学 | RIPEMD-160 哈希 | Frontier |
| 0x04 | identity | 其他 | 原样返回输入 | Frontier |
| 0x05 | modexp | 密码学 | 大整数模幂 `base^exp % mod`（EIP-198/2565） | Byzantium |
| 0x06 | bn256Add | 密码学 | BN254 G1 点加（EIP-196/1108） | Byzantium |
| 0x07 | bn256ScalarMul | 密码学 | BN254 G1 标量乘（EIP-196/1108） | Byzantium |
| 0x08 | bn256Pairing | 密码学 | BN254 pairing check（EIP-197/1108） | Byzantium |
| 0x09 | blake2f | 密码学 | BLAKE2b F 压缩函数（EIP-152） | Istanbul |
| 0x0a | pointEvaluation | 密码学 | KZG 点求值验证（EIP-4844 blob） | Cancun |
| 0x0b | bls12-381 G1Add | 密码学 | BLS12-381 G1 点加（EIP-2537） | Pectra/Prague |
| 0x0c | bls12-381 G1MSM | 密码学 | BLS12-381 G1 多标量乘 | Pectra/Prague |
| 0x0d | bls12-381 G2Add | 密码学 | BLS12-381 G2 点加 | Pectra/Prague |
| 0x0e | bls12-381 G2MSM | 密码学 | BLS12-381 G2 多标量乘 | Pectra/Prague |
| 0x0f | bls12-381 Pairing | 密码学 | BLS12-381 pairing check | Pectra/Prague |
| 0x10 | bls12-381 MapG1 | 密码学 | Fp → G1 映射 | Pectra/Prague |
| 0x11 | bls12-381 MapG2 | 密码学 | Fp2 → G2 映射 | Pectra/Prague |

**说明**：预编译均为无状态纯函数，通过 CALL/STATICCALL 调用，view 可读。BN254（0x06-0x08）对应项目已抽象的 Field bn254；BLS12-381（0x0b-0x11）为更新更强的曲线。

### 4. 日志/事件 Opcodes

| 名称 | Hex | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|-----|------|---------|--------|------------|
| LOG0 | 0xA0 | 日志 | 发出无 topic 的日志；data 来自 memory。gas=375 + 8×bytes | ❌（有副作用） | ❌ |
| LOG1 | 0xA1 | 日志 | 1 个 topic 的日志。gas=750 + 8×bytes | ❌ | ❌ |
| LOG2 | 0xA2 | 日志 | 2 个 topic 的日志。gas=1125 + 8×bytes | ❌ | ❌ |
| LOG3 | 0xA3 | 日志 | 3 个 topic 的日志。gas=1500 + 8×bytes | ❌ | ❌ |
| LOG4 | 0xA4 | 日志 | 4 个 topic 的日志。gas=1875 + 8×bytes | ❌ | ❌ |

**说明**：LOG0-LOG4 有副作用（写入交易回执），在 STATICCALL（view/pure）中禁止执行。gas 公式：`375 + 375×n + 8×data_size + mem_expansion`。对应项目的 `emit` 语义。

### 5. 密码学/随机

| 能力 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| PREVRANDAO (0x44) | 随机 | beacon chain 前一个 block 的 RANDAO mix；**有偏、可预测，不应用于高价值随机** | ✅ | ✅ |
| BLOCKHASH (0x40) | 随机（弱） | 最近 256 块 hash，可作为弱熵源 | ✅ | ✅ |
| ecrecover (0x01) | 密码学 | ECDSA 签名恢复 | ✅ | ✅ |
| sha256 (0x02) | 密码学 | SHA-256 | ✅ | ✅ |
| ripemd160 (0x03) | 密码学 | RIPEMD-160 | ✅ | ✅ |
| blake2f (0x09) | 密码学 | BLAKE2b 压缩 | ✅ | ✅ |
| modexp (0x05) | 密码学 | 大整数模幂 | ✅ | ✅ |
| BN254 (0x06-0x08) | 密码学 | 椭圆曲线运算 + pairing | ✅ | ✅ |
| BLS12-381 (0x0b-0x11) | 密码学 | BLS 曲线运算 + pairing | ✅ | ✅ |
| KZG (0x0a) | 密码学 | blob KZG 点求值验证 | ✅ | ✅ |

**关键结论**：EVM **没有原生安全随机 opcode**。PREVRANDAO 是最接近的原生随机源，但有 1-bit 偏置、可被提议者操纵，OWASP SCWE-153 明确将其列为安全弱点。安全随机需依赖外部 VRF（如 Chainlink VRF）或 commit-reveal 方案。

---

## 第二部分：Solana

### 1. Syscalls 完整清单

#### 1.1 控制流

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| abort | 资源 | 立即终止程序（LLVM 生成，非显式使用） | ❌ | ❌ |
| sol_panic_ | 资源 | 带文件名/行号终止 | ❌ | ❌ |

#### 1.2 日志

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_log_ | 日志 | 输出 UTF-8 字符串日志 | ✅（无状态变更） | ✅ |
| sol_log_64_ | 日志 | 输出 5 个 u64 值（hex） | ✅ | ✅ |
| sol_log_pubkey | 日志 | 输出 Pubkey（base58） | ✅ | ✅ |
| sol_log_compute_units_ | 资源 | 输出剩余 compute units | ✅ | ✅ |
| sol_log_data | 日志 | 输出任意字节切片（base64） | ✅ | ✅ |

**说明**：Solana 日志对应 EVM LOG0-LOG4。但 Solana 日志是纯运行时输出（不进入链上存储/回执 bloom filter），且在 view 中也可调用（不改变状态）。项目已抽象的 `emit` 对应此。

#### 1.3 密码学/哈希

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_sha256 | 密码学 | 多段字节 SHA-256 | ✅ | ✅ |
| sol_keccak256 | 密码学 | 多段字节 Keccak-256 | ✅ | ✅ |
| sol_blake3 | 密码学 | Blake3 哈希（feature-gated） | ✅ | ✅ |
| sol_poseidon | 密码学 | Poseidon 哈希（feature-gated） | ✅ | ✅ |
| sol_secp256k1_recover | 密码学 | 从签名恢复 secp256k1 公钥 | ✅ | ✅ |
| sol_curve_validate_point | 密码学 | Curve25519 点验证（feature-gated） | ✅ | ✅ |
| sol_curve_group_op | 密码学 | Curve25519 群运算 add/sub/mul（feature-gated） | ✅ | ✅ |
| sol_curve_multiscalar_mul | 密码学 | Curve25519 多标量乘（feature-gated） | ✅ | ✅ |
| sol_alt_bn128_group_op | 密码学 | BN254 G1 add/mul + pairing（feature-gated） | ✅ | ✅ |
| sol_alt_bn128_compression | 密码学 | BN254 点压缩/解压（feature-gated） | ✅ | ✅ |
| sol_big_mod_exp | 密码学 | 大整数模幂（feature-gated） | ✅ | ✅ |

**说明**：Solana 的 `sol_secp256k1_recover` 对应 EVM 的 ecrecover；`sol_sha256` 对应 EVM 的 sha256 precompile；`sol_keccak256` 对应 EVM 内置 keccak256（EVM 的 keccak 是指令而非 precompile）；`sol_alt_bn128_*` 对应 EVM BN254 precompiles（0x06-0x08）；`sol_big_mod_exp` 对应 EVM modexp（0x05）。

#### 1.4 CPI（跨程序调用）

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_invoke_signed_rust | 调用/消息 | Rust ABI CPI 调用 | ❌ | ❌ |
| sol_invoke_signed_c | 调用/消息 | C ABI CPI 调用 | ❌ | ❌ |
| sol_get_processed_sibling_instruction | 调用/消息 | 获取已执行的同级指令 | ✅ | ✅ |
| sol_get_stack_height | 调用/消息 | 获取当前调用栈高度 | ✅ | ✅ |

**说明**：CPI 对应 EVM 的 CALL/DELEGATECALL。Solana 无 ORIGIN 对应物（无 tx.origin 概念，调用者通过 AccountInfo 传入）。

#### 1.5 返回数据

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_set_return_data | 调用/消息 | 设置本指令返回数据（最大 1024 字节） | ❌（有副作用） | ❌ |
| sol_get_return_data | 调用/消息 | 读取最近一次 CPI 的返回数据 | ✅ | ✅ |

**说明**：对应 EVM 的 RETURNDATASIZE/RETURNDATACOPY（0x3D/0x3E）。

#### 1.6 PDA（程序派生地址）

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_create_program_address | 身份 | 从 seeds + program ID 派生地址（返回 1 表示在曲线上=无效 PDA） | ✅ | ✅ |
| sol_try_find_program_address | 身份 | 迭代 bump seed（255→1）寻找有效 PDA，返回地址+bump | ✅ | ✅ |

**说明**：Solana 独有概念，EVM 无直接对应物。EVM 的 CREATE2（0xF5）可算部分类比（从 salt+initcode 派生地址），但语义不同。

#### 1.7 内存操作

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_memcpy_ | 存储 | 复制 n 字节 | ✅ | ✅ |
| sol_memmove_ | 存储 | 复制 n 字节（处理重叠） | ✅ | ✅ |
| sol_memcmp_ | 存储 | 比较 n 字节 | ✅ | ✅ |
| sol_memset_ | 存储 | 填充 n 字节 | ✅ | ✅ |
| sol_alloc_free_ | 存储 | 传统 bump 分配器（**新部署已禁用**） | ✅ | ✅ |

**说明**：内存操作是 VM 内部操作，不影响链上状态，只读且 view 可读。`sol_alloc_free_` 已对新部署程序禁用。

#### 1.8 程序数据/栈

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_get_return_data | 调用/消息 | 见 1.5 | ✅ | ✅ |
| sol_get_processed_sibling_instruction | 调用/消息 | 见 1.4 | ✅ | ✅ |
| sol_get_stack_height | 调用/消息 | 见 1.4 | ✅ | ✅ |

**说明**：Solana **没有 `sol_get_account_info` syscall**。账户数据通过程序入口点（`AccountInfo` 数组）直接传入，零拷贝访问。AccountInfo 包含 key、lamports、data pointer/slice、owner、rent_epoch、is_signer、is_writable。

#### 1.9 Compute/资源

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_remaining_compute_units | 资源 | 返回剩余 compute units（feature-gated） | ✅ | ✅ |
| sol_log_compute_units_ | 资源 | 输出剩余 compute units | ✅ | ✅ |

#### 1.10 Epoch Stake

| 名称 | 类别 | 语义简述 | 只读？ | view 可读？ |
|------|------|---------|--------|------------|
| sol_get_epoch_stake | 身份/资源 | 返回当前 epoch 总质押或某投票账户质押（SIMD-0133，feature-gated） | ✅ | ✅ |

### 2. Sysvar Accounts

| Sysvar | 地址 | 类别 | 关键字段 | 只读？ | view 可读？ |
|--------|------|------|---------|--------|------------|
| Clock | `SysvarC1ock111...` | 时间/高度 | `slot: u64`、`epoch_start_timestamp: i64`、`epoch: u64`、`leader_schedule_epoch: u64`、`unix_timestamp: i64`（质押加权中位数，有漂移上限） | ✅ | ✅ |
| EpochSchedule | `SysvarEpochSchedu1e...` | 高度 | `slots_per_epoch: u64`、`leader_schedule_slot_offset: u64`、`warmup: bool`、`first_normal_epoch: u64`、`first_normal_slot: u64` | ✅ | ✅ |
| Rent | `SysvarRent111...` | 资源 | `lamports_per_byte_year: u64`（新 crate: `lamports_per_byte`）、`exemption_threshold: f64`（通常 2.0）、`burn_percent: u8`（通常 50） | ✅ | ✅ |
| SlotHashes | `SysvarS1otHashes111...` | 高度/历史 | `Vec<(Slot, Hash)>`，最近约 512 条，最新在前 | ✅ | ✅（但体量大） |
| SlotHistory | `SysvarS1otHistory111...` | 高度/历史 | `bits: BitVec<u64>`、`next_slot: u64`；**过大，`Sysvar::get()` 返回 UnsupportedSysvar** | ✅ | ❌（on-chain 不可全量读） |
| EpochRewards | `SysvarEpochRewards111...` | 资源 | `distribution_starting_block_height: u64`、`num_partitions: u64`、`parent_blockhash: Hash`、`total_points: u128`、`total_rewards: u64`、`distributed_rewards: u64`、`active: bool` | ✅ | ✅ |
| LastRestartSlot | `SysvarLastRestartS1ot...` | 高度 | `last_restart_slot: u64` | ✅ | ✅ |
| Fees | `SysvarFees111...` | 资源 | `fee_calculator.lamports_per_signature: u64`；**已废弃（1.9.0+）** | ✅ | ✅（已废弃） |
| RecentBlockhashes | `SysvarRecentB1ock...` | 高度 | `Vec<Entry{blockhash, fee_calculator}>`；**已废弃（1.9.0+）** | ✅ | ❌（不实现 get()） |

**说明**：Clock.unix_timestamp 对应项目已抽象的 `context.unixTimeSeconds`；Clock.slot 对应 EVM NUMBER（但语义不同：slot ≈ 400ms，block number 是逻辑高度）。SlotHashes 对应 EVM BLOCKHASH（但范围更大，~512 vs 256）。

### 3. Builtin / Loader 程序

| 程序 | Program ID | 类别 | 功能简述 | 只读？ | view 可读？ |
|------|-----------|------|---------|--------|------------|
| Native Loader | `NativeLoader111...` | 调用/消息 | 拥有所有 builtin 和 loader | — | — |
| BPF Loader v1 | `BPFLoader111...` | 调用/消息 | 旧版不可升级程序加载器 | — | — |
| BPF Loader v2 | `BPFLoader211...` | 调用/消息 | 旧版不可升级程序加载器 | — | — |
| BPF Loader Upgradeable v3 | `BPFLoaderUpgradeab1e...` | 调用/消息 | 当前默认加载器，支持升级/关闭/扩展 | — | — |
| System Program | `11111111111111111111111111111111` | 余额/账户 | 创建账户、SOL 转账、分配空间、分配所有权 | ❌（可写） | ❌ |
| Vote Program | `Vote111...` | 身份 | 验证者投票账户管理 | ❌ | ❌ |
| Stake Program | `Stake111...` | 资源 | 质押账户管理 | ❌ | ❌ |
| Config Program | `Config111...` | 存储 | 链上配置数据存储 | ❌ | ❌ |
| Compute Budget | `ComputeBudget111...` | 资源 | 设置 compute unit 限制和 priority fee | — | — |
| Address Lookup Table | `AddressLookupTab1e...` | 身份 | 管理 ALT（v0 交易地址压缩） | ❌ | ❌ |
| ZK ElGamal Proof | `ZkE1Gama1Proof...` | 密码学 | 验证 ElGamal 加密的零知识证明 | ✅ | — |
| Ed25519 (precompile) | `Ed25519SigVerify111...` | 密码学 | 验证 ed25519 签名（原生执行，**不可 CPI**） | ✅ | ✅ |
| Secp256k1 (precompile) | `KeccakSecp256k111...` | 密码学 | secp256k1 公钥恢复（ecrecover，**不可 CPI**） | ✅ | ✅ |
| Secp256r1 (precompile) | `Secp256r1SigVerify...` | 密码学 | 验证 secp256r1 签名（**不可 CPI**） | ✅ | ✅ |

**说明**：System Program 的 Transfer 指令对应 EVM 的原生 ETH 转账（CALL with value）。Precompiles（Ed25519/Secp256k1/Secp256r1）通过指令数据触发，不可通过 CPI 调用。

---

## 跨平台对照与无对应物标注

### 已有抽象对应关系

| 项目抽象 | EVM | Solana |
|---------|-----|--------|
| `context.unixTimeSeconds` | TIMESTAMP (0x42) | Clock.unix_timestamp |
| `context.caller` | CALLER (0x33) | AccountInfo.is_signer（通过传入账户） |
| `envRead nativeVaultBalance` | SELFBALANCE (0x47) / BALANCE (0x31) | AccountInfo.lamports |
| `emit` | LOG0-LOG4 (0xA0-0xA4) | sol_log_data / sol_log_ |
| `revert` | REVERT (0xFD) | sol_panic_ / 错误返回 |

### 各链**无共通对应物**的能力

| 能力 | 所属链 | 另一链情况 |
|------|--------|-----------|
| **CHAINID** (0x46) | EVM | Solana **无直接等价物**。Solana 通过 genesis 配置区分集群，程序无法在链上读取"链 ID"。 |
| **COINBASE** (0x41) | EVM | Solana 有 leader schedule（Clock.leader_schedule_epoch）但**不暴露具体 slot leader 地址**给程序。 |
| **BASEFEE / BLOBBASEFEE** (0x48/0x4A) | EVM | Solana 有 priority fee（Compute Budget Program）但**无 EIP-1559 base fee 概念**。 |
| **GASPRICE** (0x3A) | EVM | Solana 有 compute unit price，但语义不同（Solana 按 CU 计费，非 gas）。 |
| **ORIGIN** (0x32) | EVM | Solana **无 tx.origin 概念**。所有调用者通过 AccountInfo.is_signer 标记。 |
| **EXTCODESIZE/HASH/COPY** | EVM | Solana 程序代码不可被其他程序运行时读取（代码在只读内存区，无 syscall 暴露）。 |
| **BLOCKHASH** (0x40) | EVM | Solana 的 SlotHashes sysvar 功能类似但范围更大（~512 vs 256）且结构不同。 |
| **BLOBHASH** (0x49) | EVM | Solana 无 blob 数据可用性概念。 |
| **PDA** (`sol_create/try_find_program_address`) | Solana | EVM 的 CREATE2 (0xF5) 部分类比但语义本质不同（PDA 是确定性派生+曲线排除，CREATE2 是 hash 派生）。 |
| **CPI stack height / sibling instruction** | Solana | EVM 有 call depth（1024）但无同级指令查询。 |
| **Rent / Rent exemption** | Solana | EVM 无账户存储租金概念（gas 即一次性支付）。 |
| **Epoch / Slot / leader schedule** | Solana | EVM 的 NUMBER 是连续整数，无 epoch/leader 概念。 |
| **EpochRewards / Stake** | Solana | EVM 无质押奖励分发概念（验证者奖励在共识层处理，不暴露给 EVM）。 |
| **Solana native Ed25519** | Solana | EVM 无原生 Ed25519（需预编译或手动实现）。 |
| **EVM BLS12-381 precompiles** | EVM | Solana 有 feature-gated BLS12-381 相关 syscall（新版本），但尚未完全对应。 |
| **EVM modexp (0x05)** | EVM | Solana 有 feature-gated `sol_big_mod_exp`。 |

---

## 权威来源引用

### EVM
1. **execution-specs (EELS)** — Ethereum 执行层规范（可执行 Python 参考）：https://github.com/ethereum/execution-specs
2. **EIP-4399 (PREVRANDAO)** — https://eips.ethereum.org/EIPS/eip-4399
3. **EIP-4844 (BLOBHASH / KZG)** — https://eips.ethereum.org/EIPS/eip-4844
4. **EIP-7516 (BLOBBASEFEE)** — https://eips.ethereum.org/EIPS/eip-7516
5. **EIP-2537 (BLS12-381)** — https://eips.ethereum.org/EIPS/eip-2537
6. **EIP-1052 (EXTCODEHASH)** — https://eips.ethereum.org/EIPS/eip-1052
7. **EIP-1884 (SELFBALANCE)** — https://eips.ethereum.org/EIPS/eip-1884
8. **evm.codes (opcode 参考)** — https://www.evm.codes/
9. **evm.codes/precompiled** — https://www.evm.codes/precompiled
10. **ethereum.org opcodes** — https://ethereum.org/developers/docs/evm/opcodes/
11. **Yellow Paper** — https://github.com/ethereum/yellowpaper
12. **go-ethereum precompiles 源码** — https://github.com/ethereum/go-ethereum/blob/master/core/vm/contracts.go
13. **wolflo/evm-opcodes gas 参考** — https://github.com/wolflo/evm-opcodes/blob/main/gas.md
14. **OWASP SCWE-153 (PREVRANDAO 弱点)** — https://scs.owasp.org/SCWE/SCSVS-BLOCK/SCWE-153/

### Solana
1. **Solana 官方 Syscall Reference** — https://solana.com/docs/core/programs/syscall-reference
2. **anza-xyz/agave syscalls 源码** — https://github.com/anza-xyz/agave/blob/master/syscalls/src/lib.rs
3. **Anza Sysvar 文档** — https://docs.anza.xyz/runtime/sysvars
4. **Solana Builtin Programs** — https://solana.com/docs/core/programs/builtin-programs
5. **Solana Precompiles** — https://solana.com/docs/core/programs/precompiles
6. **solana-clock crate (Clock 字段)** — https://docs.rs/solana-clock/latest/solana_clock/struct.Clock.html
7. **solana-epoch-schedule crate** — https://docs.rs/solana-program/latest/solana_program/epoch_schedule/struct.EpochSchedule.html
8. **solana-rent crate** — https://docs.rs/solana-rent/latest/solana_rent/struct.Rent.html
9. **solana-slot-hashes crate** — https://docs.rs/solana-slot-hashes/latest/solana_slot_hashes/struct.SlotHashes.html
10. **solana-program sysvar EpochRewards** — https://docs.rs/solana-program/latest/solana_program/sysvar/epoch_rewards/struct.EpochRewards.html
11. **solana-program sysvar LastRestartSlot** — https://docs.rs/solana-program/latest/solana_program/sysvar/last_restart_slot/struct.LastRestartSlot.html
12. **solana-program sysvar Fees (deprecated)** — https://docs.rs/solana-program/latest/solana_program/sysvar/fees/index.html
13. **Solana Program Deployment (Loaders)** — https://solana.com/docs/core/programs/program-deployment
14. **Solana Programs 核心文档** — https://solana.com/docs/core/programs