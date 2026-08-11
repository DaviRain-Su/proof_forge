# Few-shot 01 — 代币化发票份额

## 用户输入（NL）

> 「登记一笔代币化发票份额：总量 500,000 份，单笔转让最多 10,000，
> 每 600 个块一个窗口，窗口内累计最多转 60,000，只有白名单地址能受让。」

## Agent 先输出字段表

| 字段 | 值 |
|---|---|
| assetName | Invoice → 程序名 `InvoiceShare` |
| totalSupply | 500000 → `init` supply |
| maxPerTx | 10000 → `init` perTx |
| windowCap | 60000 → `init` window |
| windowBlocks | 600 → 源码常量 |
| 初始白名单 | 链下，部署后 setAllow |

## Agent 产出的源文件要点

- 程序名 `InvoiceShare`（合法标识符）。
- 状态名随主题微调（`sharesIssued` 等允许），但类型/顺序与 golden 一致。
- 窗口常量 `600` 替换 golden 中的 `1000`。
- **不**加 invariant/proof；**不**加 String state；事件仅 UInt64 字段。

## 门禁

`check` 必须 `ok`；`build --target evm` 必须 `built … deployable=true`。
任一失败 → 按 system-prompt §6 修，最多 4 轮。

## 部署（运营机）

```bash
cast send --create <bin> $(cast abi-encode 'constructor(uint64,uint64,uint64)' 500000 10000 60000) …
```

## 操作动线

1. `issue(holder, 100000)`（owner）
2. `setAllow(recipient, 1)`（owner）
3. `transfer(recipient, 8000)`（holder，≤ perTx）✅
4. `transfer(recipient, 12000)` ❌ 超单笔
5. `transfer(stranger, 100)` ❌ 非白名单
6. 窗口内累计超 60000 ❌ 超窗口
