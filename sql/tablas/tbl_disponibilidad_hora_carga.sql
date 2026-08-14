-- tbl_disponibilidad_hora_carga.sql  (nuevo, aditivo)
--
-- TABLA MATERIALIZADA de la vista co_sandbox_datos.vw_disponibilidad_hora_carga.
--
-- Mismo patrón que tbl_alertas_primas: la vista es la fuente de la lógica; esta tabla
-- es un snapshot rápido para Power BI (evita el timeout ODBC). Depende de
-- sql/vistas/02_vw_disponibilidad_hora_carga.sql.
--
-- Refresco (idempotente): corre este archivo cuando quieras datos nuevos. No borra la
-- tabla (conserva GRANTs). Power BI apunta a co_sandbox_datos.tbl_disponibilidad_hora_carga.

CREATE TABLE IF NOT EXISTS co_sandbox_datos.tbl_disponibilidad_hora_carga (
    fecha_datos          DATE,
    transaction_date_sk  BIGINT,
    periodo_contable     INTEGER,
    tipo_indicador       VARCHAR(32),
    nombre_campo         VARCHAR(32),
    arribo_datos         TIMESTAMP,
    hora_arribo          TIME,
    ultima_escritura     TIMESTAMP,
    registros            BIGINT,
    minutos_vs_corte     BIGINT,
    estado               VARCHAR(20),
    fecha_calculo        TIMESTAMP
);

TRUNCATE TABLE co_sandbox_datos.tbl_disponibilidad_hora_carga;

INSERT INTO co_sandbox_datos.tbl_disponibilidad_hora_carga
SELECT * FROM co_sandbox_datos.vw_disponibilidad_hora_carga;

-- Verificación:
--   SELECT estado, COUNT(*) FROM co_sandbox_datos.tbl_disponibilidad_hora_carga GROUP BY 1 ORDER BY 1;
