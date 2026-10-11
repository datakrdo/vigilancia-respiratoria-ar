import * as Plot from "npm:@observablehq/plot";
import {alert, bands, rateRamp} from "./theme.js";

// Charts shared by the Spanish and English pages; L comes from i18n.js `t(lang)`.
// Tooltips name their channels explicitly so the reader never sees column names.

const hide = {x: false, y: false, r: false, fill: false};

export function rateMap({depts, provinces, L, dark, width}) {
  return Plot.plot({
    width: Math.min(width, 640),
    height: 840,
    projection: {type: "mercator", domain: provinces, inset: 12},
    r: {range: [1.5, 24]},
    color: {type: "sqrt", interpolate: rateRamp(dark), unknown: "#8d8c86", legend: true, label: L.rateLegend},
    marks: [
      Plot.geo(provinces, {fill: "var(--land)", stroke: "var(--line)"}),
      Plot.dot(depts, {
        x: "centroid_lon", y: "centroid_lat", r: "case_count", fill: "rate_per_100k",
        fillOpacity: 0.85, stroke: "var(--surface)", strokeWidth: 0.6, sort: {channel: "-r"},
        channels: {
          [L.department]: "department_name",
          [L.province]: "province_name",
          [L.cases]: (d) => L.fmt(d.case_count),
          [L.rate]: (d) => (d.rate_per_100k == null ? L.noPopulation : L.per100k(L.fmt(d.rate_per_100k, 1)))
        },
        tip: {format: hide}
      })
    ]
  });
}

export function rateBars({prov, L}) {
  const bar = (data, extra) =>
    Plot.barX(data, {
      y: "province_name", x: "rate", fill: "var(--accent)", ...extra,
      channels: {[L.province]: "province_name", [L.rate]: (d) => L.per100k(L.fmt(d.rate, 1)), [L.cases]: (d) => L.fmt(d.cases)},
      tip: {format: hide}
    });
  return Plot.plot({
    marginLeft: 150,
    height: 24 * prov.length + 40,
    x: {label: L.rateAxis, grid: true},
    y: {label: null, domain: prov.map((d) => d.province_name)},
    marks: [bar(prov.filter((d) => d.cases >= 20)), bar(prov.filter((d) => d.cases < 20), {fillOpacity: 0.35}), Plot.ruleX([0])]
  });
}

// Weekly cases over the corridor bands. The element's value is the epi week under the
// pointer (the last week when the pointer is away), so a map can follow it via `view()`.
export function corridorChart({rows, L, dark, width, lastWeek}) {
  if (rows.length === 0) return Object.assign(document.createElement("p"), {textContent: L.noData});
  const withBase = rows.filter((d) => d.p75 != null);
  const top = Math.max(...rows.map((d) => Math.max(d.case_count, d.p75 ?? 0))) * 1.1 || 1;
  const c = bands(dark);
  const plot = Plot.plot({
    width,
    height: 420,
    x: {label: L.weekAxis, ticks: 13},
    y: {label: L.casesPerWeek, grid: true, domain: [0, top]},
    marks: [
      Plot.areaY(withBase, {x: "epi_week", y1: 0, y2: "p25", fill: c["Éxito"]}),
      Plot.areaY(withBase, {x: "epi_week", y1: "p25", y2: "p50", fill: c["Seguridad"]}),
      Plot.areaY(withBase, {x: "epi_week", y1: "p50", y2: "p75", fill: c["Alerta"]}),
      Plot.areaY(withBase, {x: "epi_week", y1: "p75", y2: top, fill: alert(dark), fillOpacity: 0.14}),
      Plot.lineY(withBase, {x: "epi_week", y: "p50", stroke: "var(--ink-2)", strokeDasharray: "3,3", strokeWidth: 1}),
      Plot.lineY(rows, {x: "epi_week", y: "case_count", stroke: "var(--ink)", strokeWidth: 2}),
      Plot.dot(rows.filter((d) => d.zone === "Brote"), {x: "epi_week", y: "case_count", fill: alert(dark), stroke: "var(--surface)", r: 4.5}),
      Plot.ruleY([0]),
      Plot.tip(rows, Plot.pointerX({x: "epi_week", y: "case_count", title: L.corridorTipFor}))
    ]
  });
  const weeks = new Set(rows.map((d) => d.epi_week));
  const xs = plot.scale("x");
  const set = (w) => {
    if (plot.value === w) return;
    plot.value = w;
    plot.dispatchEvent(new CustomEvent("input"));
  };
  plot.value = lastWeek;
  plot.addEventListener("pointermove", (e) => {
    const box = plot.getBoundingClientRect();
    const w = Math.round(xs.invert(((e.clientX - box.left) * width) / box.width));
    if (weeks.has(w)) set(w);
  });
  plot.addEventListener("pointerleave", () => set(lastWeek));
  return plot;
}

