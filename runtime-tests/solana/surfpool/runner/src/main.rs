//! Surfpool RPC business smoke for MiniAmmAssets (engineering).
//!
//! Mirrors Mollusk `miniamm_assets` matrix against a live Surfnet:
//! initialize → addLiquidity → swap0to1 → slippage revert → removeLiquidity dual transfer.
//!
//! Env:
//! - SURFPOOL_RPC_URL
//! - SURFPOOL_PAYER_KEYPAIR / SURFPOOL_PROGRAM_KEYPAIR
//! MiniAmmAssets must already be deployed. Classic Token+ATA must exist
//! (Surfpool `SURFPOOL_NETWORK=mainnet` recommended).

use {
    sha2::{Digest, Sha256},
    solana_client::rpc_client::RpcClient,
    solana_sdk::{
        commitment_config::CommitmentConfig,
        instruction::{AccountMeta, Instruction},
        message::Message,
        pubkey::Pubkey,
        signature::{Keypair, Signer},
        system_instruction, system_program,
        transaction::Transaction,
    },
    spl_associated_token_account::{
        get_associated_token_address, instruction::create_associated_token_account_idempotent,
    },
    spl_token::instruction::{initialize_mint2, mint_to},
    std::{
        env, fs, str::FromStr, thread,
        time::{Duration, Instant},
    },
};

/// Classic SPL mint account size (82).
const MINT_LEN: usize = 82;

const OUTER_ROLE_COUNT: usize = 21;
const ROLE_STATE: usize = 0;
const ROLE_CALLER: usize = 1;
const STATE_HEADER_BYTES: usize = 8;
const SCALAR_COUNT: usize = 5;
const MAP_LEAF_COUNT: usize = 44;
const EXACT_DATA_LEN: usize = STATE_HEADER_BYTES + (SCALAR_COUNT + MAP_LEAF_COUNT) * 8;
const PRINCIPAL_LEAF_COUNT: usize = 9;
const VAULT_SEED0: &[u8] = b"proof-forge:vault:v1";
const DISCRIMINATOR_DOMAIN: &str = "proof-forge-solana-v1:";
const LAYOUT_DOMAIN: &str = "proof-forge-solana-layout-v1:";
const MINT_DECIMALS: u8 = 9;
/// Pinned by Mollusk suite for MiniAmmAssets field layout.
const EXPECTED_LAYOUT_MARKER_HEX: &str = "b8d352cbbfe6cd3b";

fn die(msg: impl AsRef<str>) -> ! {
    eprintln!("pf-surfpool-miniamm-business: FAIL: {}", msg.as_ref());
    std::process::exit(1);
}

fn info(msg: impl AsRef<str>) {
    eprintln!("pf-surfpool-miniamm-business: {}", msg.as_ref());
}

fn load_keypair(path: &str) -> Keypair {
    let bytes = fs::read(path).unwrap_or_else(|e| die(format!("read keypair {path}: {e}")));
    let arr = parse_keygen_json(&bytes).unwrap_or_else(|| die(format!("bad keypair json {path}")));
    Keypair::try_from(arr.as_slice()).unwrap_or_else(|e| die(format!("keypair decode {path}: {e}")))
}

fn parse_keygen_json(bytes: &[u8]) -> Option<Vec<u8>> {
    let s = std::str::from_utf8(bytes).ok()?.trim();
    let s = s.strip_prefix('[')?.strip_suffix(']')?;
    let mut out = Vec::new();
    for part in s.split(',') {
        let t = part.trim();
        if t.is_empty() {
            continue;
        }
        out.push(t.parse::<u8>().ok()?);
    }
    (out.len() == 64).then_some(out)
}

fn abi_param_type_string(byte_width: usize) -> &'static str {
    match byte_width {
        1 => "u8",
        2 => "u16",
        4 => "u32",
        8 => "u64",
        16 => "u128",
        32 => "u256",
        _ => die(format!("unsupported width {byte_width}")),
    }
}

fn disc_widths(name: &str, widths: &[usize]) -> String {
    let params = widths
        .iter()
        .map(|w| abi_param_type_string(*w))
        .collect::<Vec<_>>()
        .join(",");
    let preimage = format!("{DISCRIMINATOR_DOMAIN}{name}({params})");
    let digest = Sha256::digest(preimage.as_bytes());
    hex::encode(&digest)[..16].to_string()
}

