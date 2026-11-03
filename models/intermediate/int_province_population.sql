{{
  config(
    materialized='view'
  )
}}

-- Same population, aggregated one level up: province x publish_date, for marts that
-- only need a province-level denominator (`mart_endemic_corridor`, `mart_outbreaks`).
-- Every department id starts with its 2-digit province code (INDEC convention,
-- verified: no department's id disagrees with its Georef province), so the province
-- is always just the first 2 characters of the department id -- no join needed.

select
    left(department_indec_id, 2) as province_indec_id,
    publish_date,
    sum(population) as population
from {{ ref('int_department_population') }}
group by left(department_indec_id, 2), publish_date
