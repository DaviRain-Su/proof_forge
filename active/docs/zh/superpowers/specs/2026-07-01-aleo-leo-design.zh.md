# Aleo Leo 目标：Research 退出 + Spike 设计

**日期：** 2026-07-01  
**状态：** 设计规格（等待评审）  
**范围：** 仅文档设计，覆盖 `aleo-leo` Research 退出与第一个 Leo sourcegen spike；本轮不修改代码。  
**相关文档：**
- [Aleo Leo 目标说明](../../targets/aleo-leo.zh.md)
- [能力注册表](../../capability-registry.zh.md)
- [设计决策](../../decisions.zh.md)
- [验证门禁](../../validation-gates.zh.md)
- [可移植 IR](../../portable-ir.zh.md)
- [共享场景：计数器](../../shared-scenario.zh.md)

---

## 1. 目标

产出一份经过评审、文档优先的 Aleo 接入计划，将 Aleo 作为 ProofForge 的 `zk-app-sourcegen` 目标；然后设计第一个可运行的 spike：从现有的可移植 IR Counter fixture 生成一个 Counter 风格的 Leo 程序。

本规格覆盖：
1. `aleo-leo` 的 Research 退出标准。
2. 规范化能力提案。
3. Aleo Leo 包的制品清单 schema。
4. 工具链决策。
5. Spike 架构、文件结构、降级规则、CLI 扩展与冒烟测试流程。

本规格**不**包含实现代码，也**不**修改 `ProofForge.Target.Capability` / `ProofForge.Target.Registry`。

---

## 2. 执行摘要

Aleo 是一个 ZK-native 智能合约 L1，其执行模型分为两层：
- **Proof context**：私有、链下执行，可消费/创建 records 并生成 ZK 证明。
- **Finalization context**：公开、链上执行，读写 mappings 和 storage。

ProofForge 应将 Aleo 建模为**可部署程序包**目标，而不是通用 ZK 电路目标。最稳妥的第一边界是 **Leo source generation**，将 `.aleo` 指令、AVM 字节码、ABI 以及 prover/verifier 制品交给官方 `leo` 工具链处理。

第一个 spike 通过将现有的可移植 IR `Counter` 模块降级为一个带公开 `mapping` 和 `final` 块的 Leo 包，再用 `leo build` 和 `leo test` 验证，从而证明编译器边界可通。

---

## 3. 目标分类

| 属性 | 值 |
|---|---|
| 目标 id | `aleo-leo` |
| 目标家族 | `zk-app-sourcegen` |
| 制品类型 | `aleo-leo-package` |
| 状态 | Research 候选（spike 成功前仅文档） |
| 第一源码边界 | Leo |
| 更低层编译目标 | Aleo Instructions（`.aleo`） |
| 可部署执行制品 | Aleo VM 字节码 + ABI + prover/verifier 制品 |
| 本地验证 | `leo build`、`leo test`；可选 `leo test --prove`、`leo execute --print` |

后端模式：

```text
ProofForge 可移植 IR 子集
  -> 生成的 Leo 包
  -> leo build
  -> Aleo Instructions（.aleo）
  -> Aleo VM 字节码 + ABI + prover/verifier 制品
  -> leo test / 可选 leo test --prove / leo execute --print
```

与其他目标的区分：
- 不同于 `psy-dpn` 的 `zk-circuit-sourcegen`（Aleo 程序是合约，不只是电路）。
- 不同于 `zcash-shielded` 的 privacy UTXO ZK payment（Aleo 有可编程状态与 finalization）。
- 不同于 `starknet-cairo` 的 cairo-sourcegen（Aleo 使用 records、mappings 和 Aleo VM）。
- 不同于 `algorand-avm` 的 AVM sourcegen（Aleo VM ≠ Algorand AVM）。

---

## 4. Research 退出设计

### 4.1 能力提案

以下能力从候选提升为 **规范能力**，写入 `docs/capability-registry.zh.md`，足以支撑 Road 1 Counter spike。

