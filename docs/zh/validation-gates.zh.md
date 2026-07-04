# 验证门禁

本页面记录了当前验证 ProofForge 的可运行门禁，并将其与计划中但尚未实现的门禁区分开来。它反映了实际的脚本、根目录 `justfile` recipe 和 `.github/workflows/ci.yml`；它不会添加或编辑 CI 任务。

## 当前门禁

| 门禁 | 命令 | 前提条件 | 证明了什么 | 未证明什么 |
|---|---|---|---|---|
| 统一 testkit 场景 | `just testkit` | Rust/Cargo；来自 `lean-toolchain` 的 Lean 工具链；EVM bytecode 分支需要 `solc`；ValueVault EVM 分支的 Contract SDK selector hydration 需要 Foundry `cast`；Solana/Mollusk 分支可选依赖 `sbpf` 和 `solana-keygen` | RFC 0007 testkit 会发现 `testkit/scenarios/counter.toml` 和 `testkit/scenarios/value-vault.toml`，通过 Lean 发射 WAT fixture 并在确定性的 `runtime/offline-host` wasmtime NEAR host 上运行；当所需 EVM 工具可用时，发射 EVM runtime bytecode 与 artifact metadata，并在进程内 `revm` 上运行覆盖到的场景；如果 Solana 工具链可用，还会发射 Solana sBPF assembly/manifest/artifact metadata、构建 sBPF ELF，并通过 `mollusk-svm` 运行有状态场景；同时校验 scenario-declared artifact expectation，包括 Counter 在 Wasm/NEAR WAT、EVM Yul 和 Solana assembly/manifest 上的 golden source equality、ValueVault 在 Wasm/NEAR WAT、EVM Yul 以及 Solana sBPF assembly/manifest 上的 golden equality、结构化 JSON/TOML metadata/manifest path 断言（包括存在性、缺失性、类型、非空，以及 array/object/table/string length 检查）、EVM deploy manifest schema 检查、针对生成 artifact path/byte-size/SHA-256 entry 的 JSON metadata file-reference 检查、内嵌 Solana IDL metadata 的 cross-artifact JSON equality，以及 ValueVault IDL/client shape 检查；最后校验每个 target 的返回期望，并对已执行 target 断言规范化 observable trace parity | live NEAR sandbox 部署、live EVM RPC/deployment 行为、Surfpool/Web3 Solana 部署行为、替换所有旧的逐目标 smoke 脚本、event/log/gas/compute-budget parity |
| Lean 包构建 | `lake build` | 来自 `lean-toolchain` 的 Lean 工具链 | 库根节点通过类型检查且 `proof-forge` 链接成功 | 生成的 Yul/字节码有效性、外部工具、运行时行为 |
| 目标注册表冒烟测试 | `lake env lean --run Tests/TargetRegistry.lean` | 来自 `lean-toolchain` 的 Lean 工具链 | 目标注册表将 `evm` 暴露为 compiler target，同时让 `robinhood-chain-testnet` 和 `anvil-local` 等 EVM-compatible chain profile 只作为 lookup-only deployment profile 存在 | 交易广播、实时 RPC 或 explorer 可达性、wallet 集成 |
| EVM 语义计划冒烟测试 | `just evm-plan` | 来自 `lean-toolchain` 的 Lean 工具链 | EVM semantic plan 会从 target 已解析的 `CapabilityPlan` 构建，拒绝非 EVM target plan，并在 Yul 生成前校验 storage layout、scalar storage slot、map value slot、nested map value slot、map presence slot、map assign-op helper 需求以及计划出的 helper 需求 | ABI dispatch、event、crosscall、constructor metadata、artifact metadata 完全归入 `ModulePlan`、`solc` 验收、字节码、运行时行为、更广泛的 aggregate storage planning |
| EVM 语义计划（entrypoints/events/metadata）冒烟测试 | `just evm-semantic-plan` | 来自 `lean-toolchain` 的 Lean 工具链 | 已填充的 `ModulePlan` 携带 `EntrypointPlan`（selector、ABI params、return plan）、`EventPlan`（signature、indexed/data fields）、crosscall/create helper spec、checked-arithmetic 标记和 `MetadataPlan`；artifact/deploy 元数据从计划构建，不回退到 Yul 反推 | 完整 `StmtPlan`/`ExprPlan` body lowering、plan-driven optimizer、`.evm-plan.json` snapshot |
| Solana light gates | `just solana-light` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；portable ValueVault EVM selector-hydration/Yul 分支可选依赖 `cast`；其 strict-assembly 与 EVM bytecode metadata 分支可选依赖 `solc` 加 `cast`；Solana SDK build 分支可选依赖 `sbpf` 和 `solana-keygen` | Solana target diagnostics、SDK metadata、SDK manifest、生成的 Solana IDL 与 TypeScript client artifacts、Counter 和 portable ValueVault 的 Contract Source Syntax v1 routing/render checks、Learn source lowering equivalence，以及针对 CPI/PDA/state helper 错误的 Learn reference diagnostics、typed account declaration metadata、CPI packing、log lowering、target routing、portable ValueVault Learn-source CLI emission 到 EVM Yul 与 Solana sBPF assembly/manifest/IDL/client artifact metadata、token spec、return-data/compute-units SDK helpers、Counter sBPF golden assembly/manifest diff、control-flow/assertion assembly emission、SDK extension artifact metadata、CI-safe Pinocchio System/SPL Token reference-equivalence suite，以及存在 `sbpf` 时的 canned sBPF emission | 完整 Mollusk runtime 覆盖、Surfpool/Web3 部署冒烟、公共 validator 部署、Solana transaction UX、live Pinocchio dual-deploy equivalence |
| Token SDK plan smoke | `just learn-token-smoke` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；EVM bytecode 分支可选依赖 `solc`；Web3.js validation 可选依赖 Node 和 npm | 验证 legacy `.learn` token 路径会进入 Lean `TokenSpec` 边界；存在 `solc` 时发射 ERC-20 Yul/bytecode metadata；发射结构化 Solana SPL Token 与 Token-2022 plan JSON；检查 mint/ATA/`mint_to`/`transfer_checked`/`approve`/`burn`/`revoke`/authority-change plan entry；检查 Token-2022 transfer-fee extension routing 和 withheld-fee collection plan entry；存在 Node/npm 时用 `@solana/spl-token` / `@solana/web3.js` instruction builder 离线验证 Solana plan | 所有 token plan variant 的 Surfpool live 执行、真实 token balance、公共 validator 部署、wallet UX、生成 wrapper/transfer-hook program |
| Solana token plan Surfpool/Web3.js smoke | `just solana-token-plan-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；`surfpool`；Solana CLI 和 `solana-keygen`；Node；npm | 发射结构化 SPL Token plan，启动 Surfpool，通过 `@solana/spl-token` 创建 mint 和 associated token account，mint initial supply，执行计划中的 `mint_to`、`transfer_checked`、`approve`、`burn`、`revoke` 和 mint-authority `set_authority`，再通过 Web3.js 读取验证 token balance、supply、delegate state 和 authority revoke | Token-2022 extension 行为、生成 wrapper/transfer-hook program、公共 validator 部署、wallet UX |
| Solana Token-2022 transfer-fee Surfpool/Web3.js smoke | `just solana-token-2022-transfer-fee-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；`surfpool`；Solana CLI 和 `solana-keygen`；Node；npm | 发射结构化 Token-2022 transfer-fee plan，启动 Surfpool，初始化带 `TransferFeeConfig` 的 mint，创建 Token-2022 associated token accounts，mint initial supply，执行 `TransferCheckedWithFee`，验证 source balance、recipient net balance 和 recipient withheld fee，直接从 token account withdraw withheld fee；然后执行第二次 transfer，harvest withheld fee 到 mint，再从 mint withdraw，并通过 Web3.js 验证 fee receiver balance 与已清空的 withheld amount | confidential transfer setup、transfer-hook routing、生成 wrapper/transfer-hook program、公共 validator 部署、wallet UX |
| Solana Token-2022 non-transferable Surfpool/Web3.js smoke | `just solana-token-2022-non-transferable-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；`surfpool`；Solana CLI 和 `solana-keygen`；Node；npm | 从 Lean `.lean` token fixture 发射结构化 Token-2022 plan，启动 Surfpool，初始化带 `NonTransferable` 的 mint，创建 Token-2022 associated token accounts，mint initial supply，验证 mint/account extension，证明 `TransferChecked` 会以 `Transfer is disabled for this mint` 被拒绝，然后 burn token 并验证 balance 与 supply | confidential transfer setup、transfer-hook routing、生成 wrapper/transfer-hook program、公共 validator 部署、wallet UX |
| Solana PDA Web3.js derivation smoke | `just solana-pda-web3` | 来自 `lean-toolchain` 的 Lean 工具链；Node；npm | 发射 Solana SDK Vault artifact，读取 PDA `typedSeeds`，并用 `@solana/web3.js` 的 `PublicKey.findProgramAddressSync` 和 `PublicKey.createProgramAddressSync` 校验 literal/account/bump descriptor 语义；同时覆盖本地 UTF-8 与 instruction-parameter seed descriptor resolver | live deployment 或 transaction execution；SPL Token CPI 行为 |
| Solana System CPI Surfpool/Web3.js smoke | `just solana-system-cpi-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 System Program transfer CPI ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用程序，验证 recipient lamports 按请求数增加，并验证 program-owned state account 记录了同一 lamports 值 | System create-account CPI、SPL Token CPI 行为、公共 validator 部署、Rust/Pinocchio 等价性 |
| Solana System create_account CPI Surfpool/Web3.js smoke | `just solana-system-create-account-cpi-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 System Program `create_account` CPI ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用，验证新建 account 的 owner/space/lamports，并验证 program-owned state account 记录了请求的 lamports 和 space | SPL Token CPI 行为、公共 validator 部署、live Rust/Pinocchio 等价性 |
| Solana SPL Token transfer_checked CPI Surfpool/Web3.js smoke | `just solana-spl-token-transfer-cpi-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 SPL Token `transfer_checked` CPI ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/spl-token` 创建 mint 和 token accounts，通过 `@solana/web3.js` 调用生成程序，验证 source/destination token balance，并验证 program-owned state account 记录了请求的 amount | 更广泛的 SPL Token/Token-2022 覆盖、公共 validator 部署、live Rust/Pinocchio 等价性 |
| Solana SPL Token ops CPI Surfpool/Web3.js smoke | `just solana-spl-token-ops-cpi-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/spl-token` 创建 mint 和 token accounts，通过 `@solana/web3.js` 调用生成程序，验证 mint supply 与 token balance 变化，验证 delegate allowance 后再 revoke 清空，并验证 program-owned state account 记录所有请求值 | Token-2022 extension 行为、公共 validator 部署 |
| Solana SPL Token authority CPI Surfpool/Web3.js smoke | `just solana-spl-token-authority-cpi-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 SPL Token `set_authority` CPI ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/spl-token` 创建 mint，通过 `@solana/web3.js` 调用生成程序，验证 mint authority 已转移到请求的新 authority，并验证 program-owned state account 记录 marker | Token-2022 extension 行为、公共 validator 部署 |
| Solana Pinocchio reference-equivalence suite | `just solana-pinocchio-reference-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时可选依赖 `cargo` | 运行下面五个 CI-safe Pinocchio reference-equivalence smoke，并已纳入 `just solana-light` / 默认 CI `build-test` job | live dual-deploy equivalence、Pinocchio reference ELF 构建 |
| Solana Pinocchio System transfer reference-equivalence smoke | `just solana-pinocchio-system-transfer-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时可选依赖 `cargo` | emit 生成的 System Program transfer CPI source/artifact metadata，并将 instruction ABI、account order、signer/writable requirement、CPI metadata 和 lamports state write contract 与 `references/solana/pinocchio/system-transfer` 下 checked-in Pinocchio reference manifest/source 对比 | 构建/部署 Pinocchio reference ELF，并让 ProofForge/reference programs 通过同一个 Web3.js harness 对比 |
| Solana Pinocchio System create_account reference-equivalence smoke | `just solana-pinocchio-system-create-account-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时可选依赖 `cargo` | emit 生成的 System Program `create_account` CPI source/artifact metadata，并将 instruction ABI、account order、signer/writable requirement、CPI metadata、lamports/space/owner layout 和双字段 state-write contract 与 `references/solana/pinocchio/system-create-account` 下 checked-in Pinocchio reference manifest/source 对比；可选 Cargo check 会用 `pinocchio-system` typecheck 该 reference | 构建/部署 Pinocchio create_account reference ELF，并让 ProofForge/reference programs 通过同一个 Web3.js harness 对比 |
| Solana Pinocchio SPL Token transfer reference-equivalence smoke | `just solana-pinocchio-spl-token-transfer-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时可选依赖 `cargo` | emit 生成的 SPL Token `transfer_checked` CPI source/artifact metadata，并将 instruction ABI、account order、signer/writable requirement、CPI metadata、decimals/amount layout 和 amount state-write contract 与 `references/solana/pinocchio/spl-token-transfer` 下 checked-in Pinocchio reference manifest/source 对比；可选 Cargo check 会用 `pinocchio-token` typecheck 该 reference | 构建/部署 Pinocchio SPL Token reference ELF，并让 ProofForge/reference programs 通过同一个 Web3.js harness 对比 |
| Solana Pinocchio SPL Token ops reference-equivalence smoke | `just solana-pinocchio-spl-token-ops-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时可选依赖 `cargo` | emit 生成的 SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI source/artifact metadata，并将四个 instruction ABI、共享 account order、signer/writable requirement、CPI metadata、SPL Token instruction layout 和 state-write contract 与 `references/solana/pinocchio/spl-token-ops` 下 checked-in Pinocchio reference manifest/source 对比；可选 Cargo check 会用 `pinocchio-token` typecheck 该 reference | 构建/部署 Pinocchio SPL Token ops reference ELF，并让 ProofForge/reference programs 通过同一个 Web3.js harness 对比 |
| Solana Pinocchio SPL Token authority reference-equivalence smoke | `just solana-pinocchio-spl-token-authority-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；`python3`；设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时可选依赖 `cargo` | emit 生成的 SPL Token `set_authority` CPI source/artifact metadata，并将 instruction ABI、account order、signer/writable requirement、CPI metadata、`SetAuthority` instruction layout 和 marker state-write contract 与 `references/solana/pinocchio/spl-token-authority` 下 checked-in Pinocchio reference manifest/source 对比；可选 Cargo check 会用 `pinocchio-token` typecheck 该 reference | 构建/部署 Pinocchio SPL Token authority reference ELF，并让 ProofForge/reference programs 通过同一个 Web3.js harness 对比 |
| Solana Pinocchio System transfer live-equivalence smoke | `just solana-pinocchio-system-transfer-live-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；带 Solana rustc/platform-tools 的 `cargo-build-sbf`；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建 ProofForge System transfer CPI ELF 和 checked-in Pinocchio reference ELF，将两个程序部署到同一个 Surfpool instance，用同一个 Web3.js transfer scenario 分别调用，并对比 recipient lamport delta 和 state 记录值 | 在 Solana rustc 可稳定安装后纳入 CI；将 Pinocchio 对比扩展到 Token-2022 和更广 SPL helper 覆盖；`just solana-pinocchio-install-sbf-tools` 可修复缺失/损坏的 platform-tools |
| Solana Pinocchio System create_account live-equivalence smoke | `just solana-pinocchio-system-create-account-live-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；带 Solana rustc/platform-tools 的 `cargo-build-sbf`；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建 ProofForge System `create_account` CPI ELF 和 checked-in Pinocchio reference ELF，将两个程序部署到同一个 Surfpool instance，用同一个 Web3.js create-account scenario 分别调用，并对比 lamports/space 以及 state 记录值 | 在 Solana rustc 可稳定安装后纳入 CI；将 Pinocchio 对比扩展到 Token-2022 和更广 SPL helper 覆盖；`just solana-pinocchio-install-sbf-tools` 可修复缺失/损坏的 platform-tools |
| Solana Pinocchio SPL Token transfer live-equivalence smoke | `just solana-pinocchio-spl-token-transfer-live-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；带 Solana rustc/platform-tools 的 `cargo-build-sbf`；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建 ProofForge SPL Token `transfer_checked` CPI ELF 和 checked-in Pinocchio reference ELF，将两个程序部署到同一个 Surfpool instance，用同一个 Web3.js token-transfer scenario 分别调用，并对比 token balance delta 和 state 记录值 | 在 Solana rustc 可稳定安装后纳入 CI；将 Pinocchio 对比扩展到 Token-2022 和更广 SPL helper 覆盖；`just solana-pinocchio-install-sbf-tools` 可修复缺失/损坏的 platform-tools |
| Solana Pinocchio SPL Token ops live-equivalence smoke | `just solana-pinocchio-spl-token-ops-live-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；带 Solana rustc/platform-tools 的 `cargo-build-sbf`；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建 ProofForge SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI ELF 和 checked-in Pinocchio reference ELF，将两个程序部署到同一个 Surfpool instance，用同一个 Web3.js token-ops scenario 分别调用，并对比 mint/burn/approve/revoke token effect 和 state 记录值 | 在 Solana rustc 可稳定安装后纳入 CI；将 Pinocchio 对比扩展到 Token-2022 和剩余 SPL helper 覆盖；`just solana-pinocchio-install-sbf-tools` 可修复缺失/损坏的 platform-tools |
| Solana Pinocchio SPL Token authority live-equivalence smoke | `just solana-pinocchio-spl-token-authority-live-equivalence` | 来自 `lean-toolchain` 的 Lean 工具链；带 Solana rustc/platform-tools 的 `cargo-build-sbf`；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建 ProofForge SPL Token `set_authority` CPI ELF 和 checked-in Pinocchio reference ELF，将两个程序部署到同一个 Surfpool instance，用同一个 Web3.js mint-authority transfer scenario 分别调用，并对比 mint authority 与 state marker | 在 Solana rustc 可稳定安装后纳入 CI；将 Pinocchio 对比扩展到 Token-2022 和剩余 SPL helper 覆盖；`just solana-pinocchio-install-sbf-tools` 可修复缺失/损坏的 platform-tools |
| Solana log/event Surfpool/Web3.js smoke | `just solana-log-event-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 `events.emit`/Solana log-extension ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用生成程序，验证 `sol_log_64_` transaction logs 包含稳定 event tag 和 scalar field value，验证 program-owned state account 记录了同一个值，验证 `sol_log_pubkey` 会记录 state account 的 base58 pubkey，并验证 `sol_log_data` 会为 state bytes 产出 base64 `Program data:` payload | Anchor-compatible discriminator/Borsh event serialization、indexed events、`sol_log_` payload、历史索引保证 |
| Solana Clock sysvar Surfpool/Web3.js smoke | `just solana-clock-sysvar-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 `contextRead checkpointId` ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用生成程序，验证 `sol_get_clock_sysvar` 将 `Clock.slot` 记录进 program-owned state，并与 transaction slot metadata 对比 | 更丰富的 Clock fields、公共 validator 部署 |
| Solana Rent sysvar Surfpool/Web3.js smoke | `just solana-rent-sysvar-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 Solana-only `sysvar` target-extension ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用生成程序，验证 `sol_get_rent_sysvar` 将 `Rent.lamports_per_byte_year` 记录进 program-owned state，并与 Rent sysvar account data 对比 | 更多 Rent fields、公共 validator 部署 |
| Solana EpochSchedule sysvar Surfpool/Web3.js smoke | `just solana-epoch-schedule-sysvar-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 Solana-only `sysvar` target-extension ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用生成程序，验证 `sol_get_epoch_schedule_sysvar` 将当前 RPC 暴露的 5 个 `EpochSchedule` 字段记录进 program-owned state，并与 RPC `getEpochSchedule()` 对比 | 更多 Clock/Rent 字段、generic account-passed sysvar 读取、公共 validator 部署 |
| Solana EpochRewards sysvar Surfpool/Web3.js smoke | `just solana-epoch-rewards-sysvar-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 Solana-only `sysvar` target-extension ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用生成程序，验证 `sol_get_epoch_rewards_sysvar` 将当前 `EpochRewards` scalar/word-view 字段记录进 program-owned state，并与 EpochRewards sysvar account data 对比 | 更多 Clock/Rent 字段、generic account-passed sysvar 读取、公共 validator 部署 |
| Solana LastRestartSlot sysvar Surfpool/Web3.js smoke | `just solana-last-restart-slot-sysvar-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 Solana-only `sysvar` target-extension ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用生成程序，验证 feature-gated `LastRestartSlot.last_restart_slot` 读取已通过 `sol_get_sysvar` lowering，并与 LastRestartSlot sysvar account data 对比 | 其他 sysvars、公共 validator 部署、cluster feature activation 差异 |
| Solana memory syscall Surfpool/Web3.js smoke | `just solana-memory-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 `runtime.memory` ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用 `set_source` 和 `copy_compare_fill`，并验证 program-owned account bytes 证明 `sol_memcpy_`、`sol_memmove_`、`sol_memcmp_` 和 `sol_memset_` 已执行 | 更广泛的 account/data packing helper、Rust/Pinocchio 等价性 |
| Solana return-data/compute Surfpool/Web3.js smoke | `just solana-return-data-compute-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 `runtime.return_data`/`runtime.compute_units` ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用，借助 simulation returnData 验证 `sol_set_return_data`，通过 empty read 与同一条 instruction 内 set/get roundtrip 验证 `sol_get_return_data`，验证 `sol_remaining_compute_units` 写入非零 state value，并验证 `sol_log_compute_units_` 产出 compute-unit log | CPI return-value 处理、`u64` 之外的 typed return payload、public-validator feature 差异 |
| Solana SHA-256/Keccak-256/Blake3 syscall Surfpool/Web3.js smoke | `just solana-crypto-hash-web3` | 来自 `lean-toolchain` 的 Lean 工具链；`surfpool`；Solana CLI 和 `solana-keygen`；`sbpf`；Node；npm | 构建生成的 Solana-only `crypto.hash` ELF，启动 Surfpool，用 `solana program deploy --use-rpc` 部署，通过 `@solana/web3.js` 调用 `set_preimage`、`hash_preimage`、`keccak_preimage` 和 `blake3_preimage`，并验证 account 中保存的 digest 与同一 preimage bytes 的 Node SHA-256 和 `@noble/hashes` Keccak-256/Blake3 一致 | portable `Expr.hash` 路由、Rust/Pinocchio 等价性 |
| Yul 生成冒烟测试 | `lake env proof-forge build --target evm --root . --yul-output build/counter.yul -o build/counter.bin Examples/Evm/Contracts/Counter.lean` | 已构建 `proof-forge` | `contract_source` 通过 portable IR 和 EVM semantic plan 降级为 Yul | `solc` 验收、ABI 调度、EVM 运行时行为 |
| Yul 到字节码冒烟测试 | `solc --strict-assembly build/counter.yul --bin` | `PATH` 上的 `solc` | 生成的 Yul 被 `solc` 接受 | 运行时语义或方法调度 |
| 单个 EVM 字节码编译 | `lake env proof-forge --evm-bytecode --root . --module contract --artifact-output build/evm/Counter.proof-forge-artifact.json -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean` | `solc`、`cast`、`python3` 和 `Examples/Evm/Contracts/Counter.evm-methods` | Lean -> Yul -> `solc` -> 带有选择器生成的 runtime bytecode、可部署 `.init.bin` creation bytecode、`proof-forge-artifact.json` metadata，以及 `proof-forge-deploy.json` initcode manifest；manifest 中的 initcode header 会复制并返回引用的 runtime bytecode；`--evm-chain-profile <id>` 还会把已知 EVM chain profile 写入 deploy manifest，但不广播交易；`--evm-constructor-param <name:type>` 会记录静态 word constructor ABI schema；`--evm-constructor-arg <name=value>` 会 ABI-encode 支持的静态 word typed value；`--evm-constructor-args-hex <hex>` 会记录并追加一段 ABI-encoded constructor-argument tail | 运行时行为、gas、详尽的 ABI 正确性、dynamic constructor ABI types、签名/原始交易生成、真实交易广播 |
| EVM 示例编译 | `scripts/evm/build-examples.sh` | `cast`、`solc`、`python3`、`lake env proof-forge`；可选 `PROOF_FORGE_BIN`、`CONTRACTS_DIR`、`EVM_OUT_DIR` | 每个带有兄弟 `.evm-methods` 的 `.lean` 合约都编译为可复现 Yul、`.bin` 和 `.init.bin`，diff 生成的 Yul 与已跟踪的 SDK 示例 golden fixture，并校验 EVM metadata hash、initcode hash/header/runtime 关联、deploy-manifest hash、source/module 信息、solc 信息、SDK method selector/function，以及必需的 Solidity method signature | 运行时行为；没有 `.evm-methods` 的合约会被脚本跳过 |
| Learn token ERC-20 VM 冒烟测试 | `just learn-token-evm-vm` | 来自 `lean-toolchain` 的 Lean 工具链；`solc`；Node；npm | 解析 `Examples/Learn/ProofToken.learn`，通过 `proof-forge --learn-token --target evm` 发射 ERC-20 Yul、creation bytecode 和 artifact metadata，在 EthereumJS VM 中部署生成的 creation bytecode，然后验证 `totalSupply`、`decimals`、`balanceOf`、`transfer`、`approve`、`allowance`、`transferFrom`、可选 `burn`、可选 `mint`、Transfer/Approval topic，以及余额不足时的 revert 行为 | live RPC 部署、gas accounting、wallet UX、更强的 mint access-control policy |
| EVM 运行时冒烟测试 | `scripts/evm/foundry-smoke.sh` | `forge`、`cast`、`solc`；可选 `EVM_OUT_DIR`、`EVM_FORGE_DIR` | Foundry 执行为 Counter、ArrayExample、SimpleToken 和 VerifiedVault 生成的 runtime bytecode，也会通过 EVM `create` 执行生成的 Counter `.init.bin`，并包含 revert 检查 | 形式化证明覆盖、跨目标等效性、实时 RPC 部署、详尽的边界覆盖 |
| EVM Anvil 部署冒烟测试 | `scripts/evm/anvil-deploy-smoke.sh` | `anvil`、`cast`、`solc`、`python3`；可选 `EVM_ANVIL_CHAIN_ID`、`EVM_ANVIL_CHAIN_PROFILE`、`EVM_ANVIL_PORT`、`EVM_ANVIL_RUN_DIR`、`EVM_ANVIL_CONSTRUCTOR_ARG`、`EVM_ANVIL_CONSTRUCTOR_ARGS_HEX`、`EVM_ANVIL_CONSTRUCTOR_PARAM` | 启动本地 Anvil 链，默认用 deterministic typed `initial=123` constructor input、`initial:uint256` constructor ABI schema，以及 chain id `31337` 的 `anvil-local` chain profile 重新生成 Counter initcode，校验带 signature 的 Counter method metadata 和带 profile 的 deploy metadata，通过 `cast send --create` 部署生成的 Counter `.init.bin`，在 `Counter.proof-forge-deploy-run.json` 中记录 constructor ABI schema、constructor args、creation receipt、creation transaction JSON、chain profile 和 deployed address，验证 creation transaction input 等于生成的 initcode，验证 profile chain id 匹配实际本地链，验证 deployed runtime code 等于 `Counter.bin`，通过 JSON-RPC 运行 Counter `get`/`set`/`increment`/`decrement`，并用 `scripts/evm/validate-deploy-run.py` 校验 deploy-run artifact | live public RPC 部署、explorer verification、wallet UX、dynamic constructor ABI types、长期运行链状态 |
| EVM ABI ScalarProbe IR 冒烟测试 | `scripts/evm/abi-scalar-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `U64`、`U32` 和 `Bool` ABI 参数降级为 Yul 函数参数和 dispatcher calldata load，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 selector entrypoints 与 Yul/bytecode hash 的 EVM metadata，校验 `robinhood-chain-testnet`、chain id `46630` 的 chain-profile-aware deploy manifest，并通过 Foundry 校验有效调用和 malformed calldata revert | 聚合 ABI 参数/返回、storage 行为、实时 RPC 部署 |
| EVM AssertProbe IR 冒烟测试 | `scripts/evm/assert-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `assert` 和 `assert_eq` 降级为 Yul revert guard，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `assertions.check` 的 EVM metadata，并通过 Foundry 校验成功路径和断言失败 revert | 丰富 revert data、表达式类型检查 |
| EVM AssignmentProbe IR 冒烟测试 | `scripts/evm/assignment-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 可变标量 local 和 local assignment 降级为 Yul `let` 与 `:=`，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验 selector entrypoints 与 artifact hash metadata，并通过 Foundry 校验赋值结果和 bool guard 失败 revert | 聚合赋值路径、storage path 赋值路径 |
| EVM AssignOpProbe IR 冒烟测试 | `scripts/evm/assign-op-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 复合赋值支持可变 `U32`/`U64` local 和 `U64` 标量 storage，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `storage.scalar` 的 EVM metadata，通过 Foundry 校验 U64/U32 返回值，并用 `vm.load` 校验原始标量 storage，同时验证未知 selector revert | 聚合赋值 target、raw EVM word 操作之外的 checked overflow 语义 |
| EVM ConditionalProbe IR 冒烟测试 | `scripts/evm/conditional-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 语句级 `if/else` 降级为 Yul `switch` block，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `storage.scalar`、`control.conditional`、`assertions.check` 的 EVM metadata，并通过 Foundry 校验 then/else storage 更新结果和未知 selector revert；分支内早退由 `EvmLoopProbe` 覆盖 | 更多控制流分析 |
| EVM LoopProbe IR 冒烟测试 | `scripts/evm/loop-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `boundedFor` 降为带静态边界的 Yul `for` loop，分支内和 loop 内早退会降为返回值赋值后跟 Yul `leave`；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 生成 runtime bytecode，metadata 包含 `storage.scalar`、`control.conditional` 和 `control.bounded_loop`，Foundry 校验 loop 更新后的 storage、原始 storage slot、早退返回值/effect，以及未知 selector revert | 动态 loop 边界、break/continue、更多控制流分析 |
| EVM ContextProbe IR 冒烟测试 | `scripts/evm/context-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR context read 降级为 Yul `caller()`、`address()` 和 `number()`，`nativeValue` 降级为 Yul `callvalue()`，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `caller.sender`、`account.explicit`、`env.block`、`value.native` 的 EVM metadata，并通过 Foundry `vm.prank`/`vm.roll` 校验运行时 context 值、通过 `probe.call{value: ...}` 校验原生 value 和未知 selector revert | 当前 portable `userId`/`contractId`/`checkpointId` 之外的 context 字段、地址宽度类型校验 |
| EVM EventProbe IR 冒烟测试 | `scripts/evm/event-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `eventEmit` 降为 Yul `log1`，`eventEmitIndexed` 降为 Yul `log2`/`log3`/`log4`，其中 `topic0 = keccak256(Solidity-style event signature)`，U64/Bool/U32/Hash indexed scalar field 进入 topic，U64/Bool/U32/Hash scalar 非 indexed field 进入 32-byte word data，扁平 struct / scalar fixed-array / fixed-array-of-flat-struct 非 indexed field 会从 local value 和 storage read 展开为 ABI-style data word，支持的 aggregate indexed field 会对展开后的 ABI-style word 执行 `keccak256` 作为 topic；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 生成 runtime bytecode，metadata 包含 `events.emit`，并校验 `abi.events` 中的 signature、`topic0`、indexed/data field、展开后的 word type 和 topic/data encoding，Foundry recorded logs 校验 emitter/topic/data，包括 `TypedScalarEvent(bool,uint32,bytes32)`、`PairEvent((uint64,uint64))`、`StoragePairEvent((uint64,uint64))`、`StorageArrayEvent(uint64[2])`、`ArrayEvent(uint64[2])`、`PairArrayEvent((uint64,uint64)[2])`、`StoragePairArrayEvent((uint64,uint64)[2])`、`IndexedTypedScalar(bool,uint32,bytes32,uint64)`、`IndexedPair((uint64,uint64),uint64)`、`IndexedStoragePair((uint64,uint64),uint64)`、`IndexedTwoValues(uint64,uint64,uint64)`、`IndexedThreeValues(uint64,uint64,uint64,uint64)`、`IndexedStorageArray(uint64[2],uint64)`、`IndexedArray(uint64[2],uint64)`、`IndexedStoragePairArray((uint64,uint64)[2],uint64)` 和 `IndexedPairArray((uint64,uint64)[2],uint64)`，并验证 malformed Bool/U32 calldata 和未知 selector revert | 更完整的 event declaration、不支持的嵌套 aggregate indexed shape、超过 3 个 topic 的 indexed field |
| EVM CrosscallProbe IR 冒烟测试 | `scripts/evm/crosscall-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `crosscallInvoke`、`crosscallInvokeTyped`、`crosscallInvokeValueTyped`、`crosscallInvokeStaticTyped`、`crosscallInvokeDelegateTyped`、`crosscallCreate` 和 `crosscallCreate2` 降为按 arity、返回类型、value 模式、static 模式、delegate 模式和 creation 模式区分的 Yul helper，打包 selector/scalar-word、扁平 aggregate，以及 leaf 为 scalar word 或扁平 struct 的嵌套 fixed-array 参数，执行同步 EVM `call`、`staticcall`、`delegatecall`、`create` 或 `create2`，可选转发 U64 call value，在调用失败、返回数据过短或 creation 返回零地址时 revert，解码 scalar 和 entrypoint 直接返回的 aggregate return word，对 scalar 与 aggregate 返回中的 Bool/U32 word 做范围 guard，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `crosscall.invoke` 和所有 CrosscallProbe entrypoint 的 EVM metadata，并通过 Foundry 校验 U64 零/一/二参数调用、Bool/U32/Hash typed 调用、扁平 struct/scalar fixed-array/fixed-array-of-flat-struct/leaf 为 scalar 或扁平 struct 的 nested fixed-array typed-call 参数、normal/value/static/delegate 模式下扁平 struct/scalar fixed-array/fixed-array-of-flat-struct/leaf 为 scalar 或扁平 struct 的 nested fixed-array aggregate typed return、normal/value/static/delegate 模式下的 aggregate Bool/U32 malformed-return guard、native value 转发到 payable callee、带 value 的扁平和嵌套 scalar/flat-struct aggregate 参数、U64 read-only staticcall 返回、Bool/U32/Hash static typed return、static 扁平和嵌套 scalar/flat-struct aggregate 参数、非法 static Bool/U32 return guard、static context 状态写入失败、caller-storage delegatecall 读写、Bool/U32/Hash delegate typed return、delegate 扁平和嵌套 scalar/flat-struct aggregate 参数、非法 delegate Bool/U32 return guard、固定 init-code `create` 部署、确定性 `create2` 地址校验、deployed-runtime 调用、非法 typed return 和 revert 路径 | Artifact-linked creation code、动态 constructor 参数、非扁平 nested aggregate leaf、variable-length 返回数据 |
| EVM ExpressionProbe IR 冒烟测试 | `scripts/evm/expression-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR scalar expression 直接降为 Yul，覆盖 U64/U32 arithmetic、U64 exponentiation、U64/U32 bitwise 和 shift、predicate、boolean operator、scalar literal、不可变 local read、支持的 cast、单 word return 和 assertion guard；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 编译，metadata 包含 `assertions.check`，Foundry 校验运行时返回值、U32/Bool calldata guard、malformed calldata revert 和未知 selector revert | raw EVM word operation 之外的 checked overflow 语义、array/struct/ABI probe 覆盖的聚合 expression |
| EVM HashProbe IR 冒烟测试 | `scripts/evm/hash-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `Hash` 值降为单 word EVM `bytes32` ABI/storage 值，`hash4` 与 `hashValue` 将四个 limb 打包为一个 word，`hash` 与 `hash_two_to_one` 降为 Yul `keccak256` helper，生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 生成 bytecode，metadata 包含 `crypto.hash` 和 `storage.scalar`，Foundry 校验 ABI `bytes32` 参数/返回与原始标量 storage slot，并验证未知 selector revert | 聚合 hash 输入、地址宽度类型校验 |
| EVM MapProbe IR 冒烟测试 | `scripts/evm/map-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `Map<U64, U64, N>` storage 通过 Solidity-style `keccak256(key, slot)` value mapping slot 和 ProofForge 管理的 `contains` presence slot 降级，匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `storage.scalar`、`storage.map`、`assertions.check` 的 EVM metadata，并通过 Foundry 校验 get/set/insert/contains 返回值、value 为零但 present 的 key、单段和嵌套连续 `mapKey` storage path 的 read、write 和复合赋值、`vm.load` 原始 value/presence slot 和未知 selector revert | typed word map 由 `EvmTypedMapProbe` 覆盖、array/struct storage path、混合 map/aggregate storage path |
| EVM TypedMapProbe IR 冒烟测试 | `scripts/evm/typed-map-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `Map<K, V, N>` storage 对 word key/value 类型（`U32`、`Bool`、`Hash` 和已有 `U64`）通过 Solidity-style `keccak256(key, slot)` value mapping slot 和 ProofForge 管理的 `contains` presence slot 降级；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 编译，metadata 包含 `storage.scalar`、`storage.map` 和 `assertions.check`，Foundry 校验 U32/Bool/Hash map read/write、typed contains、previous-value return、原始 value/presence mapping slot、U32/Bool calldata guard、单段 `mapKey` storage-path read/write、U32 map-path 复合赋值、带 dispatcher range guard 的 U32 嵌套 mapKey path read/write/复合赋值，以及未知 selector revert | 非 word 或 aggregate map key/value 形态、混合 map/aggregate storage path |
| EVM StorageArrayProbe IR 冒烟测试 | `scripts/evm/storage-array-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `U64` 固定 storage array 降为连续 EVM storage slot，并带运行时 index bounds check；单段 `index` storage path 会降为同一个 slot helper，用于 read/write/compound assignment；fixed-array ABI return 可以由 storage element read 组装；匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `storage.scalar`、`storage.array`、`data.fixed_array` 的 EVM metadata，并通过 Foundry 校验 lifecycle/read/write/path/aggregate 返回值、`vm.load` 原始 slot layout、越界 index revert 和未知 selector revert | `U32`/`Bool`/`Hash` storage array 由 `EvmTypedStorageProbe` 覆盖、local fixed-array value 和更广的聚合 ABI 行为由 `EvmAbiAggregateProbe` 覆盖、嵌套 index storage path、struct |
| EVM TypedStorageProbe IR 冒烟测试 | `scripts/evm/typed-storage-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `Bool` scalar storage 和 `U32`/`Bool`/`Hash` 固定 storage array 降为连续 EVM word slot，并带运行时 index bounds check；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 编译，metadata 包含 `storage.scalar`、`storage.array`、`data.fixed_array` 和 `assertions.check`，Foundry 校验原始 slot layout、ABI Bool/Hash 返回、U32 calldata range guard、typed storage-path read/write、U32 storage-path 复合赋值、越界 revert 和未知 selector | 非 word storage 元素、嵌套 index storage path、struct array 由 `EvmStorageStructProbe` 覆盖、typed map 由 `EvmTypedMapProbe` 覆盖 |
| EVM StorageStructProbe IR 冒烟测试 | `scripts/evm/storage-struct-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 扁平 scalar storage struct 降为每字段一个 EVM slot，whole scalar storage struct read/write 会展开到这些字段 slot，并且 whole write 会快照 RHS 字段；扁平 struct 固定 storage array 降为连续字段展开 slot 并带运行时 index bounds check；scalar `field` 和 array `index`+`field` storage path 会降为同一 slot 公式用于 read/write/compound assignment；fixed-array-of-flat-struct ABI return 可以由 storage field read 组装；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 编译，metadata 包含 `storage.scalar`、`storage.array`、`data.fixed_array` 和 `data.struct`，Foundry 校验 U64/Bool/U32/Hash 字段、whole storage struct read/write、storage-backed ABI struct return、storage-backed fixed-array-of-struct return、原始 slot layout、越界 revert 和未知 selector | 嵌套 struct field、非扁平 struct storage |
| EVM ArrayValueProbe IR 冒烟测试 | `scripts/evm/array-value-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 不可变和可变 local fixed-array value 会降为每个元素一个 Yul local；fixed-array literal 以及静态/动态 index read 可确定性 lowering；静态/动态 local 元素赋值和数字复合赋值会更新展开后的 local；静态和动态嵌套 scalar local fixed-array read 会降为确定性 leaf local 和 nested getter helper；静态和动态嵌套 scalar leaf 赋值/复合赋值会降为直接赋值或嵌套 `switch` block；whole-local 和 whole-nested fixed-array assignment 会先快照 RHS 元素再写回；匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `data.fixed_array` 和 `assertions.check` 的 EVM metadata，并通过 Foundry 校验 U64/U32/Bool/Hash 返回值、可变元素写入、嵌套动态读写越界 revert 和未知 selector revert | ABI 聚合行为由 `EvmAbiAggregateProbe` 覆盖、leaf 非 scalar 的嵌套 array |
| EVM StructArrayValueProbe IR 冒烟测试 | `scripts/evm/struct-array-value-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 扁平 struct local fixed array 会降为每个 element field 一个 Yul local；`field(arrayGet(localArray, index), name)` 支持静态和动态字段读取；可变 struct-array 字段赋值和数字复合赋值会通过静态赋值或动态 `switch` 更新展开后的 local；从另一个 local struct array 或 struct-array literal 做 whole local assignment 时，会先快照 RHS 字段再写回目标字段；匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，metadata 包含 `data.fixed_array`、`data.struct` 和 `assertions.check`，Foundry 校验 U64/U32/Bool/Hash-backed 返回值、自引用 RHS 快照行为、动态越界 index revert 和未知 selector revert | 嵌套 array、嵌套 struct、ABI 聚合行为由 `EvmAbiAggregateProbe` 覆盖 |
| EVM StructValueProbe IR 冒烟测试 | `scripts/evm/struct-value-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 扁平不可变和可变 local struct value 会降为每个字段一个 Yul local；struct literal 和 field access 针对 U64/U32/Bool/Hash 字段可确定性 lowering；静态 local 字段赋值和数字复合赋值会更新展开后的 local；whole-local struct assignment 会先快照 RHS 字段再写回；匹配 golden Yul，通过 `solc --strict-assembly` 生成 runtime bytecode，校验包含 `data.struct` 和 `assertions.check` 的 EVM metadata，并通过 Foundry 校验 U64/U32/Bool/Hash 返回值、可变字段写入和未知 selector revert | 嵌套 struct、storage struct 行为由 `EvmStorageStructProbe` 覆盖、ABI 聚合行为由 `EvmAbiAggregateProbe` 覆盖、struct array |
| EVM AbiAggregateProbe IR 冒烟测试 | `scripts/evm/abi-aggregate-ir-smoke.sh` | `forge`、`solc`、`python3`、来自 `lean-toolchain` 的 Lean 工具链 | Portable IR 扁平静态 struct、fixed-array 和嵌套标量 fixed-array ABI 参数会展开为连续 calldata word，扁平 struct fixed array 会按 tuple-array ABI word 展开，`U32` 和 `Bool` 聚合 word 会带 dispatcher range guard，`Hash` 聚合 leaf 会在扁平 struct 和 fixed array 内降为 Solidity `bytes32` word，扁平 struct/fixed-array 返回（包括嵌套标量 fixed array、扁平 struct fixed array、HashPair struct 和 Hash fixed array）会编码为多 word ABI return data；生成的 Yul 匹配 golden fixture，通过 `solc --strict-assembly` 编译，metadata 包含 `data.fixed_array`、`data.struct` 和结构化 `abi.entrypoints` selector signature 及 calldata/return word layout，并通过 `cast sig` 和 `--expect-entrypoint-abi` 校验；Foundry 校验聚合调用/返回、包括短 `bytes32[2]` calldata 在内的 malformed calldata revert，以及未知 selector revert | 动态聚合 ABI 值、超出 `EvmStorageArrayProbe` 和 `EvmStorageStructProbe` 已覆盖的固定 word array 与扁平 struct array 的更广 storage-backed aggregate ABI return、超出扁平 word 聚合的复杂 ABI tuple；typed crosscall aggregate 行为由 `EvmCrosscallProbe` 覆盖 |
| EVM 诊断冒烟测试 | `scripts/evm/diagnostic-smoke.sh` | 来自 `lean-toolchain` 的 Lean 工具链 | 不支持或格式错误的 EVM IR 形态在 Yul 生成前以显式诊断失败，包括缺少 selector、Unit/零长度 array 和非扁平 struct field 等不支持 ABI 值、控制流路径缺少返回、Hash/U64 类型错配、array/struct/event surface、无效 bounded-loop 范围、crosscall target/method/argument 类型错误、typed crosscall 参数/返回中 leaf 为非扁平 struct 的嵌套 fixed-array 不支持、带 value crosscall 的 call value/return 类型错误以及 leaf 为非扁平 struct 的嵌套 fixed-array 不支持、static/delegate crosscall 中 leaf 为非扁平 struct 的嵌套 fixed-array 不支持、create/create2 value、salt 和 init-code hex 格式错误、不支持的 map 形态、statement 位置的 `contains`、格式错误的赋值/复合赋值类型和 target、storage path 复合赋值的表达式位置/嵌套路径误用，以及 effect 表达式/语句位置误用（包括 statement 位置的 context read）。它还会检查 EVM constructor CLI 诊断，包括不支持的 dynamic ABI type、缺失或重复的 typed value、typed/raw constructor argument source 混用、整数溢出，以及 address 过短等格式错误的 static-word value。 | 完整 unsupported surface 覆盖、solc 行为、Foundry 运行时行为、制品 metadata |
| EVM IR 覆盖清单 | `scripts/evm/check-ir-coverage-manifest.py` | `python3` | `Tests/EvmCoverage.tsv` 为 `ProofForge/IR/Contract.lean` 中每个 portable IR constructor 记录 EVM 是否 lowered、validated、unsupported 或 structural | 行为正确性、solc 行为、Foundry 运行时行为、制品生成 |
| Psy Counter IR 冒烟测试 | `scripts/psy/counter-smoke.sh` | `PATH` 上的 `dargo`；`python3`；macOS arm64 上 `psyup install 0.1.0` 已知可用 | Counter portable IR 降级为 `.psy`，匹配 golden fixture，通过 `dargo test --file`，通过 `dargo compile` 生成非空 DPN JSON，通过 `dargo execute` 返回 `result_vm: [2]`，生成非空 ABI JSON，写出 `proof-forge-deploy.json`，并在 `proof-forge-artifact.json` 中记录和校验 metadata/deploy manifest 的 hash、能力和执行结果 | 上游压缩 genesis deploy JSON、真实 Psy node/prover 行为、更广泛 IR 覆盖 |
| Psy ContextProbe IR 冒烟测试 | `scripts/psy/context-smoke.sh` | `PATH` 上的 `dargo`；`python3`；macOS arm64 上 `psyup install 0.1.0` 已知可用 | 非 Counter Psy IR 降级参数和 context reads，匹配 golden fixture，通过 `dargo test --file`，生成非空 DPN JSON 和 ABI JSON，通过 `dargo execute` 返回 `result_vm: [15]`，写出 `proof-forge-deploy.json`，并在 `proof-forge-artifact.json` 中记录和校验 metadata/deploy manifest | maps、arrays、hashes、上游压缩 genesis deploy JSON、真实 Psy node/prover 行为 |
| Psy HashProbe IR 冒烟测试 | `scripts/psy/hash-smoke.sh` | `PATH` 上的 `dargo`；`python3`；macOS arm64 上 `psyup install 0.1.0` 已知可用 | Psy IR 将 `Hash`、typed hash let-bindings、`hash` 和 `hash_two_to_one` 降级为 `.psy`，匹配 golden fixture，通过 `dargo test --file`，生成非空 DPN JSON 和 ABI JSON，通过 `dargo execute` 返回预期四 Felt hash 输出，写出 `proof-forge-deploy.json`，并在 `proof-forge-artifact.json` 中记录和校验 metadata/deploy manifest | maps、storage maps、上游压缩 genesis deploy JSON、真实 Psy node/prover 行为 |
| CI 基线 | `.github/workflows/ci.yml` `build-test` 任务 | GitHub Actions Ubuntu、`just` 1.48.0、elan、Foundry stable、`solc` 0.8.30 | 清洁环境下的 `just build`、`just target-registry`、`just evm-plan`、`just solana-light`、`just docs-check`、Wasm-NEAR 诊断冒烟、Wasm-NEAR/EmitWat IR 覆盖清单、IR ownership 规则、Wasm-NEAR 形式语义锚点、EmitWat offline host 冒烟、`just psy-golden-sources`、Psy 诊断、Psy IR 覆盖清单、EVM 诊断、EVM IR 覆盖清单、EVM ABI ScalarProbe/AssertProbe/AssignmentProbe/AssignOpProbe/ConditionalProbe/LoopProbe/ContextProbe/EventProbe/CrosscallProbe/ExpressionProbe/HashProbe/MapProbe/TypedMapProbe/StorageArrayProbe/StorageStructProbe/TypedStorageProbe/ArrayValueProbe/StructArrayValueProbe/StructValueProbe/AbiAggregateProbe IR 冒烟测试、EVM metadata/deploy-manifest 校验、EVM 编译、Foundry 冒烟测试和 Anvil deploy smoke。CI 会保留独立的 GitHub Actions 步骤用于定位失败，但每个常见门禁都通过根目录 `justfile` recipe 调用。 | 可选 Dargo 目标冒烟测试、非 Ubuntu 行为 |
| Aleo Counter IR 冒烟测试 | `scripts/aleo/counter-smoke.sh` | `PATH` 上的 `leo` CLI（已测试 4.0.2）；`python3`；来自 `lean-toolchain` 的 Lean 工具链 | Portable IR `Counter` 降级为 Leo 4.0 程序，含 `@noupgrade constructor` 和 `fn ... -> Final` entry point，匹配 `Examples/Aleo/Counter.golden.leo`，`leo build` 生成 `main.aleo` 和 `abi.json`，`leo test` 通过，`proof-forge-artifact.json` schema 校验通过 | private records、transitions、proofs、直接 Aleo Instructions、devnet 部署、跨目标等价性、独立 `.avm` 文件 |
| Aleo PureMath IR 冒烟测试 | `scripts/aleo/pure-math-smoke.sh` | `PATH` 上的 `leo` CLI（已测试 4.0.2）；`python3`；来自 `lean-toolchain` 的 Lean 工具链 | 带参数的纯函数、`if/else`、`boundedFor`、`assign`、`assignOp`、`assert` 降级为 Leo 4.0 程序，匹配 `Examples/Aleo/PureMath.golden.leo`，`leo build` 生成 `main.aleo` 和 `abi.json`，`leo test` 通过，`proof-forge-artifact.json` schema 校验通过 | 带参数的状态写入口、非局部赋值目标、动态循环边界、独立 `.avm` 文件 |

