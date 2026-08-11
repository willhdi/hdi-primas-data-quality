CREATE OR REPLACE VIEW co_sandbox_datos.vw_kpi_cubo_mensual AS
WITH base_pt AS (
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
agg_pt AS (
    SELECT
        accountable_period,
        COUNT(*) AS total_registros,

        SUM(CASE WHEN source_system IS NULL THEN 1 ELSE 0 END) AS c_source_system,
        SUM(CASE WHEN accountable_period IS NULL THEN 1 ELSE 0 END) AS c_accountable_period,
        SUM(CASE WHEN coverage_code IS NULL THEN 1 ELSE 0 END) AS c_coverage_code,
        SUM(CASE WHEN branch_sk IS NULL THEN 1 ELSE 0 END) AS c_branch_sk,
        SUM(CASE WHEN product_code IS NULL THEN 1 ELSE 0 END) AS c_product_code,
        SUM(CASE WHEN transaction_date_sk IS NULL THEN 1 ELSE 0 END) AS c_transaction_date_sk,
        SUM(CASE WHEN policy_effective_date_sk IS NULL THEN 1 ELSE 0 END) AS c_policy_effective_date_sk,
        SUM(CASE WHEN policy_expiration_date_sk IS NULL THEN 1 ELSE 0 END) AS c_policy_expiration_date_sk,
        SUM(CASE WHEN inception_date_sk IS NULL THEN 1 ELSE 0 END) AS c_inception_date_sk,
        SUM(CASE WHEN transaction_type IS NULL THEN 1 ELSE 0 END) AS c_transaction_type,
        SUM(CASE WHEN transaction_effective_date_sk IS NULL THEN 1 ELSE 0 END) AS c_transaction_effective_date_sk,
        SUM(CASE WHEN transaction_type_description IS NULL THEN 1 ELSE 0 END) AS c_transaction_type_description,
        SUM(CASE WHEN current_record_flag IS NULL THEN 1 ELSE 0 END) AS c_current_record_flag,
        SUM(CASE WHEN transaction_delta_billed_premium_amount IS NULL THEN 1 ELSE 0 END) AS c_transaction_delta_billed_premium_amount,
        SUM(CASE WHEN transaction_delta_commission_amount IS NULL THEN 1 ELSE 0 END) AS c_transaction_delta_commission_amount,
        SUM(CASE WHEN risk_number IS NULL THEN 1 ELSE 0 END) AS c_risk_number,
        SUM(CASE WHEN policy_number IS NULL THEN 1 ELSE 0 END) AS c_policy_number,
        SUM(CASE WHEN transaction_delta_billed_premium_amount_raw IS NULL THEN 1 ELSE 0 END) AS c_transaction_delta_billed_premium_amount_raw,
        SUM(CASE WHEN sseguro IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS c_sseguro,
        SUM(CASE WHEN receipt_type IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS c_receipt_type,
        SUM(
            CASE
                WHEN (receipt_number IS NULL AND source_system <> 'CO_as400' AND receipt_type <> 'not-unificado')
                  OR (receipt_type = 'not-unificado' AND receipt_number IS NOT NULL)
                THEN 1 ELSE 0
            END
        ) AS c_receipt_number,
        SUM(CASE WHEN policy_transaction_movement_sk IS NULL THEN 1 ELSE 0 END) AS c_policy_transaction_movement_sk,

        SUM(CASE WHEN source_system IS NULL OR source_system NOT IN ('CO_iaxis','CO_as400') THEN 1 ELSE 0 END) AS e_source_system,
        SUM(CASE WHEN current_record_flag IS NULL OR current_record_flag NOT IN (0,1) THEN 1 ELSE 0 END) AS e_current_record_flag,
        SUM(CASE WHEN receipt_type IS NULL OR receipt_type NOT IN ('not-unificado','unificado-detail','unificado-total') THEN 1 ELSE 0 END) AS e_receipt_type,

        SUM(CASE WHEN source_system IS NULL OR source_system = 'Unknown' THEN 1 ELSE 0 END) AS v_source_system,
        SUM(CASE WHEN coverage_code IS NULL OR coverage_code = 'Unknown' THEN 1 ELSE 0 END) AS v_coverage_code,
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
        ) AS v_product_code,
        SUM(CASE WHEN transaction_date_sk IS NULL OR transaction_date_sk::VARCHAR !~ '^[0-9]{8}$' THEN 1 ELSE 0 END) AS v_transaction_date_sk,
        SUM(CASE WHEN transaction_type IS NULL OR transaction_type = 'Unknown' OR LENGTH(transaction_type) > 2 THEN 1 ELSE 0 END) AS v_transaction_type,
        SUM(CASE WHEN risk_number IS NULL OR risk_number = 'Unknown' THEN 1 ELSE 0 END) AS v_risk_number,
        SUM(CASE WHEN policy_number IS NULL OR policy_number = 'Unknown' THEN 1 ELSE 0 END) AS v_policy_number,
        SUM(CASE WHEN LENGTH(accountable_period::VARCHAR) <> 6 THEN 1 ELSE 0 END) AS v_accountable_period,
        SUM(CASE WHEN policy_effective_date_sk IS NULL OR LENGTH(policy_effective_date_sk::VARCHAR) <> 8 THEN 1 ELSE 0 END) AS v_policy_effective_date_sk,
        SUM(CASE WHEN inception_date_sk IS NULL OR LENGTH(inception_date_sk::VARCHAR) <> 8 THEN 1 ELSE 0 END) AS v_inception_date_sk,
        SUM(CASE WHEN transaction_effective_date_sk IS NULL OR LENGTH(transaction_effective_date_sk::VARCHAR) <> 8 THEN 1 ELSE 0 END) AS v_transaction_effective_date_sk

    FROM base_pt
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
        SELECT accountable_period, total_registros, 'source_system' AS nombre_campo, c_source_system AS cantidad_mala FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'accountable_period', c_accountable_period FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'coverage_code', c_coverage_code FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'branch_sk', c_branch_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'product_code', c_product_code FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_date_sk', c_transaction_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'policy_effective_date_sk', c_policy_effective_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'policy_expiration_date_sk', c_policy_expiration_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'inception_date_sk', c_inception_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_type', c_transaction_type FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_effective_date_sk', c_transaction_effective_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_type_description', c_transaction_type_description FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'current_record_flag', c_current_record_flag FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_delta_billed_premium_amount', c_transaction_delta_billed_premium_amount FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_delta_commission_amount', c_transaction_delta_commission_amount FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'risk_number', c_risk_number FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'policy_number', c_policy_number FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_delta_billed_premium_amount_raw', c_transaction_delta_billed_premium_amount_raw FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'sseguro', c_sseguro FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'receipt_type', c_receipt_type FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'receipt_number', c_receipt_number FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'policy_transaction_movement_sk', c_policy_transaction_movement_sk FROM agg_pt
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
        SELECT accountable_period, total_registros, 'source_system' AS nombre_campo, e_source_system AS cantidad_mala FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'current_record_flag', e_current_record_flag FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'receipt_type', e_receipt_type FROM agg_pt
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
    FROM base_pt
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
        SELECT accountable_period, total_registros, 'source_system' AS nombre_campo, v_source_system AS cantidad_mala FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'coverage_code', v_coverage_code FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'product_code', v_product_code FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_date_sk', v_transaction_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_type', v_transaction_type FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'current_record_flag', e_current_record_flag FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'risk_number', v_risk_number FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'policy_number', v_policy_number FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'accountable_period', v_accountable_period FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'policy_effective_date_sk', v_policy_effective_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'inception_date_sk', v_inception_date_sk FROM agg_pt
        UNION ALL SELECT accountable_period, total_registros, 'transaction_effective_date_sk', v_transaction_effective_date_sk FROM agg_pt
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
),
cubo_union AS (
    SELECT accountable_period AS periodo_contable, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM completitud_detalle
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM completitud_total
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM exactitud_detalle
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM exactitud_total
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM unicidad_total
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM validez_detalle
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM validez_total
    UNION ALL
    SELECT accountable_period, tipo_indicador, nombre_campo, total_registros, cantidad_mala, porcentaje, es_total FROM disponibilidad_total
)
SELECT
    periodo_contable,
    TO_DATE(periodo_contable::VARCHAR, 'YYYYMM') AS periodo_fecha,
    tipo_indicador,
    nombre_campo,
    CASE nombre_campo
        WHEN 'source_system' THEN 'Sistema fuente'
        WHEN 'accountable_period' THEN 'Periodo contable'
        WHEN 'coverage_code' THEN 'Código de cobertura'
        WHEN 'branch_sk' THEN 'Sucursal / comercial'
        WHEN 'product_code' THEN 'Código de producto (ramo)'
        WHEN 'transaction_date_sk' THEN 'Fecha del movimiento'
        WHEN 'policy_effective_date_sk' THEN 'Fecha de efectividad de póliza'
        WHEN 'policy_expiration_date_sk' THEN 'Fecha de vencimiento de póliza'
        WHEN 'inception_date_sk' THEN 'Fecha de inicio del contrato'
        WHEN 'transaction_type' THEN 'Tipo de transacción'
        WHEN 'transaction_effective_date_sk' THEN 'Fecha efectiva del movimiento'
        WHEN 'transaction_type_description' THEN 'Descripción del tipo de transacción'
        WHEN 'current_record_flag' THEN 'Marca de vigencia del registro'
        WHEN 'transaction_delta_billed_premium_amount' THEN 'Prima facturada (monto neto)'
        WHEN 'transaction_delta_billed_premium_amount_raw' THEN 'Prima facturada (valor bruto)'
        WHEN 'transaction_delta_commission_amount' THEN 'Comisión del movimiento'
        WHEN 'risk_number' THEN 'Número de riesgo'
        WHEN 'policy_number' THEN 'Número de póliza'
        WHEN 'policy_transaction_movement_sk' THEN 'Identificador del movimiento'
        WHEN 'sseguro' THEN 'Identificador de seguro (derivado del riesgo)'
        WHEN 'receipt_type' THEN 'Tipo de recibo'
        WHEN 'receipt_number' THEN 'Número de recibo'
        WHEN 'TOTAL_PERIODO' THEN 'Total del periodo'
        WHEN 'TOTAL' THEN 'Total del periodo'
        WHEN 'disponibilidad_mes' THEN 'Disponibilidad del mes (días con datos)'
        WHEN 'disponibilidad_regla4' THEN 'Disponibilidad por ramo (días 1–15)'
        ELSE nombre_campo
    END AS nombre_natural,
    total_registros,
    cantidad_mala,
    porcentaje,
    es_total,
    GETDATE() AS fecha_calculo
FROM cubo_union;