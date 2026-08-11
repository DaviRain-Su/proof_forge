---
id: PLAN-PROOFSHIP-EXECUTION
title: ProofShip execution checklist (D0–D11, X Layer AI Season)
status: draft
owner: product+engineering
updated: 2026-08-11
normative: false
---

# ProofShip 执行清单（D0–D11）

> **关系**：产品定位/品牌/阶段 = [`product/proofship-positioning.md`](../product/proofship-positioning.md)；
> 竖切范围/风险/成功标准 = [`plan/ai-rwa-verified-ship-xlayer.md`](ai-rwa-verified-ship-xlayer.md)。
> 本文只做 **how & day-to-day 可勾选清单**，不扩 scope、不改 formal 状态。

## 0. 今日状态快照（2026-08-11）

| 项 | 状态 |
|---|---|
| 品牌/定位/阶段文档 | ✅ 已落（positioning + plan + handoff 同步） |
| 编译器二进制 | ✅ `just build`（main 同步后） |
| **D1 spike（工程侧）** | ✅ check → EVM build → inspect exact closure → 本地链 9 场景全绿 |
| **X Layer testnet 部署** | ✅ `0x32aa4856bf94e97e24993e07c27406163c1ba3eb`（2026-08-11，钱包直签，block 37984808） |
| **D2 template + AI 契约** | ✅ system-prompt + few-shot + gate.sh |
| **D3 AI loop 可行性** | ✅ InvoiceShare 变体一轮过 gate；Studio 对话 → bridge 真实门禁已实测 |
| **D4–D5 proof 资产** | ✅ 双 certified（EvenStep 9.6s / ShareConservation 4.3s）+ 快速负例 6s 拒绝零制品 |
| **D5–D6 产品前端** | ✅ 对话式 Studio + Registry；**https://proofship.pages.dev** 已上线（P1 托管壳） |
| X 账号 / 表单 | ⬜ **用户侧动作**（见 D0-U） |

### D1 实测坑（→ AI 禁止清单）

| 坑 | 事实 | 模板处理 |
|---|---|---|
| Bool 不可作 entry/init 参数 | S1 门拒绝 | 标志位用 `UInt64` 0/1 |
| EVM Map **值**必须 UInt64 | `Map Principal Bool` Plan fail closed | allowlist 用 `Map Principal UInt64` |
| `-o` 相对 `--root` | 传仓库相对路径会嵌套 | `-o out-evm` |
| 输出目录必须 fresh | 已存在即 `PF-OUTPUT-COLLISION` | 重建前 `rm -rf out-evm` |
| `error X()` 必须带括号 | 裸 `error X` → PF-INTERNAL | 模板全带括号 |
| event 字段仅 UInt/Int/String | Principal 字段不允许 | 事件只带 UInt64 amount |

### 🔀 main 同步（2026-08-11）

- FF 合入至 `2dc9f55b5`（4 commits）：verified initializer/view preservation slice、
  SBOM manifest refresh（覆盖本地 refresh，内容一致）、hashed-Map 测试对齐（修复
  EvmSmoke MapPut 旧断言失败）、evm-corpus pin。
- **新 certified 族 `InitializerViewEquality`**：两 UInt64 槽零初始化 + 空参 view +
  双状态等式 invariant，名字全参数化、走 production Reference 语义。RWA 味孪生
  `proof-twin/ShareConservation.lean`（`issued == distributed`）certified **4.3s**。
- 计时：EvenStep（parity）9.6s；快速负例（inventory 缺定理）6s 拒绝。深度反例
  （体形破坏/名字串篡改）撞 8min+ kernel 悬崖——现场只跑快速负例，深度类预录。

## 1. 仓库布局（拍板）

```text
proofship/                        ← 产品面（不碰 Examples/ 与 Tests/ 注册）
  README.md                       ← 门面 + 中英诚实边界
  rwa-share-v1/
    src/RwaShareRegistry.lean     ← golden 部署模板（EVM；无 invariant）
    src/InvoiceShare.lean         ← 变体样例（few-shot 01）
    proof-twin/                   ← certified 正例 ×2 + 快速负例 ×1
    ai/                           ← system-prompt + fewshot（含真实修复环）
    scripts/                      ← gate / anvil-check / proof-gate / deploy-testnet / build-dapp-artifacts
    studio-bridge/server.mjs      ← 本机门禁服务（127.0.0.1:5198，零依赖 Node）
    dapp/                         ← 对话式 Studio + Registry（Vite+React+viem）
```

- **不用** `examples/`（小写）：macOS 大小写不敏感与 `Examples/` 冲突。
- golden 走 external program 模式（`--root … --source … --module …`）。
- 不注册进 `Examples.lean` / `Tests.lean` → ordinary CI 零影响。

## 2. 日程与任务

### D0-U（用户侧 · 资格）
- [ ] 建项目 X 账号（handle 建议 `@ProofShip*`），发第一条预热帖
- [x] testnet OKB 已领（部署已完成 ⇒ faucet 已过）
- [x] 本机 deploy 能力 ✅（钱包直签已完成一次部署）
- [ ] （可选）OKX Dev Portal `OK-ACCESS-KEY`（OnchainOS 对照叙事）

### D1（spike · 工程）✅
- [x] `just build` 产出 `proof-forge-next`
- [x] golden `check` / `build --target evm` / inspect exact closure 全绿
- [x] 本地链验收 `scripts/anvil-check.sh` 9 场景全绿
- [x] **X Layer testnet 部署（2026-08-11）**：dapp 钱包直签 RwaShareRegistry，
      合约 `0x32aa4856bf94e97e24993e07c27406163c1ba3eb`（block 37984808）；
      链上 view 验证（issuedTotal=0 / policy=50000）

