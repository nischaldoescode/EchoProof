"use client";

import { useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  CheckCircle2,
  EyeOff,
  Flag,
  ShieldCheck,
  Trash2,
} from "lucide-react";
import { adminPath } from "@/lib/routes";

type EchoStatus = "under_review" | "hidden" | "rejected";

interface Report {
  id: string;
  echo_id: string;
  reporter_id: string;
  reason: string;
  description: string | null;
  reporter_weight: number;
  resolved: boolean;
  created_at: string;
  echoes: {
    id: string;
    title: string | null;
    content: string;
    status: string;
    report_score: number;
    trust_score: number;
    user_id: string;
  } | null;
  users_public: {
    username: string;
    trust_tier: string;
  } | null;
}

interface ReportQueueProps {
  reports: Report[];
}

interface ReportGroup {
  echo: NonNullable<Report["echoes"]>;
  reports: Report[];
  totalWeight: number;
  uniqueReporters: number;
  reasonDiversity: number;
  severeReports: number;
}

const severeReasons = new Set(["harassment", "misinformation", "fake_proof"]);

export function ReportQueue({ reports }: ReportQueueProps) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);

  const groups = useMemo(() => {
    const grouped = new Map<string, ReportGroup>();

    for (const report of reports) {
      if (!report.echoes) continue;

      const existing = grouped.get(report.echoes.id);
      if (existing) {
        existing.reports.push(report);
      } else {
        grouped.set(report.echoes.id, {
          echo: report.echoes,
          reports: [report],
          totalWeight: 0,
          uniqueReporters: 0,
          reasonDiversity: 0,
          severeReports: 0,
        });
      }
    }

    return Array.from(grouped.values())
      .map((group) => {
        const reporterIds = new Set(group.reports.map((r) => r.reporter_id));
        const reasons = new Set(group.reports.map((r) => r.reason));
        return {
          ...group,
          totalWeight: group.reports.reduce(
            (sum, report) => sum + report.reporter_weight,
            0,
          ),
          uniqueReporters: reporterIds.size,
          reasonDiversity: reasons.size,
          severeReports: group.reports.filter((r) => severeReasons.has(r.reason))
            .length,
        };
      })
      .sort((a, b) => {
        const scoreA = a.totalWeight + a.uniqueReporters * 2 + a.severeReports;
        const scoreB = b.totalWeight + b.uniqueReporters * 2 + b.severeReports;
        return scoreB - scoreA;
      });
  }, [reports]);

  async function resolveEchoReports(echoId: string) {
    setLoading(`resolve:${echoId}`);
    await fetch(adminPath("/api/admin/reports/resolve"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ echo_id: echoId }),
    });
    router.refresh();
    setLoading(null);
  }

  async function updateEchoStatus(
    echoId: string,
    status: EchoStatus,
    adminNote: string,
    resolveReports: boolean,
  ) {
    setLoading(`${status}:${echoId}`);
    await fetch(adminPath(`/api/admin/echo/${echoId}/status`), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        status,
        admin_note: adminNote,
        admin_verified: status === "rejected" ? false : null,
        resolve_reports: resolveReports,
        notify: true,
      }),
    });
    router.refresh();
    setLoading(null);
  }

  if (groups.length === 0) {
    return (
      <div className="overflow-hidden rounded-2xl border border-border-subtle bg-white p-10 text-center shadow-sm">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-fern-light text-fern-dark">
          <CheckCircle2 size={22} />
        </div>
        <p className="text-sm font-semibold text-charcoal">No unresolved reports</p>
        <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-gray-400">
          When reports arrive, they will be grouped by echo with reporter count,
          trust weight, reason diversity, and a suggested moderation path.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <style jsx global>{`
        @keyframes reportCardIn {
          from {
            opacity: 0;
            transform: translateY(8px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>

      {groups.map((group, index) => (
        <ReportCard
          key={group.echo.id}
          group={group}
          loading={loading}
          index={index}
          onResolve={() => resolveEchoReports(group.echo.id)}
          onReview={() =>
            updateEchoStatus(
              group.echo.id,
              "under_review",
              "Moved to review from the grouped report queue.",
              false,
            )
          }
          onHide={() =>
            updateEchoStatus(
              group.echo.id,
              "hidden",
              "Temporarily hidden after multiple independent reports.",
              false,
            )
          }
          onReject={() =>
            updateEchoStatus(
              group.echo.id,
              "rejected",
              "Removed by admin after report review.",
              true,
            )
          }
        />
      ))}
    </div>
  );
}

function ReportCard({
  group,
  loading,
  index,
  onResolve,
  onReview,
  onHide,
  onReject,
}: {
  group: ReportGroup;
  loading: string | null;
  index: number;
  onResolve: () => void;
  onReview: () => void;
  onHide: () => void;
  onReject: () => void;
}) {
  const recommendation = getRecommendation(group);
  const preview = group.echo.title || group.echo.content.slice(0, 120);
  const busy = loading?.endsWith(group.echo.id) ?? false;

  return (
    <section
      className="rounded-2xl border border-border-subtle bg-white p-4 shadow-sm transition-all duration-300 hover:-translate-y-0.5 hover:shadow-md sm:p-5"
      style={{
        animation: "reportCardIn 240ms ease-out both",
        animationDelay: `${Math.min(index * 35, 280)}ms`,
      }}
    >
      <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
        <div className="min-w-0 flex-1">
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-lg bg-coral-light px-2.5 py-1 text-xs font-semibold text-coral-dark">
              <Flag size={13} />
              {group.reports.length} report{group.reports.length === 1 ? "" : "s"}
            </span>
            <span className="rounded-lg bg-soft-sand px-2.5 py-1 text-xs text-gray-500">
              {group.uniqueReporters} independent reporter
              {group.uniqueReporters === 1 ? "" : "s"}
            </span>
            <span className="rounded-lg bg-soft-sand px-2.5 py-1 text-xs text-gray-500">
              weight {group.totalWeight}
            </span>
            <span className="rounded-lg bg-soft-sand px-2.5 py-1 text-xs capitalize text-gray-500">
              {group.echo.status.replace("_", " ")}
            </span>
          </div>

          <Link
            href={`/echoes/${group.echo.id}`}
            className="block text-sm font-semibold leading-snug text-charcoal transition-colors hover:text-fern-dark"
          >
            {preview}
          </Link>

          <p className="mt-2 line-clamp-2 text-xs leading-relaxed text-gray-500">
            {group.echo.content}
          </p>

          <div className="mt-4 grid gap-2 sm:grid-cols-3">
            <SignalPill label="Reason diversity" value={group.reasonDiversity} />
            <SignalPill label="Severe reports" value={group.severeReports} />
            <SignalPill label="Echo report score" value={group.echo.report_score ?? 0} />
          </div>

          <div className="mt-4 rounded-xl border border-border-subtle bg-soft-sand/70 p-3">
            <div className="mb-2 flex items-center gap-2 text-xs font-semibold text-charcoal">
              <ShieldCheck size={14} className="text-fern-dark" />
              Fairness recommendation
            </div>
            <p className="text-xs leading-relaxed text-gray-500">
              {recommendation}
            </p>
          </div>

          <div className="mt-4 space-y-2">
            {group.reports.slice(0, 3).map((report) => (
              <div
                key={report.id}
                className="rounded-xl border border-border-subtle px-3 py-2"
              >
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className="font-semibold uppercase tracking-wide text-coral-dark">
                    {formatReason(report.reason)}
                  </span>
                  <span className="text-gray-400">
                    by @{report.users_public?.username ?? "unknown"}
                  </span>
                  <span className="text-gray-400">
                    {report.users_public?.trust_tier ?? "unverified"} · weight{" "}
                    {report.reporter_weight}
                  </span>
                </div>
                {report.description && (
                  <p className="mt-1 text-xs italic leading-relaxed text-gray-500">
                    {report.description}
                  </p>
                )}
              </div>
            ))}
          </div>
        </div>

        <div className="grid min-w-full gap-2 sm:grid-cols-2 xl:min-w-[190px] xl:grid-cols-1">
          <ActionButton
            icon={<AlertTriangle size={14} />}
            label="Send to review"
            disabled={busy}
            onClick={onReview}
          />
          <ActionButton
            icon={<EyeOff size={14} />}
            label="Hide publicly"
            disabled={busy}
            onClick={onHide}
          />
          <ActionButton
            danger
            icon={<Trash2 size={14} />}
            label="Reject / remove"
            disabled={busy}
            onClick={onReject}
          />
          <ActionButton
            muted
            icon={<CheckCircle2 size={14} />}
            label="Resolve reports"
            disabled={busy}
            onClick={onResolve}
          />
        </div>
      </div>
    </section>
  );
}

function SignalPill({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl bg-white px-3 py-2 ring-1 ring-border-subtle">
      <p className="text-[11px] text-gray-400">{label}</p>
      <p className="text-sm font-semibold text-charcoal">{value}</p>
    </div>
  );
}

function ActionButton({
  icon,
  label,
  disabled,
  muted,
  danger,
  onClick,
}: {
  icon: ReactNode;
  label: string;
  disabled: boolean;
  muted?: boolean;
  danger?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex items-center justify-center gap-2 rounded-xl px-3 py-2 text-xs font-semibold transition-all disabled:cursor-wait disabled:opacity-50 ${
        danger
          ? "bg-coral-light text-coral-dark hover:bg-sunset-coral hover:text-white"
          : muted
            ? "bg-soft-sand text-gray-600 hover:bg-gray-200"
            : "bg-charcoal text-white hover:-translate-y-0.5 hover:shadow-md"
      }`}
    >
      {icon}
      {disabled ? "Working..." : label}
    </button>
  );
}

function getRecommendation(group: ReportGroup) {
  if (group.uniqueReporters < 2) {
    return "Low confidence. Keep visible unless the content is obviously dangerous, because one report should not decide an echo.";
  }

  if (
    group.uniqueReporters >= 4 &&
    group.totalWeight >= 12 &&
    group.reasonDiversity >= 2
  ) {
    return "Strong signal. Multiple independent reporters and different report reasons make review or temporary hiding reasonable.";
  }

  if (group.severeReports >= 2 && group.uniqueReporters >= 3) {
    return "Potentially harmful. Several reporters chose severe reasons, so move it to review quickly and hide if content is clearly unsafe.";
  }

  return "Moderate signal. Review context before removal; the engine should wait for more reporter diversity before automatic hiding.";
}

function formatReason(reason: string) {
  return reason.replace(/_/g, " ");
}
