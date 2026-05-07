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

  // rewrites (/@username → /user/username)
  async rewrites() {
    return [
      {
        source: '/@:username',
        destination: '/user/:username',
      },
    ];
  },
};

export default nextConfig;