fn disc(name: &str, param_count: usize) -> String {
    disc_widths(name, &vec![8usize; param_count])
}

fn instruction_data(disc_hex: &str, params: &[u64]) -> Vec<u8> {
    let raw = hex::decode(disc_hex).expect("disc hex");
    assert_eq!(raw.len(), 8);
    let mut data = raw;
    for p in params {
        data.extend_from_slice(&p.to_le_bytes());
    }
    data
}

fn layout_field_type_suffix(byte_width: usize) -> &'static str {
    match byte_width {
        8 => "u64-le",
        _ => die(format!("layout suffix width {byte_width}")),
    }
}

fn layout_marker_u64() -> u64 {
    let mut field_sigs: Vec<String> = Vec::new();
    let scalars = [
        ("reserve0", 0u64),
        ("reserve1", 1),
        ("totalSupply", 2),
        ("scratch", 3),
        ("scratch2", 4),
    ];
    for (i, (name, sid)) in scalars.iter().enumerate() {
        let off = STATE_HEADER_BYTES + i * 8;
        field_sigs.push(format!(
            "{sid}:{name}:0:{off}:8:{}",
            layout_field_type_suffix(8)
        ));
    }
    for i in 0..MAP_LEAF_COUNT {
        let off = STATE_HEADER_BYTES + (SCALAR_COUNT + i) * 8;
        field_sigs.push(format!(
            "5:balances_{i}:0:{off}:8:{}",
            layout_field_type_suffix(8)
        ));
    }
    let n = field_sigs.len();
    let layout_sig = format!("{}|{}", n, field_sigs.join("|"));
    let digest = Sha256::digest(format!("{LAYOUT_DOMAIN}{layout_sig}").as_bytes());
    let mut value: u64 = 0;
    for &b in &digest[..8] {
        value = (value << 8) | u64::from(b);
    }
    value
}

fn find_vault_pda(program_id: &Pubkey) -> (Pubkey, u8) {
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[VAULT_SEED0, &bump_slice];
        if let Ok(addr) = Pubkey::create_program_address(seeds, program_id) {
            return (addr, bump);
        }
    }
    die("no vault PDA bump");
}

fn wait_balance(rpc: &RpcClient, key: &Pubkey, min_lamports: u64) {
    let start = Instant::now();
    loop {
        if let Ok(bal) = rpc.get_balance(key) {
            if bal >= min_lamports {
                return;
            }
        }
        if start.elapsed() > Duration::from_secs(45) {
            die(format!("timeout waiting balance for {key}"));
        }
        thread::sleep(Duration::from_millis(250));
    }
}

fn send_tx_signers(rpc: &RpcClient, fee_payer: &Keypair, signers: &[&Keypair], ixs: Vec<Instruction>) {
    let bh = rpc
        .get_latest_blockhash()
        .unwrap_or_else(|e| die(format!("blockhash: {e}")));
    let msg = Message::new(&ixs, Some(&fee_payer.pubkey()));
    let mut tx = Transaction::new_unsigned(msg);
    let mut all: Vec<&Keypair> = Vec::with_capacity(1 + signers.len());
    all.push(fee_payer);
    for s in signers {
        if s.pubkey() != fee_payer.pubkey() {
            all.push(*s);
        }
    }
    tx.try_sign(&all, bh)
        .unwrap_or_else(|e| die(format!("sign: {e}")));
    match rpc.send_and_confirm_transaction(&tx) {
        Ok(sig) => info(format!("tx {sig}")),
        Err(e) => die(format!("send_and_confirm: {e}")),
    }
}

