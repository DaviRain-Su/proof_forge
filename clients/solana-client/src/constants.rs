//! Frozen product constants for the offline Solana artifact verifier.

pub const EXPECTED_SCHEMA_VERSION: &str = "proof-forge.output.v1";
pub const EXPECTED_TARGET: &str = "solana";
pub const EXPECTED_PROFILE: &str = "solana-sbpf-cpi-elf-v1";
pub const EXPECTED_PROGRAM_NAME: &str = "TransferSol";

pub const PROFILE_DIGEST_HEX: &str =
    "b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04";
pub const CATALOG_DIGEST_HEX: &str =
    "e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419";

pub const EXTENSION_ID: &str = "extension.solana-cpi-accounts";
pub const EXTENSION_VERSION: &str = "1.0.0";
pub const EXTENSION_DIGEST_HEX: &str =
    "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020";

/// Frozen from the tracked `Examples/TransferSol.lean` ProgramV1 canonical identity.
pub const DEFAULT_EXPECTED_SOURCE_HASH: &str =
    "1fc319e8857f121fda9639596c4922aec42a1c92e43482e5a0aef5749a5f5e29";

pub const SYSTEM_PROGRAM_BASE58: &str = "11111111111111111111111111111111";
pub const SYSTEM_PACKAGE_ID: &str = "system-v1";
pub const SYSTEM_PROGRAM_ID_HEX: &str =
    "0000000000000000000000000000000000000000000000000000000000000000";
pub const SYSTEM_RUNTIME_NATIVE_BINDING: &str =
    "runtimeNative:2a165e7a90af75c76426d1e031ed0284211d5d1e";

pub const MANIFEST_NAME: &str = "manifest.json";
pub const EVIDENCE_NAME: &str = "evidence.json";

pub const PLAN_SCHEMA: &str = "proof-forge.solana.cpi-plan.v1";
pub const IDL_SCHEMA: &str = "proof-forge.solana.cpi-idl.v1";
pub const BINDINGS_SCHEMA: &str = "proof-forge.solana.cpi-bindings.v1";
pub const IR_SCHEMA_LINE: &str = "proof-forge.solana.cpi-product-ir.v1";
