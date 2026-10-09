---
title: Situación actual
sql:
  departments: ./data/departments.parquet
  corridor: ./data/corridor.parquet
---

# Infecciones respiratorias y Dengue en Argentina: dónde está el riesgo, no solo dónde hay más casos

<p class="lede">Casos notificados al SNVS 2.0 por departamento de residencia, con la tasa cada 100.000 habitantes. Una provincia grande siempre suma más casos; la tasa y el <a href="./corredor">corredor endémico</a> dicen si la situación es realmente anormal.</p>

```js
import {alert, rateRamp, fmt} from "./components/theme.js";
const events = [...await sql`select distinct event_code, event_name from departments order by 2`];
const yearInfo = [...await sql`select year, cast(max(last_epi_week) as int) as wk from departments where case_count > 0 group by year order by year desc`];
const years = yearInfo.map((d) => d.year);
const partial = new Map(yearInfo.filter((d) => d.wk < 52).map((d) => [d.year, d.wk]));
const yearLabel = (y) => (partial.has(y) ? `${y} · parcial` : String(y));
const defaultYear = yearInfo[0].year;
```

<div class="controls">

```js
const event = view(Inputs.radio(events, {label: "Evento", format: (d) => d.event_name, value: events.find((d) => d.event_code === "ETI") ?? events[0]}));
const year = view(Inputs.radio(years, {label: "Año", format: yearLabel, value: defaultYear}));
```

</div>

${partial.has(year) ? html`<p class="fineprint">${year} es un año en curso: datos hasta la semana ${partial.get(year)}.</p>` : ""}

```js
const depts = [...await sql`
  select department_name, province_name, centroid_lat, centroid_lon, case_count, rate_per_100k, last_epi_week
  from departments where event_code = ${event.event_code} and year = ${year} and case_count > 0`];
const provinces = await FileAttachment("data/ar_provinces.geojson").json();
const prov = [...await sql`
  select province_name,
         cast(sum(case_count) as double) as cases,
         sum(case_count) / nullif(max(population), 0) * 100000 as rate
  from corridor c where event_code = ${event.event_code} and year = ${year} and population is not null
  group by province_name order by rate desc`];
const lastWeek = depts.length ? d3.max(depts, (d) => d.last_epi_week) : null;
const total = d3.sum(depts, (d) => d.case_count);
// National cases by epi week for the selected event, this year and the previous one
const weekly = new Map([...await sql`
  select year, epi_week, cast(sum(case_count) as double) as cases
  from corridor where event_code = ${event.event_code} and year in (${year}, ${year - 1})
  group by year, epi_week`].map((d) => [`${d.year}-${d.epi_week}`, d.cases]));
const cases = (y, w0, w1) => d3.sum(d3.range(w0, w1 + 1), (w) => weekly.get(`${y}-${w}`) ?? 0);
const hasPrev = [...weekly.keys()].some((k) => k.startsWith(`${year - 1}-`));
const compare = (now, before) => before > 0 ? {pct: (now / before - 1) * 100, now, before} : null;
// The last two weeks of a running year are always incomplete (late notification), so the
// comparison uses the last consolidated week; closed years stop at week 52 (week 53 is not in every year).
const ref = lastWeek ? Math.min(lastWeek >= 52 ? lastWeek : lastWeek - 2, 52) : null;
const inBrote = ref ? [...await sql`
  select province_name from corridor
  where event_code = ${event.event_code} and year = ${year} and corridor_zone = 'Brote' and epi_week = ${ref}
  order by 1`] : [];
const vsWeek = ref && hasPrev ? compare(cases(year, ref, ref), cases(year - 1, ref, ref)) : null;
const vs4 = ref && ref >= 4 && hasPrev ? compare(cases(year, ref - 3, ref), cases(year - 1, ref - 3, ref)) : null;
const delta = (c, label) => c ? html`<div class="kpi"><div class="n">${c.pct > 0 ? "▲" : c.pct < 0 ? "▼" : "="} ${fmt(Math.abs(c.pct), 0)}%</div><div class="l">${label}: ${fmt(c.now)} casos contra ${fmt(c.before)} en ${year - 1}</div></div>` : "";
```

