// echo detail page — admin view
// shows full echo content, trust scores, interactions, reports, moderation actions

import { createServerClient } from "@/lib/supabase/client";
import { notFound } from "next/navigation";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
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
  params: { id: string };
}

export default async function EchoDetailPage({ params }: Props) {
  const supabase = createServerClient();

  const { data: echo, error } = await supabase
    .from("echoes")
    .select(
      `
      *,
      users_public(username, trust_tier, avatar_url),
      echo_reports(id, reason, reporter_id, created_at),
      echo_proofs(id, proof_type, proof_url, description)
    `,
    )
    .eq("id", params.id)
    .single();

  if (error || !echo) return notFound();

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
        </Flex>
      </Card>

      {/* moderation actions */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Moderation actions
          </Heading>
          <Flex gap="3" wrap="wrap">
            <ModerationButton
              label="Mark verified"
              echoId={params.id}
              action="verified"
              color="green"
            />
            <ModerationButton
              label="Mark disputed"
              echoId={params.id}
              action="disputed"
              color="yellow"
            />
            <ModerationButton
              label="Hide echo"
              echoId={params.id}
              action="hidden"
              color="red"
            />
            <ModerationButton
              label="Reject echo"
              echoId={params.id}
              action="rejected"
              color="red"
            />
          </Flex>
        </Box>
      </Card>

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

// client component for moderation actions
function ModerationButton({
  label,
  echoId,
  action,
  color,
}: {
  label: string;
  echoId: string;
  action: string;
  color: string;
}) {
  return (
    <form action={`/api/admin/echo/${echoId}/status`} method="POST">
      <input type="hidden" name="status" value={action} />
      <Button type="submit" color={color as any} variant="soft">
        {label}
      </Button>
    </form>
  );
}
