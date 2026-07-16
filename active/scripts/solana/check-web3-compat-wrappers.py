#!/usr/bin/env python3
"""Validate legacy Solana Web3.js compatibility wrappers.

The Web3.js-backed live gates have been replaced by Rust/live harnesses. The
old script and just recipe names remain as compatibility entrypoints only; this
check prevents them from growing test logic again.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
SOLANA_DIR = REPO_ROOT / "scripts" / "solana"
JUSTFILE = REPO_ROOT / "justfile"

SCRIPT_ONLY_COMPAT = {
    "surfpool-web3-smoke.sh",
}


def fail(message: str) -> None:
    print(f"solana-web3-compat: {message}", file=sys.stderr)
    raise SystemExit(1)


def script_to_recipe(script_name: str) -> str:
    suffix = "-smoke.sh"
    if not script_name.endswith(suffix):
        fail(f"unexpected smoke script name: {script_name}")
    return "solana-" + script_name[: -len(suffix)]


def validate_wrapper(path: Path) -> str:
    rel = path.relative_to(REPO_ROOT).as_posix()
    text = path.read_text(encoding="utf-8")

    if not text.startswith("#!/usr/bin/env bash\n"):
        fail(f"{rel}: missing bash shebang")
    if "set -euo pipefail" not in text:
        fail(f"{rel}: missing strict shell mode")
    if "REPO_ROOT=" not in text:
        fail(f"{rel}: missing repo-root calculation")
    if re.search(r"\b(node|npm|yarn|pnpm)\b|@solana/web3", text):
        fail(f"{rel}: compatibility wrapper must not invoke JS tooling")

    exec_matches = re.findall(r'exec "\$REPO_ROOT/scripts/solana/([^"]+)" "\$@"', text)
    if len(exec_matches) != 1:
        fail(f"{rel}: expected exactly one exec to a Solana target script")
    target_name = exec_matches[0]
    if "web3" in target_name:
        fail(f"{rel}: target script is still Web3-named: {target_name}")
    target = SOLANA_DIR / target_name
    if not target.exists():
        fail(f"{rel}: target script does not exist: scripts/solana/{target_name}")
    return target_name


def validate_just_alias(wrapper_name: str, target_name: str, justfile: str) -> None:
    if wrapper_name in SCRIPT_ONLY_COMPAT:
        return
    alias = script_to_recipe(wrapper_name)
    target = script_to_recipe(target_name)
    pattern = rf"(?m)^{re.escape(alias)}:\s+{re.escape(target)}$"
    if not re.search(pattern, justfile):
        fail(f"justfile: missing compatibility alias `{alias}: {target}`")


def main() -> int:
    wrappers = sorted(SOLANA_DIR.glob("*web3*smoke.sh"))
    if not wrappers:
        fail("no legacy Web3 compatibility wrappers found")
    justfile = JUSTFILE.read_text(encoding="utf-8")

    for wrapper in wrappers:
        target = validate_wrapper(wrapper)
        validate_just_alias(wrapper.name, target, justfile)

    print(f"solana-web3-compat: ok ({len(wrappers)} wrapper(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
