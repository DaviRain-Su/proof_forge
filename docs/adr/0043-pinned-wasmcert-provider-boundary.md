---
id: ADR-0043
title: Pinned WasmCert-Coq provider and NEAR host refinement boundary
status: proposed
owner: architecture
updated: 2026-08-14
normative: true
---

# ADR-0043：固定 WasmCert-Coq provider 与 NEAR host refinement 边界

## Status

**proposed**（2026-08-13）。本决定延续 [ADR-0042](0042-proof-bearing-near-invariant-root-erasure.md)
和 Phase 7 target refinement；不改变 `SemanticProgramV1 + ReferenceMachineV1` 的唯一业务语义。

## Context

VerifiedVault 的 `status/init/deposit/withdraw` 已从 retained semantic 经 production Plan/MethodIR
连接到 bounded typed-WAT evaluator，finalized Wasm 也有 exact digest/provenance 与 section-envelope
结构门。但结构门不解析 section payload，不验证 module typing，也不执行 Wasm；自行在 Lean 中重写
完整 Wasm opcode/runtime semantics 会制造一套高成本且未经外部验证的新 target machine。

WasmCert-Coq 提供 Wasm relational semantics、可执行 type checker/instantiator 和从 Coq 提取的
interpreter。它适合作为 target execution authority，但其 binary parser 被上游明确标为
experimental/unverified，默认 OCaml host 也只是实验实现。上游 `wasm_coq_interpreter` 输出为面向
人的文本（可能含 ANSI），没有稳定的 machine certificate protocol。因此“CLI exit 0”不能成为
ProofForge target-refinement evidence。

## Decision

### D1 — 固定 source authority，不伪造 executable authority

首个 source pin 为：

```text
repository  https://github.com/WasmCert/WasmCert-Coq
release     2.2.1
revision    9ab0f87f03fff5507749efc273ec662fe27e6d14
upstream    wasm_coq_interpreter
```

Lean 常量位于 `Targets/Near/WasmCertProviderV1.lean`，供应链注解位于
`supply-chain/wasmcert-coq-authority.v1.json`。该 pin 只证明选中了哪份 source/schema；它不是
二进制 hash、Tool Lock entry、构建可复现性或执行结果认证。

现在两个 per-platform Tool Lock v4 都含可 provision 的 `wasmcert-coq-provider`、平台独立的
executable SHA-256、exact version probe 与依赖闭包；资产来自 durable prerelease
`wasmcert-provider-v1.0.0-rc.1`。`requireWasmCertProviderProvisionedV1` 只选择 active platform 的
admitted digest；product还必须从 Tool Root resolve、rehash并要求二者相等。不得用 git revision、
本机 opam build、PATH 上的同名程序、另一平台 hash或上游 CLI 版本文本绕过该门。

### D2 — 只接结构化 wrapper，不 scrape 上游 CLI

wrapper executable 固定名 `proof-forge-wasmcert-provider-v1`，调用形状为：

```text
proof-forge-wasmcert-provider-v1 \
  check-execute --request <request.pf-jcs.json> --result <result.pf-jcs.json>
```

argv 逐元素传递，不经 shell。stdout/stderr 只能是诊断，不能作为 evidence。request 与 result
必须是 canonical PF-JCS、closed field set、duplicate/unknown/missing field fail closed；schema
分别是 `proof-forge.near.wasmcert-request.v1` 和
`proof-forge.near.wasmcert-result.v1`。

request 精确字段：

```text
fuel, inputWasmPath, inputWasmSha256,
invocationPath, invocationSha256,
providerRevision, schema
```

`invocationSha256` 绑定另一个 canonical invocation artifact；它必须包含 export、raw input、
完整 NEAR context、pre-storage、expected host profile 和 observation policy。不得让 wrapper 从环境
变量、当前目录或 mutable implicit default 补 semantics-bearing 输入。

result 精确字段：

