-- Grain: one row per loan per month end (periodic snapshot)
-- Answers: how much was outstanding, how overdue, and how risky, at each month end

with month_ends as (

    select date_day as month_end
    from {{ ref('dim_date') }}
    where is_month_end
      and date_day <= (select max(booking_date) from {{ ref('fct_postings') }})

),

loans as (

    select * from {{ ref('stg_core_banking__loans') }}

),

repayments as (

    select * from {{ ref('stg_core_banking__repayments') }}

),

-- one row per loan for every month end on or after its payout
loan_months as (

    select
        l.loan_id,
        l.account_id,
        l.customer_id,
        l.product_code,
        l.principal_amount,
        m.month_end
    from loans l
    inner join month_ends m
        on l.disbursement_date <= m.month_end

),

-- state of the repayments AS OF each month end, not as of today
repayment_state as (

    select
        lm.loan_id,
        lm.month_end,
        coalesce(sum(case when r.paid_date <= lm.month_end then r.due_principal end), 0)
            as principal_repaid,
        min(case
                when r.due_date <= lm.month_end
                 and (r.paid_date is null or r.paid_date > lm.month_end)
                then r.due_date
            end) as oldest_unpaid_due_date
    from loan_months lm
    left join repayments r
        on lm.loan_id = r.loan_id
    group by lm.loan_id, lm.month_end

),

measured as (

    select
        lm.*,
        lm.principal_amount - rs.principal_repaid                           as outstanding_amount,
        coalesce(datediff('day', rs.oldest_unpaid_due_date, lm.month_end), 0) as days_past_due
    from loan_months lm
    inner join repayment_state rs
        on  lm.loan_id   = rs.loan_id
        and lm.month_end = rs.month_end

)

select
    {{ dbt_utils.generate_surrogate_key(['m.loan_id', 'm.month_end']) }} as loan_month_key,
    m.loan_id,
    m.month_end,
    m.account_id,
    c.customer_key,
    m.product_code,
    c.risk_rating,
    m.principal_amount,
    m.outstanding_amount,
    m.days_past_due,
    {{ dpd_bucket('m.days_past_due') }}                                  as dpd_bucket,
    m.days_past_due > 90                                                 as is_non_performing,
    case when m.days_past_due > 90 then m.outstanding_amount else 0 end  as non_performing_amount,
    rp.pd,
    rp.lgd,
    round(rp.pd * rp.lgd * m.outstanding_amount, 2)                      as expected_loss
from measured m
-- point-in-time join: the customer version valid at that month end
left join {{ ref('dim_customers') }} c
    on  m.customer_id = c.customer_id
    and m.month_end  >= c.valid_from::date
    and m.month_end  <  c.valid_to::date
left join {{ ref('risk_parameters') }} rp
    on c.risk_rating = rp.risk_rating
