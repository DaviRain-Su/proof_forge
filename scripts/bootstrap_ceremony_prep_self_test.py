#!/usr/bin/env python3
"""Self-test for scripts/bootstrap_ceremony_prep.py.

Exercises the full init -> sign-policy -> stage -> sign-required-set chain in
throwaway temporary directories with test-only seeds, plus the seed-custody
failure shapes.  Run with:

    /usr/bin/python3 -I -S scripts/bootstrap_ceremony_prep_self_test.py
"""

from __future__ import annotations

import importlib.util
import json
import secrets
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PREP = REPO_ROOT / "scripts" / "bootstrap_ceremony_prep.py"
SIGN = REPO_ROOT / "scripts" / "bootstrap_sign_tool.py"
CONSUMER = REPO_ROOT / "scripts" / "bootstrap_task_objects.py"
PY = "/usr/bin/python3"

SEED_NAMES = ("architecture", "quality", "release", "security", "service", "verifier-receipt")


class CaseFailure(AssertionError):
    pass


def check(condition: bool, detail: str) -> None:
    if not condition:
        raise CaseFailure(detail)


def load_consumer():
    spec = importlib.util.spec_from_file_location("pf_ceremony_prep_test_consumer", CONSUMER)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run(arguments: list[str], expect_rc: int = 0) -> subprocess.CompletedProcess:
    result = subprocess.run(
        [PY, "-I", "-S", *arguments],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != expect_rc:
        raise CaseFailure(
            f"{arguments[0]} rc={result.returncode} (expected {expect_rc}): "
            f"{result.stderr.strip()[:300]}"
        )
    return result


def make_seeds(root: Path, names=SEED_NAMES, mode: int = 0o400) -> Path:
    seeds = root / "seeds"
    seeds.mkdir(parents=True)
    for name in names:
        path = seeds / f"{name}.seed"
        path.write_text(secrets.token_bytes(32).hex() + "\n", encoding="ascii")
        path.chmod(mode)
    return seeds


def full_chain(root: Path) -> dict[str, Path]:
    seeds = make_seeds(root)
    work = root / "work"
    run([str(PREP), "init", "--seeds-dir", str(seeds), "--workdir", str(work)])
    for name in ("authority-policy.spec.json", "private-scan-policy.json", "service-descriptor.json"):
        check((work / name).is_file(), f"missing {name}")
    policy_out = run(
        [str(SIGN), "sign-authority-policy",
         "--spec", str(work / "authority-policy.spec.json"),
         "--output", str(work / "authority-policy.json")]
    )
    check("signed: bootstrap-authority-root" in policy_out.stdout, "policy not signed")
    run(
        [str(PREP), "stage",
         "--policy", str(work / "authority-policy.json"), "--workdir", str(work)]
    )
    spec_path = work / "required-test-set.spec.json"
    check(spec_path.is_file(), "missing required-test-set.spec.json")
    spec_text = spec_path.read_text(encoding="utf-8")
    spec_text = spec_text.replace("<seeds-dir>", str(seeds))
    spec_path.chmod(0o644)
    spec_path.write_text(spec_text, encoding="utf-8")
    rts_out = run(
        [str(SIGN), "sign-required-test-set",
         "--spec", str(spec_path), "--output", str(work / "required-test-set.json")]
    )
    check("signed: bootstrap-required-test-set" in rts_out.stdout, "required set not signed")
    descriptor = json.loads((work / "service-descriptor.json").read_text())
    spec = json.loads(spec_path.read_text())
    return {"descriptor": descriptor, "rts_spec": spec, "work": work}


def case_happy_chain(base: Path) -> None:
    result = full_chain(base / "happy")
    descriptor = result["descriptor"]
    check(descriptor["schema"] == "proof-forge.authority-store-service.v1", "descriptor schema")
    check(descriptor["maximumFrameBytes"] == 4194304, "descriptor frame budget")
    check(len(descriptor["servicePublicKey"]) == 64, "service public key shape")
    fields = result["rts_spec"]["fields"]
    check(fields["phase5Document"]["status"] == "accepted", "phase5 must be accepted")
    check(
        fields["requiredTestIds"] == sorted(fields["requiredTestIds"]),
        "required ids must be sorted",
    )
    spec_text = (result["work"] / "authority-policy.spec.json").read_text()
    check("seedFile" not in spec_text, "policy spec must not carry seed material")
    consumer = load_consumer()
    snapshot = consumer.BootstrapDocumentSnapshotV1(
        "PHASE-5",
        "docs/05-test-spec.md",
        (REPO_ROOT / "docs" / "05-test-spec.md").read_bytes(),
    )
    derived = consumer.parse_phase5_snapshot_content(snapshot)
    check(
        fields["phase5Document"]["contentDigest"]
        == "sha256:" + derived.document.contentDigest.bytes.hex(),
        "phase5 contentDigest must be the consumer-derived domain digest",
    )
    check(
        fields["requiredTestIds"] == list(derived.requiredTestIds),
        "required ids must be the full PHASE-5 denominator",
    )


def case_seed_mode_rejected(base: Path) -> None:
    root = base / "wide-mode"
    seeds = make_seeds(root, mode=0o644)
    work = root / "work"
    result = subprocess.run(
        [PY, "-I", "-S", str(PREP), "init", "--seeds-dir", str(seeds), "--workdir", str(work)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    check(result.returncode == 1, "wide-mode seed must fail")
    check("PF-CEREMONY-IO" in result.stderr, "expected PF-CEREMONY-IO")
    check("seed" not in result.stdout.lower() or ".seed" not in result.stdout, "no seed echo")


def case_missing_seed_file(base: Path) -> None:
    root = base / "missing"
    seeds = root / "seeds"
    seeds.mkdir(parents=True)
    work = root / "work"
    result = subprocess.run(
        [PY, "-I", "-S", str(PREP), "init", "--seeds-dir", str(seeds), "--workdir", str(work)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    check(result.returncode == 1, "missing seed files must fail")
    check("PF-CEREMONY-IO" in result.stderr, "expected PF-CEREMONY-IO")


def main() -> int:
    failures: list[str] = []
    for name, case in (
        ("happy-chain", case_happy_chain),
        ("seed-mode", case_seed_mode_rejected),
        ("missing-seed", case_missing_seed_file),
    ):
        try:
            with tempfile.TemporaryDirectory(prefix="pf-ceremony-test-") as temporary:
                case(Path(temporary))
        except Exception as error:  # noqa: BLE001 - report and continue
            failures.append(f"{name}: {type(error).__name__}: {error}")
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print("bootstrap-ceremony-prep-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
