---
id: RESEARCH-CODE-AGENT-LANDSCAPE
title: Code agent protocol landscape for ProofShip lanes (ACP / headless / RPC)
status: draft
owner: research
updated: 2026-08-11
normative: false
---

# Code Agent 协议面调研（ProofShip lane 选型）

> 目的：ProofShip 的 agent-agnostic 承诺要落在**真实协议面**上，不是口号。
> 本文盘点 2026-08 市面主流 code agent 的可编程接口，标注 ProofShip bridge 的 lane 状态。
> 方法：官方文档 + 本机实测（`proofship/rwa-share-v1/studio-bridge`）。

## 1. 结论先行

| 协议族 | 代表 | 对本产品的意义 |
|---|---|---|
| **ACP 原生**（`agent acp`/`--acp` stdio JSON-RPC） | omp、kimi、copilot、opencode、qwen、gemini | 首选接口：会话式、权限协商、流式更新 |
| **ACP 适配器** | claude-code-acp（Zed 官方）、aider-acp（社区） | 无原生 ACP 的热门 agent 靠适配器接入 |
| **headless exec**（`-p`/`-x`/`exec` 一次性） | codex、grok、pi、cursor-agent、amp、kimi -p | 最简 lane；无会话状态，适合单轮起草 |
| **自有 RPC/HTTP** | codex app-server、opencode serve、pi --mode rpc | 可作深度集成，非首选 |
| **编辑器锁定 / 服务停服** | gemini（个人版停）、cline（CLI 安装损坏）、hermes（venv 损坏） | 不接 |

**ACP 正在收敛成行业标准**（Zed 发起；Copilot CLI 2026-01 进入 public preview；
Kimi/OpenCode/OMP/Qwen 原生支持）。ProofShip 的 lane 抽象 `{kind: acp|exec}` 已兼容两族。

## 2. 调研矩阵

| Agent | 安装 | 协议面 | ProofShip lane | 实测状态（2026-08-11） |
|---|---|---|---|---|
| **Codex**（OpenAI） | ✅ | `codex exec` headless；app-server JSON-RPC（experimental） | `codex` (exec) | ✅ **全链验证**（NL→合约→gate 绿） |
| **Oh My Pi (OMP)** | ✅ | **`omp acp` 原生 ACP**；`-p` exec | `omp-acp` / `omp` | ✅ **ACP 全链验证** |
| **Kimi Code**（Moonshot） | ✅ | **`kimi acp` 原生 ACP**；`-p` headless + stream-json | `kimi-acp` / `kimi` | ✅ **ACP 全链验证**（用户已登录） |
| **GitHub Copilot CLI** | ⬜ 未装 | **`copilot --acp`**（stdio+TCP；2026-01 public preview）；`-p` headless | `copilot-acp` / `copilot` | 待装；BYOK 经 `COPILOT_PROVIDER_*` |
| **OpenCode** | ✅ | **`opencode acp` 原生 ACP**；`serve` HTTP API | `opencode-acp` | 协议注册；待用户配 provider |
| **Qwen Code** | ✅ | `--acp`（gemini-cli fork 继承） | `qwen-acp` | 协议注册；待验证 |
| **Claude Code** | ✅ | 无原生 ACP；**`claude-code-acp` 适配器**（已装）；stream-json | `claude-acp` | ⚠️ 协议握手过；**用户 OAuth 过期，需重登** |
| **Grok Build** | ✅ | `grok -p` headless + `--always-approve`；无 ACP server | `grok` | ⚠️ **CLI 凭据未配**（401） |
| **Cursor CLI** | ✅ | `cursor-agent -p --force` headless | `cursor-agent` | 协议注册；待验证 |
| **Amp**（Sourcegraph） | ✅ | `amp -x` execute；`--no-tui` runner | `amp` | 协议注册；待验证 |
| **Pi** | ✅ | `pi -p` exec；`--mode rpc` 自有协议 | `pi` | 协议注册；待验证 |
| **Gemini CLI** | ✅ | `--acp` 原生 | `gemini-acp` | ❌ **Google 停个人版服务**（转 Antigravity） |
| **Aider** | ⬜ 未装 | 社区适配器 `aider-acp`（jorgejhms） | 候选 | 待装 |
| **Cline CLI** | ✅（损坏） | —（npm 安装缺 pino） | 不接 | ❌ 安装损坏 |
| **Hermes** | ✅（损坏） | —（venv bad interpreter） | 不接 | ❌ 安装损坏 |

## 3. 认证模式（对 P3「绑定用户订阅」直接相关）

| 模式 | 代表 | 说明 |
|---|---|---|
| 订阅 OAuth | Claude Code（Pro/Max）、Codex（ChatGPT 账号）、Kimi（OAuth device flow） | 用户熟悉的「我有订阅」；token 在本机 keychain/config |
| API key（BYOK） | 几乎全部支持 env key；Copilot `COPILOT_PROVIDER_*` | 最易程序化；P3 云端靠 outbound-proxy 注入 |
| 平台免费档 | Gemini 个人版**已停** | 教训：免费档可被厂商单方面收回，不作依赖 |

## 4. 对本产品的设计结论

1. **lane = driver 注册表**，两条 kind 就够：`acp`（会话式）与 `exec`（一次性）。
   新 agent 接入 = 一行注册 + 实测验收。
2. **ACP 优先**：omp/kimi/copilot/opencode/qwen 都是原生 ACP；Claude 靠 Zed 适配器。
3. **exec 保底**：codex exec 是全链最稳的今天；grok/pi/cursor/amp 一行命令可接。
4. **不碰**：服务已停（gemini 个人版）、安装损坏（cline/hermes）、纯 IDE 锁定（无 CLI 的）。
5. 云端 lane（C1+）复用同一契约：Sandbox 里装同一批 CLI，凭据经 outbound-proxy 注入。

## 5. 参考

- ACP 规范：https://agentclientprotocol.com
- Copilot ACP preview：https://github.blog/changelog/2026-01-28-acp-support-in-copilot-cli-is-now-in-public-preview/
- Kimi ACP：https://moonshotai.github.io/kimi-code/en/reference/kimi-acp
- OpenCode ACP：https://opencode.ai/docs/acp/
- 适配器：https://github.com/zed-industries/claude-code-acp · https://github.com/jorgejhms/aider-acp
- comet（多设备 agent 控制面，harness-per-CLI 先例）：https://github.com/zeronsh/comet
