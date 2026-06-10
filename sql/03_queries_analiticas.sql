-- ============================================================
-- Script 03: Queries analíticas con window functions
-- Dashboard Macroeconómico de México
-- ============================================================
--
-- Variaciones %: si indicadores.aplica_log = TRUE, el valor almacenado
-- está en log natural; se reconstruye el nivel con EXP() antes de calcular
-- el cambio. Si aplica_log = FALSE, se usa la fórmula directa en niveles.


-- ── 1. VARIACIÓN MENSUAL ──────────────────────────────────────────────────
-- LAG(1): compara cada observación con la del mes anterior.
-- Útil para detectar aceleraciones o desaceleraciones en el corto plazo.

SELECT
    o.fecha,
    i.nombre,
    i.aplica_log,
    o.valor                                             AS valor_actual,
    LAG(o.valor) OVER w                                 AS valor_mes_anterior,
    ROUND(
        CASE WHEN i.aplica_log THEN
            (EXP(o.valor) - EXP(LAG(o.valor) OVER w))
            / NULLIF(EXP(LAG(o.valor) OVER w), 0) * 100
        ELSE
            (o.valor - LAG(o.valor) OVER w)
            / NULLIF(LAG(o.valor) OVER w, 0) * 100
        END,
    2)                                                  AS var_mensual_pct
FROM observaciones o
JOIN indicadores i USING (indicador_id)
WHERE o.indicador_id = 'inpc'
  AND o.fecha >= '2020-01-01'
WINDOW w AS (PARTITION BY o.indicador_id ORDER BY o.fecha)
ORDER BY o.fecha;


-- ── 2. VARIACIÓN ANUAL ────────────────────────────────────────────────────
-- LAG(12): compara con el mismo mes del año anterior (frecuencia mensual).
-- Es la métrica estándar para reportar inflación (INPC tiene aplica_log).

SELECT
    o.fecha,
    i.nombre,
    i.aplica_log,
    o.valor                                             AS valor_actual,
    LAG(o.valor, 12) OVER w                             AS valor_mismo_mes_año_anterior,
    ROUND(
        CASE WHEN i.aplica_log THEN
            (EXP(o.valor) - EXP(LAG(o.valor, 12) OVER w))
            / NULLIF(EXP(LAG(o.valor, 12) OVER w), 0) * 100
        ELSE
            (o.valor - LAG(o.valor, 12) OVER w)
            / NULLIF(LAG(o.valor, 12) OVER w, 0) * 100
        END,
    2)                                                  AS var_anual_pct
FROM observaciones o
JOIN indicadores i USING (indicador_id)
WHERE o.indicador_id = 'inpc'
  AND o.fecha >= '2010-01-01'
WINDOW w AS (PARTITION BY o.indicador_id ORDER BY o.fecha)
ORDER BY o.fecha;


-- ── 3. PROMEDIO MÓVIL DE 12 MESES ────────────────────────────────────────
-- Suaviza la serie para identificar la tendencia de fondo.
-- ROWS BETWEEN 11 PRECEDING AND CURRENT ROW = ventana de 12 meses.

SELECT
    o.fecha,
    i.nombre,
    o.valor,
    ROUND(
        AVG(o.valor) OVER (
            PARTITION BY o.indicador_id
            ORDER BY o.fecha
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ),
    4)                                                  AS promedio_movil_12m
FROM observaciones o
JOIN indicadores i USING (indicador_id)
WHERE o.indicador_id = 'igae_total'
ORDER BY o.fecha;


-- ── 4. MÁXIMOS Y MÍNIMOS HISTÓRICOS ──────────────────────────────────────
-- Para cada indicador, devuelve el valor más alto y más bajo
-- junto con la fecha en que ocurrió.

SELECT
    i.nombre,
    i.unidad,

    -- Máximo histórico
    MAX(o.valor)                                        AS valor_maximo,
    (SELECT o2.fecha
     FROM observaciones o2
     WHERE o2.indicador_id = o.indicador_id
     ORDER BY o2.valor DESC LIMIT 1)                    AS fecha_maximo,

    -- Mínimo histórico
    MIN(o.valor)                                        AS valor_minimo,
    (SELECT o3.fecha
     FROM observaciones o3
     WHERE o3.indicador_id = o.indicador_id
     ORDER BY o3.valor ASC LIMIT 1)                     AS fecha_minimo,

    -- Valor más reciente
    (SELECT o4.valor
     FROM observaciones o4
     WHERE o4.indicador_id = o.indicador_id
     ORDER BY o4.fecha DESC LIMIT 1)                    AS valor_actual

