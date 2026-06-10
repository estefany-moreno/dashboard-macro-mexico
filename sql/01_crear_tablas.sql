-- ============================================================
-- DASHBOARD MACROECONÓMICO DE MÉXICO
-- Script 01: Creación de tablas
-- ============================================================

-- Limpiar si ya existen (útil para re-ejecuciones)
DROP TABLE IF EXISTS observaciones CASCADE;
DROP TABLE IF EXISTS indicadores CASCADE;

-- ── Tabla de metadatos ─────────────────────────────────────
CREATE TABLE indicadores (
    indicador_id    VARCHAR(50)  PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    descripcion     TEXT,
    unidad          VARCHAR(50),
    fuente          VARCHAR(50),
    aplica_log      BOOLEAN      DEFAULT FALSE,
    fecha_creacion  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE indicadores IS
    'Catálogo de indicadores macroeconómicos con metadatos.';
COMMENT ON COLUMN indicadores.aplica_log IS
    'TRUE si la serie fue transformada con logaritmo en el preprocesamiento.';

-- ── Tabla de observaciones ─────────────────────────────────
CREATE TABLE observaciones (
    obs_id          SERIAL       PRIMARY KEY,
    indicador_id    VARCHAR(50)  NOT NULL
                    REFERENCES indicadores(indicador_id)
                    ON DELETE CASCADE,
    fecha           DATE         NOT NULL,
    valor           NUMERIC(18,6),

    -- Evitar duplicados: un indicador solo puede tener un valor por fecha
    CONSTRAINT uq_indicador_fecha UNIQUE (indicador_id, fecha)
);

COMMENT ON TABLE observaciones IS
    'Serie de tiempo mensual en formato largo. Una fila por indicador-fecha.';

-- ── Índices para acelerar consultas ────────────────────────
-- Índice por fecha (para filtros temporales)
CREATE INDEX idx_obs_fecha
    ON observaciones(fecha);

-- Índice compuesto (para consultas por indicador + fecha)
CREATE INDEX idx_obs_indicador_fecha
    ON observaciones(indicador_id, fecha);