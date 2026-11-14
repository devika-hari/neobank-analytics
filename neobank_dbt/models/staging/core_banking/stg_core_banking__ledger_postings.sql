-- stg_core_banking__ledger_postings.sql
-- Grain: one row per posting (deduplicated)
-- Each record represents a transaction - posting event


/* Deduplicate on posting_id (latest _loaded_at); 
normalise direction; 
amount_cents / 100 as amount; 
cast booking_date and value_date to date; 
add signed_amount */

with source as (

    select * from {{ source('core_banking', 'ledger_postings') }}

),

deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by posting_id
        order by _loaded_at desc
    ) = 1

),

cleaned as (

    select
        posting_id,
        transaction_id,
        account_id,
        gl_account_code,
        case upper(left(trim(direction), 1))
            when 'D' then 'DEBIT'
            when 'C' then 'CREDIT'
        end                                    as direction,
        (amount_cents / 100)::number(18,2)     as amount,
        currency                               as currency_code,
        try_to_date(booking_date)              as booking_date,
        try_to_date(value_date)                as value_date,
        transaction_type,
        description,
        _loaded_at                             as loaded_at
    from deduplicated

)

select
    *,
    case direction
        when 'DEBIT'  then amount
        when 'CREDIT' then -amount
    end as signed_amount
from cleaned