#![no_std]

use pinocchio::{
    error::ProgramError,
    no_allocator,
    nostd_panic_handler,
    program_entrypoint,
    AccountView,
    Address,
    ProgramResult,
};
use pinocchio_token::instructions::CloseAccount;

pub const PF_ENTRYPOINT_TAG: u8 = 0;
pub const PF_MIN_INSTRUCTION_DATA_LEN: usize = 1;
pub const PF_STATE_ACCOUNT_INDEX: usize = 0;
pub const PF_TOKEN_ACCOUNT_INDEX: usize = 1;
pub const PF_DESTINATION_ACCOUNT_INDEX: usize = 2;
pub const PF_AUTHORITY_ACCOUNT_INDEX: usize = 3;
pub const PF_SPL_TOKEN_ACCOUNT_INDEX: usize = 4;
pub const PF_ACCOUNT_COUNT: usize = 5;
pub const PF_TOKEN_CLOSE_ACCOUNT_DISCRIMINATOR: u8 = 9;
pub const PF_TOKEN_CLOSE_ACCOUNT_DATA_LEN: usize = 1;
pub const PF_STATE_WRITE_OFFSET: usize = 0;
pub const PF_STATE_WRITE_SIZE: usize = 8;
pub const PF_STATE_MARKER: u64 = 1;

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

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
    if instruction_data[0] != PF_ENTRYPOINT_TAG {
        return Err(ProgramError::InvalidInstructionData);
    }

    if !accounts[PF_STATE_ACCOUNT_INDEX].is_writable()
        || !accounts[PF_TOKEN_ACCOUNT_INDEX].is_writable()
        || !accounts[PF_DESTINATION_ACCOUNT_INDEX].is_writable()
    {
        return Err(ProgramError::InvalidArgument);
    }
    if !accounts[PF_AUTHORITY_ACCOUNT_INDEX].is_signer() {
        return Err(ProgramError::MissingRequiredSignature);
    }
    if !pinocchio_token::check_id(accounts[PF_SPL_TOKEN_ACCOUNT_INDEX].address()) {
        return Err(ProgramError::IncorrectProgramId);
    }

    let (state_accounts, cpi_accounts) = accounts.split_at_mut(PF_TOKEN_ACCOUNT_INDEX);
    let state = &mut state_accounts[PF_STATE_ACCOUNT_INDEX];
    let token_account = &cpi_accounts[0];
    let destination = &cpi_accounts[1];
    let authority = &cpi_accounts[2];

    CloseAccount::new(token_account, destination, authority).invoke()?;

    let mut state_data = state.try_borrow_mut()?;
    if state_data.len() < PF_STATE_WRITE_OFFSET + PF_STATE_WRITE_SIZE {
        return Err(ProgramError::AccountDataTooSmall);
    }
    state_data[PF_STATE_WRITE_OFFSET..PF_STATE_WRITE_OFFSET + PF_STATE_WRITE_SIZE]
        .copy_from_slice(&PF_STATE_MARKER.to_le_bytes());

    Ok(())
}
