interface DashboardStatsProps {
  totalUsers: number;
  verifiedUsers: number;
  totalEchoes: number;
  flaggedEchoes: number;
  verifiedEchoes: number;
  pendingDeletions: number;
  proUsers: number;
}

export function DashboardStats({
  totalUsers,
  verifiedUsers,
  totalEchoes,
  flaggedEchoes,
  verifiedEchoes,
  pendingDeletions,
  proUsers,
}: DashboardStatsProps) {
  const stats = [
    { label: "Total users", value: totalUsers, color: "text-[#1A1A1A]" },
    { label: "Trusted users", value: verifiedUsers, color: "text-[#2D7A4A]" },
    { label: "Pro subscribers", value: proUsers, color: "text-[#2D7A4A]" },
    { label: "Total echoes", value: totalEchoes, color: "text-[#1A1A1A]" },
    {
      label: "Verified echoes",
      value: verifiedEchoes,
      color: "text-[#2D7A4A]",
    },
    {
      label: "Flagged / hidden",
      value: flaggedEchoes,
      color: "text-[#B03E28]",
    },
    {
      label: "Deletion requests",
      value: pendingDeletions,
      color: pendingDeletions > 0 ? "text-[#B03E28]" : "text-[#1A1A1A]",
    },
  ];

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
      {stats.map((s) => (
        <div
          key={s.label}
          className="bg-white rounded-xl border border-[#E6E6E6] p-4 transition-all duration-200 hover:shadow-sm hover:-translate-y-0.5"
        >
          <p className="text-xs text-gray-400 mb-1">{s.label}</p>
          <p className={`text-2xl font-semibold ${s.color}`}>
            {s.value.toLocaleString()}
          </p>
        </div>
      ))}
    </div>
  );
}
