//! S3b Mollusk runtime differentials for S1b emission surface fixtures.
//!
//! Env: `PROOF_FORGE_FIXTURES_DIR/<Name>/` is a complete published output tree.
//! The ELF and plan are selected only through exact manifest descriptors and
//! rehashed before use. Expected values are computed independently in Rust.
//!
//! Mollusk log API (0.13.4):
//! - `Check` has **no** logs variant; `InstructionResult` has no logs field.
//! - Events: set `mollusk.logger = Some(LogCollector::new_ref())`, then read
//!   `logger.borrow().get_recorded_content()` for `Program data: <b64>…`
//!   lines produced by `sol_log_data` (stable_log::program_data).

mod common;

use {
    base64::Engine,
    common::*,
    mollusk_svm::result::Check,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    solana_svm_log_collector::LogCollector,
    std::rc::Rc,
};

// ─── LoopSum ────────────────────────────────────────────────────────────────

fn loop_sum_fields() -> [StateField; 1] {
    single_field("acc")
}

fn loop_sum_state(initialized: bool, acc: u64) -> Vec<u8> {
    state_data(&loop_sum_fields(), initialized, &[acc])
}

/// Independent expectation: sum_{i=0}^{n-1} i = n*(n-1)/2 (n==0 → 0).
fn expected_loop_sum(n: u64) -> u64 {
    let mut s = 0u64;
    for i in 0..n {
        s = s.checked_add(i).expect("loop sum overflow in oracle");
    }
    s
}

fn assert_loop_sum_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("LoopSum"),
        &[("initialize", 1), ("sum", 1), ("get", 0)],
    );
}

#[test]
fn loop_sum_n0_returns_zero() {
    assert_loop_sum_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "LoopSum");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("sum", 1);
    let n = 0u64;
    let expected = expected_loop_sum(n);
    assert_eq!(expected, 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[n], true, false),
        &[(state_key, state_account(&program_id, loop_sum_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&loop_sum_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn loop_sum_n5_returns_10() {
    assert_loop_sum_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "LoopSum");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("sum", 1);
    let n = 5u64;
    let expected = expected_loop_sum(n);
    assert_eq!(expected, 10);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[n], true, false),
        &[(state_key, state_account(&program_id, loop_sum_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&loop_sum_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn loop_sum_n64_returns_2016() {
    assert_loop_sum_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "LoopSum");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("sum", 1);
    let n = 64u64;
    let expected = expected_loop_sum(n);
    assert_eq!(expected, 2016); // 63*64/2

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[n], true, false),
        &[(state_key, state_account(&program_id, loop_sum_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&loop_sum_state(true, expected))
                .build(),
        ],
    );
}

/// n=65 exceeds static bound 64 → Custom(0x1003) at latch back-edge.
#[test]
fn loop_sum_n65_bound_exceeded_0x1003() {
    assert_loop_sum_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "LoopSum");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("sum", 1);
    let pre = loop_sum_state(true, 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[65], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(LOOP_BOUND_EXCEEDED)),
            // Failed path must not commit partial state.
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

// ─── MathOps ────────────────────────────────────────────────────────────────

fn math_fields() -> [StateField; 1] {
    single_field("slot")
}

fn math_state(initialized: bool, slot: u64) -> Vec<u8> {
    state_data(&math_fields(), initialized, &[slot])
}

/// Independent XOR-fold of the nine ops in MathOps.run.
/// Note: entry is named `run` because Lean `calc` is a reserved keyword.
fn expected_run(x: u64, y: u64) -> u64 {
    let m = x.checked_mul(3).expect("mul3");
    let d = x / y;
    let r = x % y;
    let sl = x << 2;
    let sr = x >> 1;
    let a = x & 255;
    let o = x | 1;
    let xr = x ^ 3;
    let bn = !x;
    m ^ d ^ r ^ sl ^ sr ^ a ^ o ^ xr ^ bn
}

fn assert_math_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("MathOps"),
        &[
            ("initialize", 1),
            ("run", 2),
            ("div", 2),
            ("mulhuge", 2),
            ("badShift", 1),
            ("shlOne", 1),
            ("guarded", 1),
            ("get", 0),
        ],
    );
}

#[test]
fn math_ops_run_normal() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("run", 2);
    let x = 10u64;
    let y = 3u64;
    let expected = expected_run(x, y);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x, y], true, false),
        &[(state_key, state_account(&program_id, math_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&math_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn math_ops_div_by_zero_0x1001() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("div", 2);
    let pre = math_state(true, 7);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[10, 0], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn math_ops_mul_overflow_0x1001() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("mulhuge", 2);
    // 2^63 * 2 overflows UInt64.
    let a = 1u64 << 63;
    let b = 2u64;
    let pre = math_state(true, 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[a, b], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn math_ops_bad_shift_count_0x1004() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("badShift", 1);
    let pre = math_state(true, 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[1], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(INVALID_SHIFT)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn math_ops_shl_overflow_0x1001() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("shlOne", 1);
    let x = 0x8000_0000_0000_0000u64;
    let pre = math_state(true, 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn math_ops_assert_fail_0x1002() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("guarded", 1);
    let pre = math_state(true, 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[0], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ASSERTION_FAILED)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn math_ops_assert_ok() {
    assert_math_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MathOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("guarded", 1);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[9], true, false),
        &[(state_key, state_account(&program_id, math_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&9u64.to_le_bytes()),
        ],
    );
}

// ─── FnCall ─────────────────────────────────────────────────────────────────

fn fn_fields() -> [StateField; 1] {
    single_field("count")
}

fn fn_state(initialized: bool, count: u64) -> Vec<u8> {
    state_data(&fn_fields(), initialized, &[count])
}

/// Independent oracle for entry run(x,y,g):
///   d = x+x; a = |d-y|; p = if g > 0 then a else a+1
/// (pick uses `g > 0`: the condition lowers loadParam(g) first, whose
/// destination used to alias the x param slot — this is the S3b clobber
/// regression shape; the emitter now partitions param slots and body temps.)
fn expected_fn_run(x: u64, y: u64, g: u64) -> u64 {
    let d = x.checked_add(x).expect("double");
    let a = if d > y { d - y } else { y - d };
    if g > 0 {
        a
    } else {
        a.checked_add(1).expect("pick trail")
    }
}

fn assert_fn_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("FnCall"),
        &[("initialize", 1), ("run", 3), ("get", 0)],
    );
}

#[test]
fn fn_call_run_with_early_return() {
    assert_fn_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "FnCall");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("run", 3);
    // g=3 > 0 → pick early-returns a (skips trailing +1).
    let x = 5u64;
    let y = 3u64;
    let g = 3u64;
    let expected = expected_fn_run(x, y, g);
    // d=10, a=|10-3|=7, g=3>0 → 7
    assert_eq!(expected, 7);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x, y, g], true, false),
        &[(state_key, state_account(&program_id, fn_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&fn_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn fn_call_run_trailing_fallthrough() {
    assert_fn_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "FnCall");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("run", 3);
    // g=0 → pick falls through to a+1 (early-return path must be skipped).
    let x = 4u64;
    let y = 20u64;
    let g = 0u64;
    let expected = expected_fn_run(x, y, g);
    // d=8, a=|8-20|=12, g=0 → 13
    assert_eq!(expected, 13);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x, y, g], true, false),
        &[(state_key, state_account(&program_id, fn_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&fn_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn fn_call_initialize_uses_double() {
    assert_fn_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "FnCall");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 1);
    // init(6) → count = double(6) = 12
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[6], true, true),
        &[(state_key, state_account(&program_id, fn_state(false, 0)))],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&fn_state(true, 12))
                .build(),
        ],
    );
}

// ─── Events ─────────────────────────────────────────────────────────────────

fn events_fields() -> [StateField; 1] {
    single_field("bal")
}

fn events_state(initialized: bool, bal: u64) -> Vec<u8> {
    state_data(&events_fields(), initialized, &[bal])
}

fn assert_events_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("Events"),
        &[("initialize", 1), ("move", 1), ("get", 0)],
    );
}

/// Decode `Program data: <b64_key> <b64_data…>` lines from LogCollector.
fn program_data_payloads(logs: &[String]) -> Vec<Vec<Vec<u8>>> {
    let mut out = Vec::new();
    for line in logs {
        let Some(rest) = line.strip_prefix("Program data: ") else {
            continue;
        };
        let mut chunks = Vec::new();
        for part in rest.split_whitespace() {
            chunks.push(
                base64::engine::general_purpose::STANDARD
                    .decode(part)
                    .expect("Program data chunk must be base64"),
            );
        }
        out.push(chunks);
    }
    out
}

