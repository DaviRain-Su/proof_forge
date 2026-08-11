---
id: PRODUCT-EXTERNAL-AUTHOR-MVP
title: External Author MVP — dist / host policy / command loop
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# External Author MVP：让外部作者不再 lake build

状态：`draft`（2026-08-10）  
关联：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md) · [`05-distribution-and-packages.md`](05-distribution-and-packages.md) · [`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) · [`adr/0037-developer-cli-pf.md`](../adr/0037-developer-cli-pf.md) · ADR-0013/0016（host profile）

> **一句话**：慢的不是 Yul→solc，是「为了跑通那一步前面的 90%」——编译器怎么装、装上后 host 会不会误杀、命令是否覆盖 monorepo 脚本。

---

## 0. 问题诊断（对照现状，不编故事）

### 0.1 体感对照

| 维度 | Solidity / forge | ProofForge 今天的真实路径 |
|---|---|---|
| 拿到编译器 | `npm i solc` / 预编译二进制 | crates.io 只有 `proof-forge-pf`（orchestrator）；`proof-forge-next` **NOT on crates.io**；文档诚实写明 |
| 预编译包 | 各平台 solc 即用 | `package-cli` / `release-engineering-dist` 有 tarball，但 **pf 与 next 分轨打包**；`pf-cli-dist` 本地可 side-by-side，Release 资产未强制同包 |
| 首次 build | 秒级 | monorepo `lake build` 上百～几百分钟量级（本机大 job + ~270MB 动态链接二进制） |
| Agent / MCP | 本地 solc 即可 | 远程 edge **故意**不 compile；stdio MCP 可 spawn 本机 CLI，但本机常缺 next |
| setup | 一条命令装齐 | `pf setup` **主要打印 copy-paste**；`--yes` 仅 best-effort crates.io companions，**不**装 compiler tarball / Tool Lock |
| host 门禁 | 无 | `host-profiles.lock.json` 钉死 **Mint 22.3 / 特定 Darwin**；Debian 等机 `host:stat` digest mismatch → 必须改 lock 或重编 |
| 一键 demo | `forge build && forge create` | setup 清单 + 环境变量 + 常回退 monorepo 脚本 |

### 0.2 代码事实锚点（验收时对照）

| 锚点 | 现状 |
|---|---|
| `clients/pf-cli/Cargo.toml` | `publish=true`，**不** bundle Lean compiler |
| `clients/pf-cli/src/cmd/doctor.rs` | setup 缺 next 时建议 `lake build` 或 side-by-side Release |
| `clients/pf-cli/src/compiler.rs` | 解析顺序：`PROOF_FORGE_CLI` → sibling → monorepo `.lake` |
| `scripts/package_cli_dist.sh` | 只打 `proof-forge-next-<ver>-<plat>.tar.gz`，不打 `pf` |
| `scripts/pf_cli_dist.sh` | 本地 side-by-side `pf`+`next`（**不**进 ordinary CI / 不上传 Release） |
| `.github/workflows/release-engineering-dist.yml` | multi-arch next + Author + Host SDK；**无** install-dist → `pf new` → `pf build` 陌生机 E2E |
| `host-profiles.lock.json` | 2 profiles：`linux-x86_64-mint223-eligible`、`darwin-arm64-…` |
| `ProofForgeV2/Materialization/LockedToolchainV1.lean` | finalize 路径校验 `host:stat` 等 systemTools digest |
| `proof-forge-next install` | Tool Lock 物化 **已**幂等；与 `pf setup` **未**合成一条命令 |
| 版本 | 根 `VERSION=0.1.1`；`proof-forge-pf` Cargo `0.1.2` — **心智分裂** |

### 0.3 三层缺口（不是「再写几个 shell」）

```text
① 分发 (dist)      ← 最大洞：compiler + pf 怎么装到用户/Agent 机器
② 宿主策略 (host)  ← 第二大洞：hermetic host lock 用在 engineering/dev build 过严
③ 产品命令闭环    ← setup/test/deploy/network 与 monorepo 脚本未脱钩
④ CI              ← 应用来保证 ①②③，而不是代替 ①②③
```

---

## 1. 目标形态（外部作者默认路径）

```bash
# 一次安装（单命令）
curl -fsSL https://…/install.sh | sh
# 或: pf bootstrap --target evm

pf new hello --target evm && cd hello
pf doctor --target evm          # 全绿或自动修
pf build                        # 秒～十秒级（有缓存 / 预编译 next）
pf test                         # 可选 Anvil（Tool Root 内）
# 链上（显式策略，见 §2 D3）:
#   pf deploy --network local --broadcast --private-key-env KEY
#   或 UI 只消费 build/ 产物 + 钱包
```

**中间禁止要求**（外部作者路径）：

- 手改 `host-profiles.lock.json`
- monorepo `lake build`
- 猜半打 `PROOF_FORGE_*` 环境变量才能 build
- 读五选一 markdown 迷宫才能装齐

贡献者 monorepo 路径保留，但 **不得** 是文档默认主路径。

---

## 2. 产品决策（先拍板，再开工）

| ID | 决策 | 建议默认 | 状态 |
|---|---|---|---|
| **D1** | 外部作者永远不 `lake build` | **是** | **accepted**（2026-08-10） |
| **D2** | engineering/dev 默认跳过 hermetic host pin（只严校 Tool Root 内锁工具） | **是**；formal/hermetic 另开 profile | **accepted** — `PROOF_FORGE_HOST_MODE` 默认 `dev` |
| **D3** | EVM public testnet broadcast | **v0 继续拒绝 public 默认**；`--broadcast` 仅 `local`（现状）；testnet 若开必须显式 opt-in + key 仅 env + 文档一致 | **accepted**（保持既有 safety） |
| **D4** | `pf` 与 `proof-forge-next` 强制同版本打包 / 同 `VERSION` | **是** | **accepted** — Cargo `0.1.1` 对齐 `VERSION` |
| **D5** | Agent 主路径 | **双轨**：本机 stdio MCP spawn CLI；远程 edge 只 docs/catalog，**不**装成「能 build」 | **accepted** |

权威 ADR：[`adr/0040-external-author-host-mode-and-bundle.md`](../adr/0040-external-author-host-mode-and-bundle.md)。

---

## 3. 非目标（避免做偏）

- 不为「快」让远程 MCP 持 key / 默认 broadcast
- 不把 monorepo `lake build` 当外部作者主路径
- 不用「再写一份 Solidity 镜像」当产品主路径（语义对齐但 provenance 假）
- 不把 formal Stage-0 / hermetic release 塞进本 MVP
- 不发明第二 Tool Lock 或 PATH 扫盘装工具
- 不把 ordinary `just ci` 绑死 Anvil/Mollusk host-heavy 门

---

## 4. 需求清单

### 4.1 P0 — 没有这些，Agent/外部作者永远觉得「差很多」

| ID | 需求 | 为什么 | 建议一条命令 / 交付形态 | 验收（AC） |
|---|---|---|---|---|
| **P0-1** | 可安装的 `proof-forge-next` 二进制（linux-x86_64 / darwin-arm64）与 `pf` **同级交付** | crates.io 只有 orchestrator = 断腿 | Release 资产：`proof-forge-bundle-<ver>-<plat>.tar.gz` 含 `pf` + `proof-forge-next` + `VERSION` + `INSTALL.md`；稳定 URL；`install.sh` 或 `pf bootstrap` | 干净机无 monorepo：装完 `pf version` 与 `proof-forge-next version --json` 同 `VERSION`；`which` 可见二者 |
| **P0-2** | host-profiles **开发通道**：engineering 不 fail-closed 钉死他机 `/usr/bin/stat` | Debian ≠ Mint lock → 被迫改 JSON + 重编 270MB | `PROOF_FORGE_HOST_MODE=dev`（或 `pf build` engineering 默认）；仅校验 Tool Root 内 solc 等；host 工具 warning 或 `observe-host` 写入用户 cache，**不**要求重编 compiler | 非 lock 原生 distro 上 `pf build -t evm` **不得**要求改 embedded host lock |
| **P0-3** | `pf setup --target evm -y` 真的装齐 | 现在 setup 只打印 copy-paste | setup 幂等：缺 next → 拉 bundle/tarball；缺 solc → 调 `proof-forge-next install --targets evm --yes`；可选 anvil `--with-runtime`；结束 `doctor` 全 ok | `pf setup -t evm -y && pf doctor -t evm` exit 0，无 NEED |
| **P0-4** | 本机 stdio MCP 暴露 `pf_build`（spawn 本机 CLI）；远程 edge 不装 compile | 远程只能 docs → Agent 只能硬编仓库 | 文档双轨诚实；stdio MCP 路径写死「需本机 bundle」；edge 工具列表不含假 build | agent playbook 一页；edge smoke 无 compile 工具 |
| **P0-5** | 冷启动 build 性能：用户永不 lake | lake 全量是体验杀手 | 发布 stripped/准静态 `proof-forge-next` engineering-dist；日常路径只下二进制 | 外部路径文档 **零** `lake build`；冷 build EVM hello ≤ 约定阈值（先记基线再钉 SLA） |
| **P0-6** | 错误信息 → 可执行修复 | `host:stat expected…` 对用户无意义 | 稳定错误码 + stderr 末行 `pf doctor --fix` 或一条可复制命令 | 至少 host mismatch / missing compiler / missing tool root 三类有 fix-up 行 |

### 4.2 P1 — 有了才能「像 forge 一样日用」

| ID | 需求 | 说明 | 验收要点 |
|---|---|---|---|
| **P1-1** | `pf test -t evm` 不依赖 monorepo 路径 | **done engineering**：bundle 解析 `scripts/pf_evm_test.sh`；`pf -y setup -t evm` 装 anvil/cast | standalone bundle 用户可 test（缺 tool → skip-clean） |
| **P1-2** | `pf deploy` 与前端同一产物契约 | **done engineering**：`pf write-ui-json` + deploy broadcast 写 `ui-deployment.json`（schema `proof-forge.pf.evm-local-deployment.v1`） | UI 模板读 `public/deployment.json` |
| **P1-3** | public testnet broadcast 策略与文档一致 | **done engineering**：catalog `pfProductBroadcast` + network use 文案；v0 仍拒 public broadcast | 讲得清 |
| **P1-4** | 网络 catalog 进 CLI | **done engineering**：`pf network list\|show\|use` 读 `networks.v1.json`（embedded + package） | 少手写 chainId/RPC |
| **P1-5** | 增量编译 / 模块缓存（贡献者路径） | 改一行 Hello 不应碰无关 target C 对象 | 仅 monorepo 开发体验；外部路径无关 |
| **P1-6** | CI 矩阵：linux-x86_64 + 非 Mint 发行版 smoke | Ubuntu 22.04/24.04、Debian 12：install dist → pf new → pf build 必须绿 | 见 §6 |
| **P1-7** | `pf new` 后 out-dir 与 UI 模板一键对齐 | `pf scaffold-ui --template evm-dapp` | abi/bin + chain presets |

### 4.3 P2 — 体验与产品叙事

| ID | 需求 |
|---|---|
| **P2-1** | 安装页只保留 2 条路径：① 一键 bootstrap ② 贡献者 monorepo；删「五选一文档迷宫」 |
| **P2-2** | `pf version --json` 带：compiler path、tool root、host mode、profile digest |
| **P2-3** | SBOM / 二进制 digest 与 doctor 对齐（接到 setup） |
| **P2-4** | Agent 单页 cheatsheet：install → build → test → deploy；**禁止**默认让 Agent lake build |
| **P2-5** | Host SDK / PyPI 与 CLI **同 VERSION** 锁死（消 `pf 0.1.2` + `next 0.1.1`） |

---

## 5. Epic 拆分与实现序

### Epic A — Bundle 分发（P0-1, P0-5, D4, P2-5）

1. 统一版本源：根 `VERSION` = Lean `ProductVersionV1` = `proof-forge-pf` Cargo version（发版脚本 gate）
2. 扩展 packager：`scripts/pf_bundle_dist.sh`（或合并 `package_cli_dist` + `pf_cli_dist`）产出 **bundle** tarball
3. `release-engineering-dist.yml` 上传 bundle（linux-x86_64 + darwin-arm64）；保留 next-only 资产可选兼容一版
4. `install.sh`：检测 OS/arch → 校验 sha256 → 装到 `~/.local/proof-forge/<ver>/` → PATH shim
5. 文档：INSTALL 收敛为 bootstrap + monorepo 两轨

### Epic B — Host dev 模式（P0-2, P0-6）

1. 定义 `HostMode`：`hermetic`（现行为，CI/formal）vs `dev`/`engineering`（默认产品 build）
2. `LockedToolchainV1`：dev 模式 **跳过** systemTools（`host:stat` 等）digest pin；**保留** Tool Root lock tools exact verify
3. 可选：`pf doctor --fix-host` → `observe_host_*` 写入用户 cache profile（不改仓库 lock）
4. 错误码表 + stderr fix-up 行
5. 自测：Debian/Ubuntu 容器 build 不改 lock

> **安全边界**：dev 模式 **不** 声称 hermetic / Stage-0 / formal；manifest/evidence 须标记 `hostMode=dev`。

### Epic C — setup 真装齐（P0-3, P0-6）

1. `pf setup -t <target> -y`：
   - resolve compiler；缺失则 bootstrap/download bundle（需网络 + 显式 yes）
   - spawn `proof-forge-next install --targets … --yes`（及可选 `--with-runtime`）
   - companions：`proof-forge-solana-client` 等 crates.io 仅 companion，不冒充 compiler
2. setup 结束跑 doctor；非 zero-tool 缺工具 → exit ≠ 0
3. 删除/降级「唯一建议 lake build」文案为贡献者附录

### Epic D — 命令闭环脱钩 monorepo（P1-1..P1-4, P1-7）

1. `pf test`/`deploy`/`network` 以 bundle + Tool Root 为 sole 依赖
2. 产物契约与 `templates/evm-dapp-ui` 对齐
3. 网络 catalog CLI 读 `networks.v1.json`（可 embed 或旁路文件）

### Epic E — CI 绿线（P0 守卫 + P1-6）

见 §6。没有 E 不打 engineering-dist tag。

### Epic F — Agent 叙事（P0-4, P2-1, P2-4）

1. 重写 `03-hello-dapp-agent-playbook` 默认路径为 bundle
2. MCP README 双轨表
3. 单页 cheatsheet（可进 `clients/pf-mcp/content`）

---

## 6. CI 最少三条绿线（没有就不打 engineering-dist）

| Job | 做什么 | 禁止 |
|---|---|---|
| **install-dist-smoke** | 干净 Ubuntu 容器：只下 Release/bundle tarball + 校验 sha → `pf new` → `pf setup -t evm -y` → `pf build -t evm` | monorepo checkout 作为 compiler 源；`lake build` |
| **host-dev-mode-smoke** | 非 lock 原生 distro（Debian 12 或 Ubuntu ≠ Mint profile）上 `pf build` | 要求改 embedded host lock；要求重编 next |
| **agent-path-smoke** | 仅环境变量 + `pf` 子命令完成 hello build；断言无 `lake` 调用 | 手改 lock；文档教 lake |

现有 `package-cli-smoke` / `release-engineering-dist` **保留**，但 **不替代** 上表 E2E。

实现建议：

- 新 workflow 或 job：`external-author-smoke.yml`（`workflow_dispatch` + tag 前必跑）
- 矩阵：`ubuntu-22.04`、`ubuntu-24.04`；可选 Debian container service
- 产物：upload 日志 + `proof-forge.output.v1` inspect JSON（非 formal）

---

## 7. 最小完善切片（一轮只做这些）

**名称**：PF External Author MVP（EVM-first）

| # | 交付 | 对应 |
|---|---|---|
| 1 | Release：`pf` + `proof-forge-next` + VERSION **同包** | P0-1, D4 |
| 2 | `pf bootstrap --target evm` 或 `install.sh` | P0-1, P0-3 |
| 3 | host：dev 模式不校验 `/usr/bin/stat` digest（只校验 tool-root solc） | P0-2, D2 |
| 4 | CI：Ubuntu 干净机 bootstrap → new → build | §6 install-dist-smoke |
| 5 | `pf build` 失败输出带 `pf doctor --fix` / 可复制一行 | P0-6 |

**完成定义（DoD）**：

```text
# 在干净 Ubuntu 容器（无本仓库 lake 产物）:
curl -fsSL …/install.sh | sh
pf new hello --target evm && cd hello
pf setup --target evm -y
pf doctor --target evm          # ok
pf build                        # exit 0，产出 proof-forge.output.v1
# 全程无 lake build、无手改 host-profiles.lock.json
```

做完这 5 点，DSL 路径体感接近 solc：**装一次、一条 build、产物可交给 UI/钱包**。

---

## 8. 与现有文档/代码的关系

| 已有 | 本 MVP 如何衔接 |
|---|---|
| `01-toolchain-install-surface` I0/I1 doctor/install | **复用** `proof-forge-next install`；pf setup 做编排层，不复制下载逻辑 |
| `05-distribution-and-packages` REL-CLI-* | **升级**：next-only → **bundle**；channel 仍 `engineering-dist` |
| ADR-0037 `pf` vs next | **保持**两层权威；改的是 **交付同包**，不是合并二进制职责 |
| ADR-0013/0016 host profile | hermetic 资格 **保留**；产品默认走 dev 通道，不宣称 eligibleForHermetic |
| `03-hello-dapp-agent-playbook` | 默认 env 从 monorepo 改为 bundle |
| `pf setup` copy-paste | 演进为真安装；copy-paste 仅 fallback 当网络/权限失败 |
| formal D1–D4 / Stage-0 | **正交**；本文件不推进 formal |

---

## 9. 建议后续 ADR（实现前）

**ADR-0040（建议标题）**：Engineering host mode and external-author distribution bundle

应冻结：

1. `HostMode` 枚举与默认值（engineering build = dev）
2. Bundle 资产命名与 VERSION 同源 gate
3. 外部作者路径禁止 lake 作为支持手段
4. evidence/manifest 如何标记 non-hermetic

在 ADR 落地前，本文件为 **工程执行队列权威草稿**。

---

## 10. 执行优先级（拍板后）

```text
Week 0  确认 §2 D1–D5 → 开 ADR-0040 草稿
Week 1  Epic A bundle + 版本对齐 + install.sh
Week 1  Epic B host dev mode（Lean + 错误码）
Week 2  Epic C pf setup -y 真装齐
Week 2  Epic E 三条 CI 绿线挂上 release gate
Week 3  Epic F 文档两轨收敛 + agent cheatsheet
之后    Epic D P1 日用闭环（test/deploy/network/UI）
```

并行约束：Epic B 可与 A 并行；C 依赖 A 的下载 URL 契约；E 依赖 A+B+C 最小集。

---

## 11. 成功度量（工程，非营销）

| 度量 | 基线（今日） | MVP 目标 |
|---|---|---|
| 外部作者首次成功 `pf build -t evm` 是否需要 monorepo | 是（常见） | **否** |
| 非 Mint Linux 是否需改 host lock | 是 | **否**（dev mode） |
| `pf setup -y` 后 doctor NEED 项 | 常有（compiler） | **0**（evm core） |
| 安装文档主路径条数 | 多轨 | **2**（bootstrap / monorepo） |
| Release 是否含 pf+next 同包 | 否 | **是** |

---

## 12. 变更日志

| 日期 | 变更 |
|---|---|
| 2026-08-10 | 初稿：诊断 + D1–D5 + P0/P1/P2 + Epic + CI 三绿线 + 最小五切片 |
| 2026-08-10 | **实现切片落地**：ADR-0040；`HostMode=dev` 默认；Diagnostic fix-up；`package_bundle_dist` + `install.sh` + `pf bootstrap`；setup `-y` 真调 install；pf 版本对齐 0.1.1；release workflow 打 bundle + EA smoke |
| 2026-08-10 | **实现切片落地**：ADR-0040；`HostMode=dev` 默认；Diagnostic fix-up；`package_bundle_dist` + `install.sh` + `pf bootstrap`；setup `-y` 真调 install；pf 版本对齐 0.1.1；release workflow 打 bundle + EA smoke |
| 2026-08-10 | **Wave A+B**：README 两轨；`external-author-smoke.yml`；P1-1 standalone `pf test -t evm`（bundle 脚本解析 + setup `--with-runtime`） |
| 2026-08-10 | **P1-2/3/4 + playbook**：`pf network`；`pf write-ui-json`；deploy 写 UI JSON；agent playbook 默认 bundle |
