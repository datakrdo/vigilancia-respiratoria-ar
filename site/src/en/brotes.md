---
title: Outbreaks
sql:
  outbreaks: ../data/outbreaks.parquet
---

# Outbreaks: when and where the corridor broke

<p class="lede">An outbreak is a run of consecutive weeks above a province's historical 75th percentile. The attack rate (cases per 100,000 pop.) makes provinces of different sizes comparable.</p>

```js
import {toDate} from "../components/theme.js";
import {t} from "../components/i18n.js";
import {outbreakGantt} from "../components/charts.js";
const L = t("en");
const {fmt} = L;
const events = [...await sql`select distinct event_code, event_name from outbreaks order by 2`];
```

<div class="controls">

```js
const event = view(Inputs.radio(events, {label: L.event, format: L.eventName, value: events.find((d) => d.event_code === "ETI") ?? events[0]}));
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
display(outbreakGantt({rows, order, L, dark, width}));
```

## The 15 outbreaks with the highest attack rate

```js
display(Inputs.table(d3.sort(rows, (a, b) => d3.descending(a.attack_rate_per_100k, b.attack_rate_per_100k)).slice(0, 15), {
  columns: Object.keys(L.outbreakCols),
  header: L.outbreakCols,
  format: {total_cases: (d) => fmt(d), attack_rate_per_100k: (d) => fmt(d)}
}));
```

<p class="fineprint"><b>Why are there so few outbreaks between March 2020 and February 2022?</b> It is not a data error. With lockdowns and masks, influenza and respiratory syncytial virus circulated far less, and a good share of respiratory illness was notified as suspected COVID-19, an event that is not in this dataset. Notified ETI fell from 844 thousand cases in 2019 to 346 thousand in 2020 and 478 thousand in 2021, so almost no week exceeded the 75th percentile of the previous years. 2018 has no outbreaks either because it is the first year: there is no history to compare against. And because 2020-2021 enter the 5-year baseline of 2022 to 2025, the 75th percentile of those years is lower and they flag more outbreaks.</p>