```text
argv, checkerStatus, executableSha256, executionStatus,
hostProfile, hostTraceSha256, inputWasmSha256,
instantiationStatus, invocationSha256, observationSha256,
parserStatus, providerRevision, schema, simdUsed
```

result 是 **provider record，不是 certificate**。consumer 必须重算 request/result exact file hash，
检查 tool/executable/argv/input/invocation identity，并独立打开 host trace 与 observation artifact；
仅仅能 parse result 不得 mint `target-refined` evidence。

`Targets/Near/WasmCertWireV1.lean` 已实现上述 request/result 的 canonical PF-JCS codec 与
identity/status candidate join：非 canonical JSON、unknown/duplicate/missing field、非法相对路径、
digest 漂移、非 bounded fuel、parser/checker/instantiation拒绝、非 terminal execution和 SIMD 都
fail closed。该 join 故意不把任意 `executableSha256`升级为 Tool Lock identity；product consumer
仍必须先通过 `requireWasmCertProviderProvisionedV1`并独立 resolve locked executable。因此 codec
round-trip或脱离 locked execution的 candidate join成功都只证明严格 record plumbing，不证明
WasmCert运行或 record为真。

`Targets/Near/WasmCertArtifactsV1.lean` 现进一步实现 invocation、host trace 与 observation 三种
canonical artifact。invocation逐字段携带 export/raw input、完整 strict-profile NEAR context、
canonical pre-storage 与 observation policy；trace只允许首批九个 NEAR imports，并固定 dense event
index、host i64 arguments/result、逐调用 raw payload及 ABI arity/length shape；observation固定 terminal
status、trap分类、return/log/promise/post-storage。三者均有 closed nested schema、lowercase hex、逐项与
aggregate资源上限、32 MiB wire上限；storage key必须按 raw bytes严格递增且唯一。content-level
candidate join会重算三个 exact-byte SHA-256，连接 request/result identity，校验 input和
`attached_deposit` trace payload，并固定 trap rollback与view no-write/no-promise policy。它只把结果投影
到既有 passive `CallObservationV1`，不定义另一套 invocation→outcome step，也仍不证明 provider运行。

ProofForge-owned overlay 现位于 `tools/wasmcert-provider/`，由
`scripts/build_wasmcert_provider_v1.sh` 导出 exact upstream revision、替换单一 Dune/source overlay，
并直接调用 extracted `run_parse_module_str`、`module_type_checker`、
`interp_instantiate_wrapper`、`run_one_step`，不解析 human CLI。首个 strict host只实现上述九个
imports，拒绝其他 import/type、SIMD、table/global/start、`memory.grow`、非单一 bounded memory、
view write及资源越界。最终审计候选来自 run `31766677105`：Darwin/Linux均完成2/2 clean
same-platform byte-identical build；executable SHA-256分别为 `696b55dd…99842` 与
`c08b1622…15919`。发布后的原始 archive又从公开 release URL重下载并按 exact size/SHA-256复核，
随后才分别进入对应 Tool Lock；较早的本地或首轮候选 hash没有授权力。

build recipe现只接受 native `linux-x86_64`/`darwin-arm64`，以 Python SHA-256替代 Darwin缺失的
GNU `sha256sum`，并提供 `--repeat-check`：从两个独立 clean export/build目录构建，只有 executable
逐字节相等才原子发布。build命令只生成**新候选**，不会修改既有 Tool Lock或替换当前 admitted
identity；后续版本仍必须重新经过双平台 closure审查、durable发布和独立 admission。

