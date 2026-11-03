{{
  config(
    materialized='view'
  )
}}

-- INDEC yearly population per department, keyed by `department_indec_id`. The INDEC
-- estimates use the same 5-digit department code as Georef, so no name matching is
-- needed (unlike the case data, see `int_snvs_unified`). CABA comes by comuna, so every
-- comuna has its own population. A department missing from the estimates (Georef has 529,
-- the estimates 528: 94021) simply has no row here and gets a null rate downstream.

select
    publish_date,
    department_id as department_indec_id,
    population
from {{ ref('stg_indec_population') }}
