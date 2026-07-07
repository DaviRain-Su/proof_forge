#!/usr/bin/env python3
"""Check that example sources follow the shared-vs-target topology.

The goal is narrow and structural: reusable product examples live under
Examples/Shared, while historical target paths stay as wrappers or
target-specific fixtures.
"""

from __future__ import annotations

from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    print(f"examples-topology: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(rel: str) -> str:
    path = REPO_ROOT / rel
    if not path.exists():
        fail(f"missing required file: {rel}")
    return path.read_text(encoding="utf-8")


def require_contains(rel: str, text: str, needle: str, label: str) -> None:
    if needle not in text:
        fail(f"{rel}: missing {label}: {needle}")


def check_shared_sources() -> None:
    shared_dir = REPO_ROOT / "Examples" / "Shared"
    sources = sorted(shared_dir.glob("*.lean"))
    if not sources:
        fail("Examples/Shared has no Lean sources")

    shared_readme = read("Examples/Shared/README.md")
    root_readme = read("Examples/README.md")

    for path in sources:
        rel = path.relative_to(REPO_ROOT).as_posix()
        name = path.stem
        text = path.read_text(encoding="utf-8")

        require_contains(rel, text, f"namespace Examples.Shared.{name}", "shared namespace")
        require_contains("Examples/Shared/README.md", shared_readme, f"[{name}.lean]({name}.lean)", "shared README entry")
        require_contains("Examples/README.md", root_readme, f"{name}.lean", "root README shared entry")

        if "contract_source " in text:
            require_contains(rel, text, "import ProofForge.Contract.Source", "contract_source import")
            require_contains(rel, text, f"contract_source {name}", "contract_source declaration")
        elif "def spec : ProofForge.Contract.ContractSpec" in text:
            require_contains(rel, text, "def module : ProofForge.IR.Module", "ContractSpec module export")
        elif "TokenSpec" in text:
            require_contains(rel, text, "import ProofForge.Contract.Token", "TokenSpec import")
            require_contains(rel, text, "def spec", "TokenSpec export")
        else:
            fail(f"{rel}: shared example must use contract_source or TokenSpec")


def check_wrapper(rel: str, shared_name: str) -> None:
    text = read(rel)
    require_contains(rel, text, f"import Examples.Shared.{shared_name}", "shared import")
    require_contains(rel, text, f"Examples.Shared.{shared_name}.spec", "shared spec reference")
    if "contract_source " in text:
        fail(f"{rel}: compatibility wrapper must not duplicate contract_source logic")


def check_compatibility_wrappers() -> None:
    wrappers = {
        "Examples/Evm/Contracts/ArrayExample.lean": "ArrayExample",
        "Examples/Evm/Contracts/Counter.lean": "Counter",
        "Examples/Evm/Contracts/stdlib/Ownable.lean": "Ownable",
        "Examples/Evm/Contracts/stdlib/Pausable.lean": "Pausable",
        "Examples/Evm/Contracts/stdlib/ReentrancyGuard.lean": "ReentrancyGuard",
        "Examples/Solana/Counter.lean": "Counter",
        "ProofForge/Contract/Examples/Counter.lean": "Counter",
        "ProofForge/Contract/Examples/ValueVault.lean": "ValueVault",
        "ProofForge/Contract/Token/Examples/SoulboundToken.lean": "SoulboundToken",
    }
    for rel, shared_name in wrappers.items():
        check_wrapper(rel, shared_name)


def main() -> int:
    check_shared_sources()
    check_compatibility_wrappers()
    print("examples-topology: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
