# Echoproof Web

Landing site and public profile layer for the Echoproof Android app.

## Stack

- Next.js 16 (App Router + Pages Router hybrid)
- Supabase for data
- Tailwind CSS v4
- Deployed on Vercel

## Environment

Copy `.env.local.example` to `.env.local` and fill in your Supabase keys from the project dashboard.

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
- The `/user/[username]` page intentionally blurs content to drive app installs.
- Echo pages at `/echo/[id]` are in `pages/` (not `app/`) because they use `getServerSideProps` for OG tag generation.