手动 workflow `.github/workflows/wasmcert-provider-candidates.yml` 使用 Ubuntu/macOS 14 native矩阵，
从 exact source revision和 package-version lock建立 OCaml switch，并对每个平台执行上述双构建门。
`package_wasmcert_provider_candidate_v1.py` 随后记录完整 installed package/repository observation、
version probes与 build-input hashes；Linux以 `readelf`+`ldd`拒绝非 system-root依赖，Darwin以
`otool`递归收集所有非系统 dylib到 candidate closure。每次新上传的 candidate archive仍明确携带
`toolLockAdmitted=false`与`productActivated=false`；只有本 ADR记录的 rc.1 release bytes经独立
Tool Lock变更获得授权，workflow success本身永不自动 admission。

Lean consumer 又在 artifact structural validation 后确定性 replay register/storage/read/write/
return/log/panic host trace，并把 replay结果与 call-boundary observation连接。真实 finalized
`VerifiedVaultPF.wasm` 已在本地 provider 上执行 `init/deposit/withdraw/status/withdraw-overdraw`
五个 case；每个 validated observation随后只由 sole `stepReferenceSliceV1`重新执行同一 exact
semantic subject，并比较返回值、两字段 production storage与 failure rollback。Python smoke不再
手写业务 post-state oracle；业务期望只来自 `ReferenceMachineV1`。这是 executable engineering
join及篡改负例，不是 kernel 中的一般 Wasm simulation theorem。

`Targets/Near/WasmCertProductV1.lean` 现已实现 locked product consumer，但仍位于上述 activation
gate 之后。consumer只接受 capability-bound `FinalizedArtifactsV1` 与 exact NEAR Wasm closure；在
读取 staging artifact 之前先要求显式 activation、Tool Lock resolve/rehash与 exact version probe，
随后 sole disk scanner要求 finalized base+Wasm构成 exact regular-file closure，并逐个把 base bytes
接回 materialized carrier；Wasm digest在二次 stable read后仍须等于 closure observation。然后才在
exclusive temporary directory和 clean environment中以 frozen argv运行 provider。成功输出
必须形成 input/invocation/request/result/trace/observation 六个 single-link regular file的 exact
bounded closure，三个输入逐字节保持不变，三个输出通过 canonical decode、digest join和 host replay。
最终 private execution observation绑定 active Tool Lock platform/digest、provider id/version/executable
digest、source/semantic/finalized-Wasm、fuel以及全部 request/result/trace/observation digests。该对象是
identity-bound engineering execution observation，不是通用 target-refinement theorem，也不直接复制
Reference business semantics。当前双平台 admitted closure、activation digest与真实 consumer均已
接线；missing、unprovisioned、executable/runtime tamper仍在任何 observation acceptance前 fail closed。

### D3 — mechanization status 必须逐层保留

固定 revision 的边界为：

| 层 | 状态 | 上游依据 |
|---|---|---|
| binary parser | `unverified` | README 明确称 binary parser experimental/unverified；`run_parse_module_str` 只返回 option |
| module checker | `provedSoundOnSuccess` | `module_type_checker_sound`；instruction checker有 `b_e_type_checker_reflects_typing` |
| instantiation | `provedSoundOnSuccess` | `interp_instantiate_imp_instantiate`、`interp_alloc_sound` |
| interpreter core | `provedInterpreterCore` | dependent `run_one_step_ctx` 与 `t_progress_interp_ctx` |
| host | `hostAssumptions` | extraction要求 host application extension/typing/respect assumptions |

任一 result 必须逐字记录 parser/checker/instantiation/execution/host status。binary parser 成功不能被
改写为 “verified decode”。默认 `ocaml_host.ml` 使用实验实现，不得进入 NEAR acceptance。首个
strict profile还必须要求 `simdUsed=false`；SIMD extraction override不属于本阶段证明边界。

### D4 — purpose-built NEAR host，不复制 business semantics

允许新增的 target 层只有：

1. finalized bytes / independent envelope 与 WasmCert module 的 translation witness；
2. 实现 WasmCert host assumptions 的 bounded NEAR host；
3. host-call trace 与 canonical storage/return/log/promise observation；
4. 该 observation 到现有 `ReferenceMachineV1` outcome 的 refinement theorem。

