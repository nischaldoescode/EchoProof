import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  images: {
    domains: [
      "api.dicebear.com",
      // add your supabase project storage domain here
      // format: {project_ref}.supabase.co
    ],
  },
};

export default nextConfig;