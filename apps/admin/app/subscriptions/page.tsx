import { redirect } from "next/navigation";
import { adminPath } from "@/lib/routes";

export default function LegacySubscriptionsPage() {
  redirect(adminPath("/subscription"));
}
