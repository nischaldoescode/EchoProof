// public profile page — server component, app router only
// generateMetadata requires app router — never put this in pages/

import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { supabaseAdmin as supabase } from "@/lib/supabase";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

// next.js 16 app router — params is a Promise
interface Props {
  params: Promise<{ username: string }>;
}

const tierConfig: Record<string, { label: string; color: string; bg: string }> =
  {
    elite: { label: "Elite", color: "#2D7A4A", bg: "#E8F5EE" },
    high: { label: "High", color: "#2D7A4A", bg: "#E8F5EE" },
    medium: { label: "Medium", color: "#1A1A1A", bg: "#F0F0F0" },
    low: { label: "Low", color: "#5A5A5A", bg: "#F8F7F5" },
    unverified: { label: "Unverified", color: "#9A9A9A", bg: "#F8F7F5" },
  };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { username } = await params;

  const { data } = await supabase
    .from("users_public")
    .select("username, display_name, avatar_url, trust_tier, echo_count, bio")
    .eq("username", username)
    .eq("is_public", true)
    .maybeSingle();

  if (!data) {
    return {
      title: "User not found | Echoproof",
      description: "This profile doesn't exist on Echoproof.",
    };
  }

  const displayName = data.display_name || `@${data.username}`;
  const description =
    data.bio ||
    `${displayName} has posted ${data.echo_count ?? 0} echo${(data.echo_count ?? 0) === 1 ? "" : "s"} on Echoproof — the community-verified truth platform.`;
  const image = data.avatar_url || "/og-image.png";
  const url = `${process.env.NEXT_PUBLIC_SITE_URL}/user/${username}`;

  return {
    title: `${displayName} (@${data.username}) | Echoproof`,
    description,
    alternates: { canonical: url },
    openGraph: {
      type: "profile",
      url,
      title: `${displayName} on Echoproof`,
      description,
      images: [{ url: image, width: 400, height: 400, alt: displayName }],
      siteName: "Echoproof",
    },
    twitter: {
      card: "summary",
      title: `${displayName} on Echoproof`,
      description,
      images: [image],
    },
    other: {
      "al:android:url": `echoproof://user/${username}`,
      "al:android:app_name": "Echoproof",
      "al:android:package": "com.echoproof.app",
    },
  };
}

