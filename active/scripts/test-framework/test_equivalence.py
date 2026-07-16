import pathlib
import sys
import unittest

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from check_equivalence import compare_coverage


class EquivalenceTest(unittest.TestCase):
    def test_equal_coverage_passes(self) -> None:
        self.assertEqual(compare_coverage(["build", "product"], ["product", "build"]), [])

    def test_missing_parallel_recipe_is_reported(self) -> None:
        self.assertEqual(
            compare_coverage(["build", "product"], ["build"]),
            ["parallel manifest is missing serial recipe `product`"],
        )

    def test_extra_parallel_recipe_is_reported(self) -> None:
        self.assertEqual(
            compare_coverage(["build"], ["build", "product"]),
            ["parallel manifest has extra recipe `product`"],
        )

    def test_duplicate_serial_recipe_is_reported(self) -> None:
        self.assertEqual(
            compare_coverage(["build", "build"], ["build"]),
            ["serial check contains duplicate recipe `build`"],
        )


if __name__ == "__main__":
    unittest.main()
