#!/usr/bin/env python3
"""Generate presentation-quality SVG architecture diagrams for ProofForge.

Output: docs/diagrams/svg/*.{zh,en}.svg

These SVGs render inline on GitHub and in most Markdown previews. For
hand-editable whiteboard copies, also see docs/diagrams/*.excalidraw
(regenerate with scripts/generate-excalidraw-diagrams.py).
"""

from __future__ import annotations

from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "docs" / "diagrams" / "svg"

C = {
    "bg": "#fafbfc",
    "ink": "#1a1d23",
    "muted": "#5c6570",
    "author": "#d6ebff",
    "author_b": "#3b82f6",
    "front": "#e0f2fe",
    "core": "#dcfce7",
    "core_b": "#16a34a",
    "target": "#fef9c3",
    "target_b": "#ca8a04",
    "evm": "#ffedd5",
    "sol": "#ccfbf1",
    "near": "#f3e8ff",
    "art": "#ede9fe",
    "gate": "#f1f5f9",
}


def esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def svg_open(w: int, h: int, title: str) -> str:
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">
  <defs>
    <filter id="s" x="-4%" y="-4%" width="108%" height="112%">
      <feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#0f172a" flood-opacity="0.08"/>
    </filter>
    <marker id="arr" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
      <path d="M0,0 L6,3 L0,6 Z" fill="{C['muted']}"/>
    </marker>
    <style>
      .t {{ font-family: ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif; }}
      .title {{ font-size: 22px; font-weight: 700; fill: {C['ink']}; }}
      .sub {{ font-size: 13px; fill: {C['muted']}; }}
      .b {{ font-size: 13px; font-weight: 600; fill: {C['ink']}; }}
      .s {{ font-size: 11px; fill: {C['muted']}; }}
      .tiny {{ font-size: 10px; fill: {C['muted']}; }}
    </style>
  </defs>
  <rect width="100%" height="100%" fill="{C['bg']}"/>
