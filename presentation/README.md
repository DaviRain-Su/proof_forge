# ProofForge V2 — Hackathon Slides

Built with [Slidev](https://sli.dev) for the final 7-minute research presentation.

## Files

| File | Purpose |
| --- | --- |
| `slides.md` | 15 页 Slidev 源码 |
| `speaker-script.md` | **中文演讲稿**，按 5 个评审维度平衡技术/产品/商业/团队表达，并含 Vitalik 推文页口播 |
| `slides.pdf` | 导出的 PDF（演讲/备份/打印） |
| `public/images/` | 架构图（来自 `docs/diagrams/`）+ Vitalik 推文截图 |
| `package.json` + `pnpm-lock.yaml` | 依赖与可复现 lock |

## 5 个评审维度 → 对应页码

| 维度 | 对应页码 |
| --- | --- |
| 技术创新 | 6、7、8 |
| 产品完成度 | 4、5、7、14 |
| 商业与生态潜力 | 3、11、9、12 |
| AI 与 Web3 技术应用 | 4、9、10 |
| 团队表达能力 | 13、14、15 |

## Develop

```bash
cd presentation
pnpm install
pnpm dev
```

Then open the printed localhost URL and press **presenter** or **overview** for navigation.

## Build static site / PDF

```bash
# Static export (served from `dist/`)
pnpm build

# PDF export (already produced as `slides.pdf`)
pnpm export
```

## Slide timing (≈ 7 min, 15 slides)

| # | Slide | Time | Key message |
| --- | --- | --- | --- |
| 1 | Title | 0:00 | 一句话项目定位 |
| 2 | Multi-chain pain | 0:30 | 贵、慢、危险 |
| 3 | Real demand | 1:00 | ZK/L2/跨链爆发，真实市场 |
| 4 | Product: portable compiler | 1:30 | 一份源码，换 `--target` 即可 |
| 5 | User flow | 2:00 | check → build → inspect，流程清晰 |
| 6 | Architecture overview | 2:30 | 分层架构，source 不随 target 分支 |
| 7 | Technical differentiation | 3:00 | 与 transpiler/bridge 的差异 |
| 8 | What works now? | 3:30 | 诚实成熟度表，不夸大 |
| 9 | AI & Web3 fit | 4:00 | Web3 深度融合；AI 上诚实互补定位 |
| 10 | Vitalik: the same direction | 4:30 | **Vitalik 推文外部验证** |
| 11 | Business model & ecosystem | 5:00 | 开源核心 + 企业服务 + 生态价值 |
| 12 | Why us? | 5:30 | fail-closed 是核心壁垒 |
| 13 | Roadmap & landscape | 6:00 | Phase 1 + design-only 目标 |
| 14 | Team & next steps | 6:30 | engineering 现状与 formal/product-decision 下一步分离 |
| 15 | Closing + Q&A | 6:55 | 收尾与互动 |

## 诚实宣称边界

- EVM：locked `solc` bytecode + G4 Anvil 工程差分，但不是 formal Reference↔Anvil / 完整后端。
- Solana：SBPF asm → ELF `.so` + 20-program/89-test Mollusk 工程差分；call/schedule 已发真实 `sol_invoke_signed_c` 最小路径，但外层 callee account/multi-account ABI 未闭合；非 formal Stage-0。
- NEAR：locked `wat2wasm` + host-optional runtime load + near-sandbox Counter overflow/state-hold、聚合返回与 Option state 工程路径；非 formal Reference differential。
- Noir：Plan/relation IR + `.nr` 包 + locked nargo compile-only；无 ACIR/witness/proof/VK/verify。
- Aleo：Leo source + locked leo compile-only；无 VM/prove/deploy。Psy 仍是 source-only + host-optional compile。
- AI：未用于编译器核心，定位为确定性验证层。

演讲时请严格按以上边界表达。