// Provinces colored by corridor zone in one epi week; the selected one is outlined and
// clicking a province calls onSelect(province_name).
export function zoneMap({features, zoneById, nameById, selectedName, week, L, dark, onSelect}) {
  const band = bands(dark);
  const colors = {"Éxito": band["Éxito"], "Seguridad": band["Seguridad"], "Alerta": band["Alerta"], "Brote": alert(dark)};
  const feats = features.map((f) => {
    const id = String(f.properties.province_indec_id);
    return {...f, properties: {id, name: nameById.get(id) ?? f.properties.name, zone: L.zoneLabel(zoneById.get(id))}};
  });
  const plot = Plot.plot({
    width: 340,
    height: 520,
    projection: {type: "mercator", domain: {type: "FeatureCollection", features}, inset: 6},
    color: {
      domain: [...Object.keys(colors).map((z) => L.zones[z]), L.noCorridor],
      range: [...Object.values(colors), "#8d8c86"],
      legend: true
    },
    title: L.mapWeek(week),
    marks: [
      Plot.geo(feats, {
        fill: (d) => d.properties.zone, stroke: "var(--surface)", strokeWidth: 0.6, style: "cursor: pointer",
        channels: {[L.province]: (d) => d.properties.name, [L.zone]: (d) => d.properties.zone},
        tip: {format: {fill: false}}
      }),
      Plot.geo(feats.filter((f) => f.properties.name === selectedName), {fill: "none", stroke: "var(--ink)", strokeWidth: 2.5, pointerEvents: "none"})
    ]
  });
  plot.querySelector('[aria-label="geo"]').querySelectorAll("path").forEach((path, i) =>
    path.addEventListener("click", () => onSelect(feats[i].properties.name))
  );
  return plot;
}

export function outbreakGantt({rows, order, L, dark, width}) {
  return Plot.plot({
    width,
    marginLeft: 150,
    marginTop: 24,
    height: 24 * order.length + 60,
    x: {label: null, type: "utc"},
    y: {label: null, domain: order},
    color: {type: "sqrt", interpolate: rateRamp(dark), unknown: "#8d8c86", legend: true, label: L.attackRate},
    marks: [
      Plot.rectX([{x1: new Date(Date.UTC(2020, 2, 1)), x2: new Date(Date.UTC(2022, 2, 1))}], {x1: "x1", x2: "x2", fill: "var(--ink-2)", fillOpacity: 0.12}),
      Plot.text([{x: new Date(Date.UTC(2020, 2, 1))}], {x: "x", frameAnchor: "top", dy: -14, textAnchor: "start", text: () => L.covidLabel, fill: "var(--ink-2)", fontSize: 11}),
      Plot.ruleY(order, {stroke: "var(--line)"}),
      Plot.barX(rows, {y: "province_name", x1: "start", x2: "end", fill: "attack_rate_per_100k", inset: 1, title: (d) => L.outbreakTip(d, L.fmt), tip: true})
    ]
  });
}

export function excessChart({t, L}) {
  return Plot.plot({
    marginLeft: 130, height: 40 * t.length + 40,
    x: {label: L.excessAxis, grid: true},
    y: {label: null, domain: t.map((d) => d.province_name)},
    marks: [
      Plot.barX(t, {y: "province_name", x: "total_excess_per_100k", fill: "var(--accent)", title: (d) => L.excessTip(d, L.fmt), tip: true}),
      Plot.ruleX([0])
    ]
  });
}

