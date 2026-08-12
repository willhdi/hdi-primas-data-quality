-- ////////// KPI COMPLETITUD //////////////////////// --

--TABLA RESUMEN (para Power BI)
create table co_sandbox_datos.kpi_completitud_mensual (
	periodo_contable INTEGER,
	nombre_campo VARCHAR(100),
	total_registros BIGINT,
	cantidad_nulls BIGINT,
	porcentaje_completitud DECIMAL(6,2),
	fecha_calculo TIMESTAMP default GETDATE()
);

-- ///// SP COMPLETITUD ///////--
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_completitud_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
 
-- Eliminar registros del período si ya existen (idempotencia)
DELETE FROM co_sandbox_datos.kpi_completitud_mensual
WHERE periodo_contable = p_periodo;
 
 
-- Insertar métricas optimizadas (UNA sola lectura de la vista)
INSERT INTO co_sandbox_datos.kpi_completitud_mensual
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
 
        -- 19 campos obligatorios
        SUM(CASE WHEN source_system IS NULL THEN 1 ELSE 0 END) AS n_source_system,
        SUM(CASE WHEN accountable_period IS NULL THEN 1 ELSE 0 END) AS n_accountable_period,
        SUM(CASE WHEN coverage_code IS NULL THEN 1 ELSE 0 END) AS n_coverage_code,
        SUM(CASE WHEN branch_sk IS NULL THEN 1 ELSE 0 END) AS n_branch_sk,
        SUM(CASE WHEN product_code IS NULL THEN 1 ELSE 0 END) AS n_product_code,
        SUM(CASE WHEN transaction_date_sk IS NULL THEN 1 ELSE 0 END) AS n_transaction_date_sk,
        SUM(CASE WHEN policy_effective_date_sk IS NULL THEN 1 ELSE 0 END) AS n_policy_effective_date_sk,
        SUM(CASE WHEN policy_expiration_date_sk IS NULL THEN 1 ELSE 0 END) AS n_policy_expiration_date_sk,
        SUM(CASE WHEN inception_date_sk IS NULL THEN 1 ELSE 0 END) AS n_inception_date_sk,
        SUM(CASE WHEN transaction_type IS NULL THEN 1 ELSE 0 END) AS n_transaction_type,
        SUM(CASE WHEN transaction_effective_date_sk IS NULL THEN 1 ELSE 0 END) AS n_transaction_effective_date_sk,
        SUM(CASE WHEN transaction_type_description IS NULL THEN 1 ELSE 0 END) AS n_transaction_type_description,
        SUM(CASE WHEN current_record_flag IS NULL THEN 1 ELSE 0 END) AS n_current_record_flag,
        SUM(CASE WHEN transaction_delta_billed_premium_amount IS NULL THEN 1 ELSE 0 END) AS n_transaction_delta_billed_premium_amount,
        SUM(CASE WHEN transaction_delta_commission_amount IS NULL THEN 1 ELSE 0 END) AS n_transaction_delta_commission_amount,
        SUM(CASE WHEN risk_number IS NULL THEN 1 ELSE 0 END) AS n_risk_number,
        SUM(CASE WHEN policy_number IS NULL THEN 1 ELSE 0 END) AS n_policy_number,
        SUM(CASE WHEN transaction_delta_billed_premium_amount_raw IS NULL THEN 1 ELSE 0 END) AS n_transaction_delta_billed_premium_amount_raw,
		SUM(CASE WHEN policy_transaction_movement_sk IS NULL THEN 1 ELSE 0 END) AS n_policy_transaction_movement_sk,
 
        -- 3 campos con excepción (dentro del universo filtrado)
        SUM(CASE WHEN sseguro IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS n_sseguro,
        SUM(CASE WHEN receipt_type IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS n_receipt_type,
        SUM(
			CASE 
				WHEN (
					receipt_number IS NULL 
					AND source_system <> 'CO_as400' 
					AND receipt_type <> 'not-unificado'
				)
				OR (
					receipt_type = 'not-unificado'
					AND receipt_number IS NOT NULL
				)
			THEN 1 ELSE 0 END 
 	) AS n_receipt_number
    
FROM base
)
 
SELECT
    p_periodo AS periodo_contable,
    nombre_campo,
    total_registros,
    cantidad_nulls,
    CASE 
        WHEN total_registros = 0 THEN 0
        ELSE ROUND(100.0 * (1 - cantidad_nulls::DECIMAL / total_registros), 2)
    END AS porcentaje_completitud
FROM (
    SELECT total_registros, 'source_system', n_source_system FROM agregados
    UNION ALL SELECT total_registros, 'accountable_period', n_accountable_period FROM agregados
    UNION ALL SELECT total_registros, 'coverage_code', n_coverage_code FROM agregados
    UNION ALL SELECT total_registros, 'branch_sk', n_branch_sk FROM agregados
    UNION ALL SELECT total_registros, 'product_code', n_product_code FROM agregados
    UNION ALL SELECT total_registros, 'transaction_date_sk', n_transaction_date_sk FROM agregados
    UNION ALL SELECT total_registros, 'policy_effective_date_sk', n_policy_effective_date_sk FROM agregados
    UNION ALL SELECT total_registros, 'policy_expiration_date_sk', n_policy_expiration_date_sk FROM agregados
    UNION ALL SELECT total_registros, 'inception_date_sk', n_inception_date_sk FROM agregados
    UNION ALL SELECT total_registros, 'transaction_type', n_transaction_type FROM agregados
    UNION ALL SELECT total_registros, 'transaction_effective_date_sk', n_transaction_effective_date_sk FROM agregados
    UNION ALL SELECT total_registros, 'transaction_type_description', n_transaction_type_description FROM agregados
    UNION ALL SELECT total_registros, 'current_record_flag', n_current_record_flag FROM agregados
    UNION ALL SELECT total_registros, 'transaction_delta_billed_premium_amount', n_transaction_delta_billed_premium_amount FROM agregados
    UNION ALL SELECT total_registros, 'transaction_delta_commission_amount', n_transaction_delta_commission_amount FROM agregados
    UNION ALL SELECT total_registros, 'risk_number', n_risk_number FROM agregados
    UNION ALL SELECT total_registros, 'policy_number', n_policy_number FROM agregados
    UNION ALL SELECT total_registros, 'transaction_delta_billed_premium_amount_raw', n_transaction_delta_billed_premium_amount_raw FROM agregados
    UNION ALL SELECT total_registros, 'sseguro', n_sseguro FROM agregados
    UNION ALL SELECT total_registros, 'receipt_type', n_receipt_type FROM agregados
    UNION ALL SELECT total_registros, 'receipt_number', n_receipt_number FROM agregados
	UNION ALL SELECT total_registros, 'policy_transaction_movement_sk', n_policy_transaction_movement_sk FROM agregados
) t(total_registros, nombre_campo, cantidad_nulls);
 
 
-- Insertar promedio general del período
INSERT INTO co_sandbox_datos.kpi_completitud_mensual
SELECT
    p_periodo,
    'TOTAL_PERIODO',
    MAX(total_registros),
    NULL,
    ROUND(AVG(porcentaje_completitud), 2)
FROM co_sandbox_datos.kpi_completitud_mensual
WHERE periodo_contable = p_periodo;
 
END;
$$;

--Ejecutar SP
call co_sandbox_datos.sp_kpi_completitud_mensual(202602);


--Validarlo
select *
from co_sandbox_datos.kpi_completitud_mensual
where periodo_contable = 202602
order by nombre_campo;
 
--QUERYS VALIDADORAS
-- Validar movement_type = 0%
with base as (
	select movement_type
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202602
		and current_record_flag = 1 
		and coverage_code <> 8888
		and transaction_delta_billed_premium_amount <> 0
		and (
			  (source_system = 'CO_iaxis'
			   and receipt_type not in ('unificado-total'))
			  or source_system = 'CO_as400'
		)
)
select
	count(*) as total,
	sum(case when movement_type is null then 1 else 0 end) as nulls,
	sum(case when movement_type is not null then 1 else 0 end) as no_nulls
from base;

--Revisar distribución por sistema (esto indica si el problema viene de as400 o iaxis)
with base as (
	select source_system, movement_type
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202602
		and current_record_flag = 1 
		and coverage_code <> 8888
		and transaction_delta_billed_premium_amount <> 0
		and (
			  (source_system = 'CO_iaxis'
			   and receipt_type not in ('unificado-total'))
			  or source_system = 'CO_as400'
		)
)
select
	source_system,
	count(*) as total,
	sum(case when movement_type is null then 1 else 0 end) as nulls
from base
group by source_system;

--Validar movement_type = 20,93%
with base as (
	select source_system, movement_type
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202602
		and current_record_flag = 1 
		and coverage_code <> 8888
		and transaction_delta_billed_premium_amount <> 0
		and (
			  (source_system = 'CO_iaxis'
			   and receipt_type not in ('unificado-total'))
			  or source_system = 'CO_as400'
		)
)
select
	count(*) as total,
	sum(case when movement_type is null
				and source_system <> 'CO_as400' then 1 else 0 end) as nulls_regla
from base;

--Ver distribución por sistema
select
	source_system,
	count(*) total,
	sum(case when receipt_number is null then 1 else 0 end) as nulls
from base
group by source_system;


--Validar sseguro = 99,97%
with base as (
	select source_system, sseguro
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202602
		and current_record_flag = 1 
		and coverage_code <> 8888
		and transaction_delta_billed_premium_amount <> 0
		and (
			  (source_system = 'CO_iaxis'
			   and receipt_type not in ('unificado-total'))
			  or source_system = 'CO_as400'
		)
)
select count(*) total, source_system
from base
where sseguro is null
and source_system <> 'CO_as400'
group by source_system;


--Casos puntuales para movement_type
select source_system,
	   count(*) total,
	   sum(case when movement_type is null then 1 else 0 end) as nulls
from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
where accountable_period = 202602
group by source_system;

select movement_type,
	   count(*) total
from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
where accountable_period = 202602
group by movement_type
order by 2 desc;

--Casos puntuales
select policy_number,
	   source_system,
	   movement_type,
	   transaction_type,
	   receipt_number,
	   sseguro,
	   accountable_period
from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
where accountable_period = 202602
	and current_record_flag = 1 
	and coverage_code <> 8888
	and transaction_delta_billed_premium_amount <> 0
	and (
		 (source_system = 'CO_iaxis'
			  and receipt_type not in ('unificado-total'))
			  or source_system = 'CO_as400'
		)
limit 20;

--Validar para receipt_number y movement_type en un periodo anterior
select source_system,
		   count(*) total,
		   sum(case when receipt_number is null then 1 else 0 end) as nulls
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202601
	and current_record_flag = 1 
	and coverage_code <> 8888
	and transaction_delta_billed_premium_amount <> 0
	and (
		 (source_system = 'CO_iaxis'
			  and receipt_type not in ('unificado-total'))
			  or source_system = 'CO_as400'
		)
	group by source_system;


--Comprobar si sseguro nulls son de as400
	select source_system,
		   count(*) total,
		   sum(case when sseguro is null then 1 else 0 end) as nulls
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202602
	group by source_system;

--/////// Creación de vista para Power BI ////////////////

create or replace view co_sandbox_datos.vw_kpi_completitud_mensual_pbi as
select
	periodo_contable,
	nombre_campo,
	total_registros,
	cantidad_nulls,
	porcentaje_completitud,
	fecha_calculo,
	case
		when nombre_campo = 'TOTAL_PERIODO' then 1
		else 0
	end as es_total
from co_sandbox_datos.kpi_completitud_mensual;

 drop view co_sandbox_datos.vw_kpi_completitud_mensual_pbi;
 
--Validar vista
select *
from co_sandbox_datos.vw_kpi_completitud_mensual_pbi
where periodo_contable = 202602
order by nombre_campo;
	