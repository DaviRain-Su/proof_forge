//! Independent Pinocchio ArrayExample reference for native differential tests.
//!
//! Instruction data follows authored entrypoint order: sizeOf3=0, getElem=1,
//! sumOf3=2, and outOfBounds=3. No accounts or persistent state are required.

#![no_std]

use pinocchio::{error::ProgramError, AccountView, Address, ProgramResult};
#[cfg(feature = "bpf-entrypoint")]
use pinocchio::{no_allocator, nostd_panic_handler, program_entrypoint};
use solana_define_syscall::definitions::sol_set_return_data;

const TAG_SIZE_OF_3: u8 = 0;
const TAG_GET_ELEM: u8 = 1;
const TAG_SUM_OF_3: u8 = 2;
const TAG_OUT_OF_BOUNDS: u8 = 3;

const ARRAY_INDEX_OUT_OF_BOUNDS: u32 = 0x100;
const VALUES: [u64; 3] = [10, 20, 30];

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

fn return_u64(value: u64) {
    let encoded = value.to_le_bytes();
    // SAFETY: the VM copies `encoded` during this syscall.
    unsafe { sol_set_return_data(encoded.as_ptr(), encoded.len() as u64) };
}

pub fn process_instruction(
    _program_id: &Address,
    _accounts: &mut [AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    let tag = *instruction_data
        .first()
        .ok_or(ProgramError::InvalidInstructionData)?;

    let value = match tag {
        TAG_SIZE_OF_3 => VALUES.len() as u64,
        TAG_GET_ELEM => VALUES[1],
        TAG_SUM_OF_3 => VALUES.iter().copied().sum(),
        TAG_OUT_OF_BOUNDS => return Err(ProgramError::Custom(ARRAY_INDEX_OUT_OF_BOUNDS)),
        _ => return Err(ProgramError::InvalidInstructionData),
    };
    return_u64(value);
    Ok(())
}
