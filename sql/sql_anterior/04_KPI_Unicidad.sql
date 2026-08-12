-- TABLA UNICIDAD --
create table co_sandbox_datos.kpi_unicidad_mensual (
	periodo_contable INTEGER,
	nombre_campo VARCHAR(100),
	total_registros BIGINT,
	cantidad_inexactos BIGINT,
	porcentaje_unicidad DECIMAL (10,2),
	fecha_calculo TIMESTAMP default CURRENT_TIMESTAMP,
	es_total INTEGER
);

--////////// SP UNICIDAD //////////--
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_unicidad_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
 
BEGIN
 
-- borrar datos del periodo si existen
DELETE FROM co_sandbox_datos.kpi_unicidad_mensual
WHERE periodo_contable = p_periodo;
 
INSERT INTO co_sandbox_datos.kpi_unicidad_mensual
 
WITH base AS (
 
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = p_periodo
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
 
),
 
duplicados AS (
 
    SELECT policy_transaction_movement_sk
    FROM base
    GROUP BY policy_transaction_movement_sk
    HAVING COUNT(*) > 1
 
),
 
conteo_duplicados AS (
 
    SELECT COUNT(*) AS cantidad_inexactos
    FROM base
    WHERE policy_transaction_movement_sk IN (
        SELECT policy_transaction_movement_sk
        FROM duplicados
    )
 
),
 
total_base AS (
 
    SELECT COUNT(*) AS total_registros
    FROM base
 
)
 
SELECT
    p_periodo AS periodo_contable,
    'policy_transaction_movement_sk' AS nombre_campo,
    t.total_registros,
    COALESCE(d.cantidad_inexactos,0) AS cantidad_inexactos,
 
    ROUND(
        100.0 *
        (t.total_registros - COALESCE(d.cantidad_inexactos,0))
        / t.total_registros
    ,2) AS porcentaje_unicidad,
 
    CURRENT_TIMESTAMP AS fecha_calculo,
    1 AS es_total
 
FROM total_base t
LEFT JOIN conteo_duplicados d
ON 1=1;
 
END;
$$;

-- ////// vista para power bi ///////
create or replace view co_sandbox_datos.vw_kpi_unicidad_mensual_pbi as
select
	periodo_contable,
	nombre_campo,
	total_registros,
	cantidad_inexactos,
	porcentaje_unicidad,
	fecha_calculo,
	es_total
from co_sandbox_datos.kpi_unicidad_mensual;

-- Ejecutar sp
call co_sandbox_datos.sp_kpi_unicidad_mensual(202509);

--Validarlo
select *
from co_sandbox_datos.kpi_unicidad_mensual
where periodo_contable = 202602
order by nombre_campo;