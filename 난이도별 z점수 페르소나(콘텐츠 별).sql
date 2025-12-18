WITH 
content_difficulty AS (
  SELECT DISTINCT
    `content_id`,
    `content_difficulty`
  FROM `team_pjt.start_content`
),

lessons_with_difficulty AS (
  SELECT 
    ec.user_id,
    ec.`content_id`,
    cd.`content_difficulty`
  FROM `team_pjt.end_content` AS ec
  LEFT JOIN content_difficulty AS cd
    ON ec.`content_id` = cd.`content_id`
  WHERE cd.`content_difficulty` IS NOT NULL
),


lessons_with_score AS (
  SELECT 
    user_id,
    `content_id`,
    `content_difficulty`,
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
    AVG(difficulty_score) AS weighted_mean_difficulty
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
    (upw.completions_winsorized - s.mean_completions) / NULLIF(s.std_completions, 0) AS total_skill_score
    
  FROM user_profiles_winsorized AS upw
  CROSS JOIN stats AS s
)


-- 최종 결과에 페르소나 추가(이전 부분은 위에 올린 난이도 별 z점수 코드와 같음)
SELECT 
  user_id,
  total_completed_contents,
  ROUND(weighted_mean_difficulty, 2) AS weighted_mean_difficulty,
  ROUND(z_score_difficulty, 2) AS z_score_difficulty,
  ROUND(z_score_completions, 2) AS z_score_completions,
  CASE
    WHEN z_score_completions > 2 AND z_score_difficulty > 2 THEN '고급자'
    WHEN z_score_completions > 2 AND z_score_difficulty <= 2 THEN '강의 수를 듣고 실력 오른 중급자?'
    WHEN z_score_completions <= 2 AND z_score_difficulty > 2 THEN '처음부터 고급자'
    ELSE '4. 초급자'
  END AS user_persona
FROM user_profiles_final
ORDER BY (z_score_difficulty + z_score_completions) DESC;