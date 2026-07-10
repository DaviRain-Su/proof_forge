#!/usr/bin/env python3
"""PF-P2-01: Product catalog discovery gate.

Every Examples/Product/*.lean file must appear in Examples/Product/catalog.json.
Uncatalogued or missing catalog entries fail the gate.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PRODUCT = REPO / "Examples" / "Product"
CATALOG = PRODUCT / "catalog.json"


def main() -> int:
    if not CATALOG.is_file():
        print(f"missing product catalog: {CATALOG}", file=sys.stderr)
        return 1
    data = json.loads(CATALOG.read_text())
    if data.get("kind") != "proof-forge-product-catalog":
        print("catalog kind must be proof-forge-product-catalog", file=sys.stderr)
        return 1
    listed = {entry["file"] for entry in data.get("sources", [])}
    on_disk = {p.name for p in PRODUCT.glob("*.lean") if not p.name.startswith("_")}
    # Ignore non-source helpers if any
    missing = sorted(on_disk - listed)
    extra = sorted(listed - on_disk)
    if missing:
        print("uncatalogued Product sources:", ", ".join(missing), file=sys.stderr)
        print("add them to Examples/Product/catalog.json (PF-P2-01)", file=sys.stderr)
        return 1
    if extra:
        print("catalog lists missing files:", ", ".join(extra), file=sys.stderr)
        return 1
    # Basic field checks
    for entry in data["sources"]:
        for key in ("authoring", "kind", "targets", "gates"):
            if key not in entry:
                print(f"{entry.get('file')}: missing field {key}", file=sys.stderr)
                return 1
        if entry["authoring"] not in ("contract_source", "TokenSpec", "facade"):
            print(f"{entry['file']}: bad authoring {entry['authoring']}", file=sys.stderr)
            return 1
    runtime = [e["file"] for e in data["sources"] if e.get("runtimeTriad")]
    # PF-P2-01: capability families with shared triad runtime evidence must keep
    # at least one runtimeTriad source. Remaining families (auth-policy, remote,
    # pure events/errors product sources) advance in later slices.
    required_runtime_kinds = {
        "scalar-state": "Counter / ValueVault scalar + events",
        "aggregate": "ArrayExample fixed-array map/array family",
        "auth-policy": "Ownable caller.sender auth/policy family",
        "remote": "RemoteCall crosscall.invoke family (peer equiv = PF-P2-03)",
    }
    runtime_kinds = {
        e["kind"] for e in data["sources"] if e.get("runtimeTriad") and e.get("kind")
    }
    missing_kinds = sorted(required_runtime_kinds.keys() - runtime_kinds)
    if missing_kinds:
        for kind in missing_kinds:
            print(
                f"runtimeTriad missing for capability kind `{kind}` "
                f"({required_runtime_kinds[kind]})",
                file=sys.stderr,
            )
        print(
            "mark at least one Product source runtimeTriad=true for each required kind",
            file=sys.stderr,
        )
        return 1
    print(
        f"product-catalog: ok ({len(listed)} sources; runtimeTriad={', '.join(runtime) or 'none'}; "
        f"runtimeKinds={', '.join(sorted(runtime_kinds))})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
