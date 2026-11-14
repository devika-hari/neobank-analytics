-- stg_core_banking__customers.sql
-- Grain: one row per customer (deduplicated)
-- Each record represents a customer 


/* Deduplicate on customer_id (latest updated_at); 
upper(trim(country)); 
keep null risk_rating */

with source as (

    select * from {{ source('core_banking', 'customers') }}

),

deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by customer_id
        order by updated_at desc
    ) = 1

)

    select
        customer_id, 
        full_name, 
        customer_type, 
        upper(trim(country)) as country, 
        partner_id, 
        risk_rating, 
        kyc_status, 
        created_at, 
        updated_at, 
        _loaded_at
    from deduplicated

