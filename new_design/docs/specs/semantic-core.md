---
id: SPEC-SEM-001
title: 目标中立语义核心
status: proposed
owner: semantics
updated: 2026-07-15
normative: true
---

# 目标中立语义核心

## 数据结构

`SemanticProgramV1` 包含 canonical types、logical state、callable CFG、events/errors、
invariants、requirements 和 origin map，不包含 target/profile/network、ABI selector、
storage slot、account meta、Wasm import、circuit opcode 或 deploy address。

CFG block 参数采用 SSA value ID；state 操作仍为显式 logical `load(path)`/`store(path,value)`；
ordered effects 使用单调 `EffectId`。Value ID、block ID 按 source traversal 分配并在
canonicalization 时重编号，避免 hash 受内部 hash-map 顺序影响。

## Reference Semantics

```lean
def step
  (p : SemanticProgramV1)
  (pre : LogicalState)
  (invocation : Invocation)
  (responses : ExternalResponses) : Outcome
```

执行顺序严格从左到右。所有 state write 写入 transaction overlay；`returned` 原子提交，
`reverted/trapped` 丢弃 overlay 并返回 pre-state。event/call/schedule 先进入 ordered effect
buffer，仅在 returned 时成为 committed effects。同步 external call 从 `responses` 按
EffectId 消费，缺失/多余/类型错误均 trap；schedule 只产生 workflow intent。

`assert false else E` 与 `revert E` 产生 named revert；算术错误产生标准 semantic error；
内部不变量破坏、无效 IR 或 resource exhaustion 为 trap。Target 可使用不同低层错误形式，
但 normalized outcome 必须保持 status/error class/state/effect ordering。

## 初始化与调用

未初始化 state 不能接收 entry/view。init 从 canonical zero/empty logical state 开始，成功
后置 `initialized=true`；再次 init revert。view 在独立只读 snapshot 上执行，任何 Core
write 是 validator error。entry name 与参数必须 exact match，没有 fallback dispatch。

## Canonical Serialization

格式为 length-prefixed binary `pf.semantic.v1`：固定 little-endian integers、NFC UTF-8、
array 保留语义顺序、set/map 按 canonical key bytes 排序；禁止 float、host pointer、时间、
absolute path。`semanticHash = SHA-256(serializedBytes)`。Unknown required field/version 必须
拒绝；reader 可忽略显式标记的 optional extension field。

## Normalization

source AST 先完成 type/effect，再消除语法糖、显式插入 checked operations、统一 match/
loop CFG、计算 requirement origin，最后 validate。Normalization 必须 total on TypedProgram；
内部失败为 `PF-SEMANTIC-INTERNAL` 并视为 compiler bug，不得生成部分 Core。

## 不变量

- 所有 ID 唯一且引用存在；CFG 有入口、终结块、无不可达 side effects。
- 类型 exact；phi/block 参数 arity/type exact。
- state path 类型正确；view 无 write；effect ID 严格递增。
- loop/call graph bound 已证明；private flow 已验证。
- requirement 集与实际 operations 双向一致：每个 op 有 requirement，每个自动 requirement
  至少一个 origin（program-level invariant 除外）。

## 错误与边界

`PF-SEMANTIC-INVALID` 外部/反序列化 Core 违反不变量；`PF-SEMANTIC-INTERNAL` 编译器
生成无效 Core；`PF-SEMANTICS-MISMATCH` target normalized observation 不等价。覆盖 zero
state/callable、最大 CFG、unreachable blocks、duplicate IDs、bad phi、effect reorder、
missing response、extra response、nested revert、event-before-revert、call failure、init twice、
view snapshot、Map absent、integer extrema、serializer order/path independence、unknown schema。

## 验收

关联 `FR-004/005`、`TST-SEM-001..003`。Counter、Map、event、external failure 和
bounded loop model tests 必须可执行；serializer golden + roundtrip + property tests；四目标
normalized Counter trace 与 reference 完全一致。
