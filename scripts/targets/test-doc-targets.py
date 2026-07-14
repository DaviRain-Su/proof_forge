#!/usr/bin/env python3
from pathlib import Path


def main() -> None:
    text = Path("docs/targets/arbitrum-stylus.md").read_text()
    assert "`wasm-arbitrum-stylus`" in text
    assert "Direct Wasm" in text
    assert "Rust SDK" in text
    assert "docs-only" in text
    assert '`stylus-sdk = "=0.10.8"`' in text
    assert '`cargo-stylus = "=0.10.8"`' in text
    assert "Rust `1.91.0`" in text
    assert "`wasm32-unknown-unknown`" in text
    print("stylus-doc-target: ok")


if __name__ == "__main__":
    main()
