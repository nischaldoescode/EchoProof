# Echoproof Admin

Internal moderation and operations panel for Echoproof.

## Required environment

Set these in the admin app deployment:

```bash
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
ADMIN_ALLOWED_EMAILS=admin1@example.com,admin2@example.com
```

`ADMIN_ALLOWED_EMAILS` is required in production. You can also use
`ADMIN_EMAIL_ALLOWLIST` as the same setting name. Without an allowlist, the
panel rejects production users instead of letting every authenticated Supabase
account reach service-role actions.

## Login

The admin login supports three Supabase Auth methods:

- Google OAuth, if the Google provider is enabled in Supabase.
- Magic link, if email OTP/magic links are enabled in Supabase.
- Email and password, if the admin user has a password set.

Whichever method you use, the final email must be listed in
`ADMIN_ALLOWED_EMAILS`.

## Deploying under `/admin`

If the admin panel is hosted on the same domain under `/admin`, build the admin
app with:

```bash
NEXT_PUBLIC_ADMIN_BASE_PATH=/admin
```

Then configure your host/CDN to send `/admin/**` to the admin Next app. Without
that base path, the browser asks for CSS and JS from `/_next/...`, which can be
served by the landing app instead and makes the admin look like an unstyled HTML
skeleton.

## Notes

- `NEXT_PUBLIC_SUPABASE_ANON_KEY` is safe for browser auth and RLS-bound reads.
- `SUPABASE_SERVICE_ROLE_KEY` is server-only and is only imported from
  `lib/supabase/admin.ts`.
- The proxy checks the signed-in user's email before serving admin pages.
- API routes check the same admin allowlist again before running service-role
  mutations.
