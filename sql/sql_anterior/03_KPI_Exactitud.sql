--creación tabla Exactitud 
create table co_sandbox_datos.kpi_exactitud_mensual (
	periodo_contable INTEGER,
	nombre_campo VARCHAR(100),
	total_registros BIGINT,
	cantidad_inexactos BIGINT,
	porcentaje_exactitud DECIMAL (10,2),
	fecha_calculo TIMESTAMP default CURRENT_TIMESTAMP
);

alter table co_sandbox_datos.kpi_exactitud_mensual
add column es_total INTEGER;

drop table co_sandbox_datos.kpi_exactitud_mensual;

--///////////////////// SP KPI EXACTITUD /////////////////////////--
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_exactitud_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
 
BEGIN
 
DELETE FROM co_sandbox_datos.kpi_exactitud_mensual
WHERE periodo_contable = p_periodo;
 
INSERT INTO co_sandbox_datos.kpi_exactitud_mensual
 
WITH base AS (
 
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = p_periodo
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
 
),
 
reglas AS (
 
-- SOURCE_SYSTEM
 
SELECT
    p_periodo AS periodo_contable,
    'source_system' AS nombre_campo,
    COUNT(*) AS total_registros,
 
    SUM(
        CASE
            WHEN source_system IS NULL
            OR source_system NOT IN ('CO_iaxis','CO_as400')
            THEN 1
            ELSE 0
        END
    ) AS cantidad_inexactos,
 
    ROUND(
        100.0 *
        (COUNT(*) -
            SUM(
                CASE
                    WHEN source_system IS NULL
                    OR source_system NOT IN ('CO_iaxis','CO_as400')
                    THEN 1
                    ELSE 0
                END
            )
        ) / COUNT(*)
    ,2) AS porcentaje_exactitud,
 
    CURRENT_TIMESTAMP,
    0 AS es_total
 
FROM base
 
UNION ALL
 
 
-- CURRENT_RECORD_FLAG
 
SELECT
    p_periodo,
    'current_record_flag',
    COUNT(*),
 
    SUM(
        CASE
            WHEN current_record_flag IS NULL
            OR current_record_flag NOT IN (0,1)
            THEN 1
            ELSE 0
        END
    ),
 
    ROUND(
        100.0 *
        (COUNT(*) -
            SUM(
                CASE
                    WHEN current_record_flag IS NULL
                    OR current_record_flag NOT IN (0,1)
                    THEN 1
                    ELSE 0
                END
            )
        ) / COUNT(*)
    ,2),
 
    CURRENT_TIMESTAMP,
    0
 
FROM base
 
UNION ALL
 
 
-- RECEIPT_TYPE
 
SELECT
    p_periodo,
    'receipt_type',
    COUNT(*),
 
    SUM(
        CASE
            WHEN receipt_type IS NULL
            OR receipt_type NOT IN (
                'not-unificado',
                'unificado-detail',
                'unificado-total'
            )
            THEN 1
            ELSE 0
        END
    ),
 
    ROUND(
        100.0 *
        (COUNT(*) -
            SUM(
                CASE
                    WHEN receipt_type IS NULL
                    OR receipt_type NOT IN (
                        'not-unificado',
                        'unificado-detail',
                        'unificado-total'
                    )
                    THEN 1
                    ELSE 0
                END
            )
        ) / COUNT(*)
    ,2),
 
    CURRENT_TIMESTAMP,
    0
 
FROM base
 
)
 
SELECT * FROM reglas
 
UNION ALL
 
SELECT
    p_periodo,
    'TOTAL',
    MAX (total_registros) AS total_registros,

    SUM(cantidad_inexactos) as cantidad_inexactos,
 
    ROUND(AVG(porcentaje_exactitud),2) as porcentaje_exactitud,
 
    CURRENT_TIMESTAMP as fecha_calculo,
    1 as es_total
 
FROM reglas;
 
END;
$$;


-- ////// vista para power bi ///////
create or replace view co_sandbox_datos.vw_kpi_exactitud_mensual_pbi as
select
	periodo_contable,
	nombre_campo,
	total_registros,
	cantidad_inexactos,
	porcentaje_exactitud,
	fecha_calculo,
	es_total
from co_sandbox_datos.kpi_exactitud_mensual;

drop view co_sandbox_datos.vw_kpi_exactitud_mensual_pbi;

-- Ejecutar SP
call co_sandbox_datos.sp_kpi_exactitud_mensual(202509);

--Validarlo
select *
from co_sandbox_datos.kpi_exactitud_mensual
where periodo_contable = 202602
order by nombre_campo;


--Validar que los resultados sí sean correctos
select distinct receipt_type
from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
where accountable_period = 202602;

