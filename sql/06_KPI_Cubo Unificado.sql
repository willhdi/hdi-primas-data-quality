-- ////////// CUBO UNIFICADO DE CALIDAD DE DATOS (PRIMAS) //////////////////////// --
-- Archivo nuevo e independiente: reemplaza la NECESIDAD de correr los 5
-- archivos KPI <Nombre>.sql / sus 5 tablas y procedimientos por separado.
-- No llama a sp_kpi_completitud_mensual, sp_kpi_exactitud_mensual,
-- sp_kpi_unicidad_mensual, sp_kpi_validez_mensual ni sp_kpi_disponibilidad_mensual:
-- toda la lógica de cada indicador está reescrita aquí mismo, así que este
-- archivo funciona solo (no depende de que los otros 5 se hayan ejecutado
-- antes ni de que sigan existiendo).
--
-- Los 5 archivos originales NO se tocan ni se borran en este cambio — se
-- dejan como respaldo/referencia hasta que se confirme que este cubo los
-- reemplaza en Power BI. 
--
-- Cambio de comportamiento a propósito vs. el archivo original de Exactitud:
-- aquí Exactitud SÍ aplica el filtro compartido completo (incluye
-- current_record_flag = 1), igual que Completitud/Unicidad/Validez. El
-- archivo original de Exactitud no lo tenía (ver "Hallazgos y Estado del
-- Proyecto.md") — se corrige aquí porque es código nuevo, no una
-- modificación del original.

-- //////////////////////// TABLA CUBO //////////////////////// --
-- Formato largo: una fila por periodo + indicador + campo.
create table if not exists co_sandbox_datos.kpi_cubo_mensual (
    periodo_contable INTEGER,
    tipo_indicador VARCHAR(20),   -- completitud | exactitud | unicidad | validez | disponibilidad
    nombre_campo VARCHAR(100),
    total_registros BIGINT,
    cantidad_mala BIGINT,         -- nulls / inexactos / duplicados / inválidos / faltantes, según tipo_indicador
    porcentaje DECIMAL(6,2),
    es_total INTEGER,             -- 1 = fila agregada (TOTAL_PERIODO / TOTAL / disponibilidad), 0 = fila por campo
    fecha_calculo TIMESTAMP default GETDATE()
);

-- //////////////////////// SP CUBO //////////////////////// --
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_cubo_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN

-- Idempotencia: borra el periodo completo (los 5 indicadores) antes de recalcular
DELETE FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable = p_periodo;

-- ============================================================
-- 1) COMPLETITUD
-- ============================================================
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = p_periodo
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
),
agregados AS (
    SELECT
        COUNT(*) AS total_registros,
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
    p_periodo,
    'completitud',
    nombre_campo,
    total_registros,
    cantidad_nulls,
    CASE
        WHEN total_registros = 0 THEN 0
        ELSE ROUND(100.0 * (1 - cantidad_nulls::DECIMAL / total_registros), 2)
    END,
    0,
    GETDATE()
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

INSERT INTO co_sandbox_datos.kpi_cubo_mensual
SELECT
    p_periodo,
    'completitud',
    'TOTAL_PERIODO',
    MAX(total_registros),
    SUM(cantidad_mala),
    ROUND(AVG(porcentaje), 2),
    1,
    GETDATE()
FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable = p_periodo
  AND tipo_indicador = 'completitud';

-- ============================================================
-- 2) EXACTITUD
-- (usa el filtro compartido completo, incluyendo current_record_flag = 1;
--  ver nota al inicio del archivo)
-- ============================================================
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = p_periodo
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
),
reglas AS (
    SELECT
        'source_system' AS nombre_campo,
        COUNT(*) AS total_registros,
        SUM(CASE WHEN source_system IS NULL OR source_system NOT IN ('CO_iaxis','CO_as400') THEN 1 ELSE 0 END) AS cantidad_mala
    FROM base

    UNION ALL

    SELECT
        'current_record_flag',
        COUNT(*),
        SUM(CASE WHEN current_record_flag IS NULL OR current_record_flag NOT IN (0,1) THEN 1 ELSE 0 END)
    FROM base

    UNION ALL

    SELECT
        'receipt_type',
        COUNT(*),
        SUM(
            CASE
                WHEN receipt_type IS NULL
                OR receipt_type NOT IN ('not-unificado','unificado-detail','unificado-total')
                THEN 1 ELSE 0
            END
        )
    FROM base
)
SELECT
    p_periodo,
    'exactitud',
    nombre_campo,
    total_registros,
    cantidad_mala,
    CASE WHEN total_registros = 0 THEN 0 ELSE ROUND(100.0 * (total_registros - cantidad_mala) / total_registros, 2) END,
    0,
    GETDATE()
