---
title: Hallazgos
sql:
  timing: ./data/find_season_timing.parquet
  spread: ./data/find_spread.parquet
  hotspots: ./data/find_hotspots.parquet
  warning: ./data/find_early_warning.parquet
  provinces: ./data/find_provinces.parquet
  nowcast: ./data/find_nowcast.parquet
---

# Seis preguntas que los datos permiten responder

<p class="lede">Cada hallazgo parte de una pregunta concreta de vigilancia, está calculado en SQL sobre las mismas tablas que alimentan el resto del sitio, y termina en qué conviene hacer con la respuesta. Algunos resultados son negativos, y por eso útiles.</p>

```js
import {alert, fmt} from "./components/theme.js";
const num = (rows) => rows.map((d) => Object.fromEntries(Object.entries(d).map(([k, v]) => [k, typeof v === "bigint" ? Number(v) : v])));
```

<div class="finding" id="exceso-sobre-el-corredor">

## 1. ¿Qué provincias sufrieron más, una vez descontado su tamaño?

<p class="so-what">Ordenar por casos totales premia a las provincias grandes. Ordenadas por exceso sobre el techo del corredor cada 100.000 habitantes, el ranking cambia.</p>

</div>

```js
const timing = num([...await sql`select * from timing order by season_start_year desc, total_excess_per_100k desc`]);
const seasons = [...new Set(timing.map((d) => d.season_label))];
const season = view(Inputs.radio(seasons, {label: "Temporada", value: seasons[0]}));
```

```js
const t = timing.filter((d) => d.season_label === season);
display(Plot.plot({
  marginLeft: 130, height: 40 * t.length + 40,
  x: {label: "Casos en exceso sobre el percentil 75, cada 100.000 hab.", grid: true},
  y: {label: null, domain: t.map((d) => d.province_name)},
  marks: [
    Plot.barX(t, {y: "province_name", x: "total_excess_per_100k", fill: "var(--accent)",
      title: (d) => `${d.province_name}\nExceso: ${fmt(d.total_excess_cases_over_corridor)} casos (${fmt(d.total_excess_per_100k)} cada 100.000)\nLlegó al 50% de los casos en la semana ${d.epi_week_reaching_50pct} y al 90% en la semana ${d.epi_week_reaching_90pct}`, tip: true}),
    Plot.ruleX([0])
  ]
}));
```

<div class="finding" id="gradiente-norte-sur">

## 2. ¿La temporada avanza de norte a sur?

<p class="so-what">No: todo el país pica junto. En 2024, 23 de las 24 provincias alcanzaron su pico dentro de las 3 semanas de la mediana (semana 24); en 2023 y 2025, 17 y 18. Solo las temporadas alteradas por la pandemia (2021-2022) se dispersan. No hay que esperar que el brote «baje» desde el norte: se vigilan todas las provincias a la vez.</p>

</div>

```js
const spread = num([...await sql`select * from spread order by season_start_year desc, province_lat desc`]);
const spSeasons = [...new Set(spread.map((d) => d.season_label))];
const spSeason = view(Inputs.radio(spSeasons, {label: "Temporada", value: spSeasons[0]}));
```

```js
const sp = spread.filter((d) => d.season_label === spSeason);
const spMedian = d3.median(sp, (d) => d.peak_epi_week);
const spNear = sp.filter((d) => Math.abs(d.peak_epi_week - spMedian) <= 3).length;
```

<div class="kpis">
  <div class="kpi"><div class="n">${fmt(spMedian)}</div><div class="l">semana epidemiológica mediana del pico</div></div>
  <div class="kpi"><div class="n">${fmt(spNear)} de ${fmt(sp.length)}</div><div class="l">provincias picaron a menos de 3 semanas de esa mediana</div></div>
  <div class="kpi"><div class="n">${fmt(d3.max(sp, (d) => d.peak_epi_week) - d3.min(sp, (d) => d.peak_epi_week))} sem.</div><div class="l">entre la primera y la última provincia en picar</div></div>
</div>

