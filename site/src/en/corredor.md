---
title: Endemic corridor
sql:
  corridor: ../data/corridor.parquet
---

# Endemic corridor: is this week normal for this province?

<p class="lede">The corridor compares each week with the same weeks of the previous 5 years. If cases exceed the 75th percentile of those years, the week enters the <b>outbreak</b> zone. It is the tool used by the National Epidemiological Bulletin.</p>

```js
import {fmt} from "../components/theme.js";
import {t} from "../components/i18n.js";
import {corridorChart, zoneMap} from "../components/charts.js";
const L = t("en");
const events = [...await sql`select distinct event_code, event_name from corridor order by 2`];
const provinceRows = [...await sql`select distinct province_indec_id, province_name from corridor order by 2`];
const provinces = provinceRows.map((d) => d.province_name);
const nameById = new Map(provinceRows.map((d) => [String(d.province_indec_id), d.province_name]));
const geo = await FileAttachment("../data/ar_provinces.geojson").json();
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

${partial.has(year) ? html`<p class="fineprint">${year} is a year in progress: data up to week ${partial.get(year)}.</p>` : ""}

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

<p class="fineprint">Hover over the chart to see how each province was doing that week; click a province on the map to switch to it.</p>

${["2020", "2021"].includes(String(year)) ? html`<p class="fineprint"><b>Careful with ${year}:</b> a good share of respiratory illness was notified as suspected COVID-19, an event that is not in this dataset. Cases of ${L.eventName(event)} look underestimated.</p>` : ""}

<p class="fineprint"><b>How to read it:</b> the solid line is the ${year} case count. The blue bands are what is usual for that week (up to the 25th percentile: <i>success</i>; up to the median: <i>safety</i>; up to the 75th percentile: <i>alert</i>). Above that, the red zone is <i>outbreak</i>, and the red dots mark the weeks in which cases crossed into it. The first years of the dataset (2018–2022) use fewer than 5 years of history; with none, there is no corridor.</p>

<details><summary>View as table</summary>

```js
display(Inputs.table(rows, {columns: Object.keys(L.tableCols), header: L.tableCols, format: {zone: (z) => (z ? L.zones[z] : ""), p25: (d) => fmt(d, 1), p50: (d) => fmt(d, 1), p75: (d) => fmt(d, 1)}}));
```

</details>
