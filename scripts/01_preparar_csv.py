import pandas as pd
from pathlib import Path

# ── Rutas (relativas a la raíz del proyecto) ───────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
RUTA_RAW = ROOT / "data/raw/panel_desestacionalizado.csv"
RUTA_OUT = ROOT / "data/processed/series_seleccionadas.csv"
RUTA_OUT.parent.mkdir(parents=True, exist_ok=True)

# ── Series que usaremos ────────────────────────────────────────────────────
# Clave interna : nombre de columna en panel_desestacionalizado.csv
SERIES = {
    "igae_total":          "IGAE_Total",
    "produccion_industrial":"Produccion_industrial",
    "inpc":                "INPC",
    "tasa_desocupacion":   "Tasa_desocupacion",
    "tc_fix":              "TC_FIX",
    "cetes_28":            "CETES_28_dias",
    "tasa_objetivo":       "Tasa_objetivo",
}

# ── Leer el panel ──────────────────────────────────────────────────────────
df = pd.read_csv(RUTA_RAW, index_col=0, parse_dates=True)
df.index.name = "fecha"

# Verificar que las columnas existan
faltantes = [col for col in SERIES.values() if col not in df.columns]
if faltantes:
    raise ValueError(f"Columnas no encontradas en el panel: {faltantes}")

# ── Seleccionar y renombrar ────────────────────────────────────────────────
df_sel = df[list(SERIES.values())].copy()
df_sel.columns = list(SERIES.keys())   # renombrar a claves internas

# ── Pasar a formato largo (long format) ───────────────────────────────────
df_long = (
    df_sel
    .reset_index()
    .melt(id_vars="fecha", var_name="indicador_id", value_name="valor")
    .dropna(subset=["valor"])
    .sort_values(["indicador_id", "fecha"])
    .reset_index(drop=True)
)

df_long["fecha"] = pd.to_datetime(df_long["fecha"]).dt.strftime("%Y-%m-%d")

# ── Guardar ────────────────────────────────────────────────────────────────
df_long.to_csv(RUTA_OUT, index=False)
print(f"✓ Archivo guardado: {RUTA_OUT}")
print(f"  Filas totales : {len(df_long):,}")
print(f"  Series        : {df_long['indicador_id'].nunique()}")
print(f"  Rango de fechas: {df_long['fecha'].min()} → {df_long['fecha'].max()}")