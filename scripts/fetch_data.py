"""Download the raw respiratory (IRA) files and INDEC population estimates and (optionally) sync them to the
Unity Catalog Volume that `read_files()` reads from.

    uv run --group ingest python scripts/fetch_data.py                 # download only
    uv run --group ingest python scripts/fetch_data.py --upload /Volumes/workspace/bronze/raw_data

Layout written under --out (mirrors the Volume):
    respiratory/           acute respiratory infections (IRA), rolling-window files;
                           .xls/.xlsx also get a `.converted.csv`
    indec_population/      INDEC yearly population estimates by department and sex
                           (needs the INDEC_TOKEN env var, a JWT from api.indec.gob.ar)

Only files whose name or size differ from what is already in the Volume are uploaded,
so a run with nothing new is a no-op. When running in GitHub Actions the number of
uploaded files is exposed as the `uploaded` step output.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
# datos.salud.gob.ar serves the wrong intermediate certificate, so default verification
# fails. The right one (Sectigo DV R36, public) is shipped here and added to the system
# trust store: verification stays on.
SALUD_CA = HERE / "certs" / "sectigo_dv_r36.pem"
SALUD_API = "https://datos.salud.gob.ar/api/3/action/package_show?id="
# SNVS 2.0 dataset: CKAN package id
SALUD_PACKAGE = "vigilancia-de-infecciones-respiratorias-agudas"
# The respiratory dataset also lists a data dictionary, a sheet of an unrelated event and three
# snapshots cut at Excel's 65,535-row limit (2018, 2019 and 2022-09: each later superseded
# by a complete file). Keep only the complete ones.
RESPIRATORY_FILE = re.compile(
    r"^(informacion-publica-respiratorias-nacional(?!-hasta-20220905)|vigilancia-respiratorias-agudas-2018)"
)
# INDEC population estimates at 1 July of each year, by department and sex (Census 2022 base).
# PostgREST-style API; the server caps a page at 1000 rows.
INDEC_API = "https://api.indec.gob.ar/v1/estimaciones_poblacion_departamento_2022_2035"
INDEC_COLUMNS = ["jurisdiccion_cod", "jurisdiccion_nom", "departamento_cod", "departamento_nom", "sexo_cod", "poblacion", "fecha"]
INDEC_PAGE = 1000


def _context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ctx.load_verify_locations(cafile=SALUD_CA)
    return ctx


def _get(url: str, retries: int = 3, headers: dict[str, str] | None = None) -> bytes:
    url = re.sub(r"^http://", "https://", url)
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "vigilancia-respiratoria-ar-fetch/1.0", **(headers or {})})
            with urllib.request.urlopen(req, context=_context(), timeout=120) as r:
                return r.read()
        except OSError as e:
            if isinstance(e, urllib.error.HTTPError):
                print(f"{url} -> HTTP {e.code}: {e.read(300)!r}", file=sys.stderr)
            if attempt == retries:
                raise
            time.sleep(2 * attempt)
    raise AssertionError("unreachable")


def _resources(package_url: str) -> list[str]:
    return [r["url"] for r in json.loads(_get(package_url))["result"]["resources"]]


def _name(url: str) -> str:
    return urllib.parse.unquote(url.rsplit("/", 1)[-1])


def _unmojibake(v):
    if not isinstance(v, str) or "Ã" not in v:
        return v
    try:
        return v.encode("cp1252").decode("utf-8")
    except UnicodeError:
        return v


def _to_csv(path: Path) -> Path:
    """Excel -> UTF-8 comma CSV, every cell as text (keeps zero-padded INDEC codes)."""
    import pandas as pd  # ingest group only

    out = path.with_suffix(".converted.csv")
    df = pd.read_excel(path, dtype=str)
    # some sheets hold UTF-8 text decoded as cp1252 ("CÃ³rdoba"); repair what round-trips
    df = df.apply(lambda col: col.map(_unmojibake))
    df.to_csv(out, index=False)
    return out


def _download_population(out: Path) -> Path:
    token = os.environ.get("INDEC_TOKEN") or sys.exit("INDEC_TOKEN is not set (JWT from api.indec.gob.ar)")
    query = "select=" + ",".join(INDEC_COLUMNS) + "&order=fecha,departamento_cod,sexo_cod&limit=" + str(INDEC_PAGE)
    rows: list[dict] = []
    while True:
        page = json.loads(_get(f"{INDEC_API}?{query}&offset={len(rows)}", headers={"Authorization": f"Bearer {token}"}))
        rows += page
        if len(page) < INDEC_PAGE:
            break
    if not rows:
        sys.exit("INDEC population API returned no rows")
    dest = out / "indec_population" / "estimaciones_departamento.csv"
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=INDEC_COLUMNS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"downloaded {dest.relative_to(out)} ({len(rows):,} rows)")
    return dest


def download(out: Path) -> list[Path]:
    targets: list[tuple[Path, str]] = []
    for url in _resources(SALUD_API + SALUD_PACKAGE):
        name = _name(url)
        if name.lower().endswith((".csv", ".xls", ".xlsx")) and RESPIRATORY_FILE.match(name):
            targets.append((out / "respiratory" / name, url))

    files: list[Path] = [_download_population(out)]
    for dest, url in targets:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(_get(url))
        print(f"downloaded {dest.relative_to(out)} ({dest.stat().st_size:,} bytes)")
        files.append(dest)
        if dest.suffix.lower() in (".xls", ".xlsx"):
            files.append(_to_csv(dest))
    # staging only reads CSVs; the Excel originals stay local
    return [f for f in files if f.suffix.lower() == ".csv"]


def upload(files: list[Path], out: Path, volume: str) -> int:
    """Copy to the Volume the files that are new or whose size changed."""
    if not shutil.which("databricks"):
        sys.exit("databricks CLI not found")
    remote_sizes: dict[str, int] = {}
    for sub in {f.parent.relative_to(out) for f in files}:
        res = subprocess.run(
            ["databricks", "fs", "ls", f"dbfs:{volume}/{sub}", "--output", "json"],
            capture_output=True, text=True,
        )
        if res.returncode != 0:  # first run for a new dataset folder
            subprocess.run(["databricks", "fs", "mkdir", f"dbfs:{volume}/{sub}"], check=True)
        if res.returncode == 0 and res.stdout.strip():
            for e in json.loads(res.stdout):
                remote_sizes[f"{sub}/{e['name']}"] = e.get("size", -1)

    sent = 0
    for f in files:
        rel = f.relative_to(out).as_posix()
        if remote_sizes.get(rel) == f.stat().st_size:
            continue
        subprocess.run(
            ["databricks", "fs", "cp", str(f), f"dbfs:{volume}/{rel}", "--overwrite"],
            check=True,
        )
        print(f"uploaded {rel}")
        sent += 1
    return sent


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--out", type=Path, default=HERE.parent / "data" / "raw")
    ap.add_argument("--upload", metavar="VOLUME_PATH", help="e.g. /Volumes/workspace/bronze/raw_data")
    args = ap.parse_args()

    files = download(args.out)
    sent = upload(files, args.out, args.upload.rstrip("/")) if args.upload else 0
    print(f"{len(files)} csv files, {sent} uploaded")
    if gh := os.environ.get("GITHUB_OUTPUT"):
        with open(gh, "a") as f:
            f.write(f"uploaded={sent}\n")


if __name__ == "__main__":
    main()
