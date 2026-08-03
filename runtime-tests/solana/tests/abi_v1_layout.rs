//! Independent ABIv1 virtual-image decoder and frozen CPI C-layout checks (#115).
//!
//! The fixture image is indexed by program-visible SBPF virtual offset. It
//! deliberately includes each direct-mapped account's 10,240-byte virtual
//! growth span; no host backing-buffer pitch is assumed.

#[allow(dead_code)]
mod common;

use {
    common::*,
    std::mem::{align_of, offset_of, size_of},
};

const VM_BASE: u64 = 0x4000_0000_0;

#[derive(Clone, Debug)]
struct RoleSpec {
    is_signer: bool,
    is_writable: bool,
    executable: bool,
    data_len: usize,
}

#[derive(Clone, Debug)]
struct EncodedFixture {
    bytes: Vec<u8>,
    marker_offsets: Vec<usize>,
    rent_offsets: Vec<usize>,
    program_padding: std::ops::Range<usize>,
    pointer_table_offset: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct WalkOk {
    marker_vms: Vec<u64>,
    ix_data_vm: u64,
    program_id_vm: u64,
    pointer_table_vm: u64,
    end_vm: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WalkErr {
    Cap,
    Marker,
    DuplicateMarker,
    Bool,
    OriginalDataLen,
    RentEpoch,
    Padding,
    PointerTable,
    Truncation,
    Overflow,
    Trailing,
}

fn role(data_len: usize) -> RoleSpec {
    RoleSpec {
        is_signer: false,
        is_writable: true,
        executable: false,
        data_len,
    }
}

fn prog(data_len: usize) -> RoleSpec {
    RoleSpec {
        is_signer: false,
        is_writable: false,
        executable: true,
        data_len,
    }
}

fn align_up_checked(value: usize, align: usize) -> Result<usize, WalkErr> {
    let rem = value % align;
    if rem == 0 {
        Ok(value)
    } else {
        value.checked_add(align - rem).ok_or(WalkErr::Overflow)
    }
}

fn vm(offset: usize) -> Result<u64, WalkErr> {
    VM_BASE
        .checked_add(u64::try_from(offset).map_err(|_| WalkErr::Overflow)?)
        .ok_or(WalkErr::Overflow)
}

fn require(bytes: &[u8], offset: usize, len: usize) -> Result<(), WalkErr> {
    let end = offset.checked_add(len).ok_or(WalkErr::Overflow)?;
    if end > bytes.len() {
        Err(WalkErr::Truncation)
    } else {
        Ok(())
    }
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, WalkErr> {
    require(bytes, offset, 4)?;
    Ok(u32::from_le_bytes(
        bytes[offset..offset + 4].try_into().unwrap(),
    ))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, WalkErr> {
    require(bytes, offset, 8)?;
    Ok(u64::from_le_bytes(
        bytes[offset..offset + 8].try_into().unwrap(),
    ))
}

fn push_zeros(bytes: &mut Vec<u8>, count: usize) {
    bytes.resize(bytes.len().checked_add(count).expect("fixture size"), 0);
}

fn encode_fixture(roles: &[RoleSpec], ix_data: &[u8]) -> EncodedFixture {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(roles.len() as u64).to_le_bytes());
    let mut marker_offsets = Vec::with_capacity(roles.len());
    let mut rent_offsets = Vec::with_capacity(roles.len());

    for (index, role) in roles.iter().enumerate() {
        let marker = bytes.len();
        marker_offsets.push(marker);
        bytes.push(ABI_V1_MARKER);
        bytes.push(u8::from(role.is_signer));
        bytes.push(u8::from(role.is_writable));
        bytes.push(u8::from(role.executable));
        bytes.extend_from_slice(&0u32.to_le_bytes());
        bytes.extend_from_slice(&[0x10 + index as u8; 32]);
        bytes.extend_from_slice(&[0x80 + index as u8; 32]);
        bytes.extend_from_slice(&(1000u64 + index as u64).to_le_bytes());
        bytes.extend_from_slice(&(role.data_len as u64).to_le_bytes());
        assert_eq!(bytes.len() - marker, ABI_V1_FULL_PREFIX);

        bytes.extend(std::iter::repeat(0xa0 + index as u8).take(role.data_len));
        push_zeros(&mut bytes, ABI_V1_MAX_DATA_INCREASE);
        let aligned = align_up_checked(bytes.len(), ABI_V1_ALIGN).unwrap();
        bytes.resize(aligned, 0);
        rent_offsets.push(bytes.len());
        bytes.extend_from_slice(&u64::MAX.to_le_bytes());
    }

    bytes.extend_from_slice(&(ix_data.len() as u64).to_le_bytes());
    bytes.extend_from_slice(ix_data);
    bytes.extend_from_slice(&[0x42; 32]);
    let pad_start = bytes.len();
    let padded = align_up_checked(pad_start, ABI_V1_ALIGN).unwrap();
    bytes.resize(padded, 0);
    let program_padding = pad_start..padded;
    let pointer_table_offset = bytes.len();
    for marker in &marker_offsets {
        bytes.extend_from_slice(&vm(*marker).unwrap().to_le_bytes());
    }

    EncodedFixture {
        bytes,
        marker_offsets,
        rent_offsets,
        program_padding,
        pointer_table_offset,
    }
}

/// Decode and validate an exact program-visible ABIv1 virtual image.
fn decode_abiv1(bytes: &[u8], max_roles: usize) -> Result<WalkOk, WalkErr> {
    let num_accounts_u64 = read_u64(bytes, 0)?;
    let num_accounts = usize::try_from(num_accounts_u64).map_err(|_| WalkErr::Overflow)?;
    if num_accounts > max_roles {
        return Err(WalkErr::Cap);
    }

    let mut cursor = 8usize;
    let mut markers = Vec::with_capacity(num_accounts);
    for role_index in 0..num_accounts {
        require(bytes, cursor, ABI_V1_FULL_PREFIX)?;
        let marker = cursor;
        let marker_byte = bytes[marker];
        if marker_byte != ABI_V1_MARKER {
            return if usize::from(marker_byte) < role_index {
                Err(WalkErr::DuplicateMarker)
            } else {
                Err(WalkErr::Marker)
            };
        }
        if bytes[marker + 1] > 1 || bytes[marker + 2] > 1 || bytes[marker + 3] > 1 {
            return Err(WalkErr::Bool);
        }
        if read_u32(bytes, marker + 4)? != 0 {
            return Err(WalkErr::OriginalDataLen);
        }
        markers.push(vm(marker)?);

        let data_len_u64 = read_u64(bytes, marker + 80)?;
        let data_len = usize::try_from(data_len_u64).map_err(|_| WalkErr::Overflow)?;
        let data_start = marker
            .checked_add(ABI_V1_FULL_PREFIX)
            .ok_or(WalkErr::Overflow)?;
        let after_data = data_start.checked_add(data_len).ok_or(WalkErr::Overflow)?;
        let after_growth = after_data
            .checked_add(ABI_V1_MAX_DATA_INCREASE)
            .ok_or(WalkErr::Overflow)?;
        let rent = align_up_checked(after_growth, ABI_V1_ALIGN)?;
        if read_u64(bytes, rent)? != u64::MAX {
            return Err(WalkErr::RentEpoch);
        }
        cursor = rent.checked_add(8).ok_or(WalkErr::Overflow)?;
    }

    let ix_data_len_u64 = read_u64(bytes, cursor)?;
    let ix_data_len = usize::try_from(ix_data_len_u64).map_err(|_| WalkErr::Overflow)?;
    cursor = cursor.checked_add(8).ok_or(WalkErr::Overflow)?;
    let ix_data_offset = cursor;
    require(bytes, cursor, ix_data_len)?;
    cursor = cursor.checked_add(ix_data_len).ok_or(WalkErr::Overflow)?;

    let program_id_offset = cursor;
    require(bytes, program_id_offset, 32)?;
    cursor = cursor.checked_add(32).ok_or(WalkErr::Overflow)?;
    let padded = align_up_checked(cursor, ABI_V1_ALIGN)?;
    require(bytes, cursor, padded - cursor)?;
    if bytes[cursor..padded].iter().any(|byte| *byte != 0) {
        return Err(WalkErr::Padding);
    }
    cursor = padded;
    let pointer_table_offset = cursor;

    for expected_marker in &markers {
        if read_u64(bytes, cursor)? != *expected_marker {
            return Err(WalkErr::PointerTable);
        }
        cursor = cursor.checked_add(8).ok_or(WalkErr::Overflow)?;
    }
    if cursor != bytes.len() {
        return Err(WalkErr::Trailing);
    }

    Ok(WalkOk {
        marker_vms: markers,
        ix_data_vm: vm(ix_data_offset)?,
        program_id_vm: vm(program_id_offset)?,
        pointer_table_vm: vm(pointer_table_offset)?,
        end_vm: vm(cursor)?,
    })
}

#[test]
fn abi_v1_exact_zero_one_sixteen_and_seventeen() {
    let zero = encode_fixture(&[], &[]);
    let ok = decode_abiv1(&zero.bytes, SOLANA_CPI_MAX_OUTER_ROLES).unwrap();
    assert!(ok.marker_vms.is_empty());
    assert_eq!(ok.ix_data_vm, VM_BASE + 16);
    assert_eq!(ok.program_id_vm, VM_BASE + 16);
    assert_eq!(ok.pointer_table_vm, VM_BASE + 48);
    assert_eq!(ok.end_vm, VM_BASE + 48);

    let one = encode_fixture(&[role(0)], &[0; 9]);
    let ok = decode_abiv1(&one.bytes, SOLANA_CPI_MAX_OUTER_ROLES).unwrap();
    assert_eq!(ok.marker_vms, vec![VM_BASE + 8]);
    assert_eq!(ok.ix_data_vm, VM_BASE + 10_352);

    let roles16: Vec<RoleSpec> = (0..16).map(|_| role(0)).collect();
    let sixteen = encode_fixture(&roles16, &[]);
    assert!(decode_abiv1(&sixteen.bytes, SOLANA_CPI_MAX_OUTER_ROLES).is_ok());

    let roles17: Vec<RoleSpec> = (0..17).map(|_| role(0)).collect();
    let seventeen = encode_fixture(&roles17, &[]);
    assert_eq!(
        decode_abiv1(&seventeen.bytes, SOLANA_CPI_MAX_OUTER_ROLES),
        Err(WalkErr::Cap)
    );
}

#[test]
fn abi_v1_exact_two_role_harness_offsets() {
    let fixture = encode_fixture(&[role(8), prog(36)], &[0; 9]);
    let ok = decode_abiv1(&fixture.bytes, SOLANA_CPI_MAX_OUTER_ROLES).unwrap();
    assert_eq!(fixture.marker_offsets, vec![8, 10_352]);
    assert_eq!(ok.marker_vms, vec![VM_BASE + 8, VM_BASE + 10_352]);
    assert_eq!(ok.ix_data_vm, VM_BASE + 20_736);
    assert_eq!(ok.program_id_vm, VM_BASE + 20_745);
    assert_eq!(ok.pointer_table_vm, VM_BASE + 20_784);
    assert_eq!(ok.end_vm, VM_BASE + 20_800);
}

#[test]
fn abi_v1_rejects_full_duplicate_marker_and_non_bool_flags() {
    let fixture = encode_fixture(&[role(8), prog(36)], &[0; 9]);

    let mut bad = fixture.bytes.clone();
    bad[fixture.marker_offsets[0]] = 0xfe;
    assert_eq!(decode_abiv1(&bad, 16), Err(WalkErr::Marker));

    let mut duplicate = fixture.bytes.clone();
    duplicate[fixture.marker_offsets[1]] = 0;
    assert_eq!(decode_abiv1(&duplicate, 16), Err(WalkErr::DuplicateMarker));

    for flag_offset in 1..=3 {
        let mut non_bool = fixture.bytes.clone();
        non_bool[fixture.marker_offsets[0] + flag_offset] = 2;
        assert_eq!(decode_abiv1(&non_bool, 16), Err(WalkErr::Bool));
    }
}

#[test]
fn abi_v1_rejects_origlen_rent_padding_pointer_and_trailing() {
    let fixture = encode_fixture(&[role(8), prog(36)], &[0; 9]);

    let mut bad_orig = fixture.bytes.clone();
    bad_orig[fixture.marker_offsets[0] + 4] = 1;
    assert_eq!(decode_abiv1(&bad_orig, 16), Err(WalkErr::OriginalDataLen));

    let mut bad_rent = fixture.bytes.clone();
    bad_rent[fixture.rent_offsets[1]] = 0;
    assert_eq!(decode_abiv1(&bad_rent, 16), Err(WalkErr::RentEpoch));

    assert!(!fixture.program_padding.is_empty());
    let mut bad_padding = fixture.bytes.clone();
    bad_padding[fixture.program_padding.start] = 1;
    assert_eq!(decode_abiv1(&bad_padding, 16), Err(WalkErr::Padding));

    let mut bad_pointer = fixture.bytes.clone();
    bad_pointer[fixture.pointer_table_offset] ^= 1;
    assert_eq!(decode_abiv1(&bad_pointer, 16), Err(WalkErr::PointerTable));

    let mut trailing = fixture.bytes.clone();
    trailing.push(0);
    assert_eq!(decode_abiv1(&trailing, 16), Err(WalkErr::Trailing));
}

#[test]
fn abi_v1_rejects_short_truncated_and_overflow() {
    let fixture = encode_fixture(&[role(8), prog(36)], &[0; 9]);
    for cut in [
        0usize,
        7,
        fixture.marker_offsets[0] + ABI_V1_FULL_PREFIX - 1,
        fixture.rent_offsets[0] + 7,
        fixture.pointer_table_offset + 15,
    ] {
        assert_eq!(
            decode_abiv1(&fixture.bytes[..cut], 16),
            Err(WalkErr::Truncation),
            "cut={cut}"
        );
    }

    let mut overflow = fixture.bytes.clone();
    let data_len = fixture.marker_offsets[0] + 80;
    overflow[data_len..data_len + 8].copy_from_slice(&u64::MAX.to_le_bytes());
    assert_eq!(decode_abiv1(&overflow, 16), Err(WalkErr::Overflow));
}

#[repr(C)]
struct SolInstructionC {
    program_id_addr: u64,
    accounts_addr: u64,
    accounts_len: u64,
    data_addr: u64,
    data_len: u64,
}

#[repr(C)]
struct SolAccountMetaC {
    pubkey_addr: u64,
    is_writable: u8,
    is_signer: u8,
    padding: [u8; 6],
}

#[repr(C)]
struct SolAccountInfoC {
    key_addr: u64,
    lamports_addr: u64,
    data_len: u64,
    data_addr: u64,
    owner_addr: u64,
    rent_epoch: u64,
    is_signer: u8,
    is_writable: u8,
    executable: u8,
    padding: [u8; 5],
}

#[repr(C)]
struct SolSignerSeedC {
    addr: u64,
    len: u64,
}

#[repr(C)]
struct SolSignerSeedsC {
    addr: u64,
    len: u64,
}

#[test]
fn frozen_cpi_c_struct_sizes_alignments_and_offsets() {
    assert_eq!(
        (size_of::<SolInstructionC>(), align_of::<SolInstructionC>()),
        (40, 8)
    );
    assert_eq!(offset_of!(SolInstructionC, program_id_addr), 0);
    assert_eq!(offset_of!(SolInstructionC, accounts_addr), 8);
    assert_eq!(offset_of!(SolInstructionC, accounts_len), 16);
    assert_eq!(offset_of!(SolInstructionC, data_addr), 24);
    assert_eq!(offset_of!(SolInstructionC, data_len), 32);

    assert_eq!(
        (size_of::<SolAccountMetaC>(), align_of::<SolAccountMetaC>()),
        (16, 8)
    );
    assert_eq!(offset_of!(SolAccountMetaC, pubkey_addr), 0);
    assert_eq!(offset_of!(SolAccountMetaC, is_writable), 8);
    assert_eq!(offset_of!(SolAccountMetaC, is_signer), 9);
    assert_eq!(offset_of!(SolAccountMetaC, padding), 10);

    assert_eq!(
        (size_of::<SolAccountInfoC>(), align_of::<SolAccountInfoC>()),
        (56, 8)
    );
    assert_eq!(offset_of!(SolAccountInfoC, key_addr), 0);
    assert_eq!(offset_of!(SolAccountInfoC, lamports_addr), 8);
    assert_eq!(offset_of!(SolAccountInfoC, data_len), 16);
    assert_eq!(offset_of!(SolAccountInfoC, data_addr), 24);
    assert_eq!(offset_of!(SolAccountInfoC, owner_addr), 32);
    assert_eq!(offset_of!(SolAccountInfoC, rent_epoch), 40);
    assert_eq!(offset_of!(SolAccountInfoC, is_signer), 48);
    assert_eq!(offset_of!(SolAccountInfoC, is_writable), 49);
    assert_eq!(offset_of!(SolAccountInfoC, executable), 50);
    assert_eq!(offset_of!(SolAccountInfoC, padding), 51);

    assert_eq!(
        (size_of::<SolSignerSeedC>(), align_of::<SolSignerSeedC>()),
        (16, 8)
    );
    assert_eq!(offset_of!(SolSignerSeedC, addr), 0);
    assert_eq!(offset_of!(SolSignerSeedC, len), 8);
    assert_eq!(
        (size_of::<SolSignerSeedsC>(), align_of::<SolSignerSeedsC>()),
        (16, 8)
    );
    assert_eq!(offset_of!(SolSignerSeedsC, addr), 0);
    assert_eq!(offset_of!(SolSignerSeedsC, len), 8);
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CapErr {
    OuterRoles,
    Metas,
    SignerGroups,
    SeedSlices,
    SeedBytes,
}

fn validate_product_caps(
    outer_roles: usize,
    metas: usize,
    signer_groups: &[Vec<Vec<u8>>],
) -> Result<(), CapErr> {
    if outer_roles > SOLANA_CPI_MAX_OUTER_ROLES {
        return Err(CapErr::OuterRoles);
    }
    if metas > SOLANA_CPI_MAX_METAS {
        return Err(CapErr::Metas);
    }
    if signer_groups.len() > SOLANA_CPI_MAX_SIGNER_GROUPS {
        return Err(CapErr::SignerGroups);
    }
    for group in signer_groups {
        if group.len() > SOLANA_CPI_MAX_SEED_SLICES {
            return Err(CapErr::SeedSlices);
        }
        if group
            .iter()
            .any(|seed| seed.len() > SOLANA_CPI_MAX_BYTES_PER_SEED)
        {
            return Err(CapErr::SeedBytes);
        }
    }
    Ok(())
}

#[test]
fn product_caps_execute_one_below_equal_and_one_above() {
    for outer in [15usize, 16] {
        assert!(validate_product_caps(outer, 0, &[]).is_ok());
    }
    assert_eq!(validate_product_caps(17, 0, &[]), Err(CapErr::OuterRoles));

    for metas in [15usize, 16] {
        assert!(validate_product_caps(0, metas, &[]).is_ok());
    }
    assert_eq!(validate_product_caps(0, 17, &[]), Err(CapErr::Metas));

    for groups in [3usize, 4] {
        assert!(validate_product_caps(0, 0, &vec![Vec::new(); groups]).is_ok());
    }
    assert_eq!(
        validate_product_caps(0, 0, &vec![Vec::new(); 5]),
        Err(CapErr::SignerGroups)
    );

    for slices in [15usize, 16] {
        assert!(validate_product_caps(0, 0, &[vec![Vec::new(); slices]]).is_ok());
    }
    assert_eq!(
        validate_product_caps(0, 0, &[vec![Vec::new(); 17]]),
        Err(CapErr::SeedSlices)
    );

    for bytes in [31usize, 32] {
        assert!(validate_product_caps(0, 0, &[vec![vec![0; bytes]]]).is_ok());
    }
    assert_eq!(
        validate_product_caps(0, 0, &[vec![vec![0; 33]]]),
        Err(CapErr::SeedBytes)
    );
}