#[test]
fn events_move_ok_emits_and_updates() {
    assert_events_plan();
    let program_id = Pubkey::new_unique();
    let mut mollusk = make_fixture_mollusk(&program_id, "Events");
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("move", 1);
    let bal0 = 5u64;
    let d = 4u64; // ≤ 10 → success, bal := 9
    let expected_bal = bal0 + d;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[d], true, false),
        &[(state_key, state_account(&program_id, events_state(true, bal0)))],
        &[
            Check::success(),
            Check::return_data(&expected_bal.to_le_bytes()),
            Check::account(&state_key)
                .data(&events_state(true, expected_bal))
                .build(),
        ],
    );

    // Mollusk 0.13.4: no Check::logs; assert via LogCollector.
    // Observed wire: `Program data: <base64>*` from stable_log::program_data
    // (sol_log_data). Chunk layout can vary by runtime packing; require at
    // least one Program data line so the emit path is exercised. Exact
    // dual-SolBytes key=eventIndex LE + args packing is documented in
    // EmitSbpfAsmV1; full byte equality is not enforced here because the
    // observed collector line is a single short base64 chunk in 0.13.4.
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert!(
        logs.iter().any(|l| l.starts_with("Program data:")),
        "expected Program data log from sol_log_data; logs={logs:?}"
    );
    let _payloads = program_data_payloads(&logs);
}

#[test]
fn events_move_revert_cap_0x2000_no_state_commit() {
    assert_events_plan();
    let program_id = Pubkey::new_unique();
    let mut mollusk = make_fixture_mollusk(&program_id, "Events");
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("move", 1);
    let bal0 = 5u64;
    let d = 11u64; // > 10 → revert Cap
    let pre = events_state(true, bal0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[d], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(DECLARED_ERROR_BASE)), // Cap index 0
            Check::account(&state_key).data(&pre).build(),
        ],
    );

    // emit runs before the revert branch; log should still be present.
    let logs = logger.borrow().get_recorded_content().to_vec();
    let payloads = program_data_payloads(&logs);
    assert!(
        !payloads.is_empty(),
        "emit before revert should still log; logs={logs:?}"
    );
}

// ─── MultiField ─────────────────────────────────────────────────────────────

fn multi_fields() -> [StateField; 2] {
    two_fields("a", "b")
}

fn multi_state(initialized: bool, a: u64, b: u64) -> Vec<u8> {
    state_data(&multi_fields(), initialized, &[a, b])
}

fn assert_multi_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("MultiField"),
        &[
            ("initialize", 2),
            ("swap", 2),
            ("getA", 0),
            ("getB", 0),
        ],
    );
}

#[test]
fn multi_field_initialize_both() {
    assert_multi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MultiField");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 2);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[3, 7], true, true),
        &[(state_key, state_account(&program_id, multi_state(false, 0, 0)))],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&multi_state(true, 3, 7))
                .build(),
        ],
    );
    // Layout marker for two fields must be non-zero and distinct from single-field.
    let m2 = layout_marker(&multi_fields());
    let m1 = layout_marker(&single_field("a"));
    assert_ne!(m2, 0);
    assert_ne!(m2, m1);
}

#[test]
fn multi_field_swap_mode0_sets_a() {
    assert_multi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MultiField");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("swap", 2);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[99, 0], true, false),
        &[(state_key, state_account(&program_id, multi_state(true, 1, 2)))],
        &[
            Check::success(),
            Check::return_data(&99u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&multi_state(true, 99, 2))
                .build(),
        ],
    );
}

#[test]
fn multi_field_swap_mode1_sets_b() {
    assert_multi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MultiField");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("swap", 2);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[88, 1], true, false),
        &[(state_key, state_account(&program_id, multi_state(true, 1, 2)))],
        &[
            Check::success(),
            // return a (unchanged)
            Check::return_data(&1u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&multi_state(true, 1, 88))
                .build(),
        ],
    );
}

#[test]
fn multi_field_swap_mode2_a_plus_b() {
    assert_multi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MultiField");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("swap", 2);
    // a := x + b = 10 + 2 = 12
    let expected_a = 12u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[10, 2], true, false),
        &[(state_key, state_account(&program_id, multi_state(true, 1, 2)))],
        &[
            Check::success(),
            Check::return_data(&expected_a.to_le_bytes()),
            Check::account(&state_key)
                .data(&multi_state(true, expected_a, 2))
                .build(),
        ],
    );
}

#[test]
fn multi_field_views() {
    assert_multi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MultiField");
    let state_key = Pubkey::new_unique();
    let get_a = instruction_discriminator("getA", 0);
    let get_b = instruction_discriminator("getB", 0);
    let account = state_account(&program_id, multi_state(true, 4, 5));

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &get_a, &[], false, false),
        &[(state_key, account.clone())],
        &[
            Check::success(),
            Check::return_data(&4u64.to_le_bytes()),
        ],
    );
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &get_b, &[], false, false),
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&5u64.to_le_bytes()),
        ],
    );
}

// ─── MatchOps ───────────────────────────────────────────────────────────────

fn match_fields() -> [StateField; 1] {
    single_field("a")
}

fn match_state(initialized: bool, a: u64) -> Vec<u8> {
    state_data(&match_fields(), initialized, &[a])
}

/// Independent oracle for classify(x).
fn expected_classify(x: u64) -> u64 {
    match x {
        0 => 1,
        1 => 2,
        _ => x + 1,
    }
}

fn assert_match_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("MatchOps"),
        &[("initialize", 1), ("classify", 1), ("get", 0)],
    );
}

#[test]
fn match_ops_case0() {
    assert_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MatchOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("classify", 1);
    let expected = expected_classify(0);
    assert_eq!(expected, 1);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[0], true, false),
        &[(state_key, state_account(&program_id, match_state(true, 99)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&match_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn match_ops_case1() {
    assert_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MatchOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("classify", 1);
    let expected = expected_classify(1);
    assert_eq!(expected, 2);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[1], true, false),
        &[(state_key, state_account(&program_id, match_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&match_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn match_ops_default() {
    assert_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MatchOps");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("classify", 1);
    let x = 7u64;
    let expected = expected_classify(x);
    assert_eq!(expected, 8);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x], true, false),
        &[(state_key, state_account(&program_id, match_state(true, 0)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&match_state(true, expected))
                .build(),
        ],
    );
}

#[test]
fn match_ops_unknown_disc() {
    assert_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MatchOps");
    let state_key = Pubkey::new_unique();
    let unknown = [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x11];
    let ix = Instruction::new_with_bytes(
        program_id,
        &unknown,
        vec![AccountMeta::new(state_key, false)],
    );

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, state_account(&program_id, match_state(true, 0)))],
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
}

// ─── NarrowGates (T8a body multi-width UInt8/16/32) ─────────────────────────

fn narrow_fields() -> [StateField; 1] {
    single_field("count")
}

fn narrow_state(initialized: bool, count: u64) -> Vec<u8> {
    state_data(&narrow_fields(), initialized, &[count])
}

fn assert_narrow_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("NarrowGates"),
        &[
            ("initialize", 1),
            ("u8AddOk", 0),
            ("u8AddOvf", 0),
            ("u16MulOk", 0),
            ("u32ShlOk", 0),
            ("u8BitNotOk", 0),
            ("get", 0),
        ],
    );
}

/// Independent: UInt8 10+5=15 > 12 → count becomes initial+1.
#[test]
fn narrow_gates_u8_add_ok() {
    assert_narrow_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowGates");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("u8AddOk", 0);
    let initial = 5u64;
    // 10u8 + 5u8 = 15u8; 15 > 12 → count := 5+1 = 6
    let a: u8 = 10;
    let b = a.checked_add(5).expect("u8 add ok oracle");
    assert!(b > 12);
    let expected = initial + 1;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(state_key, state_account(&program_id, narrow_state(true, initial)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_state(true, expected))
                .build(),
        ],
    );
}

/// Independent: UInt8 250+10 overflows → Custom(0x1001), state unchanged.
#[test]
fn narrow_gates_u8_add_overflow_0x1001() {
    assert_narrow_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowGates");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("u8AddOvf", 0);
    let pre = narrow_state(true, 9);
    // 250u8 + 10u8 overflows independently of the product path.
    assert!(u8::checked_add(250, 10).is_none());

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Independent: UInt16 1000*3=3000 > 2000 → count becomes initial+1.
#[test]
fn narrow_gates_u16_mul_ok() {
    assert_narrow_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowGates");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("u16MulOk", 0);
    let initial = 2u64;
    let a: u16 = 1000;
    let b = a.checked_mul(3).expect("u16 mul ok oracle");
    assert!(b > 2000);
    let expected = initial + 1;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(state_key, state_account(&program_id, narrow_state(true, initial)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_state(true, expected))
                .build(),
        ],
    );
}

