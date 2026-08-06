#!/usr/bin/env bash
# #125 Solana CPI CLI/product acceptance shell (fail-closed).
#
# Product path only: builds EscrowCpi via ordinary proof-forge-next with
# exact profile solana-sbpf-cpi-elf-v1 into a proof-forge.output.v1 tree.
# Does NOT consume runtime preactivation manifests (#118–#124), does not
# mint via private exporters, and does not activate ordinary resolver claims
# by itself — it only accepts when the product chain already mints.
#
# Expected product leaves (artifactProgramName = EscrowCpi; product-core base order):
#   materialized-base: .cpi-plan.json .cpi-ir.json .idl.json .s .cpi-bindings.json
#   finalized-extra:   .so
#   sidecars:          manifest.json evidence.json
# Manifest files order remains role-rank then path (exact closure validator).
#
# Exit codes:
#   0 success (product activation path green)
#   1 product / acceptance failure (fail closed)
#   2 missing tools / usage / unsafe out dir
#
# Env:
#   PROOF_FORGE_CPI_PRODUCT_OUT  override output dir (must stay under <repo>/build)
#   PROOF_FORGE_TOOL_ROOT        locked tool root (sbpf optional here; product
#                                finalize may require it when core is ready)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

label="solana-cpi-product-acceptance"

die() {
  echo "${label}: $*" >&2
  exit 1
}

missing() {
  echo "${label}: $*" >&2
  exit 2
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    missing "unsupported host platform: $(uname -s)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

if ! command -v lake >/dev/null 2>&1; then
  missing "lake not on PATH"
fi

if [[ -x /usr/bin/python3 ]]; then
  python_bin=/usr/bin/python3
elif command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
else
  missing "python3 not found"
fi

cli="$root/.lake/build/bin/proof-forge-next"
source_rel="runtime-tests/solana/fixtures/EscrowCpi.lean"
source_path="$root/$source_rel"
module_name="Examples.EscrowCpi"
program_name="EscrowCpi"
target_id="solana"
profile_id="solana-sbpf-cpi-elf-v1"
default_profile_id="solana-sbpf-cpi-elf-v1"
# Retired shims (ADR-0032 U1): must fail closed if selected.
legacy_plan_profile="solana-sbpf-plan-v1"
legacy_elf_profile="solana-sbpf-elf-v1"

# Active #125 pins from CpiContractV1 activeProfileDigestV1 / activeCatalogDigestV1
# (not historical preactivation profile/catalog digests).
ACTIVE_PROFILE_DIGEST="sha256:b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04"
ACTIVE_CATALOG_DIGEST="sha256:e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419"
ACTIVE_EXTENSION_DIGEST="sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"
ACTIVE_IMPLEMENTATION_STATE="product-exact-synchronous-call-active-v1"
PLAN_SCHEMA="proof-forge.solana.cpi-plan.v1"
# Product composite IR canonical text uses product-ir schema (extension still .json).
IR_SCHEMA="proof-forge.solana.cpi-product-ir.v1"
IDL_SCHEMA="proof-forge.solana.cpi-idl.v1"
BINDINGS_SCHEMA="proof-forge.solana.cpi-bindings.v1"
OUTPUT_SCHEMA="proof-forge.output.v1"

[[ -f "$source_path" && ! -L "$source_path" ]] \
  || die "missing regular non-symlink fixture $source_path"

# --- resolve / constrain product output directory under repo build/ ----------
out_dir_raw="${PROOF_FORGE_CPI_PRODUCT_OUT:-$root/build/v2/solana-cpi-product}"
out_dir="$($python_bin -I -S - "$root" "$out_dir_raw" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve(strict=True)
build = (root / "build").resolve(strict=False)
candidate = Path(sys.argv[2])
if not candidate.is_absolute():
    candidate = root / candidate
candidate = candidate.resolve(strict=False)
try:
    relative = candidate.relative_to(build)
except ValueError as exc:
    raise SystemExit(f"PROOF_FORGE_CPI_PRODUCT_OUT must be under {build}") from exc
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || missing "unsafe PROOF_FORGE_CPI_PRODUCT_OUT"

# Parent of product out for temporary negative trees (also under build/).
product_parent="$(dirname "$out_dir")"
mkdir -p "$product_parent"

# Darwin mktemp requires the template to end with continuous XXXXXX (no suffix).
# Isolate all transient logs/negatives under a fresh work dir; never reuse fixed
# sibling names that could collide with a prior interrupted run's logs.
work_tmp="$(mktemp -d "$product_parent/solana-cpi-product-acceptance.XXXXXX")" \
  || missing "create acceptance work dir"
cleanup_work_tmp() {
  rm -rf "$work_tmp"
}
trap cleanup_work_tmp EXIT

# --- ensure product CLI binary ----------------------------------------------
if [[ ! -x "$cli" ]]; then
  echo "${label}: building proof-forge-next (lake build proof_forge_next)"
  lake build proof_forge_next || die "lake build proof_forge_next failed"
fi
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run product CLI; capture combined log; return CLI exit code (not pipe).
run_cli_logged() {
  # Usage: run_cli_logged <logfile> -- <cli args...>
  local logfile="$1"
  shift
  if [[ "${1:-}" != "--" ]]; then
    die "run_cli_logged internal: expected --"
  fi
  shift
  set +e
  lake env "$cli" "$@" >"$logfile" 2>&1
  local ec=$?
  set -e
  return "$ec"
}

assert_zero_output_tree() {
  local tree="$1"
  local ctx="$2"
  # Fail-closed zero output: path must be absent, or an empty real directory.
  # A regular file / symlink / non-dir residual is never acceptable.
  if [[ ! -e "$tree" ]]; then
    return 0
  fi
  if [[ -L "$tree" ]]; then
    die "${ctx}: expected zero output but path is a symlink: $tree"
  fi
  if [[ -f "$tree" ]]; then
    die "${ctx}: expected zero output but path is a regular file: $tree"
  fi
  if [[ ! -d "$tree" ]]; then
    die "${ctx}: expected zero output but path is not a directory: $tree"
  fi
  local count
  count="$(find "$tree" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" != "0" ]]; then
    die "${ctx}: expected empty output directory under $tree (found $count entries)"
  fi
}

