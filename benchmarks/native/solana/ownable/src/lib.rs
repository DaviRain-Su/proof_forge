//! Independent Pinocchio Ownable reference for native differential tests.
//!
//! Instruction data is one tag followed by little-endian `u64` arguments:
//! init=0, owner=1, transferOwnership=2, and renounceOwnership=3.
//! Account zero is the authority signer. Account one is a writable,
//! program-owned 16-byte state containing owner and initialized words.

#![no_std]

use core::convert::TryInto;
use pinocchio::{
    error::ProgramError, no_allocator, nostd_panic_handler, program_entrypoint, AccountView,
    Address, ProgramResult,
};
use solana_define_syscall::definitions::{sol_log_64_, sol_set_return_data};

const TAG_INIT: u8 = 0;
const TAG_OWNER: u8 = 1;
const TAG_TRANSFER_OWNERSHIP: u8 = 2;
const TAG_RENOUNCE_OWNERSHIP: u8 = 3;

const OWNER: usize = 0;
const INITIALIZED: usize = 8;
const STATE_LEN: usize = 16;

const ALREADY_INITIALIZED: u32 = 0x100;
const NOT_OWNER: u32 = 0x101;
const ZERO_ADDRESS: u32 = 0x102;

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
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&authority.address().as_array()[..8]);
    u64::from_le_bytes(bytes)
}

fn return_u64(value: u64) {
    let encoded = value.to_le_bytes();
    // SAFETY: the VM copies `encoded` during this syscall.
    unsafe { sol_set_return_data(encoded.as_ptr(), encoded.len() as u64) };
}

fn ownership_transferred(previous_owner: u64, new_owner: u64) {
    // Event id zero and one log record per indexed field match the target's
    // numeric event observation contract.
    unsafe {
        sol_log_64_(0, 0, previous_owner, 0, 0);
        sol_log_64_(0, 0, new_owner, 0, 0);
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
    let sender = authority_handle(authority);

    match tag {
        TAG_INIT => {
            let mut data = state.try_borrow_mut()?;
            if read_u64(&data, INITIALIZED)? != 0 {
                return Err(ProgramError::Custom(ALREADY_INITIALIZED));
            }
            write_u64(&mut data, INITIALIZED, 1)?;
            write_u64(&mut data, OWNER, sender)?;
            ownership_transferred(0, sender);
            Ok(())
        }
        TAG_OWNER => {
            let data = state.try_borrow()?;
            return_u64(read_u64(&data, OWNER)?);
            Ok(())
        }
        TAG_TRANSFER_OWNERSHIP => {
            let new_owner = argument(instruction_data, 0)?;
            let mut data = state.try_borrow_mut()?;
            let previous_owner = read_u64(&data, OWNER)?;
            if previous_owner != sender {
                return Err(ProgramError::Custom(NOT_OWNER));
            }
            if new_owner == 0 {
                return Err(ProgramError::Custom(ZERO_ADDRESS));
            }
            ownership_transferred(previous_owner, new_owner);
            write_u64(&mut data, OWNER, new_owner)?;
            Ok(())
        }
        TAG_RENOUNCE_OWNERSHIP => {
            let mut data = state.try_borrow_mut()?;
            let previous_owner = read_u64(&data, OWNER)?;
            if previous_owner != sender {
                return Err(ProgramError::Custom(NOT_OWNER));
            }
            ownership_transferred(previous_owner, 0);
            write_u64(&mut data, OWNER, 0)?;
            Ok(())
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
