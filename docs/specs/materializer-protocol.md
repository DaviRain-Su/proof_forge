---
id: SPEC-MAT-001
title: Materializer、Plan 与 TargetIR 协议
status: proposed
owner: backends
updated: 2026-07-15
normative: true
---

# Materializer、Plan 与 TargetIR 协议

## 接口

```lean
class Materializer (target : TargetId) where
  Plan     : Type
  TargetIR : Type
  planSchema   : SchemaId
  targetIrSchema : SchemaId
  plan  : ResolvedProgram target → CodegenProfile target → CompileResult Plan
  validatePlan : Plan → CompileResult Unit
  lower : Plan → CompileResult TargetIR
  validateTargetIR : TargetIR → CompileResult Unit
  emit  : TargetIR → EmitContext → IO (CompileResult OutputSet)
```

`ResolvedProgram target` 带 resolver decisions，不存在从裸 `SemanticProgram` 调 plan 的
public API。每个阶段先构造完整值再验证；失败不返回 partial Plan/IR/OutputSet。

## Ownership

Plan 必须拥有 target 的：entry dispatch/ABI、logical-state layout、context/auth mapping、
host imports/syscalls、call/workflow/proof wiring、failure mapping、resource limits、artifact
sections 和 provenance inputs。Lower/emitter 只实现 Plan，不能重新查询 source AST、推断
storage、丢弃 requirement 或读取 network profile。

Phase 1 类型：

- `EvmPlan`：selectors/ABI、storage slots、dispatch、Yul operations、revert mapping。
- `SolanaPlan`：instruction schema、ordered account metas、owner/signer/writable、account
  layout、CPI/syscalls、ELF sections。
- `NearPlan`：exports、JSON/Borsh shape、KV keys、host imports、Promise graph、receipt commit。
- `NoirPlan`：public/private inputs、state pre/post relation、constraints、commitments、proof I/O。

未来 NEAR/CosmWasm/Soroban/ICP 只共享 `WasmModuleRecipe` 和 encoder，不共享 Plan。

## Plan Invariants

- 所有 semantic entries/state/effects 一一映射且有 origin。
- layout/selector/account/export/constraint identity 唯一。
- failure/commit/disclosure mapping 证明满足 resolved decisions。
- target limits、alignment、width、call depth、memory pages 已检查。
- Plan canonical serialization 不含 path/time/random/network。
- TargetIR 每个 instruction/section 可追溯到 Plan ID；无隐式 host import。

`planHash` 在 validatePlan 后计算；`targetIrHash` 在 validateTargetIR 后计算。schema 变化按
versioning 规格处理。

## Wasm Sharing Contract

`WasmModuleRecipe` 只包含 types/functions/memory/data/import/export/custom section 的结构化
编码请求；target Plan 已决定 ABI/storage/call/auth/resource。共享 encoder 只做 deterministic
index assignment、binary encoding 和 base structural validation，不注入 host 语义。

## ZK Contract

Noir/OpenVM 没有原生 ledger state 时，Plan 必须输出 `stateContinuity=external`、pre/post
state visibility/commitment 和 verifier binding。Aleo/Psy 的 ledger/finalization 属各自 Plan。
缺 settlement adapter 时 artifact 标记 non-deployable，不能包装成链合约。

## 错误与边界

`PF-PLAN-INVARIANT`、`PF-LOWER-INVARIANT`、`PF-SEMANTICS-MISMATCH`、
`PF-ARTIFACT-NONDEPLOYABLE`、`PF-SETTLEMENT-UNAVAILABLE`。覆盖空 entries、selector/
slot/account/export collision、unsupported width/import、layout overflow、private leak、commit
boundary mismatch、external state 未标记、unordered map emission、TargetIR dangling ref、
emitter 尝试 source/network access、partial output、tool failure、最大 sections/functions/data。

## 验收

关联 `FR-007`、`TST-MAT-001` 及四 target `TST-*-001..004`。编译期测试证明不同 Plan
不可互换；mutation tests 对每项 invariant 必须失败；Plan→IR→artifact 有完整 trace map。