| 规范能力 | 可移植含义 |
|---|---|
| `lang.leo` | Target 发射 Leo source packages。 |
| `vm.aleo_avm` | Target 运行在 Aleo VM 上。 |
| `artifact.avm` | Build 发射 Aleo VM 字节码。 |
| `artifact.aleo_abi` | Build 发射 Aleo ABI 元数据。 |
| `execution.finalize` | Program 有公开链上 finalization logic。 |
| `state.mapping` | 公开状态保存在 mappings 中。 |
| `input.public` | 函数输入是公开数据。 |
| `output.public` | 函数输出是公开的。 |
| `test.leo` | 验证使用 Leo tests。 |

以下能力仍作为**研究候选**，留给后续 spike：

| 候选能力 | 可移植含义 |
|---|---|
| `ir.aleo_instructions` | Build 发射或消费 Aleo Instructions。 |
| `proof.prover_key` | Build 或 execute flow 生成 prover 制品。 |
| `proof.verifier_key` | Build 或 deploy flow 记录 verifier 制品。 |
| `execution.transition` | Entry execution 生成 transition 和 proof。 |
| `state.record` | 私有状态保存在加密 records 中。 |
| `state.storage` | 公开状态使用 storage variables 或 storage vectors。 |
| `input.private` | 函数输入是私有 proof-context 数据。 |
| `output.private` | 函数输出默认私有。 |
| `program.import` | Program import 并调用另一个 Aleo program。 |
| `program.upgrade` | Deployment 支持显式 program upgrades。 |
| `transaction.execute` | Validation 可生成 execute transaction。 |
| `transaction.deploy` | Validation 可生成或检查 deploy transaction。 |
| `fee.credits` | Fees 以 Aleo Credits 支付，可 public 或 private。 |
| `test.aleo_devnet` | Validation 使用 Leo devnet 或 devnode-backed flows。 |

`zk.circuit` 刻意**不**用于 Aleo。它描述的是 Psy/DPN 风格的电路 source generation，无法涵盖 Aleo 的程序、状态、finalization 和 transaction 语义。

### 4.2 制品清单 Schema

`aleo-leo-package` 制品包含：

```text
aleo-leo-package
  - 生成的 Leo 源码（main.leo）
  - program id 和 imports
  - mapping / storage schema
  - proof-context entry functions
  - finalization manifest
  - 编译后的 Aleo Instructions（.aleo）
  - AVM 字节码
  - ABI JSON
  - prover/verifier 制品（spike 可选）
  - execute/deploy transaction 元数据（spike 可选）
  - leo build / leo test 验证结果
```

对应的 `proof-forge-artifact.json` 形态：

```json
{
  "schemaVersion": 1,
  "package": "counter",
  "target": "aleo-leo",
  "targetFamily": "zk-app-sourcegen",
  "artifactKind": "aleo-leo-package",
  "source": {
    "entryFile": "ProofForge/IR/Examples/Counter.lean",
    "module": "ProofForge.IR.Examples.Counter"
  },
  "proofs": {
    "checked": true,
    "warnings": []
  },
  "capabilities": [
    "lang.leo",
    "vm.aleo_avm",
    "artifact.avm",
    "artifact.aleo_abi",
    "execution.finalize",
    "state.mapping",
    "input.public",
    "output.public",
    "test.leo"
  ],
  "artifacts": {
    "leoSource": {
      "path": "build/aleo/counter/src/main.leo",
      "sha256": "...",
      "bytes": 0
    },
    "aleoInstructions": {
      "path": "build/aleo/counter/build/main.aleo",
      "sha256": "...",
      "bytes": 0
    },
    "abiJson": {
      "path": "build/aleo/counter/build/abi.json",
      "sha256": "...",
      "bytes": 0
    }
  },
  "toolchain": {
    "proofForge": "0.1.0",
    "lean": "4.31.0",
    "external": {
      "leo": "..."
    }
  },
  "targetMetadata": {
    "programId": "counter.aleo",
    "mappings": [
      { "name": "count", "keyType": "u64", "valueType": "u64" }
    ],
    "entrypoints": [
      { "name": "initialize", "publicInputs": [], "publicOutputs": [], "finalize": true },
      { "name": "increment", "publicInputs": [], "publicOutputs": [], "finalize": true },
      { "name": "get", "publicInputs": [], "publicOutputs": [], "finalize": true }
    ]
  },
  "validation": {
    "leoBuild": "passed",
    "leoTest": "passed",
    "leoTestProve": "skipped"
  }
}
```

