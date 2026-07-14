import json
import pathlib
import sys
import tempfile
import unittest


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from manifest import load_manifest, validate_manifest


class ManifestTest(unittest.TestCase):
    def write_manifest(self, payload: dict) -> pathlib.Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = pathlib.Path(directory.name) / "lanes.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def valid_payload(self) -> dict:
        return {
            "version": 1,
            "lanes": ["core-product"],
            "serialCoverage": ["build"],
            "recipes": [
                {
                    "name": "build",
                    "lane": "core-product",
                    "execution": "isolated",
                    "tags": ["core"],
                }
            ],
        }

    def test_loads_valid_manifest(self) -> None:
        manifest = load_manifest(self.write_manifest(self.valid_payload()))
        self.assertEqual(manifest.version, 1)
        self.assertEqual(manifest.recipes[0].name, "build")
        self.assertEqual(validate_manifest(manifest, {"build"}), [])

    def test_rejects_duplicate_recipe(self) -> None:
        payload = self.valid_payload()
        payload["recipes"].append(dict(payload["recipes"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate recipe `build`"):
            load_manifest(self.write_manifest(payload))

    def test_rejects_unknown_execution_class(self) -> None:
        payload = self.valid_payload()
        payload["recipes"][0]["execution"] = "parallel-ish"
        with self.assertRaisesRegex(ValueError, "unknown execution class"):
            load_manifest(self.write_manifest(payload))

    def test_rejects_undeclared_lane(self) -> None:
        payload = self.valid_payload()
        payload["recipes"][0]["lane"] = "evm"
        with self.assertRaisesRegex(ValueError, "undeclared lane `evm`"):
            load_manifest(self.write_manifest(payload))

    def test_reports_unknown_and_missing_recipes(self) -> None:
        manifest = load_manifest(self.write_manifest(self.valid_payload()))
        errors = validate_manifest(manifest, {"check"})
        self.assertIn("manifest recipe `build` is not declared by just", errors)
        self.assertIn("serial coverage recipe `build` is not declared by just", errors)

    def test_rejects_serial_coverage_drift(self) -> None:
        payload = self.valid_payload()
        payload["serialCoverage"] = ["build", "product"]
        manifest = load_manifest(self.write_manifest(payload))
        errors = validate_manifest(manifest, {"build", "product"})
        self.assertEqual(
            errors,
            ["serial coverage recipe `product` has no manifest entry"],
        )


if __name__ == "__main__":
    unittest.main()
