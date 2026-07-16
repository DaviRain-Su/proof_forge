#!/usr/bin/env python3
"""Generate Excalidraw (.excalidraw) architecture diagrams for ProofForge V2.

Open any file on https://excalidraw.com (Menu → Open / drag-and-drop), edit,
then export PNG/SVG for README. Re-running this script overwrites the generated
JSON — preserve hand edits first if needed.
"""

from __future__ import annotations

import json
import random
import string
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "docs" / "diagrams"

COLORS = {
    "authoring": "#a5d8ff",
    "frontend": "#c5f6fa",
    "core": "#b2f2bb",
    "routing": "#ffec99",
    "materializer": "#ffd8a8",
    "backend": "#ffc9c9",
    "artifact": "#d0bfff",
    "gate": "#e9ecef",
    "evm": "#ffe8cc",
    "solana": "#c3fae8",
    "near": "#eebefa",
    "noir": "#d0bfff",
    "design": "#dee2e6",
    "archive": "#ffc9c9",
    "neutral": "#ffffff",
    "reject": "#ffa8a8",
}


def gen_id() -> str:
    return "".join(random.choices(string.ascii_letters + string.digits, k=11))


class Diagram:
    def __init__(self, name: str) -> None:
        self.name = name
        self.elements: list[dict] = []
        self._seed = random.randint(1, 999_999)

    def _meta(self) -> dict:
        self._seed += 1
        return {
            "seed": self._seed,
            "version": 1,
            "versionNonce": random.randint(1, 999_999),
            "isDeleted": False,
            "groupIds": [],
            "frameId": None,
            "boundElements": [],
            "updated": 1,
            "link": None,
            "locked": False,
        }

    def title(self, text: str, x: float = 40, y: float = 20, size: int = 28) -> None:
        self.elements.append(
            {
                "id": gen_id(),
                "type": "text",
                "x": x,
                "y": y,
                "width": 1100,
                "height": 40,
                "angle": 0,
                "strokeColor": "#1e1e1e",
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 1,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": None,
                "text": text,
                "fontSize": size,
                "fontFamily": 5,
                "textAlign": "left",
                "verticalAlign": "top",
                "containerId": None,
                "originalText": text,
                "lineHeight": 1.25,
                "autoResize": True,
                **self._meta(),
            }
        )

    def subtitle(self, text: str, x: float = 40, y: float = 58) -> None:
        self.elements.append(
            {
                "id": gen_id(),
                "type": "text",
                "x": x,
                "y": y,
                "width": 1200,
                "height": 30,
                "angle": 0,
                "strokeColor": "#495057",
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 1,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": None,
                "text": text,
                "fontSize": 16,
                "fontFamily": 5,
                "textAlign": "left",
                "verticalAlign": "top",
                "containerId": None,
                "originalText": text,
                "lineHeight": 1.25,
                "autoResize": True,
                **self._meta(),
            }
        )

    def note(self, text: str, x: float, y: float, w: float = 400) -> None:
        self.elements.append(
            {
                "id": gen_id(),
                "type": "text",
                "x": x,
                "y": y,
                "width": w,
                "height": 80,
                "angle": 0,
                "strokeColor": "#495057",
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 1,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": None,
                "text": text,
                "fontSize": 14,
                "fontFamily": 5,
                "textAlign": "left",
                "verticalAlign": "top",
                "containerId": None,
                "originalText": text,
                "lineHeight": 1.25,
                "autoResize": True,
                **self._meta(),
            }
        )

    def box(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        label: str,
        *,
        bg: str = COLORS["neutral"],
        font_size: int = 15,
        align: str = "center",
    ) -> str:
        rid = gen_id()
        tid = gen_id()
        lines = label.count("\n") + 1
        text_h = max(24, lines * font_size * 1.3)
        text_y = y + (h - text_h) / 2
        self.elements.append(
            {
                "id": rid,
                "type": "rectangle",
                "x": x,
                "y": y,
                "width": w,
                "height": h,
                "angle": 0,
                "strokeColor": "#1e1e1e",
                "backgroundColor": bg,
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": {"type": 3},
                "boundElements": [{"id": tid, "type": "text"}],
                **self._meta(),
            }
        )
        self.elements.append(
            {
                "id": tid,
                "type": "text",
                "x": x + 8,
                "y": text_y,
                "width": w - 16,
                "height": text_h,
                "angle": 0,
                "strokeColor": "#1e1e1e",
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 1,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": None,
                "text": label,
                "fontSize": font_size,
                "fontFamily": 5,
                "textAlign": align,
                "verticalAlign": "middle",
                "containerId": rid,
                "originalText": label,
                "lineHeight": 1.25,
                "autoResize": True,
                **self._meta(),
            }
        )
        return rid

    def frame(self, x: float, y: float, w: float, h: float, label: str) -> str:
        fid = gen_id()
        tid = gen_id()
        self.elements.append(
            {
                "id": fid,
                "type": "rectangle",
                "x": x,
                "y": y,
                "width": w,
                "height": h,
                "angle": 0,
                "strokeColor": "#868e96",
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": "dashed",
                "roughness": 1,
                "opacity": 100,
                "roundness": {"type": 3},
                "boundElements": [{"id": tid, "type": "text"}],
                **self._meta(),
            }
        )
        self.elements.append(
            {
                "id": tid,
                "type": "text",
                "x": x + 12,
                "y": y + 8,
                "width": w - 24,
                "height": 24,
                "angle": 0,
                "strokeColor": "#495057",
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 1,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": None,
                "text": label,
                "fontSize": 14,
                "fontFamily": 5,
                "textAlign": "left",
                "verticalAlign": "top",
                "containerId": None,
                "originalText": label,
                "lineHeight": 1.25,
                "autoResize": True,
                **self._meta(),
            }
        )
        return fid

    def arrow(
        self,
        x1: float,
        y1: float,
        x2: float,
        y2: float,
        *,
        label: str | None = None,
        color: str = "#1e1e1e",
        dashed: bool = False,
    ) -> None:
        dx, dy = x2 - x1, y2 - y1
        self.elements.append(
            {
                "id": gen_id(),
                "type": "arrow",
                "x": x1,
                "y": y1,
                "width": dx,
                "height": dy,
                "angle": 0,
                "strokeColor": color,
                "backgroundColor": "transparent",
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": "dashed" if dashed else "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": {"type": 2},
                "points": [[0, 0], [dx, dy]],
                "lastCommittedPoint": None,
                "startBinding": None,
                "endBinding": None,
                "startArrowhead": None,
                "endArrowhead": "arrow",
                **self._meta(),
            }
        )
        if label:
            self.elements.append(
                {
                    "id": gen_id(),
                    "type": "text",
                    "x": x1 + dx / 2 - 50,
                    "y": y1 + dy / 2 - 18,
                    "width": 140,
                    "height": 24,
                    "angle": 0,
                    "strokeColor": "#495057",
                    "backgroundColor": "#ffffff",
                    "fillStyle": "solid",
                    "strokeWidth": 1,
                    "strokeStyle": "solid",
                    "roughness": 1,
                    "opacity": 100,
                    "roundness": None,
                    "text": label,
                    "fontSize": 13,
                    "fontFamily": 5,
                    "textAlign": "center",
                    "verticalAlign": "middle",
                    "containerId": None,
                    "originalText": label,
                    "lineHeight": 1.25,
                    "autoResize": True,
                    **self._meta(),
                }
            )

    def save(self, filename: str) -> None:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        path = OUT_DIR / filename
        payload = {
            "type": "excalidraw",
            "version": 2,
            "source": "https://excalidraw.com",
            "elements": self.elements,
            "appState": {
                "gridSize": 20,
                "viewBackgroundColor": "#ffffff",
            },
            "files": {},
        }
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"Wrote {path}")


