---
id: ADR-0053
title: Call-bind v1 — compile-time opt-in callee address table
status: proposed
owner: architecture
updated: 2026-08-20
normative: true
---

# ADR-0053：Call-bind v1（编译期 opt-in 对端绑定表）

## 状态

proposed

本 ADR 冻结 CALL-BIND 大切片的五句产品口径与表 schema。**Wave 1 只解析**
`--bindings` 与 `proof-forge.call-bind.v1`；**不改** EVM / Solana / CosmWasm
emit。无 `--bindings` 时产品行为与今天完全相同（hashed QN / QN stub 仍是
隐式默认）。Wave 2 才把「无行 = fail closed」接到三叶 Lower/Emit。

不关闭 `B-CALL-SEM` 全表。不接受 ADR-0036 / 0051。不改
`semantic-core.md`。不声称 formal / C-3 / Anvil lossless / CREATE / CREATE2。

## 背景

inspect 已诚实标出三条地址残差（2026-08-19 COMP-1-CALL-SEM-LAND）：

| Target | residual | 今天 emit |
|---|---|---|
| evm | `hashed-qn-no-deploy-bind` | static QN path UTF-8 的 Ethereum Keccak 后 20 字节 |
| solana | `callee-identity-outer-account-open` | product sync CPI；callee / 外层账户 ABI 仍开 |
| cosmwasm | `contract-addr-qn-stub` | `SubMsg.contract_addr` = QN 字符串 stub |

hashed stub 不是部署地址。空账户 EVM void `CALL` 今天会成功。ADR-0029 把
portable 互通停在 NetworkProfile；本 ADR **不**走那条路。

## 决策（五句）

1. **绑定权威 = 编译期、版本化、opt-in 表。** 文件经 `build --bindings <path>`
   读入。不是 NetworkProfile，不是 Anvil / wasmd receipt，不进
   `SemanticProgramV1`。
2. **EVM 地址种类 = 预置 20 字节。** 人手填 / 测试夹具。本切片不做 CREATE /
   CREATE2 mint。三种地址不可互换。
3. **空账户 void CALL 将在 Wave 2a 改成 fail closed。** Wave 1 不改 Yul。
   这是语义变化，必须单独立测。
4. **`schedule` 仍是同笔 tx fire-and-forget。** 本 ADR 不改 catalog 键
   `effect.asynchronous-workflow`（改键另批，与 ADR-0051 亲戚）。
5. **Bool / Int / Bytes returndata 继续 fail closed。** 本切片只绑地址。

附加纪律：

- `pf.crypto.*` 与 `pf.assets` **不走**这张表。
- 无 `identity` 字段 = 只绑地址，**不得**写成已 join 链上代码。
- Wave 1：无 `--bindings` = 今天的 stub 路径。有 flag = 解析并保留表，emit
  仍走 stub（表对产品物化仍 inert）。
- Wave 2：有 `--bindings` 时，三叶 generic `call`/`schedule` 无匹配行 →
  fail closed；hashed / QN stub **不再当隐式默认**。
- 其余十叶（noir / near / ton / icp / quint / soroban / openvm / aleo / psy /
  xrpl）给了 `--bindings` → usage / fail closed（本表只服务三叶）。
- `check` 不接受 `--bindings`。
- 不把产品 `build` 接到 Anvil 预置或任何网络。

## Schema `proof-forge.call-bind.v1`

输入必须是 **PF-JCS**（`parsePfJcs`：canonical re-encode identity；空白 /
乱序键 / 尾随数据 fail closed）。

根对象精确三键（UTF-16 排序后为 `bindings` / `schema` / `target`）：

```text
{
  "bindings":[ ... ],
  "schema":"proof-forge.call-bind.v1",
  "target":"evm"
}
```

| 字段 | 规则 |
|---|---|
| `schema` | 精确 `proof-forge.call-bind.v1` |
| `target` | 精确 `evm` / `solana` / `cosmwasm`（`TargetId.parse?`） |
| `bindings` | 数组；允许空。行按 source order 保留 |

每行必有 `callee`（点分 QualifiedName，≥2 个 identifier 分量，复用
`validateIdentifierComponent`）。其余字段按 `target`：

| target | 必填 | 校验 |
|---|---|---|
| evm | `address` | `0x` + 40 个小写 hex = 20 字节 |
| solana | `programId` + `accounts` | `programId` = 64 个小写 hex = 32 字节；`accounts` 数组，每项 `role`（identifier）+ `pubkey`（32 字节 hex）；可选 `signer`/`writable` bool，缺省 false。`role` 在该行内唯一 |
| cosmwasm | `contractAddr` | 非空 UTF-8，1..128 字节，NFC；**不**在 Wave 1 校验 bech32 |

可选 `identity` 对象，键只能是 `sourceHash` / `semanticHash` /
`artifactSha256`，值均为 `sha256:` + 64 小写 hex（`parseDigest`）。缺省 =
不 join。

未知键、缺必填、跨 target 字段（例如 evm 行带 `programId`）、重复
`callee`（同一表内 exact QN）、空 `callee` 分量 → fail closed。

## 非目标

- 不关闭 `B-CALL-SEM`（Noir witness、NEAR promise、TON message、ICP
  advertise 保持现状）。
- 不做 Token/ATA `artifactBinding`、wasmd rung-2、CREATE2、NetworkProfile。
- 不改 Normalize / CheckV1 / Semantic wire。
- 不升格 formal TASK/TST。

## 后果

Wave 1 落地后：CLI 认识 `--bindings`；表可解码、可查 QN；产品 emit 不变。
Wave 2 三叶各自消费同一 `CallBindTableV1`。inspect residual 只在 Wave 2
「该 program 全部 generic call 有行」时才清。
