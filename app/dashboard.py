import os
from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / "env.env")


def _require_env(name: str, *, allow_empty: bool = False) -> str:
    value = os.getenv(name)
    if value is None or (not allow_empty and value == ""):
        raise ValueError(f"Variable de entorno no definida: {name} (revisa {ROOT / 'env.env'})")
    return value


# ── Configuración ──────────────────────────────────────────────────────────
st.set_page_config(
    page_title="Dashboard Macroeconómico · México",
    layout="wide",
)


# ── Conexión a PostgreSQL ──────────────────────────────────────────────────
@st.cache_resource
def get_engine():
    return create_engine(
        f"postgresql+psycopg2://{_require_env('DB_USER')}:{_require_env('DB_PASSWORD', allow_empty=True)}"
        f"@{_require_env('DB_HOST')}:{_require_env('DB_PORT')}/{_require_env('DB_NAME')}"
    )


@st.cache_data(ttl=3600)
def query(sql: str, fechas: tuple[str, ...] = ("fecha",)) -> pd.DataFrame:
    with get_engine().connect() as conn:
        df = pd.read_sql(text(sql), conn)
    for col in fechas:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col])
    return df


def get_kpi(df: pd.DataFrame, nombre: str):
    row = df[df["nombre"] == nombre]
    if row.empty:
        return None, None, None
    r = row.iloc[0]
    return r["valor_actual"], r["var_anual_pct"], r["unidad"]


def fmt_metric(value, suffix: str = "", decimals: int = 2) -> str:
    if value is None or pd.isna(value):
        return "N/D"
    return f"{value:.{decimals}f}{suffix}"


def fmt_delta(value) -> str:
    if value is None or pd.isna(value):
        return None
    return f"{value:+.2f}% anual"


# ── Cargar datos desde las vistas ─────────────────────────────────────────
try:
    df_actual = query(
        "SELECT * FROM vw_indicadores_actuales",
        fechas=("fecha_ultimo_dato",),
    )
    df_inflacion = query("SELECT * FROM vw_inflacion ORDER BY fecha")
    df_igae = query("SELECT * FROM vw_igae ORDER BY fecha")
    df_tc = query("SELECT * FROM vw_tipo_cambio ORDER BY fecha")
    df_tasas = query("SELECT * FROM vw_tasas ORDER BY fecha")
except Exception as exc:
    st.error(
        "No se pudo conectar a PostgreSQL o las vistas no existen. "
        f"Ejecuta los scripts SQL (01–04) y verifica {ROOT / 'env.env'}."
    )
    st.exception(exc)
    st.stop()

# ── Header ─────────────────────────────────────────────────────────────────
st.title("Dashboard Macroeconómico de México")
ultimo_dato = pd.to_datetime(df_actual["fecha_ultimo_dato"]).max()
st.caption(
    f"Fuentes: INEGI y Banco de México · Datos hasta {ultimo_dato.strftime('%B %Y')}"
)
st.divider()

# ── Fila de KPIs ───────────────────────────────────────────────────────────
col1, col2, col3, col4 = st.columns(4)

igae_val, igae_delta, _ = get_kpi(df_actual, "IGAE Total")
inpc_val, inpc_delta, _ = get_kpi(df_actual, "INPC")
tc_val, tc_delta, _ = get_kpi(df_actual, "Tipo de Cambio FIX")
desemp_val, desemp_delta, _ = get_kpi(df_actual, "Tasa de Desocupación")

col1.metric("IGAE", fmt_metric(igae_val), fmt_delta(igae_delta))
col2.metric("INPC (índice)", fmt_metric(inpc_val), fmt_delta(inpc_delta))
col3.metric("Tipo de Cambio FIX", f"${fmt_metric(tc_val)}", fmt_delta(tc_delta))
col4.metric("Desocupación", f"{fmt_metric(desemp_val)}%", fmt_delta(desemp_delta))

st.divider()

# ── Gráficas principales ───────────────────────────────────────────────────
tab1, tab2, tab3, tab4 = st.tabs([
    "Actividad Económica",
    "Inflación",
    "Tipo de Cambio",
    "Tasas de Interés",
])

# ── Tab 1: IGAE ────────────────────────────────────────────────────────────
with tab1:
    st.subheader("IGAE — Indicador Global de la Actividad Económica")
    col_a, col_b = st.columns([3, 1])

    with col_a:
        fig = px.line(
            df_igae.dropna(subset=["var_anual_pct"]),
            x="fecha",
            y="var_anual_pct",
            title="Variación anual del IGAE (%)",
            labels={"fecha": "", "var_anual_pct": "Variación anual (%)"},
            color_discrete_sequence=["#1a6fad"],
        )
        fig.add_hline(y=0, line_dash="dash", line_color="gray", opacity=0.5)
        fig.update_layout(hovermode="x unified")
        st.plotly_chart(fig, use_container_width=True)

    with col_b:
        st.subheader("IGAE con tendencia")
        fig2 = go.Figure()
        fig2.add_trace(go.Scatter(
            x=df_igae["fecha"],
            y=df_igae["igae"],
            name="IGAE",
            line=dict(color="#aac4e0", width=1),
        ))
        fig2.add_trace(go.Scatter(
            x=df_igae["fecha"],
            y=df_igae["tendencia_12m"],
            name="Tendencia 12m",
            line=dict(color="#1a6fad", width=2),
        ))
        fig2.update_layout(
            title="IGAE vs Tendencia",
            xaxis_title="",
            yaxis_title="Índice",
            legend=dict(orientation="h", y=-0.2),
            hovermode="x unified",
        )
        st.plotly_chart(fig2, use_container_width=True)

