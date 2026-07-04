# ProofForge Architecture Diagrams (Excalidraw)

Hand-editable architecture diagrams for ProofForge, in [Excalidraw](https://excalidraw.com) format.

## How to open

1. Go to [https://excalidraw.com](https://excalidraw.com)
2. **Menu → Open** (or drag-and-drop a `.excalidraw` file onto the canvas)
3. Pick a file from this directory

You can also open these files in VS Code with the Excalidraw extension, or embed them in Notion/Obsidian where Excalidraw is supported.

## Diagram catalog

| File | Contents |
|---|---|
| [01-architecture-overview.excalidraw](01-architecture-overview.excalidraw) | End-to-end platform layers: authoring → IR → routing → backends → artifacts |
| [02-compilation-pipeline.excalidraw](02-compilation-pipeline.excalidraw) | Nine-stage compile pipeline; EVM semantic-plan detail on the side |
| [03-multi-target-counter.excalidraw](03-multi-target-counter.excalidraw) | One `Counter.lean` compiled to EVM / Solana / NEAR with validation gates |
| [04-capability-routing.excalidraw](04-capability-routing.excalidraw) | Capability registry, target profiles, fail-fast diagnostics |
| [05-developer-workflow.excalidraw](05-developer-workflow.excalidraw) | `proof-forge` CLI commands and `just` recipes |
| [06-codebase-structure.excalidraw](06-codebase-structure.excalidraw) | Repository layout and Lean module roots |
| [07-target-landscape.excalidraw](07-target-landscape.excalidraw) | Target lifecycle stages and implementation families |

## Regenerating

Diagrams are generated from `scripts/generate-excalidraw-diagrams.py`. After editing the script:

```sh
python3 scripts/generate-excalidraw-diagrams.py
```

Manual edits inside Excalidraw will be overwritten if you regenerate from the script — export or copy your changes first.

## Related docs

- [README architecture section](../../README.md#architecture) — Mermaid version of the overview
- [Portable IR](../portable-ir.md) — IR layering spec
- [Capability registry](../capability-registry.md) — capability ids checked at compile time
- [中文架构评审](../zh/architecture-review-2026-07.md) — Chinese architecture review
