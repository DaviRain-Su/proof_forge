# Changelog

All notable changes to ProofForge are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta.1] - 2026-07-10

### Breaking / Migration
- `proof-forge deploy` no longer falls back to the well-known Anvil private key.
  Deployments now require `--private-key KEY` or the `PROOF_FORGE_DEPLOY_PRIVATE_KEY`
  environment variable. Update local Anvil smokes and CI to export the test key.

### Added
- `proof-forge --version` prints the CLI version, Lean toolchain, and git short SHA.
- Per-command `--help` / `-h` for `build`, `emit`, `check`, and global usage.
- `.github/workflows/release.yml` builds Linux x86_64, macOS x86_64, and macOS ARM64
  binaries and uploads tarballs + SHA-256 checksums to GitHub Releases.
- `scripts/ci/install.sh` downloads and installs the matching release tarball.
- `scripts/i18n/check-links.py` validates internal Markdown links in `docs/zh/`.
- `.github/workflows/secret-scan.yml` runs TruffleHog with `--only-verified`.
- `CHANGELOG.md`.

### Changed
- README and AGENTS target roster now advertise only `evm`, `solana-sbpf-asm`, and
  `wasm-near` as beta-ready `contract_source` targets; demoted other targets to
  Counter-MVP / research spikes.
- Hardened `.gitignore` against key material.

### Fixed
- README "Getting Started" product build command now uses
  `Examples/Product/Counter.lean`.
- Removed the stale `proof-forge check is not yet implemented` stub in
  `ProofForge/Cli/TargetFirst.lean`.
