# Data profile — SNVS 2.0 surveillance (Dengue and acute respiratory infections)

Source: [datos.salud.gob.ar/dataset/vigilancia-de-dengue-y-zika](https://datos.salud.gob.ar/dataset/vigilancia-de-dengue-y-zika)
(Ministerio de Salud, Dirección Nacional de Epidemiología, SNVS 2.0). CC-BY 4.0.

13 resources published between 2018 and September 2026 (`data/raw/dengue_zika/`), several
of them successive revisions of the same period (2024 was published 3 times with
different counts: 06-10, 01-06, 01-13, 05-05 → this feeds `mart_revisions` directly).

## Two schema "eras" — confirms the need for the `intermediate` layer

**Legacy era (2018-2022, XLS/XLSX + one CSV)**
```
departamento_id, departamento_nombre, provincia_id, provincia_nombre,
ano|anio|año, semanas_epidemiologicas, evento_nombre, grupo_edad_id,
grupo_edad_desc, cantidad_casos
```
- `evento_nombre` carries `'Dengue'` in every year, plus `'Enfermedad por Virus del
  Zika'` in 2018 only (68 rows) — the one real Zika signal in the whole legacy era.
  2019-2022 are Dengue-only. Confirmed by querying the built
  `stg_dengue_zika__legacy` model, not just eyeballing raw files.
- `semanas_epidemiologicas` is an epi week integer (1-53), not a range.
- The year column's name varies across files (`ano`, `anio`, `año`) → normalized in
  staging.
- BOM (`ï»¿`) in the header of the first (2018) CSV → `read_files()` with explicit
  encoding.
- Three distinct delimiter/encoding combinations across the 7 files (`;` + ISO-8859-1
  for the 2022 file, comma + UTF-8-BOM for the 2018 file, comma + UTF-8 for the rest) →
  handled as separate `read_files()` branches, unioned after explicit per-branch casts
  (see `stg_dengue_zika__legacy.sql`).
- **Genuine data-entry bugs in the 2020 file, two separate ones**: (1) ~1,100 rows have
  `semanas_epidemiologicas`/`evento_nombre` swapped (the former holds `'Dengue'`, the
  latter the week number); (2) **every** row in the file has `grupo_edad_id`/
  `grupo_edad_desc` swapped (the id column holds free text, the desc column holds a
  number or the `'-'` placeholder used for "Sin Especificar"). Both are detected by
  regex (numeric vs. text) and corrected in staging rather than dropped — see
  `stg_dengue_zika__legacy.sql`.
- **`age_group_id` is not a stable key across years**: the same id (e.g. `10`) maps to
  different age buckets in different files (`"De 35 a 44 años"` in one, `"De 45 a 64
  años"` in another), and free-text descriptions vary in capitalization/wording/typos
  for the same real bucket. `dim_age_group` cannot key off the source id/desc directly —
  it needs its own normalized bucket mapping built from the description text, not the id.
- **2021 also has duplicate revisions, like 2024 does in the current era**: two legacy
  files both cover 2021 (`hasta-20210731.converted.csv`, 1,147 rows, and a second,
  hash-named file, 1,165 rows). The second file additionally has `province_id`/
  `province_name` swapped for every row (fixed the same way as the other legacy swaps,
  by regex on which value is numeric). Both revisions are kept in staging (1:1 with
  source); `int_snvs_unified`/marts need to pick one revision as
  canonical rather than double-counting 2021.
- **2018 also has two files with different counts**, found while building
  `mart_revisions` (not previously documented): `vigilancia-de-dengue-y-zika-201812.*`
  (this dataset's original, oldest filename style) and
  `informacion-publica-dengue-zika-nacional-hasta-20181231.csv` (matching the
  `hasta-<date>` naming used for the 2019-2021 files, i.e. a later historical
  backfill, not a second same-day original). Dated `2019-01-01`/`2022-01-01`
  respectively in `int_snvs_all_revisions` — an inferred ordering, since
  neither filename carries a real publish date the way the current era's do.
- **Legacy `department_id` is not one consistent coding scheme**: digit widths range
  from 1 to 6 across files (plus one garbage 11-digit value), so it can't be trusted as
  a join key on its own. `dim_geography`'s crosswalk matches on normalized department +
  province name instead (see the Georef section below) — for **both** eras: the
  current era's `id_depto_indec_residencia` looks like a real INDEC code but does NOT
  match Georef's own department numbering (e.g. source `"015"` for CABA "Comuna 15" vs
  Georef's `"02105"` for the same comuna), so name matching is used uniformly rather
  than trusting either era's composite code.

**Current era (2023 onward, CSV)**
```
id_depto_indec_residencia, departamento_residencia, id_prov_indec_residencia,
provincia_residencia, anio_min, evento, id_grupo_etario, grupo_etario,
sepi_min, cantidad
```
- Department/province codes are now explicitly INDEC (`id_depto_indec_residencia`).
- `evento` carries 2 values: `'Dengue'` and `'Dengue durante la gestación'` — a useful
  second event for `dim_event`.
- Rows with a null `sepi_min` at the end of some files (a footer/metadata row, not data)
  → filtered in staging with `sepi_min IS NOT NULL`.
- Department/province `999`/`desconocido` for unidentified residence → a legitimate row,
  mapped to an "Unknown" member of `dim_geography`, never dropped.
- `grupo_etario` has encoding inconsistencies (`dÍas` vs `días`, `años` vs `anos`)
  across files → accents normalized in staging.

## Source grain
One row = event × department of residence × age group × epidemiological week × year. No
individual notification date (this is aggregated, not case-level, data) — rules out
modeling at case grain; `fct_weekly_cases` grain matches this exactly.

## Second-event decision (open item from phase 1)
Real Zika cases exist but only as 68 rows in 2018 — too sparse for its own corridor or
seasonal comparison. Dengue vs. gestational Dengue (current era) is enough for those
analyses; Zika is kept as-is in `dim_event` for completeness but not a focus of any mart.
Adding a respiratory-illness event (from the "vigilancia-notificacion-de-enfermedades"
group) is evaluated in phase 3 if time allows — not a blocker to start bronze/staging.

## Rate denominator and canonical geography (confirmed)
- **Population**: RENAPER — "Estructura de población identificada" (`datos.gob.ar`), CSV
  by department, published several times a year (Aug-2024, Jan-2025, Jun-2025, Jun-2026).
  Identified population (not an INDEC projection), but by department and with recent
  updates — better temporal granularity than the census for this use case. The cut
  closest to each epidemiological year is used as the denominator in
  `mart_incidence_rates`. Downloaded from `datosabiertos.renaper.gob.ar` (all 4 cuts,
  department-level file) and loaded via `read_files()` like the dengue/zika source —
  see `stg_renaper_population`/`int_renaper_population`.
- **Known population gaps** (documented in `mart_incidence_rates`, not silently
  patched): CABA is published as one citywide figure, not by comuna, so no individual
  CABA comuna gets a population/rate; a handful of small departments (~0.6% of total
  population) don't name-match Georef and are also left without a rate; and years
  before the first cut (2018-2023) use the earliest available cut (Aug-2024) as a
  best-available estimate, not a true historical count.
- **Canonical geography**: [Georef API](https://apis.datos.gob.ar/georef/api/departamentos)
  (`datos.gob.ar`) — 5-digit INDEC department codes, matching
  `id_depto_indec_residencia` from the current schema era. Used as the source for
  `dim_geography` (canonical name, province, centroid) instead of relying on each
  source file's free-text names.

## Next steps (rest of phase 1)
- Download a RENAPER by-department snapshot and the full Georef catalog (seeds or a
  file loaded into a Volume).
- Databricks Free Edition setup (done by the user via `/databricks:setup`): a Volume for
  `data/raw/`, a serverless SQL warehouse, dbt's `profiles.yml`.

## Acute respiratory infections (IRA) — second dataset

Source: [datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas](https://datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas)
(same ministry, same SNVS 2.0 export, CC-BY 4.0). Same ten columns as Dengue, same grain
(event x department of residence x age group x epi week x year), 24 jurisdictions. About 1.26 M
influenza-like-illness (ETI) notifications in 2025 against 17,682 Dengue cases, and a winter peak
every year, which is why it is the headline dataset.

What differs from Dengue, and how the pipeline handles it:

- **Rolling windows.** Each release covers one to three years and the next one re-publishes the
  overlap (e.g. 2025 appears in the 2025-09, 2026-03 and 2026-09 files, with 307k / 471k / 474k
  ETI cases). Every file is kept as a revision; `int_snvs_unified` keeps the latest per year and
  event group. Publication date is the `hasta-YYYYMMDD` in the file name.
- **Truncated files, not ingested.** Three releases stop at exactly 65,535 rows (the old Excel row
  limit): 2018-12, 2019-07 and 2022-09. Each is fully covered by a later complete file, so
  `scripts/fetch_data.py` skips them. The dataset also lists a data dictionary and a Dengue sheet
  filed under the wrong dataset; both are skipped.
- **Encoding.** The 2021-09 Excel sheet carries UTF-8 text decoded as cp1252 (`CÃ³rdoba`); the
  conversion step repairs it. All other files are plain UTF-8; the year column is named `anio` or
  `año` depending on the file, so staging reads positionally.
- **Event names change over time.** Until 2023 each event is a single row ("Neumonía"); later files
  split bronchiolitis and pneumonia into outpatient, inpatient and unspecified rows. The
  `event_map` seed folds all variants into one event per family and keeps the split as
  `care_setting` (-> `mart_care_setting`, the hospitalization share).
- **Age bands** are different (`< 6 m`, `6 a 11 m`, ..., `65 a 74`, `>= a 75`) and stable across
  files; they extend the `age_group_buckets` seed. The fact table only densifies the age bands
  each event is actually reported in.
- **Pandemic years.** 2020-2021 are heavily distorted (ETI collapses in 2020-21 and rebounds in
  2022). The endemic corridor of 2022-2025 includes those years in its 5-year baseline; this is
  a documented limitation, not corrected.

Zika is not modeled: 37 cases in 2018 and none since.
