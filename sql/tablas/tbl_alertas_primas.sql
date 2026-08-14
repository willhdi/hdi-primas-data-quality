-- tbl_alertas_primas.sql  (nuevo, aditivo)
--
-- TABLA MATERIALIZADA de la vista co_sandbox_datos.vw_alertas_primas.
--
-- Por qué: la vista recomputa al vuelo (cubo de 3 años + saldos diarios + LAG) y
-- Power BI se cae por timeout al cargarla vía ODBC. Esta tabla es un SNAPSHOT que
-- Power BI lee al instante. La VISTA sigue siendo la fuente de la lógica; esta tabla
-- solo guarda su resultado. Depende de sql/vistas/03_vw_alertas_primas.sql.
--
-- Refresco (idempotente): corre este archivo cuando quieras datos nuevos. La 1ª vez
-- crea la tabla (si no existe); siempre la vacía y la recarga desde la vista. Como
-- NO borra la tabla, los permisos (GRANT) se conservan entre refrescos. Hoy manual;
-- luego se puede agendar. Power BI apunta a co_sandbox_datos.tbl_alertas_primas.
--
-- Nota: Redshift NO soporta "CREATE TABLE IF NOT EXISTS ... AS SELECT", por eso las
-- columnas van explícitas. Los VARCHAR van holgados a propósito (la vista hoy declara
-- longitudes más cortas; el margen evita errores de truncamiento si el texto crece).

CREATE TABLE IF NOT EXISTS co_sandbox_datos.tbl_alertas_primas (
    ambito            VARCHAR(32),
    clave             VARCHAR(64),
    clave_natural     VARCHAR(200),
    periodo_contable  INTEGER,
    fecha             DATE,
    valor             DOUBLE PRECISION,
    valor_referencia  DOUBLE PRECISION,
    variacion_abs     DOUBLE PRECISION,
    variacion_pct     DOUBLE PRECISION,
    umbral_adv        DECIMAL(6,2),
    umbral_crit       DECIMAL(6,2),
    estado            VARCHAR(20),
    detalle           VARCHAR(400),
    fecha_calculo     TIMESTAMP
);

TRUNCATE TABLE co_sandbox_datos.tbl_alertas_primas;

INSERT INTO co_sandbox_datos.tbl_alertas_primas
SELECT * FROM co_sandbox_datos.vw_alertas_primas;

-- Verificación:
--   SELECT ambito, estado, COUNT(*) FROM co_sandbox_datos.tbl_alertas_primas GROUP BY 1,2 ORDER BY 1,2;
