{{
  config(
    materialized='view'
  )
}}

-- `int_snvs_unified` summed over care setting: event x department x age group x epi week x
-- year. The snapshot tracks this grain (care setting is a split of the same event count,
-- not a separate series), and the fact table reads the same totals.

select
    department_indec_id,
    event,
    event_group,
    age_group_name,
    age_group_sort_order,
    year,
    epi_week,
    sum(case_count) as case_count,
    max(published_date) as published_date
from {{ ref('int_snvs_unified') }}
group by 1, 2, 3, 4, 5, 6, 7
