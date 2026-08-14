# sql/tablas — scripts que crean TABLAS persistidas

Scripts `CREATE TABLE` que **materializan** (snapshot) las vistas de `sql/vistas/`.

**Por qué existen:** las vistas de `sql/vistas/` recomputan al vuelo (3 años del hecho +
saldos diarios + LAG). Power BI se cae por **timeout** al cargarlas vía ODBC. Estas tablas
guardan el resultado de la vista para que Power BI lea algo liviano al instante. **Las
vistas siguen siendo la fuente de la lógica**; las tablas solo copian su resultado.

- `tbl_kpi_cubo_mensual.sql` — materializa `vw_kpi_cubo_mensual` → `co_sandbox_datos.tbl_kpi_cubo_mensual` (el cubo de KPIs; acelera donuts/tendencias/detalle).
- `tbl_alertas_primas.sql` — materializa `vw_alertas_primas` → `co_sandbox_datos.tbl_alertas_primas`.
- `tbl_disponibilidad_hora_carga.sql` — materializa `vw_disponibilidad_hora_carga` → `co_sandbox_datos.tbl_disponibilidad_hora_carga`.

**Patrón (idempotente):** cada script hace `CREATE TABLE IF NOT EXISTS ... AS SELECT ... WHERE 1=0`
(crea la estructura la 1ª vez) + `TRUNCATE` + `INSERT INTO ... SELECT * FROM la_vista`.
Correrlo de nuevo = refrescar el snapshot. Hoy es manual; luego se puede agendar.

**Power BI apunta a estas tablas** (`tbl_*`), NO a las vistas.

## Organización de `sql/`

- `sql/vistas/` — `CREATE OR REPLACE VIEW` (en orden de dependencia):
  - `01_vw_kpi_cubo_mensual.sql` — cubo de los 5 KPIs.
  - `02_vw_disponibilidad_hora_carga.sql` — arribo de la carga vs. corte 11am.
  - `03_vw_alertas_primas.sql` — alertas (depende de 01 y 02).
- `sql/consultas/` — solo `SELECT`, no crean objeto (los consume el notebook / Power BI):
  - `primas_monto_mensual.sql`, `disponibilidad_mes.sql`, `disponibilidad_diaria.sql`.
- `sql/tablas/` — `CREATE TABLE` (esta carpeta; vacía por ahora).
