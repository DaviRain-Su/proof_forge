//! Independent Pinocchio Pausable reference for native differential tests.
//!
//! Instruction data is one tag: paused=0, pause=1, and unpause=2.
//! Account zero is writable, program-owned, and stores one little-endian u64.

#![no_std]

use core::convert::TryInto;
use pinocchio::{
    error::ProgramError, no_allocator, nostd_panic_handler, program_entrypoint, AccountView,
    Address, ProgramResult,
};
use solana_define_syscall::definitions::sol_set_return_data;

const TAG_PAUSED: u8 = 0;
const TAG_PAUSE: u8 = 1;
const TAG_UNPAUSE: u8 = 2;

const STATE_LEN: usize = 8;
const ALREADY_PAUSED: u32 = 0x100;
const NOT_PAUSED: u32 = 0x101;

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

fn read_paused(data: &[u8]) -> Result<u64, ProgramError> {
    let bytes = data
        .get(..STATE_LEN)
        .ok_or(ProgramError::AccountDataTooSmall)?;
    Ok(u64::from_le_bytes(
        bytes
            .try_into()
            .map_err(|_| ProgramError::InvalidAccountData)?,
    ))
}

fn write_paused(data: &mut [u8], value: u64) -> Result<(), ProgramError> {
    let output = data
        .get_mut(..STATE_LEN)
        .ok_or(ProgramError::AccountDataTooSmall)?;
    output.copy_from_slice(&value.to_le_bytes());
    Ok(())
}

fn return_u64(value: u64) {
    let encoded = value.to_le_bytes();
    // SAFETY: the VM copies `encoded` during this syscall.
    unsafe { sol_set_return_data(encoded.as_ptr(), encoded.len() as u64) };
}

pub fn process_instruction(
    program_id: &Address,
    accounts: &mut [AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    let [state, ..] = accounts else {
        return Err(ProgramError::NotEnoughAccountKeys);
    };
    if !state.is_writable() || !state.owned_by(program_id) {
        return Err(ProgramError::InvalidArgument);
    }
    if state.data_len() < STATE_LEN {
        return Err(ProgramError::AccountDataTooSmall);
    }
    let tag = *instruction_data
        .first()
        .ok_or(ProgramError::InvalidInstructionData)?;

    match tag {
        TAG_PAUSED => {
            let data = state.try_borrow()?;
            return_u64(read_paused(&data)?);
            Ok(())
        }
        TAG_PAUSE => {
            let mut data = state.try_borrow_mut()?;
            if read_paused(&data)? != 0 {
                return Err(ProgramError::Custom(ALREADY_PAUSED));
            }
            write_paused(&mut data, 1)
        }
        TAG_UNPAUSE => {
            let mut data = state.try_borrow_mut()?;
            if read_paused(&data)? == 0 {
                return Err(ProgramError::Custom(NOT_PAUSED));
            }
            write_paused(&mut data, 0)
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
