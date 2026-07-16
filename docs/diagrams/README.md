---
id: DIAGRAM-INDEX
title: Architecture diagrams (Excalidraw + PNG)
status: draft
owner: architecture
updated: 2026-07-16
normative: false
---

# ProofForge V2 Architecture Diagrams

Editable [Excalidraw](https://excalidraw.com) sources **and** exported PNG previews for
the **current V2 root product** (`proof-forge-next`), not the archived v1 tree in
`active/`.

## Naming

Each diagram is a paired pair with a stable number:

| # | PNG (README / GitHub) | Excalidraw (edit) |
|---|---|---|
| 01 | [01-architecture-overview.png](01-architecture-overview.png) | [01-architecture-overview.excalidraw](01-architecture-overview.excalidraw) |
| 02 | [02-compilation-pipeline.png](02-compilation-pipeline.png) | [02-compilation-pipeline.excalidraw](02-compilation-pipeline.excalidraw) |
| 03 | [03-one-program-four-targets.png](03-one-program-four-targets.png) | [03-one-program-four-targets.excalidraw](03-one-program-four-targets.excalidraw) |
| 04 | [04-requirements-support.png](04-requirements-support.png) | [04-requirements-support.excalidraw](04-requirements-support.excalidraw) |
| 05 | [05-target-landscape.png](05-target-landscape.png) | [05-target-landscape.excalidraw](05-target-landscape.excalidraw) |
| 06 | [06-repo-layout.png](06-repo-layout.png) | [06-repo-layout.excalidraw](06-repo-layout.excalidraw) |
| 07 | [07-module-boundaries.png](07-module-boundaries.png) | [07-module-boundaries.excalidraw](07-module-boundaries.excalidraw) |

Root [README](../../README.md) embeds **01–03** inline; **04–07** are linked from the
“更多图” table so the landing page stays scannable.

## Contents

| # | Contents |
|---|---|
| 01 | End-to-end system context: author → compiler layers → Phase-1 targets → external tools |
| 02 | Parse → preflight → decode → typed → semantic → resolve → materialize + fail-closed policy |
| 03 | One Counter source fan-out to EVM / Solana / NEAR / Noir with honest maturity |
| 04 | Requirements inference and exact SupportClaim resolver |
| 05 | Phase-1 vs design-only targets and maturity ladder |
| 06 | Root V2 product vs `active/` v1 archive boundary |
| 07 | Module ownership inside the compiler |

## How to edit and re-export

1. Open [https://excalidraw.com](https://excalidraw.com).
2. **Menu → Open** the matching `0N-*.excalidraw` file.
3. Edit labels / layout.
4. **Export image → PNG** (2× scale recommended for GitHub).
5. Save/overwrite the matching `0N-*.png` in this directory (same basename).

VS Code: install the Excalidraw extension and edit the `.excalidraw` files in-repo.

## Regenerate Excalidraw JSON

```bash
python3 scripts/generate-excalidraw-diagrams.py
```

This **overwrites** the `.excalidraw` JSON only (not PNGs). Export or copy hand
edits first. After changing JSON, re-export PNGs so the two stay in sync.

## Normative sources

Diagrams are illustrations. When labels disagree with code or accepted specs,
**code and accepted docs win**:

- [Architecture](../02-architecture.md)
- [Target index](../targets/README.md)
- [Modules](../modules/README.md)
- [Document status](../document-status.md)
