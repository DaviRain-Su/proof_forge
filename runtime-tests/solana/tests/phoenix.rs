mod common;

use {
    common::{harness, instruction, plain_account, slot, state_account},
    mollusk_svm::{result::Check, Mollusk},
    mollusk_svm_programs_token::token,
    solana_account::Account,
    solana_instruction::AccountMeta,
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    solana_svm_log_collector::LogCollector,
    spl_token_interface::state::{Account as TokenAccount, AccountState, Mint},
};

const SELF_TRADE: u32 = 0x1004;
const UNAUTHORIZED: u32 = 0x1002;
const STATE_LEN: usize = 1896;
const DECIMALS: u8 = 6;
const INITIAL_TOKENS: u64 = 1_000;
const ASK_BOOK: usize = 54;
const BID_BOOK: usize = 78;

struct TraderAccounts {
    key: Pubkey,
    base_key: Pubkey,
    base: Account,
    quote_key: Pubkey,
    quote: Account,
}

impl TraderAccounts {
    fn new(base_mint: Pubkey, quote_mint: Pubkey) -> Self {
        let key = Pubkey::new_unique();
        Self {
            key,
            base_key: Pubkey::new_unique(),
            base: token_account(base_mint, key, INITIAL_TOKENS),
            quote_key: Pubkey::new_unique(),
            quote: token_account(quote_mint, key, INITIAL_TOKENS),
        }
    }
}

struct PhoenixFixture {
    program_id: Pubkey,
    self_program: Account,
    log_key: Pubkey,
    log: Account,
    mollusk: Mollusk,
    state_key: Pubkey,
    state: Account,
    base_mint_key: Pubkey,
    base_mint: Account,
    quote_mint_key: Pubkey,
    quote_mint: Account,
    base_vault_key: Pubkey,
    base_vault: Account,
    quote_vault_key: Pubkey,
    quote_vault: Account,
    token_program_key: Pubkey,
    token_program: Account,
}

fn mint_account(authority: Pubkey) -> Account {
    token::create_account_for_mint(Mint {
        mint_authority: Some(authority).into(),
        supply: 10_000_000,
        decimals: DECIMALS,
        is_initialized: true,
        freeze_authority: None.into(),
    })
}

fn token_account(mint: Pubkey, owner: Pubkey, amount: u64) -> Account {
    token::create_account_for_token_account(TokenAccount {
        mint,
        owner,
        amount,
        delegate: None.into(),
        state: AccountState::Initialized,
        is_native: None.into(),
        delegated_amount: 0,
        close_authority: None.into(),
    })
}

fn token_amount(account: &Account) -> u64 {
    u64::from_le_bytes(
        account.data[64..72]
            .try_into()
            .expect("SPL Token account amount"),
    )
}

fn account_after(accounts: &[(Pubkey, Account)], key: &Pubkey) -> Account {
    accounts
        .iter()
        .find(|(actual, _)| actual == key)
        .unwrap_or_else(|| panic!("missing resulting account {key}"))
        .1
        .clone()
}

fn has_phoenix_record(messages: &[String], origin: u8) -> bool {
    const BASE64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let prefix = format!(
        "Program data: Dw{}{}",
        BASE64[4 + usize::from(origin >> 6)] as char,
        BASE64[usize::from(origin & 63)] as char
    );
    messages.iter().any(|message| message.starts_with(&prefix))
}

fn phoenix_origin(name: &str) -> u8 {
    match name {
        "swapBuy" | "swapSell" => 0,
        "postAsk" | "postBid" => 3,
        "reduceAsk" | "reduceBid" => 5,
        "withdrawBase" | "withdrawQuote" => 12,
        "depositFunds" => 13,
        "evictSeat" => 106,
        "collectFees" => 108,
        _ => panic!("missing Phoenix origin for {name}"),
    }
}

