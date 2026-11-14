with source as (
    select * from {{ source('core_banking', 'loans') }}
)

select
    loan_id,
    account_id,
    customer_id,
    product_code,
    principal_amount,
    interest_rate_pct / 100   as interest_rate,
    term_months,
    disbursement_date,
    maturity_date,
    upper(trim(status))       as loan_status,
    updated_at,
    _loaded_at                as loaded_at
from source