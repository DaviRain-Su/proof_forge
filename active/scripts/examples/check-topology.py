#!/usr/bin/env python3
"""Check that example sources follow the shared-vs-target topology.

The goal is narrow and structural: reusable product examples live under
Examples/Product, while historical target paths stay as wrappers or
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
    shared_dir = REPO_ROOT / "Examples" / "Product"
    sources = sorted(shared_dir.glob("*.lean"))
    if not sources:
        fail("Examples/Product has no Lean sources")

    shared_readme = read("Examples/Product/README.md")
    root_readme = read("Examples/README.md")

    for path in sources:
        rel = path.relative_to(REPO_ROOT).as_posix()
        name = path.stem
        text = path.read_text(encoding="utf-8")

        require_contains(rel, text, f"namespace Examples.Product.{name}", "shared namespace")
        require_contains("Examples/Product/README.md", shared_readme, f"[{name}.lean]({name}.lean)", "shared README entry")
        require_contains("Examples/README.md", root_readme, f"{name}.lean", "root README shared entry")

        if "contract_source " in text:
            require_contains(rel, text, "import ProofForge.Contract.Source", "contract_source import")
            require_contains(rel, text, f"contract_source {name}", "contract_source declaration")
        elif "def spec : ProofForge.Contract.ContractSpec" in text:
            require_contains(rel, text, "def module : ProofForge.IR.Module", "ContractSpec module export")
        elif "TokenSpec" in text:
            require_contains(rel, text, "import ProofForge.Contract.Token", "TokenSpec import")
            require_contains(rel, text, "def spec", "TokenSpec export")
        elif "NFTSpec" in text:
            require_contains(rel, text, "import ProofForge.Contract.Nft", "NFTSpec import")
            require_contains(rel, text, "def spec", "NFTSpec export")
        else:
            fail(f"{rel}: shared example must use contract_source, TokenSpec, or NFTSpec")

        # Portable-default (Phase A): Shared must not pull chain Surface modules.
        for forbidden in (
            "import ProofForge.Contract.Source.Solana.Legacy",
            "import ProofForge.Contract.Source.Solana",
            "import ProofForge.Backend.Solana",
            "import ProofForge.Backend.Evm",
            "import ProofForge.Evm",
            "import Lean.Evm",
            "TokenStandard.erc20",
            "TokenStandard.splToken",
            "TokenStandard.splToken2022",
        ):
            if forbidden in text:
                fail(
                    f"{rel}: portable Shared must not contain `{forbidden}` "
                    "(business intent only; --target materializes chain form)"
                )


def check_wrapper(rel: str, shared_name: str) -> None:
    text = read(rel)
    require_contains(rel, text, f"import Examples.Product.{shared_name}", "shared import")
    require_contains(rel, text, f"Examples.Product.{shared_name}.spec", "shared spec reference")
    if "contract_source " in text:
        fail(f"{rel}: compatibility wrapper must not duplicate contract_source logic")


def check_compatibility_wrappers() -> None:
    wrappers = {
        "Examples/Backend/Evm/Contracts/ArrayExample.lean": "ArrayExample",
        "Examples/Backend/Evm/Contracts/Counter.lean": "Counter",
        "Examples/Backend/Evm/Contracts/stdlib/Ownable.lean": "Ownable",
        "Examples/Backend/Evm/Contracts/stdlib/Pausable.lean": "Pausable",
        "Examples/Backend/Evm/Contracts/stdlib/ReentrancyGuard.lean": "ReentrancyGuard",
        "Examples/Backend/Solana/Counter.lean": "Counter",
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
