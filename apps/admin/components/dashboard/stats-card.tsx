interface DashboardStatsProps {
  totalUsers: number;
  verifiedUsers: number;
  totalEchoes: number;
  flaggedEchoes: number;
  verifiedEchoes: number;
}

export function DashboardStats({
  totalUsers, verifiedUsers, totalEchoes, flaggedEchoes, verifiedEchoes,
}: DashboardStatsProps) {
  const stats = [
    { label: "Total users",       value: totalUsers,    color: "text-charcoal" },
    { label: "Trusted users",     value: verifiedUsers, color: "text-fern-dark" },
    { label: "Total echoes",      value: totalEchoes,   color: "text-charcoal" },
    { label: "Verified echoes",   value: verifiedEchoes, color: "text-fern-dark" },
    { label: "Flagged / hidden",  value: flaggedEchoes, color: "text-coral-dark" },
  ];

  return (
    <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
      {stats.map(s => (
        <div
          key={s.label}
          className="bg-white rounded-xl border border-border-subtle p-4"
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