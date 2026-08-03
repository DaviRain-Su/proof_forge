#!/usr/bin/env bash
# EVMOZ-004 Reference leg runner (engineering; not formal C-3).
#
# Runs real Loader→Normalize→admitReferenceProgramSliceV1→stepReferenceSliceV1
# via unregistered Tests/Materialization/EvmCorpusPrimitiveV1.lean
# (`lake env lean --run ...`). Canonicalizes intermediate JSON into
# proof-forge.evm-observation.v1 (evm=null). Hard fails when lean/lake missing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

obs_root="${PF_EVM_CORPUS_OBS_DIR:-$root/build/v2/evm-corpus-obs}"
lean_file="$root/Tests/Materialization/EvmCorpusPrimitiveV1.lean"
validator="$root/scripts/evm_corpus_v1.py"

die() { echo "evm-corpus-reference: $*" >&2; exit 1; }

[[ -f "$lean_file" ]] || die "missing $lean_file"
command -v lake >/dev/null 2>&1 || die "lake required for Reference leg (hard fail)"
command -v lean >/dev/null 2>&1 || die "lean required for Reference leg (hard fail)"

mkdir -p "$obs_root"
echo "evm-corpus-reference: lean --run EvmCorpusPrimitiveV1 → $obs_root" >&2
# Prefer lake env so ProofForgeV2 oleans resolve. When this worktree has no
# built .lake (common in parallel task worktrees), allow PF_LAKE_ROOT override
# pointing at a package root with oleans; never silently skip.
lake_root="${PF_LAKE_ROOT:-$root}"
if [[ ! -d "$lake_root/.lake/build/lib/lean/ProofForgeV2" ]] && \
   [[ ! -d "$lake_root/.lake/build/lib/lean" ]]; then
  die "ProofForgeV2 oleans missing under $lake_root/.lake (set PF_LAKE_ROOT or lake build)"
fi
(
  cd "$lake_root"
  lake env lean --run "$lean_file" -- "$root" "$obs_root"
) || die "Reference lean runner failed"

# Canonicalize every *.raw.json into proof-forge.evm-observation.v1
/usr/bin/python3 -I -S - "$validator" "$obs_root" <<'PY'
import importlib.util, json, sys
from pathlib import Path

validator = Path(sys.argv[1])
obs_root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("evm_corpus_v1", validator)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

raws = sorted(obs_root.rglob("reference-step-*.raw.json"))
if not raws:
    raise SystemExit("evm-corpus-reference: no raw reference steps found")
for raw_path in raws:
    data = json.loads(raw_path.read_text(encoding="utf-8"))
    case_id = data["caseId"]
    step = int(data["stepIndex"])
    obs_bytes = mod.mint_observation_from_shared(
        case_id=case_id,
        leg="reference",
        step_index=step,
        status=data["status"],
        return_value=data["returnValue"],
        logical_state=data["logicalState"],
        effects=data["effects"],
        rollback_equal=bool(data["rollbackEqual"]),
        evm=None,
        verdict="pass",
        skip_reason=None,
    )
    out = raw_path.parent / f"reference-step-{step}.json"
    out.write_bytes(obs_bytes)
    # Keep raw for debugging; schema validator only consumes .json without .raw
    print(f"evm-corpus-reference: minted {out.relative_to(obs_root)}", file=sys.stderr)
print(f"evm-corpus-reference: ok ({len(raws)} steps; not formal C-3)", file=sys.stderr)
PY

echo "evm-corpus-reference: ok" >&2
