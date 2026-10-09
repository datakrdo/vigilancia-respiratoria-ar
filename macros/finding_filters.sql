{# First season_start_year that is NOT complete yet, from the latest week with cases of the finding event. #}
{% macro first_incomplete_season() %}
    (
        select
            case
                when {{ var('finding_season_start_week') }} = 1 and latest_week >= 52 then latest_year + 1
                when latest_week >= {{ var('finding_season_start_week') }} then latest_year
                else latest_year - 1
            end
        from (
            select year as latest_year, epi_week as latest_week
            from {{ ref('fct_weekly_cases') }}
            where event_code = '{{ var("finding_event_code") }}' and case_count > 0
            order by year desc, epi_week desc
            limit 1
        )
    )
{% endmacro %}

{# First calendar year whose endemic corridor has at least `finding_min_corridor_years` years of history. #}
{% macro first_reliable_corridor_year() %}
    (
        select min(year)
        from {{ ref('mart_endemic_corridor') }}
        where
            event_code = '{{ var("finding_event_code") }}'
            and n_years_in_corridor >= {{ var('finding_min_corridor_years') }}
    )
{% endmacro %}
