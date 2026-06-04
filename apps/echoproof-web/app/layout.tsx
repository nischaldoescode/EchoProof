// web root layout
// @params none

import type { Metadata, Viewport } from "next";
import "./globals.css";

// advanced seo covers og, twitter, robots, canonical, verification slots
export const metadata: Metadata = {
  metadataBase: new URL("https://echoproof.online"),
  title: {
    default: "Echoproof — truth, verified by community",
    template: "%s | Echoproof",
  },
  description:
    "Echoproof is a trust-layer social platform where community members support or challenge claims. High-signal echoes get verified on-chain.",
  keywords: [
    "fact checking",
    "community verification",
    "trust",
    "truth",
    "social",
    "decentralized",
    "solana",
    "blockchain",
    "misinformation",
  ],
  authors: [{ name: "Echoproof", url: "https://echoproof.online" }],
  creator: "Echoproof",
  publisher: "Echoproof",
  category: "social",
  classification: "Social Media / Fact Checking",
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "https://echoproof.online",
    siteName: "Echoproof",
    title: "Echoproof — truth, verified by community",
    description:
      "A trust-layer social platform where the community verifies what is true.",
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "Echoproof — truth, verified by community",
        type: "image/png",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: "@echoproof",
    creator: "@echoproof",
    title: "Echoproof — truth, verified by community",
    description:
      "A trust-layer social platform where the community verifies what is true.",
    images: [
      {
        url: "/og-image.png",
        alt: "Echoproof",
      },
    ],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  alternates: {
    canonical: "https://echoproof.online",
  },
  manifest: "/site.webmanifest",
  icons: {
    icon: [
      { url: "/favicon-16x16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
      { url: "/favicon.ico" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180" }],
    shortcut: "/favicon.ico",
  },
};

export const viewport: Viewport = {
  themeColor: "#4caf6e",
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="h-full antialiased" suppressHydrationWarning>
      <body
        className="min-h-full flex flex-col font-josefin"
        suppressHydrationWarning
      >
        {children}
      </body>
    </html>
  );
}
