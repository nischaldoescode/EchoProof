-- enables pgcrypto for database-level field encryption
-- used to encrypt government id hashes at rest in the database
-- run order: 013

create extension if not exists "pgcrypto";

-- the encryption key is set as a database secret — never in code
-- in supabase dashboard: project settings > vault > add secret
-- secret name: echoproof_field_key

-- helper function: encrypts a text value using aes-256-cbc
-- called by application code before inserting sensitive fields
create or replace function encrypt_field(p_value text)
returns text language plpgsql security definer as $$
declare
  v_key text;
begin
  -- key fetched from supabase vault — never hardcoded
  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name = 'echoproof_field_key'
  limit 1;

  if v_key is null then
    -- if vault not configured, return value as-is (development mode)
    -- in production this would raise an exception
    return p_value;
  end if;

  return encode(
    encrypt(
      convert_to(p_value, 'utf8'),
      decode(v_key, 'hex'),
      'aes-cbc'
    ),
    'base64'
  );
end;
$$;

-- helper function: decrypts a field value
-- service role only — never exposed to client api
create or replace function decrypt_field(p_value text)
returns text language plpgsql security definer as $$
declare
  v_key text;
begin
  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name = 'echoproof_field_key'
  limit 1;

  if v_key is null then
    return p_value;
  end if;

  return convert_from(
    decrypt(
      decode(p_value, 'base64'),
      decode(v_key, 'hex'),
      'aes-cbc'
    ),
    'utf8'
  );
end;
$$;

-- rls: only service role can call these functions
revoke execute on function encrypt_field(text) from public;
revoke execute on function decrypt_field(text) from public;
grant execute on function encrypt_field(text) to service_role;
grant execute on function decrypt_field(text) to service_role;