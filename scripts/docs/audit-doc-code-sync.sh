#!/usr/bin/env bash
# Mechanical doc↔code sync audit for ProofForge.
#
# Compares Lean registry/CLI, justfile recipes, Examples/, and Stdlib/
# against README, shared-scenario, validation-gates, capability-registry,
# and Chinese mirror docs.
#
# Usage:
#   scripts/docs/audit-doc-code-sync.sh           # write build/doc-sync-audit.md
#   scripts/docs/audit-doc-code-sync.sh --check   # exit 1 if any P0 mechanical drift
#
# Output: build/doc-sync-audit.md (and build/doc-sync-audit.json for tooling)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=true
fi

OUT_MD="${DOC_SYNC_OUT:-build/doc-sync-audit.md}"
OUT_JSON="${DOC_SYNC_JSON:-build/doc-sync-audit.json}"
mkdir -p build

python3 - "$REPO_ROOT" "$OUT_MD" "$OUT_JSON" "$CHECK_MODE" <<'PY'
import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
out_md = Path(sys.argv[2])
out_json = Path(sys.argv[3])
check_mode = sys.argv[4].lower() == "true"

findings: list[dict] = []


def add(fid: str, category: str, severity: str, doc: str, code: str, fix: str) -> None:
    findings.append({
        "id": fid,
        "category": category,
        "severity": severity,
        "doc": doc,
        "code": code,
        "fix": fix,
    })


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def extract_backtick_ids(text: str) -> set[str]:
    return set(re.findall(r"`([a-z][a-z0-9-]+)`", text))


def parse_registry_known_ids(text: str) -> set[str]:
    # all.map after filter deprecated — extract id := "..." from profile defs in allIncludingDeprecated block
    ids: set[str] = set()
    for m in re.finditer(r'id\s*:=\s*"([^"]+)"', text):
        tid = m.group(1)
        if tid not in ("robinhood-chain-testnet", "anvil-local"):
            ids.add(tid)
    # Remove deprecated hidden from knownIds — solana-sbpf-linker, solana-zig-fork
    ids -= {"solana-sbpf-linker", "solana-zig-fork"}
    return ids


def parse_supported_target_ids(text: str) -> set[str]:
    m = re.search(
        r"def supportedTargetIds\s*:\s*Array String\s*:=\s*#\[([^\]]+)\]",
        text,
        re.S,
    )
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))


def parse_profile_capabilities(registry_text: str) -> dict[str, set[str]]:
    """Map target id -> set of .capabilityName tokens from capabilities := #[ ... ] blocks."""
    profiles: dict[str, set[str]] = {}
    # Split on def <name> : TargetProfile
    chunks = re.split(r"\ndef (\w+)\s*:\s*TargetProfile\s*:=\s*\{", registry_text)
    i = 1
    while i + 1 < len(chunks):
        _def_name, body = chunks[i], chunks[i + 1]
        id_m = re.search(r'id\s*:=\s*"([^"]+)"', body)
        cap_m = re.search(r"capabilities\s*:=\s*#\[([^\]]*)\]", body, re.S)
        if id_m and cap_m:
            caps = set(re.findall(r"\.(\w+)", cap_m.group(1)))
            profiles[id_m.group(1)] = caps
        i += 2
    return profiles


CAPABILITY_ID_TO_REGISTRY = {
    "storage.scalar": "storageScalar",
    "storage.map": "storageMap",
    "storage.array": "storageArray",
    "caller.sender": "callerSender",
    "value.native": "valueNative",
    "events.emit": "eventsEmit",
    "crosscall.invoke": "crosscallInvoke",
    "env.block": "envBlock",
    "control.conditional": "controlConditional",
    "control.bounded_loop": "controlBoundedLoop",
    "data.fixed_array": "dataFixedArray",
    "data.dynamic_bytes": "dataDynamicBytes",
    "data.struct": "dataStruct",
    "crypto.hash": "cryptoHash",
    "assertions.check": "assertions",
    "account.explicit": "accountExplicit",
    "storage.pda": "storagePda",
    "runtime.allocator": "runtimeAllocator",
    "runtime.memory": "runtimeMemory",
    "crosscall.cpi": "crosscallCpi",
    "near.promise": "nearPromise",
}