def diagram_01_overview() -> None:
    d = Diagram("overview")
    d.title("ProofForge V2 — Architecture Overview")
    d.subtitle("One portable program source → target-neutral semantics → target-owned materialization")

    d.frame(30, 100, 1180, 110, "Author / CI (trusted input boundary)")
    d.box(60, 140, 280, 50, "program … where\n(Lean portable DSL)", bg=COLORS["authoring"])
    d.box(370, 140, 280, 50, "CLI: --target / profiles\nproof-forge-next", bg=COLORS["authoring"])
    d.box(680, 140, 500, 50, "No top-level kind: not contract | circuit | zkVM in source", bg=COLORS["authoring"], font_size=14)

    d.frame(30, 240, 1180, 170, "proof-forge-next (compiler, not a chain VM)")
    d.box(60, 280, 200, 100, "Source Frontend\nLean Syntax\n+ preflight\n→ Source.Program", bg=COLORS["frontend"], font_size=13)
    d.box(290, 280, 200, 100, "Semantic Engine\nTyped → Semantic\n+ Requirements", bg=COLORS["core"], font_size=13)
    d.box(520, 280, 200, 100, "Support Resolver\nexact SupportClaim\nfail closed", bg=COLORS["routing"], font_size=13)
    d.box(750, 280, 200, 100, "Materializers\nPlan → TargetIR\n(associated types)", bg=COLORS["materializer"], font_size=13)
    d.box(980, 280, 200, 100, "Artifact Pipeline\natomic OutputSet\n+ provenance", bg=COLORS["artifact"], font_size=13)

    d.arrow(260, 330, 290, 330)
    d.arrow(490, 330, 520, 330)
    d.arrow(720, 330, 750, 330)
    d.arrow(950, 330, 980, 330)

    d.frame(30, 440, 1180, 150, "Phase-1 targets (target-owned Plan; INV: semantics unchanged by --target)")
    d.box(60, 485, 250, 80, "EVM\nYul → solc bytecode\nruntime-validated-alpha", bg=COLORS["evm"], font_size=13)
    d.box(340, 485, 250, 80, "Solana\n.sbpf-plan + IDL\nplan-only (no ELF yet)", bg=COLORS["solana"], font_size=13)
    d.box(620, 485, 250, 80, "NEAR\nWAT → Wasm\nwasm-validated-alpha", bg=COLORS["near"], font_size=13)
    d.box(900, 485, 280, 80, "Noir\n.nr packages\nsource-only (no proof)", bg=COLORS["noir"], font_size=13)

    d.arrow(1080, 380, 1080, 440)
    d.arrow(185, 380, 185, 480)
    d.arrow(465, 380, 465, 480)
    d.arrow(745, 380, 745, 480)
    d.arrow(1040, 380, 1040, 480)

    d.frame(30, 620, 1180, 120, "Outside compiler (untrusted / explicit)")
    d.box(60, 660, 260, 55, "Official packagers\nsolc / wat2wasm / …", bg=COLORS["gate"], font_size=13)
    d.box(350, 660, 260, 55, "Local runtime\nAnvil / sandbox / …", bg=COLORS["gate"], font_size=13)
    d.box(640, 660, 260, 55, "deploy / prove / verify\n(never implicit)", bg=COLORS["gate"], font_size=13)
    d.box(930, 660, 250, 55, "Network RPC / keys\nnot compiler inputs", bg=COLORS["reject"], font_size=13)

    d.note(
        "Invariants: INV-001 source layers ignore TargetId · INV-002 unequal map → reject · "
        "INV-005 no fallback success · INV-010 clean-room independent of active/ (v1 archive)",
        40,
        760,
        1180,
    )
    d.save("01-architecture-overview.excalidraw")