export function peakChart({sp, median, L}) {
  return Plot.plot({
    marginLeft: 130, height: 22 * sp.length + 60,
    x: {label: L.peakAxis, grid: true, domain: [1, 52]},
    y: {label: null, domain: sp.map((d) => d.province_name)},
    marks: [
      Plot.rectX([{a: median - 3, b: median + 3}], {x1: "a", x2: "b", fill: "var(--accent)", fillOpacity: 0.12}),
      Plot.ruleX([median], {stroke: "var(--accent)"}),
      Plot.dot(sp, {x: "peak_epi_week", y: "province_name", fill: "var(--accent)", r: 4, title: L.peakTip, tip: true})
    ]
  });
}

export function hotspotChart({hot, L}) {
  const [a, b, c] = L.hotSeries;
  const jac = hot.filter((d) => d.jaccard_similarity_to_prior_season != null);
  return Plot.plot({
    height: 300, marginBottom: 50,
    x: {label: L.season, tickRotate: -20, domain: hot.map((d) => d.season_label)},
    y: {label: L.hotIndex, domain: [0, 1], grid: true},
    color: {legend: true, domain: [a, b, c], range: ["#2a78d6", "#eb6834", "#1baf7a"]},
    marks: [
      Plot.line(hot, {x: "season_label", y: "gini_coefficient", stroke: () => a, strokeWidth: 2}),
      Plot.line(hot, {x: "season_label", y: "population_weighted_gini_coefficient", stroke: () => b, strokeWidth: 2}),
      Plot.line(jac, {x: "season_label", y: "jaccard_similarity_to_prior_season", stroke: () => c, strokeWidth: 2}),
      Plot.dot(hot, {x: "season_label", y: "gini_coefficient", fill: "#2a78d6"}),
      Plot.dot(hot, {x: "season_label", y: "population_weighted_gini_coefficient", fill: "#eb6834"}),
      Plot.dot(jac, {x: "season_label", y: "jaccard_similarity_to_prior_season", fill: "#1baf7a"}),
      Plot.ruleY([0])
    ]
  });
}

export function ratioChart({prov, L, dark}) {
  return Plot.plot({
    marginLeft: 150, height: 26 * prov.length + 50,
    x: {type: "log", label: L.ratioAxis, grid: true, ticks: [0.25, 0.5, 1, 2, 4, 8, 16, 32], tickFormat: (d) => `×${d}`},
    y: {label: null, domain: prov.map((d) => d.province_name)},
    color: {domain: [true, false], range: [alert(dark), "#8d8c86"]},
    marks: [
      Plot.ruleX([1], {stroke: "var(--ink)"}),
      Plot.ruleY(prov, {y: "province_name", x1: "ci95_low", x2: "ci95_high", stroke: "is_materially_elevated", strokeWidth: 2}),
      Plot.dot(prov, {y: "province_name", x: "rate_ratio_vs_rest_of_country", fill: "is_materially_elevated", r: 4, title: (d) => L.ratioTip(d, L.fmt), tip: true})
    ]
  });
}

export function nowcastChart({nc, L}) {
  return Plot.plot({
    height: 300, marginRight: 30,
    x: {type: "log", label: L.lagAxis, ticks: nc.map((d) => d.avg_reporting_lag_days), tickFormat: L.lagUnit},
    y: {label: L.knownAxis, domain: [0, 100], grid: true},
    marks: [
      Plot.areaY(nc, {x: "avg_reporting_lag_days", y1: "known_p90", y2: "known", fill: "var(--accent)", fillOpacity: 0.2}),
      Plot.line(nc, {x: "avg_reporting_lag_days", y: "known", stroke: "var(--accent)", strokeWidth: 2}),
      Plot.dot(nc, {x: "avg_reporting_lag_days", y: "known", fill: "var(--accent)", r: 4, title: (d) => L.nowcastTip(d, L.fmt, L.bucket(d.reporting_lag_bucket)), tip: true}),
      Plot.text(nc, {x: "avg_reporting_lag_days", y: "known", text: (d) => `${L.fmt(d.known, 0)}%`, dy: -12, fontWeight: "bold"}),
      Plot.ruleY([100])
    ]
  });
}
