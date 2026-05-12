"use client";

import Link from "next/link";
import { useState, useEffect } from "react";

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 20);
    window.addEventListener("scroll", handler);
    return () => window.removeEventListener("scroll", handler);
  }, []);

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled
          ? "bg-white/90 backdrop-blur-md shadow-[0_1px_0_0_#e8e8e8]"
          : "bg-transparent"
      }`}
    >
      <div className="max-w-5xl mx-auto px-6 h-16 flex items-center justify-between">
        {/* logo */}
        <Link href="/" className="flex items-center gap-2.5 group">
          <div className="w-8 h-8 rounded-xl overflow-hidden ring-1 ring-black/5 group-hover:ring-[#4caf6e]/40 transition-all duration-200">
            <img
              src="/logo.png"
              alt="Echoproof"
              width={32}
              height={32}
              className="w-full h-full object-cover"
            />
          </div>
          <span className="font-semibold text-[15px] tracking-tight text-charcoal">
            Echoproof
          </span>
        </Link>

        {/* desktop nav */}
        <div className="hidden md:flex items-center gap-8">
          <Link
            href="/#how-it-works"
            className="text-sm text-neutral-500 hover:text-charcoal transition-colors"
          >
            How it works
          </Link>
          <Link
            href="/#trust"
            className="text-sm text-neutral-500 hover:text-charcoal transition-colors"
          >
            Trust engine
          </Link>
          <span
            className="text-sm bg-charcoal text-white px-4 py-2 rounded-full hover:bg-neutral-800 transition-colors font-medium"
          >
            App coming soon
          </span>
        </div>

        {/* mobile menu button */}
        <button
          className="md:hidden w-8 h-8 flex flex-col items-center justify-center gap-1.5"
          onClick={() => setMenuOpen(!menuOpen)}
          aria-label="Toggle menu"
        >
          <span
            className={`w-5 h-px bg-charcoal transition-all duration-200 ${
              menuOpen ? "rotate-45 translate-y-[3px]" : ""
            }`}
          />
          <span
            className={`w-5 h-px bg-charcoal transition-all duration-200 ${
              menuOpen ? "-rotate-45 -translate-y-[3px]" : ""
            }`}
          />
        </button>
      </div>

      {/* mobile menu */}
      <div
        className={`md:hidden bg-white border-t border-neutral-100 transition-all duration-200 overflow-hidden ${
          menuOpen ? "max-h-64 opacity-100" : "max-h-0 opacity-0"
        }`}
      >
        <div className="px-6 py-4 flex flex-col gap-4">
          <Link
            href="/#how-it-works"
            className="text-sm text-neutral-600"
            onClick={() => setMenuOpen(false)}
          >
            How it works
          </Link>
          <Link
            href="/#trust"
            className="text-sm text-neutral-600"
            onClick={() => setMenuOpen(false)}
          >
            Trust engine
          </Link>
          <span
            className="text-sm bg-charcoal text-white px-4 py-2.5 rounded-full text-center font-medium"
          >
            App coming soon
          </span>
        </div>
      </div>
    </nav>
  );
}
