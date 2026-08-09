---
id: PRODUCT-DISTRIBUTION-AND-PACKAGES
title: Distribution architecture — CLI release vs Lean author SDK vs host wrappers
status: draft
owner: product+engineering
updated: 2026-08-09
normative: false
---

# 分发架构：CLI 发版 · Lean 写合约包 · 宿主 SDK/MCP

状态：`draft`（2026-08-09）  
关联：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)、[`02-external-program-v1.md`](02-external-program-v1.md)

## 1. 结论（先回答「要不要做」）

| 问题 | 答案 |
|---|---|
| 现在有没有 **产品 release 打包**？ | **没有**。只有 monorepo 内 `lake build` → `.lake/build/bin/proof-forge-next`（约数百 MB 动态链接调试二进制），无 GitHub Release 资产、无 tarball 安装、无 pip/Reservoir 发布 |
| Python MCP/SDK 是不是「用 Python 重写了编译器」？ | **不是**。它们只 **spawn** 产品 CLI 并解析 JSON；权威永远是 Lean 二进制 + Tool Lock |
| 要不要先做 **CLI engineering 发版/打包**？ | **要**。外部作者/Agent 不能依赖「克隆整仓 + lake 编译 263MB」当 sole 安装路径 |
| 要不要发 **Lean 写合约 SDK 包**？ | **要（分轨）**：与 CLI 不同轨——写源码/IDE 语法 vs 编译/物化 |
| 这是不是 formal Stage-0 / `just release-check`？ | **不是**。工程分发 ≠ formal/hermetic/release 资格；后者仍放最后 |

推荐顺序：

```text
① Engineering CLI dist（版本化二进制 + digest + 安装说明）
② Lean authoring package（最小可 require 的写合约表面）
③ Host SDK 可选发布（pip 等；仍只包 CLI）
④ formal Stage-0 / hermetic release evidence（最后）
```

## 2. 三层产品面（禁止混谈）

```text
┌─────────────────────────────────────────────────────────────┐
│  A. 产品编译器 CLI  proof-forge-next                         │
│     Lean 实现 · 读源文本 · 编译/物化/inspect/doctor/local     │
│     权威：sole product path                                  │
└───────────────────────────┬─────────────────────────────────┘
                            │ spawn + JSON
┌───────────────────────────▼─────────────────────────────────┐
│  C. 宿主封装  Python SDK / MCP server                         │
│     不是第二编译器 · 不 PATH 发明工具 · 无默认 network broadcast │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  B. Lean 写合约表面  import ProofForgeV2 + program … where    │
│     语法/导出/可选 IDE 支持 · 用户 Lake 工程可 require           │
│     与 A 解耦：产品 build 读文本，不必 lake build 用户合约包     │
└─────────────────────────────────────────────────────────────┘
```

| 层 | 现在是什么 | 用户怎么拿到 | 发版形态（目标） |
|---|---|---|---|
| **A CLI** | `lean_exe proof_forge_next`，包版本 monorepo `0.1.0` | 克隆仓库 `lake build` | 版本化 **binary dist**（平台 tarball + SHA-256）+ 固定 `lean-toolchain` 说明 |
| **B Lean author SDK** | monorepo 内整库 `lean_lib ProofForgeV2`（含编译器/targets） | 只能 path 依赖整仓 | **最小可发布 lean 包**（语法/export 子集），Reservoir 或 git tag `require` |
| **C Host SDK/MCP** | `tools/sdk` / `tools/mcp` stdlib Python | `PYTHONPATH` / 绝对路径 | 可选 **pip wheel**（薄封装）；永不内嵌 solc/leo |

## 3. 现状诚实清单

| 项 | 事实 |
|---|---|
| Lake package name | `proof-forge-next` |
| Lake `version` | `0.1.0`（工程占位，**非**已发布 release） |
| GitHub Actions | `ci.yml` 等；**无** release 上传 binary workflow |
| `just release-check` | **未注册**；禁止声称 |
| Formal Stage-0 | 独立命令；非日常完成条件 |
| 产品 build 对外部工程 | 文本路径 + `import ProofForgeV2` **gate 字符串**；**不**要求用户 `lake build` 合约 |
| Python SDK | 文档已写：**未** pip 发布 |
| CLI 二进制特征 | 本机观测约 **263MB**、动态链接、带 debug_info、**未 strip** — 不适合直接当 release 资产不加工 |

## 4. 为什么 Python「看起来像重新包装」

因为 **C 层故意很薄**：

- 实现语言选 Python stdlib → Agent/脚本易接，无第二语言工具链进 Tool Lock
- 契约：`proof-forge-next … --json` 是 sole 产品机读面
- 禁止在 SDK/MCP 内嵌 solc/leo/nargo 或第二 Tool Root 写入器

因此：

- **发版优先级在 A（CLI）**，不在把 Python 做厚  
- C 可以晚于 A 做 pip；没有 A 的稳定安装路径，C 无法独立存在  

## 5. 两轨 SDK 名称（避免歧义）

