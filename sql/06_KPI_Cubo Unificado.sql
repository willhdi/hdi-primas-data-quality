-- =====================================================================
-- KPI Cubo Unificado: los 5 indicadores en formato largo
-- (periodo_contable + tipo_indicador + nombre_campo), persistido en
-- co_sandbox_datos.kpi_cubo_mensual.
--
-- Patrón idempotente: se borra la ventana de 3 años que la consulta
-- recalcula y se vuelve a insertar. Los periodos más antiguos que la
-- ventana se conservan como histórico.
-- =====================================================================

-- 1) Tabla persistida del cubo
CREATE TABLE IF NOT EXISTS co_sandbox_datos.kpi_cubo_mensual (
    periodo_contable INTEGER,
    tipo_indicador   VARCHAR(30),
    nombre_campo     VARCHAR(100),
    total_registros  BIGINT,
    cantidad_mala    BIGINT,
    porcentaje       DECIMAL(5,2),
    es_total         SMALLINT,
    fecha_calculo    TIMESTAMP
);

-- 2) Refresco idempotente: borrar la misma ventana de 3 años que se recalcula
DELETE FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '3 years', 'YYYYMM') AS INTEGER);

-- 3) Recalcular e insertar el cubo completo
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
    (periodo_contable, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, fecha_calculo)
