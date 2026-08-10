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
    "No network broadcast tools on MCP default surface.",
    "Aleo frontend detail: docs/product/07-aleo-dapp-frontend-wallet.md (wallet adaptor + Provable SDK; not shipped by PF).",
    "EVM frontend detail: docs/product/08-evm-dapp-frontend.md + templates/evm-dapp-ui (viem/local Anvil + X Layer presets).",
    "EVM public networks (X Layer testnet/mainnet, …): docs/product/networks.v1.json + docs/product/13-xlayer-onchainos.md; MCP pf_network_info / pf_onchainos_guide.",
    "OKX OnchainOS: official DEX MCP at https://web3.okx.com/api/v1/onchainos-mcp — dual-MCP with PF; do not reimplement DEX inside PF.",
    "Solana contracts: ProofForge ProgramV1 + pf CLI; frontend templates/solana-dapp-ui; PF MCP summarizes ix codec (not external Anchor MCP)."
  ],
  "networksRef": {
    "schema": "proof-forge.network-catalog.v1",
    "path": "docs/product/networks.v1.json",
    "guide": "docs/product/13-xlayer-onchainos.md",
    "mcpTools": [
      "pf_network_info",
      "pf_onchainos_guide"
    ]
  },
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
        "template": "templates/external-aleo-hello",
        "frontendTemplate": "templates/aleo-dapp-ui"
      },
      "frontendClients": [
        {
          "name": "@provablehq/aleo-wallet-adaptor-react (+ react-ui, core, standard, types)",
          "kind": "js-ts",
          "purpose": "React WalletProvider/useWallet/WalletMultiButton — connect Leo/Puzzle/Shield/Fox/Soter; sign/decrypt/records/executeTransaction/executeDeployment",
          "shippedByProofForge": false,
          "docs": [
            "https://docs.aleo.org/build/wallets/wallet-adapter/getting-started",
            "https://github.com/ProvableHQ/aleo-dev-toolkit",
            "docs/product/07-aleo-dapp-frontend-wallet.md"
          ],
          "packages": [
            "@provablehq/aleo-wallet-adaptor-react",
            "@provablehq/aleo-wallet-adaptor-react-ui",
            "@provablehq/aleo-wallet-adaptor-core",
            "@provablehq/aleo-wallet-standard",
            "@provablehq/aleo-types",
            "@provablehq/aleo-wallet-adaptor-leo",
            "@provablehq/aleo-wallet-adaptor-puzzle",
            "@provablehq/aleo-wallet-adaptor-shield",
            "@provablehq/aleo-wallet-adaptor-fox",
            "@provablehq/aleo-wallet-adaptor-soter"
          ]
        },
        {
          "name": "@provablehq/sdk (+ @provablehq/wasm)",
          "kind": "js-ts",
          "purpose": "Program/Account/Transaction objects, optional browser/node prove, RPC helpers; pair with wallet for user-signed txs",
          "shippedByProofForge": false,
          "docs": [
            "https://github.com/ProvableHQ/sdk",
            "https://www.npmjs.com/package/@provablehq/sdk"
          ],
          "packages": [
            "@provablehq/sdk",
            "@provablehq/wasm",
            "create-leo-app"
          ]
        },
        {
          "name": "Explorer REST (api.explorer.provable.com)",
          "kind": "http",
          "purpose": "Public program/mapping/tx queries without wallet; testnet default for PF demos",
          "shippedByProofForge": false,
          "docs": [
            "https://api.explorer.provable.com/v1"
          ]
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": null
      },
      "honesty": [
        "deployable=false on product build",
        "canonical Aleo Instructions and query descriptor only",
        "no Leo compiler, local runtime, or network wrapper",
        "frontend wallet/sdk are ecosystem packages — PF does not vendor or pin versions",
        "browser must not embed APrivateKey; CLI broadcast keys stay developer-local only",
        "see PRODUCT-ALEO-DAPP-FRONTEND-WALLET for dApp wiring"
      ],
      "frontendGuide": "docs/product/07-aleo-dapp-frontend-wallet.md",
      "frontendTemplate": "templates/aleo-dapp-ui"
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
        "network": "catalog-metadata-plus-local-anvil",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_local",
          "pf_artifacts",
          "pf_chain_catalog",
          "pf_network_info",
          "pf_onchainos_guide"
        ],
        "frontendTemplate": "templates/evm-dapp-ui"
      },
      "networks": [
        "evm.local.anvil",
        "evm.xlayer.testnet",
        "evm.xlayer.mainnet"
      ],
      "ecosystem": {
        "okxOnchainOs": {
          "guide": "docs/product/13-xlayer-onchainos.md",
          "networksCatalog": "docs/product/networks.v1.json",
          "officialMcp": "https://web3.okx.com/api/v1/onchainos-mcp",
          "devPortal": "https://web3.okx.com/zh-hans/onchainos/dev-portal/project",
          "xLayerAbout": "https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/about-xlayer",
          "capabilities": [
            "wallet-agentic",
            "trade-dex",
            "market-data",
            "payments-app"
          ],
          "dualMcp": "PF MCP for contracts/catalog; OnchainOS MCP for DEX quote/swap"
        }
      },
      "frontendClients": [
        {
          "name": "viem (+ injected window.ethereum / MetaMask)",
          "kind": "js-ts",
          "purpose": "typed RPC, deploy/call StateCell-shaped ABI; default template stack; X Layer chain presets in template",
          "shippedByProofForge": false,
          "docs": [
            "https://viem.sh",
            "docs/product/08-evm-dapp-frontend.md",
            "docs/product/13-xlayer-onchainos.md",
            "templates/evm-dapp-ui"
          ],
          "packages": [
            "viem"
          ]
        },
        {
          "name": "wagmi + viem (ecosystem)",
          "kind": "js-ts",
          "purpose": "React hooks wallet UX; optional upgrade from minimal template",
          "shippedByProofForge": false,
          "packages": [
            "wagmi",
            "viem",
            "@wagmi/core"
          ]
        },
        {
          "name": "ethers v6 (ecosystem)",
          "kind": "js-ts",
          "purpose": "alternative provider/contract API",
          "shippedByProofForge": false,
          "packages": [
            "ethers"
          ]
        },
        {
          "name": "OKX Wallet / browser injected (ecosystem)",
          "kind": "js-ts",
          "purpose": "user wallet on X Layer; pair with viem; Agentic Wallet for agent paths (OnchainOS)",
          "shippedByProofForge": false,
          "docs": [
            "https://web3.okx.com/zh-hans/onchainos/dev-docs/wallet/agentic-wallet",
            "https://web3.okx.com/wallet/x-layer"
          ]
        }
      ],
      "localDev": {
        "offlineInterpret": null,
        "chainLike": "Anvil engineering differential (host-heavy)",
        "publicNetworks": "docs/product/networks.v1.json (metadata); engineering deploy scripts/pf_evm_xlayer_deploy.sh is opt-in print/stub"
      },
      "honesty": [
        "product OutputSet deployable depends on profile; do not invent mainnet",
        "frontend packages are ecosystem — PF does not vendor or pin npm versions",
        "pf v0 default refuses EVM public-chain broadcast; local Anvil is the product write demo",
        "X Layer rows are catalog + UI presets — not a claim that Lean NetworkRegistry deploy is product-complete",
        "OnchainOS DEX uses official MCP with app-local OK-ACCESS-KEY — not PF remote edge",
        "see PRODUCT-EVM-DAPP-FRONTEND, PRODUCT-XLAYER-ONCHAINOS, templates/evm-dapp-ui"
      ],
      "frontendGuide": "docs/product/08-evm-dapp-frontend.md",
      "networkGuide": "docs/product/13-xlayer-onchainos.md",
      "frontendTemplate": "templates/evm-dapp-ui"
    },
    {
      "id": "solana",
      "implemented": true,
      "maturityLabel": "CPI/ELF engineering (Mollusk host-heavy)",
      "role": "backend-contracts",
      "pfSurface": {
        "build": true,
        "localModes": [
          "runtime"
        ],
        "network": "local-loopback-only",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_local",
          "pf_artifacts",
          "pf_chain_catalog",
          "pf_solana_scaffold",
          "pf_solana_ix_codec",
          "pf_solana_artifacts"
        ],
        "template": "pf new <name> --target solana",
        "frontendTemplate": "templates/solana-dapp-ui"
      },
      "frontendClients": [
        {
          "name": "@solana/web3.js + wallet-adapter (template default)",
          "kind": "js-ts",
          "purpose": "local validator + wallet UX over PF IDL/ix encoding",
          "shippedByProofForge": false,
          "docs": [
            "docs/product/10-solana-dapp-frontend.md",
            "templates/solana-dapp-ui"
          ],
          "packages": [
            "@solana/web3.js",
            "@solana/wallet-adapter-react",
            "@solana/wallet-adapter-react-ui",
            "@solana/wallet-adapter-wallets"
          ]
        }
      ],
      "localDev": {
        "offlineInterpret": "pf verify -t solana (proof-forge-solana-client)",
        "chainLike": "Mollusk / pf test; Surfpool for dApp loopback",
        "deploy": "scripts/pf_solana_local_demo.sh (Surfpool) or pf deploy --network local; UI uses deployment.json",
        "frontend": "templates/solana-dapp-ui"
      },
      "honesty": [
        "Contracts authored in ProofForge ProgramV1 — not Anchor as primary path",
        "Principal is not Solana pubkey globally",
        "Public RPC broadcast refused in pf v0",
        "ix-data body-only = sha256(proof-forge-solana-v1:name(types))[0:8]+u64 params; CPI-product = handlerId u64 LE (not Anchor sighash)",
        "engineering maturity — not formal/mainnet evidence"
      ],
      "agentGuide": "docs/product/09-solana-agent-playbook.md",
      "demoGuide": "docs/demos/solana-local-walkthrough.md",
      "frontendGuide": "docs/product/10-solana-dapp-frontend.md"
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
      "maturityLabel": "dpn-emit + official-cli wrap",
      "role": "backend-zk-application-chain",
      "pfSurface": {
        "build": true,
        "localModes": [
          "session-test",
          "simulate-run"
        ],
        "network": "deploy-wrap-testnet",
        "mcpTools": [
          "pf_list_targets",
          "pf_doctor",
          "pf_install",
          "pf_build",
          "pf_artifacts",
          "pf_chain_catalog",
          "pf_psy_scaffold",
          "pf_psy_artifacts",
          "pf_psy_ecosystem"
        ]
      },
      "frontendClients": [
        {
          "name": "@psy-protocol/psy-sdk",
          "kind": "js-ts",
          "purpose": "RPC, wallet provider, local web prover/compiler (official; not PF)",
          "shippedByProofForge": false,
          "packages": [
            "@psy-protocol/psy-sdk",
            "@psy-protocol/contract-sdk",
            "@psy-protocol/utils"
          ],
          "docs": [
            "docs/product/12-psy-dapp-frontend.md",
            "https://github.com/PsyProtocol/psy-sdk"
          ]
        },
        {
          "name": "psy-wallet / window.psy",
          "kind": "browser-extension",
          "purpose": "user keys + sendTransaction approval UX",
          "shippedByProofForge": false,
          "docs": [
            "https://app.psy-protocol.xyz/#/wallet",
            "https://github.com/PsyProtocol/psy-template"
          ]
        }
      ],
      "localDev": {
        "offlineInterpret": "pf test -t psy (multi-step session) / pf run (psy_user_cli simulate)",
        "chainLike": "scripts/psy_local_chain_status.sh; full fabric via psy-node",
        "deploy": "pf deploy wraps psy_user_cli deploy-contract; --broadcast → --is-deploy",
        "execute": "pf execute -t psy --broadcast wraps psy_user_cli call",
        "frontend": "official psy-template + @psy-protocol/* (not PF template yet)",
        "dpnArtifact": "{program}.dpn.json from pf build -t psy"
      },
      "honesty": [
        "PF emits canonical DPN (psy-dpn-v1); OutputSet deployable remains false",
        "local multi-step uses session harness; single-call uses official simulate",
        "network deploy/call wrap official psy_user_cli only",
        "mainnet refused; keys via --private-key-env only",
        "engineering only — not formal/hermetic evidence"
      ],
      "ecosystem": {
        "docs": [
          "https://docs.psy-protocol.xyz",
          "https://psy.xyz/docs"
        ],
        "app": "https://app.psy-protocol.xyz",
        "wallet": "https://app.psy-protocol.xyz/#/wallet",
        "explorer": "https://explorer.psy-protocol.xyz",
        "ide": "https://ide.psy-protocol.xyz",
        "config": "https://config.psy-protocol.xyz/config.json",
        "toolchain": "https://github.com/QEDProtocol/psyup",
        "template": "https://github.com/PsyProtocol/psy-template",
        "node": "https://github.com/PsyProtocol/psy-node"
      },
      "agentGuide": "docs/product/11-psy-agent-playbook.md",
      "demoGuide": "docs/demos/psy-dpn-walkthrough.md",
      "frontendGuide": "docs/product/12-psy-dapp-frontend.md",
      "targetDossier": "docs/targets/10-psy.md",
      "dpnLowering": "docs/targets/10-psy-dpn-lowering.md"
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

export const NETWORKS_JSON = {
  "schema": "proof-forge.network-catalog.v1",
  "version": "1",
  "updated": "2026-08-10",
  "notes": [
    "Metadata + deploy-policy catalog for agents and future pf deploy --network.",
    "Does NOT enable product-level public broadcast by itself.",
    "build must never take --network (see docs/specs/cli.md / target-registry.md).",
    "RPC URLs are public endpoints from official docs; they may rate-limit or change.",
    "Keys never belong in this file. MCP remote surface never broadcasts.",
    "Add new EVM nets as rows under networks[] with id evm.<chain>.<env>."
  ],
  "policyEnum": [
    "local-only",
    "testnet-opt-in",
    "mainnet-gated",
    "metadata-only"
  ],
  "networks": [
    {
      "id": "evm.local.anvil",
      "targetFamily": "evm",
      "displayName": "Anvil (local)",
      "env": "local",
      "chainId": 31337,
      "nativeCurrency": {
        "name": "Ether",
        "symbol": "ETH",
        "decimals": 18
      },
      "rpcUrls": [
        "http://127.0.0.1:8545"
      ],
      "explorers": [],
      "policy": "local-only",
      "pfProductBroadcast": "local-loopback-only",
      "viemChainHint": "foundry",
      "related": {
        "demoScript": "scripts/pf_evm_local_demo.sh",
        "frontendTemplate": "templates/evm-dapp-ui",
        "guide": "docs/product/08-evm-dapp-frontend.md"
      },
      "honesty": [
        "Default EVM demo path",
        "Anvil #0 key is local-only — never use on public nets"
      ]
    },
    {
      "id": "evm.xlayer.testnet",
      "targetFamily": "evm",
      "displayName": "X Layer testnet",
      "env": "testnet",
      "chainId": 1952,
      "nativeCurrency": {
        "name": "OKB",
        "symbol": "OKB",
        "decimals": 18
      },
      "rpcUrls": [
        "https://testrpc.xlayer.tech/terigon",
        "https://xlayertestrpc.okx.com/terigon"
      ],
      "explorers": [
        {
          "name": "OKX Web3 Explorer (X Layer test)",
          "url": "https://www.okx.com/web3/explorer/xlayer-test"
        }
      ],
      "faucet": "https://web3.okx.com/xlayer/faucet",
      "bridge": "https://web3.okx.com/xlayer/bridge",
      "docs": [
        "https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/about-xlayer",
        "https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/network-information"
      ],
      "policy": "testnet-opt-in",
      "pfProductBroadcast": "engineering-lane-not-default",
      "ecosystem": "okx-xlayer",
      "hackathon": {
        "event": "Build X AI Season",
        "requirement": "Deploy on X Layer testnet during hackathon; mainnet later",
        "page": "https://web3.okx.com/zh-hans/xlayer/build-x-series"
      },
      "related": {
        "guide": "docs/product/13-xlayer-onchainos.md",
        "frontendTemplate": "templates/evm-dapp-ui",
        "deployScript": "scripts/pf_evm_xlayer_deploy.sh"
      },
      "honesty": [
        "Full EVM equivalence — PF --target evm artifacts apply",
        "Gas token is OKB, not ETH",
        "Catalog presence ≠ pf product mainnet/testnet broadcast shipped",
        "Use wallet or developer-local key env for writes; never MCP remote keys"
      ]
    },
    {
      "id": "evm.xlayer.mainnet",
      "targetFamily": "evm",
      "displayName": "X Layer mainnet",
      "env": "mainnet",
      "chainId": 196,
      "nativeCurrency": {
        "name": "OKB",
        "symbol": "OKB",
        "decimals": 18
      },
      "rpcUrls": [
        "https://rpc.xlayer.tech",
        "https://xlayerrpc.okx.com"
      ],
      "explorers": [
        {
          "name": "OKX Web3 Explorer (X Layer)",
          "url": "https://www.okx.com/web3/explorer/xlayer"
        }
      ],
      "bridge": "https://web3.okx.com/xlayer/bridge",
      "docs": [
        "https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/about-xlayer",
        "https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/network-information",
        "https://web3.okx.com/xlayer"
      ],
      "policy": "mainnet-gated",
      "pfProductBroadcast": "refused-or-explicit-gate",
      "ecosystem": "okx-xlayer",
      "architecture": {
        "stack": "OP Stack optimistic rollup + AggLayer",
        "vm": "EVM-equivalent",
        "gasToken": "OKB"
      },
      "related": {
        "guide": "docs/product/13-xlayer-onchainos.md",
        "frontendTemplate": "templates/evm-dapp-ui"
      },
      "honesty": [
        "Mainnet writes are application/operator decisions",
        "pf v0 default refuses public EVM broadcast",
        "Not formal / hermetic / Stage-0 evidence"
      ]
    },
    {
      "id": "evm.ethereum.sepolia",
      "targetFamily": "evm",
      "displayName": "Ethereum Sepolia",
      "env": "testnet",
      "chainId": 11155111,
      "nativeCurrency": {
        "name": "Sepolia Ether",
        "symbol": "ETH",
        "decimals": 18
      },
      "rpcUrls": [],
      "explorers": [
        {
          "name": "Etherscan Sepolia",
          "url": "https://sepolia.etherscan.io"
        }
      ],
      "policy": "metadata-only",
      "pfProductBroadcast": "not-shipped",
      "status": "placeholder-for-future-rows",
      "honesty": [
        "Row reserved so multi-EVM expansion is data-driven",
        "No PF product deploy path yet — fill rpcUrls when adopted"
      ]
    }
  ],
  "ecosystems": {
    "okx-onchainos": {
      "name": "OKX Onchain OS",
      "tagline": "AI-native Web3 infrastructure — wallet, trade, market, payments",
      "home": "https://web3.okx.com/zh-hans/onchainos/dev-docs/home/what-is-onchainos",
      "devPortal": "https://web3.okx.com/zh-hans/onchainos/dev-portal/project",
      "integrationModes": [
        "Skills (agent conversation)",
        "Open API (programmatic)",
        "Official MCP (DEX tools)"
      ],
      "capabilities": {
        "wallet": {
          "name": "Agentic Wallet",
          "summary": "TEE-backed agent wallet; email/Google/Apple create; agent can trade without exposing keys",
          "docs": [
            "https://web3.okx.com/zh-hans/onchainos/dev-docs/wallet/agentic-wallet"
          ],
          "mcp": {
            "status": "skills-and-api-primary",
            "note": "Prefer Agentic Wallet / user extension for signing; PF never holds keys"
          },
          "priority": "P1"
        },
        "trade": {
          "name": "DEX API / aggregator",
          "summary": "Multi-chain DEX quotes, approve calldata, swap tx construction (EVM + Solana)",
          "docs": [
            "https://web3.okx.com/onchainos/dev-docs/trade/dex-api-introduction",
            "https://web3.okx.com/onchainos/dev-docs/trade/dex-ai-tools-mcp-server"
          ],
          "mcp": {
            "status": "official",
            "url": "https://web3.okx.com/api/v1/onchainos-mcp",
            "authHeader": "OK-ACCESS-KEY",
            "tools": [
              "dex-okx-dex-aggregator-supported-chains",
              "dex-okx-dex-liquidity",
              "dex-okx-dex-quote",
              "dex-okx-dex-approve-transaction",
              "dex-okx-dex-swap",
              "dex-okx-dex-solana-swap-instruction"
            ],
            "xLayerExamples": [
              "Which DEXs are available on X-layer?",
              "How much USDC will I get for 1 OKB on X-layer?"
            ]
          },
          "priority": "P0"
        },
        "market": {
          "name": "Market API",
          "summary": "Multi-market and onchain data: prices, tokens, portfolio, social, balances, tx history",
          "docs": [
            "https://web3.okx.com/onchainos/dev-docs/market/market-api-introduction"
          ],
          "surfaces": [
            "market-price",
            "index-price",
            "token",
            "strategy",
            "address-analysis",
            "social-analysis",
            "balance",
            "tx-history"
          ],
          "mcp": {
            "status": "open-api-primary-probe-official-mcp",
            "note": "If official MCP does not expose market tools, optional thin REST proxy MCP (read-only) is P1"
          },
          "priority": "P1"
        },
        "payments": {
          "name": "Payments (APP protocol)",
          "summary": "Pay-as-you-go agent payment scenarios",
          "docs": [
            "https://web3.okx.com/onchainos/dev-docs/payments/overview"
          ],
          "mcp": {
            "status": "docs-placeholder",
            "note": "P2 — agent gas/API payment story after wallet+trade path works"
          },
          "priority": "P2"
        }
      },
      "dualMcpPattern": {
        "proofForge": {
          "role": "semantic-controlled contracts: build, catalog, docs, local runtime guidance",
          "remote": "https://proof-forge-mcp.davirain-yin.workers.dev/mcp",
          "stdio": "tools/mcp/proof_forge_mcp_server.py",
          "never": [
            "hold OK-ACCESS-KEY for third parties on public edge",
            "broadcast mainnet txs",
            "accept private keys as tool args"
          ]
        },
        "onchainos": {
          "role": "DEX quote/liquidity/swap construction; later market/wallet as available",
          "remote": "https://web3.okx.com/api/v1/onchainos-mcp",
          "auth": "OK-ACCESS-KEY from OnchainOS dev portal (app-local)"
        }
      },
      "roadmap": {
        "P0": [
          "Ship networks.v1.json with X Layer testnet/mainnet + Anvil",
          "Expose pf_network_info / pf_onchainos_guide on PF MCP",
          "Document dual-MCP wiring for agents",
          "evm-dapp-ui chain presets for X Layer (read/attach; no default public hot-key deploy)"
        ],
        "P1": [
          "Probe official MCP tools/list after API key",
          "Optional read-only market REST proxy MCP if needed",
          "Agentic Wallet / Skills wiring notes for dApp demos",
          "Engineering deploy script for X Layer testnet (developer-local key env)"
        ],
        "P2": [
          "Payments APP protocol integration notes",
          "More EVM rows (Base, Arbitrum, …) when product needs them",
          "Lean NetworkRegistry product cutover for deploy identity join (spec already exists)"
        ]
      }
    }
  }
} as const;

