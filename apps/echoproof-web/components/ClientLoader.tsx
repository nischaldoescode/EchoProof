"use client";

// client-only wrapper for the page loader
// ssr: false dynamic imports must live in client components in next.js app router

import dynamic from "next/dynamic";

const PageLoader = dynamic(() => import("@/components/PageLoader"), {
  ssr: false,
});

export default function ClientLoader() {
  return <PageLoader />;
}