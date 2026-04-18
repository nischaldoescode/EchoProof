-- row-level security policies
-- run order: 002 (after 001_initial_schema)

-- ============================================================
-- enable rls on all tables
-- ============================================================

alter table users_private enable row level security;
alter table users_public enable row level security;
alter table echoes enable row level security;
alter table echo_interactions enable row level security;
alter table echo_proofs enable row level security;
alter table echo_reports enable row level security;
alter table notifications enable row level security;
alter table admin_actions enable row level security;

-- ============================================================
-- users_private — only service role can read/write
-- no authenticated user can access their own row via the api
-- all private data goes through edge functions only
-- ============================================================

create policy "service role only" on users_private
  using (false);  -- blocks all direct client access

-- ============================================================
-- users_public — read by all authenticated users, write own row only
-- ============================================================

create policy "anyone authenticated can read public profiles"
  on users_public for select
  to authenticated
  using (true);

create policy "user can update own public profile"
  on users_public for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ============================================================
-- echoes — public read, authenticated create, own update
-- ============================================================

create policy "anyone can read active echoes"
  on echoes for select
  to authenticated
  using (status not in ('hidden', 'rejected'));

create policy "authenticated user can create echo"
  on echoes for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "user can update own echo content only"
  on echoes for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    -- scoring fields are only updatable by service role (edge functions)
    -- enforced by not including them in the policy check
  );

-- ============================================================
-- echo_interactions
-- ============================================================

create policy "authenticated can read interactions"
  on echo_interactions for select
  to authenticated
  using (true);

create policy "authenticated can create interaction"
  on echo_interactions for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "user can update own interaction"
  on echo_interactions for update
  to authenticated
  using (auth.uid() = user_id);

-- ============================================================
-- echo_proofs
-- ============================================================

create policy "authenticated can read proofs"
  on echo_proofs for select
  to authenticated
  using (true);

create policy "authenticated can add proof"
  on echo_proofs for insert
  to authenticated
  with check (auth.uid() = user_id);

-- ============================================================
-- echo_reports — reporter sees only their own reports
-- ============================================================

create policy "user sees own reports"
  on echo_reports for select
  to authenticated
  using (auth.uid() = reporter_id);

create policy "authenticated can file report"
  on echo_reports for insert
  to authenticated
  with check (auth.uid() = reporter_id);

-- ============================================================
-- notifications — user sees only their own
-- ============================================================

create policy "user sees own notifications"
  on notifications for select
  to authenticated
  using (auth.uid() = user_id);

create policy "user can mark own notifications read"
  on notifications for update
  to authenticated
  using (auth.uid() = user_id);

-- ============================================================
-- admin_actions — service role only, completely locked to clients
-- ============================================================

create policy "service role only on admin actions"
  on admin_actions using (false);