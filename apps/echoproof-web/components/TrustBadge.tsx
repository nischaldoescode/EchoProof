// web trust badge component
// @params none

interface TrustBadgeProps {
  tier: string;
  size?: "sm" | "md";
}

const tierConfig: Record<string, { label: string; color: string; bg: string }> = {
  elite:      { label: "Elite",      color: "#2d7544", bg: "#d4f0e2" },
  high:       { label: "High",       color: "#2d7544", bg: "#d4f0e2" },
  medium:     { label: "Medium",     color: "#6b7280", bg: "#f3f4f6" },
  low:        { label: "Low",        color: "#9ca3af", bg: "#f9fafb" },
  unverified: { label: "Unverified", color: "#9ca3af", bg: "#f9fafb" },
};

export default function TrustBadge({ tier, size = "sm" }: TrustBadgeProps) {
  const config = tierConfig[tier] ?? tierConfig.unverified;
  const px = size === "sm" ? "px-1.5 py-0.5" : "px-2.5 py-1";
  const fs = size === "sm" ? "text-[10px]" : "text-xs";

  return (
    <span
      className={`${px} ${fs} font-semibold rounded tracking-wide`}
      style={{ color: config.color, backgroundColor: config.bg }}
    >
      {config.label}
    </span>
  );
}