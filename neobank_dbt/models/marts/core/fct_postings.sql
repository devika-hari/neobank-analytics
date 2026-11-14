--fct_postings.sql
-- Grain: one row per posting

{{ config(
    materialized='incremental',
    unique_key='posting_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    pre_hook="alter session set timezone = 'UTC'",
    post_hook="{{ log_model_run() }}"
) }}

with postings as (

    select * from {{ ref('stg_core_banking__ledger_postings') }}

    {% if is_incremental() %}
    where loaded_at >= (select coalesce(max(loaded_at), '1900-01-01') from {{ this }})
    {% endif %}

),

accounts as (

    select account_key, account_id, customer_id from {{ ref('dim_accounts') }}

),

customers as (

    select customer_key, customer_id, valid_from, valid_to from {{ ref('dim_customers') }}

)

select
    p.posting_id,
    p.transaction_id,
    coalesce(a.account_key, '-1')   as account_key,
    c.customer_key,                              -- null on bank-side postings
    p.gl_account_code,
    p.booking_date,
    p.value_date,
    p.transaction_type,
    p.direction,
    p.amount,
    p.signed_amount,
    p.currency_code,
    p.loaded_at
from postings p
left join accounts a
    on p.account_id = a.account_id
left join customers c
    on  a.customer_id  = c.customer_id
    and p.booking_date >= c.valid_from::date
    and p.booking_date <  c.valid_to::date