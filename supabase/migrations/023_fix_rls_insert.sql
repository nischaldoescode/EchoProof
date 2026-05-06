-- Allows authenticated users to insert their own row into users_public.
-- Required for the onboarding completion flow when the signup trigger
-- has not yet created the row (slow trigger, cold start, etc.).
-- The check ensures a user can only insert a row for their own id.

create policy "user can insert own public profile"
  on users_public for insert
  to authenticated
  with check (auth.uid() = id);