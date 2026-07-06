import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import fs from "node:fs";

const MEMO_PROGRAM_ID = new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr");

function readKeypair(path) {
  const bytes = JSON.parse(fs.readFileSync(path, "utf8"));
  return Keypair.fromSecretKey(Uint8Array.from(bytes));
}

function readU64LE(data) {
  if (data.length < 8) {
    throw new Error(`expected at least 8 bytes, got ${data.length}`);
  }
  return Buffer.from(data).readBigUInt64LE(0);
}

function memoPayloadFromText(text) {
  const payload = Buffer.alloc(8);
  const input = Buffer.from(text, "utf8");
  if (input.length > 8) {
    throw new Error(`memo text must fit in 8 bytes for this fixture: ${text}`);
  }
  input.copy(payload);
  return payload;
}

function writeMemoInstructionData(payload) {
  const data = Buffer.alloc(9);
  data[0] = 0;
  payload.copy(data, 1);
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

async function pollTransactionLogs(connection, signature) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    const logs = tx?.meta?.logMessages;
    if (logs && logs.length > 0) {
      return logs;
    }
    await sleep(500);
  }
  throw new Error(`transaction logs not available for ${signature}`);
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

async function main() {
  const rpcUrl = process.env.PROOF_FORGE_SOLANA_RPC_URL;
  const wsUrl = process.env.PROOF_FORGE_SOLANA_WS_URL;
  const payerPath = process.env.PROOF_FORGE_SOLANA_PAYER;
  const programIdValue = process.env.PROOF_FORGE_SOLANA_PROGRAM_ID;
  if (!rpcUrl || !payerPath || !programIdValue) {
    throw new Error("missing PROOF_FORGE_SOLANA_RPC_URL, PROOF_FORGE_SOLANA_PAYER, or PROOF_FORGE_SOLANA_PROGRAM_ID");
  }

  const connection = new Connection(rpcUrl, {
    commitment: "confirmed",
    wsEndpoint: wsUrl,
  });
  const payer = readKeypair(payerPath);
  const programId = new PublicKey(programIdValue);
  const state = await createProgramState(connection, payer, programId, 8);
  const memoText = process.env.PROOF_FORGE_SOLANA_MEMO_TEXT ?? "pfmemo!!";
  const memoPayload = memoPayloadFromText(memoText);
  const memoWord = memoPayload.readBigUInt64LE(0);

  const ix = new TransactionInstruction({
    programId,
    keys: [
      { pubkey: state.publicKey, isSigner: false, isWritable: true },
      { pubkey: MEMO_PROGRAM_ID, isSigner: false, isWritable: false },
    ],
    data: writeMemoInstructionData(memoPayload),
  });
  const signature = await sendAndPollTransaction(connection, new Transaction().add(ix), [payer]);

  const account = await connection.getAccountInfo(state.publicKey, "confirmed");
  if (account === null) {
    throw new Error(`state account not found: ${state.publicKey.toBase58()}`);
  }
  const recordedWord = readU64LE(account.data);
  if (recordedWord !== memoWord) {
    throw new Error(`state last_memo_word mismatch: expected ${memoWord}, got ${recordedWord}`);
  }

  const logs = await pollTransactionLogs(connection, signature);
  const memoProgram = MEMO_PROGRAM_ID.toBase58();
  if (!logs.some((line) => line.includes(memoProgram))) {
    throw new Error(`logs missing Memo program id ${memoProgram}: ${JSON.stringify(logs)}`);
  }
  if (!logs.some((line) => line.includes("Memo"))) {
    throw new Error(`logs missing Memo marker: ${JSON.stringify(logs)}`);
  }
  if (!logs.some((line) => line.includes(memoText))) {
    throw new Error(`logs missing memo text ${memoText}: ${JSON.stringify(logs)}`);
  }

  console.log(JSON.stringify({
    programId: programId.toBase58(),
    state: state.publicKey.toBase58(),
    payer: payer.publicKey.toBase58(),
    signature,
    memoProgram,
    memoText,
    memoWord: memoWord.toString(),
    recordedWord: recordedWord.toString(),
    logs,
  }));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
