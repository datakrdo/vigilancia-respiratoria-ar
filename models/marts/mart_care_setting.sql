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
-- Only the latest releases report the split (earlier files carry everything as
-- "Sin especificar"), so a share is only meaningful where `inpatient + outpatient > 0`;
-- the analyses that read this mart filter on it.

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
