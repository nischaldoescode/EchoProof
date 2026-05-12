import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
} from "https://esm.sh/@solana/web3.js@1.98.4?target=deno";

const MEMO_PROGRAM_ID = new PublicKey(
  "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
);

const BASE58_ALPHABET =
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

export interface SolanaMemoResult {
  signature: string;
  explorerUrl: string;
  cluster: string;
  payer: string;
}

export function solanaCluster(rpcUrl?: string): string {
  const url = (rpcUrl ?? Deno.env.get("SOLANA_RPC_URL") ?? "").toLowerCase();
  if (url.includes("mainnet")) return "mainnet-beta";
  if (url.includes("testnet")) return "testnet";
  return "devnet";
}

export function explorerUrl(signature: string, rpcUrl?: string): string {
  const cluster = solanaCluster(rpcUrl);
  const suffix = cluster === "mainnet-beta" ? "" : `?cluster=${cluster}`;
  return `https://explorer.solana.com/tx/${signature}${suffix}`;
}

export async function writeSolanaMemo(
  memo: string,
): Promise<SolanaMemoResult> {
  const memoBytes = new TextEncoder().encode(memo);
  if (memoBytes.length > 700) {
    throw new Error("memo is too large for a single solana transaction");
  }

  const rpcUrl =
    Deno.env.get("SOLANA_RPC_URL") ?? "https://api.devnet.solana.com";
  const payer = loadServerKeypair();
  const connection = new Connection(rpcUrl, {
    commitment: "confirmed",
    confirmTransactionInitialTimeout: 60_000,
  });

  const latest = await connection.getLatestBlockhash("confirmed");
  const tx = new Transaction();
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = latest.blockhash;
  tx.add(
    new TransactionInstruction({
      programId: MEMO_PROGRAM_ID,
      keys: [
        {
          pubkey: payer.publicKey,
          isSigner: true,
          isWritable: false,
        },
      ],
      data: memoBytes,
    }),
  );

  tx.sign(payer);

  const signature = await connection.sendRawTransaction(tx.serialize(), {
    maxRetries: 3,
    preflightCommitment: "confirmed",
    skipPreflight: false,
  });

  const confirmation = await connection.confirmTransaction(
    {
      signature,
      blockhash: latest.blockhash,
      lastValidBlockHeight: latest.lastValidBlockHeight,
    },
    "confirmed",
  );

  if (confirmation.value.err) {
    throw new Error(
      `solana transaction failed: ${JSON.stringify(confirmation.value.err)}`,
    );
  }

  return {
    signature,
    explorerUrl: explorerUrl(signature, rpcUrl),
    cluster: solanaCluster(rpcUrl),
    payer: payer.publicKey.toBase58(),
  };
}

export async function sha256Hex(value: string): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function loadServerKeypair(): Keypair {
  const raw = Deno.env.get("SOLANA_SERVER_KEYPAIR")?.trim();
  if (!raw) {
    throw new Error("missing SOLANA_SERVER_KEYPAIR edge function secret");
  }

  const secret = decodeSecretKey(raw);
  if (secret.length === 64) return Keypair.fromSecretKey(secret);
  if (secret.length === 32) return Keypair.fromSeed(secret);

  throw new Error(
    `SOLANA_SERVER_KEYPAIR must decode to 32 or 64 bytes, got ${secret.length}`,
  );
}

function decodeSecretKey(raw: string): Uint8Array {
  const json = tryDecodeJsonArray(raw);
  if (json) return json;

  const commaSeparated = tryDecodeCommaSeparated(raw);
  if (commaSeparated) return commaSeparated;

  const base64 = tryDecodeBase64(raw);
  if (base64 && (base64.length === 32 || base64.length === 64)) return base64;

  return decodeBase58(raw);
}

function tryDecodeJsonArray(raw: string): Uint8Array | null {
  if (!raw.startsWith("[")) return null;
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return null;
    return toByteArray(parsed);
  } catch {
    return null;
  }
}

function tryDecodeCommaSeparated(raw: string): Uint8Array | null {
  if (!raw.includes(",")) return null;
  const parts = raw.split(",").map((part) => Number(part.trim()));
  if (parts.some((part) => !Number.isInteger(part))) return null;
  return toByteArray(parts);
}

function tryDecodeBase64(raw: string): Uint8Array | null {
  if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(raw)) return null;
  try {
    const normalized = raw.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(
      Math.ceil(normalized.length / 4) * 4,
      "=",
    );
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  } catch {
    return null;
  }
}

function decodeBase58(raw: string): Uint8Array {
  if (!raw) throw new Error("empty base58 secret key");

  const bytes = [0];
  for (const char of raw) {
    const value = BASE58_ALPHABET.indexOf(char);
    if (value < 0) throw new Error("invalid base58 character in keypair");

    let carry = value;
    for (let i = 0; i < bytes.length; i++) {
      carry += bytes[i] * 58;
      bytes[i] = carry & 0xff;
      carry >>= 8;
    }

    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }

  for (const char of raw) {
    if (char !== "1") break;
    bytes.push(0);
  }

  return new Uint8Array(bytes.reverse());
}

function toByteArray(values: unknown[]): Uint8Array {
  const bytes = values.map((value) => Number(value));
  if (
    bytes.some((value) =>
      !Number.isInteger(value) || value < 0 || value > 255
    )
  ) {
    throw new Error("secret key contains a value outside byte range");
  }
  return new Uint8Array(bytes);
}
