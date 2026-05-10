import type { Metadata } from "next";
import { Theme } from "@radix-ui/themes";
import "@radix-ui/themes/styles.css";
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
      <body>
        <Theme
          accentColor="green"
          grayColor="sand"
          radius="medium"
          scaling="95%"
          appearance="light"
        >
          {children}
        </Theme>
      </body>
    </html>
  );
}