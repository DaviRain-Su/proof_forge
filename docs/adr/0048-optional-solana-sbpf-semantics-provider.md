---
id: ADR-0048
title: Optional pinned Solana sBPF semantics provider boundary
status: proposed
owner: architecture
updated: 2026-08-14
normative: true
---

# ADR-0048：可选的固定 Solana sBPF semantics provider 边界

## Status

`proposed`（2026-08-14）。本提案不会改变 ADR-0036 的 EVM-first formal lighthouse，
也不会把当前 Solana engineering lane、Mollusk observation 或 bounded HandlerIR join
升级为 formal milestone。

## Context

ProofForge 已对 production `StateCell.get/initialize/increment` 闭合 bounded、kernel-checkable
`ReferenceMachineV1 → Plan/HandlerIR` join；当前边界仍停在 target `HandlerIR`，没有证明
assembly emitter、sBPF ISA、ELF、loader 或 Solana runtime。

在 ProofForge 内重新实现完整 sBPF/SVM semantics 会扩大可信计算基并制造一套未经独立复用的
target machine。公开仓库
[`DaviRain-Su/assembler-semantics`](https://github.com/DaviRain-Su/assembler-semantics)
已经提供 Lean 4 的 resolved sBPF instruction semantics、small-step runner、memory/host dialect、
observation 与 instruction encode/decode API；其 stable import 是 `SbpfSemantics.Api`。但它不提供
`.s` parser、label resolver、ELF reader、Solana account serializer 或完整 SVM host。

因此合理边界不是用 provider 替换 ProofForge materializer，而是由 ProofForge 对自己的
production lowering 负责，把已经 resolved 的 instruction program交给 provider解释。

## Decision

### D1 — source authority 与精确 pin

首个候选 provider 固定为：

```text
repository  https://github.com/DaviRain-Su/assembler-semantics
revision    ef6e20c20827e4158e1cb025518465aa8beb46da
package     assembler-semantics 0.1.0
import      SbpfSemantics.Api
lean        leanprover/lean4:v4.31.0
license     MIT
```

只能使用 40 位 revision；禁止 branch、tag、range、ambient sibling checkout、symlink 或
runtime fallback。依赖方向只能是 ProofForge → provider；provider不得 import ProofForge。

**本文件在 `proposed` 状态下只固定候选决定，不授权修改 `lakefile.lean` /
`lake-manifest.json`。** 只有本 ADR 依照文档协议变为 `accepted` 后，才能把 exact git pin
加入 Lake 和相应供应链闭包。

### D2 — 唯一 lowering authority

ProofForge继续唯一拥有：

- `SemanticProgramV1`、`ReferenceMachineV1` 与业务 outcome；
- Solana Plan、`HandlerIR`、account/input/return-data layout；
- production sBPF assembly/ELF materializer；
- HandlerIR/L1 assembly → resolved instruction 的 label、offset、constant 与 syscall resolution。

provider只拥有 resolved `Array Instr` 的 ISA execution meaning、memory primitives、host dialect
interface、observation 和 encode/decode。不得在 bridge 中重建 DSL callable、业务 state transition、
rollback、effect ordering 或第二套 checked-arithmetic contract。

首个 adapter 必须消费**同一个 production lowering authority**。允许的实现是：把 production
emitter 重构为共享的结构化 instruction source，再由一个 renderer产生当前 `.s`，由薄 adapter
投影到 `SbpfSemantics.Instr`。禁止独立编写一条仅供证明使用的
`HandlerIR → SbpfSemantics.Program` 平行 codegen，也禁止通过易漂移的字符串 substring goldens
冒充 instruction identity。

### D3 — 产品 ELF rail 保持独立

现有产品路径保持：

```text
Plan → HandlerIR → production .s → locked sbpf → .so
```

formal/trace lane只在相同 lowering source上增加：

```text
shared resolved instructions → SbpfSemantics.Api → observation
```

provider不得成为产品 build fallback，不得替代 locked `sbpf`，也不得让 provider execution成功
自动授权 ELF、deployment 或 runtime maturity。缺 provider 或 pin不匹配时 formal/trace lane
fail closed；普通产品 materialization行为不变。

### D4 — 首个 bounded slice

首个接线只覆盖现有 closed StateCell recipes：

1. `get()`：exact discriminator/account/header/data-length checks、state load、8-byte return；
2. `initialize(initial)`：参数 load、state write、initialized marker、success exit；
3. `increment(delta)`：state/param load、checked add、store、8-byte return；
4. increment overflow：exact nonzero program error与pre-account observation rollback。

ProofForge-owned input adapter必须构造真实 single-account Loader V3 ABIv1 bytes，而不是用 provider
示例中的 `InputCell` 代替 production layout。`sol_set_return_data` 可使用 provider default host；
其余 syscall、CPI、multi-account、compute metering 与动态 loader行为在本 slice 全部 fail closed。

最终 theorem形状应连接现有 target evaluator，而不是越过它另连业务语义：

```text
production HandlerIR observation
        ↕
shared lowering → SbpfSemantics execution observation
```

再与已经闭合的 Reference→HandlerIR theorem组合。provider内的 concrete `native_decide` examples
不构成 ProofForge theorem；ProofForge新增证明不得使用 `native_decide`、`sorry`、用户 axiom 或
`unsafe theorem`。

### D5 — mechanization status 与非声明

固定 revision 的准确边界：

| 层 | 状态 |
|---|---|
| resolved instruction small-step / executable runner | provider Lean定义 |
| flat rodata/stack/heap/input memory与LE loads/stores | provider Lean定义 |
| default return-data host subset | provider Lean定义；不等于完整 Solana host |
| instruction encode/decode | provider提供；symbolic syscall relocation不在raw round-trip内 |
| `.s` parse / labels / relocations | provider不提供，ProofForge须从production structured source解析 |
| Loader V3 account serialization | ProofForge-owned adapter obligation |
| ELF/linker/loader/SVM/runtime correctness | 未证明 |
| compute units/CPI/crypto/sysvars | 首切不支持 |

因此即使首切完成，准确声明也只能是 bounded
`HandlerIR → resolved sBPF semantics observation`；不能称 `.so`、Mollusk、validator或Solana
runtime已经被形式化验证。

## Acceptance gates

本 ADR 变为 accepted 并开始接线前/后必须分别满足：

1. exact revision、license、Lean toolchain与 stable API重新核验；
2. Lake manifest使用exact git revision，供应链闭包精确更新；
3. production `.s` 与 provider program来自同一个结构化 lowering source；
4. StateCell四条 bounded observation全部有kernel theorem与tamper fail-closed tests；
5. provider missing/revision drift/API drift不得降级为工程 golden或跳过；
6. ordinary product `.s`/`.so` exact behavior与现有 Mollusk lane不回归；
7. 文档继续区分 HandlerIR/sBPF semantics/ELF/runtime四层声明。

## Alternatives rejected

- **ProofForge自造完整sBPF/SVM semantics**：重复外部ISA工作，扩大TCB与维护面。
- **直接解释HandlerIR并称为sBPF proof**：现有HandlerSemantics已经解释HandlerIR，不能代签lowering。
- **解析最终`.s`字符串作为首选authority**：可做独立交叉检查，但不能替代结构化production source。
- **把provider接进普通产品fallback**：改变materializer行为并混淆formal/engineering成熟度。
- **直接证明ELF/runtime**：当前provider没有ELF、loader、account runtime或Agave compatibility证明。

## Consequences

- 下一代码切片先建立共享structured instruction source，再接 provider，而不是立即新增第二codegen。
- Solana bounded lane可以逐层向下推进，同时不改变EVM-first formal scope。
- 在本ADR accepted之前，仓库保持无 `assembler-semantics` Lake dependency；当前成果仅是
  decision-complete proposal与source audit。
