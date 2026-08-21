---
id: ADR-0053
title: Call-bind v1 — compile-time opt-in callee address table
status: accepted
owner: architecture
updated: 2026-08-21
normative: true
approvers: davirain
approvedAt: 2026-08-21
reviewCommit: 239e335ac4272f7b292eb87c913e46c8c805c0b9
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/239e335ac4272f7b292eb87c913e46c8c805c0b9
openFindings: none
---

# ADR-0053：Call-bind v1（编译期 opt-in 对端绑定表）

## 状态

`accepted`（2026-08-21）

本 ADR 冻结 CALL-BIND 大切片的五句产品口径与表 schema。**Wave 1** 解析
`--bindings` 与 `proof-forge.call-bind.v1`。**Wave 2** 把表显式接到三叶
emit：有 `--bindings` 时 generic `call`/`schedule` 无匹配行 fail closed；
无 flag 时 hashed QN / QN stub 不变。`pf.crypto.*` / `pf.assets` 不查表。
**Wave 2a（已接线）**：EVM generic void CALL 在 `extcodesize==0` 时
fail closed。**Wave 2b（已接线）**：Solana nonempty `accounts` → 编译期
AccountMeta（pubkey + signer/writable，≤8）。**Wave 2c（已接线）**：成功
`build` 输出 program-level `callScheduleResidual`。

**Wave 3（2026-08-21 工程闭合）**：Solana 对「有 logical state、单一 generic
callee、同步 void CALL、1..8 个 non-alias account rows、无 frozen CPI site」的
产品子集，把 state 后的 bound accounts 与 executable callee program 投影为
outer AccountInfo roles；逐项校验 key / signer / writable / executable，并把
`accounts + callee program` 的非空 AccountInfo 范围传给 `sol_invoke_signed_c`。
该子集成功 build 的 `callScheduleResidual = null`。empty-state、schedule、
empty-row、多个 generic callee、与 frozen CPI site 混合、generic result-bearing CALL
继续 fail closed 或保留 residual。target `inspect <target>` 仍是静态 kind 闭表，
不按 program 清。

不关闭 `B-CALL-SEM` 全表。不接受 ADR-0036 / 0051。不改
`semantic-core.md`。不声称 formal / C-3 / Anvil lossless / CREATE / CREATE2。

## 背景

inspect 已诚实标出三条地址残差（2026-08-19 COMP-1-CALL-SEM-LAND）：

| Target | 静态 inspect residual | 有精确 bind row 的 product build |
|---|---|---|
| evm | `hashed-qn-no-deploy-bind` | 使用表中预置 20-byte address；全部 generic QN 覆盖后 program residual 可为 `null` |
| solana | `callee-identity-outer-account-open` | Wave 3 支持子集使用 exact programId + outer AccountInfo join；其它形态保持 FC/residual |
| cosmwasm | `contract-addr-qn-stub` | 使用表中 `contractAddr`；全部 generic QN 覆盖后 program residual 可为 `null` |

target `inspect` 没有 program 或 bind table 输入，所以继续报告静态缺口；它不与
成功 build 的 program-level residual 冲突。无表时 hashed stub 不是部署地址。
空账户 EVM void `CALL` 在 Wave 2a 起 fail closed（`extcodesize`）。ADR-0029
把 portable 互通停在 NetworkProfile；本 ADR **不**走那条路。

## 决策（五句）

1. **绑定权威 = 编译期、版本化、opt-in 表。** 文件经 `build --bindings <path>`
   读入。不是 NetworkProfile，不是 Anvil / wasmd receipt，不进
   `SemanticProgramV1`。
2. **EVM 地址种类 = 预置 20 字节。** 人手填 / 测试夹具。本切片不做 CREATE /
   CREATE2 mint。三种地址不可互换。
3. **空账户 void CALL 在 Wave 2a 改成 fail closed。** generic void CALL 在
   `extcodesize==0` 时 `revert(0,0)`，然后才做 `CALL`。`schedule` 仍
   fire-and-forget；result-bearing 仍靠 `returndatasize`。这是语义变化，
   已单独立测。
4. **`schedule` 仍是同笔 tx fire-and-forget。** 本 ADR 不改 catalog 键
   `effect.asynchronous-workflow`（改键另批，与 ADR-0051 亲戚）。
5. **Bool / Int / Bytes returndata 继续 fail closed。** 本切片只绑地址。

附加纪律：

- `pf.crypto.*` 与 `pf.assets` **不走**这张表。
- 无 `identity` 字段 = 只绑地址，**不得**写成已 join 链上代码。
- Wave 1：无 `--bindings` = 今天的 stub 路径。有 flag = 解析并保留表。
- Wave 2（已接线）：有 `--bindings` 时，三叶 generic `call`/`schedule` 无匹配行 →
  fail closed；hashed / QN stub **不再当隐式默认**。表经显式参数下传到
  `emitProgram` / `materializeResult` / 三叶 `buildFromCapability`（从不进
  capability、从不做 IO.Ref）。