```js
display(Plot.plot({
  marginLeft: 130, height: 22 * sp.length + 60,
  x: {label: "Semana epidemiológica del pico de casos", grid: true, domain: [1, 52]},
  y: {label: null, domain: sp.map((d) => d.province_name)},
  marks: [
    Plot.rectX([{a: spMedian - 3, b: spMedian + 3}], {x1: "a", x2: "b", fill: "var(--accent)", fillOpacity: 0.12}),
    Plot.ruleX([spMedian], {stroke: "var(--accent)"}),
    Plot.dot(sp, {x: "peak_epi_week", y: "province_name", fill: "var(--accent)", r: 4,
      title: (d) => `${d.province_name}\nPico en la semana ${d.peak_epi_week}`, tip: true})
  ]
}));
```

<p class="fineprint">Provincias ordenadas de norte a sur. La banda marca la mediana ± 3 semanas. Si la temporada bajara desde el norte, los puntos formarían una diagonal; no la forman. El pico es la semana con más casos de la provincia en la temporada.</p>

<div class="finding" id="alerta-temprana">

## 3. ¿Una señal de crecimiento sirve como alerta de brote?

<p class="so-what">Sola, no: detecta alrededor de 1 de cada 5 brotes, y 2 de cada 3 señales no terminan en brote. Pero cuando acierta, avisa con semanas de anticipación; sirve como señal para revisar, no como alarma automática.</p>

</div>

```js
const w = num([...await sql`select * from warning`])[0] ?? {};
```

<div class="kpis">
  <div class="kpi"><div class="n">${fmt(w.recall_pct, 1)}%</div><div class="l">de los brotes (${fmt(w.outbreaks_with_advance_signal)} de ${fmt(w.total_outbreaks)}) tuvo una señal previa</div></div>
  <div class="kpi"><div class="n">${fmt(w.precision_pct, 1)}%</div><div class="l">de las señales (${fmt(w.signals_confirmed_by_outbreak)} de ${fmt(w.total_growth_signals)}) fue seguida por un brote</div></div>
  <div class="kpi"><div class="n">${fmt(w.median_lead_time_weeks, 1)} sem.</div><div class="l">de anticipación mediana cuando la señal acierta</div></div>
  <div class="kpi"><div class="n">${fmt(w.p10_lead_time_weeks_conservative, 1)} sem.</div><div class="l">de anticipación en el caso conservador (percentil 10)</div></div>
</div>

<div class="finding" id="concentracion-y-persistencia">

## 4. ¿Los focos se concentran y son los mismos cada año?

<p class="so-what">Alrededor de un cuarto de los departamentos reúne el 80% de los casos, y los focos se repiten solo en parte: la superposición con la temporada anterior va de 0,45 a 0,66. Reforzar siempre los mismos lugares deja afuera a una parte de los focos nuevos.</p>

</div>

```js
const hot = num([...await sql`select * from hotspots order by season_start_year`]);
display(Plot.plot({
  height: 300, marginBottom: 50,
  x: {label: "Temporada", tickRotate: -20, domain: hot.map((d) => d.season_label)},
  y: {label: "Índice (0 a 1)", domain: [0, 1], grid: true},
  color: {legend: true, domain: ["Gini de casos", "Gini ponderado por población", "Superposición con la temporada previa (Jaccard)"], range: ["#2a78d6", "#eb6834", "#1baf7a"]},
  marks: [
    Plot.line(hot, {x: "season_label", y: "gini_coefficient", stroke: () => "Gini de casos", strokeWidth: 2}),
    Plot.line(hot, {x: "season_label", y: "population_weighted_gini_coefficient", stroke: () => "Gini ponderado por población", strokeWidth: 2}),
    Plot.line(hot.filter((d) => d.jaccard_similarity_to_prior_season != null), {x: "season_label", y: "jaccard_similarity_to_prior_season", stroke: () => "Superposición con la temporada previa (Jaccard)", strokeWidth: 2}),
    Plot.dot(hot, {x: "season_label", y: "gini_coefficient", fill: "#2a78d6"}),
    Plot.dot(hot, {x: "season_label", y: "population_weighted_gini_coefficient", fill: "#eb6834"}),
    Plot.dot(hot.filter((d) => d.jaccard_similarity_to_prior_season != null), {x: "season_label", y: "jaccard_similarity_to_prior_season", fill: "#1baf7a"}),
    Plot.ruleY([0])
  ]
}));
```

<p class="fineprint">El Gini ponderado es menor que el de casos: parte de la concentración aparente es solo dónde vive la gente, no mayor riesgo.</p>

<div class="finding" id="exceso-significativo">

