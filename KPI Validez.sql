--creación tabla validez 
create table co_sandbox_datos.kpi_validez_mensual (
	periodo_contable INTEGER,
	nombre_campo VARCHAR(50),
	total_registros INTEGER,
	cantidad_invalidos INTEGER,
	porcentaje_validez NUMERIC(10,2),
	es_total INTEGER
);

--///////////////////// SP KPI VALIDEZ /////////////////////////--
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_validez_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
 
-- Eliminar registros del período si ya existen (idempotencia)
DELETE FROM co_sandbox_datos.kpi_validez_mensual
WHERE periodo_contable = p_periodo;
 
 
-- Universo base
INSERT INTO co_sandbox_datos.kpi_validez_mensual
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
 
agregados AS (
    
    SELECT    
		COUNT(*) AS total_registros,
 
        -- 1 source_system -> 'Unknown'
     	SUM(CASE WHEN source_system IS NULL
				OR source_system = 'Unknown'
		 THEN 1 ELSE 0 END) AS n_source_system,

  -- 2 coverage_code -> 'Unknown'
     	SUM(CASE WHEN coverage_code IS NULL
				OR coverage_code = 'Unknown'
		 THEN 1 ELSE 0 END) AS n_coverage_code,

 -- 3 product_code
     	SUM(CASE WHEN product_code IS NULL
				OR product_code = 'Unknown'
				OR LENGTH(product_code) > 6 -- válido hasta 6 dígitos 
				OR product_code LIKE '% %'
				OR product_code ~ '[^A-Za-z0-9]'
				OR (source_system = 'CO_iaxis' -- para as400 se permiten letras y para IAXIS solo números
					AND product_code ~ '[A-Za-z]') 
		 THEN 1 ELSE 0 END) AS n_product_code,

 -- 4 transaction_date_sk -> formato YYYYMMDD
     	SUM(CASE WHEN transaction_date_sk IS NULL
				OR transaction_date_sk:: VARCHAR !~ '^[0-9]{8}$'
		 THEN 1 ELSE 0 END) AS n_transaction_date_sk,

 -- 5 transaction_type
     	SUM(CASE WHEN transaction_type IS NULL
				OR transaction_type = 'Unknown'
				OR LENGTH(transaction_type) > 2 -- válido hasta 2 dígitos
		 THEN 1 ELSE 0 END) AS n_transaction_type,

 -- 6 movement_type
  /*   	SUM(CASE WHEN movement_type IS NULL
				OR movement_type = 'Unknown'
		 THEN 1 ELSE 0 END) AS n_movement_type,*/

 -- 7 current_record_flag -> solo 1 o 0
     	SUM(CASE WHEN current_record_flag IS NULL
				OR current_record_flag NOT IN (0,1)
		 THEN 1 ELSE 0 END) AS n_current_record_flag,

 -- 8 risk_number -> not in 'Unknown'
     	SUM(CASE WHEN risk_number IS NULL
				OR risk_number = 'Unknown' 
		 THEN 1 ELSE 0 END) AS n_risk_number,

 -- 9 policy_number -> not in 'Unknown'
     	SUM(CASE WHEN policy_number IS NULL
				OR policy_number = 'Unknown'
		 THEN 1 ELSE 0 END) AS n_policy_number,

-- 10 accountable_period formato YYYYMM 
		SUM(
			CASE
				WHEN accountable_period IS NULL
				OR LENGTH(accountable_period::VARCHAR) <> 6
			THEN 1 ELSE 0 END
			) AS n_accountable_period,

-- 11 policy_effective_date_sk formato YYYYMMDD 
		SUM(
			CASE
				WHEN policy_effective_date_sk IS NULL
				OR LENGTH(policy_effective_date_sk::VARCHAR) <> 8
			THEN 1 ELSE 0 END
			) AS n_policy_effective_date_sk,

-- 12 policy_expiration_date_sk formato YYYYMMDD 
		SUM(
			CASE
				WHEN policy_expiration_date_sk IS NULL
				OR LENGTH(policy_expiration_date_sk::VARCHAR) <> 8
			THEN 1 ELSE 0 END
			) AS n_policy_expiration_date_sk,

-- 13 inception_date_sk formato YYYYMMDD 
		SUM(
			CASE
				WHEN inception_date_sk IS NULL
				OR LENGTH(inception_date_sk::VARCHAR) <> 8
			THEN 1 ELSE 0 END
			) AS n_inception_date_sk,

-- 14 transaction_effective_date_sk formato YYYYMMDD 
		SUM(
			CASE
				WHEN transaction_effective_date_sk IS NULL
				OR LENGTH(transaction_effective_date_sk::VARCHAR) <> 8
			THEN 1 ELSE 0 END
			) AS n_transaction_effective_date_sk
    FROM base
)
 
