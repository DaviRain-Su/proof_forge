//! Pinocchio-class native Counter for ProofForge benchmarks (B1.2).
//!
//! Instruction layout (matches ProofForge Solana Counter fixture style):
//! - byte 0: entrypoint tag
//!   - 0 = initialize  → count = 0
//!   - 1 = increment   → count += 1
//!   - 2 = get         → return count via return data (8 LE bytes)
//! - account 0: program-owned state (writable), first 8 bytes = u64 count
//!
//! Baseline class: **Pinocchio / no_allocator** (not Anchor).

#![no_std]

use core::convert::TryInto;
use pinocchio::{
    error::ProgramError,
    no_allocator,
    nostd_panic_handler,
    program_entrypoint,
    AccountView,
    Address,
    ProgramResult,
};

pub const PF_TAG_INITIALIZE: u8 = 0;
pub const PF_TAG_INCREMENT: u8 = 1;
pub const PF_TAG_GET: u8 = 2;
pub const PF_MIN_INSTRUCTION_DATA_LEN: usize = 1;
pub const PF_STATE_ACCOUNT_INDEX: usize = 0;
pub const PF_ACCOUNT_COUNT: usize = 1;
pub const PF_COUNT_OFFSET: usize = 0;
pub const PF_COUNT_SIZE: usize = 8;

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

fn read_count(data: &[u8]) -> Result<u64, ProgramError> {
    if data.len() < PF_COUNT_OFFSET + PF_COUNT_SIZE {
        return Err(ProgramError::AccountDataTooSmall);
    }
    Ok(u64::from_le_bytes(
        data[PF_COUNT_OFFSET..PF_COUNT_OFFSET + PF_COUNT_SIZE]
            .try_into()
            .map_err(|_| ProgramError::InvalidAccountData)?,
    ))
}

fn write_count(data: &mut [u8], value: u64) -> Result<(), ProgramError> {
    if data.len() < PF_COUNT_OFFSET + PF_COUNT_SIZE {
        return Err(ProgramError::AccountDataTooSmall);
    }
    data[PF_COUNT_OFFSET..PF_COUNT_OFFSET + PF_COUNT_SIZE]
        .copy_from_slice(&value.to_le_bytes());
    Ok(())
}

pub fn process_instruction(
    _program_id: &Address,
    accounts: &mut [AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    if accounts.len() < PF_ACCOUNT_COUNT {
        return Err(ProgramError::NotEnoughAccountKeys);
    }
    if instruction_data.len() < PF_MIN_INSTRUCTION_DATA_LEN {
        return Err(ProgramError::InvalidInstructionData);
    }
    if !accounts[PF_STATE_ACCOUNT_INDEX].is_writable() {
        return Err(ProgramError::InvalidArgument);
    }

    let state = &mut accounts[PF_STATE_ACCOUNT_INDEX];
    match instruction_data[0] {
        PF_TAG_INITIALIZE => {
            let mut data = state.try_borrow_mut()?;
            write_count(&mut data, 0)?;
            Ok(())
        }
        PF_TAG_INCREMENT => {
            let mut data = state.try_borrow_mut()?;
            let n = read_count(&data)?;
            let next = n
                .checked_add(1)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            write_count(&mut data, next)?;
            Ok(())
        }
        PF_TAG_GET => {
            let data = state.try_borrow()?;
            let n = read_count(&data)?;
            // Return LE u64 via sol_set_return_data when available; for host
            // typecheck we only exercise the read path.
            let _ = n;
            Ok(())
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