## 5. ¿Qué provincias tienen una tasa realmente más alta, y no solo ruido?

<p class="so-what">Una provincia pequeña puede tener una tasa alta por azar. La razón de tasas con su intervalo de confianza al 95% separa un exceso real (el intervalo no cruza 1) de una fluctuación. Con más de un millón de casos al año hasta una diferencia del 2% sale “significativa”, así que además se exige una razón de tasas de al menos 1,5.</p>

</div>

```js
const prov = num([...await sql`select * from provinces order by rate_ratio_vs_rest_of_country desc`]);
display(Plot.plot({
  marginLeft: 150, height: 26 * prov.length + 50,
  x: {type: "log", label: "Razón de tasas vs. el resto del país (escala logarítmica)", grid: true, ticks: [0.25, 0.5, 1, 2, 4, 8, 16, 32], tickFormat: (d) => `×${d}`},
  y: {label: null, domain: prov.map((d) => d.province_name)},
  color: {domain: [true, false], range: [alert(dark), "#8d8c86"]},
  marks: [
    Plot.ruleX([1], {stroke: "var(--ink)"}),
    Plot.ruleY(prov, {y: "province_name", x1: "ci95_low", x2: "ci95_high", stroke: "is_materially_elevated", strokeWidth: 2}),
    Plot.dot(prov, {y: "province_name", x: "rate_ratio_vs_rest_of_country", fill: "is_materially_elevated", r: 4,
      title: (d) => `${d.province_name}\nRazón de tasas ${fmt(d.rate_ratio_vs_rest_of_country, 2)} (IC 95%: ${fmt(d.ci95_low, 2)}–${fmt(d.ci95_high, 2)})\n${fmt(d.province_rate_per_100k, 1)} casos cada 100.000`, tip: true})
  ]
}));
```

<p class="fineprint">Rojo: exceso significativo y de al menos ×1,5. Gris: no cumple las dos condiciones. Las diferencias de tasa también reflejan cuánto notifica cada jurisdicción.</p>

<div class="finding" id="retraso-de-notificacion">

## 6. ¿Cuánto hay que corregir los números de la última semana?

<p class="so-what">Bastante: entre los períodos que se revisan, el primer valor publicado dentro de la primera semana es en la mediana el 28% del final (×3,5); entre 8 y 30 días, el 50% (×2); entre 31 y 90, el 67%; pasados 90 días, el 75% (×1,3). Los números de la última semana siempre se leen como un piso.</p>

</div>

```js
const nc = num([...await sql`select * from nowcast order by avg_reporting_lag_days`])
  .map((d) => ({...d, known: 100 / d.median_correction_factor, known_p90: 100 / d.p90_correction_factor}));
display(Plot.plot({
  height: 300, marginRight: 30,
  x: {type: "log", label: "Días entre el fin de la semana y la primera publicación", ticks: nc.map((d) => d.avg_reporting_lag_days), tickFormat: (d) => `${d} d`},
  y: {label: "% del valor final ya conocido", domain: [0, 100], grid: true},
  marks: [
    Plot.areaY(nc, {x: "avg_reporting_lag_days", y1: "known_p90", y2: "known", fill: "var(--accent)", fillOpacity: 0.2}),
    Plot.line(nc, {x: "avg_reporting_lag_days", y: "known", stroke: "var(--accent)", strokeWidth: 2}),
    Plot.dot(nc, {x: "avg_reporting_lag_days", y: "known", fill: "var(--accent)", r: 4,
      title: (d) => `${d.reporting_lag_bucket}: ${fmt(d.n_periods)} períodos revisados\nMediana: se conoce el ${fmt(d.known, 0)}% del final (×${d.median_correction_factor})\nPercentil 90: solo el ${fmt(d.known_p90, 0)}% (×${d.p90_correction_factor})`, tip: true}),
    Plot.text(nc, {x: "avg_reporting_lag_days", y: "known", text: (d) => `${fmt(d.known, 0)}%`, dy: -12, fontWeight: "bold"}),
    Plot.ruleY([100])
  ]
}));
```

<p class="fineprint">Línea: mediana. Banda: hasta el caso desfavorable (percentil 90). Solo cuenta períodos que después se revisaron, así que exagera la corrección de una semana típica. La demora de 0 a 7 días tiene pocos períodos (826).</p>
