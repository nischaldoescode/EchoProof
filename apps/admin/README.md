# Echoproof Admin

Internal moderation and operations panel for Echoproof.

## Required Environment

Set these in the admin app deployment:

```bash
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
ADMIN_ALLOWED_EMAILS=support@echoproof.online,nischala389@gmail.com
ADMIN_PUBLIC_URL=https://echoproof-admin.onrender.com
```

`ADMIN_ALLOWED_EMAILS` is required in production. You can also use
`ADMIN_EMAIL_ALLOWLIST` as the same setting name.

`ADMIN_PUBLIC_URL` is recommended on Render because the app can see Render's
internal host, such as `localhost:10000`, while handling OAuth callbacks. Set it
to the external admin URL so redirects never bounce to the internal host.

## Login

The admin login supports:

- GitHub OAuth, if the GitHub provider is enabled in Supabase Auth.
- Google OAuth, if the Google provider is enabled in Supabase Auth.
- Magic link, if Email OTP is enabled in Supabase Auth.
- Optional recovery access key, if configured.

Whichever method you use, the final admin email must be listed in
`ADMIN_ALLOWED_EMAILS`.

If magic link returns `Signups not allowed for otp`, either enable Email OTP
signups in Supabase Auth or create the admin email first in Authentication >
Users. Your Supabase Dashboard login is separate from this app's Auth users.

To enable the non-Supabase recovery login, set both:

```bash
ADMIN_ACCESS_KEY=
ADMIN_SESSION_SECRET=
```

Use long random values. The email must still be allowlisted.

## Deploying Under `/admin`

Only set a base path if the admin panel is hosted under another site's path:

```bash
NEXT_PUBLIC_ADMIN_BASE_PATH=/admin
```

Do not set this for `https://echoproof-admin.onrender.com/`, because that app is
hosted at the root of its own domain.
