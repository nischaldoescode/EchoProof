// echoproof landing page
// storytelling scroll-reveal layout with parallax, horizontal ticker, and scroll animations
// all animation via css — no extra animation libraries needed

import type { Metadata } from "next";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import LandingClient from "@/components/LandingClient";

export const metadata: Metadata = {
  title: "Echoproof — truth, verified by community",
  description:
    "A trust-layer social platform where community members support or challenge claims. High-signal echoes get verified on-chain.",
  alternates: {
    canonical: "https://echoproof.online",
  },
};

export default function Home() {
  return (
    <>
      <Nav />
      <LandingClient />
      <Footer />
    </>
  );
}