fn try_send_expect_fail(
    rpc: &RpcClient,
    fee_payer: &Keypair,
    signers: &[&Keypair],
    ixs: Vec<Instruction>,
) {
    let bh = rpc
        .get_latest_blockhash()
        .unwrap_or_else(|e| die(format!("blockhash: {e}")));
    let msg = Message::new(&ixs, Some(&fee_payer.pubkey()));
    let mut tx = Transaction::new_unsigned(msg);
    let mut all: Vec<&Keypair> = vec![fee_payer];
    for s in signers {
        if s.pubkey() != fee_payer.pubkey() {
            all.push(*s);
        }
    }
    tx.try_sign(&all, bh)
        .unwrap_or_else(|e| die(format!("sign: {e}")));
    match rpc.send_and_confirm_transaction(&tx) {
        Ok(sig) => die(format!("expected failure but succeeded: {sig}")),
        Err(e) => info(format!("expected fail ok: {e}")),
    }
}

fn ensure_funded(rpc: &RpcClient, payer: &Keypair, key: &Pubkey, lamports: u64) {
    if rpc.get_balance(key).unwrap_or(0) >= lamports {
        return;
    }
    send_tx_signers(
        rpc,
        payer,
        &[],
        vec![system_instruction::transfer(
            &payer.pubkey(),
            key,
            lamports.max(1_000_000),
        )],
    );
}

fn read_u64_le(data: &[u8], off: usize) -> u64 {
    u64::from_le_bytes(data[off..off + 8].try_into().unwrap())
}

fn token_amount(data: &[u8]) -> u64 {
    assert!(data.len() >= 72, "token account too short");
    u64::from_le_bytes(data[64..72].try_into().unwrap())
}

struct World {
    program_id: Pubkey,
    state: Keypair,
    /// Same as fee payer (signer for caller role).
    caller: Pubkey,
    mint0: Keypair,
    mint1: Keypair,
    to: Keypair,
    vault: Pubkey,
    vault_ata0: Pubkey,
    vault_ata1: Pubkey,
    dst_ata0: Pubkey,
    dst_ata1: Pubkey,
    token_program: Pubkey,
    ata_program: Pubkey,
    placeholders: Vec<Pubkey>,
}

impl World {
    fn role_key(&self, role: usize) -> Pubkey {
        match role {
            0 => self.state.pubkey(),
            1 => self.caller,
            4 => system_program::id(),
            5 => self.ata_program,
            6 => self.token_program,
            9 => self.vault,
            n => self.placeholders[n],
        }
    }

    fn base_metas(&self) -> Vec<AccountMeta> {
        (0..OUTER_ROLE_COUNT)
            .map(|i| {
                let k = self.role_key(i);
                if i == ROLE_STATE {
                    AccountMeta::new(k, false)
                } else if i == ROLE_CALLER {
                    AccountMeta::new(k, true)
                } else if matches!(i, 7 | 8 | 12 | 13 | 17 | 18 | 19 | 20) {
                    AccountMeta::new(k, false)
                } else {
                    AccountMeta::new_readonly(k, false)
                }
            })
            .collect()
    }

    fn set(metas: &mut [AccountMeta], role: usize, key: Pubkey, writable: bool, signer: bool) {
        metas[role] = if writable {
            AccountMeta::new(key, signer)
        } else {
            AccountMeta::new_readonly(key, signer)
        };
    }

    fn assert_distinct(metas: &[AccountMeta], label: &str) {
        for i in 0..metas.len() {
            for j in (i + 1)..metas.len() {
                if metas[i].pubkey == metas[j].pubkey {
                    die(format!("{label}: roles {i}/{j} share {}", metas[i].pubkey));
                }
            }
        }
    }

    fn metas_init(&self, state_signer: bool) -> Vec<AccountMeta> {
        let mut m = self.base_metas();
        m[ROLE_STATE] = AccountMeta::new(self.state.pubkey(), state_signer);
        m[ROLE_CALLER] = AccountMeta::new(self.caller, true);
        Self::assert_distinct(&m, "init");
        m
    }

    fn metas_swap0(&self) -> Vec<AccountMeta> {
        let mut m = self.base_metas();
        m[ROLE_STATE] = AccountMeta::new(self.state.pubkey(), false);
        m[ROLE_CALLER] = AccountMeta::new(self.caller, true);
        Self::set(&mut m, 2, self.mint1.pubkey(), false, false);
        Self::set(&mut m, 3, self.to.pubkey(), false, false);
        Self::set(&mut m, 7, self.vault_ata1, true, false);
        Self::set(&mut m, 8, self.dst_ata1, true, false);
        Self::set(&mut m, 9, self.vault, false, false);
        Self::assert_distinct(&m, "swap0");
        m
    }