### D2（template 定稿）✅
- [x] golden 冻结为 sole 模板；负路径本地链上固定
- [x] `ai/system-prompt.md`：字段 schema + DSL 白名单 + 禁止清单
- [x] `ai/fewshot/01-invoice.md`（NL→字段→源→门禁→动线）+ `02-repair-loop.md`（真实修复环）
- [x] `scripts/gate.sh`：单命令门禁（check → build → inspect exact closure）

### D3–D4（AI loop · 关键路径）✅ 可行性闭合
- [x] 一轮收敛：InvoiceShare 变体过 gate
- [x] **Studio 对话 → bridge 真实门禁**已实测（正例 ok / 负例 PF-SRC-INVALID 回传）
- [x] **本地 agent lane（多agent 注册表，15 lanes）**：`GET /api/agent/lanes` 探测，
      **codex（exec）/ omp-acp / kimi-acp 三条 lane 全链验证**（NL→源→gate 绿）；
      协议注册待验证：qwen-acp、opencode-acp、cursor-agent、amp、pi、copilot(-acp 待装)；
      待用户重登：grok（401）、claude-acp（OAuth 过期）；gemini-acp 服务停服标记。
      调研矩阵与认证模式：[`research/2026-08-11-code-agent-landscape.md`](../research/2026-08-11-code-agent-landscape.md)
- [ ] 另一 MCP agent（Claude/Cursor）同流程跑通（agent-agnostic 补充证据）
- [ ] 文档字段抽取 P0-lite（发票/条款 → 参数）
- [x] **R0 中继已实现并上线**（提前于赛后计划）：`proofship/relay`（SessionRoom DO）部署至
      `proofship-relay.davirain-yin.workers.dev`；bridge `--link` 模式（PROOFSHIP_RELAY/TOKEN）；
      dapp 只读 live 视图（`?launch=<id>`）；本地全链验证（viewer 实时收到 gate.start/done/sealed）

### D4–D5（proof verdicts）✅ 资产就绪
- [x] certified 正例 ×2 + 快速负例 ×1，固化在 `scripts/proof-gate.sh`
- [x] 孪生纪律写进 system-prompt §5 与 twin 文件头注释
- [ ] （stretch）`spent ≤ windowCap` shape 引理
- [ ] 现场操作彩排：族内现场跑 + 深度负例仅口头/预录

### D5–D6（deploy UX + 产品前端）✅
- [x] `scripts/deploy-testnet.sh`（opt-in + env 持钥；未用——实际走了钱包直签）
- [x] `pf` developer CLI 已构建（备选项目流面）
- [x] **对话式 Studio**：launches 栏 + 对话流 + Inspector（Fields/Program/Gate/Ship）；
      `studio-bridge` 本机真实门禁；Pages 静态壳降级展示封存报告
- [x] **Registry 页**：钱包连接 X Layer 1952/Anvil、attach、issue/setAllow/transfer/查询、
      负路径进日志、钱包直签部署
- [x] **P1 Hosted surface**：https://proofship.pages.dev（deployment.json 内置实地址+ABI）
- [x] **产品字样清扫**：`demo/` → `scripts/`，零 demo/演示 字样
- [ ] testnet 链上操作联调（issue/setAllow/transfer/负路径，对着实地址跑一遍）——
      `scripts/testnet-acceptance.sh` 已就绪（7 tx，revert 显式 gas-limit 保证被打包可见），等用户 env key 跑一次

### D7–D9（polish）
- [x] 90s 视频脚本（`proofship/video-script-90s.md`：分镜 + 口播 + 拍摄纪律）
- [x] 发布文案（`proofship/launch-copy.md`：X 主帖 EN/中文 + 预热帖 + 表单预填 + 措辞红线）
- [x] README 中英诚实边界段（proofship/README.md；视频口播已对齐）
- [ ] 录制 90s 视频（按脚本）；X 账号建立 + 预热帖；主帖提交前 24–48h 发

### D10–D11（buffer / 提交）
- [ ] testnet 再压一轮；表单提交（08-21 23:59 UTC 前）
- [ ] 每日三合体检查（A 生成门禁在？C RWA 份额在？X Layer 地址活？）

## 3. 命令速查

```bash
just build                                          # 编译器
proofship/rwa-share-v1/scripts/gate.sh              # golden 门禁
proofship/rwa-share-v1/scripts/anvil-check.sh       # 本地链 9 场景
proofship/rwa-share-v1/scripts/proof-gate.sh        # proof verdicts
proofship/rwa-share-v1/scripts/build-dapp-artifacts.sh  # 刷新 dapp 产物 + gate 报告

cd proofship/rwa-share-v1/dapp
npm run bridge     # 本机门禁服务 :5198
npm run dev        # http://localhost:5175

# testnet 部署（env 持钥；或网页 Registry 页钱包直签）
PF_XLAYER_CONFIRM=yes PF_XLAYER_PRIVATE_KEY_ENV=PF_XLAYER_KEY \
  proofship/rwa-share-v1/scripts/deploy-testnet.sh 1000000 50000 100000
```

## 4. 不做清单（赛期）

与 plan §7.3/§10.3 一致：EVM invariant lowering、任意自动证明、Launch 刷量、
多 target 同场、真实托管/预言机、外部 Yul 形式化接入、多租户 SaaS（P3 另开 ADR）。

## 5. 分工边界

| 谁 | 干什么 |
|---|---|
| **Agent** | golden 源、AI prompt/few-shot、脚本、前端、README/操作文档、录屏脚本、Pages 托管 |
| **用户** | X 账号、水龙头、deploy key/钱包、视频出镜、表单提交、主网赛后义务 |
