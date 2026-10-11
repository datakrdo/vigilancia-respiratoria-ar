import {fmt} from "./theme.js";

// UI strings that live inside charts, controls and tooltips. Page prose is written in each
// language's own .md file; data values (province names, corridor zones) stay in Spanish
// and are translated here when displayed.
const es = {
  locale: "es-AR",
  zone: "Zona", event: "Evento", year: "Año", province: "Provincia", season: "Temporada", department: "Departamento",
  cases: "Casos", rate: "Tasa", noPopulation: "sin población de referencia",
  events: {ETI: "Enfermedad tipo influenza (ETI)", BRONQUIOLITIS: "Bronquiolitis en menores de 2 años", NEUMONIA: "Neumonía"},
  zones: {"Éxito": "Éxito", "Seguridad": "Seguridad", "Alerta": "Alerta", "Brote": "Brote"},
  noCorridor: "Sin corredor",
  partial: (y) => `${y} · parcial`,
  rateLegend: "Casos cada 100.000 hab.",
  rateAxis: "Casos cada 100.000 habitantes",
  casesUnit: (n) => `${n} casos`,
  per100k: (n) => `${n} cada 100.000`,
  week: "Semana", weekAxis: "Semana epidemiológica", casesPerWeek: "Casos por semana",
  noData: "Sin datos para esta combinación.",
  corridorTip: (d, f) => `Semana ${d.epi_week} (${d.week_start_date})\n${f(d.case_count)} casos\n${d.zone ? `Zona: ${d.zones[d.zone]}` : "Sin años previos para comparar"}${d.p75 != null ? `\nMediana ${f(d.p50)} · p75 ${f(d.p75)}` : ""}`,
  tableCols: {epi_week: "Semana", week_start_date: "Inicio", case_count: "Casos", zone: "Zona", p25: "p25", p50: "p50", p75: "p75", n_years: "Años de base"},
  mapWeek: (w) => `Semana ${w}`,
  // brotes
  outbreakTip: (d, f) => `${d.province_name}\n${d.outbreak_start_date} → ${d.outbreak_end_date} (${d.duration_weeks} sem.)\n${f(d.total_cases)} casos · pico semanal ${f(d.peak_case_count)}\nTasa de ataque ${f(d.attack_rate_per_100k)} cada 100.000`,
  attackRate: "Tasa de ataque (casos cada 100.000 hab.)",
  covidLabel: "COVID-19: cuadros respiratorios notificados como sospecha de COVID",
  outbreakCols: {province_name: "Provincia", outbreak_start_date: "Inicio", duration_weeks: "Semanas", total_cases: "Casos", attack_rate_per_100k: "Tasa de ataque"},
  // hallazgos
  excessAxis: "Casos en exceso sobre el percentil 75, cada 100.000 hab.",
  excessTip: (d, f) => `${d.province_name}\nExceso: ${f(d.total_excess_cases_over_corridor)} casos (${f(d.total_excess_per_100k)} cada 100.000)\nLlegó al 50% de los casos en la semana ${d.epi_week_reaching_50pct} y al 90% en la semana ${d.epi_week_reaching_90pct}`,
  peakAxis: "Semana epidemiológica del pico de casos",
  peakTip: (d) => `${d.province_name}\nPico en la semana ${d.peak_epi_week}`,
  hotIndex: "Índice (0 a 1)",
  hotSeries: ["Gini de casos", "Gini ponderado por población", "Superposición con la temporada previa (Jaccard)"],
  ratioAxis: "Razón de tasas vs. el resto del país (escala logarítmica)",
  ratioTip: (d, f) => `${d.province_name}\nRazón de tasas ${f(d.rate_ratio_vs_rest_of_country, 2)} (IC 95%: ${f(d.ci95_low, 2)}–${f(d.ci95_high, 2)})\n${f(d.province_rate_per_100k, 1)} casos cada 100.000`,
  lagAxis: "Días entre el fin de la semana y la primera publicación",
  lagUnit: (d) => `${d} d`,
  knownAxis: "% del valor final ya conocido",
  bucket: (s) => s.replace("days", "días"),
  nowcastTip: (d, f, bucket) => `${bucket}: ${f(d.n_periods)} períodos revisados\nMediana: se conoce el ${f(d.known, 0)}% del final (×${d.median_correction_factor})\nPercentil 90: solo el ${f(d.known_p90, 0)}% (×${d.p90_correction_factor})`
};