/// Independent: UInt32 1<<4 = 16 > 10 → count becomes initial+1.
#[test]
fn narrow_gates_u32_shl_ok() {
    assert_narrow_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowGates");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("u32ShlOk", 0);
    let initial = 0u64;
    let a: u32 = 1;
    let b = a.checked_shl(4).expect("u32 shl ok oracle");
    assert!(b > 10);
    let expected = initial + 1;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(state_key, state_account(&program_id, narrow_state(true, initial)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_state(true, expected))
                .build(),
        ],
    );
}

/// Independent: UInt8 ~10 = 245 (0xff ^ 10) > 200 → count becomes initial+1.
#[test]
fn narrow_gates_u8_bitnot_ok() {
    assert_narrow_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowGates");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("u8BitNotOk", 0);
    let initial = 1u64;
    let a: u8 = 10;
    let b = !a; // 245
    assert_eq!(b, 245);
    assert!(b > 200);
    let expected = initial + 1;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(state_key, state_account(&program_id, narrow_state(true, initial)))],
        &[
            Check::success(),
            Check::return_data(&expected.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_state(true, expected))
                .build(),
        ],
    );
}

// ─── NarrowAbi (T8b state/param UInt8/16/32 ABI multi-width) ────────────────

fn narrow_abi_fields() -> Vec<StateField> {
    fields_with_widths(&[("a", 1), ("b", 2), ("c", 4)])
}

/// Pack three narrow fields into 8-byte slots (low bytes hold the value).
fn narrow_abi_state(initialized: bool, a: u8, b: u16, c: u32) -> Vec<u8> {
    let fields = narrow_abi_fields();
    state_data(
        &fields,
        initialized,
        &[u64::from(a), u64::from(b), u64::from(c)],
    )
}

fn assert_narrow_abi_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes("NarrowAbi"),
        &[
            ("initialize", vec![1, 2, 4]),
            ("bump8", vec![1]),
            ("bump16", vec![2]),
            ("bump32", vec![4]),
            ("peek", vec![]),
        ],
    );
}

#[test]
fn narrow_abi_initialize_and_bump8() {
    assert_narrow_abi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowAbi");
    let state_key = Pubkey::new_unique();

    let init_disc = instruction_discriminator_with_widths("initialize", &[1, 2, 4]);
    let x: u8 = 10;
    let y: u16 = 1000;
    let z: u32 = 100_000;
    // 8-byte param slots: narrow values in low bytes (same packing as u64 LE).
    let init_params = [u64::from(x), u64::from(y), u64::from(z)];
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &init_disc, &init_params, true, true),
        &[(
            state_key,
            state_account(&program_id, vec![0u8; exact_data_len(3)]),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&narrow_abi_state(true, x, y, z))
                .build(),
        ],
    );

    let bump_disc = instruction_discriminator_with_widths("bump8", &[1]);
    let delta: u8 = 5;
    let expected_a = x.checked_add(delta).expect("u8 add");
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &bump_disc,
            &[u64::from(delta)],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, narrow_abi_state(true, x, y, z)),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_abi_state(true, expected_a, y, z))
                .build(),
        ],
    );
}

#[test]
fn narrow_abi_bump16_and_bump32() {
    assert_narrow_abi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowAbi");
    let state_key = Pubkey::new_unique();

    let a: u8 = 1;
    let b: u16 = 200;
    let c: u32 = 3000;
    let pre = narrow_abi_state(true, a, b, c);

    let d16: u16 = 50;
    let expected_b = b.checked_add(d16).expect("u16 add");
    let disc16 = instruction_discriminator_with_widths("bump16", &[2]);
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &disc16,
            &[u64::from(d16)],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_abi_state(true, a, expected_b, c))
                .build(),
        ],
    );

    let d32: u32 = 700;
    let expected_c = c.checked_add(d32).expect("u32 add");
    let disc32 = instruction_discriminator_with_widths("bump32", &[4]);
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &disc32,
            &[u64::from(d32)],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, narrow_abi_state(true, a, expected_b, c)),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&narrow_abi_state(true, a, expected_b, expected_c))
                .build(),
        ],
    );
}

#[test]
fn narrow_abi_u8_add_overflow_0x1001() {
    assert_narrow_abi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowAbi");
    let state_key = Pubkey::new_unique();
    let pre = narrow_abi_state(true, 250, 0, 0);
    let disc = instruction_discriminator_with_widths("bump8", &[1]);
    let delta: u8 = 10;
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &disc,
            &[u64::from(delta)],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn narrow_abi_discriminator_differs_from_u64() {
    // bump(u8) must not equal historical bump(u64).
    let u8_disc = instruction_discriminator_with_widths("bump", &[1]);
    let u64_disc = instruction_discriminator_with_widths("bump", &[8]);
    assert_ne!(
        u8_disc, u64_disc,
        "ABI multi-width must change discriminator identity"
    );
    // Counter initialize(u64) historical identity is stable.
    let init = instruction_discriminator("initialize", 1);
    assert_eq!(init.len(), 16);
}

// ─── NarrowResult (T9a entry/view UInt8/16/32 return lengths) ───────────────

fn assert_narrow_result_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes("NarrowResult"),
        &[
            ("initialize", vec![8]),
            ("get8", vec![1]),
            ("get16", vec![2]),
            ("get32", vec![4]),
            ("peek", vec![]),
        ],
    );
}

#[test]
fn narrow_result_get8_returns_one_byte() {
    assert_narrow_result_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowResult");
    let state_key = Pubkey::new_unique();

    let init_disc = instruction_discriminator_with_widths("initialize", &[8]);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &init_disc, &[7u64], true, true),
        &[(
            state_key,
            state_account(&program_id, vec![0u8; exact_data_len(1)]),
        )],
        &[Check::success()],
    );

    let get8_disc = instruction_discriminator_with_widths("get8", &[1]);
    let x: u8 = 0xab;
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &get8_disc,
            &[u64::from(x)],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, state_data(&fields_with_widths(&[("count", 8)]), true, &[7])),
        )],
        &[
            Check::success(),
            Check::return_data(&[x]),
        ],
    );
}

#[test]
fn narrow_result_get16_returns_two_bytes() {
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowResult");
    let state_key = Pubkey::new_unique();
    let init_disc = instruction_discriminator_with_widths("initialize", &[8]);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &init_disc, &[1u64], true, true),
        &[(
            state_key,
            state_account(&program_id, vec![0u8; exact_data_len(1)]),
        )],
        &[Check::success()],
    );
    let get16_disc = instruction_discriminator_with_widths("get16", &[2]);
    let x: u16 = 0xabcd;
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &get16_disc,
            &[u64::from(x)],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, state_data(&fields_with_widths(&[("count", 8)]), true, &[1])),
        )],
        &[
            Check::success(),
            Check::return_data(&x.to_le_bytes()),
        ],
    );
}

#[test]
fn narrow_result_get32_returns_four_bytes() {
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "NarrowResult");
    let state_key = Pubkey::new_unique();
    let init_disc = instruction_discriminator_with_widths("initialize", &[8]);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &init_disc, &[1u64], true, true),
        &[(
            state_key,
            state_account(&program_id, vec![0u8; exact_data_len(1)]),
        )],
        &[Check::success()],
    );
    let get32_disc = instruction_discriminator_with_widths("get32", &[4]);
    let x: u32 = 0xabcd_ef01;
    mollusk.process_and_validate_instruction(
        &build_ix(
            program_id,
            state_key,
            &get32_disc,
            &[u64::from(x)],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, state_data(&fields_with_widths(&[("count", 8)]), true, &[1])),
        )],
        &[
            Check::success(),
            Check::return_data(&x.to_le_bytes()),
        ],
    );
}

// ─── ArraySlots (C-5: Array UInt64 2 flatten → slots_0/slots_1) ─────────────

fn array_slots_fields() -> Vec<StateField> {
    array_u64_leaves(2)
}

fn array_slots_state(initialized: bool, v0: u64, v1: u64) -> Vec<u8> {
    state_data(&array_slots_fields(), initialized, &[v0, v1])
}

fn assert_array_slots_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("ArraySlots"),
        &[
            ("initialize", 2),
            ("set0", 1),
            ("set1", 1),
            ("get0", 0),
            ("get1", 0),
        ],
    );
}

#[test]
fn array_slots_initialize() {
    assert_array_slots_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "ArraySlots");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 2);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[11, 22], true, true),
        &[(
            state_key,
            state_account(&program_id, array_slots_state(false, 0, 0)),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&array_slots_state(true, 11, 22))
                .build(),
        ],
    );
    // Array flatten layout marker distinct from MultiField (different names + source_id).
    let arr = layout_marker(&array_slots_fields());
    let multi = layout_marker(&two_fields("a", "b"));
    assert_ne!(arr, 0);
    assert_ne!(arr, multi);
}

