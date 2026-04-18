-- development seed data
-- run via: supabase db reset or scripts/seed_dev.sh
-- DO NOT run this in production

-- seed two test users into auth.users
-- passwords are all: TestPass123!

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.com',
   crypt('TestPass123!', gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.com',
   crypt('TestPass123!', gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

-- seed public profiles
insert into users_public (id, username, trust_tier, trust_score, echo_count, categories)
values
  ('00000000-0000-0000-0000-000000000001', 'quiet_wave_42', 'high', 75, 3, '{tech,ai}'),
  ('00000000-0000-0000-0000-000000000002', 'truth_signal_7', 'medium', 45, 1, '{finance,startups}')
on conflict (id) do nothing;

-- seed private profiles
insert into users_private (id, email, identity_score, is_identity_verified)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.com', 80, true),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.com', 0, false)
on conflict (id) do nothing;

-- seed sample echoes
insert into echoes (id, user_id, title, content, category, status, trust_score, confidence_score, support_count, challenge_count)
values
  (
    'aaaaaaaa-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'This AI startup never shipped their product',
    'I paid $299 for early access to their platform in January. It is now October and they have shipped nothing. Their support emails go unanswered. The founder is still posting on X about how great their roadmap is.',
    'startups',
    'active',
    0, 0.0, 0, 0
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000002',
    'Solana transaction fees are lower than Ethereum even for complex contracts',
    'I ran the same contract deployment on both chains last week. Solana cost $0.00025. Ethereum cost $4.80 on a slow day. The fee difference is real and consistent.',
    'web3',
    'verified',
    55, 78.0, 12, 3
  )
on conflict (id) do nothing;