# ── Tab 2: Inflación ───────────────────────────────────────────────────────
with tab2:
    st.subheader("Inflación — INPC")

    año_min = int(pd.to_datetime(df_inflacion["fecha"]).dt.year.min())
    año_max = int(pd.to_datetime(df_inflacion["fecha"]).dt.year.max()) - 1
    año_inicio = st.slider(
        "Año de inicio",
        min_value=año_min,
        max_value=max(año_min, año_max),
        value=max(2010, año_min),
        step=1,
    )
    df_inf_fil = df_inflacion[
        df_inflacion["fecha"] >= pd.Timestamp(f"{año_inicio}-01-01")
    ].dropna(subset=["inflacion_anual_pct"])

    fig = px.area(
        df_inf_fil,
        x="fecha",
        y="inflacion_anual_pct",
        title=f"Inflación anual (%) desde {año_inicio}",
        labels={"fecha": "", "inflacion_anual_pct": "Inflación anual (%)"},
        color_discrete_sequence=["#d64e4e"],
    )
    fig.add_hline(
        y=3,
        line_dash="dot",
        line_color="green",
        annotation_text="Meta Banxico: 3%",
        annotation_position="right",
    )
    fig.add_hline(
        y=4,
        line_dash="dash",
        line_color="orange",
        annotation_text="Banda superior: 4%",
        annotation_position="right",
    )
    fig.update_layout(hovermode="x unified")
    st.plotly_chart(fig, use_container_width=True)

# ── Tab 3: Tipo de cambio ──────────────────────────────────────────────────
with tab3:
    st.subheader("Tipo de Cambio FIX (MXN/USD)")

    col_a, col_b = st.columns([2, 1])
    with col_a:
        fig = px.line(
            df_tc,
            x="fecha",
            y="tc_fix",
            title="Tipo de Cambio FIX — Serie histórica",
            labels={"fecha": "", "tc_fix": "Pesos por USD"},
            color_discrete_sequence=["#2a9d5c"],
        )
        fig.add_trace(go.Scatter(
            x=df_tc["fecha"],
            y=df_tc["promedio_movil_12m"],
            name="Promedio móvil 12m",
            line=dict(color="#1a5c3a", width=2, dash="dash"),
        ))
        fig.update_layout(hovermode="x unified")
        st.plotly_chart(fig, use_container_width=True)

    with col_b:
        st.subheader("Depreciación anual (%)")
        df_dep = df_tc.dropna(subset=["depreciacion_anual_pct"])
        fig2 = px.bar(
            df_dep[df_dep["fecha"] >= pd.Timestamp("2010-01-01")],
            x="fecha",
            y="depreciacion_anual_pct",
            color="depreciacion_anual_pct",
            color_continuous_scale=["#2a9d5c", "white", "#d64e4e"],
            color_continuous_midpoint=0,
        )
        fig2.update_layout(showlegend=False, coloraxis_showscale=False)
        st.plotly_chart(fig2, use_container_width=True)

# ── Tab 4: Tasas ───────────────────────────────────────────────────────────
with tab4:
    st.subheader("Tasas de Interés")
    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=df_tasas["fecha"],
        y=df_tasas["tasa_objetivo"],
        name="Tasa objetivo Banxico",
        line=dict(color="#7c3aed", width=2),
    ))
    fig.add_trace(go.Scatter(
        x=df_tasas["fecha"],
        y=df_tasas["cetes_28d"],
        name="CETES 28 días",
        line=dict(color="#c084fc", width=1.5, dash="dot"),
    ))
    fig.update_layout(
        title="Tasa objetivo vs CETES 28 días (%)",
        xaxis_title="",
        yaxis_title="Tasa (%)",
        hovermode="x unified",
    )
    st.plotly_chart(fig, use_container_width=True)

# ── Tabla resumen ──────────────────────────────────────────────────────────
st.divider()
st.subheader("Resumen de indicadores")
tabla = df_actual[[
    "nombre",
    "valor_actual",
    "unidad",
    "var_anual_pct",
    "fecha_ultimo_dato",
    "fuente",
]].copy()
tabla.columns = [
    "Indicador",
    "Valor actual",
    "Unidad",
    "Var. anual (%)",
    "Último dato",
    "Fuente",
]
tabla["Último dato"] = pd.to_datetime(tabla["Último dato"]).dt.strftime("%b %Y")
st.dataframe(tabla, use_container_width=True, hide_index=True)
