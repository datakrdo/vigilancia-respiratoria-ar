---
title: Methodology
---

# Methodology, sources and limits

## Where the numbers come from

- **Cases:** a dataset of SNVS 2.0, Argentina's National Ministry of Health, CC-BY 4.0 license: [Acute respiratory infection surveillance](https://datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas) (influenza-like illness, bronchiolitis in children under 2 and pneumonia). Files are published in overlapping windows and some years were republished several times with different figures: for each year the latest publication is used.
- **Population:** [Identified population structure](https://datos.gob.ar/dataset/renaper-estructura-poblacion-argentina), RENAPER, CC-BY 4.0. It is population with a national ID, not an INDEC projection.
- **Geography:** department and province codes from [Georef](https://datosgobar.github.io/georef-ar-api/). Province outlines from [Natural Earth](https://www.naturalearthdata.com/) (public domain).
- **Updates:** once a week the pipeline checks for new or modified files; if there are none, the site is not rebuilt.

## How it is calculated

- **Rate:** cases in the period per 100,000 population, using the population cut closest to the year.
- **Respiratory events:** bronchiolitis and pneumonia are summed across outpatient, inpatient and unspecified. That breakdown was only reported nationwide in 2020-2022; from 2023 only Salta reports inpatients, so no inpatient share by province is published.
- **Running year:** the latest year is incomplete. The site opens on the latest year by default, even if partial, and marks it as such.
- **COVID-19 (March 2020 to February 2022):** a good share of respiratory illness was notified as suspected COVID-19, which is not in this dataset, and influenza and respiratory syncytial virus also circulated less. Cases for those years are underestimated and there are almost no outbreaks; in addition, 2020-2021 lower the 2022 to 2025 corridor.
- **Rates with few cases:** a province with fewer than 20 cases has an unstable rate; the chart shows it faded.
- **Endemic corridor:** 25th, 50th and 75th percentiles of the same week in the previous 5 years, by province and event. It does not include the year being evaluated. Years with fewer than 5 years of history use whatever is available.
- **Outbreak:** run of consecutive weeks above the 75th percentile. A week with no historical baseline does not count as an outbreak.
- **Code and tests:** all processing is SQL versioned with dbt. The [data model documentation](https://datakrdo.github.io/vigilancia-respiratoria-ar/dbt/) includes the full lineage.

## What this site does not say

- **Residence, not infection.** Cases are assigned to the department of residence, which may not be where the person was infected.
- **The latest weeks are incomplete.** Notifications arrive late; see the finding on [reporting delay](./hallazgos#reporting-delay).
- **CABA is published as one city.** RENAPER reports the population of CABA as a whole, not by comuna: comunas appear without a rate.
- **No age breakdown.** Small counts by department, age and week could identify people, so this site only publishes aggregates by department or province.
- **Notification is uneven.** Some jurisdictions notify much less than others to SNVS 2.0: Santa Fe went from 322 ETI cases per 100,000 in 2019 to 52 in 2025, and CABA from 815 to 240, while Córdoba is at 3,379. A low rate may be little notification rather than little disease; compare each province with its own history before comparing it with the others.
- **Notified is not confirmed.** Figures are cases notified to the system, with criteria that may vary between jurisdictions and years.
