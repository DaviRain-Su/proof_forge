//! SDK-independent current-program-tagged-v1 PDA goldens (#115 / ADR-0024 §6).
//!
//! The primary oracle implements seed validation, SHA-256, Ed25519 curve
//! rejection, and the pinned 255..1 bump search directly. Solana's Pubkey API
//! is used only as a second, compared oracle.

#[allow(dead_code)]
mod common;

use {
    common::*,
    curve25519_dalek::edwards::CompressedEdwardsY,
    sha2::{Digest, Sha256},
    solana_pubkey::Pubkey,
};

const PDA_MARKER: &[u8] = b"ProgramDerivedAddress";
const MAX_SEEDS: usize = 16;
const MAX_SEED_LEN: usize = 32;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PdaErr {
    TooManySeeds,
    SeedTooLong,
    OnCurve,
    NoCanonicalBump,
    NonCanonical,
}

fn independent_create_program_address(
    seeds: &[&[u8]],
    program_id: &Pubkey,
) -> Result<Pubkey, PdaErr> {
    if seeds.len() > MAX_SEEDS {
        return Err(PdaErr::TooManySeeds);
    }
    if seeds.iter().any(|seed| seed.len() > MAX_SEED_LEN) {
        return Err(PdaErr::SeedTooLong);
    }

    let mut hasher = Sha256::new();
    for seed in seeds {
        hasher.update(seed);
    }
    hasher.update(program_id.as_ref());
    hasher.update(PDA_MARKER);
    let hash: [u8; 32] = hasher.finalize().into();
    if CompressedEdwardsY(hash).decompress().is_some() {
        Err(PdaErr::OnCurve)
    } else {
        Ok(Pubkey::new_from_array(hash))
    }
}

fn independent_find(seeds: &[&[u8]], program_id: &Pubkey) -> Result<(Pubkey, u8), PdaErr> {
    if seeds.len() >= MAX_SEEDS {
        return Err(PdaErr::TooManySeeds);
    }
    if seeds.iter().any(|seed| seed.len() > MAX_SEED_LEN) {
        return Err(PdaErr::SeedTooLong);
    }
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let mut with_bump: Vec<&[u8]> = seeds.to_vec();
        with_bump.push(&bump_slice);
        match independent_create_program_address(&with_bump, program_id) {
            Ok(address) => return Ok((address, bump)),
            Err(PdaErr::OnCurve) => {}
            Err(error) => return Err(error),
        }
    }
    Err(PdaErr::NoCanonicalBump)
}

fn validate_canonical_pair(
    seeds: &[&[u8]],
    program_id: &Pubkey,
    supplied_address: &Pubkey,
    supplied_bump: u8,
) -> Result<(), PdaErr> {
    if supplied_bump == 0 {
        return Err(PdaErr::NonCanonical);
    }
    let (expected_address, expected_bump) = independent_find(seeds, program_id)?;
    if expected_address != *supplied_address || expected_bump != supplied_bump {
        Err(PdaErr::NonCanonical)
    } else {
        Ok(())
    }
}

#[test]
fn pda_marker_and_recipe_constants() {
    assert_eq!(
        hex::encode(PDA_MARKER),
        "50726f6772616d4465726976656441646472657373"
    );
    assert_eq!(HARNESS_PDA_SEED0, b"proof-forge:pda:v1");
    assert_eq!(
        hex::encode(HARNESS_PDA_SEED0),
        "70726f6f662d666f7267653a7064613a7631"
    );
}