export const DOCS_INDEX_JSON = {
  "schema": "proof-forge.mcp.docs-index.v1",
  "docs": [
    {
      "id": "01-toolchain-install-surface.md",
      "title": "Product surface ladder — install / doctor / CLI / MCP",
      "bytes": 17976,
      "kind": "markdown"
    },
    {
      "id": "02-external-program-v1.md",
      "title": "External ProgramV1 project guide (build / SDK / MCP)",
      "bytes": 4176,
      "kind": "markdown"
    },
    {
      "id": "03-hello-dapp-agent-playbook.md",
      "title": "Hello dApp agent playbook (MCP / SDK / external template)",
      "bytes": 4459,
      "kind": "markdown"
    },
    {
      "id": "04-chain-client-catalog.md",
      "title": "Chain client / frontend catalog (metadata for agents)",
      "bytes": 4367,
      "kind": "markdown"
    },
    {
      "id": "05-distribution-and-packages.md",
      "title": "Distribution architecture — CLI release vs Lean author SDK vs host wrappers",
      "bytes": 16425,
      "kind": "markdown"
    },
    {
      "id": "06-pypi-host-sdk.md",
      "title": "Host SDK PyPI publish (engineering-dist)",
      "bytes": 5561,
      "kind": "markdown"
    },
    {
      "id": "07-aleo-dapp-frontend-wallet.md",
      "title": "Aleo dApp frontend — Wallet Adapter + Provable SDK (FCCP companion)",
      "bytes": 16801,
      "kind": "markdown"
    },
    {
      "id": "08-evm-dapp-frontend.md",
      "title": "EVM dApp frontend — viem/MetaMask + PF bytecode (FCCP companion)",
      "bytes": 5218,
      "kind": "markdown"
    },
    {
      "id": "09-solana-agent-playbook.md",
      "title": "Solana agent playbook — ProofForge CLI/SDK first",
      "bytes": 3905,
      "kind": "markdown"
    },
    {
      "id": "10-psy-dpn-lowering.md",
      "title": "Psy DPN lowering contract",
      "bytes": 5915,
      "kind": "markdown"
    },
    {
      "id": "10-psy.md",
      "title": "Psy DPN target dossier",
      "bytes": 6254,
      "kind": "markdown"
    },
    {
      "id": "10-solana-dapp-frontend.md",
      "title": "Solana dApp frontend — wallet-adapter + PF IDL (not Anchor)",
      "bytes": 5096,
      "kind": "markdown"
    },
    {
      "id": "11-psy-agent-playbook.md",
      "title": "Psy agent playbook — ProofForge DPN + official Psy toolchain",
      "bytes": 8164,
      "kind": "markdown"
    },
    {
      "id": "12-psy-dapp-frontend.md",
      "title": "Psy dApp frontend — wallet + SDK (FCCP companion)",
      "bytes": 4905,
      "kind": "markdown"
    },
    {
      "id": "13-xlayer-onchainos.md",
      "title": "X Layer networks + OKX OnchainOS integration (catalog / MCP / roadmap)",
      "bytes": 7987,
      "kind": "markdown"
    },
    {
      "id": "aleo-testnet-walkthrough.md",
      "title": "Demo — Aleo with pf (local run → Testnet deploy → execute)",
      "bytes": 11782,
      "kind": "markdown"
    },
    {
      "id": "evm-local-walkthrough.md",
      "title": "Demo — EVM with pf (build → Anvil deploy → browser UI)",
      "bytes": 1718,
      "kind": "markdown"
    },
    {
      "id": "mcp-stdio-readme.md",
      "title": "ProofForge MCP-V0",
      "bytes": 4858,
      "kind": "markdown"
    },
    {
      "id": "psy-dpn-walkthrough.md",
      "title": "Demo — Psy DPN with pf (+ official ecosystem pointers)",
      "bytes": 3732,
      "kind": "markdown"
    },
    {
      "id": "solana-local-walkthrough.md",
      "title": "Demo — Solana with pf (build → Surfpool → UI)",
      "bytes": 2594,
      "kind": "markdown"
    },
    {
      "id": "chain-client-catalog.v1.json",
      "title": "Chain client catalog",
      "bytes": 20038,
      "kind": "catalog"
    },
    {
      "id": "networks.v1.json",
      "title": "Network catalog (X Layer / Anvil)",
      "bytes": 10314,
      "kind": "catalog"
    }
  ]
} as const;

