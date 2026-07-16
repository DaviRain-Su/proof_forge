# 教程：从零走 Product 路径（Counter → Ownable → Token → Remote）

状态：**产品教程（T4.2）**  
受众：只写可移植业务意图的新贡献者

这是推荐的 **零到多目标** 路径。源码全部在 `Examples/Product/`，使用 name-only
的 `entry`/`query`（不手写 EVM selector），且从不 import Solana/NEAR 链 Surface。

相关：

- [Examples/Product/README](../../../Examples/Product/README.md)
- [三目标 Counter 深教程](portable-contract-three-targets.zh.md)
- [编写模型](../authoring-model.zh.md) — selector 与 family-only 构造子
- 聚合门禁：`just product`

## 前置

```bash
# 仓库根目录
lake build
# 多目标脚本可选：solc、wat2wasm、cast
```

## 步骤 0 — Product 规则

```bash
just portable-default
```

确认 Product 源保持业务-only（无链 Surface、无 TokenStandard、无 Promise/CREATE2/selector 钉死）。

## 步骤 1 — Counter

**源：** [Examples/Product/Counter.lean](../../../Examples/Product/Counter.lean)

```bash
just portable-counter-multi-target
```

同一文件 → EVM bytecode · Solana sBPF · NEAR WAT。

## 步骤 2 — Ownable

**源：** Ownable / OwnablePausable

```bash
just portable-auth-materialize
```

## 步骤 3 — Token 意图

**源：** FungibleToken（只写 features，不写标准）

```bash
just shared-token-intent
just token-feature-matrix
```

## 步骤 4 — Remote

**源：** RemoteCall

```bash
just portable-remote-call-multi-target
```

## 步骤 5 — Auth + debit + remote

**源：** AuthRemoteCall

```bash
just portable-solana-accounts
```

## 一键

```bash
just product
```

## 检查清单

- [ ] `just product` 绿
- [ ] Product 源使用 **name-only** entrypoint
- [ ] 无 Solana/NEAR Surface import
- [ ] Token 只用 `TokenFeature`
- [ ] Remote 用 `remote` + `remoteCallRef`

分类规范见 [examples-and-tests-taxonomy.zh.md](../examples-and-tests-taxonomy.zh.md)。