fn assert_atomic_failure(
    result: &mollusk_svm::result::InstructionResult,
    snapshots: &[(Pubkey, Vec<u8>)],
) {
    assert!(
        result.raw_result.is_err(),
        "instruction unexpectedly succeeded"
    );
    for (key, before) in snapshots {
        assert_eq!(
            &account_after(&result.resulting_accounts, key).data,
            before,
            "failed instruction mutated {key}"
        );
    }
}

impl PhoenixFixture {
    fn new(tick_size: u64) -> Self {
        let (program_id, mut mollusk) = harness("Phoenix", "PF_PHOENIX_SO");
        mollusk.logger = Some(LogCollector::new_ref_with_limit(None));
        token::add_program(&mut mollusk);

        let self_program = mollusk_svm::program::create_program_account_loader_v3(&program_id);
        let (log_key, _) = Pubkey::find_program_address(&[b"log"], &program_id);
        let log = plain_account();
        let state_key = Pubkey::new_unique();
        let base_mint_key = Pubkey::new_unique();
        let quote_mint_key = Pubkey::new_unique();
        let mint_authority = Pubkey::new_unique();
        let base_mint = mint_account(mint_authority);
        let quote_mint = mint_account(mint_authority);
        let (base_vault_key, _) = Pubkey::find_program_address(
            &[b"vault", state_key.as_ref(), base_mint_key.as_ref()],
            &program_id,
        );
        let (quote_vault_key, _) = Pubkey::find_program_address(
            &[b"vault", state_key.as_ref(), quote_mint_key.as_ref()],
            &program_id,
        );
        let base_vault = token_account(base_mint_key, base_vault_key, 0);
        let quote_vault = token_account(quote_mint_key, quote_vault_key, 0);
        let (token_program_key, token_program) = token::keyed_account();
        let bootstrap = TraderAccounts::new(base_mint_key, quote_mint_key);

        let init = instruction(
            program_id,
            state_key,
            "initialize",
            &[tick_size],
            true,
            true,
            Self::metas_for(
                &bootstrap,
                base_mint_key,
                quote_mint_key,
                base_vault_key,
                quote_vault_key,
                token_program_key,
                program_id,
                log_key,
                true,
            ),
        );
        let init_accounts = vec![
            (state_key, state_account(&program_id, STATE_LEN)),
            (bootstrap.key, plain_account()),
            (bootstrap.base_key, bootstrap.base),
            (bootstrap.quote_key, bootstrap.quote),
            (base_mint_key, base_mint.clone()),
            (quote_mint_key, quote_mint.clone()),
            (base_vault_key, base_vault.clone()),
            (quote_vault_key, quote_vault.clone()),
            (token_program_key, token_program.clone()),
            (program_id, self_program.clone()),
            (log_key, log.clone()),
        ];
        let initialized =
            mollusk.process_and_validate_instruction(&init, &init_accounts, &[Check::success()]);
        {
            let logger = mollusk
                .logger
                .as_ref()
                .expect("Phoenix log collector")
                .borrow();
            assert!(
                has_phoenix_record(logger.get_recorded_content(), 100),
                "initialize did not publish Phoenix data: {:?}",
                logger.get_recorded_content()
            );
        }
        let state = account_after(&initialized.resulting_accounts, &state_key);
        assert_eq!((slot(&state, 0), slot(&state, 1)), (1, tick_size));
        assert_eq!((slot(&state, 2), slot(&state, 3)), (1, 5));
        assert_eq!(
            (
                slot(&state, ASK_BOOK),
                slot(&state, ASK_BOOK + 1),
                slot(&state, ASK_BOOK + 2),
                slot(&state, ASK_BOOK + 3),
            ),
            (0, 0, 1, 1),
            "empty ask allocator state"
        );
        assert_eq!(
            (
                slot(&state, BID_BOOK),
                slot(&state, BID_BOOK + 1),
                slot(&state, BID_BOOK + 2),
                slot(&state, BID_BOOK + 3),
            ),
            (0, 0, 1, 1),
            "empty bid allocator state"
        );
        assert_eq!(
            (slot(&state, 102), slot(&state, 103), slot(&state, 104)),
            (0, 1, 1),
            "empty trader allocator state"
        );

        Self {
            program_id,
            self_program,
            log_key,
            log,
            mollusk,
            state_key,
            state,
            base_mint_key,
            base_mint,
            quote_mint_key,
            quote_mint,
            base_vault_key,
            base_vault,
            quote_vault_key,
            quote_vault,
            token_program_key,
            token_program,
        }
    }

