"use client";

import {
  LineChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer,
} from "recharts";
import { format, parseISO, subDays, startOfDay } from "date-fns";

interface ActivityChartProps {
  echoes: { created_at: string; status: string }[];
}

export function ActivityChart({ echoes }: ActivityChartProps) {
  // group echoes by day for the last 14 days
  const days = Array.from({ length: 14 }, (_, i) => {
    const date = startOfDay(subDays(new Date(), 13 - i));
    return {
      date: format(date, "MMM d"),
      total: 0,
      verified: 0,
    };
  });

  echoes.forEach(echo => {
    const date     = format(startOfDay(parseISO(echo.created_at)), "MMM d");
    const dayEntry = days.find(d => d.date === date);
    if (dayEntry) {
      dayEntry.total++;
      if (echo.status === "verified") dayEntry.verified++;
    }
  });

  return (
    <div className="admin-soft-card bg-white rounded-xl border border-border-subtle p-4 sm:p-5">
      <p className="text-sm font-medium text-charcoal mb-4">Echo activity — last 14 days</p>
      <ResponsiveContainer width="100%" height={200}>
        <LineChart data={days} margin={{ top: 0, right: 0, bottom: 0, left: -20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#E6E6E6" />
          <XAxis
            dataKey="date"
            tick={{ fontSize: 11, fill: "#9A9A9A" }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 11, fill: "#9A9A9A" }}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip
            contentStyle={{
              background: "#fff",
              border: "1px solid #E6E6E6",
              borderRadius: 8,
              fontSize: 12,
            }}
          />
          <Line
            type="monotone"
            dataKey="total"
            stroke="#1A1A1A"
            strokeWidth={1.5}
            dot={false}
            name="Total"
          />
          <Line
            type="monotone"
            dataKey="verified"
            stroke="#4CAF6E"
            strokeWidth={1.5}
            dot={false}
            name="Verified"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
