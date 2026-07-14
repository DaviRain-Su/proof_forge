//! Independent Pinocchio ValueVault reference for native differential tests.
//!
//! Instruction data is one tag followed by little-endian `u64` arguments:
//! initialize=0, deposit=1, charge_fee=2, release=3, snapshot=4,
//! get_balance=5, and get_net_value=6. Account zero owns 48 bytes containing
//! six consecutive `u64` fields.

#![no_std]

use core::convert::TryInto;
use pinocchio::{
    error::ProgramError,
    no_allocator, nostd_panic_handler, program_entrypoint,
    sysvars::{clock::Clock, Sysvar},
    AccountView, Address, ProgramResult,
};
use solana_define_syscall::definitions::{sol_log_64_, sol_set_return_data};

const TAG_INITIALIZE: u8 = 0;
const TAG_DEPOSIT: u8 = 1;
const TAG_CHARGE_FEE: u8 = 2;
const TAG_RELEASE: u8 = 3;
const TAG_SNAPSHOT: u8 = 4;
const TAG_GET_BALANCE: u8 = 5;
const TAG_GET_NET_VALUE: u8 = 6;

const BALANCE: usize = 0;
const RELEASED: usize = 8;
const FEES: usize = 16;
const LAST_VALUE: usize = 24;
const LAST_CHECKPOINT: usize = 32;
const OPERATIONS: usize = 40;
const STATE_LEN: usize = 48;

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

fn return_u64(value: u64) {
    let encoded = value.to_le_bytes();
    // SAFETY: the VM copies `encoded` during this syscall.
    unsafe { sol_set_return_data(encoded.as_ptr(), encoded.len() as u64) };
}

fn event(event_id: u64, values: &[u64]) {
    for value in values {
        // This matches the target's documented numeric event observation:
        // event id in arg0 and one field value in arg2 per log record.
        unsafe { sol_log_64_(event_id, 0, *value, 0, 0) };
    }
}

pub fn process_instruction(
    _program_id: &Address,
    accounts: &mut [AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    let state = accounts
        .first_mut()
        .ok_or(ProgramError::NotEnoughAccountKeys)?;
    if !state.is_writable() {
        return Err(ProgramError::InvalidArgument);
    }
    if state.data_len() < STATE_LEN {
        return Err(ProgramError::AccountDataTooSmall);
    }
    let tag = *instruction_data
        .first()
        .ok_or(ProgramError::InvalidInstructionData)?;

    match tag {
        TAG_INITIALIZE => {
            let initial = argument(instruction_data, 0)?;
            let checkpoint = Clock::get()?.slot;
            let mut data = state.try_borrow_mut()?;
            write_u64(&mut data, BALANCE, initial)?;
            write_u64(&mut data, RELEASED, 0)?;
            write_u64(&mut data, FEES, 0)?;
            write_u64(&mut data, LAST_VALUE, initial)?;
            write_u64(&mut data, LAST_CHECKPOINT, checkpoint)?;
            write_u64(&mut data, OPERATIONS, 1)?;
            event(0, &[initial, checkpoint]);
            Ok(())
        }
        TAG_DEPOSIT => {
            let amount = argument(instruction_data, 0)?;
            let mut data = state.try_borrow_mut()?;
            let balance = read_u64(&data, BALANCE)?
                .checked_add(amount)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let operations = read_u64(&data, OPERATIONS)?
                .checked_add(1)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            write_u64(&mut data, BALANCE, balance)?;
            write_u64(&mut data, LAST_VALUE, amount)?;
            write_u64(&mut data, OPERATIONS, operations)?;
            event(1, &[amount, balance, operations]);
            Ok(())
        }
        TAG_CHARGE_FEE => {
            let gross = argument(instruction_data, 0)?;
            let fee_bps = argument(instruction_data, 1)?;
            let fee = gross
                .checked_mul(fee_bps)
                .and_then(|value| value.checked_div(10_000))
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let net = gross
                .checked_sub(fee)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let mut data = state.try_borrow_mut()?;
            let balance = read_u64(&data, BALANCE)?
                .checked_add(net)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let fees = read_u64(&data, FEES)?
                .checked_add(fee)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let operations = read_u64(&data, OPERATIONS)?
                .checked_add(1)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            write_u64(&mut data, BALANCE, balance)?;
            write_u64(&mut data, FEES, fees)?;
            write_u64(&mut data, LAST_VALUE, net)?;
            write_u64(&mut data, OPERATIONS, operations)?;
            event(2, &[gross, fee, net, balance]);
            Ok(())
        }
        TAG_RELEASE => {
            let amount = argument(instruction_data, 0)?;
            let mut data = state.try_borrow_mut()?;
            let balance = read_u64(&data, BALANCE)?
                .checked_sub(amount)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let released = read_u64(&data, RELEASED)?
                .checked_add(amount)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            let operations = read_u64(&data, OPERATIONS)?
                .checked_add(1)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            write_u64(&mut data, BALANCE, balance)?;
            write_u64(&mut data, RELEASED, released)?;
            write_u64(&mut data, LAST_VALUE, amount)?;
            write_u64(&mut data, OPERATIONS, operations)?;
            event(3, &[amount, balance, released]);
            Ok(())
        }
        TAG_SNAPSHOT => {
            let checkpoint = Clock::get()?.slot;
            let mut data = state.try_borrow_mut()?;
            let balance = read_u64(&data, BALANCE)?;
            let released = read_u64(&data, RELEASED)?;
            let fees = read_u64(&data, FEES)?;
            write_u64(&mut data, LAST_CHECKPOINT, checkpoint)?;
            event(4, &[balance, released, fees, checkpoint]);
            return_u64(balance);
            Ok(())
        }
        TAG_GET_BALANCE => {
            let data = state.try_borrow()?;
            return_u64(read_u64(&data, BALANCE)?);
            Ok(())
        }
        TAG_GET_NET_VALUE => {
            let data = state.try_borrow()?;
            let value = read_u64(&data, BALANCE)?
                .checked_sub(read_u64(&data, FEES)?)
                .ok_or(ProgramError::ArithmeticOverflow)?;
            return_u64(value);
            Ok(())
        }
        _ => Err(ProgramError::InvalidInstructionData),
    }
}
