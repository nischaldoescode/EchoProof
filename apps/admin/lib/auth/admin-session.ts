// admin auth session helper
// @params none

import type { NextRequest } from "next/server";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";

export const ADMIN_SESSION_COOKIE = "ep_admin_session";
const encoder = new TextEncoder();
const decoder = new TextDecoder();

type AdminSessionPayload = {
  email: string;
  exp: number;
  iat: number;
};

export type StaticAdminSession = {
  email: string;
  expiresAt: Date;
};

export async function createAdminSessionToken(email: string) {
  const now = Math.floor(Date.now() / 1000);
  const payload: AdminSessionPayload = {
    email: email.trim().toLowerCase(),
    iat: now,
    exp: now + 60 * 60 * 8,
  };
  const body = base64UrlEncode(JSON.stringify(payload));
  const signature = await sign(body);
  return `${body}.${signature}`;
}

export async function verifyAdminSessionToken(token?: string | null) {
  if (!token) return null;

  const [body, signature] = token.split(".");
  if (!body || !signature) return null;

  const expected = await sign(body);
  if (!timingSafeEqual(signature, expected)) return null;

  let payload: AdminSessionPayload;
  try {
    payload = JSON.parse(base64UrlDecode(body)) as AdminSessionPayload;
  } catch {
    return null;
  }

  if (!payload.email || !payload.exp) return null;
  if (payload.exp <= Math.floor(Date.now() / 1000)) return null;
  if (!isAllowedAdminEmail(payload.email)) return null;

  return {
    email: payload.email,
    expiresAt: new Date(payload.exp * 1000),
  } satisfies StaticAdminSession;
}

export async function adminSessionFromRequest(request: NextRequest) {
  return verifyAdminSessionToken(
    request.cookies.get(ADMIN_SESSION_COOKIE)?.value,
  );
}

export function hasStaticAdminLoginConfig() {
  return Boolean(adminPassword() && sessionSecret());
}

export function verifyAdminPassword(value: string) {
  const configured = adminPassword();
  if (!configured) return false;
  return timingSafeEqual(value, configured);
}

export const verifyAdminAccessKey = verifyAdminPassword;

export function staticAdminEmail() {
  return (process.env.ADMIN_EMAIL || "support@echoproof.online")
    .trim()
    .toLowerCase();
}

function adminPassword() {
  return (
    process.env.ADMIN_PASSWORD ||
    process.env.ADMIN_ACCESS_PASSWORD ||
    process.env.ADMIN_ACCESS_KEY ||
    ""
  );
}

function sessionSecret() {
  return process.env.ADMIN_SESSION_SECRET || "";
}

async function sign(value: string) {
  const secret = sessionSecret();
  if (!secret) {
    throw new Error("ADMIN_SESSION_SECRET is required for admin password login");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return base64UrlFromBytes(new Uint8Array(signature));
}

function timingSafeEqual(left: string, right: string) {
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  if (leftBytes.length !== rightBytes.length) return false;

  let diff = 0;
  for (let i = 0; i < leftBytes.length; i += 1) {
    diff |= leftBytes[i] ^ rightBytes[i];
  }
  return diff === 0;
}

function base64UrlEncode(value: string) {
  return base64UrlFromBytes(encoder.encode(value));
}

function base64UrlDecode(value: string) {
  const padded = value.padEnd(value.length + ((4 - (value.length % 4)) % 4), "=");
  const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return decoder.decode(bytes);
}

function base64UrlFromBytes(bytes: Uint8Array) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