说明：
- `targetMetadata` 是目标相关的。对于 Aleo，它记录 program id、mappings 以及 entrypoint 的可见性/finalization 元数据。
- prover/verifier 制品和 transaction 元数据在本 spike 中为可选，可记录为 `null` 或直接省略。
- Leo 4.0.2 的 `leo build` 输出 `main.aleo` 和 `abi.json`；不输出独立的 `.avm` 文件，因此 spike 的 artifact 列表中省略 `avmBytecode`。

### 4.3 工具链决策

| 门禁 | 工具 | spike 是否必需 |
|---|---|---|
| 源码生成 | `proof-forge --emit-counter-ir-leo` | 是 |
| Golden fixture 对比 | `diff` | 是 |
| 包布局 | `scripts/aleo/write-leo-package.py` | 是 |
| 编译为 Aleo Instructions | `leo build` | 是 |
| 运行单元测试 | `leo test` | 是 |
| 可选 prove 门禁 | `leo test --prove` | 否 |
| 可选 execute 元数据 | `leo execute --print` | 否 |
| 网络部署/执行 | devnet / devnode | 延后 |

主要本地验证路径是 `leo build` + `leo test`。Prove-heavy 门禁为可选，尤其在 CI 中。

### 4.4 Research 退出标准检查清单

Aleo 只有在以下全部文档化并评审通过后才能离开 Research：

- [ ] `docs/targets/aleo-leo.zh.md` 记录 `zk-app-sourcegen` 分类、非目标与退出标准。
- [ ] `docs/capability-registry.zh.md` 包含 4.1 节的规范能力表。
- [ ] `docs/decisions.zh.md` 包含一条决策（如 D-025），批准 `aleo-leo` 作为 `zk-app-sourcegen` Research 候选及 Leo-first 边界。
- [ ] `aleo-leo-package` 的制品清单 schema 已文档化。
- [ ] 工具链决策（`leo build` / `leo test` 为主）已文档化。
- [ ] 明确在 spike 成功且 proof/finalization split 审查完成前，**不**将 `aleo-leo` 加入 `ProofForge.Target.Capability` / `ProofForge.Target.Registry`。
- [ ] 文档化一个可重复的本地 smoke 命令或脚本，即使 prove-heavy 门禁在 CI 中可选。

---

## 5. Spike 设计

### 5.1 Spike 范围

- **仅 Road 1：** 带公开 `mapping` 的 Leo Sourcegen Package Counter。
- **IR 输入：** 复用 `ProofForge.IR.Examples.Counter.module`。
- **生成制品：** `Counter.leo` 包。
- **验证方式：** `leo build` 和 `leo test`。
- **不在范围内：** private records、transitions/proofs、direct Aleo Instructions、program imports、devnet 部署。

### 5.2 架构

```text
ProofForge.IR.Examples.Counter.module
  -> ProofForge.Compiler.Leo.Emit.emitModule
  -> ProofForge.Compiler.Leo.Printer.printProgram
  -> Counter.leo
  -> scripts/aleo/write-leo-package.py
  -> build/aleo/counter/{leo.toml, src/main.leo}
  -> leo build
  -> .aleo 指令 + ABI JSON
  -> leo test
  -> proof-forge-artifact.json
```

Spike 复用 Psy DPN sourcegen 模式：
- 一个 Lean 后端模块将可移植 IR 降级为目标源码。
- 一个 CLI flag 发射源码。
- 一个 golden fixture 纳入版本控制。
- 一个 shell 脚本编排包生成、工具链调用与元数据校验。

### 5.3 文件结构

#### 新增 Lean 模块

| 文件 | 职责 |
|---|---|
| `ProofForge/Backend/Aleo.lean` | 公开导出 `ProofForge.Backend.Aleo.IR`。 |
| `ProofForge/Backend/Aleo/IR.lean` | 对 `ProofForge.Compiler.Leo.Emit` 和 `ProofForge.Compiler.Leo.Printer` 的薄封装。 |
| `ProofForge/Compiler/Leo/` | 结构化 Leo AST（`AST`）、AST 打印器（`Printer`）以及 IR→AST 发射器（`Emit`）。 |
| `ProofForge/Aleo.lean` | 可选的未来 SDK 表面。本 spike 可为空或省略。 |

