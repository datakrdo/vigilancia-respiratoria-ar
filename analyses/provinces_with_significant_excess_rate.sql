-- Question: which provinces have an incidence rate that's materially higher than the rest
-- of the country -- not just numerically higher, which can happen by chance in a small
-- population? Ranking by raw rate alone rewards small provinces with noisy rates; a rate
-- ratio with a confidence interval doesn't.
-- Answer: for the latest complete year, each province's case rate vs. the rest of the
-- country as a rate ratio (RR) with a 95% CI (log-Poisson approximation). Two flags:
-- `is_significantly_elevated` (CI excludes 1) and `is_materially_elevated` (also RR >=
-- `finding_min_rate_ratio`, 1.5). With ~1.2M cases a year the CI is so narrow that a 2%
-- difference is "significant" (Chubut: RR 1.02, CI 1.00-1.03), so the first flag alone
-- says nothing useful at this volume.
-- Uses `mart_endemic_corridor`'s province-level population (not `mart_incidence_rates`'
-- department-level one), because CABA only has a population figure at the province level
-- -- RENAPER publishes it as one citywide row (see `int_province_population`).
-- Finding: for ETI in 2025, 12 of 24 provinces are significantly elevated but only 6 are
-- materially so: Catamarca (RR 4.9), Jujuy (3.9), La Rioja (3.1), Chaco (2.1), Entre Ríos
-- (2.0) and Tucumán (1.7). All are in the north and west; Buenos Aires (RR 0.90) and
-- Córdoba (1.3) carry the most cases but not an unusual burden. Notification practice
-- differs between jurisdictions, so this ranks reporting intensity as much as risk.

with latest_season as (

    -- same "most recent complete year" guard as elsewhere: fct_weekly_cases
    -- densifies the current, still-in-progress year to zero, so a naive
    -- max(year) would silently pick the wrong one.
    select max(year) as year
    from {{ ref('mart_endemic_corridor') }}
    where event_code = '{{ var("finding_event_code") }}' and year < {{ first_incomplete_season() }}

),

by_province as (

    select
        c.province_name,
        sum(c.case_count) as province_cases,
        max(c.population) as province_population
    from {{ ref('mart_endemic_corridor') }} c
    inner join latest_season ly on c.year = ly.year
    where c.event_code = '{{ var("finding_event_code") }}'
    group by c.province_name
    having max(c.population) is not null

),

national as (

    select sum(province_cases) as national_cases, sum(province_population) as national_population
    from by_province

),

-- rate ratio of province vs. everyone else (excluding itself, so a large
-- province can't be compared against a "rest of country" that's mostly itself)
rate_ratio as (

    select
        p.province_name,
        p.province_cases,
        p.province_population,
        round(1e5 * p.province_cases / nullif(p.province_population, 0), 1) as province_rate_per_100k,
        n.national_cases - p.province_cases as rest_of_country_cases,
        n.national_population - p.province_population as rest_of_country_population,
        (p.province_cases / p.province_population)
        / ((n.national_cases - p.province_cases) / nullif(n.national_population - p.province_population, 0))
            as rate_ratio
    from by_province p
    cross join national n

),

-- 95% CI on ln(RR): ln(RR) +/- 1.96 * sqrt(1/a + 1/b), a/b = case counts
-- (standard log-Poisson rate ratio approximation)
with_ci as (

    select
        *,
        1.96 * sqrt(1.0 / nullif(province_cases, 0) + 1.0 / nullif(rest_of_country_cases, 0)) as log_rr_margin,
        exp(
            ln(rate_ratio)
            - 1.96 * sqrt(1.0 / nullif(province_cases, 0) + 1.0 / nullif(rest_of_country_cases, 0))
        ) as rate_ratio_ci_low,
        exp(
            ln(rate_ratio)
            + 1.96 * sqrt(1.0 / nullif(province_cases, 0) + 1.0 / nullif(rest_of_country_cases, 0))
        ) as rate_ratio_ci_high
    from rate_ratio
    where province_cases > 0

)

select
    province_name,
    province_rate_per_100k,
    round(rate_ratio, 2) as rate_ratio_vs_rest_of_country,
    round(rate_ratio_ci_low, 2) as ci95_low,
    round(rate_ratio_ci_high, 2) as ci95_high,
    rate_ratio_ci_low > 1 as is_significantly_elevated,
    rate_ratio_ci_low > 1 and rate_ratio >= {{ var('finding_min_rate_ratio') }} as is_materially_elevated
from with_ci
order by rate_ratio_vs_rest_of_country desc
