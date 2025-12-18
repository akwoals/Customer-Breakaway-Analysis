WITH 
-- 2-1: 레슨 완료 기록에 난이도 정보 결합
content_difficulty AS (
  SELECT DISTINCT
    `content_id`,
    `content_difficulty`
  FROM `team_pjt.start_content`
),

lessons_with_difficulty AS (
  SELECT 
    cl.user_id,
    cl.`content_id`,
    cd.`content_difficulty`
  FROM `team_pjt.complete_lesson` AS cl
  LEFT JOIN content_difficulty AS cd
    ON cl.`content_id` = cd.`content_id`
  WHERE cd.`content_difficulty` IS NOT NULL
),

-- 2-2: 난이도를 숫자 점수로 변환
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

-- 2-3: 사용자별 가중 평균 난이도와 총 레슨 완료 수 계산
user_profiles_base AS (
  SELECT 
    user_id,
    COUNT(*) AS total_completed_lessons,
    SUM(difficulty_score) AS sum_of_score_x_weight,
    AVG(difficulty_score) AS weighted_mean_difficulty
  FROM lessons_with_score
  GROUP BY user_id
),

-- 상위/하위 5% 경계값 계산
quantile_bounds AS (
  SELECT
    APPROX_QUANTILES(total_completed_lessons, 100)[OFFSET(5)] AS lower_bound,
    APPROX_QUANTILES(total_completed_lessons, 100)[OFFSET(95)] AS upper_bound
  FROM user_profiles_base
),

-- Winsorizing 적용
user_profiles_winsorized AS (
  SELECT 
    upb.*,
    CASE 
      WHEN upb.total_completed_lessons < qb.lower_bound THEN qb.lower_bound
      WHEN upb.total_completed_lessons > qb.upper_bound THEN qb.upper_bound
      ELSE upb.total_completed_lessons
    END AS completions_winsorized
  FROM user_profiles_base AS upb
  CROSS JOIN quantile_bounds AS qb
),

-- 전체 평균 및 표준편차 계산
stats AS (
  SELECT
    AVG(weighted_mean_difficulty) AS mean_difficulty,
    STDDEV_POP(weighted_mean_difficulty) AS std_difficulty,
    AVG(completions_winsorized) AS mean_completions,
    STDDEV_POP(completions_winsorized) AS std_completions
  FROM user_profiles_winsorized
),

-- Z-score 계산 및 종합 실력 점수 생성
user_profiles_final AS (
  SELECT 
    upw.user_id,
    upw.total_completed_lessons,
    upw.weighted_mean_difficulty,
    upw.sum_of_score_x_weight,
    upw.completions_winsorized,
    
    -- Z-score 계산
    (upw.weighted_mean_difficulty - s.mean_difficulty) / NULLIF(s.std_difficulty, 0) AS z_score_difficulty,
    (upw.completions_winsorized - s.mean_completions) / NULLIF(s.std_completions, 0) AS z_score_completions,
    
    -- 종합 실력 점수
    (upw.weighted_mean_difficulty - s.mean_difficulty) / NULLIF(s.std_difficulty, 0) +
    (upw.completions_winsorized - s.mean_completions) / NULLIF(s.std_completions, 0) AS total_skill_score
    
  FROM user_profiles_winsorized AS upw
  CROSS JOIN stats AS s
)

-- 최종 결과: 종합 실력 점수 상위 사용자
SELECT 
  user_id,
  total_completed_lessons,
  weighted_mean_difficulty,
  completions_winsorized,
  ROUND(z_score_difficulty, 4) AS z_score_difficulty,
  ROUND(z_score_completions, 4) AS z_score_completions,
  ROUND(total_skill_score, 4) AS total_skill_score
FROM user_profiles_final
ORDER BY total_skill_score DESC