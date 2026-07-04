#!/usr/bin/env python3
"""
ProofForge documentation translator.

Translates English Markdown docs to Chinese using Ollama Cloud (OpenAI-compatible
chat endpoint). Incremental: only re-translates files whose source sha256 changed
since the last run.

Usage:
    python3 scripts/translate-docs.py                # translate stale docs
    python3 scripts/translate-docs.py --force        # retranslate all
    python3 scripts/translate-docs.py --check        # report stale, translate nothing
    python3 scripts/translate-docs.py --list         # list mapping and status
    python3 scripts/translate-docs.py --model glm-4.7

Design:
- Manifest scripts/i18n/manifest.json maps EN source path -> ZH path + last sha256.
- Glossary scripts/i18n/glossary.json constrains technical term renderings.
- Fenced code blocks (```), inline code (`code`), and URLs are preserved verbatim;
  only prose is translated. Markdown structure (headings, tables, lists) is kept.
- Each file is sent as one LLM call with a system prompt carrying the glossary.
- On success the manifest is updated with the new sha256; on failure the stale
  entry is left so the next run retries.

Env:
    OLLAMA_API_KEY  required (Ollama Cloud bearer token)
    OLLAMA_BASE_URL optional (default https://api.ollama.com)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
I18N_DIR = REPO_ROOT / "scripts" / "i18n"
MANIFEST_PATH = I18N_DIR / "manifest.json"
GLOSSARY_PATH = I18N_DIR / "glossary.json"

DEFAULT_MODEL = "gemini-3-flash-preview"
DEFAULT_BASE_URL = "https://api.ollama.com"
HTTP_TIMEOUT = 300  # per request
# Split prose segments larger than this into paragraph chunks to avoid timeouts.
CHUNK_MAX_CHARS = 4000


# ---------------------------------------------------------------------------
# Document mapping
# ---------------------------------------------------------------------------
# Each entry: en (relative to repo root) -> zh (relative to repo root).
# Edit this when a new English doc is added.
DOC_MAP: dict[str, str] = {
    "README.md": "docs/zh/README-root.zh.md",
    "CONTRIBUTING.md": "docs/zh/CONTRIBUTING.zh.md",
    "docs/INDEX.md": "docs/zh/INDEX.zh.md",
    "docs/onboarding.md": "docs/zh/onboarding.zh.md",
    "docs/gate-status.md": "docs/zh/gate-status.zh.md",
    "docs/decisions.md": "docs/zh/decisions.zh.md",
    "docs/capability-registry.md": "docs/zh/capability-registry.zh.md",
    "docs/portable-ir.md": "docs/zh/portable-ir.zh.md",
    "docs/shared-scenario.md": "docs/zh/shared-scenario.zh.md",
    "docs/tutorials/portable-contract-three-targets.md": "docs/zh/tutorials/portable-contract-three-targets.zh.md",
    "docs/implementation-backlog.md": "docs/zh/implementation-backlog.zh.md",
    "docs/review-checklist.md": "docs/zh/review-checklist.zh.md",
    "docs/development-standards.md": "docs/zh/development-standards.zh.md",
    "docs/validation-gates.md": "docs/zh/validation-gates.zh.md",
    "docs/rfcs/README.md": "docs/zh/rfcs-README.zh.md",
    "docs/rfcs/0001-multichain-platform.md": "docs/zh/rfcs/0001-multichain-platform.zh.md",
    "docs/rfcs/0002-target-implementation-design.md": "docs/zh/rfcs/0002-target-implementation-design.zh.md",
    "docs/rfcs/0003-portable-ir-and-runtime.md": "docs/zh/rfcs/0003-portable-ir-and-runtime.zh.md",
    "docs/rfcs/0004-evm-semantic-plan.md": "docs/zh/rfcs/0004-evm-semantic-plan.zh.md",
    "docs/targets/README.md": "docs/zh/targets-README.zh.md",
    "docs/targets/evm.md": "docs/zh/targets/evm.zh.md",
    "docs/targets/wasm-family.md": "docs/zh/targets/wasm-family.zh.md",
    "docs/targets/wasm-near.md": "docs/zh/targets/wasm-near.zh.md",
    "docs/targets/solana-sbf.md": "docs/zh/targets/solana-sbf.zh.md",
    "docs/targets/move-family.md": "docs/zh/targets/move-family.zh.md",
    "Examples/Evm/README.md": "docs/zh/examples-evm-README.zh.md",
}

# Docs that are originally Chinese (not translated, kept as-is). Listed here so
# the sync status report knows they exist and are not stale translations.
NATIVE_ZH_DOCS = [
    "docs/zh/feasibility-analysis.md",
    "docs/zh/technical-implementation-plan.md",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def split_preserve_codeblocks(text: str) -> list[tuple[str, str]]:
    """Split markdown into segments tagged 'prose' or 'code'.

    Fenced code blocks (```...```) are kept verbatim. Everything else is prose
    eligible for translation. We also keep inline code spans verbatim by
    masking them with placeholders before sending prose to the model, then
    restoring them after.
    """
    segments: list[tuple[str, str]] = []
    # Match fenced code blocks, including the info string and language.
    pattern = re.compile(r"```.*?```", re.DOTALL)
    last = 0
    for m in pattern.finditer(text):
        if m.start() > last:
            segments.append(("prose", text[last:m.start()]))
        segments.append(("code", text[m.start():m.end()]))
        last = m.end()
    if last < len(text):
        segments.append(("prose", text[last:]))
    return segments


def mask_inline_code(prose: str) -> tuple[str, dict[str, str]]:
    """Replace `inline code` with stable placeholders, return masked text + map."""
    placeholders: dict[str, str] = {}
    counter = 0

    def repl(m: re.Match) -> str:
        nonlocal counter
        key = f"XXINLINE{counter}XX"
        placeholders[key] = m.group(0)
        counter += 1
        return key

    masked = re.sub(r"`[^`\n]+`", repl, prose)
    return masked, placeholders


def restore_inline_code(text: str, placeholders: dict[str, str]) -> str:
    for key, original in placeholders.items():
        text = text.replace(key, original)
    return text


# ---------------------------------------------------------------------------
# LLM call
# ---------------------------------------------------------------------------
def build_system_prompt(glossary_terms: dict[str, str]) -> str:
    # Pick the most error-prone terms (blockchain/compiler jargon that models
    # often mistranslate). The full glossary stays in glossary.json for human
    # reference; only these critical ones go into every LLM call to keep the
    # prompt short and fast.
    critical_keys = [
        "capability", "capabilities", "capability id", "capability registry",
        "capability lowering", "capability lowering table", "capability call",
        "target", "target id", "target profile", "target family",
        "target adapter", "target registry", "portable IR", "portable core",
        "runtime profile", "host bridge", "degenerate runtime",
        "source generation", "sourcegen", "lowering", "lower", "emit",
        "entrypoint", "smoke test", "golden snapshot", "workstream",
        "acceptance criteria", "artifact", "artifact metadata",
        "extern", "opaque", "sidecar", "spike",
    ]
    critical = {k: glossary_terms[k] for k in critical_keys if k in glossary_terms}
    terms_block = ", ".join(f"{en}={zh}" for en, zh in critical.items())
    return (
        "You are a technical translator for ProofForge (Lean-first multi-chain "
        "smart contract platform). Translate English Markdown prose to Simplified "
        "Chinese. Rules: keep Markdown structure (headings, tables, lists, links) "
        "intact; keep code, identifiers, CLI flags, file paths, target ids, "
        "capability ids, RFC numbers verbatim; keep technical terms without "
        "standard Chinese (spike, sidecar, Experimental, Research, ability, "
        "acquires, UID) in English; translate ONLY the given content, never add "
        "or hallucinate text, links, or list items; preserve boundary whitespace; "
        "output ONLY the translation, no preamble.\n"
        f"Key terms: {terms_block}"
    )


def build_glossary_prefix(glossary_terms: dict[str, str]) -> str:
    """Stub: glossary is now in the system prompt to avoid per-chunk overhead."""
    return ""


def call_llm(
    base_url: str,
    api_key: str,
    model: str,
    system_prompt: str,
    user_text: str,
    max_retries: int = 3,
) -> str:
    url = f"{base_url.rstrip('/')}/api/chat"
    # Use streaming so the connection stays alive while the model generates.
    # Non-streaming requests to Ollama Cloud time out around 60s for slow models
    # because the full response is buffered server-side before any byte is sent.
    payload = {
        "model": model,
        "stream": True,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text},
        ],
        "options": {"temperature": 0.2},
    }
    body = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
        "User-Agent": "proof-forge-translator/0.1",
        "Accept": "application/x-ndjson",
    }
    last_err = None
    for attempt in range(max_retries + 1):
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            pieces: list[str] = []
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
                for raw_line in resp:
                    line = raw_line.decode("utf-8").strip()
                    if not line:
                        continue
                    chunk = json.loads(line)
                    if chunk.get("done"):
                        break
                    delta = chunk.get("message", {}).get("content", "")
                    if delta:
                        pieces.append(delta)
            content = "".join(pieces).strip()
            if not content:
                raise RuntimeError("empty streamed response")
            return content
        except (urllib.error.URLError, RuntimeError, json.JSONDecodeError, ConnectionError) as e:
            last_err = e
            if attempt < max_retries:
                wait = 10 * (attempt + 1)
                sys.stderr.write(f"  [retry {attempt+1}/{max_retries}] {e}; waiting {wait}s\n")
                time.sleep(wait)
    raise RuntimeError(f"LLM call failed after {max_retries+1} attempts: {last_err}")


# ---------------------------------------------------------------------------
# Translation of one file
# ---------------------------------------------------------------------------
def split_prose_into_chunks(prose: str, max_chars: int = CHUNK_MAX_CHARS) -> list[str]:
    """Split a prose segment into chunks no larger than max_chars.

    Splits on blank lines (paragraph boundaries) first, then on single newlines
    if a single paragraph still exceeds max_chars. Preserves the separators so
    concatenating the chunks reproduces the original text.
    """
    if len(prose) <= max_chars:
        return [prose]
    chunks: list[str] = []
    # Split on blank lines, keeping the separators.
    parts = re.split(r"(\n\n+)", prose)
    cur = ""
    for part in parts:
        if len(cur) + len(part) <= max_chars:
            cur += part
        else:
            if cur:
                chunks.append(cur)
                cur = ""
            if len(part) <= max_chars:
                cur = part
            else:
                # Single paragraph too long: split on single newlines.
                lines = re.split(r"(\n)", part)
                buf = ""
                for ln in lines:
                    if len(buf) + len(ln) <= max_chars:
                        buf += ln
                    else:
                        if buf:
                            chunks.append(buf)
                        buf = ln
                cur = buf
    if cur:
        chunks.append(cur)
    return chunks


def translate_file(
    en_path: Path,
    zh_path: Path,
    base_url: str,
    api_key: str,
    model: str,
    system_prompt: str,
    glossary_prefix: str,
    max_workers: int = 2,
) -> str:
    """Translate one English markdown file to Chinese. Returns new sha256.

    All translatable prose chunks across the file are translated in parallel
    via a thread pool, then reassembled in order. Code blocks and whitespace
    are preserved verbatim.
    """
    raw = en_path.read_text(encoding="utf-8")
    segments = split_preserve_codeblocks(raw)

    # First pass: collect translation tasks with their positional index.
    # Each task is (slot_index, chunk_index, text, lead_ws, trail_ws, placeholders).
    tasks: list[tuple[int, int, str, str, str, dict[str, str]]] = []
    # slot_results maps slot_index -> list of translated chunks (in chunk order).
    slot_chunk_counts: dict[int, int] = {}
    slot_meta: dict[int, tuple[str, str, dict[str, str]]] = {}

    for slot, (kind, seg) in enumerate(segments):
        if kind == "code" or not seg.strip():
            continue
        masked, placeholders = mask_inline_code(seg)
        if not masked.strip():
            continue
        lead_ws = re.match(r"^(\s*)", masked).group(1)
        trail_ws_match = re.search(r"(\s*)$", masked)
        trail_ws = trail_ws_match.group(1) if trail_ws_match else ""
        core = masked[len(lead_ws):len(masked) - len(trail_ws) if trail_ws else len(masked)]
        if not core.strip():
            continue
        chunks = split_prose_into_chunks(core)
        slot_chunk_counts[slot] = len(chunks)
        slot_meta[slot] = (lead_ws, trail_ws, placeholders)
        for ci, ch in enumerate(chunks):
            if ch.strip():
                tasks.append((slot, ci, ch, lead_ws, trail_ws, placeholders))

    # Parallel translation.
    results: dict[tuple[int, int], str] = {}
    if tasks:
        def do_task(task):
            slot, ci, ch, _, _, _ = task
            tr = call_llm(base_url, api_key, model, system_prompt, glossary_prefix + ch)
            return (slot, ci), tr

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(do_task, task): task for task in tasks}
            for fut in as_completed(futures):
                key, tr = fut.result()
                results[key] = tr

    # Second pass: reassemble.
    out_parts: list[str] = []
    for slot, (kind, seg) in enumerate(segments):
        if kind == "code":
            out_parts.append(seg)
            continue
        if slot not in slot_chunk_counts:
            out_parts.append(seg)
            continue
        lead_ws, trail_ws, placeholders = slot_meta[slot]
        n = slot_chunk_counts[slot]
        chunk_out: list[str] = []
        for ci in range(n):
            key = (slot, ci)
            if key in results:
                chunk_out.append(results[key])
            else:
                # empty chunk was not sent for translation; reinsert original
                chunk_out.append("")
        restored = restore_inline_code(lead_ws + "".join(chunk_out) + trail_ws, placeholders)
        out_parts.append(restored)
    zh_text = "".join(out_parts)
    if not zh_text.endswith("\n"):
        zh_text += "\n"
    zh_path.parent.mkdir(parents=True, exist_ok=True)
    zh_path.write_text(zh_text, encoding="utf-8")
    return sha256_file(en_path)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def cmd_list(args) -> int:
    manifest = load_json(MANIFEST_PATH)
    print(f"{'STATUS':<10} {'EN':<48} {'ZH'}")
    print("-" * 100)
    for en_rel, zh_rel in DOC_MAP.items():
        en_path = REPO_ROOT / en_rel
        if not en_path.exists():
            print(f"{'MISSING':<10} {en_rel:<48} {zh_rel}")
            continue
        cur = sha256_file(en_path)
        rec = manifest.get(en_rel, {})
        prev = rec.get("sha256")
        if prev == cur:
            status = "fresh"
        elif prev:
            status = "stale"
        else:
            status = "new"
        print(f"{status:<10} {en_rel:<48} {zh_rel}")
    if NATIVE_ZH_DOCS:
        print("-" * 100)
        print("Native Chinese (not translated, kept as-is):")
        for p in NATIVE_ZH_DOCS:
            print(f"  {p}")
    return 0


def cmd_check(args) -> int:
    manifest = load_json(MANIFEST_PATH)
    stale: list[str] = []
    for en_rel in DOC_MAP:
        en_path = REPO_ROOT / en_rel
        if not en_path.exists():
            stale.append(f"MISSING {en_rel}")
            continue
        cur = sha256_file(en_path)
        rec = manifest.get(en_rel, {})
        if rec.get("sha256") != cur:
            stale.append(en_rel)
    if not stale:
        print("All translations up to date.")
        return 0
    print(f"{len(stale)} doc(s) need translation:")
    for p in stale:
        print(f"  {p}")
    return 1


def cmd_translate(args) -> int:
    api_key = os.environ.get("OLLAMA_API_KEY")
    if not api_key:
        sys.stderr.write("ERROR: OLLAMA_API_KEY is not set.\n")
        return 2
    base_url = os.environ.get("OLLAMA_BASE_URL", DEFAULT_BASE_URL)
    glossary = load_json(GLOSSARY_PATH)
    glossary_terms = glossary.get("terms", {})
    system_prompt = build_system_prompt(glossary_terms)
    glossary_prefix = build_glossary_prefix(glossary_terms)
    manifest = load_json(MANIFEST_PATH)

    todo: list[str] = []
    for en_rel in DOC_MAP:
        en_path = REPO_ROOT / en_rel
        if not en_path.exists():
            sys.stderr.write(f"SKIP (missing source): {en_rel}\n")
            continue
        cur = sha256_file(en_path)
        rec = manifest.get(en_rel, {})
        if args.force or rec.get("sha256") != cur:
            todo.append(en_rel)

    if not todo:
        print("Nothing to translate; all docs are fresh.")
        return 0

    print(f"Translating {len(todo)} doc(s) with model {args.model}...")
    succeeded = 0
    failed: list[str] = []
    for en_rel in todo:
        zh_rel = DOC_MAP[en_rel]
        en_path = REPO_ROOT / en_rel
        zh_path = REPO_ROOT / zh_rel
        print(f"  -> {en_rel}")
        t0 = time.time()
        try:
            new_sha = translate_file(
                en_path, zh_path, base_url, api_key, args.model, system_prompt, glossary_prefix
            )
            manifest[en_rel] = {"sha256": new_sha, "zh": zh_rel, "model": args.model}
            save_json(MANIFEST_PATH, manifest)
            dt = time.time() - t0
            print(f"     ok ({dt:.1f}s) -> {zh_rel}")
            succeeded += 1
        except Exception as e:
            dt = time.time() - t0
            sys.stderr.write(f"     FAIL ({dt:.1f}s): {e}\n")
            failed.append(en_rel)

    print(f"\nDone: {succeeded} ok, {len(failed)} failed.")
    if failed:
        print("Failed:")
        for p in failed:
            print(f"  {p}")
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="ProofForge doc translator (EN -> ZH)")
    parser.add_argument("--force", action="store_true", help="retranslate all docs")
    parser.add_argument("--check", action="store_true", help="report stale docs, translate nothing")
    parser.add_argument("--list", action="store_true", help="list mapping and status")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Ollama model (default {DEFAULT_MODEL})")
    args = parser.parse_args()
    if args.list:
        return cmd_list(args)
    if args.check:
        return cmd_check(args)
    return cmd_translate(args)


if __name__ == "__main__":
    sys.exit(main())
