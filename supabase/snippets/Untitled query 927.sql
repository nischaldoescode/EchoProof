-- Ensure the trigger function exists and is robust.
-- This runs whenever a new auth.users row is inserted (Google, email OTP, etc.)
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  _username text;
  _display  text;
begin
  -- Generate a temp username from the first 8 chars of the UUID.
  _username := 'user' || replace(new.id::text, '-', '');
  _username := substring(_username, 1, 20);

  -- Try to extract display name from metadata (Google provides this).
  _display := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    ''
  );

  -- Insert a skeleton row so the app never gets a missing-row error.
  -- onboarding_complete stays false until the user finishes onboarding.
  insert into users_public (
    id,
    username,
    display_name,
    trust_tier,
    trust_score,
    echo_count,
    proof_count,
    is_public,
    onboarding_complete,
    created_at
  ) values (
    new.id,
    _username,
    _display,
    'unverified',
    0,
    0,
    0,
    true,
    false,
    now()
  )
  on conflict (id) do nothing; -- safe to call multiple times

  -- Also create users_private row if it doesn't exist.
  insert into users_private (
    id,
    is_identity_verified,
    created_at
  ) values (
    new.id,
    false,
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- Drop and recreate the trigger to ensure it fires.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();