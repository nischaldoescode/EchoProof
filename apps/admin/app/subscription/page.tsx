// subscriptions management page
// admin can: grant/revoke subscriptions, change pricing, see all subscribers

import { createAdminClient } from "@/lib/supabase/admin";
import {
  Heading,
  Card,
  Table,
  Badge,
  Button,
  Box,
  Text,
  Flex,
} from "@radix-ui/themes";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { adminPath } from "@/lib/routes";

export const dynamic = "force-dynamic";

export default async function SubscriptionsPage() {
  const supabase = createAdminClient();

  const { data: subscribers } = await supabase
    .from("subscriptions")
    .select(
      `
    *,
    users_public!inner(username, trust_tier, is_pro, pro_plan, pro_expires_at)
  `,
    )
    .order("created_at", { ascending: false });

  // Also fetch identity-verified users for context.
  const { data: verifiedUsers } = await supabase
    .from("users_private")
    .select("id, is_identity_verified")
    .eq("is_identity_verified", true);

  const verifiedIds = new Set((verifiedUsers ?? []).map((u) => u.id));

  const { data: pricing } = await supabase
    .from("subscription_pricing")
    .select("*")
    .single();

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title="Subscriptions"
          subtitle="Manual grants, revokes, and pricing controls"
        />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6 space-y-6">
      <Heading size="6">Subscriptions</Heading>

      {/* pricing controls */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Pricing
          </Heading>
          <form action={adminPath("/api/admin/subscription/pricing")} method="POST">
            <Flex gap="4" align="end" wrap="wrap">
              <Box>
                <Text size="2" color="gray">
                  Monthly price (USD)
                </Text>
                <input
                  name="monthly_usd"
                  type="number"
                  step="0.01"
                  defaultValue={pricing?.monthly_usd ?? 4.99}
                  className="border rounded p-2 w-32 mt-1"
                />
              </Box>
              <Box>
                <Text size="2" color="gray">
                  New user discount (%)
                </Text>
                <input
                  name="new_user_discount_pct"
                  type="number"
                  defaultValue={pricing?.new_user_discount_pct ?? 30}
                  className="border rounded p-2 w-24 mt-1"
                />
              </Box>
              <Box>
                <Text size="2" color="gray">
                  Yearly price (USD)
                </Text>
                <input
                  name="yearly_usd"
                  type="number"
                  step="0.01"
                  defaultValue={pricing?.yearly_usd ?? 39.99}
                  className="border rounded p-2 w-32 mt-1"
                />
              </Box>
              <Box>
                <Text size="2" color="gray">
                  Free trial days
                </Text>
                <input
                  name="trial_days"
                  type="number"
                  defaultValue={pricing?.trial_days ?? 7}
                  className="border rounded p-2 w-24 mt-1"
                />
              </Box>
              <Button type="submit" color="green">
                Save pricing
              </Button>
            </Flex>
          </form>
        </Box>
      </Card>

      {/* grant subscription to any user */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Grant subscription manually
          </Heading>
          <form action={adminPath("/api/admin/subscription/grant")} method="POST">
            <Flex gap="3" align="end" wrap="wrap" className="w-full">
              <Box className="w-full sm:w-auto">
                <Text size="2" color="gray">
                  Username
                </Text>
                <input
                  name="username"
                  placeholder="@username"
                  className="border rounded p-2 w-full sm:w-48 mt-1"
                />
              </Box>
              <Box className="w-[calc(50%-6px)] sm:w-auto">
                <Text size="2" color="gray">
                  Plan
                </Text>
                <select
                  name="plan_type"
                  defaultValue="pro_monthly"
                  className="border rounded p-2 w-full sm:w-40 mt-1 bg-white"
                >
                  <option value="pro_monthly">Pro monthly</option>
                  <option value="pro_yearly">Pro yearly</option>
                </select>
              </Box>
              <Box className="w-[calc(50%-6px)] sm:w-auto">
                <Text size="2" color="gray">
                  Duration (days)
                </Text>
                <input
                  name="days"
                  type="number"
                  min={1}
                  max={3650}
                  defaultValue={30}
                  className="border rounded p-2 w-full sm:w-24 mt-1"
                />
              </Box>
              <Box className="w-full sm:w-auto">
                <Text size="2" color="gray">
                  Purchase history
                </Text>
                <select
                  name="purchase_history_mode"
                  defaultValue="none"
                  className="border rounded p-2 w-full sm:w-64 mt-1 bg-white"
                >
                  <option value="none">Do not generate</option>
                  <option value="active">Generate active mock order</option>
                  <option value="acknowledged">
                    Generate acknowledged mock order
                  </option>
                </select>
              </Box>
              <Button type="submit" color="green" className="w-full sm:w-auto">
                Grant
              </Button>
            </Flex>
            <Text size="1" color="gray" mt="3" as="p">
              Mock history is for admin-only manual grants and uses the same
              expiry as the granted subscription. Real Google Play purchases
              should still come through server validation.
            </Text>
          </form>
        </Box>
      </Card>

      {/* subscriber list */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Subscribers ({subscribers?.length ?? 0})
          </Heading>
          <div className="overflow-x-auto">
          <Table.Root className="min-w-[720px]">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>User</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Plan</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Status</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Started</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Expires</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Actions</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {(subscribers ?? []).map((sub: any) => (
                <Table.Row key={sub.id}>
                  <Table.Cell>
                    <div>
                      <p>@{sub.users_public?.username ?? "—"}</p>
                      {verifiedIds.has(sub.user_id) && (
                        <p
                          style={{
                            fontSize: 10,
                            color: "#4CAF6E",
                            fontWeight: 600,
                          }}
                        >
                          ID verified ✓
                        </p>
                      )}
                    </div>
                  </Table.Cell>
                  <Table.Cell>
                    <Badge color="purple">{sub.plan}</Badge>
                  </Table.Cell>
                  <Table.Cell>
                    <Badge color={sub.status === "active" ? "green" : "gray"}>
                      {sub.status}
                    </Badge>
                  </Table.Cell>
                  <Table.Cell>
                    {new Date(sub.created_at).toLocaleDateString()}
                  </Table.Cell>
                  <Table.Cell>
                    {sub.expires_at
                      ? new Date(sub.expires_at).toLocaleDateString()
                      : "—"}
                  </Table.Cell>
                  <Table.Cell>
                    <form
                      action={adminPath("/api/admin/subscription/revoke")}
                      method="POST"
                    >
                      <input
                        type="hidden"
                        name="subscription_id"
                        value={sub.id}
                      />
                      <Button type="submit" color="red" variant="soft" size="1">
                        Revoke
                      </Button>
                    </form>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table.Root>
          </div>
        </Box>
      </Card>
        </div>
      </main>
    </div>
  );
}
