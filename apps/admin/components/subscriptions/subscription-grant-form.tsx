"use client";

import { useState } from "react";
import { Box, Button, Flex, Text } from "@radix-ui/themes";
import { adminPath } from "@/lib/routes";

type EligibleGrantUser = {
  id: string;
  username: string | null;
  display_name?: string | null;
};

export function SubscriptionGrantForm({
  users,
}: {
  users: EligibleGrantUser[];
}) {
  const [plan, setPlan] = useState("pro_monthly");
  const isYearly = plan === "pro_yearly";
  const maxCount = isYearly ? 1 : 2;

  return (
    <form action={adminPath("/api/admin/subscription/grant")} method="POST">
      <Flex gap="3" align="end" wrap="wrap" className="w-full">
        <Box className="w-full sm:w-auto">
          <Text size="2" color="gray">
            Completed free user
          </Text>
          <select
            name="username"
            disabled={users.length === 0}
            className="mt-1 w-full rounded border bg-white p-2 disabled:bg-gray-100 disabled:text-gray-400 sm:w-72"
            required
          >
            {users.length === 0 ? (
              <option value="">No eligible free users yet</option>
            ) : (
              users.map((user) => (
                <option key={user.id} value={user.username ?? ""}>
                  @{user.username}
                  {user.display_name ? ` - ${user.display_name}` : ""}
                </option>
              ))
            )}
          </select>
        </Box>

        <Box className="w-[calc(50%-6px)] sm:w-auto">
          <Text size="2" color="gray">
            Plan
          </Text>
          <select
            name="plan_type"
            value={plan}
            onChange={(event) => setPlan(event.target.value)}
            className="mt-1 w-full rounded border bg-white p-2 sm:w-40"
          >
            <option value="pro_monthly">Pro monthly</option>
            <option value="pro_yearly">Pro yearly</option>
          </select>
        </Box>

        <Box className="w-[calc(50%-6px)] sm:w-auto">
          <Text size="2" color="gray">
            {isYearly ? "Years" : "Months"}
          </Text>
          <input
            key={plan}
            name="duration_count"
            type="number"
            min={1}
            max={maxCount}
            defaultValue={1}
            className="mt-1 w-full rounded border p-2 sm:w-24"
          />
        </Box>

        <Box className="w-full sm:w-auto">
          <Text size="2" color="gray">
            Purchase history
          </Text>
          <select
            name="purchase_history_mode"
            defaultValue="none"
            className="mt-1 w-full rounded border bg-white p-2 sm:w-64"
          >
            <option value="none">Do not generate</option>
            <option value="active">Generate active mock order</option>
            <option value="acknowledged">Generate acknowledged mock order</option>
          </select>
        </Box>

        <Button
          type="submit"
          color="green"
          className="w-full sm:w-auto"
          disabled={users.length === 0}
        >
          Grant
        </Button>
      </Flex>
      <Text size="1" color="gray" mt="3" as="p">
        Active Pro users are hidden here. Monthly grants allow 1-2 months.
        Yearly grants allow exactly 1 year. Expired users become eligible again.
      </Text>
    </form>
  );
}
