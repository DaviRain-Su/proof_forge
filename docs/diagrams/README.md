---
id: DIAGRAM-INDEX
title: Architecture diagrams (Excalidraw)
status: draft
owner: architecture
updated: 2026-07-16
normative: false
---

# ProofForge V2 Architecture Diagrams

Editable sources for [Excalidraw](https://excalidraw.com). These diagrams describe
the **current V2 root product** (`proof-forge-next`), not the archived v1 tree in
`active/`.

## How to use

1. Open [https://excalidraw.com](https://excalidraw.com).
2. **Menu → Open** (or drag-and-drop) a `*.excalidraw` file from this directory.
3. Edit labels / layout as needed.
4. **Export image → PNG or SVG** for README / slides.
5. Drop exports beside these sources (e.g. `01-architecture-overview.png`) and
   link them from the root [README](../../README.md).

VS Code: install the Excalidraw extension and open the same files in-repo.

## Catalog

| File | Contents |
|---|---|
| [01-architecture-overview.excalidraw](01-architecture-overview.excalidraw) | End-to-end system context: author → compiler layers → Phase-1 targets → external tools |
| [02-compilation-pipeline.excalidraw](02-compilation-pipeline.excalidraw) | Parse → preflight → decode → typed → semantic → resolve → materialize + fail-closed policy |
| [03-one-program-four-targets.excalidraw](03-one-program-four-targets.excalidraw) | One Counter source fan-out to EVM / Solana / NEAR / Noir with honest maturity |
| [04-requirements-support.excalidraw](04-requirements-support.excalidraw) | Requirements inference and exact SupportClaim resolver |
| [05-target-landscape.excalidraw](05-target-landscape.excalidraw) | Phase-1 vs design-only targets and maturity ladder |
| [06-repo-layout.excalidraw](06-repo-layout.excalidraw) | Root V2 product vs `active/` v1 archive boundary |
| [07-module-boundaries.excalidraw](07-module-boundaries.excalidraw) | Module ownership inside the compiler |

## Regenerate

```bash
python3 scripts/generate-excalidraw-diagrams.py
```

Regeneration **overwrites** the JSON. Export or copy hand edits first.

## Normative sources

Diagrams are illustrations. When labels disagree with code or accepted specs,
**code and accepted docs win**:

- [Architecture](../02-architecture.md)
- [Target index](../targets/README.md)
- [Modules](../modules/README.md)
- [Document status](../document-status.md)