## 计划中但尚不可运行的门禁

以下门禁处于 `Planned` 状态，且不存在于 CI 或脚本中：

- `proof-forge build --target <id>` — 统一的面向目标的构建命令。
- `proof-forge test --target <id>` — 统一的面向目标的测试命令。
- 非 EVM、非 Psy 的 `proof-forge-artifact.json` 验证 — 尚未写出 metadata 的目标仍需制品元数据 schema 验证。
- 黄金 Yul/输出快照 — 通过快照差异对比进行回归检测。
- CosmWasm 冒烟测试 — `cosmwasm-check` 或 `cw-multi-test` 验证。
- Solana sBPF assembly 门禁（目标 `solana-sbpf-asm`，D-026）。这些门禁会随工作流 6-7 落地变成可运行项；`sbpf` 工具链先在本地验证 build + disassemble round-trip + Counter 的 `sbpf test`：
  - **V-GATE-SOLANA-01** — `--emit-sbpf-asm` 产生可被 `sbpf build` 接受的有效 `.s`。脚本：`scripts/solana/emit-asm-smoke.sh`（可运行，Phase 0 完成）。
  - **V-GATE-SOLANA-02** — `sbpf build` 产生有效 ELF，且 `sbpf disassemble` 可以 round-trip。脚本：`scripts/solana/emit-asm-smoke.sh`（可运行，Phase 0 完成）。
  - **V-GATE-SOLANA-03** — Counter 场景（initialize、increment、get）通过 `sbpf test` (Mollusk)。脚本：`scripts/solana/counter-smoke.sh`（Phase 1 完成；4 项 Mollusk 断言：initialize→0、increment 0→1、increment 5→6、get→return_data）。生成的 `.s` 现在包含账户校验 prologue（writable + owner 检查），并伴随 `manifest.toml`；由 `scripts/solana/build-examples.sh` 保持 `Examples/Solana/Counter.golden.s` 与 `Counter.manifest.toml` 同步。
  - **V-GATE-SOLANA-04** — Counter 场景通过 Surfpool 本地 simnet 部署和 Web3.js 行为冒烟。脚本：`scripts/solana/surfpool-web3-smoke.sh`（可选，取决于 `surfpool`、Solana CLI、`sbpf`、Node 和 npm 是否可用）。脚本会构建 Counter ELF、启动 Surfpool、用 `solana program deploy --use-rpc` 部署、通过 `@solana/web3.js` 创建 program-owned counter account、调用 initialize/increment/get、验证 account data 0→1→2，并检查 `get` return data。
  - **V-GATE-SOLANA-05** — 能力检查器以包含 target id 和 capability id 的清晰诊断拒绝不支持能力。脚本：`scripts/solana/diagnostic-smoke.sh` 运行 `Tests/SolanaDiagnostics.lean`，断言 8 个 `crosscall.invoke` 家族拒绝用例均输出预期消息 `target \`solana-sbpf-asm\` does not support capability \`crosscall.invoke\`: ...`。（Phase 1 完成）。
  - **V-GATE-SOLANA-06** — `proof-forge-artifact.json` 包含 `target: "solana-sbpf-asm"`、`irVersion` 和 entrypoint 列表。
  - **V-GATE-SOLANA-07** — `sbpf debug --elf --input` 可交互工作（开发者体验门禁，不进入 CI）。
  - **V-GATE-SOLANA-08** — 控制流 + 断言 IR 覆盖。两半部分：
      * 发射半部分（可运行，不需要 `sbpf`）：`scripts/solana/emit-control-smoke.sh` 运行 `--emit-control-ir-sbpf`，grep 生成的 `.s` 中 `control.conditional` / `control.assert` / `control.assert_eq` 标记、`assert_fail`（exit 2）与 `assert_eq_fail`（exit 3）全局 label、三个 entrypoint 的 dispatch 行、驱动 `r3` 与 `r2` 的 `jeq`/`jlt` 比较指令，判断汇编跨重发射逐字节可复现，并校验制品 metadata 记录 `target: "solana-sbpf-asm"`、`fixture: "control-ir-sbpf"`、`sourceModule: "ControlFlowAssertProbe"` 以及 `storage.scalar` / `control.conditional` / `assertions.check` / `account.explicit` 能力。（发射半部分完成）。
      * 运行时半部分（依 `sbpf` + `cargo` + `solana-keygen`）：`scripts/solana/control-smoke.sh` 通过 `sbpf build` 汇编生成的 `.s` 并跑由 `Tests/solana/control_mollusk.rs.tpl` 渲染的 Mollusk 测试 crate。6 项 Mollusk 断言覆盖从零状态及非零 pre-state 调用 `lifecycle`（都落到 10u64 并返回 10）、从 3 调用 `guarded_increment`（`.assert` 通过、count→4）及从 9 调用（`.assert` 经 `assert_fail` exit 2 revert）、从 7 调用 `equality_guard`（`.assertEq` 通过、count→7 且返回 7）及从 42 调用（`.assertEq` 经 `assert_eq_fail` exit 3 revert）。Mollusk fixture 关闭 `account_data_direct_mapping` / `direct_account_pointers_in_program_input` / `virtual_address_space_adjustments`，以使用 Phase 1 lowering 的 legacy 嵌入式账户数据布局。（Phase 1 完成）。
  - **V-GATE-SOLANA-09** — PDA typed seed descriptor 与 Solana Web3.js 兼容。
    脚本：`scripts/solana/pda-web3-smoke.sh` 发射 SDK Vault artifact，在隔离
    temp project 中安装 `@solana/web3.js`，读取
    `solanaExtensions.pdas[].typedSeeds`，并确认 literal/account/bump descriptor
    通过 `PublicKey.findProgramAddressSync` 和
    `PublicKey.createProgramAddressSync` 可以复现同一个 PDA。Harness 也覆盖
    UTF-8 和 instruction-parameter seed resolver 行为。这是离线 derivation
    gate；不会部署或执行交易。
  - **V-GATE-SOLANA-10** — System Program transfer CPI 通过 Surfpool 和
    Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/system-cpi-web3-smoke.sh` 构建生成的
    `--solana-system-cpi-elf` fixture，校验 artifact schema，启动 Surfpool，
    用 `solana program deploy --use-rpc` 部署 ELF，通过标准
    `@solana/web3.js` transaction 调用生成的 transfer entrypoint，并同时检查
    recipient lamport delta 与 program-owned state account 中记录的 lamports 值。
  - **V-GATE-SOLANA-10R** — System Program transfer Pinocchio
    reference-equivalence contract。脚本：
    `scripts/solana/pinocchio-system-transfer-equivalence.sh` emit 同一个
    `--solana-system-cpi-elf` fixture，并将生成 artifact 与
    `references/solana/pinocchio/system-transfer/reference-manifest.json`
    以及 source constants 对比。它先锁住 reference account order、
    signer/writable constraint、instruction data shape、CPI protocol/data
    layout 和 state-write contract，再进入后续 dual-deploy runtime harness。
  - **V-GATE-SOLANA-10L** — System Program transfer Pinocchio live
    equivalence。脚本：
    `scripts/solana/pinocchio-system-transfer-live-equivalence.sh` 构建
    ProofForge ELF 和 checked-in Pinocchio reference ELF，启动 Surfpool，
    用不同 program id 部署两个程序，用同一个 `@solana/web3.js` System
    transfer scenario 分别调用，并对比 recipient lamport delta 和
    program-owned state write。若 `cargo-build-sbf` 找不到 Solana
    rustc/platform-tools，该 gate 会 skip；可运行
    `just solana-pinocchio-install-sbf-tools` 修复该工具链。
  - **V-GATE-SOLANA-11** — System Program `create_account` CPI 通过 Surfpool
    和 Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/system-create-account-cpi-web3-smoke.sh` 构建生成的
    `--solana-system-create-account-cpi-elf` fixture，校验 artifact schema，
    启动 Surfpool，用 `solana program deploy --use-rpc` 部署 ELF，使用 payer
    和 new-account signer 调用生成的 create entrypoint，并检查新 account 的
    owner、data length、lamports，以及 state account 记录的 lamports 和 space。
  - **V-GATE-SOLANA-11R** — System Program `create_account` Pinocchio
    reference equivalence。脚本：
    `scripts/solana/pinocchio-system-create-account-equivalence.sh` 会 emit
    生成的 `--solana-system-create-account-cpi-elf` artifact，并将
    instruction ABI、account order、signer/writable constraint、CPI
    protocol/data layout、lamports/space/owner contract 和双字段 state-write
    contract 与 `references/solana/pinocchio/system-create-account` 对比；
    设置 `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时还会用
    `pinocchio-system` typecheck 该 reference。
  - **V-GATE-SOLANA-11L** — System Program `create_account` Pinocchio live
    equivalence。脚本：
    `scripts/solana/pinocchio-system-create-account-live-equivalence.sh` 构建
    ProofForge ELF 和 checked-in Pinocchio reference ELF，启动 Surfpool，用不同
    program id 部署两个程序，用同一个 `@solana/web3.js` create-account
    scenario 分别调用，并对比 lamports/space 输入和两个 program-owned state
    write。若 `cargo-build-sbf` 找不到 Solana rustc/platform-tools，该 gate 会
    skip；可运行 `just solana-pinocchio-install-sbf-tools` 修复该工具链。
  - **V-GATE-SOLANA-12** — SPL Token `transfer_checked` CPI 通过 Surfpool
    和 Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/spl-token-transfer-cpi-web3-smoke.sh` 构建生成的
    `--solana-spl-token-transfer-cpi-elf` fixture，校验 artifact schema，
    启动 Surfpool，用 `solana program deploy --use-rpc` 部署 ELF，通过
    `@solana/spl-token` 创建 mint、source token account 和 destination token
    account，用 source authority signer 调用生成的 transfer entrypoint，并检查
    token balance delta 与 state account 记录的 amount。
  - **V-GATE-SOLANA-12R** — SPL Token `transfer_checked` Pinocchio reference
    equivalence。脚本：
    `scripts/solana/pinocchio-spl-token-transfer-equivalence.sh` 会 emit 生成的
    `--solana-spl-token-transfer-cpi-elf` artifact，将 instruction ABI、
    account order、signer/writable constraint、CPI protocol/data layout、
    decimals/amount contract 和 state-write contract 与
    `references/solana/pinocchio/spl-token-transfer` 对比；设置
    `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时还会用 `pinocchio-token` typecheck
    该 reference。
  - **V-GATE-SOLANA-12L** — SPL Token `transfer_checked` Pinocchio live
    equivalence。脚本：
    `scripts/solana/pinocchio-spl-token-transfer-live-equivalence.sh` 构建
    ProofForge ELF 和 checked-in Pinocchio Token reference ELF，启动
    Surfpool，用不同 program id 部署两个程序，用同一个
    `@solana/web3.js` + `@solana/spl-token` transfer_checked scenario
    分别调用，并对比 source/destination token balance delta 以及
    program-owned amount state write。若 `cargo-build-sbf` 找不到 Solana
    rustc/platform-tools，该 gate 会 skip；可运行
    `just solana-pinocchio-install-sbf-tools` 修复该工具链。
  - **V-GATE-SOLANA-13** — SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI
    通过 Surfpool 和 Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/spl-token-ops-cpi-web3-smoke.sh` 构建生成的
    `--solana-spl-token-ops-cpi-elf` fixture，校验四个 entrypoint 的 artifact
    instruction schema，启动 Surfpool，用 `solana program deploy --use-rpc`
    部署 ELF，通过 `@solana/spl-token` 创建 mint、source token account 和
    destination token account，用 source/mint authority signer 调用生成的
    mint、burn、approve 和 revoke entrypoint，并检查 supply/balance/delegate
    变化以及 state account 记录的 mint、burn、approve 和 revoke 值。
  - **V-GATE-SOLANA-13R** — SPL Token `mint_to`/`burn`/`approve`/`revoke`
    Pinocchio reference equivalence。脚本：
    `scripts/solana/pinocchio-spl-token-ops-equivalence.sh` 会 emit 生成的
    `--solana-spl-token-ops-cpi-elf` artifact，将四个 instruction ABI、共享
    account order、signer/writable constraint、CPI protocol/data layout、
    SPL Token instruction tag 和 state-write contract 与
    `references/solana/pinocchio/spl-token-ops` 对比；设置
    `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时还会用 `pinocchio-token` typecheck
    该 reference。
  - **V-GATE-SOLANA-13L** — SPL Token `mint_to`/`burn`/`approve`/`revoke`
    Pinocchio live equivalence。脚本：
    `scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh` 构建
    ProofForge ELF 和 checked-in Pinocchio Token ops reference ELF，启动
    Surfpool，用不同 program id 部署两个程序，用同一个
    `@solana/web3.js` + `@solana/spl-token` mint/burn/approve/revoke scenario
    分别调用，并对比 token effect 以及 program-owned state write。若
    `cargo-build-sbf` 找不到 Solana rustc/platform-tools，该 gate 会 skip；
    可运行 `just solana-pinocchio-install-sbf-tools` 修复该工具链。
  - **V-GATE-SOLANA-13A** — SPL Token `set_authority` CPI 通过 Surfpool 和
    Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/spl-token-authority-cpi-web3-smoke.sh` 构建生成的
    `--solana-spl-token-authority-cpi-elf` fixture，校验 artifact schema，
    启动 Surfpool，用 `solana program deploy --use-rpc` 部署 ELF，通过
    `@solana/spl-token` 创建 mint，然后用 `@solana/web3.js` 调用生成程序，
    验证 mint authority 已被转移到 instruction accounts 中提供的新 authority
    pubkey，并检查 program-owned state marker。
  - **V-GATE-SOLANA-13AR** — SPL Token `set_authority` Pinocchio reference
    equivalence。脚本：
    `scripts/solana/pinocchio-spl-token-authority-equivalence.sh` 会 emit
    生成的 `--solana-spl-token-authority-cpi-elf` artifact，将 instruction
    ABI、account order、signer/writable constraint、CPI protocol/data layout、
    `SetAuthority` instruction contract 和 marker state-write contract 与
    `references/solana/pinocchio/spl-token-authority` 对比；设置
    `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1` 时还会用 `pinocchio-token`
    typecheck 该 reference。
  - **V-GATE-SOLANA-13AL** — SPL Token `set_authority` Pinocchio live
    equivalence。脚本：
    `scripts/solana/pinocchio-spl-token-authority-live-equivalence.sh` 构建
    ProofForge ELF 和 checked-in Pinocchio Token authority reference ELF，
    启动 Surfpool，用不同 program id 部署两个程序，用同一个
    `@solana/web3.js` + `@solana/spl-token` mint-authority transfer scenario
    分别调用，并对比 mint authority 与 program-owned state marker。若
    `cargo-build-sbf` 找不到 Solana rustc/platform-tools，该 gate 会 skip；
    可运行 `just solana-pinocchio-install-sbf-tools` 修复该工具链。
  - **V-GATE-SOLANA-14** — Solana `events.emit` scalar log 加
    `sol_log_pubkey`、`sol_log_data` 通过 Surfpool 和 Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/log-event-web3-smoke.sh` 构建生成的
    `--solana-log-event-elf` fixture，校验 artifact instruction schema、
    `events.emit` capability metadata、Solana-only `pubkeyLogActions` 和
    Solana-only `dataLogActions`，
    启动 Surfpool，用 `solana program deploy --use-rpc` 部署 ELF，用
    scalar `amount` instruction parameter 调用生成的 `emit` entrypoint，
    检查 program-owned state account 记录的 amount，检查 transaction
    `logMessages` 中 `sol_log_64_` 输出包含稳定的 `AmountEvent` tag 和
    scalar value，调用 `log_state_pubkey`，并检查 transaction `logMessages`
    中包含来自 `sol_log_pubkey` 的 state account base58 pubkey；随后调用
    `log_state_data`，并检查 transaction `logMessages` 中包含来自
    `sol_log_data` 的 base64 `Program data:` payload。
  - **V-GATE-SOLANA-15** — Solana Clock sysvar 通过 Surfpool 和 Web3.js
    进行 live 行为验证。脚本：`scripts/solana/clock-sysvar-web3-smoke.sh`
    构建生成的 `--solana-clock-sysvar-elf` fixture，校验 artifact
    instruction schema 与 `env.block` capability metadata，启动 Surfpool，
    用 `solana program deploy --use-rpc` 部署 ELF，调用生成的 `record`
    entrypoint，检查 `sol_get_clock_sysvar` 把 `Clock.slot` 写入
    program-owned state account，并与 Web3.js metadata 中的 transaction slot
    对比。
  - **V-GATE-SOLANA-16** — Solana memory syscall 通过 Surfpool 和 Web3.js
    进行 live 行为验证。脚本：`scripts/solana/memory-web3-smoke.sh`
    构建生成的 `--solana-memory-elf` fixture，校验 `runtime.memory`
    artifact metadata，启动 Surfpool，用 `solana program deploy --use-rpc`
    部署 ELF，依次调用 `set_source` 和 `copy_compare_fill`，并检查
    program-owned state account 中的 copied value、moved value、memcmp result
    和 memset byte pattern。
  - **V-GATE-SOLANA-17** — Solana SHA-256/Keccak-256/Blake3 syscall 通过 Surfpool 和 Web3.js
    进行 live 行为验证。脚本：`scripts/solana/crypto-hash-web3-smoke.sh`
    构建生成的 `--solana-crypto-hash-elf` fixture，校验 `crypto.hash`
    artifact metadata，启动 Surfpool，用 `solana program deploy --use-rpc`
    部署 ELF，依次调用 `set_preimage`、`hash_preimage`、`keccak_preimage` 和
    `blake3_preimage`，并将 program-owned account 中的 32-byte digest 与同一
    preimage bytes 的 Node `crypto.createHash("sha256")` 和 `@noble/hashes`
    Keccak-256/Blake3 对比。
  - **V-GATE-SOLANA-18** — Solana Rent sysvar 通过 Surfpool 和 Web3.js
    进行 live 行为验证。脚本：`scripts/solana/rent-sysvar-web3-smoke.sh`
    构建生成的 `--solana-rent-sysvar-elf` fixture，校验 `sysvar` target
    extension artifact metadata，启动 Surfpool，用 `solana program deploy --use-rpc`
    部署 ELF，调用 `record_rent`，并将 program-owned account 记录的
    `Rent.lamports_per_byte_year` 与 Rent sysvar account 的第一个 `u64` word
    对比。
  - **V-GATE-SOLANA-19** — Solana EpochSchedule sysvar 通过 Surfpool 和
    Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/epoch-schedule-sysvar-web3-smoke.sh` 构建生成的
    `--solana-epoch-schedule-sysvar-elf` fixture，校验 `sysvar` target
    extension artifact metadata，启动 Surfpool，用 `solana program deploy --use-rpc`
    部署 ELF，调用 `record_epoch_schedule`，并将 program-owned account 记录的
    `EpochSchedule.slots_per_epoch`、`EpochSchedule.leader_schedule_slot_offset`、
    `EpochSchedule.warmup`、`EpochSchedule.first_normal_epoch` 和
    `EpochSchedule.first_normal_slot` 字段与 RPC `getEpochSchedule()` 对比。
  - **V-GATE-SOLANA-20** — Solana LastRestartSlot sysvar 通过 Surfpool 和
    Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/last-restart-slot-sysvar-web3-smoke.sh` 构建生成的
    `--solana-last-restart-slot-sysvar-elf` fixture，校验 feature-gated
    `sysvar` target-extension artifact metadata，启动 Surfpool，用
    `solana program deploy --use-rpc` 部署 ELF，调用
    `record_last_restart_slot`，并将 program-owned account 记录的
    `LastRestartSlot.last_restart_slot` 与 LastRestartSlot sysvar account 的第一个
    `u64` word 对比。生成的汇编使用
    `SysvarLastRestartS1ot1111111111111111111111` 调用 `sol_get_sysvar`，
    以兼容当前 `sbpf` assembler，同时保留 Solana SDK 层的 LastRestartSlot
    能力。
  - **V-GATE-SOLANA-21** — Solana EpochRewards sysvar 通过 Surfpool 和
    Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/epoch-rewards-sysvar-web3-smoke.sh` 构建生成的
    `--solana-epoch-rewards-sysvar-elf` fixture，校验当前所有
    `EpochRewards` 字段的 `sysvar` target-extension artifact metadata，启动
    Surfpool，用 `solana program deploy --use-rpc` 部署 ELF，调用
    `record_epoch_rewards`，并把 program-owned account 里记录的
    `EpochRewards.distribution_starting_block_height`、
    `EpochRewards.num_partitions`、`EpochRewards.parent_blockhash_word0..3`、
    `EpochRewards.total_points_low/high`、`EpochRewards.total_rewards`、
    `EpochRewards.distributed_rewards` 和 `EpochRewards.active` 与
    EpochRewards sysvar account data 对比。
  - **V-GATE-SOLANA-22** — Solana return-data 与 compute-unit syscall 通过
    Surfpool 和 Web3.js 进行 live 行为验证。脚本：
    `scripts/solana/return-data-compute-web3-smoke.sh` 构建生成的
    `--solana-return-data-compute-elf` fixture，校验 `runtime.return_data`
    与 `runtime.compute_units` target-extension artifact metadata，启动
    Surfpool，用 `solana program deploy --use-rpc` 部署 ELF，通过
    simulation `returnData` 确认 `sol_set_return_data`，检查 empty
    `sol_get_return_data` 读取，检查同一条 instruction 内的 set/get
    roundtrip 以及返回的 program id words，记录非零
    `sol_remaining_compute_units` value，并验证 `sol_log_compute_units_`
    产出 compute-unit log。
