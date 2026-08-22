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
EVM 的 exact endpoint 同时进入 Plan schema / Plan digest / EngineeringBuildIdentity，
不是 emitter-only override；这不等于验证了可选 `identity` digest metadata。
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

**Wave 4（2026-08-21，EVM static artifact identity）**：EVM bind row 一旦带
`identity`，`build` 必须同时给独立 PF-JCS `--binding-evidence`。evidence 以
callee/address 映射到一个既有 engineering output directory；产品复用
`inspectEngineeringOutputDirV1` 重验 sidecar identity、逐文件 SHA-256、exact disk
closure 与 `outputSetDigest`，并把该 output 的 source/semantic 与 raw published
`{artifactProgramName}.bin` SHA-256 对回 bind row 的期望值。identity-bearing rows
的 canonical digest 进入 EVM Plan / plan digest / caller OutputSet provenance；无
identity 时不追加 Plan 字节，保持历史 bytes。该门只验证调用方提供的**静态
artifact/address attestation**；它不查 RPC、不读取 `EXTCODEHASH`，因此绝不声称
address 当前链上代码等于该 artifact。

**Solana local-output identity follow-on（2026-08-21 工程接线）**：Solana 表中每行
必须给出完整三 digest，并以 repeatable `--callee-output` 显式提供本地 callee output。
CLI 按 callee program name + manifest source/semantic digest + `{program}.so` raw-byte
SHA-256 exact join，再把 verified identity 保留到 caller Plan 的 `callBindProgram` role。
SVM runtime 仍只校验 programId/account key/executable 与既有账户权限，不证明链上
ProgramData、upgrade authority、当前 ELF 或部署过程。EVM 产品 ingress 继续只使用
`--binding-evidence`，不接受 `--callee-output`。

不关闭 `B-CALL-SEM` 全表。本 ADR 不自动接受其它 ADR；ADR-0036 已由同日另行
owner directive accepted，ADR-0051 仍 proposed。不改 `semantic-core.md`。不声称
formal / C-3 / Anvil lossless / CREATE / CREATE2。

## 背景

inspect 已诚实标出三条地址残差（2026-08-19 COMP-1-CALL-SEM-LAND）：

| Target | 静态 inspect residual | 有精确 bind row 的 product build |
|---|---|---|
| evm | `hashed-qn-no-deploy-bind` | 使用表中预置 20-byte address；全部 generic QN 覆盖后 program residual 可为 `null` |
| solana | `callee-identity-outer-account-open` | Wave 3 支持子集要求 exact local OutputSet/ELF identity join，保留三 digest 到 caller Plan，并使用 exact programId + outer AccountInfo join；其它形态保持 FC/residual |
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
- EVM 无 `identity` 字段 = 只绑地址，**不得**写成已 join 链上代码。Solana 每行
  必须有完整 identity 并由显式 local output exact join，但仍不得写成已 join 链上
  ProgramData/current ELF。
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
- EVM row 有 `identity` 时必须给 `--binding-evidence`；无 identity rows 时反而拒绝
  该 flag。Solana 必须给 repeatable `--callee-output`，且每行对唯一匹配 authority
  完整 join、所有提供的 authority 均被使用；该 flag 是 Solana-only。CosmWasm
  identity 仍是 parse-only metadata。EVM 不接受 `--callee-output`，Solana/CosmWasm
  不接受 `--binding-evidence`。

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
不 join。CosmWasm 的 `identity` 仍是 parse-only metadata。EVM 的 identity 必须由下节
evidence 闭合，且 `artifactSha256` 必填；`sourceHash` / `semanticHash` 若出现也必须与
inspected output 精确一致。EVM `artifactSha256` 定义为 finalizer 发布的
`{artifactProgramName}.bin` **原始文件字节** SHA-256（包含 publisher 写入的尾随换行），
不是 hex 解码后的 bytecode，也不是 `.yul`。

Solana product build 要求每行 `identity` 三字段全部存在，并以 repeatable
`--callee-output <dir>` 显式提供 fully inspected deployable Solana output。callee 的
倒数第二个 QN 分量必须等于 `artifactProgramName`；source/semantic 必须与 manifest
精确相等；`artifactSha256` 是 finalizer-owned `{artifactProgramName}.so` raw bytes
的 SHA-256。每行必须匹配恰好一个 authority，额外/重复 authority fail closed。verified
identity 写入 caller CPI Plan 的 `callBindProgram.callBindOutputIdentity`。这些字段
不进入 SupportClaim；runtime 也不据此读取 ProgramData 或 ELF bytes。

未知键、缺必填、跨 target 字段（例如 evm 行带 `programId`）、重复
`callee`（同一表内 exact QN）、空 `callee` 分量 → fail closed。

## Schema `proof-forge.call-bind-evidence.v1`（EVM only）

`build --target evm --bindings <bindings> --binding-evidence <evidence>` 的 evidence
也必须是 PF-JCS。根对象仍精确为 `bindings` / `schema` / `target`：

```text
{
  "bindings":[
    {
      "address":"0x1111111111111111111111111111111111111111",
      "callee":"Oracle.feed",
      "outputDir":"outputs/Oracle"
    }
  ],
  "schema":"proof-forge.call-bind-evidence.v1",
  "target":"evm"
}
```