FROM reglas;

INSERT INTO co_sandbox_datos.kpi_cubo_mensual
SELECT
    p_periodo,
    'exactitud',
    'TOTAL',
    MAX(total_registros),
    SUM(cantidad_mala),
    ROUND(AVG(porcentaje), 2),
    1,
    GETDATE()
FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable = p_periodo
  AND tipo_indicador = 'exactitud';

-- ============================================================
-- 3) UNICIDAD
-- ============================================================
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = p_periodo
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
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
    SELECT COUNT(*) AS cantidad_mala
    FROM base
    WHERE policy_transaction_movement_sk IN (SELECT policy_transaction_movement_sk FROM duplicados)
),
total_base AS (
    SELECT COUNT(*) AS total_registros FROM base
)
SELECT
    p_periodo,
    'unicidad',
    'policy_transaction_movement_sk',
    t.total_registros,
    COALESCE(d.cantidad_mala, 0),
    ROUND(100.0 * (t.total_registros - COALESCE(d.cantidad_mala, 0)) / t.total_registros, 2),
    1,
    GETDATE()
FROM total_base t
LEFT JOIN conteo_duplicados d ON 1 = 1;

-- ============================================================
-- 4) VALIDEZ
-- ============================================================
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
WITH base AS (
    SELECT *
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE accountable_period = p_periodo
      AND current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND (
            (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
),
agregados AS (
    SELECT
        COUNT(*) AS total_registros,
        SUM(CASE WHEN source_system IS NULL OR source_system = 'Unknown' THEN 1 ELSE 0 END) AS n_source_system,
        SUM(CASE WHEN coverage_code IS NULL OR coverage_code = 'Unknown' THEN 1 ELSE 0 END) AS n_coverage_code,
        SUM(
            CASE
                WHEN product_code IS NULL
                OR product_code = 'Unknown'
                OR LENGTH(product_code) > 6
                OR product_code LIKE '% %'
                OR product_code ~ '[^A-Za-z0-9]'
                OR (source_system = 'CO_iaxis' AND product_code ~ '[A-Za-z]')
                THEN 1 ELSE 0
            END
        ) AS n_product_code,
        SUM(CASE WHEN transaction_date_sk IS NULL OR transaction_date_sk::VARCHAR !~ '^[0-9]{8}$' THEN 1 ELSE 0 END) AS n_transaction_date_sk,
        SUM(CASE WHEN transaction_type IS NULL OR transaction_type = 'Unknown' OR LENGTH(transaction_type) > 2 THEN 1 ELSE 0 END) AS n_transaction_type,
        SUM(CASE WHEN current_record_flag IS NULL OR current_record_flag NOT IN (0,1) THEN 1 ELSE 0 END) AS n_current_record_flag,
        SUM(CASE WHEN risk_number IS NULL OR risk_number = 'Unknown' THEN 1 ELSE 0 END) AS n_risk_number,
        SUM(CASE WHEN policy_number IS NULL OR policy_number = 'Unknown' THEN 1 ELSE 0 END) AS n_policy_number,
        SUM(CASE WHEN accountable_period IS NULL OR LENGTH(accountable_period::VARCHAR) <> 6 THEN 1 ELSE 0 END) AS n_accountable_period,
        SUM(CASE WHEN policy_effective_date_sk IS NULL OR LENGTH(policy_effective_date_sk::VARCHAR) <> 8 THEN 1 ELSE 0 END) AS n_policy_effective_date_sk,
        SUM(CASE WHEN inception_date_sk IS NULL OR LENGTH(inception_date_sk::VARCHAR) <> 8 THEN 1 ELSE 0 END) AS n_inception_date_sk,
        SUM(CASE WHEN transaction_effective_date_sk IS NULL OR LENGTH(transaction_effective_date_sk::VARCHAR) <> 8 THEN 1 ELSE 0 END) AS n_transaction_effective_date_sk
    FROM base
)
SELECT
    p_periodo,
    'validez',
    nombre_campo,
    total_registros,
    cantidad_invalidos,
    CASE
        WHEN total_registros = 0 THEN 0
        ELSE ROUND(100.0 * (1 - cantidad_invalidos::DECIMAL / total_registros), 2)
    END,
    0,
    GETDATE()
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

INSERT INTO co_sandbox_datos.kpi_cubo_mensual
SELECT
    p_periodo,
    'validez',
    'TOTAL_PERIODO',
    MAX(total_registros),
    SUM(cantidad_mala),
    ROUND(AVG(porcentaje), 2),
    1,
    GETDATE()
FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable = p_periodo
  AND tipo_indicador = 'validez';

-- ============================================================
-- 5) DISPONIBILIDAD
-- (sin el filtro compartido a propósito: necesita comparar fact vs. vista
--  completas para no esconder brechas de sincronización — ver CLAUDE.md)
-- ============================================================
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
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
    LEFT JOIN base_vista t2 ON t1.policy_transaction_movement_sk = t2.policy_transaction_movement_sk
    WHERE t2.policy_transaction_movement_sk IS NULL
),
totales AS (
    SELECT COUNT(*) AS total_registros FROM base_dwh
)
SELECT
    p_periodo,
    'disponibilidad',
    'disponibilidad_sync',
    t.total_registros,
    f.missing_count,
    CASE WHEN t.total_registros = 0 THEN 0 ELSE ROUND(((t.total_registros - f.missing_count) * 100.0 / t.total_registros), 2) END,
    1,
    GETDATE()
