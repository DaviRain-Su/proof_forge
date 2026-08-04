//! Exact TransferSol outer instruction construction (handler0 + lamports).

use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_message::Message;
use solana_pubkey::Pubkey;
use solana_signer::Signer;
use solana_system_interface::program as system_program;
use solana_transaction::Transaction;

use crate::constants::{HANDLER_TRANSFER, OUTER_IX_DATA_LEN};

/// Exact 16-byte outer instruction data: handler 0 LE + lamports LE.
pub fn build_transfer_ix_data(lamports: u64) -> [u8; OUTER_IX_DATA_LEN] {
    let mut data = [0u8; OUTER_IX_DATA_LEN];
    data[0..8].copy_from_slice(&HANDLER_TRANSFER.to_le_bytes());
    data[8..16].copy_from_slice(&lamports.to_le_bytes());
    data
}

/// Ordered account metas: payer (w+s), recipient (w), System (ro).
pub fn build_transfer_account_metas(payer: &Pubkey, recipient: &Pubkey) -> Vec<AccountMeta> {
    vec![
        AccountMeta::new(*payer, true),
        AccountMeta::new(*recipient, false),
        AccountMeta::new_readonly(system_program::id(), false),
    ]
}

pub fn build_transfer_instruction(
    program_id: &Pubkey,
    payer: &Pubkey,
    recipient: &Pubkey,
    lamports: u64,
) -> Instruction {
    Instruction {
        program_id: *program_id,
        accounts: build_transfer_account_metas(payer, recipient),
        data: build_transfer_ix_data(lamports).to_vec(),
    }
}

pub fn create_and_sign_transfer_tx(
    payer: &Keypair,
    recipient: &Pubkey,
    program_id: &Pubkey,
    lamports: u64,
    recent_blockhash: solana_hash::Hash,
) -> Transaction {
    let ix = build_transfer_instruction(program_id, &payer.pubkey(), recipient, lamports);
    let message = Message::new(&[ix], Some(&payer.pubkey()));
    let mut tx = Transaction::new_unsigned(message);
    tx.sign(&[payer], recent_blockhash);
    tx
}

/// System transfer CPI data: `u32le(2) || u64le(amount)` (12 bytes).
pub fn system_transfer_ix_data(lamports: u64) -> [u8; 12] {
    let mut d = [0u8; 12];
    d[0..4].copy_from_slice(&2u32.to_le_bytes());
    d[4..12].copy_from_slice(&lamports.to_le_bytes());
    d
}

pub fn generate_ephemeral_keypair() -> Keypair {
    Keypair::new()
}

pub fn system_program_id() -> Pubkey {
    system_program::id()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::HANDLER_TRANSFER;

    #[test]
    fn ix_data_is_exact_16_bytes_handler0_plus_lamports_le() {
        let data = build_transfer_ix_data(1_000);
        assert_eq!(data.len(), 16);
        assert_eq!(data[0..8], HANDLER_TRANSFER.to_le_bytes());
        assert_eq!(
            data,
            [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x03, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00,
            ]
        );
    }

    #[test]
    fn account_metas_ordered_payer_recipient_system() {
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let metas = build_transfer_account_metas(&payer, &recipient);
        assert_eq!(metas.len(), 3);
        assert!(metas[0].is_writable && metas[0].is_signer);
        assert!(metas[1].is_writable && !metas[1].is_signer);
        assert!(!metas[2].is_writable && !metas[2].is_signer);
        assert_eq!(metas[2].pubkey, system_program::id());
    }

    #[test]
    fn system_transfer_data_is_disc2_plus_lamports() {
        let d = system_transfer_ix_data(42);
        assert_eq!(&d[0..4], &2u32.to_le_bytes());
        assert_eq!(&d[4..12], &42u64.to_le_bytes());
    }
}