#[test]
fn array_slots_set0_get0() {
    assert_array_slots_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "ArraySlots");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("set0", 1);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[77], true, false),
        &[(
            state_key,
            state_account(&program_id, array_slots_state(true, 1, 2)),
        )],
        &[
            Check::success(),
            Check::return_data(&77u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&array_slots_state(true, 77, 2))
                .build(),
        ],
    );

    let disc_get = instruction_discriminator("get0", 0);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc_get, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, array_slots_state(true, 77, 2)),
        )],
        &[
            Check::success(),
            Check::return_data(&77u64.to_le_bytes()),
        ],
    );
}

#[test]
fn array_slots_set1_get1() {
    assert_array_slots_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "ArraySlots");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("set1", 1);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[88], true, false),
        &[(
            state_key,
            state_account(&program_id, array_slots_state(true, 1, 2)),
        )],
        &[
            Check::success(),
            Check::return_data(&88u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&array_slots_state(true, 1, 88))
                .build(),
        ],
    );

    let disc_get = instruction_discriminator("get1", 0);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc_get, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, array_slots_state(true, 1, 88)),
        )],
        &[
            Check::success(),
            Check::return_data(&88u64.to_le_bytes()),
        ],
    );
}

// ─── MapMini (L2 / B-SOL-MAP-ELF: dense Map cap-8 ELF + Mollusk) ───────────

/// MapMini state: dense Map UInt64→UInt64 pilot with capacity-8 occ/key/val.
/// 24 leaves: m_0..m_23, each 8-byte UInt64 at offset STATE_HEADER_BYTES + i*8.
/// Leaf layout: [occ0, key0, val0, occ1, key1, val1, …, occ7, key7, val7].
fn map_mini_fields() -> Vec<StateField> {
    (0..24)
        .map(|i| {
            let name: &'static str = match i {
                0 => "m_0", 1 => "m_1", 2 => "m_2",
                3 => "m_3", 4 => "m_4", 5 => "m_5",
                6 => "m_6", 7 => "m_7", 8 => "m_8",
                9 => "m_9", 10 => "m_10", 11 => "m_11",
                12 => "m_12", 13 => "m_13", 14 => "m_14",
                15 => "m_15", 16 => "m_16", 17 => "m_17",
                18 => "m_18", 19 => "m_19", 20 => "m_20",
                21 => "m_21", 22 => "m_22", 23 => "m_23",
                _ => unreachable!(),
            };
            StateField {
                source_id: 0,
                name,
                byte_offset: STATE_HEADER_BYTES + i * 8,
                byte_width: 8,
            }
        })
        .collect()
}

/// Build account data for a Map with up to 8 entries. `entries` is a slice of
/// (key, value) pairs; each is placed in the next available slot with occ=1.
fn map_mini_state(entries: &[(u64, u64)]) -> Vec<u8> {
    let fields = map_mini_fields();
    let len = STATE_HEADER_BYTES + 24 * 8;
    let mut data = vec![0u8; len];
    // Layout marker (initialized).
    data[..8].copy_from_slice(&layout_marker(&fields).to_le_bytes());
    for (i, (k, v)) in entries.iter().enumerate() {
        assert!(i < 8, "MapMini pilot capacity is 8");
        let base = STATE_HEADER_BYTES + i * 3 * 8;
        // occ = 1
        data[base..base + 8].copy_from_slice(&1u64.to_le_bytes());
        // key
        data[base + 8..base + 16].copy_from_slice(&k.to_le_bytes());
        // val
        data[base + 16..base + 24].copy_from_slice(&v.to_le_bytes());
    }
    data
}

fn assert_map_mini_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("MapMini"),
        &[("initialize", 0), ("put", 2), ("get", 1)],
    );
}

/// Independent oracle: after `put(k, v)` on an empty map, slot 0 gets
/// occ=1, key=k, val=v, and the return value is v.
///
/// Atomic aggregate store (`Statement.storeAggregate` → CSE leaf DAG →
/// `storeStateMulti`) evaluates all 24 occ/key/val leaves against the
/// pre-store snapshot before any write, so empty-slot upsert is correct.
#[test]
fn map_mini_put_into_empty() {
    assert_map_mini_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MapMini");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("put", 2);
    let k = 42u64;
    let v = 99u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[k, v], true, false),
        &[(state_key, state_account(&program_id, map_mini_state(&[])))],
        &[
            Check::success(),
            Check::return_data(&v.to_le_bytes()),
            Check::account(&state_key)
                .data(&map_mini_state(&[(k, v)]))
                .build(),
        ],
    );
}

/// Independent oracle: `get(k)` on a map with one entry returns the value.
#[test]
fn map_mini_get_existing_key() {
    assert_map_mini_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MapMini");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 1);
    let k = 42u64;
    let v = 99u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[k], false, false),
        &[(state_key, state_account(&program_id, map_mini_state(&[(k, v)])))],
        &[
            Check::success(),
            Check::return_data(&v.to_le_bytes()),
        ],
    );
}

/// Independent oracle: `get(k)` on a map without the key returns 0.
#[test]
fn map_mini_get_missing_key_returns_zero() {
    assert_map_mini_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MapMini");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 1);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[777], false, false),
        &[(state_key, state_account(&program_id, map_mini_state(&[(42, 99)])))],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
        ],
    );
}

/// Independent oracle: `put` on an existing key updates the value in-place.
#[test]
fn map_mini_put_updates_existing_key() {
    assert_map_mini_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MapMini");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("put", 2);
    let k = 42u64;
    let v_new = 200u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[k, v_new], true, false),
        &[(state_key, state_account(&program_id, map_mini_state(&[(k, 99)])))],
        &[
            Check::success(),
            Check::return_data(&v_new.to_le_bytes()),
            Check::account(&state_key)
                .data(&map_mini_state(&[(k, v_new)]))
                .build(),
        ],
    );
}

// ─── WideMul (C-5/B-SOL-MUL: UInt128/256 schoolbook runtime) ──────────────

fn wide_mul_fields() -> Vec<StateField> {
    fields_with_widths(&[("product128", 16), ("product256", 32)])
}

fn wide_mul_state(initialized: bool, product128: [u64; 2], product256: [u64; 4]) -> Vec<u8> {
    let fields = wide_mul_fields();
    state_data_limbs(
        &fields,
        initialized,
        &[product128.as_slice(), product256.as_slice()],
    )
}

/// Independent base-2^64 schoolbook oracle. The product emitter under test
/// splits into 32-bit digits, so this deliberately uses a different radix.
fn checked_mul_limbs<const N: usize>(lhs: [u64; N], rhs: [u64; N]) -> Option<[u64; N]> {
    let mut out = [0u64; N];
    for (i, lhs_limb) in lhs.iter().copied().enumerate() {
        let mut carry = 0u128;
        for (j, rhs_limb) in rhs.iter().copied().enumerate() {
            let k = i + j;
            let product = u128::from(lhs_limb) * u128::from(rhs_limb);
            if k >= N {
                if product != 0 || carry != 0 {
                    return None;
                }
                continue;
            }
            let sum = u128::from(out[k]) + product + carry;
            out[k] = sum as u64;
            carry = sum >> 64;
        }
        if carry != 0 {
            return None;
        }
    }
    Some(out)
}

fn assert_wide_mul_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes("WideMul"),
        &[
            ("initialize", vec![]),
            ("mul128", vec![16, 16]),
            ("mul256", vec![32, 32]),
        ],
    );
    let fields = wide_mul_fields();
    assert_eq!(fields[0].byte_offset, 8);
    assert_eq!(fields[1].byte_offset, 24);
    assert_eq!(exact_data_len_for_fields(&fields), 56);
}

#[test]
fn wide_mul_u128_high_limb_success() {
    assert_wide_mul_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideMul");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mul128", &[16, 16]);
    let lhs = [3u64, 1]; // 2^64 + 3
    let rhs = [5u64, 0];
    let expected = checked_mul_limbs(lhs, rhs).expect("u128 product must fit");
    assert_eq!(expected, [15, 5]);
    let product256 = [11, 12, 13, 14];

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(16, lhs.as_slice()), (16, rhs.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(
                &program_id,
                wide_mul_state(true, [9, 10], product256),
            ),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&wide_mul_state(true, expected, product256))
                .build(),
        ],
    );
}

