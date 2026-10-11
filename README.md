🇬🇧 [English](README.md) · 🇪🇸 [Español](README_es.md)

# vigilancia-respiratoria-ar 🫁

Analytics engineering on epidemiological surveillance in Argentina (SNVS 2.0, Ministry of
Health): acute respiratory infections (influenza-like illness, bronchiolitis, pneumonia; about
1.3 M notifications a year) built with **dbt-databricks** on Databricks Free
Edition (Unity Catalog, serverless SQL warehouse). Built for public-health teams: the
SQL layer feeds a public site and weekly self-updating data.

Sources: [respiratory infections](https://datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas) (CC-BY 4.0). Full data profile, overlapping releases and the quality issues found:
[`docs/data_profile.md`](docs/data_profile.md).

## See it 👀

- **[Public site](https://datakrdo.github.io/vigilancia-respiratoria-ar/)** (Observable Framework, Spanish and English): cases and rate by department, interactive endemic corridor per province, outbreaks, and the six findings below in plain language.
- **[dbt docs](https://datakrdo.github.io/vigilancia-respiratoria-ar/dbt/)**: full lineage, column docs and tests.

Both sites rebuild by themselves when the source publishes new data (see *Automatic updates*).

## Read this before using the numbers ⚠️

- Cases are assigned to the department of **residence**, not where the infection happened.
- The most recent weeks are **incomplete** (late notification); see the nowcast finding.
- CABA's population is only published citywide, so its comunas have no rate.
- Notification is uneven across jurisdictions: Santa Fe reports 52 ETI cases per 100k in 2025 (322 in 2019), CABA 240 (815 in 2019), Córdoba 3,379. A low rate can mean little reporting, not little disease.
- The current year is partial, and 2020-2021 (COVID) distort the 5-year baseline of the endemic corridor for the years that follow.
- Rates built on fewer than 20 cases are unstable; the site shows them faded.
- The public site shows only department/province aggregates, never age breakdowns (small counts could identify people).

## Architecture (medallion) 🏗️

```
seeds/                  georef_departments, age_group_buckets, event_map (crosswalks)
sources (Volume CSVs) ──read_files()──► staging/
  stg_respiratory               (IRA 2018+, rolling-window releases)
  stg_renaper_population        (RENAPER identified population by department)
        │
        ▼
intermediate/
  int_snvs_all_revisions  every publication of every period, incremental by source file (mart_revisions' grain)
  int_snvs_unified        one canonical row per period (latest revision)
  int_renaper_population
        │
        ▼
snapshots/
  snap_snvs_weekly        weekly SCD2 over int_snvs_weekly_by_event
        │
        ▼
marts/
  dim_geography, dim_province, dim_age_group, dim_event, dim_epi_week, dim_date
  fct_weekly_cases        event x department x age group x epi week x year (densified)
  mart_incidence_rates    rate per 100k, cumulative-within-year, year-over-year comparison
  mart_endemic_corridor   endemic corridor (25th/50th/75th percentiles of the 5 prior years)
  mart_outbreaks          outbreak episodes (gaps & islands over the corridor)
  mart_care_setting       outpatient / inpatient split of respiratory events (only reported nationwide in 2020-2022)
  mart_revisions          how much an already-published figure changes on later revisions
```

Every mart (`dim_*`, `fct_*`, `mart_*`) has `contract: enforced: true`.

## Running it 🚀

```bash
uv sync --group ingest
cp profiles.yml.example ~/.dbt/profiles.yml   # fill in host/http_path, log in via `databricks auth login`
uv run python scripts/fetch_data.py --upload /Volumes/workspace/bronze/raw_data   # download + sync to the Volume
dbt deps
dbt build        # models, seeds, snapshot, tests and unit tests
```

The Volume path is the `raw_volume_path` var in `dbt_project.yml`.

Lint (Databricks dialect, dbt templater):

```bash
sqlfluff lint models/ analyses/ tests/
```

## Automatic updates 🔄

The source publishes irregularly (from a week to several months apart), so CI
(`.github/workflows/ci.yml`) checks **every Monday**: `scripts/fetch_data.py`
downloads the files, uploads only the new or changed ones to the Volume, and only then runs
`dbt build` (which also records revisions in the snapshot). The load is incremental: `int_snvs_all_revisions` only resolves files that are new or were replaced since the last run (`dbt build --full-refresh` rebuilds everything), regenerates the dbt docs and
redeploys the site to GitHub Pages. Nothing new → nothing rebuilt. On pull requests it runs
`sqlfluff lint` and `dbt parse` with a dummy profile (no secrets). Needs the repo secrets
`DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DATABRICKS_TOKEN`.

## Findings (`analyses/`) 🔍

- [`season_timing_and_severity.sql`](analyses/season_timing_and_severity.sql) —
  per province and season, the week reaching 50%/90% of
  that season's cases and total excess over the endemic corridor's p75 ceiling, ranked
  by excess **per 100k population** so big provinces don't top the list just for being
  big. In 2025, Jujuy (3,315 excess cases/100k), Catamarca (2,231) and Tucumán (2,038)
  lead; 50% of the season's cases arrive by week 22-28, so campaigns have to land by
  April-May.
- [`geographic_spread_of_season.sql`](analyses/geographic_spread_of_season.sql) —
  checks whether each season travels north to south by comparing the epi week in which each
  province peaks. Finding: it doesn't — in 2023-2025 the median province peaks in week
  24-25 and 17-23 of 24 provinces peak within 3 weeks of it — a useful negative result.
- [`outbreak_early_warning_lead_time.sql`](analyses/outbreak_early_warning_lead_time.sql) —
  scores a rolling case-growth threshold as an early-warning signal for outbreak onset.
  Recall is about 20% (105/528 outbreaks) and precision about 35%, but the outbreaks it
  does catch get a median 6-week lead time — worth a review flag, not a stand-alone alert.
- [`hotspot_concentration_and_persistence.sql`](analyses/hotspot_concentration_and_persistence.sql) —
  Pareto/Gini concentration of cases across departments, a population-weighted Gini
  (Lorenz curve by rate, not raw cases) to separate risk concentration from where people
  live, plus season-to-season Jaccard overlap of the top decile by rate. ETI is concentrated (17-28% of departments hold 80% of a
  season's cases, raw Gini 0.70-0.80) and partly persistent (top-decile Jaccard 0.45-0.66).
  The population-weighted Gini runs lower every season (2025: 0.58 vs. 0.74 raw), showing
  part of the raw concentration is just population, not risk.
- [`provinces_with_significant_excess_rate.sql`](analyses/provinces_with_significant_excess_rate.sql) —
  rate ratio vs. the rest of the country with a 95% log-Poisson CI, to separate a real
  excess from a small-population fluke. Uses province-level population so CABA (whose
  population RENAPER only publishes citywide) isn't silently dropped. In 2025, 12 of 24
  provinces are significant but only 6 are materially elevated (RR ≥ 1.5), all in the
  north and west; it partly ranks reporting intensity, not only risk.
- [`reporting_delay_nowcast_factor.sql`](analyses/reporting_delay_nowcast_factor.sql) —
  correction factor (latest known count / first published count) by reporting-lag bucket,
  for the subset of periods that do get revised after publication. A week first published
  within 7 days of its end ends up 3.5x higher at the median.
- [`inpatient_reporting_coverage.sql`](analyses/inpatient_reporting_coverage.sql) —
  checks whether the outpatient/inpatient split can compare severity across provinces. It
  can't: from 2023 only Salta reports inpatients, so no inpatient share is published.

## Data and licenses

Code: MIT ([`LICENSE`](LICENSE)). Data: Ministry of Health (SNVS 2.0) and RENAPER, CC-BY 4.0; province
outlines from Natural Earth (public domain).