FROM totales t, faltantes f;

INSERT INTO co_sandbox_datos.kpi_cubo_mensual
WITH base AS (
    SELECT
        product_code,
        CAST(SUBSTRING(CAST(transaction_date_sk AS VARCHAR), 7, 2) AS INTEGER) AS dia
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE CAST(TO_CHAR(transaction_accounting_ts, 'YYYYMM') AS INTEGER) = p_periodo
),
dias_validos AS (
    SELECT 1 AS dia UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL
    SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL
    SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL
    SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
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
faltantes_regla4 AS (
    SELECT r.product_code
    FROM ramo_dias_esperados r
    LEFT JOIN ramo_dias_reales t ON r.product_code = t.product_code AND r.dia = t.dia
    WHERE t.product_code IS NULL
),
total_ramos AS (
    SELECT COUNT(DISTINCT product_code) AS total FROM base
),
ramos_ok AS (
    SELECT COUNT(*) AS ok_count
    FROM (
        SELECT DISTINCT product_code FROM base
        EXCEPT
        SELECT DISTINCT product_code FROM faltantes_regla4
    ) t
)
SELECT
    p_periodo,
    'disponibilidad',
    'disponibilidad_regla4',
    t.total,
    (t.total - r.ok_count),
    CASE WHEN t.total = 0 THEN 0 ELSE ROUND((r.ok_count * 100.0 / t.total), 2) END,
    1,
    GETDATE()
FROM total_ramos t, ramos_ok r;

END;
$$;

-- //////////////////////// SP AUTO (detección de periodos pendientes) //////////////////////// --
-- Independiente de los 5 procedimientos originales: solo compara la fuente
-- contra el propio cubo (kpi_cubo_mensual), no contra kpi_completitud_mensual.
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_cubo_auto()
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT accountable_period AS periodo
        FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
        WHERE current_record_flag = 1
          AND accountable_period NOT IN (
                SELECT DISTINCT periodo_contable
                FROM co_sandbox_datos.kpi_cubo_mensual
          )
        ORDER BY 1
    LOOP
        CALL co_sandbox_datos.sp_kpi_cubo_mensual(r.periodo);
    END LOOP;
END;
$$;

-- Nota de automatización end-to-end:
-- sp_kpi_cubo_auto() resuelve el "qué periodo calcular", pero todavía
-- necesita un disparador externo (Glue, EventBridge, un job programado, etc.)
-- que lo invoque periódicamente (`CALL co_sandbox_datos.sp_kpi_cubo_auto();`).
-- Ese disparador no existe hoy en el stack (ver README.md) y su
-- construcción/gestión está fuera del alcance de este repositorio de SQL.

-- //////////////////////// VISTA PARA POWER BI //////////////////////// --
create or replace view co_sandbox_datos.vw_kpi_cubo_mensual_pbi as
select
    periodo_contable,
    tipo_indicador,
    nombre_campo,
    total_registros,
    cantidad_mala,
    porcentaje,
    es_total,
    fecha_calculo
from co_sandbox_datos.kpi_cubo_mensual;

-- //////////////////////// EJECUCIÓN Y VALIDACIÓN //////////////////////// --
-- Backfill de un periodo puntual:
-- call co_sandbox_datos.sp_kpi_cubo_mensual(202602);

-- Procesar automáticamente todos los periodos pendientes:
-- call co_sandbox_datos.sp_kpi_cubo_auto();

--Validarlo
select *
from co_sandbox_datos.kpi_cubo_mensual
where periodo_contable = 202602
order by tipo_indicador, nombre_campo;

-- Periodos ya calculados vs. periodos disponibles en la fuente:
select distinct accountable_period as periodo_disponible
from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
where current_record_flag = 1
order by 1;

select distinct periodo_contable as periodo_calculado
from co_sandbox_datos.kpi_cubo_mensual
order by 1;
