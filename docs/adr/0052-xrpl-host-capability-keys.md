---
id: ADR-0052
title: XRPL host-key bindings for unixTime / caller / sha256 (symbols only)
status: proposed
owner: architecture
updated: 2026-08-17
normative: true
---

# ADR-0052：XRPL host 键绑定（unixTime / caller / sha256）

## 状态

proposed

本 ADR **只冻符号与诚实处置**。owner 未对 TIME / CALLER 拍 **yes** 之前，
Plan / IR / Emit **不得**开叶。`pf.crypto.sha256` 本 ADR 已拍 **keep-FC**。
不发明 CAP-7 / CAP-8 / CAP-9 leaf ID。

## 背景

ADR-0049 / ADR-0050 已交付 XRPL Q0 `.rs` + Q1 opt-in `.wasm` extra。发射面钉在
craft `xrpl-wasm-std` rev `ffbe88da26df27e59a72b6202883f42f696933cc`
（crate path `xrpl_wasm_std`）。Lower 对 ContextRead 与 `pf.crypto.*` 仍 named
FC，诊断写「no XRPL host binding」。

CAP 层既有纪律（ADR-0031 / `capability-layer-tasks.md`）：先 `CAP-D-*` 冻真实
host 或诚实 keep-FC，再另批 leaf。XRPL 是第 13 个 materializer，**不**自动加入
既有 CAP-1a…5 编码行。本 ADR 只做 XRPL 三键决策，不开
`blockHeight` / `attachedValue` / `chainId` / `self` / `keccak256`。

证据来源（只读，不切 official crate）：

- craft `xrpl-wasm-std` @ `ffbe88da…`：`src/host/host_bindings.rs`、
  `src/core/current_tx/{contract_call,traits}.rs`
- [XLS-0102](https://xls.xrpl.org/xls/XLS-0102-wasm-vm.html) host 表
  （`parent_ldgr_time` / `sha512_half`）
- Q0 已发射：`get_current_contract_call` / `ContractCallFields` /
  `get_data`/`set_data` / `trace`。view-only 与 entry+view 共用同一
  `get_current_contract_call` storage helper；这不开放
  `context.caller`，也不声称 ContractCall 运行期对 view 诚实。

不得改用 official `ripple/xrpl-wasm-stdlib` + `wasm32v1-none`（ADR-0050 已拒）。

## 决策

三节独立。任一节 yes / keep-FC 不牵动另外两节。

### TIME — `context.unixTimeSeconds`

**候选符号（冻）**：`xrpl_wasm_std::host::get_parent_ledger_time() -> i32`

对应 XLS-0102 `parent_ldgr_time`。单位是 **Ripple Time**（自 2000-01-01
00:00:00 UTC 起的秒），**不是** Unix。catalog 键是 Unix seconds。

若 owner 日后拍 yes，唯一合法 lowering 是：

```text
host < 0  → fail closed（host error code，不得 wrap）
host ≥ 0  → (host as u64) + 946684800   // Ripple epoch → Unix
```

`946684800` 是 XRPL 协议公开常量，不是发明偏移。禁止把 Ripple Time 原值
当成 `unixTimeSeconds`。禁止改绑 `get_ledger_sqn`（那是高度，本 ADR 不决策）。

**本切片处置**：符号已冻；叶 **保持 named FC**，等
`CAP-D-XRPL-TIME` owner yes。

### CALLER — `context.caller`

**候选符号（冻）**：

```text
let tx = xrpl_wasm_std::core::current_tx::contract_call::get_current_contract_call();
tx.get_account()   // TransactionCommonFields；20-byte AccountID
```

`get_account` 是当前 **ContractCall** 交易的 `Account`（发起方）。不是：

| 符号 | 为何不是 caller |
|---|---|
| `get_contract_account()` | 合约自身 → 将来若开是 `context.self`，本 ADR 不决策 |
| `get_owner()` | 合约创建者，不是本次调用方 |
| T4 Principal 9 叶 | identity 存储；**不是** AccountID |

若 owner 日后拍 yes，编码必须跟 ADR-0025 同类
`u32le(20)‖AccountID`（network-order 20B）。**禁止**把 Principal 全局等同
XRPL AccountID。T4 `len+w0..w7` 存储面不变。

callable 范围（日后叶，本 ADR 预钉）：仅 **entry**（ContractCall 上下文）。
`init` 走 `ContractCreate`，`get_current_contract_call` 不诚实；**view** 与
ICP/NEAR/CW 同纪律，名义 FC。

**本切片处置**：符号已冻；叶 **保持 named FC**，等
`CAP-D-XRPL-CALLER` owner yes。

### SHA — `pf.crypto.sha256`

craft host **没有** SHA-256。唯一哈希原语是
`xrpl_wasm_std::host::compute_sha512_half`（XLS-0102 `sha512_half`：SHA-512
的前 32 字节）。official `xrpl_wasm_stdlib` 同样只有 `compute_sha512_half`。

`sha512Half ≠ sha256`。把 `compute_sha512_half` 别名成
`pf.crypto.sha256` 违反 CAP 层「弱原语不得冒充 catalog 项」
（同 TON `string_hash`、CosmWasm 无 host）。

**本切片处置（已决）**：**keep named FC**。不冻伪 sha256 符号。
`keccak256` / siblings 继续 FC。不发明 `pf.crypto.sha512Half` catalog 行。

## 明确排除

- 本 ADR **不开** Plan / IR / Emit / Validate / `Targets.lean` 叶
- `blockHeight`（`get_ledger_sqn`）、`chainId`（`get_network_id`）、
  `self`、`attachedValue`、`keccak256`
- AlphaNet / `ContractCreate` / `ContractCall` 产品部署 / `B-CALL-SEM`
- official `xrpl-wasm-stdlib` 切换、Tool Lock rustc、`deployable=true`
- accepted PRD 扩面、formal TASK / TST

## 理由

- TIME / CALLER 在已钉 crate 上有可引用 path；先冻 path 与单位/编码，避免
  日后叶发明宏或错绑 `Owner` / Ripple Time。
- SHA 没有诚实 host。keep-FC 是完整决策，不是「待查」。
- 与 CAP-D-SOL-TIME / CAP-D-TON-SHA / CAP-D-ICP-PRINCIPAL 同形：决策与编码
  叶分两刀。

## 影响

- 文档：`capability-layer-tasks.md` 增 `CAP-D-XRPL-TIME` /
  `CALLER` / `SHA`；parity 记 XRPL 列全 F；gap / §1e / dossier 指向本 ADR。
- 代码：无。Lower 现有 named FC 文案保持。
- 日后叶：仅当对应 CAP-D 为 yes 时另批 ID；SHA 本 ADR 已关闭，除非未来
  host 出现真实 SHA-256（另开 ADR，不得复用本 SHA 节）。

## 备选

- 把 Ripple Time 原值当作 Unix（拒绝：catalog 键撒谎）。
- 把 `sha512_half` 当作 sha256（拒绝：与 CAP-X-CW-SHA / TON `string_hash`
  同一失败模式）。
- 把 AccountID 写成 Principal 全局类型（拒绝：T4 / B-3）。
- 三份独立 ADR 文件（拒绝：一文件三独立节即可逐键拍板）。
