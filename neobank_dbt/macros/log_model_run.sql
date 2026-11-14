{% macro log_model_run() %}
    insert into {{ target.database }}.{{ target.schema }}_audit.model_run_log
    select
        '{{ this.name }}',
        count(*),
        '{{ run_started_at.strftime("%Y-%m-%d %H:%M:%S") }}',
        '{{ invocation_id }}'
    from {{ this }}
{% endmacro %}