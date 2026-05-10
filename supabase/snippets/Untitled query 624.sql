do $$
declare
  admin_id uuid;
begin
  -- get admin user id
  select id into admin_id
  from public.users_private
  where lower(email) = 'support@echoproof.online'
  limit 1;

  if admin_id is null then
    raise exception 'Admin user not found';
  end if;

  -- 🔥 delete user-related data

  delete from public.signal_responses where user_id <> admin_id;

  delete from public.echo_interactions where user_id <> admin_id;

  delete from public.echo_replies where user_id <> admin_id;

  delete from public.echo_proofs where user_id <> admin_id;

  delete from public.notifications where user_id <> admin_id;

  delete from public.user_feed_signals where user_id <> admin_id;

  delete from public.subscriptions where user_id <> admin_id;

  delete from public.device_tokens where user_id <> admin_id;

  delete from public.truth_bonds where user_id <> admin_id;

  delete from public.moderation_log where user_id <> admin_id;

  delete from public.purchase_history where user_id <> admin_id;

  delete from public.verification_sessions where user_id <> admin_id;

  delete from public.verification_ip_log where user_id <> admin_id;

  delete from public.user_category_affinity_decayed where user_id <> admin_id;

  -- special cases

  delete from public.echo_reports where reporter_id <> admin_id;

  -- tables without user_id → delete via echo ownership

  delete from public.echo_signals
  where echo_id in (
    select id from public.echoes where user_id <> admin_id
  );

  -- core content

  delete from public.echoes where user_id <> admin_id;

  -- optional (no user reference → wipe safely)
  delete from public.deletion_requests;
  delete from public.admin_actions;

  -- finally users

  delete from public.users_public where id <> admin_id;

  delete from public.users_private where id <> admin_id;

  delete from auth.users where id <> admin_id;

end $$;