    fn trader(&self) -> TraderAccounts {
        TraderAccounts::new(self.base_mint_key, self.quote_mint_key)
    }

    fn metas_for(
        trader: &TraderAccounts,
        base_mint: Pubkey,
        quote_mint: Pubkey,
        base_vault: Pubkey,
        quote_vault: Pubkey,
        token_program: Pubkey,
        self_program: Pubkey,
        log: Pubkey,
        trader_signer: bool,
    ) -> Vec<AccountMeta> {
        vec![
            AccountMeta::new_readonly(trader.key, trader_signer),
            AccountMeta::new(trader.base_key, false),
            AccountMeta::new(trader.quote_key, false),
            AccountMeta::new_readonly(base_mint, false),
            AccountMeta::new_readonly(quote_mint, false),
            AccountMeta::new(base_vault, false),
            AccountMeta::new(quote_vault, false),
            AccountMeta::new_readonly(token_program, false),
            AccountMeta::new_readonly(self_program, false),
            AccountMeta::new_readonly(log, false),
        ]
    }

    fn invocation(
        &self,
        trader: &TraderAccounts,
        name: &str,
        params: &[u64],
        trader_signer: bool,
        state: Account,
    ) -> (solana_instruction::Instruction, Vec<(Pubkey, Account)>) {
        let ix = instruction(
            self.program_id,
            self.state_key,
            name,
            params,
            true,
            true,
            Self::metas_for(
                trader,
                self.base_mint_key,
                self.quote_mint_key,
                self.base_vault_key,
                self.quote_vault_key,
                self.token_program_key,
                self.program_id,
                self.log_key,
                trader_signer,
            ),
        );
        let accounts = vec![
            (self.state_key, state),
            (trader.key, plain_account()),
            (trader.base_key, trader.base.clone()),
            (trader.quote_key, trader.quote.clone()),
            (self.base_mint_key, self.base_mint.clone()),
            (self.quote_mint_key, self.quote_mint.clone()),
            (self.base_vault_key, self.base_vault.clone()),
            (self.quote_vault_key, self.quote_vault.clone()),
            (self.token_program_key, self.token_program.clone()),
            (self.program_id, self.self_program.clone()),
            (self.log_key, self.log.clone()),
        ];
        (ix, accounts)
    }

    fn run(&mut self, trader: &mut TraderAccounts, name: &str, params: &[u64], expected: u64) {
        let (ix, accounts) = self.invocation(trader, name, params, true, self.state.clone());
        let log_start = self
            .mollusk
            .logger
            .as_ref()
            .expect("Phoenix log collector")
            .borrow()
            .get_recorded_content()
            .len();
        let result = self.mollusk.process_and_validate_instruction(
            &ix,
            &accounts,
            &[
                Check::success(),
                Check::return_data(&expected.to_le_bytes()),
            ],
        );
        assert!(has_phoenix_record(
            &self
                .mollusk
                .logger
                .as_ref()
                .expect("Phoenix log collector")
                .borrow()
                .get_recorded_content()[log_start..],
            phoenix_origin(name)
        ));
        let resulting = result.resulting_accounts;
        self.state = account_after(&resulting, &self.state_key);
        trader.base = account_after(&resulting, &trader.base_key);
        trader.quote = account_after(&resulting, &trader.quote_key);
        self.base_vault = account_after(&resulting, &self.base_vault_key);
        self.quote_vault = account_after(&resulting, &self.quote_vault_key);
    }

