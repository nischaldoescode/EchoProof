"use client";

// landing page — full parallax storytelling layout
// page loader lives here — purely client-side, no ssr complications
// smooth scroll, scroll reveal, parallax, horizontal ticker

import { useEffect, useRef, useState } from "react";

// ─── LOADER ──────────────────────────────────────────────────────────────────

function PageLoader() {
  // three states: "in" (fading in), "hold" (fully visible), "out" (fading out), "gone"
  const [phase, setPhase] = useState<"in" | "hold" | "out" | "gone">("gone");

  useEffect(() => {
    const already = sessionStorage.getItem("echoproof_loader_shown");
    if (already) return; // skip on refresh

    sessionStorage.setItem("echoproof_loader_shown", "1");

    // start fade-in on the next tick to avoid a sync state update in effect
    const startTimer = setTimeout(() => setPhase("in"), 0);

    // fully visible after fade-in completes (600ms)
    const holdTimer = setTimeout(() => setPhase("hold"), 600);
    // start fade-out at 2.8s
    const outTimer = setTimeout(() => setPhase("out"), 2800);
    // remove from dom at 3.4s
    const goneTimer = setTimeout(() => setPhase("gone"), 3400);

    return () => {
      clearTimeout(holdTimer);
      clearTimeout(outTimer);
      clearTimeout(goneTimer);
      clearTimeout(startTimer);
    };
  }, []);

  if (phase === "gone") return null;

  const opacity = phase === "in" ? 1 : phase === "hold" ? 1 : 0;
  const pointerEvents = phase === "out" ? "none" : "all";

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 9999,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "#E8F5EE",
        opacity,
        // fade-in is fast, fade-out is slower and smooth
        transition:
          phase === "in"
            ? "opacity 600ms ease-out"
            : "opacity 600ms ease-in-out",
        pointerEvents: pointerEvents as "none" | "all",
      }}
    >
      <style>{`
        @keyframes ldr-ring {
          0%   { transform: scale(0.55); opacity: 0.4; }
          100% { transform: scale(1.4);  opacity: 0; }
        }
        @keyframes ldr-logo {
          0%   { opacity: 0; transform: scale(0.80); }
          100% { opacity: 1; transform: scale(1); }
        }
        @keyframes ldr-glow {
          0%,100% { box-shadow: 0 0 0px 0px rgba(76,175,110,0); }
          50%      { box-shadow: 0 0 36px 10px rgba(76,175,110,0.22); }
        }
        @keyframes ldr-word {
          0%   { opacity: 0; transform: translateY(10px); }
          100% { opacity: 1; transform: translateY(0); }
        }
        .ldr-ring {
          position: absolute;
          width: 160px; height: 160px;
          border-radius: 50%;
          border: 1.5px solid #4CAF6E;
          animation: ldr-ring 1.2s ease-out forwards;
        }
        .ldr-r1 { animation-delay: 0.05s; }
        .ldr-r2 { animation-delay: 0.22s; }
        .ldr-r3 { animation-delay: 0.40s; }
        .ldr-logo {
          animation: ldr-logo 700ms cubic-bezier(0.34,1.56,0.64,1) 80ms both,
                     ldr-glow 900ms ease-in-out 800ms both;
        }
        .ldr-name { animation: ldr-word 600ms ease-out 500ms both; }
        .ldr-tag  { animation: ldr-word 600ms ease-out 660ms both; }
      `}</style>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 28,
        }}
      >
        {/* rings + logo mark */}
        <div
          style={{
            position: "relative",
            width: 200,
            height: 200,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div className="ldr-ring ldr-r1" />
          <div className="ldr-ring ldr-r2" />
          <div className="ldr-ring ldr-r3" />

          <div className="ldr-logo" style={{ position: "relative", zIndex: 1 }}>
            <div
              style={{
                width: 110,
                height: 110,
                borderRadius: 28,
                overflow: "hidden",
                boxShadow: "0 0 0 1px rgba(0,0,0,0.06)",
              }}
            >
              <img
                src="/logo.png"
                alt="Echoproof"
                width={110}
                height={110}
                style={{ width: "100%", height: "100%", objectFit: "cover" }}
              />
            </div>
          </div>
        </div>

        {/* wordmark */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 5,
          }}
        >
          <span
            className="ldr-name"
            style={{
              fontSize: 24,
              fontWeight: 700,
              letterSpacing: "-0.02em",
              color: "#1A1A1A",
              fontFamily: "'Josefin Sans', sans-serif",
            }}
          >
            Echoproof
          </span>
          <span
            className="ldr-tag"
            style={{
              fontSize: 12,
              color: "#9A9A9A",
              letterSpacing: "0.18em",
              textTransform: "uppercase",
              fontFamily: "'Josefin Sans', sans-serif",
            }}
          >
            truth, verified
          </span>
        </div>
      </div>
    </div>
  );
}

