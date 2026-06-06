// web host routing
// @params request incoming next request

import { NextResponse, type NextRequest } from "next/server";

const JOIN_HOSTS = new Set(["join.echoproof.online", "www.join.echoproof.online"]);

export function proxy(request: NextRequest) {
  const host = (request.headers.get("host") || "")
    .split(":")[0]
    .toLowerCase();

  if (JOIN_HOSTS.has(host) && request.nextUrl.pathname === "/") {
    const url = request.nextUrl.clone();
    url.pathname = "/room";
    return NextResponse.rewrite(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\..*).*)"],
};
