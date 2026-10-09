-- Question: can the outpatient / inpatient split of the respiratory events be used to
-- compare severity across provinces, or does it depend on who reports it?
-- Answer: per event and year, how many of the provinces with notifications report any
-- inpatient case, how many cases carry a known care setting, and the inpatient share
-- among those that do.
-- Finding: bronchiolitis carries the split nationally in 2020-2022 (22-24 provinces
-- report inpatients) and pneumonia only in 2022; from 2023 on a single province (Salta)
-- reports inpatients at all, and the rest file everything as outpatient or "Sin
-- especificar". The national inpatient share collapses from 11.5% (bronchiolitis, 2021)
-- to 0.7% (2023 on) for that reason, not because severity dropped. An inpatient share by
-- province for recent seasons would measure reporting practice, so none is published.

with by_event_year as (

    select
        event_name,
        year,
        count(distinct case when case_count > 0 then province_name end) as provinces_with_cases,
        count(distinct case when care_setting = 'Internado' and case_count > 0 then province_name end)
            as provinces_reporting_inpatients,
        sum(case when care_setting = 'Internado' then case_count else 0 end) as inpatient_cases,
        sum(case when care_setting = 'Ambulatorio' then case_count else 0 end) as outpatient_cases,
        sum(case when care_setting = 'Sin especificar' then case_count else 0 end) as unspecified_cases,
        sum(case_count) as total_cases
    from {{ ref('mart_care_setting') }}
    where event_name <> 'Enfermedad tipo influenza (ETI)'
    group by event_name, year

)

select
    event_name,
    year,
    provinces_with_cases,
    provinces_reporting_inpatients,
    inpatient_cases,
    round(try_divide(total_cases - unspecified_cases, total_cases) * 100, 1) as pct_with_known_setting,
    round(try_divide(inpatient_cases, inpatient_cases + outpatient_cases) * 100, 1) as inpatient_pct_of_known
from by_event_year
where year >= 2020
order by event_name, year
