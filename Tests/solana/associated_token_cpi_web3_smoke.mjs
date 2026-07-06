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
  TOKEN_PROGRAM_ID,
  createMint,
  getAccount,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import fs from "node:fs";

function readKeypair(path) {
  const bytes = JSON.parse(fs.readFileSync(path, "utf8"));
  return Keypair.fromSecretKey(Uint8Array.from(bytes));
}

function readU64LEAt(data, offset) {
  if (data.length < offset + 8) {
    throw new Error(`expected at least ${offset + 8} bytes, got ${data.length}`);
  }
  return Buffer.from(data).readBigUInt64LE(offset);
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

async function createSystemWallet(connection, payer) {
  const wallet = Keypair.generate();
  const lamports = await connection.getMinimumBalanceForRentExemption(0);
  const ix = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: wallet.publicKey,
    lamports,
    space: 0,
    programId: SystemProgram.programId,
  });
  await sendAndPollTransaction(connection, new Transaction().add(ix), [payer, wallet]);
  return wallet;
}

function readArtifact(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function validateInstructionSchemas(artifact) {
  const instructions = artifact.solanaInstructions ?? [];
  const names = instructions.map((instruction) => instruction.name);
  const expectedNames = ["create_associated"];
  if (JSON.stringify(names) !== JSON.stringify(expectedNames)) {
    throw new Error(`instruction names mismatch: ${JSON.stringify(names)}`);
  }
  const instruction = instructions[0];
  if (instruction.tag !== 0 || instruction.minDataLen !== 1) {
    throw new Error(`instruction ABI mismatch: ${JSON.stringify(instruction)}`);
  }
  if ((instruction.params ?? []).length !== 0) {
    throw new Error(`create_associated should not declare params: ${JSON.stringify(instruction.params)}`);
  }

  const cpis = artifact.solanaExtensions?.cpis ?? [];
  if (cpis.length !== 1) {
    throw new Error(`expected one CPI definition: ${JSON.stringify(cpis)}`);
  }
  const cpi = cpis[0];
  if (
    cpi.name !== "create_associated_token" ||
    cpi.program !== "associated_token" ||
    cpi.protocol !== "associated-token" ||
    cpi.instruction !== "create_idempotent" ||
    cpi.dataLayout !== "associated-token.create_idempotent" ||
    cpi.tokenProgram !== "spl_token"
  ) {
    throw new Error(`CPI schema mismatch: ${JSON.stringify(cpi)}`);
  }
  return instruction.accounts ?? [];
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

async function invoke(connection, payer, programId, keys, extraInstructions = []) {
  const ix = new TransactionInstruction({
    programId,
    keys,
    data: Buffer.from([0]),
  });
  const transaction = new Transaction().add(ix);
  for (const extraIx of extraInstructions) {
    transaction.add(extraIx);
  }
  return sendAndPollTransaction(connection, transaction, [payer]);
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
  const accounts = validateInstructionSchemas(artifact);
  const connection = new Connection(rpcUrl, {
    commitment: "confirmed",
    wsEndpoint: wsUrl,
  });
  const payer = readKeypair(payerPath);
  const programId = new PublicKey(programIdValue);
  const state = await createProgramState(connection, payer, programId, 8);
  const decimals = Number(process.env.PROOF_FORGE_SOLANA_TOKEN_DECIMALS ?? "9");
  const wallet = await createSystemWallet(connection, payer);
  const mint = await createMint(
    connection,
    payer,
    payer.publicKey,
    null,
    decimals,
    undefined,
    { commitment: "confirmed" },
    TOKEN_PROGRAM_ID
  );
  const associatedAccount = getAssociatedTokenAddressSync(
    mint,
    wallet.publicKey,
    false,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  const before = await connection.getAccountInfo(associatedAccount, "confirmed");
  if (before !== null) {
    throw new Error(`associated token account already exists: ${associatedAccount.toBase58()}`);
  }

  const pubkeys = {
    last_created_marker: state.publicKey,
    payer: payer.publicKey,
    associated_account: associatedAccount,
    wallet: wallet.publicKey,
    mint,
    system_program: SystemProgram.programId,
    spl_token: TOKEN_PROGRAM_ID,
    associated_token: ASSOCIATED_TOKEN_PROGRAM_ID,
  };
  const keys = buildKeys(accounts, pubkeys);

  const signature = await invoke(connection, payer, programId, keys);
  const secondSignature = await invoke(connection, payer, programId, keys, [
    SystemProgram.transfer({
      fromPubkey: payer.publicKey,
      toPubkey: payer.publicKey,
      lamports: 0,
    }),
  ]);
  const tokenAccount = await getAccount(connection, associatedAccount, "confirmed", TOKEN_PROGRAM_ID);
  if (!tokenAccount.owner.equals(wallet.publicKey)) {
    throw new Error(`associated account owner mismatch: ${tokenAccount.owner.toBase58()}`);
  }
  if (!tokenAccount.mint.equals(mint)) {
    throw new Error(`associated account mint mismatch: ${tokenAccount.mint.toBase58()}`);
  }
  if (tokenAccount.amount !== 0n) {
    throw new Error(`associated account amount mismatch: ${tokenAccount.amount}`);
  }

  const stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  if (stateAccount === null) {
    throw new Error(`state account not found: ${state.publicKey.toBase58()}`);
  }
  const recordedMarker = readU64LEAt(stateAccount.data, 0);
  if (recordedMarker !== 1n) {
    throw new Error(`state last_created_marker mismatch: expected 1, got ${recordedMarker}`);
  }

  console.log(JSON.stringify({
    programId: programId.toBase58(),
    state: state.publicKey.toBase58(),
    payer: payer.publicKey.toBase58(),
    wallet: wallet.publicKey.toBase58(),
    mint: mint.toBase58(),
    associatedAccount: associatedAccount.toBase58(),
    tokenProgram: TOKEN_PROGRAM_ID.toBase58(),
    associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID.toBase58(),
    signature,
    secondSignature,
    decimals,
    recordedMarker: recordedMarker.toString(),
    associatedAccountOwner: tokenAccount.owner.toBase58(),
    associatedAccountMint: tokenAccount.mint.toBase58(),
    associatedAccountAmount: tokenAccount.amount.toString(),
  }));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