#### 新增示例与 golden fixture

| 文件 | 职责 |
|---|---|
| `Examples/Backend/Aleo/Counter.golden.leo` | Counter IR fixture 期望生成的 Leo 源码。 |
| `Examples/Backend/Aleo/README.md` | 说明 golden 文件如何生成与更新。 |

#### 新增脚本

| 文件 | 职责 |
|---|---|
| `scripts/aleo/counter-smoke.sh` | 端到端 smoke：生成 Leo → leo build → leo test → 写制品元数据 → 校验。 |
| `scripts/aleo/write-leo-package.py` | 根据发射的源码生成 `leo.toml` 和 `src/main.leo` 目录结构。 |
| `scripts/aleo/write-artifact-metadata.py` | 为 Aleo build 写 `proof-forge-artifact.json`。 |
| `scripts/aleo/validate-artifact-metadata.py` | 校验 Aleo 制品元数据 schema。 |

#### 更新的文档

| 文件 | 职责 |
|---|---|
| `docs/targets/aleo-leo.md` / `.zh.md` | 更新后的 Research 说明。 |
| `docs/capability-registry.md` / `.zh.md` | Aleo 规范能力。 |
| `docs/decisions.md` / `.zh.md` | D-025 批准。 |
| `docs/validation-gates.md` / `.zh.md` | `scripts/aleo/counter-smoke.sh` 命令。 |

### 5.4 与现有代码的关系

- **不修改** `ProofForge.IR.Contract`。
- **不修改** `ProofForge.Target.Capability` 或 `ProofForge.Target.Registry`。
- **扩展** `ProofForge.Cli`：新增 `--emit-counter-ir-leo` 模式（实现阶段再做，本轮只设计）。
- **参考** `ProofForge.Backend.Psy.IR` 的模块结构、错误处理与 golden fixture 模式。

---

## 6. 降级规则

### 6.1 Counter IR 到 Leo 的映射

输入模块（现有）：

```text
module Counter {
  state count: scalar U64

  entrypoint initialize() {
    effect storage.scalar.write("count", 0)
  }

  entrypoint increment() {
    let n = effect storage.scalar.read("count")
    effect storage.scalar.write("count", n + 1)
  }

  entrypoint get() -> U64 {
    return effect storage.scalar.read("count")
  }
}
```

输出形态（Leo 4.0，已通过 `leo build` 和 `leo test` 验证）：

```leo
program counter.aleo {
    mapping count: u64 => u64;

    @noupgrade
    constructor() {}

    fn initialize() -> Final {
        return final {
            Mapping::set(count, 0u64, 0u64);
        };
    }

    fn increment() -> Final {
        return final {
            let current: u64 = Mapping::get_or_use(count, 0u64, 0u64);
            Mapping::set(count, 0u64, current + 1u64);
        };
    }

    fn get() -> Final {
        return final {
            let current: u64 = Mapping::get_or_use(count, 0u64, 0u64);
        };
    }
}
```

说明：
- 标量 `U64` 状态映射为以固定 `0u64` 为键的公开 `mapping`，因为 Aleo mapping 需要显式 key。
- Leo 4.0 对所有 entry point 使用 `fn`。会改变状态的 entry point 返回 `Final`，并将逻辑嵌入
  `final { ... }` 块以在链上执行。
- 新程序必须包含 `@noupgrade constructor() {}` 以满足部署规则。
- `storage.scalar.read` 映射为 `final` 块中的 `Mapping::get_or_use(<name>, 0u64, 0u64)`；
  mapping 读取只允许出现在 finalization 上下文。
- `storage.scalar.write` 映射为 `final` 块中的 `Mapping::set(<name>, 0u64, <value>);`。
- `get` 不能从 transition 返回普通 `u64`，因为 transition 无法读取 mapping。它返回 `Final`，
  使 mapping 读取发生在 finalization 上下文。

### 6.2 通用降级规则（v0）

