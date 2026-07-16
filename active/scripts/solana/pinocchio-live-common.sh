#!/usr/bin/env bash
# Shared helpers for ProofForge vs Pinocchio live-equivalence scripts.
#
# The caller is expected to set:
#   CARGO_BUILD_SBF_BIN, SOLANA_RUSTUP_TOOLCHAIN, REFERENCE_DIR,
#   PINOCCHIO_BUILD_DIR, SBPF_ARCH, OUT_DIR, and SURFPOOL_PID.

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

rustupCargoAvailable() {
  [ -x "$HOME/.cargo/bin/cargo" ] &&
    PATH="$HOME/.cargo/bin:$PATH" cargo +"$SOLANA_RUSTUP_TOOLCHAIN" --version >/dev/null 2>&1
}

platformToolsRustBin() {
  local cargo_build_sbf_path
  cargo_build_sbf_path="$(command -v "$CARGO_BUILD_SBF_BIN" 2>/dev/null || true)"
  [ -n "$cargo_build_sbf_path" ] || return 1
  printf '%s/platform-tools-sdk/sbf/dependencies/platform-tools/rust/bin\n' "$(dirname "$cargo_build_sbf_path")"
}

platformToolsCargoAvailable() {
  local rust_bin
  rust_bin="$(platformToolsRustBin)" || return 1
  [ -x "$rust_bin/rustc" ] && [ -x "$rust_bin/cargo" ]
}

printSbfToolchainHint() {
  local script_path="${PINOCCHIO_LIVE_SCRIPT:-$0}"
  cat >&2 <<EOF
Pinocchio reference SBF build needs Solana rustc/platform-tools.
Suggested repair:
  PATH="\$HOME/.cargo/bin:\$PATH" cargo-build-sbf --install-only --force-tools-install --tools-version v1.52
Then rerun:
  PROOF_FORGE_PINOCCHIO_USE_RUSTUP=1 $script_path
EOF
}

selectPinocchioSbfBuildMode() {
  use_no_rustup_override=0
  case "${PROOF_FORGE_PINOCCHIO_USE_RUSTUP:-auto}" in
    1|true|yes|auto)
      if rustupCargoAvailable; then
        export PATH="$HOME/.cargo/bin:$PATH"
        echo "  using rustup Solana toolchain: $SOLANA_RUSTUP_TOOLCHAIN"
      elif platformToolsCargoAvailable; then
        use_no_rustup_override=1
        export PATH="$(platformToolsRustBin):$PATH"
        echo "  using Agave platform-tools rustc with --no-rustup-override"
      elif [ "${PROOF_FORGE_PINOCCHIO_USE_RUSTUP:-auto}" = "auto" ]; then
        use_no_rustup_override=1
        echo "  rustup Solana toolchain unavailable; trying PATH rustc with --no-rustup-override"
      else
        printSbfToolchainHint
        skip "rustup Solana toolchain unavailable: $SOLANA_RUSTUP_TOOLCHAIN"
      fi
      ;;
    0|false|no)
      use_no_rustup_override=1
      ;;
    *)
      fail "invalid PROOF_FORGE_PINOCCHIO_USE_RUSTUP value: ${PROOF_FORGE_PINOCCHIO_USE_RUSTUP:-}"
      ;;
  esac
}

buildPinocchioReference() {
  if [ "${use_no_rustup_override:-0}" = "1" ]; then
    "$CARGO_BUILD_SBF_BIN" --no-rustup-override \
      --manifest-path "$REFERENCE_DIR/Cargo.toml" \
      --no-default-features \
      --features bpf-entrypoint \
      --sbf-out-dir "$PINOCCHIO_BUILD_DIR" \
      --arch "$SBPF_ARCH"
  else
    "$CARGO_BUILD_SBF_BIN" \
      --manifest-path "$REFERENCE_DIR/Cargo.toml" \
      --no-default-features \
      --features bpf-entrypoint \
      --sbf-out-dir "$PINOCCHIO_BUILD_DIR" \
      --arch "$SBPF_ARCH"
  fi
}

copyPinocchioReferenceElf() {
  local target_elf="$1"
  local built_elf
  built_elf="$(find "$PINOCCHIO_BUILD_DIR" -maxdepth 1 -type f -name '*.so' | head -n 1)"
  [ -n "$built_elf" ] || fail "Pinocchio ELF not found in $PINOCCHIO_BUILD_DIR"
  cp "$built_elf" "$target_elf"
}

cleanup() {
  if [ -n "${SURFPOOL_PID:-}" ] && kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
    kill "$SURFPOOL_PID" >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
      if ! kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
        wait "$SURFPOOL_PID" >/dev/null 2>&1 || true
        return
      fi
      sleep 1
    done
    kill -9 "$SURFPOOL_PID" >/dev/null 2>&1 || true
    wait "$SURFPOOL_PID" >/dev/null 2>&1 || true
  fi
}