'''


def svg_close() -> str:
    return "</svg>\n"


def round_rect(
    x: float, y: float, w: float, h: float, fill: str, stroke: str, sw: float = 1.5, r: float = 12
) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" ry="{r}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}" filter="url(#s)"/>'
    )


def text(x: float, y: float, s: str, cls: str = "b", anchor: str = "middle") -> str:
    return f'<text x="{x}" y="{y}" class="t {cls}" text-anchor="{anchor}">{esc(s)}</text>'


def arrow(x1: float, y1: float, x2: float, y2: float) -> str:
    return (
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{C["muted"]}" '
        f'stroke-width="2" marker-end="url(#arr)"/>'
    )


def write(name: str, body: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    path.write_text(body, encoding="utf-8")
    print(f"Wrote {path}")


def overview(lang: str) -> None:
    zh = lang == "zh"
    w, h = 1180, 520
    title = "ProofForge · 架构总览" if zh else "ProofForge · Architecture Overview"
    sub = (
        "产品源 → Frontend → Canonical Core → Target → Backend → 制品与证据"
        if zh
        else "Product source → Frontend → Canonical Core → Target → Backend → artifacts & evidence"
    )
    stages = [
        (40, "① 作者" if zh else "1 Author", C["author"], C["author_b"], [
            ("Product", "Examples/Product"),
            ("DSL", "contract_source"),
            ("Intent", "Token / NFT Spec"),
        ]),
        (240, "② Frontend" if zh else "2 Frontend", C["front"], "#0284c7", [
            ("Authored", "Canonicalize"),
            ("兼容" if zh else "Compat", "ContractSpec"),
            ("Materialize", "按目标展开" if zh else "per target"),
        ]),
        (440, "③ Core" if zh else "3 Core", C["core"], C["core_b"], [
            ("IR.Core", "Syntax · Type"),
            ("Validate", "fail-closed"),
            ("Semantics", "参考解释器" if zh else "ref. interpreter"),
        ]),
        (640, "④ Target" if zh else "4 Target", C["target"], C["target_b"], [
            ("Registry", "knownIds"),
            ("Capability", "CapabilityPlan"),
            ("HostOps", "EVM/Sol/Near"),
        ]),
        (840, "⑤ Backend" if zh else "5 Backend", C["evm"], "#ea580c", [
            ("evm", "Plan→Yul→solc"),
            ("solana", "Plan→sBPF→ELF"),
            ("wasm-near", "Plan→WAT→wasm"),
        ]),
        (1000, "⑥ 证据" if zh else "6 Evidence", C["gate"], "#475569", [
            ("制品" if zh else "Artifacts", "bin · wat · so"),
            ("Gates", "just product"),
            ("Runtime", "Anvil/Mollusk"),
        ]),
    ]
    parts = [svg_open(w, h, title), text(40, 36, title, "title", "start"), text(40, 58, sub, "sub", "start")]
    for x, stitle, fill, accent, cards in stages:
        parts.append(f'<rect x="{x}" y="82" width="160" height="34" rx="8" fill="{accent}"/>')
        parts.append(
            f'<text x="{x+80}" y="104" class="t b" text-anchor="middle" fill="#ffffff">{esc(stitle)}</text>'
        )
        cy = 130
        for name, detail in cards:
            parts.append(round_rect(x, cy, 160, 72, fill, accent, 1.5, 10))
            parts.append(text(x + 80, cy + 30, name, "b"))
            parts.append(text(x + 80, cy + 50, detail, "s"))
            cy += 84
        if x < 1000:
            parts.append(arrow(x + 164, 250, x + 196, 250))
    foot = (
        "主三链：evm · solana-sbpf-asm · wasm-near　　次级：Stylus / Psy / Aleo / Quint"
        if zh
        else "Primary triad: evm · solana-sbpf-asm · wasm-near    Secondary: Stylus / Psy / Aleo / Quint"
    )
    parts.append(text(40, 500, foot, "tiny", "start"))
    parts.append(svg_close())
    write(f"01-overview.{lang}.svg", "\n".join(parts))


def pipeline(lang: str) -> None:
    zh = lang == "zh"
    w, h = 1100, 280
    title = "编译流水线（主路径）" if zh else "Compilation pipeline (primary path)"
    sub = (
        "从 Lean 产品模块到链上制品 — 失败一律 fail-closed"
        if zh
        else "Lean product module → chain artifact — failures are fail-closed"
    )
    parts = [svg_open(w, h, title), text(40, 36, title, "title", "start"), text(40, 58, sub, "sub", "start")]
    steps = [
        (40, "Product", "Counter.lean", C["author"], C["author_b"]),
        (200, "Authored", "normalize", C["front"], "#0284c7"),
        (360, "Core", "validate", C["core"], C["core_b"]),
        (520, "Caps", "CapabilityPlan", C["target"], C["target_b"]),
        (680, "Plan", "EVM/Sol/Near", C["evm"], "#ea580c"),
        (840, "Artifact", "bin / so / wasm", C["art"], "#7c3aed"),
    ]
    for i, (x, a, b, fill, accent) in enumerate(steps):
        parts.append(round_rect(x, 100, 140, 100, fill, accent, 2, 14))
        parts.append(text(x + 70, 140, a, "b"))
        parts.append(text(x + 70, 165, b, "s"))
        if i < len(steps) - 1:
            parts.append(arrow(x + 144, 150, x + 196, 150))
    cli = (
        "CLI：lake env proof-forge build --target <id> -o out/ Examples/Product/….lean"
        if zh
        else "CLI: lake env proof-forge build --target <id> -o out/ Examples/Product/….lean"
    )
    parts.append(text(40, 250, cli, "s", "start"))
    parts.append(svg_close())
    write(f"02-pipeline.{lang}.svg", "\n".join(parts))


def triad(lang: str) -> None:
    zh = lang == "zh"
    w, h = 1000, 420
    title = "同一产品源 · 三个目标" if zh else "One product source · three targets"
    sub = "只改 --target；业务逻辑不复制" if zh else "Change only --target; no business-logic forks"
    parts = [svg_open(w, h, title), text(40, 36, title, "title", "start"), text(40, 58, sub, "sub", "start")]
    parts.append(round_rect(320, 90, 360, 70, C["author"], C["author_b"], 2, 14))
    parts.append(text(500, 120, "Examples/Product/Counter.lean", "b"))
    parts.append(
        text(500, 140, "contract_source · 可移植业务" if zh else "contract_source · portable business", "s")
    )
    parts.append(round_rect(350, 200, 300, 50, C["core"], C["core_b"], 2, 12))
    parts.append(text(500, 230, "Checked Canonical Core", "b"))
    parts.append(arrow(500, 160, 500, 196))
    targets = [
        (60, "evm", "ModulePlan → Yul → solc", "Anvil / Foundry", C["evm"], "#ea580c"),
        (350, "solana-sbpf-asm", "SolanaModulePlan → sBPF → ELF", "Mollusk / Pinocchio", C["sol"], "#0d9488"),
        (640, "wasm-near", "NearModulePlan → WAT → wasm", "offline host / near-vm", C["near"], "#7c3aed"),
    ]
    for x, name, path, run, fill, accent in targets:
        parts.append(arrow(500, 250, x + 140, 290))
        parts.append(round_rect(x, 290, 280, 100, fill, accent, 2, 12))
        parts.append(text(x + 140, 320, name, "b"))
        parts.append(text(x + 140, 342, path, "s"))
        parts.append(text(x + 140, 364, run, "tiny"))
    parts.append(svg_close())
    write(f"03-three-targets.{lang}.svg", "\n".join(parts))


def stack(lang: str) -> None:
    zh = lang == "zh"
    w, h = 900, 560
    title = "分层栈 · 由外到内" if zh else "Layer stack · outside-in"
    sub = (
        "越往下越接近链与证明；越往上越接近作者"
        if zh
        else "Lower layers are closer to chains & proofs; upper layers to authors"
    )
    parts = [svg_open(w, h, title), text(40, 36, title, "title", "start"), text(40, 58, sub, "sub", "start")]
    if zh:
        bands = [
            (80, 70, "作者 / 产品", "Examples/Product · Stdlib · TokenSpec · NFTSpec", C["author"], C["author_b"]),
            (155, 70, "CLI", "proof-forge · TargetFirst · TargetDriver · Loaders · Artifacts", C["gate"], "#64748b"),
            (230, 70, "Frontend", "Authored.Canonicalize · ContractSpec · Surface · Materialize", C["front"], "#0284c7"),
            (305, 70, "Canonical Core", "IR.Core Syntax · Type · Validate · Semantics · HostOp refs", C["core"], C["core_b"]),
            (380, 70, "Target 所有权", "Registry · Capability · HostOps · StorageBinding · Crosscall", C["target"], C["target_b"]),
            (455, 90, "Backend Plans", "Evm.Plan · Solana.Plan · WasmHost/NearModulePlan · Stylus/Psy/…", C["evm"], "#ea580c"),
        ]
    else:
        bands = [
            (80, 70, "Author / Product", "Examples/Product · Stdlib · TokenSpec · NFTSpec", C["author"], C["author_b"]),
            (155, 70, "CLI", "proof-forge · TargetFirst · TargetDriver · Loaders · Artifacts", C["gate"], "#64748b"),
            (230, 70, "Frontend", "Authored.Canonicalize · ContractSpec · Surface · Materialize", C["front"], "#0284c7"),
            (305, 70, "Canonical Core", "IR.Core Syntax · Type · Validate · Semantics · HostOp refs", C["core"], C["core_b"]),
            (380, 70, "Target ownership", "Registry · Capability · HostOps · StorageBinding · Crosscall", C["target"], C["target_b"]),
            (455, 90, "Backend plans", "Evm.Plan · Solana.Plan · WasmHost/NearModulePlan · Stylus/Psy/…", C["evm"], "#ea580c"),
        ]
    for y, hh, t, body, fill, accent in bands:
        parts.append(round_rect(40, y, 820, hh, fill, accent, 2, 12))
        parts.append(text(60, y + 28, t, "b", "start"))
        parts.append(text(60, y + 50, body, "s", "start"))
    parts.append(svg_close())
    write(f"04-layer-stack.{lang}.svg", "\n".join(parts))


def components(lang: str) -> None:
    zh = lang == "zh"
    w, h = 1100, 640
    title = "核心组件内部一览" if zh else "Core component internals"
    sub = "每个盒子 = 仓库里的一个主要子系统" if zh else "Each card is a major subsystem in the tree"
    parts = [svg_open(w, h, title), text(40, 36, title, "title", "start"), text(40, 58, sub, "sub", "start")]
    cards = [
        (40, 90, "CLI", C["gate"], "#64748b", ["main / Options", "TargetDriver", "Loaders", "*Artifacts · Deploy"]),
        (300, 90, "Frontend", C["front"], "#0284c7", ["Authored/*", "ContractSpec", "Surface/*", "Materialize/*"]),
        (560, 90, "IR.Core", C["core"], C["core_b"], ["Syntax · Type", "Validate", "Semantics", "HostOp refs"]),
        (820, 90, "Target", C["target"], C["target_b"], ["Registry", "Capability", "HostOps/*", "Materialize"]),
        (40, 340, "Backend.Evm", C["evm"], "#ea580c", ["Plan.Core", "Validate · Lower", "ToYul", "solc → bytecode"]),
        (300, 340, "Backend.Solana", C["sol"], "#0d9488", ["Plan.Core", "Extension · Syscalls", "Asm · BpfEncode", "ELF · Manifest"]),
        (560, 340, "Backend.WasmHost", C["near"], "#7c3aed", ["NearModulePlan", "Layout · ABI", "EmitWat", "Host bridges"]),
        (
            820,
            340,
            "证据栈" if zh else "Evidence",
            C["art"],
            "#7c3aed",
            ["just product/check", "testkit harness", "differential", "Formal* 可选" if zh else "Formal* optional"],
        ),
    ]
    for x, y, t, fill, accent, lines in cards:
        parts.append(round_rect(x, y, 240, 220, fill, accent, 2, 14))
        parts.append(f'<rect x="{x}" y="{y}" width="240" height="40" rx="14" fill="{accent}"/>')
        parts.append(f'<rect x="{x}" y="{y+20}" width="240" height="20" fill="{accent}"/>')
        parts.append(
            f'<text x="{x+120}" y="{y+26}" class="t b" text-anchor="middle" fill="#ffffff">{esc(t)}</text>'
        )
        for i, line in enumerate(lines):
            parts.append(text(x + 120, y + 70 + i * 32, line, "s"))
    parts.append(svg_close())
    write(f"05-components.{lang}.svg", "\n".join(parts))


def main() -> None:
    for lang in ("zh", "en"):
        overview(lang)
        pipeline(lang)
        triad(lang)
        stack(lang)
        components(lang)
    print("All architecture SVGs generated.")


if __name__ == "__main__":
    main()
