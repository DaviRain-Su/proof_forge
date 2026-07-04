#!/usr/bin/env python3
"""Generate Excalidraw (.excalidraw) architecture diagrams for ProofForge."""

from __future__ import annotations

import json
import random
import string
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "docs" / "diagrams"

COLORS = {
    "authoring": "#a5d8ff",
    "core": "#b2f2bb",
    "routing": "#ffec99",
    "backend": "#ffc9c9",
    "artifact": "#d0bfff",
    "gate": "#e9ecef",
    "evm": "#ffe8cc",
    "solana": "#c3fae8",
    "near": "#eebefa",
    "psy": "#ffd8a8",
    "neutral": "#ffffff",
    "title": "#ffffff",
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
        tid = gen_id()
        self.elements.append(
            {
                "id": tid,
                "type": "text",
                "x": x,
                "y": y,
                "width": 900,
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
        tid = gen_id()
        self.elements.append(
            {
                "id": tid,
                "type": "text",
                "x": x,
                "y": y,
                "width": 1100,
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

    def box(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        label: str,
        *,
        bg: str = COLORS["neutral"],
        font_size: int = 16,
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
    ) -> None:
        aid = gen_id()
        dx, dy = x2 - x1, y2 - y1
        self.elements.append(
            {
                "id": aid,
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
                "strokeStyle": "solid",
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
            lx = x1 + dx / 2 - 40
            ly = y1 + dy / 2 - 20
            self.elements.append(
                {
                    "id": gen_id(),
                    "type": "text",
                    "x": lx,
                    "y": ly,
                    "width": 120,
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
                    "fontSize": 14,
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

    def diamond(self, cx: float, cy: float, size: float, label: str) -> str:
        did = gen_id()
        tid = gen_id()
        x, y = cx - size / 2, cy - size / 2
        self.elements.append(
            {
                "id": did,
                "type": "diamond",
                "x": x,
                "y": y,
                "width": size,
                "height": size,
                "angle": 0,
                "strokeColor": "#1e1e1e",
                "backgroundColor": COLORS["routing"],
                "fillStyle": "solid",
                "strokeWidth": 2,
                "strokeStyle": "solid",
                "roughness": 1,
                "opacity": 100,
                "roundness": {"type": 2},
                "boundElements": [{"id": tid, "type": "text"}],
                **self._meta(),
            }
        )
        self.elements.append(
            {
                "id": tid,
                "type": "text",
                "x": x + 10,
                "y": y + size / 2 - 20,
                "width": size - 20,
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
                "text": label,
                "fontSize": 14,
                "fontFamily": 5,
                "textAlign": "center",
                "verticalAlign": "middle",
                "containerId": did,
                "originalText": label,
                "lineHeight": 1.25,
                "autoResize": True,
                **self._meta(),
            }
        )
        return did

    def save(self, filename: str) -> None:
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
        path = OUT_DIR / filename
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"Wrote {path}")


def diagram_architecture_overview() -> None:
    d = Diagram("architecture")
    d.title("ProofForge — Architecture Overview")
    d.subtitle("Lean-first multi-chain smart contract platform: one source, many targets")

    d.frame(30, 100, 1140, 130, "Authoring (user-facing, chain-neutral)")
    sdk = d.box(60, 140, 200, 70, "Lean SDK\ncontract_source", bg=COLORS["authoring"])
    tok = d.box(290, 140, 200, 70, "Token SDK\nTokenSpec", bg=COLORS["authoring"])
    learn = d.box(520, 140, 200, 70, ".learn parser\n(frozen compat)", bg=COLORS["authoring"])
    ext = d.box(750, 140, 380, 70, "Target Extension SDKs\n(Solana PDA/CPI, EVM guards…)", bg=COLORS["authoring"])

    d.frame(30, 260, 1140, 110, "Compiler-owned core")
    spec = d.box(200, 295, 220, 60, "ContractSpec", bg=COLORS["core"])
    ir = d.box(480, 295, 280, 60, "Portable IR\n+ AllocatorConfig", bg=COLORS["core"])
    sem = d.box(820, 295, 300, 60, "IR semantics\n(formal verification)", bg=COLORS["core"])

    d.frame(30, 400, 1140, 110, "Target routing (--target)")
    reg = d.box(80, 435, 240, 60, "Target Registry\nprofiles + bindings", bg=COLORS["routing"])
    cap = d.box(380, 435, 280, 60, "Capability Check\nreject unsupported", bg=COLORS["routing"])
    plan = d.box(720, 435, 400, 60, "CapabilityPlan + target metadata", bg=COLORS["routing"])

    d.frame(30, 540, 1140, 120, "Backends")
    evm = d.box(60, 580, 150, 60, "EVM\nPlan→Yul→solc", bg=COLORS["evm"])
    sol = d.box(230, 580, 150, 60, "Solana\nsBPF asm→ELF", bg=COLORS["solana"])
    near = d.box(400, 580, 150, 60, "NEAR\nEmitWat→wasm", bg=COLORS["near"])
    psy = d.box(570, 580, 150, 60, "Psy/DPN\n.psy→Dargo", bg=COLORS["psy"])
    aleo = d.box(740, 580, 150, 60, "Aleo\nLeo package", bg=COLORS["backend"])
    cfw = d.box(910, 580, 150, 60, "CF Workers\nTypeScript", bg=COLORS["backend"])

    d.frame(30, 690, 1140, 130, "Artifacts + validation gates")
    art = d.box(80, 730, 500, 70, "Artifacts: bytecode / ELF / wasm / circuit\n+ ABI / IDL / deploy manifests / TS clients", bg=COLORS["artifact"])
    gates = d.box(640, 730, 480, 70, "Gates: just check · testkit · Foundry\nMollusk · offline host · dargo/leo", bg=COLORS["gate"])

    # vertical flow
    for src_x, dst_y in [(160, 260), (390, 260), (620, 260), (940, 260)]:
        d.arrow(src_x, 210, 310, 255)
    d.arrow(310, 355, 310, 395)
    d.arrow(620, 355, 520, 395)
    d.arrow(970, 355, 920, 395)
    d.arrow(520, 495, 135, 535)
    d.arrow(520, 495, 305, 535)
    d.arrow(520, 495, 475, 535)
    d.arrow(920, 495, 135, 535, color="#868e96")
    d.arrow(135, 640, 135, 685)
    d.arrow(305, 640, 305, 685)
    d.arrow(475, 640, 475, 685)
    d.arrow(645, 640, 645, 685)
    d.arrow(815, 640, 815, 685)
    d.arrow(985, 640, 985, 685)
    d.arrow(330, 800, 630, 800)

    d.save("01-architecture-overview.excalidraw")


def diagram_compilation_pipeline() -> None:
    d = Diagram("pipeline")
    d.title("ProofForge — Compilation Pipeline")
    d.subtitle("From Lean contract source to chain-native artifacts")

    steps = [
        (60, "1. Author", "contract_source / TokenSpec / .learn\n→ Contract Intent API", COLORS["authoring"]),
        (60, "2. Load", "ContractLoader finds spec : ContractSpec\nin Lean module", COLORS["core"]),
        (60, "3. IR", "Portable IR Module\nentrypoints · state · effects · types", COLORS["core"]),
        (60, "4. Resolve", "--target selects profile\n→ collect capability calls", COLORS["routing"]),
        (60, "5. Check", "requireCapabilities\nunsupported → diagnostic (fail fast)", COLORS["routing"]),
        (60, "6. Plan", "CapabilityPlan + semantic plan\n(storage layout, selectors…)", COLORS["routing"]),
        (60, "7. Lower", "Backend renderModule\n→ Yul / sBPF asm / WAT / .psy / Leo / TS", COLORS["backend"]),
        (60, "8. Toolchain", "External tools: solc · sbpf · wat2wasm\ndargo · leo · tsc/wrangler", COLORS["artifact"]),
        (60, "9. Output", "Primary artifact + proof-forge-artifact.json\nselectors · capabilities · deploy hints", COLORS["artifact"]),
    ]

    y = 110
    prev_bottom = None
    for _, title, body, color in steps:
        d.box(60, y, 180, 50, title, bg=color, font_size=18)
        d.box(280, y, 860, 50, body, bg=COLORS["neutral"], align="left")
        if prev_bottom is not None:
            d.arrow(150, prev_bottom, 150, y)
            d.arrow(700, prev_bottom, 700, y)
        prev_bottom = y + 50
        y += 70

    d.frame(980, 110, 200, 560, "EVM detail")
    d.box(1000, 150, 160, 45, "IR Module", bg=COLORS["core"], font_size=14)
    d.arrow(1080, 195, 1080, 215)
    d.box(1000, 215, 160, 45, "Semantic Plan", bg=COLORS["routing"], font_size=14)
    d.arrow(1080, 260, 1080, 280)
    d.box(1000, 280, 160, 45, "Yul AST", bg=COLORS["backend"], font_size=14)
    d.arrow(1080, 325, 1080, 345)
    d.box(1000, 345, 160, 45, "Yul text", bg=COLORS["backend"], font_size=14)
    d.arrow(1080, 390, 1080, 410)
    d.box(1000, 410, 160, 45, "solc", bg=COLORS["artifact"], font_size=14)
    d.arrow(1080, 455, 1080, 475)
    d.box(1000, 475, 160, 45, "bytecode", bg=COLORS["artifact"], font_size=14)

    d.save("02-compilation-pipeline.excalidraw")


def diagram_multi_target() -> None:
    d = Diagram("multi-target")
    d.title("ProofForge — One Contract, Three Targets")
    d.subtitle("Examples/Shared/Counter.lean — same source, --target selects backend")

    src = d.box(420, 110, 340, 80, "Examples/Shared/Counter.lean\ncontract_source Counter do … end", bg=COLORS["authoring"])
    ir = d.box(420, 240, 340, 60, "Portable IR (shared)", bg=COLORS["core"])
    d.arrow(590, 190, 590, 235)

    d.frame(30, 340, 1120, 200, "proof-forge build --target <id>")
    evm = d.box(60, 390, 320, 120, "evm\nLean IR → semantic plan → Yul\n→ solc → Counter.bin", bg=COLORS["evm"])
    sol = d.box(430, 390, 320, 120, "solana-sbpf-asm\nIR → sBPF assembly (.s)\n→ sbpf → Counter.so (ELF)", bg=COLORS["solana"])
    near = d.box(800, 390, 320, 120, "wasm-near\nIR → EmitWat → WAT\n→ wat2wasm → Counter.wasm", bg=COLORS["near"])

    for x in [220, 590, 960]:
        d.arrow(590, 300, x, 385)

    d.frame(30, 570, 1120, 130, "Validation (shared scenarios)")
    d.box(60, 610, 320, 70, "Foundry smoke\njust evm-all", bg=COLORS["gate"])
    d.box(430, 610, 320, 70, "Mollusk / Surfpool\nSolana runtime", bg=COLORS["gate"])
    d.box(800, 610, 320, 70, "offline-host / NEAR stubs\ntestkit scenarios", bg=COLORS["gate"])

    d.arrow(220, 510, 220, 605)
    d.arrow(590, 510, 590, 605)
    d.arrow(960, 510, 960, 605)

    d.box(350, 730, 480, 50, "just portable-counter-multi-target", bg=COLORS["routing"], font_size=18)

    d.save("03-multi-target-counter.excalidraw")


def diagram_capability_routing() -> None:
    d = Diagram("capability")
    d.title("ProofForge — Capability Routing")
    d.subtitle("Unsupported capabilities are rejected at compile time (D-028)")

    mod = d.box(440, 100, 280, 60, "IR Module + intents", bg=COLORS["core"])
    reg = d.box(440, 200, 280, 60, "Target Registry\n--target profile", bg=COLORS["routing"])
    collect = d.box(440, 300, 280, 60, "Collect capability calls\nfrom module + extensions", bg=COLORS["routing"])
    check = d.diamond(480, 400, 200, "All caps\nsupported?")

    d.arrow(580, 160, 580, 195)
    d.arrow(580, 260, 580, 295)
    d.arrow(580, 360, 580, 395)

    ok = d.box(760, 410, 260, 60, "CapabilityPlan\n+ target metadata", bg=COLORS["core"])
    fail = d.box(120, 410, 260, 60, "Structured diagnostic\n(no silent fallback)", bg=COLORS["backend"])
    lower = d.box(760, 520, 260, 60, "Backend lowering\nrenderModule", bg=COLORS["artifact"])

    d.arrow(680, 450, 755, 450, label="yes")
    d.arrow(480, 450, 385, 450, label="no")
    d.arrow(890, 470, 890, 515)

    d.frame(30, 620, 550, 180, "Example capabilities")
    caps = [
        "storage.scalar · storage.map",
        "events.emit · context.caller",
        "crosscall.cpi (Solana)",
        "crosscall.invoke (EVM)",
    ]
    for i, cap in enumerate(caps):
        d.box(50 + (i % 2) * 260, 660 + (i // 2) * 55, 240, 45, cap, bg=COLORS["neutral"], font_size=14)

    d.frame(620, 620, 530, 180, "Target profiles (P0 closed)")
    d.box(640, 660, 150, 50, "evm", bg=COLORS["evm"])
    d.box(810, 660, 150, 50, "solana-sbpf-asm", bg=COLORS["solana"])
    d.box(980, 660, 150, 50, "wasm-near", bg=COLORS["near"])
    d.box(700, 730, 380, 50, "Counter + ValueVault portable on all three", bg=COLORS["routing"], font_size=14)

    d.save("04-capability-routing.excalidraw")


def diagram_developer_workflow() -> None:
    d = Diagram("workflow")
    d.title("ProofForge — Developer Workflow")
    d.subtitle("CLI + just recipes for local development and CI")

    d.frame(30, 100, 520, 420, "Author & compile")
    d.box(60, 140, 460, 55, "1. Write contract_source in Lean\nProofForge.Contract.Source", bg=COLORS["authoring"], align="left")
    d.box(60, 210, 460, 55, "2. proof-forge check --target evm Contract.lean\nStatic validation only", bg=COLORS["routing"], align="left")
    d.box(60, 280, 460, 55, "3. proof-forge build --target evm -o out.bin Contract.lean\nFull compile to artifact", bg=COLORS["core"], align="left")
    d.box(60, 350, 460, 55, "4. proof-forge init --template portable-counter\nScaffold new project", bg=COLORS["authoring"], align="left")
    d.box(60, 420, 460, 55, "5. proof-forge --list-targets / --list-fixtures", bg=COLORS["neutral"], align="left")

    d.frame(580, 100, 570, 420, "just recipes (CI entrypoint)")
    recipes = [
        ("just build", "lake build — compile ProofForge itself"),
        ("just check", "Fast baseline: registry, EVM plan, NEAR, testkit"),
        ("just evm-all", "Full EVM: examples, Foundry, Anvil deploy"),
        ("just ci", "Full local CI sequence"),
        ("just testkit", "Unified cross-target scenario runner"),
        ("just portable-counter-multi-target", "Counter on evm + solana + near"),
    ]
    y = 130
    for cmd, desc in recipes:
        d.box(600, y, 220, 45, cmd, bg=COLORS["routing"], font_size=14)
        d.box(830, y, 300, 45, desc, bg=COLORS["neutral"], font_size=13, align="left")
        y += 58

    d.frame(30, 550, 1120, 100, "Emit intermediate formats")
    d.box(60, 585, 200, 50, "emit --format yul", bg=COLORS["evm"], font_size=13)
    d.box(280, 585, 200, 50, "emit --format elf", bg=COLORS["solana"], font_size=13)
    d.box(500, 585, 200, 50, "emit --format wat", bg=COLORS["near"], font_size=13)
    d.box(720, 585, 200, 50, "emit --format psy", bg=COLORS["psy"], font_size=13)
    d.box(940, 585, 180, 50, "emit --format leo/ts", bg=COLORS["backend"], font_size=13)

    d.save("05-developer-workflow.excalidraw")


def diagram_codebase_structure() -> None:
    d = Diagram("codebase")
    d.title("ProofForge — Codebase Structure")
    d.subtitle("Key directories and Lean module roots")

    root = d.box(480, 90, 200, 50, "ProofForge repo", bg=COLORS["routing"], font_size=18)

    dirs = [
        (60, 180, "ProofForge/", "Compiler core\nContract · IR · Target\nBackend · Cli · Solana · Psy", COLORS["core"]),
        (320, 180, "Examples/", "Golden outputs\nShared/ Evm/ Solana/\nnear/ Psy/ Aleo/", COLORS["authoring"]),
        (580, 180, "Tests/", "Lean smoke tests\nplan · diagnostics · CLI", COLORS["gate"]),
        (840, 180, "testkit/", "RFC 0007\nRust scenario runner\nrevm · Mollusk · NEAR", COLORS["artifact"]),
        (60, 340, "docs/", "RFCs · IR spec\ndecisions · targets/", COLORS["neutral"]),
        (320, 340, "scripts/", "Per-target validation\nsmokes (evm, solana…)", COLORS["neutral"]),
        (580, 340, "templates/", "portable-counter\nstarter template", COLORS["authoring"]),
        (840, 340, "runtime/", "offline-host\nWasmtime NEAR tests", COLORS["near"]),
    ]

    for x, y, title, body, color in dirs:
        d.arrow(580, 140, x + 100, y - 5)
        d.box(x, y, 220, 45, title, bg=color, font_size=16)
        d.box(x, y + 55, 220, 90, body, bg=COLORS["neutral"], font_size=13)

    d.frame(60, 480, 500, 200, "Lean package roots (lakefile.lean)")
    modules = [
        "ProofForge.Contract — authoring SDK",
        "ProofForge.IR — portable IR",
        "ProofForge.Target — registry + adapter",
        "ProofForge.Backend — per-target lowering",
        "ProofForge.Cli — proof-forge executable",
    ]
    for i, m in enumerate(modules):
        d.box(80, 520 + i * 32, 460, 28, m, bg=COLORS["core"], font_size=13, align="left")

    d.frame(600, 480, 550, 200, "Build outputs (gitignored)")
    d.box(620, 520, 240, 50, "build/\nper-target artifacts", bg=COLORS["artifact"])
    d.box(880, 520, 240, 50, ".lake/\nLean build cache", bg=COLORS["artifact"])

    d.save("06-codebase-structure.excalidraw")


def diagram_target_landscape() -> None:
    d = Diagram("targets")
    d.title("ProofForge — Target Landscape")
    d.subtitle("Lifecycle stages per docs/targets/README.md")

    d.frame(30, 100, 350, 280, "Baseline / Experimental (P0)")
    d.box(50, 140, 310, 55, "evm — Yul → solc → bytecode", bg=COLORS["evm"], align="left")
    d.box(50, 205, 310, 55, "solana-sbpf-asm — sBPF asm → ELF", bg=COLORS["solana"], align="left")
    d.box(50, 270, 310, 55, "wasm-near — EmitWat → wasm", bg=COLORS["near"], align="left")
    d.box(50, 335, 310, 35, "✓ Counter + ValueVault portable", bg=COLORS["routing"], font_size=13)

    d.frame(410, 100, 350, 280, "Experimental (restricted)")
    d.box(430, 140, 310, 55, "psy-dpn — .psy → Dargo → circuit", bg=COLORS["psy"], align="left")
    d.box(430, 220, 310, 70, "Multi-chain Token SDK\nERC-20 / SPL Token-2022", bg=COLORS["authoring"], align="left")

    d.frame(790, 100, 360, 280, "Research spikes")
    d.box(810, 140, 320, 50, "aleo-leo — Leo package", bg=COLORS["backend"], align="left")
    d.box(810, 200, 320, 50, "wasm-cloudflare-workers — TS", bg=COLORS["backend"], align="left")
    d.box(810, 260, 320, 50, "move-aptos / move-sui — Move", bg=COLORS["neutral"], align="left")
    d.box(810, 320, 320, 50, "wasm-cosmwasm — WAT spike", bg=COLORS["neutral"], align="left")

    ir = d.box(380, 420, 420, 60, "All routes consume the same Portable IR", bg=COLORS["core"], font_size=16)
    for fx in [205, 585, 970]:
        d.arrow(fx, 380, 590, 415)

    d.frame(30, 510, 1120, 100, "Implementation families (RFC 0002)")
    d.box(50, 550, 200, 45, "Direct compiler\n(EVM Yul)", bg=COLORS["evm"], font_size=13)
    d.box(270, 550, 200, 45, "Wasm host adapter\n(NEAR, CosmWasm)", bg=COLORS["near"], font_size=13)
    d.box(490, 550, 200, 45, "Binary toolchain\n(Solana sbpf)", bg=COLORS["solana"], font_size=13)
    d.box(710, 550, 200, 45, "Source codegen\n(Move, Leo, Psy)", bg=COLORS["psy"], font_size=13)
    d.box(930, 550, 200, 45, "Policy / ZK research\n(docs-only)", bg=COLORS["gate"], font_size=13)

    d.save("07-target-landscape.excalidraw")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    diagram_architecture_overview()
    diagram_compilation_pipeline()
    diagram_multi_target()
    diagram_capability_routing()
    diagram_developer_workflow()
    diagram_codebase_structure()
    diagram_target_landscape()
    print(f"Generated 7 diagrams in {OUT_DIR}")


if __name__ == "__main__":
    main()