def diagram_02_pipeline() -> None:
    d = Diagram("pipeline")
    d.title("ProofForge V2 — Compilation Pipeline")
    d.subtitle("Syntax is not domain semantics: decoder → typed check → neutral core → target Plan/IR")

    stages = [
        (40, "1. Parse", "Lean Parser\nportable commands\nonly", COLORS["frontend"]),
        (210, "2. Preflight", "node / nesting\nbudgets\nPF-BOUND-001", COLORS["frontend"]),
        (380, "3. Decode", "Source.Program\nneutral AST", COLORS["frontend"]),
        (550, "4. Check", "Typed.Program\nname/type/effect", COLORS["core"]),
        (720, "5. Normalize", "Semantic.Program\n+ Requirements", COLORS["core"]),
        (890, "6. Resolve", "ResolvedProgram\nexact claims", COLORS["routing"]),
        (1060, "7. Materialize", "Plan → IR →\nOutputSet", COLORS["materializer"]),
    ]
    y = 140
    for x, title, body, color in stages:
        d.box(x, y, 155, 110, f"{title}\n{body}", bg=color, font_size=13)
    for i in range(len(stages) - 1):
        x1 = stages[i][0] + 155
        x2 = stages[i + 1][0]
        d.arrow(x1, y + 55, x2, y + 55)

    d.frame(40, 300, 1175, 200, "Failure policy (fail closed — never downgrade or legacy fallback)")
    d.box(70, 350, 250, 110, "Unsupported req\n→ PF-REQ-UNSUPPORTED\nno best-effort emit", bg=COLORS["reject"], font_size=13)
    d.box(360, 350, 250, 110, "Research target\n→ PF-TARGET-NOT-\nIMPLEMENTED", bg=COLORS["reject"], font_size=13)
    d.box(650, 350, 250, 110, "Tool missing / hash\n→ PF-TOOLCHAIN-*\nno silent PATH tool", bg=COLORS["reject"], font_size=13)
    d.box(940, 350, 240, 110, "Output collision\n→ PF-OUTPUT-\nCOLLISION", bg=COLORS["reject"], font_size=13)

    d.frame(40, 540, 1175, 160, "Reference semantics (target-neutral)")
    d.box(
        70,
        590,
        1100,
        80,
        "step : State → Invocation → ExternalResponses → Outcome\n"
        "returned | reverted (atomic rollback) | trapped  ·  target may only preserve or reject",
        bg=COLORS["core"],
        font_size=14,
    )
    d.save("02-compilation-pipeline.excalidraw")


