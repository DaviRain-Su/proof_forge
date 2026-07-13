import pathlib
import sys
import unittest

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from select_tests import select_tags


class SelectTest(unittest.TestCase):
    def test_backend_paths(self) -> None:
        cases = [
            ("ProofForge/Backend/Evm/Plan.lean", {"fast", "evm-fast"}),
            ("scripts/solana/plan-smoke.sh", {"fast", "solana-fast"}),
            ("ProofForge/Backend/WasmHost/ModulePlan.lean", {"fast", "wasm-fast"}),
            ("ProofForge/Backend/Stylus/Plan.lean", {"fast", "stylus-fast"}),
        ]
        for path, expected in cases:
            with self.subTest(path=path): self.assertEqual(select_tags([path]), expected)

    def test_shared_change_selects_primary_triad(self) -> None:
        self.assertEqual(select_tags(["ProofForge/IR/Core/Syntax.lean"]),
            {"fast", "evm-fast", "solana-fast", "wasm-fast", "stylus-fast"})

    def test_docs_change_selects_docs(self) -> None:
        self.assertEqual(select_tags(["docs/architecture.md"]), {"fast", "docs"})

    def test_unknown_and_empty_use_baseline(self) -> None:
        self.assertEqual(select_tags(["misc/unknown.txt"]), {"fast"})
        self.assertEqual(select_tags([]), {"fast"})

    def test_multiple_changes_union_tags(self) -> None:
        self.assertEqual(select_tags(["ProofForge/Backend/Evm/Plan.lean", "docs/a.md"]),
            {"fast", "evm-fast", "docs"})


if __name__ == "__main__": unittest.main()
