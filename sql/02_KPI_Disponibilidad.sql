-- Lógica Estebitan para Disponibilidad --

--Si la cuenta es = 0: Está sincronizada.
 --Si la cuenta es > 0: No se ha terminado de hacer el refresh de la vista materializada y hay N filas faltantes en la vista.
SELECT COUNT(*) AS missing_count
FROM gde_adp_dwh.fact_policy_transaction_movement t1
LEFT JOIN gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement t2
  ON t1.policy_transaction_movement_sk = t2.policy_transaction_movement_sk
WHERE t2.policy_transaction_movement_sk IS NULL;

-- Tabla KPI Disponibilidad
create table if not exists co_sandbox_datos.kpi_disponibilidad_mensual (
	periodo_contable integer,
	nombre_campo varchar(50),
	total_registros bigint,
	cantidad_faltantes bigint,
	porcentaje_disponibilidad decimal (5,2),
	es_total integer,
	fecha_calculo timestamp
);

--//////////////////////// SP KPI DISPONIBILIDAD //////////////////////// --

CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_disponibilidad_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
 
BEGIN
 
-- Limpiar datos del periodo
DELETE FROM co_sandbox_datos.kpi_disponibilidad_mensual
WHERE periodo_contable = p_periodo;
 
-- Insertar KPI
INSERT INTO co_sandbox_datos.kpi_disponibilidad_mensual
 
WITH base_dwh AS (
    SELECT policy_transaction_movement_sk
    FROM gde_adp_dwh.fact_policy_transaction_movement
    WHERE CAST(TO_CHAR(transaction_accounting_ts, 'YYYYMM') AS INTEGER) = p_periodo
),
 
base_vista AS (
    SELECT policy_transaction_movement_sk
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE CAST(TO_CHAR(transaction_accounting_ts, 'YYYYMM') AS INTEGER) = p_periodo
),
 
faltantes AS (
    SELECT COUNT(*) AS missing_count
    FROM base_dwh t1
    LEFT JOIN base_vista t2
        ON t1.policy_transaction_movement_sk = t2.policy_transaction_movement_sk
    WHERE t2.policy_transaction_movement_sk IS NULL
),
 
totales AS (
    SELECT COUNT(*) AS total_registros
    FROM base_dwh
)
 
SELECT
    p_periodo AS periodo_contable,
    'disponibilidad_sync' AS nombre_campo,
    t.total_registros,
    f.missing_count AS cantidad_faltantes,
    CASE
        WHEN t.total_registros = 0 THEN 0
        ELSE ROUND(((t.total_registros - f.missing_count) * 100.0 / t.total_registros), 2)
    END AS porcentaje_disponibilidad,
    1 AS es_total,
    CURRENT_TIMESTAMP AS fecha_calculo
FROM totales t, faltantes f;

-- regla 4 (días 1- 15 por ramo)
insert into co_sandbox_datos.kpi_disponibilidad_mensual

with base as (
	select 
		product_code, 
		cast(substring(cast(transaction_date_sk as varchar), 7, 2) as integer) as dia
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where CAST(TO_CHAR(transaction_accounting_ts, 'YYYYMM') AS INTEGER) = p_periodo
),

-- días válidos 1-15
dias_validos as (
	select 1 as dia union all
	select 2 union all
	select 3 union all
	select 4 union all
	select 5 union all
	select 6 union all
	select 7 union all
	select 8 union all
	select 9 union all
	select 10 union all
	select 11 union all
	select 12 union all
	select 13 union all
	select 14 union all
	select 15
	
),

-- combinaciones esperadas (ramo x dia), es decir todos los días que deberían existir
ramo_dias_esperados as (
	select distinct b.product_code, d.dia
from (select distinct product_code from base) b
cross join dias_validos d
),

-- combinaciones reales (lo que realmente llegó)
ramo_dias_reales as (
	select distinct product_code, dia
	from base
	where dia between 1 and 15
),

