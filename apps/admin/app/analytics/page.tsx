import { BarChart3, UsersRound, Activity, MousePointer2 } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { getFirebaseAnalyticsDashboard } from "@/lib/firebase-analytics";

export const dynamic = "force-dynamic";

export default async function AnalyticsPage() {
  const analytics = await getFirebaseAnalyticsDashboard();

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex min-w-0 flex-1 flex-col">
        <Topbar title="Analytics" subtitle="Firebase Analytics, last 30 days" />
        <div className="admin-stagger space-y-6 p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6">
          {!analytics.configured ? (
            <section className="border border-amber-200 bg-amber-50 p-5 text-sm text-amber-950">
              Firebase Analytics is not connected. Configure the Analytics property ID and service-account JSON as server environment variables; do not add service-account files to this repository.
            </section>
          ) : analytics.error ? (
            <section className="border border-red-200 bg-red-50 p-5 text-sm text-red-900">
              {analytics.error}
            </section>
          ) : (
            <>
              <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <Metric icon={UsersRound} label="Active users" value={analytics.overview.activeUsers} />
                <Metric icon={UsersRound} label="New users" value={analytics.overview.newUsers} />
                <Metric icon={Activity} label="Sessions" value={analytics.overview.sessions} />
                <Metric icon={MousePointer2} label="Tracked events" value={analytics.overview.events} />
              </section>
              <section className="grid gap-6 xl:grid-cols-[1.2fr_0.8fr]">
                <div className="border border-gray-200 bg-white p-5">
                  <div className="mb-4 flex items-center gap-2">
                    <BarChart3 size={17} className="text-emerald-700" />
                    <h2 className="text-sm font-semibold text-gray-950">Daily activity</h2>
                  </div>
                  <div className="space-y-2">
                    {analytics.daily.map((day) => (
                      <div key={day.date} className="grid grid-cols-[86px_1fr_64px] items-center gap-3 text-xs">
                        <span className="text-gray-500">{day.date}</span>
                        <div className="h-2 overflow-hidden bg-gray-100">
                          <div
                            className="h-full bg-emerald-600"
                            style={{
                              width: `${Math.max(3, Math.min(100, (day.activeUsers / Math.max(...analytics.daily.map((item) => item.activeUsers), 1)) * 100))}%`,
                            }}
                          />
                        </div>
                        <span className="text-right font-medium text-gray-800">{day.activeUsers}</span>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="border border-gray-200 bg-white p-5">
                  <h2 className="mb-4 text-sm font-semibold text-gray-950">Most-used actions</h2>
                  <div className="divide-y divide-gray-100">
                    {analytics.topEvents.map((event) => (
                      <div key={event.name} className="flex items-center justify-between gap-3 py-3 text-sm">
                        <div className="min-w-0">
                          <p className="truncate font-medium text-gray-900">{event.name}</p>
                          <p className="text-xs text-gray-500">{event.users} users</p>
                        </div>
                        <span className="font-semibold text-gray-800">{event.count}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </section>
            </>
          )}
        </div>
      </main>
    </div>
  );
}

function Metric({
  icon: Icon,
  label,
  value,
}: {
  icon: LucideIcon;
  label: string;
  value: number;
}) {
  return (
    <div className="border border-gray-200 bg-white p-4">
      <Icon size={17} className="mb-4 text-emerald-700" />
      <p className="text-2xl font-semibold text-gray-950">{value.toLocaleString()}</p>
      <p className="mt-1 text-xs text-gray-500">{label}</p>
    </div>
  );
}
