-- supabase/migrations/018_profile_visibility.sql
alter table users_public add column if not exists is_public boolean not null default true;
alter table users_public add column if not exists bio text;