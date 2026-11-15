{# Turns a days-past-due number into a reporting bucket.
   One definition, reused by every model that needs it. #}
{% macro dpd_bucket(days_column) %}
    case
        when {{ days_column }} <= 0  then '0 current'
        when {{ days_column }} <= 30 then '1-30'
        when {{ days_column }} <= 60 then '31-60'
        when {{ days_column }} <= 90 then '61-90'
        else '90+'
    end
{% endmacro %}
