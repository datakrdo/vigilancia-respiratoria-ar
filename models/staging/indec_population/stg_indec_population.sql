{{
  config(
    materialized='view'
  )
}}

-- INDEC population estimates at 1 July of each year (Census 2022 base), by department and
-- sex. The sex split isn't needed downstream (the marts only need total population per
-- department per year), so it's summed away here. `fecha` is just the year, so the
-- publish date is 1 July of that year. `departamento_cod` is the 5-digit INDEC code with
-- the province as its first 2 digits, the same code Georef uses.

with source as (

    select
        jurisdiccion_cod,
        jurisdiccion_nom,
        departamento_cod,
        departamento_nom,
        poblacion,
        fecha,
        _metadata.file_path as _source_file
    from read_files(
        '{{ var("raw_volume_path") }}/indec_population/*.csv',
        format => 'csv',
        header => true,
        schema => 'jurisdiccion_cod STRING, jurisdiccion_nom STRING, departamento_cod STRING, departamento_nom STRING, sexo_cod STRING, poblacion INT, fecha STRING'
    )

)

select
    make_date(cast(fecha as int), 7, 1) as publish_date,
    jurisdiccion_cod as province_id,
    trim(jurisdiccion_nom) as province_name,
    departamento_cod as department_id,
    trim(departamento_nom) as department_name,
    sum(poblacion) as population,
    max(_source_file) as _source_file,
    current_timestamp() as _loaded_at
from source
group by 1, 2, 3, 4, 5
