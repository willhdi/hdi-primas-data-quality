-- disponibilidad_mes.sql  (nuevo, aditivo)
--
-- Disponibilidad — variante SOLO-VISTA basada en transaction_date_sk.
--
-- Objetivo: verificar que "sí llegó data del mes" usando UNICAMENTE la vista
-- gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement y su campo
-- transaction_date_sk (fecha del movimiento, YYYYMMDD). NO usa para nada la tabla
-- base gde_adp_dwh.fact_policy_transaction_movement (que requiere un permiso aparte).
-- Reemplaza al chequeo antiguo `disponibilidad_sync` (tabla base vs. vista).
--
-- Idea: por cada periodo contable, se mira cuántos días del mes tuvieron al menos un
-- movimiento (según transaction_date_sk). Si el mes anterior (último cerrado) tiene
-- todos sus días cubiertos, se confirma directamente que la data del mes está disponible.
--
-- Grano: un renglón por periodo_contable (accountable_period, YYYYMM).
--   total_registros = días exigidos del mes  (días del mes cerrado; días ya
--                     transcurridos —hasta ayer— si el mes está en curso).
--   cantidad_mala   = días exigidos SIN ningún movimiento (huecos de disponibilidad).
--   porcentaje      = 100 * (dias_exigidos - dias_faltantes) / dias_exigidos.
--   hay_datos_mes   = TRUE si el mes tuvo al menos un día con movimientos.
--
-- Sin periodos quemados: barre los ultimos ~13 meses contables presentes en la vista
-- y detecta el mes en curso con CURRENT_DATE (a ese solo le exige los dias transcurridos).

WITH parametros AS (
    SELECT
        CAST(TO_CHAR(CURRENT_DATE, 'YYYYMM') AS INTEGER)                         AS periodo_actual,
        CAST(TO_CHAR(CURRENT_DATE - INTERVAL '13 months', 'YYYYMM') AS INTEGER)  AS periodo_desde,
        GREATEST(0, EXTRACT(DAY FROM CURRENT_DATE)::INTEGER - 1)                 AS dias_transcurridos
),
base AS (
    -- Un renglon por movimiento, con el dia-del-mes tomado de transaction_date_sk.
    -- Solo cuentan los movimientos cuyo transaction_date_sk cae EN el mismo mes del
    -- periodo contable (asi el dia pertenece de verdad a ese mes).
    SELECT
        v.accountable_period            AS periodo_contable,
        MOD(v.transaction_date_sk, 100) AS dia
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement v
    CROSS JOIN parametros p
    WHERE v.transaction_date_sk IS NOT NULL
      AND v.accountable_period >= p.periodo_desde
      AND v.transaction_date_sk / 100 = v.accountable_period
),
esperados AS (
    -- Dias que se le exigen a cada mes (mes cerrado = dias del mes; mes en curso = transcurridos).
    SELECT
        b.periodo_contable,
        CASE
            WHEN b.periodo_contable = p.periodo_actual
                THEN LEAST(
                        p.dias_transcurridos,
                        EXTRACT(DAY FROM LAST_DAY(TO_DATE(CAST(b.periodo_contable AS VARCHAR), 'YYYYMM')))::INTEGER)
            ELSE EXTRACT(DAY FROM LAST_DAY(TO_DATE(CAST(b.periodo_contable AS VARCHAR), 'YYYYMM')))::INTEGER
        END AS dias_exigidos
    FROM (SELECT DISTINCT periodo_contable FROM base) b
    CROSS JOIN parametros p
),
presentes AS (
    SELECT
        b.periodo_contable,
        COUNT(DISTINCT CASE WHEN b.dia BETWEEN 1 AND e.dias_exigidos THEN b.dia END) AS dias_con_datos
    FROM base b
    JOIN esperados e ON e.periodo_contable = b.periodo_contable
    GROUP BY b.periodo_contable
)
SELECT
    e.periodo_contable,
    'disponibilidad'                                                             AS tipo_indicador,
    'disponibilidad_mes'                                                         AS nombre_campo,
    e.dias_exigidos                                                              AS total_registros,   -- dias exigidos del mes
    e.dias_exigidos - COALESCE(pr.dias_con_datos, 0)                             AS cantidad_mala,      -- dias sin movimientos
    ROUND(100.0 * COALESCE(pr.dias_con_datos, 0) / NULLIF(e.dias_exigidos, 0), 2) AS porcentaje,
    1                                                                            AS es_total,
    (COALESCE(pr.dias_con_datos, 0) > 0)                                         AS hay_datos_mes,
    GETDATE()                                                                    AS fecha_calculo
FROM esperados e
LEFT JOIN presentes pr ON pr.periodo_contable = e.periodo_contable
ORDER BY e.periodo_contable;
