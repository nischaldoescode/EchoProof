import type { Metadata } from "next";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The rules governing your use of Echoproof.",
};

export default function TermsPage() {
  return (
    <>
      <Nav />
      <main className="pt-24 pb-20 max-w-2xl mx-auto px-6">
        <h1
          className="text-3xl font-bold tracking-tight text-charcoal mb-2"
          style={{ fontFamily: "'Josefin Sans', sans-serif" }}
        >
          Terms of Service
        </h1>
        <p
          className="text-sm text-neutral-400 mb-12"
          style={{ fontFamily: "'Josefin Sans', sans-serif" }}
        >
          Last updated: May 10, 2026
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
            Questions?{" "}
            <a
              href="mailto:support@echoproof.online"
              className="text-[#4caf6e] hover:underline font-medium"
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
    title: "Acceptance of terms",
    body: "By creating an account or using Echoproof, you agree to these Terms of Service. If you do not agree, do not use the platform. We may update these terms from time to time and will notify you of material changes through the app or by email.",
  },
  {
    title: "Eligibility",
    body: "You must be at least 13 years old to use Echoproof. By registering, you confirm that you meet this requirement. If we learn that a user is under 13, we will terminate their account immediately.",
  },
  {
    title: "Your account",
    body: "You are responsible for maintaining the security of your account credentials. You may not share your account with others or use another person's account without permission. You are responsible for all activity that occurs under your account.",
  },
  {
    title: "Content you post",
    body: "You retain ownership of the content you post on Echoproof. By posting, you grant us a worldwide, non-exclusive, royalty-free licence to display, distribute, and store your content on the platform. You are solely responsible for ensuring your content does not violate any laws or third-party rights.",
  },
  {
    title: "Prohibited conduct",
    body: "You agree not to: post content that is illegal, threatening, harassing, defamatory, or that infringes intellectual property rights; attempt to manipulate trust scores through coordinated inauthentic behaviour; create multiple accounts to circumvent bans or limits; use automated tools to interact with the platform without our written permission; post personal information of others without their consent.",
  },
  {
    title: "Content moderation",
    body: "We use automated systems and human review to moderate content. We reserve the right to remove any content that violates these terms or our community guidelines without prior notice. Repeated violations may result in account suspension or permanent ban. Moderation decisions are logged internally for audit purposes.",
  },
  {
    title: "Identity verification",
    body: "Identity verification is voluntary and processed by our partner Didit. Verified status increases your trust tier and voting weight on the platform. We reserve the right to revoke verified status if we detect fraudulent verification. Your government ID is processed by Didit and is subject to their privacy practices.",
  },
  {
    title: "Subscriptions and payments",
    body: "Pro subscriptions are billed through Google Play. All billing, refunds, and payment disputes are governed by Google Play's policies. We do not store payment card information. Subscriptions automatically renew unless cancelled before the renewal date through your Google Play account settings.",
  },
  {
    title: "On-chain records",
    body: "When an echo reaches verified status, a hash of its content may be written to the Solana blockchain. This record is permanent and cannot be deleted by Echoproof or by you. By posting content on Echoproof, you acknowledge that verified echoes may result in a permanent on-chain record.",
  },
  {
    title: "Intellectual property",
    body: "The Echoproof name, logo, and platform design are our intellectual property. You may not use them without our written permission. We respect the intellectual property rights of others and expect you to do the same.",
  },
  {
    title: "Disclaimers",
    body: "Echoproof is provided on an as-is basis. We make no warranties about the accuracy of content posted by users. The platform does not constitute professional advice of any kind. We are not responsible for decisions made based on content verified by the community.",
  },
  {
    title: "Limitation of liability",
    body: "To the maximum extent permitted by law, Echoproof and its operators shall not be liable for any indirect, incidental, or consequential damages arising from your use of the platform. Our total liability to you for any claim shall not exceed the amount you paid us in the 12 months preceding the claim.",
  },
  {
    title: "Termination",
    body: "You may delete your account at any time through the app settings or by submitting a deletion request at echoproof.online/delete-account. We may suspend or terminate your account at any time for violations of these terms. Upon termination, your right to use the platform ceases immediately.",
  },
  {
    title: "Governing law",
    body: "These terms are governed by the laws of India. Any disputes arising from these terms shall be subject to the exclusive jurisdiction of the courts of Bengaluru, Karnataka.",
  },
];