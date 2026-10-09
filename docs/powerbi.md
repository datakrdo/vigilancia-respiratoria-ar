# Power BI report

A composite semantic model over the dbt marts, with row- and object-level security.
Built in Power BI Desktop (free) and versioned as a PBIP project (text/TMDL) in
`powerbi/`. It is not published to the Power BI service: a free account can't use
*Publish to web* with DirectQuery (Microsoft documents that limit), and an open
DirectQuery endpoint would wake the serverless warehouse on every visit. The public,
always-on view is the [static site](https://datakrdo.github.io/vigilancia-respiratoria-ar/); this report
is the analyst-facing one.

## Connection

*Get data → Databricks* with the Free Edition SQL warehouse (Server hostname and HTTP
path from *SQL Warehouses → Connection details*), personal access token. Catalog
`workspace`, schema `dev_vigilancia_respiratoria_ar_marts`. Never commit credentials: the PBIP stores
the server and path, not the token; check `*.pbi*/` and `definition/` before pushing.

## Why composite, and which table is which

| Table | Storage | Role |
|---|---|---|
| `fct_weekly_cases` | **DirectQuery** | Detail: event × department × age group × week. Only hit when a visual needs the age breakdown. |
| `mart_incidence_rates` | Import (hidden) | **User-defined aggregation** of `fct_weekly_cases` at department × event × week × year (it is exactly the fact summed over age group). |
| `mart_endemic_corridor`, `mart_outbreaks` | Import | Province-grain, small. |
| `mart_revisions` | Import | Data-quality page; hidden from the press role. |
| `dim_geography`, `dim_province`, `dim_epi_week`, `dim_event`, `dim_age_group` | **Dual** | Answer from memory when the query hits the aggregation, from the source when it hits the detail table. |
| `dim_user_access` | Import | Drives RLS. |

*Manage aggregations* on `mart_incidence_rates`: `case_count` → Sum → `fct_weekly_cases[case_count]`;
`department_indec_id`, `event_code`, `year`, `epi_week` → GroupBy → the same columns of
the fact. A visual by department, province, week or event is served from the imported
aggregate; a visual by age group falls through to DirectQuery. Confirm it with
*Performance analyzer* (DirectQuery duration should be absent for the first kind) and keep
a screenshot in `docs/img/`.

## Relationships (single direction, dimension → fact)

`dim_geography[department_indec_id]` → `fct_weekly_cases`, `mart_incidence_rates` ·
`dim_province[province_indec_id]` → `dim_geography`, `mart_endemic_corridor`, `mart_outbreaks`,
`dim_user_access` · `dim_epi_week[year, epi_week]` → fact, rates, corridor (create a key
column `year*100+epi_week` on both sides, since Power BI joins on one column) ·
`dim_event[event_code]` → fact, rates, corridor, outbreaks · `dim_age_group[age_group_name]` → `fct_weekly_cases`.
`dim_user_access` filters nothing by relationship: the role expression reads it.

## Measures

```dax
Cases = SUM ( mart_incidence_rates[case_count] )

-- A rate is sum(cases) / sum(population), never an average of rates.
-- Population repeats on every week row, so take one value per department.
Population =
SUMX ( VALUES ( dim_geography[department_indec_id] ),
       CALCULATE ( MAX ( mart_incidence_rates[population] ) ) )

Cases with population =
CALCULATE ( [Cases], NOT ISBLANK ( mart_incidence_rates[population] ) )

Rate per 100k = DIVIDE ( [Cases with population], [Population] ) * 100000

Excess over p75 =
SUMX ( mart_endemic_corridor,
       MAX ( 0, mart_endemic_corridor[case_count] - mart_endemic_corridor[p75_case_count] ) )

Provinces in outbreak =
CALCULATE ( DISTINCTCOUNT ( mart_endemic_corridor[province_indec_id] ),
            mart_endemic_corridor[corridor_zone] = "Brote" )
```

Excluding cases without a population from the numerator keeps CABA's comunas (whose
population RENAPER only publishes citywide) from inflating the rate.

## Calendar table and time intelligence

