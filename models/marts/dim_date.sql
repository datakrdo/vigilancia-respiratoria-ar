{{
  config(
    materialized='table'
  )
}}

-- Calendar table at day grain (one row per day, no gaps, from the first to the last date).
-- Each day carries its calendar attributes and the epidemiological week it falls in, so a
-- report can compare against "the same month last year" (calendar) or "the same epi week last year".
--
-- `dim_epi_week` can hold a week 53 that the calendar rule does not produce (the source
-- reports one in some years), and that week overlaps the next year's week 1. A day must
-- belong to one week, so where they overlap the later year wins. Facts still join on
-- `week_start_date`, which stays unique per day.

with days as (

    select
        explode(sequence(week_start_date, week_end_date)) as date_day,
        year as epi_year,
        epi_week,
        week_start_date
    from {{ ref('dim_epi_week') }}

),

one_week_per_day as (

    select date_day, epi_year, epi_week, week_start_date
    from days
    qualify row_number() over (partition by date_day order by epi_year desc, epi_week desc) = 1

)

select
    date_day,
    year(date_day) as year,
    month(date_day) as month_number,
    date_format(date_day, 'yyyy-MM') as year_month,
    cast(date_trunc('month', date_day) as date) as month_start_date,
    quarter(date_day) as quarter_number,
    epi_year,
    epi_week,
    week_start_date,
    cast(date_diff(date_day, week_start_date) as int) as day_of_epi_week
from one_week_per_day
