import type { Metadata, Viewport } from "next";
import "./globals.css";

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
  ],
  authors: [{ name: "Echoproof" }],
  creator: "Echoproof",
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
        alt: "Echoproof",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Echoproof — truth, verified by community",
    description:
      "A trust-layer social platform where the community verifies what is true.",
    images: ["/og-image.png"],
  },
  robots: {
    index: true,
    follow: true,
  },
  manifest: "/site.webmanifest",
  icons: {
    icon: [
      { url: "/favicon-16x16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180" }],
  },
};

export const viewport: Viewport = {
  themeColor: "#4caf6e",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col font-josefin">{children}</body>
    </html>
  );
}
