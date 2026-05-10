-- trust engine database-side helpers
-- run order: 003 (after 002_rls_policies)

-- ============================================================
-- function: calculate_interaction_weight
-- returns the trust weight for a given user
-- called by edge functions before inserting interactions
-- ============================================================

create or replace function calculate_interaction_weight(p_user_id uuid)
returns integer language plpgsql security definer as $$
declare
  v_trust_tier trust_tier;
begin
  select trust_tier into v_trust_tier
  from users_public
  where id = p_user_id;

  return case v_trust_tier
    when 'elite'      then 5
    when 'high'       then 4
    when 'medium'     then 3
    when 'low'        then 2
    when 'unverified' then 1
    else 1
  end;
end;
$$;

-- ============================================================
-- function: recalculate_echo_scores
-- called by edge function after any interaction or report event
-- updates all scoring fields atomically
-- ============================================================

create or replace function recalculate_echo_scores(p_echo_id uuid)
returns void language plpgsql security definer as $$
declare
  v_support_weight   integer := 0;
  v_challenge_weight integer := 0;
  v_support_count    integer := 0;
  v_challenge_count  integer := 0;
  v_report_score     integer := 0;
  v_trust_score      integer;
  v_confidence       numeric(5,2);
  v_controversy      numeric(5,2);
  v_new_status       echo_status;
  v_total_interactions integer;
begin
  -- aggregate support and challenge weights
  select
    coalesce(sum(case when type = 'support' then weight else 0 end), 0),
    coalesce(sum(case when type = 'challenge' then weight else 0 end), 0),
    coalesce(count(case when type = 'support' then 1 end), 0),
    coalesce(count(case when type = 'challenge' then 1 end), 0)
  into v_support_weight, v_challenge_weight, v_support_count, v_challenge_count
  from echo_interactions
  where echo_id = p_echo_id;

  -- aggregate report score
  select coalesce(sum(reporter_weight), 0)
  into v_report_score
  from echo_reports
  where echo_id = p_echo_id and resolved = false;

  -- trust score: net weighted support
  v_trust_score := v_support_weight - v_challenge_weight;

  -- confidence score: what % of weighted interactions are supportive
  v_total_interactions := v_support_weight + v_challenge_weight;
  if v_total_interactions > 0 then
    v_confidence := (v_support_weight::numeric / v_total_interactions) * 100;
  else
    v_confidence := 0;
  end if;

  -- controversy score: how balanced is the split (0 = one-sided, 1 = perfectly split)
  if greatest(v_support_count, v_challenge_count) > 0 then
    v_controversy := least(v_support_count, v_challenge_count)::numeric
                     / greatest(v_support_count, v_challenge_count)::numeric;
  else
    v_controversy := 0;
  end if;

  -- determine status based on score thresholds
  v_new_status := case
    when v_report_score >= 70                                  then 'hidden'
    when v_report_score >= 20 and v_trust_score < 10          then 'under_review'
    when v_trust_score >= 50 and v_confidence >= 70            then 'verified'
    when v_controversy >= 0.6 and v_total_interactions >= 10   then 'controversial'
    when v_trust_score < 0                                     then 'disputed'
    when v_trust_score >= 10                                   then 'active'
    else 'pending_verification'
  end;

  -- update echo atomically
  update echoes set
    trust_score       = v_trust_score,
    confidence_score  = v_confidence,
    controversy_score = v_controversy * 100,
    report_score      = v_report_score,
    support_count     = v_support_count,
    challenge_count   = v_challenge_count,
    status            = coalesce(
      -- if admin has manually overridden, respect it
      case when admin_verified is not null
        then case when admin_verified then 'verified'::echo_status else 'rejected'::echo_status end
        else null
      end,
      v_new_status
    ),
    last_engine_run_at = now()
  where id = p_echo_id;
end;
$$;

-- ============================================================
-- function: update_user_trust_tier
-- recalculates and sets a user's public trust tier
-- called after identity verification or significant activity milestones
-- ============================================================

create or replace function update_user_trust_tier(p_user_id uuid)
returns void language plpgsql security definer as $$
declare
  v_identity_score  integer := 0;
  v_echo_count      integer := 0;
  v_proof_count     integer := 0;
  v_composite_score integer;
  v_new_tier        trust_tier;
begin
  select identity_score into v_identity_score
  from users_private where id = p_user_id;

  select echo_count, proof_count
  into v_echo_count, v_proof_count
  from users_public where id = p_user_id;

  -- composite score: identity is dominant signal
  v_composite_score := (v_identity_score * 0.7)::integer
                     + least(v_echo_count, 20)        -- cap at 20 echoes contribution
                     + least(v_proof_count * 2, 20);  -- proofs worth 2x, capped

  v_new_tier := case
    when v_composite_score >= 90 then 'elite'
    when v_composite_score >= 70 then 'high'
    when v_composite_score >= 50 then 'medium'
    when v_composite_score >= 20 then 'low'
    else 'unverified'
  end;

  update users_public
  set trust_tier = v_new_tier, trust_score = v_composite_score
  where id = p_user_id;
end;
$$;

-- ============================================================
-- function: expire_zero_engagement_echoes
-- marks echoes with 0 interactions older than 72h as low-priority
-- intended to run daily via pg_cron or a scheduled edge function
-- ============================================================

create or replace function expire_zero_engagement_echoes()
returns void language plpgsql security definer as $$
begin
  update echoes
  set status = 'pending_verification',
      expires_at = now() + interval '7 days'
  where status = 'active'
    and support_count = 0
    and challenge_count = 0
    and report_score = 0
    and created_at < now() - interval '72 hours'
    and expires_at is null;
end;
$$;