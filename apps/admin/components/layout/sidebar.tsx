"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import type { LucideIcon } from "lucide-react";
import {
  BadgeDollarSign,
  Flag,
  LayoutDashboard,
  LogOut,
  MessageSquareText,
  ShieldCheck,
  Trash2,
  Users,
} from "lucide-react";
import { adminPath } from "@/lib/routes";

const nav: Array<{
  href: string;
  label: string;
  shortLabel?: string;
  Icon: LucideIcon;
}> = [
  { href: "/", label: "Dashboard", Icon: LayoutDashboard },
  { href: "/echoes", label: "Echoes", Icon: MessageSquareText },
  { href: "/users", label: "Users", Icon: Users },
  { href: "/reports", label: "Reports", Icon: Flag },
  {
    href: "/subscription",
    label: "Subscriptions",
    shortLabel: "Subs",
    Icon: BadgeDollarSign,
  },
  {
    href: "/deletion-requests",
    label: "Deletion requests",
    shortLabel: "Delete",
    Icon: Trash2,
  },
  {
    href: "/trust-engine",
    label: "Trust engine",
    shortLabel: "Trust",
    Icon: ShieldCheck,
  },
];

export function Sidebar() {
  const pathname = usePathname();
  const router = useRouter();

  async function handleSignOut() {
    const supabase = createBrowserClient();
    await supabase.auth.signOut();
    router.push(adminPath("/login"));
  }

  return (
    <>
      <aside className="w-56 min-h-screen bg-[#1A1A1A] flex-col px-4 py-6 hidden md:flex flex-shrink-0">
        <div className="flex items-center gap-2.5 mb-8 px-2">
          <BrandMark />
          <div>
            <p className="text-white text-xs font-semibold leading-none">
              Echoproof
            </p>
            <p className="text-gray-500 text-xs leading-none mt-0.5">Admin</p>
          </div>
        </div>

        <nav className="flex-1 space-y-0.5">
          {nav.map((item) => {
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm transition-all duration-200 cursor-pointer ${
                  active
                    ? "bg-white/10 text-white font-medium translate-x-0.5"
                    : "text-gray-400 hover:text-white hover:bg-white/5 hover:translate-x-0.5"
                }`}
              >
                <item.Icon size={15} strokeWidth={2} />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <button
          onClick={handleSignOut}
          className="flex items-center gap-2.5 px-3 py-2 rounded-lg text-gray-400 hover:text-white hover:bg-white/5 text-sm transition-all duration-200 cursor-pointer hover:translate-x-0.5"
        >
          <LogOut size={15} strokeWidth={2} />
          Sign out
        </button>
      </aside>

      <nav className="md:hidden fixed inset-x-3 bottom-[calc(0.75rem+env(safe-area-inset-bottom))] z-40 rounded-2xl border border-white/10 bg-[#1A1A1A]/95 px-2 py-2 shadow-2xl backdrop-blur">
        <div className="flex items-center gap-1 overflow-x-auto">
          {nav.map((item) => {
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`min-w-[64px] rounded-xl px-2 py-2 text-center text-[10px] transition-all ${
                  active
                    ? "bg-white/10 text-white"
                    : "text-gray-400 hover:bg-white/5 hover:text-white"
                }`}
                aria-label={item.label}
              >
                <item.Icon className="mx-auto" size={15} strokeWidth={2} />
                <span className="mt-1 block truncate">
                  {item.shortLabel ?? item.label}
                </span>
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}

function BrandMark() {
  return (
    <div className="w-7 h-7 rounded-lg bg-fern-light flex items-center justify-center flex-shrink-0">
      <svg width="14" height="14" viewBox="0 0 20 20" fill="none">
        <circle cx="10" cy="10" r="2" fill="#4CAF6E" />
        <circle
          cx="10"
          cy="10"
          r="5"
          stroke="#4CAF6E"
          strokeWidth="1.2"
          fill="none"
        />
        <circle
          cx="10"
          cy="10"
          r="8"
          stroke="#4CAF6E"
          strokeWidth="0.8"
          fill="none"
          opacity="0.5"
        />
      </svg>
    </div>
  );
}

function isActive(pathname: string | null, href: string) {
  if (!pathname) return false;
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}
