// subscriptions management page
// admin can: grant/revoke subscriptions, change pricing, see all subscribers

import { createServerClient } from '@/lib/supabase/client';
import { Heading, Card, Table, Badge, Button, Box, Text, Flex } from '@radix-ui/themes';
import Link from 'next/link';

export default async function SubscriptionsPage() {
  const supabase = createServerClient();

  const { data: subscribers } = await supabase
    .from('subscriptions')
    .select(`
      *,
      users_public(username, trust_tier)
    `)
    .order('created_at', { ascending: false });

  const { data: pricing } = await supabase
    .from('subscription_pricing')
    .select('*')
    .single();

  return (
    <div className="p-6 space-y-6">
      <Heading size="6">Subscriptions</Heading>

      {/* pricing controls */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">Pricing</Heading>
          <form action="/api/admin/subscriptions/pricing" method="POST">
            <Flex gap="4" align="end">
              <Box>
                <Text size="2" color="gray">Monthly price (USD)</Text>
                <input
                  name="monthly_usd"
                  type="number"
                  step="0.01"
                  defaultValue={pricing?.monthly_usd ?? 4.99}
                  className="border rounded p-2 w-32 mt-1"
                />
              </Box>
              <Box>
                <Text size="2" color="gray">New user discount (%)</Text>
                <input
                  name="new_user_discount_pct"
                  type="number"
                  defaultValue={pricing?.new_user_discount_pct ?? 30}
                  className="border rounded p-2 w-24 mt-1"
                />
              </Box>
              <Box>
                <Text size="2" color="gray">Free trial days</Text>
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
          <Heading size="4" mb="4">Grant subscription manually</Heading>
          <form action="/api/admin/subscriptions/grant" method="POST">
            <Flex gap="3" align="end">
              <Box>
                <Text size="2" color="gray">Username</Text>
                <input
                  name="username"
                  placeholder="@username"
                  className="border rounded p-2 w-48 mt-1"
                />
              </Box>
              <Box>
                <Text size="2" color="gray">Duration (days)</Text>
                <input
                  name="days"
                  type="number"
                  defaultValue={30}
                  className="border rounded p-2 w-24 mt-1"
                />
              </Box>
              <Button type="submit" color="green">
                Grant
              </Button>
            </Flex>
          </form>
        </Box>
      </Card>

      {/* subscriber list */}
      <Card>
        <Box p="4">
          <Heading size="4" mb="4">
            Subscribers ({subscribers?.length ?? 0})
          </Heading>
          <Table.Root>
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
                    @{sub.users_public?.username ?? '—'}
                  </Table.Cell>
                  <Table.Cell>
                    <Badge color="purple">{sub.plan}</Badge>
                  </Table.Cell>
                  <Table.Cell>
                    <Badge color={sub.status === 'active' ? 'green' : 'gray'}>
                      {sub.status}
                    </Badge>
                  </Table.Cell>
                  <Table.Cell>
                    {new Date(sub.created_at).toLocaleDateString()}
                  </Table.Cell>
                  <Table.Cell>
                    {sub.expires_at
                      ? new Date(sub.expires_at).toLocaleDateString()
                      : '—'}
                  </Table.Cell>
                  <Table.Cell>
                    <form action="/api/admin/subscriptions/revoke" method="POST">
                      <input type="hidden" name="subscription_id" value={sub.id} />
                      <Button type="submit" color="red" variant="soft" size="1">
                        Revoke
                      </Button>
                    </form>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table.Root>
        </Box>
      </Card>
    </div>
  );
}