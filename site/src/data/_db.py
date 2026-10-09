"""Shared Databricks access for the Parquet data loaders.

Auth: DATABRICKS_HOST + DATABRICKS_HTTP_PATH, plus DATABRICKS_TOKEN (CI) or, when
no token is set, browser OAuth (local `npm run dev`). Marts live in
`<catalog>.<VIGILANCIA_SCHEMA>_marts` (default dev_vigilancia_respiratoria_ar, as in the CI profile).
"""

import os
import sys
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
from databricks import sql

CATALOG = os.environ.get("VIGILANCIA_CATALOG", "workspace")
MARTS = f"{CATALOG}.{os.environ.get('VIGILANCIA_SCHEMA', 'dev_vigilancia_respiratoria_ar')}_marts"
COMPILED_ANALYSES = (
    Path(__file__).resolve().parents[3] / "target/compiled/vigilancia_respiratoria_ar/analyses"
)


def _connect():
    kw = {
        "server_hostname": os.environ["DATABRICKS_HOST"].removeprefix("https://").rstrip("/"),
        "http_path": os.environ["DATABRICKS_HTTP_PATH"],
    }
    if token := os.environ.get("DATABRICKS_TOKEN"):
        kw["access_token"] = token
    else:
        kw["auth_type"] = "databricks-oauth"
    return sql.connect(**kw)


def emit(query: str) -> None:
    """Run a query and stream the result to stdout as Parquet (the loader contract)."""
    with _connect() as conn, conn.cursor() as cur:
        cur.execute(query)
        table = cur.fetchall_arrow()
        # long official names break chart axes; the site only needs the common short ones
        if "province_name" in table.column_names:
            short = {"Ciudad Autónoma de Buenos Aires": "CABA", "Tierra del Fuego, Antártida e Islas del Atlántico Sur": "Tierra del Fuego"}
            names = [short.get(n, n) for n in table["province_name"].to_pylist()]
            table = table.set_column(table.column_names.index("province_name"), "province_name", pa.array(names))
        # decimals reach the browser as opaque objects; every one here is a rate or a share
        for i, f in enumerate(table.schema):
            if pa.types.is_decimal(f.type):
                table = table.set_column(i, f.name, table[f.name].cast(pa.float64()))
        pq.write_table(table, sys.stdout.buffer)


def emit_analysis(name: str) -> None:
    """Run an already-compiled dbt analysis (written by `dbt docs generate`)."""
    emit((COMPILED_ANALYSES / f"{name}.sql").read_text().strip().rstrip(";"))
