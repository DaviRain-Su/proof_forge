//! Shared constants for generic Solana OutputSet verification and known profiles.

/// Exact engineering OutputSet schema.
pub const EXPECTED_SCHEMA_VERSION: &str = "proof-forge.output.v1";
pub const EXPECTED_TARGET: &str = "solana";

/// Closed current Solana codegen profile IDs (unknown → fail closed).
pub const PROFILE_PLAN_V1: &str = "solana-sbpf-plan-v1";
pub const PROFILE_ELF_V1: &str = "solana-sbpf-elf-v1";
pub const PROFILE_CPI_ELF_V1: &str = "solana-sbpf-cpi-elf-v1";

/// Pinned CPI profile/catalog/extension (engineering joins, not provenance).
pub const CPI_PROFILE_DIGEST_HEX: &str =
    "b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04";
pub const CPI_CATALOG_DIGEST_HEX: &str =
    "e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419";
pub const CPI_EXTENSION_ID: &str = "extension.solana-cpi-accounts";
pub const CPI_EXTENSION_VERSION: &str = "1.0.0";
pub const CPI_EXTENSION_DIGEST_HEX: &str =
    "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020";

/// CPI document schemas.
pub const CPI_PLAN_SCHEMA: &str = "proof-forge.solana.cpi-plan.v1";
pub const CPI_IDL_SCHEMA: &str = "proof-forge.solana.cpi-idl.v1";
pub const CPI_BINDINGS_SCHEMA: &str = "proof-forge.solana.cpi-bindings.v1";
pub const CPI_IR_SCHEMA_LINE: &str = "proof-forge.solana.cpi-product-ir.v1";
/// Body-only / Map programs (P3-c full-body hybrid marker IR).
pub const FULL_BODY_HYBRID_IR_SCHEMA: &str = "proof-forge.solana.full-body-hybrid-ir.v1";
pub const BODY_ONLY_EXTENSION_ID: &str = "proof-forge.solana.body-only.v1";
pub const BODY_ONLY_EXTENSION_VERSION: &str = "1.0.0";
pub const BODY_ONLY_EXTENSION_DIGEST_HEX: &str =
    "4d1411f28eb064d0b8c402645dcac3832e4d174cd6af89f189f56baa2651a044";

pub const SYSTEM_PROGRAM_BASE58: &str = "11111111111111111111111111111111";
pub const SYSTEM_PACKAGE_ID: &str = "system-v1";
pub const SYSTEM_PROGRAM_ID_HEX: &str =
    "0000000000000000000000000000000000000000000000000000000000000000";
pub const SYSTEM_RUNTIME_NATIVE_BINDING: &str =
    "runtimeNative:2a165e7a90af75c76426d1e031ed0284211d5d1e";

pub const MANIFEST_NAME: &str = "manifest.json";
pub const EVIDENCE_NAME: &str = "evidence.json";

pub const ROLE_MATERIALIZED_BASE: &str = "materialized-base";
pub const ROLE_FINALIZED_EXTRA: &str = "finalized-extra";

/// TransferSol program adapter identity (opt-in only).
pub const PROGRAM_ADAPTER_TRANSFER_SOL_V1: &str = "transfer-sol-v1";
pub const TRANSFER_SOL_PROGRAM_NAME: &str = "TransferSol";

/// Frozen from the tracked `Examples/TransferSol.lean` ProgramV1 canonical identity.
pub const TRANSFER_SOL_SOURCE_HASH: &str =
    "1fc319e8857f121fda9639596c4922aec42a1c92e43482e5a0aef5749a5f5e29";

// ---------------------------------------------------------------------------
// Backward-compatible aliases used by older TransferSol-focused call sites.
// ---------------------------------------------------------------------------

pub const EXPECTED_PROFILE: &str = PROFILE_CPI_ELF_V1;
pub const EXPECTED_PROGRAM_NAME: &str = TRANSFER_SOL_PROGRAM_NAME;
pub const PROFILE_DIGEST_HEX: &str = CPI_PROFILE_DIGEST_HEX;
pub const CATALOG_DIGEST_HEX: &str = CPI_CATALOG_DIGEST_HEX;
pub const EXTENSION_ID: &str = CPI_EXTENSION_ID;
pub const EXTENSION_VERSION: &str = CPI_EXTENSION_VERSION;
pub const EXTENSION_DIGEST_HEX: &str = CPI_EXTENSION_DIGEST_HEX;
pub const DEFAULT_EXPECTED_SOURCE_HASH: &str = TRANSFER_SOL_SOURCE_HASH;
pub const PLAN_SCHEMA: &str = CPI_PLAN_SCHEMA;
pub const IDL_SCHEMA: &str = CPI_IDL_SCHEMA;
pub const BINDINGS_SCHEMA: &str = CPI_BINDINGS_SCHEMA;
pub const IR_SCHEMA_LINE: &str = CPI_IR_SCHEMA_LINE;