def diagram_03_one_program_four_targets() -> None:
    d = Diagram("four-targets")
    d.title("ProofForge V2 — One Program, Four Phase-1 Targets")
    d.subtitle("Same Source/Semantic hash; --target only changes materialization + artifact encoding")

    d.box(
        420,
        120,
        340,
        120,
        "program Counter where\n  state count : UInt64\n  entry increment …\n  view get …",
        bg=COLORS["authoring"],
        font_size=14,
    )
    d.box(420, 280, 340, 70, "Semantic.Program\n+ ProgramRequirements", bg=COLORS["core"], font_size=14)
    d.arrow(590, 240, 590, 280)

    targets = [
        (40, "evm", "EvmPlan\nYul + ABI + .bin\nAnvil smoke ✓", COLORS["evm"]),
        (340, "solana", "SolanaPlan\n.sbpf-plan + IDL\nno ELF yet", COLORS["solana"]),
        (640, "near", "NearPlan\nWAT + Wasm\nno receipt yet", COLORS["near"]),
        (940, "noir", "NoirPlan\n.nr relations\nno ACIR/proof", COLORS["noir"]),
    ]
    for x, name, body, color in targets:
        d.box(x, 420, 260, 120, f"--target {name}\n{body}", bg=color, font_size=13)
        d.arrow(590, 350, x + 130, 420)

    d.note(
        "Honest maturity: do not upgrade plan-only / source-only artifacts to runtime or proof-complete claims.",
        40,
        580,
        1100,
    )
    d.save("03-one-program-four-targets.excalidraw")


