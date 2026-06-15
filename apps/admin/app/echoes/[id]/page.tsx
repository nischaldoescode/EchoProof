// echo detail page admin view
// shows full echo content, trust scores, interactions, reports, moderation actions

import { createAdminClient } from "@/lib/supabase/admin";
import { notFound } from "next/navigation";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { adminPath } from "@/lib/routes";
import {
  Badge,
  Card,
  Text,
  Heading,
  Flex,
  Box,
  Button,
} from "@radix-ui/themes";

export const dynamic = "force-dynamic";

interface Props {
  params: Promise<{ id: string }> | { id: string };
}

export default async function EchoDetailPage({ params }: Props) {
  const { id } = await Promise.resolve(params);
  const supabase = createAdminClient();

  const { data: echo, error } = await supabase
    .from("echoes")
    .select(
      `
      *,
      users_public!echoes_user_id_fkey(username, trust_tier, avatar_url),
      echo_reports(id, reason, reporter_id, created_at),
      echo_proofs(id, proof_type, proof_url, description),
      signal_responses(
        id, content, stance, like_count, moderation_status, media_urls, created_at,
        users_public(username)
      )
    `,
    )
    .eq("id", id)
    .single();

  if (error || !echo) return notFound();
  const publicLocked =
    echo.public_verdict && echo.public_verdict !== "open";
  const adminLocked = publicLocked || echo.admin_override_used;

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar title="Echo detail" subtitle="Full content, reports, proofs, and moderation actions" />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6 max-w-4xl w-full mx-auto space-y-6">
      <Heading size="6">Echo detail</Heading>

      {/* main card */}
      <Card>
        <Flex direction="column" gap="4" p="4">
          {/* author */}
          <Flex gap="3" align="center">
            <Box>
              <Text size="2" color="gray">
                Posted by
              </Text>
              <Text size="3" weight="bold">
                @{echo.users_public?.username ?? "unknown"}
              </Text>
            </Box>
            <Badge color={tierColor(echo.users_public?.trust_tier)}>
              {echo.users_public?.trust_tier ?? "unverified"}
            </Badge>
          </Flex>

          {/* content */}
          <Box>
            <Text size="5" weight="bold">
              {echo.title}
            </Text>
            <Text
              size="3"
              color="gray"
              style={{ marginTop: 8, display: "block" }}
            >
              {echo.content}
            </Text>
          </Box>

          {/* scores */}
          <Flex gap="4">
            <Box>
              <Text size="1" color="gray">
                Trust score
              </Text>
              <Text size="4" weight="bold">
                {echo.trust_score}
              </Text>
            </Box>
            <Box>
              <Text size="1" color="gray">
                Confidence
              </Text>
              <Text size="4" weight="bold">
                {echo.confidence_score?.toFixed(0)}%
              </Text>
            </Box>
            <Box>
              <Text size="1" color="gray">
                Support
              </Text>
              <Text size="4" weight="bold" color="green">
                {echo.support_count}
              </Text>
            </Box>
            <Box>
              <Text size="1" color="gray">
                Challenge
              </Text>
              <Text size="4" weight="bold" color="red">
                {echo.challenge_count}
              </Text>
            </Box>
            <Box>
              <Text size="1" color="gray">
                Reports
              </Text>
              <Text size="4" weight="bold">
                {echo.report_score ?? 0}
              </Text>
            </Box>
          </Flex>

          {/* status badge */}
          <Flex align="center" gap="2">
            <Text size="2" color="gray">
              Status:
            </Text>
            <Badge color={statusColor(echo.status)}>{echo.status}</Badge>
          </Flex>
          <Flex align="center" gap="2" wrap="wrap">
            <Text size="2" color="gray">
              Public verdict:
            </Text>
            <Badge color={verdictColor(echo.public_verdict)}>
              {verdictLabel(echo.public_verdict)}
            </Badge>
            <Text size="2" color="gray">
              {echo.context_support_count ?? 0} support ·{" "}
              {echo.context_challenge_count ?? 0} challenge ·{" "}
              {evaluationLabel(echo)}
            </Text>
          </Flex>
        </Flex>
      </Card>

      {/* moderation actions */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Moderation actions
          </Heading>
          {adminLocked && (
            <Text size="2" color="gray" as="p" mb="3">
              {publicLocked
                ? "Public context has already decided this echo, so admin status actions are locked."
                : "The one admin override for this echo has already been used."}
            </Text>
          )}
          <Flex gap="3" wrap="wrap">
            <ModerationButton
              label="Mark verified"
              echoId={id}
              action="verified"
              color="green"
              disabled={adminLocked}
            />
            <ModerationButton
              label="Mark disputed"
              echoId={id}
              action="disputed"
              color="yellow"
              disabled={adminLocked}
            />
            <ModerationButton
              label="Hide echo"
              echoId={id}
              action="hidden"
              color="red"
              disabled={adminLocked}
            />
            <ModerationButton
              label="Reject echo"
              echoId={id}
              action="rejected"
              color="red"
              disabled={adminLocked}
            />
          </Flex>
        </Box>
      </Card>

      {echo.signal_responses?.length > 0 && (
        <Card>
          <Box p="4">
            <Heading size="4" mb="4">
              Public context ({echo.signal_responses.length})
            </Heading>
            <div className="space-y-3">
              {echo.signal_responses.map((r: any) => (
                <div key={r.id} className="rounded-lg border border-gray-200 p-3">
                  <Flex align="center" gap="2" wrap="wrap">
                    <Badge color={r.stance === "support" ? "green" : "red"}>
                      {r.stance}
                    </Badge>
                    <Text size="2" weight="bold">
                      @{r.users_public?.username ?? "unknown"}
                    </Text>
                    <Text size="2" color="gray">
                      {r.like_count ?? 0} likes · {r.moderation_status}
                    </Text>
                  </Flex>
                  <Text size="2" as="p" mt="2">
                    {r.content}
                  </Text>
                  {r.media_urls?.length > 0 && (
                    <Text size="2" color="gray" as="p" mt="2">
                      {r.media_urls.length} media attachment
                      {r.media_urls.length === 1 ? "" : "s"}
                    </Text>
                  )}
                </div>
              ))}
            </div>
          </Box>
        </Card>
      )}

      {/* reports */}
      {echo.echo_reports?.length > 0 && (
        <Card>
          <Box p="4">
            <Heading size="4" mb="4">
              Reports ({echo.echo_reports.length})
            </Heading>
            <div className="space-y-2">
              {echo.echo_reports.map((r: any) => (
                <Flex key={r.id} gap="3" align="center">
                  <Badge color="red">{r.reason}</Badge>
                  <Text size="2" color="gray">
                    {new Date(r.created_at).toLocaleDateString()}
                  </Text>
                </Flex>
              ))}
            </div>
          </Box>
        </Card>
      )}

      {/* proofs */}
      {echo.echo_proofs?.length > 0 && (
        <Card>
          <Box p="4">
            <Heading size="4" mb="4">
              Evidence ({echo.echo_proofs.length})
            </Heading>
            <div className="space-y-3">
              {echo.echo_proofs.map((p: any) => (
                <Flex key={p.id} gap="3" direction="column">
                  <Badge>{p.proof_type}</Badge>
                  {p.description && <Text size="2">{p.description}</Text>}
                  <a
                    href={p.proof_url}
                    target="_blank"
                    className="text-blue-600 text-sm underline"
                  >
                    View proof
                  </a>
                </Flex>
              ))}
            </div>
          </Box>
        </Card>
      )}
        </div>
      </main>
    </div>
  );
}