| 名称（建议） | 层 | 语言 | 职责 |
|---|---|---|---|
| **ProofForge Author SDK** | B | Lean | 写 `program`、语法、（可选）export/elab；用户 `lakefile` `require` |
| **ProofForge Host SDK** | C | Python（未来可 TS） | 调 CLI：doctor/install/build/local/catalog |
| **ProofForge CLI** | A | Lean→native exe | 编译器与物化产品 |

「用 Lean 写的 SDK 用来写合约」= **Author SDK（B）**，不是 Host SDK（C）。

## 6. Engineering 发版切片（建议实现序）

### 6.1 REL-CLI-0 — 版本与身份

- 单一 `PRODUCT_VERSION`（SemVer）与 CLI `--version` / doctor JSON 对齐  
- 绑定 `lean-toolchain` + git describe/commit（dirty 标记）  
- **非** formal BuildIdentity 完成声明  

### 6.2 REL-CLI-1 — binary dist 菜谱

- `just package-cli` / `scripts/package_cli_dist.sh`  
- 输入：已 `lake build proof_forge_next`  
- 输出：`dist/proof-forge-next-<ver>-<platform>.tar.gz` + `.sha256`  
- 内容：`bin/proof-forge-next`（考虑 strip 为可选 profile）、`README`、`VERSION`、`lean-toolchain` 副本  
- **不做**：捆绑整个 monorepo、不捆绑 Tool Lock 工具（leo 仍走 `install`/Tool Lock）  

### 6.3 REL-CLI-2 — 安装面

- 文档：下载 tarball → 校验 digest → 放到 `PATH` 或 `PROOF_FORGE_CLI`  
- 与现有 `proof-forge-next install --targets …` 接：CLI 就位后再装链工具  
- 可选：GitHub Release 上传（engineering tag `v0.x.y`）— **仍非** Stage-0 formal  

### 6.4 REL-AUTHOR-0 — Lean Author SDK 最小包

目标：用户工程：

```lean
-- lakefile.lean
require proof_forge_author from git "…" @ "v0.x.y"
-- 或 path 依赖发布树
```

```lean
import ProofForgeV2  -- 或未来更窄 namespace ProofForge.Author
program Hello where …
```

约束：

- **不得**把整个 materializer/tests 塞进 author 包（体积与依赖爆炸）  
- 首切片：Syntax/export/gate 所需最小 import 闭包（需独立测量与删减）  
- 产品 CLI 仍可纯文本编译；Author SDK 服务 **IDE/编辑体验** 与 lake 工程规范  
- monorepo 可保留 umbrella；author 包是 **可发布投影**，不是第二语义权威  

### 6.5 REL-HOST-0 — Host SDK 可选发布

- `pip install` 仅当 CLI dist 稳定后  
- wheel 内 **无** 编译器二进制强制捆绑（或明确 extra 可选）  
- MCP 继续 stdlib 单文件 + 环境变量指 CLI  

### 6.6 明确不在本阶梯

- formal Stage-0 / hermetic / `governance-check`  
- 把 Python 升格为编译器  
- 默认 MCP network broadcast  
- 因发版改 `deployable=true`  

## 7. 与「外部工程模板」关系

| 路径 | 需要 A CLI dist？ | 需要 B Author SDK？ |
|---|---|---|
| 纯文本 + CLI build/sandbox（当前模板） | **是（体验）** | 否（gate 字符串即可） |
| 用户 Lake 工程 IDE 语法高亮/elab | 是 | **是** |
| Agent 经 MCP | 是（CLI 可发现） | 否 |

当前模板「不 require Lake」是 **诚实 MVP**；发版后应变成：

1. 安装 CLI dist  
2. （可选）require Author SDK  
3. Host SDK/MCP 指到同一 CLI  

## 8. 风险

| 风险 | 缓解 |
|---|---|
| CLI 二进制过大 / 动态链接难移植 | strip profile；记录链接依赖；平台矩阵 linux-x86_64 / darwin-arm64 先 |
| Author 包 import 拖进半个编译器 | 闭包测量 + 只导出 Language/Syntax 层 |
| 把 engineering tag 说成 formal release | 文档与 CI 命名 `engineering-dist` vs `stage0` |
| 双版本漂移（CLI vs Author） | 同一 PRODUCT_VERSION 族；doctor 报告双方 |

## 9. 下一刀实现入口（工程）

1. 写 `scripts/package_cli_dist.sh` + `just package-cli`（本机 linux 先）  
2. CLI `--version` 与 `VERSION` 文件对齐  
3. 文档「安装 CLI dist」替换「必须 lake build  monorepo」为 **推荐路径**（monorepo 仍为开发者路径）  
4. 另开 lane 测量 Author SDK 最小 import 闭包（不阻塞 CLI dist）  

## 10. 一句话

**要做发版打包，而且优先 CLI engineering dist；Python 只是宿主壳；Lean 写合约是另一轨 Author SDK。**  
formal 发布资格仍放整仓最后，不能挡 engineering 分发。
