"use client";

// page loader — mirrors the flutter splash screen animation
// only shown once per session — subsequent refreshes skip it
// rings expand from center, logo fades in with glow, then fades out

import { useEffect, useState } from "react";

export default function PageLoader() {
  const [shouldShow, setShouldShow] = useState(false);
  const [fading, setFading] = useState(false);
  const [gone, setGone] = useState(false);

  useEffect(() => {
    // check if loader was already shown this session
    const already = sessionStorage.getItem("echoproof_loader_shown");
    if (already) {
      setGone(true);
      return;
    }

    // mark as shown so refreshes skip it
    sessionStorage.setItem("echoproof_loader_shown", "1");
    setShouldShow(true);

    const fadeTimer = setTimeout(() => setFading(true), 1800);
    const goneTimer = setTimeout(() => setGone(true), 2300);
    return () => {
      clearTimeout(fadeTimer);
      clearTimeout(goneTimer);
    };
  }, []);

  if (gone || !shouldShow) return null;

  return (
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center"
      style={{
        backgroundColor: "#E8F5EE",
        opacity: fading ? 0 : 1,
        transition: "opacity 500ms ease-in-out",
        pointerEvents: fading ? "none" : "all",
      }}
    >
      <style>{`
        @keyframes ring-expand {
          0%   { transform: scale(0.55); opacity: 0.35; }
          100% { transform: scale(1.35); opacity: 0; }
        }
        @keyframes logo-in {
          0%   { opacity: 0; transform: scale(0.82); }
          100% { opacity: 1; transform: scale(1); }
        }
        @keyframes glow-pulse {
          0%, 100% { box-shadow: 0 0 0px 0px rgba(76,175,110,0); }
          50%       { box-shadow: 0 0 32px 8px rgba(76,175,110,0.25); }
        }
        .ring {
          position: absolute;
          width: 160px;
          height: 160px;
          border-radius: 50%;
          border: 1.5px solid #4CAF6E;
          animation: ring-expand 1s ease-out forwards;
        }
        .ring-1 { animation-delay: 0.1s; }
        .ring-2 { animation-delay: 0.25s; }
        .ring-3 { animation-delay: 0.4s; }
        .logo-mark {
          animation: logo-in 600ms cubic-bezier(0.34, 1.56, 0.64, 1) 100ms both,
                     glow-pulse 800ms ease-in-out 700ms;
        }
        .wordmark { animation: logo-in 600ms ease-out 400ms both; }
        .tagline  { animation: logo-in 600ms ease-out 550ms both; }
      `}</style>

      <div className="flex flex-col items-center gap-8">
        <div className="relative w-[200px] h-[200px] flex items-center justify-center">
          <div className="ring ring-1" />
          <div className="ring ring-2" />
          <div className="ring ring-3" />

          <div className="logo-mark relative z-10">
            <div
              style={{
                width: 110,
                height: 110,
                borderRadius: 28,
                overflow: "hidden",
                boxShadow: "0 0 0 1px rgba(0,0,0,0.05)",
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

        <div className="flex flex-col items-center gap-1.5">
          <span
            className="wordmark text-2xl font-semibold tracking-tight"
            style={{
              color: "#1A1A1A",
              fontFamily: "'Josefin Sans', sans-serif",
            }}
          >
            Echoproof
          </span>
          <span
            className="tagline text-[13px] font-normal"
            style={{
              color: "#5A5A5A",
              letterSpacing: "0.2px",
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
