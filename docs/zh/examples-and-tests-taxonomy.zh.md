# 示例与测试分类（Product vs Backend）

状态：**规范（2026-07-09）**  
相关：[产品编写架构](../product-authoring-architecture.md)、
[编写模型](authoring-model.zh.md)。

## 产品主张

```text
作者只写：  业务逻辑
作者只选：  --target <id>
平台负责：  链上物化（ABI、账户、CPI、host、代币标准）
```

## 目录职责

| 路径 | 角色 | 谁关心 |
|------|------|--------|
| **`Examples/Product/`** | 可移植业务合约 + TokenSpec 意图 | 应用作者、产品 CI |
| **`Examples/Backend/`** | 链探针、golden、Source.Solana/NEAR fixture、研究 spike | 编译器 / 后端工程师 |
| **`Tests/Product/`** | 对 Product 源的多目标物化矩阵 | 产品主门禁（`just product`） |
| **`Tests/Backend/`** | Solana / EmitWat / Wasm host / Evm plan 探针 | 后端深度（`just backend`、`solana-light`…） |
| **`Tests/*`（IR/Cli/Sdk）** | 编译器内部、形式化、CLI | 工程 CI |
| **`ProofForge/IR/Examples/`** | 语义用 IR fixture（非作者教程） | 形式化 / IR 测试 |

## 硬规则

1. **Product** 源只 import `ProofForge.Contract.Source` 或 `ProofForge.Contract.Token`
   （以及作为业务策略组合的 stdlib mixin）。
2. **Product** 不得依赖 `Source.Solana`、手写 selector、CREATE2、Promise API
   （`just portable-default` 强制）。
3. **Backend** 可用链 Surface 与 golden diff；**不是**产品 API，不得主导教程。
4. 每个合约名只有一份业务源。链目录只放 **制品**（golden/manifest），不放分叉业务逻辑。

## 主命令

```bash
just product
```

会跑：

1. `portable-default`（Product 源保持业务-only）
2. `product-matrix` — `Tests/Product/Matrix.lean`（每个 Product 模块 × EVM · Solana · NEAR · Soroban；TokenSpec 诚实性）
3. 多目标 CLI 冒烟（Counter、RemoteCall）

后端探针：`just backend` 或 `solana-light` / `emitwat-ci-smoke`。

完整工程套件仍是 `just check`（product + backend + formal）。

## CI（Phase 5）

| 宿主 | 产品优先 | 全量 |
|------|----------|------|
| GitHub Actions | job **`product`**（required） | job **`build-test`**（`needs: [product]`） |
| Codeberg Woodpecker | 步骤 **`proof-forge-product`** | 步骤 **`proof-forge-check`**（`just check`） |

## Counter 单作者源（Phase 2）

| 模块 | 角色 |
|------|------|
| `Examples/Product/Counter.lean` | **作者源**（name-only entrypoint） |
| `ProofForge.Contract.Examples.Counter` | Spec 别名 → Product |
| `ProofForge.IR.Examples.Counter` | IR fixture：同**形状**；可为 formal/CLI 钉 selector / wrapping add |
| `Examples/Backend/*/Counter` | 薄 wrapper / golden only |

形状对齐由 `Tests/Product/Matrix.lean` 强制。

## 迁移说明

原 `Examples/Shared` 现为 `Examples/Product`。原 `Examples/{Evm,Solana,…}` 在
`Examples/Backend/` 下。