禁止新增 DSL State、Effect、invocation→outcome step、合约 registry 或 VerifiedVault 专用
interpreter。NEAR host只实现已选择 recipes实际需要的 imports，并对 unknown import、unsupported
memory shape、SIMD、resource exhaustion、malformed trace全部 fail closed。

### D5 — fail-closed 分类与 activation 顺序

provider consumer至少区分：

```text
unprovisioned / tool-identity / request-identity / malformed-record
parser-rejected / checker-rejected / instantiation-rejected
unsupported-import / host-contract / exhaustion / provider-internal
trace-mismatch / observation-mismatch
```

Wasm trap 是 execution terminal observation，不自动等于 provider failure；正负 recipe由后续
Reference join判断 expected returned/reverted/trapped。activation顺序固定为：Tool Lock resolve与
rehash → exact request identity → isolated provider run → result canonical decode与identity join → trace/
observation decode → Reference refinement。任一步失败都不得发布 partial target-refinement evidence。

## Upstream source evidence

固定 revision 上的重要入口/定理：

- `theories/extraction_instance.v`：`run_parse_module_str`、`run_one_step`、
  `interp_instantiate_wrapper`、`invoke_extern`；
- `theories/instantiation_func.v`：`module_type_checker`、`interp_instantiate`；
- `theories/type_checker_reflects_typing.v`：`b_e_type_checker_reflects_typing`；
- `theories/interp_instantiate_sound.v`：`module_type_checker_sound`、
  `interp_alloc_sound`、`interp_instantiate_imp_instantiate`；
- `theories/interpreter_ctx.v` / `theories/type_progress.v`：`run_one_step_ctx`、
  `t_progress_interp_ctx`；
- `src/parse.ml`、`src/execute.ml`、`src/wasm_coq_interpreter.ml`：当前 human CLI glue；
- `src/ocaml_host.ml`：不得采用的实验 host。

许可证按 upstream `LICENSE.txt` 记录：主体 MIT，`src/Parray/` 与 `compcert/` 为
LGPL-2.1-or-later；不能只复制 opam 的简化 MIT 字段。

## Consequences

- 当前 NEAR assurance **不升级为 formal target-refined**：四个 bounded MethodIR/typed-WAT recipe、
  finalized Wasm structural boundary与 locked WasmCert executable/host/Reference join已经贯通，但
  parser仍未验证，且没有一般 IR/WAT→Wasm simulation theorem。
- source pin、closed protocol、canonical artifacts、provider overlay、host replay和五 case join均可
  审计；isolated locked consumer从 exact `VerifiedVaultPF.lean`重新认证、materialize/finalize，再由
  `executeLockedWasmCertV1`和`joinLockedWasmCertReferenceV1`跑通五条路径，不消费预制业务 oracle。
- Linux provider仅动态依赖系统 `libgmp`、`libm`、`libc`与 loader；它们落在 Tool Lock既有
  system dependency roots内。Darwin arm64 closure则显式携带 exact `lib/libgmp.10.dylib`，并由
  Mach-O policy绑定唯一 external edge。
- activation digest API按 `darwin-arm64`/`linux-x86_64`持有两个不同 row，且各自等于对应 lock
  executable pin；source revision、archive digest、canonical lock identity和executable digest保持
  不同概念，不能互相冒充。
- NEAR本阶段的双平台 provisioning/activation/consumer出口已经实现，并进入 Linux主CI与
  macOS 14独立 lane。translation、unverified parser、host与adapter assumptions仍必须明示；下一步
  可按路线恢复 Solana bounded target slice，而不能把本出口宣传成一般 Wasm/NEAR formal refinement。
- WasmCert parser、wrapper glue、OCaml compiler/runtime和 purpose-built host仍属于明确列出的 TCB/
  assumption边界；文档和 UI 不得用单一 `verified=true` 抹平这些差异。
