-- realtime setup for echoproof
-- enables supabase realtime on tables that need live updates
-- run order: 004 (after 003_trust_engine)
-- enable realtime on echoes — clients subscribe to score updates
alter publication supabase_realtime add table echoes;

-- enable realtime on notifications — clients get live notification badges
alter publication supabase_realtime add table notifications;

-- add increment_echo_count function
-- called by on-echo-created edge function after successful echo creation
create or replace function increment_echo_count(p_user_id uuid)
returns void language plpgsql security definer as $$
begin
  update users_public
  set echo_count = echo_count + 1
  where id = p_user_id;
end;
$$;