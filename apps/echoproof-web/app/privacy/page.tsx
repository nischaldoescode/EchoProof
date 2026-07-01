// web privacy page
// @params none

import type { Metadata } from "next";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Echoproof handles your data.",
};

export default function PrivacyPage() {
  return (
    <>
      <Nav />
      <main className="pt-24 pb-20 max-w-2xl mx-auto px-6">
        <h1
          className="text-3xl font-bold tracking-tight text-charcoal mb-2"
          style={{ fontFamily: "'Josefin Sans', sans-serif" }}
        >
          Privacy Policy
        </h1>
        <p
          className="text-sm text-neutral-400 mb-12"
          style={{ fontFamily: "'Josefin Sans', sans-serif" }}
        >
          Last updated: July 1, 2026
        </p>

        {sections.map((s) => (
          <section key={s.title} className="mb-10">
            <h2
              className="text-lg font-semibold text-charcoal mb-3"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              {s.title}
            </h2>
            <p
              className="text-sm text-neutral-600 leading-7"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              {s.body}
            </p>
          </section>
        ))}

        <div className="mt-16 p-5 rounded-xl bg-neutral-50 border border-neutral-100">
          <p
            className="text-sm text-neutral-500"
            style={{ fontFamily: "'Josefin Sans', sans-serif" }}
          >
            Questions about this policy?{" "}
            <a
              href="mailto:support@echoproof.online"
              className="text-fern-green hover:underline font-medium"
            >
              support@echoproof.online
            </a>
          </p>
        </div>
      </main>
      <Footer />
    </>
  );
}

const sections = [
  {
    title: "Who we are",
    body: "Echoproof is a trust-layer social platform where community members verify claims and opinions. We are committed to handling your data with care and transparency.",
  },
  {
    title: "What we collect",
    body: "We collect your email address, username, and age or date of birth when you create an account. If you choose to verify your identity, a government-issued ID and liveness selfie are processed by Didit, our identity verification partner, and we receive only a verification status, not the raw documents. We also collect your echoes, replies, support and challenge context, reports, attachments you choose to upload, and device tokens for push notifications.",
  },
  {
    title: "What we do not collect",
    body: "We do not collect your real name unless you provide it. We do not sell your personal data to any third party. We do not share your data except as described in this policy. We do not read your notifications, contacts, or any data outside the Echoproof app.",
  },
  {
    title: "How we use your data",
    body: "Your email is used for account authentication and important notices. Your username is your public identity and may be used to review echo reports, abuse reports, appeals, and moderation history for the correct account. Your age is used for eligibility, safety, and moderation context and is not displayed publicly. Your public echoes and interactions are visible to users by design.",
  },
  {
    title: "Identity verification",
    body: "If you choose to verify your identity, the process is handled by Didit (didit.me), a third-party identity verification service. Didit processes your government ID and liveness selfie. We receive only a verification status (verified or not verified). Your raw ID documents are stored by Didit according to their retention policy and are not stored on Echoproof servers.",
  },
  {
    title: "Push notifications",
    body: "We use Firebase Cloud Messaging to send you notifications. Your device token is stored securely in our database and is only used to deliver notifications to your device. You can disable notifications at any time from your device settings.",
  },
  {
    title: "Security and encryption",
    body: "We protect data in transit with encryption and store data using database and storage security controls, including encryption at rest where provided by our infrastructure. Secure room content is encrypted before storage. Public echoes, public context, and public blockchain hashes remain public by design.",
  },
  {
    title: "Diagnostics and crash reports",
    body: "We use Sentry only for error tracking and reliability. For example, if the app crashes during sign in, Sentry may receive the app version, device model, operating system version, screen name, and technical stack trace needed to fix the issue. We do not use Sentry to sell data, show ads, read private messages, collect private room content, or capture screenshots by default. We value transparency and user privacy above all.",
  },
  {
    title: "Data retention",
    body: "Your account data is retained as long as your account exists. If you request deletion, your account enters a 7-day recovery window before permanent removal. Some records may be retained longer when required by law, abuse prevention, billing, or public blockchain records that Echoproof cannot remove.",
  },
  {
    title: "Your rights",
    body: "You have the right to access the data we hold about you, request a correction of inaccurate data, request deletion of your account and associated personal data, and withdraw consent at any time. To exercise any of these rights, contact us at support@echoproof.online.",
  },
  {
    title: "Internal operations",
    body: "Echoproof staff may access account data as necessary to provide support, investigate abuse reports, enforce these terms, or comply with legal obligations. Access is logged and restricted to authorised personnel only. We do not access your private messages or sensitive personal information except as required to investigate specific reports of abuse.",
  },

  {
    title: "Cookies",
    body: "The Echoproof mobile app does not use cookies. Our website (echoproof.online) may use minimal, strictly necessary cookies for security purposes only. We do not use tracking or advertising cookies.",
  },
  {
    title: "Changes to this policy",
    body: "We may update this privacy policy from time to time. We will notify you of significant changes via email or an in-app notification. Continued use of Echoproof after changes constitutes acceptance of the updated policy.",
  },
];