    fn metas_remove(&self) -> Vec<AccountMeta> {
        let mut m = self.base_metas();
        m[ROLE_STATE] = AccountMeta::new(self.state.pubkey(), false);
        m[ROLE_CALLER] = AccountMeta::new(self.caller, true);
        Self::set(&mut m, 14, self.mint0.pubkey(), false, false);
        Self::set(&mut m, 15, self.mint1.pubkey(), false, false);
        Self::set(&mut m, 16, self.to.pubkey(), false, false);
        Self::set(&mut m, 17, self.vault_ata0, true, false);
        Self::set(&mut m, 18, self.dst_ata0, true, false);
        Self::set(&mut m, 19, self.vault_ata1, true, false);
        Self::set(&mut m, 20, self.dst_ata1, true, false);
        Self::set(&mut m, 9, self.vault, false, false);
        Self::assert_distinct(&m, "remove");
        m
    }
}

fn main() {
    let rpc_url = env::var("SURFPOOL_RPC_URL").unwrap_or_else(|_| {
        env::args()
            .nth(1)
            .unwrap_or_else(|| die("SURFPOOL_RPC_URL or argv[1] required"))
    });
    let payer_path =
        env::var("SURFPOOL_PAYER_KEYPAIR").unwrap_or_else(|_| die("SURFPOOL_PAYER_KEYPAIR"));
    let program_path =
        env::var("SURFPOOL_PROGRAM_KEYPAIR").unwrap_or_else(|_| die("SURFPOOL_PROGRAM_KEYPAIR"));

    let payer = load_keypair(&payer_path);
    let program_kp = load_keypair(&program_path);
    let program_id = program_kp.pubkey();

    info(format!("rpc={rpc_url}"));
    info(format!("payer={}", payer.pubkey()));
    info(format!("program_id={program_id}"));

    let rpc = RpcClient::new_with_commitment(rpc_url, CommitmentConfig::confirmed());
    let prog = rpc
        .get_account(&program_id)
        .unwrap_or_else(|e| die(format!("program not deployed: {e}")));
    if !prog.executable {
        die("program account not executable");
    }
    wait_balance(&rpc, &payer.pubkey(), 50_000_000);

    let token_program = Pubkey::from_str("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap();
    let ata_program = Pubkey::from_str("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL").unwrap();
    if rpc.get_account(&token_program).is_err() {
        die("classic Token missing — use SURFPOOL_NETWORK=mainnet fork");
    }
    if rpc.get_account(&ata_program).is_err() {
        die("classic ATA missing — use SURFPOOL_NETWORK=mainnet fork");
    }

    let marker = layout_marker_u64();
    let marker_hex = format!("{marker:016x}");
    info(format!("layout_marker={marker_hex}"));
    if marker_hex != EXPECTED_LAYOUT_MARKER_HEX {
        die(format!(
            "layout marker mismatch: got {marker_hex} want {EXPECTED_LAYOUT_MARKER_HEX}"
        ));
    }

    let (vault, _) = find_vault_pda(&program_id);
    info(format!("vault_pda={vault}"));
    ensure_funded(&rpc, &payer, &vault, 2_000_000);

    let state = Keypair::new();
    let mint0 = Keypair::new();
    let mint1 = Keypair::new();
    let to = Keypair::new();

    // Pairwise-distinct placeholders for unused multi-role slots.
    let mut placeholders: Vec<Pubkey> = (0..OUTER_ROLE_COUNT)
        .map(|i| {
            let mut b = [0u8; 32];
            b[0] = 0xA0;
            b[1] = i as u8;
            b[2] = 0x5A;
            b[3] = (i as u8).wrapping_mul(17);
            b[31] = 0xEE;
            Pubkey::new_from_array(b)
        })
        .collect();

    let mut reserved = vec![
        state.pubkey(),
        payer.pubkey(),
        system_program::id(),
        ata_program,
        token_program,
        vault,
        mint0.pubkey(),
        mint1.pubkey(),
        to.pubkey(),
    ];
    for ph in placeholders.iter_mut() {
        while reserved.contains(ph) {
            let mut b = ph.to_bytes();
            b[4] = b[4].wrapping_add(1);
            *ph = Pubkey::new_from_array(b);
        }
        reserved.push(*ph);
    }

    let vault_ata0 = get_associated_token_address(&vault, &mint0.pubkey());
    let vault_ata1 = get_associated_token_address(&vault, &mint1.pubkey());
    let dst_ata0 = get_associated_token_address(&to.pubkey(), &mint0.pubkey());
    let dst_ata1 = get_associated_token_address(&to.pubkey(), &mint1.pubkey());

    let world = World {
        program_id,
        state,
        caller: payer.pubkey(),
        mint0,
        mint1,
        to,
        vault,
        vault_ata0,
        vault_ata1,
        dst_ata0,
        dst_ata1,
        token_program,
        ata_program,
        placeholders,
    };

    let rent0 = rpc.get_minimum_balance_for_rent_exemption(0).unwrap_or(890_880);
    for i in 0..OUTER_ROLE_COUNT {
        if matches!(i, 0 | 1 | 4 | 5 | 6 | 9) {
            continue;
        }
        ensure_funded(&rpc, &payer, &world.placeholders[i], rent0);
    }
    ensure_funded(&rpc, &payer, &world.to.pubkey(), rent0);

    // State account owned by program.
    let state_rent = rpc
        .get_minimum_balance_for_rent_exemption(EXACT_DATA_LEN)
        .unwrap_or_else(|e| die(format!("state rent: {e}")));
    send_tx_signers(
        &rpc,
        &payer,
        &[&world.state],
        vec![system_instruction::create_account(
            &payer.pubkey(),
            &world.state.pubkey(),
            state_rent,
            EXACT_DATA_LEN as u64,
            &program_id,
        )],
    );
    info(format!("state={}", world.state.pubkey()));

    // Mints (authority = payer).
    let mint_rent = rpc
        .get_minimum_balance_for_rent_exemption(MINT_LEN)
        .unwrap_or_else(|e| die(format!("mint rent: {e}")));
    for mint in [&world.mint0, &world.mint1] {
        send_tx_signers(
            &rpc,
            &payer,
            &[mint],
            vec![
                system_instruction::create_account(
                    &payer.pubkey(),
                    &mint.pubkey(),
                    mint_rent,
                    MINT_LEN as u64,
                    &token_program,
                ),
                initialize_mint2(
                    &token_program,
                    &mint.pubkey(),
                    &payer.pubkey(),
                    None,
                    MINT_DECIMALS,
                )
                .unwrap_or_else(|e| die(format!("init_mint: {e}"))),
            ],
        );
    }

    // ATAs (idempotent).
    for (wallet, mint) in [
        (vault, world.mint0.pubkey()),
        (vault, world.mint1.pubkey()),
        (world.to.pubkey(), world.mint0.pubkey()),
        (world.to.pubkey(), world.mint1.pubkey()),
    ] {
        send_tx_signers(
            &rpc,
            &payer,
            &[],
            vec![create_associated_token_account_idempotent(
                &payer.pubkey(),
                &wallet,
                &mint,
                &token_program,
            )],
        );
    }

    let amount0 = 1000u64;
    let amount1 = 2000u64;
    send_tx_signers(
        &rpc,
        &payer,
        &[],
        vec![
            mint_to(
                &token_program,
                &world.mint0.pubkey(),
                &vault_ata0,
                &payer.pubkey(),
                &[],
                amount0,
            )
            .unwrap(),
            mint_to(
                &token_program,
                &world.mint1.pubkey(),
                &vault_ata1,
                &payer.pubkey(),
                &[],
                amount1,
            )
            .unwrap(),
        ],
    );

    // initialize
    let init_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc("initialize", 0), &[]),
        world.metas_init(true),
    );
    send_tx_signers(&rpc, &payer, &[&world.state], vec![init_ix]);
    let st = rpc
        .get_account_data(&world.state.pubkey())
        .unwrap_or_else(|e| die(format!("state: {e}")));
    assert_eq!(&st[..8], &marker.to_le_bytes());
    info("initialize ok");

    // addLiquidity
    let add_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc("addLiquidity", 2), &[amount0, amount1]),
        world.metas_init(false),
    );
    send_tx_signers(&rpc, &payer, &[], vec![add_ix]);
    let st = rpc.get_account_data(&world.state.pubkey()).unwrap();
    assert_eq!(read_u64_le(&st, 8), amount0);
    assert_eq!(read_u64_le(&st, 16), amount1);
    assert_eq!(read_u64_le(&st, 24), amount0);
    info("addLiquidity ok");

    // Pre-fund amountIn mint0
    let amount_in = 100u64;
    send_tx_signers(
        &rpc,
        &payer,
        &[],
        vec![mint_to(
            &token_program,
            &world.mint0.pubkey(),
            &vault_ata0,
            &payer.pubkey(),
            &[],
            amount_in,
        )
        .unwrap()],
    );
    let expected_out = amount_in * amount1 / (amount0 + amount_in);
    assert_eq!(expected_out, 181);

    // swap0to1
    let mut swap_leaves = vec![0u64; PRINCIPAL_LEAF_COUNT * 2 + 2];
    swap_leaves[PRINCIPAL_LEAF_COUNT * 2] = amount_in;
    swap_leaves[PRINCIPAL_LEAF_COUNT * 2 + 1] = expected_out;
    let swap_disc = disc_widths("swap0to1", &vec![8; PRINCIPAL_LEAF_COUNT * 2 + 2]);
    let swap_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&swap_disc, &swap_leaves),
        world.metas_swap0(),
    );
    send_tx_signers(&rpc, &payer, &[], vec![swap_ix]);
    let st = rpc.get_account_data(&world.state.pubkey()).unwrap();
    assert_eq!(read_u64_le(&st, 8), amount0 + amount_in);
    assert_eq!(read_u64_le(&st, 16), amount1 - expected_out);
    assert_eq!(
        token_amount(&rpc.get_account_data(&dst_ata1).unwrap()),
        expected_out
    );
    assert_eq!(
        token_amount(&rpc.get_account_data(&vault_ata1).unwrap()),
        amount1 - expected_out
    );
    info(format!("swap0to1 ok out={expected_out}"));

    // slippage
    let mut bad = swap_leaves.clone();
    bad[PRINCIPAL_LEAF_COUNT * 2 + 1] = expected_out + 1;
    let bad_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&swap_disc, &bad),
        world.metas_swap0(),
    );
    let before = rpc.get_account_data(&world.state.pubkey()).unwrap();
    try_send_expect_fail(&rpc, &payer, &[], vec![bad_ix]);
    let after = rpc.get_account_data(&world.state.pubkey()).unwrap();
    assert_eq!(before, after, "slippage state hold");
    info("slippage revert hold ok");

    // removeLiquidity
    let lp = 250u64;
    let r0 = amount0 + amount_in;
    let r1 = amount1 - expected_out;
    let total = amount0;
    let out0 = lp * r0 / total;
    let out1 = lp * r1 / total;
    let mut rem = vec![0u64; PRINCIPAL_LEAF_COUNT * 3 + 1];
    rem[PRINCIPAL_LEAF_COUNT * 3] = lp;
    let rem_disc = disc_widths("removeLiquidity", &vec![8; PRINCIPAL_LEAF_COUNT * 3 + 1]);
    let rem_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&rem_disc, &rem),
        world.metas_remove(),
    );
    send_tx_signers(&rpc, &payer, &[], vec![rem_ix]);
    let st = rpc.get_account_data(&world.state.pubkey()).unwrap();
    assert_eq!(read_u64_le(&st, 8), r0 - out0);
    assert_eq!(read_u64_le(&st, 16), r1 - out1);
    assert_eq!(read_u64_le(&st, 24), total - lp);
    assert_eq!(token_amount(&rpc.get_account_data(&dst_ata0).unwrap()), out0);
    assert_eq!(
        token_amount(&rpc.get_account_data(&dst_ata1).unwrap()),
        expected_out + out1
    );
    info(format!("removeLiquidity ok out0={out0} out1={out1}"));

    info("ok full business matrix on Surfpool");
    info("engineering only — not formal TASK-D5 / mainnet claim");
}
