import { createSign } from "node:crypto";

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type DataApiRow = {
  dimensionValues?: Array<{ value?: string }>;
  metricValues?: Array<{ value?: string }>;
};

type DataApiResponse = {
  rows?: DataApiRow[];
};

export type FirebaseAnalyticsDashboard = {
  configured: boolean;
  error?: string;
  overview: {
    activeUsers: number;
    newUsers: number;
    sessions: number;
    events: number;
  };
  daily: Array<{ date: string; activeUsers: number; events: number }>;
  topEvents: Array<{ name: string; count: number; users: number }>;
};

const emptyDashboard: FirebaseAnalyticsDashboard = {
  configured: false,
  overview: { activeUsers: 0, newUsers: 0, sessions: 0, events: 0 },
  daily: [],
  topEvents: [],
};

export async function getFirebaseAnalyticsDashboard(): Promise<FirebaseAnalyticsDashboard> {
  const propertyId = process.env.FIREBASE_ANALYTICS_PROPERTY_ID?.trim();
  const serviceAccountRaw = process.env.FIREBASE_ANALYTICS_SERVICE_ACCOUNT_JSON;
  if (!propertyId || !serviceAccountRaw) return emptyDashboard;

  try {
    const serviceAccount = JSON.parse(serviceAccountRaw) as ServiceAccount;
    if (!serviceAccount.client_email || !serviceAccount.private_key) {
      return { ...emptyDashboard, error: "Analytics service account is incomplete." };
    }
    const accessToken = await getAccessToken(serviceAccount);
    const [overviewReport, dailyReport, eventsReport] = await Promise.all([
      runReport(accessToken, propertyId, {
        dateRanges: [{ startDate: "30daysAgo", endDate: "today" }],
        metrics: [
          { name: "activeUsers" },
          { name: "newUsers" },
          { name: "sessions" },
          { name: "eventCount" },
        ],
      }),
      runReport(accessToken, propertyId, {
        dateRanges: [{ startDate: "30daysAgo", endDate: "today" }],
        dimensions: [{ name: "date" }],
        metrics: [{ name: "activeUsers" }, { name: "eventCount" }],
        orderBys: [
          {
            dimension: { dimensionName: "date" },
            desc: false,
          },
        ],
        limit: "31",
      }),
      runReport(accessToken, propertyId, {
        dateRanges: [{ startDate: "30daysAgo", endDate: "today" }],
        dimensions: [{ name: "eventName" }],
        metrics: [{ name: "eventCount" }, { name: "activeUsers" }],
        orderBys: [
          {
            metric: { metricName: "eventCount" },
            desc: true,
          },
        ],
        limit: "12",
      }),
    ]);

    const overviewValues = overviewReport.rows?.[0]?.metricValues ?? [];
    return {
      configured: true,
      overview: {
        activeUsers: toNumber(overviewValues[0]?.value),
        newUsers: toNumber(overviewValues[1]?.value),
        sessions: toNumber(overviewValues[2]?.value),
        events: toNumber(overviewValues[3]?.value),
      },
      daily: (dailyReport.rows ?? []).map((row) => ({
        date: formatDate(row.dimensionValues?.[0]?.value),
        activeUsers: toNumber(row.metricValues?.[0]?.value),
        events: toNumber(row.metricValues?.[1]?.value),
      })),
      topEvents: (eventsReport.rows ?? []).map((row) => ({
        name: row.dimensionValues?.[0]?.value ?? "unknown",
        count: toNumber(row.metricValues?.[0]?.value),
        users: toNumber(row.metricValues?.[1]?.value),
      })),
    };
  } catch {
    return {
      ...emptyDashboard,
      configured: true,
      error: "Firebase Analytics could not be loaded. Check the server configuration and Analytics Viewer access.",
    };
  }
}

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const assertion = signJwt(
    {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/analytics.readonly",
      aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    serviceAccount.private_key.replace(/\\n/g, "\n"),
  );
  const response = await fetch(
    serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
      cache: "no-store",
    },
  );
  if (!response.ok) throw new Error("token request failed");
  const data = (await response.json()) as { access_token?: string };
  if (!data.access_token) throw new Error("token missing");
  return data.access_token;
}

function signJwt(payload: Record<string, unknown>, privateKey: string): string {
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = base64Url(JSON.stringify(payload));
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${body}`);
  signer.end();
  return `${header}.${body}.${signer.sign(privateKey).toString("base64url")}`;
}

function base64Url(value: string): string {
  return Buffer.from(value).toString("base64url");
}

async function runReport(
  accessToken: string,
  propertyId: string,
  body: Record<string, unknown>,
): Promise<DataApiResponse> {
  const response = await fetch(
    `https://analyticsdata.googleapis.com/v1beta/properties/${encodeURIComponent(propertyId)}:runReport`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      cache: "no-store",
    },
  );
  if (!response.ok) throw new Error("analytics report failed");
  return (await response.json()) as DataApiResponse;
}

function toNumber(value: string | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatDate(value: string | undefined): string {
  if (!value || !/^\d{8}$/.test(value)) return value ?? "";
  return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`;
}
