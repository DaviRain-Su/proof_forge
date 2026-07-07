#!/usr/bin/env python3
"""Validate legacy Learn-token compatibility wrappers.

The canonical token gates are token-intent based. The former Learn-token script
and just recipe names remain as compatibility entrypoints only; this check keeps
them as thin forwards instead of letting legacy test logic grow back.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
JUSTFILE = REPO_ROOT / "justfile"


@dataclass(frozen=True)
class Wrapper:
    script: str
    target_script: str
    recipe: str
    target_recipe: str


WRAPPERS = (
    Wrapper(
        script="scripts/portable/learn-token-smoke.sh",
        target_script="scripts/portable/token-intent-smoke.sh",
        recipe="learn-token-smoke",
        target_recipe="token-intent-smoke",
    ),
    Wrapper(
        script="scripts/evm/learn-token-erc20-vm-smoke.sh",
        target_script="scripts/evm/token-intent-evm-vm-smoke.sh",
        recipe="learn-token-evm-vm",
        target_recipe="token-intent-evm-vm",
    ),
)


def fail(message: str) -> None:
    print(f"token-compat-wrappers: {message}", file=sys.stderr)
    raise SystemExit(1)


def meaningful_lines(text: str) -> list[str]:
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#") and not stripped.startswith("#!"):
            continue
        lines.append(stripped)
    return lines


def validate_wrapper(wrapper: Wrapper) -> None:
    path = REPO_ROOT / wrapper.script
    target = REPO_ROOT / wrapper.target_script
    if not path.exists():
        fail(f"{wrapper.script}: missing compatibility wrapper")
    if not target.exists():
        fail(f"{wrapper.script}: target script does not exist: {wrapper.target_script}")

    text = path.read_text(encoding="utf-8")
    lines = meaningful_lines(text)
    if len(lines) != 4:
        fail(f"{wrapper.script}: wrapper must contain only shebang, strict mode, repo-root calculation, and exec")
    if lines[0] != "#!/usr/bin/env bash":
        fail(f"{wrapper.script}: missing bash shebang")
    if lines[1] != "set -euo pipefail":
        fail(f"{wrapper.script}: missing strict shell mode")

    root_match = re.fullmatch(
        r'([A-Z_]+)="\$\(cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/\.\./\.\." && pwd\)"',
        lines[2],
    )
    if not root_match:
        fail(f"{wrapper.script}: missing repo-root calculation from BASH_SOURCE")
    root_var = root_match.group(1)

    exec_match = re.fullmatch(rf'exec "\${root_var}/([^"]+)" "\$@"', lines[3])
    if not exec_match:
        fail(f"{wrapper.script}: expected exactly one exec using ${root_var}")
    actual_target = exec_match.group(1)
    if actual_target != wrapper.target_script:
        fail(f"{wrapper.script}: forwards to {actual_target}, expected {wrapper.target_script}")

    forbidden = re.compile(r"\b(lake|cargo|solc|node|npm|yarn|pnpm)\b|@solana/web3")
    for line in lines[:-1]:
        if forbidden.search(line):
            fail(f"{wrapper.script}: compatibility wrapper must not run test/build tooling")


def validate_just_aliases() -> None:
    justfile = JUSTFILE.read_text(encoding="utf-8")
    for wrapper in WRAPPERS:
        pattern = rf"(?m)^{re.escape(wrapper.recipe)}:\s+{re.escape(wrapper.target_recipe)}$"
        if not re.search(pattern, justfile):
            fail(f"justfile: missing compatibility alias `{wrapper.recipe}: {wrapper.target_recipe}`")


def main() -> int:
    for wrapper in WRAPPERS:
        validate_wrapper(wrapper)
    validate_just_aliases()
    print(f"token-compat-wrappers: ok ({len(WRAPPERS)} wrapper(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
