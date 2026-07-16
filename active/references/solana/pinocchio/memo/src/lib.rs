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
use pinocchio_memo::instructions::Memo;

pub const PF_LOG_MEMO_TAG: u8 = 0;
pub const PF_LOG_MEMO_BYTES_TAG: u8 = 1;
pub const PF_LOG_MEMO_MIN_INSTRUCTION_DATA_LEN: usize = 9;
pub const PF_LOG_MEMO_BYTES_MIN_INSTRUCTION_DATA_LEN: usize = 17;
pub const PF_MEMO_ARG_OFFSET: usize = 1;
pub const PF_MEMO_ARG_SIZE: usize = 8;
pub const PF_MEMO_BYTES_OFFSET: usize = 1;
pub const PF_MEMO_BYTES_SIZE: usize = 16;
pub const PF_STATE_ACCOUNT_INDEX: usize = 0;
pub const PF_MEMO_PROGRAM_ACCOUNT_INDEX: usize = 1;
pub const PF_ACCOUNT_COUNT: usize = 2;
pub const PF_STATE_WRITE_OFFSET: usize = 0;
pub const PF_STATE_WRITE_SIZE: usize = 8;

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

/// SPL Memo accepts arbitrary bytes; pinocchio-memo exposes `&str`.
/// Treat instruction payload bytes as an opaque string view for CPI data.
fn memo_str_from_bytes(bytes: &[u8]) -> &str {
    // SAFETY: Memo program does not require UTF-8; we only need a byte view.
    unsafe { core::str::from_utf8_unchecked(bytes) }
}

pub fn process_instruction(
    _program_id: &Address,
    accounts: &mut [AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    if accounts.len() < PF_ACCOUNT_COUNT {
        return Err(ProgramError::NotEnoughAccountKeys);
    }
    if instruction_data.is_empty() {
        return Err(ProgramError::InvalidInstructionData);
    }
    if !accounts[PF_STATE_ACCOUNT_INDEX].is_writable() {
        return Err(ProgramError::InvalidArgument);
    }
    if !pinocchio_memo::check_id(accounts[PF_MEMO_PROGRAM_ACCOUNT_INDEX].address()) {
        return Err(ProgramError::IncorrectProgramId);
    }

    match instruction_data[0] {
        PF_LOG_MEMO_TAG => {
            if instruction_data.len() < PF_LOG_MEMO_MIN_INSTRUCTION_DATA_LEN {
                return Err(ProgramError::InvalidInstructionData);
            }
            let memo_bytes =
                &instruction_data[PF_MEMO_ARG_OFFSET..PF_MEMO_ARG_OFFSET + PF_MEMO_ARG_SIZE];
            let memo_word = u64::from_le_bytes(
                memo_bytes
                    .try_into()
                    .map_err(|_| ProgramError::InvalidInstructionData)?,
            );

            Memo {
                signers: &[] as &[&AccountView],
                memo: memo_str_from_bytes(memo_bytes),
            }
            .invoke()?;

            let state = &mut accounts[PF_STATE_ACCOUNT_INDEX];
            let mut state_data = state.try_borrow_mut()?;
            if state_data.len() < PF_STATE_WRITE_OFFSET + PF_STATE_WRITE_SIZE {
                return Err(ProgramError::AccountDataTooSmall);
            }
            state_data[PF_STATE_WRITE_OFFSET..PF_STATE_WRITE_OFFSET + PF_STATE_WRITE_SIZE]
                .copy_from_slice(&memo_word.to_le_bytes());
            Ok(())
        }
        PF_LOG_MEMO_BYTES_TAG => {
            if instruction_data.len() < PF_LOG_MEMO_BYTES_MIN_INSTRUCTION_DATA_LEN {
                return Err(ProgramError::InvalidInstructionData);
            }
            let memo_bytes =
                &instruction_data[PF_MEMO_BYTES_OFFSET..PF_MEMO_BYTES_OFFSET + PF_MEMO_BYTES_SIZE];

            Memo {
                signers: &[] as &[&AccountView],
                memo: memo_str_from_bytes(memo_bytes),
            }
            .invoke()?;
            Ok(())
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
