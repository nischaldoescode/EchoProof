# Echoproof Web

Landing site and public profile layer for the Echoproof Android app.

## Stack

- Next.js 16 (App Router)
- Supabase for data
- Tailwind CSS v4
- Deployed on Vercel

## Environment

Copy `.env.local.example` to `.env.local` and fill in your Supabase keys from the project dashboard.

Required deployment variables:

```bash
NEXT_PUBLIC_SITE_URL=https://echoproof.online
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
NEXT_PUBLIC_TURNSTILE_SITE_KEY=
TURNSTILE_SECRET_KEY=
TURNSTILE_ALLOWED_HOSTNAMES=echoproof.online,www.echoproof.online
```

`TURNSTILE_ALLOWED_HOSTNAMES` is optional, but useful when Cloudflare returns a
preview or alternate host. Keep it comma-separated and do not include `https://`.

## Deployment routing

Deploy this folder as a Next.js app with SSR enabled. Do not deploy it as static
hosting only; dynamic URLs like `/user/name`, `/user/@name`, and `/echo/id` need
the Next server to receive the request.

## Routes

| Route | Purpose |
|---|---|
| `/` | Landing page |
| `/privacy` | Privacy policy |
| `/delete-account` | Account deletion request form |
| `/user/[username]` | Public profile with app deep link |
| `/echo/[id]` | Echo open graph + deep link redirect |
| `/api/delete-request` | Deletion request API |

## Notes

- `SUPABASE_SERVICE_ROLE_KEY` is server-only. Never use it client-side.
- The `/user/[username]` page accepts both `/user/name` and `/user/@name`, then normalizes to the same public profile.
- The `/user/[username]` page intentionally blurs private or app-only content.
- Echo pages at `/echo/[id]` use App Router metadata so direct visits and shared link previews use the same route.
