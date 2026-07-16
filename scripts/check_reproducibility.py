#!/usr/bin/env python3
"""Compare two Phase-1 output trees byte-for-byte."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


def digest_tree(root: Path) -> dict[str, str]:
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: check_reproducibility.py <tree-a> <tree-b>")
    left, right = map(Path, sys.argv[1:])
    left_digests, right_digests = digest_tree(left), digest_tree(right)
    if left_digests != right_digests:
        left_keys, right_keys = set(left_digests), set(right_digests)
        print(f"only-left: {sorted(left_keys - right_keys)}", file=sys.stderr)
        print(f"only-right: {sorted(right_keys - left_keys)}", file=sys.stderr)
        for key in sorted(left_keys & right_keys):
            if left_digests[key] != right_digests[key]:
                print(f"digest-mismatch: {key}", file=sys.stderr)
        raise SystemExit(1)
    print(f"reproducibility: ok ({len(left_digests)} files)")


if __name__ == "__main__":
    main()