// ─── DATA ─────────────────────────────────────────────────────────────────────

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

const statusConfig: Record<string, { color: string; bg: string; dot: string }> =
  {
    verified: { color: "#2D7A4A", bg: "#E8F5EE", dot: "#4CAF6E" },
    controversial: { color: "#7A5200", bg: "#FFF3E0", dot: "#E8A000" },
    disputed: { color: "#B03E28", bg: "#FFF0ED", dot: "#FF7759" },
    active: { color: "#1A6DB5", bg: "#E8F4FD", dot: "#3498DB" },
  };

const tierColor: Record<string, string> = {
  Unverified: "#9A9A9A",
  Low: "#5A5A5A",
  Medium: "#1A1A1A",
  High: "#4CAF6E",
  Elite: "#2D7A4A",
};

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

// ─── HOOKS ────────────────────────────────────────────────────────────────────

function useParallax(speed = 0.3) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let ticking = false;
    const onScroll = () => {
      if (!ref.current || ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        if (!ref.current) return;
        const parent = ref.current.parentElement;
        if (!parent) return;
        const rect = parent.getBoundingClientRect();
        const vh = window.innerHeight;
        const progress = (vh / 2 - rect.top - rect.height / 2) / vh;
        ref.current.style.transform = `translateY(${progress * speed * 160}px)`;
        ticking = false;
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener("scroll", onScroll);
  }, [speed]);

  return ref;
}

function useScrollReveal(threshold = 0.12) {
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

// ─── COMPONENTS ───────────────────────────────────────────────────────────────

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
    up: "translateY(48px)",
    left: "translateX(-48px)",
    right: "translateX(48px)",
    none: "none",
  };
  return (
    <div
      ref={ref}
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? "none" : transforms[direction],
        transition: `opacity 0.9s ease ${delay}ms, transform 0.9s cubic-bezier(0.16,1,0.3,1) ${delay}ms`,
        willChange: "opacity, transform",
      }}
    >
      {children}
    </div>
  );
}

function PlayStoreBadge({ light = false }: { light?: boolean }) {
  const [hovered, setHovered] = useState(false);
  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 10,
        height: 52,
        padding: "0 22px 0 18px",
        borderRadius: 14,
        background: light
          ? hovered
            ? "rgba(255,255,255,0.18)"
            : "rgba(255,255,255,0.10)"
          : hovered
            ? "#2d2d2d"
            : "#1A1A1A",
        border: light ? "1px solid rgba(255,255,255,0.2)" : "none",
        transition: "background 0.2s, box-shadow 0.2s, transform 0.2s",
        boxShadow: hovered
          ? light
            ? "0 8px 28px rgba(0,0,0,0.25)"
            : "0 8px 28px rgba(0,0,0,0.22)"
          : "none",
        transform: hovered ? "translateY(-2px)" : "none",
        fontFamily: "'Josefin Sans', sans-serif",
        flexShrink: 0,
      }}
    >
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
        <path
          d="M3.18 23.76c.42.24.9.24 1.32 0L16.1 16.9l-3.28-3.28-9.64 10.14z"
          fill={light ? "#fff" : "#EA4335"}
        />
        <path
          d="M20.82 10.03c-.42-.24-.9-.35-1.38-.35l-3.34 1.93 3.52 3.52 1.2-.69c.84-.48.84-1.68 0-2.16z"
          fill={light ? "#fff" : "#FBBC04"}
        />
        <path
          d="M3.18.24A1.44 1.44 0 002 1.68v20.64c0 .6.33 1.13.82 1.44L15.54 12 3.18.24z"
          fill={light ? "#fff" : "#4285F4"}
        />
        <path
          d="M4.5.24L16.1 7.1l-3.28 3.28L3.18.24A1.5 1.5 0 014.5.24z"
          fill={light ? "#fff" : "#34A853"}
        />
      </svg>
      <div style={{ display: "flex", flexDirection: "column", gap: 1 }}>
        <span
          style={{
            fontSize: 9,
            color: light ? "rgba(255,255,255,0.7)" : "#9A9A9A",
            letterSpacing: "0.08em",
            textTransform: "uppercase",
          }}
        >
          Coming soon on
        </span>
        <span
          style={{
            fontSize: 14,
            fontWeight: 700,
            color: "#fff",
            letterSpacing: "-0.01em",
          }}
        >
          Google Play
        </span>
      </div>
    </div>
  );
}