- Move 冒烟测试 — `aptos move compile/test` 或 Sui Move 验证。
- 能力拒绝测试 — 针对不支持的能力/目标组合的编译时诊断。

## 新目标工作的预先验证规则

在目标退出 `Research` 之前，文档必须指明：

1. 所需的外部工具。
2. 目标生成的最小制品。
3. 构建或验证该制品的本地命令或脚本。
4. 预期的制品路径。
5. 一个可观察的成功标准。

如果不存在可运行的本地命令，则该目标保持 `Research` 状态。

## 可选外部工具

当前的 CI 安装了 `just` 1.48.0、Foundry stable 和 `solc` 0.8.30。本地机器可能没有 `just`、`solc`、`cast`、`forge`、`psyup`、`dargo`、`sbpf`、`surfpool`、Solana CLI、Node 或 npm。缺失 `just` 会阻塞本地命令目录，但不会阻塞直接调用底层脚本。缺失 EVM 工具会阻塞 EVM 工具链门禁，但不会阻塞 `lake build`。缺失 Psy 工具只会阻塞 Psy smoke 的 Dargo 部分；source generation 和 golden diff 会在脚本退出前先运行。缺失 Solana 工具会阻塞 Solana assembly/runtime smoke，但不会阻塞 Lean build 或 target-registry check。
