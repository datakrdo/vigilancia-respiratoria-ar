// Data loaders (src/data/*.py) run through `uv run` so they use the project's locked
// `site` dependency group (databricks-sql-connector, pyarrow).
const pages = [
  {name: "Situación actual", path: "/"},
  {name: "Corredor endémico", path: "/corredor"},
  {name: "Brotes", path: "/brotes"},
  {name: "Hallazgos", path: "/hallazgos"},
  {name: "Metodología", path: "/metodologia"},
  {name: "English", path: "/en"}
];

// Paths come with a leading slash and no extension ("/corredor"); the home page is "/index".
const href = (p) => (p === "/" ? "./" : `.${p}`);
const nav = ({path}) =>
  `<a class="brand" href="./">Vigilancia respiratoria <b>AR</b></a>
<nav class="site-nav" aria-label="Páginas">${pages
    .map((d) => `<a href="${href(d.path)}"${(path === "/index" ? "/" : path) === d.path ? ' aria-current="page"' : ""}>${d.name}</a>`)
    .join("")}</nav>`;

export default {
  title: "Vigilancia respiratoria AR",
  root: "src",
  base: "/vigilancia-respiratoria-ar/",
  style: "style.css",
  pager: true,
  toc: false,
  sidebar: false,
  header: nav,
  footer: `Datos: Ministerio de Salud de la Nación (SNVS 2.0) y RENAPER, CC-BY 4.0 · Contornos: Natural Earth · <a href="https://github.com/datakrdo/vigilancia-respiratoria-ar">código</a>`,
  pages,
  interpreters: {
    ".py": ["uv", "run", "--frozen", "--no-dev", "--group", "site", "--project", "..", "python"]
  }
};