assert_fail_closed_diagnostic() {
  local logfile="$1"
  local ctx="$2"
  # Closed diagnostic code set only (no generic "unsupported" substring).
  if ! "$python_bin" -I -S - "$logfile" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
# Exact closed product/plan/toolchain failure codes observed on fail-closed paths.
CLOSED_CODES = (
    "PF-REQ-UNSUPPORTED",
    "PF-PLAN-INVARIANT",
    "PF-SRC-INVALID",
    "PF-ARTIFACT-NONDEPLOYABLE",
    "PF-ARTIFACT-INVALID",
    "PF-TOOLCHAIN-MISSING",
    "PF-TOOLCHAIN-MISMATCH",
)
if any(code in text for code in CLOSED_CODES):
    raise SystemExit(0)
# Also accept exact wire form "CODE: message" for the closed set.
wire = re.compile(
    r"\b(PF-REQ-UNSUPPORTED|PF-PLAN-INVARIANT|PF-SRC-INVALID|"
    r"PF-ARTIFACT-NONDEPLOYABLE|PF-ARTIFACT-INVALID|"
    r"PF-TOOLCHAIN-MISSING|PF-TOOLCHAIN-MISMATCH)\b"
)
if wire.search(text):
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    die "${ctx}: expected closed PF-* diagnostic code; log=$(cat "$logfile")"
  fi
  if grep -E -q 'built target=|schemaVersion=proof-forge\.output\.v1' "$logfile" 2>/dev/null; then
    die "${ctx}: failure path must not print product success"
  fi
}

# ---------------------------------------------------------------------------
# 1) Default profile is sole rail solana-sbpf-cpi-elf-v1 (ADR-0032 U1).
# ---------------------------------------------------------------------------
echo "${label}: inspect solana default profile"
default_log="$(mktemp "$work_tmp/default-profile.XXXXXX")"
if ! run_cli_logged "$default_log" -- inspect solana --json; then
  die "inspect solana --json failed: $(cat "$default_log")"
fi
"$python_bin" -I -S - "$default_log" "$default_profile_id" <<'PY' \
  || die "default profile pin failed"
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# CLI may emit a single PF-JCS object line.
payload = None
for line in text.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(line)
        break
    except json.JSONDecodeError:
        continue
if payload is None:
    # whole stdout
    payload = json.loads(text)
if not isinstance(payload, dict):
    raise SystemExit("inspect solana JSON root must be object")
got = payload.get("defaultProfile")
want = sys.argv[2]
if got != want:
    raise SystemExit(f"defaultProfile must be {want!r}, got {got!r}")
if "solana-sbpf-cpi-elf-v1" not in (payload.get("profiles") or []):
    raise SystemExit("profiles must still list solana-sbpf-cpi-elf-v1")
print(f"solana-cpi-product-acceptance: defaultProfile={got}")
PY

# ---------------------------------------------------------------------------
# 2) Legacy plan/elf profiles: same fixture must stable-fail with zero output.
# ---------------------------------------------------------------------------
for legacy_profile in "$legacy_plan_profile" "$legacy_elf_profile"; do
  # Fresh unique tree under work_tmp (no fixed sibling path reuse).
  legacy_out="$(mktemp -d "$work_tmp/legacy-${legacy_profile}.XXXXXX")"
  # CLI requires -o path absent; recreate empty parent slot after mktemp dir.
  rm -rf "$legacy_out"
  legacy_log="$(mktemp "$work_tmp/legacy-${legacy_profile}.XXXXXX")"
  echo "${label}: legacy fail-closed --profile ${legacy_profile}"
  if run_cli_logged "$legacy_log" -- build "$source_rel" \
      --module "$module_name" \
      --target "$target_id" \
      --profile "$legacy_profile" \
      -o "$legacy_out"; then
    die "legacy profile ${legacy_profile} unexpectedly succeeded for EscrowCpi"
  fi
  assert_fail_closed_diagnostic "$legacy_log" "legacy ${legacy_profile}"
  assert_zero_output_tree "$legacy_out" "legacy ${legacy_profile}"