| 可移植 IR | Leo（v0） |
|---|---|
| `Module.name` | `program <name>.aleo { ... }` |
| 程序 constructor | `@noupgrade constructor() {}` |
| `StateDecl scalar U64` | 以 `0u64` 为键的 `mapping <name>: u64 => u64;`（Counter 专用） |
| 带副作用的 `Entrypoint` | `fn <name>() -> Final { return final { ... }; }` |
| 读取 mapping 的 `Entrypoint` | `fn <name>() -> Final { return final { ... }; }` |
| `storageScalarRead` | `Mapping::get_or_use(<name>, 0u64, 0u64)` |
| `storageScalarWrite` | `Mapping::set(<name>, 0u64, <value>);` |
| `add` / `sub` / 等 | `+` / `-` / 等 |
| `U64 literal` | `<value>u64` |
| `letBind` / `letMutBind` | `let <name>: <type> = <value>;` |
| `return` | `return <expr>;` |

实际降级在 `ProofForge.Compiler.Leo.Emit` 中实现：它先把 IR 转换为结构化的 Leo AST（`ProofForge.Compiler.Leo.AST`），再由 `ProofForge.Compiler.Leo.Printer` 输出兼容 Leo 4.0.2 的源码。AST 对齐 `ProvableHQ/leo crates/ast/src/`（v4.3.2），而打印器将 `async { }` / `Future<Fn(...)>` 降级为本地工具链支持的 `final { }` / `Final`。

### 6.3 被拒绝的 IR 节点

以下 IR 节点在本 spike 中由 Aleo 后端拒绝，因为所需能力不在范围内：

| IR 节点 | 缺失能力 |
|---|---|
| `eventEmit` / `eventEmitIndexed` | Aleo 事件能力尚未定义 |
| `crosscallInvoke*` | `program.import` |
| `nativeValue` | `fee.credits` |
| `storageMap*`（通用） | `state.mapping` 通用形式延后 |
| `storageArray*` | `state.storage` |
| `contextRead` | `input.public` / `output.public` 的 caller/env 映射尚未设计 |

每次拒绝必须产生 `LowerError`，包含目标 id、能力 id 以及可用的源码位置。

---

## 7. CLI 扩展

新增一个 emit mode：

```lean
| counterIrLeo
```

新增命令行选项：

```text
proof-forge --emit-counter-ir-leo [-o output.leo]
```

默认输出路径：`build/aleo/Counter.leo`。

实现函数签名（规划中）：

```lean
def compileCounterIrLeo (opts : CliOptions) : IO UInt32
```

行为：
1. 调用 `ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module`。
2. 降级失败时打印 `LowerError.render` 并返回非零退出码。
3. 成功时将生成的 Leo 源码写入输出路径。

---

## 8. 冒烟测试流程

### 8.1 `scripts/aleo/counter-smoke.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ALEO_OUT_DIR:-$ROOT/build/aleo}"
PROJECT_DIR="$OUT_DIR/counter"
LEO_FILE="$OUT_DIR/Counter.leo"
GOLDEN_FILE="${ALEO_GOLDEN:-$ROOT/Examples/Backend/Aleo/Counter.golden.leo}"
LEO_BIN="${LEO:-leo}"
METADATA_FILE="$PROJECT_DIR/proof-forge-artifact.json"

mkdir -p "$OUT_DIR"

lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" --emit-counter-ir-leo -o "$LEO_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$LEO_FILE"
fi

if ! command -v "$LEO_BIN" >/dev/null 2>&1; then
  echo "aleo-counter-smoke: leo not found. Install the Aleo CLI." >&2
  echo "aleo-counter-smoke: generated $LEO_FILE for inspection." >&2
  exit 127
fi

python3 "$ROOT/scripts/aleo/write-leo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$LEO_FILE" \
  --program-name "counter"

(
  cd "$PROJECT_DIR"
  "$LEO_BIN" build
  "$LEO_BIN" test
)

python3 "$ROOT/scripts/aleo/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture Counter \
  --source "$LEO_FILE" \
  --leo-project "$PROJECT_DIR" \
  --out "$METADATA_FILE" \
  --leo "$LEO_BIN"

