"use client";

// echo app handoff controls
// @params echoid maps the web preview to the android app route

import { useEffect, useMemo, useState } from "react";

const ANDROID_PACKAGE = "com.echoproof.app";
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.echoproof.app";

type DeviceInfo = {
  isAndroid: boolean;
  isMobile: boolean;
};

function detectDevice(userAgent: string): DeviceInfo {
  const ua = userAgent.toLowerCase();
  return {
    isAndroid: ua.includes("android"),
    isMobile: /android|iphone|ipad|ipod|mobile/.test(ua),
  };
}

function buildAndroidIntent(echoId: string) {
  const encodedId = encodeURIComponent(echoId);
  const fallback = encodeURIComponent(PLAY_STORE_URL);
  return `intent://echo/${encodedId}#Intent;scheme=echoproof;package=${ANDROID_PACKAGE};S.browser_fallback_url=${fallback};end`;
}

export default function EchoOpenActions({ echoId }: { echoId: string }) {
  const [device, setDevice] = useState<DeviceInfo>({
    isAndroid: false,
    isMobile: false,
  });
  const [opening, setOpening] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setDevice(detectDevice(window.navigator.userAgent));
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!opening) return;
    const timer = window.setTimeout(() => setOpening(false), 2800);
    return () => window.clearTimeout(timer);
  }, [opening]);

  const appHref = useMemo(() => {
    if (!echoId) return "#";
    if (device.isAndroid) return buildAndroidIntent(echoId);
    return `echoproof://echo/${encodeURIComponent(echoId)}`;
  }, [device.isAndroid, echoId]);

  if (!device.isMobile) {
    return (
      <div className="mt-7 grid gap-3 sm:grid-cols-[1fr_auto]">
        <a
          href={PLAY_STORE_URL}
          className="ep-hover-lift flex h-12 items-center justify-center rounded-xl bg-charcoal px-6 text-sm font-bold text-white"
        >
          Get it on Google Play
        </a>
        <div className="flex min-h-12 items-center justify-center rounded-xl border border-border-subtle px-5 text-center text-sm font-semibold text-neutral-500">
          Android app only for now
        </div>
      </div>
    );
  }

  return (
    <div className="mt-7 grid gap-3 sm:grid-cols-[1fr_auto]">
      <a
        href={appHref}
        onClick={() => setOpening(true)}
        className="ep-hover-lift flex h-12 items-center justify-center gap-2 rounded-xl bg-charcoal px-6 text-sm font-bold text-white"
      >
        {opening ? (
          <>
            <span className="h-2.5 w-2.5 animate-ping rounded-full bg-fern-green" />
            Opening Echoproof
          </>
        ) : (
          "Open in Echoproof"
        )}
      </a>
      <a
        href={PLAY_STORE_URL}
        className="flex h-12 items-center justify-center rounded-xl border border-border-subtle px-5 text-sm font-semibold text-neutral-600 transition hover:border-fern-green"
      >
        Google Play
      </a>
    </div>
  );
}
