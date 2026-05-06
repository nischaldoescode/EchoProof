-- Create the media bucket for echo image/video uploads.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'media',
  'media',
  true,
  42428800, -- 50MB
  array['image/png', 'image/jpeg', 'image/webp', 'video/mp4', 'video/quicktime']
)
on conflict (id) do nothing;

-- Allow authenticated users to upload to their own folder.
create policy "users can upload echo media"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'media' and
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow public read.
create policy "media is publicly readable"
  on storage.objects for select
  to public
  using (bucket_id = 'media');