done

# ---------------------------------------------------------------------------
# 3) Product build (exact #125 acceptance command)
# ---------------------------------------------------------------------------
rm -rf "$out_dir"
echo "${label}: product build --source ${source_rel} --module ${module_name} --target ${target_id} --profile ${profile_id} -o ${out_dir}"
product_log="$(mktemp "$work_tmp/product-build.XXXXXX")"
if ! run_cli_logged "$product_log" -- build "$source_rel" \
    --module "$module_name" \
    --target "$target_id" \
    --profile "$profile_id" \
    -o "$out_dir"; then
  # Core not ready: fail closed with the real diagnostic (do not soft-skip).
  die "product build failed (core activation path not ready or rejected). log=$(cat "$product_log")"
fi
if ! grep -q "built target=${target_id}" "$product_log"; then
  die "product build missing success line; log=$(cat "$product_log")"
fi
if ! grep -q "profile=${profile_id}" "$product_log"; then
  die "product build must bind profile=${profile_id}; log=$(cat "$product_log")"
fi
if ! grep -q "deployable=true" "$product_log"; then
  die "product build must report deployable=true; log=$(cat "$product_log")"
fi

# ---------------------------------------------------------------------------
# 4) Product inspect + independent exact closure (not preactivation)
# ---------------------------------------------------------------------------
echo "${label}: inspect exact closure ${out_dir}"
if ! lake env "$cli" inspect --output-dir "$out_dir" --json >/dev/null; then
  die "product inspect --output-dir failed for $out_dir"
fi

# ---------------------------------------------------------------------------
# 5) Strict product file set + pin consistency (Python, no fragile grep pins)
# ---------------------------------------------------------------------------
echo "${label}: validate product tree pins + roles"
"$python_bin" -I -S - \
  "$out_dir" "$program_name" "$profile_id" \
  "$ACTIVE_PROFILE_DIGEST" "$ACTIVE_CATALOG_DIGEST" "$ACTIVE_EXTENSION_DIGEST" \
  "$ACTIVE_IMPLEMENTATION_STATE" \
  "$PLAN_SCHEMA" "$IR_SCHEMA" "$IDL_SCHEMA" "$BINDINGS_SCHEMA" "$OUTPUT_SCHEMA" \
  "$root" "$root/scripts" <<'PY' || die "product tree validation failed"
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path

(
    out_dir_s,
    program_name,
    profile_id,
    active_profile_digest,
    active_catalog_digest,
    active_extension_digest,
    active_implementation_state,
    plan_schema,
    ir_schema,
    idl_schema,
    bindings_schema,
    output_schema,
    repo_root_s,
    scripts_dir_s,
) = sys.argv[1:15]

sys.path.insert(0, scripts_dir_s)
from validate_artifacts import (  # noqa: E402
    artifact_paths_from_manifest,
    exact_physical_closure,
    validate_engineering_output_manifest,
    verify_descriptor_contents,
    verify_evidence_sha256,
)

HEX64 = re.compile(r"[0-9a-f]{64}")
FORBIDDEN_ASM = (
    "TEST-PREACTIVATION",
    "test-preactivation",
    "activationDenied",
    "activation-denied",
    "0xec01",
)
REQUIRED_SYSCALLS = (
    "sol_invoke_signed_c",
    "sol_try_find_program_address",
    "sol_set_return_data",
)
# Preactivation / harness runtime schemas must never be accepted as product.
FORBIDDEN_SCHEMAS = (
    "proof-forge.solana.cpi-escrow-runtime.v1",
    "proof-forge.solana.cpi-ata-runtime.v1",
    "proof-forge.solana.cpi-token-runtime.v1",
    "proof-forge.solana.cpi-system-runtime.v1",
    "proof-forge.solana.cpi-pda-runtime.v1",
    "proof-forge.solana.cpi-unsigned-runtime.v1",
    "proof-forge.solana.cpi-preflight-runtime.v1",
    "proof-forge.solana.cpi-harness.v1",
)


def fail(msg: str) -> None:
    raise SystemExit(f"solana-cpi-product-acceptance: {msg}")


def reject_dup_keys(pairs):
    out = {}
    for k, v in pairs:
        if k in out:
            raise ValueError(f"duplicate JSON key {k!r}")
        out[k] = v
    return out


def require_regular_file(path: Path, *, label: str) -> None:
    try:
        st = os.lstat(path)
    except FileNotFoundError as exc:
        fail(f"{label}: missing {path.name}")
        raise AssertionError("unreachable") from exc
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
        fail(f"{label}: {path.name} must be a regular non-symlink file")
    if st.st_nlink != 1:
        fail(f"{label}: {path.name} must be a single-link file")


