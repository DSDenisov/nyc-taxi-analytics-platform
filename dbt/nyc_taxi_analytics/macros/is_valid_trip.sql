{% macro is_valid_trip() %}
    dropoff_datetime >= pickup_datetime
    and pickup_datetime >= '2020-01-01'
    and pickup_datetime < dateadd(month, 1, current_date())
{% endmacro %}