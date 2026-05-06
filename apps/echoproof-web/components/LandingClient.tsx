"use client";

// landing page client component
// handles all scroll reveals, parallax, ticker, and interactive sections
// split from page.tsx so the server component can export metadata cleanly

import { useEffect, useRef, useState } from "react";

// real echo card data — representative of what lives in the app
const tickerEchoes = [
  {
    id: 1,
    username: "@meera_k",
    tier: "High",
    tierWeight: "4×",
    timeAgo: "2h ago",
    content:
      "The Reserve Bank's rate hold was fully priced in two weeks before the announcement. Markets knew. Media acted surprised.",
    status: "verified",
    statusLabel: "Verified by community",
    confidence: 84,
    supports: 312,
    challenges: 41,
    category: "Finance",
  },
  {
    id: 2,
    username: "@prakash_v",
    tier: "Elite",
    tierWeight: "5×",
    timeAgo: "5h ago",
    content:
      "Peer-reviewed studies on ultraprocessed food and ADHD in adolescents are being systematically underfunded by the same institutions that review them.",
    status: "controversial",
    statusLabel: "Controversial",
    confidence: 51,
    supports: 198,
    challenges: 187,
    category: "Health",
  },
  {
    id: 3,
    username: "@devika_r",
    tier: "Medium",
    tierWeight: "3×",
    timeAgo: "1d ago",
    content:
      "Open-source models have surpassed GPT-4 on every public benchmark that matters. The narrative that closed labs are still ahead is three months stale.",
    status: "disputed",
    statusLabel: "Disputed",
    confidence: 34,
    supports: 89,
    challenges: 201,
    category: "Technology",
  },
  {
    id: 4,
    username: "@arjun_ms",
    tier: "High",
    tierWeight: "4×",
    timeAgo: "3h ago",
    content:
      "Bengaluru's groundwater depletion rate accelerated 40% between 2019 and 2024. The official numbers published by BWSSB undercount this by a significant margin.",
    status: "verified",
    statusLabel: "Verified by community",
    confidence: 91,
    supports: 543,
    challenges: 22,
    category: "Environment",
  },
  {
    id: 5,
    username: "@nandini_t",
    tier: "Low",
    tierWeight: "2×",
    timeAgo: "7h ago",
    content:
      "Most productivity influencers are selling the anxiety they claim to cure. The market for attention management tools grows fastest in populations that are most distracted.",
    status: "active",
    statusLabel: "Active",
    confidence: 68,
    supports: 156,
    challenges: 43,
    category: "Culture",
  },
  {
    id: 6,
    username: "@rohit_sg",
    tier: "Elite",
    tierWeight: "5×",
    timeAgo: "12h ago",
    content:
      "EV battery degradation in Indian climates is being underreported. The thermal cycles here are substantially more aggressive than European testing conditions assume.",
    status: "verified",
    statusLabel: "Verified by community",
    confidence: 77,
    supports: 289,
    challenges: 67,
    category: "Technology",
  },
];

// status config
const statusConfig: Record<string, { color: string; bg: string; dot: string }> =
  {
    verified: { color: "#2D7A4A", bg: "#E8F5EE", dot: "#4CAF6E" },
    controversial: { color: "#7A5200", bg: "#FFF3E0", dot: "#E8A000" },
    disputed: { color: "#B03E28", bg: "#FFF0ED", dot: "#FF7759" },
    active: { color: "#1A6DB5", bg: "#E8F4FD", dot: "#3498DB" },
  };

// tier colors
const tierColor: Record<string, string> = {
  Unverified: "#9A9A9A",
  Low: "#5A5A5A",
  Medium: "#1A1A1A",
  High: "#4CAF6E",
  Elite: "#2D7A4A",
};

// trust tier rows for the trust engine section
const tiers = [
  {
    label: "Unverified",
    weight: "1×",
    description: "Default new account — still has a voice.",
  },
  {
    label: "Low",
    weight: "2×",
    description: "Active participation and consistent posting.",
  },
  {
    label: "Medium",
    weight: "3×",
    description: "Established contributor with track record.",
  },
  {
    label: "High",
    weight: "4×",
    description: "Identity verified — government ID + liveness check.",
  },
  {
    label: "Elite",
    weight: "5×",
    description: "Highest tier — sustained top contributor across months.",
  },
];

