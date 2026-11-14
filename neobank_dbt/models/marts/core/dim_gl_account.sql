--dim_gl_account
-- Grain: one row per GL account

select
    gl_account_code,
    gl_account_name,
    account_class,
    normal_balance,
    is_off_balance
from {{ ref('stg_core_banking__gl_accounts') }}