<div class="kpis">
  <div class="kpi"><div class="n">${fmt(total)}</div><div class="l">casos notificados en ${year}${lastWeek ? ` (hasta la semana ${lastWeek})` : ""}</div></div>
  ${delta(vsWeek, `la semana ${ref} respecto de la misma semana`)}
  ${delta(vs4, `las 4 semanas hasta la semana ${ref} respecto de las mismas`)}
  <div class="kpi"><div class="n">${prov[0] ? prov[0].province_name : "—"}</div><div class="l">mayor tasa: ${prov[0] ? fmt(prov[0].rate, 1) : "—"} casos cada 100.000 hab.</div></div>
  <div class="kpi alert"><div class="n">${fmt(inBrote.length)}</div><div class="l">provincias en zona de brote en la semana ${ref}${inBrote.length ? `: ${inBrote.map((d) => d.province_name).join(", ")}` : ""}</div></div>
</div>

## Mapa por departamento

El tamaño del círculo es la cantidad de casos; el color, la tasa cada 100.000 habitantes. Los círculos grises no tienen población de referencia (las comunas de CABA solo se publican como ciudad completa).

```js
display(Plot.plot({
  width: Math.min(width, 640),
  height: 840,
  projection: {type: "mercator", domain: provinces, inset: 12},
  r: {range: [1.5, 24]},
  color: {type: "sqrt", range: rateRamp(dark), unknown: "#8d8c86", legend: true, label: "Casos cada 100.000 hab."},
  marks: [
    Plot.geo(provinces, {fill: "var(--land)", stroke: "var(--line)"}),
    Plot.dot(depts, {
      x: "centroid_lon", y: "centroid_lat", r: "case_count", fill: "rate_per_100k",
      fillOpacity: 0.8, stroke: "var(--surface)", strokeWidth: 0.6, sort: {channel: "-r"},
      channels: {Departamento: "department_name", Provincia: "province_name"},
      tip: {format: {r: (d) => `${fmt(d)} casos`, fill: (d) => d == null || Number.isNaN(d) ? "sin población de referencia" : `${fmt(d, 1)} cada 100.000`, x: false, y: false}}
    })
  ]
}));
```

## Tasa por provincia

${total === 0 ? html`<p class="fineprint"><b>No se notificaron casos de ${event.event_name} en ${year}.</b> Elegí otro evento o año.</p>` : ""}

```js
display(Plot.plot({
  marginLeft: 150,
  height: 24 * prov.length + 40,
  x: {label: "Casos cada 100.000 habitantes", grid: true},
  y: {label: null, domain: prov.map((d) => d.province_name)},
  marks: [
    Plot.barX(prov, {y: "province_name", x: "rate", fill: "var(--accent)", fillOpacity: (d) => (d.cases < 20 ? 0.35 : 1), tip: {format: {x: (d) => fmt(d, 1)}}}),
    Plot.ruleX([0])
  ]
}));
```

${["2020", "2021"].includes(String(year)) && event.event_code !== "DENGUE" ? html`<p class="fineprint"><b>Ojo con ${year}:</b> buena parte de los cuadros respiratorios se notificó como sospecha de COVID-19, un evento que no está en este dataset. Los casos de ${event.event_name} aparecen subestimados.</p>` : ""}

<p class="fineprint">Los comparativos usan la última semana consolidada: se descartan las dos últimas del año en curso porque siempre están incompletas. Las barras claras son provincias con menos de 20 casos: con tan pocos casos la tasa es inestable y no conviene compararla. Las notificaciones se corrigen con el tiempo: las semanas más recientes suelen estar subestimadas (ver <a href="./hallazgos#retraso-de-notificacion">retraso de notificación</a>). Datos por residencia del caso, no por lugar de contagio. Las tasas dependen también de cuánto notifica cada jurisdicción: Santa Fe y CABA notifican muy poca ETI al SNVS 2.0 (Santa Fe, 52 casos cada 100.000 en 2025 contra 3.379 en Córdoba), así que sus tasas bajas no indican menos enfermedad.</p>