const en = {
  locale: "en-US",
  zone: "Zone", event: "Event", year: "Year", province: "Province", season: "Season", department: "Department",
  cases: "Cases", rate: "Rate", noPopulation: "no reference population",
  events: {ETI: "Influenza-like illness (ILI)", BRONQUIOLITIS: "Bronchiolitis in children under 2", NEUMONIA: "Pneumonia"},
  zones: {"Éxito": "Success", "Seguridad": "Safety", "Alerta": "Alert", "Brote": "Outbreak"},
  noCorridor: "No corridor",
  partial: (y) => `${y} · partial`,
  rateLegend: "Cases per 100,000 pop.",
  rateAxis: "Cases per 100,000 population",
  casesUnit: (n) => `${n} cases`,
  per100k: (n) => `${n} per 100,000`,
  week: "Week", weekAxis: "Epidemiological week", casesPerWeek: "Cases per week",
  noData: "No data for this combination.",
  corridorTip: (d, f) => `Week ${d.epi_week} (${d.week_start_date})\n${f(d.case_count)} cases\n${d.zone ? `Zone: ${d.zones[d.zone]}` : "No previous years to compare"}${d.p75 != null ? `\nMedian ${f(d.p50)} · p75 ${f(d.p75)}` : ""}`,
  tableCols: {epi_week: "Week", week_start_date: "Start", case_count: "Cases", zone: "Zone", p25: "p25", p50: "p50", p75: "p75", n_years: "Baseline years"},
  mapWeek: (w) => `Week ${w}`,
  outbreakTip: (d, f) => `${d.province_name}\n${d.outbreak_start_date} → ${d.outbreak_end_date} (${d.duration_weeks} wk.)\n${f(d.total_cases)} cases · weekly peak ${f(d.peak_case_count)}\nAttack rate ${f(d.attack_rate_per_100k)} per 100,000`,
  attackRate: "Attack rate (cases per 100,000 pop.)",
  covidLabel: "COVID-19: respiratory illness reported as suspected COVID",
  outbreakCols: {province_name: "Province", outbreak_start_date: "Start", duration_weeks: "Weeks", total_cases: "Cases", attack_rate_per_100k: "Attack rate"},
  excessAxis: "Cases above the 75th percentile, per 100,000 pop.",
  excessTip: (d, f) => `${d.province_name}\nExcess: ${f(d.total_excess_cases_over_corridor)} cases (${f(d.total_excess_per_100k)} per 100,000)\nReached 50% of cases in week ${d.epi_week_reaching_50pct} and 90% in week ${d.epi_week_reaching_90pct}`,
  peakAxis: "Epidemiological week of the case peak",
  peakTip: (d) => `${d.province_name}\nPeak in week ${d.peak_epi_week}`,
  hotIndex: "Index (0 to 1)",
  hotSeries: ["Case Gini", "Population-weighted Gini", "Overlap with previous season (Jaccard)"],
  ratioAxis: "Rate ratio vs. rest of the country (log scale)",
  ratioTip: (d, f) => `${d.province_name}\nRate ratio ${f(d.rate_ratio_vs_rest_of_country, 2)} (95% CI: ${f(d.ci95_low, 2)}–${f(d.ci95_high, 2)})\n${f(d.province_rate_per_100k, 1)} cases per 100,000`,
  lagAxis: "Days between the end of the week and first publication",
  lagUnit: (d) => `${d} d`,
  knownAxis: "% of the final value already known",
  bucket: (s) => s,
  nowcastTip: (d, f, bucket) => `${bucket}: ${f(d.n_periods)} revised periods\nMedian: ${f(d.known, 0)}% of the final count is known (×${d.median_correction_factor})\n90th percentile: only ${f(d.known_p90, 0)}% (×${d.p90_correction_factor})`
};

export function t(lang) {
  const L = lang === "en" ? en : es;
  const f = (n, d = 0) => fmt(n, d, L.locale);
  return {
    ...L,
    lang,
    fmt: f,
    eventName: (e) => L.events[e.event_code] ?? e.event_name,
    zoneLabel: (z) => (z ? L.zones[z] : L.noCorridor),
    corridorTipFor: (d) => L.corridorTip({...d, zones: L.zones}, f)
  };
}
