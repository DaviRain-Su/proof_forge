//! Integration-test crate for CosmWasm product WASM runtime differentials.
//!
//! Product tests live under `tests/`. This library unit is intentionally empty
//! so `cargo test` can load the package without a binary target.
//!
//! Engineering mock-runtime only (cosmwasm-vm 3.0.9 + MockStorage/Api/Querier).
//! Not wasmd, not formal Stage-0, not hermetic release evidence.

#![allow(dead_code)]
