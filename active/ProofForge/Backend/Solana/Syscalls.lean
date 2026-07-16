/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Syscall Constants

Symbolic names for the Solana runtime syscalls available to sBPF programs.
These are rendered as `call <name>` in assembly and resolved by the sbpf
assembler/linker.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

namespace ProofForge.Backend.Solana.Syscalls

def sol_log_                : String := "sol_log_"
def sol_log_64_             : String := "sol_log_64_"
def sol_log_pubkey          : String := "sol_log_pubkey"
def sol_log_data            : String := "sol_log_data"
def sol_log_compute_units_  : String := "sol_log_compute_units_"
def sol_memcpy_             : String := "sol_memcpy_"
def sol_memmove_            : String := "sol_memmove_"
def sol_memset_             : String := "sol_memset_"
def sol_memcmp_             : String := "sol_memcmp_"
def sol_create_program_address : String := "sol_create_program_address"
def sol_try_find_program_address : String := "sol_try_find_program_address"
def sol_invoke_signed_c     : String := "sol_invoke_signed_c"
def sol_invoke_signed_rust  : String := "sol_invoke_signed_rust"
def sol_get_clock_sysvar    : String := "sol_get_clock_sysvar"
def sol_get_rent_sysvar     : String := "sol_get_rent_sysvar"
def sol_get_epoch_schedule_sysvar : String := "sol_get_epoch_schedule_sysvar"
def sol_get_epoch_rewards_sysvar : String := "sol_get_epoch_rewards_sysvar"
def sol_get_last_restart_slot : String := "sol_get_last_restart_slot"
def sol_get_sysvar          : String := "sol_get_sysvar"
def sol_get_return_data     : String := "sol_get_return_data"
def sol_set_return_data     : String := "sol_set_return_data"
def sol_sha256              : String := "sol_sha256"
def sol_keccak256           : String := "sol_keccak256"
def sol_blake3              : String := "sol_blake3"
def sol_panic_              : String := "sol_panic_"
def sol_remaining_compute_units : String := "sol_remaining_compute_units"
def sol_alloc_free_         : String := "sol_alloc_free_"

end ProofForge.Backend.Solana.Syscalls
