{{
  config(
    materialized='table'
  )
}}

-- Grain: event x province x care setting x epi week x year. The care-setting split
-- (outpatient / inpatient / unspecified) of each respiratory event, which the corridor
-- and the fact table sum away. Inpatient cases are the severity signal: the share of an
-- event that ends up hospitalized.
--
-- The split was only reported nationwide in 2020-2022; from 2023 on only Salta reports
-- inpatients and the rest file everything as outpatient or "Sin especificar" (see
-- `analyses/inpatient_reporting_coverage.sql`). A share is only meaningful where
-- `inpatient + outpatient > 0`, and not comparable across provinces in recent years.

select
    g.province_indec_id,
    g.province_name,
    u.event as event_name,
    u.care_setting,
    u.year,
    u.epi_week,
    sum(u.case_count) as case_count
from {{ ref('int_snvs_unified') }} u
inner join {{ ref('dim_geography') }} g on g.department_indec_id = u.department_indec_id
where u.event_group = 'respiratory' and not g.is_unknown
group by 1, 2, 3, 4, 5, 6