def diagram_04_requirements_support() -> None:
    d = Diagram("requirements")
    d.title("ProofForge V2 — Requirements & Support Resolver")
    d.subtitle("Exact SupportClaim lookup; aggregate all rejections; materializer never ignores requirements")

    d.box(60, 140, 280, 100, "Semantic.Program\ninferred requirements\nvalue / state / effect\ndisclosure / failure …", bg=COLORS["core"], font_size=13)
    d.box(420, 140, 280, 100, "CLI TargetId\n(+ CodegenProfileId\n+ NetworkProfileId\nare separate)", bg=COLORS["routing"], font_size=13)
    d.box(780, 140, 300, 100, "Target Registry\nstatic descriptors\nPhase-1 vs design-only", bg=COLORS["routing"], font_size=13)

    d.box(300, 300, 580, 90, "Support Resolver\n1 exact target · 2 claim digests · 3 preconditions · 4 all rejections · 5 ResolvedProgram", bg=COLORS["routing"], font_size=13)
    d.arrow(200, 240, 420, 300)
    d.arrow(560, 240, 560, 300)
    d.arrow(930, 240, 700, 300)

    d.box(80, 460, 360, 100, "ResolvedProgram target\n→ Materializer.makePlan\n→ lower → emit", bg=COLORS["materializer"], font_size=14)
    d.box(560, 460, 420, 100, "Any rejection\n→ CompileError\nno partial success artifact", bg=COLORS["reject"], font_size=14)
    d.arrow(450, 390, 260, 460, label="all ok")
    d.arrow(650, 390, 770, 460, label="any fail")

    d.note(
        "Axes stay independent: disclosure ≠ authority ≠ stateCustody · artifact encoding ≠ execution/proof/settlement",
        60,
        600,
        1000,
    )
    d.save("04-requirements-support.excalidraw")


def diagram_05_target_landscape() -> None:
    d = Diagram("targets")
    d.title("ProofForge V2 — Target Landscape")
    d.subtitle("Family is a reading view only; compiler decisions use multi-axis TargetDescriptor + SupportClaim")

    d.frame(40, 120, 560, 280, "Phase 1 — implement")
    d.box(70, 170, 240, 70, "evm · contract VM\nruntime-validated-alpha", bg=COLORS["evm"], font_size=13)
    d.box(330, 170, 240, 70, "solana · SVM accounts\nplan-only", bg=COLORS["solana"], font_size=13)
    d.box(70, 270, 240, 70, "near · Wasm host\nwasm-validated-alpha", bg=COLORS["near"], font_size=13)
    d.box(330, 270, 240, 70, "noir · circuit\nsource-only", bg=COLORS["noir"], font_size=13)

    d.frame(640, 120, 560, 280, "Design / research only — no product backend claim")
    d.box(670, 170, 240, 70, "cosmwasm · soroban · icp\nWasm hosts (own Plans)", bg=COLORS["design"], font_size=13)
    d.box(930, 170, 240, 70, "openvm · zkVM", bg=COLORS["design"], font_size=13)
    d.box(670, 270, 240, 70, "aleo · psy\nZK app chains", bg=COLORS["design"], font_size=13)
    d.box(930, 270, 240, 70, "shared Wasm = AST/encode\nnever shared host Plan", bg=COLORS["design"], font_size=13)

    d.frame(40, 440, 1160, 160, "Maturity ladder (no skipping)")
    steps = [
        (70, "research"),
        (260, "design"),
        (450, "implemented"),
        (680, "runtime-\nvalidated"),
        (910, "network / proof-\nvalidated"),
    ]
    for x, label in steps:
        d.box(x, 500, 170, 70, label, bg=COLORS["gate"], font_size=13)
    for i in range(len(steps) - 1):
        d.arrow(steps[i][0] + 170, 535, steps[i + 1][0], 535)

    d.save("05-target-landscape.excalidraw")


