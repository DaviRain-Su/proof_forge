// AUTO-GENERATED — do not edit by hand.
export const CATALOG_JSON = {
  "schema": "proof-forge.chain-client-catalog.v1",
  "version": "1",
  "updated": "2026-08-10",
  "notes": [
    "Metadata only for authors and Code Agents. Not a second compiler.",
    "clientSdk fields name ecosystem packages; ProofForge does not vendor or pin them here.",
    "pfSurface describes product CLI/MCP/SDK entry points only.",
    "deployable is always false on product OutputSet until N3 product decision.",
    "No network broadcast tools on MCP default surface."
  ],
  "targets": [
    {
      "id": "aleo",
      "implemented": true,
      "maturityLabel": "direct-instructions zero-tool",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ],
        "template": "templates/external-aleo-hello"
      },
      "frontendClients": [
        {
          "name": "Aleo SDK / Provable SDK (ecosystem)",
          "kind": "js-ts",
          "purpose": "wallet, program query, transaction submit outside ProofForge",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": null
      },
      "honesty": [
        "deployable=false on product build",
        "canonical Aleo Instructions and query descriptor only",
        "no Leo compiler, local runtime, or network wrapper"
      ]
    },
    {
      "id": "evm",
      "implemented": true,
      "maturityLabel": "runtime-validated-alpha",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [
          "runtime"
        ],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_local",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [
        {
          "name": "ethers / viem / wagmi (ecosystem)",
          "kind": "js-ts",
          "purpose": "RPC, wallet, ABI call for dApp UI",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "Anvil engineering differential (host-heavy)"
      },
      "honesty": [
        "product OutputSet deployable depends on profile; do not invent mainnet"
      ]
    },
    {
      "id": "solana",
      "implemented": true,
      "maturityLabel": "plan-only / ELF engineering",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [
          "runtime"
        ],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_local",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [
        {
          "name": "@solana/web3.js / wallet-adapter (ecosystem)",
          "kind": "js-ts",
          "purpose": "RPC, wallet, instruction send",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "Mollusk runtime tests (host-heavy; not ordinary ci)"
      },
      "honesty": [
        "Principal is not Solana pubkey globally"
      ]
    },
    {
      "id": "near",
      "implemented": true,
      "maturityLabel": "wasm-validated-alpha",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [
        {
          "name": "near-api-js (ecosystem)",
          "kind": "js-ts",
          "purpose": "account, call, view",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "near-sandbox engineering (host-heavy)"
      },
      "honesty": []
    },
    {
      "id": "noir",
      "implemented": true,
      "maturityLabel": "source-only + ACIR dual-write engineering",
      "role": "backend-circuits",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [
        {
          "name": "bb.js / noir.js (ecosystem; not product prove)",
          "kind": "js-ts",
          "purpose": "circuit UX outside product prove path",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "nargo compile-only engineering; prove/VK fail-closed honesty"
      },
      "honesty": [
        "ACIR dual-write is opt-in profile; default is source relations"
      ]
    },
    {
      "id": "psy",
      "implemented": true,
      "maturityLabel": "direct-dpn zero-tool",
      "role": "backend-zk-application-chain",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": null
      },
      "honesty": [
        "canonical DPN package only; no Psy source, Dargo, local VM, or proof lane"
      ]
    },
    {
      "id": "quint",
      "implemented": true,
      "maturityLabel": "source-only executable model",
      "role": "backend-model",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "zero-tool .qnt emission; product does not run Quint/Apalache"
      },
      "honesty": [
        "not a deployable chain target"
      ]
    },
    {
      "id": "cosmwasm",
      "implemented": true,
      "maturityLabel": "wasm-validated-alpha",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [
        {
          "name": "cosmjs (ecosystem)",
          "kind": "js-ts",
          "purpose": "Cosmos LCD/RPC, signing",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "cosmwasm-vm mock + wasmd engineering rungs"
      },
      "honesty": [
        "sync call FC; async SubMsg subset"
      ]
    },
    {
      "id": "ton",
      "implemented": true,
      "maturityLabel": "source-only + sandbox engineering",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [],
        "network": "none-product",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [
        {
          "name": "TON Connect / @ton/core (ecosystem)",
          "kind": "js-ts",
          "purpose": "wallet and message UX",
          "shippedByProofForge": false
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "TON sandbox engineering (host-heavy)"
      },
      "honesty": []
    },
    {
      "id": "soroban",
      "implemented": false,
      "maturityLabel": "design-only",
      "role": "design-only",
      "pfSurface": {
        "build": false,
        "localModes": [],
        "network": "none",
        "mcpTools": [
          "pf_list_targets",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": null
      },
      "honesty": [
        "unsupported for install/build"
      ]
    },
    {
      "id": "icp",
      "implemented": false,
      "maturityLabel": "design-only",
      "role": "design-only",
      "pfSurface": {
        "build": false,
        "localModes": [],
        "network": "none",
        "mcpTools": [
          "pf_list_targets",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": null
      },
      "honesty": [
        "unsupported for install/build"
      ]
    },
    {
      "id": "openvm",
      "implemented": false,
      "maturityLabel": "design-only",
      "role": "design-only",
      "pfSurface": {
        "build": false,
        "localModes": [],
        "network": "none",
        "mcpTools": [
          "pf_list_targets",
          "pf_chain_catalog"
        ]
      },
      "frontendClients": [],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": null
      },
      "honesty": [
        "unsupported for install/build"
      ]
    }
  ]
} as const;

export const DOCS_INDEX_JSON = {
  "schema": "proof-forge.mcp.docs-index.v1",
  "docs": [
    {
      "id": "01-toolchain-install-surface.md",
      "title": "产品面阶梯：安装选链 → 本机验证 → SDK / MCP",
      "bytes": 17876,
      "kind": "markdown"
    },
    {
      "id": "02-external-program-v1.md",
      "title": "外部 ProgramV1 工程：写合约 → build → inspect",
      "bytes": 4176,
      "kind": "markdown"
    },
    {
      "id": "03-hello-dapp-agent-playbook.md",
      "title": "Hello dApp：Code Agent 剧本（后端合约 + direct artifact）",
      "bytes": 3546,
      "kind": "markdown"
    },
    {
      "id": "04-chain-client-catalog.md",
      "title": "多链客户端 / 前端 catalog（元数据）",
      "bytes": 2844,
      "kind": "markdown"
    },
    {
      "id": "05-distribution-and-packages.md",
      "title": "分发架构：CLI 发版 · Lean 写合约包 · 宿主 SDK/MCP",
      "bytes": 16425,
      "kind": "markdown"
    },
    {
      "id": "aleo-testnet-walkthrough.md",
      "title": "Demo: Aleo with `pf` — local run → Testnet deploy → execute",
      "bytes": 11087,
      "kind": "markdown"
    },
    {
      "id": "chain-client-catalog.v1.json",
      "title": "chain-client-catalog.v1",
      "bytes": 8832,
      "kind": "catalog"
    },
    {
      "id": "mcp-stdio-readme.md",
      "title": "ProofForge MCP-V0",
      "bytes": 3129,
      "kind": "markdown"
    }
  ]
} as const;

export const MARKDOWN: Record<string, string> = {
  "01-toolchain-install-surface.md": "---\nid: PRODUCT-TOOLCHAIN-INSTALL-SURFACE\ntitle: Product surface ladder — install / doctor / CLI / MCP\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# 产品面阶梯：安装选链 → 本机验证 → SDK / MCP\n\n状态：`draft`（2026-08-10；I0–I2 + MCP-V0 + SDK-V0 + distribution REL-CLI/Author/CI engineering done；Aleo/Psy tool/runtime lanes removed）\n执行入口：workflow `product-surface-ladder`（`.grok/workflows/product-surface-ladder.rhai`）\nTool Lock 规范：[`specs/toolchains.md`](../specs/toolchains.md)（`proof-forge.toolchains.v4`）\n\n## 0. 实现状态（诚实）\n\n| 相位 | 状态 |\n|---|---|\n| **DOC**（本文 + index 指针） | **done**（本文件） |\n| **I0 doctor** | **done**（`scripts/proof_forge_doctor.py` + `proof-forge-next doctor`；schema `proof-forge.doctor.v1`；缺 Tool Root → `PF-TOOLCHAIN-MISSING`） |\n| **I1 install** | **done**（`scripts/proof_forge_install.py` + `proof-forge-next install`；schema `proof-forge.install.v1`；`--targets`/`--all-core` + `--yes`；delegate `toolchain_assets` provision/materialize；digest 幂等 skip；无 PATH fallback；`--dry-run` 计划-only） |\n| I1b CLI wire residual | **done with I1**（CLI 薄包装 + parse 覆盖 + `scripts/install_smoke.sh`；若后续扩 usage 文案仍可叠） |\n| I2 local/network 统一包装 | **done / narrowed**（`local` 仅保留 EVM/Solana runtime wrappers；`network` 对全部 target fail closed；`scripts/local_network_smoke.sh`） |\n| **MCP-V0** | **done**（`tools/mcp/proof_forge_mcp_server.py` stdio MCP；tools: `pf_list_targets`/`pf_doctor`/`pf_install`/`pf_build`/`pf_artifacts`；仅 spawn 产品 CLI/引擎 JSON；无 network broadcast 工具；`tools/mcp/README.md` Agent 接线；`scripts/mcp_smoke.sh`） |\n| **SDK-V0** | **done**（Python `tools/sdk/proof_forge_sdk.py`：`ProofForgeClient` spawn `proof-forge-next` + parse doctor/install/list-targets JSON + `load_output_manifest` for engineering `proof-forge.output.v1`；非第二编译器；`tools/sdk/README.md`；`scripts/sdk_smoke.sh`） |\n| **Close** | **done**（本文 + index 成熟度诚实；剩余 backlog：交互式 install UI、全链 runtime pack、N3 前 `deployable=true` 禁改） |\n| **External ProgramV1** | **done engineering**（[`02-external-program-v1.md`](02-external-program-v1.md) + `templates/external-aleo-hello/` + sandbox/SDK/MCP `--root` + `just external-hello-smoke`；非 Lake SDK / formal） |\n| **Hello agent playbook** | **done engineering**（[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)；MCP 顺序 doctor→install→build/local→artifacts） |\n| **Chain client catalog** | **done engineering**（[`04-chain-client-catalog.md`](04-chain-client-catalog.md) + `chain-client-catalog.v1.json` + `pf_chain_catalog` / SDK `chain_catalog`；元数据 only） |\n| **Distribution / packages** | **engineering-dist + PyPI wiring done**（[`05-distribution-and-packages.md`](05-distribution-and-packages.md) / [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)：CLI multi-arch、Author SDK、Host wheel+OIDC PyPI job；Trusted Publisher 需一次人工配置；formal Stage-0 仍 pending） |\n\n本文是 **产品契约与实现顺序** 的权威草稿；I0–I2、MCP-V0、SDK-V0 与 distribution engineering dist 已接线。Aleo/Psy 仅保留 zero-tool direct materializer；不再提供 Leo/Dargo/snarkOS/local VM/network 产品或工程 lane。不声称 formal / hermetic / mainnet / Stage-0。\n\n## 1. 产品目标\n\n用户安装 / 使用 ProofForge 时：\n\n1. **知道** 当前支持哪些 target（`TargetRegistryV1` 事实，非营销名单）。\n2. **选择** 要开发的链，安装对应 **Tool Lock** 锁定工具到 `PROOF_FORGE_TOOL_ROOT`。\n3. **诊断** 缺工具 / digest 不匹配（`doctor`），再 **build / local / network**。\n4. 后续 **SDK / MCP** 只封装同一 CLI 契约，供 Code Agent 做 Web Coding。\n\n## 2. 非目标\n\n- 不把 install 变成「静默 PATH 扫全盘随便装」。\n- 不默认 `deployable=true` 或主网广播（无产品 N3 决策不得改写 maturity）。\n- 不在 ordinary `just ci` 里起 snarkOS / Anvil / Mollusk。\n- 不先做大而全多语言 SDK；先 CLI + 薄封装。\n- design-only target（`soroban` / `icp` / `openvm`）只展示为 `unsupported`，不提供假安装。\n- 不发明 Tool Lock 外的第二工具权威或 “best effort” fallback 进 Tool Root。\n\n## 3. 阶梯切片（workflow 相位）\n\n| 相位 | ID | 交付 | 完成标准 |\n|---|---|---|---|\n| DOC | `DOC` | 本文 + `docs/index.md` 指针 | `just docs-check` 过 |\n| I0 | `I0-DOCTOR` | `proof-forge-next doctor` | **done**：每 implemented target 报告 ok/missing/mismatch/partial；`--json`=`proof-forge.doctor.v1`；无 Tool Root → `PF-TOOLCHAIN-MISSING`；引擎 `scripts/proof_forge_doctor.py`；CLI 薄包装 |\n| I1 | `I1-INSTALL` | 非交互 `install --targets a,b --yes` | **done**：`scripts/proof_forge_install.py`；复用 `toolchain_assets` provision/materialize；只装 lock 内 asset；digest 校验；幂等 skip；`--dry-run`/`--json`；`scripts/install_smoke.sh` |\n| I1b | `I1b-CLI-WIRE` | CLI 子命令接到 Exe；`--json`；usage | **done with I1**：`proof-forge-next install` 薄包装 + parse 覆盖 |\n| I2 | `I2-LOCAL-CMDS` | 统一本机入口包装 | **done / narrowed**：`local --target evm|solana` 调现有 runtime 脚本；`network` 全 target fail closed；`scripts/local_network_smoke.sh` |\n| MCP | `MCP-V0` | 最小 MCP server | **done**：`tools/mcp/proof_forge_mcp_server.py`；tools 含 `pf_local`（仅 EVM/Solana）+ build/doctor；拒 network broadcast；见 §8 |\n| SDK | `SDK-V0` | 可选薄 SDK（TS 或 Python 选一） | **done**（Python）：`tools/sdk/proof_forge_sdk.py`；spawn CLI + `local` 通用 API + parse manifest；非第二编译器；见 §9 |\n| Close | `Close` | AGENTS/backlog 指针 | **done**：成熟度诚实；不声称 formal / hermetic / mainnet；剩余见 §0 Close 行 |\n\n## 4. 架构约束\n\n```text\nUser / Agent\n    │\n    ▼\nproof-forge-next  (sole product CLI)\n    │  doctor | install | build | check | local | network | inspect | list-targets\n    ▼\nscripts/toolchain_assets.py  +  Tool Lock v4\n    │\n    ▼\nPROOF_FORGE_TOOL_ROOT/   # default: ~/.cache/proof-forge-v2/tool-root/<platform>/\n    solc, sbpf, nargo, wat2wasm, anvil, …  (lock-defined only)\n```\n\n### 4.1 Tool Lock 权威菜单\n\n| File | `platform` | 备注 |\n|---|---|---|\n| `toolchains.lock.json` | `darwin-arm64` | Mach-O policy |\n| `toolchains-linux-x86_64.lock.json` | `linux-x86_64` | ELF policy |\n\n- Schema：`proof-forge.toolchains.v4`（见 SPEC-TOOL-001）。\n- **当前无** `linux-aarch64` 等其它平台 lock；未锁平台上 install 必须 fail closed。\n- 引擎：`scripts/toolchain_assets.py`（provision / materialize / verify）；产品 install 是其薄 CLI 包装，不复制第二份下载逻辑。\n- **禁止** PATH fallback 把非 lock 二进制写入 `PROOF_FORGE_TOOL_ROOT`。\n\n### 4.2 Target 菜单\n\n- **Implemented（可 install 编译档）**：`evm`、`solana`、`near`、`noir`、`aleo`、`psy`、`quint`、`cosmwasm`、`ton`（与 `TargetRegistryV1` 九 materializer 一致）。\n- **Design-only（`unsupported`，不可 install）**：`soroban`、`icp`、`openvm`。\n- Accepted PRD Phase 1 文案仍为四目标；engineering 九 target 扩面不自动改写 accepted 范围（ADR-0036）。\n\n### 4.3 编译档 vs runtime 档\n\n| 档 | 默认 `install` | 例 |\n|---|---|---|\n| **core / compile** | 是（`--targets` / `--all-core`） | `solc`、`sbpf`、`nargo`、`wat2wasm`、`tolk`、`cosmwasm-check`、`jv` |\n| **runtime** | 否；需 `--with-runtime` 或 `--profile runtime` | lock：`anvil`/`cast`、`near-sandbox` |\n\nhost-heavy 门（`just solana-runtime` / Anvil）**不**并入 ordinary `just ci`。\n\n### 4.4 Implemented target → lock tools（doctor 规划表）\n\n| Target | core tools（Tool Lock ids） | runtime / 额外 |\n|---|---|---|\n| `evm` | `solc` | `anvil`、`cast`（runtime 档） |\n| `solana` | `sbpf` | Mollusk 等工程 harness（非本 lock 的 install 默认面；runtime 文档另述） |\n| `near` | `wat2wasm` | `near-sandbox`（runtime） |\n| `noir` | `nargo` | prove/VK / barretenberg：**unresolved / FC**（见 lock `unresolved.barretenberg`） |\n| `aleo` | —（sole `aleo-instructions-v1` zero-tool） | 无 compiler/runtime/network lane |\n| `psy` | —（sole `psy-dpn-v1` zero-tool） | 无 compiler/runtime/network lane |\n| `quint` | `jv`（模型侧辅助；Quint 产品 finalize 仍 zero-tool source） | 无 snarkOS 类 runtime |\n| `cosmwasm` | `wat2wasm`、`cosmwasm-check` | wasmd Docker rung 等工程门，非 CLI 默认 install |\n| `ton` | `tolk` | sandbox 工程门独立 |\n\n表中 “core” 是 doctor/install 的 **规划映射**；某 profile 的 exact `requiredByProfiles` 仍以 lock 字段为准，不得在 doctor 里发明额外工具。\n\n## 5. doctor 输出契约（I0）\n\n对 zero-tool direct target，doctor 必须明确报告空工具集合，而不是要求已删除的编译器：\n\n```text\nplatform=linux-x86_64\ntool_root=...\ntarget=aleo status=ok\n```\n\n```json\n{\n  \"schema\": \"proof-forge.doctor.v1\",\n  \"platform\": \"linux-x86_64\",\n  \"toolRoot\": \"...\",\n  \"targets\": [\n    {\"id\": \"aleo\", \"status\": \"ok\", \"tools\": []},\n    {\"id\": \"psy\", \"status\": \"ok\", \"tools\": []}\n  ]\n}\n```\n\n状态枚举：`ok` | `partial` | `missing` | `mismatch` | `unsupported`。\n\n- 无 `PROOF_FORGE_TOOL_ROOT` 且默认 cache 不存在 → fail closed：stderr `PF-TOOLCHAIN-MISSING: tool root does not exist: …`，exit 3。\n- `PROOF_FORGE_TOOL_ROOT` 非绝对路径 → `PF-TOOLCHAIN-MISMATCH`，exit 3。\n- 对所有非 zero-tool target，Tool Root 采用 **current-lock exact-set closure**：允许只物化所选 target 的 lock 子集，但任何不属于当前全局 Tool Lock 的文件、目录、symlink 或 special node 都使 target 为 `mismatch`，并给出 `install --all-core --yes` 修复提示。这样已退役工具不会再出现 doctor 绿、构建门禁红。\n- design-only id → `unsupported`，不假装可装。\n- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_doctor.py`；产品 CLI：`proof-forge-next doctor` 通过 `PackageRootV1` 解析 package root（`PROOF_FORGE_ROOT` 绝对路径 → `IO.appDir` 父目录含 `scripts/` → CWD），并以 `cwd=packageRoot` spawn。\n- 聚焦 smoke：`scripts/doctor_smoke.sh`。\n\n## 6. install 契约（I1）\n\n```bash\nproof-forge-next install --targets solana --yes\nproof-forge-next install --all-core --yes   # 所有 implemented target 的非空 compile/core 档\n```\n\n- 无 `--yes` 且非 `--dry-run` → usage / fail closed（非交互；不提供 TTY 确认）。\n- 禁止 PATH fallback 安装进 Tool Root。\n- 已存在且 digest 匹配 → skip（幂等）。\n- 只物化 **当前平台 lock** 中的 asset；跨平台/缺锁 fail closed。\n- 每次 install（包括 zero-tool target）都会扫描 Tool Root：保留当前 lock 中尚未选装的合法成员，清除不再属于当前 lock 的退役节点；`--dry-run` 只在 `notes` 报告 `would remove`，不落盘。\n- `--with-runtime` 仅物化 lock 内 runtime 工具（`anvil`/`cast`、`near-sandbox`）；Aleo/Psy 没有 runtime 配方或外部工具 fallback。\n- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_install.py`；产品 CLI：`proof-forge-next install` 同样经 `PackageRootV1` 定位 package root并以 `cwd=packageRoot` spawn。\n- 聚焦 smoke：`scripts/install_smoke.sh`（含 temp root 上 `quint`/`jv` 物化 + 幂等 skip + Aleo/Psy zero-tool + 退役 `leo` dry-run/清理断言）。\n- 成功后同一进程或紧随 `doctor` 可验证 present。\n\n## 7. 本机包装（I2）\n\n**已实现并收窄**。`local` 只保留 EVM/Solana 已有 runtime wrapper；Aleo/Psy 及其它 target\nfail closed。已删除无实现 target 的 `network` 子命令：\n\n```bash\nproof-forge-next local --target solana [--mode runtime] [--json] [--] [script-args...]\nproof-forge-next local --target evm [--mode runtime] [--json] [--] [script-args...]\n```\n\n| Target | `local` 模式（默认） | 包装脚本 | 等价工程入口 |\n|---|---|---|---|\n| `solana` | `runtime`（默认） | `scripts/solana_runtime_test.sh` | `just solana-runtime` |\n| `evm` | `runtime`（默认） | `scripts/evm_anvil_differential.sh` | Anvil engineering smokes |\n| 其它 implemented | — | fail closed（无产品 script path） | 见 target dossier |\n| design-only | — | fail closed `unsupported` | 不可 install/local |\n\n- local wrapper 经 `PackageRootV1` 定位 package root，以 `cwd=packageRoot` 固定执行 `/bin/bash -p`，\n  并设置 `PROOF_FORGE_ROOT=packageRoot`；禁止 PATH/BASH_ENV fallback。\n- 顶层 `network` 子命令已删除，作为未知命令以 usage / exit 2 拒绝；build 的 `--network`\n  flag 同样为 usage error，因为尚无 network registry。\n- schema 仅为 `proof-forge.local.v1`；不得在 JSON 中暴露秘密。\n- 聚焦门：`scripts/local_network_smoke.sh`。实际 runtime 仍 host-heavy，不并入 ordinary CI 或 formal evidence。\n\n## 8. MCP-V0 工具列表 — **done**\n\n实现：`tools/mcp/proof_forge_mcp_server.py`（stdlib-only stdio JSON-RPC MCP；newline 分隔；stderr 日志）。\n接线说明：`tools/mcp/README.md`。聚焦 smoke：`scripts/mcp_smoke.sh`。\n\n| Tool | 映射 |\n|---|---|\n| `pf_list_targets` | `list-targets [--all] --json` → `proof-forge.cli.list-targets.v1` |\n| `pf_doctor` | `doctor --json` → `proof-forge.doctor.v1` |\n| `pf_install` | `install --targets … --yes`（或 `--dry-run`）`--json` → `proof-forge.install.v1` |\n| `pf_build` | `build` source `--module` `--target` `-o` `--json`（**拒** broadcast/network 参数） |\n| `pf_artifacts` | `inspect --output-dir <dir> --json` 或 `inspect <target> --json` |\n| `pf_local` | `local --target … [--mode sandbox]` + 透传 script args；Aleo sandbox **通用** 须 `source`+`module`（可选 `root`/`runs`/`golden`/`skipRun`；有 `root` 时传为 product `--root`）；**拒** broadcast / private-key |\n| `pf_chain_catalog` | 静态 `docs/product/chain-client-catalog.v1.json`（前后端分工元数据；不装前端包、不 broadcast） |\n\nV0+ 已暴露 `pf_local` 与 `pf_chain_catalog`；**仍不**暴露 network broadcast 工具（network 必须显式 `network --broadcast`，不经 MCP 默认面）。Hello 剧本见 [`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)。\n返回包装 schema：`proof-forge.mcp.tool-result.v1`（`ok`/`exitCode`/`command`/`stdout`/`stderr`/`parsed`/`error`）。\nEnv：`PROOF_FORGE_ROOT` / `PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT`（继承 doctor/install/build 契约）。\nMCP **只** spawn 产品 CLI 并解析 JSON/manifest，不内嵌 solc/leo/nargo；不 PATH fallback 写 Tool Root；不改 `deployable`。\n\n## 9. SDK-V0 — **done**（Python）\n\n实现：`tools/sdk/proof_forge_sdk.py`（stdlib-only；可选 `PYTHONPATH=tools/sdk`）。\n接线说明：`tools/sdk/README.md`。聚焦 smoke：`scripts/sdk_smoke.sh`。\n\n| API | 映射 |\n|---|---|\n| `ProofForgeClient.list_targets` | `list-targets [--all] --json` → `proof-forge.cli.list-targets.v1` |\n| `ProofForgeClient.doctor` | `doctor --json` → `proof-forge.doctor.v1`（exit 3 + body 仍 `ok` 给 Agent） |\n| `ProofForgeClient.install` | `install --yes`/`--dry-run --json` → `proof-forge.install.v1` |\n| `ProofForgeClient.build` / `check` | 产品 `build`/`check --json`；**拒** design-only target；**无** network/broadcast |\n| `ProofForgeClient.inspect_artifacts` / `inspect_target` | `inspect --output-dir` / `inspect <target> --json` |\n| `ProofForgeClient.local` | `local --target …`；Aleo sandbox 透传 `--source`/`--module`/`--root`/`--run`（通用；有 `root=` 时传为 product `--root`；拒 broadcast/signer） |\n| `ProofForgeClient.chain_catalog` | 静态 chain client catalog（`proof-forge.chain-client-catalog.v1`） |\n| `load_output_manifest` / `client.load_output_manifest` | 读 on-disk `manifest.json` 的 engineering `schemaVersion=proof-forge.output.v1`（**不**重走 exact disk closure；closure 用 `inspect_artifacts`） |\n\n- 返回载体 schema：`proof-forge.sdk.result.v1`（`ok`/`exitCode`/`command`/`stdout`/`stderr`/`parsed`/`error`/`productOk`）。\n- Env：`PROOF_FORGE_ROOT` / `PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT`（与 MCP/CLI 相同契约）。\n- **非**第二编译器、**非**第二 Tool Root 写入器、**无** PATH fallback 物化 lock tools、**不**改 `deployable`。\n- 未做：TS SDK、交互式 install UI、全链 runtime pack 一键装、pip 发布。\n\n## 11. 与现有脚本 / CLI 关系\n\n| 现有 | 角色 |\n|---|---|\n| `scripts/toolchain_assets.py` | install 引擎（I1 复用） |\n| `toolchains*.lock.json` | 唯一可装 tool 菜单 |\n| `just toolchains-*` | 工程/CI 旁路；产品 CLI 成后文档主推 CLI |\n| `proof-forge-next` 现有 | `build` / `check` / `inspect` / `list-targets` / **`doctor`** / **`install`** / **`local`** / **`network`** |\n| `tools/mcp/proof_forge_mcp_server.py` | MCP-V0 stdio 薄封装（仅 spawn 上列 CLI JSON） |\n| `tools/sdk/proof_forge_sdk.py` | SDK-V0 Python 薄客户端（spawn CLI + parse JSON/manifest） |\n| `scripts/solana_runtime_test.sh` / `scripts/evm_anvil_differential.sh` | I2 `local --target solana|evm`；`just solana-runtime` / Anvil 工程 lane 仍可用 |\n\n## 12. 验证\n\n- 每切片：聚焦测或脚本 smoke + `just docs-check`。\n- 改 Lean 产品面时按 AGENTS 跑相关测 + 必要时 `just sbom-package-files-refresh`。\n- 不声称 ordinary ci 已含 host-heavy runtime。\n- 不声称 formal Stage-0 / hermetic / mainnet / release。\n\n## 13. 相关文档\n\n- Tool Lock：[`specs/toolchains.md`](../specs/toolchains.md)\n- CLI 规格：[`specs/cli.md`](../specs/cli.md)\n- 导航：[`index.md`](../index.md)\n- 工作流：`.grok/workflows/product-surface-ladder.rhai`\n",
  "02-external-program-v1.md": "---\nid: PRODUCT-EXTERNAL-PROGRAM-V1\ntitle: External ProgramV1 project guide (build / SDK / MCP)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# 外部 ProgramV1 工程：写合约 → build → inspect\n\n状态：`draft`（2026-08-10；external ProgramV1 build surface）\n前置：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)\n\n## 1. 权威范围与目标\n\n本文说明外部目录如何满足 source gate、如何用 `--root` + 相对 `--source` 调用 build，\n以及 SDK/MCP 对同一 build/inspect 契约的字段映射。它不扩大 target maturity，也不替代\nCLI、Aleo target 或 OutputSet 规格。\n\n作者在 **ProofForge monorepo 之外**维护一个最小工程目录，用产品 CLI\n`build --target aleo` 得到 canonical Instructions + query-contract，再经 `inspect`、SDK 或 MCP\n复用同一 OutputSet 契约。Aleo 没有 Leo sandbox/runtime/network 产品 lane。\n\n**不要求** 外部工程 `require` Lake 包 `proof-forge-next`。产品 `build` 路径是进程内\n`IO.FS.readFile` → Loader，不是 `lake build` 用户包。\n\nCloseout honesty：external source tree + `--root` build 与 SDK/MCP build 字段映射已接线。Aleo profile 是 zero-tool `aleo-instructions-v1`，保持 **`deployable=false`**；无本地执行、网络广播或 formal/release 声明。\n\n## 2. 源文件契约\n\n| 规则 | 说明 |\n|---|---|\n| 文件扩展名 | `.lean` |\n| 必填首行门 | 源文本须 **exact** 含 `import ProofForgeV2`（产品 gate；非 Lake 解析） |\n| 程序形状 | 统一 `program Name where …`（用户不写顶层 kind） |\n| `--source` | 相对 `--root` 的规范相对路径（如 `src/Hello.lean`） |\n| `--module` | 必填 pure Lean module 标识（可与 program 名不同；模板用 `Hello`） |\n| `--root` | 外部工程根；省略时默认 CLI CWD / 包根（见 CLI 规格） |\n\n最小 Hello 是一个 UInt64 counter：`init` / `entry increment` / `view get`。\n\n## 3. 推荐目录\n\n```text\nmy-dapp-contracts/           # --root\n  README.md\n  src/\n    Hello.lean              # import ProofForgeV2 + program Hello where …\n  out-aleo/                 # build -o（gitignore）\n```\n\n\n## 4. 命令阶梯（Aleo direct Instructions）\n\n```bash\nexport PF=/path/to/proof_forge\nexport PROOF_FORGE_CLI=$PF/.lake/build/bin/proof-forge-next\nexport PROJ=/path/to/my-dapp-contracts\n\n# 0) doctor（Aleo 为 zero-tool target）\n(cd \"$PF\" && \"$PROOF_FORGE_CLI\" doctor --target aleo --json)\n\n# 1) build\n\"$PROOF_FORGE_CLI\" build src/Hello.lean \\\n  --module Hello --target aleo --root \"$PROJ\" -o \"$PROJ/out-aleo\"\n\n# 2) inspect\n\"$PROOF_FORGE_CLI\" inspect --output-dir \"$PROJ/out-aleo\" --json\n```\n\n生成的 `.aleo` 是 canonical Aleo Instructions 制品；query descriptor 只描述 network-state 查询契约。\n产品不调用 Leo、snarkOS 或其它本地/网络 runtime。\n\n## 5. SDK / MCP\n\n| 面 | 用法 |\n|---|---|\n| SDK | `client.build(..., target=\"aleo\", root=…)` 后读取 OutputSet manifest |\n| MCP | `pf_build` 后用 `pf_artifacts` 检查 exact disk closure |\n\nAgent 剧本：\n\n1. `pf_doctor`（target=aleo；预期 zero-tool `ok`）\n2. 写/改 `src/Hello.lean`\n3. `pf_build`\n4. `pf_artifacts` 看 OutputSet\n\nMCP-V0 不暴露 Aleo local/network action。\n\n## 6. 非目标\n\n- 不要求外部工程作为 Lake SDK package 依赖 `proof-forge-next`；CLI source gate 已足够\n- 不提供完整 Lean IDE 插件 / 语法高亮包（可后续）\n- 不把 monorepo `Examples` 设为 sole 外部入口\n- 不设 `deployable=true`、不 formal、不主网\n- 不提供 Aleo compiler、local runtime、network deploy/execute 或其 fallback\n\n## 7. 聚焦门\n\n外部模板复用 ordinary product build/inspect smoke；不再有 Aleo-specific external sandbox recipe。\n\n## 8. 成熟度\n\n| 层 | 状态 |\n|---|---|\n| 外部源 + `--root` build | **engineering done** |\n| Direct Instructions + query descriptor | **engineering done** |\n| MCP / SDK external root fields | **engineering done** |\n| Local/compiler/network runtime | **removed / unsupported** |\n| Lake syntax package | **optional remaining**（not required for product build） |\n| Formal / release | **remaining** |\n",
  "03-hello-dapp-agent-playbook.md": "---\nid: PRODUCT-HELLO-DAPP-AGENT-PLAYBOOK\ntitle: Hello dApp agent playbook (MCP / SDK / external template)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Hello dApp：Code Agent 剧本（后端合约 + direct artifact）\n\n状态：`draft`（2026-08-10）\n前置：[`02-external-program-v1.md`](02-external-program-v1.md)、[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)  \nCatalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md) / `pf_chain_catalog`\n\n## 1. 范围\n\n本剧本让 **Code Agent**（经 MCP）或脚本（经 SDK/CLI）完成 **hello 级 artifact 闭环**：\n\n```text\ndoctor → 写/确认 ProgramV1 → build → inspect artifacts\n```\n\n**后端** = ProofForge `program … where` 合约。  \n**前端** = 生态客户端（见 chain catalog）；本剧本 **不** 生成完整 Web UI，只钉后端可测。\n\n## 2. 非目标\n\n- MCP **不**暴露 `network --broadcast` / private-key\n- 不设 `deployable=true`、不主网、不 formal\n- 不发明 Aleo compiler/local runtime/network fallback\n- 不要求外部工程 Lake `require` PF\n\n## 3. 环境\n\n| 变量 | 含义 |\n|---|---|\n| `PROOF_FORGE_ROOT` | monorepo 根（含 `scripts/`、`tools/mcp/`） |\n| `PROOF_FORGE_CLI` | `proof-forge-next` 绝对路径 |\n| `PROOF_FORGE_TOOL_ROOT` | Tool Lock 根；Aleo direct target 不需要工具 |\n\nMCP 接线见 [`tools/mcp/README.md`](../../tools/mcp/README.md)。\n\n## 4. MCP 工具顺序（Aleo Hello）\n\n| 步 | Tool | 参数（示意） | 成功判据 |\n|---|---|---|---|\n| 0 | `pf_chain_catalog` | `target=aleo` | 看到 direct artifact + honesty |\n| 1 | `pf_doctor` | `targets=[\"aleo\"]` | JSON `proof-forge.doctor.v1`；zero-tool `ok` |\n| 2 | 写源 | 文件系统 | `import ProofForgeV2` + `program Hello where` |\n| 3 | `pf_build` | 见下 | exit 0 |\n| 4 | `pf_artifacts` | `outputDir=…` | exact closure inspect |\n\n### 4.1 仅 build\n\n```json\n{\n  \"source\": \"src/Hello.lean\",\n  \"module\": \"Hello\",\n  \"target\": \"aleo\",\n  \"root\": \"/abs/path/to/project\",\n  \"output\": \"/abs/path/to/project/out-aleo\"\n}\n```\n\n构建结果是 canonical Aleo Instructions + query descriptor。`pf_local` 对 Aleo fail closed；\n不存在 Leo/Dargo/snarkOS fallback。\n\n## 5. SDK 等价\n\n```python\nfrom proof_forge_sdk import ProofForgeClient\nc = ProofForgeClient()\nc.doctor(targets=[\"aleo\"])\nresult = c.build(\n    source=\"src/Hello.lean\",\n    module=\"Hello\",\n    target=\"aleo\",\n    root=\"/abs/path/to/project\",\n    output=\"/abs/path/to/project/out-aleo\",\n)\nprint(result.parsed)\n```\n\n## 6. CLI 等价\n\n```bash\nproof-forge-next build src/Hello.lean --module Hello --target aleo \\\n  --root \"$PROJ\" -o \"$PROJ/out-aleo\"\nproof-forge-next inspect --output-dir \"$PROJ/out-aleo\" --json\n```\n\n## 7. 前端下一步（剧本外）\n\nAgent 完成后端后：\n\n1. `pf_chain_catalog` 读 `frontendClients`（ecosystem，**非** PF 发货）\n2. 用生态 SDK 做极薄页面/脚本（未来网络接线）— **人工或后续切片**\n3. Aleo network deploy 当前 unsupported；不得从 Instructions artifact 推断已部署\n\n## 8. 失败剧本\n\n| 现象 | 处理 |\n|---|---|\n| 缺 `--source`/`--module` | usage exit；补参数 |\n| `import ProofForgeV2` 缺失 | `PF-SRC-INVALID`；补 gate 行 |\n| Aleo local/network 请求 | **拒绝**；只支持 direct build/inspect |\n| design-only target | catalog `implemented=false`；不 install/build |\n\n## 9. 成熟度标签（日志中应保持）\n\n- `deployable=false`\n- `ALEO-INSTRUCTIONS-DIRECT`\n- `NO-LOCAL-OR-NETWORK-RUNTIME`\n- 非 formal / 非 mainnet\n",
  "04-chain-client-catalog.md": "---\nid: PRODUCT-CHAIN-CLIENT-CATALOG\ntitle: Chain client / frontend catalog (metadata for agents)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-09\nnormative: false\n---\n\n# 多链客户端 / 前端 catalog（元数据）\n\n状态：`draft`（2026-08-09）  \n机器可读权威：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  \nschema：`proof-forge.chain-client-catalog.v1`  \nMCP：`pf_chain_catalog` · SDK：`ProofForgeClient.chain_catalog`\n\n## 1. 目的\n\n给 Code Agent / 作者回答：\n\n- 某条链 **后端** 走 ProofForge 哪些入口（build / local / network）？\n- **前端 / 客户端** 生态常见包是什么（**不由 PF 发货或 pin**）？\n- 本机如何测、哪些诚实边界？\n\n**不是** 第二编译器、不是钱包实现、不是 RPC 代理。\n\n## 2. 字段（每 target）\n\n| 字段 | 含义 |\n|---|---|\n| `id` | `TargetId` |\n| `implemented` | registry implemented vs design-only |\n| `maturityLabel` | 工程成熟度文案（非 formal） |\n| `role` | `backend-contracts` / circuits / model / design-only |\n| `pfSurface` | build/localModes/network/mcpTools/template |\n| `frontendClients[]` | 生态客户端名；`shippedByProofForge=false` |\n| `localDev` | offline interpret / chain-like engineering gates |\n| `honesty[]` | 禁止升级话术 |\n\n## 3. 后端 vs 前端\n\n```text\n                    ┌─────────────────────────────┐\n  Agent / Author    │  ProofForge CLI / SDK / MCP │  后端合约编译与本机测\n                    └─────────────┬───────────────┘\n                                  │ artifacts (e.g. .aleo)\n                                  ▼\n                    ┌─────────────────────────────┐\n  dApp UI (later)   │  Ecosystem chain client SDK │  前端 / 钱包 / RPC\n                    └─────────────────────────────┘\n```\n\nHello 后端剧本：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)。\n\n## 4. 查询\n\n```bash\n# MCP tool pf_chain_catalog  { \"target\": \"aleo\" } 或 { \"includeDesignOnly\": true }\n# SDK:\npython3 -I tools/sdk/proof_forge_sdk.py chain-catalog --target aleo\n```\n\n过滤：`target` 单 id；省略则返回全表 implemented（或 `includeDesignOnly`）。\n\n## 5. 更新纪律\n\n- 与 `TargetRegistryV1` **implemented 集合** 对齐；design-only 仅 catalog 展示\n- 不把 resolver support 写成完整平台语义\n- 不因 catalog 存在而改 `deployable`\n- 生态 SDK 名称可演进；变更只改 JSON + 本页日期\n\n## 6. 非目标\n\n- 不安装前端 npm 包\n- 不提供 mainnet endpoint 白名单（network 脚本另有 policy）\n- 不 formal / Stage-0\n",
  "05-distribution-and-packages.md": "---\nid: PRODUCT-DISTRIBUTION-AND-PACKAGES\ntitle: Distribution architecture — CLI release vs Lean author SDK vs host wrappers\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-09\nnormative: false\n---\n\n# 分发架构：CLI 发版 · Lean 写合约包 · 宿主 SDK/MCP\n\n状态：`draft`（2026-08-09）\n关联：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)、[`02-external-program-v1.md`](02-external-program-v1.md)、[`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)\n\n## 1. 结论（先回答「要不要做」）\n\n| 问题 | 答案 |\n|---|---|\n| 现在有没有 **产品 release 打包**？ | **没有**。只有 monorepo 内 `lake build` → `.lake/build/bin/proof-forge-next`（约数百 MB 动态链接调试二进制），无 GitHub Release 资产、无 tarball 安装、无 pip/Reservoir 发布 |\n| Python MCP/SDK 是不是「用 Python 重写了编译器」？ | **不是**。它们只 **spawn** 产品 CLI 并解析 JSON；权威永远是 Lean 二进制 + Tool Lock |\n| 要不要先做 **CLI engineering 发版/打包**？ | **要**。外部作者/Agent 不能依赖「克隆整仓 + lake 编译 263MB」当 sole 安装路径 |\n| 要不要发 **Lean 写合约 SDK 包**？ | **要（分轨）**：与 CLI 不同轨——写源码/IDE 语法 vs 编译/物化 |\n| 这是不是 formal Stage-0 / `just release-check`？ | **不是**。工程分发 ≠ formal/hermetic/release 资格；后者仍放最后 |\n\n推荐顺序：\n\n```text\n① Engineering CLI dist（版本化二进制 + digest + 安装说明）\n② Lean authoring package（最小可 require 的写合约表面）\n③ Host SDK 可选发布（pip 等；仍只包 CLI）\n④ formal Stage-0 / hermetic release evidence（最后）\n```\n\n## 2. 三层产品面（禁止混谈）\n\n```text\n┌─────────────────────────────────────────────────────────────┐\n│  A. 产品编译器 CLI  proof-forge-next                         │\n│     Lean 实现 · 读源文本 · 编译/物化/inspect/doctor/local     │\n│     权威：sole product path                                  │\n└───────────────────────────┬─────────────────────────────────┘\n                            │ spawn + JSON\n┌───────────────────────────▼─────────────────────────────────┐\n│  C. 宿主封装  Python SDK / MCP server                         │\n│     不是第二编译器 · 不 PATH 发明工具 · 无默认 network broadcast │\n└─────────────────────────────────────────────────────────────┘\n\n┌─────────────────────────────────────────────────────────────┐\n│  B. Lean 写合约表面  import ProofForgeV2 + program … where    │\n│     语法/导出/可选 IDE 支持 · 用户 Lake 工程可 require           │\n│     与 A 解耦：产品 build 读文本，不必 lake build 用户合约包     │\n└─────────────────────────────────────────────────────────────┘\n```\n\n| 层 | 现在是什么 | 用户怎么拿到 | 发版形态（目标） |\n|---|---|---|---|\n| **A CLI** | `lean_exe proof_forge_next`，包版本 monorepo `0.1.0` | 克隆仓库 `lake build` 或 `package-cli` tarball | 版本化 **binary dist**（平台 tarball + SHA-256）+ 固定 `lean-toolchain` 说明；Linux CI engineering Release 已接线 |\n| **B Lean author SDK** | monorepo 内整库 `lean_lib ProofForgeV2`（含编译器/targets）；另有薄 Author SDK 投影 | path/git 依赖 `proof-forge-author-*` 或整仓 | **最小可发布 lean 包**（Syntax + ProgramElaborationV1 import closure），tarball/GitHub asset；Reservoir/published package 仍 pending |\n| **C Host SDK/MCP** | `tools/sdk` / `tools/mcp` stdlib Python | `PYTHONPATH` / 绝对路径 | 可选 **pip wheel**（薄封装）；永不内嵌 target compilers |\n\n## 3. 现状诚实清单\n\n| 项 | 事实 |\n|---|---|\n| Lake package name | `proof-forge-next` |\n| Lake `version` | `0.1.0`（工程占位，**非**已发布 release） |\n| GitHub Actions | `ci.yml` + `.github/workflows/release-engineering-dist.yml`；tag `v*` / `workflow_dispatch` 会打 CLI + Author SDK engineering assets 并可创建 prerelease/draft GitHub Release |\n| `just release-check` | **未注册**；禁止声称 |\n| Formal Stage-0 | 独立命令；非日常完成条件 |\n| 产品 build 对外部工程 | 文本路径 + `import ProofForgeV2` **gate 字符串**；**不**要求用户 `lake build` 合约 |\n| Python SDK | 文档已写：**未** pip 发布；Host SDK 发布仍等 CLI dist 稳定后 |\n| CLI 二进制特征 | `package-cli` 默认保留动态链接/debug 信息；`--strip` 仅为可选 size profile。当前工程 tarball 可作为 **engineering-dist**，不得称 formal release asset |\n| Author SDK 包 | `package-author-sdk` 从 `ProgramElaborationV1` import closure 生成薄 `ProofForgeV2` root；不包含 CLI/materializers/targets |\n\n## 4. 为什么 Python「看起来像重新包装」\n\n因为 **C 层故意很薄**：\n\n- 实现语言选 Python stdlib → Agent/脚本易接，无第二语言工具链进 Tool Lock\n- 契约：`proof-forge-next … --json` 是 sole 产品机读面\n- 禁止在 SDK/MCP 内嵌 solc/nargo 或第二 Tool Root 写入器\n\n因此：\n\n- **发版优先级在 A（CLI）**，不在把 Python 做厚\n- C 可以晚于 A 做 pip；没有 A 的稳定安装路径，C 无法独立存在\n\n## 5. 两轨 SDK 名称（避免歧义）\n\n| 名称（建议） | 层 | 语言 | 职责 |\n|---|---|---|---|\n| **ProofForge Author SDK** | B | Lean | 写 `program`、语法、（可选）export/elab；用户 `lakefile` `require` |\n| **ProofForge Host SDK** | C | Python（未来可 TS） | 调 CLI：doctor/install/build/local/catalog |\n| **ProofForge CLI** | A | Lean→native exe | 编译器与物化产品 |\n\n「用 Lean 写的 SDK 用来写合约」= **Author SDK（B）**，不是 Host SDK（C）。\n\n## 6. Engineering 发版切片（建议实现序）\n\n### 6.1 REL-CLI-0 — 版本与身份\n\n- 单一 `PRODUCT_VERSION`（SemVer）与 CLI `--version` / doctor JSON 对齐\n- 绑定 `lean-toolchain` + git describe/commit（dirty 标记）\n- **非** formal BuildIdentity 完成声明\n\n### 6.2 REL-CLI-1 — binary dist 菜谱\n\n- `just package-cli` / `scripts/package_cli_dist.sh`\n- 输入：已 `lake build proof_forge_next`\n- 输出：`dist/proof-forge-next-<ver>-<platform>.tar.gz` + `.sha256`\n- 内容：`bin/proof-forge-next`（考虑 strip 为可选 profile）、`README`、`VERSION`、`lean-toolchain` 副本\n- **不做**：捆绑整个 monorepo、不捆绑 Tool Lock 工具（target 工具仍走 `install`/Tool Lock）\n\n### 6.3 REL-CLI-2 — 安装面\n\n- 文档：下载 tarball → 校验 digest → 放到 `PATH` 或 `PROOF_FORGE_CLI`\n- 与现有 `proof-forge-next install --targets …` 接：CLI 就位后再装链工具\n- GitHub Release engineering 上传已接线：`.github/workflows/release-engineering-dist.yml` 在 tag `v*` 或手动触发时上传 CLI + Author SDK assets（prerelease；非 tag 手动触发默认为 draft）— **仍非** Stage-0 formal\n\n### 6.4 REL-AUTHOR-0 — Lean Author SDK 最小包\n\n目标：用户工程：\n\n```lean\n-- lakefile.lean\nrequire proof_forge_author from git \"…\" @ \"v0.x.y\"\n-- 或 path 依赖发布树\n```\n\n```lean\nimport ProofForgeV2  -- 或未来更窄 namespace ProofForge.Author\nprogram Hello where …\n```\n\n约束：\n\n- **不得**把整个 materializer/tests 塞进 author 包（体积与依赖爆炸）\n- 首切片已落：`ProgramElaborationV1` import closure + 薄 `ProofForgeV2` root（拉入 Syntax 与 `program … where` elab surface），并由 `package-author-sdk-smoke` 在临时 Lake consumer 中验证\n- 产品 CLI 仍可纯文本编译；Author SDK 服务 **IDE/编辑体验** 与 lake 工程规范\n- monorepo 可保留 umbrella；author 包是 **可发布投影**，不是第二语义权威\n\n### 6.5 REL-HOST-0 — Host SDK 可选发布\n\n- `pip install` 仅当 CLI dist 稳定后\n- wheel 内 **无** 编译器二进制强制捆绑（或明确 extra 可选）\n- MCP 继续 stdlib 单文件 + 环境变量指 CLI\n\n### 6.6 明确不在本阶梯\n\n- formal Stage-0 / hermetic / `governance-check`\n- 把 Python 升格为编译器\n- 默认 MCP network broadcast\n- 因发版改 `deployable=true`\n\n## 7. 与「外部工程模板」关系\n\n| 路径 | 需要 A CLI dist？ | 需要 B Author SDK？ |\n|---|---|---|\n| 纯文本 + CLI build/sandbox（当前模板） | **是（体验）** | 否（gate 字符串即可） |\n| 用户 Lake 工程 IDE 语法高亮/elab | 是 | **是** |\n| Agent 经 MCP | 是（CLI 可发现） | 否 |\n\n当前模板「不 require Lake」是 **诚实 MVP**；发版后应变成：\n\n1. 安装 CLI dist\n2. （可选）require Author SDK\n3. Host SDK/MCP 指到同一 CLI\n\n## 8. 风险\n\n| 风险 | 缓解 |\n|---|---|\n| CLI 二进制过大 / 动态链接难移植 | strip profile；记录链接依赖；平台矩阵 linux-x86_64 / darwin-arm64 先 |\n| Author 包 import 拖进半个编译器 | 闭包测量 + 只导出 Language/Syntax 层 |\n| 把 engineering tag 说成 formal release | 文档与 CI 命名 `engineering-dist` vs `stage0` |\n| 双版本漂移（CLI vs Author） | 同一 PRODUCT_VERSION 族；doctor 报告双方 |\n\n## 9. 实现状态（engineering）\n\n`implemented=true`（engineering distribution surface）。本标记只覆盖本页 A/B/C 工程分发切片（CLI dist、Author SDK、Host SDK、CI engineering-dist），不代表 formal Stage-0、hermetic release、PyPI/Reservoir 公开发布或 mainnet/network 资格。\n\n本次本机证据（2026-08-09，Linux x86_64）：\n\n- `just package-host-sdk-smoke`：exit 0；生成 `proof_forge_sdk-0.1.0-py3-none-any.whl` 与 `proof_forge_sdk-0.1.0.tar.gz`；import/self_check 通过；输出 `package-host-sdk-smoke: HOST-SDK-SMOKE-OK`。\n- `just package-cli-smoke`：exit 0；version JSON 为 `schema=proof-forge.cli.version.v1`、`version=0.1.0`、`channel=engineering-dist`；临时打包 `proof-forge-next-0.1.0-linux-x86_64.tar.gz`（68,037,691 bytes，SHA-256 `9916b713962dd05c8ac3e62b1c0556b0a395dcfc6cc9fc22447fe92ef4f034bf`）；校验通过；输出 `package-cli-dist-smoke: PACK-SMOKE-OK`。\n- `just docs-check`：本页更新后运行，要求 exit 0 才可声明本段为当前证据。\n\n| 切片 | 状态 | 入口 |\n|---|---|---|\n| **REL-CLI-0** 版本身份 | **done** | 根目录 `VERSION`；`ProofForgeV2/CLI/ProductVersionV1.lean`；`proof-forge-next version [--json]` / `--version`；schema `proof-forge.cli.version.v1`；channel=`engineering-dist` |\n| **REL-CLI-1** binary dist | **done** | `scripts/package_cli_dist.sh` + `just package-cli` → `dist/proof-forge-next-<ver>-<platform>.tar.gz` + `.sha256`；`just package-cli-smoke` |\n| **REL-CLI-2** 安装文档 | **done（本页 §9.1）** | monorepo `lake build` 仍为开发者路径；dist 为外部作者推荐路径 |\n| **REL-AUTHOR-0** Lean Author SDK | **done engineering** | `scripts/package_author_sdk.py` + `just package-author-sdk`：Syntax 闭包薄 `ProofForgeV2` 根 + tarball；`just package-author-sdk-smoke` |\n| **REL-CI-0** CI 发工程版 | **done engineering** | `.github/workflows/release-engineering-dist.yml`：tag `v*` / workflow_dispatch → build CLI + author tarball → GitHub Release（prerelease，`engineering-dist`） |\n| **REL-HOST-0** pip 打包 | **done engineering** | `tools/sdk/pyproject.toml` + `just package-host-sdk` → wheel/sdist；`package-host-sdk-smoke`；CI 随 engineering Release 上传 |\n| **REL-HOST-1** PyPI 发布 | **done engineering（repo wiring）；owner PyPI setup required** | tag `v${VERSION}` → job `publish-pypi` / display name `publish-host-sdk-pypi`（OIDC Trusted Publishing，environment `pypi`）；本地 `just publish-host-sdk-pypi`；Trusted Publisher 字段表见 [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md) |\n| **REL-CI-1** multi-arch | **done engineering** | `release-engineering-dist.yml`：linux-x86_64 + **darwin-arm64** CLI 矩阵 + portable Author/Host 包 → GitHub Release + PyPI；tag 须匹配 `VERSION` |\n| formal Stage-0 | **out of scope** | 整仓最后 |\n\n### 9.1 安装 CLI dist（推荐外部作者）\n\n```bash\n# 在已 build 的 monorepo 上打工程包（或从未来 GitHub Release 下载同名资产）\njust package-cli\n# → dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz\n# → dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz.sha256\n\nsha256sum -c dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz.sha256\ntar -xzf dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz -C /opt\nexport PROOF_FORGE_CLI=/opt/proof-forge-next-0.1.0-linux-x86_64/bin/proof-forge-next\n\"$PROOF_FORGE_CLI\" version --json\n# expect: version=0.1.0, channel=engineering-dist\n```\n\n说明：\n\n- 包内 **无** Tool Lock 工具；链工具仍走 `install`（且 doctor/install/local 仍需 package `scripts/` CWD — 后续可把引擎装进 dist）\n- `build` / `check` / `version` / `list-targets` 仅需二进制即可\n- **禁止**把本 tarball 说成 formal / Stage-0 / hermetic 证据\n\n### 9.2 CI 发版（工程 channel）\n\n| 触发 | 行为 |\n|---|---|\n| push tag `v*`（如 `v0.1.0`） | Linux 构建 CLI + Author SDK → **GitHub Release**（`prerelease: true`）上传 tarball+sha256 |\n| `workflow_dispatch` | 同样打包；非 tag 时默认 **draft** release，避免误发 |\n\n工作流：`.github/workflows/release-engineering-dist.yml`\n命名必须带 **engineering-dist**；**禁止**写成 formal Stage-0 / `release-check`。\n\n本机等价：\n\n```bash\njust package-cli\njust package-author-sdk\n# 产物在 dist/\n```\n\n### 9.3 Author SDK 用法（Lake）\n\n```bash\njust package-author-sdk\ntar -xzf dist/proof-forge-author-0.1.0.tar.gz\n# 在用户工程 lakefile:\n#   require «proof-forge-author» from \"/path/to/proof-forge-author-0.1.0\"\n```\n\n用户源仍写 `import ProofForgeV2`（与产品 CLI 源文本 gate 兼容）。\n**编译**仍用 CLI dist 的 `proof-forge-next`，不是 `lake build` 用户合约出链上制品。\n\n### 9.4 CWD-free doctor/install/local/network（REL-CWD-0）— **done engineering**\n\nPackage root 解析（`PackageRootV1`）：\n\n1. `PROOF_FORGE_ROOT`（必须是绝对路径；含 `scripts/proof_forge_doctor.py`）\n2. `IO.appDir` 的父目录（当该父目录含 `scripts/proof_forge_doctor.py`；典型为 `<root>/bin/proof-forge-next`）\n3. 进程 CWD（monorepo 开发路径）\n\n`just package-cli` 打包 `scripts/` 引擎 + Tool Lock pin JSON。  \n聚焦门：`just package-cli-cwd-free-smoke`（foreign CWD 上 `doctor`）。\n\n### 9.5 CI 多架构 + Host SDK（REL-CI-1 / REL-HOST-0）\n\n| 平台 | CLI 资产 | runner |\n|---|---|---|\n| linux-x86_64 | `proof-forge-next-<ver>-linux-x86_64.tar.gz` | `ubuntu-latest` |\n| darwin-arm64 | `proof-forge-next-<ver>-darwin-arm64.tar.gz` | `macos-14` |\n\n可移植包（单次构建）：Author SDK tarball、Host SDK wheel/sdist。\n\n**发版门：**\n\n```bash\n# VERSION 文件 = 0.1.0 时：\ngit tag v0.1.0\ngit push origin v0.1.0\n# → Release engineering-dist workflow\n#    tag 必须是 v${VERSION} 或 v${VERSION}-* 前缀\n```\n\n`workflow_dispatch` 默认 **draft** Release（非 tag）。  \n所有 Release 标记 **prerelease** + `engineering-dist` 文案。\n\n本机：\n\n```bash\njust package-cli              # 当前主机平台\njust package-author-sdk\njust package-host-sdk\njust package-host-sdk-smoke\n```\n\n### 9.6 剩余\n\n1. Reservoir/git published Author SDK channel（当前只有 tarball/Release asset + path require）\n2. PyPI / TestPyPI 项目侧 Trusted Publisher 一次性人工配置（代码已接线；未配置则 `publish-pypi` job 失败；字段表见 [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)）\n3. formal Stage-0\n\n## 10. 一句话\n\n**要做发版打包，而且优先 CLI engineering dist；Python 只是宿主壳；Lean 写合约是另一轨 Author SDK。**\nformal 发布资格仍放整仓最后，不能挡 engineering 分发。\n",
  "aleo-testnet-walkthrough.md": "# Demo: Aleo with `pf` — local run → Testnet deploy → execute\n\n**Audience:** video / livestream  \n**Time:** ~8–12 minutes (save-only) · +5–15 minutes if real Testnet broadcast  \n**Claims:** engineering demo only — **not** formal / hermetic / mainnet  \n\n## What this proves\n\n| Step | What viewers see |\n|---|---|\n| 1 Setup | `pf setup` checklist (compiler + Leo) |\n| 2 New project | cargo-like `pf new` |\n| 3 Build | `pf build` → `.aleo` OutputSet |\n| 4 Local VM | `pf run` initialize / increment (offline Leo) |\n| 5 Deploy package | `pf deploy` → saved deployment JSON (default **no broadcast**) |\n| 6 Execute package | `pf execute` → saved execution JSON |\n| 7 (Optional) Testnet | `--broadcast` with **your funded** key on testnet |\n\n## Safety (say this on camera)\n\n1. Default `pf deploy` / `pf execute` are **save-only** — no chain write.  \n2. Mainnet is **refused**.  \n3. Broadcast needs `--private-key-env NAME` and a **funded** testnet key — never the Leo well-known dev key.  \n4. Do **not** paste private keys into chat, slides, or git.\n\n---\n\n## Prerequisites (before recording)\n\n```bash\n# Product tools (this machine already works if these pass)\nexport PROOF_FORGE_CLI=/path/to/proof-forge-next   # monorepo: $PWD/.lake/build/bin/proof-forge-next\nexport PATH=\"$HOME/.cargo/bin:$PATH\"               # leo + cargo-installed pf\n\n# Optional: install from crates.io\n# cargo install proof-forge-pf --locked\n\npf setup --target aleo\n# Expect: proof-forge-next ok, leo ok\n```\n\n### For real Testnet broadcast only\n\n| Need | Notes |\n|---|---|\n| Aleo testnet account | Create via Leo / Provable explorer tooling |\n| Funded credits | Testnet faucet / community faucet (policy changes — check current docs) |\n| Env var with private key | e.g. `export PF_ALEO_TESTNET_KEY='APrivateKey1…'` — **never commit** |\n| Network | `testnet` only (`devnet` ok for local snarkOS; mainnet refused) |\n\n---\n\n## Shot list (record in one terminal, large font)\n\n### Shot 0 — Title card (5s)\n\n> ProofForge `pf` · Aleo · local → Testnet  \n> Default: save-only · Optional: broadcast\n\n### Shot 1 — Setup (30s)\n\n```bash\npf setup --target aleo\npf version\n```\n\n**Say:** “`pf` is the developer CLI. Compiler is `proof-forge-next`. Leo is the official VM/tool.”\n\n### Shot 2 — New project (45s)\n\n```bash\nrm -rf /tmp/pf-aleo-video && mkdir -p /tmp/pf-aleo-video && cd /tmp/pf-aleo-video\npf new hello --target aleo\ncd hello\ncat pf.toml\nsed -n '1,40p' src/Hello.lean\n```\n\n**Say:** “Same shape as our StateCell template — init, increment, get. No Lake package.”\n\n### Shot 3 — Build (45s)\n\n```bash\npf build\nls -la build/aleo/\nhead -30 build/aleo/hello.aleo   # program id may be hello.aleo\ncat build/aleo/manifest.json | head -40\n```\n\n**Say:** “Compiler emits Aleo Instructions OutputSet. We never rewrite deployable.”\n\n### Shot 4 — Local run (90s)\n\n```bash\npf run -- initialize 5u64\npf run -- increment 3u64\npf run -v -- increment 1u64    # optional: show full Leo log once\n```\n\n**Say:** “Offline Leo VM via imports pin — no network.”\n\n### Shot 5 — Deploy save-only (60s)\n\n```bash\npf deploy --network testnet\nls -la build/aleo/tx/\n# show a slice of the deployment JSON (no secrets)\npython3 -I -c 'import json,glob; p=glob.glob(\"build/aleo/tx/*.deployment.json\")[0]; d=json.load(open(p)); print(p); print(\"keys\", list(d)[:12] if isinstance(d,dict) else type(d))'\n```\n\n**Say:** “This materializes a deploy transaction and **saves** it. broadcast=false by default.”\n\n### Shot 6 — Execute save-only (60s)\n\n```bash\npf execute --network testnet -- initialize 5u64\nls -la build/aleo/tx/\n```\n\n**Say:** “Same for execute — package the call, don’t send unless we opt in.”\n\n### Shot 7 — Safety demo (30s)\n\n```bash\n# Must fail:\npf deploy --network mainnet || true\n```\n\n**Say:** “Mainnet hard-refused in pf v0.”\n\n### Shot 8 — Optional real Testnet broadcast (only if funded key ready)\n\n```bash\n# DO NOT type the key on camera — load from a pre-exported env in a private shell\n# export PF_ALEO_TESTNET_KEY='…'   # already set off-camera\n\npf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY\n# Wait for explorer confirmation; paste program id on screen\n\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- initialize 5u64\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- increment 3u64\n```\n\n**Say:**\n\n- “Broadcast is explicit.”  \n- “Key comes from env name only — never a default file scan.”  \n- “Well-known Leo demo key is refused for broadcast.”  \n- Open Provable/Aleo explorer for the program + txs if available.\n\n### Shot 9 — Close (20s)\n\n```bash\npf --help | head -40\n```\n\n**Say:** “Same `pf` surface for EVM/Solana later — build / test / deploy save-only. Aleo is first full local+network packaging path.”\n\n---\n\n## Live Testnet result (2026-08-10)\n\nSuccessful end-to-end broadcast with funded key.\n\n### Public recording\n\n| Item | Link |\n|------|------|\n| **asciinema (public)** | https://asciinema.org/a/1262697 |\n| Embed | `<script src=\"https://asciinema.org/a/1262697.js\" id=\"asciicast-1262697\" async></script>` |\n| Local cast (gitignored) | `build/demos/aleo/pf-aleo-demo-20260810T043722Z.cast` |\n\n```bash\n# local replay\nasciinema play build/demos/aleo/pf-aleo-demo-20260810T043722Z.cast\n```\n\n### On-chain\n\n| Item | Value |\n|------|-------|\n| Network | Aleo **testnet** (`https://api.explorer.provable.com/v1`) |\n| Program | `pfdemo336641.aleo` |\n| Deploy tx | `at147hjftmt294hrdgy7hfkjzn69ryxj3j2ank4jxl4u9qn8vl6nvqs73a5mt` |\n| Execute tx (increment) | `at1j4g47meu322csew7vdlwx5x3hrpfaq0fftmet3zphdyzvxfanczsns58fd` |\n| On-chain state | `pf_state_0[0]=8u64` (initialize `5` + increment `3`), `initialized[0]=true` |\n| Deploy fee | `3125778` microcredits (~3.13 credits) |\n| Execute fee (increment) | `1849` microcredits |\n\n### Explorer (click-through)\n\n| What | URL |\n|------|-----|\n| Program | https://testnet.explorer.provable.com/program/pfdemo336641.aleo |\n| Deploy transaction | https://testnet.explorer.provable.com/transaction/at147hjftmt294hrdgy7hfkjzn69ryxj3j2ank4jxl4u9qn8vl6nvqs73a5mt |\n| Execute transaction | https://testnet.explorer.provable.com/transaction/at1j4g47meu322csew7vdlwx5x3hrpfaq0fftmet3zphdyzvxfanczsns58fd |\n\nAPI cross-checks used during the demo:\n\n```bash\n# deployment id for program\ncurl -sS https://api.explorer.provable.com/v1/testnet/find/transactionID/deployment/pfdemo336641.aleo\n# mappings present\ncurl -sS https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mappings\n# live state\ncurl -sS https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mapping/pf_state_0/0u8\ncurl -sS https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mapping/initialized/0u8\n```\n\n**Toolchain gate:** Leo **4.4.1+** required for current Testnet base-fee validation. Leo 4.0.2 under-estimates deployment base fee and is rejected by the node.\n\n**pf flags used for live broadcast:**\n\n```bash\npf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id pfdemo336641\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id pfdemo336641 -- initialize 5u64\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id pfdemo336641 -- increment 3u64\n```\n\nBroadcast mode generates real deploy certificates / execution proofs (save-only still uses skip flags for speed).\n\n## One-shot rehearsal script (no broadcast)\n\n```bash\n#!/usr/bin/env bash\nset -euo pipefail\nexport PROOF_FORGE_CLI=\"${PROOF_FORGE_CLI:?set PROOF_FORGE_CLI}\"\nPF=\"${PF:-pf}\"\ncommand -v \"$PF\" >/dev/null || PF=\"$(pwd)/clients/pf-cli/target/release/pf\"\n\nROOT=\"$(mktemp -d \"${TMPDIR:-/tmp}/pf-aleo-video.XXXXXX\")\"\necho \"demo root: $ROOT\"\ncd \"$ROOT\"\n\n\"$PF\" setup --target aleo\n\"$PF\" new hello --target aleo\ncd hello\n\"$PF\" build\n\"$PF\" run -- initialize 5u64\n\"$PF\" run -- increment 3u64\n\"$PF\" deploy --network testnet\n\"$PF\" execute --network testnet -- initialize 5u64\necho \"SAVE-ONLY OK — artifacts under $ROOT/hello/build/aleo/\"\nls -la build/aleo/tx/\n```\n\nSave as `scripts/demo_aleo_testnet_save_only.sh` in the monorepo (optional) and run before filming.\n\n---\n\n## Broadcast checklist (day of shoot)\n\n- [ ] Fresh shell; `echo $PF_ALEO_TESTNET_KEY` is set **off camera**  \n- [ ] Key is **not** the Leo well-known dev key  \n- [ ] Balance > fee on testnet  \n- [ ] Screen recording hides any env dump / shell history  \n- [ ] Plan B if faucet is down: film save-only only, show JSON + explorer docs  \n\n---\n\n## If something fails\n\n| Symptom | Fix |\n|---|---|\n| `proof-forge-next` missing | `export PROOF_FORGE_CLI=…` or monorepo lake build |\n| `leo not found` | install Leo 4.x; `pf setup --target aleo` |\n| deploy twin mismatch | template must stay StateCell-shaped (`pf new` default) |\n| broadcast refused well-known key | use a real testnet key in env |\n| broadcast fee / network error | check endpoint, balance, Leo version |\n| want quieter Leo | default `pf run` is quiet; `-v` for full log |\n\n---\n\n## Non-goals for this video\n\n- Mainnet  \n- Non–StateCell-shaped Aleo programs (twin registry only `statecell-v1` today)  \n- Claiming formal verification or “production ready”  \n- Showing private keys or seed phrases  \n\n## CLI recording tools (what we use)\n\n| Tool | Role | Install |\n|---|---|---|\n| **asciinema** | Terminal session cast (best for CLI demos) | `brew install asciinema` |\n| **ffmpeg** | Optional screen MP4 from desktop | `brew install ffmpeg` |\n| **script(1)** | Plain typescript log | preinstalled on macOS |\n\n### One-command record (save-only)\n\n```bash\nexport PROOF_FORGE_CLI=\"$PWD/.lake/build/bin/proof-forge-next\"\njust pf-cli-aleo-record\n# → build/demos/aleo/pf-aleo-demo-*.cast\nasciinema play build/demos/aleo/pf-aleo-demo-*.cast\n# optional public share:\n# asciinema upload build/demos/aleo/pf-aleo-demo-*.cast\n# published public recording: https://asciinema.org/a/1262697\n```\n\n### Real Testnet broadcast record\n\n1. Create account (off camera): `leo account new`  \n2. Fund via **https://faucet.aleo.org/** (captcha — human only; ~3+ credits for deploy)  \n3. Load key into env (never echo):\n\n```bash\nexport PF_ALEO_TESTNET_KEY='APrivateKey1…'   # funded testnet key\nexport PF_ALEO_BROADCAST=1\njust pf-cli-aleo-record\n```\n\nDeploy fee observed in rehearsal: **~3.04 credits** (namespace + storage + synthesis).\n\nWithout faucet funds, broadcast correctly fails with insufficient balance after building the deployment plan — still useful footage.\n\n### Optional desktop MP4 (macOS)\n\n```bash\n# Capture main display while you run the demo in Terminal (large font)\nffmpeg -f avfoundation -i \"2:none\" -r 30 -t 600 build/demos/aleo/screen.mp4\n```\n\n(`2` = “Capture screen 0” from `ffmpeg -f avfoundation -list_devices true -i \"\"`)\n\n## Related\n\n- `clients/pf-cli/README.md`  \n- `docs/specs/cli-developer.md` § Aleo  \n- `scripts/demo_aleo_record.sh` / `scripts/demo_aleo_testnet_save_only.sh`  \n- `scripts/aleo_instructions_network_tx_acceptance.sh` (CI gate; save-only default)  \n",
  "mcp-stdio-readme.md": "# ProofForge MCP-V0\n\nMinimal **stdio** MCP server that exposes product CLI tools for Code Agents.\n\nAuthority: [`docs/product/01-toolchain-install-surface.md`](../../docs/product/01-toolchain-install-surface.md) §8.\n\n## Tools\n\n| Tool | CLI mapping |\n|---|---|\n| `pf_list_targets` | `proof-forge-next list-targets [--all] --json` |\n| `pf_doctor` | `proof-forge-next doctor --json` |\n| `pf_install` | `proof-forge-next install --targets … --yes --json` |\n| `pf_build` | `proof-forge-next build <source> --module … --target … -o … --json` |\n| `pf_artifacts` | `proof-forge-next inspect --output-dir <dir> --json` |\n| `pf_local` | `proof-forge-next local --target … [--mode sandbox] -- --source … --module … [--root …]` |\n| `pf_chain_catalog` | static `docs/product/chain-client-catalog.v1.json` (client/frontend metadata) |\n\n- **No** default network broadcast tool (use product CLI `network --broadcast` explicitly if needed).\n- Aleo `pf_local` is **generic**: requires `source` + `module`; optional `root` / `runs` / `golden` / `skipRun` — no default program. When `root` is provided it is passed through as product `--root` after `--`, so repo-external source paths resolve against that project root.\n- Hello agent playbook: [`docs/product/03-hello-dapp-agent-playbook.md`](../../docs/product/03-hello-dapp-agent-playbook.md).\n- Tools **only** spawn the product CLI / package engines (except `pf_chain_catalog`, which reads package JSON); they do **not** reimplement solc/leo/nargo.\n- Tool Lock installs never use PATH fallback into `PROOF_FORGE_TOOL_ROOT`.\n- Success is **not** formal / hermetic / mainnet / `deployable=true` evidence.\n\n## Prerequisites\n\n```bash\n# From package root\nlake build          # produces .lake/build/bin/proof-forge-next\n# Optional: install toolchain assets for a target\n./.lake/build/bin/proof-forge-next install --targets quint --yes\n```\n\n## Agent wiring (Cursor / Claude Desktop / other MCP hosts)\n\n```json\n{\n  \"mcpServers\": {\n    \"proof-forge\": {\n      \"command\": \"/usr/bin/python3\",\n      \"args\": [\n        \"-I\",\n        \"/absolute/path/to/proof_forge/tools/mcp/proof_forge_mcp_server.py\"\n      ],\n      \"env\": {\n        \"PROOF_FORGE_ROOT\": \"/absolute/path/to/proof_forge\",\n        \"PROOF_FORGE_CLI\": \"/absolute/path/to/proof_forge/.lake/build/bin/proof-forge-next\",\n        \"PROOF_FORGE_TOOL_ROOT\": \"/absolute/path/to/tool-root/linux-x86_64\"\n      }\n    }\n  }\n}\n```\n\nNotes:\n\n- `PROOF_FORGE_ROOT` must contain `scripts/proof_forge_doctor.py` (package root).\n- `PROOF_FORGE_CLI` is optional if `.lake/build/bin/proof-forge-next` exists under the root.\n- Inherit or set `PROOF_FORGE_TOOL_ROOT` so doctor/install/build see locked tools (never PATH fallback).\n\n## Self-check / smoke\n\n```bash\n/usr/bin/python3 -I tools/mcp/proof_forge_mcp_server.py --self-check\nscripts/mcp_smoke.sh\n```\n\n## Design boundaries\n\n- Package is stdlib-only Python (no extra pip dependency).\n- `pf_install` always passes `--yes` unless `dryRun=true` (non-interactive).\n- `pf_build` rejects `broadcast` / `network` arguments.\n- Design-only targets (`soroban`, `icp`, `openvm`) remain unsupported for install.\n",
};
