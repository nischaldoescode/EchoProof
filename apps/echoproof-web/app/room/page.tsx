"use client";

import { useEffect, useMemo, useState } from "react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

export default function RoomInvitePage() {
  const [code, setCode] = useState("");
  const [key, setKey] = useState("");

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
    setCode((params.get("code") || fragment.get("code") || "").toUpperCase());
    setKey(params.get("key") || fragment.get("key") || "");
  }, []);

  const appLink = useMemo(() => {
    const params = new URLSearchParams();
    if (code) params.set("code", code);
    if (key) params.set("key", key);
    return `echoproof://room/join?${params.toString()}`;
  }, [code, key]);

  return (
    <>
      <Nav />
      <main className="min-h-screen bg-white px-6 py-20 text-charcoal">
        <section className="mx-auto grid max-w-5xl gap-8 md:grid-cols-[1.05fr_0.95fr] md:items-center">
          <div className="ep-page-enter">
            <p className="mb-4 inline-flex rounded-full border border-fern-green/25 bg-fern-light px-4 py-2 text-sm font-semibold text-fern-dark">
              EchoProof secure room
            </p>
            <h1 className="max-w-xl text-5xl font-bold leading-[0.95] tracking-normal md:text-6xl">
              Join room. Enjoy encrypted chat.
            </h1>
            <p className="mt-5 max-w-xl text-lg leading-7 text-neutral-600">
              Open this invite in the EchoProof app to join a private room.
              Messages are encrypted on device, signed per message, and removed
              automatically after the room timer.
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <a
                href={appLink}
                className="rounded-full bg-charcoal px-6 py-3 text-center font-semibold text-white transition hover:bg-neutral-800"
              >
                Open EchoProof
              </a>
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
                {code || "PRIVATE"}
              </p>
              <div className="mt-8 rounded-2xl border border-white/10 bg-white/[0.08] p-4">
                <p className="text-sm font-semibold text-fern-green">
                  Secret key travels in the invite fragment.
                </p>
                <p className="mt-2 text-sm leading-6 text-white/68">
                  EchoProof does not store the room key. If this device does
                  not receive the key, old messages cannot be decrypted.
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