export const MARKDOWN: Record<string, string> = {
  "01-toolchain-install-surface.md": "---\nid: PRODUCT-TOOLCHAIN-INSTALL-SURFACE\ntitle: Product surface ladder — install / doctor / CLI / MCP\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# 产品面阶梯：安装选链 → 本机验证 → SDK / MCP\n\n状态：`draft`（2026-08-10；I0–I2 + MCP-V0 + SDK-V0 + distribution REL-CLI/Author/CI engineering done；Aleo/Psy tool/runtime lanes removed）\n执行入口：workflow `product-surface-ladder`（`.grok/workflows/product-surface-ladder.rhai`）\nTool Lock 规范：[`specs/toolchains.md`](../specs/toolchains.md)（`proof-forge.toolchains.v4`）\n\n## 0. 实现状态（诚实）\n\n| 相位 | 状态 |\n|---|---|\n| **DOC**（本文 + index 指针） | **done**（本文件） |\n| **I0 doctor** | **done**（`scripts/proof_forge_doctor.py` + `proof-forge-next doctor`；schema `proof-forge.doctor.v1`；缺 Tool Root → `PF-TOOLCHAIN-MISSING`） |\n| **I1 install** | **done**（`scripts/proof_forge_install.py` + `proof-forge-next install`；schema `proof-forge.install.v1`；`--targets`/`--all-core` + `--yes`；delegate `toolchain_assets` provision/materialize；digest 幂等 skip；无 PATH fallback；`--dry-run` 计划-only） |\n| I1b CLI wire residual | **done with I1**（CLI 薄包装 + parse 覆盖 + `scripts/install_smoke.sh`；若后续扩 usage 文案仍可叠） |\n| I2 local/network 统一包装 | **done / narrowed**（`local` 仅保留 EVM/Solana runtime wrappers；`network` 对全部 target fail closed；`scripts/local_network_smoke.sh`） |\n| **MCP-V0** | **done** (stdio) + **remote edge** `clients/pf-mcp` → https://proof-forge-mcp.davirain-yin.workers.dev/mcp（`tools/mcp/proof_forge_mcp_server.py` stdio MCP；tools: `pf_list_targets`/`pf_doctor`/`pf_install`/`pf_build`/`pf_artifacts`；仅 spawn 产品 CLI/引擎 JSON；无 network broadcast 工具；`tools/mcp/README.md` Agent 接线；`scripts/mcp_smoke.sh`） |\n| **SDK-V0** | **done**（Python `tools/sdk/proof_forge_sdk.py`：`ProofForgeClient` spawn `proof-forge-next` + parse doctor/install/list-targets JSON + `load_output_manifest` for engineering `proof-forge.output.v1`；非第二编译器；`tools/sdk/README.md`；`scripts/sdk_smoke.sh`） |\n| **Close** | **done**（本文 + index 成熟度诚实；剩余 backlog：交互式 install UI、全链 runtime pack、N3 前 `deployable=true` 禁改） |\n| **External ProgramV1** | **done engineering**（[`02-external-program-v1.md`](02-external-program-v1.md) + `templates/external-aleo-hello/` + sandbox/SDK/MCP `--root` + `just external-hello-smoke`；非 Lake SDK / formal） |\n| **Hello agent playbook** | **done engineering**（[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)；MCP 顺序 doctor→install→build/local→artifacts） |\n| **Chain client catalog** | **done engineering**（[`04-chain-client-catalog.md`](04-chain-client-catalog.md) + `chain-client-catalog.v1.json` + `pf_chain_catalog` / SDK `chain_catalog`；元数据 only） |\n| **Distribution / packages** | **engineering-dist + PyPI wiring done**（[`05-distribution-and-packages.md`](05-distribution-and-packages.md) / [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)：CLI multi-arch、Author SDK、Host wheel+OIDC PyPI job；Trusted Publisher 需一次人工配置；formal Stage-0 仍 pending） |\n\n本文是 **产品契约与实现顺序** 的权威草稿；I0–I2、MCP-V0、SDK-V0 与 distribution engineering dist 已接线。Aleo/Psy 仅保留 zero-tool direct materializer；不再提供 Leo/Dargo/snarkOS/local VM/network 产品或工程 lane。不声称 formal / hermetic / mainnet / Stage-0。\n\n## 1. 产品目标\n\n用户安装 / 使用 ProofForge 时：\n\n1. **知道** 当前支持哪些 target（`TargetRegistryV1` 事实，非营销名单）。\n2. **选择** 要开发的链，安装对应 **Tool Lock** 锁定工具到 `PROOF_FORGE_TOOL_ROOT`。\n3. **诊断** 缺工具 / digest 不匹配（`doctor`），再 **build / local / network**。\n4. 后续 **SDK / MCP** 只封装同一 CLI 契约，供 Code Agent 做 Web Coding。\n\n## 2. 非目标\n\n- 不把 install 变成「静默 PATH 扫全盘随便装」。\n- 不默认 `deployable=true` 或主网广播（无产品 N3 决策不得改写 maturity）。\n- 不在 ordinary `just ci` 里起 snarkOS / Anvil / Mollusk。\n- 不先做大而全多语言 SDK；先 CLI + 薄封装。\n- design-only target（`soroban` / `icp` / `openvm`）只展示为 `unsupported`，不提供假安装。\n- 不发明 Tool Lock 外的第二工具权威或 “best effort” fallback 进 Tool Root。\n\n## 3. 阶梯切片（workflow 相位）\n\n| 相位 | ID | 交付 | 完成标准 |\n|---|---|---|---|\n| DOC | `DOC` | 本文 + `docs/index.md` 指针 | `just docs-check` 过 |\n| I0 | `I0-DOCTOR` | `proof-forge-next doctor` | **done**：每 implemented target 报告 ok/missing/mismatch/partial；`--json`=`proof-forge.doctor.v1`；无 Tool Root → `PF-TOOLCHAIN-MISSING`；引擎 `scripts/proof_forge_doctor.py`；CLI 薄包装 |\n| I1 | `I1-INSTALL` | 非交互 `install --targets a,b --yes` | **done**：`scripts/proof_forge_install.py`；复用 `toolchain_assets` provision/materialize；只装 lock 内 asset；digest 校验；幂等 skip；`--dry-run`/`--json`；`scripts/install_smoke.sh` |\n| I1b | `I1b-CLI-WIRE` | CLI 子命令接到 Exe；`--json`；usage | **done with I1**：`proof-forge-next install` 薄包装 + parse 覆盖 |\n| I2 | `I2-LOCAL-CMDS` | 统一本机入口包装 | **done / narrowed**：`local --target evm|solana` 调现有 runtime 脚本；`network` 全 target fail closed；`scripts/local_network_smoke.sh` |\n| MCP | `MCP-V0` | 最小 MCP server | **done**：`tools/mcp/proof_forge_mcp_server.py`；tools 含 `pf_local`（仅 EVM/Solana）+ build/doctor；拒 network broadcast；见 §8 |\n| SDK | `SDK-V0` | 可选薄 SDK（TS 或 Python 选一） | **done**（Python）：`tools/sdk/proof_forge_sdk.py`；spawn CLI + `local` 通用 API + parse manifest；非第二编译器；见 §9 |\n| Close | `Close` | AGENTS/backlog 指针 | **done**：成熟度诚实；不声称 formal / hermetic / mainnet；剩余见 §0 Close 行 |\n\n## 4. 架构约束\n\n```text\nUser / Agent\n    │\n    ▼\nproof-forge-next  (sole product CLI)\n    │  doctor | install | build | check | local | network | inspect | list-targets\n    ▼\nscripts/toolchain_assets.py  +  Tool Lock v4\n    │\n    ▼\nPROOF_FORGE_TOOL_ROOT/   # default: ~/.cache/proof-forge-v2/tool-root/<platform>/\n    solc, sbpf, nargo, wat2wasm, anvil, …  (lock-defined only)\n```\n\n### 4.1 Tool Lock 权威菜单\n\n| File | `platform` | 备注 |\n|---|---|---|\n| `toolchains.lock.json` | `darwin-arm64` | Mach-O policy |\n| `toolchains-linux-x86_64.lock.json` | `linux-x86_64` | ELF policy |\n\n- Schema：`proof-forge.toolchains.v4`（见 SPEC-TOOL-001）。\n- **当前无** `linux-aarch64` 等其它平台 lock；未锁平台上 install 必须 fail closed。\n- 引擎：`scripts/toolchain_assets.py`（provision / materialize / verify）；产品 install 是其薄 CLI 包装，不复制第二份下载逻辑。\n- **禁止** PATH fallback 把非 lock 二进制写入 `PROOF_FORGE_TOOL_ROOT`。\n\n### 4.2 Target 菜单\n\n- **Implemented（可 install 编译档）**：`evm`、`solana`、`near`、`noir`、`aleo`、`psy`、`quint`、`cosmwasm`、`ton`（与 `TargetRegistryV1` 九 materializer 一致）。\n- **Design-only（`unsupported`，不可 install）**：`soroban`、`icp`、`openvm`。\n- Accepted PRD Phase 1 文案仍为四目标；engineering 九 target 扩面不自动改写 accepted 范围（ADR-0036）。\n\n### 4.3 编译档 vs runtime 档\n\n| 档 | 默认 `install` | 例 |\n|---|---|---|\n| **core / compile** | 是（`--targets` / `--all-core`） | `solc`、`sbpf`、`nargo`、`wat2wasm`、`tolk`、`cosmwasm-check`、`jv` |\n| **runtime** | 否；需 `--with-runtime` 或 `--profile runtime` | lock：`anvil`/`cast`、`near-sandbox` |\n\nhost-heavy 门（`just solana-runtime` / Anvil）**不**并入 ordinary `just ci`。\n\n### 4.4 Implemented target → lock tools（doctor 规划表）\n\n| Target | core tools（Tool Lock ids） | runtime / 额外 |\n|---|---|---|\n| `evm` | `solc` | `anvil`、`cast`（runtime 档） |\n| `solana` | `sbpf` | Mollusk 等工程 harness（非本 lock 的 install 默认面；runtime 文档另述） |\n| `near` | `wat2wasm` | `near-sandbox`（runtime） |\n| `noir` | `nargo` | prove/VK / barretenberg：**unresolved / FC**（见 lock `unresolved.barretenberg`） |\n| `aleo` | —（sole `aleo-instructions-v1` zero-tool） | 无 compiler/runtime/network lane |\n| `psy` | —（sole `psy-dpn-v1` zero-tool） | 无 compiler/runtime/network lane |\n| `quint` | `jv`（模型侧辅助；Quint 产品 finalize 仍 zero-tool source） | 无 snarkOS 类 runtime |\n| `cosmwasm` | `wat2wasm`、`cosmwasm-check` | wasmd Docker rung 等工程门，非 CLI 默认 install |\n| `ton` | `tolk` | sandbox 工程门独立 |\n\n表中 “core” 是 doctor/install 的 **规划映射**；某 profile 的 exact `requiredByProfiles` 仍以 lock 字段为准，不得在 doctor 里发明额外工具。\n\n## 5. doctor 输出契约（I0）\n\n对 zero-tool direct target，doctor 必须明确报告空工具集合，而不是要求已删除的编译器：\n\n```text\nplatform=linux-x86_64\ntool_root=...\ntarget=aleo status=ok\n```\n\n```json\n{\n  \"schema\": \"proof-forge.doctor.v1\",\n  \"platform\": \"linux-x86_64\",\n  \"toolRoot\": \"...\",\n  \"targets\": [\n    {\"id\": \"aleo\", \"status\": \"ok\", \"tools\": []},\n    {\"id\": \"psy\", \"status\": \"ok\", \"tools\": []}\n  ]\n}\n```\n\n状态枚举：`ok` | `partial` | `missing` | `mismatch` | `unsupported`。\n\n- 无 `PROOF_FORGE_TOOL_ROOT` 且默认 cache 不存在 → fail closed：stderr `PF-TOOLCHAIN-MISSING: tool root does not exist: …`，exit 3。\n- `PROOF_FORGE_TOOL_ROOT` 非绝对路径 → `PF-TOOLCHAIN-MISMATCH`，exit 3。\n- 对所有非 zero-tool target，Tool Root 采用 **current-lock exact-set closure**：允许只物化所选 target 的 lock 子集，但任何不属于当前全局 Tool Lock 的文件、目录、symlink 或 special node 都使 target 为 `mismatch`，并给出 `install --all-core --yes` 修复提示。这样已退役工具不会再出现 doctor 绿、构建门禁红。\n- design-only id → `unsupported`，不假装可装。\n- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_doctor.py`；产品 CLI：`proof-forge-next doctor` 通过 `PackageRootV1` 解析 package root（`PROOF_FORGE_ROOT` 绝对路径 → `IO.appDir` 父目录含 `scripts/` → CWD），并以 `cwd=packageRoot` spawn。\n- 聚焦 smoke：`scripts/doctor_smoke.sh`。\n\n## 6. install 契约（I1）\n\n```bash\nproof-forge-next install --targets solana --yes\nproof-forge-next install --all-core --yes   # 所有 implemented target 的非空 compile/core 档\n```\n\n- 无 `--yes` 且非 `--dry-run` → usage / fail closed（非交互；不提供 TTY 确认）。\n- 禁止 PATH fallback 安装进 Tool Root。\n- 已存在且 digest 匹配 → skip（幂等）。\n- 只物化 **当前平台 lock** 中的 asset；跨平台/缺锁 fail closed。\n- 每次 install（包括 zero-tool target）都会扫描 Tool Root：保留当前 lock 中尚未选装的合法成员，清除不再属于当前 lock 的退役节点；`--dry-run` 只在 `notes` 报告 `would remove`，不落盘。\n- `--with-runtime` 仅物化 lock 内 runtime 工具（`anvil`/`cast`、`near-sandbox`）；Aleo/Psy 没有 runtime 配方或外部工具 fallback。\n- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_install.py`；产品 CLI：`proof-forge-next install` 同样经 `PackageRootV1` 定位 package root并以 `cwd=packageRoot` spawn。\n- 聚焦 smoke：`scripts/install_smoke.sh`（含 temp root 上 `quint`/`jv` 物化 + 幂等 skip + Aleo/Psy zero-tool + 退役 `leo` dry-run/清理断言）。\n- 成功后同一进程或紧随 `doctor` 可验证 present。\n\n## 7. 本机包装（I2）\n\n**已实现并收窄**。`local` 只保留 EVM/Solana 已有 runtime wrapper；Aleo/Psy 及其它 target\nfail closed。已删除无实现 target 的 `network` 子命令：\n\n```bash\nproof-forge-next local --target solana [--mode runtime] [--json] [--] [script-args...]\nproof-forge-next local --target evm [--mode runtime] [--json] [--] [script-args...]\n```\n\n| Target | `local` 模式（默认） | 包装脚本 | 等价工程入口 |\n|---|---|---|---|\n| `solana` | `runtime`（默认） | `scripts/solana_runtime_test.sh` | `just solana-runtime` |\n| `evm` | `runtime`（默认） | `scripts/evm_anvil_differential.sh` | Anvil engineering smokes |\n| 其它 implemented | — | fail closed（无产品 script path） | 见 target dossier |\n| design-only | — | fail closed `unsupported` | 不可 install/local |\n\n- local wrapper 经 `PackageRootV1` 定位 package root，以 `cwd=packageRoot` 固定执行 `/bin/bash -p`，\n  并设置 `PROOF_FORGE_ROOT=packageRoot`；禁止 PATH/BASH_ENV fallback。\n- 顶层 `network` 子命令已删除，作为未知命令以 usage / exit 2 拒绝；build 的 `--network`\n  flag 同样为 usage error，因为尚无 network registry。\n- schema 仅为 `proof-forge.local.v1`；不得在 JSON 中暴露秘密。\n- 聚焦门：`scripts/local_network_smoke.sh`。实际 runtime 仍 host-heavy，不并入 ordinary CI 或 formal evidence。\n\n## 8. MCP-V0 工具列表 — **done**\n\n实现：`tools/mcp/proof_forge_mcp_server.py`（stdlib-only stdio JSON-RPC MCP；newline 分隔；stderr 日志）。\n接线说明：`tools/mcp/README.md`。聚焦 smoke：`scripts/mcp_smoke.sh`。\n\n| Tool | 映射 |\n|---|---|\n| `pf_list_targets` | `list-targets [--all] --json` → `proof-forge.cli.list-targets.v1` |\n| `pf_doctor` | `doctor --json` → `proof-forge.doctor.v1` |\n| `pf_install` | `install --targets … --yes`（或 `--dry-run`）`--json` → `proof-forge.install.v1` |\n| `pf_build` | `build` source `--module` `--target` `-o` `--json`（**拒** broadcast/network 参数） |\n| `pf_artifacts` | `inspect --output-dir <dir> --json` 或 `inspect <target> --json` |\n| `pf_local` | `local --target … [--mode sandbox]` + 透传 script args；Aleo sandbox **通用** 须 `source`+`module`（可选 `root`/`runs`/`golden`/`skipRun`；有 `root` 时传为 product `--root`）；**拒** broadcast / private-key |\n| `pf_chain_catalog` | 静态 `docs/product/chain-client-catalog.v1.json`（前后端分工元数据；不装前端包、不 broadcast） |\n\nV0+ 已暴露 `pf_local` 与 `pf_chain_catalog`；**仍不**暴露 network broadcast 工具（network 必须显式 `network --broadcast`，不经 MCP 默认面）。Hello 剧本见 [`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)。\n返回包装 schema：`proof-forge.mcp.tool-result.v1`（`ok`/`exitCode`/`command`/`stdout`/`stderr`/`parsed`/`error`）。\nEnv：`PROOF_FORGE_ROOT` / `PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT`（继承 doctor/install/build 契约）。\nMCP **只** spawn 产品 CLI 并解析 JSON/manifest，不内嵌 solc/leo/nargo；不 PATH fallback 写 Tool Root；不改 `deployable`。\n\n## 9. SDK-V0 — **done**（Python）\n\n实现：`tools/sdk/proof_forge_sdk.py`（stdlib-only；可选 `PYTHONPATH=tools/sdk`）。\n接线说明：`tools/sdk/README.md`。聚焦 smoke：`scripts/sdk_smoke.sh`。\n\n| API | 映射 |\n|---|---|\n| `ProofForgeClient.list_targets` | `list-targets [--all] --json` → `proof-forge.cli.list-targets.v1` |\n| `ProofForgeClient.doctor` | `doctor --json` → `proof-forge.doctor.v1`（exit 3 + body 仍 `ok` 给 Agent） |\n| `ProofForgeClient.install` | `install --yes`/`--dry-run --json` → `proof-forge.install.v1` |\n| `ProofForgeClient.build` / `check` | 产品 `build`/`check --json`；**拒** design-only target；**无** network/broadcast |\n| `ProofForgeClient.inspect_artifacts` / `inspect_target` | `inspect --output-dir` / `inspect <target> --json` |\n| `ProofForgeClient.local` | `local --target …`；Aleo sandbox 透传 `--source`/`--module`/`--root`/`--run`（通用；有 `root=` 时传为 product `--root`；拒 broadcast/signer） |\n| `ProofForgeClient.chain_catalog` | 静态 chain client catalog（`proof-forge.chain-client-catalog.v1`） |\n| `load_output_manifest` / `client.load_output_manifest` | 读 on-disk `manifest.json` 的 engineering `schemaVersion=proof-forge.output.v1`（**不**重走 exact disk closure；closure 用 `inspect_artifacts`） |\n\n- 返回载体 schema：`proof-forge.sdk.result.v1`（`ok`/`exitCode`/`command`/`stdout`/`stderr`/`parsed`/`error`/`productOk`）。\n- Env：`PROOF_FORGE_ROOT` / `PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT`（与 MCP/CLI 相同契约）。\n- **非**第二编译器、**非**第二 Tool Root 写入器、**无** PATH fallback 物化 lock tools、**不**改 `deployable`。\n- 未做：TS SDK、交互式 install UI、全链 runtime pack 一键装、pip 发布。\n\n## 11. 与现有脚本 / CLI 关系\n\n| 现有 | 角色 |\n|---|---|\n| `scripts/toolchain_assets.py` | install 引擎（I1 复用） |\n| `toolchains*.lock.json` | 唯一可装 tool 菜单 |\n| `just toolchains-*` | 工程/CI 旁路；产品 CLI 成后文档主推 CLI |\n| `proof-forge-next` 现有 | `build` / `check` / `inspect` / `list-targets` / **`doctor`** / **`install`** / **`local`** / **`network`** |\n| `tools/mcp/proof_forge_mcp_server.py` | MCP-V0 stdio 薄封装（仅 spawn 上列 CLI JSON） |\n| `tools/sdk/proof_forge_sdk.py` | SDK-V0 Python 薄客户端（spawn CLI + parse JSON/manifest） |\n| `scripts/solana_runtime_test.sh` / `scripts/evm_anvil_differential.sh` | I2 `local --target solana|evm`；`just solana-runtime` / Anvil 工程 lane 仍可用 |\n\n## 12. 验证\n\n- 每切片：聚焦测或脚本 smoke + `just docs-check`。\n- 改 Lean 产品面时按 AGENTS 跑相关测 + 必要时 `just sbom-package-files-refresh`。\n- 不声称 ordinary ci 已含 host-heavy runtime。\n- 不声称 formal Stage-0 / hermetic / mainnet / release。\n\n## 13. 相关文档\n\n- Tool Lock：[`specs/toolchains.md`](../specs/toolchains.md)\n- CLI 规格：[`specs/cli.md`](../specs/cli.md)\n- 导航：[`index.md`](../index.md)\n- 工作流：`.grok/workflows/product-surface-ladder.rhai`\n",
  "02-external-program-v1.md": "---\nid: PRODUCT-EXTERNAL-PROGRAM-V1\ntitle: External ProgramV1 project guide (build / SDK / MCP)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# 外部 ProgramV1 工程：写合约 → build → inspect\n\n状态：`draft`（2026-08-10；external ProgramV1 build surface）\n前置：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)\n\n## 1. 权威范围与目标\n\n本文说明外部目录如何满足 source gate、如何用 `--root` + 相对 `--source` 调用 build，\n以及 SDK/MCP 对同一 build/inspect 契约的字段映射。它不扩大 target maturity，也不替代\nCLI、Aleo target 或 OutputSet 规格。\n\n作者在 **ProofForge monorepo 之外**维护一个最小工程目录，用产品 CLI\n`build --target aleo` 得到 canonical Instructions + query-contract，再经 `inspect`、SDK 或 MCP\n复用同一 OutputSet 契约。Aleo 没有 Leo sandbox/runtime/network 产品 lane。\n\n**不要求** 外部工程 `require` Lake 包 `proof-forge-next`。产品 `build` 路径是进程内\n`IO.FS.readFile` → Loader，不是 `lake build` 用户包。\n\nCloseout honesty：external source tree + `--root` build 与 SDK/MCP build 字段映射已接线。Aleo profile 是 zero-tool `aleo-instructions-v1`，保持 **`deployable=false`**；无本地执行、网络广播或 formal/release 声明。\n\n## 2. 源文件契约\n\n| 规则 | 说明 |\n|---|---|\n| 文件扩展名 | `.lean` |\n| 必填首行门 | 源文本须 **exact** 含 `import ProofForgeV2`（产品 gate；非 Lake 解析） |\n| 程序形状 | 统一 `program Name where …`（用户不写顶层 kind） |\n| `--source` | 相对 `--root` 的规范相对路径（如 `src/Hello.lean`） |\n| `--module` | 必填 pure Lean module 标识（可与 program 名不同；模板用 `Hello`） |\n| `--root` | 外部工程根；省略时默认 CLI CWD / 包根（见 CLI 规格） |\n\n最小 Hello 是一个 UInt64 counter：`init` / `entry increment` / `view get`。\n\n## 3. 推荐目录\n\n```text\nmy-dapp-contracts/           # --root\n  README.md\n  src/\n    Hello.lean              # import ProofForgeV2 + program Hello where …\n  out-aleo/                 # build -o（gitignore）\n```\n\n\n## 4. 命令阶梯（Aleo direct Instructions）\n\n```bash\nexport PF=/path/to/proof_forge\nexport PROOF_FORGE_CLI=$PF/.lake/build/bin/proof-forge-next\nexport PROJ=/path/to/my-dapp-contracts\n\n# 0) doctor（Aleo 为 zero-tool target）\n(cd \"$PF\" && \"$PROOF_FORGE_CLI\" doctor --target aleo --json)\n\n# 1) build\n\"$PROOF_FORGE_CLI\" build src/Hello.lean \\\n  --module Hello --target aleo --root \"$PROJ\" -o \"$PROJ/out-aleo\"\n\n# 2) inspect\n\"$PROOF_FORGE_CLI\" inspect --output-dir \"$PROJ/out-aleo\" --json\n```\n\n生成的 `.aleo` 是 canonical Aleo Instructions 制品；query descriptor 只描述 network-state 查询契约。\n产品不调用 Leo、snarkOS 或其它本地/网络 runtime。\n\n## 5. SDK / MCP\n\n| 面 | 用法 |\n|---|---|\n| SDK | `client.build(..., target=\"aleo\", root=…)` 后读取 OutputSet manifest |\n| MCP | `pf_build` 后用 `pf_artifacts` 检查 exact disk closure |\n\nAgent 剧本：\n\n1. `pf_doctor`（target=aleo；预期 zero-tool `ok`）\n2. 写/改 `src/Hello.lean`\n3. `pf_build`\n4. `pf_artifacts` 看 OutputSet\n\nMCP-V0 不暴露 Aleo local/network action。\n\n## 6. 非目标\n\n- 不要求外部工程作为 Lake SDK package 依赖 `proof-forge-next`；CLI source gate 已足够\n- 不提供完整 Lean IDE 插件 / 语法高亮包（可后续）\n- 不把 monorepo `Examples` 设为 sole 外部入口\n- 不设 `deployable=true`、不 formal、不主网\n- 不提供 Aleo compiler、local runtime、network deploy/execute 或其 fallback\n\n## 7. 聚焦门\n\n外部模板复用 ordinary product build/inspect smoke；不再有 Aleo-specific external sandbox recipe。\n\n## 8. 成熟度\n\n| 层 | 状态 |\n|---|---|\n| 外部源 + `--root` build | **engineering done** |\n| Direct Instructions + query descriptor | **engineering done** |\n| MCP / SDK external root fields | **engineering done** |\n| Local/compiler/network runtime | **removed / unsupported** |\n| Lake syntax package | **optional remaining**（not required for product build） |\n| Formal / release | **remaining** |\n",
  "03-hello-dapp-agent-playbook.md": "---\nid: PRODUCT-HELLO-DAPP-AGENT-PLAYBOOK\ntitle: Hello dApp agent playbook (MCP / SDK / external template)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Hello dApp：Code Agent 剧本（后端合约 + direct artifact）\n\n状态：`draft`（2026-08-10）\n前置：[`02-external-program-v1.md`](02-external-program-v1.md)、[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)  \nCatalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md) / `pf_chain_catalog`\n\n## 1. 范围\n\n本剧本让 **Code Agent**（经 MCP）或脚本（经 SDK/CLI）完成 **hello 级 artifact 闭环**：\n\n```text\ndoctor → 写/确认 ProgramV1 → build → inspect artifacts\n```\n\n**后端** = ProofForge `program … where` 合约。  \n**前端** = 生态客户端（见 chain catalog）；本剧本 **不** 生成完整 Web UI，只钉后端可测。\n\n## 2. 非目标\n\n- MCP **不**暴露 `network --broadcast` / private-key\n- 不设 `deployable=true`、不主网、不 formal\n- 不发明 Aleo compiler/local runtime/network fallback\n- 不要求外部工程 Lake `require` PF\n\n## 3. 环境\n\n| 变量 | 含义 |\n|---|---|\n| `PROOF_FORGE_ROOT` | monorepo 根（含 `scripts/`、`tools/mcp/`） |\n| `PROOF_FORGE_CLI` | `proof-forge-next` 绝对路径 |\n| `PROOF_FORGE_TOOL_ROOT` | Tool Lock 根；Aleo direct target 不需要工具 |\n\nMCP 接线见 [`tools/mcp/README.md`](../../tools/mcp/README.md)。\n\n## 4. MCP 工具顺序（Aleo Hello）\n\n| 步 | Tool | 参数（示意） | 成功判据 |\n|---|---|---|---|\n| 0 | `pf_chain_catalog` | `target=aleo` | 看到 direct artifact + honesty |\n| 1 | `pf_doctor` | `targets=[\"aleo\"]` | JSON `proof-forge.doctor.v1`；zero-tool `ok` |\n| 2 | 写源 | 文件系统 | `import ProofForgeV2` + `program Hello where` |\n| 3 | `pf_build` | 见下 | exit 0 |\n| 4 | `pf_artifacts` | `outputDir=…` | exact closure inspect |\n\n### 4.1 仅 build\n\n```json\n{\n  \"source\": \"src/Hello.lean\",\n  \"module\": \"Hello\",\n  \"target\": \"aleo\",\n  \"root\": \"/abs/path/to/project\",\n  \"output\": \"/abs/path/to/project/out-aleo\"\n}\n```\n\n构建结果是 canonical Aleo Instructions + query descriptor。`pf_local` 对 Aleo fail closed；\n不存在 Leo/Dargo/snarkOS fallback。\n\n## 5. SDK 等价\n\n```python\nfrom proof_forge_sdk import ProofForgeClient\nc = ProofForgeClient()\nc.doctor(targets=[\"aleo\"])\nresult = c.build(\n    source=\"src/Hello.lean\",\n    module=\"Hello\",\n    target=\"aleo\",\n    root=\"/abs/path/to/project\",\n    output=\"/abs/path/to/project/out-aleo\",\n)\nprint(result.parsed)\n```\n\n## 6. CLI 等价\n\n```bash\nproof-forge-next build src/Hello.lean --module Hello --target aleo \\\n  --root \"$PROJ\" -o \"$PROJ/out-aleo\"\nproof-forge-next inspect --output-dir \"$PROJ/out-aleo\" --json\n```\n\n## 7. 前端下一步（Aleo dApp）\n\nAgent 完成后端后，**前端不是可选闲笔**——完整 Aleo APP 需要 Wallet 交互。权威剧本：\n\n[`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md)\n\n最短路径：\n\n1. `pf_chain_catalog` `target=aleo` → 读 `frontendClients`（`@provablehq/aleo-wallet-adaptor-*` · `@provablehq/sdk`）\n2. 脚手架：复制/打开 [`templates/aleo-dapp-ui`](../../templates/aleo-dapp-ui/)（Vite + `AleoWalletProvider` / `WalletMultiButton`）\n3. 从 PF `pf deploy`（或 explorer）取得 **program id**，写入前端 env（**无私钥**）\n4. 用户钱包 `executeTransaction` 调 `initialize` / `increment`；public mapping 用 explorer REST 读\n5. 开发者本机仍可用 `pf deploy|execute --broadcast` 做冒烟；**终端用户只走钱包**\n\n边界：\n\n- MCP **不**代签、不持 key、不默认 broadcast\n- 不得从 Instructions artifact  alone 推断「已部署」\n- 浏览器禁止嵌入 `APrivateKey1…`\n\n\n## 7b. EVM 前端下一步\n\n对称 Aleo 前端剧本：[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md)\n\n```bash\nbash scripts/pf_evm_local_demo.sh\ncd templates/evm-dapp-ui && npm install && npm run dev\n```\n\n本地 Anvil only；无 public broadcast。\n\n## 8. 失败剧本\n\n| 现象 | 处理 |\n|---|---|\n| 缺 `--source`/`--module` | usage exit；补参数 |\n| `import ProofForgeV2` 缺失 | `PF-SRC-INVALID`；补 gate 行 |\n| Aleo local/network 请求 | **拒绝**；只支持 direct build/inspect |\n| design-only target | catalog `implemented=false`；不 install/build |\n\n## 9. 成熟度标签（日志中应保持）\n\n- `deployable=false`\n- `ALEO-INSTRUCTIONS-DIRECT`\n- `NO-LOCAL-OR-NETWORK-RUNTIME`\n- 非 formal / 非 mainnet\n",
  "04-chain-client-catalog.md": "---\nid: PRODUCT-CHAIN-CLIENT-CATALOG\ntitle: Chain client / frontend catalog (metadata for agents)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# 多链客户端 / 前端 catalog（元数据）\n\n状态：`draft`（2026-08-09）  \n机器可读权威：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  \n网络表：[`networks.v1.json`](networks.v1.json)（schema `proof-forge.network-catalog.v1`）  \nX Layer / OnchainOS：[`13-xlayer-onchainos.md`](13-xlayer-onchainos.md)  \nschema：`proof-forge.chain-client-catalog.v1`  \nMCP：`pf_chain_catalog` · `pf_network_info` · `pf_onchainos_guide` · SDK：`chain_catalog` / `network_catalog`\n\n## 1. 目的\n\n给 Code Agent / 作者回答：\n\n- 某条链 **后端** 走 ProofForge 哪些入口（build / local / network）？\n- **前端 / 客户端** 生态常见包是什么（**不由 PF 发货或 pin**）？\n- 本机如何测、哪些诚实边界？\n\n**不是** 第二编译器、不是钱包实现、不是 RPC 代理。\n\n## 2. 字段（每 target）\n\n| 字段 | 含义 |\n|---|---|\n| `id` | `TargetId` |\n| `implemented` | registry implemented vs design-only |\n| `maturityLabel` | 工程成熟度文案（非 formal） |\n| `role` | `backend-contracts` / circuits / model / design-only |\n| `pfSurface` | build/localModes/network/mcpTools/template |\n| `frontendClients[]` | 生态客户端名；`shippedByProofForge=false` |\n| `localDev` | offline interpret / chain-like engineering gates |\n| `honesty[]` | 禁止升级话术 |\n\n## 3. 后端 vs 前端\n\n```text\n                    ┌─────────────────────────────┐\n  Agent / Author    │  ProofForge CLI / SDK / MCP │  后端合约编译与本机测\n                    └─────────────┬───────────────┘\n                                  │ artifacts (e.g. .aleo)\n                                  ▼\n                    ┌─────────────────────────────┐\n  dApp UI (later)   │  Ecosystem chain client SDK │  前端 / 钱包 / RPC\n                    └─────────────────────────────┘\n```\n\nHello 后端剧本：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)。\n\n## 4. 查询\n\n```bash\n# MCP tool pf_chain_catalog  { \"target\": \"aleo\" } 或 { \"includeDesignOnly\": true }\n# SDK:\npython3 -I tools/sdk/proof_forge_sdk.py chain-catalog --target aleo\n```\n\n过滤：`target` 单 id；省略则返回全表 implemented（或 `includeDesignOnly`）。\n\n## 5. 更新纪律\n\n- 与 `TargetRegistryV1` **implemented 集合** 对齐；design-only 仅 catalog 展示\n- 不把 resolver support 写成完整平台语义\n- 不因 catalog 存在而改 `deployable`\n- 生态 SDK 名称可演进；变更只改 JSON + 本页日期\n\n## 6. 非目标\n\n- 不安装前端 npm 包\n- 不因 catalog 存在而默认 public broadcast（policy 在 `networks.v1.json`）\n- 不 formal / Stage-0\n\n## 6b. EVM networks + OnchainOS\n\n- 网络 id / RPC / policy：[`networks.v1.json`](networks.v1.json)\n- 集成与 P0–P2：[`13-xlayer-onchainos.md`](13-xlayer-onchainos.md)\n- `evm` target 行含 `networks[]`、`ecosystem.okxOnchainOs`、`networksRef`\n\n## 7. Aleo frontend deep-dive\n\nAleo dApp 前端（Wallet Adapter · Provable SDK · 与 `pf` 产物对接）见：\n\n[`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md)\n\nCatalog JSON 的 `aleo.frontendClients` 列出具体 `@provablehq/aleo-wallet-adaptor-*` 与 `@provablehq/sdk` 包名；**仍不**由 PF 安装或 pin。\n\n最小可运行 UI 模板：[`templates/aleo-dapp-ui/`](../../templates/aleo-dapp-ui/)。\n\n## 8. EVM frontend deep-dive\n\nEVM dApp 前端（viem / MetaMask / 本地 Anvil + X Layer 预设）见：\n\n[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md) · 模板 [`templates/evm-dapp-ui/`](../../templates/evm-dapp-ui/) · [`13-xlayer-onchainos.md`](13-xlayer-onchainos.md)\n\n## Solana (ProofForge path)\n\nContracts: ProgramV1 + `pf build --target solana`. Frontend: `templates/solana-dapp-ui`. MCP: `pf_solana_scaffold` / `pf_solana_ix_codec` / `pf_solana_artifacts` (in-product summary — not external Anchor MCP).\nSee `docs/product/09-solana-agent-playbook.md` and `10-solana-dapp-frontend.md`.\n",
  "05-distribution-and-packages.md": "---\nid: PRODUCT-DISTRIBUTION-AND-PACKAGES\ntitle: Distribution architecture — CLI release vs Lean author SDK vs host wrappers\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-09\nnormative: false\n---\n\n# 分发架构：CLI 发版 · Lean 写合约包 · 宿主 SDK/MCP\n\n状态：`draft`（2026-08-09）\n关联：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)、[`02-external-program-v1.md`](02-external-program-v1.md)、[`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)\n\n## 1. 结论（先回答「要不要做」）\n\n| 问题 | 答案 |\n|---|---|\n| 现在有没有 **产品 release 打包**？ | **没有**。只有 monorepo 内 `lake build` → `.lake/build/bin/proof-forge-next`（约数百 MB 动态链接调试二进制），无 GitHub Release 资产、无 tarball 安装、无 pip/Reservoir 发布 |\n| Python MCP/SDK 是不是「用 Python 重写了编译器」？ | **不是**。它们只 **spawn** 产品 CLI 并解析 JSON；权威永远是 Lean 二进制 + Tool Lock |\n| 要不要先做 **CLI engineering 发版/打包**？ | **要**。外部作者/Agent 不能依赖「克隆整仓 + lake 编译 263MB」当 sole 安装路径 |\n| 要不要发 **Lean 写合约 SDK 包**？ | **要（分轨）**：与 CLI 不同轨——写源码/IDE 语法 vs 编译/物化 |\n| 这是不是 formal Stage-0 / `just release-check`？ | **不是**。工程分发 ≠ formal/hermetic/release 资格；后者仍放最后 |\n\n推荐顺序：\n\n```text\n① Engineering CLI dist（版本化二进制 + digest + 安装说明）\n② Lean authoring package（最小可 require 的写合约表面）\n③ Host SDK 可选发布（pip 等；仍只包 CLI）\n④ formal Stage-0 / hermetic release evidence（最后）\n```\n\n## 2. 三层产品面（禁止混谈）\n\n```text\n┌─────────────────────────────────────────────────────────────┐\n│  A. 产品编译器 CLI  proof-forge-next                         │\n│     Lean 实现 · 读源文本 · 编译/物化/inspect/doctor/local     │\n│     权威：sole product path                                  │\n└───────────────────────────┬─────────────────────────────────┘\n                            │ spawn + JSON\n┌───────────────────────────▼─────────────────────────────────┐\n│  C. 宿主封装  Python SDK / MCP server                         │\n│     不是第二编译器 · 不 PATH 发明工具 · 无默认 network broadcast │\n└─────────────────────────────────────────────────────────────┘\n\n┌─────────────────────────────────────────────────────────────┐\n│  B. Lean 写合约表面  import ProofForgeV2 + program … where    │\n│     语法/导出/可选 IDE 支持 · 用户 Lake 工程可 require           │\n│     与 A 解耦：产品 build 读文本，不必 lake build 用户合约包     │\n└─────────────────────────────────────────────────────────────┘\n```\n\n| 层 | 现在是什么 | 用户怎么拿到 | 发版形态（目标） |\n|---|---|---|---|\n| **A CLI** | `lean_exe proof_forge_next`，包版本 monorepo `0.1.0` | 克隆仓库 `lake build` 或 `package-cli` tarball | 版本化 **binary dist**（平台 tarball + SHA-256）+ 固定 `lean-toolchain` 说明；Linux CI engineering Release 已接线 |\n| **B Lean author SDK** | monorepo 内整库 `lean_lib ProofForgeV2`（含编译器/targets）；另有薄 Author SDK 投影 | path/git 依赖 `proof-forge-author-*` 或整仓 | **最小可发布 lean 包**（Syntax + ProgramElaborationV1 import closure），tarball/GitHub asset；Reservoir/published package 仍 pending |\n| **C Host SDK/MCP** | `tools/sdk` / `tools/mcp` stdlib Python | `PYTHONPATH` / 绝对路径 | 可选 **pip wheel**（薄封装）；永不内嵌 target compilers |\n\n## 3. 现状诚实清单\n\n| 项 | 事实 |\n|---|---|\n| Lake package name | `proof-forge-next` |\n| Lake `version` | `0.1.0`（工程占位，**非**已发布 release） |\n| GitHub Actions | `ci.yml` + `.github/workflows/release-engineering-dist.yml`；tag `v*` / `workflow_dispatch` 会打 CLI + Author SDK engineering assets 并可创建 prerelease/draft GitHub Release |\n| `just release-check` | **未注册**；禁止声称 |\n| Formal Stage-0 | 独立命令；非日常完成条件 |\n| 产品 build 对外部工程 | 文本路径 + `import ProofForgeV2` **gate 字符串**；**不**要求用户 `lake build` 合约 |\n| Python SDK | 文档已写：**未** pip 发布；Host SDK 发布仍等 CLI dist 稳定后 |\n| CLI 二进制特征 | `package-cli` 默认保留动态链接/debug 信息；`--strip` 仅为可选 size profile。当前工程 tarball 可作为 **engineering-dist**，不得称 formal release asset |\n| Author SDK 包 | `package-author-sdk` 从 `ProgramElaborationV1` import closure 生成薄 `ProofForgeV2` root；不包含 CLI/materializers/targets |\n\n## 4. 为什么 Python「看起来像重新包装」\n\n因为 **C 层故意很薄**：\n\n- 实现语言选 Python stdlib → Agent/脚本易接，无第二语言工具链进 Tool Lock\n- 契约：`proof-forge-next … --json` 是 sole 产品机读面\n- 禁止在 SDK/MCP 内嵌 solc/nargo 或第二 Tool Root 写入器\n\n因此：\n\n- **发版优先级在 A（CLI）**，不在把 Python 做厚\n- C 可以晚于 A 做 pip；没有 A 的稳定安装路径，C 无法独立存在\n\n## 5. 两轨 SDK 名称（避免歧义）\n\n| 名称（建议） | 层 | 语言 | 职责 |\n|---|---|---|---|\n| **ProofForge Author SDK** | B | Lean | 写 `program`、语法、（可选）export/elab；用户 `lakefile` `require` |\n| **ProofForge Host SDK** | C | Python（未来可 TS） | 调 CLI：doctor/install/build/local/catalog |\n| **ProofForge CLI** | A | Lean→native exe | 编译器与物化产品 |\n\n「用 Lean 写的 SDK 用来写合约」= **Author SDK（B）**，不是 Host SDK（C）。\n\n## 6. Engineering 发版切片（建议实现序）\n\n### 6.1 REL-CLI-0 — 版本与身份\n\n- 单一 `PRODUCT_VERSION`（SemVer）与 CLI `--version` / doctor JSON 对齐\n- 绑定 `lean-toolchain` + git describe/commit（dirty 标记）\n- **非** formal BuildIdentity 完成声明\n\n### 6.2 REL-CLI-1 — binary dist 菜谱\n\n- `just package-cli` / `scripts/package_cli_dist.sh`\n- 输入：已 `lake build proof_forge_next`\n- 输出：`dist/proof-forge-next-<ver>-<platform>.tar.gz` + `.sha256`\n- 内容：`bin/proof-forge-next`（考虑 strip 为可选 profile）、`README`、`VERSION`、`lean-toolchain` 副本\n- **不做**：捆绑整个 monorepo、不捆绑 Tool Lock 工具（target 工具仍走 `install`/Tool Lock）\n\n### 6.3 REL-CLI-2 — 安装面\n\n- 文档：下载 tarball → 校验 digest → 放到 `PATH` 或 `PROOF_FORGE_CLI`\n- 与现有 `proof-forge-next install --targets …` 接：CLI 就位后再装链工具\n- GitHub Release engineering 上传已接线：`.github/workflows/release-engineering-dist.yml` 在 tag `v*` 或手动触发时上传 CLI + Author SDK assets（prerelease；非 tag 手动触发默认为 draft）— **仍非** Stage-0 formal\n\n### 6.4 REL-AUTHOR-0 — Lean Author SDK 最小包\n\n目标：用户工程：\n\n```lean\n-- lakefile.lean\nrequire proof_forge_author from git \"…\" @ \"v0.x.y\"\n-- 或 path 依赖发布树\n```\n\n```lean\nimport ProofForgeV2  -- 或未来更窄 namespace ProofForge.Author\nprogram Hello where …\n```\n\n约束：\n\n- **不得**把整个 materializer/tests 塞进 author 包（体积与依赖爆炸）\n- 首切片已落：`ProgramElaborationV1` import closure + 薄 `ProofForgeV2` root（拉入 Syntax 与 `program … where` elab surface），并由 `package-author-sdk-smoke` 在临时 Lake consumer 中验证\n- 产品 CLI 仍可纯文本编译；Author SDK 服务 **IDE/编辑体验** 与 lake 工程规范\n- monorepo 可保留 umbrella；author 包是 **可发布投影**，不是第二语义权威\n\n### 6.5 REL-HOST-0 — Host SDK 可选发布\n\n- `pip install` 仅当 CLI dist 稳定后\n- wheel 内 **无** 编译器二进制强制捆绑（或明确 extra 可选）\n- MCP 继续 stdlib 单文件 + 环境变量指 CLI\n\n### 6.6 明确不在本阶梯\n\n- formal Stage-0 / hermetic / `governance-check`\n- 把 Python 升格为编译器\n- 默认 MCP network broadcast\n- 因发版改 `deployable=true`\n\n## 7. 与「外部工程模板」关系\n\n| 路径 | 需要 A CLI dist？ | 需要 B Author SDK？ |\n|---|---|---|\n| 纯文本 + CLI build/sandbox（当前模板） | **是（体验）** | 否（gate 字符串即可） |\n| 用户 Lake 工程 IDE 语法高亮/elab | 是 | **是** |\n| Agent 经 MCP | 是（CLI 可发现） | 否 |\n\n当前模板「不 require Lake」是 **诚实 MVP**；发版后应变成：\n\n1. 安装 CLI dist\n2. （可选）require Author SDK\n3. Host SDK/MCP 指到同一 CLI\n\n## 8. 风险\n\n| 风险 | 缓解 |\n|---|---|\n| CLI 二进制过大 / 动态链接难移植 | strip profile；记录链接依赖；平台矩阵 linux-x86_64 / darwin-arm64 先 |\n| Author 包 import 拖进半个编译器 | 闭包测量 + 只导出 Language/Syntax 层 |\n| 把 engineering tag 说成 formal release | 文档与 CI 命名 `engineering-dist` vs `stage0` |\n| 双版本漂移（CLI vs Author） | 同一 PRODUCT_VERSION 族；doctor 报告双方 |\n\n## 9. 实现状态（engineering）\n\n`implemented=true`（engineering distribution surface）。本标记只覆盖本页 A/B/C 工程分发切片（CLI dist、Author SDK、Host SDK、CI engineering-dist），不代表 formal Stage-0、hermetic release、PyPI/Reservoir 公开发布或 mainnet/network 资格。\n\n本次本机证据（2026-08-09，Linux x86_64）：\n\n- `just package-host-sdk-smoke`：exit 0；生成 `proof_forge_sdk-0.1.0-py3-none-any.whl` 与 `proof_forge_sdk-0.1.0.tar.gz`；import/self_check 通过；输出 `package-host-sdk-smoke: HOST-SDK-SMOKE-OK`。\n- `just package-cli-smoke`：exit 0；version JSON 为 `schema=proof-forge.cli.version.v1`、`version=0.1.0`、`channel=engineering-dist`；临时打包 `proof-forge-next-0.1.0-linux-x86_64.tar.gz`（68,037,691 bytes，SHA-256 `9916b713962dd05c8ac3e62b1c0556b0a395dcfc6cc9fc22447fe92ef4f034bf`）；校验通过；输出 `package-cli-dist-smoke: PACK-SMOKE-OK`。\n- `just docs-check`：本页更新后运行，要求 exit 0 才可声明本段为当前证据。\n\n| 切片 | 状态 | 入口 |\n|---|---|---|\n| **REL-CLI-0** 版本身份 | **done** | 根目录 `VERSION`；`ProofForgeV2/CLI/ProductVersionV1.lean`；`proof-forge-next version [--json]` / `--version`；schema `proof-forge.cli.version.v1`；channel=`engineering-dist` |\n| **REL-CLI-1** binary dist | **done** | `scripts/package_cli_dist.sh` + `just package-cli` → `dist/proof-forge-next-<ver>-<platform>.tar.gz` + `.sha256`；`just package-cli-smoke` |\n| **REL-CLI-2** 安装文档 | **done（本页 §9.1）** | monorepo `lake build` 仍为开发者路径；dist 为外部作者推荐路径 |\n| **REL-AUTHOR-0** Lean Author SDK | **done engineering** | `scripts/package_author_sdk.py` + `just package-author-sdk`：Syntax 闭包薄 `ProofForgeV2` 根 + tarball；`just package-author-sdk-smoke` |\n| **REL-CI-0** CI 发工程版 | **done engineering** | `.github/workflows/release-engineering-dist.yml`：tag `v*` / workflow_dispatch → build CLI + author tarball → GitHub Release（prerelease，`engineering-dist`） |\n| **REL-HOST-0** pip 打包 | **done engineering** | `tools/sdk/pyproject.toml` + `just package-host-sdk` → wheel/sdist；`package-host-sdk-smoke`；CI 随 engineering Release 上传 |\n| **REL-HOST-1** PyPI 发布 | **done engineering（repo wiring）；owner PyPI setup required** | tag `v${VERSION}` → job `publish-pypi` / display name `publish-host-sdk-pypi`（OIDC Trusted Publishing，environment `pypi`）；本地 `just publish-host-sdk-pypi`；Trusted Publisher 字段表见 [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md) |\n| **REL-CI-1** multi-arch | **done engineering** | `release-engineering-dist.yml`：linux-x86_64 + **darwin-arm64** CLI 矩阵 + portable Author/Host 包 → GitHub Release + PyPI；tag 须匹配 `VERSION` |\n| formal Stage-0 | **out of scope** | 整仓最后 |\n\n### 9.1 安装 CLI dist（推荐外部作者）\n\n```bash\n# 在已 build 的 monorepo 上打工程包（或从未来 GitHub Release 下载同名资产）\njust package-cli\n# → dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz\n# → dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz.sha256\n\nsha256sum -c dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz.sha256\ntar -xzf dist/proof-forge-next-0.1.0-linux-x86_64.tar.gz -C /opt\nexport PROOF_FORGE_CLI=/opt/proof-forge-next-0.1.0-linux-x86_64/bin/proof-forge-next\n\"$PROOF_FORGE_CLI\" version --json\n# expect: version=0.1.0, channel=engineering-dist\n```\n\n说明：\n\n- 包内 **无** Tool Lock 工具；链工具仍走 `install`（且 doctor/install/local 仍需 package `scripts/` CWD — 后续可把引擎装进 dist）\n- `build` / `check` / `version` / `list-targets` 仅需二进制即可\n- **禁止**把本 tarball 说成 formal / Stage-0 / hermetic 证据\n\n### 9.2 CI 发版（工程 channel）\n\n| 触发 | 行为 |\n|---|---|\n| push tag `v*`（如 `v0.1.0`） | Linux 构建 CLI + Author SDK → **GitHub Release**（`prerelease: true`）上传 tarball+sha256 |\n| `workflow_dispatch` | 同样打包；非 tag 时默认 **draft** release，避免误发 |\n\n工作流：`.github/workflows/release-engineering-dist.yml`\n命名必须带 **engineering-dist**；**禁止**写成 formal Stage-0 / `release-check`。\n\n本机等价：\n\n```bash\njust package-cli\njust package-author-sdk\n# 产物在 dist/\n```\n\n### 9.3 Author SDK 用法（Lake）\n\n```bash\njust package-author-sdk\ntar -xzf dist/proof-forge-author-0.1.0.tar.gz\n# 在用户工程 lakefile:\n#   require «proof-forge-author» from \"/path/to/proof-forge-author-0.1.0\"\n```\n\n用户源仍写 `import ProofForgeV2`（与产品 CLI 源文本 gate 兼容）。\n**编译**仍用 CLI dist 的 `proof-forge-next`，不是 `lake build` 用户合约出链上制品。\n\n### 9.4 CWD-free doctor/install/local/network（REL-CWD-0）— **done engineering**\n\nPackage root 解析（`PackageRootV1`）：\n\n1. `PROOF_FORGE_ROOT`（必须是绝对路径；含 `scripts/proof_forge_doctor.py`）\n2. `IO.appDir` 的父目录（当该父目录含 `scripts/proof_forge_doctor.py`；典型为 `<root>/bin/proof-forge-next`）\n3. 进程 CWD（monorepo 开发路径）\n\n`just package-cli` 打包 `scripts/` 引擎 + Tool Lock pin JSON。  \n聚焦门：`just package-cli-cwd-free-smoke`（foreign CWD 上 `doctor`）。\n\n### 9.5 CI 多架构 + Host SDK（REL-CI-1 / REL-HOST-0）\n\n| 平台 | CLI 资产 | runner |\n|---|---|---|\n| linux-x86_64 | `proof-forge-next-<ver>-linux-x86_64.tar.gz` | `ubuntu-latest` |\n| darwin-arm64 | `proof-forge-next-<ver>-darwin-arm64.tar.gz` | `macos-14` |\n\n可移植包（单次构建）：Author SDK tarball、Host SDK wheel/sdist。\n\n**发版门：**\n\n```bash\n# VERSION 文件 = 0.1.0 时：\ngit tag v0.1.0\ngit push origin v0.1.0\n# → Release engineering-dist workflow\n#    tag 必须是 v${VERSION} 或 v${VERSION}-* 前缀\n```\n\n`workflow_dispatch` 默认 **draft** Release（非 tag）。  \n所有 Release 标记 **prerelease** + `engineering-dist` 文案。\n\n本机：\n\n```bash\njust package-cli              # 当前主机平台\njust package-author-sdk\njust package-host-sdk\njust package-host-sdk-smoke\n```\n\n### 9.6 剩余\n\n1. Reservoir/git published Author SDK channel（当前只有 tarball/Release asset + path require）\n2. PyPI / TestPyPI 项目侧 Trusted Publisher 一次性人工配置（代码已接线；未配置则 `publish-pypi` job 失败；字段表见 [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)）\n3. formal Stage-0\n\n## 10. 一句话\n\n**要做发版打包，而且优先 CLI engineering dist；Python 只是宿主壳；Lean 写合约是另一轨 Author SDK。**\nformal 发布资格仍放整仓最后，不能挡 engineering 分发。\n",
  "06-pypi-host-sdk.md": "---\nid: PRODUCT-PYPI-HOST-SDK\ntitle: Host SDK PyPI publish (engineering-dist)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-09\nnormative: false\n---\n\n# Host SDK → PyPI（engineering-dist）\n\n状态：`draft`（2026-08-09）  \n包名：`proof-forge-sdk`  \n权威：[`05-distribution-and-packages.md`](05-distribution-and-packages.md) REL-HOST-1  \n源：`tools/sdk/` · 版本：根目录 `VERSION`（与 CLI engineering-dist 同号）\n\n## 1. 结论\n\n| 项 | 值 |\n|---|---|\n| 是否第二编译器 | **否**（Host SDK 只 spawn `proof-forge-next` 并解析 JSON / manifest） |\n| Channel | `engineering-dist` |\n| Formal Stage-0 / hermetic / release qualification | **否** |\n| wheel 是否捆绑 CLI / Tool Lock 工具 | **否**；用户必须显式提供 `PROOF_FORGE_CLI`（多数 API） |\n| 自动发布触发 | push tag `v${VERSION}`，与 CLI/Author SDK engineering-dist 同一 workflow |\n| 推荐鉴权 | **PyPI Trusted Publishing (OIDC)**；无长期 PyPI token 进仓库 |\n| 仓库接线状态 | **done engineering**：workflow job、wheel/sdist staging、twine check 与 OIDC publish 已接线 |\n| 外部 PyPI 配置状态 | **owner action required**：首次发布前在 PyPI/TestPyPI 配置 Trusted Publisher |\n\n## 2. 用户安装\n\n```bash\npip install proof-forge-sdk==0.1.1\nexport PROOF_FORGE_CLI=/path/to/proof-forge-next   # 必填（多数 API）\n# 可选：与 CLI dist 同级，用于 doctor/install/local engines\n# export PROOF_FORGE_ROOT=/path/to/proof-forge-next-0.1.0-linux-x86_64\npython -c \"from proof_forge_sdk import ProofForgeClient; print(ProofForgeClient().list_targets().ok)\"\n```\n\n## 3. CI 行为\n\nWorkflow：`.github/workflows/release-engineering-dist.yml` job **`publish-pypi`**（display name `publish-host-sdk-pypi`）。\n\n1. `package-portable` 构建 Author SDK tarball + Host SDK wheel/sdist。\n2. `publish-pypi` 只在 **tag push** `v${VERSION}` 运行；`workflow_dispatch` 不发 PyPI。\n3. 发布前只 stage `proof_forge_sdk-${VERSION}-*.whl` 与 Host SDK sdist，并显式拒绝 CLI / Author tarball。\n4. `twine check pypi-dist/*` 先验 metadata。\n5. `pypa/gh-action-pypi-publish` 使用 GitHub OIDC（environment `pypi`，`id-token: write`）。\n6. `skip-existing: true`；PyPI 已发布版本不可覆盖。\n\n## 4. Trusted Publisher 一次性配置表\n\n### 4.1 PyPI project publisher\n\n在 PyPI 项目页 **Settings → Publishing** 配置；项目尚不存在时使用 PyPI 的 pending publisher 流程。下列字段必须逐字匹配 GitHub workflow，否则 OIDC 发布会 fail closed。\n\n| Trusted Publisher 字段 | 值 | 说明 |\n|---|---|---|\n| PyPI Project name | `proof-forge-sdk` | Python package name；不是 CLI asset 名称 |\n| Owner | `DaviRain-Su` | GitHub owner / user |\n| Repository | `proof_forge` | GitHub repository name |\n| Workflow name | `release-engineering-dist.yml` | 文件名，不含 `.github/workflows/` 前缀 |\n| Environment name | `pypi` | 必须与 workflow `environment.name` 相同 |\n\n### 4.2 GitHub environment\n\n| GitHub 设置 | 值 | 说明 |\n|---|---|---|\n| Environment | `pypi` | Repository Settings → Environments |\n| Deployment branches/tags | `refs/tags/v*`（推荐） | 与 job 的 tag-only guard 对齐 |\n| Required reviewers | maintainer 选择 | 可选；会让 PyPI publish 等待人工批准 |\n| Secrets | none required | Trusted Publishing 不需要 `PYPI_API_TOKEN` |\n\n### 4.3 TestPyPI dry run（可选）\n\nTestPyPI 与 PyPI 是独立 issuer 配置；若要先试跑，需要在 TestPyPI 项目配置同名 Trusted Publisher，或本地用 TestPyPI token。\n\n| TestPyPI 字段 | 值 |\n|---|---|\n| Project name | `proof-forge-sdk` |\n| Owner | `DaviRain-Su` |\n| Repository | `proof_forge` |\n| Workflow name | `release-engineering-dist.yml` |\n| Environment name | `pypi`（或另开 `testpypi` 后同步 workflow） |\n\n## 5. Tag 发布 runbook\n\n```bash\n# VERSION 文件 = 0.1.0 时，tag 必须 exact match：\ngit tag v0.1.0\ngit push origin v0.1.0\n# → package CLI multi-arch + Author SDK + Host SDK\n# → GitHub prerelease engineering-dist\n# → PyPI Host SDK publish via Trusted Publishing\n```\n\n失败排查：\n\n| 现象 | 优先检查 |\n|---|---|\n| workflow tag gate 失败 | tag 是否 exact `v$(cat VERSION)` |\n| PyPI OIDC unauthorized | PyPI Trusted Publisher 的 Owner/Repository/Workflow/Environment 是否逐字匹配 |\n| package already exists | PyPI 版本不可变； bump `VERSION` 后重发 |\n| non-Host artifact staged | `publish-pypi` staging step 会拒绝 CLI / Author tarball，保持 Host SDK-only |\n\n## 6. 本机命令\n\n```bash\njust package-host-sdk\njust publish-host-sdk-pypi --dry-run          # twine check only\n# 真实上传（本地 token；仅紧急路径，不推荐长期使用）：\n# export TWINE_USERNAME=__token__\n# export TWINE_PASSWORD=pypi-...\n# just publish-host-sdk-pypi\n# TestPyPI：\n# just publish-host-sdk-pypi --repository testpypi\n```\n\n## 7. 重发 / 新版本\n\n1. 改根目录 `VERSION`、Lean `ProductVersionV1.productVersionV1` 与 `tools/sdk/pyproject.toml` 默认 version。\n2. 本地跑 `just package-host-sdk-smoke` 与 `just docs-check`。\n3. 推送 exact tag `vX.Y.Z`。\n4. CI 自动 GitHub Release + PyPI。\n\n已发布版本号 **不可覆盖**；`skip-existing` 只跳过同版本已存在文件，不代表内容可替换。\n\n## 8. 非目标\n\n- 不把 monorepo `build/` 目录打进 wheel。\n- 不捆绑 `proof-forge-next` 二进制或 Tool Lock 工具。\n- 不用 PyPI token 替代 repository OIDC 作为默认 CI 路径。\n- 不声明 formal / hermetic / Stage-0 / mainnet / proof 完成。\n",
  "07-aleo-dapp-frontend-wallet.md": "---\nid: PRODUCT-ALEO-DAPP-FRONTEND-WALLET\ntitle: Aleo dApp frontend — Wallet Adapter + Provable SDK (FCCP companion)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Aleo dApp 前端：Wallet Adapter · Provable SDK · 与 ProofForge 的分工\n\n状态：`draft`（2026-08-10）  \n前置：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) · [`04-chain-client-catalog.md`](04-chain-client-catalog.md) · [`02-external-program-v1.md`](02-external-program-v1.md)  \n参考（生态，**非** PF 发货）：\n\n| 源 | 用途 |\n|---|---|\n| [Aleo Wallet Adapter (docs.aleo.org)](https://docs.aleo.org/build/wallets/wallet-adapter/getting-started) | 官方 Wallet Adapter 入门 |\n| [ProvableHQ/aleo-dev-toolkit](https://github.com/ProvableHQ/aleo-dev-toolkit) | Wallet adaptor monorepo + React 示例 |\n| [ProvableHQ/sdk](https://github.com/ProvableHQ/sdk) / [`@provablehq/sdk`](https://www.npmjs.com/package/@provablehq/sdk) | 链上对象、prove/deploy/execute、RPC |\n| [create-leo-app](https://github.com/ProvableHQ/sdk/tree/mainnet/create-leo-app) | 框架脚手架示例 |\n| [aleodocs.vercel.app](https://aleodocs.vercel.app)（Aleo-101 / OpenBuild） | 中文学习路径：账户、Program、Transaction、Credits |\n| [Leo Wallet docs](https://docs.leo.app/) | 历史 demox-labs adapter 文档（见 §8 版本说明） |\n\n## 1. 问题：FCCP 缺了什么\n\n现有 FCCP（Front/Chain Client Product）把 Aleo **后端**钉死了：\n\n```text\nProgramV1 (Lean) → pf build → .aleo Instructions + query descriptor\n```\n\n但 **完整 dApp** 还需要前端：\n\n```text\nBrowser UI\n  ├─ Wallet connect / address / network\n  ├─ Sign / decrypt / request records\n  ├─ requestTransaction / executeDeployment (keys stay in wallet)\n  └─ optional: @provablehq/sdk for offline prove, program parse, RPC query\n         ▲\n         │ program id + function ABI from PF artifact\n         │\nProofForge backend (this monorepo)\n```\n\n此前 `chain-client-catalog` 只写了一行模糊的 “Aleo SDK / Provable SDK”，**没有**：\n\n- 具体 npm 包名与职责分层  \n- Wallet Adapter 安装/Provider/`useWallet` 面  \n- 与 `pf build` 产物如何对接  \n- 密钥边界（浏览器 vs `pf deploy --broadcast`）  \n- Agent 可执行的前端剧本  \n\n本文补齐 **metadata + 剧本 + 最小代码样例**。ProofForge **不** vendor/pin 这些 npm 包，**不**在 MCP 默认面持有私钥或广播。\n\n## 2. 后端 vs 前端权威边界\n\n| 层 | 谁负责 | 典型命令 / 包 | 密钥 |\n|---|---|---|---|\n| **Backend contracts** | ProofForge `pf` / `proof-forge-next` | `pf new` · `pf build` · `pf run` · `pf deploy`（CLI） | CLI 侧 env key **仅**开发者本机；MCP **禁止** |\n| **Frontend wallet UX** | 生态 Wallet Adapter | `@provablehq/aleo-wallet-adaptor-*` | **钱包扩展**保管；dApp 不持 private key |\n| **Frontend chain logic** | 生态 Provable SDK | `@provablehq/sdk` · `@provablehq/wasm` | 可选本地 prove；生产优先 wallet 内 prove |\n| **Indexer / explorer** | 公共 API | `https://api.explorer.provable.com/v1` | 无 |\n\n**诚实句（必须保留）：**\n\n- PF 产品 OutputSet 对 Aleo 仍可是 `deployable=false` 的 direct Instructions 面；CLI `pf` 的 deploy/execute 是 **工程 lane**，不是 formal/mainnet。  \n- 前端 wallet 广播 **不等于** PF 已提供产品级 network 工具。  \n- 不要把浏览器里的 `executeTransaction` 写进 MCP 默认工具。\n\n## 3. 推荐包分层（2026-08 生态）\n\n### 3.1 Wallet Adapter（React dApp 首选）\n\n来自 **ProvableHQ/aleo-dev-toolkit**（当前 npm 作用域 `@provablehq/*`）：\n\n| 包 | 角色 |\n|---|---|\n| `@provablehq/aleo-wallet-adaptor-react` | `AleoWalletProvider` · `useWallet` |\n| `@provablehq/aleo-wallet-adaptor-react-ui` | `WalletModalProvider` · `WalletMultiButton` · CSS |\n| `@provablehq/aleo-wallet-adaptor-core` | 错误类型 · `DecryptPermission` · base types |\n| `@provablehq/aleo-wallet-standard` | Wallet Standard 接口 |\n| `@provablehq/aleo-types` | `Network` 等公共类型 |\n| `@provablehq/aleo-wallet-adaptor-leo` | **Leo Wallet** |\n| `@provablehq/aleo-wallet-adaptor-puzzle` | Puzzle |\n| `@provablehq/aleo-wallet-adaptor-shield` | Shield（含 privacy props） |\n| `@provablehq/aleo-wallet-adaptor-fox` | Fox |\n| `@provablehq/aleo-wallet-adaptor-soter` | Soter |\n| `@provablehq/aleo-hooks` | 链数据 hooks（可选） |\n\n安装（核心 + 常用钱包）：\n\n```bash\nnpm install --save \\\n  @provablehq/aleo-wallet-adaptor-react \\\n  @provablehq/aleo-wallet-adaptor-react-ui \\\n  @provablehq/aleo-wallet-adaptor-core \\\n  @provablehq/aleo-wallet-standard \\\n  @provablehq/aleo-types \\\n  @provablehq/aleo-wallet-adaptor-leo \\\n  @provablehq/aleo-wallet-adaptor-puzzle \\\n  @provablehq/aleo-wallet-adaptor-shield \\\n  react react-dom\n```\n\n### 3.2 Provable SDK（程序对象 / prove / RPC）\n\n| 包 | 角色 |\n|---|---|\n| `@provablehq/sdk` | Account、Program、Transaction、deploy/execute、RPC client |\n| `@provablehq/wasm` | Wasm 绑定（sdk 依赖；浏览器 prove 重量级） |\n| `create-leo-app` | 官方 web 示例脚手架 |\n\n### 3.3 历史包名（兼容说明）\n\n旧文档/教程可能写 `@demox-labs/aleo-wallet-adapter-*`（Leo Wallet 早期 adapter）。  \n**新 dApp 优先 `@provablehq/aleo-wallet-adaptor-*`**。若维护旧代码，对照 [docs.leo.app](https://docs.leo.app/) 迁移，不要在同一应用混用两套 Provider。\n\n## 4. 端到端 dApp 拓扑\n\n```text\n┌──────────────────────────── ProofForge monorepo ────────────────────────────┐\n│  src/*.lean (ProgramV1)                                                     │\n│       │ pf build --target aleo                                              │\n│       ▼                                                                     │\n│  build/aleo/*.aleo  +  *-query-contract.json  +  manifest.json              │\n│       │                                                                     │\n│  optional eng: pf deploy/execute --network testnet [--broadcast]            │\n└───────────────────────────────┬─────────────────────────────────────────────┘\n                                │ copy program id / .aleo text / query ABI\n                                ▼\n┌──────────────────────────── Frontend app (Vite/Next) ───────────────────────┐\n│  AleoWalletProvider + WalletModalProvider                                   │\n│       │ connect (Leo / Puzzle / Shield / …)                                 │\n│       │ executeTransaction(programId, function, inputs, fee)                │\n│       │ requestRecords / decrypt (private state)                            │\n│       ▼                                                                     │\n│  Explorer RPC  https://api.explorer.provable.com/v1/{network}/…             │\n└─────────────────────────────────────────────────────────────────────────────┘\n```\n\n**PF 产物如何喂给前端：**\n\n| Artifact | 前端用法 |\n|---|---|\n| `*.aleo` | 部署源；或已上链后只保留 **program id**（如 `helloworld.aleo` / `pfdemo….aleo`） |\n| `*-query-contract.json` | 映射/view 查询形状（public state） |\n| `manifest.json` | 校验 output schema / 文件清单；**不要**当 runtime ABI 权威 |\n\nStateCell 形程序的链上调用与 CLI 一致：`initialize` / `increment`（public `u64` 输入）；public mapping 可用 explorer API 读。\n\n## 5. 最小 React 接线（Wallet）\n\n### 5.1 Provider 根\n\n```tsx\nimport React, { useMemo, type FC, type ReactNode } from \"react\";\nimport { AleoWalletProvider } from \"@provablehq/aleo-wallet-adaptor-react\";\nimport {\n  WalletModalProvider,\n  WalletMultiButton,\n} from \"@provablehq/aleo-wallet-adaptor-react-ui\";\nimport { LeoWalletAdapter } from \"@provablehq/aleo-wallet-adaptor-leo\";\nimport { PuzzleWalletAdapter } from \"@provablehq/aleo-wallet-adaptor-puzzle\";\nimport { ShieldWalletAdapter } from \"@provablehq/aleo-wallet-adaptor-shield\";\nimport { Network } from \"@provablehq/aleo-types\";\nimport { DecryptPermission } from \"@provablehq/aleo-wallet-adaptor-core\";\nimport \"@provablehq/aleo-wallet-adaptor-react-ui/dist/styles.css\";\n\n/** Programs this dApp intends to call (empty = any). Prefer pinning. */\nconst PROGRAMS = [\"credits.aleo\", \"YOUR_PROGRAM.aleo\"];\n\nexport const AleoAppShell: FC<{ children: ReactNode }> = ({ children }) => {\n  const wallets = useMemo(\n    () => [\n      new LeoWalletAdapter(),\n      new PuzzleWalletAdapter(),\n      new ShieldWalletAdapter(),\n    ],\n    [],\n  );\n\n  return (\n    <AleoWalletProvider\n      wallets={wallets}\n      network={Network.TESTNET}\n      decryptPermission={DecryptPermission.UponRequest}\n      autoConnect={false}\n      programs={PROGRAMS}\n      onError={(e) => console.error(\"[aleo-wallet]\", e)}\n    >\n      <WalletModalProvider>\n        <header style={{ display: \"flex\", gap: 12, alignItems: \"center\" }}>\n          <strong>ProofForge × Aleo</strong>\n          <WalletMultiButton />\n        </header>\n        {children}\n      </WalletModalProvider>\n    </AleoWalletProvider>\n  );\n};\n```\n\n### 5.2 `useWallet` 能力面（agent 应知道的方法名）\n\n| 方法 / 状态 | 用途 |\n|---|---|\n| `connected` · `address` · `network` | 连接状态 |\n| `connect` · `disconnect` · `selectWallet` · `switchNetwork` | 会话 |\n| `signMessage` | 登录/绑定 |\n| `decrypt` · `requestRecords` | 私有 record |\n| `executeTransaction` · `transactionStatus` | **调用已部署 program** |\n| `executeDeployment` | 从浏览器部署 program（fee 高；测试网慎用） |\n| `transitionViewKeys` · `requestTransactionHistory` | 需更高 decrypt 权限 |\n\n### 5.3 调用已部署 program（示意）\n\n> 具体 `Transaction` / input 编码以当前 `@provablehq/aleo-wallet-adaptor-*` 与钱包实现为准；升级包后对照官方 example app：  \n> https://aleo-dev-toolkit-react-app.vercel.app/\n\n```tsx\nimport { useCallback } from \"react\";\nimport { useWallet } from \"@provablehq/aleo-wallet-adaptor-react\";\nimport { WalletNotConnectedError } from \"@provablehq/aleo-wallet-adaptor-core\";\n\nconst PROGRAM_ID = \"YOUR_PROGRAM.aleo\"; // from pf deploy / explorer\n\nexport function IncrementButton() {\n  const { connected, address, executeTransaction, transactionStatus } =\n    useWallet();\n\n  const onIncrement = useCallback(async () => {\n    if (!connected || !address) throw new WalletNotConnectedError();\n    // Wallet builds+proves+broadcasts; dApp never sees private key.\n    const txId = await executeTransaction({\n      program: PROGRAM_ID,\n      functionName: \"increment\",\n      inputs: [\"3u64\"],\n      // fee / priority fields: follow current adapter types\n    } as never);\n    // Poll status (finality is not instant)\n    const status = await transactionStatus(txId);\n    console.log({ txId, status });\n  }, [connected, address, executeTransaction, transactionStatus]);\n\n  return (\n    <button disabled={!connected} onClick={() => void onIncrement()}>\n      increment(+3)\n    </button>\n  );\n}\n```\n\n### 5.4 读 public mapping（无需钱包）\n\n与 CLI demo 相同的 explorer REST：\n\n```bash\n# example from live PF demo\ncurl -sS \\\n  \"https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mapping/pf_state_0/0u8\"\n```\n\n前端：\n\n```ts\nconst ENDPOINT = \"https://api.explorer.provable.com/v1\";\nconst network = \"testnet\"; // or mainnet — product default stays testnet\nasync function readU64(program: string, mapping: string, key: string) {\n  const url = `${ENDPOINT}/${network}/program/${program}/mapping/${mapping}/${key}`;\n  const res = await fetch(url);\n  if (!res.ok) throw new Error(`${res.status} ${url}`);\n  return res.text(); // e.g. \"\\\"8u64\\\"\"\n}\n```\n\n## 6. 与 `pf` 后端的对接清单\n\n| 步 | 后端（PF） | 前端 |\n|---|---|---|\n| 1 | `pf setup --target aleo` · `pf new` · `pf build` | — |\n| 2 | `pf run -- initialize 5u64`（本机 VM） | — |\n| 3 | `pf deploy --network testnet`（save-only）或 `--broadcast` | 记录 **program id** |\n| 4 | （可选）`pf execute … --broadcast` 冒烟 | 或改用 wallet `executeTransaction` |\n| 5 | 把 program id + 函数名写进前端 env | `VITE_ALEO_PROGRAM_ID=….aleo` |\n| 6 | — | Wallet connect → execute → explorer 校验 mapping |\n\n**不要：**\n\n- 把 `APrivateKey1…` 放进前端 bundle / Vercel env 给浏览器  \n- 在 MCP remote 工具里代用户签名  \n- 混用 demox-labs 与 `@provablehq` 两套 adapter  \n\n**可以：**\n\n- 开发者本机用 `PF_ALEO_TESTNET_KEY` + `pf deploy --broadcast` 做 CI/demo  \n- 终端用户只通过扩展钱包交互  \n\n## 7. Agent 剧本（前端切片）\n\n接在 [`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) **后端完成后**：\n\n| 步 | 动作 | 成功判据 |\n|---|---|---|\n| F0 | `pf_chain_catalog` `target=aleo` | `frontendClients` 含 wallet-adaptor + sdk 条目 |\n| F1 | 读本文 §3–§5 | 选 `@provablehq/aleo-wallet-adaptor-*` |\n| F2 | 脚手架 Vite/Next React app | `AleoWalletProvider` 可编译 |\n| F3 | 安装 Leo（或 Puzzle/Shield）扩展 · Testnet | `WalletMultiButton` 显示 address |\n| F4 | 配置 `PROGRAM_ID`（来自 PF deploy 或 explorer） | env 无私钥 |\n| F5 | `executeTransaction` initialize/increment | explorer tx + mapping 更新 |\n| F6 | （可选）`@provablehq/sdk` 做只读 Program 解析 | 不替代 wallet 签名 |\n\nRemote MCP 可增加的 **guidance-only** 提示（已有 `pf_cli_cheatsheet` / `pf_aleo_live_demo`）：指向本文 id `PRODUCT-ALEO-DAPP-FRONTEND-WALLET`。\n\n## 8. 网络与费用\n\n| 网络 | 用途 | PF 默认 |\n|---|---|---|\n| `Network.TESTNET` | dApp 联调 · faucet | **默认** |\n| `Network.CANARY` | 预发 | 可选 |\n| `Network.MAINNET` | 生产 | PF CLI **拒绝** mainnet；前端若接 mainnet 是 **应用自己的产品决策**，与 PF formal 无关 |\n\n- Deploy fee ≈ 数 credits（namespace + synthesis）；短 program 名更贵。  \n- Execute fee 远小于 deploy。  \n- Faucet：https://faucet.aleo.org/（人机验证，不进 CI）。  \n\n## 9. 安全清单\n\n1. **私钥只在钱包或开发者本机 CLI env** — 永不进 git / 前端。  \n2. `decryptPermission` 默认偏紧（`NoDecrypt` / `UponRequest`）；不要一上来 `OnChainHistory`。  \n3. `programs` 白名单限制 dApp 可请求的 program id。  \n4. Shield 的 `readAddress` / `recordAccess` 用于隐私 dApp；默认读官方 privacy guide。  \n5. XSS = 丢会话；CSP + 勿 `eval` 用户 program 文本。  \n6. 依赖锁定用应用自己的 package-lock；PF catalog **不 pin** 版本号（只给名字）。  \n\n## 10. 与 aleodocs.vercel.app 学习路径的映射\n\n[aleodocs.vercel.app](https://aleodocs.vercel.app)（Aleo-101）适合补概念；实现时落到官方包：\n\n| 文档概念 | 前端落点 |\n|---|---|\n| Accounts & Keys | Wallet connect · 不导出 private key |\n| Programs | PF `.aleo` + on-chain program id |\n| Transactions / Transitions | `executeTransaction` · `transactionStatus` |\n| Credits & Transfers | `credits.aleo` + wallet records |\n| Record scanning | `requestRecords` · `decrypt` |\n| Public vs private state | mapping REST vs record decrypt |\n\n## 11. 成熟度 / 非目标\n\n| 项 | 状态 |\n|---|---|\n| 本文 + catalog 字段 | **engineering draft** |\n| 最小 React 模板 | **done**：[`templates/aleo-dapp-ui/`](../../templates/aleo-dapp-ui/)（不 pin 进 Tool Lock） |\n| MCP 代签 / 远程 broadcast | **明确不做** |\n| Formal / mainnet / hermetic | **不声称** |\n\n\n## 11b. 最小模板（可运行）\n\n仓库内脚手架：\n\n```bash\ncd templates/aleo-dapp-ui\ncp .env.example .env\nnpm install\nnpm run dev\n# http://127.0.0.1:5173\n```\n\n默认 `VITE_ALEO_PROGRAM_ID=pfdemo336641.aleo`（live Testnet demo）。  \n功能：WalletMultiButton · initialize/increment · explorer mapping 刷新。  \n细节见模板 [`README.md`](../../templates/aleo-dapp-ui/README.md)。\n\n## 12. 相关\n\n- 后端 Hello：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)  \n- Catalog JSON：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  \n- Testnet CLI demo：[`../demos/aleo-testnet-walkthrough.md`](../demos/aleo-testnet-walkthrough.md)  \n- 远程 MCP：`https://proof-forge-mcp.davirain-yin.workers.dev/mcp` · tool `pf_aleo_live_demo`  \n",
  "08-evm-dapp-frontend.md": "---\nid: PRODUCT-EVM-DAPP-FRONTEND\ntitle: EVM dApp frontend — viem/MetaMask + PF bytecode (FCCP companion)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# EVM dApp 前端：viem · MetaMask · 与 ProofForge 的分工\n\n状态：`draft`（2026-08-10）  \n前置：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) · [`04-chain-client-catalog.md`](04-chain-client-catalog.md) · [`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)  \n模板：[`templates/evm-dapp-ui/`](../../templates/evm-dapp-ui/)  \nWalkthrough：[`../demos/evm-local-walkthrough.md`](../demos/evm-local-walkthrough.md)  \nX Layer / OnchainOS：[`13-xlayer-onchainos.md`](13-xlayer-onchainos.md) · [`networks.v1.json`](networks.v1.json)  \n对称文档（Aleo）：[`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md)\n\n## 1. 问题\n\nFCCP 对 EVM 后端已经很强（Yul/solc/Anvil），但前端只有 catalog 一行 `ethers/viem/wagmi`。  \n完整 dApp 需要：\n\n```text\nBrowser UI (viem + injected wallet)\n  ├─ connect / switch chain\n  ├─ deploy (optional) or attach address\n  ├─ eth_call get()\n  └─ send increment(uint64)\n         ▲\n         │ ABI + bytecode / address from PF\n         │\nProofForge: pf build -t evm → *.abi.json + *.bin\n            pf test -t evm / pf deploy --network local\n```\n\n## 2. 后端 vs 前端边界\n\n| 层 | 谁 | 密钥 |\n|---|---|---|\n| Compile | `pf build -t evm` | 无 |\n| Local test | `pf test -t evm` / Anvil scripts | Anvil 默认 key（本机） |\n| Local deploy | `pf deploy --broadcast --network local` 或 demo script | 本机 / Anvil #0 |\n| dApp UX | `templates/evm-dapp-ui` + MetaMask | **钱包**；禁止主网私钥进前端 |\n| Public chain write | **pf v0 默认拒绝**；catalog 有 X Layer 元数据 | — |\n| X Layer attach UI | `VITE_NETWORK_ID=evm.xlayer.testnet` 等 | 用户钱包 |\n\n## 2b. 网络预设\n\n| id | chainId | 用途 |\n|---|---|---|\n| `evm.local.anvil` | 31337 | 产品默认 demo |\n| `evm.xlayer.testnet` | 1952 | 黑客松 / 联调（OKB） |\n| `evm.xlayer.mainnet` | 196 | mainnet-gated（OKB） |\n\n权威：[`networks.v1.json`](networks.v1.json)。模板：`src/chains.ts`。\n\n## 3. PF 产物（StateCell 形）\n\n`pf build Examples/StateCell.lean --module Examples.StateCell -t evm -o <dir>`：\n\n| 文件 | 用途 |\n|---|---|\n| `StateCell.abi.json` | Solidity JSON ABI（constructor / increment / get） |\n| `StateCell.bin` | creation bytecode（hex，可无 `0x` 前缀） |\n| `StateCell.yul` | 中间表示（前端通常不需要） |\n| `manifest.json` | OutputSet 清单 |\n\n典型 ABI：\n\n```json\nconstructor(uint64 initial)\nfunction increment(uint64 delta) returns (uint64)\nfunction get() view returns (uint64)\n```\n\n## 4. 推荐包\n\n| 包 | 角色 |\n|---|---|\n| `viem` | 类型化 RPC / encode / wallet client（模板默认） |\n| `wagmi` + `viem` | React hooks 全家桶（可选，未打进最小模板） |\n| `ethers` v6 | 生态替代 |\n| MetaMask / Rabby | injected `window.ethereum` |\n\n模板故意 **只依赖 viem**，降低安装面；catalog 仍列出 wagmi/ethers 作为生态选项。\n\n## 5. 最小模板\n\n```bash\n# monorepo — builds, Anvil, deploy, writes deployment.json\nbash scripts/pf_evm_local_demo.sh\n\n# other terminal\ncd templates/evm-dapp-ui && npm install && npm run dev\n```\n\n`public/deployment.json` schema：`proof-forge.pf.evm-local-deployment.v1`  \n字段：`rpcUrl` · `chainId` · `contractAddress` · `abi` · `bytecode?` · `constructorInitial`。\n\n## 6. Agent 剧本（前端）\n\n| 步 | 动作 |\n|---|---|\n| F0 | `pf_chain_catalog` `target=evm` |\n| F1 | `pf build -t evm` 得到 abi/bin |\n| F2 | `bash scripts/pf_evm_local_demo.sh` 或 `pf test -t evm` |\n| F3 | 起 `templates/evm-dapp-ui` · MetaMask 加本地链 |\n| F4 | connect → get → increment |\n| F5 | **不要**把热私钥写进模板默认路径 |\n| F6 | （可选）`VITE_NETWORK_ID=evm.xlayer.testnet` attach 已部署合约；DEX 走官方 OnchainOS MCP |\n\n## 7. 安全\n\n1. Anvil #0 私钥仅本地演示；永不用于 public 链。  \n2. pf v0 **默认拒绝** EVM public broadcast；X Layer 写链是工程/钱包决策。  \n3. 前端不要内嵌部署私钥；用户签名走扩展 / OKX Wallet。  \n4. `deployment.json` 可进 gitignore（含本机地址）；模板默认 ignore。  \n5. 成功 ≠ formal / hermetic / mainnet。  \n6. OnchainOS `OK-ACCESS-KEY` 仅应用本地；不进 PF remote MCP。\n\n## 8. 与路线 B 的边界\n\n本文 + 模板是 **路线 A（产品闭环）**。  \n路线 B（code-size、真实 CALL 地址、corpus 扩面、OZ）见 engineering backlog / `docs/targets/01-evm.md` residuals——**不在本切片声明完成**。  \nX Layer / OnchainOS 元数据与双 MCP 见 [`13-xlayer-onchainos.md`](13-xlayer-onchainos.md)（P0 catalog done；P1+ 另列）。\n\n## 9. 相关\n\n- 模板 README：`templates/evm-dapp-ui/README.md`  \n- Demo 脚本：`scripts/pf_evm_local_demo.sh`  \n- X Layer 工程 stub：`scripts/pf_evm_xlayer_deploy.sh`  \n- 网络 catalog：`docs/product/networks.v1.json`  \n- 既有 Anvil 测：`scripts/pf_evm_test.sh` · `scripts/evm_anvil_differential.sh`  \n- Target dossier：`docs/targets/01-evm.md`  \n \n",
  "09-solana-agent-playbook.md": "---\nid: PRODUCT-SOLANA-AGENT-PLAYBOOK\ntitle: Solana agent playbook — ProofForge CLI/SDK first\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Solana agent playbook（ProofForge 主路径）\n\n**Audience:** coding agents + developers  \n**Claims:** engineering guidance only — **not** formal / hermetic / mainnet\n\n## 一句话\n\n用 **ProofForge 语言 + `pf` CLI（+ host SDK）** 写/编/测/部署 Solana 程序；  \n前端用 **`templates/solana-dapp-ui`** 消费 `*.idl.json`。  \n**不要**把「Solana 官方 Rust/Anchor MCP」当成写 PF 合约的入口。\n\n## 唯一推荐 MCP\n\n| Server | Endpoint | 用途 |\n|---|---|---|\n| **ProofForge remote MCP** | `https://proof-forge-mcp.davirain-yin.workers.dev/mcp` | catalog、CLI ladder、ix 编码摘要、前端模板指引 |\n\n```bash\ncodex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n```\n\nPF MCP 工具（Solana）：\n\n| Tool | 作用 |\n|---|---|\n| `pf_solana_scaffold` | setup → new → build → verify → test → deploy → UI |\n| `pf_solana_ix_codec` | **摘要** PF ix-data（body-only disc **或** CPI handlerId） |\n| `pf_solana_artifacts` | build 产物清单 / 哪些给前端 |\n| `pf_target_info` / `pf_cli_cheatsheet` | target=solana |\n| `pf_get_doc` | `09-…` / `10-…` / demo walkthrough |\n\n> 说明：官方 `https://mcp.solana.com/mcp` 面向 **Rust/Anchor/Pinocchio** 文档与 autofixer。  \n> 与 PF Lean→sBPF 路径不同；本产品 **不在 agent 默认路径里推荐** 双 MCP。  \n> 若维护者手写生态 Rust 适配层，可自行查阅 Solana 文档，但 **合约本体仍走 PF**。\n\n## 本地 `pf` ladder\n\n```bash\nexport PROOF_FORGE_CLI=/path/to/proof-forge-next\nexport PATH=\"$HOME/.cargo/bin:$PATH\"\n\npf setup --target solana\npf doctor --target solana\n\npf new hello --target solana && cd hello\n# 编辑 src/*.lean（ProgramV1）— 不是 Cargo/Anchor 工程\npf build\npf verify\npf test\npf deploy --network local\n# optional loopback only:\n# pf deploy --network local --broadcast --endpoint http://127.0.0.1:8899\n```\n\n### Surfpool end-to-end（StateCell → UI）\n\n```bash\njust pf-solana-local-demo\n# build → verify → Surfpool up → deploy → create state → init/increment/get\n# → templates/solana-dapp-ui/public/deployment.json\ncd templates/solana-dapp-ui && npm install && npm run dev\njust solana-surfpool-down   # when done\n```\n\nMonorepo example:\n\n```bash\npf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol\npf verify --target solana -o build/v2/sc-sol\ncp build/v2/sc-sol/StateCell.idl.json templates/solana-dapp-ui/public/artifacts/\n```\n\n## Instruction encoding（agents must branch）\n\n| Profile | Programs | ix prefix |\n|---|---|---|\n| **body-only S1b** | StateCell, `pf new` | `sha256(\"proof-forge-solana-v1:\"+name+\"(\"+types+\")\")[0:8]` |\n| **CPI-product** | TransferSol, … | `u64le(handlerId)` from IDL |\n\n- `init` → disc name **`initialize`**\n- StateCell state: 16B = marker@0 + count@8\n- init needs **state signer** (script, not browser wallet)\n\nSee MCP `pf_solana_ix_codec` and `templates/solana-dapp-ui/src/ix.ts`.\n\n## 前端\n\n见 [`10-solana-dapp-frontend.md`](10-solana-dapp-frontend.md) · 模板 [`templates/solana-dapp-ui/`](../../templates/solana-dapp-ui/)。\n\n## Install companions\n\n| Binary | Purpose |\n|---|---|\n| `pf` (`proof-forge-pf`) | Developer CLI |\n| `proof-forge-next` | Compiler |\n| `proof-forge-solana-client` | `pf verify -t solana` |\n| `surfpool` 1.x | local Surfnet for dApp demo (`~/.local/bin`) |\n\n## Honesty\n\n- CPI/ELF engineering maturity — not mainnet-ready claim  \n- Principal ≠ Solana pubkey globally  \n- Public RPC broadcast refused in pf v0  \n- Never paste private keys into chat / MCP / git  \n\n## Related\n\n- `docs/demos/solana-local-walkthrough.md`  \n- `docs/targets/02-solana.md`  \n- `docs/product/10-solana-dapp-frontend.md`  \n",
  "10-psy-dpn-lowering.md": "---\nid: TARGET-PSY-DPN\ntitle: Psy DPN lowering contract\nstatus: draft\nowner: engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Psy DPN lowering contract\n\n本文记录 `ProgramV1 → SemanticProgramV1 → PsyPlan → DPN` 的工程合同。产品只输出\nDPN package；不存在 Psy source artifact、source compiler profile、debug dual-write或\nsource-language fallback。\n\n## 1. Authority pin\n\n| 项 | 值 |\n|---|---|\n| Repository | `https://github.com/PsyProtocol/psy-node` |\n| Revision | `79e0b82422ebdd1173a7b4b3751eb3186aad83e5` |\n| Crate | `psy_vm` |\n| Schema | `DPNFunctionCircuitDefinition` |\n| Paths | `client_prover/psy_vm/src/dpn/vm/def.rs`, `client_prover/psy_vm/src/dpn/ops/` |\n| Lean pin | `ProofForgeV2.Targets.Psy.Dpn.SchemaV1.psyNodeDpnAuthorityRevV1` |\n| Supply-chain annotation | `supply-chain/psy-node-dpn-authority.v1.json` |\n\n该 revision 只提供 schema、discriminant 与 method-id algorithm authority。它不是产品可执行\n工具，不进入 Tool Lock。revision 改变时必须重新验证 schema constants、codec 与 goldens。\n\n## 2. Product contract\n\n```text\nResolvedEngineeringBuildV1\n  → Psy.planFromCapability\n  → Psy.irFromCapability\n  → Psy.buildFromCapability\n  → {programName}.dpn.json\n```\n\nExact identities：\n\n- target：`psy`\n- codegen profile：`psy-dpn-v1`\n- artifact encoding：`psyDpn`\n- MIME：`application/json`\n- finalizer：zero-tool、`deployable=false`\n\n旧 profile id 不在 registry。选择旧 id 返回 `PF-PROFILE-UNKNOWN`；产品不得 fallback。\n\n## 3. DPN model\n\n每个 materialized callable 对应一个 `DPNFunctionCircuitDefinition`：\n\n```text\nDPNFunctionCircuitDefinition {\n  name,\n  method_id,\n  circuit_inputs,\n  circuit_outputs,\n  state_commands,\n  state_command_resolution_indices,\n  assertions,\n  definitions,\n  events\n}\n```\n\n`DPNIndexedVarDef` 使用 exact data-type/op-type discriminants。indexed id 为\n`(dataType << 32) | index`。枚举有保留洞，禁止按声明 ordinal 自行推导 wire value。\n\nMethod id 使用 pinned upstream `gen_dapen_contract_function_method_id` algorithm；Counter\n`get`、`increment`、`initialize` fixtures固定算法结果。产品不使用仅靠名称的自由 pin 表。\n\n## 4. State and value layout\n\n- scalar values使用 DPN Target/Bool/U32 carriers；\n- UInt128/256使用 4/8 个 little-endian UInt32 limbs；\n- named aggregates、Array、Bytes、Principal identity、Option 与 dense Map 采用 Plan 冻结的\n  deterministic leaf order；\n- aggregate store 必须先在 pre-store snapshot 求值全部 leaves，再提交 ordered state commands；\n- state-command resolution index 与 command array exact 对齐；\n- return leaves按 target ABI order进入 `circuit_outputs`。\n\nUnknown type、leaf count、layout或 state command fail closed。\n\n## 5. Operation coverage\n\n当前 DPN lower支持已开放 Plan 中的：\n\n- literal、state load/store、construct/field/index；\n- checked UInt/Int arithmetic、compare、logical、bitwise、shift；\n- Goldilocks Field add/sub/mul/div/neg/eq/ne；\n- if/match Select lowering；\n- bounded UInt64 loop static unroll；\n- assert、bare revert；\n- constants与 pure-function inline；\n- event与 void synchronous call 的既有 PARTIAL DPN encoding。\n\nWide integer multiplication采用 bounded schoolbook construction；division/remainder使用\nrestoring division；shift使用 bounded bit walk。所有中间 carrier、range guard、overflow与\nzero-divisor behavior由 target-owned lowering固定。\n\n## 6. Fail-closed matrix\n\n| Surface | Status | Boundary |\n|---|---|---|\n| UInt8/16/32/64/128/256 | lowered | Plan + DPN tests |\n| Int8/16/32/64 | lowered | Plan + DPN tests |\n| Goldilocks Field | lowered | exact FieldSpec |\n| bn254/BLS12-377 Field | fail closed | Plan type closure |\n| named/Array/Bytes/Principal/Option | bounded lower | leaf cap/layout gate |\n| dense Map UInt64 cap-8 | lowered | fixed 24-leaf layout |\n| nested Map / Map return | fail closed | Plan gate |\n| if / match | lowered | Select/branch construction |\n| bounded for | bounded lower | static-unroll budget |\n| pureFn/localCall | bounded inline | recursion/effect gate |\n| payload error | fail closed | no structured DPN payload ABI |\n| event | PARTIAL | ordered DPN event encoding only |\n| void sync call | PARTIAL | exact DPN invoke shape only |\n| result call / schedule | fail closed | capability/Plan gate |\n| ContextRead / Commit | fail closed | no frozen public-input binding |\n| nonempty invariant | fail closed | no target refinement contract |\n| UPS / network / deploy | absent | outside materializer/finalizer |\n\nIf Plan admission succeeds but DPN lowering cannot encode the shape, materialization fails with\n`PSY-DPN-G5-HARD`. The residual fallback allowlist is empty.\n\n## 7. Canonical codec and tests\n\n`Dpn.JsonCodecV1` is the sole package encoder/decoder. It validates exact JSON shape, integer-only\nwire values, required fields and round-trip identity. The test corpus pins：\n\n- operation/data-type discriminants and indexed ids；\n- method-id algorithm；\n- Counter full-byte package golden；\n- control flow, wide integers, aggregate layouts, Map and effects；\n- sole-profile product materialization；\n- unknown/unsupported shapes fail closed；\n- exactly one `.dpn.json` output and no alternate artifact encoding。\n\nThe Counter golden is a DPN schema fixture. It does not imply execution by an external compiler or\nruntime.\n\n## 8. Finalization and maturity\n\n`Psy.FinalizeV1` performs no compilation or execution and adds no files. The product has no compiler\nor runtime tool dependency for Psy. Removal of the old source lane also removes its acceptance/runtime\nrecipes and distribution payloads.\n\nCurrent claim ceiling：canonical DPN emission with content-bound artifact closure. No local execution,\nproof generation, UPS, network settlement, deployment, hermetic qualification or formal\nReference↔Psy refinement is claimed.\n",
  "10-psy.md": "---\nid: TARGET-PSY\ntitle: Psy DPN target dossier\nstatus: draft\nowner: architecture\nupdated: 2026-08-10\nnormative: true\n---\n\n# Target Dossier：Psy DPN\n\n状态：`draft`\nTarget ID：`psy`\n工程状态：implemented leaf；不自动扩展 accepted Phase 1 范围。\n\n## 产品物化权威\n\nPsy 只有一条产品路径：\n\n```text\nSemanticProgramV1\n  → capability-gated PsyPlan\n  → target-owned DPN IR/package\n  → canonical {programName}.dpn.json\n  → zero-tool FinalizeV1\n```\n\n唯一 codegen profile 是 `psy-dpn-v1`。旧 Psy source profile、source emitter、debug\nartifact、source compiler/runtime recipes 和 compiler Tool Lock 成员已删除；旧 profile id\n必须返回 `PF-PROFILE-UNKNOWN`，不得 fallback。\n\n权威实现：\n\n- `ProofForgeV2/Targets/Psy/LowerSemanticV1.lean`\n- `ProofForgeV2/Targets/Psy/Dpn/SchemaV1.lean`\n- `ProofForgeV2/Targets/Psy/Dpn/LowerPlanV1.lean`\n- `ProofForgeV2/Targets/Psy/Dpn/JsonCodecV1.lean`\n- `ProofForgeV2/Targets/Psy/EmitIRV1.lean`\n- `ProofForgeV2/Targets/Psy/FinalizeV1.lean`\n\n迁移决定见 [ADR-0035](../adr/0035-direct-native-artifact-materializers.md)，DPN 规格见\n[`10-psy-dpn-lowering.md`](10-psy-dpn-lowering.md)。\n\n## 1. 身份与执行模型\n\nPsy 的公开材料描述用户分区状态、本地 Contract Function Circuit、User Proving Session\n递归聚合和网络最终证明，因此属于 ZK application chain，而不是通用 circuit compiler。\n当前产品仅编码 target-owned DPN 方法定义；不执行 proof、UPS、network settlement 或 deploy。\n\nDPN schema/method-id authority 固定到\n`PsyProtocol/psy-node@79e0b82422ebdd1173a7b4b3751eb3186aad83e5`，对应\n`DPNFunctionCircuitDefinition`、operation/state-command discriminants 与\n`gen_dapen_contract_function_method_id`。这是 source/schema authority pin，不是 executable\nTool Lock 成员。\n\n## 2. 支持表面\n\n当前 DPN lowering 覆盖：\n\n- UInt8/16/32/64/128/256 与 Int8/16/32/64 的受限 envelope；\n- exact Goldilocks Field、Bool、Unit；\n- named Struct/Enum、Array、Bytes、Principal identity、`Option UInt64` 与 dense Map cap-8\n  的受限 leaf lowering；\n- checked arithmetic、比较、logical/bitwise/shift；\n- immutable let、assign、assert、if/match、bounded-for static unroll、bare revert；\n- literal-backed constants与 pure-function inline；\n- DPN event 与 void synchronous-call 的既有 PARTIAL encoding。\n\nUInt128/256 采用 little-endian UInt32 limbs；乘法、除余与 shift 使用 target-owned bounded\nalgorithms。支持结论以当前 Plan/DPN tests 为准，不由历史 source compiler 行为推导。\n\n## 3. Fail-closed 边界\n\n以下仍拒绝或保持既有 PARTIAL 标签：\n\n- bn254/BLS12-377 Field；\n- nested Map、Map return、超出 aggregate-return cap；\n- result-bearing call、schedule、ContextRead、Commit、nonempty invariant；\n- `pf.assets` bindings、UPS、network 与 deploy。\n\nPlan admitted 但 DPN lowering 失败时返回 `PSY-DPN-G5-HARD`；不存在 source 语言旁路。\n\n## 4. DPN Target IR 与制品\n\n`Psy.TargetIR` 保留关联 `PsyPlan` 与 canonical\n`Array DPNFunctionCircuitDefinition`。`ArtifactEncoding.psyDpn` 是唯一 Psy artifact\nencoding。materialize 只输出 `{programName}.dpn.json`，MIME 为 `application/json`。\n\nJSON codec 强制 target-owned schema、canonical field order/shape 与 decode/encode round trip。\nCounter golden 和 wider structural fixtures用于固定 method id、indexed ids、state commands、\nassertions、definitions 与 inputs/outputs。\n\n## 5. Finalization 与工具边界\n\n`FinalizeV1` 是 zero-tool、`deployable=false`。产品不启动 source compiler、local VM、prover、\nUPS 或 network client。Tool Lock 不包含 Psy source compiler/runtime；doctor/install 对 Psy\n返回空 core-tool closure。\n\n改变 upstream DPN schema/revision 时必须同步 schema constants、supply-chain annotation、\ncodec 与 golden。不得发明不可供给的 `psy-node` executable row。\n\n## 6. 安全与资源\n\n重点风险：用户分区隔离、proof/state-delta binding、authorization、encrypted delta\n披露、aggregation soundness、data availability 与 pre-testnet schema drift。\n\nDPN lower 保留函数、参数、static-unroll、aggregate leaf、expression work 与 package size上限；\n未知 opcode/shape fail closed。输出继续经过 content-bound inventory、evidence、manifest-last 与\n`inspect` exact disk closure。\n\n## 7. 成熟度\n\n当前成熟度是 **canonical DPN package emission** + **host-optional official local simulate**（`psy_user_cli simulate` via `pf test`/`pf run` / `scripts/psy_dpn_local_smoke.sh`）。没有 PF-owned VM、proof、UPS、\nnetwork deploy、hermetic 或 formal refinement 证据；删除旧 source/compiler path 不提高这些\n成熟度。accepted PRD Phase 1 仍为 EVM/Solana/NEAR/Noir；Psy 属 engineering\n扩面，accepted/engineering scope 边界由 ADR-0036 固定。\n\n\n## 8. Product surface (agents / dApp)\n\n- Agent playbook: [`../product/11-psy-agent-playbook.md`](../product/11-psy-agent-playbook.md)\n- Frontend / wallet companion: [`../product/12-psy-dapp-frontend.md`](../product/12-psy-dapp-frontend.md)\n- Demo walkthrough: [`../demos/psy-dpn-walkthrough.md`](../demos/psy-dpn-walkthrough.md)\n- Official: [app](https://app.psy-protocol.xyz) · [wallet](https://app.psy-protocol.xyz/#/wallet) · [explorer](https://explorer.psy-protocol.xyz) · [IDE](https://ide.psy-protocol.xyz) · [config](https://config.psy-protocol.xyz/config.json) · [docs](https://docs.psy-protocol.xyz)\n\n> **Session continuity:** `psy_user_cli simulate` is **one call per process** (fresh memory).\n> For `init(7) → increment(5) → get = 12`, use `scripts/psy_dpn_session.py` / `pf test -t psy`\n> (shared-state harness). Do not expect three separate simulates to accumulate.\n\n## 9. Official tool wrap (pf)\n\n| pf command | Official tool |\n|---|---|\n| `pf run -t psy` | `psy_user_cli simulate` |\n| `pf deploy -t psy` | `psy_user_cli deploy-contract` (save-only default; `--broadcast` → `--is-deploy`) |\n| `pf test -t psy` | multi-step session harness + optional simulate sanity |\n| chain probe | `scripts/psy_local_chain_status.sh` |\n\nPersistent local chain requires host-heavy `psy-node` / `psy_node_cli` fabric — not auto-started by pf.\n",
  "10-solana-dapp-frontend.md": "---\nid: PRODUCT-SOLANA-DAPP-FRONTEND\ntitle: Solana dApp frontend — wallet-adapter + PF IDL (not Anchor)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Solana dApp 前端：wallet-adapter · PF IDL · 与 ProofForge 的分工\n\n状态：`draft`（2026-08-10）  \n模板：[`templates/solana-dapp-ui/`](../../templates/solana-dapp-ui/)  \n剧本：[`09-solana-agent-playbook.md`](09-solana-agent-playbook.md)  \nWalkthrough：[`../demos/solana-local-walkthrough.md`](../demos/solana-local-walkthrough.md)\n\n## 1. 核心原则\n\n**合约用 ProofForge 写，不用 Solana 官方 Rust/Anchor 脚手架当主路径。**\n\n```text\nProgramV1 (Lean)  --pf build -t solana-->  *.idl.json + *.so + manifest\n                                               |\n                 scripts/pf_solana_local_demo.sh (Surfpool)\n                                               |\n Browser UI (wallet-adapter + web3.js)  <------ deployment.json + IDL\n```\n\n| 层 | 谁 | 密钥 |\n|---|---|---|\n| 写合约 | ProofForge 语言 + `pf` / `proof-forge-next` | 无 |\n| 编译 | `pf build --target solana` | 无 |\n| 本地测 | `pf verify` / `pf test`（Mollusk） | 无 / 本机 |\n| 本地部署 + invoke | `scripts/pf_solana_local_demo.sh`（Surfpool） | 本机 keypair |\n| dApp UX | `templates/solana-dapp-ui` + 钱包 | **钱包**（entry/view） |\n| 公网写 | **pf v0 拒绝** | — |\n\n官方 Solana Developer MCP（Rust/Anchor autofixer）**不是**本产品的合约写作路径；PF MCP 只摘要 PF 需要的 ix 编码 / 产物 / CLI 知识。\n\n## 2. PF 产物（StateCell 形）\n\n`pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o <dir>`：\n\n| 文件 | 前端是否需要 |\n|---|---|\n| `StateCell.idl.json` | **是** — name / mode / accounts / handlerId（CPI 分支才用 handlerId） |\n| `StateCell.so` | 否（CLI deploy） |\n| `StateCell.s` | 否 |\n| `manifest.json` / `evidence.json` | 可选审计 |\n| `*.cpi-*.json` | 否（工程中间态） |\n\n## 3. Instruction data（必须钉死 · 分 profile）\n\nPF sBPF **不是** Anchor sighash。编码按 **build profile** 分支：\n\n### 3.1 body-only S1b（StateCell / `pf new` 默认）\n\n```text\nix data = sha256(\"proof-forge-solana-v1:\" ++ discName ++ \"(\" ++ types ++ \")\")[0:8]\n          || u64le(param0) || u64le(param1) || …\n\ntypes = \"u64\" * n joined by \",\"\ndiscName(init) = \"initialize\"   # IDL name may still be \"init\"\n```\n\nKnown StateCell discriminators (hex LE bytes):\n\n| ix | disc name | first 8 hex |\n|---|---|---|\n| init | `initialize(u64)` | `5e494767a7582864` |\n| increment | `increment(u64)` | `9dc79703d1db3e22` |\n| get | `get()` | `a4a276b0d690dd37` |\n\nAccount metas (StateCell):\n\n| ix | state.is_signer | state.is_writable |\n|---|---|---|\n| init | **true** | true |\n| increment | false | true |\n| get | false | false |\n\nBrowser wallets usually **cannot** sign an arbitrary state keypair → run init via\n`scripts/pf_solana_local_demo.sh` / `pf_solana_statecell_invoke.py`, then use the UI for entry/view.\n\n### 3.2 CPI-product（TransferSol 等）\n\n```text\nix data = u64le(handlerId) || u64le(param0) || …\n```\n\n- `handlerId` 来自 IDL `instructions[].handlerId`\n- 模板默认 UI 走 body-only；CPI 路径按 manifest/profile 分支，见 MCP `pf_solana_ix_codec`\n\n### 3.3 错误示范\n\n- 对 body-only ELF 使用 `handlerId`\n- 对 PF ELF 使用 Anchor `sha256(\"global:increment\")[..8]`\n- 把两种 layout 混成一个全局规则\n\n模板：`templates/solana-dapp-ui/src/ix.ts` → `encodePfIxData`（body-only）\n\n## 4. State account layout（StateCell ordinary）\n\n16 bytes：\n\n```text\noffset 0: layout marker u64 LE  (non-zero when initialized)\noffset 8: count u64 LE\n```\n\nUI：`readStateCellCount` 读 offset 8（**不是** offset 0）。\n\n## 5. 一键本地 demo（推荐）\n\n```bash\n# needs: surfpool 1.x on PATH (~/.local/bin), solana CLI, solders venv optional\njust pf-solana-local-demo\n# or:\nbash scripts/pf_solana_local_demo.sh\n\n# leaves Surfpool up by default; tear down:\njust solana-surfpool-down\n```\n\nWrites:\n\n- `templates/solana-dapp-ui/public/deployment.json`\n- `templates/solana-dapp-ui/public/artifacts/StateCell.idl.json`\n\nThen:\n\n```bash\ncd templates/solana-dapp-ui && npm install && npm run dev\n```\n\n## 6. Agent 剧本（前端）\n\n| 步 | 动作 |\n|---|---|\n| F0 | MCP `pf_solana_scaffold` / `pf_chain_catalog target=solana` |\n| F1 | **用 PF 语言**写/改合约（不要新建 Anchor 工程） |\n| F2 | `pf build -t solana` → 复制 `*.idl.json` |\n| F3 | `pf verify` / `pf test` |\n| F4 | `just pf-solana-local-demo`（Surfpool deploy + init）→ `deployment.json` |\n| F5 | 起 `templates/solana-dapp-ui` · 钱包连本地 Surfpool RPC |\n| F6 | 禁止默认连 mainnet/devnet 热路径 |\n\n## 7. 安全\n\n- 无私钥进前端仓库 / MCP 参数  \n- pf v0 **拒绝** public Solana RPC broadcast  \n- Principal wire ≠ Solana pubkey 全局等价  \n- 工程 demo ≠ formal/mainnet evidence  \n\n## Related\n\n- `templates/solana-dapp-ui/`  \n- `scripts/pf_solana_local_demo.sh`  \n- `docs/product/09-solana-agent-playbook.md`  \n- `docs/targets/02-solana.md`  \n",
  "11-psy-agent-playbook.md": "---\nid: PRODUCT-PSY-AGENT-PLAYBOOK\ntitle: Psy agent playbook — ProofForge DPN + official Psy toolchain\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Psy agent playbook（ProofForge DPN 主路径）\n\n**Audience:** coding agents + developers  \n**Claims:** engineering guidance only — **not** formal / hermetic / mainnet deploy from PF\n\n## 一句话\n\n用 **ProofForge 语言 + `pf` CLI** 把 `ProgramV1` **编译成 canonical DPN package**（`*.dpn.json`）。  \n链上部署、prove、钱包、前端 **走 Psy 官方工具**（`psyup` / `dargo` / `psy_user_cli` / `@psy-protocol/psy-sdk` / wallet / WebIDE）。  \n**不要**把 Dargo/Psy-lang 手写脚手架当成 PF 合约主路径；也 **不要**假装 PF 已内置 Psy network broadcast。\n\n## 官方入口（生态，非 PF 发货）\n\n| 面 | URL | 用途 |\n|---|---|---|\n| Docs | https://docs.psy-protocol.xyz · https://psy.xyz/docs | 协议 / 语言 / SDK / VM / RPC |\n| App / Bridge | https://app.psy-protocol.xyz | 支付 / bridge / UX |\n| Wallet | https://app.psy-protocol.xyz/#/wallet · https://app.psy-protocol.xyz/wallet | 用户密钥 / 签名 / claim |\n| Explorer | https://explorer.psy-protocol.xyz | 区块 / 交易 / 合约观察 |\n| WebIDE | https://ide.psy-protocol.xyz | 浏览器写 Psy-lang · compile · 交互 |\n| Config | https://config.psy-protocol.xyz · `…/config.json` | 公共 RPC / L1 Sepolia / 合约地址 |\n| GitHub | https://github.com/PsyProtocol · psy-sdk / psy-compiler / psy-node / psy-template | 源码与模板 |\n| Toolchain installer | https://github.com/QEDProtocol/psyup | `psyup` 安装 dargo / psy_user_cli 等 |\n\nRelease config snapshot（2026-07-20 公开面，**会变** — 以 `config.json` 为准）：\n\n| Key | Value |\n|---|---|\n| L1 | Ethereum Sepolia (`chain_id=11155111`) |\n| coordinator_rpc | `https://coordinator.psy-protocol.xyz` |\n| realm_rpcs | `https://realm0.psy-protocol.xyz`, `https://realm1.psy-protocol.xyz` |\n| prove_proxy | `https://prove.psy-protocol.xyz` |\n| indexer | `https://indexer.psy-protocol.xyz/v1/graphql` |\n\n## 唯一推荐 MCP\n\n| Server | Endpoint |\n|---|---|\n| **ProofForge remote MCP** | `https://proof-forge-mcp.davirain-yin.workers.dev/mcp` |\n\nPsy tools：\n\n| Tool | 作用 |\n|---|---|\n| `pf_psy_scaffold` | PF ladder + 官方 toolchain 边界 |\n| `pf_psy_artifacts` | `*.dpn.json` 产物说明 |\n| `pf_psy_ecosystem` | 官方站点 / SDK / wallet / config 摘要 |\n| `pf_target_info` / `pf_cli_cheatsheet` | `target=psy` |\n| `pf_get_doc` | `11-…` / `12-…` / demo walkthrough |\n\n## 分工（必须钉死）\n\n```text\nProgramV1 (Lean)\n    │  pf build --target psy\n    ▼\n{name}.dpn.json   ← ProofForge sole product artifact (deployable=false)\n    │\n    │  hand-off (human / agent on developer machine)\n    ▼\nOfficial Psy toolchain\n    dargo / psyup build   (Psy-lang source projects)\n    psyup deploy / psy_user_cli\n    @psy-protocol/psy-sdk + psy-wallet / WebIDE\n    explorer / coordinator / realm RPC\n```\n\n| 层 | 谁 | PF 是否发货 |\n|---|---|---|\n| 写 PF 合约 · 出 DPN | `pf` / `proof-forge-next` | **是** |\n| Psy-lang 源工程 · ABI | `dargo` / `psyup` / WebIDE | 否（官方） |\n| 部署 / 调用 CLI | `psyup deploy` · `psy_user_cli` | 否 |\n| 浏览器钱包 | psy-wallet · `window.psy` | 否 |\n| TS SDK | `@psy-protocol/psy-sdk` · `contract-sdk` | 否 |\n| 本地全节点集群 | `psy-node` | 否 |\n\n**诚实边界：**\n\n- PF profile **仅** `psy-dpn-v1`；`deployable=false`；zero-tool finalize。  \n- 旧 Dargo/source/VM/proof product lane **已删除**（ADR-0035 / C-2）。  \n- DPN 可被官方 VM schema 消费的权威 pin 见 `supply-chain/psy-node-dpn-authority.v1.json` — **不是** Tool Lock 可执行物。  \n- **没有** PF→testnet 一键 deploy；不要在 MCP 默认面持有 Psy 私钥或 broadcast。\n\n## 本地 `pf` ladder（DPN only）\n\n```bash\nexport PROOF_FORGE_CLI=/path/to/proof-forge-next\nexport PATH=\"$HOME/.cargo/bin:$PATH\"\n\npf setup --target psy      # zero-tool: doctor ok with empty tool set\npf doctor --target psy\n\npf new hello --target psy && cd hello\n# edit Lean ProgramV1 — not Dargo.toml / .psy as PF source of truth\npf build\n# monorepo:\n# pf build Examples/StateCell.lean --module Examples.StateCell --target psy -o build/v2/sc-psy\n\nls *.dpn.json manifest.json evidence.json\npf inspect --output-dir .\n\n\n> **Session continuity:** `psy_user_cli simulate` is **one call per process** (fresh memory).\n> For `init(7) → increment(5) → get = 12`, use `scripts/psy_dpn_session.py` / `pf test -t psy`\n> (shared-state harness). Do not expect three separate simulates to accumulate.\n\n# Local DPN VM (official psy_user_cli simulate — host tool)\nexport PATH=\"$HOME/.psy/bin:$PATH\"\npf test -t psy\npf run -t psy -- initialize 7\n# multi-call session is NOT preserved across simulates (fresh memory each call)\n```\n\nStateCell 示例 method_id（DPN，算法钉死；重建可能变若 schema pin 变）：\n\n| method | method_id (u32) |\n|---|---|\n| get | 1459926901 |\n| increment | 1990357658 |\n| initialize | 202172507 |\n\n## 官方 toolchain（部署 / dApp — 开发者本机）\n\n```bash\n# Installer (public docs; network name follows psyup release — often sepolia config)\ncurl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh \\\n  | PSYUP_DEFAULT_NETWORK=sepolia sh\npsyup install   # dargo, psy_user_cli, …\n\n# Optional official scaffold (Psy-lang, not PF Lean)\npsyup new my-app\ncd my-app/contract && psyup build\n\n# Deploy is official CLI — NOT pf deploy\n# psyup init && export KEYSTORE_PATH=$HOME/.psy/keystore/default\n# psyup deploy\n```\n\n浏览器路径：\n\n1. https://ide.psy-protocol.xyz — 写/编译 Psy-lang  \n2. https://app.psy-protocol.xyz/#/wallet — 钱包  \n3. https://explorer.psy-protocol.xyz — 观察  \n\n## Frontend 包（生态）\n\n| Package | 角色 |\n|---|---|\n| `@psy-protocol/psy-sdk` | RPC · wallet provider · local web prover/compiler |\n| `@psy-protocol/contract-sdk` | ABI codegen / typed contract runtime |\n| `@psy-protocol/utils` | 共享工具 |\n\n模板注入：`window.psy.requestAccounts` / `sendTransaction`（见官方 `psy-template`）。\n\n\n## Deploy (official CLI wrapped by `pf`)\n\n```bash\npf build -t psy -o build/v2/sc-psy\n# save-only: materialize deploy_cmd.json via psy_user_cli deploy-contract (no --is-deploy)\npf deploy -t psy --artifact build/v2/sc-psy --network local\n\n# broadcast (needs funded key + live coordinator)\n# local cluster:\npf deploy -t psy --artifact build/v2/sc-psy --network local --broadcast --private-key-env PF_PSY_KEY\n# public staging/testnet (sepolia config in ~/.psy/config.json):\npf deploy -t psy --artifact build/v2/sc-psy --network testnet --broadcast --private-key-env PF_PSY_KEY\n# after deploy: tx/deployment.json has contractId\npf execute -t psy --artifact build/v2/sc-psy --network testnet --broadcast --private-key-env PF_PSY_KEY -- initialize 7\npf execute -t psy --artifact build/v2/sc-psy --network testnet --broadcast --private-key-env PF_PSY_KEY -- increment 5\n```\n\n`pf` only shells to `psy_user_cli deploy-contract`. Mainnet refused.\nProbe chain: `bash scripts/psy_local_chain_status.sh`\n\n\n### Funding note (call vs deploy)\n\n- `pf deploy --broadcast` may succeed with **zero L2 balance**.\n- `pf execute` / `psy_user_cli call` burns **GUTA + DA fees** (~1e9 native units observed on staging).\n- If you see `insufficient balance (left: 0, right: 1)`: fund via\n  [Psy app / faucet / bridge](https://app.psy-protocol.xyz) for the registered user, then retry.\n- Check leaf: `psy_user_cli get-user-leaf --user-id <id> --rpc-config <sepolia-config>`.\n\n## Honesty\n\n- engineering DPN emission ≠ execution / UPS / proof / network settlement  \n- Principal / identity model ≠ EVM address 全局等价  \n- Never paste private keys into chat / MCP / git  \n- Config endpoints drift — always refresh `config.psy-protocol.xyz/config.json`\n\n## Related\n\n- [`12-psy-dapp-frontend.md`](12-psy-dapp-frontend.md)  \n- [`../demos/psy-dpn-walkthrough.md`](../demos/psy-dpn-walkthrough.md)  \n- [`../targets/10-psy.md`](../targets/10-psy.md)  \n- [`../targets/10-psy-dpn-lowering.md`](../targets/10-psy-dpn-lowering.md)  \n",
  "12-psy-dapp-frontend.md": "---\nid: PRODUCT-PSY-DAPP-FRONTEND\ntitle: Psy dApp frontend — wallet + SDK (FCCP companion)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Psy dApp 前端：Wallet · SDK · 与 ProofForge 的分工\n\n状态：`draft`（2026-08-10）  \n剧本：[`11-psy-agent-playbook.md`](11-psy-agent-playbook.md)  \nWalkthrough：[`../demos/psy-dpn-walkthrough.md`](../demos/psy-dpn-walkthrough.md)  \nTarget dossier：[`../targets/10-psy.md`](../targets/10-psy.md)\n\n## 1. 核心原则\n\n**合约语义用 ProofForge 写并物化为 DPN；链上交互用 Psy 官方钱包/SDK。**\n\n```text\nProgramV1 --pf build -t psy-->  *.dpn.json (+ manifest)\n                                      │\n                    hand-off to official Psy stack\n                                      │\n Browser / WebIDE / psy-wallet  <----- contract_id + ABI + SDK\n```\n\nProofForge **不** vendor `@psy-protocol/*` npm 包，**不**在 MCP 默认面持私钥或广播。\n\n## 2. PF 产物（StateCell 形）\n\n```bash\npf build Examples/StateCell.lean --module Examples.StateCell --target psy -o <dir>\n```\n\n| 文件 | 前端/官方工具是否需要 |\n|---|---|\n| `StateCell.dpn.json` | **是** — canonical DPN package（method_id / definitions / state_commands） |\n| `manifest.json` | 审计 / Agent inspect |\n| `evidence.json` | 可选 |\n\n`deployable=false`。没有 PF 生成的 `.psy` / Dargo 工程作为产品权威输出。\n\n### DPN 形状（摘要）\n\n每个 callable → `DPNFunctionCircuitDefinition`：\n\n```text\nname, method_id, circuit_inputs, circuit_outputs,\nstate_commands, state_command_resolution_indices,\nassertions, definitions, events\n```\n\nAuthority pin：`PsyProtocol/psy-node@79e0b824…`（schema only — 见 supply-chain annotation）。\n\n## 3. 官方前端 / 钱包面\n\n| 面 | URL |\n|---|---|\n| App | https://app.psy-protocol.xyz |\n| Wallet | https://app.psy-protocol.xyz/#/wallet |\n| Explorer | https://explorer.psy-protocol.xyz |\n| WebIDE | https://ide.psy-protocol.xyz |\n| Config JSON | https://config.psy-protocol.xyz/config.json |\n\n### 3.1 浏览器扩展 / `window.psy`（官方模板）\n\n```ts\n// conceptual — follow current psy-template types\nconst accounts = await window.psy.requestAccounts()\nconst txId = await window.psy.sendTransaction(accounts[0], {\n  contract_id: 7n,\n  method_name: \"increment\",\n  inputs: [5n],\n})\n```\n\n- 密钥留在钱包；dApp 不持 private key。  \n- 读路径可能需要公共 RPC / SDK `PsyUserWallet`（以官方模板 README 为准）。\n\n### 3.2 npm 包\n\n```bash\npnpm add @psy-protocol/psy-sdk @psy-protocol/contract-sdk\n```\n\n| 包 | 用途 |\n|---|---|\n| `@psy-protocol/psy-sdk` | coordinator/realm RPC · wallet · local web prover/compiler |\n| `@psy-protocol/contract-sdk` | ABI → typed contract helpers |\n| `@psy-protocol/utils` | 共享 |\n\n子路径（以当前 package exports 为准）：`@psy-protocol/psy-sdk/local-web-compiler`、`…/local-web-prover`。\n\n### 3.3 公共配置\n\n```bash\ncurl -sS https://config.psy-protocol.xyz/config.json | jq '.services,.frontends,.l1'\n```\n\nL1 侧当前公开面为 **Sepolia** bridge 相关合约；Psy L2/realm 走 coordinator + realm RPCs。地址会变 — **禁止**把旧地址写死进 PF 仓库当权威。\n\n## 4. 与 DPN / method_id 的衔接\n\n1. `pf build -t psy` → 读 `*.dpn.json` 的 `name` + `method_id`。  \n2. 官方部署成功后得到 `contract_id` / `contract_uuid`（`contract/.psy-deploy` 一类元数据 — 官方工具写出）。  \n3. 前端调用用 **官方 ABI/SDK 形状**（`method_name` + `inputs: bigint[]`），不是 Solana discriminator，也不是 EVM calldata。  \n4. PF **不**保证 DPN 可被某一版 `dargo` 直接“当源码导入”；hand-off 是 **schema-compatible package**，部署流水线以官方文档为准。若官方要求 `.psy` 源，则：\n   - 用 WebIDE / `psyup new` 写官方合约，或  \n   - 将 DPN 作为审计/对照物，而不是假装 PF 已生成可 `psyup deploy` 的完整 Dargo 工程。\n\n## 5. Agent 剧本（前端）\n\n| 步 | 动作 |\n|---|---|\n| P0 | MCP `pf_psy_scaffold` / `pf_chain_catalog target=psy` |\n| P1 | PF 语言写合约 → `pf build -t psy` → 保留 `*.dpn.json` |\n| P2 | 打开官方 docs / config；安装 `psyup`（开发者机） |\n| P3 | WebIDE 或 `psyup new` 做官方交互原型 |\n| P4 | wallet connect · 小额 test 调用 · explorer 核对 |\n| P5 | **禁止**把私钥放进 MCP/git；**禁止**声称 PF 已 mainnet |\n\n## 6. 安全\n\n- 无私钥进前端仓库 / MCP 参数  \n- PF v0 **无** Psy network broadcast 产品命令  \n- UPS / local prove 在用户设备或官方 prover 路径 — 非 PF  \n- engineering demo ≠ formal evidence  \n\n## Related\n\n- `docs/product/11-psy-agent-playbook.md`  \n- `docs/demos/psy-dpn-walkthrough.md`  \n- `docs/targets/10-psy-dpn-lowering.md`  \n- https://github.com/PsyProtocol/psy-sdk  \n- https://github.com/PsyProtocol/psy-template  \n",
  "13-xlayer-onchainos.md": "---\nid: PRODUCT-XLAYER-ONCHAINOS\ntitle: X Layer networks + OKX OnchainOS integration (catalog / MCP / roadmap)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# X Layer · OnchainOS · ProofForge\n\n状态：`draft`（2026-08-10）  \n机器可读网络表：[`networks.v1.json`](networks.v1.json)（schema `proof-forge.network-catalog.v1`）  \n链客户端 catalog：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  \nEVM 前端：[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md) · [`templates/evm-dapp-ui/`](../../templates/evm-dapp-ui/)  \n官方 X Layer： [about](https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/about-xlayer) · [network info](https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/network-information)  \nOnchainOS 总览： [what-is-onchainos](https://web3.okx.com/zh-hans/onchainos/dev-docs/home/what-is-onchainos)  \nBuild X 黑客松： [build-x-series](https://web3.okx.com/zh-hans/xlayer/build-x-series)\n\n## 1. 目的\n\n给作者 / Code Agent 固定：\n\n1. **X Layer** 主网 / 测试网参数（chainId、RPC、explorer、OKB gas）\n2. **OnchainOS** 能力地图（钱包 · 交易 · 行情 · 支付）与 **官方 MCP**\n3. 与 ProofForge 的 **分工** 与 **P0–P2 路线**（产品决策未定时仍可开发）\n\n**不是** 第二编译器、不是钱包实现、不是默认 public broadcast。\n\n## 2. 网络速查\n\n| id | env | chainId | gas | policy |\n|---|---|---|---|---|\n| `evm.local.anvil` | local | 31337 | ETH | `local-only`（默认 demo） |\n| `evm.xlayer.testnet` | testnet | **1952** | **OKB** | `testnet-opt-in` |\n| `evm.xlayer.mainnet` | mainnet | **196** | **OKB** | `mainnet-gated` |\n| `evm.ethereum.sepolia` | testnet | 11155111 | ETH | `metadata-only`（占位） |\n\n权威字段与 RPC 列表见 [`networks.v1.json`](networks.v1.json)。\n\n### X Layer 要点\n\n- **全 EVM 等效** → ProofForge `--target evm` 产物（Yul / solc bytecode / ABI）可部署，无需改 materializer 语义。\n- 架构：OP Stack 乐观 Rollup + AggLayer（见官方 about 页）。\n- Gas：**OKB**（不是 ETH）。\n- 黑客松：期间 **testnet**；之后 **mainnet**。\n\n## 3. 架构边界\n\n```text\nAuthor / Agent\n    │\n    ├─ ProofForge (pf / proof-forge-next / PF MCP)\n    │     program → build --target evm → abi + bytecode + manifest\n    │     catalog: networks · chain-client · docs\n    │     local: Anvil differential / templates/evm-dapp-ui\n    │     NO default public broadcast · NO keys on remote MCP\n    │\n    └─ OKX OnchainOS (official MCP + Open API + Skills)\n          DEX quote / liquidity / swap calldata\n          Market data (API; MCP probe)\n          Agentic Wallet (TEE; agent execution)\n          Payments (APP protocol; later)\n                    │\n                    ▼\n              X Layer (1952 / 196)\n```\n\n| 层 | 谁 | 密钥 |\n|---|---|---|\n| 合约语义 + codegen | ProofForge | 无 |\n| 本机 Anvil demo | PF scripts + Anvil #0 | 仅 local |\n| X Layer 读链 / 前端 attach | dApp + public RPC | 无 |\n| X Layer 写链 | 用户钱包或开发者本机 env key | **永不**进 PF remote MCP |\n| DEX 报价 / swap 构造 | OnchainOS MCP（`OK-ACCESS-KEY`） | API key 在应用本地 |\n\n## 4. 官方 OnchainOS MCP（P0：直接用）\n\n| | |\n|---|---|\n| URL | `https://web3.okx.com/api/v1/onchainos-mcp` |\n| Auth | Header `OK-ACCESS-KEY`（[Dev Portal](https://web3.okx.com/zh-hans/onchainos/dev-portal/project)） |\n| 文档 | [DEX MCP Server](https://web3.okx.com/onchainos/dev-docs/trade/dex-ai-tools-mcp-server) |\n\n已文档化的工具（Trade/DEX 面）：\n\n- `dex-okx-dex-aggregator-supported-chains`\n- `dex-okx-dex-liquidity`（示例含 **X-layer**）\n- `dex-okx-dex-quote`\n- `dex-okx-dex-approve-transaction`\n- `dex-okx-dex-swap`\n- `dex-okx-dex-solana-swap-instruction`\n\n### Agent 双挂示例\n\n```bash\n# ProofForge remote (docs/catalog/guidance)\ncodex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n\n# OnchainOS official (DEX) — key from portal, app-local only\nclaude mcp add onchainos-mcp https://web3.okx.com/api/v1/onchainos-mcp -t http \\\n  -H \"OK-ACCESS-KEY: <your-key>\"\n```\n\n**禁止**：把 `OK-ACCESS-KEY` 写进 monorepo、Workers 公共 env、或 PF 远程工具参数。\n\n## 5. 能力 × 优先级（P0–P2）\n\n| Pri | 能力 | 动作 | 状态（本切片） |\n|---|---|---|---|\n| **P0** | X Layer 网络元数据 | `networks.v1.json` + MCP `pf_network_info` | **done (catalog)** |\n| **P0** | OnchainOS 地图 + 双 MCP 说明 | 本文 + `pf_onchainos_guide` | **done (docs/MCP guidance)** |\n| **P0** | DEX | **官方** onchainos-mcp，不自研 | **use official** |\n| **P0** | EVM UI 链预设 | `templates/evm-dapp-ui` X Layer chain ids | **done (template presets)** |\n| **P1** | 行情 Market API | 探官方 MCP；否则只读 REST 薄包装 | **planned** |\n| **P1** | Agentic Wallet | 文档 + Skills/dApp 接线；PF 不实现 TEE | **planned** |\n| **P1** | testnet 部署脚本 | `scripts/pf_evm_xlayer_deploy.sh` 工程 lane | **stub / planned** |\n| **P2** | Payments APP | 文档占位 → 后置 | **planned** |\n| **P2** | 更多 EVM 行 | 同表加 `evm.<chain>.<env>` | **placeholder row exists** |\n| **P2** | Lean `NetworkRegistry` | 规格已有；产品 deploy identity join | **spec only** |\n\n## 6. PF 查询面\n\n| 面 | 入口 |\n|---|---|\n| JSON | `docs/product/networks.v1.json` |\n| 远程 MCP | `pf_network_info` · `pf_onchainos_guide` · `pf_get_doc` id=`13-xlayer-onchainos.md` |\n| 本地 stdio MCP | 同名工具（读 monorepo JSON） |\n| SDK | `ProofForgeClient.network_catalog` / `networks` |\n| chain catalog | `pf_chain_catalog` `target=evm` → `networksRef` + `ecosystem.okxOnchainOs` |\n\n### `pf_network_info` 参数（示意）\n\n```json\n{ \"id\": \"evm.xlayer.testnet\" }\n```\n\n```json\n{ \"targetFamily\": \"evm\", \"env\": \"testnet\" }\n```\n\n省略 filter → 返回全表 + notes。\n\n## 7. 前端（X Layer）\n\n默认 demo 仍是 **Anvil**。连 X Layer testnet 时：\n\n```bash\ncd templates/evm-dapp-ui\n# example — attach already-deployed contract; wallet signs\nexport VITE_CHAIN_ID=1952\nexport VITE_RPC_URL=https://testrpc.xlayer.tech/terigon\nexport VITE_CONTRACT_ADDRESS=0x…\nnpm run dev\n```\n\n或使用模板内 `XLAYER_TESTNET` / `XLAYER_MAINNET` 预设（见 `src/chains.ts`）。\n\n**不要**把主网热钱包私钥放进 `.env` 或前端 bundle。\n\n## 8. 工程部署（诚实）\n\n| 路径 | 现状 |\n|---|---|\n| `pf build -t evm` | 产品支持（产物） |\n| Anvil local deploy | 产品 demo 脚本 |\n| X Layer testnet write | **工程 lane**：开发者本机 cast/viem + funded OKB；非 MCP 默认面 |\n| X Layer mainnet write | **gated**；pf v0 默认拒绝 public broadcast |\n| Lean NetworkRegistry digest join | 规格见 `docs/specs/target-registry.md`；未产品接线 |\n\nDeploy 脚本占位：`scripts/pf_evm_xlayer_deploy.sh`（fail-closed 除非显式 env）。\n\n## 9. 黑客松产品方向（未定案 · 仅参考）\n\n竖切候选（决策前不绑定实现）：\n\n- **ForgeAgent**：NL → 受控 PF 模板 → EVM 部署 X Layer → OnchainOS quote/swap 编排\n- 合约侧：限额金库 / Intent Guard / 分账（ProgramV1）\n- 不冲 Launch Grant 刷量；主打完成度 + AI + X Layer 真实部署\n\n## 10. 非目标\n\n- 不在 `proof-forge-next build` 上加 `--network`\n- 不把 OnchainOS REST 重写成 Lean\n- 不在远程 PF MCP 代签或代持 OKX key\n- 不声称 formal / hermetic / mainnet-ready\n- 不因 catalog 存在而改 `deployable=true`\n\n## 11. 相关\n\n- Network catalog：[`networks.v1.json`](networks.v1.json)\n- Chain client catalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md)\n- EVM frontend：[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md)\n- CLI network 规格：[`../specs/target-registry.md`](../specs/target-registry.md) · [`../specs/cli.md`](../specs/cli.md)\n- 远程 MCP：[`../../clients/pf-mcp/`](../../clients/pf-mcp/)\n",
  "aleo-testnet-walkthrough.md": "---\nid: DEMO-ALEO-TESTNET-WALKTHROUGH\ntitle: Demo — Aleo with pf (local run → Testnet deploy → execute)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Demo: Aleo with `pf` — local run → Testnet deploy → execute\n\n**Audience:** video / livestream  \n**Time:** ~8–12 minutes (save-only) · +5–15 minutes if real Testnet broadcast  \n**Claims:** engineering demo only — **not** formal / hermetic / mainnet  \n\n## What this proves\n\n| Step | What viewers see |\n|---|---|\n| 1 Setup | `pf setup` checklist (compiler + Leo) |\n| 2 New project | cargo-like `pf new` |\n| 3 Build | `pf build` → `.aleo` OutputSet |\n| 4 Local VM | `pf run` initialize / increment (offline Leo) |\n| 5 Deploy package | `pf deploy` → saved deployment JSON (default **no broadcast**) |\n| 6 Execute package | `pf execute` → saved execution JSON |\n| 7 (Optional) Testnet | `--broadcast` with **your funded** key on testnet |\n\n## Safety (say this on camera)\n\n1. Default `pf deploy` / `pf execute` are **save-only** — no chain write.  \n2. Mainnet is **refused**.  \n3. Broadcast needs `--private-key-env NAME` and a **funded** testnet key — never the Leo well-known dev key.  \n4. Do **not** paste private keys into chat, slides, or git.\n\n---\n\n## Prerequisites (before recording)\n\n```bash\n# Product tools (this machine already works if these pass)\nexport PROOF_FORGE_CLI=/path/to/proof-forge-next   # monorepo: $PWD/.lake/build/bin/proof-forge-next\nexport PATH=\"$HOME/.cargo/bin:$PATH\"               # leo + cargo-installed pf\n\n# Optional: install from crates.io\n# cargo install proof-forge-pf --locked\n\npf setup --target aleo\n# Expect: proof-forge-next ok, leo ok\n```\n\n### For real Testnet broadcast only\n\n| Need | Notes |\n|---|---|\n| Aleo testnet account | Create via Leo / Provable explorer tooling |\n| Funded credits | Testnet faucet / community faucet (policy changes — check current docs) |\n| Env var with private key | e.g. `export PF_ALEO_TESTNET_KEY='APrivateKey1…'` — **never commit** |\n| Network | `testnet` only (`devnet` ok for local snarkOS; mainnet refused) |\n\n---\n\n## Shot list (record in one terminal, large font)\n\n### Shot 0 — Title card (5s)\n\n> ProofForge `pf` · Aleo · local → Testnet  \n> Default: save-only · Optional: broadcast\n\n### Shot 1 — Setup (30s)\n\n```bash\npf setup --target aleo\npf version\n```\n\n**Say:** “`pf` is the developer CLI. Compiler is `proof-forge-next`. Leo is the official VM/tool.”\n\n### Shot 2 — New project (45s)\n\n```bash\nrm -rf /tmp/pf-aleo-video && mkdir -p /tmp/pf-aleo-video && cd /tmp/pf-aleo-video\npf new hello --target aleo\ncd hello\ncat pf.toml\nsed -n '1,40p' src/Hello.lean\n```\n\n**Say:** “Same shape as our StateCell template — init, increment, get. No Lake package.”\n\n### Shot 3 — Build (45s)\n\n```bash\npf build\nls -la build/aleo/\nhead -30 build/aleo/hello.aleo   # program id may be hello.aleo\ncat build/aleo/manifest.json | head -40\n```\n\n**Say:** “Compiler emits Aleo Instructions OutputSet. We never rewrite deployable.”\n\n### Shot 4 — Local run (90s)\n\n```bash\npf run -- initialize 5u64\npf run -- increment 3u64\npf run -v -- increment 1u64    # optional: show full Leo log once\n```\n\n**Say:** “Offline Leo VM via imports pin — no network.”\n\n### Shot 5 — Deploy save-only (60s)\n\n```bash\npf deploy --network testnet\nls -la build/aleo/tx/\n# show a slice of the deployment JSON (no secrets)\npython3 -I -c 'import json,glob; p=glob.glob(\"build/aleo/tx/*.deployment.json\")[0]; d=json.load(open(p)); print(p); print(\"keys\", list(d)[:12] if isinstance(d,dict) else type(d))'\n```\n\n**Say:** “This materializes a deploy transaction and **saves** it. broadcast=false by default.”\n\n### Shot 6 — Execute save-only (60s)\n\n```bash\npf execute --network testnet -- initialize 5u64\nls -la build/aleo/tx/\n```\n\n**Say:** “Same for execute — package the call, don’t send unless we opt in.”\n\n### Shot 7 — Safety demo (30s)\n\n```bash\n# Must fail:\npf deploy --network mainnet || true\n```\n\n**Say:** “Mainnet hard-refused in pf v0.”\n\n### Shot 8 — Optional real Testnet broadcast (only if funded key ready)\n\n```bash\n# DO NOT type the key on camera — load from a pre-exported env in a private shell\n# export PF_ALEO_TESTNET_KEY='…'   # already set off-camera\n\npf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY\n# Wait for explorer confirmation; paste program id on screen\n\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- initialize 5u64\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- increment 3u64\n```\n\n**Say:**\n\n- “Broadcast is explicit.”  \n- “Key comes from env name only — never a default file scan.”  \n- “Well-known Leo demo key is refused for broadcast.”  \n- Open Provable/Aleo explorer for the program + txs if available.\n\n### Shot 9 — Close (20s)\n\n```bash\npf --help | head -40\n```\n\n**Say:** “Same `pf` surface for EVM/Solana later — build / test / deploy save-only. Aleo is first full local+network packaging path.”\n\n---\n\n## Live Testnet result (2026-08-10)\n\nSuccessful end-to-end broadcast with funded key.\n\n### Public recording\n\n| Item | Link |\n|------|------|\n| **asciinema (public)** | https://asciinema.org/a/1262697 |\n| Embed | `<script src=\"https://asciinema.org/a/1262697.js\" id=\"asciicast-1262697\" async></script>` |\n| Local cast (gitignored) | `build/demos/aleo/pf-aleo-demo-20260810T043722Z.cast` |\n\n```bash\n# local replay\nasciinema play build/demos/aleo/pf-aleo-demo-20260810T043722Z.cast\n```\n\n### On-chain\n\n| Item | Value |\n|------|-------|\n| Network | Aleo **testnet** (`https://api.explorer.provable.com/v1`) |\n| Program | `pfdemo336641.aleo` |\n| Deploy tx | `at147hjftmt294hrdgy7hfkjzn69ryxj3j2ank4jxl4u9qn8vl6nvqs73a5mt` |\n| Execute tx (increment) | `at1j4g47meu322csew7vdlwx5x3hrpfaq0fftmet3zphdyzvxfanczsns58fd` |\n| On-chain state | `pf_state_0[0]=8u64` (initialize `5` + increment `3`), `initialized[0]=true` |\n| Deploy fee | `3125778` microcredits (~3.13 credits) |\n| Execute fee (increment) | `1849` microcredits |\n\n### Explorer (click-through)\n\n| What | URL |\n|------|-----|\n| Program | https://testnet.explorer.provable.com/program/pfdemo336641.aleo |\n| Deploy transaction | https://testnet.explorer.provable.com/transaction/at147hjftmt294hrdgy7hfkjzn69ryxj3j2ank4jxl4u9qn8vl6nvqs73a5mt |\n| Execute transaction | https://testnet.explorer.provable.com/transaction/at1j4g47meu322csew7vdlwx5x3hrpfaq0fftmet3zphdyzvxfanczsns58fd |\n\nAPI cross-checks used during the demo:\n\n```bash\n# deployment id for program\ncurl -sS https://api.explorer.provable.com/v1/testnet/find/transactionID/deployment/pfdemo336641.aleo\n# mappings present\ncurl -sS https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mappings\n# live state\ncurl -sS https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mapping/pf_state_0/0u8\ncurl -sS https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mapping/initialized/0u8\n```\n\n**Toolchain gate:** Leo **4.4.1+** required for current Testnet base-fee validation. Leo 4.0.2 under-estimates deployment base fee and is rejected by the node.\n\n**pf flags used for live broadcast:**\n\n```bash\npf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id pfdemo336641\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id pfdemo336641 -- initialize 5u64\npf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id pfdemo336641 -- increment 3u64\n```\n\nBroadcast mode generates real deploy certificates / execution proofs (save-only still uses skip flags for speed).\n\n## One-shot rehearsal script (no broadcast)\n\n```bash\n#!/usr/bin/env bash\nset -euo pipefail\nexport PROOF_FORGE_CLI=\"${PROOF_FORGE_CLI:?set PROOF_FORGE_CLI}\"\nPF=\"${PF:-pf}\"\ncommand -v \"$PF\" >/dev/null || PF=\"$(pwd)/clients/pf-cli/target/release/pf\"\n\nROOT=\"$(mktemp -d \"${TMPDIR:-/tmp}/pf-aleo-video.XXXXXX\")\"\necho \"demo root: $ROOT\"\ncd \"$ROOT\"\n\n\"$PF\" setup --target aleo\n\"$PF\" new hello --target aleo\ncd hello\n\"$PF\" build\n\"$PF\" run -- initialize 5u64\n\"$PF\" run -- increment 3u64\n\"$PF\" deploy --network testnet\n\"$PF\" execute --network testnet -- initialize 5u64\necho \"SAVE-ONLY OK — artifacts under $ROOT/hello/build/aleo/\"\nls -la build/aleo/tx/\n```\n\nSave as `scripts/demo_aleo_testnet_save_only.sh` in the monorepo (optional) and run before filming.\n\n---\n\n## Broadcast checklist (day of shoot)\n\n- [ ] Fresh shell; `echo $PF_ALEO_TESTNET_KEY` is set **off camera**  \n- [ ] Key is **not** the Leo well-known dev key  \n- [ ] Balance > fee on testnet  \n- [ ] Screen recording hides any env dump / shell history  \n- [ ] Plan B if faucet is down: film save-only only, show JSON + explorer docs  \n\n---\n\n## If something fails\n\n| Symptom | Fix |\n|---|---|\n| `proof-forge-next` missing | `export PROOF_FORGE_CLI=…` or monorepo lake build |\n| `leo not found` | install Leo 4.x; `pf setup --target aleo` |\n| deploy twin mismatch | template must stay StateCell-shaped (`pf new` default) |\n| broadcast refused well-known key | use a real testnet key in env |\n| broadcast fee / network error | check endpoint, balance, Leo version |\n| want quieter Leo | default `pf run` is quiet; `-v` for full log |\n\n---\n\n## Non-goals for this video\n\n- Mainnet  \n- Non–StateCell-shaped Aleo programs (twin registry only `statecell-v1` today)  \n- Claiming formal verification or “production ready”  \n- Showing private keys or seed phrases  \n\n## CLI recording tools (what we use)\n\n| Tool | Role | Install |\n|---|---|---|\n| **asciinema** | Terminal session cast (best for CLI demos) | `brew install asciinema` |\n| **ffmpeg** | Optional screen MP4 from desktop | `brew install ffmpeg` |\n| **script(1)** | Plain typescript log | preinstalled on macOS |\n\n### One-command record (save-only)\n\n```bash\nexport PROOF_FORGE_CLI=\"$PWD/.lake/build/bin/proof-forge-next\"\njust pf-cli-aleo-record\n# → build/demos/aleo/pf-aleo-demo-*.cast\nasciinema play build/demos/aleo/pf-aleo-demo-*.cast\n# optional public share:\n# asciinema upload build/demos/aleo/pf-aleo-demo-*.cast\n# published public recording: https://asciinema.org/a/1262697\n```\n\n### Real Testnet broadcast record\n\n1. Create account (off camera): `leo account new`  \n2. Fund via **https://faucet.aleo.org/** (captcha — human only; ~3+ credits for deploy)  \n3. Load key into env (never echo):\n\n```bash\nexport PF_ALEO_TESTNET_KEY='APrivateKey1…'   # funded testnet key\nexport PF_ALEO_BROADCAST=1\njust pf-cli-aleo-record\n```\n\nDeploy fee observed in rehearsal: **~3.04 credits** (namespace + storage + synthesis).\n\nWithout faucet funds, broadcast correctly fails with insufficient balance after building the deployment plan — still useful footage.\n\n### Optional desktop MP4 (macOS)\n\n```bash\n# Capture main display while you run the demo in Terminal (large font)\nffmpeg -f avfoundation -i \"2:none\" -r 30 -t 600 build/demos/aleo/screen.mp4\n```\n\n(`2` = “Capture screen 0” from `ffmpeg -f avfoundation -list_devices true -i \"\"`)\n\n## Related\n\n- `clients/pf-cli/README.md`  \n- `docs/specs/cli-developer.md` § Aleo  \n- `scripts/demo_aleo_record.sh` / `scripts/demo_aleo_testnet_save_only.sh`  \n- `scripts/aleo_instructions_network_tx_acceptance.sh` (CI gate; save-only default)\n\n## Remote MCP (agents)\n\nProofForge also ships a **public remote MCP** (Cloudflare Workers), for coding agents (Streamable HTTP):\n\n- Landing: https://proof-forge-mcp.davirain-yin.workers.dev/\n- Endpoint: `https://proof-forge-mcp.davirain-yin.workers.dev/mcp`\n- Tool for this demo: `pf_aleo_live_demo`\n\n```bash\ncodex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n```\n\nEdge MCP is docs/catalog/guidance only — compile and Testnet broadcast still run via local `pf`.\n\n",
  "evm-local-walkthrough.md": "---\nid: DEMO-EVM-LOCAL-WALKTHROUGH\ntitle: Demo — EVM with pf (build → Anvil deploy → browser UI)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Demo: EVM with `pf` — build → local Anvil → browser\n\n**Audience:** video / hackathon  \n**Time:** ~8–12 minutes  \n**Claims:** engineering demo only — **not** formal / hermetic / mainnet / public broadcast  \n\n## Shot list\n\n### 1) Build\n\n```bash\nexport PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next\npf build Examples/StateCell.lean --module Examples.StateCell -t evm -o build/v2/sc-ui\nls build/v2/sc-ui/\n# StateCell.abi.json  StateCell.bin  StateCell.yul  manifest.json\n```\n\n### 2) One-shot local demo (recommended)\n\n```bash\nbash scripts/pf_evm_local_demo.sh\n# starts Anvil, deploys ctor(7), writes templates/evm-dapp-ui/public/deployment.json\n# leave running\n```\n\n### 3) UI\n\n```bash\ncd templates/evm-dapp-ui\nnpm install\nnpm run dev\n# http://127.0.0.1:5174\n```\n\nMetaMask → add network (RPC/port/chainId printed by script) → Connect → Refresh get() → increment(5) → get()==12.\n\n### 4) Safety on camera\n\n- Local Anvil only  \n- Anvil #0 key is a **well-known demo key** — never mainnet  \n- `pf deploy --network testnet --broadcast` for EVM is **refused** in v0  \n\n## Manual cast path (optional)\n\n```bash\nanvil --port 8545 &\nBYTECODE=$(tr -d '\\n' < build/v2/sc-ui/StateCell.bin)\nENC=$(cast abi-encode 'constructor(uint64)' 7)\ncast send --rpc-url http://127.0.0.1:8545 \\\n  --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \\\n  --create \"0x${BYTECODE}${ENC#0x}\"\n```\n\n## Related\n\n- `docs/product/08-evm-dapp-frontend.md`  \n- `templates/evm-dapp-ui/`  \n- `scripts/pf_evm_test.sh`  \n",
  "mcp-stdio-readme.md": "# ProofForge MCP-V0\n\nMinimal **stdio** MCP server that exposes product CLI tools for Code Agents.\n\nAuthority: [`docs/product/01-toolchain-install-surface.md`](../../docs/product/01-toolchain-install-surface.md) §8.\n\n## Tools\n\n| Tool | CLI mapping |\n|---|---|\n| `pf_list_targets` | `proof-forge-next list-targets [--all] --json` |\n| `pf_doctor` | `proof-forge-next doctor --json` |\n| `pf_install` | `proof-forge-next install --targets … --yes --json` |\n| `pf_build` | `proof-forge-next build <source> --module … --target … -o … --json` |\n| `pf_artifacts` | `proof-forge-next inspect --output-dir <dir> --json` |\n| `pf_local` | `proof-forge-next local --target … [--mode sandbox] -- --source … --module … [--root …]` |\n| `pf_chain_catalog` | static `docs/product/chain-client-catalog.v1.json` (client/frontend metadata) |\n| `pf_network_info` | static `docs/product/networks.v1.json` (Anvil / X Layer / placeholders) |\n| `pf_onchainos_guide` | OKX OnchainOS dual-MCP map + P0–P2 (from networks catalog ecosystems) |\n\n- **No** default network broadcast tool (use product CLI `network --broadcast` explicitly if needed).\n- Aleo `pf_local` is **generic**: requires `source` + `module`; optional `root` / `runs` / `golden` / `skipRun` — no default program. When `root` is provided it is passed through as product `--root` after `--`, so repo-external source paths resolve against that project root.\n- Hello agent playbook: [`docs/product/03-hello-dapp-agent-playbook.md`](../../docs/product/03-hello-dapp-agent-playbook.md).\n- X Layer / OnchainOS: [`docs/product/13-xlayer-onchainos.md`](../../docs/product/13-xlayer-onchainos.md). DEX quotes use **official** `https://web3.okx.com/api/v1/onchainos-mcp` (not this server).\n- Tools **only** spawn the product CLI / package engines (except catalog tools, which read package JSON); they do **not** reimplement solc/leo/nargo.\n- Tool Lock installs never use PATH fallback into `PROOF_FORGE_TOOL_ROOT`.\n- Success is **not** formal / hermetic / mainnet / `deployable=true` evidence.\n\n## Prerequisites\n\n```bash\n# From package root\nlake build          # produces .lake/build/bin/proof-forge-next\n# Optional: install toolchain assets for a target\n./.lake/build/bin/proof-forge-next install --targets quint --yes\n```\n\n## Agent wiring (Cursor / Claude Desktop / other MCP hosts)\n\n```json\n{\n  \"mcpServers\": {\n    \"proof-forge\": {\n      \"command\": \"/usr/bin/python3\",\n      \"args\": [\n        \"-I\",\n        \"/absolute/path/to/proof_forge/tools/mcp/proof_forge_mcp_server.py\"\n      ],\n      \"env\": {\n        \"PROOF_FORGE_ROOT\": \"/absolute/path/to/proof_forge\",\n        \"PROOF_FORGE_CLI\": \"/absolute/path/to/proof_forge/.lake/build/bin/proof-forge-next\",\n        \"PROOF_FORGE_TOOL_ROOT\": \"/absolute/path/to/tool-root/linux-x86_64\"\n      }\n    }\n  }\n}\n```\n\nNotes:\n\n- `PROOF_FORGE_ROOT` must contain `scripts/proof_forge_doctor.py` (package root).\n- `PROOF_FORGE_CLI` is optional if `.lake/build/bin/proof-forge-next` exists under the root.\n- Inherit or set `PROOF_FORGE_TOOL_ROOT` so doctor/install/build see locked tools (never PATH fallback).\n\n## Self-check / smoke\n\n```bash\n/usr/bin/python3 -I tools/mcp/proof_forge_mcp_server.py --self-check\nscripts/mcp_smoke.sh\n```\n\n## Design boundaries\n\n- Package is stdlib-only Python (no extra pip dependency).\n- `pf_install` always passes `--yes` unless `dryRun=true` (non-interactive).\n- `pf_build` rejects `broadcast` / `network` arguments.\n- Design-only targets (`soroban`, `icp`, `openvm`) remain unsupported for install.\n\n## Remote MCP (Cloudflare Workers)\n\nPublic Streamable HTTP endpoint (Solana-style remote MCP):\n\n| | |\n|---|---|\n| Landing | https://proof-forge-mcp.davirain-yin.workers.dev/ |\n| Health | https://proof-forge-mcp.davirain-yin.workers.dev/health |\n| MCP | `https://proof-forge-mcp.davirain-yin.workers.dev/mcp` |\n| Source | `clients/pf-mcp/` |\n\n```bash\n# Codex\ncodex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n\n# Claude Code\nclaude mcp add --transport http proof-forge-mcp https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n\n# Generic local proxy\nnpx -y mcp-remote https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n```\n\n**Edge tools (guidance only):** `pf_health`, `pf_list_docs`, `pf_get_doc`, `pf_search_docs`,\n`pf_chain_catalog`, `pf_network_info`, `pf_onchainos_guide`, `pf_target_info`, `pf_agent_instructions`,\n`pf_cli_cheatsheet`, `pf_aleo_live_demo`, `pf_solana_scaffold`, `pf_solana_ix_codec`, `pf_solana_artifacts`.\n\nThe remote Worker **does not** spawn Lean/CLI, hold keys, or broadcast. Local compile/deploy still uses\nthis stdio server or the `pf` CLI.\n\n\n## Solana (ProofForge path)\n\nRemote MCP tools: `pf_solana_scaffold`, `pf_solana_ix_codec`, `pf_solana_artifacts`.\nFrontend template: `templates/solana-dapp-ui`.\nContracts: ProgramV1 + `pf build --target solana` (not Anchor-first).\n",
  "psy-dpn-walkthrough.md": "---\nid: DEMO-PSY-DPN-WALKTHROUGH\ntitle: Demo — Psy DPN with pf (+ official ecosystem pointers)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Demo: Psy with ProofForge `pf`（DPN emission）\n\n**Claims:** engineering only — PF stops at canonical DPN; deploy/prove/wallet are official Psy tools  \n**Time:** ~5 minutes (PF) · optional +N minutes on official WebIDE/wallet\n\n## What this proves\n\n| Step | Viewers see |\n|---|---|\n| 1 Setup | `pf setup --target psy` (zero-tool) |\n| 2 Build | `pf build -t psy` → `StateCell.dpn.json` |\n| 3 Inspect | method_id / state_commands / manifest `deployable=false` |\n| 4 Ecosystem | open config / explorer / IDE / wallet (no PF private key) |\n\n## Safety\n\n1. Default `pf deploy` is **save-only**; `--broadcast` wraps official `deploy-contract --is-deploy` (testnet/local).  \n2. Do **not** paste private keys into chat, slides, or git.  \n3. Success ≠ mainnet / formal readiness.  \n4. Public endpoints from `config.psy-protocol.xyz` **drift** — refresh live JSON.\n\n---\n\n## Shot list\n\n### 1) Tooling\n\n```bash\nexport PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next\nexport PATH=\"$HOME/.cargo/bin:$PATH\"\npf setup --target psy\npf doctor --target psy\n# expect: psy status=ok, tools=[]\n```\n\n### 2) Build DPN\n\n```bash\npf build Examples/StateCell.lean \\\n  --module Examples.StateCell \\\n  --target psy \\\n  -o build/v2/sc-psy\n\nls -la build/v2/sc-psy/\n# StateCell.dpn.json  manifest.json  evidence.json\n```\n\n**Say:** “Sole profile `psy-dpn-v1`. No Dargo source, no local VM in PF.”\n\n### 3) Peek package\n\n```bash\njq '.[].name, .[].method_id' build/v2/sc-psy/StateCell.dpn.json\njq '{target,codegenProfile,deployable,files}' build/v2/sc-psy/manifest.json\n```\n\nExpected shape: array of function circuit defs (`get` / `increment` / `initialize`).\n\n\n\n\n> **Session continuity:** `psy_user_cli simulate` is **one call per process** (fresh memory).\n> For `init(7) → increment(5) → get = 12`, use `scripts/psy_dpn_session.py` / `pf test -t psy`\n> (shared-state harness). Do not expect three separate simulates to accumulate.\n\n### 3b) Local VM via official `psy_user_cli simulate` (now wired)\n\n```bash\n# one-shot monorepo smoke\njust psy-dpn-local-smoke\n# or:\nexport PATH=\"$HOME/.psy/bin:$PATH\"\npf build Examples/StateCell.lean --module Examples.StateCell --target psy -o build/v2/sc-psy\npf test -t psy --artifact build/v2/sc-psy\npf run -t psy --artifact build/v2/sc-psy -- initialize 7\npf run -t psy --artifact build/v2/sc-psy -- increment 5\n```\n\n**Honesty:** each `simulate` uses a **fresh** in-memory state (no multi-tx session).  \nThis is the official DPN VM, not a PF-written interpreter. Not UPS/proof/network.\n\n### 4) Official surfaces (browser)\n\n| Open | Why |\n|---|---|\n| https://config.psy-protocol.xyz | live RPC + L1 Sepolia addresses |\n| https://explorer.psy-protocol.xyz | chain observability |\n| https://ide.psy-protocol.xyz | write/compile Psy-lang in browser |\n| https://app.psy-protocol.xyz/#/wallet | wallet UX |\n| https://docs.psy-protocol.xyz | language · SDK · VM · RPC |\n\nOptional developer machine:\n\n```bash\ncurl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh \\\n  | PSYUP_DEFAULT_NETWORK=sepolia sh\npsyup install\n# psyup new demo && cd demo && psyup build\n# deploy remains official: psyup deploy (funded key / keystore)\n```\n\n### 5) Closing line\n\n> ProofForge ships **verifiable DPN packages** from a shared ProgramV1.  \n> Psy official stack ships **language, prove, deploy, wallet**.  \n> We integrate at the package boundary — we don’t fake a second Psy compiler inside PF.\n\n## Related\n\n- `docs/product/11-psy-agent-playbook.md`  \n- `docs/product/12-psy-dapp-frontend.md`  \n- `docs/targets/10-psy.md`  \n",
  "solana-local-walkthrough.md": "---\nid: DEMO-SOLANA-LOCAL-WALKTHROUGH\ntitle: Demo — Solana with pf (build → Surfpool → UI)\nstatus: draft\nowner: product+engineering\nupdated: 2026-08-10\nnormative: false\n---\n\n# Demo: Solana with ProofForge `pf` + Surfpool\n\n**Claims:** engineering only — not formal / hermetic / public broadcast\n\n## MCP（只要 PF）\n\n```bash\ncodex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp\n# tools: pf_solana_scaffold · pf_solana_ix_codec · pf_solana_artifacts\n```\n\n## Shot list（推荐一键）\n\n### 0) Tooling\n\n```bash\nexport PATH=\"$HOME/.local/bin:$HOME/.local/share/solana/install/active_release/bin:$HOME/.cargo/bin:$PATH\"\nexport PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next\n# surfpool 1.x preferred over cargo-installed 0.10.x\nsurfpool --version\nsolana --version\npf setup --target solana && pf doctor --target solana\n```\n\nOptional solders venv (for create-account + invoke helper):\n\n```bash\npython3 -m venv /tmp/pf-sol-venv\n/tmp/pf-sol-venv/bin/pip install 'solders>=0.21'\n```\n\n### 1) One command: build → verify → Surfpool deploy → init\n\n```bash\njust pf-solana-local-demo\n# or: bash scripts/pf_solana_local_demo.sh\n```\n\nExpected:\n\n- offline `pf verify` ok  \n- Surfpool RPC (e.g. `http://127.0.0.1:19422`)  \n- program deploy + StateCell `init(7)` + `increment(5)` + `get`  \n- account count **12** at offset 8  \n- writes `templates/solana-dapp-ui/public/deployment.json`\n\nSurfpool stays up by default (`PF_SOLANA_DEMO_KEEP=0` to tear down).\n\n### 2) Frontend\n\n```bash\ncd templates/solana-dapp-ui && npm install && npm run dev\n# wallet → custom RPC from deployment.json\n# entry/view only (init already done by script; needs state signer)\n```\n\n### 3) Manual ladder (without one-shot)\n\n```bash\npf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol\npf verify --target solana -o build/v2/sc-sol\njust solana-surfpool-up\n# pf deploy --network local --broadcast --endpoint <rpc> …\n# python3 scripts/pf_solana_statecell_invoke.py --rpc … --idl … --init 7 --delta 5\n```\n\n### 4) Encoding reminder\n\nBody-only (this demo):\n\n```text\ndisc = sha256(\"proof-forge-solana-v1:initialize(u64)\")[0:8]   # not handlerId\nstate = [marker u64 | count u64]   # count @ offset 8\n```\n\n### 5) Safety\n\n- No public Solana RPC broadcast in pf v0  \n- No keys in MCP/git  \n- Success ≠ mainnet readiness  \n- Tear down: `just solana-surfpool-down`\n\n## Related\n\n- `docs/product/09-solana-agent-playbook.md`  \n- `docs/product/10-solana-dapp-frontend.md`  \n- `templates/solana-dapp-ui/`  \n- `scripts/pf_solana_local_demo.sh`  \n",
};

