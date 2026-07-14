#!/usr/bin/env python3

import collections
import json
import pathlib
import subprocess
import sys
from collections.abc import Sequence

from manifest import load_manifest


def compare_coverage(serial: Sequence[str], parallel: Sequence[str]) -> list[str]:
    errors: list[str] = []
    for name, count in sorted(collections.Counter(serial).items()):
        if count > 1:
            errors.append(f"serial check contains duplicate recipe `{name}`")
    for name in sorted(set(serial) - set(parallel)):
        errors.append(f"parallel manifest is missing serial recipe `{name}`")
    for name in sorted(set(parallel) - set(serial)):
        errors.append(f"parallel manifest has extra recipe `{name}`")
    return errors


def serial_dependencies(recipe: str = "check-serial") -> list[str]:
    result = subprocess.run(
        ["just", "--dump", "--dump-format", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    return [item["recipe"] for item in payload["recipes"][recipe]["dependencies"]]


def main() -> int:
    manifest = load_manifest(pathlib.Path(__file__).with_name("lanes.json"))
    try:
        errors = compare_coverage(serial_dependencies(), manifest.serial_coverage)
    except (KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"test-equivalence: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"test-equivalence: {error}", file=sys.stderr)
        return 1
    print(f"test-equivalence: ok ({len(manifest.serial_coverage)} recipes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
