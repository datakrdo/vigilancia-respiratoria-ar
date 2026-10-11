# Data profile — SNVS 2.0 acute respiratory infections (IRA)

Source: [datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas](https://datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas)
(Ministerio de Salud, Dirección Nacional de Epidemiología, SNVS 2.0). CC-BY 4.0.

One row = event × department of residence × age group × epidemiological week × year, 24
jurisdictions. No individual notification date (this is aggregated, not case-level, data), which
rules out modeling at case grain; `fct_weekly_cases` matches this grain exactly. About 1.26 M
influenza-like-illness (ETI) notifications in 2025, with a winter peak every year.

Columns (ten, positional in staging because the year column is named `anio` or `año` depending
on the file):
```
departamento_id, departamento_nombre, provincia_id, provincia_nombre,
anio|año, semanas_epidemiologicas, evento_nombre, grupo_edad_id,
grupo_edad_desc, cantidad_casos
```

## How the pipeline handles the source

- **Rolling windows.** Each release covers one to three years and the next one re-publishes the
  overlap (e.g. 2025 appears in the 2025-09, 2026-03 and 2026-09 files, with 818k / 1.25M / 1.26M
  ETI cases). Every file is kept as a revision (this feeds `mart_revisions` directly);
  `int_snvs_unified` keeps the latest per year and event group. Publication date is the
  `hasta-YYYYMMDD` in the file name; the one undated file is the 2021-03-29 cut.
- **Truncated files, not ingested.** Three releases stop at exactly 65,535 rows (the old Excel row
  limit): 2018-12, 2019-07 and 2022-09. Each is fully covered by a later complete file, so
  `scripts/fetch_data.py` skips them. The dataset also lists a data dictionary and a sheet of an
  unrelated event; both are skipped.
- **Encoding.** The 2021-09 Excel sheet carries UTF-8 text decoded as cp1252 (`CÃ³rdoba`); the
  conversion step repairs it. All other files are plain UTF-8.
- **Footer rows.** Rows with a null `semanas_epidemiologicas` are footer/metadata rows, filtered
  in staging.
- **Event names change over time.** Until 2023 each event is a single row ("Neumonía"); later files
  split bronchiolitis and pneumonia into outpatient, inpatient and unspecified rows. The
  `event_map` seed folds all variants into one event per family and keeps the split as
  `care_setting` (-> `mart_care_setting`, the hospitalization share).
- **Age bands** (`< 6 m`, `6 a 11 m`, ..., `65 a 74`, `>= a 75`) are stable across files, but
  `age_group_id` is not a reliable key and the free-text descriptions vary in capitalization,
  wording and accents. `age_group_buckets` maps the normalized description text, not the id. The
  fact table only densifies the age bands each event is actually reported in.
- **Unidentified residence.** Department/province `999`/`desconocido` is a legitimate row, mapped
  to an "Unknown" member of `dim_geography`, never dropped.
- **Department codes are not a join key.** Source codes are not Georef's own department numbering
  (e.g. source `"015"` for CABA "Comuna 15" vs Georef's `"02105"`), so
  `int_snvs_all_revisions` matches on normalized department + province name instead.
- **Pandemic years.** 2020-2021 are heavily distorted (ETI collapses in 2020-21 and rebounds in
  2022). The endemic corridor of 2022-2025 includes those years in its 5-year baseline; this is
  a documented limitation, not corrected.

## Rate denominator and canonical geography

- **Population**: RENAPER — "Estructura de población identificada" (`datos.gob.ar`), CSV
  by department, published several times a year (Aug-2024, Jan-2025, Jun-2025, Jun-2026).
  Identified population (not an INDEC projection), but by department and with recent
  updates — better temporal granularity than the census for this use case. The cut
  closest to each epidemiological year is used as the denominator in
  `mart_incidence_rates`; see `stg_renaper_population` / `int_renaper_population`.
- **Known population gaps** (documented in `mart_incidence_rates`, not silently
  patched): CABA is published as one citywide figure, not by comuna, so no individual
  CABA comuna gets a population/rate; a handful of small departments (~0.6% of total
  population) don't name-match Georef and are also left without a rate; and years
  before the first cut (2018-2023) use the earliest available cut (Aug-2024) as a
  best-available estimate, not a true historical count.
- **Canonical geography**: [Georef API](https://apis.datos.gob.ar/georef/api/departamentos)
  (`datos.gob.ar`) — 5-digit INDEC department codes. Used as the source for
  `dim_geography` (canonical name, province, centroid) instead of relying on each
  source file's free-text names.
