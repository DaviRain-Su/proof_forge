#!/usr/bin/env python3
"""Generate deterministic, untracked source-boundary fixtures under build/."""

from __future__ import annotations

import argparse
from pathlib import Path


HEADER = "import ProofForgeV2\nopen ProofForgeV2.Language\n"


def namespace_source(depth: int) -> str:
    return (
        HEADER
        + "namespace N\n" * depth
        + "program Bounded where\n"
        + "  state count : UInt64\n"
        + "  init() do\n    count := 0\n"
        + "  view get() : UInt64 do\n    return count\n"
        + "end N\n" * depth
    )


def expression_source(terms: int) -> str:
    return (
        HEADER
        + "program Deep where\n  view get() : UInt64 do\n    return "
        + " + ".join(["1"] * terms)
        + "\n"
    )


def wide_source(state_count: int) -> str:
    return (
        HEADER
        + "program Wide where\n"
        + "  state cell : UInt64\n" * state_count
        + "  view get() : UInt64 do\n    return 0\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    destination: Path = args.destination
    destination.mkdir(parents=True, exist_ok=True)

    fixtures = {
        "namespace-at-limit.lean": namespace_source(255),
        "namespace-over-limit.lean": namespace_source(256),
        "expression-over-limit.lean": expression_source(300),
        "nodes-over-limit.lean": wide_source(20_000),
    }
    for name, source in fixtures.items():
        (destination / name).write_text(source, encoding="utf-8")
    (destination / "source-over-limit.lean").write_bytes(
        b" " * (16 * 1024 * 1024 + 1)
    )


if __name__ == "__main__":
    main()
