-- dim_customers.sql
-- Grain: one row per customer version (SCD Type 2)

with snapshot as (

    select * from {{ ref('snap_customers') }}

),

partners as (

    select * from {{ ref('partners') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['s.customer_id', 's.dbt_valid_from']) }}   as customer_key,   -- must identify unique version
    s.customer_id,
    s.full_name,
    s.customer_type,
    s.country                                            as country_code,
    s.partner_id,
    p.partner_name,
    p.partner_segment,
    coalesce(s.risk_rating, 'Unrated')                      as risk_rating,    
    s.kyc_status,
    s.created_at,
    case
        when row_number() over (
            partition by s.customer_id order by s.dbt_valid_from
        ) = 1
        then '1900-01-01'::timestamp
        else s.dbt_valid_from
    end                                     as valid_from,

    --s.dbt_valid_from                                     as valid_from,
    s.dbt_valid_to                                       as valid_to,
    s.dbt_valid_to::date = '9999-12-31'             as is_current    
from snapshot s
left join partners p
    on s.partner_id = p.partner_id