export default async function UserProfilePage({ params }: Props) {
  const { username } = await params;

  const { data: profile } = await supabase
    .from("users_public")
    .select(
      "id, username, display_name, avatar_url, trust_tier, trust_score, echo_count, proof_count, bio, is_public, created_at",
    )
    .eq("username", username)
    .maybeSingle();

  if (!profile) notFound();

  const tier = tierConfig[profile.trust_tier] ?? tierConfig.unverified;
  const displayName = profile.display_name || `@${profile.username}`;
  const joinedYear = new Date(profile.created_at).getFullYear();
  const skeletonCards = Array.from({ length: 4 });

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "Person",
            name: displayName,
            url: `${process.env.NEXT_PUBLIC_SITE_URL}/user/${username}`,
            image: profile.avatar_url,
            description: profile.bio,
          }),
        }}
      />

      <Nav />

      <main
        style={{
          flex: 1,
          background: "#F8F7F5",
          minHeight: "100svh",
          fontFamily: "'Josefin Sans', sans-serif",
        }}
      >
        <div
          style={{ maxWidth: 600, margin: "0 auto", padding: "88px 16px 80px" }}
        >
          {/* profile card */}
          <div
            style={{
              background: "#fff",
              borderRadius: 20,
              border: "1px solid #E6E6E6",
              padding: "24px 20px",
              marginBottom: 16,
              boxShadow: "0 2px 16px rgba(0,0,0,0.05)",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "flex-start",
                gap: 16,
                marginBottom: 20,
              }}
            >
              <div style={{ position: "relative", flexShrink: 0 }}>
                {profile.avatar_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={profile.avatar_url}
                    alt={displayName}
                    width={72}
                    height={72}
                    style={{
                      width: 72,
                      height: 72,
                      borderRadius: "50%",
                      objectFit: "cover",
                      border:
                        profile.trust_tier === "high" ||
                        profile.trust_tier === "elite"
                          ? "2px solid #4CAF6E"
                          : "1.5px solid #E6E6E6",
                    }}
                  />
                ) : (
                  <div
                    style={{
                      width: 72,
                      height: 72,
                      borderRadius: "50%",
                      background: "#E8F5EE",
                      border: "1.5px solid #4CAF6E40",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                    }}
                  >
                    <span
                      style={{
                        fontSize: 26,
                        fontWeight: 700,
                        color: "#2D7A4A",
                        textTransform: "uppercase",
                      }}
                    >
                      {profile.username?.[0] ?? "?"}
                    </span>
                  </div>
                )}
              </div>

              <div style={{ flex: 1, minWidth: 0 }}>
                <h1
                  style={{
                    fontSize: 18,
                    fontWeight: 700,
                    color: "#1A1A1A",
                    letterSpacing: "-0.02em",
                    margin: "0 0 2px",
                  }}
                >
                  {displayName}
                </h1>
                <p
                  style={{ fontSize: 13, color: "#9A9A9A", margin: "0 0 10px" }}
                >
                  @{profile.username} · joined {joinedYear}
                </p>
                <span
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    gap: 5,
                    padding: "3px 10px",
                    borderRadius: 999,
                    background: tier.bg,
                    fontSize: 11,
                    fontWeight: 600,
                    color: tier.color,
                  }}
                >
                  <span
                    style={{
                      width: 5,
                      height: 5,
                      borderRadius: "50%",
                      background: tier.color,
                    }}
                  />
                  {tier.label} trust
                </span>
              </div>
            </div>

            {profile.bio && (
              <p
                style={{
                  fontSize: 13,
                  color: "#5A5A5A",
                  lineHeight: 1.7,
                  marginBottom: 20,
                  paddingBottom: 20,
                  borderBottom: "1px solid #F0F0F0",
                }}
              >
                {profile.bio}
              </p>
            )}

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr 1fr",
                gap: 8,
              }}
            >
              {[
                { label: "Echoes", value: profile.echo_count ?? 0 },
                { label: "Proofs", value: profile.proof_count ?? 0 },
                { label: "Score", value: profile.trust_score ?? 0 },
              ].map((stat) => (
                <div
                  key={stat.label}
                  style={{
                    textAlign: "center",
                    padding: "12px 8px",
                    background: "#F8F7F5",
                    borderRadius: 12,
                  }}
                >
                  <p
                    style={{
                      fontSize: 20,
                      fontWeight: 700,
                      color: "#1A1A1A",
                      margin: "0 0 2px",
                      letterSpacing: "-0.02em",
                    }}
                  >
                    {stat.value}
                  </p>
                  <p
                    style={{
                      fontSize: 10,
                      color: "#9A9A9A",
                      margin: 0,
                      textTransform: "uppercase",
                      letterSpacing: "0.08em",
                    }}
                  >
                    {stat.label}
                  </p>
                </div>
              ))}
            </div>
          </div>

          {/* open in app */}
          <a
            href={`echoproof://user/${profile.username}`}
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 10,
              width: "100%",
              height: 52,
              borderRadius: 14,
              background: "#1A1A1A",
              color: "#fff",
              fontSize: 14,
              fontWeight: 600,
              textDecoration: "none",
              marginBottom: 16,
              boxSizing: "border-box",
              fontFamily: "'Josefin Sans', sans-serif",
            }}
          >
            <svg
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden
            >
              <path
                d="M3.18 23.76c.42.24.9.24 1.32 0L16.1 16.9l-3.28-3.28-9.64 10.14z"
                fill="#EA4335"
              />
              <path
                d="M20.82 10.03c-.42-.24-.9-.35-1.38-.35l-3.34 1.93 3.52 3.52 1.2-.69c.84-.48.84-1.68 0-2.16z"
                fill="#FBBC04"
              />
              <path
                d="M3.18.24A1.44 1.44 0 002 1.68v20.64c0 .6.33 1.13.82 1.44L15.54 12 3.18.24z"
                fill="#4285F4"
              />
              <path
                d="M4.5.24L16.1 7.1l-3.28 3.28L3.18.24A1.5 1.5 0 014.5.24z"
                fill="#34A853"
              />
            </svg>
            Open in Echoproof
          </a>

          {/* download fallback */}
          <a
            href="https://play.google.com/store/apps/details?id=com.echoproof.app"
            target="_blank"
            rel="noopener noreferrer"
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: "100%",
              height: 44,
              borderRadius: 14,
              border: "1px solid #E6E6E6",
              color: "#5A5A5A",
              fontSize: 13,
              fontWeight: 500,
              textDecoration: "none",
              marginBottom: 24,
              boxSizing: "border-box",
              fontFamily: "'Josefin Sans', sans-serif",
            }}
          >
            Don&apos;t have the app? Download on Android
          </a>

          {/* blurred echoes section */}
          <div style={{ position: "relative" }}>
            <p
              style={{
                fontSize: 11,
                fontWeight: 600,
                color: "#9A9A9A",
                letterSpacing: "0.14em",
                textTransform: "uppercase",
                marginBottom: 12,
              }}
            >
              Echoes
            </p>

            {/* skeleton cards — empty chrome only, no real data */}
            <div
              style={{
                filter: "blur(7px)",
                pointerEvents: "none",
                userSelect: "none",
                WebkitUserSelect: "none",
              }}
            >
              {skeletonCards.map((_, i) => (
                <div
                  key={i}
                  style={{
                    background: "#fff",
                    borderRadius: 16,
                    border: "1px solid #E6E6E6",
                    padding: "18px 18px 14px",
                    marginBottom: 12,
                  }}
                >
                  <div
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 10,
                      marginBottom: 12,
                    }}
                  >
                    <div
                      style={{
                        width: 34,
                        height: 34,
                        borderRadius: "50%",
                        background: "#F0F0F0",
                      }}
                    />
                    <div>
                      <div
                        style={{
                          width: 80,
                          height: 10,
                          borderRadius: 4,
                          background: "#F0F0F0",
                          marginBottom: 4,
                        }}
                      />
                      <div
                        style={{
                          width: 50,
                          height: 8,
                          borderRadius: 4,
                          background: "#F8F7F5",
                        }}
                      />
                    </div>
                  </div>
                  <div
                    style={{
                      width: "100%",
                      height: 10,
                      borderRadius: 4,
                      background: "#F0F0F0",
                      marginBottom: 6,
                    }}
                  />
                  <div
                    style={{
                      width: "85%",
                      height: 10,
                      borderRadius: 4,
                      background: "#F0F0F0",
                      marginBottom: 6,
                    }}
                  />
                  <div
                    style={{
                      width: "70%",
                      height: 10,
                      borderRadius: 4,
                      background: "#F8F7F5",
                    }}
                  />
                  <div
                    style={{
                      marginTop: 14,
                      height: 4,
                      borderRadius: 999,
                      background: "#F0F0F0",
                    }}
                  >
                    <div
                      style={{
                        width: "60%",
                        height: "100%",
                        borderRadius: 999,
                        background: "#D0D0D0",
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>

            {/* overlay */}
            <div
              style={{
                position: "absolute",
                inset: 0,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: 14,
                padding: "0 24px",
                textAlign: "center",
              }}
            >
              <div
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 14,
                  overflow: "hidden",
                  boxShadow: "0 4px 16px rgba(76,175,110,0.2)",
                }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/logo.png"
                  alt="Echoproof"
                  width={44}
                  height={44}
                  style={{ width: "100%", height: "100%", objectFit: "cover" }}
                />
              </div>
              <p
                style={{
                  fontSize: 15,
                  fontWeight: 700,
                  color: "#1A1A1A",
                  margin: 0,
                  letterSpacing: "-0.01em",
                }}
              >
                See {displayName.split(" ")[0]}&apos;s echoes in the app
              </p>
              <p
                style={{
                  fontSize: 12,
                  color: "#9A9A9A",
                  margin: 0,
                  lineHeight: 1.6,
                }}
              >
                Full profiles, confidence scores, and community signals are only
                visible in Echoproof.
              </p>
              <a
                href={`echoproof://user/${profile.username}`}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  height: 44,
                  padding: "0 22px",
                  borderRadius: 999,
                  background: "#1A1A1A",
                  color: "#fff",
                  fontSize: 13,
                  fontWeight: 600,
                  textDecoration: "none",
                  fontFamily: "'Josefin Sans', sans-serif",
                }}
              >
                Open in Echoproof
              </a>
            </div>
          </div>
        </div>
      </main>

      <Footer />
    </>
  );
}
