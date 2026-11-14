--dim_date
-- Grain: one row per calendar day

with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2026-01-01' as date)",
        end_date="cast('2027-01-01' as date)"
    ) }}

)

select
    date_day::date                          as date_day,
    year(date_day)                          as year_number,
    month(date_day)                         as month_number,
    to_char(date_day, 'YYYY-MM')            as year_month,
    dayofweekiso(date_day) in (6, 7)        as is_weekend,
    date_day::date = last_day(date_day)     as is_month_end
from spine