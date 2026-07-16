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
        print(f"aleo-write-pure-math-package: source not found: {source}", file=sys.stderr)
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
  "description": "ProofForge Aleo PureMath smoke fixture",
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
    fn test_pure_functions() {{
        let r1: u64 = {program_name}.aleo::plus(1u64, 2u64);
        assert(r1 == 3u64);

        let r2: u64 = {program_name}.aleo::max(5u64, 3u64);
        assert(r2 == 5u64);

        let r3: u64 = {program_name}.aleo::max(2u64, 7u64);
        assert(r3 == 7u64);

        let r4: u64 = {program_name}.aleo::sumFirst10();
        assert(r4 == 45u64);

        let r5: bool = {program_name}.aleo::isEven(4u64);
        assert(r5);

        let r6: bool = {program_name}.aleo::isEven(5u64);
        assert(!r6);
    }}

    @noupgrade
    constructor() {{}}
}}
"""
    )

    print(f"aleo-write-pure-math-package: wrote {project_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