// on-chain features
const chainFeatures = [
  {
    title: "Proof staking",
    body: "When you attach evidence to an echo, you can stake a small amount to signal confidence. If the community verifies your proof, you earn it back with a reward. If rejected, it is forfeited. False evidence becomes economically costly.",
  },
  {
    title: "Portable reputation",
    body: "When you reach High or Elite trust tier, your reputation score is written to the Solana blockchain via a memo transaction. A timestamped, immutable record of your credibility — independent of Echoproof itself.",
  },
  {
    title: "Truth bonds",
    body: "On any verified echo, you can mint a compressed NFT that publicly ties your reputation to that claim's truth. Bonds settle after 30 days. If an admin downgrades the echo on new evidence, your bond is marked Contested — forever.",
  },
];

// hook: detect when element enters viewport
function useScrollReveal(threshold = 0.15) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          obs.disconnect();
        }
      },
      { threshold },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [threshold]);

  return { ref, visible };
}

// single echo card used in the ticker
function TickerCard({ echo }: { echo: (typeof tickerEchoes)[0] }) {
  const cfg = statusConfig[echo.status] ?? statusConfig.active;
  const pct = echo.confidence;

  return (
    <div
      style={{
        width: 320,
        flexShrink: 0,
        background: "#fff",
        borderRadius: 20,
        border: `1.2px solid ${cfg.dot}40`,
        padding: "20px 20px 16px",
        boxShadow: "0 2px 16px rgba(0,0,0,0.05)",
        display: "flex",
        flexDirection: "column",
        gap: 12,
        fontFamily: "'Josefin Sans', sans-serif",
      }}
    >
      {/* header */}
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: "50%",
            background: "#E8F5EE",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            border:
              echo.tier === "High" || echo.tier === "Elite"
                ? "1.5px solid #4CAF6E"
                : "1px solid #E6E6E6",
            flexShrink: 0,
          }}
        >
          <span style={{ fontSize: 12, fontWeight: 700, color: "#2D7A4A" }}>
            {echo.username[1].toUpperCase()}
          </span>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p
            style={{
              fontSize: 12,
              fontWeight: 600,
              color: "#1A1A1A",
              margin: 0,
            }}
          >
            {echo.username}
          </p>
          <p style={{ fontSize: 10, color: "#9A9A9A", margin: 0 }}>
            {echo.tier} · {echo.tierWeight} weight · {echo.category}
          </p>
        </div>
        <span style={{ fontSize: 10, color: "#9A9A9A" }}>{echo.timeAgo}</span>
      </div>

      {/* content */}
      <p
        style={{
          fontSize: 13,
          color: "#1A1A1A",
          lineHeight: 1.6,
          margin: 0,
          display: "-webkit-box",
          WebkitLineClamp: 4,
          WebkitBoxOrient: "vertical",
          overflow: "hidden",
        }}
      >
        {echo.content}
      </p>

      {/* status label */}
      <div
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 5,
          background: cfg.bg,
          borderRadius: 6,
          padding: "3px 8px",
          alignSelf: "flex-start",
        }}
      >
        <span
          style={{
            width: 5,
            height: 5,
            borderRadius: "50%",
            background: cfg.dot,
            flexShrink: 0,
          }}
        />
        <span style={{ fontSize: 10, fontWeight: 600, color: cfg.color }}>
          {echo.statusLabel}
        </span>
      </div>

      {/* confidence bar */}
      <div>
        <div
          style={{
            height: 5,
            background: "#F8F7F5",
            borderRadius: 999,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              height: "100%",
              width: `${pct}%`,
              background: cfg.dot,
              borderRadius: 999,
              transition: "width 1s ease",
            }}
          />
        </div>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            marginTop: 4,
          }}
        >
          <span style={{ fontSize: 9, color: "#9A9A9A" }}>
            Community confidence
          </span>
          <span style={{ fontSize: 9, fontWeight: 700, color: cfg.dot }}>
            {pct}%
          </span>
        </div>
      </div>

      {/* actions */}
      <div
        style={{
          display: "flex",
          gap: 8,
          paddingTop: 10,
          borderTop: "1px solid #F8F7F5",
        }}
      >
        <span
          style={{
            fontSize: 11,
            fontWeight: 600,
            color: "#4CAF6E",
            background: "#E8F5EE",
            borderRadius: 999,
            padding: "4px 10px",
          }}
        >
          Support · {echo.supports}
        </span>
        <span
          style={{
            fontSize: 11,
            fontWeight: 500,
            color: "#9A9A9A",
            background: "#F8F7F5",
            borderRadius: 999,
            padding: "4px 10px",
          }}
        >
          Challenge · {echo.challenges}
        </span>
      </div>
    </div>
  );
}

