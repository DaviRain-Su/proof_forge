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
use pinocchio_token::instructions::{Approve, Burn, MintTo, Revoke};

pub const PF_MINT_ENTRYPOINT_TAG: u8 = 0;
pub const PF_BURN_ENTRYPOINT_TAG: u8 = 1;
pub const PF_APPROVE_ENTRYPOINT_TAG: u8 = 2;
pub const PF_REVOKE_ENTRYPOINT_TAG: u8 = 3;
pub const PF_AMOUNT_MIN_INSTRUCTION_DATA_LEN: usize = 9;
pub const PF_REVOKE_MIN_INSTRUCTION_DATA_LEN: usize = 1;
pub const PF_AMOUNT_OFFSET: usize = 1;
pub const PF_AMOUNT_SIZE: usize = 8;
pub const PF_STATE_ACCOUNT_INDEX: usize = 0;
pub const PF_MINT_ACCOUNT_INDEX: usize = 1;
pub const PF_DESTINATION_ACCOUNT_INDEX: usize = 2;
pub const PF_AUTHORITY_ACCOUNT_INDEX: usize = 3;
pub const PF_SPL_TOKEN_ACCOUNT_INDEX: usize = 4;
pub const PF_SOURCE_ACCOUNT_INDEX: usize = 5;
pub const PF_DELEGATE_ACCOUNT_INDEX: usize = 6;
pub const PF_ACCOUNT_COUNT: usize = 7;
pub const PF_TOKEN_MINT_TO_DISCRIMINATOR: u8 = 7;
pub const PF_TOKEN_BURN_DISCRIMINATOR: u8 = 8;
pub const PF_TOKEN_APPROVE_DISCRIMINATOR: u8 = 4;
pub const PF_TOKEN_REVOKE_DISCRIMINATOR: u8 = 5;
pub const PF_TOKEN_AMOUNT_DATA_LEN: usize = 9;
pub const PF_TOKEN_REVOKE_DATA_LEN: usize = 1;
pub const PF_STATE_MINT_WRITE_OFFSET: usize = 0;
pub const PF_STATE_BURN_WRITE_OFFSET: usize = 8;
pub const PF_STATE_APPROVE_WRITE_OFFSET: usize = 16;
pub const PF_STATE_REVOKE_WRITE_OFFSET: usize = 24;
pub const PF_STATE_WRITE_SIZE: usize = 8;
pub const PF_REVOKE_STATE_MARKER: u64 = 1;

#[cfg(feature = "bpf-entrypoint")]
program_entrypoint!(process_instruction);

#[cfg(feature = "bpf-entrypoint")]
nostd_panic_handler!();

#[cfg(feature = "bpf-entrypoint")]
no_allocator!();

fn parse_amount(instruction_data: &[u8]) -> Result<u64, ProgramError> {
    if instruction_data.len() < PF_AMOUNT_MIN_INSTRUCTION_DATA_LEN {
        return Err(ProgramError::InvalidInstructionData);
    }
    Ok(u64::from_le_bytes(
        instruction_data[PF_AMOUNT_OFFSET..PF_AMOUNT_OFFSET + PF_AMOUNT_SIZE]
            .try_into()
            .map_err(|_| ProgramError::InvalidInstructionData)?,
    ))
}

fn write_state_u64(state: &mut AccountView, offset: usize, value: u64) -> ProgramResult {
    let mut state_data = state.try_borrow_mut()?;
    if state_data.len() < offset + PF_STATE_WRITE_SIZE {
        return Err(ProgramError::AccountDataTooSmall);
    }
    state_data[offset..offset + PF_STATE_WRITE_SIZE].copy_from_slice(&value.to_le_bytes());
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
    if instruction_data.is_empty() {
        return Err(ProgramError::InvalidInstructionData);
    }

    if !accounts[PF_STATE_ACCOUNT_INDEX].is_writable()
        || !accounts[PF_MINT_ACCOUNT_INDEX].is_writable()
        || !accounts[PF_DESTINATION_ACCOUNT_INDEX].is_writable()
        || !accounts[PF_SOURCE_ACCOUNT_INDEX].is_writable()
    {
        return Err(ProgramError::InvalidArgument);
    }
    if !accounts[PF_AUTHORITY_ACCOUNT_INDEX].is_signer() {
        return Err(ProgramError::MissingRequiredSignature);
    }
    if !pinocchio_token::check_id(accounts[PF_SPL_TOKEN_ACCOUNT_INDEX].address()) {
        return Err(ProgramError::IncorrectProgramId);
    }

    let tag = instruction_data[0];
    let (state_accounts, cpi_accounts) = accounts.split_at_mut(1);
    let state = &mut state_accounts[PF_STATE_ACCOUNT_INDEX];
    let mint = &cpi_accounts[PF_MINT_ACCOUNT_INDEX - 1];
    let destination = &cpi_accounts[PF_DESTINATION_ACCOUNT_INDEX - 1];
    let authority = &cpi_accounts[PF_AUTHORITY_ACCOUNT_INDEX - 1];
    let source = &cpi_accounts[PF_SOURCE_ACCOUNT_INDEX - 1];
    let delegate = &cpi_accounts[PF_DELEGATE_ACCOUNT_INDEX - 1];

    match tag {
        PF_MINT_ENTRYPOINT_TAG => {
            let amount = parse_amount(instruction_data)?;
            MintTo::new(mint, destination, authority, amount).invoke()?;
            write_state_u64(state, PF_STATE_MINT_WRITE_OFFSET, amount)
        }
        PF_BURN_ENTRYPOINT_TAG => {
            let amount = parse_amount(instruction_data)?;
            Burn::new(source, mint, authority, amount).invoke()?;
            write_state_u64(state, PF_STATE_BURN_WRITE_OFFSET, amount)
        }
        PF_APPROVE_ENTRYPOINT_TAG => {
            let amount = parse_amount(instruction_data)?;
            Approve::new(source, delegate, authority, amount).invoke()?;
            write_state_u64(state, PF_STATE_APPROVE_WRITE_OFFSET, amount)
        }
        PF_REVOKE_ENTRYPOINT_TAG => {
            if instruction_data.len() < PF_REVOKE_MIN_INSTRUCTION_DATA_LEN {
                return Err(ProgramError::InvalidInstructionData);
            }
            Revoke::new(source, authority).invoke()?;
            write_state_u64(state, PF_STATE_REVOKE_WRITE_OFFSET, PF_REVOKE_STATE_MARKER)
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
