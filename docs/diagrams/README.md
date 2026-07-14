# ProofForge Architecture Diagrams

Three presentation modes, pick what you need:

| Mode | Path | Best for |
|---|---|---|
| **SVG (current, inline)** | [svg/](svg/) | GitHub / Markdown preview, clean product look |
| **PNG (Excalidraw export)** | `proofforge_*.png` | slides, hand-drawn demo style |
| **Excalidraw sources** | `0*.excalidraw` | open on [excalidraw.com](https://excalidraw.com) and edit |

**Start here:**

- EN visual guide: [../system-architecture-visual.md](../system-architecture-visual.md)
- 中文视觉导览: [../zh/system-architecture-visual.zh.md](../zh/system-architecture-visual.zh.md)

## SVG catalog (`svg/`)

Regenerate with:

```sh
python3 scripts/generate-architecture-svg.py
```

| File | Contents |
|---|---|
| `01-overview.{zh,en}.svg` | Six-column end-to-end architecture |
| `02-pipeline.{zh,en}.svg` | Primary compile path (one row) |
| `03-three-targets.{zh,en}.svg` | One Counter source → three targets |
| `04-layer-stack.{zh,en}.svg` | Outside-in layer bands |
| `05-components.{zh,en}.svg` | CLI / Frontend / Core / Target / backends / evidence |

## Excalidraw catalog

Hand-editable [Excalidraw](https://excalidraw.com) diagrams:

1. Go to [https://excalidraw.com](https://excalidraw.com)
2. **Menu → Open** (or drag-and-drop a `.excalidraw` file)
3. Or use the VS Code Excalidraw extension

| File | Contents |
|---|---|
| [01-architecture-overview.excalidraw](01-architecture-overview.excalidraw) | End-to-end platform layers |
| [02-compilation-pipeline.excalidraw](02-compilation-pipeline.excalidraw) | Nine-stage compile pipeline; EVM detail |
| [03-multi-target-counter.excalidraw](03-multi-target-counter.excalidraw) | One Counter → EVM / Solana / NEAR |
| [04-capability-routing.excalidraw](04-capability-routing.excalidraw) | Capability registry, fail-fast |
| [05-developer-workflow.excalidraw](05-developer-workflow.excalidraw) | CLI and `just` recipes |
| [06-codebase-structure.excalidraw](06-codebase-structure.excalidraw) | Repository layout |
| [07-target-landscape.excalidraw](07-target-landscape.excalidraw) | Target lifecycle / families |

Matching PNG exports live beside these files (`proofforge_*.png`).

Regenerate Excalidraw JSON:

```sh
python3 scripts/generate-excalidraw-diagrams.py
```

Manual edits in Excalidraw are overwritten if you regenerate from the script —
export or copy changes first. Prefer updating the **SVG generator** for
current architecture labels; keep Excalidraw for whiteboard storytelling.

## Related docs

- [System architecture visual](../system-architecture-visual.md)
- [System architecture map](../system-architecture.md)
- [Portable IR](../portable-ir.md)
- [Capability registry](../capability-registry.md)