// reveal wrapper
function Reveal({
  children,
  delay = 0,
  direction = "up",
}: {
  children: React.ReactNode;
  delay?: number;
  direction?: "up" | "left" | "right" | "none";
}) {
  const { ref, visible } = useScrollReveal();

  const transforms: Record<string, string> = {
    up: "translateY(40px)",
    left: "translateX(-40px)",
    right: "translateX(40px)",
    none: "none",
  };

  return (
    <div
      ref={ref}
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? "none" : transforms[direction],
        transition: `opacity 0.8s ease ${delay}ms, transform 0.8s cubic-bezier(0.22,1,0.36,1) ${delay}ms`,
        willChange: "opacity, transform",
      }}
    >
      {children}
    </div>
  );
}

// parallax hook — works on both desktop and mobile (scroll-based, not mouse-based)
function useParallax(speed = 0.3) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let ticking = false;

    const onScroll = () => {
      if (!ref.current || ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        if (!ref.current) return;
        const rect = ref.current.parentElement?.getBoundingClientRect();
        if (!rect) return;
        const offset = -rect.top * speed;
        ref.current.style.transform = `translateY(${offset}px)`;
        ticking = false;
      });
    };

    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, [speed]);

  return ref;
}

// horizontal ticker with pause on hover and auto-scroll with IntersectionObserver trigger
function EchoTicker() {
  const trackRef = useRef<HTMLDivElement>(null);
  const [paused, setPaused] = useState(false);
  const { ref: wrapperRef, visible } = useScrollReveal(0.1);

  // doubled for seamless loop
  const doubled = [...tickerEchoes, ...tickerEchoes];

  return (
    <div ref={wrapperRef} style={{ overflow: "hidden" }}>
      <style>{`
        @keyframes ticker-scroll {
          0%   { transform: translateX(0); }
          100% { transform: translateX(-50%); }
        }
        .ticker-track {
          display: flex;
          gap: 16px;
          width: max-content;
          animation: ticker-scroll 40s linear infinite;
        }
        .ticker-track.paused {
          animation-play-state: paused;
        }
        .ticker-track:not(.playing) {
          animation-play-state: paused;
        }
      `}</style>
      <div
        className={`ticker-track ${paused ? "paused" : ""} ${visible ? "playing" : ""}`}
        ref={trackRef}
        onMouseEnter={() => setPaused(true)}
        onMouseLeave={() => setPaused(false)}
        onTouchStart={() => setPaused(true)}
        onTouchEnd={() => setPaused(false)}
      >
        {doubled.map((echo, i) => (
          <TickerCard key={`${echo.id}-${i}`} echo={echo} />
        ))}
      </div>
    </div>
  );
}

