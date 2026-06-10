┌─────────────────────────────────────┐
│            indicadores              │
├──────────────────┬──────────────────┤
│ indicador_id  PK │ VARCHAR(50)      │
│ nombre           │ VARCHAR(100)     │
│ descripcion      │ TEXT             │
│ unidad           │ VARCHAR(50)      │
│ fuente           │ VARCHAR(50)      │
│ aplica_log       │ BOOLEAN          │
└──────────────────┴──────────────────┘
              │ 1
              │
              │ N
┌─────────────────────────────────────┐
│           observaciones             │
├──────────────────┬──────────────────┤
│ obs_id        PK │ SERIAL           │
│ indicador_id  FK │ VARCHAR(50)      │
│ fecha            │ DATE             │
│ valor            │ NUMERIC(18,6)    │
└──────────────────┴──────────────────┘