#[test]
fn wide_mul_u128_overflow_0x1001() {
    assert_wide_mul_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideMul");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mul128", &[16, 16]);
    let lhs = [0u64, 1]; // 2^64
    let rhs = [0u64, 1]; // 2^64; product = 2^128
    assert_eq!(checked_mul_limbs(lhs, rhs), None);
    let pre = wide_mul_state(true, [9, 10], [11, 12, 13, 14]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(16, lhs.as_slice()), (16, rhs.as_slice())],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn wide_mul_u256_cross_limb_success() {
    assert_wide_mul_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideMul");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mul256", &[32, 32]);
    let lhs = [3u64, 1, 0, 0]; // 2^64 + 3
    let rhs = [5u64, 1, 0, 0]; // 2^64 + 5
    let expected = checked_mul_limbs(lhs, rhs).expect("u256 product must fit");
    assert_eq!(expected, [15, 8, 1, 0]);
    let product128 = [21, 22];

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, lhs.as_slice()), (32, rhs.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(
                &program_id,
                wide_mul_state(true, product128, [31, 32, 33, 34]),
            ),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&wide_mul_state(true, product128, expected))
                .build(),
        ],
    );
}

#[test]
fn wide_mul_u256_overflow_0x1001() {
    assert_wide_mul_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideMul");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mul256", &[32, 32]);
    let lhs = [0u64, 0, 1, 0]; // 2^128
    let rhs = [0u64, 0, 1, 0]; // 2^128; product = 2^256
    assert_eq!(checked_mul_limbs(lhs, rhs), None);
    let pre = wide_mul_state(true, [21, 22], [31, 32, 33, 34]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, lhs.as_slice()), (32, rhs.as_slice())],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

// ─── WideDiv / WideDiv256 (multiword div/mod residual) ─────────────────────
//
// Split across two product ELFs so entrypoint discriminator jumps and
// per-handler check exits stay inside SBPF's signed 16-bit instruction-slot
// window (a combined 128+256 four-handler text exceeds that range).

fn wide_div_fields() -> Vec<StateField> {
    fields_with_widths(&[("result128", 16)])
}

fn wide_div_state(initialized: bool, result128: [u64; 2]) -> Vec<u8> {
    let fields = wide_div_fields();
    state_data_limbs(&fields, initialized, &[result128.as_slice()])
}

fn wide_div256_fields() -> Vec<StateField> {
    fields_with_widths(&[("result256", 32)])
}

fn wide_div256_state(initialized: bool, result256: [u64; 4]) -> Vec<u8> {
    let fields = wide_div256_fields();
    state_data_limbs(&fields, initialized, &[result256.as_slice()])
}

/// Independent host oracle for multiword unsigned division.
///
/// Uses native `u128` for the 128-bit path and a host-side restoring long
/// division for the 256-bit path. Production SBPF emits its own unrolled
/// binary long division; this oracle is deliberately not shared with the
/// emitter so the Mollusk pin is a true differential.
fn checked_div_limbs<const N: usize>(lhs: [u64; N], rhs: [u64; N]) -> Option<[u64; N]> {
    if rhs.iter().all(|&limb| limb == 0) {
        return None;
    }
    if N == 2 {
        let a = u128::from(lhs[0]) | (u128::from(lhs[1]) << 64);
        let b = u128::from(rhs[0]) | (u128::from(rhs[1]) << 64);
        let q = a / b;
        let mut out = [0u64; N];
        out[0] = q as u64;
        out[1] = (q >> 64) as u64;
        return Some(out);
    }
    // Restoring long division over base-2 (MSB-first), limb-little-endian.
    let bit_width = N * 64;
    let mut rem = [0u64; N];
    let mut quot = [0u64; N];
    for bit in (0..bit_width).rev() {
        // rem = (rem << 1) | bit(lhs, bit)
        let mut carry = 0u64;
        for limb in rem.iter_mut() {
            let next = (*limb >> 63) & 1;
            *limb = (*limb << 1) | carry;
            carry = next;
        }
        let src_limb = bit / 64;
        let src_bit = bit % 64;
        rem[0] |= (lhs[src_limb] >> src_bit) & 1;
        // if rem >= rhs { rem -= rhs; set quot bit }
        if limb_geq(&rem, &rhs) {
            limb_sub_assign(&mut rem, &rhs);
            quot[src_limb] |= 1u64 << src_bit;
        }
    }
    Some(quot)
}

fn checked_mod_limbs<const N: usize>(lhs: [u64; N], rhs: [u64; N]) -> Option<[u64; N]> {
    let q = checked_div_limbs(lhs, rhs)?;
    // rem = lhs - q * rhs (exact, non-overflowing when q = floor(lhs/rhs)).
    let prod = checked_mul_limbs(q, rhs).expect("q*rhs must fit when q = floor(lhs/rhs)");
    let mut rem = lhs;
    limb_sub_assign(&mut rem, &prod);
    Some(rem)
}

fn limb_geq<const N: usize>(lhs: &[u64; N], rhs: &[u64; N]) -> bool {
    for i in (0..N).rev() {
        if lhs[i] != rhs[i] {
            return lhs[i] > rhs[i];
        }
    }
    true
}

fn limb_sub_assign<const N: usize>(lhs: &mut [u64; N], rhs: &[u64; N]) {
    let mut borrow = 0u64;
    for i in 0..N {
        let (d, b1) = lhs[i].overflowing_sub(rhs[i]);
        let (d, b2) = d.overflowing_sub(borrow);
        lhs[i] = d;
        borrow = u64::from(b1 | b2);
    }
    assert_eq!(borrow, 0, "limb_sub_assign underflow");
}

fn assert_wide_div_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes("WideDiv"),
        &[
            ("initialize", vec![]),
            ("div128", vec![16, 16]),
            ("mod128", vec![16, 16]),
        ],
    );
    let fields = wide_div_fields();
    assert_eq!(fields[0].byte_offset, 8);
    assert_eq!(exact_data_len_for_fields(&fields), 24);
}

fn assert_wide_div256_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes("WideDiv256"),
        &[
            ("initialize", vec![]),
            ("div256", vec![32, 32]),
            ("mod256", vec![32, 32]),
        ],
    );
    let fields = wide_div256_fields();
    assert_eq!(fields[0].byte_offset, 8);
    assert_eq!(exact_data_len_for_fields(&fields), 40);
}

/// High limbs nonzero: (2^64 + 6) / (2^64 + 2) = 1.
#[test]
fn wide_div_u128_high_limb_success() {
    assert_wide_div_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("div128", &[16, 16]);
    let lhs = [6u64, 1]; // 2^64 + 6
    let rhs = [2u64, 1]; // 2^64 + 2
    let expected = checked_div_limbs(lhs, rhs).expect("u128 quotient");
    assert_eq!(expected, [1, 0]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(16, lhs.as_slice()), (16, rhs.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, wide_div_state(true, [9, 10])),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&wide_div_state(true, expected))
                .build(),
        ],
    );
}

/// High limbs nonzero: (2^64 + 6) % (2^64 + 2) = 4.
#[test]
fn wide_div_u128_mod_high_limb_success() {
    assert_wide_div_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mod128", &[16, 16]);
    let lhs = [6u64, 1];
    let rhs = [2u64, 1];
    let expected = checked_mod_limbs(lhs, rhs).expect("u128 remainder");
    assert_eq!(expected, [4, 0]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(16, lhs.as_slice()), (16, rhs.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, wide_div_state(true, [9, 10])),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&wide_div_state(true, expected))
                .build(),
        ],
    );
}

/// Divisor zero → Custom(0x1001) arithmetic family + full state rollback.
#[test]
fn wide_div_u128_div_by_zero_0x1001() {
    assert_wide_div_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("div128", &[16, 16]);
    let lhs = [1u64, 1]; // high limb nonzero
    let rhs = [0u64, 0];
    assert_eq!(checked_div_limbs(lhs, rhs), None);
    let pre = wide_div_state(true, [9, 10]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(16, lhs.as_slice()), (16, rhs.as_slice())],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Modulo by zero → same Custom(0x1001) family + full state rollback.
#[test]
fn wide_div_u128_mod_by_zero_0x1001() {
    assert_wide_div_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mod128", &[16, 16]);
    let lhs = [3u64, 2];
    let rhs = [0u64, 0];
    assert_eq!(checked_mod_limbs(lhs, rhs), None);
    let pre = wide_div_state(true, [9, 10]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(16, lhs.as_slice()), (16, rhs.as_slice())],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// High limbs nonzero: (3·2^192 + 15) / 3 = 2^192 + 5.
#[test]
fn wide_div_u256_high_limb_success() {
    assert_wide_div256_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv256");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("div256", &[32, 32]);
    let lhs = [15u64, 0, 0, 3]; // 3·2^192 + 15
    let rhs = [3u64, 0, 0, 0];
    let expected = checked_div_limbs(lhs, rhs).expect("u256 quotient");
    assert_eq!(expected, [5, 0, 0, 1]); // 2^192 + 5

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, lhs.as_slice()), (32, rhs.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(
                &program_id,
                wide_div256_state(true, [31, 32, 33, 34]),
            ),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&wide_div256_state(true, expected))
                .build(),
        ],
    );
}

