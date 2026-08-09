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
| 是否第二编译器 | **否**（只 spawn `proof-forge-next`） |
| Channel | `engineering-dist` |
| Formal Stage-0 | **否** |
| 自动发布触发 | push tag `v${VERSION}`（与 CLI 发版同一 workflow） |
| 推荐鉴权 | **PyPI Trusted Publishing (OIDC)**，无长期 token 进仓库 |

## 2. 用户安装

```bash
pip install proof-forge-sdk==0.1.0
export PROOF_FORGE_CLI=/path/to/proof-forge-next   # 必填（多数 API）
# 可选：与 CLI dist 同级
# export PROOF_FORGE_ROOT=/path/to/proof-forge-next-0.1.0-linux-x86_64
python -c "from proof_forge_sdk import ProofForgeClient; print(ProofForgeClient().list_targets().ok)"
```

## 3. CI 行为

Workflow：`.github/workflows/release-engineering-dist.yml` job **`publish-host-sdk-pypi`**

1. `package-portable` 构建 wheel + sdist  
2. 仅在 **tag push** `v${VERSION}` 时运行 publish  
3. 过滤掉 Author/CLI tarball，只上传 Host SDK  
4. `pypa/gh-action-pypi-publish` + **OIDC**（environment `pypi`）  
5. `skip-existing: true`（重复跑不炸）

## 4. 一次性：在 PyPI 配置 Trusted Publisher

在 https://pypi.org/manage/account/publishing/ （或项目 Settings → Publishing）：

| 字段 | 值 |
|---|---|
| PyPI Project name | `proof-forge-sdk` |
| Owner | `DaviRain-Su`（GitHub org/user） |
| Repository | `proof_forge` |
| Workflow name | `release-engineering-dist.yml` |
| Environment name | `pypi` |

首次发布若项目尚不存在：用 **pending publisher** 创建项目，或先在 TestPyPI 试跑。

GitHub 仓库：

1. Settings → Environments → 新建 **`pypi`**  
2. 可选：限制仅 `refs/tags/v*` 可部署  

**不要**把 `PYPI_API_TOKEN` 提交进仓库；本地紧急上传才用 token。

## 5. 本机命令

```bash
just package-host-sdk
just publish-host-sdk-pypi --dry-run          # twine check only
# 真实上传（本地 token）：
# export TWINE_USERNAME=__token__
# export TWINE_PASSWORD=pypi-...
# just publish-host-sdk-pypi
# TestPyPI：
# just publish-host-sdk-pypi --repository testpypi
```

## 6. 重发 / 新版本

1. 改 `VERSION` + Lean `ProductVersionV1.productVersionV1` + `tools/sdk/pyproject.toml` 默认 version  
2. `git tag vX.Y.Z && git push origin vX.Y.Z`  
3. CI 自动 GitHub Release + PyPI  

已发布版本号 **不可覆盖**（PyPI 不可变）；`skip-existing` 仅跳过相同文件。

## 7. 非目标

- 不把 monorepo `build/` 目录打进 wheel  
- 不捆绑 `proof-forge-next` 二进制  
- 不 formal / hermetic 证据  