    fn run_error(
        &self,
        trader: &TraderAccounts,
        name: &str,
        params: &[u64],
        trader_signer: bool,
        error: ProgramError,
    ) {
        let (ix, accounts) =
            self.invocation(trader, name, params, trader_signer, self.state.clone());
        self.mollusk.process_and_validate_instruction(
            &ix,
            &accounts,
            &[
                Check::err(error),
                Check::account(&self.state_key)
                    .data(&self.state.data)
                    .build(),
                Check::account(&trader.base_key)
                    .data(&trader.base.data)
                    .build(),
                Check::account(&trader.quote_key)
                    .data(&trader.quote.data)
                    .build(),
                Check::account(&self.base_vault_key)
                    .data(&self.base_vault.data)
                    .build(),
                Check::account(&self.quote_vault_key)
                    .data(&self.quote_vault.data)
                    .build(),
            ],
        );
    }

    fn slots<const N: usize>(&self, indices: [usize; N]) -> [u64; N] {
        indices.map(|index| slot(&self.state, index))
    }
}

fn book_min(state: &Account, base: usize) -> u64 {
    let mut address = slot(state, base);
    for _ in 0..4 {
        assert!((1..=4).contains(&address), "invalid book address {address}");
        let left = slot(state, base + 8 + address as usize - 1);
        if left == 0 {
            return address;
        }
        address = left;
    }
    panic!("book topology contains a cycle");
}

fn assert_live_book(state: &Account, base: usize, count: u64) {
    let root = slot(state, base);
    assert!((1..=4).contains(&root), "invalid book root {root}");
    assert_eq!(slot(state, base + 1), count, "book count");
    assert_eq!(slot(state, base + 16 + root as usize - 1), 0, "root parent");
    assert_eq!(slot(state, base + 20 + root as usize - 1), 0, "root color");
}

#[test]
fn ask_lifecycle_buy_fee_withdraw_and_evict_run_on_chain() {
    let mut fixture = PhoenixFixture::new(1);
    let mut maker = fixture.trader();
    let mut taker = fixture.trader();

    fixture.run(&mut maker, "depositFunds", &[8, 0], 1);
    assert_eq!(
        (token_amount(&maker.base), token_amount(&fixture.base_vault)),
        (992, 8)
    );
    assert_eq!(
        fixture.slots([102, 126, 154, 158, 164, 165]),
        [1, 1, 0, 8, 0, 8]
    );
    for (word, index) in [130usize, 134, 138, 142].into_iter().enumerate() {
        let offset = word * 8;
        let expected = u64::from_le_bytes(
            maker.key.to_bytes()[offset..offset + 8]
                .try_into()
                .expect("pubkey limb"),
        );
        assert_eq!(slot(&fixture.state, index), expected);
    }

    fixture.run(&mut maker, "postAsk", &[10, 3, 11, 12, 0, 0], 3);
    assert_eq!(fixture.slots([6, 10, 14, 18]), [10, 1, 1, 3]);
    assert_eq!(fixture.slots([2, 154, 158, 164, 165]), [2, 3, 5, 3, 5]);

    fixture.run(&mut maker, "reduceAsk", &[10, 1, 0], 0);
    fixture.run(&mut maker, "reduceAsk", &[10, 1, 1], 1);
    assert_eq!(fixture.slots([18, 154, 158, 164, 165]), [2, 2, 6, 2, 6]);

    fixture.run(&mut taker, "depositFunds", &[0, 100], 2);
    assert_eq!(
        (
            token_amount(&taker.quote),
            token_amount(&fixture.quote_vault)
        ),
        (900, 100)
    );
    fixture.run(&mut taker, "swapBuy", &[0, 21, 22, 2, 10], 2);
    assert_eq!(fixture.slots([18, 154, 150, 151, 159]), [0, 0, 20, 79, 2]);
    assert_eq!(fixture.slots([5, 162, 163, 164, 165]), [1, 0, 99, 0, 8]);
    assert_eq!(
        (
            token_amount(&fixture.base_vault),
            token_amount(&fixture.quote_vault)
        ),
        (8, 100),
        "registered free-funds matching is vault-internal"
    );

    fixture.run(&mut maker, "collectFees", &[], 1);
    assert_eq!(fixture.slots([4, 5, 175, 225]), [1, 0, 7, 1]);

    fixture.run(&mut maker, "withdrawQuote", &[100], 20);
    fixture.run(&mut maker, "withdrawBase", &[100], 6);
    assert_eq!(fixture.slots([150, 158, 163, 165]), [0, 0, 79, 2]);
    assert_eq!(
        (
            token_amount(&maker.base),
            token_amount(&maker.quote),
            token_amount(&fixture.base_vault),
            token_amount(&fixture.quote_vault),
        ),
        (998, 1020, 2, 80)
    );

    fixture.run(&mut maker, "evictSeat", &[], 1);
    assert_eq!(
        fixture.slots([102, 103, 104, 105, 109, 126, 127]),
        [1, 3, 1, 3, 2, 0, 1]
    );
}