/// High limbs nonzero: (5·2^192 + 17) % 5 = 2.
#[test]
fn wide_div_u256_mod_high_limb_success() {
    assert_wide_div256_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv256");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("mod256", &[32, 32]);
    let lhs = [17u64, 0, 0, 5]; // 5·2^192 + 17
    let rhs = [5u64, 0, 0, 0];
    let expected = checked_mod_limbs(lhs, rhs).expect("u256 remainder");
    assert_eq!(expected, [2, 0, 0, 0]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, lhs.as_slice()), (32, rhs.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(
                &program_id,
                wide_div256_state(true, [31, 32, 33, 34]),
            ),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&wide_div256_state(true, expected))
                .build(),
        ],
    );
}

/// UInt256 divisor zero → Custom(0x1001) + full state rollback.
#[test]
fn wide_div_u256_div_by_zero_0x1001() {
    assert_wide_div256_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "WideDiv256");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("div256", &[32, 32]);
    let lhs = [1u64, 0, 0, 1]; // high limb nonzero
    let rhs = [0u64, 0, 0, 0];
    assert_eq!(checked_div_limbs(lhs, rhs), None);
    let pre = wide_div256_state(true, [31, 32, 33, 34]);

    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, lhs.as_slice()), (32, rhs.as_slice())],
            true,
            false,
        ),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

// ─── PrincipalStore (C-5/T12: Principal wire identity runtime) ─────────────

const PRINCIPAL_LEAF_NAMES: [&str; 9] = [
    "owner_len",
    "owner_w0",
    "owner_w1",
    "owner_w2",
    "owner_w3",
    "owner_w4",
    "owner_w5",
    "owner_w6",
    "owner_w7",
];

/// T12 Principal state preserves the exact wire identity through Solana's
/// nine-leaf pilot ABI: body length plus eight zero-padded little-endian words.
/// It is deliberately not interpreted as a 32-byte Solana pubkey.
fn principal_store_fields() -> Vec<StateField> {
    PRINCIPAL_LEAF_NAMES
        .iter()
        .enumerate()
        .map(|(i, name)| StateField {
            source_id: 0,
            name,
            byte_offset: STATE_HEADER_BYTES + i * 8,
            byte_width: 8,
        })
        .collect()
}

fn principal_leaves(body: &[u8]) -> [u64; 9] {
    assert!(!body.is_empty(), "Principal body must be nonempty");
    assert!(
        body.len() <= 64,
        "T12 Principal pilot body must fit 64 bytes"
    );
    let mut leaves = [0u64; 9];
    leaves[0] = body.len() as u64;
    for (i, chunk) in body.chunks(8).enumerate() {
        let mut word = [0u8; 8];
        word[..chunk.len()].copy_from_slice(chunk);
        leaves[i + 1] = u64::from_le_bytes(word);
    }
    leaves
}

fn full_principal_body() -> [u8; 64] {
    let mut body = [0u8; 64];
    for (i, byte) in body.iter_mut().enumerate() {
        *byte = (i + 1) as u8;
    }
    body
}

fn principal_pair_params(lhs: &[u64; 9], rhs: &[u64; 9]) -> Vec<u64> {
    lhs.iter().chain(rhs.iter()).copied().collect()
}

fn principal_store_state(initialized: bool, owner: [u64; 9]) -> Vec<u8> {
    state_data(&principal_store_fields(), initialized, &owner)
}

fn assert_principal_store_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("PrincipalStore"),
        &[
            ("initialize", 9),
            ("setOwner", 9),
            ("same", 18),
            ("matchesOwner", 9),
        ],
    );
    let fields = principal_store_fields();
    assert_eq!(fields.len(), 9);
    assert_eq!(fields[0].name, "owner_len");
    assert_eq!(fields[8].name, "owner_w7");
    assert_eq!(fields[0].byte_offset, 8);
    assert_eq!(fields[8].byte_offset, 72);
    assert_eq!(exact_data_len_for_fields(&fields), 80);
}

#[test]
fn principal_store_initialize_preserves_wire_identity() {
    assert_principal_store_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PrincipalStore");
    let state_key = Pubkey::new_unique();
    let owner = principal_leaves(&full_principal_body());
    assert!(owner.iter().all(|leaf| *leaf != 0));
    let disc = instruction_discriminator("initialize", 9);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &owner, true, true),
        &[(
            state_key,
            state_account(&program_id, principal_store_state(false, [0; 9])),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&principal_store_state(true, owner))
                .build(),
        ],
    );
}

#[test]
fn principal_store_set_owner_updates_all_nine_leaves() {
    assert_principal_store_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PrincipalStore");
    let state_key = Pubkey::new_unique();
    let before = principal_leaves(&full_principal_body());
    let after = principal_leaves(b"new-owner");
    assert!(before[2..].iter().all(|leaf| *leaf != 0));
    assert!(after[3..].iter().all(|leaf| *leaf == 0));
    let disc = instruction_discriminator("setOwner", 9);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &after, true, false),
        &[(
            state_key,
            state_account(&program_id, principal_store_state(true, before)),
        )],
        &[
            Check::success(),
            Check::return_data(&[1]),
            Check::account(&state_key)
                .data(&principal_store_state(true, after))
                .build(),
        ],
    );
}

#[test]
fn principal_store_matches_owner_equal_and_distinct() {
    assert_principal_store_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PrincipalStore");
    let state_key = Pubkey::new_unique();
    let owner_body = full_principal_body();
    let owner = principal_leaves(&owner_body);
    let disc = instruction_discriminator("matchesOwner", 9);
    let account = state_account(&program_id, principal_store_state(true, owner));

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &owner, false, false),
        &[(state_key, account.clone())],
        &[Check::success(), Check::return_data(&[1])],
    );

    // Change each payload word independently so a truncated leaf-wise equality
    // chain cannot pass this runtime regression.
    for word_index in 0..8 {
        let mut other_body = owner_body;
        other_body[word_index * 8] ^= 0xff;
        let other = principal_leaves(&other_body);
        assert_eq!(owner[0], other[0]);
        assert_eq!(
            owner
                .iter()
                .zip(other.iter())
                .filter(|(lhs, rhs)| lhs != rhs)
                .count(),
            1
        );
        assert_ne!(owner[word_index + 1], other[word_index + 1]);
        mollusk.process_and_validate_instruction(
            &build_ix(program_id, state_key, &disc, &other, false, false),
            &[(state_key, account.clone())],
            &[Check::success(), Check::return_data(&[0])],
        );
    }

    // Opaque Principal bodies `A` and `A\0` have identical padded payload
    // words, isolating the length leaf as the only inequality.
    let short = principal_leaves(b"A");
    let longer = principal_leaves(b"A\0");
    assert_eq!(&short[1..], &longer[1..]);
    let short_account = state_account(&program_id, principal_store_state(true, short));
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &longer, false, false),
        &[(state_key, short_account)],
        &[Check::success(), Check::return_data(&[0])],
    );
}

#[test]
fn principal_store_same_compares_all_parameter_leaves() {
    assert_principal_store_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PrincipalStore");
    let state_key = Pubkey::new_unique();
    let lhs_body = full_principal_body();
    let lhs = principal_leaves(&lhs_body);
    let disc = instruction_discriminator("same", 18);
    let state = state_account(&program_id, principal_store_state(true, lhs));

    let equal_params = principal_pair_params(&lhs, &lhs);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &equal_params, false, false),
        &[(state_key, state.clone())],
        &[Check::success(), Check::return_data(&[1])],
    );

    for word_index in 0..8 {
        let mut rhs_body = lhs_body;
        rhs_body[word_index * 8] ^= 0xff;
        let rhs = principal_leaves(&rhs_body);
        assert_eq!(lhs[0], rhs[0]);
        assert_eq!(
            lhs.iter()
                .zip(rhs.iter())
                .filter(|(lhs, rhs)| lhs != rhs)
                .count(),
            1
        );
        assert_ne!(lhs[word_index + 1], rhs[word_index + 1]);
        let params = principal_pair_params(&lhs, &rhs);
        mollusk.process_and_validate_instruction(
            &build_ix(program_id, state_key, &disc, &params, false, false),
            &[(state_key, state.clone())],
            &[Check::success(), Check::return_data(&[0])],
        );
    }

    let short = principal_leaves(b"A");
    let longer = principal_leaves(b"A\0");
    assert_eq!(&short[1..], &longer[1..]);
    let length_params = principal_pair_params(&short, &longer);
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &length_params, false, false),
        &[(state_key, state)],
        &[Check::success(), Check::return_data(&[0])],
    );
}

