-- tbl_kpi_cubo_mensual.sql  (nuevo, aditivo)
--
-- TABLA MATERIALIZADA de la vista co_sandbox_datos.vw_kpi_cubo_mensual (el cubo de KPIs).
--
-- Mismo patrón que tbl_alertas_primas: la vista es la fuente de la lógica; esta tabla es
-- un snapshot rápido para Power BI. La vista recomputa los 5 indicadores sobre 3 años del
-- hecho al vuelo, así que materializarla acelera todo el tablero (donuts, tendencias,
-- detalle). Depende de sql/vistas/01_vw_kpi_cubo_mensual.sql.
--
-- Refresco (idempotente): corre este archivo para datos nuevos. No borra la tabla
-- (conserva GRANTs). Power BI apunta a co_sandbox_datos.tbl_kpi_cubo_mensual.

CREATE TABLE IF NOT EXISTS co_sandbox_datos.tbl_kpi_cubo_mensual (
    periodo_contable  INTEGER,
    periodo_fecha     DATE,
    tipo_indicador    VARCHAR(32),
    nombre_campo      VARCHAR(64),
    nombre_natural    VARCHAR(128),
    total_registros   BIGINT,
    cantidad_mala     BIGINT,
    porcentaje        DECIMAL(10,2),
    es_total          INTEGER,
    fecha_calculo     TIMESTAMP
);

TRUNCATE TABLE co_sandbox_datos.tbl_kpi_cubo_mensual;

INSERT INTO co_sandbox_datos.tbl_kpi_cubo_mensual
SELECT * FROM co_sandbox_datos.vw_kpi_cubo_mensual;

-- Verificación:
--   SELECT tipo_indicador, COUNT(*) FROM co_sandbox_datos.tbl_kpi_cubo_mensual GROUP BY 1 ORDER BY 1;
