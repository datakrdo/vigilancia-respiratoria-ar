---
title: Corredor endémico
sql:
  corridor: ./data/corridor.parquet
---

# Corredor endémico: ¿esta semana es normal para esta provincia?

<p class="lede">El corredor compara cada semana con las mismas semanas de los 5 años anteriores. Si los casos superan el percentil 75 de esos años, la semana entra en zona de <b>brote</b>. Es la herramienta que usa el Boletín Epidemiológico Nacional.</p>

```js
import {fmt} from "./components/theme.js";
import {t} from "./components/i18n.js";
import {corridorChart, zoneMap} from "./components/charts.js";
const L = t("es");
const events = [...await sql`select distinct event_code, event_name from corridor order by 2`];
const provinceRows = [...await sql`select distinct province_indec_id, province_name from corridor order by 2`];
const provinces = provinceRows.map((d) => d.province_name);
const nameById = new Map(provinceRows.map((d) => [String(d.province_indec_id), d.province_name]));
const geo = await FileAttachment("data/ar_provinces.geojson").json();
const yearInfo = [...await sql`select year, cast(max(epi_week) as int) as wk from corridor where case_count > 0 group by year order by year desc`];
const years = yearInfo.map((d) => d.year);
const partial = new Map(yearInfo.filter((d) => d.wk < 52).map((d) => [d.year, d.wk]));
const yearLabel = (y) => (partial.has(y) ? L.partial(y) : String(y));
const defaultYear = yearInfo[0].year;
```

<div class="controls">

```js
const event = view(Inputs.radio(events, {label: L.event, format: L.eventName, value: events.find((d) => d.event_code === "ETI") ?? events[0]}));
const provinceInput = Inputs.select(provinces, {label: L.province, value: provinces.includes("Córdoba") ? "Córdoba" : provinces[0]});
const province = view(provinceInput);
const year = view(Inputs.radio(years, {label: L.year, format: yearLabel, value: defaultYear}));
```

</div>

${partial.has(year) ? html`<p class="fineprint">${year} es un año en curso: datos hasta la semana ${partial.get(year)}.</p>` : ""}

```js
const rows = [...await sql`
  select epi_week, week_start_date, case_count, p25_case_count as p25, p50_case_count as p50,
         p75_case_count as p75, corridor_zone as zone, n_years_in_corridor as n_years
  from corridor
  where event_code = ${event.event_code} and province_name = ${province} and year = ${year}
    and epi_week <= (select coalesce(max(epi_week), 0) from corridor where event_code = ${event.event_code} and year = ${year} and case_count > 0)
  order by epi_week`];
const zones = [...await sql`
  select cast(province_indec_id as string) as id, epi_week, corridor_zone as zone
  from corridor where event_code = ${event.event_code} and year = ${year}`];
const lastWeek = d3.max(rows, (d) => d.epi_week);
```

<div class="split">

```js
const week = view(corridorChart({rows, L, dark, width: width >= 900 ? width - 400 : width, lastWeek}));
```

```js
const zoneById = new Map(zones.filter((d) => d.epi_week === week).map((d) => [d.id, d.zone]));
display(zoneMap({
  features: geo.features, zoneById, nameById, selectedName: province, week, L, dark,
  onSelect: (name) => {
    provinceInput.value = name;
    provinceInput.dispatchEvent(new Event("input", {bubbles: true}));
  }
}));
```

</div>

<p class="fineprint">Pasá el cursor por el gráfico para ver cómo estaba cada provincia en esa semana; con un clic sobre el mapa se cambia la provincia.</p>

${["2020", "2021"].includes(String(year)) ? html`<p class="fineprint"><b>Ojo con ${year}:</b> buena parte de los cuadros respiratorios se notificó como sospecha de COVID-19, un evento que no está en este dataset. Los casos de ${L.eventName(event)} aparecen subestimados.</p>` : ""}

<p class="fineprint"><b>Cómo leerlo:</b> la línea sólida son los casos de ${year}. Las franjas azules son lo habitual para esa semana (hasta el percentil 25: <i>éxito</i>; hasta la mediana: <i>seguridad</i>; hasta el percentil 75: <i>alerta</i>). Por encima, la zona roja es <i>brote</i>, y los puntos rojos marcan las semanas en que los casos la atravesaron. Los primeros años del dataset (2018–2022) usan menos de 5 años de historia; sin ninguno, no hay corredor.</p>

<details><summary>Ver como tabla</summary>

```js
display(Inputs.table(rows, {columns: Object.keys(L.tableCols), header: L.tableCols, format: {zone: (z) => (z ? L.zones[z] : ""), p25: (d) => fmt(d, 1), p50: (d) => fmt(d, 1), p75: (d) => fmt(d, 1)}}));
```

</details>