def parse_capability_registry_table(text: str) -> dict[str, dict[str, str]]:
    """capability id -> {target_col: Y|P|N|—} for markdown table rows."""
    rows: dict[str, dict[str, str]] = {}
    col_names: list[str] = []
    in_core = False
    for line in text.splitlines():
        if line.startswith("## Core Capabilities"):
            in_core = True
            continue
        if in_core and line.startswith("## ") and "Core Capabilities" not in line:
            break
        if not in_core or not line.startswith("| `"):
            if in_core and line.startswith("| Capability id"):
                headers = [h.strip() for h in line.split("|")[1:-1]]
                col_names = headers[1:]  # skip capability id
            continue
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if len(parts) < 2:
            continue
        cap_id = parts[0].strip("`")
        rows[cap_id] = {}
        for col, val in zip(col_names, parts[1:]):
            rows[cap_id][col.strip()] = val.strip()
    return rows


COL_TO_TARGET = {
    "EVM": "evm",
    "NEAR": "wasm-near",
    "CosmWasm": "wasm-cosmwasm",
    "Solana": "solana-sbpf-asm",
    "Aptos": "move-aptos",
    "Sui": "move-sui",
    "Psy DPN": "psy-dpn",
    "CF Workers": "wasm-cloudflare-workers",
}


def registry_has_cap(profile_caps: set[str], cap_id: str) -> bool:
    reg = CAPABILITY_ID_TO_REGISTRY.get(cap_id)
    return reg in profile_caps if reg else False


def ypn_to_bool(val: str) -> str:
    v = val.strip()
    if v in ("Y", "P"):
        return "yes"
    if v in ("N", "—", "-"):
        return "no"
    return "unknown"


def parse_readme_backend_targets(text: str) -> set[str]:
    ids: set[str] = set()
    in_table = False
    for line in text.splitlines():
        if line.startswith("| Target id |"):
            in_table = True
            continue
        if in_table:
            if not line.startswith("| `"):
                if ids:
                    break
                continue
            m = re.match(r"\|\s*`([^`]+)`", line)
            if m:
                ids.add(m.group(1))
    return ids


def parse_shared_scenario_examples(text: str) -> dict[str, str]:
    """target label -> status cell text from Example Locations table."""
    result: dict[str, str] = {}
    in_section = False
    for line in text.splitlines():
        if line.startswith("## Example Locations"):
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if not in_section or not line.startswith("|"):
            continue
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if len(parts) >= 3 and parts[0] not in ("Target", "---", "**All primary chains**"):
            result[parts[0]] = parts[2]
        if len(parts) >= 3 and parts[0] == "**All primary chains**":
            result["primary"] = parts[2]
    return result


def parse_just_recipes(text: str) -> set[str]:
    recipes: set[str] = set()
    for line in text.splitlines():
        m = re.match(r"^([a-zA-Z0-9_-]+)(?: .*)?:", line)
        if m and not line.startswith("set "):
            recipes.add(m.group(1))
    return recipes


def parse_validation_gates_planned(text: str) -> list[str]:
    items: list[str] = []
    in_planned = False
    for line in text.splitlines():
        if line.startswith("## Planned gates"):
            in_planned = True
            continue
        if in_planned and line.startswith("## ") and "Planned" not in line:
            break
        if in_planned and line.startswith("- "):
            items.append(line[2:].strip())
    return items


def parse_validation_gates_current_just_refs(text: str) -> set[str]:
    refs: set[str] = set()
    for m in re.finditer(r"`just ([a-zA-Z0-9_-]+)`", text):
        refs.add(m.group(1))
    for m in re.finditer(r"\|\s*`just ([a-zA-Z0-9_-]+)`", text):
        refs.add(m.group(1))
    return refs


def parse_sdk_gaps_covered(text: str) -> set[str]:
    covered: set[str] = set()
    in_evm = False
    for line in text.splitlines():
        if line.startswith("## EVM"):
            in_evm = True
        elif line.startswith("## ") and in_evm:
            break
        if in_evm and line.startswith("|") and "Covered" in line:
            parts = [p.strip() for p in line.split("|")[1:-1]]
            if parts and parts[0] not in ("Feature", "---"):
                covered.add(parts[0])
    return covered


# --- Load sources ---
registry_text = read_text(repo / "ProofForge/Target/Registry.lean")
fixture_text = read_text(repo / "ProofForge/Cli/Fixture.lean")
readme = read_text(repo / "README.md")
zh_readme = read_text(repo / "docs/zh/README-root.zh.md")
shared = read_text(repo / "docs/shared-scenario.md")
justfile = read_text(repo / "justfile")
val_gates = read_text(repo / "docs/validation-gates.md")
cap_reg = read_text(repo / "docs/capability-registry.md")
sdk_gaps = read_text(repo / "docs/sdk-ecosystem-gaps-2026-07.md")
cf_workers = read_text(repo / "docs/targets/cloudflare-workers.md")
targets_readme = read_text(repo / "docs/targets/README.md")

