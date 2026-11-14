--dim_accounts.sql
-- Grain: one row per account, plus one placeholder row for bank-side postings

with accounts as (

    select * from {{ ref('stg_core_banking__accounts') }}

),

products as (

    select * from {{ ref('products') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['a.account_id']) }} as account_key,
    a.account_id,
    a.customer_id,
    a.product_code,
    p.product_name,
    p.product_category,
    a.currency_code,
    a.account_status,
    a.credit_limit,
    a.opened_at::date       as opened_date,
    a.closed_at::date       as closed_date,
    false                   as is_placeholder
from accounts a
left join products p
    on a.product_code = p.product_code

union all

select
    '-1', 'N/A', null, 'N/A', 'Not applicable', 'Not applicable',
    null, 'N/A', null, null, null, true