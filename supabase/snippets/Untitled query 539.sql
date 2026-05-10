-- Fix the type cast issue in get_personalized_feed
CREATE OR REPLACE FUNCTION get_personalized_feed(
  p_user_id uuid,
  p_offset  integer default 0,
  p_limit   integer default 20
) RETURNS TABLE (
  echo_id         uuid,
  personalized_score numeric
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS echo_id,
    (
      (e.trust_score::numeric * 0.40)

      + COALESCE(
          (SELECT affinity_score FROM user_category_affinity
           WHERE user_id = p_user_id
             -- FIX: cast echo_category enum to text for comparison with text column
             AND category = e.category::text
           LIMIT 1),
          0
        ) * 0.30

      + (20.0 * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - e.created_at)) / 604800)) * 0.20

      + (e.confidence_score * 0.10)

      + (e.controversy_score * 0.05)

      + CASE WHEN e.category = ANY(
          SELECT UNNEST(categories)
          FROM users_public
          WHERE id = p_user_id
        ) THEN 15 ELSE 0 END

      + CASE WHEN (
          SELECT is_pro FROM users_public WHERE id = e.user_id
        ) THEN 10 ELSE 0 END  -- Pro users get feed priority boost

      - CASE WHEN EXISTS (
          SELECT 1 FROM echo_interactions
          WHERE echo_interactions.echo_id = e.id
            AND echo_interactions.user_id = p_user_id
        ) THEN 30 ELSE 0 END

    ) AS personalized_score
  FROM echoes e
  WHERE e.status NOT IN ('hidden', 'rejected')
    AND e.user_id != p_user_id
  ORDER BY personalized_score DESC
  OFFSET p_offset
  LIMIT p_limit;
END;
$$;