function tierColor(tier?: string): "gray" | "green" | "blue" | "gold" {
  return (
    ({
      unverified: "gray",
      low: "gray",
      medium: "blue",
      high: "green",
      elite: "gold",
    }[tier ?? "unverified"] as any) ?? "gray"
  );
}

function statusColor(
  status?: string,
): "gray" | "green" | "red" | "yellow" | "orange" | "blue" {
  return (
    ({
      pending_verification: "gray",
      active: "blue",
      verified: "green",
      disputed: "red",
      controversial: "yellow",
      under_review: "orange",
      hidden: "red",
      rejected: "red",
    }[status ?? "active"] as any) ?? "gray"
  );
}

function verdictLabel(verdict?: string | null) {
  return (
    {
      supported: "supported",
      not_supported: "not supported",
      contested: "contested",
      open: "open",
    }[verdict ?? "open"] ?? "open"
  );
}

function verdictColor(
  verdict?: string | null,
): "gray" | "green" | "red" | "yellow" {
  return (
    ({
      supported: "green",
      not_supported: "red",
      contested: "yellow",
      open: "gray",
    }[verdict ?? "open"] as any) ?? "gray"
  );
}

function evaluationLabel(echo: any) {
  if (echo.public_verdict && echo.public_verdict !== "open") return "locked";
  if (!echo.public_context_closes_at) return "7d window";
  const ms = new Date(echo.public_context_closes_at).getTime() - Date.now();
  if (ms <= 0) return "window ended";
  const hours = Math.ceil(ms / 36e5);
  return hours >= 24 ? `${Math.ceil(hours / 24)}d left` : `${hours}h left`;
}

// client component for moderation actions
function ModerationButton({
  label,
  echoId,
  action,
  color,
  disabled,
}: {
  label: string;
  echoId: string;
  action: string;
  color: string;
  disabled?: boolean;
}) {
  return (
    <form action={adminPath(`/api/admin/echo/${echoId}/status`)} method="POST">
      <input type="hidden" name="status" value={action} />
      <Button type="submit" color={color as any} variant="soft" disabled={disabled}>
        {label}
      </Button>
    </form>
  );
}
