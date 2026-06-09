"use client";

// admin deletion request queue component
// @params none

import { useState } from "react";
import { useRouter } from "next/navigation";
import { adminPath } from "@/lib/routes";

interface DeletionRequest {
  id: string;
  email: string;
  reason: string;
  description: string | null;
  status: "pending" | "processed";
  ip: string | null;
  created_at: string;
}

interface DeletionRequestQueueProps {
  requests: DeletionRequest[];
}

export function DeletionRequestQueue({ requests }: DeletionRequestQueueProps) {
  const router = useRouter();
  const [filter, setFilter] = useState<"all" | "pending" | "processed">(
    "pending",
  );
  const [loading, setLoading] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const filtered = requests.filter((r) =>
    filter === "all" ? true : r.status === filter,
  );

  async function markProcessed(requestId: string) {
    setLoading(requestId);
    await fetch(adminPath(`/api/admin/deletion-requests/${requestId}/process`), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ delete_account: false }),
    });
    router.refresh();
    setLoading(null);
  }

  async function deleteAccount(request: DeletionRequest) {
    const confirmed = window.confirm(
      `Schedule account deletion for ${request.email}?\n\nThe user will be signed out and can restore the account for 7 days.`,
    );
    if (!confirmed) return;

    setDeleting(request.id);

    try {
      const res = await fetch(
        adminPath(`/api/admin/deletion-requests/${request.id}/process`),
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ delete_account: true }),
        },
      );

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "Delete failed");
      }

      router.refresh();
    } catch (e) {
      alert(`Deletion failed: ${e}`);
    }

    setDeleting(null);
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        {(["pending", "processed", "all"] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-all duration-200 cursor-pointer hover:scale-95 ${
              filter === f
                ? "bg-[#1A1A1A] text-white border-[#1A1A1A]"
                : "bg-white text-gray-500 border-[#E6E6E6] hover:border-gray-300"
            }`}
          >
            {f === "all" ? "All" : f.charAt(0).toUpperCase() + f.slice(1)}
          </button>
        ))}
        <span className="w-full text-xs text-gray-400 sm:ml-auto sm:w-auto">
          {filtered.filter((r) => r.status === "pending").length} pending
        </span>
      </div>

      {filtered.length === 0 && (
        <div className="bg-white rounded-xl border border-[#E6E6E6] p-10 text-center">
          <p className="text-gray-400 text-sm">No {filter} deletion requests</p>
        </div>
      )}

      <div className="space-y-3">
        {filtered.map((request) => (
          <div
            key={request.id}
            className="admin-soft-card overflow-hidden rounded-xl border border-[#E6E6E6] bg-white transition-all duration-200"
          >
            <div
              className="p-4 cursor-pointer hover:bg-[#F8F7F5] transition-colors"
              onClick={() =>
                setExpandedId(expandedId === request.id ? null : request.id)
              }
            >
              <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span
                      className={`text-xs font-semibold px-2 py-0.5 rounded-full ${
                        request.status === "pending"
                          ? "bg-[#FFF0ED] text-[#B03E28]"
                          : "bg-[#E8F5EE] text-[#2D7A4A]"
                      }`}
                    >
                      {request.status}
                    </span>
                    <span className="text-xs text-gray-400">
                      {new Date(request.created_at).toLocaleDateString(
                        "en-GB",
                        {
                          day: "2-digit",
                          month: "short",
                          year: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        },
                      )}
                    </span>
                  </div>
                  <p className="text-sm font-semibold text-[#1A1A1A]">
                    {request.email}
                  </p>
                  <p className="text-xs text-gray-500 mt-0.5">
                    Reason: {request.reason}
                  </p>
                </div>

                {request.status === "pending" && (
                  <div className="grid w-full flex-shrink-0 grid-cols-1 gap-2 sm:w-auto sm:grid-cols-2">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        deleteAccount(request);
                      }}
                      disabled={deleting === request.id}
                      className="rounded-lg bg-[#FF7759] px-3 py-2 text-xs font-semibold text-white transition-all duration-200 hover:scale-95 hover:bg-[#e05e40] disabled:opacity-40"
                    >
                      {deleting === request.id
                        ? "Scheduling..."
                        : "Schedule deletion"}
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        markProcessed(request.id);
                      }}
                      disabled={loading === request.id}
                      className="rounded-lg bg-[#F8F7F5] px-3 py-2 text-xs text-gray-600 transition-all duration-200 hover:scale-95 hover:bg-gray-200 disabled:opacity-40"
                    >
                      {loading === request.id ? "Saving..." : "Mark processed"}
                    </button>
                  </div>
                )}
              </div>
            </div>

            {/* expanded detail */}
            {expandedId === request.id && (
              <div className="border-t border-[#F0F0F0] px-4 py-3 bg-[#F8F7F5]">
                <div className="space-y-2">
                  {request.description && (
                    <div>
                      <p className="text-xs font-medium text-gray-400">
                        Details
                      </p>
                      <p className="text-xs text-[#1A1A1A] mt-0.5">
                        {request.description}
                      </p>
                    </div>
                  )}
                  {request.ip && (
                    <div>
                      <p className="text-xs font-medium text-gray-400">
                        IP address
                      </p>
                      <p className="text-xs font-mono text-[#1A1A1A] mt-0.5">
                        {request.ip}
                      </p>
                    </div>
                  )}
                  <div className="bg-[#FFF3E0] rounded-lg p-3 mt-2">
                    <p className="text-xs text-[#7A5200] font-medium">
                      Server-side deletion
                    </p>
                    <p className="text-xs text-[#7A5200] mt-0.5">
                      "Schedule deletion" runs through an admin API route with
                      the service role, signs active devices out, starts the
                      7-day recovery window, sends the recovery email, and then
                      marks this request processed.
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
