-- ============================================================
-- Script 04: Creación de vistas analíticas
-- ============================================================
--
-- Compatible con scripts 01–03. Variaciones % respetan
-- indicadores.aplica_log (EXP() para series en log natural).

-- Re-ejecutable: DROP permite cambiar columnas/tipos entre versiones
DROP VIEW IF EXISTS vw_indicadores_actuales;
DROP VIEW IF EXISTS vw_tasas;
DROP VIEW IF EXISTS vw_tipo_cambio;
DROP VIEW IF EXISTS vw_igae;
DROP VIEW IF EXISTS vw_inflacion;


-- ── Vista 1: Inflación anual (INPC) ───────────────────────────────────────
-- INPC tiene aplica_log = TRUE: se muestra el índice en niveles (EXP)
-- y la inflación se calcula sobre esos niveles reconstruidos.
CREATE OR REPLACE VIEW vw_inflacion AS
SELECT
    o.fecha,
    ROUND(EXP(o.valor), 4)                              AS inpc,
    ROUND(
        (EXP(o.valor) - EXP(LAG(o.valor, 12) OVER w))
        / NULLIF(EXP(LAG(o.valor, 12) OVER w), 0) * 100,
    2)                                                  AS inflacion_anual_pct,
    ROUND(
        (EXP(o.valor) - EXP(LAG(o.valor, 1) OVER w))
        / NULLIF(EXP(LAG(o.valor, 1) OVER w), 0) * 100,
    4)                                                  AS inflacion_mensual_pct
FROM observaciones o
WHERE o.indicador_id = 'inpc'
WINDOW w AS (ORDER BY o.fecha);

COMMENT ON VIEW vw_inflacion IS
    'Serie del INPC (índice en niveles) con variación mensual y anual.';


-- ── Vista 2: Actividad económica (IGAE) ───────────────────────────────────
-- IGAE tiene aplica_log = FALSE: variación directa en niveles del índice.
CREATE OR REPLACE VIEW vw_igae AS
SELECT
    o.fecha,
    o.valor                                             AS igae,
    ROUND(
        (o.valor - LAG(o.valor, 12) OVER w)
        / NULLIF(LAG(o.valor, 12) OVER w, 0) * 100,
    2)                                                  AS var_anual_pct,
    ROUND(
        AVG(o.valor) OVER (
            ORDER BY o.fecha
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ),
    4)                                                  AS tendencia_12m
FROM observaciones o
WHERE o.indicador_id = 'igae_total'
WINDOW w AS (ORDER BY o.fecha);

COMMENT ON VIEW vw_igae IS
    'IGAE con variación anual y tendencia de 12 meses.';


-- ── Vista 3: Tipo de cambio ────────────────────────────────────────────────
-- tc_fix tiene aplica_log = TRUE: se muestra pesos/USD (EXP) y la
-- depreciación se calcula sobre niveles reconstruidos.
CREATE OR REPLACE VIEW vw_tipo_cambio AS
SELECT
    o.fecha,
    ROUND(EXP(o.valor), 4)                              AS tc_fix,
    ROUND(
        (EXP(o.valor) - EXP(LAG(o.valor, 12) OVER w))
        / NULLIF(EXP(LAG(o.valor, 12) OVER w), 0) * 100,
    2)                                                  AS depreciacion_anual_pct,
    ROUND(
        AVG(EXP(o.valor)) OVER (
            ORDER BY o.fecha
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ),
    4)                                                  AS promedio_movil_12m
FROM observaciones o
WHERE o.indicador_id = 'tc_fix'
WINDOW w AS (ORDER BY o.fecha);

COMMENT ON VIEW vw_tipo_cambio IS
    'Tipo de cambio FIX (pesos/USD) con depreciación anual y promedio móvil.';


-- ── Vista 4: Tasas de interés ──────────────────────────────────────────────
-- FULL OUTER JOIN: tasa_objetivo y CETES no comparten todas las fechas.
CREATE OR REPLACE VIEW vw_tasas AS
SELECT
    COALESCE(t.fecha, c.fecha)                          AS fecha,
    t.valor                                             AS tasa_objetivo,
    c.valor                                             AS cetes_28d
FROM (
    SELECT fecha, ROUND(valor, 4) AS valor
    FROM observaciones
    WHERE indicador_id = 'tasa_objetivo'
) t
FULL OUTER JOIN (
    SELECT fecha, ROUND(valor, 4) AS valor
    FROM observaciones
    WHERE indicador_id = 'cetes_28'
) c ON t.fecha = c.fecha
ORDER BY fecha;

COMMENT ON VIEW vw_tasas IS
    'Tasa objetivo de Banxico y CETES 28 días en formato wide por fecha.';


-- ── Vista 5: Panel de indicadores actuales ────────────────────────────────
-- Resumen ejecutivo: última lectura disponible de cada indicador.
CREATE OR REPLACE VIEW vw_indicadores_actuales AS
WITH ultimo AS (
    SELECT DISTINCT ON (indicador_id)
        indicador_id,
        fecha   AS fecha_ultimo_dato,
        valor   AS valor_actual
    FROM observaciones
    ORDER BY indicador_id, fecha DESC
),
hace_12m AS (
    SELECT DISTINCT ON (o.indicador_id)
        o.indicador_id,
        o.valor   AS valor_hace_12m
    FROM observaciones o
    JOIN ultimo u USING (indicador_id)
    WHERE o.fecha = u.fecha_ultimo_dato - INTERVAL '12 months'
    ORDER BY o.indicador_id, o.fecha DESC
)
SELECT
    i.indicador_id,
    i.nombre,
    i.unidad,
    i.fuente,
    i.aplica_log,
    u.fecha_ultimo_dato,
    ROUND(
        CASE WHEN i.aplica_log THEN EXP(u.valor_actual) ELSE u.valor_actual END,
    4)                                                  AS valor_actual,
    ROUND(
        CASE WHEN i.aplica_log THEN EXP(h.valor_hace_12m) ELSE h.valor_hace_12m END,
    4)                                                  AS valor_hace_12m,
    ROUND(
        CASE WHEN i.aplica_log THEN
            (EXP(u.valor_actual) - EXP(h.valor_hace_12m))
            / NULLIF(EXP(h.valor_hace_12m), 0) * 100
        ELSE
            (u.valor_actual - h.valor_hace_12m)
            / NULLIF(h.valor_hace_12m, 0) * 100
        END,
    2)                                                  AS var_anual_pct
FROM ultimo u
JOIN indicadores i USING (indicador_id)
LEFT JOIN hace_12m h USING (indicador_id)
ORDER BY i.fuente, i.nombre;

COMMENT ON VIEW vw_indicadores_actuales IS
    'Panel resumen: último valor disponible de cada indicador con variación anual.';