#[test]
fn bid_lifecycle_reduce_and_sell_run_on_chain() {
    let mut fixture = PhoenixFixture::new(1);
    let mut maker = fixture.trader();
    let mut taker = fixture.trader();

    fixture.run(&mut maker, "depositFunds", &[0, 100], 1);
    fixture.run(&mut maker, "postBid", &[12, 3, 31, 32, 0, 0], 3);
    assert_eq!(fixture.slots([30, 34, 38, 42]), [12, !1, 1, 3]);
    assert_eq!(fixture.slots([2, 146, 150, 162, 163]), [2, 36, 64, 36, 64]);

    fixture.run(&mut maker, "reduceBid", &[12, !1, 0], 0);
    fixture.run(&mut maker, "reduceBid", &[12, !1, 1], 1);
    assert_eq!(fixture.slots([42, 146, 150, 162, 163]), [2, 24, 76, 24, 76]);

    fixture.run(&mut taker, "depositFunds", &[2, 0], 2);
    fixture.run(&mut taker, "swapSell", &[0, 41, 42, 2, 12], 2);
    assert_eq!(fixture.slots([42, 146, 151, 158, 159]), [0, 0, 23, 2, 0]);
    assert_eq!(fixture.slots([5, 162, 163, 164, 165]), [1, 0, 99, 0, 2]);
    assert_eq!(
        (
            token_amount(&fixture.base_vault),
            token_amount(&fixture.quote_vault)
        ),
        (2, 100),
        "registered free-funds matching is vault-internal"
    );
}

#[test]
fn order_books_persist_topology_and_reuse_evicted_addresses_on_chain() {
    let mut asks = PhoenixFixture::new(1);
    let mut ask_maker = asks.trader();
    asks.run(&mut ask_maker, "depositFunds", &[8, 0], 1);
    for price in [10, 20, 30, 40] {
        asks.run(&mut ask_maker, "postAsk", &[price, 1, 0, 0, 0, 0], 1);
    }
    assert_live_book(&asks.state, ASK_BOOK, 4);
    assert_eq!(book_min(&asks.state, ASK_BOOK), 1);
    assert_eq!(asks.slots([6, 7, 8, 9]), [10, 20, 30, 40]);

    asks.run(&mut ask_maker, "postAsk", &[15, 1, 0, 0, 0, 0], 1);
    assert_live_book(&asks.state, ASK_BOOK, 4);
    assert_eq!(book_min(&asks.state, ASK_BOOK), 1, "best ask address");
    assert_eq!(asks.slots([6, 7, 8, 9]), [10, 20, 30, 15]);

    let mut bids = PhoenixFixture::new(1);
    let mut bid_maker = bids.trader();
    bids.run(&mut bid_maker, "depositFunds", &[0, 200], 1);
    for price in [40, 30, 20, 10] {
        bids.run(&mut bid_maker, "postBid", &[price, 1, 0, 0, 0, 0], 1);
    }
    assert_live_book(&bids.state, BID_BOOK, 4);
    assert_eq!(book_min(&bids.state, BID_BOOK), 1);
    assert_eq!(bids.slots([30, 31, 32, 33]), [40, 30, 20, 10]);

    bids.run(&mut bid_maker, "postBid", &[25, 1, 0, 0, 0, 0], 1);
    assert_live_book(&bids.state, BID_BOOK, 4);
    assert_eq!(book_min(&bids.state, BID_BOOK), 1, "best bid address");
    assert_eq!(bids.slots([30, 31, 32, 33]), [40, 30, 20, 25]);
}