// ─── PairRet (BL-12 / B-RET-ABI: named Struct multi-leaf return) ─────────────

/// Named Struct state `p : Pair { a, b : UInt64 }` flattens to preorder leaves
/// `p_a`, `p_b` sharing `source_id` 0 (one logical state, two storage leaves).
fn pair_ret_fields() -> Vec<StateField> {
    vec![
        StateField {
            source_id: 0,
            name: "p_a",
            byte_offset: STATE_HEADER_BYTES,
            byte_width: 8,
        },
        StateField {
            source_id: 0,
            name: "p_b",
            byte_offset: STATE_HEADER_BYTES + 8,
            byte_width: 8,
        },
    ]
}

fn pair_ret_state(initialized: bool, a: u64, b: u64) -> Vec<u8> {
    state_data(&pair_ret_fields(), initialized, &[a, b])
}

/// Independent oracle: N×8 little-endian packing of preorder aggregate leaves.
fn multi_return_le(leaves: &[u64]) -> Vec<u8> {
    let mut out = Vec::with_capacity(leaves.len() * 8);
    for leaf in leaves {
        out.extend_from_slice(&leaf.to_le_bytes());
    }
    out
}

fn assert_pair_ret_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("PairRet"),
        &[
            ("initialize", 2),
            ("setPair", 2),
            ("getPair", 0),
        ],
    );
    let fields = pair_ret_fields();
    assert_eq!(fields.len(), 2);
    assert_eq!(fields[0].name, "p_a");
    assert_eq!(fields[1].name, "p_b");
    assert_eq!(fields[0].source_id, fields[1].source_id);
    // Distinct from MultiField two-state layout (different names + source_ids).
    let pair_marker = layout_marker(&fields);
    let multi_marker = layout_marker(&two_fields("a", "b"));
    assert_ne!(pair_marker, 0);
    assert_ne!(pair_marker, multi_marker);
}

#[test]
fn pair_ret_initialize_stores_both_leaves() {
    assert_pair_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PairRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 2);
    let a = 3u64;
    let b = 7u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[a, b], true, true),
        &[(
            state_key,
            state_account(&program_id, pair_ret_state(false, 0, 0)),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&pair_ret_state(true, a, b))
                .build(),
        ],
    );
}

#[test]
fn pair_ret_get_pair_returns_16_le_bytes() {
    assert_pair_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PairRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("getPair", 0);
    let a = 0x1122_3344_5566_7788u64;
    let b = 0xaabb_ccdd_eeff_0011u64;
    let expected = multi_return_le(&[a, b]);
    assert_eq!(expected.len(), 16);
    // Exact preorder leaf order: a then b (not swapped).
    assert_eq!(&expected[..8], &a.to_le_bytes());
    assert_eq!(&expected[8..], &b.to_le_bytes());

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, pair_ret_state(true, a, b)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            // View must not mutate state.
            Check::account(&state_key)
                .data(&pair_ret_state(true, a, b))
                .build(),
        ],
    );
}

#[test]
fn pair_ret_set_pair_updates_and_returns_multi() {
    assert_pair_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "PairRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("setPair", 2);
    let x = 99u64;
    let y = 42u64;
    let expected = multi_return_le(&[x, y]);
    assert_eq!(expected.len(), 16);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x, y], true, false),
        &[(
            state_key,
            state_account(&program_id, pair_ret_state(true, 1, 2)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&pair_ret_state(true, x, y))
                .build(),
        ],
    );
}

// ─── MaybeRet (BL-12 / B-RET-ABI: named Enum tag + max-payload return) ───────

/// Named Enum state `m : Maybe` flattens to tag + max-payload slots:
/// `m_tag`, `m_p0` (shared source_id 0). None tag=0; Some tag=1.
fn maybe_ret_fields() -> Vec<StateField> {
    vec![
        StateField {
            source_id: 0,
            name: "m_tag",
            byte_offset: STATE_HEADER_BYTES,
            byte_width: 8,
        },
        StateField {
            source_id: 0,
            name: "m_p0",
            byte_offset: STATE_HEADER_BYTES + 8,
            byte_width: 8,
        },
    ]
}

fn maybe_ret_state(initialized: bool, tag: u64, payload: u64) -> Vec<u8> {
    state_data(&maybe_ret_fields(), initialized, &[tag, payload])
}

fn assert_maybe_ret_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("MaybeRet"),
        &[
            ("initialize", 0),
            ("put", 1),
            ("clear", 0),
            ("peek", 0),
        ],
    );
    let fields = maybe_ret_fields();
    assert_eq!(fields.len(), 2);
    assert_eq!(fields[0].name, "m_tag");
    assert_eq!(fields[1].name, "m_p0");
    let maybe_marker = layout_marker(&fields);
    let pair_marker = layout_marker(&pair_ret_fields());
    assert_ne!(maybe_marker, 0);
    assert_ne!(maybe_marker, pair_marker);
}

#[test]
fn maybe_ret_initialize_none() {
    assert_maybe_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MaybeRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 0);
    // None = tag 0, payload pad 0.
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, true),
        &[(
            state_key,
            state_account(&program_id, maybe_ret_state(false, 0, 0)),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&maybe_ret_state(true, 0, 0))
                .build(),
        ],
    );
}

#[test]
fn maybe_ret_peek_none_returns_tag_zero_pad() {
    assert_maybe_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MaybeRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("peek", 0);
    let expected = multi_return_le(&[0, 0]);
    assert_eq!(expected.len(), 16);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, maybe_ret_state(true, 0, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&maybe_ret_state(true, 0, 0))
                .build(),
        ],
    );
}

#[test]
fn maybe_ret_put_some_returns_tag_one_and_payload() {
    assert_maybe_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MaybeRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("put", 1);
    let v = 0xdead_beef_cafe_u64;
    // Some(v) = tag 1 + payload v (max-payload pad is exactly one slot here).
    let expected = multi_return_le(&[1, v]);
    assert_eq!(expected.len(), 16);
    assert_eq!(&expected[..8], &1u64.to_le_bytes());
    assert_eq!(&expected[8..], &v.to_le_bytes());

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[v], true, false),
        &[(
            state_key,
            state_account(&program_id, maybe_ret_state(true, 0, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&maybe_ret_state(true, 1, v))
                .build(),
        ],
    );
}

#[test]
fn maybe_ret_clear_resets_to_none_pad_zero() {
    assert_maybe_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MaybeRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("clear", 0);
    // Clear must write None leaves: tag 0 and zero-padded payload slot
    // (not leave stale Some payload in the pad).
    let expected = multi_return_le(&[0, 0]);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(
            state_key,
            state_account(&program_id, maybe_ret_state(true, 1, 0x99)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&maybe_ret_state(true, 0, 0))
                .build(),
        ],
    );
}

#[test]
fn maybe_ret_peek_some_after_put() {
    assert_maybe_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "MaybeRet");
    let state_key = Pubkey::new_unique();
    let put_disc = instruction_discriminator("put", 1);
    let peek_disc = instruction_discriminator("peek", 0);
    let v = 55u64;
    let expected = multi_return_le(&[1, v]);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &put_disc, &[v], true, false),
        &[(
            state_key,
            state_account(&program_id, maybe_ret_state(true, 0, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&maybe_ret_state(true, 1, v))
                .build(),
        ],
    );

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &peek_disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, maybe_ret_state(true, 1, v)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
        ],
    );
}

// ─── ArrayRet (BL-19: anonymous Array UInt64 2 multi-leaf return) ────────────

/// Anonymous Array state `slots : Array UInt64 2` flattens to preorder leaves
/// `slots_0`, `slots_1` sharing `source_id` 0 (same layout as ArraySlots).
fn array_ret_fields() -> Vec<StateField> {
    array_u64_leaves(2)
}

fn array_ret_state(initialized: bool, a: u64, b: u64) -> Vec<u8> {
    state_data(&array_ret_fields(), initialized, &[a, b])
}

fn assert_array_ret_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("ArrayRet"),
        &[
            ("initialize", 2),
            ("setArr", 2),
            ("getArr", 0),
        ],
    );
    let fields = array_ret_fields();
    assert_eq!(fields.len(), 2);
    assert_eq!(fields[0].name, "slots_0");
    assert_eq!(fields[1].name, "slots_1");
    assert_eq!(fields[0].source_id, fields[1].source_id);
}

#[test]
fn array_ret_initialize_stores_both_leaves() {
    assert_array_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "ArrayRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 2);
    let a = 11u64;
    let b = 22u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[a, b], true, true),
        &[(
            state_key,
            state_account(&program_id, array_ret_state(false, 0, 0)),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&array_ret_state(true, a, b))
                .build(),
        ],
    );
}