- Wave 3（已接线）：Solana 支持子集把既有 roles 后缀固定为 bound account rows
  （source order）再接 executable callee program；Plan / IDL / IR / emitter / client
  verifier 必须投影同一 role order、key policy、constraint 与 privilege。generic
  call-bind 不伪造 frozen `cpiSites`。
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
| solana | `programId` + `accounts` | `programId` = 64 个小写 hex = 32 字节；`accounts` 数组，每项 `role`（identifier）+ `pubkey`（32 字节 hex）；可选 `signer`/`writable` bool，缺省 false。`role` 在该行内唯一；build cap 为 8。Wave 3 要求数组非空、account pubkey 两两不同且均不等于 `programId` |
| cosmwasm | `contractAddr` | 非空 UTF-8，1..128 字节，NFC；**不**在 Wave 1 校验 bech32 |

可选 `identity` 对象，键只能是 `sourceHash` / `semanticHash` /
`artifactSha256`，值均为 `sha256:` + 64 小写 hex（`parseDigest`）。缺省 =
不 join。当前三个 emitter 只消费 endpoint（address / programId / contractAddr）和
Solana account rows；`identity` digest 即使存在也仍是 parse-only metadata，**不**参与
artifact-to-endpoint 验证、SupportClaim 或 emit。

未知键、缺必填、跨 target 字段（例如 evm 行带 `programId`）、重复
`callee`（同一表内 exact QN）、空 `callee` 分量 → fail closed。

## 非目标

- 不关闭 `B-CALL-SEM`（Noir witness、NEAR promise、TON message、ICP
  advertise 保持现状）。
- 不做 Token/ATA `artifactBinding`、wasmd rung-2、CREATE2、NetworkProfile。
- 不把 identity digest metadata 当成已验证的链上代码身份。
- 不开放 Solana schedule、generic result-bearing CALL、empty-state / empty-row /
  multi-callee / mixed frozen-site outer join。
- 不改 Normalize / CheckV1 / Semantic wire。
- 不升格 formal TASK/TST。

## 后果

Wave 2 落地后：CLI 认识 `--bindings`；表可解码、可查 QN；有表时三叶
generic call/schedule 消费同一 `CallBindTableV1`（EVM Yul 地址、CW WAT
`contract_addr`、Solana program id / AccountMeta）。无表行为不变。
Wave 2a：generic void CALL 空账户 fail closed。Wave 3 对上列 Solana 支持子集完成
outer AccountInfo join，并保持 empty rows 为旧 partial path。Wave 2c 的成功 `build`
露出 program-level `callScheduleResidual`（string 或 `null`）：无 generic call、
EVM/CW 全覆盖、或 Solana Wave 3 支持子集全覆盖时为 `null`；其它 Solana
形态保留 `callee-identity-outer-account-open`。target `inspect` 仍静态报告三条
地址残差。不进 SupportClaim / manifest / evidence / inspect-output。

## 工程 DoD 与复现证据（2026-08-21）

Wave 1–3 的工程 DoD 已满足：

- PF-JCS schema / target join / duplicate 与 malformed negatives；
- 三叶有表消费与 missing-row FC；EVM empty-code void CALL FC；
- Solana Plan / IDL / IR / SBPF / client verifier 的 exact outer-role projection；
- Solana 支持子集的 program-level residual 清零，unsupported shape 保持 residual/FC；
- 两个独立 product-built ELF 的真实 generic CPI：成功 source-order commit；wrong
  account key、signer、writable、program key、executable 与 inner failure 均回滚；
- `sol_oneshot` 对 call-bind multi-role artifact 明确拒绝并指向 `pf test`。

已执行且通过：

```text
lake build ProofForgeV2.Targets.Solana.EmitSbpfAsmV1 \
  Tests.Materialization.CallBindV1 proof_forge_next
lake build Tests.Materialization.CallBindV1
lake env lean --run /dev/stdin <<'EOF'
import Tests.Materialization.CallBindV1
unsafe def main : IO Unit := Tests.Materialization.CallBindV1.run
EOF
(cd clients/solana-client && cargo test)  # offline suite 34 tests
scripts/solana_runtime_test.sh            # 含 call_bind_product 8 tests
git diff --check
```

这是 engineering product/runtime evidence，不是 formal TST、C-3、hermetic、release
qualification 或 ADR acceptance。

## Acceptance gate

owner `davirain` 已对 review commit
`239e335ac4272f7b292eb87c913e46c8c805c0b9` 的本版正文明确批准，
`openFindings: none`。本次 acceptance 是 owner directive，不声称 independent review，
也不以“测试通过”代签治理批准。

该批准不关闭 `B-CALL-SEM` 全表、formal / C-3 / Anvil lossless，不把 identity
digest 视为已验证，也不开放本 ADR 明列为 fail-closed 的 Solana shapes。
