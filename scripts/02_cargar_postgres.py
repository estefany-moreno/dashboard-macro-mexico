import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import bindparam, create_engine, text

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / "env.env")

def _require_env(name: str, *, allow_empty: bool = False) -> str:
    value = os.getenv(name)
    if value is None or (not allow_empty and value == ""):
        raise ValueError(f"Variable de entorno no definida: {name} (revisa {ROOT / 'env.env'})")
    return value

# ── Conexión ───────────────────────────────────────────────────────────────
engine = create_engine(
    f"postgresql+psycopg2://{_require_env('DB_USER')}:{_require_env('DB_PASSWORD', allow_empty=True)}"
    f"@{_require_env('DB_HOST')}:{_require_env('DB_PORT')}/{_require_env('DB_NAME')}"
)

# ── Cargar metadatos (SQL externo) ─────────────────────────────────────────
# El SQL usa ON CONFLICT DO UPDATE: se puede ejecutar varias veces sin error.
with engine.connect() as conn:
    with open(ROOT / "sql/02_cargar_datos.sql", encoding="utf-8") as f:
        sql = f.read()
    conn.execute(text(sql))
    conn.commit()
print("✓ Metadatos de indicadores cargados (insert/update)")

# ── Cargar observaciones ───────────────────────────────────────────────────
df = pd.read_csv(ROOT / "data/processed/series_seleccionadas.csv", parse_dates=["fecha"])

# Re-ejecutable: borra observaciones previas de las series del CSV
# antes de insertar, para evitar duplicados en (indicador_id, fecha).
indicadores_csv = df["indicador_id"].unique().tolist()
delete_stmt = text(
    "DELETE FROM observaciones WHERE indicador_id IN :ids"
).bindparams(bindparam("ids", expanding=True))

with engine.connect() as conn:
    deleted = conn.execute(delete_stmt, {"ids": indicadores_csv}).rowcount
    conn.commit()

if deleted:
    print(f"  Observaciones previas eliminadas: {deleted:,}")

df.to_sql(
    name="observaciones",
    con=engine,
    if_exists="append",
    index=False,
    method="multi",
    chunksize=500,
)

print(f"✓ Observaciones cargadas: {len(df):,} filas")

# ── Verificación rápida ────────────────────────────────────────────────────
with engine.connect() as conn:
    result = conn.execute(text("""
        SELECT i.nombre, COUNT(o.obs_id) AS n_obs,
               MIN(o.fecha) AS desde, MAX(o.fecha) AS hasta
        FROM observaciones o
        JOIN indicadores i USING (indicador_id)
        GROUP BY i.nombre
        ORDER BY i.nombre;
    """))
    print("\n── Resumen de carga ──────────────────────────────")
    print(f"{'Indicador':<35} {'Obs':>6}  {'Desde':>12}  {'Hasta':>12}")
    print("─" * 70)
    for row in result:
        print(f"{row.nombre:<35} {row.n_obs:>6}  {str(row.desde):>12}  {str(row.hasta):>12}")