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
use pinocchio_token::instructions::{AuthorityType, SetAuthority};

pub const PF_ENTRYPOINT_TAG: u8 = 0;
pub const PF_MIN_INSTRUCTION_DATA_LEN: usize = 1;
pub const PF_STATE_ACCOUNT_INDEX: usize = 0;
pub const PF_MINT_ACCOUNT_INDEX: usize = 1;
pub const PF_AUTHORITY_ACCOUNT_INDEX: usize = 2;
pub const PF_NEW_AUTHORITY_ACCOUNT_INDEX: usize = 3;
pub const PF_SPL_TOKEN_ACCOUNT_INDEX: usize = 4;
pub const PF_ACCOUNT_COUNT: usize = 5;
pub const PF_TOKEN_SET_AUTHORITY_DISCRIMINATOR: u8 = 6;
pub const PF_TOKEN_AUTHORITY_TYPE_MINT_TOKENS: u8 = 0;
pub const PF_TOKEN_NEW_AUTHORITY_OPTION: u8 = 1;
pub const PF_TOKEN_SET_AUTHORITY_DATA_LEN: usize = 35;
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
        || !accounts[PF_MINT_ACCOUNT_INDEX].is_writable()
    {
        return Err(ProgramError::InvalidArgument);
    }
    if !accounts[PF_AUTHORITY_ACCOUNT_INDEX].is_signer() {
        return Err(ProgramError::MissingRequiredSignature);
    }
    if !pinocchio_token::check_id(accounts[PF_SPL_TOKEN_ACCOUNT_INDEX].address()) {
        return Err(ProgramError::IncorrectProgramId);
    }

    let (before_new_authority, new_authority_accounts) =
        accounts.split_at_mut(PF_NEW_AUTHORITY_ACCOUNT_INDEX);
    let new_authority = new_authority_accounts[0].address();
    let (state_accounts, cpi_accounts) = before_new_authority.split_at_mut(1);
    let state = &mut state_accounts[PF_STATE_ACCOUNT_INDEX];
    let mint = &cpi_accounts[PF_MINT_ACCOUNT_INDEX - 1];
    let authority = &cpi_accounts[PF_AUTHORITY_ACCOUNT_INDEX - 1];

    SetAuthority::new(
        mint,
        authority,
        AuthorityType::MintTokens,
        Some(new_authority),
    )
    .invoke()?;

    let mut state_data = state.try_borrow_mut()?;
    if state_data.len() < PF_STATE_WRITE_OFFSET + PF_STATE_WRITE_SIZE {
        return Err(ProgramError::AccountDataTooSmall);
    }
    state_data[PF_STATE_WRITE_OFFSET..PF_STATE_WRITE_OFFSET + PF_STATE_WRITE_SIZE]
        .copy_from_slice(&PF_STATE_MARKER.to_le_bytes());

    Ok(())
}
