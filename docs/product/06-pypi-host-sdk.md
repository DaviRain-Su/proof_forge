---
id: PRODUCT-PYPI-HOST-SDK
title: Host SDK PyPI publish (engineering-dist)
status: draft
owner: product+engineering
updated: 2026-08-09
normative: false
---

# Host SDK → PyPI（engineering-dist）

状态：`draft`（2026-08-09）  
包名：`proof-forge-sdk`  
权威：[`05-distribution-and-packages.md`](05-distribution-and-packages.md) REL-HOST-1  
源：`tools/sdk/` · 版本：根目录 `VERSION`（与 CLI engineering-dist 同号）

## 1. 结论

| 项 | 值 |
|---|---|
| 是否第二编译器 | **否**（Host SDK 只 spawn `proof-forge-next` 并解析 JSON / manifest） |
| Channel | `engineering-dist` |
| Formal Stage-0 / hermetic / release qualification | **否** |
| wheel 是否捆绑 CLI / Tool Lock 工具 | **否**；用户必须显式提供 `PROOF_FORGE_CLI`（多数 API） |
| 自动发布触发 | push tag `v${VERSION}`，与 CLI/Author SDK engineering-dist 同一 workflow |
| 推荐鉴权 | **PyPI Trusted Publishing (OIDC)**；无长期 PyPI token 进仓库 |
| 仓库接线状态 | **done engineering**：workflow job、wheel/sdist staging、twine check 与 OIDC publish 已接线 |
| 外部 PyPI 配置状态 | **owner action required**：首次发布前在 PyPI/TestPyPI 配置 Trusted Publisher |

## 2. 用户安装

```bash
pip install proof-forge-sdk==0.1.1
export PROOF_FORGE_CLI=/path/to/proof-forge-next   # 必填（多数 API）
# 可选：与 CLI dist 同级，用于 doctor/install/local engines
# export PROOF_FORGE_ROOT=/path/to/proof-forge-next-0.1.0-linux-x86_64
python -c "from proof_forge_sdk import ProofForgeClient; print(ProofForgeClient().list_targets().ok)"
```

## 3. CI 行为

Workflow：`.github/workflows/release-engineering-dist.yml` job **`publish-pypi`**（display name `publish-host-sdk-pypi`）。

1. `package-portable` 构建 Author SDK tarball + Host SDK wheel/sdist。
2. `publish-pypi` 只在 **tag push** `v${VERSION}` 运行；`workflow_dispatch` 不发 PyPI。
3. 发布前只 stage `proof_forge_sdk-${VERSION}-*.whl` 与 Host SDK sdist，并显式拒绝 CLI / Author tarball。
4. `twine check pypi-dist/*` 先验 metadata。
5. `pypa/gh-action-pypi-publish` 使用 GitHub OIDC（environment `pypi`，`id-token: write`）。
6. `skip-existing: true`；PyPI 已发布版本不可覆盖。

## 4. Trusted Publisher 一次性配置表

### 4.1 PyPI project publisher

在 PyPI 项目页 **Settings → Publishing** 配置；项目尚不存在时使用 PyPI 的 pending publisher 流程。下列字段必须逐字匹配 GitHub workflow，否则 OIDC 发布会 fail closed。

| Trusted Publisher 字段 | 值 | 说明 |
|---|---|---|
| PyPI Project name | `proof-forge-sdk` | Python package name；不是 CLI asset 名称 |
| Owner | `DaviRain-Su` | GitHub owner / user |
| Repository | `proof_forge` | GitHub repository name |
| Workflow name | `release-engineering-dist.yml` | 文件名，不含 `.github/workflows/` 前缀 |
| Environment name | `pypi` | 必须与 workflow `environment.name` 相同 |

### 4.2 GitHub environment

| GitHub 设置 | 值 | 说明 |
|---|---|---|
| Environment | `pypi` | Repository Settings → Environments |
| Deployment branches/tags | `refs/tags/v*`（推荐） | 与 job 的 tag-only guard 对齐 |
| Required reviewers | maintainer 选择 | 可选；会让 PyPI publish 等待人工批准 |
| Secrets | none required | Trusted Publishing 不需要 `PYPI_API_TOKEN` |

### 4.3 TestPyPI dry run（可选）

TestPyPI 与 PyPI 是独立 issuer 配置；若要先试跑，需要在 TestPyPI 项目配置同名 Trusted Publisher，或本地用 TestPyPI token。

| TestPyPI 字段 | 值 |
|---|---|
| Project name | `proof-forge-sdk` |
| Owner | `DaviRain-Su` |
| Repository | `proof_forge` |
| Workflow name | `release-engineering-dist.yml` |
| Environment name | `pypi`（或另开 `testpypi` 后同步 workflow） |

## 5. Tag 发布 runbook

```bash
# VERSION 文件 = 0.1.0 时，tag 必须 exact match：
git tag v0.1.0
git push origin v0.1.0
# → package CLI multi-arch + Author SDK + Host SDK
# → GitHub prerelease engineering-dist
# → PyPI Host SDK publish via Trusted Publishing
```

失败排查：

| 现象 | 优先检查 |
|---|---|
| workflow tag gate 失败 | tag 是否 exact `v$(cat VERSION)` |
| PyPI OIDC unauthorized | PyPI Trusted Publisher 的 Owner/Repository/Workflow/Environment 是否逐字匹配 |
| package already exists | PyPI 版本不可变； bump `VERSION` 后重发 |
| non-Host artifact staged | `publish-pypi` staging step 会拒绝 CLI / Author tarball，保持 Host SDK-only |

## 6. 本机命令

```bash
just package-host-sdk
just publish-host-sdk-pypi --dry-run          # twine check only
# 真实上传（本地 token；仅紧急路径，不推荐长期使用）：
# export TWINE_USERNAME=__token__
# export TWINE_PASSWORD=pypi-...
# just publish-host-sdk-pypi
# TestPyPI：
# just publish-host-sdk-pypi --repository testpypi
```

## 7. 重发 / 新版本

1. 改根目录 `VERSION`、Lean `ProductVersionV1.productVersionV1` 与 `tools/sdk/pyproject.toml` 默认 version。
2. 本地跑 `just package-host-sdk-smoke` 与 `just docs-check`。
3. 推送 exact tag `vX.Y.Z`。
4. CI 自动 GitHub Release + PyPI。

已发布版本号 **不可覆盖**；`skip-existing` 只跳过同版本已存在文件，不代表内容可替换。

## 8. 非目标

- 不把 monorepo `build/` 目录打进 wheel。
- 不捆绑 `proof-forge-next` 二进制或 Tool Lock 工具。
- 不用 PyPI token 替代 repository OIDC 作为默认 CI 路径。
- 不声明 formal / hermetic / Stage-0 / mainnet / proof 完成。
