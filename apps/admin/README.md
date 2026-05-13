# Echoproof Admin

Internal moderation and operations panel for Echoproof.

## Required Environment

Set these in the admin app deployment:

```bash
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
ADMIN_EMAIL=support@echoproof.online
ADMIN_PASSWORD=
ADMIN_SESSION_SECRET=
ADMIN_ALLOWED_EMAILS=support@echoproof.online
ADMIN_PUBLIC_URL=https://echoproof-admin.onrender.com
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are used server-side for admin
operations. `SUPABASE_ANON_KEY` is only kept for compatibility with older auth
paths; the current login does not depend on Supabase OAuth.

`ADMIN_PASSWORD` is the private admin login password. `ADMIN_ACCESS_PASSWORD`
and `ADMIN_ACCESS_KEY` are accepted aliases, but prefer `ADMIN_PASSWORD`.
`ADMIN_SESSION_SECRET` must be a different long random value used to sign the
admin session cookie.

`ADMIN_PUBLIC_URL` is recommended on Render because the app can see Render's
internal host, such as `localhost:10000`, while handling OAuth callbacks. Set it
to the external admin URL so redirects never bounce to the internal host.

## Login

The admin login is email + server password only. The default email is
`support@echoproof.online`, and it must still be present in
`ADMIN_ALLOWED_EMAILS`.

## Deploying Under `/admin`

Only set a base path if the admin panel is hosted under another site's path:

```bash
NEXT_PUBLIC_ADMIN_BASE_PATH=/admin
```

Do not set this for `https://echoproof-admin.onrender.com/`, because that app is
hosted at the root of its own domain.
