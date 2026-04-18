import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Echoproof Admin",
  description: "Trust engine control panel",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="bg-gray-50 text-charcoal font-sans antialiased">
        {children}
      </body>
    </html>
  );
}