function TickerCard({ echo }: { echo: (typeof tickerEchoes)[0] }) {
  const cfg = statusConfig[echo.status] ?? statusConfig.active;
  return (
    <div
      style={{
        width: 310,
        flexShrink: 0,
        background: "#fff",
        borderRadius: 20,
        border: `1.2px solid ${cfg.dot}35`,
        padding: "18px 18px 14px",
        boxShadow: "0 2px 20px rgba(0,0,0,0.06)",
        display: "flex",
        flexDirection: "column",
        gap: 11,
        fontFamily: "'Josefin Sans', sans-serif",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
        <div
          style={{
            width: 34,
            height: 34,
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
          <span style={{ fontSize: 11, fontWeight: 700, color: "#2D7A4A" }}>
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
              lineHeight: 1.3,
            }}
          >
            {echo.username}
          </p>
          <p style={{ fontSize: 10, color: "#9A9A9A", margin: 0 }}>
            {echo.tier} · {echo.tierWeight} · {echo.category}
          </p>
        </div>
        <span style={{ fontSize: 10, color: "#AAAAAA", flexShrink: 0 }}>
          {echo.timeAgo}
        </span>
      </div>

      <p
        style={{
          fontSize: 12.5,
          color: "#1A1A1A",
          lineHeight: 1.65,
          margin: 0,
          display: "-webkit-box",
          WebkitLineClamp: 4,
          WebkitBoxOrient: "vertical",
          overflow: "hidden",
        }}
      >
        {echo.content}
      </p>

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

      <div>
        <div
          style={{
            height: 4,
            background: "#F8F7F5",
            borderRadius: 999,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              height: "100%",
              width: `${echo.confidence}%`,
              background: cfg.dot,
              borderRadius: 999,
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
          <span style={{ fontSize: 9, color: "#AAAAAA" }}>
            Community confidence
          </span>
          <span style={{ fontSize: 9, fontWeight: 700, color: cfg.dot }}>
            {echo.confidence}%
          </span>
        </div>
      </div>

      <div
        style={{
          display: "flex",
          gap: 7,
          paddingTop: 9,
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
            padding: "3px 10px",
          }}
        >
          Support · {echo.supports}
        </span>
        <span
          style={{
            fontSize: 11,
            color: "#9A9A9A",
            background: "#F8F7F5",
            borderRadius: 999,
            padding: "3px 10px",
          }}
        >
          Challenge · {echo.challenges}
        </span>
      </div>
    </div>
  );
}

function EchoTicker() {
  const { ref: wrapperRef, visible } = useScrollReveal(0.05);
  const [paused, setPaused] = useState(false);
  const doubled = [...tickerEchoes, ...tickerEchoes];

  return (
    <div ref={wrapperRef} style={{ overflow: "hidden" }}>
      <style>{`
        @keyframes ticker-scroll {
          from { transform: translateX(0); }
          to   { transform: translateX(-50%); }
        }
        .ticker-track { display: flex; gap: 14px; width: max-content; padding: 4px 2px 12px; }
        .ticker-running { animation: ticker-scroll 44s linear infinite; }
        .ticker-paused  { animation: ticker-scroll 44s linear infinite paused; }
      `}</style>
      <div
        className={
          visible
            ? paused
              ? "ticker-track ticker-paused"
              : "ticker-track ticker-running"
            : "ticker-track"
        }
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

// ─── MAIN ─────────────────────────────────────────────────────────────────────

export default function LandingClient() {
  const heroMeshRef = useParallax(0.55);
  const heroOrbTopRef = useParallax(0.75);
  const heroOrbBotRef = useParallax(0.4);
  const heroGridRef = useParallax(0.2);
  const heroContentRef = useParallax(0.12);
  const tickerOrbRef = useParallax(0.6);
  const howItWorksBgRef = useParallax(0.5);
  const trustMeshRef = useParallax(0.65);
  const trustOrbRef = useParallax(0.8);
  const chainBgRef = useParallax(0.45);
  const ctaOrbRef = useParallax(0.7);

  return (
    <>
      {/* loader renders here — purely client side, no ssr involvement */}
      <PageLoader />

      <main
        style={{
          flex: 1,
          background: "#fff",
          overflowX: "hidden",
          fontFamily: "'Josefin Sans', sans-serif",
        }}
      >
        <style>{`
          /* smooth scroll for anchor links */
          html { scroll-behavior: smooth; }

          /* section entrance — content fades up when navigating to anchor */
          @keyframes section-enter {
            0%   { opacity: 0.6; transform: translateY(12px); }
            100% { opacity: 1;   transform: translateY(0); }
          }
          section:target {
            animation: section-enter 0.7s cubic-bezier(0.16,1,0.3,1) both;
          }

          @keyframes float-slow {
            0%,100% { transform: translateY(0) scale(1); }
            50%      { transform: translateY(-22px) scale(1.03); }
          }
          @keyframes float-med {
            0%,100% { transform: translateY(0) rotate(0deg); }
            50%      { transform: translateY(-14px) rotate(2deg); }
          }
          @keyframes grid-drift {
            0%   { transform: translateX(0) translateY(0); }
            100% { transform: translateX(-40px) translateY(-20px); }
          }
          @keyframes hero-in {
            0%   { opacity:0; transform:translateY(36px); }
            100% { opacity:1; transform:translateY(0); }
          }
          @keyframes fade-up {
            0%   { opacity:0; transform:translateY(20px); }
            100% { opacity:1; transform:translateY(0); }
          }
          @keyframes spin-slow {
            from { transform: rotate(0deg); }
            to   { transform: rotate(360deg); }
          }
          .hero-eyebrow { animation: fade-up 0.8s ease 100ms both; }
          .hero-h1-1    { animation: hero-in 1s cubic-bezier(0.16,1,0.3,1) 250ms both; }
          .hero-h1-2    { animation: hero-in 1s cubic-bezier(0.16,1,0.3,1) 420ms both; }
          .hero-sub     { animation: fade-up 1s ease 650ms both; }
          .hero-cta     { animation: fade-up 1s ease 850ms both; }
          .hero-hint    { animation: fade-up 1s ease 1150ms both; }
          .ring-rotate  { animation: spin-slow 24s linear infinite; }

          @media (max-width:640px) {
            .hero-h1 { font-size: clamp(38px, 12vw, 62px) !important; }
          }
        `}</style>

        {/* ── HERO ──────────────────────────────────────────────────────────── */}
        <section
          style={{
            position: "relative",
            minHeight: "100svh",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            overflow: "hidden",
            padding: "120px 24px 96px",
          }}
        >
          <div
            ref={heroGridRef}
            aria-hidden
            style={{
              position: "absolute",
              inset: "-30%",
              zIndex: 0,
              backgroundImage:
                "radial-gradient(circle, rgba(26,26,26,0.07) 1px, transparent 1px)",
              backgroundSize: "28px 28px",
              animation: "grid-drift 30s linear infinite alternate",
              opacity: 0.6,
            }}
          />

          <div
            ref={heroMeshRef}
            aria-hidden
            style={{
              position: "absolute",
              inset: "-20%",
              zIndex: 1,
              background:
                "radial-gradient(ellipse 75% 60% at 50% 25%, rgba(76,175,110,0.11) 0%, transparent 65%), radial-gradient(ellipse 50% 40% at 20% 80%, rgba(232,160,0,0.06) 0%, transparent 55%)",
            }}
          />

          <div
            ref={heroOrbTopRef}
            aria-hidden
            style={{
              position: "absolute",
              top: "8%",
              right: "-4%",
              width: 500,
              height: 500,
              zIndex: 2,
              borderRadius: "50%",
              background:
                "radial-gradient(circle, rgba(76,175,110,0.13) 0%, transparent 68%)",
              animation: "float-slow 10s ease-in-out infinite",
              filter: "blur(1px)",
            }}
          />

          <div
            ref={heroOrbBotRef}
            aria-hidden
            style={{
              position: "absolute",
              bottom: "-5%",
              left: "-8%",
              width: 380,
              height: 380,
              zIndex: 2,
              borderRadius: "50%",
              background:
                "radial-gradient(circle, rgba(76,175,110,0.08) 0%, transparent 65%)",
              animation: "float-med 13s ease-in-out infinite 2s",
            }}
          />

          <div
            className="ring-rotate"
            aria-hidden
            style={{
              position: "absolute",
              top: "20%",
              right: "12%",
              width: 180,
              height: 180,
              zIndex: 2,
              borderRadius: "50%",
              opacity: 0.12,
              border: "1px solid #4CAF6E",
            }}
          />
          <div
            className="ring-rotate"
            aria-hidden
            style={{
              position: "absolute",
              top: "22%",
              right: "14%",
              width: 120,
              height: 120,
              zIndex: 2,
              borderRadius: "50%",
              opacity: 0.08,
              border: "1px solid #4CAF6E",
              animationDirection: "reverse",
              animationDuration: "16s",
            }}
          />

          <div
            ref={heroContentRef}
            style={{
              position: "relative",
              zIndex: 3,
              maxWidth: 700,
              width: "100%",
              textAlign: "center",
            }}
          >
            <p
              className="hero-eyebrow"
              style={{
                fontSize: 11,
                letterSpacing: "0.20em",
                textTransform: "uppercase",
                color: "#9A9A9A",
                marginBottom: 28,
              }}
            >
              A new kind of social network
            </p>

            <h1
              className="hero-h1"
              style={{
                fontSize: "clamp(44px, 8vw, 78px)",
                fontWeight: 700,
                letterSpacing: "-0.035em",
                lineHeight: 1.06,
                color: "#1A1A1A",
                margin: "0 0 26px",
              }}
            >
              <span className="hero-h1-1" style={{ display: "block" }}>
                The crowd decides
              </span>
              <span
                className="hero-h1-2"
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
                lineHeight: 1.8,
                maxWidth: 460,
                margin: "0 auto 44px",
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
                alignItems: "center",
              }}
            >
              <PlayStoreBadge />
              <a
                href="#how-it-works"
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  height: 52,
                  padding: "0 26px",
                  borderRadius: 14,
                  border: "1px solid #E6E6E6",
                  color: "#1A1A1A",
                  fontSize: 13,
                  fontWeight: 500,
                  textDecoration: "none",
                  transition: "border-color 0.2s, background 0.2s",
                  fontFamily: "'Josefin Sans', sans-serif",
                }}
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLElement).style.borderColor =
                    "#1A1A1A";
                  (e.currentTarget as HTMLElement).style.background = "#F8F7F5";
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLElement).style.borderColor =
                    "#E6E6E6";
                  (e.currentTarget as HTMLElement).style.background =
                    "transparent";
                }}
              >
                How it works
              </a>
            </div>
          </div>

          <div
            className="hero-hint"
            aria-hidden
            style={{
              position: "absolute",
              bottom: 32,
              left: "50%",
              transform: "translateX(-50%)",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
            }}
          >
            <div
              style={{
                width: 1,
                height: 52,
                background:
                  "linear-gradient(to bottom, transparent, rgba(154,154,154,0.5))",
                borderRadius: 999,
              }}
            />
          </div>
        </section>

        {/* ── TICKER ────────────────────────────────────────────────────────── */}
        <section
          style={{
            position: "relative",
            padding: "80px 0 72px",
            background: "#F8F7F5",
            overflow: "hidden",
          }}
        >
          <div
            ref={tickerOrbRef}
            aria-hidden
            style={{
              position: "absolute",
              top: "-30%",
              right: "-5%",
              width: 360,
              height: 360,
              borderRadius: "50%",
              pointerEvents: "none",
              background:
                "radial-gradient(circle, rgba(76,175,110,0.09) 0%, transparent 65%)",
            }}
          />

          <div
            style={{ maxWidth: 960, margin: "0 auto", padding: "0 24px 28px" }}
          >
            <Reveal>
              <p
                style={{
                  fontSize: 11,
                  letterSpacing: "0.18em",
                  textTransform: "uppercase",
                  color: "#9A9A9A",
                  marginBottom: 8,
                }}
              >
                Live from the platform
              </p>
              <h2
                style={{
                  fontSize: "clamp(24px, 4.5vw, 38px)",
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
            style={{ maxWidth: 960, margin: "20px auto 0", padding: "0 24px" }}
          >
            <Reveal delay={80}>
              <p
                style={{
                  fontSize: 12,
                  color: "#9A9A9A",
                  lineHeight: 1.65,
                  maxWidth: 560,
                }}
              >
                Every card above is a real format — exactly what you see in the
                app. Status, confidence, and support counts evolve as the
                community weighs in. Nothing is static.
              </p>
            </Reveal>
          </div>
        </section>

        {/* ── HOW IT WORKS ──────────────────────────────────────────────────── */}
        <section
          id="how-it-works"
          style={{
            position: "relative",
            overflow: "hidden",
            padding: "100px 24px",
            maxWidth: 960,
            margin: "0 auto",
          }}
        >
          <div
            ref={howItWorksBgRef}
            aria-hidden
            style={{
              position: "absolute",
              top: "5%",
              right: "-2%",
              width: 300,
              height: 300,
              borderRadius: "50%",
              pointerEvents: "none",
              background:
                "radial-gradient(circle, rgba(76,175,110,0.06) 0%, transparent 65%)",
            }}
          />

          <Reveal>
            <p
              style={{
                fontSize: 11,
                letterSpacing: "0.18em",
                textTransform: "uppercase",
                color: "#9A9A9A",
                marginBottom: 8,
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
                lineHeight: 1.12,
                marginBottom: 14,
              }}
            >
              From claim to consensus
            </h2>
            <p
              style={{
                fontSize: 15,
                color: "#5A5A5A",
                lineHeight: 1.8,
                maxWidth: 520,
                marginBottom: 68,
              }}
            >
              Most platforms amplify what is popular. Echoproof surfaces what
              holds up under scrutiny. The process is transparent, weighted, and
              once resolved — permanent.
            </p>
          </Reveal>

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
              delay={i * 75}
              direction={i % 2 === 0 ? "left" : "right"}
            >
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "auto 1fr",
                  gap: "0 28px",
                  alignItems: "start",
                  marginBottom: 52,
                  paddingBottom: 52,
                  borderBottom: "1px solid #F0F0F0",
                }}
              >
                <span
                  style={{
                    fontSize: 11,
                    fontWeight: 700,
                    color: "#4CAF6E",
                    letterSpacing: "0.10em",
                    paddingTop: 5,
                    minWidth: 24,
                  }}
                >
                  {step.number}
                </span>
                <div>
                  <h3
                    style={{
                      fontSize: "clamp(17px, 2.8vw, 22px)",
                      fontWeight: 700,
                      color: "#1A1A1A",
                      letterSpacing: "-0.02em",
                      marginBottom: 11,
                      lineHeight: 1.25,
                    }}
                  >
                    {step.title}
                  </h3>
                  <p
                    style={{
                      fontSize: 14,
                      color: "#5A5A5A",
                      lineHeight: 1.85,
                      marginBottom: 14,
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
                      margin: 0,
                    }}
                  >
                    {step.aside}
                  </p>
                </div>
              </div>
            </Reveal>
          ))}
        </section>

        {/* ── TRUST ENGINE ──────────────────────────────────────────────────── */}
        <section
          id="trust"
          style={{
            position: "relative",
            overflow: "hidden",
            background: "#1A1A1A",
            padding: "100px 24px",
          }}
        >
          <div
            ref={trustMeshRef}
            aria-hidden
            style={{
              position: "absolute",
              inset: "-20%",
              background:
                "radial-gradient(ellipse 65% 55% at 80% 40%, rgba(76,175,110,0.10) 0%, transparent 60%), radial-gradient(ellipse 40% 40% at 10% 70%, rgba(76,175,110,0.06) 0%, transparent 55%)",
              pointerEvents: "none",
              zIndex: 0,
            }}
          />
          <div
            ref={trustOrbRef}
            aria-hidden
            style={{
              position: "absolute",
              top: "-15%",
              right: "-6%",
              width: 440,
              height: 440,
              borderRadius: "50%",
              pointerEvents: "none",
              zIndex: 0,
              background:
                "radial-gradient(circle, rgba(76,175,110,0.13) 0%, transparent 62%)",
              animation: "float-slow 12s ease-in-out infinite",
            }}
          />
          <div
            aria-hidden
            style={{
              position: "absolute",
              inset: 0,
              backgroundImage:
                "radial-gradient(circle, rgba(255,255,255,0.04) 1px, transparent 1px)",
              backgroundSize: "32px 32px",
              pointerEvents: "none",
              zIndex: 0,
            }}
          />

          <div
            style={{
              maxWidth: 960,
              margin: "0 auto",
              position: "relative",
              zIndex: 1,
            }}
          >
            <Reveal>
              <p
                style={{
                  fontSize: 11,
                  letterSpacing: "0.18em",
                  textTransform: "uppercase",
                  color: "#4CAF6E",
                  marginBottom: 8,
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
                  lineHeight: 1.12,
                  marginBottom: 14,
                }}
              >
                Not all voices carry the same weight.
              </h2>
              <p
                style={{
                  fontSize: 15,
                  color: "#9A9A9A",
                  lineHeight: 1.8,
                  maxWidth: 520,
                  marginBottom: 56,
                }}
              >
                On every other platform, a thousand new accounts can out-shout a
                hundred experts. On Echoproof, a verified contributor&apos;s single
                vote can outweigh a wave of anonymous noise. The engine
                calculates this automatically — no moderation team required.
              </p>
            </Reveal>

            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              {tiers.map((tier, i) => (
                <Reveal key={tier.label} delay={i * 65} direction="left">
                  <div
                    style={{
                      display: "grid",
                      gridTemplateColumns: "100px 1fr auto",
                      alignItems: "center",
                      gap: 18,
                      padding: "14px 18px",
                      borderRadius: 13,
                      background: "rgba(255,255,255,0.04)",
                      border: "1px solid rgba(255,255,255,0.07)",
                      transition: "background 0.2s",
                    }}
                    onMouseEnter={(e) =>
                      ((e.currentTarget as HTMLElement).style.background =
                        "rgba(255,255,255,0.07)")
                    }
                    onMouseLeave={(e) =>
                      ((e.currentTarget as HTMLElement).style.background =
                        "rgba(255,255,255,0.04)")
                    }
                  >
                    <div
                      style={{ display: "flex", alignItems: "center", gap: 9 }}
                    >
                      <div
                        style={{
                          width: 7,
                          height: 7,
                          borderRadius: "50%",
                          background: tierColor[tier.label],
                          flexShrink: 0,
                        }}
                      />
                      <span
                        style={{ fontSize: 13, fontWeight: 600, color: "#fff" }}
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
                        minWidth: 24,
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

        {/* ── ON-CHAIN ──────────────────────────────────────────────────────── */}
        <section
          style={{
            position: "relative",
            overflow: "hidden",
            padding: "100px 24px",
            maxWidth: 960,
            margin: "0 auto",
          }}
        >
          <div
            ref={chainBgRef}
            aria-hidden
            style={{
              position: "absolute",
              bottom: "-10%",
              left: "-5%",
              width: 350,
              height: 350,
              borderRadius: "50%",
              pointerEvents: "none",
              background:
                "radial-gradient(circle, rgba(76,175,110,0.07) 0%, transparent 65%)",
            }}
          />

          <Reveal>
            <p
              style={{
                fontSize: 11,
                letterSpacing: "0.18em",
                textTransform: "uppercase",
                color: "#9A9A9A",
                marginBottom: 8,
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
                lineHeight: 1.12,
                marginBottom: 14,
              }}
            >
              Once verified, no one can undo it.
            </h2>
            <p
              style={{
                fontSize: 15,
                color: "#5A5A5A",
                lineHeight: 1.8,
                maxWidth: 560,
                marginBottom: 60,
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
              gridTemplateColumns: "repeat(auto-fit, minmax(255px, 1fr))",
              gap: 18,
            }}
          >
            {chainFeatures.map((feature, i) => (
              <Reveal key={feature.title} delay={i * 90}>
                <div
                  style={{
                    padding: 24,
                    borderRadius: 18,
                    border: "1px solid #E6E6E6",
                    background: "#F8F7F5",
                    height: "100%",
                    boxSizing: "border-box",
                    transition: "box-shadow 0.2s, transform 0.2s",
                  }}
                  onMouseEnter={(e) => {
                    (e.currentTarget as HTMLElement).style.boxShadow =
                      "0 8px 28px rgba(0,0,0,0.08)";
                    (e.currentTarget as HTMLElement).style.transform =
                      "translateY(-3px)";
                  }}
                  onMouseLeave={(e) => {
                    (e.currentTarget as HTMLElement).style.boxShadow = "none";
                    (e.currentTarget as HTMLElement).style.transform = "none";
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
                      lineHeight: 1.8,
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

        {/* ── REPUTATION ────────────────────────────────────────────────────── */}
        <section
          style={{
            position: "relative",
            overflow: "hidden",
            background: "#EAE7DF",
            padding: "88px 24px",
          }}
        >
          <div
            ref={ctaOrbRef}
            aria-hidden
            style={{
              position: "absolute",
              top: "-20%",
              right: "-5%",
              width: 380,
              height: 380,
              borderRadius: "50%",
              pointerEvents: "none",
              background:
                "radial-gradient(circle, rgba(76,175,110,0.10) 0%, transparent 65%)",
              animation: "float-med 11s ease-in-out infinite",
            }}
          />

          <div
            style={{
              maxWidth: 680,
              margin: "0 auto",
              textAlign: "center",
              position: "relative",
              zIndex: 1,
            }}
          >
            <Reveal>
              <h2
                style={{
                  fontSize: "clamp(22px, 4.5vw, 38px)",
                  fontWeight: 700,
                  letterSpacing: "-0.025em",
                  color: "#1A1A1A",
                  lineHeight: 1.2,
                  marginBottom: 18,
                }}
              >
                Your reputation belongs to you — not the platform.
              </h2>
              <p
                style={{
                  fontSize: 15,
                  color: "#5A5A5A",
                  lineHeight: 1.85,
                  maxWidth: 520,
                  margin: "0 auto 40px",
                }}
              >
                When you reach High or Elite trust tier, your reputation is
                anchored to the Solana blockchain. That record is yours. It
                cannot be deleted when you leave. It cannot be altered if we
                shut down. It lives independently, and it travels with you to
                any platform that reads the ledger.
              </p>
              <PlayStoreBadge />
            </Reveal>
          </div>
        </section>

        {/* ── FINAL CTA ─────────────────────────────────────────────────────── */}
        <section
          style={{
            position: "relative",
            overflow: "hidden",
            padding: "100px 24px",
            background: "#1A1A1A",
          }}
        >
          <div
            aria-hidden
            style={{
              position: "absolute",
              inset: 0,
              backgroundImage:
                "radial-gradient(circle, rgba(255,255,255,0.035) 1px, transparent 1px)",
              backgroundSize: "28px 28px",
              pointerEvents: "none",
            }}
          />
          <div
            aria-hidden
            style={{
              position: "absolute",
              inset: "-20%",
              background:
                "radial-gradient(ellipse 70% 55% at 50% 50%, rgba(76,175,110,0.10) 0%, transparent 60%)",
              pointerEvents: "none",
            }}
          />

          <div
            style={{
              maxWidth: 560,
              margin: "0 auto",
              textAlign: "center",
              position: "relative",
              zIndex: 1,
            }}
          >
            <Reveal>
              <div
                style={{
                  width: 64,
                  height: 64,
                  borderRadius: 18,
                  overflow: "hidden",
                  margin: "0 auto 28px",
                  boxShadow:
                    "0 0 0 1px rgba(255,255,255,0.1), 0 8px 28px rgba(76,175,110,0.25)",
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
                  color: "#fff",
                  lineHeight: 1.2,
                  marginBottom: 14,
                }}
              >
                Join the conversation.{" "}
                <span style={{ color: "#4CAF6E" }}>Make it count.</span>
              </h2>
              <p
                style={{
                  fontSize: 14,
                  color: "#9A9A9A",
                  lineHeight: 1.8,
                  marginBottom: 36,
                }}
              >
                Coming soon on Android. Post echoes, earn trust, stake claims,
                and help the community establish what is actually true.
              </p>
              <PlayStoreBadge light />
            </Reveal>
          </div>
        </section>
      </main>
    </>
  );
}
