import {interpolateRgbBasis} from "npm:d3-interpolate";

// Red is reserved for "Brote" (outbreak); the blue bands are what is normal for the week;
// the rate of cases per 100k goes from pale amber to dark orange: urgent, not catastrophic.
export const alert = (dark) => (dark ? "#e66767" : "#e34948");
export const rateRamp = (dark) =>
  interpolateRgbBasis(dark ? ["#7a3a0c", "#d9780f", "#f7b44a", "#ffe3a6"] : ["#fde9b8", "#f5a53c", "#d9650f", "#8a3b0a"]);
export const bands = (dark) =>
  dark
    ? {"Éxito": "#222a36", "Seguridad": "#2b3a52", "Alerta": "#35507a"}
    : {"Éxito": "#e8f0fa", "Seguridad": "#cde2fb", "Alerta": "#9ec5f4"};
export const fmt = (n, d = 0, locale = "es-AR") =>
  n == null ? "—" : Number(n).toLocaleString(locale, {maximumFractionDigits: d});
export const toDate = (s) => new Date(`${s}T00:00:00`);
