//! Independent Pinocchio StatusMessage reference for native differential tests.
//!
//! Instruction data is one tag followed by little-endian `u64` arguments:
//! init=0, set_status=1, and get_status=2. Account zero is the authority signer;
//! account one is writable, program-owned state with a fixed-capacity map.

#![cfg_attr(not(feature = "host-tests"), no_std)]

use core::convert::TryInto;
use pinocchio::{error::ProgramError, AccountView, Address, ProgramResult};
#[cfg(feature = "bpf-entrypoint")]
use pinocchio::{no_allocator, nostd_panic_handler, program_entrypoint};
use solana_define_syscall::definitions::{sol_log_64_, sol_set_return_data};
use solana_sha256_hasher::hash;

const TAG_INIT: u8 = 0;
const TAG_SET_STATUS: u8 = 1;
const TAG_GET_STATUS: u8 = 2;

const VERSION_OFFSET: usize = 0;
const RECORDS_OFFSET: usize = 8;
const ENTRY_LEN: usize = 24;
const CAPACITY: usize = 256;
const STATE_LEN: usize = RECORDS_OFFSET + CAPACITY * ENTRY_LEN;
const MAP_FULL: u32 = 0x100;

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

fn read_u64(data: &[u8], offset: usize) -> Result<u64, ProgramError> {
    let bytes = data
        .get(offset..offset + 8)
        .ok_or(ProgramError::AccountDataTooSmall)?;
    Ok(u64::from_le_bytes(
        bytes
            .try_into()
            .map_err(|_| ProgramError::InvalidAccountData)?,
    ))
}

fn write_u64(data: &mut [u8], offset: usize, value: u64) -> Result<(), ProgramError> {
    let output = data
        .get_mut(offset..offset + 8)
        .ok_or(ProgramError::AccountDataTooSmall)?;
    output.copy_from_slice(&value.to_le_bytes());
    Ok(())
}

fn argument(data: &[u8], index: usize) -> Result<u64, ProgramError> {
    read_u64(data, 1 + index * 8).map_err(|_| ProgramError::InvalidInstructionData)
}

fn authority_handle(authority: &AccountView) -> u64 {
    let digest = hash(authority.address().as_array());
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&digest.as_ref()[..8]);
    u64::from_le_bytes(bytes)
}

fn record_offset(index: usize) -> usize {
    RECORDS_OFFSET + index * ENTRY_LEN
}

fn find_record(data: &[u8], key: u64) -> Result<Option<usize>, ProgramError> {
    for index in 0..CAPACITY {
        let offset = record_offset(index);
        let occupied = read_u64(data, offset)?;
        if occupied == 0 {
            return Ok(None);
        }
        if read_u64(data, offset + 8)? == key {
            return Ok(Some(offset));
        }
    }
    Ok(None)
}

fn find_record_or_empty(data: &[u8], key: u64) -> Result<usize, ProgramError> {
    for index in 0..CAPACITY {
        let offset = record_offset(index);
        let occupied = read_u64(data, offset)?;
        if occupied == 0 || read_u64(data, offset + 8)? == key {
            return Ok(offset);
        }
    }
    Err(ProgramError::Custom(MAP_FULL))
}

fn return_u64(value: u64) {
    let encoded = value.to_le_bytes();
    // SAFETY: the VM copies `encoded` during this syscall.
    unsafe { sol_set_return_data(encoded.as_ptr(), encoded.len() as u64) };
}

fn status_set(account: u64, status: u64) {
    unsafe {
        sol_log_64_(0, 0, account, 0, 0);
        sol_log_64_(0, 0, status, 0, 0);
    }
}

pub fn process_instruction(
    program_id: &Address,
    accounts: &mut [AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    let [authority, state, ..] = accounts else {
        return Err(ProgramError::NotEnoughAccountKeys);
    };
    if !authority.is_signer() || !state.is_writable() || !state.owned_by(program_id) {
        return Err(ProgramError::InvalidArgument);
    }
    if state.data_len() < STATE_LEN {
        return Err(ProgramError::AccountDataTooSmall);
    }
    let tag = *instruction_data
        .first()
        .ok_or(ProgramError::InvalidInstructionData)?;

    match tag {
        TAG_INIT => {
            let mut data = state.try_borrow_mut()?;
            write_u64(&mut data, VERSION_OFFSET, 1)
        }
        TAG_SET_STATUS => {
            let status = argument(instruction_data, 0)?;
            let who = authority_handle(authority);
            let mut data = state.try_borrow_mut()?;
            let offset = find_record_or_empty(&data, who)?;
            write_u64(&mut data, offset, 1)?;
            write_u64(&mut data, offset + 8, who)?;
            write_u64(&mut data, offset + 16, status)?;
            status_set(who, status);
            Ok(())
        }
        TAG_GET_STATUS => {
            let who = argument(instruction_data, 0)?;
            let data = state.try_borrow()?;
            let status = match find_record(&data, who)? {
                Some(offset) => read_u64(&data, offset + 16)?,
                None => 0,
            };
            return_u64(status);
            Ok(())
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}

#[cfg(all(test, feature = "host-tests"))]
mod tests {
    use super::*;

    #[test]
    fn fixed_map_updates_existing_record() {
        let mut data = [0u8; STATE_LEN];
        let first = find_record_or_empty(&data, 7).unwrap();
        write_u64(&mut data, first, 1).unwrap();
        write_u64(&mut data, first + 8, 7).unwrap();
        write_u64(&mut data, first + 16, 11).unwrap();
        assert_eq!(find_record(&data, 7).unwrap(), Some(first));

        let update = find_record_or_empty(&data, 7).unwrap();
        assert_eq!(update, first);
        write_u64(&mut data, update + 16, 99).unwrap();
        assert_eq!(read_u64(&data, update + 16).unwrap(), 99);
        assert_eq!(find_record(&data, 8).unwrap(), None);
    }
}
