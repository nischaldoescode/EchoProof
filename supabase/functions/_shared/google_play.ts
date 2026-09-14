export const PLAY_PACKAGE_NAME = "com.echoproof.app";

export type PlaySubscriptionV2 = {
  subscriptionState?: string;
  acknowledgementState?: string;
  startTime?: string;
  latestOrderId?: string;
  externalAccountIdentifiers?: {
    obfuscatedExternalAccountId?: string;
  };
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
    latestSuccessfulOrderId?: string;
    autoRenewingPlan?: {
      recurringPrice?: {
        currencyCode?: string;
        units?: string | number;
        nanos?: number;
      };
    };
  }>;
};

export class GooglePlayApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "GooglePlayApiError";
    this.status = status;
  }
}

function base64UrlEncode(value: string | Uint8Array): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

export async function getGoogleAccessToken(
  serviceAccountJson: string,
): Promise<string> {
  const serviceAccount = JSON.parse(serviceAccountJson) as {
    client_email?: string;
    private_key?: string;
  };
  if (!serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error("Google Play service account is incomplete");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const keyData = serviceAccount.private_key
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binaryKey = Uint8Array.from(atob(keyData), (char) => char.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`,
    }),
  });
  if (!tokenResponse.ok) {
    throw new GooglePlayApiError(
      tokenResponse.status,
      `Google OAuth token request failed: ${await tokenResponse.text()}`,
    );
  }

  const token = await tokenResponse.json() as { access_token?: string };
  if (!token.access_token) throw new Error("Google OAuth response had no access token");
  return token.access_token;
}

export async function getSubscriptionV2(
  accessToken: string,
  purchaseToken: string,
): Promise<PlaySubscriptionV2> {
  const url = new URL(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PLAY_PACKAGE_NAME}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
  );
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) {
    throw new GooglePlayApiError(
      response.status,
      `Google Play subscriptionsv2.get failed: ${await response.text()}`,
    );
  }
  return await response.json() as PlaySubscriptionV2;
}

export async function acknowledgeSubscription(
  accessToken: string,
  productId: string,
  purchaseToken: string,
): Promise<void> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PLAY_PACKAGE_NAME}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  if (!response.ok) {
    throw new GooglePlayApiError(
      response.status,
      `Google Play acknowledge failed: ${await response.text()}`,
    );
  }
}

export type PlaySubscriptionSnapshot = {
  state: string;
  status: string;
  productId: string | null;
  expiresAt: Date | null;
  expiresTimeMs: number | null;
  purchaseTimeMs: number | null;
  latestOrderId: string | null;
  obfuscatedAccountId: string | null;
  acknowledgementState: string | null;
  amountMicros: number | null;
  currencyCode: string | null;
  isEntitled: boolean;
};

export function snapshotSubscription(
  subscription: PlaySubscriptionV2,
  requestedProductId?: string,
  nowMs = Date.now(),
): PlaySubscriptionSnapshot {
  const lineItems = subscription.lineItems ?? [];
  const lineItem = requestedProductId
    ? lineItems.find((item) => item.productId === requestedProductId) ?? lineItems[0]
    : lineItems[0];
  const expiresTimeMs = lineItem?.expiryTime
    ? Date.parse(lineItem.expiryTime)
    : NaN;
  const safeExpiresTimeMs = Number.isFinite(expiresTimeMs) ? expiresTimeMs : null;
  const state = subscription.subscriptionState ?? "SUBSCRIPTION_STATE_UNSPECIFIED";
  const status = subscriptionStatus(state);
  const purchaseTimeMs = subscription.startTime
    ? Date.parse(subscription.startTime)
    : NaN;
  const safePurchaseTimeMs = Number.isFinite(purchaseTimeMs) ? purchaseTimeMs : null;
  const recurringPrice = lineItem?.autoRenewingPlan?.recurringPrice;
  const units = recurringPrice?.units === undefined
    ? null
    : Number(recurringPrice.units);
  const nanos = recurringPrice?.nanos === undefined ? 0 : Number(recurringPrice.nanos);
  const amountMicros = units !== null && Number.isFinite(units) && Number.isFinite(nanos)
    ? units * 1_000_000 + nanos / 1_000
    : null;
  const isEntitled = [
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
  ].includes(state) && safeExpiresTimeMs !== null && safeExpiresTimeMs > nowMs;

  return {
    state,
    status,
    productId: lineItem?.productId ?? null,
    expiresAt: safeExpiresTimeMs === null ? null : new Date(safeExpiresTimeMs),
    expiresTimeMs: safeExpiresTimeMs,
    purchaseTimeMs: safePurchaseTimeMs,
    latestOrderId: lineItem?.latestSuccessfulOrderId ?? subscription.latestOrderId ?? null,
    obfuscatedAccountId: subscription.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    acknowledgementState: subscription.acknowledgementState ?? null,
    amountMicros,
    currencyCode: recurringPrice?.currencyCode ?? null,
    isEntitled,
  };
}

export function subscriptionStatus(state: string): string {
  switch (state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      return "active";
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      return "grace_period";
    case "SUBSCRIPTION_STATE_CANCELED":
      return "canceled";
    case "SUBSCRIPTION_STATE_ON_HOLD":
      return "on_hold";
    case "SUBSCRIPTION_STATE_PAUSED":
      return "paused";
    case "SUBSCRIPTION_STATE_EXPIRED":
      return "expired";
    case "SUBSCRIPTION_STATE_PENDING":
      return "pending";
    case "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED":
      return "pending_canceled";
    case "SUBSCRIPTION_STATE_DEFERRED":
      return "deferred";
    default:
      return "unknown";
  }
}
