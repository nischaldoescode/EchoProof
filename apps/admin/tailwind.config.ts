// admin tailwind config
// @params none

import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // echoproof brand colors matches flutter appcolors exactly
        charcoal:    "#1A1A1A",
        "fern-green": "#4CAF6E",
        "fern-light": "#E8F5EE",
        "fern-dark":  "#2D7A4A",
        "soft-sand":  "#EAE7DF",
        "sunset-coral": "#FF7759",
        "coral-light":  "#FFF0ED",
        "coral-dark":   "#B03E28",
        "border-subtle": "#E6E6E6",
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "sans-serif"],
      },
      borderRadius: {
        DEFAULT: "8px",
        md: "12px",
        lg: "16px",
      },
    },
  },
  plugins: [],
};

export default config;