FROM observaciones o
JOIN indicadores i USING (indicador_id)
GROUP BY i.nombre, i.unidad, o.indicador_id
ORDER BY i.nombre;


-- ── 5. RANKING DE VARIACIÓN ANUAL (último dato disponible) ───────────────
-- Compara todos los indicadores entre sí según su variación anual más reciente.
-- RANK() asigna posición 1 al de mayor variación.

WITH ultimos AS (
    -- Para cada indicador, obtener el dato más reciente y el de hace 12 meses
    SELECT
        o.indicador_id,
        i.nombre,
        i.unidad,
        i.aplica_log,
        o.valor                                         AS valor_actual,
        o.fecha                                         AS fecha_actual,
        LAG(o.valor, 12) OVER (
            PARTITION BY o.indicador_id
            ORDER BY o.fecha
        )                                               AS valor_hace_12m
    FROM observaciones o
    JOIN indicadores i USING (indicador_id)
),
recientes AS (
    -- Quedarse solo con la observación más reciente de cada indicador
    SELECT DISTINCT ON (indicador_id) *
    FROM ultimos
    WHERE valor_hace_12m IS NOT NULL
    ORDER BY indicador_id, fecha_actual DESC
),
con_variacion AS (
    -- Ratio de variación anual según escala (log vs niveles)
    SELECT
        *,
        CASE WHEN aplica_log THEN
            (EXP(valor_actual) - EXP(valor_hace_12m))
            / NULLIF(EXP(valor_hace_12m), 0)
        ELSE
            (valor_actual - valor_hace_12m)
            / NULLIF(valor_hace_12m, 0)
        END                                             AS var_anual_ratio
    FROM recientes
)
SELECT
    nombre,
    unidad,
    aplica_log,
    ROUND(valor_actual, 4)                              AS valor_actual,
    fecha_actual,
    ROUND(var_anual_ratio * 100, 2)                     AS var_anual_pct,
    RANK() OVER (
        ORDER BY ABS(var_anual_ratio) DESC
    )                                                   AS ranking_variacion
FROM con_variacion
ORDER BY ranking_variacion;


-- ── 6. VALOR ACTUAL VS PROMEDIO HISTÓRICO ─────────────────────────────────
-- Contextualiza el último dato frente a la media histórica.
-- Útil para identificar si un indicador está por encima o debajo de su norma.

WITH historico AS (
    SELECT
        indicador_id,
        AVG(valor)      AS promedio_historico,
        STDDEV(valor)   AS desviacion_std
    FROM observaciones
    GROUP BY indicador_id
),
actual AS (
    SELECT DISTINCT ON (indicador_id)
        indicador_id,
        valor   AS valor_actual,
        fecha   AS fecha_actual
    FROM observaciones
    ORDER BY indicador_id, fecha DESC
)
SELECT
    i.nombre,
    i.fuente,
    ROUND(a.valor_actual, 4)                            AS valor_actual,
    a.fecha_actual,
    ROUND(h.promedio_historico, 4)                      AS promedio_historico,
    ROUND(h.desviacion_std, 4)                          AS desviacion_std,
    ROUND(a.valor_actual - h.promedio_historico, 4)     AS diferencia,
    -- Z-score: cuántas desviaciones estándar está del promedio
    ROUND(
        (a.valor_actual - h.promedio_historico)
        / NULLIF(h.desviacion_std, 0),
    2)                                                  AS z_score
FROM actual a
JOIN historico h USING (indicador_id)
JOIN indicadores i USING (indicador_id)
ORDER BY ABS(
    (a.valor_actual - h.promedio_historico)
    / NULLIF(h.desviacion_std, 0)
) DESC;


-- ── 7. EVOLUCIÓN ANUAL RESUMIDA (promedios por año) ──────────────────────
-- Agrega la serie mensual a frecuencia anual para tendencias de largo plazo.

SELECT
    EXTRACT(YEAR FROM o.fecha)::INT                     AS anio,
    i.nombre,
    ROUND(AVG(o.valor), 4)                              AS promedio_anual,
    ROUND(MIN(o.valor), 4)                              AS minimo_anual,
    ROUND(MAX(o.valor), 4)                              AS maximo_anual,
    COUNT(*)                                            AS meses_con_dato
FROM observaciones o
JOIN indicadores i USING (indicador_id)
GROUP BY EXTRACT(YEAR FROM o.fecha), i.nombre, o.indicador_id
ORDER BY i.nombre, anio;