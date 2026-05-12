// protects all admin routes — redirects to login if no supabase session

import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
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
    path === magicLinkPath;
  const isAllowedAdmin = isAllowedAdminEmail(user?.email);

  if (!user && !isPublicAuthPath) {
    return NextResponse.redirect(new URL(adminPath("/login"), request.url));
  }

  if (user && !isAllowedAdmin && !isLoginPage) {
    const url = new URL(adminPath("/login"), request.url);
    url.searchParams.set("error", "unauthorized");
    return NextResponse.redirect(url);
  }

  if (user && isLoginPage && isAllowedAdmin) {
    return NextResponse.redirect(new URL(adminPath("/"), request.url));
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