export default function LandingClient() {
  const parallaxBgRef = useParallax(0.25);
  const parallaxTextRef = useParallax(0.12);
  const parallaxOrbRef = useParallax(0.4);

  return (
    <main
      style={{
        flex: 1,
        background: "#fff",
        overflowX: "hidden",
        fontFamily: "'Josefin Sans', sans-serif",
      }}
    >
      <style>{`
        @keyframes float-orb {
          0%, 100% { transform: translateY(0px) scale(1); }
          50%       { transform: translateY(-20px) scale(1.04); }
        }
        @keyframes hero-line-in {
          0%   { opacity: 0; transform: translateY(32px); }
          100% { opacity: 1; transform: translateY(0); }
        }
        @keyframes fade-up-slow {
          0%   { opacity: 0; transform: translateY(20px); }
          100% { opacity: 1; transform: translateY(0); }
        }
        @keyframes line-grow {
          0%   { width: 0; }
          100% { width: 48px; }
        }
        .hero-line-1 { animation: hero-line-in 1s cubic-bezier(0.22,1,0.36,1) 200ms both; }
        .hero-line-2 { animation: hero-line-in 1s cubic-bezier(0.22,1,0.36,1) 400ms both; }
        .hero-sub    { animation: fade-up-slow 1s ease 700ms both; }
        .hero-cta    { animation: fade-up-slow 1s ease 950ms both; }
        .hero-scroll-hint { animation: fade-up-slow 1s ease 1300ms both; }

        @media (max-width: 640px) {
          .hero-display { font-size: clamp(38px, 11vw, 64px) !important; }
        }
      `}</style>

      {/* hero — full viewport with parallax layers */}
      <section
        style={{
          position: "relative",
          minHeight: "100svh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          overflow: "hidden",
          padding: "120px 24px 80px",
        }}
      >
        {/* parallax background mesh */}
        <div
          ref={parallaxBgRef}
          aria-hidden
          style={{
            position: "absolute",
            inset: "-20%",
            zIndex: 0,
            background:
              "radial-gradient(ellipse 70% 55% at 50% 30%, rgba(76,175,110,0.10) 0%, transparent 65%), radial-gradient(ellipse 40% 40% at 80% 70%, rgba(232,160,0,0.05) 0%, transparent 60%)",
          }}
        />

        {/* floating orb — parallax */}
        <div
          ref={parallaxOrbRef}
          aria-hidden
          style={{
            position: "absolute",
            top: "15%",
            right: "8%",
            width: 320,
            height: 320,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(76,175,110,0.12) 0%, transparent 70%)",
            animation: "float-orb 8s ease-in-out infinite",
            zIndex: 0,
            filter: "blur(2px)",
          }}
        />

        <div
          ref={parallaxTextRef}
          style={{
            position: "relative",
            zIndex: 1,
            maxWidth: 720,
            width: "100%",
            textAlign: "center",
          }}
        >
          <p
            className="hero-scroll-hint"
            style={{
              fontSize: 11,
              letterSpacing: "0.18em",
              textTransform: "uppercase",
              color: "#9A9A9A",
              marginBottom: 32,
            }}
          >
            A new kind of social network
          </p>

          <h1
            className="hero-display"
            style={{
              fontSize: "clamp(44px, 8vw, 80px)",
              fontWeight: 700,
              letterSpacing: "-0.03em",
              lineHeight: 1.06,
              color: "#1A1A1A",
              margin: "0 0 28px",
            }}
          >
            <span className="hero-line-1" style={{ display: "block" }}>
              The crowd decides
            </span>
            <span
              className="hero-line-2"
              style={{ display: "block", color: "#4CAF6E" }}
            >
              what is true.
            </span>
          </h1>

          <p
            className="hero-sub"
            style={{
              fontSize: 16,
              color: "#5A5A5A",
              lineHeight: 1.75,
              maxWidth: 480,
              margin: "0 auto 40px",
            }}
          >
            Echoproof is where claims meet scrutiny. Every post is weighed by
            the community — and the ones that survive become permanent record.
          </p>

          <div
            className="hero-cta"
            style={{
              display: "flex",
              flexWrap: "wrap",
              gap: 12,
              justifyContent: "center",
            }}
          >
            <a
              href="https://play.google.com/store/apps/details?id=com.echoproof.app"
              target="_blank"
              rel="noopener noreferrer"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                height: 48,
                padding: "0 28px",
                borderRadius: 999,
                background: "#1A1A1A",
                color: "#fff",
                fontSize: 13,
                fontWeight: 600,
                textDecoration: "none",
                letterSpacing: "0.01em",
                transition: "background 0.2s, box-shadow 0.2s",
                fontFamily: "'Josefin Sans', sans-serif",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLElement).style.background = "#2d2d2d";
                (e.currentTarget as HTMLElement).style.boxShadow =
                  "0 8px 24px rgba(0,0,0,0.18)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLElement).style.background = "#1A1A1A";
                (e.currentTarget as HTMLElement).style.boxShadow = "none";
              }}
            >
              Download for Android
            </a>
            <a
              href="#how-it-works"
              style={{
                display: "inline-flex",
                alignItems: "center",
                height: 48,
                padding: "0 28px",
                borderRadius: 999,
                border: "1px solid #E6E6E6",
                color: "#1A1A1A",
                fontSize: 13,
                fontWeight: 500,
                textDecoration: "none",
                transition: "border-color 0.2s, background 0.2s",
                fontFamily: "'Josefin Sans', sans-serif",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLElement).style.borderColor = "#1A1A1A";
                (e.currentTarget as HTMLElement).style.background = "#F8F7F5";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLElement).style.borderColor = "#E6E6E6";
                (e.currentTarget as HTMLElement).style.background =
                  "transparent";
              }}
            >
              How it works
            </a>
          </div>
        </div>

        {/* scroll nudge line */}
        <div
          className="hero-scroll-hint"
          aria-hidden
          style={{
            position: "absolute",
            bottom: 36,
            left: "50%",
            transform: "translateX(-50%)",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 6,
          }}
        >
          <div
            style={{
              width: 1,
              height: 48,
              background: "linear-gradient(to bottom, transparent, #9A9A9A60)",
              borderRadius: 999,
            }}
          />
        </div>
      </section>

      {/* live echoes ticker — real content scrolling automatically */}
      <section
        style={{
          padding: "72px 0",
          background: "#F8F7F5",
          overflow: "hidden",
        }}
      >
        <div
          style={{ maxWidth: 960, margin: "0 auto", padding: "0 24px 32px" }}
        >
          <Reveal>
            <p
              style={{
                fontSize: 11,
                letterSpacing: "0.18em",
                textTransform: "uppercase",
                color: "#9A9A9A",
                marginBottom: 10,
              }}
            >
              Live from the platform
            </p>
            <h2
              style={{
                fontSize: "clamp(26px, 5vw, 40px)",
                fontWeight: 700,
                letterSpacing: "-0.025em",
                color: "#1A1A1A",
                lineHeight: 1.15,
              }}
            >
              Real echoes. Real scrutiny.
            </h2>
          </Reveal>
        </div>
        <EchoTicker />
        <div
          style={{ maxWidth: 960, margin: "24px auto 0", padding: "0 24px" }}
        >
          <Reveal delay={100}>
            <p style={{ fontSize: 12, color: "#9A9A9A", lineHeight: 1.6 }}>
              Every card above is a real format — what you see in the app.
              Status, confidence, and support counts evolve as the community
              weighs in.
            </p>
          </Reveal>
        </div>
      </section>

      {/* how it works — editorial chapter layout */}
      <section
        id="how-it-works"
        style={{
          padding: "96px 24px",
          maxWidth: 960,
          margin: "0 auto",
        }}
      >
        <Reveal>
          <p
            style={{
              fontSize: 11,
              letterSpacing: "0.18em",
              textTransform: "uppercase",
              color: "#9A9A9A",
              marginBottom: 10,
            }}
          >
            How it works
          </p>
          <h2
            style={{
              fontSize: "clamp(26px, 5vw, 42px)",
              fontWeight: 700,
              letterSpacing: "-0.025em",
              color: "#1A1A1A",
              lineHeight: 1.15,
              marginBottom: 16,
            }}
          >
            From claim to consensus
          </h2>
          <p
            style={{
              fontSize: 15,
              color: "#5A5A5A",
              lineHeight: 1.75,
              maxWidth: 520,
              marginBottom: 64,
            }}
          >
            Most platforms amplify what is popular. Echoproof surfaces what
            holds up under scrutiny. The process is transparent, weighted, and
            permanent.
          </p>
        </Reveal>

        {/* chapter steps — alternating layout */}
        {[
          {
            number: "01",
            title: "You post an echo.",
            body: "Any claim, opinion, or observation — backed by evidence or standing on its own. Your trust tier determines how much weight your supporting interactions carry, but anyone can post. The floor for participation is zero.",
            aside:
              "Every echo starts neutral. No algorithm pre-sorts it. The community encounters it fresh.",
          },
          {
            number: "02",
            title: "The community weighs in.",
            body: "Other users can support or challenge your echo. A support from an Elite-tier identity-verified user carries five times the weight of a brand-new account. This is not about volume — it is about signal quality.",
            aside:
              "Weighted consensus means a thousand anonymous accounts cannot drown out a hundred verified experts.",
          },
          {
            number: "03",
            title: "Scores evolve in real time.",
            body: "The trust engine continuously recalculates four scores: trust, confidence, controversy, and report intensity. An echo that starts disputed can become verified as higher-tier users engage. Nothing is frozen.",
            aside:
              "Confidence above 70% with trust score above 50 triggers the verification threshold.",
          },
          {
            number: "04",
            title: "Truth is anchored on-chain.",
            body: "When an echo crosses the verification threshold, a SHA-256 hash of its content along with its confidence score and timestamp is written to Solana. The record is permanent. Not even Echoproof can alter it.",
            aside:
              "Anyone with a Solana explorer can independently verify the record exists and matches the echo.",
          },
        ].map((step, i) => (
          <Reveal
            key={step.number}
            delay={i * 80}
            direction={i % 2 === 0 ? "left" : "right"}
          >
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr",
                gap: 24,
                marginBottom: 56,
                paddingBottom: 56,
                borderBottom: "1px solid #F0F0F0",
              }}
            >
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "auto 1fr",
                  gap: "0 32px",
                  alignItems: "start",
                }}
              >
                {/* step number */}
                <span
                  style={{
                    fontSize: 11,
                    fontWeight: 700,
                    color: "#4CAF6E",
                    letterSpacing: "0.12em",
                    paddingTop: 4,
                    minWidth: 28,
                  }}
                >
                  {step.number}
                </span>
                <div>
                  <h3
                    style={{
                      fontSize: "clamp(18px, 3vw, 24px)",
                      fontWeight: 700,
                      color: "#1A1A1A",
                      letterSpacing: "-0.02em",
                      marginBottom: 12,
                      lineHeight: 1.25,
                    }}
                  >
                    {step.title}
                  </h3>
                  <p
                    style={{
                      fontSize: 14,
                      color: "#5A5A5A",
                      lineHeight: 1.8,
                      marginBottom: 16,
                      maxWidth: 560,
                    }}
                  >
                    {step.body}
                  </p>
                  <p
                    style={{
                      fontSize: 12,
                      color: "#9A9A9A",
                      lineHeight: 1.7,
                      borderLeft: "2px solid #E8F5EE",
                      paddingLeft: 12,
                      maxWidth: 480,
                      fontStyle: "italic",
                    }}
                  >
                    {step.aside}
                  </p>
                </div>
              </div>
            </div>
          </Reveal>
        ))}
      </section>

      {/* trust engine — dark section with parallax */}
      <section
        id="trust"
        style={{
          position: "relative",
          overflow: "hidden",
          background: "#1A1A1A",
          padding: "96px 24px",
        }}
      >
        {/* parallax accent orb */}
        <div
          aria-hidden
          style={{
            position: "absolute",
            top: "-10%",
            right: "-5%",
            width: 400,
            height: 400,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(76,175,110,0.12) 0%, transparent 65%)",
            pointerEvents: "none",
          }}
        />

        <div style={{ maxWidth: 960, margin: "0 auto" }}>
          <Reveal>
            <p
              style={{
                fontSize: 11,
                letterSpacing: "0.18em",
                textTransform: "uppercase",
                color: "#4CAF6E",
                marginBottom: 10,
              }}
            >
              Trust engine
            </p>
            <h2
              style={{
                fontSize: "clamp(26px, 5vw, 42px)",
                fontWeight: 700,
                letterSpacing: "-0.025em",
                color: "#fff",
                lineHeight: 1.15,
                marginBottom: 16,
              }}
            >
              Not all voices carry the same weight.
            </h2>
            <p
              style={{
                fontSize: 15,
                color: "#9A9A9A",
                lineHeight: 1.75,
                maxWidth: 520,
                marginBottom: 56,
              }}
            >
              On every other platform, a thousand new accounts can out-shout a
              hundred experts. On Echoproof, a verified contributor's single
              vote can outweigh a wave of anonymous noise. The engine calculates
              this automatically — no moderation team required.
            </p>
          </Reveal>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 12,
            }}
          >
            {tiers.map((tier, i) => (
              <Reveal key={tier.label} delay={i * 70} direction="left">
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "120px 1fr auto",
                    alignItems: "center",
                    gap: 20,
                    padding: "16px 20px",
                    borderRadius: 14,
                    background: "rgba(255,255,255,0.04)",
                    border: "1px solid rgba(255,255,255,0.07)",
                  }}
                >
                  <div
                    style={{ display: "flex", alignItems: "center", gap: 10 }}
                  >
                    <div
                      style={{
                        width: 8,
                        height: 8,
                        borderRadius: "50%",
                        background: tierColor[tier.label],
                        flexShrink: 0,
                      }}
                    />
                    <span
                      style={{
                        fontSize: 13,
                        fontWeight: 600,
                        color: "#fff",
                      }}
                    >
                      {tier.label}
                    </span>
                  </div>
                  <p
                    style={{
                      fontSize: 12,
                      color: "#9A9A9A",
                      lineHeight: 1.5,
                      margin: 0,
                    }}
                  >
                    {tier.description}
                  </p>
                  <span
                    style={{
                      fontSize: 13,
                      fontWeight: 700,
                      color: tierColor[tier.label],
                      minWidth: 28,
                      textAlign: "right",
                      flexShrink: 0,
                    }}
                  >
                    {tier.weight}
                  </span>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* on-chain section — what permanent means */}
      <section
        style={{
          padding: "96px 24px",
          maxWidth: 960,
          margin: "0 auto",
        }}
      >
        <Reveal>
          <p
            style={{
              fontSize: 11,
              letterSpacing: "0.18em",
              textTransform: "uppercase",
              color: "#9A9A9A",
              marginBottom: 10,
            }}
          >
            On-chain permanence
          </p>
          <h2
            style={{
              fontSize: "clamp(26px, 5vw, 42px)",
              fontWeight: 700,
              letterSpacing: "-0.025em",
              color: "#1A1A1A",
              lineHeight: 1.15,
              marginBottom: 16,
            }}
          >
            Once verified, no one can undo it.
          </h2>
          <p
            style={{
              fontSize: 15,
              color: "#5A5A5A",
              lineHeight: 1.75,
              maxWidth: 560,
              marginBottom: 64,
            }}
          >
            Platforms delete posts. Institutions revise records. Echoproof
            writes verified echoes to the Solana blockchain — where no single
            entity, including us, can alter or remove what the community has
            confirmed.
          </p>
        </Reveal>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
            gap: 20,
          }}
        >
          {chainFeatures.map((feature, i) => (
            <Reveal key={feature.title} delay={i * 100}>
              <div
                style={{
                  padding: 24,
                  borderRadius: 18,
                  border: "1px solid #E6E6E6",
                  background: "#F8F7F5",
                  height: "100%",
                  boxSizing: "border-box",
                }}
              >
                <div
                  style={{
                    width: 6,
                    height: 6,
                    borderRadius: "50%",
                    background: "#4CAF6E",
                    marginBottom: 16,
                  }}
                />
                <h3
                  style={{
                    fontSize: 15,
                    fontWeight: 700,
                    color: "#1A1A1A",
                    marginBottom: 10,
                    letterSpacing: "-0.01em",
                  }}
                >
                  {feature.title}
                </h3>
                <p
                  style={{
                    fontSize: 13,
                    color: "#5A5A5A",
                    lineHeight: 1.75,
                    margin: 0,
                  }}
                >
                  {feature.body}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      {/* reputation portability — standalone statement section */}
      <section
        style={{
          background: "#EAE7DF",
          padding: "80px 24px",
        }}
      >
        <div style={{ maxWidth: 720, margin: "0 auto", textAlign: "center" }}>
          <Reveal>
            <h2
              style={{
                fontSize: "clamp(22px, 4.5vw, 38px)",
                fontWeight: 700,
                letterSpacing: "-0.025em",
                color: "#1A1A1A",
                lineHeight: 1.2,
                marginBottom: 20,
              }}
            >
              Your reputation belongs to you — not the platform.
            </h2>
            <p
              style={{
                fontSize: 15,
                color: "#5A5A5A",
                lineHeight: 1.8,
                maxWidth: 520,
                margin: "0 auto 40px",
              }}
            >
              When you reach High or Elite trust tier, your reputation is
              anchored to the Solana blockchain. That record is yours. It cannot
              be deleted when you leave. It cannot be altered if we shut down.
              It lives independently, and it travels with you to any platform
              that reads the ledger.
            </p>
            <a
              href="https://play.google.com/store/apps/details?id=com.echoproof.app"
              target="_blank"
              rel="noopener noreferrer"
              style={{
                display: "inline-flex",
                alignItems: "center",
                height: 48,
                padding: "0 28px",
                borderRadius: 999,
                background: "#1A1A1A",
                color: "#fff",
                fontSize: 13,
                fontWeight: 600,
                textDecoration: "none",
                transition: "background 0.2s",
                fontFamily: "'Josefin Sans', sans-serif",
              }}
            >
              Build your reputation
            </a>
          </Reveal>
        </div>
      </section>

      {/* final cta */}
      <section
        style={{
          padding: "96px 24px",
          background: "#fff",
        }}
      >
        <div style={{ maxWidth: 600, margin: "0 auto", textAlign: "center" }}>
          <Reveal>
            <div
              style={{
                width: 64,
                height: 64,
                borderRadius: 18,
                overflow: "hidden",
                margin: "0 auto 28px",
                boxShadow: "0 4px 20px rgba(76,175,110,0.2)",
              }}
            >
              <img
                src="/logo.png"
                alt="Echoproof"
                width={64}
                height={64}
                style={{ width: "100%", height: "100%", objectFit: "cover" }}
              />
            </div>
            <h2
              style={{
                fontSize: "clamp(24px, 5vw, 38px)",
                fontWeight: 700,
                letterSpacing: "-0.025em",
                color: "#1A1A1A",
                lineHeight: 1.2,
                marginBottom: 16,
              }}
            >
              Join the conversation.
              <br />
              <span style={{ color: "#4CAF6E" }}>Make it count.</span>
            </h2>
            <p
              style={{
                fontSize: 14,
                color: "#5A5A5A",
                lineHeight: 1.75,
                marginBottom: 36,
              }}
            >
              Available now on Android. Post echoes, earn trust, stake claims,
              and help the community establish what is actually true.
            </p>
            <a
              href="https://play.google.com/store/apps/details?id=com.echoproof.app"
              target="_blank"
              rel="noopener noreferrer"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                height: 52,
                padding: "0 32px",
                borderRadius: 999,
                background: "#1A1A1A",
                color: "#fff",
                fontSize: 14,
                fontWeight: 600,
                textDecoration: "none",
                transition: "background 0.2s, box-shadow 0.2s",
                fontFamily: "'Josefin Sans', sans-serif",
              }}
            >
              Download for Android
            </a>
          </Reveal>
        </div>
      </section>
    </main>
  );
}
