import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import {
  ExtensionType,
  TOKEN_2022_PROGRAM_ID,
  createInitializeMintInstruction,
  getMint,
  getMintLen,
  getPausableConfig,
} from "@solana/spl-token";
import fs from "node:fs";

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

function writeData(tag) {
  return Buffer.from([tag]);
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

function validateInstructionSchemas(artifact) {
  require(artifact.fixture === "solana-spl-token-2022-pausable-cpi-elf", `fixture mismatch: ${artifact.fixture}`);
  const instructions = artifact.solanaInstructions ?? [];
  const names = instructions.map((instruction) => instruction.name);
  const expectedNames = ["initialize_pausable_config", "pause", "resume"];
  require(JSON.stringify(names) === JSON.stringify(expectedNames), `instruction names mismatch: ${JSON.stringify(names)}`);

  const expectedAccounts = ["last_marker", "pausable_mint", "spl_token_2022", "pausable_authority"];
  for (const instruction of instructions) {
    const accounts = (instruction.accounts ?? []).map((account) => account.name);
    require(
      JSON.stringify(accounts) === JSON.stringify(expectedAccounts),
      `instruction ${instruction.name} account schema mismatch: ${JSON.stringify(accounts)}`,
    );
    require((instruction.params ?? []).length === 0, `instruction ${instruction.name} should not declare params`);
  }

  const cpis = Object.fromEntries((artifact.solanaExtensions?.cpis ?? []).map((cpi) => [cpi.name, cpi]));
  const expectedCpis = {
    token_2022_init_pausable_config: "token-2022.initialize_pausable_config",
    token_2022_pause: "token-2022.pause",
    token_2022_resume: "token-2022.resume",
  };
  require(JSON.stringify(Object.keys(cpis)) === JSON.stringify(Object.keys(expectedCpis)), `CPI names mismatch: ${JSON.stringify(Object.keys(cpis))}`);
  for (const [name, layout] of Object.entries(expectedCpis)) {
    const cpi = cpis[name];
    require(cpi.program === "spl_token_2022", `CPI ${name} program mismatch: ${JSON.stringify(cpi)}`);
    require(cpi.protocol === "token-2022", `CPI ${name} protocol mismatch: ${JSON.stringify(cpi)}`);
    require(cpi.dataLayout === layout, `CPI ${name} layout mismatch: ${JSON.stringify(cpi)}`);
  }
  require(cpis.token_2022_init_pausable_config.pausableAuthority === "pausable_authority", "pausable authority metadata mismatch");
  return Object.fromEntries(instructions.map((instruction) => [instruction.name, instruction]));
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

async function invokeGenerated(connection, payer, programId, instruction, pubkeys, data, extraSigners) {
  const ix = new TransactionInstruction({
    programId,
    keys: buildKeys(instruction.accounts ?? [], pubkeys),
    data,
  });
  return sendAndPollTransaction(connection, new Transaction().add(ix), [payer, ...extraSigners]);
}

async function main() {
  const rpcUrl = process.env.PROOF_FORGE_SOLANA_RPC_URL ?? "http://127.0.0.1:8904";
  const wsUrl = process.env.PROOF_FORGE_SOLANA_WS_URL;
  const payerPath = process.env.PROOF_FORGE_SOLANA_PAYER;
  const programIdValue = process.env.PROOF_FORGE_SOLANA_PROGRAM_ID;
  const artifactPath = process.env.PROOF_FORGE_SOLANA_ARTIFACT;
  require(payerPath, "PROOF_FORGE_SOLANA_PAYER is required");
  require(programIdValue, "PROOF_FORGE_SOLANA_PROGRAM_ID is required");
  require(artifactPath, "PROOF_FORGE_SOLANA_ARTIFACT is required");

  const connection = new Connection(rpcUrl, {
    commitment: "confirmed",
    wsEndpoint: wsUrl,
  });
  const payer = readKeypair(payerPath);
  const programId = new PublicKey(programIdValue);
  const artifact = readArtifact(artifactPath);
  const byName = validateInstructionSchemas(artifact);

  const state = await createProgramState(connection, payer, programId, 8);
  const { mint: pausableMint, signature: createPausableMintAccountSignature } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.PausableConfig]);
  const pausableAuthority = await createScratchAccount(connection, payer);
  const decimals = 9;
  const pubkeys = {
    last_marker: state.publicKey,
    pausable_mint: pausableMint.publicKey,
    spl_token_2022: TOKEN_2022_PROGRAM_ID,
    pausable_authority: pausableAuthority.publicKey,
  };

  const initPausableConfigSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_pausable_config,
    pubkeys,
    writeData(0),
    [pausableAuthority],
  );
  const initializePausableMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeMintInstruction(
        pausableMint.publicKey,
        decimals,
        payer.publicKey,
        null,
        TOKEN_2022_PROGRAM_ID,
      ),
    ),
    [payer],
  );
  let pausableMintState = await getMint(connection, pausableMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  let pausableConfig = getPausableConfig(pausableMintState);
  require(pausableConfig !== null, "mint missing PausableConfig extension after generated init");
  require(pausableConfig.authority.equals(pausableAuthority.publicKey), "pausable authority mismatch");
  require(pausableConfig.paused === false, "pausable mint should initialize unpaused");
  let stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after initialize_pausable_config");
  require(readU64LEAt(stateAccount.data, 0) === 1n, "state marker after initialize_pausable_config mismatch");

  const pauseSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.pause,
    pubkeys,
    writeData(1),
    [pausableAuthority],
  );
  pausableMintState = await getMint(connection, pausableMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  pausableConfig = getPausableConfig(pausableMintState);
  require(pausableConfig !== null, "mint missing PausableConfig extension after generated pause");
  require(pausableConfig.paused === true, "pausable mint should be paused after generated pause");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after pause");
  require(readU64LEAt(stateAccount.data, 0) === 2n, "state marker after pause mismatch");

  const resumeSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.resume,
    pubkeys,
    writeData(2),
    [pausableAuthority],
  );
  pausableMintState = await getMint(connection, pausableMint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  pausableConfig = getPausableConfig(pausableMintState);
  require(pausableConfig !== null, "mint missing PausableConfig extension after generated resume");
  require(pausableConfig.paused === false, "pausable mint should be unpaused after generated resume");
  stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  require(stateAccount !== null, "state missing after resume");
  require(readU64LEAt(stateAccount.data, 0) === 3n, "state marker after resume mismatch");

  console.log(JSON.stringify({
    programId: programId.toBase58(),
    state: state.publicKey.toBase58(),
    pausableMint: pausableMint.publicKey.toBase58(),
    pausableAuthority: pausableAuthority.publicKey.toBase58(),
    tokenProgram: TOKEN_2022_PROGRAM_ID.toBase58(),
    signatures: {
      createPausableMintAccount: createPausableMintAccountSignature,
      initializePausableConfig: initPausableConfigSignature,
      initializePausableMint: initializePausableMintSignature,
      pause: pauseSignature,
      resume: resumeSignature,
    },
  }));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
