// open graph page for echo links
// when someone shares an echo link, this page shows a preview in chat apps
// if the app is installed, it deep links directly into the app

import type { GetServerSideProps } from "next";
import Head from "next/head";

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
          maxWidth: 600,
          margin: "80px auto",
          padding: "0 24px",
        }}
      >
        <div style={{ marginBottom: 24 }}>
          <img src="/logo.png" width={48} height={48} alt="Echoproof" />
        </div>

        <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>
          {echo?.title ?? "Echo not found"}
        </h1>

        {echo && (
          <>
            <p style={{ color: "#666", marginBottom: 24 }}>
              Posted by @{echo.username}
            </p>
            <p style={{ lineHeight: 1.6, marginBottom: 32 }}>{echo.content}</p>
          </>
        )}

        {/* deep link button — opens app or redirects to store */}
        <a
          href={`echoproof://echo/${echoId}`}
          style={{
            display: "inline-block",
            background: "#1A1A1A",
            color: "white",
            padding: "14px 28px",
            borderRadius: "12px",
            textDecoration: "none",
            fontWeight: 600,
          }}
        >
          Open in Echoproof
        </a>

        <p style={{ marginTop: 16, fontSize: 12, color: "#999" }}>
          Don't have the app?{" "}
          <a href="https://play.google.com/store/apps/details?id=com.echoproof.app">
            Download for Android
          </a>
        </p>
      </div>
    </>
  );
}

export const getServerSideProps: GetServerSideProps = async ({ params }) => {
  const echoId = params?.id as string;

  try {
    // fetch echo from supabase for OG tags
    const res = await fetch(
      `${process.env.SUPABASE_URL}/rest/v1/echoes?id=eq.${echoId}&select=title,content,status,user_id`,
      {
        headers: {
          apikey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
          Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY!}`,
        },
      },
    );

    const data = await res.json();
    const echo = data[0] ?? null;

    return {
      props: { echo: echo ?? null, echoId },
    };
  } catch {
    return { props: { echo: null, echoId } };
  }
};
