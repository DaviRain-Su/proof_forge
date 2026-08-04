//! Frozen product constants for TransferSol engineering client.

/// Exact outer instruction: `u64le(handler_id=0) || u64le(lamports)` → 16 bytes.
pub const HANDLER_TRANSFER: u64 = 0;
pub const OUTER_IX_DATA_LEN: usize = 16;

/// Well-known public Solana Devnet genesis hash (cluster identity anchor).
pub const DEVNET_GENESIS_HASH_BASE58: &str = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG";

pub const DEFAULT_DEVNET_RPC_URL: &str = "https://api.devnet.solana.com";
pub const DEFAULT_RPC_TIMEOUT_SECS: u64 = 30;
pub const MAX_AIRDROP_LAMPORTS: u64 = 2_000_000_000; // 2 SOL
pub const DEFAULT_TRANSFER_LAMPORTS: u64 = 1_000;

/// Expected product identity fields on `proof-forge.output.v1` manifest.
pub const EXPECTED_SCHEMA_VERSION: &str = "proof-forge.output.v1";
pub const EXPECTED_TARGET: &str = "solana";
pub const EXPECTED_PROFILE: &str = "solana-sbpf-cpi-elf-v1";
pub const EXPECTED_PROGRAM_NAME: &str = "TransferSol";

/// Profile / catalog digests advertised by `solana-sbpf-cpi-elf-v1` (hex, no `sha256:` prefix).
pub const PROFILE_DIGEST_HEX: &str =
    "b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04";
pub const CATALOG_DIGEST_HEX: &str =
    "e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419";

/// Extension required by TransferSol source (`extension solana.cpi.accounts` 1.0.0).
pub const EXTENSION_ID: &str = "extension.solana-cpi-accounts";
pub const EXTENSION_VERSION: &str = "1.0.0";
pub const EXTENSION_DIGEST_HEX: &str =
    "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020";

/// Trust anchor for product `sourceHash`.
///
/// Frozen from the tracked `Examples/TransferSol.lean` ProgramV1 canonical identity.
/// The product CLI does not accept a runtime override; an intentional source-AST change must
/// update this pin and its tests in the same reviewed change. Mismatch fails closed.
pub const DEFAULT_EXPECTED_SOURCE_HASH: &str =
    "1fc319e8857f121fda9639596c4922aec42a1c92e43482e5a0aef5749a5f5e29";

pub const SYSTEM_PROGRAM_BASE58: &str = "11111111111111111111111111111111";
pub const SYSTEM_PACKAGE_ID: &str = "system-v1";
pub const SYSTEM_PROGRAM_ID_HEX: &str =
    "0000000000000000000000000000000000000000000000000000000000000000";
/// Exact runtime-native artifact binding pin for system-v1 (Agave commit).
pub const SYSTEM_RUNTIME_NATIVE_BINDING: &str =
    "runtimeNative:2a165e7a90af75c76426d1e031ed0284211d5d1e";

pub const LOADER_V3_BASE58: &str = "BPFLoaderUpgradeab1e11111111111111111111111";
/// On-chain ProgramData metadata region length (Option::Some authority layout).
pub const PROGRAMDATA_META_LEN: usize = 45;

pub const MANIFEST_NAME: &str = "manifest.json";
pub const EVIDENCE_NAME: &str = "evidence.json";

pub const PLAN_SCHEMA: &str = "proof-forge.solana.cpi-plan.v1";
pub const IDL_SCHEMA: &str = "proof-forge.solana.cpi-idl.v1";
pub const BINDINGS_SCHEMA: &str = "proof-forge.solana.cpi-bindings.v1";
pub const IR_SCHEMA_LINE: &str = "proof-forge.solana.cpi-product-ir.v1";

pub const SANITIZED_RECEIPT_SCHEMA: &str = "proof-forge.solana.sanitized-receipt.v1";

pub const TOCTOU_NOTE: &str = "\
TOCTOU: ELF bind is a point-in-time account snapshot at the RPC commitment used for \
getAccountInfo. If upgrade_authority is Some, that authority may Upgrade the ProgramData \
ELF between this observation and any later transaction execution; re-fetch+re-bind is \
required near execution. Even with authority None (immutable), the observation remains \
endpoint-relative (RPC node honesty/commitment/fork) and does not prove future slots.";
