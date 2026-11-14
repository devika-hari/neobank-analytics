with source as (
    select * from {{ source('core_banking', 'gl_accounts') }}
)

select
    gl_account_code,
    gl_account_name,
    account_class,
    normal_balance,
    is_off_balance,
    _loaded_at   as loaded_at
from source