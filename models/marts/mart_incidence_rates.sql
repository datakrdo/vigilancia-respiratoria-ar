{{
  config(
    materialized='table'
  )
}}

-- Grain: event x department x epi week x year. Age group is summed away
-- here (population is only available totaled, not split by age — see
-- `stg_indec_population`), unlike `fct_weekly_cases`'s finer grain.
--
-- Population denominator: INDEC publishes one estimate per year (at 1 July, from
-- 2022 on — see docs/data_profile.md), so each case year is matched to the estimate
-- whose date is closest to that year's 1 July: an exact match for 2022 onwards, and
-- the earliest (2022) estimate for the years before it (2018-2021) for lack of
-- anything closer — the best available estimate, not a true historical count.
--
-- `dim_geography`'s synthetic "Unknown" members are excluded from the rate
-- entirely: the estimates only cover real departments, and dividing "residence not
-- identified" cases by anything else would produce a meaningless rate. A real
-- department missing from the estimates (94021) also ends up with a null rate.

with weekly_cases as (

    select
        department_indec_id,
        event_code,
        event_name,
        year,
        epi_week,
        week_start_date,
        week_end_date,
        sum(case_count) as case_count
    from {{ ref('fct_weekly_cases') }}
    group by 1, 2, 3, 4, 5, 6, 7

),

case_years as (

    select distinct year from weekly_cases

),

population_cuts as (

    select distinct publish_date from {{ ref('int_department_population') }}

),

year_to_publish_date as (

    select year, publish_date
    from (
        select
            y.year,
            p.publish_date,
            row_number() over (
                partition by y.year
                order by abs(datediff(make_date(y.year, 7, 1), p.publish_date))
            ) as rn
        from case_years y
        cross join population_cuts p
    )
    where rn = 1

),

with_population as (

    select
        w.department_indec_id,
        w.event_code,
        w.event_name,
        w.year,
        w.epi_week,
        w.week_start_date,
        w.week_end_date,
        w.case_count,
        case when geo.is_unknown then null else pop.population end as population
    from weekly_cases w
    left join year_to_publish_date ytp on w.year = ytp.year
    left join {{ ref('dim_geography') }} geo on geo.department_indec_id = w.department_indec_id
    left join {{ ref('int_department_population') }} pop
        on
            pop.department_indec_id = w.department_indec_id
            and pop.publish_date = ytp.publish_date

)

select
    department_indec_id,
    event_code,
    event_name,
    year,
    epi_week,
    week_start_date,
    week_end_date,
    case_count,
    population,
    case when population > 0 then case_count / population * 100000 end as incidence_rate_per_100k,
    sum(case_count) over (
        partition by department_indec_id, event_code, year
        order by epi_week
        rows between unbounded preceding and current row
    ) as cumulative_case_count,
    case
        when population > 0 then
            sum(case_count) over (
                partition by department_indec_id, event_code, year
                order by epi_week
                rows between unbounded preceding and current row
            ) / population * 100000
    end as cumulative_incidence_rate_per_100k,
    lag(case_count) over (
        partition by department_indec_id, event_code, epi_week
        order by year
    ) as prior_year_case_count
from with_population
