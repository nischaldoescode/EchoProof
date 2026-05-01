"use client";

import { useState } from "react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

const reasons = [
  "I no longer use Echoproof",
  "I have privacy concerns",
  "The app is not working correctly",
  "I found a better alternative",
  "I created a duplicate account",
  "Other",
];

// in-memory set to prevent duplicate submissions in the same session
// server-side email dedup is in the API route
const submittedEmails = new Set<string>();

export default function DeleteAccountPage() {
  const [email,       setEmail]       = useState("");
  const [reason,      setReason]      = useState("");
  const [description, setDescription] = useState("");
  const [loading,     setLoading]     = useState(false);
  const [done,        setDone]        = useState(false);
  const [error,       setError]       = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    if (!email || !reason) {
      setError("Please fill in all required fields.");
      return;
    }

    // client-side dedup — prevents double-submit
    const normalizedEmail = email.trim().toLowerCase();
    if (submittedEmails.has(normalizedEmail)) {
      setError("A deletion request for this email was already submitted in this session.");
      return;
    }

    setLoading(true);

    try {
      const res = await fetch("/api/delete-request", {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email:       normalizedEmail,
          reason,
          description: description.trim(),
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Something went wrong. Please try again.");
        setLoading(false);
        return;
      }

      submittedEmails.add(normalizedEmail);
      setDone(true);
    } catch {
      setError("Network error. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <Nav />
      <main className="pt-24 pb-20 max-w-lg mx-auto px-6">
        {done ? (
          <div className="text-center py-16">
            <div
              className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-6"
              style={{ background: "#D4F0E2" }}
            >
              <svg width="28" height="28" fill="none" viewBox="0 0 24 24">
                <path
                  d="M5 13l4 4L19 7"
                  stroke="#4caf6e"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
            </div>
            <h2
              className="text-2xl font-bold text-charcoal mb-3"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              Request received
            </h2>
            <p
              className="text-sm text-neutral-500 leading-6"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              We have received your account deletion request. We will process it
              within 30 days and send a confirmation to{" "}
              <strong>{email}</strong>.
            </p>
          </div>
        ) : (
          <>
            <h1
              className="text-3xl font-bold tracking-tight text-charcoal mb-2"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              Delete your account
            </h1>
            <p
              className="text-sm text-neutral-400 mb-10 leading-6"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              We are sorry to see you go. Fill out the form below and we will
              process your deletion request within 30 days. You will receive a
              confirmation at your email once complete.
            </p>

            <form onSubmit={handleSubmit} className="space-y-5">
              {/* email */}
              <div>
                <label
                  className="block text-sm font-medium text-neutral-700 mb-1.5"
                  style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                >
                  Email address <span className="text-red-400">*</span>
                </label>
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="the email on your Echoproof account"
                  className="w-full px-4 py-3 text-sm rounded-xl border border-neutral-200 bg-neutral-50 focus:outline-none focus:ring-2 focus:ring-[#4caf6e]/30 focus:border-[#4caf6e] transition-all"
                  style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                />
              </div>

              {/* reason */}
              <div>
                <label
                  className="block text-sm font-medium text-neutral-700 mb-1.5"
                  style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                >
                  Reason <span className="text-red-400">*</span>
                </label>
                <select
                  required
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  className="w-full px-4 py-3 text-sm rounded-xl border border-neutral-200 bg-neutral-50 focus:outline-none focus:ring-2 focus:ring-[#4caf6e]/30 focus:border-[#4caf6e] transition-all appearance-none"
                  style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                >
                  <option value="">Select a reason</option>
                  {reasons.map((r) => (
                    <option key={r} value={r}>{r}</option>
                  ))}
                </select>
              </div>

              {/* description */}
              <div>
                <label
                  className="block text-sm font-medium text-neutral-700 mb-1.5"
                  style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                >
                  Additional details{" "}
                  <span className="text-neutral-400 font-normal">(optional)</span>
                </label>
                <textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  rows={4}
                  maxLength={500}
                  placeholder="Is there anything we could have done better?"
                  className="w-full px-4 py-3 text-sm rounded-xl border border-neutral-200 bg-neutral-50 focus:outline-none focus:ring-2 focus:ring-[#4caf6e]/30 focus:border-[#4caf6e] transition-all resize-none"
                  style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                />
                <p className="text-xs text-neutral-400 mt-1 text-right">
                  {description.length}/500
                </p>
              </div>

              {error && (
                <div className="flex items-start gap-2 p-3 rounded-xl bg-red-50 border border-red-100">
                  <svg
                    className="w-4 h-4 text-red-400 mt-0.5 shrink-0"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                  <p
                    className="text-sm text-red-600"
                    style={{ fontFamily: "'Josefin Sans', sans-serif" }}
                  >
                    {error}
                  </p>
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3.5 rounded-xl text-sm font-semibold text-white bg-charcoal hover:bg-neutral-800 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                style={{ fontFamily: "'Josefin Sans', sans-serif" }}
              >
                {loading ? (
                  <span className="flex items-center justify-center gap-2">
                    <svg className="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                      <circle
                        className="opacity-25"
                        cx="12" cy="12" r="10"
                        stroke="currentColor" strokeWidth="4"
                      />
                      <path
                        className="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8v8z"
                      />
                    </svg>
                    Submitting...
                  </span>
                ) : (
                  "Submit deletion request"
                )}
              </button>
            </form>

            <p
              className="mt-8 text-xs text-neutral-400 text-center leading-5"
              style={{ fontFamily: "'Josefin Sans', sans-serif" }}
            >
              This action is permanent. All your echoes, interactions, and
              account data will be deleted within 30 days of your request.
            </p>
          </>
        )}
      </main>
      <Footer />
    </>
  );
}