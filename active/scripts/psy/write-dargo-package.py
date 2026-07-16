#!/usr/bin/env python3
import argparse
import json
import shutil
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--description", required=True)
    args = parser.parse_args()

    project_dir = Path(args.project_dir)
    if not project_dir.name.startswith("dargo-"):
        raise SystemExit(
            f"psy-dargo-package: refusing to rewrite non-smoke package dir: {project_dir}"
        )

    source = Path(args.source)
    if not source.is_file():
        raise SystemExit(f"psy-dargo-package: source does not exist: {source}")

    shutil.rmtree(project_dir, ignore_errors=True)
    src_dir = project_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, src_dir / "main.psy")

    manifest = "\n".join(
        [
            "[package]",
            f"name = {json.dumps(args.package_name)}",
            'version = "0.1.0"',
            'type = "bin"',
            f"description = {json.dumps(args.description)}",
            "",
            "[dependencies]",
            "",
        ]
    )
    (project_dir / "Dargo.toml").write_text(manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
