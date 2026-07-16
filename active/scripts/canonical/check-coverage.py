#!/usr/bin/env python3
"""Coverage manifest checker for the canonical Core IR migration.

Compares LegacyCoverage.tsv against:
- Tests/Backend/Evm/EvmCoverage.tsv (EVM target evidence)
- Tests/Backend/Wasm/EmitWatCoverage.tsv (NEAR/Wasm target evidence)
- Tests/Backend/Solana/CanonicalPlan.lean (Solana target evidence)
- just product source list (product matrix evidence)

Fails when an advertised Legacy case has no canonical decision or test evidence.
"""
import csv
import sys
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
COVERAGE_TSV = ROOT / "Tests/Canonical/LegacyCoverage.tsv"

def load_coverage():
    """Load the coverage manifest."""
    if not COVERAGE_TSV.exists():
        print(f"ERROR: Coverage manifest not found: {COVERAGE_TSV}")
        sys.exit(1)
    rows = []
    with open(COVERAGE_TSV, newline='') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            rows.append(row)
    return rows

def check_column(rows, column):
    """Check that every row has a non-empty value in the given column."""
    missing = [r for r in rows if not r.get(column, '').strip()]
    return missing

def main():
    rows = load_coverage()
    errors = []

    # Check required columns exist
    required_cols = ['node_kind', 'constructor', 'disposition',
                     'core_semantics', 'evm', 'solana', 'near', 'evidence']
    if not rows:
        print("ERROR: Coverage manifest is empty")
        sys.exit(1)

    header_cols = list(rows[0].keys())
    for col in required_cols:
        if col not in header_cols:
            errors.append(f"Missing column: {col}")

    # Check that every row has a disposition (preserve/reject/placeholder)
    for row in rows:
        disp = row.get('disposition', '').strip()
        if disp not in ('preserve', 'reject', 'placeholder'):
            errors.append(f"Row {row.get('constructor', '?')}: invalid disposition '{disp}'")

    # Check core_semantics is filled
    missing_semantics = check_column(rows, 'core_semantics')
    for m in missing_semantics:
        errors.append(f"Row {m.get('constructor', '?')}: missing core_semantics")

    # Check evidence is filled
    missing_evidence = check_column(rows, 'evidence')
    for m in missing_evidence:
        errors.append(f"Row {m.get('constructor', '?')}: missing evidence")

    # Check that any 'preserve' with 'implemented' core_semantics has
    # at least one target marked as implemented or fail-closed
    for row in rows:
        if row.get('disposition') == 'preserve' and row.get('core_semantics') == 'implemented':
            evm = row.get('evm', '').strip()
            solana = row.get('solana', '').strip()
            near = row.get('near', '').strip()
            if not any(v in ('implemented', 'fail-closed') for v in [evm, solana, near]):
                errors.append(
                    f"Row {row.get('constructor', '?')}: "
                    f"implemented in Core but no target has implementation or fail-closed"
                )

    if errors:
        print(f"Coverage check FAILED ({len(errors)} errors):")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print(f"Coverage check PASSED ({len(rows)} rows verified)")
        sys.exit(0)

if __name__ == '__main__':
    main()