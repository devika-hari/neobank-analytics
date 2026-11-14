with source as (
    select * from {{ source('core_banking', 'accounts') }}
)

select
    account_id,
    customer_id,
    product_code,
    currency              as currency_code,
    upper(trim(status))   as account_status,
    credit_limit,
    opened_at,
    closed_at,
    updated_at,
    _loaded_at            as loaded_at
from source