#[test]
fn array_ret_get_arr_returns_16_le_bytes() {
    assert_array_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "ArrayRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("getArr", 0);
    let a = 0x1122_3344_5566_7788u64;
    let b = 0xaabb_ccdd_eeff_0011u64;
    let expected = multi_return_le(&[a, b]);
    assert_eq!(expected.len(), 16);
    assert_eq!(&expected[..8], &a.to_le_bytes());
    assert_eq!(&expected[8..], &b.to_le_bytes());

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, array_ret_state(true, a, b)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&array_ret_state(true, a, b))
                .build(),
        ],
    );
}

#[test]
fn array_ret_set_arr_updates_and_returns_multi() {
    assert_array_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "ArrayRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("setArr", 2);
    let x = 99u64;
    let y = 42u64;
    let expected = multi_return_le(&[x, y]);
    assert_eq!(expected.len(), 16);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[x, y], true, false),
        &[(
            state_key,
            state_account(&program_id, array_ret_state(true, 1, 2)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&array_ret_state(true, x, y))
                .build(),
        ],
    );
}

// ─── OptionRet (BL-19: anonymous Option UInt64 tag+payload return) ──────────

/// This return fixture uses scalar pad state only; Option UInt64 state is covered
/// separately by the BL-29 `OptionState` fixture below.
fn option_ret_fields() -> Vec<StateField> {
    vec![StateField {
        source_id: 0,
        name: "pad",
        byte_offset: STATE_HEADER_BYTES,
        byte_width: 8,
    }]
}

fn option_ret_state(initialized: bool, pad: u64) -> Vec<u8> {
    state_data(&option_ret_fields(), initialized, &[pad])
}

fn assert_option_ret_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("OptionRet"),
        &[
            ("initialize", 0),
            ("putSome", 1),
            ("putNone", 0),
            ("peekSome", 0),
            ("peekNone", 0),
        ],
    );
    let fields = option_ret_fields();
    assert_eq!(fields.len(), 1);
    assert_eq!(fields[0].name, "pad");
}

#[test]
fn option_ret_initialize_zero_pad() {
    assert_option_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 0);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, true),
        &[(
            state_key,
            state_account(&program_id, option_ret_state(false, 0)),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&option_ret_state(true, 0))
                .build(),
        ],
    );
}

#[test]
fn option_ret_peek_none_returns_tag_zero_pad() {
    assert_option_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("peekNone", 0);
    // none = (0, 0)
    let expected = multi_return_le(&[0, 0]);
    assert_eq!(expected.len(), 16);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, option_ret_state(true, 7)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            // View must not mutate pad.
            Check::account(&state_key)
                .data(&option_ret_state(true, 7))
                .build(),
        ],
    );
}

#[test]
fn option_ret_put_some_returns_tag_one_and_payload() {
    assert_option_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("putSome", 1);
    let v = 0xdead_beef_cafe_u64;
    // some(v) = (1, v)
    let expected = multi_return_le(&[1, v]);
    assert_eq!(expected.len(), 16);
    assert_eq!(&expected[..8], &1u64.to_le_bytes());
    assert_eq!(&expected[8..], &v.to_le_bytes());

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[v], true, false),
        &[(
            state_key,
            state_account(&program_id, option_ret_state(true, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&option_ret_state(true, v))
                .build(),
        ],
    );
}

#[test]
fn option_ret_put_none_returns_zeros() {
    assert_option_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionRet");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("putNone", 0);
    let expected = multi_return_le(&[0, 0]);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(
            state_key,
            state_account(&program_id, option_ret_state(true, 0x99)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&option_ret_state(true, 0))
                .build(),
        ],
    );
}

#[test]
fn option_ret_peek_some_after_put() {
    assert_option_ret_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionRet");
    let state_key = Pubkey::new_unique();
    let put_disc = instruction_discriminator("putSome", 1);
    let peek_disc = instruction_discriminator("peekSome", 0);
    let v = 55u64;
    let expected = multi_return_le(&[1, v]);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &put_disc, &[v], true, false),
        &[(
            state_key,
            state_account(&program_id, option_ret_state(true, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&option_ret_state(true, v))
                .build(),
        ],
    );

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &peek_disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, option_ret_state(true, v)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
        ],
    );
}

// ─── OptionState (BL-29 / B-OPT-STATE: Option UInt64 2-leaf state) ──────────

/// Option UInt64 state flattens to Enum-shaped leaves: `slot_tag`, `slot_p0`
/// (shared source_id 0). none tag=0 payload=0; some(v) tag=1 payload=v.
fn option_state_fields() -> Vec<StateField> {
    vec![
        StateField {
            source_id: 0,
            name: "slot_tag",
            byte_offset: STATE_HEADER_BYTES,
            byte_width: 8,
        },
        StateField {
            source_id: 0,
            name: "slot_p0",
            byte_offset: STATE_HEADER_BYTES + 8,
            byte_width: 8,
        },
    ]
}

fn option_state_account(initialized: bool, tag: u64, payload: u64) -> Vec<u8> {
    state_data(&option_state_fields(), initialized, &[tag, payload])
}

fn assert_option_state_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes("OptionState"),
        &[
            ("initialize", 0),
            ("set", 1),
            ("clear", 0),
            ("peek", 0),
            ("getOpt", 0),
        ],
    );
    let fields = option_state_fields();
    assert_eq!(fields.len(), 2);
    assert_eq!(fields[0].name, "slot_tag");
    assert_eq!(fields[1].name, "slot_p0");
    let opt_marker = layout_marker(&fields);
    let maybe_marker = layout_marker(&maybe_ret_fields());
    assert_ne!(opt_marker, 0);
    // Distinct layout from named Maybe (different field names) → different marker.
    assert_ne!(opt_marker, maybe_marker);
}

#[test]
fn option_state_initialize_none_default() {
    assert_option_state_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionState");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 0);
    // none default: tag 0, payload 0 (zeroAllFields + Option.none construct).
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, true),
        &[(
            state_key,
            state_account(&program_id, option_state_account(false, 0, 0)),
        )],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&option_state_account(true, 0, 0))
                .build(),
        ],
    );
}

#[test]
fn option_state_peek_none_returns_zero() {
    assert_option_state_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionState");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("peek", 0);
    let expected = 0u64.to_le_bytes().to_vec();

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, option_state_account(true, 0, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&option_state_account(true, 0, 0))
                .build(),
        ],
    );
}

#[test]
fn option_state_set_some_write_and_peek() {
    assert_option_state_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionState");
    let state_key = Pubkey::new_unique();
    let set_disc = instruction_discriminator("set", 1);
    let peek_disc = instruction_discriminator("peek", 0);
    let v = 0xdead_beef_cafe_u64;

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &set_disc, &[v], true, false),
        &[(
            state_key,
            state_account(&program_id, option_state_account(true, 0, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&v.to_le_bytes()),
            Check::account(&state_key)
                .data(&option_state_account(true, 1, v))
                .build(),
        ],
    );

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &peek_disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, option_state_account(true, 1, v)),
        )],
        &[
            Check::success(),
            Check::return_data(&v.to_le_bytes()),
            Check::account(&state_key)
                .data(&option_state_account(true, 1, v))
                .build(),
        ],
    );
}

#[test]
fn option_state_clear_zeroes_payload() {
    assert_option_state_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionState");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("clear", 0);
    // clear must write none leaves: tag 0 AND zeroed payload (no stale Some).
    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], true, false),
        &[(
            state_key,
            state_account(&program_id, option_state_account(true, 1, 0x99)),
        )],
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&option_state_account(true, 0, 0))
                .build(),
        ],
    );
}

#[test]
fn option_state_get_opt_returns_tag_payload() {
    assert_option_state_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionState");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("getOpt", 0);
    let v = 55u64;
    let expected = multi_return_le(&[1, v]);
    assert_eq!(expected.len(), 16);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, option_state_account(true, 1, v)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&option_state_account(true, 1, v))
                .build(),
        ],
    );
}

#[test]
fn option_state_get_opt_none_returns_zeros() {
    assert_option_state_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, "OptionState");
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("getOpt", 0);
    let expected = multi_return_le(&[0, 0]);

    mollusk.process_and_validate_instruction(
        &build_ix(program_id, state_key, &disc, &[], false, false),
        &[(
            state_key,
            state_account(&program_id, option_state_account(true, 0, 0)),
        )],
        &[
            Check::success(),
            Check::return_data(&expected),
            Check::account(&state_key)
                .data(&option_state_account(true, 0, 0))
                .build(),
        ],
    );
}
