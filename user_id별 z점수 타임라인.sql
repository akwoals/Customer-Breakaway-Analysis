WITH 
content_difficulty AS (
 SELECT DISTINCT
    ss.*,
    content_id,
    content_difficulty
  FROM `team_pjt.start_content` as sc
  left join `team_pjt.subscription_status` as ss on sc.user_id = ss.user_id
  where ss.user_id is not null
),


lessons_with_difficulty AS (
  SELECT 
    ec.user_id,
    ec.`content_id`,
    cd.`content_difficulty`,
    cd.FIRST_SUBSCRIPTION_DATETIME_KST,
    cd.FIRST_SUBSCRIPTION_PLUS_12M_KST

  FROM `team_pjt.end_content` AS ec
  left JOIN content_difficulty AS cd
    ON ec.`content_id` = cd.`content_id`
  WHERE cd.`content_difficulty` IS NOT NULL and cd.user_id is not null
),


lessons_with_score AS (
  SELECT 
    user_id,
    `content_id`,
    `content_difficulty`,
    FIRST_SUBSCRIPTION_DATETIME_KST,
    FIRST_SUBSCRIPTION_PLUS_12M_KST,

    CASE 
      WHEN `content_difficulty` = 'beginner' THEN 1
      WHEN `content_difficulty` = 'intermediate' THEN 2
      WHEN `content_difficulty` = 'advanced' THEN 3
      WHEN `content_difficulty` = 'hard' THEN 4
      ELSE 0
    END AS difficulty_score
  FROM lessons_with_difficulty
),


user_profiles_base AS (
  SELECT 
    user_id,
    COUNT(*) AS total_completed_contents,
    SUM(difficulty_score) AS sum_of_score_x_weight,
    AVG(difficulty_score) AS weighted_mean_difficulty,
   MIN(FIRST_SUBSCRIPTION_DATETIME_KST) AS FIRST_SUBSCRIPTION_DATETIME_KST,
   MIN(FIRST_SUBSCRIPTION_PLUS_12M_KST) AS FIRST_SUBSCRIPTION_PLUS_12M_KST
  FROM lessons_with_score
  GROUP BY user_id
),


quantile_bounds AS (
  SELECT
    APPROX_QUANTILES(total_completed_contents, 100)[OFFSET(5)] AS lower_bound,
    APPROX_QUANTILES(total_completed_contents, 100)[OFFSET(95)] AS upper_bound
  FROM user_profiles_base
),

user_profiles_winsorized AS (
  SELECT 
    upb.*,
    CASE 
      WHEN upb.total_completed_contents < qb.lower_bound THEN qb.lower_bound
      WHEN upb.total_completed_contents > qb.upper_bound THEN qb.upper_bound
      ELSE upb.total_completed_contents
    END AS completions_winsorized
  FROM user_profiles_base AS upb
  CROSS JOIN quantile_bounds AS qb
),


stats AS (
  SELECT
    AVG(weighted_mean_difficulty) AS mean_difficulty,
    STDDEV_POP(weighted_mean_difficulty) AS std_difficulty,
    AVG(completions_winsorized) AS mean_completions,
    STDDEV_POP(completions_winsorized) AS std_completions
  FROM user_profiles_winsorized
),

user_profiles_final AS (
  SELECT 
    upw.user_id,
    upw.total_completed_contents,
    upw.weighted_mean_difficulty,
    upw.sum_of_score_x_weight,
    upw.completions_winsorized,
    
    (upw.weighted_mean_difficulty - s.mean_difficulty) / NULLIF(s.std_difficulty, 0) AS z_score_difficulty,
    (upw.completions_winsorized - s.mean_completions) / NULLIF(s.std_completions, 0) AS z_score_completions,
    
    
    (upw.weighted_mean_difficulty - s.mean_difficulty) / NULLIF(s.std_difficulty, 0) +
    (upw.completions_winsorized - s.mean_completions) / NULLIF(s.std_completions, 0) AS total_skill_score,
    
    FIRST_SUBSCRIPTION_DATETIME_KST,
    FIRST_SUBSCRIPTION_PLUS_12M_KST


    
  FROM user_profiles_winsorized AS upw
  CROSS JOIN stats AS s
)


-- user_id별 z점수와 각 페르소나
SELECT 
  user_id,
   ROUND(z_score_completions, 2) AS z_score_completions,
  ROUND(z_score_difficulty, 2) AS z_score_difficulty,
  CASE
    WHEN z_score_completions > 1.5 AND z_score_difficulty > 1.5 THEN '꾸준 완성형'
    WHEN z_score_completions > 1.5 AND z_score_difficulty <= 1.5 THEN '꾸준 성장형'
    WHEN z_score_completions <= 1.5 AND z_score_difficulty > 1.5 THEN '여유 심화형'
    ELSE '느린 출발형'
  END AS user_persona,
  FIRST_SUBSCRIPTION_DATETIME_KST,
  FIRST_SUBSCRIPTION_PLUS_12M_KST
FROM user_profiles_final
where z_score_difficulty >= 0 and z_score_completions >=0