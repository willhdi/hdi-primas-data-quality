# sql/tablas — scripts que crean TABLAS persistidas

Carpeta reservada para scripts `CREATE TABLE` (objetos materializados en el warehouse).

**Hoy está vacía a propósito:** el diseño actual usa **vistas puras** (ver `sql/vistas/`)
que se recalculan al consultarse, sin tablas ni procedimientos. Los KPIs originales sí
usaban tablas + stored procedures, pero esos archivos se retiraron (recuperables desde
el historial de git; ver `CLAUDE.md`).

Si en el futuro se materializa algo (por rendimiento o para snapshots históricos),
el `CREATE TABLE` + su carga van aquí.

## Organización de `sql/`

- `sql/vistas/` — `CREATE OR REPLACE VIEW` (en orden de dependencia):
  - `01_vw_kpi_cubo_mensual.sql` — cubo de los 5 KPIs.
  - `02_vw_disponibilidad_hora_carga.sql` — arribo de la carga vs. corte 11am.
  - `03_vw_alertas_primas.sql` — alertas (depende de 01 y 02).
- `sql/consultas/` — solo `SELECT`, no crean objeto (los consume el notebook / Power BI):
  - `primas_monto_mensual.sql`, `disponibilidad_mes.sql`, `disponibilidad_diaria.sql`.
- `sql/tablas/` — `CREATE TABLE` (esta carpeta; vacía por ahora).