python3 "$ROOT/scripts/aleo/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "aleo-counter-smoke: passed"
```

### 8.2 `scripts/aleo/write-leo-package.py`

职责：
- 创建包含包元数据的 `leo.toml`。
- 通过复制生成的源码创建 `src/main.leo`。
- 保持确定性布局，使 smoke 脚本可幂等运行。

### 8.3 `scripts/aleo/write-artifact-metadata.py`

职责：
- 为 `leoSource`、`aleoInstructions`、`avmBytecode`、`abiJson` 计算 SHA-256 和字节大小。
- 记录使用的能力。
- 记录工具链版本（如可获取 `leo --version`）。
- 按 4.2 节 schema 写 `proof-forge-artifact.json`。

### 8.4 `scripts/aleo/validate-artifact-metadata.py`

职责：
- 校验 JSON schema 版本。
- 校验必填字段：`target`、`targetFamily`、`artifactKind`、`capabilities`、`artifacts`、`validation`。
- 校验每个列出的制品路径存在且非空。
- 校验 `validation.leoBuild` 和 `validation.leoTest` 为 `"passed"`。

### 8.5 验收标准

- `lake build` 通过。
- `proof-forge --emit-counter-ir-leo` 生成的 Leo 与 `Examples/Backend/Aleo/Counter.golden.leo` 一致。
- `leo build` 成功。
- `leo test` 成功。
- 生成 `proof-forge-artifact.json` 并通过校验。
- 当 `leo` 未安装时，脚本以代码 `127` 退出并打印清晰提示。

---

## 9. 非目标

- 本轮不将 `aleo-leo` 加入 `ProofForge.Target.Registry`。
- 本轮不将 Aleo 能力加入 `ProofForge.Target.Capability`。
- spike 不实现 private records、transitions 或 proof generation。
- spike 不实现 direct Aleo Instructions 生成。
- spike 不实现 devnet/deploy/execute transaction 元数据。
- 不将 Aleo 仅建模为通用 ZK 电路目标。
- 不混淆 Aleo VM 与 Algorand AVM。

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| Leo 的 mapping/finalize 语法变化 | 高 | 保持生成源码最小化；根据工具链反馈更新 golden fixture 和降级规则。 |
| `leo` CLI 安装重或 CI 不可用 | 中 | 像 Psy DPN 一样将 Aleo smoke 设为可选。 |
| Counter IR 语义无法干净映射到 Aleo mapping | 中 | 先手写 Leo Counter 确认形态，再自动化降级。 |
| Aleo 需要显式 program id / address 处理 | 低 | 生成确定性的 `program counter.aleo`，并文档化任何 setup 步骤。 |
| Proving 在 CI 中太慢 | 低 | 保持 `leo test --prove` 可选；spike 仅依赖 `leo test`。 |

---

## 11. 后续工作

Spike 成功后，下一个里程碑：

1. **加入代码注册表：** 向 `ProofForge.Target.Capability` / `ProofForge.Target.Registry` 添加 `zkAppSourcegen` 家族、`aleoLeo` target profile 和规范能力。
2. **Private record 流程（Road 2）：** 扩展 IR 或新建 fixture，实现 record 的消费与创建。
3. **Prove/execute 门禁：** 将 `leo test --prove` 和 `leo execute --print` 作为可选 CI 门禁集成。
4. **Direct Aleo Instructions（Road 3）：** 评估是否为了编译器精度将 IR 直接降级到 `.aleo` 指令。
5. **Devnet smoke：** 添加 devnet/devnode 部署/执行验证。
6. **共享场景强化：** 确保 Counter 场景在 EVM、Psy DPN 和 Aleo 上均通过。

---

## 12. 决策请求

本规格请求批准以下决策：

1. `aleo-leo` 继续作为 `zk-app-sourcegen` 家族的 Research 候选。
2. 接受 4.1 节的规范能力。
3. 接受 4.2 节的制品清单 schema。
4. 接受 4.3 节的 Leo-first 工具链决策。
5. Spike 范围仅限 Road 1：从 `ProofForge.IR.Examples.Counter` 生成公开 mapping Counter。
6. 在 spike 成功前不做代码注册表变更。
