#!/usr/bin/env python3

import argparse
import dataclasses
import json
import pathlib
import subprocess
import sys
from typing import Any


EXECUTION_CLASSES = frozenset({"isolated", "lane_serial", "exclusive"})


@dataclasses.dataclass(frozen=True)
class RecipeSpec:
    name: str
    lane: str
    execution: str
    tags: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class Manifest:
    version: int
    lanes: tuple[str, ...]
    serial_coverage: tuple[str, ...]
    recipes: tuple[RecipeSpec, ...]


def _require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a non-empty string")
    return value


def load_manifest(path: pathlib.Path) -> Manifest:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("version") != 1:
        raise ValueError("manifest version must be 1")

    lanes = tuple(_require_string(value, "lane") for value in payload.get("lanes", []))
    if not lanes or len(lanes) != len(set(lanes)):
        raise ValueError("lanes must be a non-empty unique list")

    serial_coverage = tuple(
        _require_string(value, "serial coverage recipe")
        for value in payload.get("serialCoverage", [])
    )
    if len(serial_coverage) != len(set(serial_coverage)):
        raise ValueError("serial coverage contains duplicate recipes")

    recipes: list[RecipeSpec] = []
    seen: set[str] = set()
    for raw in payload.get("recipes", []):
        name = _require_string(raw.get("name"), "recipe name")
        if name in seen:
            raise ValueError(f"duplicate recipe `{name}`")
        seen.add(name)
        lane = _require_string(raw.get("lane"), f"recipe `{name}` lane")
        if lane not in lanes:
            raise ValueError(f"recipe `{name}` uses undeclared lane `{lane}`")
        execution = _require_string(raw.get("execution"), f"recipe `{name}` execution")
        if execution not in EXECUTION_CLASSES:
            raise ValueError(
                f"recipe `{name}` has unknown execution class `{execution}`"
            )
        tags = tuple(
            _require_string(value, f"recipe `{name}` tag")
            for value in raw.get("tags", [])
        )
        recipes.append(RecipeSpec(name, lane, execution, tags))

    return Manifest(1, lanes, serial_coverage, tuple(recipes))


def validate_manifest(manifest: Manifest, known_recipes: set[str]) -> list[str]:
    errors: list[str] = []
    manifest_names = {recipe.name for recipe in manifest.recipes}
    for recipe in manifest.recipes:
        if recipe.name not in known_recipes:
            errors.append(f"manifest recipe `{recipe.name}` is not declared by just")
    for name in manifest.serial_coverage:
        if name not in known_recipes:
            errors.append(f"serial coverage recipe `{name}` is not declared by just")
        if name not in manifest_names:
            errors.append(f"serial coverage recipe `{name}` has no manifest entry")
    for name in sorted(manifest_names - set(manifest.serial_coverage)):
        errors.append(f"manifest recipe `{name}` is absent from serial coverage")
    return errors


def known_just_recipes() -> set[str]:
    result = subprocess.run(
        ["just", "--summary"], check=True, capture_output=True, text=True
    )
    return set(result.stdout.split())


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the parallel test manifest")
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        default=pathlib.Path(__file__).with_name("lanes.json"),
    )
    parser.add_argument("--check", action="store_true", required=True)
    args = parser.parse_args()

    try:
        manifest = load_manifest(args.manifest)
        errors = validate_manifest(manifest, known_just_recipes())
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"test-manifest: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"test-manifest: {error}", file=sys.stderr)
        return 1
    print(
        f"test-manifest: ok ({len(manifest.recipes)} recipes, "
        f"{len(manifest.lanes)} lanes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