SELECT
    p_periodo AS periodo_contable,
    nombre_campo,
    total_registros,
    cantidad_invalidos,
    CASE 
        WHEN total_registros = 0 THEN 0
        ELSE ROUND(100.0 * (1 - cantidad_invalidos::DECIMAL / total_registros), 2)
    END AS porcentaje_validez
FROM (
    SELECT total_registros, 'source_system', n_source_system FROM agregados
    UNION ALL SELECT total_registros, 'coverage_code', n_coverage_code FROM agregados
    UNION ALL SELECT total_registros, 'product_code', n_product_code FROM agregados
    UNION ALL SELECT total_registros, 'transaction_date_sk', n_transaction_date_sk FROM agregados
    UNION ALL SELECT total_registros, 'transaction_type', n_transaction_type FROM agregados
    UNION ALL SELECT total_registros, 'current_record_flag', n_current_record_flag FROM agregados
    UNION ALL SELECT total_registros, 'risk_number', n_risk_number FROM agregados
    UNION ALL SELECT total_registros, 'policy_number', n_policy_number FROM agregados
	UNION ALL SELECT total_registros, 'accountable_period', n_accountable_period FROM agregados
	UNION ALL SELECT total_registros, 'policy_effective_date_sk', n_policy_effective_date_sk FROM agregados
	UNION ALL SELECT total_registros, 'inception_date_sk', n_inception_date_sk FROM agregados
	UNION ALL SELECT total_registros, 'transaction_effective_date_sk', n_transaction_effective_date_sk FROM agregados
) t(total_registros, nombre_campo, cantidad_invalidos);
 
 
-- Insertar promedio general del período
INSERT INTO co_sandbox_datos.kpi_validez_mensual
SELECT
    p_periodo,
    'TOTAL_PERIODO',
    MAX(total_registros),
    NULL,
    ROUND(AVG(porcentaje_validez), 2)
FROM co_sandbox_datos.kpi_validez_mensual
WHERE periodo_contable = p_periodo;
 
END;
$$;

--Creación vista KPI Validez
create or replace view co_sandbox_datos.vw_kpi_validez_mensual_pbi as
select
	periodo_contable,
	nombre_campo,
	total_registros,
	cantidad_invalidos,
	porcentaje_validez,
	case
		when nombre_campo = 'TOTAL_PERIODO' then 1
		else 0
	end as es_total
from co_sandbox_datos.kpi_validez_mensual;

--Validar Vista
select *
from co_sandbox_datos.vw_kpi_validez_mensual_pbi
where periodo_contable = 202602
order by nombre_campo;


--Ejecutar SP
call co_sandbox_datos.sp_kpi_validez_mensual(202602);

--Validarlo
select *
from co_sandbox_datos.kpi_validez_mensual
where periodo_contable = 202602
order by nombre_campo;

select * from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement limit 5;

--Validación de los invalidos (se hace con cada uno de los que tuvieron baja validez)
--distribución general

--movement_type
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select
	movement_type,
	count(*) as cantidad
from base
group by movement_type
order by cantidad desc;

--transaction_type
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select
	transaction_type,
	count(*) as cantidad
from base
group by transaction_type
order by 2 desc;

--product_code
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select
	product_code,
	count(*) as cantidad
from base
group by product_code
order by 2 desc
limit 20;

--risk_number
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select
	risk_number,
	count(*) as cantidad
from base
group by risk_number
order by 2 desc;

--policy_number
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select
	policy_number,
	count(*) as cantidad
from base
group by policy_number
order by 2 desc;

--detalle
--movement_type
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select * 
from base
where movement_type is null
	or movement_type = 'Unknown'
limit 100;

--transaction_type
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select * 
from base
where transaction_type is null
	or transaction_type = 'Unknown'
	or length(transaction_type) <> 2 -- es válido con uno y 2 dígitos - revisar
limit 100;

--product_code
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202602
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis'
             AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
)
select
	product_code,
	count(*) as cantidad
from base
where product_code like '% %'
--where product_code ~ '[^A-Za-z0-9]'
--where length(product_code) <> 6
--where source_system <> 'CO_as400'
	--and product_code ~ '[A-Za-z]'
group by product_code
order by 2 desc
limit 20;