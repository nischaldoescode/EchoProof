-- Helper to increment verification attempt count atomically
create or replace function increment_verification_attempts(p_user_id uuid)
returns integer language plpgsql security definer as $$
declare
  v_count integer;
begin
  update users_private
  set verification_attempt_count = verification_attempt_count + 1
  where id = p_user_id
  returning verification_attempt_count into v_count;
  return v_count;
end;
$$;