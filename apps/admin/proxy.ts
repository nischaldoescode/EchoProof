// protects all admin routes redirects to login if no supabase session

import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import type { User } from "@supabase/supabase-js";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import { adminSessionFromRequest } from "@/lib/auth/admin-session";
import { adminUrl } from "@/lib/public-url";
import { adminPath } from "@/lib/routes";
import {
  getSupabaseAnonKey,
  getSupabaseProjectUrl,
} from "@/lib/supabase-env";

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

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
  const staticAdmin = await adminSessionFromRequest(request);

  if (staticAdmin) {
    if (isLoginPage) {
      return NextResponse.redirect(adminUrl(request, "/"));
    }
    return response;
  }

  const supabaseUrl = getSupabaseProjectUrl();
  const supabaseAnonKey = getSupabaseAnonKey();
  let user: User | null = null;

  if (supabaseUrl && supabaseAnonKey) {
    const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
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
    });

    const result = await supabase.auth.getUser();
    user = result.data.user;
  }

  const isAllowedAdmin = isAllowedAdminEmail(user?.email);
  const isAuthenticatedAdmin = isAllowedAdmin;

  if (!user && !isPublicAuthPath) {
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