def read_json_object(path: Path, *, label: str) -> dict:
    require_regular_file(path, label=label)
    try:
        text = path.read_bytes().decode("utf-8", errors="strict")
        value = json.loads(text, object_pairs_hook=reject_dup_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        fail(f"{label}: invalid JSON in {path.name}: {exc}")
    if not isinstance(value, dict):
        fail(f"{label}: {path.name} root must be an object")
    return value


def read_kv_object(path: Path, *, label: str) -> dict:
    """Parse product composite IR canonical text: top-level key=value lines.

    Handler/body lines (no single top-level assignment form) are ignored for
    pin extraction. Duplicate keys fail closed.
    """
    require_regular_file(path, label=label)
    try:
        text = path.read_bytes().decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        fail(f"{label}: invalid UTF-8 in {path.name}: {exc}")
    if not text.strip():
        fail(f"{label}: empty IR text")
    out: dict[str, str] = {}
    for line_no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("handler:"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            fail(f"{label}: empty key at line {line_no}")
        if key in out:
            fail(f"{label}: duplicate key {key!r} at line {line_no}")
        out[key] = value
    if not out:
        fail(f"{label}: no key=value fields in IR text")
    return out


def bare_hex(digest: object, *, field: str) -> str:
    if not isinstance(digest, str) or not digest:
        fail(f"invalid digest field {field}")
    if digest.startswith("sha256:"):
        digest = digest[len("sha256:") :]
    if not HEX64.fullmatch(digest):
        fail(f"{field} must be 64 lowercase hex (optional sha256: prefix), got {digest!r}")
    return digest


def pick_digest(obj: dict, keys: tuple[str, ...], *, label: str) -> str | None:
    for key in keys:
        if key in obj and obj[key] is not None:
            return bare_hex(obj[key], field=f"{label}.{key}")
    return None


def require_pin_fields(obj: dict, *, label: str) -> dict:
    schema = obj.get("schema")
    if schema is not None and not isinstance(schema, str):
        fail(f"{label}: schema must be string")
    if isinstance(schema, str) and schema in FORBIDDEN_SCHEMAS:
        fail(f"{label}: preactivation/runtime schema {schema!r} is not product")
    profile = None
    for key in ("profileId", "codegenProfile", "profile"):
        if key in obj and isinstance(obj[key], str):
            profile = obj[key]
            break
    if profile is not None and profile != profile_id:
        fail(f"{label}: profile must be {profile_id!r}, got {profile!r}")
    profile_digest = pick_digest(
        obj, ("profileDigest", "codegenProfileDigest"), label=label
    )
    catalog_digest = pick_digest(
        obj, ("calleeCatalogDigest", "catalogDigest"), label=label
    )
    want_profile = bare_hex(active_profile_digest, field="active.profileDigest")
    want_catalog = bare_hex(active_catalog_digest, field="active.catalogDigest")
    if profile_digest is not None and profile_digest != want_profile:
        fail(
            f"{label}: profileDigest pin mismatch "
            f"(got sha256:{profile_digest}, want sha256:{want_profile})"
        )
    if catalog_digest is not None and catalog_digest != want_catalog:
        fail(
            f"{label}: catalogDigest pin mismatch "
            f"(got sha256:{catalog_digest}, want sha256:{want_catalog})"
        )
    ext = obj.get("extensionRequirement")
    if isinstance(ext, dict) and "digest" in ext:
        got = bare_hex(ext["digest"], field=f"{label}.extensionRequirement.digest")
        want = bare_hex(active_extension_digest, field="active.extensionDigest")
        if got != want:
            fail(f"{label}: extension digest pin mismatch")
    return {
        "schema": schema if isinstance(schema, str) else None,
        "profile": profile,
        "profile_digest": profile_digest,
        "catalog_digest": catalog_digest,
        "plan_digest": pick_digest(
            obj,
            ("planDigest", "sourcePlanDigest", "digest"),
            label=label,
        ),
    }


root = Path(out_dir_s)
label = f"product {program_name}"

# --- manifest / evidence product envelope -----------------------------------
manifest = read_json_object(root / "manifest.json", label=label)
if manifest.get("schemaVersion") != output_schema:
    fail(
        f"{label}: schemaVersion must be {output_schema!r}, "
        f"got {manifest.get('schemaVersion')!r}"
    )
blob = json.dumps(manifest, separators=(",", ":"), ensure_ascii=True)
for forbidden in FORBIDDEN_SCHEMAS:
    if forbidden in blob:
        fail(f"{label}: manifest embeds preactivation schema {forbidden}")

try:
    descriptors = validate_engineering_output_manifest(manifest, label=label)
    paths = artifact_paths_from_manifest(manifest)
except SystemExit as exc:
    fail(str(exc))

if manifest["target"] != "solana":
    fail(f"{label}: target must be 'solana'")
if manifest["codegenProfile"] != profile_id:
    fail(
        f"{label}: codegenProfile must be {profile_id!r}, "
        f"got {manifest['codegenProfile']!r}"
    )
if manifest["artifactProgramName"] != program_name:
    fail(
        f"{label}: artifactProgramName must be {program_name!r}, "
        f"got {manifest['artifactProgramName']!r}"
    )
if manifest["deployable"] is not True:
    fail(f"{label}: deployable must be true")

# Product-core base emission order (CpiProductV1); exact set + roles enforced.
# Manifest files order is role-rank then path (validate_engineering_output_manifest).
base_order = [
    f"{program_name}.cpi-plan.json",
    f"{program_name}.cpi-ir.json",
    f"{program_name}.idl.json",
    f"{program_name}.s",
    f"{program_name}.cpi-bindings.json",
]
expected_roles = {path: "materialized-base" for path in base_order}
expected_roles[f"{program_name}.so"] = "finalized-extra"
if set(paths) != set(expected_roles) or len(paths) != len(expected_roles):
    fail(
        f"{label}: files must be exactly {sorted(expected_roles)}, got {sorted(paths)}"
    )
by_path = {d["path"]: d for d in descriptors}
for path, role in expected_roles.items():
    if by_path[path]["role"] != role:
        fail(
            f"{label}: role for {path} must be {role!r}, "
            f"got {by_path[path]['role']!r}"
        )
for path in base_order:
    if path not in by_path or by_path[path]["role"] != "materialized-base":
        fail(f"{label}: missing product-core base path {path!r}")

expected_files = set(paths) | {"manifest.json", "evidence.json"}
try:
    exact_physical_closure(root, expected_files, label=label)
    verify_descriptor_contents(root, descriptors, label=label)
    verify_evidence_sha256(root, manifest["evidenceSha256"], label=label)
except SystemExit as exc:
    fail(str(exc))

manifest_plan_digest = bare_hex(manifest["planDigest"], field="manifest.planDigest")

# --- leaves: plan/idl/bindings JSON; IR product key=value text ----------------
plan = read_json_object(root / f"{program_name}.cpi-plan.json", label=f"{label}.plan")
ir = read_kv_object(root / f"{program_name}.cpi-ir.json", label=f"{label}.ir")
idl = read_json_object(root / f"{program_name}.idl.json", label=f"{label}.idl")
bindings = read_json_object(
    root / f"{program_name}.cpi-bindings.json", label=f"{label}.bindings"
)

plan_meta = require_pin_fields(plan, label=f"{label}.plan")
ir_meta = require_pin_fields(ir, label=f"{label}.ir")
idl_meta = require_pin_fields(idl, label=f"{label}.idl")
bind_meta = require_pin_fields(bindings, label=f"{label}.bindings")

if plan_meta["schema"] != plan_schema:
    fail(f"{label}.plan: schema must be {plan_schema!r}, got {plan_meta['schema']!r}")
if ir_meta["schema"] != ir_schema:
    fail(f"{label}.ir: schema must be {ir_schema!r}, got {ir_meta['schema']!r}")
if idl_meta["schema"] is None:
    fail(f"{label}.idl: missing schema field")
if idl_meta["schema"] != idl_schema:
    fail(f"{label}.idl: schema must be {idl_schema!r}, got {idl_meta['schema']!r}")
if bind_meta["schema"] is None:
    fail(f"{label}.bindings: missing schema field")
if bind_meta["schema"] != bindings_schema:
    fail(
        f"{label}.bindings: schema must be {bindings_schema!r}, "
        f"got {bind_meta['schema']!r}"
    )

# planDigest cross-bind across IR/IDL/bindings (+ plan if present) vs manifest.
observed_plan_digests = []
for meta, name in (
    (plan_meta, "plan"),
    (ir_meta, "ir"),
    (idl_meta, "idl"),
    (bind_meta, "bindings"),
):
    if meta["plan_digest"] is not None:
        observed_plan_digests.append((name, meta["plan_digest"]))

if not observed_plan_digests:
    fail(f"{label}: no planDigest/sourcePlanDigest found in CPI leaves")

if ir_meta["plan_digest"] is None:
    fail(f"{label}.ir: missing sourcePlanDigest/planDigest")
if ir_meta["plan_digest"] != manifest_plan_digest:
    fail(
        f"{label}: ir plan digest {ir_meta['plan_digest']} "
        f"!= manifest.planDigest {manifest_plan_digest}"
    )
if idl_meta["plan_digest"] is None:
    fail(f"{label}.idl: missing planDigest")
if idl_meta["plan_digest"] != manifest_plan_digest:
    fail(
        f"{label}: idl plan digest {idl_meta['plan_digest']} "
        f"!= manifest.planDigest {manifest_plan_digest}"
    )
if bind_meta["plan_digest"] is None:
    fail(f"{label}.bindings: missing planDigest")
if bind_meta["plan_digest"] != manifest_plan_digest:
    fail(
        f"{label}: bindings plan digest {bind_meta['plan_digest']} "
        f"!= manifest.planDigest {manifest_plan_digest}"
    )
if plan_meta["plan_digest"] is not None and plan_meta["plan_digest"] != manifest_plan_digest:
    fail(
        f"{label}: plan digest field {plan_meta['plan_digest']} "
        f"!= manifest.planDigest {manifest_plan_digest}"
    )
for name, digest in observed_plan_digests:
    if digest != manifest_plan_digest:
        fail(
            f"{label}: {name} plan digest {digest} diverges from "
            f"manifest.planDigest {manifest_plan_digest}"
        )

# Profile/catalog pins must appear on plan (identity authority) and IR.
if plan_meta["profile_digest"] is None:
    fail(f"{label}.plan: missing profileDigest")
if plan_meta["catalog_digest"] is None:
    fail(f"{label}.plan: missing calleeCatalogDigest/catalogDigest")
if ir_meta["profile_digest"] is None:
    fail(f"{label}.ir: missing profileDigest")
if ir_meta["catalog_digest"] is None:
    fail(f"{label}.ir: missing catalogDigest")
if plan.get("profileId") != profile_id:
    fail(f"{label}.plan: profileId must be {profile_id!r}")
if plan.get("programName") not in (None, program_name):
    if plan.get("programName") != program_name:
        fail(
            f"{label}.plan: programName must be {program_name!r}, "
            f"got {plan.get('programName')!r}"
        )

# Active implementation-state on plan computeAssumptions + bindings.
impl = None
compute = plan.get("computeAssumptions")
if isinstance(compute, dict) and isinstance(compute.get("implementationState"), str):
    impl = compute["implementationState"]
elif isinstance(plan.get("implementationState"), str):
    impl = plan["implementationState"]
if impl != active_implementation_state:
    fail(
        f"{label}.plan: implementationState must be "
        f"{active_implementation_state!r}, got {impl!r}"
    )
bind_impl = bindings.get("implementationState")
if bind_impl != active_implementation_state:
    fail(
        f"{label}.bindings: implementationState must be "
        f"{active_implementation_state!r}, got {bind_impl!r}"
    )

# --- referencedPackages exact order/set (Escrow product; no companion) ------
# Actual EscrowCpi product reference order from product-core bindings mint.
SYSTEM_COMMIT = "2a165e7a90af75c76426d1e031ed0284211d5d1e"
ATA_SHA = "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
ATA_SIZE = 111136
ATA_PATH = "supply-chain/solana-cpi-assets/v1/ata_classic_v1.so"
ATA_PROGRAM_ID_HEX = "8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859"
TOKEN_SHA = "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
TOKEN_SIZE = 94960
TOKEN_PATH = "supply-chain/solana-cpi-assets/v1/token_classic_v1.so"
TOKEN_PROGRAM_ID_HEX = (
    "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
)
EXPECTED_REFERENCED_PACKAGES = [
    {
        "packageId": "system-v1",
        "admittedForMaterialization": True,
        "artifactBinding": f"runtimeNative:{SYSTEM_COMMIT}",
        "executionClass": "native-system",
        "programIdHex": "00" * 32,
    },
    {
        "packageId": "ata-classic-v1",
        "admittedForMaterialization": True,
        "artifactBinding": (
            f"loaderV3Elf:{ATA_SHA}:size{ATA_SIZE}:{ATA_PATH}"
        ),
        "executionClass": "loader-v3-sbpf",
        "programIdHex": ATA_PROGRAM_ID_HEX,
    },
    {
        "packageId": "token-classic-v1",
        "admittedForMaterialization": True,
        "artifactBinding": (
            f"loaderV3Elf:{TOKEN_SHA}:size{TOKEN_SIZE}:{TOKEN_PATH}"
        ),
        "executionClass": "loader-v3-sbpf",
        "programIdHex": TOKEN_PROGRAM_ID_HEX,
    },
]
pkgs = bindings.get("referencedPackages")
if not isinstance(pkgs, list):
    fail(f"{label}.bindings: referencedPackages must be an array")
if any(
    isinstance(p, dict) and p.get("packageId") == "companion-v1" for p in pkgs
):
    fail(f"{label}.bindings: companion-v1 must not appear in referencedPackages")
if len(pkgs) != len(EXPECTED_REFERENCED_PACKAGES):
    fail(
        f"{label}.bindings: referencedPackages length "
        f"{len(pkgs)} != {len(EXPECTED_REFERENCED_PACKAGES)}"
    )
for idx, (got, want) in enumerate(zip(pkgs, EXPECTED_REFERENCED_PACKAGES)):
    if not isinstance(got, dict):
        fail(f"{label}.bindings: referencedPackages[{idx}] must be object")
    for key, expected in want.items():
        actual = got.get(key)
        if actual != expected:
            fail(
                f"{label}.bindings: referencedPackages[{idx}].{key} "
                f"must be {expected!r}, got {actual!r}"
            )
    # Reject unexpected package ids outside the exact Escrow set.
    if got.get("packageId") not in {
        "system-v1",
        "ata-classic-v1",
        "token-classic-v1",
    }:
        fail(
            f"{label}.bindings: unexpected packageId "
            f"{got.get('packageId')!r} at index {idx}"
        )
got_ids = [p.get("packageId") for p in pkgs if isinstance(p, dict)]
if got_ids != ["system-v1", "ata-classic-v1", "token-classic-v1"]:
    fail(
        f"{label}.bindings: referencedPackages order/set must be "
        f"['system-v1','ata-classic-v1','token-classic-v1'], got {got_ids!r}"
    )

# --- supply-chain ELF assets: regular/single-link/size/sha + manifest rows --
repo_root = Path(repo_root_s)
asset_manifest_path = repo_root / "supply-chain/solana-cpi-assets/v1/manifest.json"
asset_manifest = read_json_object(
    asset_manifest_path, label=f"{label}.asset-manifest"
)
if asset_manifest.get("schema") != "proof-forge.solana.cpi-assets.v1":
    fail(
        f"{label}.asset-manifest: schema must be "
        f"'proof-forge.solana.cpi-assets.v1', got {asset_manifest.get('schema')!r}"
    )
if asset_manifest.get("catalogVersion") != "1.1.0":
    fail(
        f"{label}.asset-manifest: catalogVersion must be '1.1.0', "
        f"got {asset_manifest.get('catalogVersion')!r}"
    )
assets_rows = asset_manifest.get("assets")
if not isinstance(assets_rows, list):
    fail(f"{label}.asset-manifest: assets must be an array")
rows_by_id: dict[str, dict] = {}
for row in assets_rows:
    if not isinstance(row, dict):
        fail(f"{label}.asset-manifest: asset row must be object")
    pid = row.get("packageId")
    if not isinstance(pid, str) or not pid:
        fail(f"{label}.asset-manifest: asset row missing packageId")
    if pid in rows_by_id:
        fail(f"{label}.asset-manifest: duplicate packageId {pid!r}")
    rows_by_id[pid] = row
if "companion-v1" in rows_by_id:
    fail(f"{label}.asset-manifest: companion-v1 must not be an asset row")

EXPECTED_ASSET_ROWS = {
    "ata-classic-v1": {
        "packageId": "ata-classic-v1",
        "relativePath": ATA_PATH,
        "sha256": ATA_SHA,
        "size": ATA_SIZE,
        "sourceRepo": "https://github.com/solana-program/associated-token-account",
        "sourceTag": "program@v8.0.0",
        "tagObject": "de77f367fdc0341879b1b9f0224c6b86107e1769",
        "peeledCommit": "0b867b5340cd001e5980d8ca7928effc4e10015c",
        "buildRecipeDigest": (
            "f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2"
        ),
    },
    "token-classic-v1": {
        "packageId": "token-classic-v1",
        "relativePath": TOKEN_PATH,
        "sha256": TOKEN_SHA,
        "size": TOKEN_SIZE,
        "sourceRepo": "https://github.com/solana-program/token",
        "sourceTag": "program@v9.0.0",
        "tagObject": "5c37ac99c248567bd7d50b965af8cbd45b6ced96",
        "peeledCommit": "dfb260231c761be7d9c8b63728e770a102b86495",
        "buildRecipeDigest": (
            "4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063"
        ),
    },
}
if set(rows_by_id) != set(EXPECTED_ASSET_ROWS):
    fail(
        f"{label}.asset-manifest: packageId set must be "
        f"{sorted(EXPECTED_ASSET_ROWS)}, got {sorted(rows_by_id)}"
    )
for pid, want in EXPECTED_ASSET_ROWS.items():
    row = rows_by_id[pid]
    for key, expected in want.items():
        actual = row.get(key)
        if actual != expected:
            fail(
                f"{label}.asset-manifest: {pid}.{key} must be {expected!r}, "
                f"got {actual!r}"
            )

for rel, want_sha, want_size in (
    (ATA_PATH, ATA_SHA, ATA_SIZE),
    (TOKEN_PATH, TOKEN_SHA, TOKEN_SIZE),
):
    # Path safety: relative under repo, no .. components.
    if rel.startswith("/") or "\\" in rel or ".." in Path(rel).parts:
        fail(f"{label}: unsafe asset relative path {rel!r}")
    asset_path = repo_root / rel
    try:
        st = os.lstat(asset_path)
    except FileNotFoundError as exc:
        fail(f"{label}: missing asset {rel}")
        raise AssertionError("unreachable") from exc
    if stat.S_ISLNK(st.st_mode):
        fail(f"{label}: asset {rel} must not be a symlink")
    if not stat.S_ISREG(st.st_mode):
        fail(f"{label}: asset {rel} must be a regular file")
    # Portable single-link check when the host reports link count.
    if hasattr(st, "st_nlink") and st.st_nlink != 1:
        fail(
            f"{label}: asset {rel} must be a single-link regular file "
            f"(nlink={st.st_nlink})"
        )
    data = asset_path.read_bytes()
    if len(data) != want_size or st.st_size != want_size:
        fail(
            f"{label}: asset {rel} size must be {want_size}, "
            f"got disk={st.st_size} read={len(data)}"
        )
    got_sha = hashlib.sha256(data).hexdigest()
    if got_sha != want_sha:
        fail(
            f"{label}: asset {rel} sha256 must be {want_sha}, got {got_sha}"
        )

# --- assembly surface -------------------------------------------------------
asm_path = root / f"{program_name}.s"
require_regular_file(asm_path, label=label)
asm = asm_path.read_text(encoding="utf-8", errors="strict")
if not asm.strip():
    fail(f"{label}: assembly is empty")
for needle in FORBIDDEN_ASM:
    if needle in asm:
        fail(f"{label}: assembly contains forbidden product marker {needle!r}")
if re.search(r"(?m)^\s*callx\b", asm) or re.search(r"\bcallx\b", asm):
    fail(f"{label}: assembly contains forbidden callx")
if "0xec01" in asm.lower():
    fail(f"{label}: assembly contains forbidden legacy 0xec01 surface")
for syscall in REQUIRED_SYSCALLS:
    if syscall not in asm:
        fail(f"{label}: assembly missing required syscall {syscall}")
# Product header honesty (must not deny product status).
if "isProductArtifact=true" not in asm:
    fail(f"{label}: assembly missing isProductArtifact=true product marker")
if "PRODUCT ARTIFACT" not in asm:
    fail(f"{label}: assembly missing PRODUCT ARTIFACT header")

so_path = root / f"{program_name}.so"
so_size = so_path.stat().st_size
if so_size <= 0:
    fail(f"{label}: empty .so")

print(
    f"solana-cpi-product-acceptance: product ok "
    f"planDigest={manifest_plan_digest} so={so_size}B "
    f"files={sorted(expected_roles)} "
    f"packages={got_ids}"
)
PY

# ---------------------------------------------------------------------------
# 6) Negative mutations under work_tmp/ (schedule + unknown callee)
#    Temporary sources only; must fail closed with zero final product output.
# ---------------------------------------------------------------------------
neg_root="$(mktemp -d "$work_tmp/negatives.XXXXXX")"

make_mutation() {
  local name="$1"
  local mode="$2" # schedule | unknown_callee
  local out_src="$neg_root/${name}.lean"
  "$python_bin" -I -S - "$source_path" "$out_src" "$mode" "$name" <<'PY'
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text(encoding="utf-8")
out = Path(sys.argv[2])
mode = sys.argv[3]
prog = sys.argv[4]
# Rename program so module identity is distinct; keep namespace Examples.
if "program EscrowCpi where" not in src:
    raise SystemExit("fixture missing program EscrowCpi where")
text = src.replace("program EscrowCpi where", f"program {prog} where", 1)
# Drop test-preactivation comments so negatives stay about product semantics.
text = "\n".join(
    line
    for line in text.splitlines()
    if "test-preactivation" not in line and "activationDenied" not in line
) + "\n"
if mode == "schedule":
    # First structured call becomes schedule (async not product-supported).
    if "call solana." not in text:
        raise SystemExit("no call solana.* to mutate")
    text = text.replace("call solana.", "schedule solana.", 1)
elif mode == "unknown_callee":
    if "solana.token.transferChecked(" not in text:
        raise SystemExit("no transferChecked call to mutate")
    text = text.replace(
        "solana.token.transferChecked(",
        "solana.token.notARealInstruction(",
        1,
    )
else:
    raise SystemExit(f"unknown mode {mode}")
out.write_text(text, encoding="utf-8")
print(out)
PY
}

run_negative() {
  local name="$1"
  local mode="$2"
  local src_path
  src_path="$(make_mutation "$name" "$mode")"
  local neg_out="$neg_root/${name}-out"
  local neg_log="$neg_root/${name}.log"
  local src_rel="${src_path#"$root/"}"
  [[ "$src_rel" != "$src_path" ]] \
    || die "negative ${mode}: mutation source escaped repository root"
  rm -rf "$neg_out"
  echo "${label}: negative ${mode} → ${name}"
  # Loader accepts only canonical project-relative paths under the repository root.
  if run_cli_logged "$neg_log" -- build "$src_rel" \
      --module "Examples.${name}" \
      --target "$target_id" \
      --profile "$profile_id" \
      -o "$neg_out"; then
    die "negative ${mode} unexpectedly succeeded"
  fi
  assert_fail_closed_diagnostic "$neg_log" "negative ${mode}"
  assert_zero_output_tree "$neg_out" "negative ${mode}"
}

run_negative "EscrowCpiScheduleNeg" "schedule"
run_negative "EscrowCpiUnknownCalleeNeg" "unknown_callee"

# Resolve canonical out for callers (Mollusk may later consume without
# changing #124 preactivation env).
out_dir="$(cd "$out_dir" && pwd -P)"
export PROOF_FORGE_CPI_PRODUCT_OUT="$out_dir"

echo "${label}: ok product=${out_dir}"
echo "${label}: note=proof-forge.output.v1 only; not preactivation runtime manifest"
