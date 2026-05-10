// 404 page — shown for any unmatched route
// consistent with the design system, links back to home and the android app

import Link from "next/link";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

export default function NotFound() {
  return (
    <>
      <Nav />
      <main
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          minHeight: "100svh",
          padding: "120px 24px 80px",
          background: "#fff",
          fontFamily: "'Josefin Sans', sans-serif",
          textAlign: "center",
        }}
      >
        {/* large faint 404 */}
        <p
          aria-hidden
          style={{
            fontSize: "clamp(80px, 20vw, 160px)",
            fontWeight: 700,
            color: "#F0F0F0",
            lineHeight: 1,
            letterSpacing: "-0.04em",
            margin: "0 0 -20px",
            userSelect: "none",
          }}
        >
          404
        </p>

        <div style={{ position: "relative", zIndex: 1 }}>
          <div
            style={{
              width: 8,
              height: 8,
              borderRadius: "50%",
              background: "#4CAF6E",
              margin: "0 auto 20px",
            }}
          />
          <h1
            style={{
              fontSize: "clamp(22px, 4vw, 32px)",
              fontWeight: 700,
              color: "#1A1A1A",
              letterSpacing: "-0.025em",
              marginBottom: 12,
            }}
          >
            This page doesn't exist.
          </h1>
          <p
            style={{
              fontSize: 14,
              color: "#5A5A5A",
              lineHeight: 1.75,
              maxWidth: 360,
              margin: "0 auto 36px",
            }}
          >
            If you were looking for a specific echo or profile, it may have been
            removed or the link may be wrong.
          </p>

          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              gap: 12,
              justifyContent: "center",
            }}
          >
            <Link
              href="/"
              style={{
                display: "inline-flex",
                alignItems: "center",
                height: 44,
                padding: "0 24px",
                borderRadius: 999,
                background: "#1A1A1A",
                color: "#fff",
                fontSize: 13,
                fontWeight: 600,
                textDecoration: "none",
                fontFamily: "'Josefin Sans', sans-serif",
              }}
            >
              Back to home
            </Link>
            <a
              href="https://play.google.com/store/apps/details?id=com.echoproof.app"
              target="_blank"
              rel="noopener noreferrer"
              style={{
                display: "inline-flex",
                alignItems: "center",
                height: 44,
                padding: "0 24px",
                borderRadius: 999,
                border: "1px solid #E6E6E6",
                color: "#1A1A1A",
                fontSize: 13,
                fontWeight: 500,
                textDecoration: "none",
                fontFamily: "'Josefin Sans', sans-serif",
              }}
            >
              Open the app
            </a>
          </div>
        </div>
      </main>
      <Footer />
    </>
  );
}
