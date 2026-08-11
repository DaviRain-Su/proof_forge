# ProofShip · rwa-share-v1

> **AI drafts the rules. The gate checks. Then it ships to X Layer.**
> 首发 vertical：AI-RWA 受限份额登记与转让。引擎：ProofForge。

这是 ProofShip 黑客松竖切的唯一业务模板目录（P0 local-first 形态）。
品牌/定位/阶段：[`docs/product/proofship-positioning.md`](../docs/product/proofship-positioning.md) ·
竖切规划：[`docs/plan/ai-rwa-verified-ship-xlayer.md`](../docs/plan/ai-rwa-verified-ship-xlayer.md) ·
执行清单：[`docs/plan/proofship-execution.md`](../docs/plan/proofship-execution.md)。

## 布局

```text
rwa-share-v1/
  src/RwaShareRegistry.lean     ← golden 部署模板（EVM；无 invariant）
  src/InvoiceShare.lean         ← AI 生成变体样例（few-shot 01 的产物形态）
  proof-twin/
    ShareConservation.lean      ← certified 正例（issued == distributed 守恒族）
    EvenStep.lean               ← certified 正例（parity 族）
    EvenStepBad.lean            ← 快速负例（缺定理 → 拒绝 + 零制品）
  ai/
    system-prompt.md            ← Agent 生成契约（白名单/禁止清单/修复环）
    fewshot/01-invoice.md       ← NL → 字段 → 源 → 门禁 → 动线
    fewshot/02-repair-loop.md   ← 真实修复环（D1 诊断逐字）
  scripts/                    ← 产品流水线（门禁 / 本地链验收 / 部署 / 产物）
    gate.sh                     ← 单命令门禁：check → build --target evm → inspect
    anvil-check.sh              ← 本地链验收 9 场景（正负路径）
    proof-gate.sh               ← 双 certified + 拒绝 + 零制品
    deploy-testnet.sh           ← X Layer testnet 部署（opt-in，env 持钥）
    build-dapp-artifacts.sh     ← 复跑全部门禁并刷新 dapp 产物 + gate-report.json
  dapp/                         ← 产品前端（Vite + React + viem）
    Launch Studio 页：NL → 字段 → pipeline → 真实 gate 数据
    Share Registry 页：钱包连 X Layer / Anvil，issue / setAllow / transfer / 查询 / 负路径
```

## 快速复现（本机）

```bash
just build                                            # 编译器
proofship/rwa-share-v1/scripts/gate.sh                # golden 门禁（check+build+inspect）
proofship/rwa-share-v1/scripts/anvil-check.sh         # 本地链正负路径（9 场景）
proofship/rwa-share-v1/scripts/proof-gate.sh          # proof 门禁正/负验证

# 前端（产品面）
proofship/rwa-share-v1/scripts/build-dapp-artifacts.sh  # 刷新 dapp 产物 + gate 报告
cd proofship/rwa-share-v1/dapp && npm install
npm run bridge     # 本机门禁服务（:5198）——Studio 对话里的 gate 真实执行
npm run dev        # http://localhost:5175（/api 自动代理到 bridge）
```

R0 preview relay link（让云端 Studio 旁观本机 bridge）：

```bash
cd proofship/rwa-share-v1/dapp
PROOFSHIP_RELAY=wss://proofship-relay.<acct>.workers.dev \
PROOFSHIP_DEVICE_TOKEN=<shared-secret> \
npm run bridge
```

线上托管壳（静态，无 bridge 时展示最近一次封存的 gate 报告）：
**https://proofship.pages.dev**

testnet 部署（需要你自己的 funded key；**永不**写进文件/参数/MCP）：

```bash
export PF_XLAYER_KEY=<hex>          # 你自己保管
PF_XLAYER_CONFIRM=yes PF_XLAYER_PRIVATE_KEY_ENV=PF_XLAYER_KEY \
  proofship/rwa-share-v1/scripts/deploy-testnet.sh 1000000 50000 100000
```

## 诚实边界（必守）

**中文**：本目录展示的是「机器核验的部署前门禁」——语义检查与同文件 theorem
certification（工程能力）不过则不产出制品、不部署。我们**不**声称 full formal
verification、不声称链上字节码已被证明、不声称证券级合规。部署合约
（`src/`）不含 invariant（EVM 对 nonempty invariant fail closed）；
`proof-twin/` 用于验证门禁机制本身（certified 族内形状）。

**EN**: This directory provides a machine-checked pre-deploy gate (semantic
checks + same-file theorem certification, engineering grade). We do **not** claim
full formal verification, proven bytecode, or securities compliance. The deploy
file carries no invariant (EVM fails closed on nonempty invariants); the
`proof-twin/` files exercise the gate mechanism on certified families.

## 边界（非目标）

- 不做真实法域托管 / KYC / 证券发行
- 不刷 Launch Grant 交易量
- 赛期不接外部 Yul→EVM 形式化 backend（见 plan §7.4）
- 不是多租户 SaaS（P0 local-first；演进见 positioning §4）
