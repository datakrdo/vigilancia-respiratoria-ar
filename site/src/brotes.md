---
title: Brotes
sql:
  outbreaks: ./data/outbreaks.parquet
---

# Brotes: cuándo y dónde el corredor se rompió

<p class="lede">Un brote es una racha de semanas consecutivas por encima del percentil 75 histórico de una provincia. La tasa de ataque (casos cada 100.000 hab.) permite comparar provincias de distinto tamaño.</p>

```js
import {alert, fmt, rateRamp, toDate} from "./components/theme.js";
const events = [...await sql`select distinct event_code, event_name from outbreaks order by 2`];
```

<div class="controls">

```js
const event = view(Inputs.radio(events, {label: "Evento", format: (d) => d.event_name, value: events.find((d) => d.event_code === "ETI") ?? events[0]}));
```

</div>

```js
const rows = [...await sql`
  select province_name, outbreak_start_date, outbreak_end_date, duration_weeks, total_cases,
         peak_case_count, attack_rate_per_100k
  from outbreaks where event_code = ${event.event_code} order by outbreak_start_date`]
  .map((d) => ({...d, start: toDate(d.outbreak_start_date), end: toDate(d.outbreak_end_date)}));
const order = d3.sort(d3.rollup(rows, (v) => d3.sum(v, (d) => d.total_cases), (d) => d.province_name), ([, a]) => -a).map(([k]) => k);
```

```js
display(Plot.plot({
  width,
  marginLeft: 150,
  marginTop: 24,
  height: 24 * order.length + 60,
  x: {label: null, type: "utc"},
  y: {label: null, domain: order},
  color: {type: "sqrt", range: rateRamp(dark), unknown: "#8d8c86", legend: true, label: "Tasa de ataque (casos cada 100.000 hab.)"},
  marks: [
    Plot.rectX([{x1: new Date(Date.UTC(2020, 2, 1)), x2: new Date(Date.UTC(2022, 2, 1))}], {x1: "x1", x2: "x2", fill: "var(--ink-2)", fillOpacity: 0.12}),
    Plot.text([{x: new Date(Date.UTC(2020, 2, 1))}], {x: "x", frameAnchor: "top", dy: -14, textAnchor: "start", text: () => "COVID-19: cuadros respiratorios notificados como sospecha de COVID", fill: "var(--ink-2)", fontSize: 11}),
    Plot.ruleY(order, {stroke: "var(--line)"}),
    Plot.barX(rows, {
      y: "province_name", x1: "start", x2: "end", fill: "attack_rate_per_100k", inset: 1,
      title: (d) => `${d.province_name}\n${d.outbreak_start_date} → ${d.outbreak_end_date} (${d.duration_weeks} sem.)\n${fmt(d.total_cases)} casos · pico semanal ${fmt(d.peak_case_count)}\nTasa de ataque ${fmt(d.attack_rate_per_100k)} cada 100.000`,
      tip: true
    })
  ]
}));
```

## Los 15 brotes con mayor tasa de ataque

```js
display(Inputs.table(d3.sort(rows, (a, b) => d3.descending(a.attack_rate_per_100k, b.attack_rate_per_100k)).slice(0, 15), {
  columns: ["province_name", "outbreak_start_date", "duration_weeks", "total_cases", "attack_rate_per_100k"],
  header: {province_name: "Provincia", outbreak_start_date: "Inicio", duration_weeks: "Semanas", total_cases: "Casos", attack_rate_per_100k: "Tasa de ataque"},
  format: {total_cases: (d) => fmt(d), attack_rate_per_100k: (d) => fmt(d)}
}));
```

${event.event_code !== "DENGUE" ? html`<p class="fineprint"><b>¿Por qué hay pocos brotes entre marzo de 2020 y febrero de 2022?</b> No es un error de datos. Con el aislamiento y el barbijo circularon mucho menos la influenza y el virus sincicial, y además buena parte de los cuadros respiratorios se notificó como sospecha de COVID-19, un evento que no está en este dataset. La ETI notificada cayó de 844 mil casos en 2019 a 346 mil en 2020 y 478 mil en 2021, así que casi ninguna semana superó el percentil 75 de los años previos. En 2018 tampoco hay brotes porque es el primer año: no hay historia para comparar. Y como 2020-2021 entran en la base de 5 años de 2022 a 2025, el percentil 75 de esos años es más bajo y marcan más brotes.</p>` : ""}
