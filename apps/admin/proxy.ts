// protects all admin routes — redirects to login if no supabase session

import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import { adminSessionFromRequest } from "@/lib/auth/admin-session";
import { adminUrl } from "@/lib/public-url";
import { adminPath } from "@/lib/routes";

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookiesToSet) => {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const loginPath = adminPath("/login");
  const callbackPath = adminPath("/auth/callback");
  const magicLinkPath = adminPath("/api/auth/admin-magic-link");
  const path = request.nextUrl.pathname;
  const isLoginPage =
    path === "/login" || path === loginPath;
  const isPublicAuthPath =
    isLoginPage ||
    path === "/auth/callback" ||
    path === callbackPath ||
    path === "/api/auth/admin-magic-link" ||
    path === magicLinkPath ||
    path === "/api/auth/admin-access-login" ||
    path === adminPath("/api/auth/admin-access-login") ||
    path === "/api/auth/admin-logout" ||
    path === adminPath("/api/auth/admin-logout");
  const isAllowedAdmin = isAllowedAdminEmail(user?.email);
  const staticAdmin = await adminSessionFromRequest(request);
  const isAuthenticatedAdmin = isAllowedAdmin || Boolean(staticAdmin);

  if (!user && !staticAdmin && !isPublicAuthPath) {
    return NextResponse.redirect(adminUrl(request, "/login"));
  }

  if (user && !isAuthenticatedAdmin && !isLoginPage) {
    const url = adminUrl(request, "/login");
    url.searchParams.set("error", "unauthorized");
    return NextResponse.redirect(url);
  }

  if (isLoginPage && isAuthenticatedAdmin) {
    return NextResponse.redirect(adminUrl(request, "/"));
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
