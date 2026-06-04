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
import { SubscriptionGrantForm } from "@/components/subscriptions/subscription-grant-form";

export const dynamic = "force-dynamic";

type SubscriptionRow = {
  id: string;
  user_id: string;
  plan: string;
  status: string;
  expires_at: string | null;
  created_at: string;
};

type SubscriptionUser = {
  id: string;
  username: string | null;
  display_name?: string | null;
  trust_tier?: string | null;
  is_pro?: boolean | null;
  pro_plan?: string | null;
  pro_expires_at?: string | null;
  onboarding_complete?: boolean | null;
  created_at?: string | null;
};

type DisplaySubscriptionRow = SubscriptionRow & {
  users_public: SubscriptionUser | null;
  profileOnly?: boolean;
};

export default async function SubscriptionsPage() {
  const supabase = createAdminClient();

  const { data: subscriptionRows, error: subscribersError } = await supabase
    .from("subscriptions")
    .select("id, user_id, plan, status, expires_at, created_at")
    .order("created_at", { ascending: false });

  const subscriptions = (subscriptionRows ?? []) as SubscriptionRow[];
  const subscriptionUserIds = subscriptions.map((sub) => sub.user_id);
  const { data: subscriberProfiles } = subscriptionUserIds.length
    ? await supabase
        .from("users_public")
        .select(
          "id, username, display_name, trust_tier, is_pro, pro_plan, pro_expires_at, created_at",
        )
        .in("id", subscriptionUserIds)
    : { data: [] };
  const profileById = new Map(
    ((subscriberProfiles ?? []) as SubscriptionUser[]).map((profile) => [
      profile.id,
      profile,
    ]),
  );
  const subscribers: DisplaySubscriptionRow[] = subscriptions.map((sub) => ({
    ...sub,
    users_public: profileById.get(sub.user_id) ?? null,
  }));
  const activeSubscriptionUserIds = new Set(
    subscriptions
      .filter((sub) => isActiveSubscription(sub.status, sub.expires_at))
      .map((sub) => sub.user_id),
  );

  // also fetch identity-verified users for context
  const { data: verifiedUsers } = await supabase
    .from("users_private")
    .select("id, is_identity_verified")
    .eq("is_identity_verified", true);

  const verifiedIds = new Set((verifiedUsers ?? []).map((u) => u.id));

  const { data: pricing } = await supabase
    .from("subscription_pricing")
    .select("*")
    .single();

  const { data: eligibleUsers, error: eligibleUsersError } = await supabase
    .from("users_public")
    .select(
      "id, username, display_name, trust_tier, is_pro, pro_plan, pro_expires_at, onboarding_complete, created_at",
    )
    .eq("onboarding_complete", true)
    .not("username", "is", null)
    .order("username", { ascending: true })
    .limit(500);

  let signedUpRows: Array<{ id: string }> = [];
  let signedUpUsersError: { message: string } | null = null;
  const eligibleIds = (eligibleUsers ?? []).map((user) => user.id);
  if (eligibleIds.length > 0) {
    const result = await supabase
      .from("users_private")
      .select("id")
      .in("id", eligibleIds);
    signedUpRows = (result.data ?? []) as Array<{ id: string }>;
    signedUpUsersError = result.error;
  }
  const signedUpIds = new Set(signedUpRows.map((user) => user.id));
  const completedUsers = (eligibleUsers ?? []) as SubscriptionUser[];
  const activeProUsers = completedUsers.filter(isActiveProfilePro);
  const proWithoutSubscription = activeProUsers.filter(
    (user) => !activeSubscriptionUserIds.has(user.id),
  );
  const eligibleGrantUsers = (eligibleUsers ?? []).filter((user) =>
    Boolean(user.username?.trim()) &&
    signedUpIds.has(user.id) &&
    !isActiveProfilePro(user) &&
    !activeSubscriptionUserIds.has(user.id),
  );
  const displaySubscribers: DisplaySubscriptionRow[] = [
    ...subscribers,
    ...proWithoutSubscription.map((profile) => ({
      id: `profile-${profile.id}`,
      user_id: profile.id,
      plan: profile.pro_plan ?? "profile_pro",
      status: "profile-only",
      expires_at: profile.pro_expires_at ?? null,
      created_at: profile.created_at ?? new Date().toISOString(),
      users_public: profile,
      profileOnly: true,
    })),
  ];

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title="Subscriptions"
          subtitle="Manual grants, revokes, and pricing controls"
        />
        <div className="admin-stagger p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6 space-y-6">
      <Heading size="6">Subscriptions</Heading>

      {(subscribersError || eligibleUsersError || signedUpUsersError) && (
        <div className="rounded-xl border border-coral-dark/20 bg-coral-light p-4 text-sm text-coral-dark">
          {subscribersError?.message ??
            eligibleUsersError?.message ??
            signedUpUsersError?.message}
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-3">
        <div className="admin-soft-card rounded-xl border border-border-subtle bg-white p-4">
          <p className="text-xs text-gray-400">Subscription rows</p>
          <p className="mt-1 text-2xl font-semibold text-charcoal">
            {subscribers?.length ?? 0}
          </p>
        </div>
        <div className="admin-soft-card rounded-xl border border-border-subtle bg-white p-4">
          <p className="text-xs text-gray-400">Eligible free users</p>
          <p className="mt-1 text-2xl font-semibold text-charcoal">
            {eligibleGrantUsers.length}
          </p>
        </div>
        <div className="admin-soft-card rounded-xl border border-border-subtle bg-white p-4">
          <p className="text-xs text-gray-400">ID verified users</p>
          <p className="mt-1 text-2xl font-semibold text-charcoal">
            {verifiedIds.size}
          </p>
        </div>
      </div>

      {proWithoutSubscription.length > 0 && (
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-900">
          <p className="font-medium">
            {proWithoutSubscription.length} Pro profile
            {proWithoutSubscription.length === 1 ? "" : "s"} do not have an
            active subscription row.
          </p>
          <p className="mt-1">
            These users have `users_public.is_pro=true`, so they are hidden from
            manual grants, but the `subscriptions` table has no active row for
            them. They are shown below as profile-only rows.
          </p>
        </div>
      )}

      {eligibleGrantUsers.length === 0 && (
        <div className="rounded-xl border border-border-subtle bg-white p-4 text-sm leading-6 text-gray-500 shadow-sm">
          <p className="font-medium text-charcoal">
            Manual grants unlock after a real app signup finishes onboarding.
          </p>
          <p className="mt-1">
            The dropdown only includes rows that exist in both `users_public`
            and `users_private`, have a username, and have
            `onboarding_complete=true`. That prevents Pro access from being
            attached to partial or auth-only accounts.
          </p>
        </div>
      )}

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

      {/* grant subscription to an onboarded user */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Grant subscription manually
          </Heading>
          <SubscriptionGrantForm users={eligibleGrantUsers} />
        </Box>
      </Card>

      {/* subscriber list */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Subscribers ({displaySubscribers.length})
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
              {displaySubscribers.map((sub) => (
                <Table.Row key={sub.id}>
                  <Table.Cell>
                    <div>
                      <p>@{sub.users_public?.username ?? "unknown"}</p>
                      {sub.profileOnly && (
                        <p className="text-[10px] font-semibold text-amber-700">
                          Profile Pro, no subscription row
                        </p>
                      )}
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
                    <Badge
                      color={
                        sub.status === "active"
                          ? "green"
                          : sub.profileOnly
                            ? "orange"
                            : "gray"
                      }
                    >
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
                    {sub.profileOnly ? (
                      <Text size="1" color="gray">
                        No row to revoke
                      </Text>
                    ) : (
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
                    )}
                  </Table.Cell>
                </Table.Row>
              ))}
              {displaySubscribers.length === 0 && (
                <Table.Row>
                  <Table.Cell colSpan={6}>
                    <div className="py-8 text-center text-sm text-gray-400">
                      No active subscription rows yet
                    </div>
                  </Table.Cell>
                </Table.Row>
              )}
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

function isActiveSubscription(status: string, expiresAt: string | null) {
  if (status !== "active") return false;
  if (!expiresAt) return true;
  return new Date(expiresAt).getTime() > Date.now();
}

function isActiveProfilePro(user: {
  is_pro?: boolean | null;
  pro_expires_at?: string | null;
}) {
  if (!user.is_pro) return false;
  if (!user.pro_expires_at) return true;
  return new Date(user.pro_expires_at).getTime() > Date.now();
}
