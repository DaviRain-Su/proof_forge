#!/usr/bin/env python3
"""Package a minimal Lean Author SDK from the Syntax import closure.

Authority: docs/product/05-distribution-and-packages.md (REL-AUTHOR-0)

Emits:
  dist/proof-forge-author-<ver>/
    lakefile.lean, lean-toolchain, VERSION, README.md
    ProofForgeV2.lean          # thin root: import Syntax only
    ProofForgeV2/**           # closure files
  dist/proof-forge-author-<ver>.tar.gz
  dist/proof-forge-author-<ver>.tar.gz.sha256

This is engineering-dist only (not formal Stage-0). Product CLI still owns compile;
this package is for Lake/IDE authoring (`import ProofForgeV2` + program syntax).
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

IMPORT_RE = re.compile(r"^import\s+([A-Za-z0-9_.]+)\s*$")
SKIP_PREFIXES = ("Lean", "Init", "Std", "Lake")


def die(msg: str, code: int = 1) -> None:
    print(f"package-author-sdk: {msg}", file=sys.stderr)
    raise SystemExit(code)


def mod_to_path(mod: str) -> Path:
    return Path(*mod.split(".")).with_suffix(".lean")


def should_skip(mod: str) -> bool:
    for p in SKIP_PREFIXES:
        if mod == p or mod.startswith(p + "."):
            return True
    return False


def import_closure(repo: Path, start_mods: list[str]) -> set[Path]:
    seen: set[Path] = set()
    queue: list[Path] = [mod_to_path(m) for m in start_mods]
    missing: list[str] = []
    while queue:
        rel = queue.pop()
        if rel in seen:
            continue
        abs_path = repo / rel
        if not abs_path.is_file():
            missing.append(str(rel))
            continue
        seen.add(rel)
        for line in abs_path.read_text(encoding="utf-8").splitlines():
            m = IMPORT_RE.match(line.strip())
            if not m:
                continue
            mod = m.group(1)
            if should_skip(mod):
                continue
            child = mod_to_path(mod)
            if child not in seen:
                queue.append(child)
    if missing:
        die("missing modules in closure:\n  " + "\n  ".join(missing))
    return seen


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output directory (default: <repo>/dist)",
    )
    ap.add_argument(
        "--root",
        type=Path,
        default=None,
        help="repo root (default: parent of scripts/)",
    )
    args = ap.parse_args(argv)

    script_dir = Path(__file__).resolve().parent
    repo = (args.root or script_dir.parent).resolve()
    out_dir = (args.out or (repo / "dist")).resolve()

    version_path = repo / "VERSION"
    if not version_path.is_file():
        die("missing VERSION", 2)
    version = version_path.read_text(encoding="utf-8").strip()
    if not version:
        die("VERSION empty", 2)

    toolchain_path = repo / "lean-toolchain"
    if not toolchain_path.is_file():
        die("missing lean-toolchain", 2)
    toolchain = toolchain_path.read_text(encoding="utf-8").strip()

    # Root for authoring: program syntax + elab_rules (ProgramElaborationV1).
    # Syntax alone registers `programDecl` but does not implement elaboration.
    start = ["ProofForgeV2.Language.ProgramElaborationV1"]
    files = import_closure(repo, start)
    print(f"package-author-sdk: closure files={len(files)} version={version}")

    stage_name = f"proof-forge-author-{version}"
    stage = out_dir / stage_name
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)

    # Thin product-compatible root module name (CLI source gate: import ProofForgeV2).
    write_text(
        stage / "ProofForgeV2.lean",
        "-- ProofForge Author SDK thin root (engineering-dist).\n"
        "-- Full monorepo umbrella is NOT included (no materializers/CLI/targets).\n"
        "-- ProgramElaborationV1 pulls Syntax + elab_rules for `program … where`.\n"
        "import ProofForgeV2.Language.Syntax\n"
        "import ProofForgeV2.Language.ProgramElaborationV1\n",
    )

    for rel in sorted(files):
        src = repo / rel
        dst = stage / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    write_text(stage / "VERSION", version + "\n")
    write_text(stage / "lean-toolchain", toolchain + "\n")

    lakefile = f"""import Lake
open Lake DSL

package «proof-forge-author» where
  version := v!"{version}"
  -- Engineering Author SDK only. Not the product compiler CLI.
  -- Channel: engineering-dist (not formal Stage-0).

@[default_target]
lean_lib ProofForgeV2 where
  roots := #[`ProofForgeV2]
"""
    write_text(stage / "lakefile.lean", lakefile)

    readme = f"""# proof-forge-author {version} (engineering-dist)

Minimal **Lean Author SDK** for writing ProofForge `program … where` sources.

- Provides `import ProofForgeV2` → Syntax + ProgramElaborationV1 (parser + elab surface)
- **Does not** include the product CLI, materializers, or target emitters
- Compile/materialize still uses **`proof-forge-next`** (CLI engineering dist)
- Channel: `engineering-dist` — **not** formal Stage-0 / hermetic release

## Require (path / git)

```lean
-- lakefile.lean
require «proof-forge-author» from "…"  -- path or git tag
```

```lean
import ProofForgeV2
open ProofForgeV2.Language

program Hello where
  state count : UInt64
  init(initial : UInt64) do
    count := initial
  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count
  view get() : UInt64 do
    return count
```

Then:

```bash
export PROOF_FORGE_CLI=/path/to/proof-forge-next
"$PROOF_FORGE_CLI" build src/Hello.lean --module Hello --target aleo --root "$PWD" -o out
```

## Contents

- `{len(files) + 1}` Lean modules (thin `ProofForgeV2` root + Syntax import closure)
- Same `lean-toolchain` pin as the monorepo product: `{toolchain}`
"""
    write_text(stage / "README.md", readme)

    # Optional COMMIT stamp
    try:
        commit = subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            text=True,
        ).strip()
        write_text(stage / "COMMIT", commit + "\n")
    except (OSError, subprocess.CalledProcessError):
        pass

    archive = out_dir / f"{stage_name}.tar.gz"
    if archive.is_file():
        archive.unlink()
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(stage, arcname=stage_name)

    digest = sha256_file(archive)
    sum_path = Path(str(archive) + ".sha256")
    sum_path.write_text(f"{digest}  {archive.name}\n", encoding="utf-8")

    print(f"package-author-sdk: stage={stage}")
    print(f"package-author-sdk: archive={archive} bytes={archive.stat().st_size}")
    print(f"package-author-sdk: sha256={digest}")
    print("package-author-sdk: PACKAGED-OK channel=engineering-dist")
    print("package-author-sdk: NOT formal Stage-0 / hermetic / mainnet")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
