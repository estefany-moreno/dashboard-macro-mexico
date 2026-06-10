-- ============================================================
-- Script 02: Carga de metadatos e inserción de observaciones
-- ============================================================

-- ── Metadatos de los 7 indicadores ────────────────────────
-- Re-ejecutable: si el indicador ya existe, actualiza sus metadatos
-- en lugar de fallar por clave duplicada (ON CONFLICT ... DO UPDATE).
INSERT INTO indicadores
    (indicador_id, nombre, descripcion, unidad, fuente, aplica_log)
VALUES
    (
        'igae_total',
        'IGAE Total',
        'Indicador Global de la Actividad Económica. Aproximación mensual al PIB.',
        'Índice (base 2018=100)',
        'INEGI',
        FALSE
    ),
    (
        'produccion_industrial',
        'Producción Industrial',
        'Índice de producción industrial total del país.',
        'Índice (base 2018=100)',
        'INEGI',
        FALSE
    ),
    (
        'inpc',
        'INPC',
        'Índice Nacional de Precios al Consumidor. Mide la inflación general.',
        'Índice (base 2Q2018=100)',
        'INEGI',
        TRUE
    ),
    (
        'tasa_desocupacion',
        'Tasa de Desocupación',
        'Porcentaje de la PEA que se encuentra desocupada (ENOE).',
        'Porcentaje (%)',
        'INEGI',
        FALSE
    ),
    (
        'tc_fix',
        'Tipo de Cambio FIX',
        'Tipo de cambio FIX determinado por Banxico. Pesos por dólar americano.',
        'Pesos por USD',
        'Banxico',
        TRUE   -- almacenado como ln(tipo de cambio)
    ),
    (
        'cetes_28',
        'CETES 28 días',
        'Tasa de rendimiento de Certificados de la Tesorería a 28 días.',
        'Tasa (%)',
        'Banxico',
        FALSE
    ),
    (
        'tasa_objetivo',
        'Tasa Objetivo Banxico',
        'Tasa de interés de política monetaria fijada por Banxico.',
        'Tasa (%)',
        'Banxico',
        FALSE
    )
ON CONFLICT (indicador_id) DO UPDATE SET
    nombre      = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    unidad      = EXCLUDED.unidad,
    fuente      = EXCLUDED.fuente,
    aplica_log  = EXCLUDED.aplica_log;

-- Verificar inserción
SELECT indicador_id, nombre, fuente FROM indicadores ORDER BY fuente, indicador_id;