`dim_date` (one row per day, no gaps, built in dbt) is the model's date table: mark it with
*Table tools → Mark as date table* on `date_day`, and relate `fct_weekly_cases[week_start_date]`
→ `dim_date[date_day]` (Dual mode). Each fact row sits on the Sunday that starts its epi week, so
calendar functions work over real dates, and `dim_date` also carries `epi_year` / `epi_week` for
epi-week logic. The year-over-year KPIs of the public site exist here in both flavors:

```dax
Cases PY = CALCULATE ( [Cases], SAMEPERIODLASTYEAR ( dim_date[date_day] ) )

Cases YoY % = DIVIDE ( [Cases] - [Cases PY], [Cases PY] )

-- Same epi week, last epi year: aligned on the epi calendar, not on 365 days.
Cases PY (epi week) =
VAR wk = MAX ( dim_date[epi_week] )
VAR yr = MAX ( dim_date[epi_year] ) - 1
RETURN CALCULATE ( [Cases], REMOVEFILTERS ( dim_date ), dim_date[epi_year] = yr, dim_date[epi_week] = wk )

-- The last two weeks of a running year are always incomplete (late notification): compare
-- against the last consolidated week, as the site does.
Last data week =
CALCULATE ( MAX ( dim_date[week_start_date] ), REMOVEFILTERS ( dim_date ), fct_weekly_cases[case_count] > 0 )

Reference week = [Last data week] - 14

Cases (reference week) =
CALCULATE ( [Cases], REMOVEFILTERS ( dim_date ), dim_date[week_start_date] = [Reference week] )

Cases (reference week, PY) =
CALCULATE ( [Cases (reference week)], SAMEPERIODLASTYEAR ( dim_date[date_day] ) )

Cases last 4 weeks =
CALCULATE ( [Cases], REMOVEFILTERS ( dim_date ),
            DATESBETWEEN ( dim_date[date_day], [Reference week] - 21, [Reference week] + 6 ) )

Cases last 4 weeks PY =
CALCULATE ( [Cases last 4 weeks], DATEADD ( dim_date[date_day], -52 * 7, DAY ) )

-- "Same month last year" is what the epi weeks cannot give: the calendar month is the
-- reason `dim_date` has `year_month`.
Cases same month PY = CALCULATE ( [Cases], DATEADD ( dim_date[date_day], -1, YEAR ) )
```

Notes: `DATEADD(..., -52 * 7, DAY)` shifts exactly 52 weeks, so the same four epi weeks line up
(a year's week 53 only exists in some years, and this is why the comparison stops at week 52).
`SAMEPERIODLASTYEAR` shifts by calendar year and can slide by a few days against the epi week; the
`(epi week)` measure is the one that stays aligned. These DAX measures were written against the
model above and have not been run in Desktop yet.

## Security

Three roles, mutually exclusive (a member of several roles that include OLS gets an error):

| Role | Type | Effect |
|---|---|---|
| `Nacional` | none | Everything. |
| `Provincial` | **RLS**, dynamic | `USERPRINCIPALNAME()` looked up in `dim_user_access` (seed `rls_province_access`, fictitious users); filters `dim_province` and `dim_geography`. |
| `PrensaPublico` | **OLS** | Hides `dim_age_group`, `mart_revisions` and the age columns of the fact: statistical disclosure control. |

Desktop has no UI for OLS, so the roles are TMDL files: copy `powerbi/roles/*.tmdl` into
`<report>.SemanticModel/definition/roles/` and reopen the project. Test with *Modeling →
View as*: `Provincial` + other user `referente.cordoba@example.org` (only Córdoba),
`coordinacion.noa@example.org` (Salta, Tucumán, Jujuy), and `PrensaPublico` (no age field
in the field list). Save a screenshot of each in `docs/img/`.

Honest limit: in a real deployment the user map would come from the identity provider, and
dynamic RLS needs the model in the service (here it is only exercised in Desktop).

## Pages

1. **Current situation**: KPI cards (cases, rate, provinces in outbreak, plus the year-over-year cards: reference week and last four weeks against the same period last year), rate by department map, province ranking.
2. **Endemic corridor**: p25/p50/p75 bands and the season's cases, slicers for province, event and year.
3. **Outbreaks and data quality**: outbreak table (duration, attack rate), size of later revisions from `mart_revisions`.

Palette and chart choices follow the site (blue sequential ramp, red reserved for outbreak).
Export a PDF to `docs/` and screenshots to `docs/img/` for the README.