registry_ids = parse_registry_known_ids(registry_text)
cli_ids = parse_supported_target_ids(fixture_text)
readme_ids = parse_readme_backend_targets(readme)
zh_ids = parse_readme_backend_targets(zh_readme)
profile_caps = parse_profile_capabilities(registry_text)
cap_table = parse_capability_registry_table(cap_reg)
just_recipes = parse_just_recipes(justfile)
planned_gates = parse_validation_gates_planned(val_gates)
current_just_refs = parse_validation_gates_current_just_refs(val_gates)
sdk_covered = parse_sdk_gaps_covered(sdk_gaps)
shared_examples = parse_shared_scenario_examples(shared)

stdlib_files = {p.stem for p in (repo / "ProofForge/Contract/Stdlib").glob("*.lean")}

# Example paths on disk
example_paths = {
    "CosmWasm Counter.lean": (repo / "Examples/CosmWasm/Counter.lean").is_file(),
    "CosmWasm golden.wat": (repo / "Examples/CosmWasm/Counter.golden.wat").is_file(),
    "Aptos Move/Aptos": (repo / "Examples/Move/Aptos/Counter").is_dir(),
    "Aptos Counter/golden": (repo / "Examples/Aptos/Counter/golden").is_dir(),
    "CF Counter.lean": (repo / "Examples/CloudflareWorkers/Counter.lean").is_file(),
    "CF Counter dir": (repo / "Examples/CloudflareWorkers/Counter").is_dir(),
    "Shared Counter.lean": (repo / "Examples/Shared/Counter.lean").is_file(),
}

# --- A. Target inventory ---
only_registry = sorted(registry_ids - readme_ids)
only_readme = sorted(readme_ids - registry_ids)
cli_not_registry = sorted(cli_ids - registry_ids)
registry_not_cli = sorted(registry_ids - cli_ids - {"wasm-cloudflare-workers"})

for tid in only_registry:
    add(
        f"DC-TGT-{tid.replace('-', '_').upper()}",
        "target_inventory",
        "P1",
        f"README.md Backend Status table",
        f"ProofForge/Target/Registry.lean id `{tid}`",
        f"Add `{tid}` row to README Backend Status (or remove from registry if deprecated).",
    )

# CLI-only targets not in Registry.knownIds (documented, not drift)
CLI_ONLY_README = {"aleo-leo"}

for tid in only_readme:
    if tid in CLI_ONLY_README:
        continue
    add(
        f"DC-TGT-README-{tid.replace('-', '_').upper()}",
        "target_inventory",
        "P1",
        f"README.md lists `{tid}`",
        "Registry.knownIds",
        f"Remove README row or add target to Registry.",
    )

for tid in cli_not_registry:
    add(
        f"DC-CLI-{tid.replace('-', '_').upper()}",
        "target_inventory",
        "P2",
        "docs (registry vs CLI boundary)",
        f"Cli/Fixture.supportedTargetIds has `{tid}` but not Registry.knownIds",
        f"Document `{tid}` as CLI-only spike (aleo-leo, quint) in README/AGENTS.",
    )

zh_missing = sorted(readme_ids - zh_ids)
for tid in zh_missing:
    add(
        f"DC-ZH-{tid.replace('-', '_').upper()}",
        "i18n",
        "P2",
        f"docs/zh/README-root.zh.md Backend table missing `{tid}`",
        f"README.md has `{tid}`",
        f"Sync Chinese README after English source is updated; run translate-docs.py.",
    )

# --- B. Example locations ---
if shared_examples.get("CosmWasm", "").lower().find("planned") >= 0 and example_paths["CosmWasm golden.wat"]:
    add(
        "DC-EX-COSMWASM",
        "examples",
        "P0",
        "docs/shared-scenario.md: CosmWasm Counter.lean Planned, not in repo",
        "Examples/CosmWasm/Counter.golden.wat exists; emit via fixture counter",
        "Update path to Counter.golden.wat; status Spike (golden fixture, no contract_source yet).",
    )

if shared_examples.get("Aptos", "").lower().find("planned") >= 0 and example_paths["Aptos Counter/golden"]:
    add(
        "DC-EX-APTOS",
        "examples",
        "P0",
        "docs/shared-scenario.md: Examples/Move/Aptos/Counter/ Planned",
        "Examples/Aptos/Counter/golden/ exists",
        "Update path to Examples/Aptos/Counter/golden/; status Spike.",
    )

