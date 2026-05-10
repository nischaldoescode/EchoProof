-- adds date_of_birth to users_public for accurate age calculation
-- age column already exists from 014, we keep it for fast queries
-- dob is stored as date, never exposed publicly via rls

alter table public.users_public
  add column if not exists date_of_birth date;

comment on column public.users_public.date_of_birth is
  'user date of birth — used to calculate age at verification time. never shown publicly.';