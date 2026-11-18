{# Custom generic test. Returns the rows that break the rule; zero rows = pass. #}
{% test not_negative(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} < 0

{% endtest %}