-- faltantes
faltantes_regla4 as (
	select r.product_code
	from ramo_dias_esperados r
	left join ramo_dias_reales t -- detecta días faltantes por ramo
		on r.product_code = t.product_code
		and r.dia = t.dia
	where t.product_code is null
),

-- ramos totales
total_ramos as (
	select count(distinct product_code) as total
	from base
), 

-- ramos que cumplen (no están en faltantes)
ramos_ok as (
	select count(*) as ok_count
	from (
		select distinct product_code from base
		except
		select distinct product_code from faltantes_regla4
	) t
)

select 
	p_periodo,
	'disponibilidad_regla4',
	t.total,
	(t.total - r.ok_count),
	case
		when t.total = 0 then 0
		else round((r.ok_count * 100.0 / t.total), 2)
	end,
	1,
	current_timestamp
from total_ramos t, ramos_ok r;

END;
$$;


-- Vista KPI --
create or replace view co_sandbox_datos.vw_kpi_disponibilidad_mensual_pbi as
select *
from co_sandbox_datos.kpi_disponibilidad_mensual;


-- Llamado del SP
call co_sandbox_datos.sp_kpi_disponibilidad_mensual(202509);

--consultar tabla disponibilidad
select * from co_sandbox_datos.kpi_disponibilidad_mensual

--consultas a la fact y a la vista fact
select * from gde_adp_dwh.fact_policy_transaction_movement
limit 5;

select * from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
limit 5;


--Interpretación del resultado

--Hay 2 tipos de registros por periodo:

--*disponibilidad_sync
-- + Compara fact vs vista
-- + Mide si la vista está sincronizada

--*disponibilidad_regla4
-- + Evalúa presencia de datos por ramo en días 1-15
-- + Es una regla de negocio (no técnica)

--Validación de disponibilidad_sync

--Ejemplo (202603)
--total_registros: 9.253.645
--cantidad_faltantes: 112.388
--porcentaje: 98,79%
-- 98% --> casi sincronizado
-- no es 100% --> hay retraso en refresh

--Validación de disponibilidad_regla4
--Ejemplo (202603)
--total_registros: 82
--cantidad_faltantes: 76
--porcentaje: 7,32%

-- Qué significa realmente:
--total = número de ramos
--faltantes = ramos que NO tienen datos en algún día (1-15)
--% = ramos completos

--Es decir solo el 7% de los ramos tienen datos TODOS los días del 1 al 15
--El resto falla en al menos un día

--Validación QA

--ver ramos con problema
--con esto podemos decir X ramo no tiene datos el día 3,7,12..
WITH base AS (
    SELECT
        product_code,
        CAST(SUBSTRING(CAST(transaction_date_sk AS VARCHAR), 7, 2) AS INT) AS dia
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = 202603
),
 
dias_validos AS (
    SELECT 1 AS dia UNION ALL
    SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL
    SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL
    SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL
    SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL
    SELECT 14 UNION ALL SELECT 15
),
 
ramo_dias_esperados AS (
    SELECT DISTINCT b.product_code, d.dia
    FROM (SELECT DISTINCT product_code FROM base) b
    CROSS JOIN dias_validos d
),
 
ramo_dias_reales AS (
    SELECT DISTINCT product_code, dia
    FROM base
    WHERE dia BETWEEN 1 AND 15
),
 
faltantes AS (
    SELECT r.product_code, r.dia
    FROM ramo_dias_esperados r
    LEFT JOIN ramo_dias_reales t
        ON r.product_code = t.product_code
        AND r.dia = t.dia
    WHERE t.product_code IS NULL
)
 
SELECT *
FROM faltantes
ORDER BY product_code, dia;


-- ¿Cuántos días tiene info en cada ramo?
with base as (
	select
		product_code,
		cast(substring(cast(transaction_date_sk as varchar), 7, 2) as int) as dia
	from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
	where accountable_period = 202603
)
select
	product_code,
	count(distinct dia) as dias_con_info
from base
where dia between 1 and 15
group by product_code
order by dias_con_info;