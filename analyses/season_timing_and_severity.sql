-- Question: for each respiratory season (epi week `finding_season_start_week` through the
-- end of the cycle; calendar year for ETI) and province, how
-- early does the season build up -- the epi week where it hits 50%/90% of its own final
-- case count -- and how far over the endemic corridor's alert ceiling (p75) did it run?
-- Seasonal staffing and vaccination campaigns have to land *before* the 50% week.
-- Answer: per province x season, the epi weeks reaching 50%/90% cumulative share and the
-- excess over p75, top 5 per season ranked by excess **per 100k population** -- raw
-- excess counts favor big provinces just for being big, so the ranking is by rate; the
-- absolute case count stays as a column for sizing the response. Only complete seasons
-- with at least `finding_min_corridor_years` years of corridor history are included.
-- Finding: for ETI in 2025, Jujuy leads (3,315 excess cases/100k), ahead of Catamarca
-- (2,231) and Tucumán (2,038), whose raw excess (35,006 cases) is the largest of the top
-- five. Catamarca is in the top five in 2023, 2024 and 2025, and in the leading provinces
-- 50% of the season's cases arrive by week 22-28, so a campaign meant to precede the peak
-- has to be in place by April-May.

with corridor_seasoned as (

    select
        province_name,
        event_code,
        event_name,
        case when epi_week >= {{ var('finding_season_start_week') }} then year else year - 1 end as season_start_year,
        epi_week,
        case_count,
        population,
        p75_case_count
    from {{ ref('mart_endemic_corridor') }}
    where
        event_code = '{{ var("finding_event_code") }}'
        and n_years_in_corridor >= {{ var('finding_min_corridor_years') }}

),

season_totals as (

    select
        province_name,
        season_start_year,
        sum(case_count) as season_total_cases
    from corridor_seasoned
    group by province_name, season_start_year

),

cumulative as (

    select
        cs.*,
        st.season_total_cases,
        sum(cs.case_count) over (
            partition by cs.province_name, cs.season_start_year
            order by cs.epi_week
            rows between unbounded preceding and current row
        ) as cumulative_cases,
        greatest(cs.case_count - cs.p75_case_count, 0) as excess_over_p75,
        case
            when cs.population > 0
                then greatest(cs.case_count - cs.p75_case_count, 0) / cs.population * 100000
        end as excess_over_p75_per_100k
    from corridor_seasoned cs
    inner join season_totals st
        on cs.province_name = st.province_name and cs.season_start_year = st.season_start_year

),

with_share as (

    select
        *,
        try_divide(cumulative_cases, nullif(season_total_cases, 0)) as cumulative_share
    from cumulative

),

season_summary as (

    select
        province_name,
        season_start_year,
        max(season_total_cases) as season_total_cases,
        min(case when cumulative_share >= 0.5 then epi_week end) as epi_week_reaching_50pct,
        min(case when cumulative_share >= 0.9 then epi_week end) as epi_week_reaching_90pct,
        sum(excess_over_p75) as total_excess_cases_over_corridor,
        sum(excess_over_p75_per_100k) as total_excess_per_100k
    from with_share
    group by province_name, season_start_year

)

select
    province_name,
    season_start_year,
    {{ season_label('season_start_year') }} as season_label,
    season_total_cases,
    epi_week_reaching_50pct,
    epi_week_reaching_90pct,
    total_excess_cases_over_corridor,
    round(total_excess_per_100k, 1) as total_excess_per_100k
from season_summary
where season_total_cases > 0 and season_start_year < {{ first_incomplete_season() }}
qualify row_number() over (partition by season_start_year order by total_excess_per_100k desc) <= 5
order by season_start_year desc, total_excess_per_100k desc