#[test]
fn unregistered_buy_and_sell_execute_both_token_legs() {
    let mut buy = PhoenixFixture::new(1);
    let mut ask_maker = buy.trader();
    let mut buy_taker = buy.trader();
    buy.run(&mut ask_maker, "depositFunds", &[4, 0], 1);
    buy.run(&mut ask_maker, "postAsk", &[10, 4, 1, 2, 0, 0], 4);
    buy.run(&mut buy_taker, "swapBuy", &[0, 3, 4, 4, 10], 4);
    assert_eq!(
        (
            token_amount(&buy_taker.base),
            token_amount(&buy_taker.quote),
            token_amount(&buy.base_vault),
            token_amount(&buy.quote_vault),
        ),
        (1004, 959, 0, 41)
    );
    assert_eq!(
        buy.slots([5, 154, 158, 162, 163, 164, 165]),
        [1, 0, 0, 0, 40, 0, 0]
    );

    let mut sell = PhoenixFixture::new(1);
    let mut bid_maker = sell.trader();
    let mut sell_taker = sell.trader();
    sell.run(&mut bid_maker, "depositFunds", &[0, 100], 1);
    sell.run(&mut bid_maker, "postBid", &[12, 4, 5, 6, 0, 0], 4);
    sell.run(&mut sell_taker, "swapSell", &[0, 7, 8, 4, 12], 4);
    assert_eq!(
        (
            token_amount(&sell_taker.base),
            token_amount(&sell_taker.quote),
            token_amount(&sell.base_vault),
            token_amount(&sell.quote_vault),
        ),
        (996, 1047, 4, 53)
    );
    assert_eq!(
        sell.slots([5, 146, 150, 158, 162, 163, 164, 165]),
        [1, 0, 52, 4, 0, 52, 0, 4]
    );
}

#[test]
fn slot_and_unix_time_in_force_expire_strictly_on_chain() {
    let mut fixture = PhoenixFixture::new(1);
    let mut maker = fixture.trader();
    let mut taker = fixture.trader();

    fixture.mollusk.warp_to_slot(100);
    fixture.mollusk.sysvars.clock.unix_timestamp = 1_000;
    fixture.run(&mut maker, "depositFunds", &[4, 0], 1);
    fixture.run(&mut taker, "depositFunds", &[0, 100], 2);

    fixture.run(&mut maker, "postAsk", &[10, 2, 51, 52, 100, 0], 2);
    fixture.mollusk.warp_to_slot(101);
    fixture.run(&mut taker, "swapBuy", &[0, 61, 62, 1, 10], 0);
    assert_eq!(fixture.slots([18, 154, 158, 164, 165]), [0, 0, 4, 0, 4]);

    fixture.run(&mut maker, "postAsk", &[11, 2, 71, 72, 0, 1_000], 2);
    fixture.mollusk.sysvars.clock.unix_timestamp = 1_001;
    fixture.run(&mut taker, "swapBuy", &[0, 81, 82, 1, 11], 0);
    assert_eq!(fixture.slots([18, 154, 158, 164, 165]), [0, 0, 4, 0, 4]);
}

