#!/usr/bin/env bash
# ProofShip rwa-share-v1 — proof gate verdicts (certified positives + fast negative).
#
#   1. check proof-twin/EvenStep.lean    → expect ok + proofStatus=certified
#   2. check proof-twin/ShareConservation.lean → expect ok + certified
#   3. check proof-twin/EvenStepBad.lean → expect gate REJECTION + zero artifacts
#
# Honesty: the twin files exercise the gate mechanism on certified families
# (generic preservation APIs). The RWA deploy file carries no invariant
# (EVM fails closed on nonempty invariants); we never claim the share rules
# are formally proven.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"
proj="proofship/rwa-share-v1"
cli="$root/.lake/build/bin/proof-forge-next"
[[ -x "$cli" ]] || { echo "proof-gate: CLI missing (run just build)" >&2; exit 70; }

die() { echo "proof-gate: FAIL: $*" >&2; exit 1; }

echo "== 1. positive: EvenStep (parity family) must certify ==" >&2
out="$("$cli" check proof-twin/EvenStep.lean --module EvenStep --root "$proj")" \
  || die "EvenStep check failed"
echo "$out"
echo "$out" | grep -q "proofStatus=certified" || die "expected proofStatus=certified"
echo "$out" | grep -q "proofTheoremCount=1" || die "expected proofTheoremCount=1"

echo "== 1b. positive: ShareConservation (initializer/view equality family, RWA-flavored) must certify ==" >&2
outb="$("$cli" check proof-twin/ShareConservation.lean --module ShareConservation --root "$proj")" \
  || die "ShareConservation check failed"
echo "$outb"
echo "$outb" | grep -q "proofStatus=certified" || die "expected proofStatus=certified (ShareConservation)"

echo "== 2. negative: EvenStepBad must be rejected with zero artifacts ==" >&2
if "$cli" check proof-twin/EvenStepBad.lean --module EvenStepBad --root "$proj" >/tmp/proofship-bad-check.log 2>&1; then
  die "EvenStepBad unexpectedly passed the proof gate"
fi
echo "-- gate rejected as expected; diagnostic head:" >&2
head -5 /tmp/proofship-bad-check.log >&2

# Zero-artifact proof: build must also fail and leave no output directory.
if "$cli" build proof-twin/EvenStepBad.lean --module EvenStepBad --root "$proj" \
    --target evm -o out-evm-evenstepbad >/dev/null 2>&1; then
  die "EvenStepBad unexpectedly built"
fi
[[ ! -e "$proj/out-evm-evenstepbad" ]] || die "rejected build left artifacts behind"
echo "proof-gate: ok (certified positive + rejected negative + zero artifacts)" >&2
exit 0
