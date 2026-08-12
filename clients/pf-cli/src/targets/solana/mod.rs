//! Solana developer adapter:
//! - D7a: offline verify via proof-forge-solana-client
//! - D7b: Mollusk StateCell-shaped / TransferSol test
//! - D11: deploy package + optional local RPC broadcast
//! - pf run: one-shot Mollusk (body-only StateCell-shaped)

pub mod deploy;
pub mod local_run;
pub mod test;
pub mod verify;
