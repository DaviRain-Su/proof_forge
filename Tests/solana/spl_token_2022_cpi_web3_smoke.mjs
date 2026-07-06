import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import {
  ASSOCIATED_TOKEN_PROGRAM_ID,
  ExtensionType,
  TOKEN_2022_PROGRAM_ID,
  calculateEpochFee,
  createInitializeAccountInstruction,
  createInitializeMintInstruction,
  getAccount,
  getAccountLen,
  getDefaultAccountState,
  getImmutableOwner,
  getInterestBearingMintConfigState,
  getMemoTransfer,
  getMetadataPointerState,
  getMint,
  getMintLen,
  getNonTransferable,
  getPermanentDelegate,
  getOrCreateAssociatedTokenAccount,
  getTransferHook,
  getTransferFeeAmount,
  getTransferFeeConfig,
  mintTo,
} from "@solana/spl-token";
import fs from "node:fs";

const ACCOUNT_STATE_FROZEN = 2;
const INTEREST_RATE_BASIS_POINTS = 250;

function readKeypair(path) {
  const bytes = JSON.parse(fs.readFileSync(path, "utf8"));
  return Keypair.fromSecretKey(Uint8Array.from(bytes));
}

function readArtifact(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function require(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function readU64LEAt(data, offset) {
  if (data.length < offset + 8) {
    throw new Error(`expected at least ${offset + 8} bytes, got ${data.length}`);
  }
  return Buffer.from(data).readBigUInt64LE(offset);
}

function assertAmount(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label} amount mismatch: expected ${expected}, got ${actual}`);
  }
}

function writeData(tag, values = []) {
  const data = Buffer.alloc(1 + values.length * 8);
  data[0] = tag;
  values.forEach((value, index) => {
    data.writeBigUInt64LE(BigInt(value), 1 + index * 8);
  });
  return data;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sendAndPollTransaction(connection, transaction, signers) {
  const latest = await connection.getLatestBlockhash("confirmed");
  transaction.recentBlockhash = latest.blockhash;
  transaction.feePayer = signers[0].publicKey;
  transaction.sign(...signers);
  const signature = await connection.sendRawTransaction(transaction.serialize(), {
    skipPreflight: false,
  });
  for (let attempt = 0; attempt < 60; attempt += 1) {
    const statuses = await connection.getSignatureStatuses([signature], {
      searchTransactionHistory: true,
    });
    const status = statuses.value[0];
    if (status?.err) {
      throw new Error(`transaction ${signature} failed: ${JSON.stringify(status.err)}`);
    }
    if (status?.confirmationStatus === "confirmed" || status?.confirmationStatus === "finalized") {
      return signature;
    }
    await sleep(500);
  }
  throw new Error(`transaction ${signature} was not confirmed`);
}

async function createProgramState(connection, payer, programId, space) {
  const state = Keypair.generate();
  const lamports = await connection.getMinimumBalanceForRentExemption(space);
  const ix = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: state.publicKey,
    lamports,
    space,
    programId,
  });
  await sendAndPollTransaction(connection, new Transaction().add(ix), [payer, state]);
  return state;
}

async function createScratchAccount(connection, payer, space = 0) {
  const account = Keypair.generate();
  const lamports = await connection.getMinimumBalanceForRentExemption(space);
  const ix = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: account.publicKey,
    lamports,
    space,
    programId: SystemProgram.programId,
  });
  await sendAndPollTransaction(connection, new Transaction().add(ix), [payer, account]);
  return account;
}

function validateInstructionSchemas(artifact) {
  const instructions = artifact.solanaInstructions ?? [];
  const names = instructions.map((instruction) => instruction.name);
  const expectedNames = [
    "init_fee_config",
    "transfer_with_fee",
    "withdraw_from_mint",
    "withdraw_from_accounts",
    "harvest_to_mint",
    "set_transfer_fee",
    "initialize_non_transferable",
    "initialize_metadata_pointer",
    "initialize_default_account_state",
    "initialize_immutable_owner",
    "initialize_permanent_delegate",
    "initialize_interest_bearing",
    "enable_memo_transfer",
    "initialize_transfer_hook",
  ];
  require(JSON.stringify(names) === JSON.stringify(expectedNames), `instruction names mismatch: ${JSON.stringify(names)}`);

  const expectedAccounts = [
    "last_amount",
    "mint",
    "spl_token_2022",
    "source",
    "destination",
    "authority",
    "fee_receiver",
    "withdraw_withheld_authority",
    "withheld_source",
    "transfer_fee_config_authority",
    "non_transferable_mint",
    "metadata_pointer_mint",
    "default_state_mint",
    "immutable_owner_account",
    "permanent_delegate_mint",
    "interest_bearing_mint",
    "memo_transfer_account",
    "transfer_hook_mint",
    "metadata_pointer_authority",
    "metadata_address",
    "permanent_delegate",
    "interest_rate_authority",
    "transfer_hook_authority",
    "transfer_hook_program",
  ];
  for (const instruction of instructions) {
    const accountNames = (instruction.accounts ?? []).map((account) => account.name);
    require(
      JSON.stringify(accountNames) === JSON.stringify(expectedAccounts),
      `instruction ${instruction.name} account schema mismatch: ${JSON.stringify(accountNames)}`,
    );
  }

  const initParams = instructions[0].params ?? [];
  const transferParams = instructions[1].params ?? [];
  const setFeeParams = instructions[5].params ?? [];
  const expectedTwoU64Params = (first, second) => [
    { name: first, type: "U64", offset: 1, byteSize: 8, encoding: "le-u64" },
    { name: second, type: "U64", offset: 9, byteSize: 8, encoding: "le-u64" },
  ];
  require(JSON.stringify(initParams) === JSON.stringify(expectedTwoU64Params("basis_points", "maximum_fee")), `init_fee_config params mismatch: ${JSON.stringify(initParams)}`);
  require(JSON.stringify(transferParams) === JSON.stringify(expectedTwoU64Params("amount", "fee")), `transfer_with_fee params mismatch: ${JSON.stringify(transferParams)}`);
  require(JSON.stringify(setFeeParams) === JSON.stringify(expectedTwoU64Params("basis_points", "maximum_fee")), `set_transfer_fee params mismatch: ${JSON.stringify(setFeeParams)}`);
  for (const instruction of [
    instructions[2],
    instructions[3],
    instructions[4],
    instructions[6],
    instructions[7],
    instructions[8],
    instructions[9],
    instructions[10],
    instructions[11],
    instructions[12],
    instructions[13],
  ]) {
    require((instruction.params ?? []).length === 0, `instruction ${instruction.name} should not declare params`);
  }

  const cpis = Object.fromEntries((artifact.solanaExtensions?.cpis ?? []).map((cpi) => [cpi.name, cpi]));
  const expectedCpis = {
    token_2022_init_fee_config: "token-2022.initialize_transfer_fee_config",
    token_2022_transfer_with_fee: "token-2022.transfer_checked_with_fee",
    token_2022_withdraw_from_mint: "token-2022.withdraw_withheld_tokens_from_mint",
    token_2022_withdraw_from_accounts: "token-2022.withdraw_withheld_tokens_from_accounts",
    token_2022_harvest_to_mint: "token-2022.harvest_withheld_tokens_to_mint",
    token_2022_set_transfer_fee: "token-2022.set_transfer_fee",
    token_2022_init_non_transferable: "token-2022.initialize_non_transferable_mint",
    token_2022_init_metadata_pointer: "token-2022.initialize_metadata_pointer",
    token_2022_init_default_account_state: "token-2022.initialize_default_account_state",
    token_2022_init_immutable_owner: "token-2022.initialize_immutable_owner",
    token_2022_init_permanent_delegate: "token-2022.initialize_permanent_delegate",
    token_2022_init_interest_bearing: "token-2022.initialize_interest_bearing_mint",
    token_2022_enable_memo_transfer: "token-2022.enable_required_memo_transfers",
    token_2022_init_transfer_hook: "token-2022.initialize_transfer_hook",
  };
  require(JSON.stringify(Object.keys(cpis)) === JSON.stringify(Object.keys(expectedCpis)), `CPI names mismatch: ${JSON.stringify(Object.keys(cpis))}`);
  for (const [name, layout] of Object.entries(expectedCpis)) {
    const cpi = cpis[name];
    require(cpi.program === "spl_token_2022", `CPI ${name} program mismatch: ${JSON.stringify(cpi)}`);
    require(cpi.protocol === "token-2022", `CPI ${name} protocol mismatch: ${JSON.stringify(cpi)}`);
    require(cpi.dataLayout === layout, `CPI ${name} layout mismatch: ${JSON.stringify(cpi)}`);
  }
  require(cpis.token_2022_transfer_with_fee.feeSource === "fee", "transfer_with_fee missing feeSource");
  require(cpis.token_2022_transfer_with_fee.decimals === "9", "transfer_with_fee decimals mismatch");
  require(cpis.token_2022_withdraw_from_accounts.numTokenAccounts === "1", "withdraw_from_accounts numTokenAccounts mismatch");
  require(cpis.token_2022_init_metadata_pointer.metadataPointerAuthority === "metadata_pointer_authority", "metadata_pointer missing authority source");
  require(cpis.token_2022_init_metadata_pointer.metadataAddress === "metadata_address", "metadata_pointer missing metadata address source");
  require(cpis.token_2022_init_default_account_state.defaultAccountState === String(ACCOUNT_STATE_FROZEN), "default_account_state mismatch");
  require(cpis.token_2022_init_permanent_delegate.permanentDelegate === "permanent_delegate", "permanent_delegate missing delegate source");
  require(cpis.token_2022_init_interest_bearing.interestRateAuthority === "interest_rate_authority", "interest_bearing missing authority source");
  require(cpis.token_2022_init_interest_bearing.interestRate === String(INTEREST_RATE_BASIS_POINTS), "interest_bearing rate mismatch");
  require(cpis.token_2022_enable_memo_transfer.memoTransferRequired === "true", "memo_transfer required flag mismatch");
  require(cpis.token_2022_init_transfer_hook.transferHookAuthority === "transfer_hook_authority", "transfer_hook missing authority source");
  require(cpis.token_2022_init_transfer_hook.transferHookProgram === "transfer_hook_program", "transfer_hook missing program source");
  return instructions;
}

function buildKeys(accounts, pubkeys) {
  return accounts.map((account) => {
    const pubkey = pubkeys[account.name];
    if (!pubkey) {
      throw new Error(`missing pubkey for account ${account.name}`);
    }
    return {
      pubkey,
      isSigner: account.signer === true,
      isWritable: account.writable === true,
    };
  });
}

async function invokeGenerated(connection, payer, programId, instruction, pubkeys, data, extraSigners = []) {
  const ix = new TransactionInstruction({
    programId,
    keys: buildKeys(instruction.accounts ?? [], pubkeys),
    data,
  });
  return sendAndPollTransaction(connection, new Transaction().add(ix), [payer, ...extraSigners]);
}

async function createMintAccountWithExtensions(connection, payer, extensions) {
  const mint = Keypair.generate();
  const mintLen = getMintLen(extensions);
  const mintRent = await connection.getMinimumBalanceForRentExemption(mintLen);
  const ix = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: mint.publicKey,
    lamports: mintRent,
    space: mintLen,
    programId: TOKEN_2022_PROGRAM_ID,
  });
  const signature = await sendAndPollTransaction(connection, new Transaction().add(ix), [payer, mint]);
  return { mint, signature };
}

async function createTokenAccountWithExtensions(connection, payer, extensions) {
  const account = Keypair.generate();
  const accountLen = getAccountLen(extensions);
  const accountRent = await connection.getMinimumBalanceForRentExemption(accountLen);
  const ix = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: account.publicKey,
    lamports: accountRent,
    space: accountLen,
    programId: TOKEN_2022_PROGRAM_ID,
  });
  const signature = await sendAndPollTransaction(connection, new Transaction().add(ix), [payer, account]);
  return { account, signature };
}

async function main() {
  const rpcUrl = process.env.PROOF_FORGE_SOLANA_RPC_URL;
  const wsUrl = process.env.PROOF_FORGE_SOLANA_WS_URL;
  const payerPath = process.env.PROOF_FORGE_SOLANA_PAYER;
  const programIdValue = process.env.PROOF_FORGE_SOLANA_PROGRAM_ID;
  const artifactPath = process.env.PROOF_FORGE_SOLANA_ARTIFACT;
  if (!rpcUrl || !payerPath || !programIdValue || !artifactPath) {
    throw new Error("missing PROOF_FORGE_SOLANA_RPC_URL, PROOF_FORGE_SOLANA_PAYER, PROOF_FORGE_SOLANA_PROGRAM_ID, or PROOF_FORGE_SOLANA_ARTIFACT");
  }

  const artifact = readArtifact(artifactPath);
  const instructions = validateInstructionSchemas(artifact);
  const byName = Object.fromEntries(instructions.map((instruction) => [instruction.name, instruction]));
  const connection = new Connection(rpcUrl, {
    commitment: "confirmed",
    wsEndpoint: wsUrl,
  });
  const payer = readKeypair(payerPath);
  const programId = new PublicKey(programIdValue);
  const state = await createProgramState(connection, payer, programId, 40);
  const decimals = Number(process.env.PROOF_FORGE_SOLANA_TOKEN_DECIMALS ?? "9");
  const initialSupply = BigInt(process.env.PROOF_FORGE_SOLANA_TOKEN_INITIAL_SUPPLY ?? "1000000000");
  const transferFeeBasisPoints = BigInt(process.env.PROOF_FORGE_SOLANA_TRANSFER_FEE_BPS ?? "125");
  const maximumFee = BigInt(process.env.PROOF_FORGE_SOLANA_TRANSFER_FEE_MAX_FEE ?? "10000");
  const nextBasisPoints = BigInt(process.env.PROOF_FORGE_SOLANA_TRANSFER_FEE_NEXT_BPS ?? "250");
  const nextMaximumFee = BigInt(process.env.PROOF_FORGE_SOLANA_TRANSFER_FEE_NEXT_MAX_FEE ?? "20000");
  const transferAmount = BigInt(process.env.PROOF_FORGE_SOLANA_TOKEN_TRANSFER_AMOUNT ?? "250000");
  if (initialSupply <= transferAmount * 2n) {
    throw new Error(`initial supply ${initialSupply} is too small for two transfers of ${transferAmount}`);
  }
  for (const [label, value] of [["basis points", transferFeeBasisPoints], ["next basis points", nextBasisPoints]]) {
    if (value < 0n || value > 10000n) {
      throw new Error(`invalid ${label}: ${value}`);
    }
  }

  const { mint, signature: createMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.TransferFeeConfig]);
  const { mint: metadataPointerMint, signature: createMetadataPointerMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.MetadataPointer]);
  const { mint: defaultStateMint, signature: createDefaultStateMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.DefaultAccountState]);
  const { mint: immutableOwnerMint, signature: createImmutableOwnerMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, []);
  const { account: immutableOwnerAccount, signature: createImmutableOwnerAccountSignature } =
    await createTokenAccountWithExtensions(connection, payer, [ExtensionType.ImmutableOwner]);
  const { mint: nonTransferableMint, signature: createNonTransferableMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.NonTransferable]);
  const { mint: permanentDelegateMint, signature: createPermanentDelegateMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.PermanentDelegate]);
  const { mint: interestBearingMint, signature: createInterestBearingMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.InterestBearingConfig]);
  const { mint: memoTransferMint, signature: createMemoTransferMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, []);
  const { account: memoTransferAccount, signature: createMemoTransferAccountSignature } =
    await createTokenAccountWithExtensions(connection, payer, [ExtensionType.MemoTransfer]);
  const { mint: transferHookMint, signature: createTransferHookMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.TransferHook]);
  const tokenOwner = await createScratchAccount(connection, payer);
  const withdrawWithheldAuthority = await createScratchAccount(connection, payer);
  const transferFeeConfigAuthority = await createScratchAccount(connection, payer);
  const metadataPointerAuthority = await createScratchAccount(connection, payer);
  const metadataAddress = await createScratchAccount(connection, payer);
  const permanentDelegate = await createScratchAccount(connection, payer);
  const interestRateAuthority = await createScratchAccount(connection, payer);
  const transferHookAuthority = await createScratchAccount(connection, payer);
  const transferHookProgram = await createScratchAccount(connection, payer);
  const scratchSource = await createScratchAccount(connection, payer);
  const scratchDestination = await createScratchAccount(connection, payer);
  const scratchFeeReceiver = await createScratchAccount(connection, payer);
  const scratchWithheldSource = await createScratchAccount(connection, payer);
  const generatedSigners = [tokenOwner, withdrawWithheldAuthority, transferFeeConfigAuthority];
  const basePubkeys = () => ({
    last_amount: state.publicKey,
    mint: mint.publicKey,
    spl_token_2022: TOKEN_2022_PROGRAM_ID,
    source: scratchSource.publicKey,
    destination: scratchDestination.publicKey,
    authority: tokenOwner.publicKey,
    fee_receiver: scratchFeeReceiver.publicKey,
    withdraw_withheld_authority: withdrawWithheldAuthority.publicKey,
    withheld_source: scratchWithheldSource.publicKey,
    transfer_fee_config_authority: transferFeeConfigAuthority.publicKey,
    metadata_pointer_mint: metadataPointerMint.publicKey,
    default_state_mint: defaultStateMint.publicKey,
    immutable_owner_account: immutableOwnerAccount.publicKey,
    non_transferable_mint: nonTransferableMint.publicKey,
    permanent_delegate_mint: permanentDelegateMint.publicKey,
    interest_bearing_mint: interestBearingMint.publicKey,
    memo_transfer_account: memoTransferAccount.publicKey,
    transfer_hook_mint: transferHookMint.publicKey,
    metadata_pointer_authority: metadataPointerAuthority.publicKey,
    metadata_address: metadataAddress.publicKey,
    permanent_delegate: permanentDelegate.publicKey,
    interest_rate_authority: interestRateAuthority.publicKey,
    transfer_hook_authority: transferHookAuthority.publicKey,
    transfer_hook_program: transferHookProgram.publicKey,
  });
  const pubkeysFor = (overrides) => ({ ...basePubkeys(), ...overrides });

  const initFeeSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.init_fee_config,
    pubkeysFor({}),
    writeData(0, [transferFeeBasisPoints, maximumFee]),
    generatedSigners,
  );
  let stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, `state account not found after init_fee_config: ${state.publicKey.toBase58()}`);
  assertAmount("state last_basis_points after init", readU64LEAt(stateAccount.data, 16), transferFeeBasisPoints);
  assertAmount("state last_maximum_fee after init", readU64LEAt(stateAccount.data, 24), maximumFee);

  const initializeMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        mint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );

  let mintAccount = await getMint(connection, mint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  let feeConfig = getTransferFeeConfig(mintAccount);
  require(feeConfig !== null, "mint missing TransferFeeConfig extension after generated init");
  require(feeConfig.transferFeeConfigAuthority.equals(transferFeeConfigAuthority.publicKey), "transfer-fee config authority mismatch");
  require(feeConfig.withdrawWithheldAuthority.equals(withdrawWithheldAuthority.publicKey), "withdraw-withheld authority mismatch");
  require(feeConfig.newerTransferFee.transferFeeBasisPoints === Number(transferFeeBasisPoints), "transfer-fee basis points mismatch");
  assertAmount("transfer-fee maximum", feeConfig.newerTransferFee.maximumFee, maximumFee);

  const recipient = Keypair.generate();
  const harvestRecipient = Keypair.generate();
  const feeReceiver = Keypair.generate();
  const ownerAta = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint.publicKey,
    tokenOwner.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );
  const recipientAta = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint.publicKey,
    recipient.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );
  const harvestRecipientAta = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint.publicKey,
    harvestRecipient.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );
  const feeReceiverAta = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint.publicKey,
    feeReceiver.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );

  const mintToSignature = await mintTo(
    connection,
    payer,
    mint.publicKey,
    ownerAta.address,
    payer,
    initialSupply,
    [],
    { commitment: "confirmed" },
    TOKEN_2022_PROGRAM_ID,
  );
  let ownerAccount = await getAccount(connection, ownerAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  let recipientAccount = await getAccount(connection, recipientAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  let harvestRecipientAccount = await getAccount(connection, harvestRecipientAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  let feeReceiverAccount = await getAccount(connection, feeReceiverAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  assertAmount("owner after mint", ownerAccount.amount, initialSupply);
  assertAmount("recipient initial", recipientAccount.amount, 0n);
  assertAmount("harvest recipient initial", harvestRecipientAccount.amount, 0n);
  assertAmount("fee receiver initial", feeReceiverAccount.amount, 0n);

  const epochInfo = await connection.getEpochInfo("confirmed");
  feeConfig = getTransferFeeConfig(await getMint(connection, mint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID));
  require(feeConfig !== null, "mint missing TransferFeeConfig before transfer");
  const expectedFee = calculateEpochFee(feeConfig, BigInt(epochInfo.epoch), transferAmount);
  const transferPubkeys = {
    ...basePubkeys(),
    source: ownerAta.address,
    destination: recipientAta.address,
    fee_receiver: feeReceiverAta.address,
  };
  const transferSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.transfer_with_fee,
    transferPubkeys,
    writeData(1, [transferAmount, expectedFee]),
    generatedSigners,
  );
  ownerAccount = await getAccount(connection, ownerAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  recipientAccount = await getAccount(connection, recipientAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  let recipientFeeAmount = getTransferFeeAmount(recipientAccount);
  require(recipientFeeAmount !== null, "recipient account missing TransferFeeAmount extension");
  assertAmount("owner after generated transfer_with_fee", ownerAccount.amount, initialSupply - transferAmount);
  assertAmount("recipient after generated transfer_with_fee", recipientAccount.amount, transferAmount - expectedFee);
  assertAmount("recipient withheld transfer fee", recipientFeeAmount.withheldAmount, expectedFee);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after transfer_with_fee");
  assertAmount("state last_amount after transfer", readU64LEAt(stateAccount.data, 0), transferAmount);
  assertAmount("state last_fee after transfer", readU64LEAt(stateAccount.data, 8), expectedFee);

  const withdrawFromAccountsSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.withdraw_from_accounts,
    pubkeysFor({
      fee_receiver: feeReceiverAta.address,
      withheld_source: recipientAta.address,
    }),
    writeData(3),
    generatedSigners,
  );
  recipientAccount = await getAccount(connection, recipientAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  feeReceiverAccount = await getAccount(connection, feeReceiverAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  recipientFeeAmount = getTransferFeeAmount(recipientAccount);
  require(recipientFeeAmount !== null, "recipient account missing TransferFeeAmount after withdraw");
  assertAmount("recipient withheld fee after generated withdraw_from_accounts", recipientFeeAmount.withheldAmount, 0n);
  assertAmount("fee receiver after generated withdraw_from_accounts", feeReceiverAccount.amount, expectedFee);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after withdraw_from_accounts");
  assertAmount("state marker after withdraw_from_accounts", readU64LEAt(stateAccount.data, 32), 2n);

  const harvestTransferPubkeys = {
    ...basePubkeys(),
    source: ownerAta.address,
    destination: harvestRecipientAta.address,
    fee_receiver: feeReceiverAta.address,
  };
  const harvestTransferSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.transfer_with_fee,
    harvestTransferPubkeys,
    writeData(1, [transferAmount, expectedFee]),
    generatedSigners,
  );
  ownerAccount = await getAccount(connection, ownerAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  harvestRecipientAccount = await getAccount(connection, harvestRecipientAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  let harvestRecipientFeeAmount = getTransferFeeAmount(harvestRecipientAccount);
  require(harvestRecipientFeeAmount !== null, "harvest recipient missing TransferFeeAmount extension");
  assertAmount("owner after harvest-path generated transfer", ownerAccount.amount, initialSupply - transferAmount * 2n);
  assertAmount("harvest recipient after generated transfer_with_fee", harvestRecipientAccount.amount, transferAmount - expectedFee);
  assertAmount("harvest recipient withheld fee", harvestRecipientFeeAmount.withheldAmount, expectedFee);

  const harvestToMintSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.harvest_to_mint,
    pubkeysFor({
      fee_receiver: feeReceiverAta.address,
      withheld_source: harvestRecipientAta.address,
    }),
    writeData(4),
    generatedSigners,
  );
  harvestRecipientAccount = await getAccount(connection, harvestRecipientAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  mintAccount = await getMint(connection, mint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  harvestRecipientFeeAmount = getTransferFeeAmount(harvestRecipientAccount);
  feeConfig = getTransferFeeConfig(mintAccount);
  require(harvestRecipientFeeAmount !== null, "harvest recipient missing TransferFeeAmount after harvest");
  require(feeConfig !== null, "mint missing TransferFeeConfig after harvest");
  assertAmount("harvest recipient withheld fee after generated harvest_to_mint", harvestRecipientFeeAmount.withheldAmount, 0n);
  assertAmount("mint withheld fee after generated harvest_to_mint", feeConfig.withheldAmount, expectedFee);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after harvest_to_mint");
  assertAmount("state marker after harvest_to_mint", readU64LEAt(stateAccount.data, 32), 3n);

  const withdrawFromMintSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.withdraw_from_mint,
    pubkeysFor({
      fee_receiver: feeReceiverAta.address,
    }),
    writeData(2),
    generatedSigners,
  );
  feeReceiverAccount = await getAccount(connection, feeReceiverAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  mintAccount = await getMint(connection, mint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  feeConfig = getTransferFeeConfig(mintAccount);
  require(feeConfig !== null, "mint missing TransferFeeConfig after withdraw_from_mint");
  assertAmount("fee receiver after generated withdraw_from_mint", feeReceiverAccount.amount, expectedFee * 2n);
  assertAmount("mint withheld fee after generated withdraw_from_mint", feeConfig.withheldAmount, 0n);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after withdraw_from_mint");
  assertAmount("state marker after withdraw_from_mint", readU64LEAt(stateAccount.data, 32), 1n);

  const setFeeSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.set_transfer_fee,
    pubkeysFor({
      fee_receiver: feeReceiverAta.address,
    }),
    writeData(5, [nextBasisPoints, nextMaximumFee]),
    generatedSigners,
  );
  mintAccount = await getMint(connection, mint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  feeConfig = getTransferFeeConfig(mintAccount);
  require(feeConfig !== null, "mint missing TransferFeeConfig after set_transfer_fee");
  require(feeConfig.newerTransferFee.transferFeeBasisPoints === Number(nextBasisPoints), "next transfer-fee basis points mismatch");
  assertAmount("next transfer-fee maximum", feeConfig.newerTransferFee.maximumFee, nextMaximumFee);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after set_transfer_fee");
  assertAmount("state last_basis_points after set", readU64LEAt(stateAccount.data, 16), nextBasisPoints);
  assertAmount("state last_maximum_fee after set", readU64LEAt(stateAccount.data, 24), nextMaximumFee);

  const initNonTransferableSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_non_transferable,
    pubkeysFor({}),
    writeData(6),
    generatedSigners,
  );
  const initializeNonTransferableMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        nonTransferableMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const nonTransferableMintState = await getMint(connection, nonTransferableMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  require(getNonTransferable(nonTransferableMintState) !== null, "mint missing NonTransferable extension after generated init");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_non_transferable");
  assertAmount("state marker after initialize_non_transferable", readU64LEAt(stateAccount.data, 32), 4n);

  const initMetadataPointerSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_metadata_pointer,
    pubkeysFor({}),
    writeData(7),
    generatedSigners,
  );
  const initializeMetadataPointerMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        metadataPointerMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const metadataPointerMintState = await getMint(connection, metadataPointerMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const metadataPointerState = getMetadataPointerState(metadataPointerMintState);
  require(metadataPointerState !== null, "metadata pointer mint missing MetadataPointer extension");
  require(metadataPointerState.authority?.equals(metadataPointerAuthority.publicKey), "metadata pointer authority mismatch");
  require(metadataPointerState.metadataAddress?.equals(metadataAddress.publicKey), "metadata pointer address mismatch");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_metadata_pointer");
  assertAmount("state marker after initialize_metadata_pointer", readU64LEAt(stateAccount.data, 32), 5n);

  const initDefaultAccountStateSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_default_account_state,
    pubkeysFor({}),
    writeData(8),
    generatedSigners,
  );
  const initializeDefaultStateMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        defaultStateMint.publicKey,
        decimals,
        payer.publicKey,
        payer.publicKey,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const defaultStateMintState = await getMint(connection, defaultStateMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const defaultAccountState = getDefaultAccountState(defaultStateMintState);
  require(defaultAccountState !== null, "default-state mint missing DefaultAccountState extension");
  require(defaultAccountState.state === ACCOUNT_STATE_FROZEN, `default account state mismatch: ${defaultAccountState.state}`);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_default_account_state");
  assertAmount("state marker after initialize_default_account_state", readU64LEAt(stateAccount.data, 32), 6n);

  const initializeImmutableOwnerMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        immutableOwnerMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const initImmutableOwnerSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_immutable_owner,
    pubkeysFor({}),
    writeData(9),
    generatedSigners,
  );
  const initializeImmutableOwnerAccountSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeAccountInstruction(
        immutableOwnerAccount.publicKey,
        immutableOwnerMint.publicKey,
        tokenOwner.publicKey,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const immutableOwnerState = await getAccount(connection, immutableOwnerAccount.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  require(getImmutableOwner(immutableOwnerState) !== null, "token account missing ImmutableOwner extension");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_immutable_owner");
  assertAmount("state marker after initialize_immutable_owner", readU64LEAt(stateAccount.data, 32), 7n);

  const initPermanentDelegateSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_permanent_delegate,
    pubkeysFor({}),
    writeData(10),
    generatedSigners,
  );
  const initializePermanentDelegateMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        permanentDelegateMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const permanentDelegateMintState = await getMint(connection, permanentDelegateMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const permanentDelegateState = getPermanentDelegate(permanentDelegateMintState);
  require(permanentDelegateState !== null, "mint missing PermanentDelegate extension after generated init");
  require(permanentDelegateState.delegate.equals(permanentDelegate.publicKey), "permanent delegate mismatch");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_permanent_delegate");
  assertAmount("state marker after initialize_permanent_delegate", readU64LEAt(stateAccount.data, 32), 8n);

  const initInterestBearingSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_interest_bearing,
    pubkeysFor({}),
    writeData(11),
    generatedSigners,
  );
  const initializeInterestBearingMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        interestBearingMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const interestBearingMintState = await getMint(connection, interestBearingMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const interestBearingState = getInterestBearingMintConfigState(interestBearingMintState);
  require(interestBearingState !== null, "mint missing InterestBearingConfig extension after generated init");
  require(interestBearingState.rateAuthority.equals(interestRateAuthority.publicKey), "interest-bearing rate authority mismatch");
  require(interestBearingState.currentRate === INTEREST_RATE_BASIS_POINTS, `interest-bearing rate mismatch: ${interestBearingState.currentRate}`);
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_interest_bearing");
  assertAmount("state marker after initialize_interest_bearing", readU64LEAt(stateAccount.data, 32), 9n);

  const initializeMemoTransferMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        memoTransferMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const initializeMemoTransferAccountSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeAccountInstruction(
        memoTransferAccount.publicKey,
        memoTransferMint.publicKey,
        tokenOwner.publicKey,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const enableMemoTransferSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.enable_memo_transfer,
    pubkeysFor({}),
    writeData(12),
    generatedSigners,
  );
  const memoTransferAccountState = await getAccount(connection, memoTransferAccount.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const memoTransferState = getMemoTransfer(memoTransferAccountState);
  require(memoTransferState !== null, "token account missing MemoTransfer extension after generated enable");
  require(memoTransferState.requireIncomingTransferMemos === true, "memo-transfer required flag mismatch");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after enable_memo_transfer");
  assertAmount("state marker after enable_memo_transfer", readU64LEAt(stateAccount.data, 32), 10n);

  const initTransferHookSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_transfer_hook,
    pubkeysFor({}),
    writeData(13),
    generatedSigners,
  );
  const initializeTransferHookMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        transferHookMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  const transferHookMintState = await getMint(connection, transferHookMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const transferHookState = getTransferHook(transferHookMintState);
  require(transferHookState !== null, "mint missing TransferHook extension after generated init");
  require(transferHookState.authority.equals(transferHookAuthority.publicKey), "transfer-hook authority mismatch");
  require(transferHookState.programId.equals(transferHookProgram.publicKey), "transfer-hook program id mismatch");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_transfer_hook");
  assertAmount("state marker after initialize_transfer_hook", readU64LEAt(stateAccount.data, 32), 11n);

  console.log(JSON.stringify({
    programId: programId.toBase58(),
    state: state.publicKey.toBase58(),
    payer: payer.publicKey.toBase58(),
    tokenOwner: tokenOwner.publicKey.toBase58(),
    withdrawWithheldAuthority: withdrawWithheldAuthority.publicKey.toBase58(),
    transferFeeConfigAuthority: transferFeeConfigAuthority.publicKey.toBase58(),
    mint: mint.publicKey.toBase58(),
    metadataPointerMint: metadataPointerMint.publicKey.toBase58(),
    defaultStateMint: defaultStateMint.publicKey.toBase58(),
    immutableOwnerMint: immutableOwnerMint.publicKey.toBase58(),
    immutableOwnerAccount: immutableOwnerAccount.publicKey.toBase58(),
    nonTransferableMint: nonTransferableMint.publicKey.toBase58(),
    permanentDelegateMint: permanentDelegateMint.publicKey.toBase58(),
    interestBearingMint: interestBearingMint.publicKey.toBase58(),
    memoTransferMint: memoTransferMint.publicKey.toBase58(),
    memoTransferAccount: memoTransferAccount.publicKey.toBase58(),
    transferHookMint: transferHookMint.publicKey.toBase58(),
    metadataPointerAuthority: metadataPointerAuthority.publicKey.toBase58(),
    metadataAddress: metadataAddress.publicKey.toBase58(),
    permanentDelegate: permanentDelegate.publicKey.toBase58(),
    interestRateAuthority: interestRateAuthority.publicKey.toBase58(),
    transferHookAuthority: transferHookAuthority.publicKey.toBase58(),
    transferHookProgram: transferHookProgram.publicKey.toBase58(),
    ownerAta: ownerAta.address.toBase58(),
    recipientAta: recipientAta.address.toBase58(),
    harvestRecipientAta: harvestRecipientAta.address.toBase58(),
    feeReceiverAta: feeReceiverAta.address.toBase58(),
    tokenProgram: TOKEN_2022_PROGRAM_ID.toBase58(),
    decimals,
    initialSupply: initialSupply.toString(),
    transferAmount: transferAmount.toString(),
    expectedFee: expectedFee.toString(),
    transferFeeBasisPoints: transferFeeBasisPoints.toString(),
    maximumFee: maximumFee.toString(),
    nextBasisPoints: nextBasisPoints.toString(),
    nextMaximumFee: nextMaximumFee.toString(),
    interestRateBasisPoints: String(INTEREST_RATE_BASIS_POINTS),
    ownerFinal: ownerAccount.amount.toString(),
    feeReceiverFinal: feeReceiverAccount.amount.toString(),
    signatures: {
      createMintAccount: createMintAccountSignature,
      initFee: initFeeSignature,
      initializeMint: initializeMintSignature,
      mintTo: mintToSignature,
      transfer: transferSignature,
      withdrawFromAccounts: withdrawFromAccountsSignature,
      harvestTransfer: harvestTransferSignature,
      harvestToMint: harvestToMintSignature,
      withdrawFromMint: withdrawFromMintSignature,
      setFee: setFeeSignature,
      createNonTransferableMintAccount: createNonTransferableMintAccountSignature,
      initNonTransferable: initNonTransferableSignature,
      initializeNonTransferableMint: initializeNonTransferableMintSignature,
      createMetadataPointerMintAccount: createMetadataPointerMintAccountSignature,
      initMetadataPointer: initMetadataPointerSignature,
      initializeMetadataPointerMint: initializeMetadataPointerMintSignature,
      createDefaultStateMintAccount: createDefaultStateMintAccountSignature,
      initDefaultAccountState: initDefaultAccountStateSignature,
      initializeDefaultStateMint: initializeDefaultStateMintSignature,
      createImmutableOwnerMintAccount: createImmutableOwnerMintAccountSignature,
      initializeImmutableOwnerMint: initializeImmutableOwnerMintSignature,
      createImmutableOwnerAccount: createImmutableOwnerAccountSignature,
      initImmutableOwner: initImmutableOwnerSignature,
      initializeImmutableOwnerAccount: initializeImmutableOwnerAccountSignature,
      createPermanentDelegateMintAccount: createPermanentDelegateMintAccountSignature,
      initPermanentDelegate: initPermanentDelegateSignature,
      initializePermanentDelegateMint: initializePermanentDelegateMintSignature,
      createInterestBearingMintAccount: createInterestBearingMintAccountSignature,
      initInterestBearing: initInterestBearingSignature,
      initializeInterestBearingMint: initializeInterestBearingMintSignature,
      createMemoTransferMintAccount: createMemoTransferMintAccountSignature,
      createMemoTransferAccount: createMemoTransferAccountSignature,
      initializeMemoTransferMint: initializeMemoTransferMintSignature,
      initializeMemoTransferAccount: initializeMemoTransferAccountSignature,
      enableMemoTransfer: enableMemoTransferSignature,
      createTransferHookMintAccount: createTransferHookMintAccountSignature,
      initTransferHook: initTransferHookSignature,
      initializeTransferHookMint: initializeTransferHookMintSignature,
    },
  }));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
