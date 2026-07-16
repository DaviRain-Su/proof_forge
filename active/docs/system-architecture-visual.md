# ProofForge System Architecture · Visual Guide

Status: **visual-first guide (2026-07-15)**

Prefer this page when Mermaid feels dense. It uses:

1. **SVG overviews** (render inline on GitHub / VS Code)
2. **Excalidraw PNG exports** (hand-drawn presentation style)
3. **Editable `.excalidraw` sources** ([excalidraw.com](https://excalidraw.com))

Deep text inventory:
[system-architecture.md](system-architecture.md).
中文视觉版: [zh/system-architecture-visual.zh.md](zh/system-architecture-visual.zh.md).

## Regenerate

```bash
python3 scripts/generate-architecture-svg.py
python3 scripts/generate-excalidraw-diagrams.py   # .excalidraw JSON only
```

## Figure 1 · Overview

![Architecture overview](diagrams/svg/01-overview.en.svg)

## Figure 2 · Primary pipeline

![Compilation pipeline](diagrams/svg/02-pipeline.en.svg)

## Figure 3 · One source, three targets

![Three targets](diagrams/svg/03-three-targets.en.svg)

## Figure 4 · Layer stack

![Layer stack](diagrams/svg/04-layer-stack.en.svg)

## Figure 5 · Component cards

![Components](diagrams/svg/05-components.en.svg)

## Figure 6 · Excalidraw PNG gallery

| Diagram | Image |
|---|---|
| Platform overview | ![overview](diagrams/proofforge_architecture.png) |
| Nine-stage pipeline | ![pipeline](diagrams/proofForge_compilation_pipeline.png) |
| One contract, three targets | ![triad](diagrams/prooffroge_one_contract_three_target.png) |
| Capability routing | ![caps](diagrams/proofforge_capability_routing.png) |
| Developer workflow | ![workflow](diagrams/proofforge_developer_workflow.png) |
| Codebase layout | ![codebase](diagrams/proofforge_codebase.png) |
| Target landscape | ![targets](diagrams/proofforge_target_landscape.png) |

Catalog: [diagrams/README.md](diagrams/README.md).

> Excalidraw JSON may still carry some historical labels. Treat the **SVG set**
> and **code** as current; refresh Excalidraw text via the generator when needed.
