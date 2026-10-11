---
title: Findings
sql:
  timing: ../data/find_season_timing.parquet
  spread: ../data/find_spread.parquet
  hotspots: ../data/find_hotspots.parquet
  warning: ../data/find_early_warning.parquet
  provinces: ../data/find_provinces.parquet
  nowcast: ../data/find_nowcast.parquet
---

# Six questions the data can answer

<p class="lede">Each finding starts from a concrete surveillance question, is computed in SQL over the same tables that feed the rest of the site, and ends with what to do with the answer. Some results are negative, which makes them useful.</p>

```js
import {t} from "../components/i18n.js";
import {excessChart, peakChart, hotspotChart, ratioChart, nowcastChart} from "../components/charts.js";
const L = t("en");
const {fmt} = L;
const num = (rows) => rows.map((d) => Object.fromEntries(Object.entries(d).map(([k, v]) => [k, typeof v === "bigint" ? Number(v) : v])));
```

<div class="finding" id="excess-over-the-corridor">

## 1. Which provinces suffered most, once size is discounted?

<p class="so-what">Ranking by total cases rewards big provinces. Ranked by excess over the corridor ceiling per 100,000 population, the ranking changes.</p>

</div>

```js
const timing = num([...await sql`select * from timing order by season_start_year desc, total_excess_per_100k desc`]);
const seasons = [...new Set(timing.map((d) => d.season_label))];
const season = view(Inputs.radio(seasons, {label: L.season, value: seasons[0]}));
```

```js
const tm = timing.filter((d) => d.season_label === season);
display(excessChart({t: tm, L}));
```

<div class="finding" id="north-south-gradient">

## 2. Does the season travel from north to south?

<p class="so-what">No: the whole country peaks together. In 2024, 23 of the 24 provinces peaked within 3 weeks of the median (week 24); in 2023 and 2025, 17 and 18. Only the pandemic-disrupted seasons (2021-2022) are scattered. Do not wait for the outbreak to "come down" from the north: watch all provinces at once.</p>

</div>

```js
const spread = num([...await sql`select * from spread order by season_start_year desc, province_lat desc`]);
const spSeasons = [...new Set(spread.map((d) => d.season_label))];
const spSeason = view(Inputs.radio(spSeasons, {label: L.season, value: spSeasons[0]}));
```

```js
const sp = spread.filter((d) => d.season_label === spSeason);
const spMedian = d3.median(sp, (d) => d.peak_epi_week);
const spNear = sp.filter((d) => Math.abs(d.peak_epi_week - spMedian) <= 3).length;
```

<div class="kpis">
  <div class="kpi"><div class="n">${fmt(spMedian)}</div><div class="l">median epidemiological week of the peak</div></div>
  <div class="kpi"><div class="n">${fmt(spNear)} of ${fmt(sp.length)}</div><div class="l">provinces peaked within 3 weeks of that median</div></div>
  <div class="kpi"><div class="n">${fmt(d3.max(sp, (d) => d.peak_epi_week) - d3.min(sp, (d) => d.peak_epi_week))} wk.</div><div class="l">between the first and the last province to peak</div></div>
</div>

```js
display(peakChart({sp, median: spMedian, L}));
```

<p class="fineprint">Provinces ordered north to south. The band marks the median ± 3 weeks. If the season came down from the north, the dots would form a diagonal; they do not. The peak is the province's week with the most cases in the season.</p>

<div class="finding" id="early-warning">

## 3. Does a growth signal work as an outbreak alert?

<p class="so-what">On its own, no: it detects about 1 in 5 outbreaks, and 2 in 3 signals do not end in an outbreak. But when it is right, it warns weeks ahead; use it as a signal to review, not as an automatic alarm.</p>

</div>

```js
const w = num([...await sql`select * from warning`])[0] ?? {};
```

<div class="kpis">
  <div class="kpi"><div class="n">${fmt(w.recall_pct, 1)}%</div><div class="l">of outbreaks (${fmt(w.outbreaks_with_advance_signal)} of ${fmt(w.total_outbreaks)}) had an earlier signal</div></div>
  <div class="kpi"><div class="n">${fmt(w.precision_pct, 1)}%</div><div class="l">of signals (${fmt(w.signals_confirmed_by_outbreak)} of ${fmt(w.total_growth_signals)}) were followed by an outbreak</div></div>
  <div class="kpi"><div class="n">${fmt(w.median_lead_time_weeks, 1)} wk.</div><div class="l">median lead time when the signal is right</div></div>
  <div class="kpi"><div class="n">${fmt(w.p10_lead_time_weeks_conservative, 1)} wk.</div><div class="l">lead time in the conservative case (10th percentile)</div></div>
</div>

<div class="finding" id="concentration-and-persistence">

## 4. Are hot spots concentrated, and the same every year?

<p class="so-what">About a quarter of departments hold 80% of the cases, and hot spots repeat only in part: the overlap with the previous season runs from 0.45 to 0.66. Always reinforcing the same places leaves out part of the new hot spots.</p>

</div>

```js
const hot = num([...await sql`select * from hotspots order by season_start_year`]);
display(hotspotChart({hot, L}));
```

<p class="fineprint">The weighted Gini is lower than the case Gini: part of the apparent concentration is just where people live, not higher risk.</p>

<div class="finding" id="significant-excess">

## 5. Which provinces have a truly higher rate, and not just noise?

<p class="so-what">A small province can have a high rate by chance. The rate ratio with its 95% confidence interval separates a real excess (the interval does not cross 1) from a fluctuation. With over a million cases a year even a 2% difference comes out "significant", so a rate ratio of at least 1.5 is also required.</p>

</div>

```js
const prov = num([...await sql`select * from provinces order by rate_ratio_vs_rest_of_country desc`]);
display(ratioChart({prov, L, dark}));
```

<p class="fineprint">Red: significant excess of at least ×1.5. Gray: does not meet both conditions. Rate differences also reflect how much each jurisdiction notifies.</p>

<div class="finding" id="reporting-delay">

## 6. How much should last week's numbers be corrected?

<p class="so-what">A lot: among the periods that get revised, the first value published within the first week is, at the median, 28% of the final one (×3.5); between 8 and 30 days, 50% (×2); between 31 and 90, 67%; after 90 days, 75% (×1.3). The numbers for the latest week should always be read as a floor.</p>

</div>

```js
const nc = num([...await sql`select * from nowcast order by avg_reporting_lag_days`])
  .map((d) => ({...d, known: 100 / d.median_correction_factor, known_p90: 100 / d.p90_correction_factor}));
display(nowcastChart({nc, L}));
```

<p class="fineprint">Line: median. Band: up to the unfavorable case (90th percentile). It only counts periods that were later revised, so it overstates the correction of a typical week. The 0 to 7 day lag has few periods (826).</p>
