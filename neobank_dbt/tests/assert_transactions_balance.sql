-- Singular test: every transaction must net to zero (debits = credits).
-- Returns the transactions that do not. Warn only: Finance decides what to do.
-- store_failures keeps the failing rows in a table for investigation.

{{ config(severity='warn', store_failures=true) }}

select
    transaction_id,
    sum(signed_amount) as net_amount,
    count(*)           as posting_count
from {{ ref('fct_postings') }}
group by transaction_id
having sum(signed_amount) <> 0
