#!/usr/bin/env python3
"""Generate deterministic, untracked ProgramV1 source-boundary fixtures under build/.

Root-aware identity (CLI --module Root):
  programIdentity = [Root] ++ N*depth ++ [Bounded]
  depth 254 → 256 components (accept)
  depth 255 → 257 components (identity over-limit → PF-BOUND-001)
  deeper depths reach Loader namespace overLimit (also PF-BOUND-001)

Bodies use S1-compatible Counter-like shapes so accept vectors can compile.
"""

from __future__ import annotations

import argparse
from pathlib import Path


HEADER = "import ProofForgeV2\nopen ProofForgeV2.Language\n"

# S1-compatible: no integer literals; init takes a parameter.
BOUNDED_BODY = (
    "program Bounded where\n"
    "  state count : UInt64\n"
    "  init(initial : UInt64) do\n"
    "    count := initial\n"
    "  view get() : UInt64 do\n"
    "    return count\n"
)


def namespace_source(depth: int) -> str:
    return (
        HEADER
        + "namespace N\n" * depth
        + BOUNDED_BODY
        + "end N\n" * depth
    )


def unwound_namespace_source(peak_depth: int, retained_depth: int) -> str:
    return (
        HEADER
        + "namespace N\n" * peak_depth
        + "end N\n" * (peak_depth - retained_depth)
        + BOUNDED_BODY
        + "end N\n" * retained_depth
    )


def namespace_expression_source(depth: int, terms: int) -> str:
    return (
        HEADER
        + "namespace N\n" * depth
        + "program Deep where\n  view get() : UInt64 do\n    return "
        + " + ".join(["1"] * terms)
        + "\n"
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

    # Root-aware depths: identity components = 1 (Root) + depth + 1 (Bounded).
    fixtures = {
        # Accept: Root + 254 N + Bounded = 256.
        "namespace-at-limit.lean": namespace_source(254),
        # Identity overflow: Root + 255 N + Bounded = 257 → PF-BOUND-001.
        "identity-over-limit.lean": namespace_source(255),
        # Loader namespace overLimit vector (namespace parts alone exceed 256).
        "namespace-over-limit.lean": namespace_source(257),
        # Transient over-limit then unwind to legal identity 256.
        "namespace-unwound-at-limit.lean": unwound_namespace_source(257, 254),
        # Syntax preflight wins before identity.
        "namespace-and-expression-over-limit.lean": namespace_expression_source(257, 300),
        "expression-over-limit.lean": expression_source(300),
        "nodes-over-limit.lean": wide_source(20_000),
    }
    for name, source in fixtures.items():
        (destination / name).write_text(source, encoding="utf-8")

    # Exact 16 MiB UTF-8 accept (pad with spaces after a valid S1 program).
    source_at_limit = (HEADER + BOUNDED_BODY).encode("utf-8")
    pad = 16 * 1024 * 1024 - len(source_at_limit)
    assert pad > 0, "base program must fit under 16 MiB"
    source_at_limit = source_at_limit + (b" " * pad)
    assert len(source_at_limit) == 16 * 1024 * 1024
    (destination / "source-at-limit.lean").write_bytes(source_at_limit)

    # 16 MiB + 1 reject before parsing (PF-SRC-INVALID).
    (destination / "source-over-limit.lean").write_bytes(
        b" " * (16 * 1024 * 1024 + 1)
    )


if __name__ == "__main__":
    main()
