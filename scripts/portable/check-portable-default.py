#!/usr/bin/env python3
"""Phase A portable-default gate (product-authoring-architecture).

Examples/Product is the product path: business logic / TokenSpec only.
Authors must not import chain Surface modules, pick TokenStandard, or
embed Account/PDA/CPI authoring in shared sources.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SHARED = REPO_ROOT / "Examples" / "Product"

# Imports that pull chain-native authoring into the default product path.
FORBIDDEN_IMPORT_RE = re.compile(
    r"^\s*import\s+("
    r"ProofForge\.Solana"
    r"|ProofForge\.Contract\.Source\.Solana"
    r"|ProofForge\.Contract\.Source\.Near"
    r"|ProofForge\.Backend\.(Solana|Evm|WasmNear|Move)"
    r"|ProofForge\.Evm\b"
    r"|Lean\.Evm\b"
    r")",
    re.MULTILINE,
)

# NEAR Promise host-extension must not appear in Shared product sources.
FORBIDDEN_NEAR_EXTENSION = [
    "nearPromiseThen",
    "nearPromiseResultU64",
    "nearPromiseResultsCount",
    "nearCrosscallPool",
    "nearCrosscallInvokePool",
]

# EVM family-only chain constructors (T4.3) — use portable remoteCall instead.
FORBIDDEN_EVM_FAMILY = [
    "create2Deploy",
    "crosscallCreate2",
    "crosscallCreate(",
    "entrySelector",
    "methodWithSelector",
    "entrySelectorReturns",
    "entrySelectorWithParams",
]

# Host string-pool / index APIs are materializer concerns. Shared must use
# declareRemote / declareRemoteUnit / peerHandle / remoteCall only.
FORBIDDEN_NEAR_METADATA = [
    "registerNearCrosscallString",
    "nearAddressLit",
    "nearCrosscallString",
    "ensureCrosscallString",
]

# Author must not select a chain token standard in Shared sources.
FORBIDDEN_STANDARD_RE = re.compile(
    r"TokenStandard\.(erc20|splToken|splToken2022)"
    r"|standard\s*:=\s*\.(erc20|splToken|splToken2022)",
)

# Solana account model must not appear as authoring in Shared (extensions live
# under Examples/Backend/Solana and ProofForge.Solana / Source.Solana).
FORBIDDEN_SOLANA_AUTHORING = [
    "pdaAccount",
    "pda_account",
    "cpiInvoke",
    "cpi_invoke",
    "accountConstraint",
    "account_constraint",
    "splTokenTransfer",
    "spl_token_transfer",
    "systemTransfer",
    "system_transfer",
    "allocator bump",
    "derive pda",
    "literal_seed",
    "account_seed",
    "signer_seeds",
]

# contract_source DSL lines that are Solana-extension-only
FORBIDDEN_SOLANA_DSL_RE = re.compile(
    r"(?m)^\s*(account |pda |cpi |derive pda |invoke |realloc |init_transfer_hook)"
)


def fail(message: str) -> None:
    print(f"portable-default: {message}", file=sys.stderr)
    raise SystemExit(1)


def check_shared_file(path: Path) -> None:
    rel = path.relative_to(REPO_ROOT).as_posix()
    text = path.read_text(encoding="utf-8")

    for match in FORBIDDEN_IMPORT_RE.finditer(text):
        fail(f"{rel}: portable Shared must not import chain Surface/backend `{match.group(1)}`")

    if FORBIDDEN_STANDARD_RE.search(text):
        fail(
            f"{rel}: portable Shared must not select TokenStandard; "
            "write TokenFeature only and let planForTarget resolve the standard"
        )

    # Allow TokenSpec module import; ban Solana Surface-style helpers.
    for needle in FORBIDDEN_SOLANA_AUTHORING:
        if needle in text:
            fail(
                f"{rel}: portable Shared must not contain Solana authoring `{needle}`; "
                "use business logic / TokenSpec and let --target materialize accounts/CPI "
                "(or import ProofForge.Contract.Source.Solana only in Examples/Backend/Solana)"
            )

    for needle in FORBIDDEN_NEAR_EXTENSION:
        if needle in text:
            fail(
                f"{rel}: portable Shared must not use NEAR Promise host-extension `{needle}`; "
                "use remoteCall (portable crosscall.invoke) and let --target materialize "
                "(or import ProofForge.Contract.Source.Near only in NEAR fixtures)"
            )

    for needle in FORBIDDEN_EVM_FAMILY:
        if needle in text:
            fail(
                f"{rel}: portable Shared must not use EVM family-only / selector pin `{needle}`; "
                "use name-only entry/query (no entrySelector) and remoteCallRef for remotes; "
                "CREATE2 and selector fixtures stay under Examples/Backend/Evm (T4.1/T4.3)"
            )

    for needle in FORBIDDEN_NEAR_METADATA:
        if needle in text:
            fail(
                f"{rel}: portable Shared must not use host string-pool API `{needle}`; "
                "use declareRemoteUnit / peerHandle / remoteCall so Wasm-NEAR/Soroban "
                "materialize the pool from deployment peer ids"
            )

    if FORBIDDEN_SOLANA_DSL_RE.search(text):
        fail(
            f"{rel}: portable Shared must not use Solana account/PDA/CPI DSL; "
            "import ProofForge.Contract.Source only (extension: Source.Solana)"
        )

    token_spec_decl = re.search(
        r"(?m)^\s*def\s+[A-Za-z_][A-Za-z0-9_']*\s*:\s*"
        r"(?:ProofForge\.Contract\.Token\.)?TokenSpec\b",
        text,
    )
    if token_spec_decl:
        if "import ProofForge.Contract.Token" not in text and "import ProofForge.Contract.Token." not in text:
            # Soulbound may re-export via alias; require Token import or open path
            if "ProofForge.Contract.Token" not in text:
                fail(f"{rel}: TokenSpec example must import ProofForge.Contract.Token")
        # Product rule: no standard field on authoring
        if re.search(r"standard\s*:=", text) and "TokenPlan" not in text:
            fail(f"{rel}: TokenSpec authoring must not set `standard`")

    if "contract_source " in text:
        if "import ProofForge.Contract.Source" not in text:
            fail(f"{rel}: contract_source example must import ProofForge.Contract.Source")


def check_token_api_docs() -> None:
    """Sanity: TokenSpec structure comment still advertises no standard field."""
    token_lean = (REPO_ROOT / "ProofForge" / "Contract" / "Token.lean").read_text(encoding="utf-8")
    if "structure TokenSpec where" not in token_lean:
        fail("TokenSpec structure missing")
    # Between structure TokenSpec and next structure/inductive, no standard field
    m = re.search(
        r"structure TokenSpec where(.*?)(?:structure |inductive |def TokenSpec\.|end ProofForge)",
        token_lean,
        re.DOTALL,
    )
    if not m:
        fail("could not parse TokenSpec structure body")
    body = m.group(1)
    if re.search(r"\bstandard\s*:", body):
        fail("TokenSpec must not expose an author-facing `standard` field")


def main() -> int:
    if not SHARED.is_dir():
        fail("Examples/Product missing")

    sources = sorted(SHARED.glob("*.lean"))
    if not sources:
        fail("Examples/Product has no Lean sources")

    for path in sources:
        check_shared_file(path)

    check_token_api_docs()
    print(f"portable-default: ok ({len(sources)} shared sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
