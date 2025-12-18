with
  RankedRenwals as(
    select user_id,
    coupon_discount_amount,
    client_event_time,
    row_number() over(partition by user_id order by client_event_time ) as renewal_rank
    from `team_pjt.renew_subscription`
  ) ,
 ---- 첫번째 갱신한사람
  FristRenewalGroups as (
    select user_id, 
    case when coupon_discount_amount > 0 then '갱신시 쿠폰 사용자'
    else '갱신시 쿠폰 비사용자' end AS first_renewal_group
    from RankedRenwals
    where renewal_rank = 1
  ),

  ------ 두번 이상 갱신한 사람
    SecondRenewalUsers as (
    select user_id
    from RankedRenwals
    where renewal_rank >=2
  )

------ 그룹별 두 번째 갱신율 계산
  select first_renewal_group,
  count(distinct frg.user_id) as total_first_renewers,
  COUNT(DISTINCT sru.user_id) AS second_renewers,
  round(safe_divide(COUNT(DISTINCT sru.user_id), count(distinct frg.user_id) * 100),5) as second_renewal_rate_percentage

  from FristRenewalGroups as frg
  left join SecondRenewalUsers AS sru
  ON frg.user_id = sru.user_id
  group by first_renewal_group

