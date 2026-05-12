-- Server-side email validation for app auth requests.
-- The mobile app calls this before requesting an OTP. This protects the app
-- flow from invalid addresses and throwaway/custom domains.

create or replace function public.validate_auth_email(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_domain text;
  v_allowed_domains constant text[] := array[
    'gmail.com',
    'googlemail.com',
    'outlook.com',
    'hotmail.com',
    'live.com',
    'msn.com',
    'yahoo.com',
    'ymail.com',
    'icloud.com',
    'me.com',
    'mac.com',
    'proton.me',
    'protonmail.com',
    'pm.me'
  ];
begin
  if v_email !~ $re$^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$re$ then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'invalid_format'
    );
  end if;

  v_domain := split_part(v_email, '@', 2);

  if not (v_domain = any(v_allowed_domains)) then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'unsupported_domain',
      'domain', v_domain
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'reason', 'ok',
    'domain', v_domain
  );
end;
$$;

grant execute on function public.validate_auth_email(text) to anon, authenticated;
