{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=[
      'department_indec_id', 'event', 'care_setting', 'age_group_name',
      'year', 'epi_week', 'published_date', '_source_file'
    ],
    on_schema_change='fail'
  )
}}


-- Every published revision of the SNVS 2.0 acute respiratory infections dataset, fully
-- resolved (geography, age group, event), at grain: event x care setting x department x
-- age group x epi week x year x published_date. `int_snvs_unified` picks the single canonical (latest)
-- revision per year from this model; `mart_revisions` uses every revision, since
-- that's the whole point of it — see `snap_snvs_weekly`.
--
-- Departments are matched by normalized department + province name against the Georef
-- seed, not by composite code: the source's `id_depto_indec_residencia` looks like
-- an INDEC code but ISN'T Georef's own department code (e.g. source "015" for CABA
-- "Comuna 15" vs Georef's real "02105" for the same comuna, confirmed by inspection) —
-- composite-code matching silently produced wrong department assignments. Unmatched department names fall
-- back to "Unknown department in this province"; unmatched province names fall back to
-- fully "Unknown" (see docs/data_profile.md).
--
-- `age_group_id` isn't a stable key across source files either (same id maps to
-- different age buckets in different years), so the canonical `age_group_name` is
-- resolved here too, via the `age_group_buckets` seed keyed on normalized free-text
-- description rather than the id.
--
-- Events are resolved through the `event_map` seed (keyed on the normalized source
-- string) into a canonical `event` name, an `event_group` and a `care_setting`: the
-- dataset splits each event into outpatient / inpatient / unspecified rows
-- (and renamed them over time), so the corridor works on the family total while the
-- hospitalization share is still available. Any event not in the seed stays null and fails the `not_null` test.
--
-- Files are rolling windows named `...-hasta-YYYYMMDD`; that date is the
-- publication date (the one undated file is the 2021-03-29 cut).
--
-- Incremental by source file: the first run (or `--full-refresh`) resolves every file; later
-- runs only resolve files whose modification time is newer than the latest already loaded,
-- merging on the grain + `_source_file` so a re-published file replaces its own rows.
--
-- Grouped and summed at the end on the *resolved* key (department_indec_id,
-- age_group_name), not the raw one: distinct raw `age_group_desc` strings that
-- resolve to the same canonical bucket (encoding/wording variants, see
-- docs/data_profile.md) would otherwise surface as separate rows for the same
-- period/publication — `mart_revisions` needs exactly one row per period per
-- publication to compare revisions meaningfully, or its revision-over-revision diff
-- ends up comparing unrelated raw rows instead of the same real-world count.

with unioned as (

    select
        department_id,
        department_name,
        province_id,
        province_name,
        year,
        epi_week,
        event,
        age_group_id,
        age_group_desc,
        case_count,
        _source_file,
        _file_modified_at,
        _loaded_at
    from {{ ref('stg_respiratory') }}

),

with_published_date as (

    select
        *,
        coalesce(
            try_to_date(nullif(regexp_extract(_source_file, 'hasta-(\\d{8})', 1), ''), 'yyyyMMdd'),
            date('2021-03-29')
        ) as published_date
    from unioned
    {% if is_incremental() %}
        -- only files that appeared or were replaced since the last run; a corrected
        -- file keeps its name, gets a newer modification time, and its rows are merged over
        where _file_modified_at > (select max(_file_modified_at) from {{ this }})
    {% endif %}

),

georef as (

    select distinct
        department_indec_id,
        {{ normalize_geo_name('department_name') }} as department_name_norm,
        province_indec_id,
        {{ normalize_geo_name('province_name') }} as province_name_norm
    from {{ ref('georef_departments') }}

),

georef_provinces as (

    select distinct province_indec_id, province_name_norm
    from georef

),

event_map as (

    select event_desc_norm, event_name, event_group, care_setting
    from {{ ref('event_map') }}

),

age_buckets as (

    select desc_norm, age_group_name, age_group_sort_order
    from {{ ref('age_group_buckets') }}

),

geo_matched as (

    select
        u.*,
        dept_match.department_indec_id as matched_department_id,
        prov_match.province_indec_id as matched_province_id,
        bucket.age_group_name,
        bucket.age_group_sort_order,
        ev.event_name,
        ev.event_group,
        ev.care_setting
    from with_published_date u
    left join georef_provinces prov_match
        on (
            {{ normalize_geo_name('u.province_name') }} = prov_match.province_name_norm
            or prov_match.province_name_norm like concat({{ normalize_geo_name('u.province_name') }}, '%')
            or ({{ normalize_geo_name('u.province_name') }} = 'CABA' and prov_match.province_name_norm like 'CIUDAD AUTONOMA%')
        )
    left join georef dept_match
        on
            dept_match.province_indec_id = prov_match.province_indec_id
            and dept_match.department_name_norm = {{ normalize_geo_name('u.department_name') }}
    left join event_map ev
        on ev.event_desc_norm = {{ normalize_age_desc('u.event') }}
    left join age_buckets bucket
        on bucket.desc_norm = {{ normalize_age_desc('u.age_group_desc') }}

),

resolved as (

    select
        case
            when matched_department_id is not null then matched_department_id
            when matched_province_id is not null then concat(matched_province_id, '999')
            else '99999'
        end as department_indec_id,
        year,
        epi_week,
        event_name as event,
        event_group,
        care_setting,
        coalesce(age_group_name, 'Sin especificar') as age_group_name,
        coalesce(age_group_sort_order, 999) as age_group_sort_order,
        case_count,
        published_date,
        _source_file,
        _file_modified_at,
        _loaded_at
    from geo_matched

)

select
    department_indec_id,
    year,
    epi_week,
    event,
    event_group,
    care_setting,
    age_group_name,
    age_group_sort_order,
    coalesce(sum(case_count), 0) as case_count,
    published_date,
    _source_file,
    max(_file_modified_at) as _file_modified_at,
    max(_loaded_at) as _loaded_at
from resolved
group by 1, 2, 3, 4, 5, 6, 7, 8, 10, 11
