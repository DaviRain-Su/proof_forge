---
id: ADR-0043
title: Pinned WasmCert-Coq provider and NEAR host refinement boundary
status: proposed
owner: architecture
updated: 2026-08-13
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

在 per-platform Tool Lock v4 中存在可 provision 的
`wasmcert-coq-provider` executable、exact executable SHA-256、version probe 与依赖闭包之前，
`requireWasmCertProviderProvisionedV1` 必须返回 `executableUnprovisioned`。不得用 git revision、
本机 opam build、PATH 上的同名程序或上游 CLI 版本文本绕过该门。

### D2 — 只接结构化 wrapper，不 scrape 上游 CLI

未来 wrapper executable 固定名 `proof-forge-wasmcert-provider-v1`，调用形状为：

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

未来 provider consumer至少区分：

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

- 当前 NEAR assurance **不升级**：仍是四个 bounded MethodIR/typed-WAT recipe + finalized Wasm
  structural boundary，整体不是 fully target-refined。
- source pin 与 closed protocol可以先审计；不存在真实 executable 时 product仍机械 fail closed。
- 后续工作先实现/锁定 structured wrapper，再实现 bounded NEAR host 与四 recipe trace join；在这个
  NEAR阶段出口前不继续 Solana扩面。
- WasmCert parser、wrapper glue、OCaml compiler/runtime和 purpose-built host仍属于明确列出的 TCB/
  assumption边界；文档和 UI 不得用单一 `verified=true` 抹平这些差异。
