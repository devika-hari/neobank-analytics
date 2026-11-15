-- Grain: one row per loan account
-- Compares the general ledger (GL 1200) with the loan sub-ledger.
-- Full outer join so that an account missing on either side still shows up.

with ledger as (

    select
        a.account_id,
        sum(p.signed_amount) as ledger_outstanding
    from {{ ref('fct_postings') }} p
    inner join {{ ref('dim_accounts') }} a
        on p.account_key = a.account_key
    where p.gl_account_code = '1200'
    group by a.account_id

),

subledger as (

    select
        l.account_id,
        l.loan_id,
        l.principal_amount
            - coalesce(sum(case when r.is_paid then r.due_principal end), 0) as subledger_outstanding
    from {{ ref('stg_core_banking__loans') }} l
    left join {{ ref('stg_core_banking__repayments') }} r
        on l.loan_id = r.loan_id
    group by l.account_id, l.loan_id, l.principal_amount

)

select
    coalesce(s.account_id, g.account_id)                      as account_id,
    s.loan_id,
    g.ledger_outstanding,
    s.subledger_outstanding,
    coalesce(g.ledger_outstanding, 0) - coalesce(s.subledger_outstanding, 0) as difference,
    case
        when g.account_id is null then 'MISSING_IN_LEDGER'
        when s.account_id is null then 'MISSING_IN_SUBLEDGER'
        when g.ledger_outstanding = s.subledger_outstanding then 'MATCHED'
        else 'AMOUNT_DIFFERS'
    end                                                       as reconciliation_status
from subledger s
full outer join ledger g
    on s.account_id = g.account_id
