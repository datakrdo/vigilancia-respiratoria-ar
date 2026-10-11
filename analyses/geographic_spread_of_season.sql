-- Question: do the provinces peak at different times -- does the season travel from a
-- northern focus southward -- or does the whole country peak together? If it travels,
-- southern provinces get an evidence-based lead time before their own peak.
-- Answer: per complete season, the epi week in which each province's case count peaked,
-- with the province's latitude so the site can line them up north to south. The peak is
-- used instead of the first "Brote" week: out of season (summer) the corridor sits so low
-- that a handful of cases flags an "outbreak" in week 1-5, which says nothing about when
-- the real wave arrives. Seasons whose corridor has fewer than `finding_min_corridor_years`
-- years of history are skipped.
-- Finding: no north-to-south travel; the whole country peaks together. In 2023-2025 the
-- median province peaks in epi week 24-25 and 17-23 of the 24 provinces peak within 3 weeks
-- of it (23 in 2024). Only the pandemic-disrupted seasons are scattered (2021-2022: 5 and 2
-- provinces within 3 weeks of the median). Timing looks driven by weather and the
-- circulating virus, not by distance from the north: watch every province at once.

with province_centroid as (

    -- Antártida Argentina (dept 94028) is an uninhabited claim whose centroid
    -- (~lat -82.8) drags Tierra del Fuego's average far past any real town;
    -- excluded so the province centroid reflects where people actually are.
    select
        province_name,
        avg(centroid_lat) as province_lat
    from {{ ref('dim_geography') }}
    where not is_unknown and department_name <> 'Antártida Argentina'
    group by province_name

),

province_peak as (

    select
        province_name,
        case when epi_week >= {{ var('finding_season_start_week') }} then year else year - 1 end as season_start_year,
        max_by(epi_week, case_count) as peak_epi_week
    from {{ ref('mart_endemic_corridor') }}
    where
        event_code = '{{ var("finding_event_code") }}'
        and case_count > 0
        and n_years_in_corridor >= {{ var('finding_min_corridor_years') }}
    group by province_name, case when epi_week >= {{ var('finding_season_start_week') }} then year else year - 1 end

)

select
    pp.season_start_year,
    {{ season_label('pp.season_start_year') }} as season_label,
    pp.province_name,
    pc.province_lat,
    pp.peak_epi_week
from province_peak pp
inner join province_centroid pc on pp.province_name = pc.province_name
where pp.season_start_year < {{ first_incomplete_season() }}
order by pp.season_start_year desc, pc.province_lat desc
