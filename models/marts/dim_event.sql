{{
  config(
    materialized='table'
  )
}}

-- One row per canonical event, straight from the `event_map` seed (the source spells the
-- respiratory events several ways over time and splits them by care setting, so the
-- distinct-from-data shortcut no longer holds). Care setting is not part of the key: the
-- corridor works on the family total.

select distinct
    event_name,
    event_code,
    event_group
from {{ ref('event_map') }}