WITH base AS (
    SELECT
        source_system,
        accountable_period,
        coverage_code,
        branch_sk,
        product_code,
        transaction_date_sk,
        policy_effective_date_sk,
        policy_expiration_date_sk,
        inception_date_sk,
        transaction_type,
        transaction_effective_date_sk,
        transaction_type_description,
        current_record_flag,
        transaction_delta_billed_premium_amount,
        transaction_delta_commission_amount,
        risk_number,
        policy_number,
        transaction_delta_billed_premium_amount_raw,
        policy_transaction_movement_sk,
        sseguro,
        receipt_type,
        receipt_number
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND accountable_period >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '3 years', 'YYYYMM') AS INTEGER)
      AND (
            (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
),
completitud_agg AS (
    SELECT
        accountable_period,
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
                WHEN (receipt_number IS NULL AND source_system <> 'CO_as400' AND receipt_type <> 'not-unificado')
                  OR (receipt_type = 'not-unificado' AND receipt_number IS NOT NULL)
                THEN 1 ELSE 0
            END
        ) AS n_receipt_number
    FROM base
    GROUP BY accountable_period
),
completitud_detalle AS (
    SELECT
        accountable_period,
        'completitud' AS tipo_indicador,
        nombre_campo,
        total_registros,
        cantidad_mala,
        CASE WHEN total_registros = 0 THEN 0 ELSE ROUND(100.0 * (1 - cantidad_mala::DECIMAL / total_registros), 2) END AS porcentaje,
        0 AS es_total
    FROM (
        SELECT accountable_period, total_registros, 'source_system' AS nombre_campo, n_source_system AS cantidad_mala FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'accountable_period', n_accountable_period FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'coverage_code', n_coverage_code FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'branch_sk', n_branch_sk FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'product_code', n_product_code FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_date_sk', n_transaction_date_sk FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'policy_effective_date_sk', n_policy_effective_date_sk FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'policy_expiration_date_sk', n_policy_expiration_date_sk FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'inception_date_sk', n_inception_date_sk FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_type', n_transaction_type FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_effective_date_sk', n_transaction_effective_date_sk FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_type_description', n_transaction_type_description FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'current_record_flag', n_current_record_flag FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_delta_billed_premium_amount', n_transaction_delta_billed_premium_amount FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_delta_commission_amount', n_transaction_delta_commission_amount FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'risk_number', n_risk_number FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'policy_number', n_policy_number FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_delta_billed_premium_amount_raw', n_transaction_delta_billed_premium_amount_raw FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'sseguro', n_sseguro FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'receipt_type', n_receipt_type FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'receipt_number', n_receipt_number FROM completitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'policy_transaction_movement_sk', n_policy_transaction_movement_sk FROM completitud_agg
    ) t
),
completitud_total AS (
    SELECT
        accountable_period,
        'completitud' AS tipo_indicador,
        'TOTAL_PERIODO' AS nombre_campo,
        MAX(total_registros) AS total_registros,
        SUM(cantidad_mala) AS cantidad_mala,
        ROUND(AVG(porcentaje), 2) AS porcentaje,
        1 AS es_total
    FROM completitud_detalle
    GROUP BY accountable_period
),
exactitud_agg AS (
    SELECT
        accountable_period,
        COUNT(*) AS total_registros,
        SUM(CASE WHEN source_system IS NULL OR source_system NOT IN ('CO_iaxis','CO_as400') THEN 1 ELSE 0 END) AS n_source_system,
        SUM(CASE WHEN current_record_flag IS NULL OR current_record_flag NOT IN (0,1) THEN 1 ELSE 0 END) AS n_current_record_flag,
        SUM(CASE WHEN receipt_type IS NULL OR receipt_type NOT IN ('not-unificado','unificado-detail','unificado-total') THEN 1 ELSE 0 END) AS n_receipt_type
    FROM base
    GROUP BY accountable_period
),
exactitud_detalle AS (
    SELECT
        accountable_period,
        'exactitud' AS tipo_indicador,
        nombre_campo,
        total_registros,
        cantidad_mala,
        CASE WHEN total_registros = 0 THEN 0 ELSE ROUND(100.0 * (total_registros - cantidad_mala) / total_registros, 2) END AS porcentaje,
        0 AS es_total
    FROM (
        SELECT accountable_period, total_registros, 'source_system' AS nombre_campo, n_source_system AS cantidad_mala FROM exactitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'current_record_flag', n_current_record_flag FROM exactitud_agg
        UNION ALL SELECT accountable_period, total_registros, 'receipt_type', n_receipt_type FROM exactitud_agg
    ) t
),
exactitud_total AS (
    SELECT
        accountable_period,
        'exactitud' AS tipo_indicador,
        'TOTAL' AS nombre_campo,
        MAX(total_registros) AS total_registros,
        SUM(cantidad_mala) AS cantidad_mala,
        ROUND(AVG(porcentaje), 2) AS porcentaje,
        1 AS es_total
    FROM exactitud_detalle
    GROUP BY accountable_period
),
unicidad_llaves AS (
    SELECT accountable_period, policy_transaction_movement_sk, COUNT(*) AS cnt
    FROM base
    GROUP BY accountable_period, policy_transaction_movement_sk
),
unicidad_total AS (
    SELECT
        accountable_period,
        'unicidad' AS tipo_indicador,
        'policy_transaction_movement_sk' AS nombre_campo,
        SUM(cnt) AS total_registros,
        SUM(CASE WHEN cnt > 1 THEN cnt ELSE 0 END) AS cantidad_mala,
        ROUND(100.0 * (SUM(cnt) - SUM(CASE WHEN cnt > 1 THEN cnt ELSE 0 END)) / SUM(cnt), 2) AS porcentaje,
        1 AS es_total
    FROM unicidad_llaves
    GROUP BY accountable_period
),
validez_agg AS (
    SELECT
        accountable_period,
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
    GROUP BY accountable_period
),
validez_detalle AS (
    SELECT
        accountable_period,
        'validez' AS tipo_indicador,
        nombre_campo,
        total_registros,
        cantidad_mala,
        CASE WHEN total_registros = 0 THEN 0 ELSE ROUND(100.0 * (1 - cantidad_mala::DECIMAL / total_registros), 2) END AS porcentaje,
        0 AS es_total
    FROM (
        SELECT accountable_period, total_registros, 'source_system' AS nombre_campo, n_source_system AS cantidad_mala FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'coverage_code', n_coverage_code FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'product_code', n_product_code FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_date_sk', n_transaction_date_sk FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_type', n_transaction_type FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'current_record_flag', n_current_record_flag FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'risk_number', n_risk_number FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'policy_number', n_policy_number FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'accountable_period', n_accountable_period FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'policy_effective_date_sk', n_policy_effective_date_sk FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'inception_date_sk', n_inception_date_sk FROM validez_agg
        UNION ALL SELECT accountable_period, total_registros, 'transaction_effective_date_sk', n_transaction_effective_date_sk FROM validez_agg
    ) t
),
validez_total AS (
    SELECT
        accountable_period,
        'validez' AS tipo_indicador,
        'TOTAL_PERIODO' AS nombre_campo,
        MAX(total_registros) AS total_registros,
        SUM(cantidad_mala) AS cantidad_mala,
        ROUND(AVG(porcentaje), 2) AS porcentaje,
        1 AS es_total
    FROM validez_detalle
    GROUP BY accountable_period
),
regla4_dias AS (
    SELECT
        CAST(TO_CHAR(transaction_accounting_ts, 'YYYYMM') AS INTEGER) AS periodo,
        product_code,
        COUNT(DISTINCT CASE WHEN CAST(SUBSTRING(CAST(transaction_date_sk AS VARCHAR), 7, 2) AS INTEGER) BETWEEN 1 AND 15
              THEN CAST(SUBSTRING(CAST(transaction_date_sk AS VARCHAR), 7, 2) AS INTEGER) END) AS dias_presentes
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE transaction_accounting_ts >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY 1, product_code
),
regla4_ramos AS (
    SELECT
        periodo,
        COUNT(*) AS total_ramos,
        SUM(
            CASE
                WHEN dias_presentes >= (
                    CASE
                        WHEN periodo = CAST(TO_CHAR(GETDATE(), 'YYYYMM') AS INTEGER)
                        THEN LEAST(15, GREATEST(CAST(DATE_PART('day', GETDATE()) AS INTEGER) - 1, 0))
                        ELSE 15
                    END
                )
                THEN 1 ELSE 0
            END
        ) AS ramos_ok
    FROM regla4_dias
    GROUP BY periodo
),
disponibilidad_total AS (
    SELECT
        periodo AS accountable_period,
        'disponibilidad' AS tipo_indicador,
        'disponibilidad_regla4' AS nombre_campo,
        total_ramos AS total_registros,
        (total_ramos - ramos_ok) AS cantidad_mala,
        CASE WHEN total_ramos = 0 THEN 0 ELSE ROUND(ramos_ok * 100.0 / total_ramos, 2) END AS porcentaje,
        1 AS es_total
    FROM regla4_ramos
)
SELECT accountable_period AS periodo_contable, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() AS fecha_calculo FROM completitud_detalle
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM completitud_total
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM exactitud_detalle
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM exactitud_total
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM unicidad_total
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM validez_detalle
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM validez_total
UNION ALL
SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total, GETDATE() FROM disponibilidad_total;

-- 4) Verificación: inspeccionar el cubo persistido
SELECT *
FROM co_sandbox_datos.kpi_cubo_mensual
ORDER BY periodo_contable, tipo_indicador, nombre_campo;