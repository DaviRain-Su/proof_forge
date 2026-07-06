import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  createMint,
  getOrCreateAssociatedTokenAccount,
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
  const expectedNames = ["close_account"];
  if (JSON.stringify(names) !== JSON.stringify(expectedNames)) {
    throw new Error(`instruction names mismatch: ${JSON.stringify(names)}`);
  }
  const instruction = instructions[0];
  if (instruction.tag !== 0 || instruction.minDataLen !== 1) {
    throw new Error(`instruction ABI mismatch: ${JSON.stringify(instruction)}`);
  }
  if ((instruction.params ?? []).length !== 0) {
    throw new Error(`close_account should not declare params: ${JSON.stringify(instruction.params)}`);
  }

  const cpis = artifact.solanaExtensions?.cpis ?? [];
  if (cpis.length !== 1) {
    throw new Error(`expected one CPI definition: ${JSON.stringify(cpis)}`);
  }
  const cpi = cpis[0];
  if (
    cpi.name !== "token_close" ||
    cpi.program !== "spl_token" ||
    cpi.protocol !== "spl-token" ||
    cpi.instruction !== "close_account" ||
    cpi.dataLayout !== "spl-token.close_account"
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

async function invoke(connection, payer, programId, keys) {
  const ix = new TransactionInstruction({
    programId,
    keys,
    data: Buffer.from([0]),
  });
  return sendAndPollTransaction(connection, new Transaction().add(ix), [payer]);
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
  const destination = await createSystemWallet(connection, payer);
  const decimals = Number(process.env.PROOF_FORGE_SOLANA_TOKEN_DECIMALS ?? "9");
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
  const tokenAccount = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint,
    payer.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_PROGRAM_ID
  );
  if (tokenAccount.amount !== 0n) {
    throw new Error(`token account must be empty before close: ${tokenAccount.amount}`);
  }

  const closeAccountBefore = await connection.getAccountInfo(tokenAccount.address, "confirmed");
  if (closeAccountBefore === null) {
    throw new Error(`token account not found before close: ${tokenAccount.address.toBase58()}`);
  }
  const destinationBefore = await connection.getBalance(destination.publicKey, "confirmed");

  const pubkeys = {
    last_close_marker: state.publicKey,
    token_account: tokenAccount.address,
    destination: destination.publicKey,
    authority: payer.publicKey,
    spl_token: TOKEN_PROGRAM_ID,
  };
  const keys = buildKeys(accounts, pubkeys);

  const signature = await invoke(connection, payer, programId, keys);
  const closeAccountAfter = await connection.getAccountInfo(tokenAccount.address, "confirmed");
  if (closeAccountAfter !== null) {
    throw new Error(`token account still exists after close: ${tokenAccount.address.toBase58()}`);
  }

  const destinationAfter = await connection.getBalance(destination.publicKey, "confirmed");
  const expectedDestinationAfter = BigInt(destinationBefore) + BigInt(closeAccountBefore.lamports);
  if (BigInt(destinationAfter) !== expectedDestinationAfter) {
    throw new Error(`destination lamports mismatch: expected ${expectedDestinationAfter}, got ${destinationAfter}`);
  }

  const stateAccount = await connection.getAccountInfo(state.publicKey, "confirmed");
  if (stateAccount === null) {
    throw new Error(`state account not found: ${state.publicKey.toBase58()}`);
  }
  const recordedMarker = readU64LEAt(stateAccount.data, 0);
  if (recordedMarker !== 1n) {
    throw new Error(`state last_close_marker mismatch: expected 1, got ${recordedMarker}`);
  }

  console.log(JSON.stringify({
    programId: programId.toBase58(),
    state: state.publicKey.toBase58(),
    payer: payer.publicKey.toBase58(),
    mint: mint.toBase58(),
    tokenAccount: tokenAccount.address.toBase58(),
    destination: destination.publicKey.toBase58(),
    tokenProgram: TOKEN_PROGRAM_ID.toBase58(),
    signature,
    decimals,
    closedLamports: closeAccountBefore.lamports.toString(),
    destinationBefore: destinationBefore.toString(),
    destinationAfter: destinationAfter.toString(),
    recordedMarker: recordedMarker.toString(),
  }));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
