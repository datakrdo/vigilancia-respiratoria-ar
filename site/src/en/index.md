---
title: Current situation
sql:
  departments: ../data/departments.parquet
  corridor: ../data/corridor.parquet
---

# Respiratory infections in Argentina: where the risk is, not just where the cases are

<p class="lede">Cases notified to SNVS 2.0 by department of residence, with the rate per 100,000 population. A big province always adds up more cases; the rate and the <a href="./corredor">endemic corridor</a> say whether the situation is really abnormal.</p>

```js
import {t} from "../components/i18n.js";
import {rateMap, rateBars} from "../components/charts.js";
const L = t("en");
const {fmt} = L;
const events = [...await sql`select distinct event_code, event_name from departments order by 2`];
const yearInfo = [...await sql`select year, cast(max(last_epi_week) as int) as wk from departments where case_count > 0 group by year order by year desc`];
const years = yearInfo.map((d) => d.year);
const partial = new Map(yearInfo.filter((d) => d.wk < 52).map((d) => [d.year, d.wk]));
const yearLabel = (y) => (partial.has(y) ? L.partial(y) : String(y));
const defaultYear = yearInfo[0].year;
```

<div class="controls">

```js
const event = view(Inputs.radio(events, {label: L.event, format: L.eventName, value: events.find((d) => d.event_code === "ETI") ?? events[0]}));
const year = view(Inputs.radio(years, {label: L.year, format: yearLabel, value: defaultYear}));
```

</div>

${partial.has(year) ? html`<p class="fineprint">${year} is a year in progress: data up to week ${partial.get(year)}.</p>` : ""}

```js
const depts = [...await sql`
  select department_name, province_name, centroid_lat, centroid_lon, case_count, rate_per_100k, last_epi_week
  from departments where event_code = ${event.event_code} and year = ${year} and case_count > 0`];
const provinces = await FileAttachment("../data/ar_provinces.geojson").json();
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
const delta = (c, label) => c ? html`<div class="kpi"><div class="n">${c.pct > 0 ? "▲" : c.pct < 0 ? "▼" : "="} ${fmt(Math.abs(c.pct), 0)}%</div><div class="l">${label}: ${fmt(c.now)} cases against ${fmt(c.before)} in ${year - 1}</div></div>` : "";
```

<div class="kpis">
  <div class="kpi"><div class="n">${fmt(total)}</div><div class="l">cases notified in ${year}${lastWeek ? ` (up to week ${lastWeek})` : ""}</div></div>
  ${delta(vsWeek, `week ${ref} compared with the same week`)}
  ${delta(vs4, `the 4 weeks up to week ${ref} compared with the same weeks`)}
  <div class="kpi"><div class="n">${prov[0] ? prov[0].province_name : "—"}</div><div class="l">highest rate: ${prov[0] ? fmt(prov[0].rate, 1) : "—"} cases per 100,000 pop.</div></div>
  <div class="kpi alert"><div class="n">${fmt(inBrote.length)}</div><div class="l">provinces in the outbreak zone in week ${ref}${inBrote.length ? `: ${inBrote.map((d) => d.province_name).join(", ")}` : ""}</div></div>
</div>

## Map by department

The circle size is the number of cases; the color, the rate per 100,000 population. Gray circles have no reference population (CABA's comunas are only published as a whole city).

```js
display(rateMap({depts, provinces, L, dark, width}));
```

## Rate by province

${total === 0 ? html`<p class="fineprint"><b>No cases of ${L.eventName(event)} were notified in ${year}.</b> Pick another event or year.</p>` : ""}

```js
display(rateBars({prov, L}));
```

${["2020", "2021"].includes(String(year)) ? html`<p class="fineprint"><b>Careful with ${year}:</b> a good share of respiratory illness was notified as suspected COVID-19, an event that is not in this dataset. Cases of ${L.eventName(event)} look underestimated.</p>` : ""}

<p class="fineprint">Comparisons use the last consolidated week: the final two weeks of the running year are dropped because they are always incomplete. Light bars are provinces with fewer than 20 cases: with so few cases the rate is unstable and should not be compared. Notifications are corrected over time: the most recent weeks tend to be underestimated (see <a href="./hallazgos#reporting-delay">reporting delay</a>). Data by the case's residence, not place of infection. Rates also depend on how much each jurisdiction notifies: Santa Fe and CABA notify very little ETI to SNVS 2.0 (Santa Fe, 52 cases per 100,000 in 2025 against 3,379 in Córdoba), so their low rates do not mean less disease.</p>
