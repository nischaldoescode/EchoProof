"use client";

// web room invite page
// @params none

import { useEffect, useMemo, useState } from "react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

const ANDROID_PACKAGE = "com.echoproof.app";
const ROOM_CODE_RE = /^[A-Z2-9]{8}$/;

type DeviceInfo = {
  isAndroid: boolean;
  isIos: boolean;
  isMobile: boolean;
};

function detectDevice(userAgent: string): DeviceInfo {
  const ua = userAgent.toLowerCase();
  return {
    isAndroid: ua.includes("android"),
    isIos: /iphone|ipad|ipod/.test(ua),
    isMobile: /android|iphone|ipad|ipod|mobile/.test(ua),
  };
}

function encodeAppQuery(code: string, key: string) {
  const params = new URLSearchParams();
  params.set("code", code);
  params.set("key", key);
  return params.toString();
}

function buildAndroidIntent(code: string, key: string, fallbackUrl: string) {
  const query = encodeAppQuery(code, key);
  const fallback = encodeURIComponent(
    fallbackUrl || "https://echoproof.online/room",
  );
  return `intent://room/join?${query}#Intent;scheme=echoproof;package=${ANDROID_PACKAGE};S.browser_fallback_url=${fallback};end`;
}

export default function RoomInvitePage() {
  const [code, setCode] = useState("");
  const [key, setKey] = useState("");
  const [device, setDevice] = useState<DeviceInfo>({
    isAndroid: false,
    isIos: false,
    isMobile: false,
  });
  const [currentUrl, setCurrentUrl] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams(window.location.search);
      const fragment = new URLSearchParams(
        window.location.hash.replace(/^#/, ""),
      );
      setCode((params.get("code") || fragment.get("code") || "").toUpperCase());
      setKey(params.get("key") || fragment.get("key") || "");
      setDevice(detectDevice(window.navigator.userAgent));
      setCurrentUrl(window.location.href);
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  const hasCode = ROOM_CODE_RE.test(code);
  const hasKey = key.trim().length > 0;
  const hasFullInvite = hasCode && hasKey;

  const appLink = useMemo(() => {
    if (!hasFullInvite) return "";
    return `echoproof://room/join?${encodeAppQuery(code, key)}`;
  }, [code, hasFullInvite, key]);

  const androidIntent = useMemo(() => {
    if (!hasFullInvite) return "";
    return buildAndroidIntent(code, key, currentUrl);
  }, [code, currentUrl, hasFullInvite, key]);

  const openHref = device.isAndroid && androidIntent ? androidIntent : appLink;
  const status = useMemo(() => {
    if (hasFullInvite) {
      return {
        tone: "ready",
        eyebrow: "invite ready",
        title: "Open this room in EchoProof.",
        body:
          "The room code and secret key were found. EchoProof will use them locally so this device can decrypt the room.",
      };
    }

    if (hasCode && !hasKey) {
      return {
        tone: "warn",
        eyebrow: "secret key missing",
        title: "This invite is incomplete.",
        body:
          "The room code is present, but the secret key is missing. Ask the sender to share the full invite link again.",
      };
    }

    if (!hasCode && hasKey) {
      return {
        tone: "warn",
        eyebrow: "room code missing",
        title: "This invite cannot be opened yet.",
        body:
          "A secret key was found, but there is no valid 8-character room code. Paste the complete invite from EchoProof.",
      };
    }

    return {
      tone: "empty",
      eyebrow: "secure room doorway",
      title: "Open a full EchoProof room invite.",
      body:
        "This page opens encrypted room links. A usable invite needs both a room code and a secret key.",
    };
  }, [hasCode, hasFullInvite, hasKey]);

  useEffect(() => {
    if (!hasFullInvite || !device.isAndroid || !androidIntent) return;
    const timer = window.setTimeout(() => {
      window.location.href = androidIntent;
    }, 650);
    return () => window.clearTimeout(timer);
  }, [androidIntent, device.isAndroid, hasFullInvite]);

  async function copyInvite() {
    if (!currentUrl || !navigator.clipboard) return;
    await navigator.clipboard.writeText(currentUrl);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <>
      <Nav />
      <main className="min-h-screen bg-white px-6 py-20 text-charcoal">
        <section className="mx-auto grid max-w-5xl gap-8 md:grid-cols-[1.05fr_0.95fr] md:items-center">
          <div className="ep-page-enter">
            <p
              className={`mb-4 inline-flex rounded-full border px-4 py-2 text-sm font-semibold ${
                status.tone === "ready"
                  ? "border-fern-green/25 bg-fern-light text-fern-dark"
                  : "border-sunset-coral/20 bg-coral-light text-coral-dark"
              }`}
            >
              {status.eyebrow}
            </p>
            <h1 className="max-w-xl text-5xl font-bold leading-[0.95] tracking-normal md:text-6xl">
              {status.title}
            </h1>
            <p className="mt-5 max-w-xl text-lg leading-7 text-neutral-600">
              {status.body}
            </p>

            <div className="mt-6 rounded-3xl border border-border-subtle bg-[#fbfaf8] p-5">
              <p className="text-sm font-semibold text-charcoal">
                {device.isAndroid
                  ? "Android detected. The button uses an app intent first."
                  : device.isIos
                    ? "iPhone or iPad detected. Use the app link if EchoProof is installed."
                    : "Desktop browser detected. Open this link on your phone."}
              </p>
              <p className="mt-2 text-sm leading-6 text-neutral-600">
                If the app does not open, make sure EchoProof is installed and
                the invite was copied without losing the secret key after the
                hash symbol.
              </p>
            </div>

            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <a
                href={hasFullInvite ? openHref : "#"}
                aria-disabled={!hasFullInvite}
                onClick={(event) => {
                  if (!hasFullInvite) event.preventDefault();
                }}
                className={`rounded-full px-6 py-3 text-center font-semibold transition ${
                  hasFullInvite
                    ? "bg-charcoal text-white hover:bg-neutral-800"
                    : "cursor-not-allowed bg-neutral-200 text-neutral-500"
                }`}
              >
                {hasFullInvite ? "Open EchoProof" : "Invite incomplete"}
              </a>
              <button
                type="button"
                onClick={copyInvite}
                disabled={!currentUrl}
                className="rounded-full border border-border-subtle px-6 py-3 text-center font-semibold text-charcoal transition hover:border-fern-green disabled:cursor-not-allowed disabled:text-neutral-400"
              >
                {copied ? "Copied" : "Copy invite link"}
              </button>
              <a
                href="https://echoproof.online"
                className="rounded-full border border-border-subtle px-6 py-3 text-center font-semibold text-charcoal transition hover:border-fern-green"
              >
                Learn about EchoProof
              </a>
            </div>
          </div>

          <div className="ep-card-in rounded-[2rem] border border-border-subtle bg-[#f8f7f5] p-6 shadow-[0_24px_70px_rgba(26,26,26,0.08)]">
            <div className="rounded-[1.5rem] bg-charcoal p-5 text-white">
              <div className="mb-10 flex items-center justify-between">
                <span className="rounded-full bg-white/10 px-3 py-1 text-xs font-semibold">
                  room invite
                </span>
                <span className="ep-liquid-loader" />
              </div>
              <p className="text-sm text-white/60">Room code</p>
              <p className="mt-2 break-all text-4xl font-bold tracking-normal">
                {hasCode ? code : "missing"}
              </p>
              <div className="mt-8 rounded-2xl border border-white/10 bg-white/[0.08] p-4">
                <p
                  className={`text-sm font-semibold ${
                    hasFullInvite ? "text-fern-green" : "text-[#ffb5a5]"
                  }`}
                >
                  {hasFullInvite
                    ? "Secret key found in this invite."
                    : "Secret key not ready."}
                </p>
                <p className="mt-2 text-sm leading-6 text-white/68">
                  EchoProof does not store room keys. If a link is opened
                  without the key, this device cannot decrypt the room.
                </p>
              </div>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
