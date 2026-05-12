import { cache } from "react";
import type { Metadata } from "next";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import { supabaseAdmin as supabase } from "@/lib/supabase";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type Props = {
  params: Promise<{ id: string }>;
};

type EchoAuthor = {
  username: string | null;
  display_name: string | null;
  avatar_url: string | null;
  trust_tier: string | null;
  is_public: boolean | null;
};

type EchoRow = {
  id: string;
  title: string | null;
  content: string;
  status: string;
  category: string | null;
  confidence_score: number | null;
  support_count: number | null;
  challenge_count: number | null;
  created_at: string;
  users_public: EchoAuthor | EchoAuthor[] | null;
};

const visibleStatuses = new Set([
  "active",
  "pending_verification",
  "under_review",
  "verified",
  "controversial",
  "disputed",
]);

function normalizeEchoId(value: string) {
  let decoded = value;
  try {
    decoded = decodeURIComponent(value);
  } catch {
    decoded = value;
  }

  return decoded.trim();
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
}

function publicSiteUrl() {
  return (process.env.NEXT_PUBLIC_SITE_URL || "https://echoproof.online").replace(
    /\/$/,
    "",
  );
}

function firstRelation<T>(value: T | T[] | null | undefined) {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function summary(content?: string | null) {
  const clean = (content || "").replace(/\s+/g, " ").trim();
  if (!clean) return "Open this echo in Echoproof.";
  return clean.length > 160 ? `${clean.slice(0, 157)}...` : clean;
}

function shortId(id: string) {
  return id.length > 16 ? `${id.slice(0, 8)}...${id.slice(-4)}` : id;
}

const loadEcho = cache(async (echoId: string) => {
  if (!isUuid(echoId)) return null;

  const { data, error } = await supabase
    .from("echoes")
    .select(
      `
        id, title, content, status, category, confidence_score,
        support_count, challenge_count, created_at,
        users_public(username, display_name, avatar_url, trust_tier, is_public)
      `,
    )
    .eq("id", echoId)
    .maybeSingle();

  if (error || !data) return null;

  const row = data as EchoRow;
  if (!visibleStatuses.has(row.status)) return null;

  return {
    ...row,
    author: firstRelation(row.users_public),
  };
});

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id: rawId } = await params;
  const echoId = normalizeEchoId(rawId);
  const echo = await loadEcho(echoId);
  const title = echo?.title?.trim() || "Echo on Echoproof";
  const description = summary(echo?.content);
  const url = `${publicSiteUrl()}/echo/${encodeURIComponent(echoId)}`;
  const image = `${publicSiteUrl()}/og-image.png`;

  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      type: "article",
      url,
      title,
      description,
      images: [{ url: image, width: 1200, height: 630, alt: title }],
      siteName: "Echoproof",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [image],
    },
    robots: echo ? undefined : { index: false, follow: false },
    other: {
      "al:android:url": `echoproof://echo/${echoId}`,
      "al:android:app_name": "Echoproof",
      "al:android:package": "com.echoproof.app",
      "al:ios:url": `echoproof://echo/${echoId}`,
      "al:ios:app_name": "Echoproof",
    },
  };
}

export default async function EchoLandingPage({ params }: Props) {
  const { id: rawId } = await params;
  const echoId = normalizeEchoId(rawId);
  const echo = await loadEcho(echoId);
  const author = echo?.author;
  const displayName =
    author?.display_name || (author?.username ? `@${author.username}` : "Echoproof");

  return (
    <>
      <Nav />
      <main className="ep-page-enter flex-1 bg-[#F8F7F5] px-5 pb-20 pt-24">
        <div className="mx-auto w-full max-w-3xl">
          <div className="mb-5 flex items-center gap-3">
            <div className="h-12 w-12 overflow-hidden rounded-2xl ring-1 ring-black/5">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/logo.png"
                width={48}
                height={48}
                alt="Echoproof"
                className="h-full w-full object-cover"
              />
            </div>
            <div>
              <p className="text-sm font-bold text-charcoal">Echoproof</p>
              <p className="text-xs text-neutral-500">Public echo preview</p>
            </div>
          </div>

          <section className="ep-card-in rounded-[22px] border border-border-subtle bg-white p-5 shadow-[0_18px_60px_rgba(26,26,26,0.08)] sm:p-7">
            {echo ? (
              <>
                <div className="mb-5 flex items-start gap-3">
                  <div className="h-11 w-11 shrink-0 overflow-hidden rounded-full bg-fern-light ring-1 ring-fern-green/20">
                    {author?.avatar_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={author.avatar_url}
                        alt={displayName}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center text-sm font-bold uppercase text-fern-dark">
                        {(author?.username || "e")[0]}
                      </div>
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-bold text-charcoal">
                      {displayName}
                    </p>
                    <p className="truncate text-xs text-neutral-500">
                      @{author?.username || "echoproof"} · echo #{shortId(echoId)}
                    </p>
                  </div>
                </div>

                <p className="mb-3 inline-flex rounded-full bg-fern-light px-3 py-1 text-xs font-bold uppercase text-fern-dark">
                  {echo.status.replace(/_/g, " ")}
                </p>

                <h1 className="text-2xl font-bold leading-tight text-charcoal sm:text-3xl">
                  {echo.title || "Echo"}
                </h1>

                <p className="mt-4 whitespace-pre-wrap text-[15px] leading-7 text-neutral-700">
                  {echo.content}
                </p>

                <div className="mt-6 grid grid-cols-3 gap-2">
                  {[
                    {
                      label: "Category",
                      value: echo.category?.replace(/_/g, " ") || "other",
                    },
                    {
                      label: "Confidence",
                      value: `${Number(echo.confidence_score ?? 0).toFixed(0)}%`,
                    },
                    {
                      label: "Signals",
                      value: `${echo.support_count ?? 0}/${echo.challenge_count ?? 0}`,
                    },
                  ].map((stat) => (
                    <div
                      key={stat.label}
                      className="rounded-xl bg-[#F8F7F5] px-3 py-3 text-center"
                    >
                      <p className="text-[11px] uppercase text-neutral-400">
                        {stat.label}
                      </p>
                      <p className="mt-1 truncate text-sm font-bold capitalize text-charcoal">
                        {stat.value}
                      </p>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div className="py-8 text-center">
                <div className="mx-auto mb-5 h-12 w-12 rounded-2xl bg-neutral-100 ep-shimmer" />
                <h1 className="text-2xl font-bold text-charcoal">
                  Echo unavailable
                </h1>
                <p className="mx-auto mt-3 max-w-sm text-sm leading-6 text-neutral-500">
                  This echo may have been removed, made unavailable, or the link
                  may be incomplete.
                </p>
              </div>
            )}

            <div className="mt-7 grid gap-3 sm:grid-cols-[1fr_auto]">
              <a
                href={`echoproof://echo/${echoId}`}
                className="ep-hover-lift flex h-12 items-center justify-center rounded-xl bg-charcoal px-6 text-sm font-bold text-white"
              >
                Open in Echoproof
              </a>
              <div className="flex h-12 items-center justify-center rounded-xl border border-border-subtle px-5 text-sm font-semibold text-neutral-500">
                Android download coming soon
              </div>
            </div>
          </section>
        </div>
      </main>
      <Footer />
    </>
  );
}
