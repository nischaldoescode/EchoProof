// open graph page for echo links
// when someone shares an echo link, this page shows a preview in chat apps
// if the app is installed, it deep links directly into the app

import type { GetServerSideProps } from "next";
import Head from "next/head";
import { supabaseAdmin as supabase } from "@/lib/supabase";

interface Props {
  echo: {
    title: string;
    content: string;
    username: string;
    status: string;
  } | null;
  echoId: string;
}

export default function EchoPage({ echo, echoId }: Props) {
  return (
    <>
      <Head>
        <title>{echo?.title ?? "Echo on Echoproof"}</title>
        <meta name="description" content={echo?.content?.slice(0, 160)} />

        {/* open graph — shows in WhatsApp, Twitter, Telegram previews */}
        <meta
          property="og:title"
          content={echo?.title ?? "Echo on Echoproof"}
        />
        <meta
          property="og:description"
          content={echo?.content?.slice(0, 160)}
        />
        <meta
          property="og:image"
          content="https://echoproof.online/og-image.png"
        />
        <meta
          property="og:url"
          content={`https://echoproof.online/echo/${echoId}`}
        />
        <meta property="og:type" content="article" />

        {/* twitter card */}
        <meta name="twitter:card" content="summary_large_image" />
        <meta
          name="twitter:title"
          content={echo?.title ?? "Echo on Echoproof"}
        />
        <meta
          name="twitter:description"
          content={echo?.content?.slice(0, 160)}
        />

        {/* android app links — opens app if installed */}
        <meta name="al:android:url" content={`echoproof://echo/${echoId}`} />
        <meta name="al:android:app_name" content="Echoproof" />
        <meta name="al:android:package" content="com.echoproof.app" />

        {/* ios app links */}
        <meta name="al:ios:url" content={`echoproof://echo/${echoId}`} />
        <meta name="al:ios:app_name" content="Echoproof" />
        <meta name="al:ios:app_store_id" content="YOUR_APP_STORE_ID" />
      </Head>

      <div
        style={{
          fontFamily: "'Josefin Sans', sans-serif",
          minHeight: "100svh",
          background: "#F8F7F5",
          padding: "72px 20px",
        }}
      >
        <main style={{ maxWidth: 620, margin: "0 auto" }}>
          <div style={{ marginBottom: 20 }}>
            <img
              src="/logo.png"
              width={52}
              height={52}
              alt="Echoproof"
              style={{ borderRadius: 14 }}
            />
          </div>

          <section
            style={{
              background: "#fff",
              border: "1px solid #E6E6E6",
              borderRadius: 22,
              padding: "24px 22px",
              boxShadow: "0 12px 34px rgba(0,0,0,0.06)",
            }}
          >
            <p
              style={{
                margin: "0 0 10px",
                color: "#2D7A4A",
                fontSize: 12,
                fontWeight: 700,
                textTransform: "uppercase",
                letterSpacing: "0.12em",
              }}
            >
              Echo preview
            </p>

            <h1
              style={{
                fontSize: 26,
                lineHeight: 1.15,
                fontWeight: 800,
                color: "#1A1A1A",
                margin: "0 0 8px",
              }}
            >
              {echo?.title ?? "Echo not found"}
            </h1>

            {echo && (
              <>
                <p style={{ color: "#777", margin: "0 0 22px" }}>
                  Posted by @{echo.username || "echoproof"}
                </p>
                <p
                  style={{
                    lineHeight: 1.65,
                    margin: "0 0 28px",
                    color: "#3A3A3A",
                    fontSize: 15,
                  }}
                >
                  {echo.content}
                </p>
              </>
            )}

            {/* deep link button — keep intact for installed app handoff */}
            <a
              href={`echoproof://echo/${echoId}`}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background: "#1A1A1A",
                color: "white",
                height: 52,
                borderRadius: "14px",
                textDecoration: "none",
                fontWeight: 700,
              }}
            >
              Open in Echoproof
            </a>

            <div
              style={{
                marginTop: 14,
                height: 44,
                border: "1px solid #E6E6E6",
                borderRadius: 14,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#777",
                fontSize: 13,
                fontWeight: 600,
              }}
            >
              Android download coming soon
            </div>
          </section>
        </main>
      </div>
    </>
  );
}

export const getServerSideProps: GetServerSideProps = async ({ params }) => {
  const echoId = params?.id as string;

  try {
    const { data } = await supabase
      .from("echoes")
      .select("title, content, status, users_public(username)")
      .eq("id", echoId)
      .maybeSingle();

    const user = Array.isArray(data?.users_public)
      ? data?.users_public[0]
      : data?.users_public;
    const echo = data
      ? {
          title: data.title,
          content: data.content,
          status: data.status,
          username: user?.username ?? "echoproof",
        }
      : null;

    return {
      props: { echo: echo ?? null, echoId },
    };
  } catch {
    return { props: { echo: null, echoId } };
  }
};
