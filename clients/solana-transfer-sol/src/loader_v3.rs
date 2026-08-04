//! Loader V3 Program → ProgramData ELF bind (offline pure + live fetch).

use serde::{Deserialize, Serialize};
use solana_loader_v3_interface::get_program_data_address;
use solana_loader_v3_interface::state::UpgradeableLoaderState;
use solana_pubkey::Pubkey;
use solana_sdk_ids::bpf_loader_upgradeable;
use std::str::FromStr;

use crate::constants::{PROGRAMDATA_META_LEN, TOCTOU_NOTE};
use crate::error::ClientError;
use crate::util::sha256_hex;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountSnapshot {
    pub lamports: u64,
    pub data: Vec<u8>,
    pub owner: Pubkey,
    pub executable: bool,
    pub rent_epoch: u64,
}

pub fn loader_v3_id() -> Pubkey {
    bpf_loader_upgradeable::id()
}

pub fn system_program_id() -> Pubkey {
    solana_sdk_ids::system_program::id()
}

pub fn program_data_address(program_id: &Pubkey) -> Pubkey {
    get_program_data_address(program_id)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramAccountDecode {
    pub programdata_address: Pubkey,
    pub derived_programdata_address: Pubkey,
    pub addresses_match: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProgramDataDecode {
    pub slot: u64,
    pub upgrade_authority: Option<String>,
    pub elf_bytes: Vec<u8>,
    pub elf_sha256_hex: String,
    pub authority_is_mutable: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ElfBindResult {
    pub local_sha256_hex: String,
    pub onchain_full_region_sha256_hex: String,
    pub onchain_prefix_sha256_hex: String,
    pub local_len: usize,
    pub onchain_region_len: usize,
    pub prefix_bytes_equal: bool,
    pub trailing_zeros: bool,
    pub upgrade_authority: Option<String>,
    pub last_modified_slot: u64,
    pub toctou_note: String,
}

pub fn decode_loader_v3_program_account(
    program_id: &Pubkey,
    account: &AccountSnapshot,
) -> Result<ProgramAccountDecode, ClientError> {
    if account.owner != loader_v3_id() {
        return Err(ClientError::LoaderBind(format!(
            "Program owner wrong: expected {} actual {}",
            loader_v3_id(),
            account.owner
        )));
    }
    if !account.executable {
        return Err(ClientError::LoaderBind(
            "Program account must be executable".into(),
        ));
    }
    let state: UpgradeableLoaderState = bincode::deserialize(&account.data)
        .map_err(|e| ClientError::LoaderBind(format!("Program state decode: {e}")))?;
    let programdata_address = match state {
        UpgradeableLoaderState::Program {
            programdata_address,
        } => programdata_address,
        other => {
            return Err(ClientError::LoaderBind(format!(
                "expected Program state, got {other:?}"
            )));
        }
    };
    let derived = get_program_data_address(program_id);
    Ok(ProgramAccountDecode {
        programdata_address,
        derived_programdata_address: derived,
        addresses_match: programdata_address == derived,
    })
}

pub fn decode_loader_v3_programdata_account(
    account: &AccountSnapshot,
) -> Result<ProgramDataDecode, ClientError> {
    if account.owner != loader_v3_id() {
        return Err(ClientError::LoaderBind(format!(
            "ProgramData owner wrong: expected {} actual {}",
            loader_v3_id(),
            account.owner
        )));
    }
    if account.executable {
        return Err(ClientError::LoaderBind(
            "ProgramData must not be executable".into(),
        ));
    }
    let meta_len = UpgradeableLoaderState::size_of_programdata_metadata();
    debug_assert_eq!(meta_len, PROGRAMDATA_META_LEN);
    if account.data.len() < meta_len {
        return Err(ClientError::LoaderBind(format!(
            "ProgramData shorter than metadata ({})",
            account.data.len()
        )));
    }
    let meta_bytes = &account.data[..meta_len];
    let state: UpgradeableLoaderState = bincode::deserialize(meta_bytes)
        .map_err(|e| ClientError::LoaderBind(format!("ProgramData metadata decode: {e}")))?;
    let (slot, upgrade_authority) = match state {
        UpgradeableLoaderState::ProgramData {
            slot,
            upgrade_authority_address,
        } => (slot, upgrade_authority_address),
        other => {
            return Err(ClientError::LoaderBind(format!(
                "expected ProgramData state, got {other:?}"
            )));
        }
    };
    let elf_bytes = account.data[meta_len..].to_vec();
    let elf_sha256_hex = sha256_hex(&elf_bytes);
    Ok(ProgramDataDecode {
        slot,
        upgrade_authority: upgrade_authority.map(|p| p.to_string()),
        elf_bytes,
        elf_sha256_hex,
        authority_is_mutable: upgrade_authority.is_some(),
    })
}

pub fn bind_programdata_elf_to_local_bytes(
    programdata: &ProgramDataDecode,
    local: &[u8],
) -> Result<ElfBindResult, ClientError> {
    let local_sha = sha256_hex(local);
    let onchain = &programdata.elf_bytes;
    if onchain.len() < local.len() {
        return Err(ClientError::LoaderBind(format!(
            "on-chain ELF region shorter than local .so ({} < {})",
            onchain.len(),
            local.len()
        )));
    }
    let prefix = &onchain[..local.len()];
    if prefix != local {
        return Err(ClientError::LoaderBind(format!(
            "ELF prefix hash mismatch: onchain={} local={}",
            sha256_hex(prefix),
            local_sha
        )));
    }
    let trailing = &onchain[local.len()..];
    if let Some(i) = trailing.iter().position(|&b| b != 0) {
        return Err(ClientError::LoaderBind(format!(
            "on-chain ELF region has non-zero pad at offset {}",
            local.len() + i
        )));
    }
    Ok(ElfBindResult {
        local_sha256_hex: local_sha.clone(),
        onchain_full_region_sha256_hex: programdata.elf_sha256_hex.clone(),
        onchain_prefix_sha256_hex: sha256_hex(prefix),
        local_len: local.len(),
        onchain_region_len: onchain.len(),
        prefix_bytes_equal: true,
        trailing_zeros: true,
        upgrade_authority: programdata.upgrade_authority.clone(),
        last_modified_slot: programdata.slot,
        toctou_note: TOCTOU_NOTE.to_string(),
    })
}

/// Full Program → ProgramData → local ELF bind from account snapshots.
pub fn bind_deployed_program(
    program_id: &Pubkey,
    program_account: &AccountSnapshot,
    programdata_account: &AccountSnapshot,
    local_so: &[u8],
) -> Result<(ProgramAccountDecode, ProgramDataDecode, ElfBindResult), ClientError> {
    let prog = decode_loader_v3_program_account(program_id, program_account)?;
    if !prog.addresses_match {
        return Err(ClientError::LoaderBind(format!(
            "ProgramData address {} != derived PDA {}",
            prog.programdata_address, prog.derived_programdata_address
        )));
    }
    let pd = decode_loader_v3_programdata_account(programdata_account)?;
    let bind = bind_programdata_elf_to_local_bytes(&pd, local_so)?;
    Ok((prog, pd, bind))
}

// ---------------------------------------------------------------------------
// Synthetic fixtures (offline tests)
// ---------------------------------------------------------------------------

pub fn synth_program_account(programdata_address: Pubkey, lamports: u64) -> AccountSnapshot {
    let state = UpgradeableLoaderState::Program {
        programdata_address,
    };
    let data = bincode::serialize(&state).expect("serialize Program state");
    AccountSnapshot {
        lamports,
        data,
        owner: loader_v3_id(),
        executable: true,
        rent_epoch: u64::MAX,
    }
}

pub fn synth_programdata_account(
    slot: u64,
    upgrade_authority: Option<Pubkey>,
    elf: &[u8],
    pad_zeros: usize,
    lamports: u64,
) -> AccountSnapshot {
    let state = UpgradeableLoaderState::ProgramData {
        slot,
        upgrade_authority_address: upgrade_authority,
    };
    let meta_len = UpgradeableLoaderState::size_of_programdata_metadata();
    let mut data = bincode::serialize(&state).expect("serialize ProgramData metadata");
    debug_assert!(data.len() <= meta_len);
    data.resize(meta_len, 0);
    data.extend_from_slice(elf);
    data.extend(std::iter::repeat_n(0u8, pad_zeros));
    AccountSnapshot {
        lamports,
        data,
        owner: loader_v3_id(),
        executable: false,
        rent_epoch: u64::MAX,
    }
}

pub fn parse_pubkey(s: &str) -> Result<Pubkey, ClientError> {
    Pubkey::from_str(s).map_err(|e| ClientError::Usage(format!("invalid pubkey {s}: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::PROGRAMDATA_META_LEN;

    #[test]
    fn loader_ids_stable() {
        assert_eq!(
            loader_v3_id().to_string(),
            "BPFLoaderUpgradeab1e11111111111111111111111"
        );
        assert_eq!(
            system_program_id().to_string(),
            "11111111111111111111111111111111"
        );
        assert_eq!(
            UpgradeableLoaderState::size_of_programdata_metadata(),
            PROGRAMDATA_META_LEN
        );
    }

    #[test]
    fn bind_prefix_and_pad() {
        let program_id = Pubkey::new_unique();
        let pd_addr = program_data_address(&program_id);
        let local = b"\x7fELF-test-bytes-only!!!!";
        let prog_acc = synth_program_account(pd_addr, 1);
        let pd_acc = synth_programdata_account(9, Some(Pubkey::new_unique()), local, 16, 1);
        let (prog, pd, bind) =
            bind_deployed_program(&program_id, &prog_acc, &pd_acc, local).unwrap();
        assert!(prog.addresses_match);
        assert!(bind.prefix_bytes_equal && bind.trailing_zeros);
        assert_eq!(pd.slot, 9);
        assert!(pd.authority_is_mutable);
        assert!(bind.toctou_note.contains("TOCTOU"));
    }

    #[test]
    fn bind_rejects_mutation_and_nonzero_pad() {
        let local = b"abc";
        let mut bad = local.to_vec();
        bad[0] ^= 0xff;
        let acc = synth_programdata_account(1, None, &bad, 0, 1);
        let pd = decode_loader_v3_programdata_account(&acc).unwrap();
        assert!(bind_programdata_elf_to_local_bytes(&pd, local).is_err());

        let mut acc = synth_programdata_account(1, None, local, 4, 1);
        let meta = UpgradeableLoaderState::size_of_programdata_metadata();
        acc.data[meta + local.len() + 1] = 1;
        let pd = decode_loader_v3_programdata_account(&acc).unwrap();
        assert!(bind_programdata_elf_to_local_bytes(&pd, local).is_err());
    }
}