#[test]
fn frozen_golden_matches_independent_and_sdk_oracles() {
    let program = harness_caller_id();
    let authority = Pubkey::new_from_array([0x11; 32]);
    let seed_tag = 7u64;
    let tag_le = seed_tag.to_le_bytes();
    let seeds: &[&[u8]] = &[HARNESS_PDA_SEED0, authority.as_ref(), &tag_le];

    let (independent_address, independent_bump) = independent_find(seeds, &program).unwrap();
    let (sdk_address, sdk_bump) = Pubkey::find_program_address(seeds, &program);
    assert_eq!(
        (independent_address, independent_bump),
        (sdk_address, sdk_bump)
    );

    // Hard-coded after the independent path was compared with pinned runtime.
    assert_eq!(independent_bump, 252);
    assert_eq!(
        hex::encode(independent_address.to_bytes()),
        "19555948c77ab11acee83d54f1cc470988f59a6313da9759b12d76ffff975f3b"
    );

    let (helper_address, helper_bump) =
        find_pda_current_program_tagged_v1(&program, &authority, seed_tag);
    assert_eq!(
        (helper_address, helper_bump),
        (independent_address, independent_bump)
    );
    assert!(
        validate_canonical_pair(seeds, &program, &independent_address, independent_bump).is_ok()
    );
}

#[test]
fn bump_zero_and_valid_noncanonical_pair_are_rejected() {
    let program = harness_caller_id();
    let authority = Pubkey::new_from_array([0x22; 32]);

    // Find a deterministic tag for which explicit bump 0 is itself off-curve.
    // The profile still rejects the otherwise valid pair because 0 is outside
    // the pinned canonical 255..1 search domain.
    let (tag, bump0_address) = (0u64..1024)
        .find_map(|tag| {
            let tag_le = tag.to_le_bytes();
            independent_create_program_address(
                &[HARNESS_PDA_SEED0, authority.as_ref(), &tag_le, &[0]],
                &program,
            )
            .ok()
            .map(|address| (tag, address))
        })
        .expect("an off-curve bump-0 candidate in bounded deterministic search");
    let tag_le = tag.to_le_bytes();
    let seeds: &[&[u8]] = &[HARNESS_PDA_SEED0, authority.as_ref(), &tag_le];
    assert_eq!(
        validate_canonical_pair(seeds, &program, &bump0_address, 0),
        Err(PdaErr::NonCanonical)
    );

    let (canonical_address, canonical_bump) = independent_find(seeds, &program).unwrap();
    let (other_address, other_bump) = (1u8..=255)
        .rev()
        .filter(|bump| *bump != canonical_bump)
        .find_map(|bump| {
            independent_create_program_address(
                &[HARNESS_PDA_SEED0, authority.as_ref(), &tag_le, &[bump]],
                &program,
            )
            .ok()
            .map(|address| (address, bump))
        })
        .expect("a valid noncanonical bump candidate");
    assert_ne!(
        (other_address, other_bump),
        (canonical_address, canonical_bump)
    );
    assert_eq!(
        validate_canonical_pair(seeds, &program, &other_address, other_bump),
        Err(PdaErr::NonCanonical)
    );
}

#[test]
fn wrong_seed_order_bytes_and_limits_fail_independently() {
    let program = harness_caller_id();
    let authority = Pubkey::new_from_array([0x33; 32]);
    let tag = 1u64.to_le_bytes();
    let (good, _) =
        independent_find(&[HARNESS_PDA_SEED0, authority.as_ref(), &tag], &program).unwrap();
    let (bad_order, _) =
        independent_find(&[authority.as_ref(), HARNESS_PDA_SEED0, &tag], &program).unwrap();
    let (bad_seed0, _) = independent_find(&[b"wrong", authority.as_ref(), &tag], &program).unwrap();
    assert_ne!(good, bad_order);
    assert_ne!(good, bad_seed0);

    let oversized = [0u8; 33];
    assert_eq!(
        independent_create_program_address(&[&oversized, &[255]], &program),
        Err(PdaErr::SeedTooLong)
    );
    let seed = [0u8; 1];
    let too_many: Vec<&[u8]> = std::iter::repeat(seed.as_slice()).take(17).collect();
    assert_eq!(
        independent_create_program_address(&too_many, &program),
        Err(PdaErr::TooManySeeds)
    );
}

#[test]
fn canonical_search_domain_is_exactly_255_through_1() {
    let domain: Vec<u8> = (1u8..=255).rev().collect();
    assert_eq!(domain.first(), Some(&255));
    assert_eq!(domain.last(), Some(&1));
    assert_eq!(domain.len(), 255);
    assert!(!domain.contains(&0));
}