#[test]
fn all_self_trade_behaviors_run_on_chain() {
    let mut abort = PhoenixFixture::new(1);
    let mut abort_trader = abort.trader();
    abort.run(&mut abort_trader, "depositFunds", &[3, 100], 1);
    abort.run(&mut abort_trader, "postAsk", &[10, 3, 0, 0, 0, 0], 3);
    abort.run_error(
        &abort_trader,
        "swapBuy",
        &[0, 0, 0, 2, 10],
        true,
        ProgramError::Custom(SELF_TRADE),
    );

    let mut cancel = PhoenixFixture::new(1);
    let mut cancel_trader = cancel.trader();
    cancel.run(&mut cancel_trader, "depositFunds", &[3, 100], 1);
    cancel.run(&mut cancel_trader, "postAsk", &[10, 3, 0, 0, 0, 0], 3);
    cancel.run(&mut cancel_trader, "swapBuy", &[1, 0, 0, 2, 10], 0);
    assert_eq!(cancel.slots([18, 154, 158, 164, 165]), [0, 0, 3, 0, 3]);

    let mut decrement = PhoenixFixture::new(1);
    let mut decrement_trader = decrement.trader();
    decrement.run(&mut decrement_trader, "depositFunds", &[3, 100], 1);
    decrement.run(&mut decrement_trader, "postAsk", &[10, 3, 0, 0, 0, 0], 3);
    decrement.run(&mut decrement_trader, "swapBuy", &[2, 0, 0, 2, 10], 0);
    assert_eq!(decrement.slots([18, 154, 158, 164, 165]), [1, 1, 2, 1, 2]);
}

