import type { NextConfig } from "next";

function normalizeBasePath(value?: string) {
  const trimmed = value?.trim() ?? "";
  if (!trimmed || trimmed === "/") return undefined;

  const withSlash = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  return withSlash.replace(/\/+$/, "");
}

const adminBasePath = normalizeBasePath(
  process.env.NEXT_PUBLIC_ADMIN_BASE_PATH || process.env.ADMIN_BASE_PATH,
);

const nextConfig: NextConfig = {
  reactStrictMode: true,
  ...(adminBasePath ? { basePath: adminBasePath } : {}),
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "api.dicebear.com",
      },
      {
        protocol: "https",
        hostname: "*.supabase.co",
        pathname: "/storage/v1/object/public/**",
      },
      {
        protocol: "http",
        hostname: "192.168.1.3",
        port: "54321",
        pathname: "/storage/v1/object/public/**",
      },
    ],
  },
};

export default nextConfig;
