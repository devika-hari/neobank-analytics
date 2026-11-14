with source as (
    select * from {{ source('core_banking', 'repayments') }}
)

select
    repayment_id,
    loan_id,
    installment_no,
    due_date,
    due_principal,
    due_interest,
    due_amount,
    paid_date,
    paid_amount,
    paid_date is not null   as is_paid,
    _loaded_at              as loaded_at
from source