if "Planned, not in repo" in cf_workers and example_paths["CF Counter dir"]:
    add(
        "DC-EX-CF",
        "examples",
        "P0",
        "docs/targets/cloudflare-workers.md Example Locations",
        "Examples/CloudflareWorkers/Counter/ (wrangler package)",
        "Mark In repo (TS spike package); note IR emit produces build/ts/Counter.ts.",
    )

# --- C. Cloudflare backend claim ---
if "no local backend yet" in cf_workers.lower():
    if (repo / "ProofForge/Compiler/TS/Emit.lean").is_file():
        add(
            "DC-CF-BACKEND",
            "target_status",
            "P0",
            "docs/targets/cloudflare-workers.md: no local backend yet",
            "ProofForge/Compiler/TS/Emit.lean + registry wasm-cloudflare-workers",
            "Stage → Spike; pipeline IR → TypeScript (not EmitZig).",
        )

# --- D. targets/README stale EVM note ---
if "lacks target registry" in targets_readme.lower():
    add(
        "DC-TGT-README-EVM-REG",
        "target_status",
        "P1",
        "docs/targets/README.md: EVM lacks target registry",
        "evm in Registry.lean; portable-counter-multi-target smoke",
        "Remove outdated sentence; EVM is in registry with portable IR.",
    )

if "Sui Move | Move/object sourcegen | Follows Aptos" in targets_readme.replace("\n", " "):
    if (repo / "ProofForge/Backend/Move/Sui.lean").is_file():
        add(
            "DC-TGT-README-SUI",
            "target_status",
            "P1",
            "docs/targets/README.md Tier-3: Sui follows Aptos (parked)",
            "move-sui Counter MVP implemented; README has move-sui row",
            "Move Sui to Maintenance-Only Landed Inventory; beyond-Counter remains roadmap.",
        )

# --- E. Capability registry vs Registry.lean (primary targets) ---
for cap_id, cols in cap_table.items():
    reg_name = CAPABILITY_ID_TO_REGISTRY.get(cap_id)
    if not reg_name:
        continue
    for col, target_id in COL_TO_TARGET.items():
        if col not in cols:
            continue
        doc_val = ypn_to_bool(cols[col])
        has = registry_has_cap(profile_caps.get(target_id, set()), cap_id)
        if doc_val == "yes" and not has:
            add(
                f"DC-CAP-{cap_id.replace('.', '_')}-{target_id.replace('-', '_')}",
                "capability",
                "P2",
                f"capability-registry.md `{cap_id}` {col}={cols[col]}",
                f"Registry {target_id} lacks .{reg_name}",
                f"Set {col} to N or add capability to Registry profile.",
            )
        elif doc_val == "no" and has:
            add(
                f"DC-CAP-MISS-{cap_id.replace('.', '_')}-{target_id.replace('-', '_')}",
                "capability",
                "P2",
                f"capability-registry.md `{cap_id}` {col}={cols[col]}",
                f"Registry {target_id} has .{reg_name}",
                f"Set {col} to Y or P.",
            )

# --- F. Stdlib vs sdk-gaps ---
STDLIB_FEATURE_MAP = {
    "ERC-20": "ERC20",
    "ERC-721 (NFT)": "ERC721",
    "ERC-1155 (multi-token)": "ERC1155",
    "ERC-165 (supportsInterface)": "ERC165",
    "Ownable": "Ownable",
    "AccessControl (roles)": "AccessControl",
    "Pausable": "Pausable",
    "ReentrancyGuard": "ReentrancyGuard",
    "CREATE2 factory": "Create2Factory",
}

for feature, stem in STDLIB_FEATURE_MAP.items():
    if stem in stdlib_files and feature not in sdk_covered:
        add(
            f"DC-SDK-{stem.upper()}",
            "sdk",
            "P2",
            f"sdk-ecosystem-gaps: {feature} not marked Covered",
            f"ProofForge/Contract/Stdlib/{stem}.lean",
            f"Update sdk-gaps status or README stdlib list with cross-ref.",
        )

