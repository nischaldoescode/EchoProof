import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // image config
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "*.supabase.co",
      },
    ],
  },

  // Rewrites keep shared handles friendly while the page also normalizes params.
  async rewrites() {
    return [
      {
        source: "/@:username",
        destination: "/user/:username",
      },
      {
        source: "/user/@:username",
        destination: "/user/:username",
      },
    ];
  },
};

export default nextConfig;
