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
  createInitializeTransferHookInstruction,
  createTransferCheckedWithTransferHookInstruction,
  getAccount,
  getExtraAccountMetaAddress,
  getExtraAccountMetas,
  getMint,
  getMintLen,
  getOrCreateAssociatedTokenAccount,
  getTransferHook,
  mintTo,
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sendAndPollTransaction(connection, transaction, signers, options = {}) {
  const latest = await connection.getLatestBlockhash("confirmed");
  transaction.recentBlockhash = latest.blockhash;
  transaction.feePayer = signers[0].publicKey;
  transaction.sign(...signers);
  const signature = await connection.sendRawTransaction(transaction.serialize(), {
    skipPreflight: options.skipPreflight ?? false,
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

async function expectTransactionFailure(connection, transaction, signers) {
  try {
    await sendAndPollTransaction(connection, transaction, signers);
  } catch (err) {
    return String(err?.message ?? err);
  }
  throw new Error("expected transaction failure, but transaction succeeded");
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

async function createFundedSystemSigner(connection, payer, lamports) {
  const account = Keypair.generate();
  const ix = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: account.publicKey,
    lamports: Number(lamports),
    space: 0,
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
  return { mint, signature, mintLen };
}

function writeInitData(tag, rentLamports, extraMetaSpace, bump) {
  const data = Buffer.alloc(25);
  data.writeUInt8(tag, 0);
  data.writeBigUInt64LE(BigInt(rentLamports), 1);
  data.writeBigUInt64LE(BigInt(extraMetaSpace), 9);
  data.writeBigUInt64LE(BigInt(bump), 17);
  return data;
}

function validateInstructionSchemas(artifact) {
  require(artifact.fixture === "solana-spl-token-2022-transfer-hook-elf", `fixture mismatch: ${artifact.fixture}`);
  const instructions = artifact.solanaInstructions ?? [];
  const names = instructions.map((instruction) => instruction.name);
  const expectedNames = ["initialize_extra_account_meta_list", "execute"];
  require(JSON.stringify(names) === JSON.stringify(expectedNames), `instruction names mismatch: ${JSON.stringify(names)}`);

  const expectedAccounts = [
    "source",
    "mint",
    "destination",
    "authority",
    "extra_account_meta_list",
    "sentinel",
    "system_program",
  ];
  for (const instruction of instructions) {
    const accounts = (instruction.accounts ?? []).map((account) => account.name);
    require(
      JSON.stringify(accounts) === JSON.stringify(expectedAccounts),
      `instruction ${instruction.name} account schema mismatch: ${JSON.stringify(accounts)}`,
    );
  }

  const [init, execute] = instructions;
  require(init.minDataLen === 25, `init minDataLen mismatch: ${init.minDataLen}`);
  require(
    JSON.stringify((init.params ?? []).map((param) => param.offset)) === JSON.stringify([1, 9, 17]),
    `init param offsets mismatch: ${JSON.stringify(init.params)}`,
  );
  require(execute.minDataLen === 16, `execute minDataLen mismatch: ${execute.minDataLen}`);
  require(execute.params?.[0]?.name === "amount" && execute.params[0].offset === 8, `execute param mismatch: ${JSON.stringify(execute.params)}`);
  require(init.accounts[0].signer === true && init.accounts[0].writable === true, "init source must be signer+writable");
  require(execute.accounts[0].signer === false && execute.accounts[0].writable === false, "execute source must be readonly/non-signer");
  require(execute.accounts[4].writable === false, "execute validation PDA must be readonly");

  const actions = artifact.solanaIdl?.entrypointActions?.transferHookExtraMetas ?? [];
  require(actions.length === 1, `transfer-hook action mismatch: ${JSON.stringify(actions)}`);
  const action = actions[0];
  require(
    JSON.stringify(action.extraAccounts) === JSON.stringify(["sentinel", "system_program"]),
    `extra account route mismatch: ${JSON.stringify(action)}`,
  );
  require(action.executeDiscriminator === "692565c54bfb661a", "execute discriminator mismatch");
  require(action.extraAccountCount === 2, `extra account count mismatch: ${JSON.stringify(action)}`);
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

async function invokeGenerated(connection, payer, programId, instruction, pubkeys, data, extraSigners = []) {
  const ix = new TransactionInstruction({
    programId,
    keys: buildKeys(instruction.accounts ?? [], pubkeys),
    data,
  });
  return sendAndPollTransaction(connection, new Transaction().add(ix), [payer, ...extraSigners]);
}

function pubkeySet(keys) {
  return new Set(keys.map((key) => key.pubkey.toBase58()));
}

async function main() {
  const rpcUrl = process.env.PROOF_FORGE_SOLANA_RPC_URL;
  const wsUrl = process.env.PROOF_FORGE_SOLANA_WS_URL;
  const payerPath = process.env.PROOF_FORGE_SOLANA_PAYER;
  const programIdValue = process.env.PROOF_FORGE_SOLANA_PROGRAM_ID;
  const artifactPath = process.env.PROOF_FORGE_SOLANA_ARTIFACT;
  require(rpcUrl, "PROOF_FORGE_SOLANA_RPC_URL is required");
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

  const decimals = Number(process.env.PROOF_FORGE_SOLANA_TOKEN_DECIMALS ?? "0");
  const initialSupply = BigInt(process.env.PROOF_FORGE_SOLANA_TOKEN_INITIAL_SUPPLY ?? "100");
  const allowedAmount = BigInt(process.env.PROOF_FORGE_SOLANA_TRANSFER_HOOK_ALLOWED_AMOUNT ?? "10");
  const rejectedAmount = BigInt(process.env.PROOF_FORGE_SOLANA_TRANSFER_HOOK_REJECTED_AMOUNT ?? "60");
  require(allowedAmount <= 50n, `allowed amount must satisfy generated hook cap: ${allowedAmount}`);
  require(rejectedAmount > 50n, `rejected amount must exceed generated hook cap: ${rejectedAmount}`);
  require(initialSupply >= allowedAmount + rejectedAmount, `initial supply too small: ${initialSupply}`);

  const { mint, signature: createMintAccountSignature, mintLen } =
    await createMintAccountWithExtensions(connection, payer, [ExtensionType.TransferHook]);
  const sentinel = await createScratchAccount(connection, payer);
  const initAuthority = await createScratchAccount(connection, payer);
  const [extraAccountMetaList, bump] = PublicKey.findProgramAddressSync(
    [Buffer.from("extra-account-metas"), mint.publicKey.toBuffer()],
    programId,
  );
  const expectedExtraAccountMetaList = getExtraAccountMetaAddress(mint.publicKey, programId);
  require(
    extraAccountMetaList.equals(expectedExtraAccountMetaList),
    `extra account meta PDA mismatch: ${extraAccountMetaList.toBase58()} != ${expectedExtraAccountMetaList.toBase58()}`,
  );

  const initializeMintSignature = await sendAndPollTransaction(
    connection,
    new Transaction().add(
      createInitializeTransferHookInstruction(
        mint.publicKey,
        payer.publicKey,
        programId,
        TOKEN_2022_PROGRAM_ID,
      ),
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
  const transferHookMint = await getMint(connection, mint.publicKey, "confirmed", TOKEN_2022_PROGRAM_ID);
  const transferHook = getTransferHook(transferHookMint);
  require(transferHook !== null, "mint missing TransferHook extension");
  require(transferHook.programId.equals(programId), `transfer hook program mismatch: ${transferHook.programId.toBase58()}`);

  const sourceAta = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint.publicKey,
    payer.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_2022_PROGRAM_ID,
  );
  const destinationOwner = await createScratchAccount(connection, payer);
  const destinationAta = await getOrCreateAssociatedTokenAccount(
    connection,
    payer,
    mint.publicKey,
    destinationOwner.publicKey,
    false,
    "confirmed",
    undefined,
    TOKEN_2022_PROGRAM_ID,
  );
  const mintToSignature = await mintTo(
    connection,
    payer,
    mint.publicKey,
    sourceAta.address,
    payer.publicKey,
    initialSupply,
    [],
    { commitment: "confirmed" },
    TOKEN_2022_PROGRAM_ID,
  );

  const extraMetaSpace = 86n;
  const rentLamports = BigInt(await connection.getMinimumBalanceForRentExemption(Number(extraMetaSpace)));
  const initSource = await createFundedSystemSigner(connection, payer, rentLamports + 1_000_000n);
  const pubkeys = {
    source: initSource.publicKey,
    mint: mint.publicKey,
    destination: destinationAta.address,
    authority: initAuthority.publicKey,
    extra_account_meta_list: extraAccountMetaList,
    sentinel: sentinel.publicKey,
    system_program: SystemProgram.programId,
  };
  const initExtraMetaSignature = await invokeGenerated(
    connection,
    payer,
    programId,
    byName.initialize_extra_account_meta_list,
    pubkeys,
    writeInitData(0, rentLamports, extraMetaSpace, bump),
    [initSource],
  );

  const validationAccount = await connection.getAccountInfo(extraAccountMetaList, "confirmed");
  require(validationAccount !== null, `validation account not found: ${extraAccountMetaList.toBase58()}`);
  require(validationAccount.owner.equals(programId), `validation account owner mismatch: ${validationAccount.owner.toBase58()}`);
  require(validationAccount.data.length === Number(extraMetaSpace), `validation account size mismatch: ${validationAccount.data.length}`);
  const extraMetas = getExtraAccountMetas(validationAccount);
  require(extraMetas.length === 2, `expected two extra metas, got ${extraMetas.length}`);
  const sentinelMeta = new PublicKey(extraMetas[0].addressConfig);
  const systemProgramMeta = new PublicKey(extraMetas[1].addressConfig);
  require(sentinelMeta.equals(sentinel.publicKey), `sentinel route mismatch: ${sentinelMeta.toBase58()}`);
  require(systemProgramMeta.equals(SystemProgram.programId), `system program route mismatch: ${systemProgramMeta.toBase58()}`);
  for (const [idx, meta] of extraMetas.entries()) {
    require(meta.discriminator === 0, `extra meta ${idx} discriminator mismatch: ${meta.discriminator}`);
    require(meta.isSigner === false, `extra meta ${idx} signer should be false`);
    require(meta.isWritable === false, `extra meta ${idx} writable should be false`);
  }

  const successIx = await createTransferCheckedWithTransferHookInstruction(
    connection,
    sourceAta.address,
    mint.publicKey,
    destinationAta.address,
    payer.publicKey,
    allowedAmount,
    decimals,
    [],
    "confirmed",
    TOKEN_2022_PROGRAM_ID,
  );
  const successKeys = pubkeySet(successIx.keys);
  for (const routed of [sentinel.publicKey, SystemProgram.programId, programId, extraAccountMetaList]) {
    require(successKeys.has(routed.toBase58()), `transfer instruction missing routed account ${routed.toBase58()}`);
  }
  const successSignature = await sendAndPollTransaction(connection, new Transaction().add(successIx), [payer]);

  let sourceAccount = await getAccount(connection, sourceAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  let destinationAccount = await getAccount(connection, destinationAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  require(sourceAccount.amount === initialSupply - allowedAmount, `source after allowed transfer mismatch: ${sourceAccount.amount}`);
  require(destinationAccount.amount === allowedAmount, `destination after allowed transfer mismatch: ${destinationAccount.amount}`);

  const rejectIx = await createTransferCheckedWithTransferHookInstruction(
    connection,
    sourceAta.address,
    mint.publicKey,
    destinationAta.address,
    payer.publicKey,
    rejectedAmount,
    decimals,
    [],
    "confirmed",
    TOKEN_2022_PROGRAM_ID,
  );
  const rejectError = await expectTransactionFailure(connection, new Transaction().add(rejectIx), [payer]);
  sourceAccount = await getAccount(connection, sourceAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  destinationAccount = await getAccount(connection, destinationAta.address, "confirmed", TOKEN_2022_PROGRAM_ID);
  require(sourceAccount.amount === initialSupply - allowedAmount, `source changed after rejected transfer: ${sourceAccount.amount}`);
  require(destinationAccount.amount === allowedAmount, `destination changed after rejected transfer: ${destinationAccount.amount}`);

  console.log(JSON.stringify({
    programId: programId.toBase58(),
    payer: payer.publicKey.toBase58(),
    mint: mint.publicKey.toBase58(),
    mintLen,
    source: sourceAta.address.toBase58(),
    destination: destinationAta.address.toBase58(),
    extraAccountMetaList: extraAccountMetaList.toBase58(),
    sentinel: sentinel.publicKey.toBase58(),
    initAuthority: initAuthority.publicKey.toBase58(),
    initSource: initSource.publicKey.toBase58(),
    tokenProgram: TOKEN_2022_PROGRAM_ID.toBase58(),
    signatures: {
      createMintAccount: createMintAccountSignature,
      initializeMint: initializeMintSignature,
      mintTo: mintToSignature,
      initializeExtraMetas: initExtraMetaSignature,
      allowedTransfer: successSignature,
    },
    allowedAmount: allowedAmount.toString(),
    rejectedAmount: rejectedAmount.toString(),
    sourceAmount: sourceAccount.amount.toString(),
    destinationAmount: destinationAccount.amount.toString(),
    extraMetaCount: extraMetas.length,
    rejectError,
  }));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
