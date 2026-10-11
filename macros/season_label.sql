{# "2023-2024" for seasons that straddle the year (a season starting after week 1), "2024" for calendar-year seasons. #}
{% macro season_label(column) %}
    {%- if var('finding_season_start_week') == 1 -%}
        cast({{ column }} as string)
    {%- else -%}
        concat({{ column }}, '-', {{ column }} + 1)
    {%- endif -%}
{% endmacro %}
