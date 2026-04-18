-- echoproof initial database schema
-- run order: 001 (first migration, no dependencies)

-- ============================================================
-- extensions
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pg_trgm";  -- for fuzzy text search on echoes

-- ============================================================
-- enums
-- ============================================================

create type trust_tier as enum ('unverified', 'low', 'medium', 'high', 'elite');
create type echo_status as enum (
  'pending_verification',
  'active',
  'under_review',
  'verified',
  'controversial',
  'disputed',
  'hidden',
  'rejected'
);
create type interaction_type as enum ('support', 'challenge');
create type report_reason as enum ('spam', 'misinformation', 'harassment', 'fake_proof', 'other');
create type echo_category as enum (
  'tech', 'finance', 'startups', 'social_issues',
  'web3', 'ai', 'gaming', 'education', 'other'
);

-- ============================================================
-- users_private
-- stores real identity data — never exposed to public api
-- row-level security will lock this table down to service role only
-- ============================================================

create table users_private (
  id                  uuid primary key references auth.users(id) on delete cascade,
  real_name           text,
  government_id_hash  text,                         -- sha-256 hash, never plain text
  email               text not null,
  google_uid          text,
  identity_score      integer not null default 0,   -- 0-100
  is_identity_verified boolean not null default false,
  device_fingerprint  text,
  ip_risk_score       integer not null default 0,   -- 0-100 (higher = riskier)
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ============================================================
-- users_public
-- safe to read by authenticated users
-- anonymity preserved — no real name, no email here
-- ============================================================

create table users_public (
  id             uuid primary key references auth.users(id) on delete cascade,
  username       text not null unique,
  avatar_url     text,
  bio            text,
  trust_tier     trust_tier not null default 'unverified',
  trust_score    integer not null default 0,       -- internal numeric, not shown directly
  proof_count    integer not null default 0,
  echo_count     integer not null default 0,
  is_suspended   boolean not null default false,
  is_shadow_banned boolean not null default false,
  categories     echo_category[] not null default '{}',  -- user's selected interest categories
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ============================================================
-- echoes
-- the core content unit of echoproof
-- ============================================================

create table echoes (
  id                    uuid primary key default uuid_generate_v4(),
  user_id               uuid not null references users_public(id) on delete cascade,
  title                 text not null check (char_length(title) between 1 and 120),
  content               text not null check (char_length(content) between 1 and 2000),
  category              echo_category not null,
  status                echo_status not null default 'pending_verification',
  verification_required boolean not null default true,

  -- scoring fields — updated by trust engine edge function
  trust_score           integer not null default 0,
  confidence_score      numeric(5,2) not null default 0.0,  -- 0.00 to 100.00
  controversy_score     numeric(5,2) not null default 0.0,
  report_score          integer not null default 0,

  -- interaction counts — denormalized for fast feed queries
  support_count         integer not null default 0,
  challenge_count       integer not null default 0,

  -- admin override fields
  admin_verified        boolean,
  admin_note            text,

  -- timestamps
  last_engine_run_at    timestamptz,
  expires_at            timestamptz,  -- for auto-expiration of zero-engagement echoes
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- text search index on echoes
create index echoes_content_search_idx on echoes using gin (to_tsvector('english', title || ' ' || content));
create index echoes_status_idx on echoes(status);
create index echoes_category_idx on echoes(category);
create index echoes_user_id_idx on echoes(user_id);
create index echoes_trust_score_idx on echoes(trust_score desc);
create index echoes_created_at_idx on echoes(created_at desc);

-- ============================================================
-- echo_interactions
-- one row per user per echo (enforced by unique constraint)
-- ============================================================

create table echo_interactions (
  id          uuid primary key default uuid_generate_v4(),
  echo_id     uuid not null references echoes(id) on delete cascade,
  user_id     uuid not null references users_public(id) on delete cascade,
  type        interaction_type not null,
  weight      integer not null default 1,  -- set by engine based on user trust tier
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  unique(echo_id, user_id)  -- one interaction per user per echo
);

create index echo_interactions_echo_id_idx on echo_interactions(echo_id);

-- ============================================================
-- echo_proofs
-- evidence attached to an echo by any user
-- ============================================================

create table echo_proofs (
  id           uuid primary key default uuid_generate_v4(),
  echo_id      uuid not null references echoes(id) on delete cascade,
  user_id      uuid not null references users_public(id) on delete cascade,
  proof_type   text not null check (proof_type in ('url', 'image', 'document')),
  proof_url    text not null,
  description  text check (char_length(description) <= 500),
  weight       integer not null default 1,
  created_at   timestamptz not null default now()
);

create index echo_proofs_echo_id_idx on echo_proofs(echo_id);

-- ============================================================
-- echo_reports
-- community reports with weighted scoring
-- ============================================================

create table echo_reports (
  id             uuid primary key default uuid_generate_v4(),
  echo_id        uuid not null references echoes(id) on delete cascade,
  reporter_id    uuid not null references users_public(id) on delete cascade,
  reason         report_reason not null,
  description    text check (char_length(description) <= 500),
  reporter_weight integer not null default 1,
  resolved       boolean not null default false,
  created_at     timestamptz not null default now(),

  unique(echo_id, reporter_id)  -- one report per user per echo
);

create index echo_reports_echo_id_idx on echo_reports(echo_id);
create index echo_reports_resolved_idx on echo_reports(resolved) where resolved = false;

-- ============================================================
-- user_categories
-- tracks onboarding category selections
-- already stored as array in users_public but kept here for query flexibility
-- ============================================================

-- ============================================================
-- notifications
-- ============================================================

create table notifications (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references users_public(id) on delete cascade,
  type        text not null,   -- e.g. 'echo_verified', 'report_resolved', 'trust_update'
  title       text not null,
  body        text not null,
  data        jsonb,           -- arbitrary payload for deep linking
  read        boolean not null default false,
  created_at  timestamptz not null default now()
);

create index notifications_user_id_idx on notifications(user_id);
create index notifications_unread_idx on notifications(user_id) where read = false;

-- ============================================================
-- admin_actions
-- audit log for every admin action — immutable append-only
-- ============================================================

create table admin_actions (
  id           uuid primary key default uuid_generate_v4(),
  admin_id     uuid not null references auth.users(id),
  target_type  text not null check (target_type in ('echo', 'user')),
  target_id    uuid not null,
  action       text not null,
  note         text,
  created_at   timestamptz not null default now()
);

-- ============================================================
-- updated_at auto-update triggers
-- ============================================================

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_users_private_updated_at before update on users_private
  for each row execute function set_updated_at();

create trigger set_users_public_updated_at before update on users_public
  for each row execute function set_updated_at();

create trigger set_echoes_updated_at before update on echoes
  for each row execute function set_updated_at();

create trigger set_interactions_updated_at before update on echo_interactions
  for each row execute function set_updated_at();