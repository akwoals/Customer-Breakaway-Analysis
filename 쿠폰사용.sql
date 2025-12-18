with 
    fristpurchasegroup as(
      select user_id, case 
                         when coupon_discount_amount > 0 then "쿠폰 사용자"
                         else "쿠폰 비사용자" end as coupon_group
      from `team_pjt.complete_subscription`
    )

select fsg.coupon_group,
       count(distinct fsg.user_id) as total_users,
       count(distinct rs.user_id) as renewed_users,
       round(safe_divide(count(distinct rs.user_id), count(distinct fsg.user_id)) *100,1) as renewal_rate_percentage
from fristpurchasegroup as fsg
left join `team_pjt.renew_subscription` as rs on fsg.user_id = rs.user_id
group by fsg.coupon_group