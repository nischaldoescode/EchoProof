// admin public url helper
// @params none

import type { NextRequest } from "next/server";
import { adminPath } from "@/lib/routes";

export function publicOrigin(request: NextRequest) {
  const configured =
    process.env.NEXT_PUBLIC_ADMIN_URL ||
    process.env.ADMIN_PUBLIC_URL ||
    process.env.RENDER_EXTERNAL_URL;

  if (configured?.trim()) {
    return new URL(configured).origin;
  }

  const forwardedHost = firstHeader(request.headers.get("x-forwarded-host"));
  const forwardedProto = firstHeader(request.headers.get("x-forwarded-proto"));
  const host = forwardedHost || request.headers.get("host") || request.nextUrl.host;
  const proto = forwardedProto || request.nextUrl.protocol.replace(":", "") || "https";

  return `${proto}://${host}`;
}

export function adminUrl(request: NextRequest, path = "/") {
  return new URL(adminPath(path), publicOrigin(request));
}

function firstHeader(value: string | null) {
  return value?.split(",")[0]?.trim() || "";
}
