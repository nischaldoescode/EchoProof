"use client";

// web auth callback page
// @params none

import Image from "next/image";
import { useEffect } from "react";

function authCallbackUrl() {
  if (typeof window === "undefined") return "echoproof://auth-callback";
  return `echoproof://auth-callback${window.location.search}${window.location.hash}`;
}

export default function AuthCallbackPage() {
  useEffect(() => {
    const timer = window.setTimeout(() => {
      window.location.assign(authCallbackUrl());
    }, 300);

    return () => window.clearTimeout(timer);
  }, []);

  return (
    <main className="min-h-screen bg-[#f5faf7] text-[#171717] flex items-center justify-center px-6">
      <section className="callback-panel w-full max-w-sm rounded-[8px] bg-white p-6 shadow-[0_16px_40px_rgba(23,23,23,0.08)] border border-black/5 text-center">
        <div className="logo-stage mx-auto">
          <span className="logo-ring logo-ring-one" />
          <span className="logo-ring logo-ring-two" />
          <Image
            src="/logo.png"
            alt="Echoproof"
            width={68}
            height={68}
            className="relative z-10 rounded-[8px]"
            priority
          />
        </div>
        <h1 className="mt-6 text-xl font-semibold tracking-normal">
          Opening Echoproof
        </h1>
        <p className="mt-2 text-sm leading-6 text-neutral-600">
          One moment while we bring you back to the app.
        </p>
        <div
          aria-hidden="true"
          className="mt-5 flex items-center justify-center gap-1.5"
        >
          <span className="status-dot status-dot-one" />
          <span className="status-dot status-dot-two" />
          <span className="status-dot status-dot-three" />
        </div>
        <a
          href="echoproof://auth-callback"
          onClick={(event) => {
            event.preventDefault();
            window.location.assign(authCallbackUrl());
          }}
          className="mt-6 inline-flex w-full items-center justify-center rounded-[8px] bg-[#171717] px-4 py-3 text-sm font-semibold text-white"
        >
          Open app
        </a>
      </section>
      <style jsx>{`
        .callback-panel {
          animation: panel-in 520ms cubic-bezier(0.16, 1, 0.3, 1) both;
        }

        .logo-stage {
          position: relative;
          display: grid;
          place-items: center;
          width: 92px;
          height: 92px;
        }

        .logo-ring {
          position: absolute;
          inset: 8px;
          border: 1px solid rgba(76, 175, 110, 0.28);
          border-radius: 18px;
          animation: ring-breathe 1800ms ease-in-out infinite;
        }

        .logo-ring-two {
          inset: 0;
          opacity: 0.42;
          animation-delay: 260ms;
        }

        .status-dot {
          width: 6px;
          height: 6px;
          border-radius: 999px;
          background: #4caf6e;
          animation: dot-rise 900ms ease-in-out infinite;
        }

        .status-dot-two {
          animation-delay: 120ms;
        }

        .status-dot-three {
          animation-delay: 240ms;
        }

        @keyframes panel-in {
          from {
            opacity: 0;
            transform: translateY(10px) scale(0.98);
          }
          to {
            opacity: 1;
            transform: translateY(0) scale(1);
          }
        }

        @keyframes ring-breathe {
          0%,
          100% {
            transform: scale(0.96);
            opacity: 0.38;
          }
          50% {
            transform: scale(1.08);
            opacity: 0.75;
          }
        }

        @keyframes dot-rise {
          0%,
          100% {
            transform: translateY(0);
            opacity: 0.5;
          }
          50% {
            transform: translateY(-4px);
            opacity: 1;
          }
        }

        @media (prefers-reduced-motion: reduce) {
          .callback-panel,
          .logo-ring,
          .status-dot {
            animation: none;
          }
        }
      `}</style>
    </main>
  );
}
