-- A name containing U+FFFD means a source file was read with the wrong encoding
-- (staging reads every file as UTF-8). Fails with the offending names.
select distinct
    'geo' as kind,
    department_name as value
from {{ ref('stg_respiratory') }}
where department_name like '%�%' or province_name like '%�%'

union all

select distinct
    'age' as kind,
    age_group_desc as value
from {{ ref('stg_respiratory') }}
where age_group_desc like '%�%'
