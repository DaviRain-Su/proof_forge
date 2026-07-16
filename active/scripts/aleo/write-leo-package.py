#!/usr/bin/env python3
import argparse
import shutil
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--program-name", required=True)
    args = parser.parse_args()

    project_dir = Path(args.project_dir)
    source = Path(args.source)
    program_name = args.program_name

    if not source.is_file():
        print(f"aleo-write-leo-package: source not found: {source}", file=sys.stderr)
        return 1

    if project_dir.exists():
        shutil.rmtree(project_dir)
    project_dir.mkdir(parents=True, exist_ok=True)

    src_dir = project_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, src_dir / "main.leo")

    program_json = project_dir / "program.json"
    program_json.write_text(
        f"""{{
  "program": "{program_name}.aleo",
  "version": "0.1.0",
  "description": "ProofForge Aleo counter smoke fixture",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}}
"""
    )

    tests_dir = project_dir / "tests"
    tests_dir.mkdir(parents=True, exist_ok=True)
    test_file = tests_dir / f"test_{program_name}.leo"
    test_file.write_text(
        f"""// The 'test_{program_name}' test program.
import {program_name}.aleo;

program test_{program_name}.aleo {{
    @test
    fn test_lifecycle() -> Final {{
        let f1: Final = {program_name}.aleo::initialize();
        let f2: Final = {program_name}.aleo::get();
        let f3: Final = {program_name}.aleo::increment();
        let f4: Final = {program_name}.aleo::increment();
        let f5: Final = {program_name}.aleo::get();
        return final {{
            f1.run();
            f2.run();
            f3.run();
            f4.run();
            f5.run();
        }};
    }}

    @noupgrade
    constructor() {{}}
}}
"""
    )

    print(f"aleo-write-leo-package: wrote {project_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
