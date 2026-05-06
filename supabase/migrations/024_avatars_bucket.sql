-- Creates the avatars storage bucket for user avatar images.
-- Must run once to enable the avatar upload flow in onboarding.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do nothing;