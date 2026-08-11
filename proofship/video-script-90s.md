# ProofShip — 90s 视频脚本（拍摄版）

> 目标：评审在 90 秒内相信三件事——① AI 真的在写合约；② 门禁真的能拦住；
> ③ 它真的部署在 X Layer 上并能跑。
> 素材全部现货：Pages 站点、testnet 合约、proof-gate、链上负路径。
> 纪律：说 *machine-checked gate*，**不**说 formal verification / 字节码已证。

## 分镜与口播

### 0:00–0:08 · Hook（痛点）

**画面**：黑底白字快速打出两行：
「AI 一分钟能写完一个合约。」「你敢让它直接上主网吗？」
**口播**：AI can draft a contract in a minute. Would you let it ship straight to a chain?

### 0:08–0:16 · 产品一句话

**画面**：proofship.pages.dev 首页（Studio 空态）。
**口播**：ProofShip — describe share rules in plain language; a code agent drafts the
program; the machine gate decides what ships to X Layer.

### 0:16–0:30 · 对话 → 草案

**画面**：Studio 对话。粘贴发票规则（建议语一键填入）→ 草案卡展开字段与源码。
**口播**：I describe an invoice share: total supply, per-transfer cap, a rolling window,
allowlist only. The agent drafts the program — real ProgramV1 source, not pseudocode.

### 0:30–0:44 · 门禁（核心差异化，给足时间）

**画面**：gate 卡从 running 到 **⊢ GATE PASS**（真实 check→build→inspect，digests 滚动）。
切到 Inspector 的 Gate 页：两枚 certified 印章 + 一枚 REJECTED。
**口播**：Every draft faces the ProofForge gate: semantic checks and a machine-checked
proof. Pass, and artifacts are sealed. Fail — like this broken proof — and you get a
rejection with zero artifacts. Nothing bypasses the gate.

### 0:44–0:56 · 部署到 X Layer

**画面**：Registry 页 → Deploy → 钱包弹窗签名 → 地址出现；切 OKX explorer 页面。
**口播**：One click, my wallet signs, keys never leave my side — and it's live on
X Layer testnet, chain 1952.

### 0:56–1:14 · 链上正/负路径（实锤）

**画面**：Registry 页操作 + explorer 并排：
issue 100,000 → setAllow → 两笔 40,000 转账成功；
然后：超单笔 60,000 → **链上 revert**；非白名单地址 → **revert**（explorer 显示 failed tx）。
**口播**：On-chain now: the owner issues shares, allowlists a recipient, transfers settle.
Exceed the per-tx cap — reverted. Non-allowlisted address — reverted. The policy holds
because the gate only shipped rules that check out.

### 1:14–1:26 · 收口 + 生态

**画面**：回到 manifest；角落打 `Powered by ProofForge · agent-agnostic via MCP`。
**口播**：This is the AI-RWA vertical: onchain share registry with transfer policy.
The spine is Verified Ship — any MCP agent, any future template, same gate.

### 1:26–1:30 · 结尾卡

**画面**：黑底：⊢ ProofShip · proofship.pages.dev · @XLayerOfficial #BuildX
**口播**：ProofShip — the gate decides what ships.

## 拍摄注意

| 项 | 处理 |
|---|---|
| gate 真实时长 ~20s | 用跳剪；保留 digests 滚动的 2–3 秒真实感 |
| 深度负例（8min kernel 悬崖） | **不**现场跑；口播也不提时长细节 |
| 链上 revert 可见性 | 用 `scripts/testnet-acceptance.sh` 的 tx（显式 gas-limit，revert 会被打包，explorer 可见 failed 状态） |
| 孪生纪律 | 口播只说 "machine-checked proof gate"，不说 "contract is proven" |
| 钱包 | 录屏用测试钱包；地址可露，私钥永不出现 |
