🇬🇧 [English](README.md) · 🇪🇸 [Español](README_es.md)

# vigilancia-respiratoria-ar 🫁

Analytics engineering sobre vigilancia epidemiológica en Argentina (SNVS 2.0, Ministerio de
Salud): infecciones respiratorias agudas (enfermedad tipo influenza, bronquiolitis, neumonía;
unas 1,3 M de notificaciones por año), con **dbt-databricks** sobre Databricks Free Edition
(Unity Catalog, SQL warehouse serverless). Pensado para equipos de salud pública: la capa SQL alimenta un sitio público y datos que se actualizan solos cada semana.

Fuentes: [infecciones respiratorias](https://datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas) (CC-BY 4.0). Perfil completo de los datos, publicaciones superpuestas y problemas
de calidad encontrados: [`docs/data_profile.md`](docs/data_profile.md).

## Para verlo 👀

- **[Sitio público](https://datakrdo.github.io/vigilancia-respiratoria-ar/)** (Observable Framework, en español e inglés): casos y tasa por departamento, corredor endémico interactivo por provincia, brotes y los seis hallazgos de abajo en lenguaje llano.
- **[Documentación dbt](https://datakrdo.github.io/vigilancia-respiratoria-ar/dbt/)**: linaje completo, columnas y tests.

Ambos sitios se reconstruyen solos cuando la fuente publica datos nuevos (ver *Actualización automática*).

## Leer antes de usar los números ⚠️

- Los casos se asignan al departamento de **residencia**, no al lugar donde ocurrió el contagio.
- Las últimas semanas están **incompletas** (notificación tardía); ver el hallazgo de nowcast.
- La población de CABA solo se publica por ciudad, así que sus comunas no tienen tasa.
- La notificación es despareja entre jurisdicciones: Santa Fe informa 52 casos de ETI cada 100.000 en 2025 (322 en 2019), CABA 240 (815 en 2019), Córdoba 3.379. Una tasa baja puede ser poca notificación y no poca enfermedad.
- El año en curso es parcial, y 2020-2021 (COVID) distorsionan la base de 5 años del corredor endémico de los años siguientes.
- Las tasas con menos de 20 casos son inestables; el sitio las muestra atenuadas.
- El sitio público muestra solo agregados por departamento o provincia, nunca por edad (conteos chicos podrían identificar personas).

## Arquitectura (medallion) 🏗️

```
seeds/                  georef_departments, age_group_buckets, event_map (crosswalks)
sources (Volume CSVs) ──read_files()──► staging/
  stg_respiratory               (IRA 2018+, publicaciones en ventanas superpuestas)
  stg_renaper_population        (población identificada RENAPER por departamento)
        │
        ▼
intermediate/
  int_snvs_all_revisions  toda publicación de cada período, incremental por archivo de origen (grano de mart_revisions)
  int_snvs_unified        una fila canónica por período (última revisión)
  int_renaper_population
        │
        ▼
snapshots/
  snap_snvs_weekly        SCD2 semanal sobre int_snvs_weekly_by_event
        │
        ▼
marts/
  dim_geography, dim_province, dim_age_group, dim_event, dim_epi_week, dim_date
  fct_weekly_cases        evento x depto x grupo etario x semana epi x año (densificado)
  mart_incidence_rates    tasas por 100k, acumulado anual, comparación interanual
  mart_endemic_corridor   corredor endémico (percentiles 25/50/75 de los 5 años previos)
  mart_outbreaks          episodios de brote (gaps & islands sobre el corredor)
  mart_care_setting       apertura ambulatorio / internado de eventos respiratorios (solo informada a nivel nacional en 2020-2022)
  mart_revisions          cuánto cambia un dato ya publicado en revisiones sucesivas
```

Todos los marts (`dim_*`, `fct_*`, `mart_*`) tienen `contract: enforced: true`.

## Cómo correrlo 🚀

```bash
uv sync --group ingest
cp profiles.yml.example ~/.dbt/profiles.yml   # completar host/http_path, login con `databricks auth login`
uv run python scripts/fetch_data.py --upload /Volumes/workspace/bronze/raw_data   # descarga + sincroniza el Volume
dbt deps
dbt build        # modelos, seeds, snapshot, tests y unit tests
```

La ruta del Volume es la var `raw_volume_path` de `dbt_project.yml`.

Lint (dialecto Databricks, plantilla dbt):

```bash
sqlfluff lint models/ analyses/ tests/
```

## Actualización automática 🔄

La fuente publica de forma irregular (entre una semana y varios meses), así que el CI
(`.github/workflows/ci.yml`) revisa **todos los lunes**: `scripts/fetch_data.py`
descarga los archivos, sube al Volume solo los nuevos o modificados y recién entonces corre
`dbt build` (que también registra revisiones en el snapshot). La carga es incremental: `int_snvs_all_revisions` solo resuelve los archivos nuevos o reemplazados desde la última corrida (`dbt build --full-refresh` reconstruye todo), regenera la documentación de dbt
y vuelve a desplegar el sitio en GitHub Pages. Sin novedades no se reconstruye nada. En pull
requests corre `sqlfluff lint` y `dbt parse` con un perfil ficticio (sin secrets). Requiere los
secrets `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH` y `DATABRICKS_TOKEN`.

## Hallazgos (`analyses/`) 🔍

- [`season_timing_and_severity.sql`](analyses/season_timing_and_severity.sql) —
  por provincia y temporada, la semana en la que se alcanza
  el 50%/90% de los casos de esa temporada y el exceso total sobre el techo p75 del
  corredor endémico, rankeado por exceso **cada 100 mil habitantes** para que una
  provincia grande no encabece la lista solo por tamaño. En 2025 lideran Jujuy (3.315
  casos de exceso/100k), Catamarca (2.231) y Tucumán (2.038); el 50% de los casos de la
  temporada llega antes de la semana 22-28, así que las campañas tienen que estar listas
  en abril-mayo.
- [`geographic_spread_of_season.sql`](analyses/geographic_spread_of_season.sql) —
  revisa si cada temporada avanza de norte a sur comparando la semana epidemiológica en
  que pica cada provincia. Hallazgo: no avanza — en 2023-2025 la provincia mediana pica en
  la semana 24-25 y entre 17 y 23 de las 24 provincias lo hacen a menos de 3 semanas de ella —
  un resultado negativo útil.
- [`outbreak_early_warning_lead_time.sql`](analyses/outbreak_early_warning_lead_time.sql) —
  evalúa un umbral de crecimiento de casos como señal de alerta temprana de brote.
  El recall es de cerca del 20% (105/528 brotes) y la precisión de cerca del 35%, pero los
  brotes que sí detecta dan una anticipación mediana de 6 semanas — vale como señal a
  revisar, no como alerta autónoma.
- [`hotspot_concentration_and_persistence.sql`](analyses/hotspot_concentration_and_persistence.sql) —
  concentración de casos por departamento (Pareto/Gini), un Gini ponderado por
  población (curva de Lorenz por tasa, no por casos crudos) para separar concentración
  de riesgo de dónde vive la gente, y superposición Jaccard del decil superior por tasa
  entre temporadas consecutivas. La ETI está concentrada (17-28% de los departamentos reúnen el 80% de los casos de una
  temporada, Gini crudo 0,70-0,80) y es parcialmente persistente (Jaccard del decil
  superior 0,45-0,66). El Gini ponderado por población es más bajo todas las temporadas
  (2025: 0,58 contra 0,74 crudo), lo que muestra que parte de la concentración cruda es solo
  población, no riesgo.
- [`provinces_with_significant_excess_rate.sql`](analyses/provinces_with_significant_excess_rate.sql) —
  rate ratio contra el resto del país con IC 95% log-Poisson, para separar un exceso
  real de un artefacto de población chica. Usa población a nivel provincia para que
  CABA (cuya población RENAPER solo publica a nivel ciudad) no quede afuera del
  ranking. En 2025, 12 de 24 provincias son significativas pero solo 6 tienen un exceso
  material (RR ≥ 1,5), todas del norte y el oeste; en parte rankea intensidad de
  notificación, no solo riesgo.
- [`reporting_delay_nowcast_factor.sql`](analyses/reporting_delay_nowcast_factor.sql) —
  factor de corrección (último valor conocido / primer valor publicado) por bucket de
  demora de notificación, para el subconjunto de períodos que sí se revisan después de
  publicados. Una semana publicada a menos de 7 días de su cierre termina 3,5 veces más
  alta en la mediana.
- [`inpatient_reporting_coverage.sql`](analyses/inpatient_reporting_coverage.sql) —
  revisa si la apertura ambulatorio/internado sirve para comparar gravedad entre
  provincias. No sirve: desde 2023 solo Salta informa internados, así que no se publica
  una proporción de internados.

## Datos y licencias

Código: MIT ([`LICENSE`](LICENSE)). Datos: Ministerio de Salud (SNVS 2.0) y RENAPER, CC-BY 4.0; contornos
provinciales de Natural Earth (dominio público).
