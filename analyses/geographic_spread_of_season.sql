-- Question: does each season spread geographically from a northern focus southward, and
-- how fast (weeks per degree of latitude)? If the spread is measurable and consistent,
-- southern provinces get an evidence-based lead time before their own season starts.
-- Answer: per complete season, each province's first "Brote" epi week vs. its distance
-- (haversine, km) from that season's earliest-affected province, plus the fitted
-- weeks-per-degree-latitude slope and its R^2. Seasons whose corridor has fewer than
-- `finding_min_corridor_years` years of history are skipped (with a partial baseline
-- almost every province is in "Brote" in week 1 and the fit is degenerate).
-- Finding: the "spreads north to south" hypothesis doesn't hold -- R^2 is 0.14 or less in
-- every season (0.04 or less in 2022-2025, with slopes between -0.03 and 0.22 weeks per
-- degree), so a latitude-based early-warning rule for southern provinces isn't supported
-- by this data. Useful negative result: respiratory outbreaks start almost simultaneously
-- across the country (17-24 provinces enter "Brote" each season), so timing looks driven
-- by weather and circulating viruses rather than by distance from the north.

with province_centroid as (

    -- Antártida Argentina (dept 94028) is an uninhabited claim whose centroid
    -- (~lat -82.8) drags Tierra del Fuego's average far past any real town;
    -- excluded so the province centroid reflects where people actually are.
    select
        province_name,
        avg(centroid_lat) as province_lat,
        avg(centroid_lon) as province_lon
    from {{ ref('dim_geography') }}
    where not is_unknown and department_name <> 'Antártida Argentina'
    group by province_name

),

first_outbreak_week as (

    select
        province_name,
        case when epi_week >= {{ var('finding_season_start_week') }} then year else year - 1 end as season_start_year,
        min(epi_week) as first_brote_epi_week
    from {{ ref('mart_endemic_corridor') }}
    where
        event_code = '{{ var("finding_event_code") }}'
        and corridor_zone = 'Brote'
        and n_years_in_corridor >= {{ var('finding_min_corridor_years') }}
    group by province_name, case when epi_week >= {{ var('finding_season_start_week') }} then year else year - 1 end

),

-- One origin province per season, tie-broken deterministically by name so a
-- multi-way tie for earliest week can't fan the join out below.
season_origin as (

    select season_start_year, province_name as origin_province_name, first_brote_epi_week as origin_epi_week
    from first_outbreak_week
    qualify row_number() over (
        partition by season_start_year
        order by first_brote_epi_week, province_name
    ) = 1

),

spread as (

    select
        f.province_name,
        f.season_start_year,
        f.first_brote_epi_week,
        f.first_brote_epi_week - o.origin_epi_week as weeks_after_season_origin,
        pc.province_lat,
        -- haversine distance (km) from this province's centroid to the centroid
        -- of the earliest-affected province that same season
        6371 * acos(least(1.0, greatest(
            -1.0,
            sin(radians(pc.province_lat)) * sin(radians(origin_pc.province_lat))
            + cos(radians(pc.province_lat)) * cos(radians(origin_pc.province_lat))
            * cos(radians(pc.province_lon - origin_pc.province_lon))
        ))) as km_from_season_origin
    from first_outbreak_week f
    inner join season_origin o on f.season_start_year = o.season_start_year
    inner join province_centroid pc on f.province_name = pc.province_name
    inner join province_centroid origin_pc on o.origin_province_name = origin_pc.province_name

)

select
    season_start_year,
    {{ season_label('season_start_year') }} as season_label,
    count(*) as provinces_reaching_outbreak,
    round(regr_slope(weeks_after_season_origin, province_lat), 2) as weeks_per_degree_latitude,
    round(regr_r2(weeks_after_season_origin, province_lat), 2) as fit_r2,
    round(regr_slope(weeks_after_season_origin, km_from_season_origin) * 100, 2) as weeks_per_100km
from spread
group by season_start_year
having count(*) >= 3 and season_start_year < {{ first_incomplete_season() }}
order by season_start_year desc
