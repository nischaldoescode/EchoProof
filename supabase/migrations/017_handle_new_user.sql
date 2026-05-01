create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users_public (
    id,
    username,
    display_name,
    trust_tier,
    trust_score,
    echo_count,
    proof_count,
    created_at
  ) values (
    new.id,
    null,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      ''
    ),
    'unverified',
    0,
    0,
    0,
    now()
  )
  on conflict (id) do nothing;

  insert into public.users_private (
    id,
    email,
    is_identity_verified,
    created_at
  ) values (
    new.id,
    coalesce(new.email, ''),
    false,
    now()
  )
  on conflict (id) do nothing;

  return new;

exception
  when others then
    raise log 'handle_new_user error for id=%: % (sqlstate=%)', new.id, sqlerrm, sqlstate;
    return new;
end;
$$;