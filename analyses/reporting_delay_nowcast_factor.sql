-- Question: for a week that was just published, how much should its case
-- count be corrected upward to estimate what it'll eventually settle at, as a
-- function of how long ago it was first published? A bulletin written from
-- the freshest data needs a nowcast factor, not a face-value read.
-- Answer: for every period, the reporting lag (days from that epi week's end
-- to its first publication) bucketed, with the median and p90 correction
-- factor (latest known count / first published count) observed in each
-- bucket.
-- Finding: for ETI, 69,841 periods changed after first publication -- far more than for
-- Dengue -- and the correction is large for the fresh ones: the median factor is 3.5x for
-- periods first published within 7 days of the week's end (p90 15.9x, only 826 periods),
-- 2.0x for 8-30 days (p90 5.5x), 1.5x for 31-90 days and 1.3x beyond 90 days. Counts for
-- the latest weeks must be read as a floor, and a nowcast correction by lag bucket is
-- worth applying to a bulletin written from the freshest data. These factors are computed
-- on revised periods only, so they overstate the typical correction of an average week.

with first_publication as (

    select department_indec_id, event, age_group_name, year, epi_week, published_date, case_count as first_published_case_count
    from {{ ref('mart_revisions') }}
    where revision_number = 1

),

latest_publication as (

    select department_indec_id, event, age_group_name, year, epi_week, case_count as latest_case_count
    from {{ ref('mart_revisions') }}
    where is_latest_revision

),

combined as (

    select
        f.first_published_case_count,
        l.latest_case_count,
        datediff(f.published_date, w.week_end_date) as reporting_lag_days
    from first_publication f
    inner join latest_publication l
        on
            f.department_indec_id = l.department_indec_id
            and f.event = l.event
            and f.age_group_name = l.age_group_name
            and f.year = l.year
            and f.epi_week = l.epi_week
    inner join {{ ref('dim_epi_week') }} w on w.year = f.year and w.epi_week = f.epi_week
    where f.first_published_case_count is not null and f.first_published_case_count <> l.latest_case_count

),

bucketed as (

    select
        *,
        case
            when reporting_lag_days <= 7 then '0-7 days'
            when reporting_lag_days <= 30 then '8-30 days'
            when reporting_lag_days <= 90 then '31-90 days'
            else '90+ days'
        end as reporting_lag_bucket,
        try_divide(latest_case_count, nullif(first_published_case_count, 0)) as nowcast_correction_factor
    from combined

)

select
    reporting_lag_bucket,
    count(*) as n_periods,
    round(avg(reporting_lag_days), 0) as avg_reporting_lag_days,
    round(percentile_cont(0.5) within group (order by nowcast_correction_factor), 2) as median_correction_factor,
    round(percentile_cont(0.9) within group (order by nowcast_correction_factor), 2) as p90_correction_factor
from bucketed
group by reporting_lag_bucket
order by avg_reporting_lag_days