def diagram_06_repo_layout() -> None:
    d = Diagram("repo")
    d.title("ProofForge V2 — Repository Layout")
    d.subtitle("Root is the product. active/ is archived v1 research only — never a runtime dependency.")

    d.frame(40, 120, 700, 420, "Repository root = proof-forge-next (V2)")
    d.box(70, 170, 300, 55, "ProofForgeV2/\nCore · Language · Targets · CLI", bg=COLORS["core"], font_size=13)
    d.box(400, 170, 300, 55, "Examples/ · Tests/\nportable programs + gates", bg=COLORS["authoring"], font_size=13)
    d.box(70, 250, 300, 55, "docs/\nPRD · arch · specs · ADR", bg=COLORS["frontend"], font_size=13)
    d.box(400, 250, 300, 55, "scripts/ · sandbox/\nclean-room + evidence", bg=COLORS["gate"], font_size=13)
    d.box(70, 330, 630, 55, "justfile · lakefile · lean-toolchain · toolchains.lock.json", bg=COLORS["routing"], font_size=13)
    d.box(70, 410, 630, 55, "CI: just ci  (Linux portable) · local just check / v2-clean-room-alpha (macOS hermetic)", bg=COLORS["gate"], font_size=13)

    d.frame(780, 120, 400, 420, "active/ archive (v1)")
    d.box(810, 180, 340, 120, "Legacy ProofForge\nProofForge/ · testkit ·\nold CI · product SDK\nresearch reference only", bg=COLORS["archive"], font_size=14)
    d.box(810, 340, 340, 120, "Forbidden for V2:\nimport · PATH fallback ·\noracle · symlink ·\nLEAN_PATH reuse", bg=COLORS["reject"], font_size=14)

    d.arrow(740, 330, 810, 330, label="no edge", dashed=True, color="#c92a2a")
    d.save("06-repo-layout.excalidraw")


def diagram_07_modules() -> None:
    d = Diagram("modules")
    d.title("ProofForge V2 — Module Boundaries")
    d.subtitle("Each module owns its contract; ValidationHarness depends on product modules, never the reverse")

    d.box(480, 120, 240, 60, "CliOrchestrator", bg=COLORS["routing"], font_size=14)
    d.box(80, 240, 220, 80, "SourceFrontend\n(no TargetId)", bg=COLORS["frontend"], font_size=13)
    d.box(340, 240, 220, 80, "SemanticEngine\n(no registry)", bg=COLORS["core"], font_size=13)
    d.box(600, 240, 220, 80, "SupportResolver\n(no emitter)", bg=COLORS["routing"], font_size=13)
    d.box(860, 240, 260, 80, "MaterializerRuntime\nper-target Plan/IR", bg=COLORS["materializer"], font_size=13)

    d.arrow(520, 180, 190, 240)
    d.arrow(560, 180, 450, 240)
    d.arrow(600, 180, 710, 240)
    d.arrow(640, 180, 960, 240)

    d.box(860, 380, 260, 70, "WasmEncoder\n(AST only; no host ABI)", bg=COLORS["near"], font_size=13)
    d.box(480, 380, 260, 70, "ArtifactPipeline\natomic rename + hashes", bg=COLORS["artifact"], font_size=13)
    d.box(100, 380, 260, 70, "ValidationHarness\ntests only", bg=COLORS["gate"], font_size=13)

    d.arrow(990, 320, 990, 380, dashed=True, label="NEAR…")
    d.arrow(990, 320, 610, 380)
    d.arrow(190, 320, 230, 380, dashed=True)

    d.note(
        "Import boundary gate: SourceFrontend ↛ Targets · SemanticEngine ↛ Registry · product ↛ Tests",
        80,
        500,
        1000,
    )
    d.save("07-module-boundaries.excalidraw")


def main() -> None:
    random.seed(42)  # stable-ish ids across runs for smaller diffs
    diagram_01_overview()
    diagram_02_pipeline()
    diagram_03_one_program_four_targets()
    diagram_04_requirements_support()
    diagram_05_target_landscape()
    diagram_06_repo_layout()
    diagram_07_modules()
    print(f"\nOpen any file from {OUT_DIR} on https://excalidraw.com")


if __name__ == "__main__":
    main()