#[test]
fn vault_mint_program_log_and_writable_failures_are_atomic() {
    let fixture = PhoenixFixture::new(1);
    let trader = fixture.trader();

    let (mut wrong_vault_ix, mut wrong_vault_accounts) = fixture.invocation(
        &trader,
        "depositFunds",
        &[1, 0],
        true,
        fixture.state.clone(),
    );
    let wrong_vault = Pubkey::new_unique();
    wrong_vault_ix.accounts[6] = AccountMeta::new(wrong_vault, false);
    wrong_vault_accounts[6] = (
        wrong_vault,
        token_account(fixture.base_mint_key, wrong_vault, 0),
    );
    fixture.mollusk.process_and_validate_instruction(
        &wrong_vault_ix,
        &wrong_vault_accounts,
        &[
            Check::err(ProgramError::Custom(UNAUTHORIZED)),
            Check::account(&fixture.state_key)
                .data(&fixture.state.data)
                .build(),
            Check::account(&trader.base_key)
                .data(&trader.base.data)
                .build(),
        ],
    );

    let (mut wrong_mint_ix, mut wrong_mint_accounts) = fixture.invocation(
        &trader,
        "depositFunds",
        &[1, 0],
        true,
        fixture.state.clone(),
    );
    let wrong_mint = Pubkey::new_unique();
    let (wrong_derived_vault, _) = Pubkey::find_program_address(
        &[b"vault", fixture.state_key.as_ref(), wrong_mint.as_ref()],
        &fixture.program_id,
    );
    wrong_mint_ix.accounts[4] = AccountMeta::new_readonly(wrong_mint, false);
    wrong_mint_ix.accounts[6] = AccountMeta::new(wrong_derived_vault, false);
    wrong_mint_accounts[4] = (wrong_mint, mint_account(Pubkey::new_unique()));
    wrong_mint_accounts[6] = (
        wrong_derived_vault,
        token_account(wrong_mint, wrong_derived_vault, 0),
    );
    let snapshots = vec![
        (fixture.state_key, fixture.state.data.clone()),
        (trader.base_key, trader.base.data.clone()),
        (wrong_derived_vault, wrong_mint_accounts[6].1.data.clone()),
    ];
    let wrong_mint_result = fixture
        .mollusk
        .process_instruction(&wrong_mint_ix, &wrong_mint_accounts);
    assert_atomic_failure(&wrong_mint_result, &snapshots);

    let (mut wrong_program_ix, mut wrong_program_accounts) = fixture.invocation(
        &trader,
        "depositFunds",
        &[1, 0],
        true,
        fixture.state.clone(),
    );
    let wrong_program = Pubkey::new_unique();
    wrong_program_ix.accounts[8] = AccountMeta::new_readonly(wrong_program, false);
    wrong_program_accounts[8] = (wrong_program, plain_account());
    let snapshots = vec![
        (fixture.state_key, fixture.state.data.clone()),
        (trader.base_key, trader.base.data.clone()),
        (fixture.base_vault_key, fixture.base_vault.data.clone()),
    ];
    let wrong_program_result = fixture
        .mollusk
        .process_instruction(&wrong_program_ix, &wrong_program_accounts);
    assert_atomic_failure(&wrong_program_result, &snapshots);

    let (mut wrong_self_ix, mut wrong_self_accounts) = fixture.invocation(
        &trader,
        "depositFunds",
        &[1, 0],
        true,
        fixture.state.clone(),
    );
    let wrong_self = Pubkey::new_unique();
    wrong_self_ix.accounts[9] = AccountMeta::new_readonly(wrong_self, false);
    wrong_self_accounts[9] = (wrong_self, plain_account());
    let snapshots = vec![
        (fixture.state_key, fixture.state.data.clone()),
        (trader.base_key, trader.base.data.clone()),
        (fixture.base_vault_key, fixture.base_vault.data.clone()),
    ];
    let wrong_self_result = fixture
        .mollusk
        .process_instruction(&wrong_self_ix, &wrong_self_accounts);
    assert_atomic_failure(&wrong_self_result, &snapshots);

    let (mut wrong_log_ix, mut wrong_log_accounts) = fixture.invocation(
        &trader,
        "depositFunds",
        &[1, 0],
        true,
        fixture.state.clone(),
    );
    let wrong_log = Pubkey::new_unique();
    wrong_log_ix.accounts[10] = AccountMeta::new_readonly(wrong_log, false);
    wrong_log_accounts[10] = (wrong_log, plain_account());
    let snapshots = vec![
        (fixture.state_key, fixture.state.data.clone()),
        (trader.base_key, trader.base.data.clone()),
        (fixture.base_vault_key, fixture.base_vault.data.clone()),
    ];
    let wrong_log_result = fixture
        .mollusk
        .process_instruction(&wrong_log_ix, &wrong_log_accounts);
    assert_atomic_failure(&wrong_log_result, &snapshots);

    let (mut readonly_ix, readonly_accounts) = fixture.invocation(
        &trader,
        "depositFunds",
        &[1, 0],
        true,
        fixture.state.clone(),
    );
    readonly_ix.accounts[6] = AccountMeta::new_readonly(fixture.base_vault_key, false);
    let snapshots = vec![
        (fixture.state_key, fixture.state.data.clone()),
        (trader.base_key, trader.base.data.clone()),
        (fixture.base_vault_key, fixture.base_vault.data.clone()),
    ];
    let readonly_result = fixture
        .mollusk
        .process_instruction(&readonly_ix, &readonly_accounts);
    assert_atomic_failure(&readonly_result, &snapshots);
}

#[test]
fn signer_and_state_owner_failures_are_atomic() {
    let fixture = PhoenixFixture::new(1);
    let trader = fixture.trader();

    fixture.run_error(
        &trader,
        "depositFunds",
        &[1, 0],
        false,
        ProgramError::Custom(1),
    );

    let mut forged = fixture.state.clone();
    forged.owner = Pubkey::new_unique();
    let (ix, accounts) = fixture.invocation(&trader, "depositFunds", &[1, 0], true, forged);
    fixture.mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::err(ProgramError::Custom(1)),
            Check::account(&fixture.state_key)
                .data(&fixture.state.data)
                .build(),
        ],
    );
}