if "UUPSProxy" in stdlib_files or "UUPSUpgradeable" in stdlib_files:
    uups_line = [l for l in sdk_gaps.splitlines() if "UUPS proxy" in l]
    if uups_line and "Missing" in uups_line[0]:
        add(
            "DC-SDK-UUPS",
            "sdk",
            "P2",
            "sdk-ecosystem-gaps: UUPS proxy Missing",
            "Stdlib/UUPSProxy.lean + UUPSUpgradeable.lean exist",
            "Clarify: stdlib mixin exists; product UpgradePolicy may still restrict — mark Partial.",
        )

# --- G. just check description ---
if "Lean + EVM + Psy" in readme and "solana-light" in justfile:
    add(
        "DC-README-CHECK",
        "gates",
        "P1",
        "README.md: just check described as Lean + EVM + Psy only",
        "justfile check includes solana-light, near-target-first, testkit, quint",
        "Update description to match just check recipe deps.",
    )

# --- H. Planned gates that reference existing scripts ---
LANDED_SCRIPT_MARKERS = [
    ("cosmwasm-check", "cosmwasm-counter-smoke", "CosmWasm smoke"),
    ("proof-forge build --target", "cli-target-first", "unified target-oriented build"),
    ("Golden Yul", "evm-build-examples", "Golden Yul snapshots"),
]

for marker, recipe, label in LANDED_SCRIPT_MARKERS:
    planned_text = "\n".join(planned_gates)
    if marker.lower() in planned_text.lower():
        if recipe in just_recipes or any(recipe in p for p in just_recipes):
            add(
                f"DC-GATE-{recipe.upper().replace('-', '_')}",
                "gates",
                "P1",
                f"validation-gates.md Planned: {label}",
                f"just {recipe} exists in justfile",
                f"Move from Planned to Current gates section.",
            )

# Current gates referencing missing just recipes
missing_just = sorted(current_just_refs - just_recipes)
for r in missing_just[:20]:
    add(
        f"DC-GATE-MISS-{r.upper().replace('-', '_')}",
        "gates",
        "P2",
        f"validation-gates.md references `just {r}`",
        "justfile",
        f"Add recipe or fix doc reference.",
    )

# --- Summary stats ---
p0 = sum(1 for f in findings if f["severity"] == "P0")
p1 = sum(1 for f in findings if f["severity"] == "P1")
p2 = sum(1 for f in findings if f["severity"] == "P2")

report = {
    "generated": "mechanical",
    "registry_ids": sorted(registry_ids),
    "cli_ids": sorted(cli_ids),
    "readme_ids": sorted(readme_ids),
    "zh_ids": sorted(zh_ids),
    "just_recipe_count": len(just_recipes),
    "stdlib_modules": sorted(stdlib_files),
    "findings": findings,
    "summary": {"P0": p0, "P1": p1, "P2": p2, "total": len(findings)},
}

out_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

lines = [
    "# Doc↔Code Mechanical Sync Audit",
    "",
    "Generated by `scripts/docs/audit-doc-code-sync.sh`.",
    "Semantic gaps (backlog checkboxes, RFC dates) are in `docs/doc-code-sync-audit-2026-07.md`.",
    "",
    "## Summary",
    "",
    f"| Severity | Count |",
    f"|----------|-------|",
    f"| P0 | {p0} |",
    f"| P1 | {p1} |",
    f"| P2 | {p2} |",
    f"| **Total** | **{len(findings)}** |",
    "",
    "## Source snapshots",
    "",
    f"- Registry `knownIds`: {', '.join(f'`{x}`' for x in sorted(registry_ids))}",
    f"- CLI `supportedTargetIds`: {', '.join(f'`{x}`' for x in sorted(cli_ids))}",
    f"- README Backend table: {', '.join(f'`{x}`' for x in sorted(readme_ids))}",
    f"- zh README Backend table: {', '.join(f'`{x}`' for x in sorted(zh_ids))}",
    f"- justfile recipes: {len(just_recipes)}",
    f"- Stdlib modules: {len(stdlib_files)}",
    "",
    "## Findings",
    "",
    "| ID | Sev | Category | Doc | Code | Suggested fix |",
    "|----|-----|----------|-----|------|---------------|",
]

for f in findings:
    doc = f["doc"].replace("|", "\\|")
    code = f["code"].replace("|", "\\|")
    fix = f["fix"].replace("|", "\\|")
    lines.append(
        f"| {f['id']} | {f['severity']} | {f['category']} | {doc} | {code} | {fix} |"
    )

lines.append("")
out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(f"Wrote {out_md} ({len(findings)} findings: P0={p0} P1={p1} P2={p2})")
print(f"Wrote {out_json}")

if check_mode and p0 > 0:
    sys.exit(1)
PY
