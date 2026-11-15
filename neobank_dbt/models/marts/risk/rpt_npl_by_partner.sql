-- Grain: one row per month end per partner
-- The ratio is calculated AFTER summing. Never average a ratio.

select
    f.month_end,
    c.partner_name,
    count(*)                                              as loans,
    sum(f.outstanding_amount)                             as outstanding_amount,
    sum(f.non_performing_amount)                          as non_performing_amount,
    div0(sum(f.non_performing_amount), sum(f.outstanding_amount)) as npl_ratio,
    sum(f.expected_loss)                                  as expected_loss
from {{ ref('fct_loan_monthly') }} f
left join {{ ref('dim_customers') }} c
    on f.customer_key = c.customer_key
group by f.month_end, c.partner_name