| 字段 | 规则 |
|---|---|
| `schema` | 精确 `proof-forge.call-bind-evidence.v1` |
| `target` | 精确 `evm` |
| `bindings` | 恰好覆盖 `--bindings` 中全部且仅全部 identity-bearing EVM rows；duplicate / missing / extra callee fail closed |
| `callee` | 与 bind row exact QualifiedName 相同；其倒数第二个分量必须等于 inspected output 的 `artifactProgramName` |
| `address` | 与 bind row 同一精确 20-byte lowercase-hex endpoint；独立重复以捕获两输入分歧 |
| `outputDir` | evidence 文件父目录下的 canonical safe relative path；`..`、absolute、空分量等拒绝 |

每个目录必须通过既有 product output inspector：EVM target、`deployable=true`、
manifest/evidence identity、descriptor inventory、每个 artifact 原始字节 SHA-256、
固定 sidecars、无额外/缺失目录叶、`outputSetDigest` 重算全部精确一致。随后才比较
`sourceHash` / `semanticHash` / `{artifactProgramName}.bin` SHA-256。evidence 文档本身
不携带这些 digest，避免把 bind row 的期望值复制一遍后自证。

这里的 `address` 仍是调用者提交的静态映射；schema 没有 deployment receipt、block
identity、RPC endpoint 或 code-at-address observation。故通过该门只证明「本次 build
校验过这份 artifact output，且两份输入同意 callee/address」，不证明该地址在任何链上
已部署或仍运行这些 bytes。

## 非目标

- 不关闭 `B-CALL-SEM`（Noir witness、NEAR promise、TON message、ICP
  advertise 保持现状）。
- 不新增 Token/ATA generic call shape、wasmd rung-2、CREATE2、NetworkProfile。
- 不把通过静态 output-dir evidence 当成已验证的链上代码身份；不做 receipt / RPC /
  `eth_getCode` / `EXTCODEHASH` join。
- 不把 Solana local output/ELF digest 当成 ProgramData、upgrade authority、当前链上
  ELF 或 deployment proof。
- 不开放 Solana schedule、generic result-bearing CALL、empty-state / empty-row /
  multi-callee / mixed frozen-site outer join。
- 不改 Normalize / CheckV1 / Semantic wire。
- 不升格 formal TASK/TST。

## 后果

Wave 2 落地后：CLI 认识 `--bindings`；表可解码、可查 QN；有表时三叶
generic call/schedule 消费同一 `CallBindTableV1`（EVM Yul 地址、CW WAT
`contract_addr`、Solana program id / AccountMeta）。EVM exact endpoint 由 Plan 携带，
因此 bound/unbound Plan digest 与 engineering build / OutputSet identity 不同；同表
重复物化确定。无表的历史 Plan tags、hashed-QN Yul 与产品行为不变。
Wave 2a：generic void CALL 空账户 fail closed。Wave 3 对上列 Solana 支持子集完成
outer AccountInfo join，并保持 empty rows 为旧 partial path。Wave 2c 的成功 `build`
露出 program-level `callScheduleResidual`（string 或 `null`）：无 generic call、
EVM/CW 全覆盖、或 Solana Wave 3 支持子集全覆盖时为 `null`；其它 Solana
形态保留 `callee-identity-outer-account-open`。target `inspect` 仍静态报告三条
地址残差。不进 SupportClaim / inspect-output。Wave 4 的 EVM expected identity table
digest 进入 Plan digest，继而进入 caller 的 engineering build identity / manifest /
OutputSet；独立 evidence 文件和被检查 callee OutputSet 不复制进 caller 输出。
Solana local-output follow-on 则把 verified source/semantic/ELF digest 保留在 caller
Plan 的 `callBindProgram` role；callee OutputSet 同样不复制进 caller 输出。

## 工程 DoD 与复现证据（2026-08-21）

Wave 1–4 的工程 DoD 已满足：

- PF-JCS schema / target join / duplicate 与 malformed negatives；
- 三叶有表消费与 missing-row FC；EVM exact endpoint Plan/digest/build-identity
  绑定及 empty-code void CALL FC；
- Solana Plan / IDL / IR / SBPF / client verifier 的 exact outer-role projection；
- Solana 支持子集的 program-level residual 清零，unsupported shape 保持 residual/FC；
- Solana row identity 缺失/不完整、callee program name、target/deployability、
  source/semantic/raw `.so` digest mismatch、duplicate/unused output 全部 fail closed；
  成功 caller Plan 保留 exact 三 digest；
- EVM identity row 无 evidence、无 artifact digest、schema/target/callee/address/output
  mismatch、unsafe path、missing/extra/duplicate row、non-EVM/nondeployable output、
  source/semantic/artifact mismatch 全部 fail closed；canonical OutputSet 成功路径与
  `.bin` 落盘 mutation 逐文件重算负例已钉；
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

Wave 4 的推荐切片由 owner 在同一 Amp thread 以「按推荐」明确指示实施；实施基线为
`a581e879f43ca8394e86d69f69906ad2fd9de01a`。这同样不是 independent review；
frontmatter 的原始 acceptance `reviewCommit` 保留，不伪造成对 Wave 4 commit 的事后复审。
Solana local-output follow-on 也不改写该 review commit；focused/runtime 通过不代签新的
治理或 independent review。

该批准不关闭 `B-CALL-SEM` 全表、formal / C-3 / Anvil lossless，不把 static identity
evidence 视为 EVM code-at-address 或 Solana ProgramData/current ELF 验证，也不开放
本 ADR 明列为 fail-closed 的 Solana shapes。
