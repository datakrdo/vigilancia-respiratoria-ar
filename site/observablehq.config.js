// Data loaders (src/data/*.py) run through `uv run` so they use the project's locked
// `site` dependency group (databricks-sql-connector, pyarrow).
export default {
  title: "Vigilancia respiratoria AR",
  root: "src",
  base: "/vigilancia-respiratoria-ar/",
  style: "style.css",
  pager: false,
  toc: false,
  sidebar: false,
  header: `<a class="brand" href="./">Vigilancia respiratoria <b>AR</b></a>`,
  footer: `Datos: Ministerio de Salud de la Nación (SNVS 2.0) y RENAPER, CC-BY 4.0 · Contornos: Natural Earth · <a href="https://github.com/datakrdo/vigilancia-respiratoria-ar">código</a>`,
  pages: [
    {name: "Situación actual", path: "/"},
    {name: "Corredor endémico", path: "/corredor"},
    {name: "Brotes", path: "/brotes"},
    {name: "Hallazgos", path: "/hallazgos"},
    {name: "Metodología", path: "/metodologia"},
    {name: "English", path: "/en"}
  ],
  interpreters: {
    ".py": ["uv", "run", "--frozen", "--no-dev", "--group", "site", "--project", "..", "python"]
  }
};
