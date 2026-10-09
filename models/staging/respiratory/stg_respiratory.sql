{{
  config(
    materialized='view'
  )
}}

-- Acute respiratory infections (IRA, SNVS 2.0) from the same portal and export layout
-- as Dengue, but published as rolling windows: every file covers one to three years and
-- the next one re-publishes the overlap (see docs/data_profile.md). Revisions are kept
-- 1:1 here; `int_snvs_unified` picks the latest per year.
--
-- Every file is a comma-separated UTF-8 CSV with the same 10 columns (the Excel releases
-- are converted by scripts/fetch_data.py, which also repairs the text of the 2021 sheet).
-- Only the header of the year column varies (`anio`/`año`), so the explicit schema is
-- positional. Codes stay strings to keep INDEC zero-padding.

select
    departamento_id as department_id,
    trim(departamento_nombre) as department_name,
    provincia_id as province_id,
    trim(provincia_nombre) as province_name,
    cast(year_raw as int) as year,
    cast(semanas_epidemiologicas as int) as epi_week,
    trim(evento_nombre) as event,
    grupo_edad_id as age_group_id,
    trim(grupo_edad_desc) as age_group_desc,
    cast(cast(cantidad_casos as double) as int) as case_count,
    _metadata.file_path as _source_file,
    _metadata.file_modification_time as _file_modified_at,
    current_timestamp() as _loaded_at
from
    read_files(
        '{{ var("raw_volume_path") }}/respiratory/*.csv',
        format => 'csv',
        header => true,
        encoding => 'UTF-8',
        schema => 'departamento_id STRING, departamento_nombre STRING, provincia_id STRING, provincia_nombre STRING, year_raw STRING, semanas_epidemiologicas STRING, evento_nombre STRING, grupo_edad_id STRING, grupo_edad_desc STRING, cantidad_casos STRING'
    )
where semanas_epidemiologicas is not null
