// Data loaders (src/data/*.py) run through `uv run` so they use the project's locked
// `site` dependency group (databricks-sql-connector, pyarrow).
const sections = {
  es: [["Situación actual", "index"], ["Corredor endémico", "corredor"], ["Brotes", "brotes"], ["Hallazgos", "hallazgos"], ["Metodología", "metodologia"]],
  en: [["Current situation", "index"], ["Endemic corridor", "corredor"], ["Outbreaks", "brotes"], ["Findings", "hallazgos"], ["Methodology", "metodologia"]]
};

// Spanish pages live at the root, their English mirrors under /en/. Paths come without
// extension ("/corredor", "/en/corredor"); each home page is "index". The flag links to the
// same page in the other language. Framework resolves header links against the site root and
// adjusts them for the depth of the page, so every link below is written as seen from the root.
const nav = ({path}) => {
  const en = path.startsWith("/en/");
  const slug = en ? path.slice(4) : path.slice(1);
  const href = (s, toEn) => (toEn ? (s === "index" ? "./en/" : `./en/${s}`) : s === "index" ? "./" : `./${s}`);
  return `<a class="brand" href="${href("index", en)}">${en ? "Respiratory surveillance" : "Vigilancia respiratoria"} <b>AR</b></a>
<nav class="site-nav" aria-label="${en ? "Pages" : "Páginas"}">${sections[en ? "en" : "es"]
    .map(([name, s]) => `<a href="${href(s, en)}"${s === slug ? ' aria-current="page"' : ""}>${name}</a>`)
    .join("")}<a class="lang-switch" href="${href(slug, !en)}" hreflang="${en ? "es" : "en"}" title="${en ? "Ver en español" : "View in English"}">${en ? "🇦🇷 Español" : "🇬🇧 English"}</a></nav>`;
};

export default {
  title: "Vigilancia respiratoria AR",
  root: "src",
  base: "/vigilancia-respiratoria-ar/",
  style: "style.css",
  pager: false,
  toc: false,
  sidebar: false,
  header: nav,
  footer: `Datos / Data: Ministerio de Salud de la Nación (SNVS 2.0) y/and RENAPER, CC-BY 4.0 · Contornos / Boundaries: Natural Earth · <a href="https://github.com/datakrdo/vigilancia-respiratoria-ar">código / code</a>`,
  interpreters: {
    ".py": ["uv", "run", "--frozen", "--no-dev", "--group", "site", "--project", "..", "python"]
  }
};
