{# Called from on-run-end. `results` holds the outcome of every node in the run. #}
{% macro log_run_summary(results) %}
    {% if execute %}
        {% set failed = results | selectattr('status', 'in', ['error', 'fail']) | list %}
        {{ log("Run summary: " ~ (results | length) ~ " nodes, " ~ (failed | length) ~ " failed", info=True) }}
        {% for r in failed %}
            {{ log("  FAILED " ~ r.node.name ~ ": " ~ r.message, info=True) }}
        {% endfor %}
    {% endif %}
{% endmacro %}
