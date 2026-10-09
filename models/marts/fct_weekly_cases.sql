{{
  config(
    materialized='incremental',
    unique_key=['department_indec_id', 'event_code', 'age_group_sort_order', 'year', 'epi_week'],
    incremental_strategy='merge',
    on_schema_change='fail'
  )
}}

-- Grain: event x department x age group x epi week x year (not
-- collapsed). Densified via a full cross join of the dimensions: a week
-- with no reported cases for a given department/event/age group gets an explicit
-- `case_count = 0` row here, so a later mart never has to guess whether an absent row
-- means "zero cases" or "not published yet".
--
-- Incremental on a 2-year rolling window: published revisions to this dataset only ever
-- land on the current and prior epidemiological year (see docs/data_profile.md); older
-- years are stable once built, so only the recent window is recomputed and merged on
-- each run instead of rebuilding the full grid every time.
--
-- The grid only pairs each event with the age groups it is actually reported in
-- (Dengue and the respiratory events use different age bands), so the densified zeros
-- never include an age band the source does not have for that event.

with source_agg as (

    select
        department_indec_id,
        event,
        age_group_name,
        age_group_sort_order,
        year,
        epi_week,
        sum(case_count) as case_count
    from {{ ref('int_snvs_weekly_by_event') }}
    {% if is_incremental() %}
        where year >= (select max(year) - 1 from {{ this }})
    {% endif %}
    group by 1, 2, 3, 4, 5, 6

),

observed_event_age as (

    select distinct event, age_group_name
    from {{ ref('int_snvs_weekly_by_event') }}

),

grid as (

    select
        g.department_indec_id,
        e.event_code,
        e.event_name,
        a.age_group_name,
        a.age_group_sort_order,
        w.year,
        w.epi_week,
        w.week_start_date,
        w.week_end_date
    from {{ ref('dim_geography') }} g
    cross join {{ ref('dim_event') }} e
    inner join observed_event_age oea on oea.event = e.event_name
    inner join {{ ref('dim_age_group') }} a on a.age_group_name = oea.age_group_name
    cross join {{ ref('dim_epi_week') }} w
    {% if is_incremental() %}
        where w.year >= (select max(year) - 1 from {{ this }})
    {% endif %}

)

select
    grid.department_indec_id,
    grid.event_code,
    grid.event_name,
    grid.age_group_name,
    grid.age_group_sort_order,
    grid.year,
    grid.epi_week,
    grid.week_start_date,
    grid.week_end_date,
    coalesce(source_agg.case_count, 0) as case_count
from grid
left join source_agg
    on
        grid.department_indec_id = source_agg.department_indec_id
        and grid.event_name = source_agg.event
        and grid.age_group_name = source_agg.age_group_name
        and grid.year = source_agg.year
        and grid.epi_week = source_agg.epi_week
