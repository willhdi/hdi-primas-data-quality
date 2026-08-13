-- 03_vw_alertas_primas.sql  (nuevo, aditivo)
--
-- Vista única de ALERTAS del workstream Primas. Formato largo (long): un renglón
-- por alerta, con un `estado` semáforo homogéneo (Normal / Advertencia / Crítica),
-- para conectar directo a Power BI o a un futuro envío (Power Automate) sin más
-- transformación. NO recalcula la calidad: reutiliza vw_kpi_cubo_mensual (sql/vistas/01_vw_kpi_cubo_mensual.sql).
--
-- Reúne cuatro ámbitos (columna `ambito`) que NO son comparables entre sí:
--   1) 'saldo_ramo'    — saldo diario de prima por ramo (product_code) vs. el día
--                        con datos inmediatamente anterior. Umbrales MoM ±15% / ±30%.
--   2) 'dimension'     — % de cumplimiento por dimensión de calidad (fila es_total=1
--                        del cubo). Umbrales <95% Advertencia, <90% Crítica.
--                        Integridad se incluye como fila 'Pendiente' (aún sin lógica).
--   3) 'disponibilidad'— % de disponibilidad (regla 4, por ramo, días 1–15). Umbrales
--                        propios y laxos: valores bajos son NORMALES aquí (un solo día
--                        faltante condena un ramo), por eso NO usa la banda 90/95.
--   4) 'hora_carga'    — arribo diario de la carga vs. el corte de las 11:00 am
--                        (desde vw_disponibilidad_hora_carga, sql/vistas/02_vw_disponibilidad_hora_carga.sql). 'valor' = minutos
--                        respecto al corte (negativo = antes de las 11 = a tiempo).
--
-- Convenciones del repo: porcentajes 0–100; periodo_contable INTEGER YYYYMM;
-- todo en español; se lee SOLO de la vista general + del cubo (sin tablas base).
--
-- DEPENDENCIAS (crear en este orden): sql/vistas/01_vw_kpi_cubo_mensual.sql (vw_kpi_cubo_mensual) y sql/vistas/02_vw_disponibilidad_hora_carga.sql
-- (vw_disponibilidad_hora_carga) deben existir ANTES de correr este archivo.
--
-- Consumo típico:
--   SELECT * FROM co_sandbox_datos.vw_alertas_primas WHERE estado <> 'Normal';

CREATE OR REPLACE VIEW co_sandbox_datos.vw_alertas_primas AS

-- =====================================================================
-- 1) SALDO DIARIO POR RAMO  (ámbito 'saldo_ramo')
--    Mismo universo/filtro que sql/consultas/primas_monto_mensual.sql (serie de primas) para que reconcilie.
--    "ramo" = product_code (grano nativo del hecho). Ventana: últimos ~90 días.
-- =====================================================================
WITH saldo_diario AS (
    SELECT
        TRIM(product_code)                                       AS ramo,
        TO_DATE(transaction_date_sk::VARCHAR, 'YYYYMMDD')        AS fecha,
        CAST(TO_CHAR(TO_DATE(transaction_date_sk::VARCHAR, 'YYYYMMDD'), 'YYYYMM') AS INTEGER) AS periodo_contable,
        SUM(transaction_delta_billed_premium_amount)             AS prima_dia
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE current_record_flag = 1
      AND coverage_code <> 8888
      AND transaction_delta_billed_premium_amount <> 0
      AND transaction_date_sk IS NOT NULL
      AND transaction_date_sk::VARCHAR ~ '^[0-9]{8}$'
      AND transaction_date_sk >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '90 days', 'YYYYMMDD') AS INTEGER)
      AND (
            (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
            OR source_system = 'CO_as400'
          )
    GROUP BY 1, 2, 3
),
saldo_con_previo AS (
    SELECT
        ramo,
        fecha,
        periodo_contable,
        prima_dia,
        -- Día con datos inmediatamente anterior del MISMO ramo (evita huecos/fines de semana).
        LAG(prima_dia) OVER (PARTITION BY ramo ORDER BY fecha) AS prima_dia_previo,
        LAG(fecha)     OVER (PARTITION BY ramo ORDER BY fecha) AS fecha_previo
    FROM saldo_diario
),
alertas_saldo AS (
    SELECT
        'saldo_ramo'                                             AS ambito,
        ramo                                                     AS clave,
        ramo                                                     AS clave_natural,
        periodo_contable,
        fecha,
        ROUND(prima_dia, 2)                                      AS valor,
        ROUND(prima_dia_previo, 2)                               AS valor_referencia,
        ROUND(prima_dia - prima_dia_previo, 2)                   AS variacion_abs,
        CASE WHEN prima_dia_previo IS NULL OR prima_dia_previo = 0 THEN NULL
             ELSE ROUND(100.0 * (prima_dia - prima_dia_previo) / ABS(prima_dia_previo), 2)
        END                                                      AS variacion_pct,
        15.0                                                     AS umbral_adv,
        30.0                                                     AS umbral_crit,
        CASE
            WHEN prima_dia_previo IS NULL OR prima_dia_previo = 0 THEN 'Sin base'
            WHEN ABS(100.0 * (prima_dia - prima_dia_previo) / ABS(prima_dia_previo)) > 30 THEN 'Crítica'
            WHEN ABS(100.0 * (prima_dia - prima_dia_previo) / ABS(prima_dia_previo)) > 15 THEN 'Advertencia'
            ELSE 'Normal'
        END                                                      AS estado,
        'Saldo del día vs. día con datos anterior (' || COALESCE(TO_CHAR(fecha_previo, 'YYYY-MM-DD'), 's/d') || '). Umbrales ±15% / ±30%.' AS detalle
    FROM saldo_con_previo
),

-- =====================================================================
-- 2) DIMENSIONES DE CALIDAD  (ámbito 'dimension')
--    Fila total (es_total = 1) de cada dimensión comparable, desde el cubo.
--    Disponibilidad se saca aparte (ver bloque 3) porque su banda es distinta.
-- =====================================================================
dims_cubo AS (
    SELECT periodo_contable, periodo_fecha, tipo_indicador, porcentaje
    FROM co_sandbox_datos.vw_kpi_cubo_mensual
    WHERE es_total = 1
),
alertas_dimension AS (
    SELECT
        'dimension'                                              AS ambito,
        tipo_indicador                                           AS clave,
        INITCAP(tipo_indicador)                                  AS clave_natural,
        periodo_contable,
        periodo_fecha                                            AS fecha,
        porcentaje                                               AS valor,
        95.0                                                     AS valor_referencia,
        NULL::DECIMAL                                            AS variacion_abs,
        NULL::DECIMAL                                            AS variacion_pct,
        95.0                                                     AS umbral_adv,
        90.0                                                     AS umbral_crit,
        CASE
            WHEN porcentaje < 90 THEN 'Crítica'
            WHEN porcentaje < 95 THEN 'Advertencia'
            ELSE 'Normal'
        END                                                      AS estado,
        '% de cumplimiento de la dimensión. Umbrales <95% Advertencia, <90% Crítica.' AS detalle
    FROM dims_cubo
    WHERE tipo_indicador IN ('completitud', 'exactitud', 'unicidad', 'validez')
),

-- Integridad: aún sin lógica en ningún lado (indicador bloqueado). Se deja
-- una fila 'Pendiente' por periodo para que se vea el faltante en el tablero.
alertas_integridad AS (
    SELECT
        'dimension'                                              AS ambito,
        'integridad'                                             AS clave,
        'Integridad'                                             AS clave_natural,
        periodo_contable,
        periodo_fecha                                            AS fecha,
        NULL::DECIMAL                                            AS valor,
        NULL::DECIMAL                                            AS valor_referencia,
        NULL::DECIMAL                                            AS variacion_abs,
        NULL::DECIMAL                                            AS variacion_pct,
        95.0                                                     AS umbral_adv,
        90.0                                                     AS umbral_crit,
        'Pendiente'                                              AS estado,
        'Integridad aún no tiene lógica definida (a la espera de la Política / Paula Torres).' AS detalle
    FROM (SELECT DISTINCT periodo_contable, periodo_fecha FROM dims_cubo) p
),

-- =====================================================================
-- 3) DISPONIBILIDAD  (ámbito 'disponibilidad')
--    regla4 (por ramo, días 1–15). Banda propia y laxa: aquí un % bajo es normal.
-- =====================================================================
alertas_disponibilidad AS (
    SELECT
        'disponibilidad'                                         AS ambito,
        tipo_indicador                                           AS clave,
        'Disponibilidad por ramo (días 1–15)'                    AS clave_natural,
        periodo_contable,
        periodo_fecha                                            AS fecha,
        porcentaje                                               AS valor,
        NULL::DECIMAL                                            AS valor_referencia,
        NULL::DECIMAL                                            AS variacion_abs,
        NULL::DECIMAL                                            AS variacion_pct,
        50.0                                                     AS umbral_adv,
        25.0                                                     AS umbral_crit,
        CASE
            WHEN porcentaje < 25 THEN 'Crítica'
            WHEN porcentaje < 50 THEN 'Advertencia'
            ELSE 'Normal'
        END                                                      AS estado,
        'Disponibilidad regla 4 (% de ramos con todos los días 1–15). Banda laxa: valores bajos son esperables.' AS detalle
    FROM dims_cubo
    WHERE tipo_indicador = 'disponibilidad'
),

-- =====================================================================
-- 4) HORA DE CARGA vs. CORTE 11am  (ámbito 'hora_carga')
--    Arribo diario de la carga (desde vw_disponibilidad_hora_carga, sql/vistas/02_vw_disponibilidad_hora_carga.sql).
--    valor = minutos respecto al corte (negativo = antes de las 11 = a tiempo).
--    Banda: a tiempo Normal; hasta 2 h tarde Advertencia; más de 2 h Crítica.
-- =====================================================================
alertas_hora_carga AS (
    SELECT
        'hora_carga'                                            AS ambito,
        nombre_campo                                            AS clave,
        'Hora de carga (corte 11am)'                            AS clave_natural,
        periodo_contable,
        fecha_datos                                             AS fecha,
        minutos_vs_corte::DECIMAL                               AS valor,
        0.0                                                     AS valor_referencia,   -- 0 = justo a las 11:00
        NULL::DECIMAL                                           AS variacion_abs,
        NULL::DECIMAL                                           AS variacion_pct,
        0.0                                                     AS umbral_adv,          -- cualquier minuto tarde
        120.0                                                   AS umbral_crit,         -- más de 2 h tarde
        CASE
            WHEN minutos_vs_corte <= 0   THEN 'Normal'
            WHEN minutos_vs_corte <= 120 THEN 'Advertencia'
            ELSE 'Crítica'
        END                                                     AS estado,
        'Datos del día arribaron a las ' || TO_CHAR(arribo_datos, 'HH24:MI') || ' (corte 11:00). Negativo = a tiempo.' AS detalle
    FROM co_sandbox_datos.vw_disponibilidad_hora_carga
)

-- =====================================================================
-- UNIÓN FINAL — una sola vista consultable
-- =====================================================================
SELECT ambito, clave, clave_natural, periodo_contable, fecha, valor, valor_referencia,
       variacion_abs, variacion_pct, umbral_adv, umbral_crit, estado, detalle,
       GETDATE() AS fecha_calculo
FROM alertas_saldo
UNION ALL
SELECT ambito, clave, clave_natural, periodo_contable, fecha, valor, valor_referencia,
       variacion_abs, variacion_pct, umbral_adv, umbral_crit, estado, detalle,
       GETDATE() AS fecha_calculo
FROM alertas_dimension
UNION ALL
SELECT ambito, clave, clave_natural, periodo_contable, fecha, valor, valor_referencia,
       variacion_abs, variacion_pct, umbral_adv, umbral_crit, estado, detalle,
       GETDATE() AS fecha_calculo
FROM alertas_integridad
UNION ALL
SELECT ambito, clave, clave_natural, periodo_contable, fecha, valor, valor_referencia,
       variacion_abs, variacion_pct, umbral_adv, umbral_crit, estado, detalle,
       GETDATE() AS fecha_calculo
FROM alertas_disponibilidad
UNION ALL
SELECT ambito, clave, clave_natural, periodo_contable, fecha, valor, valor_referencia,
       variacion_abs, variacion_pct, umbral_adv, umbral_crit, estado, detalle,
       GETDATE() AS fecha_calculo
FROM alertas_hora_carga;

-- =====================================================================
-- Consultas de validación (no forman parte de la vista)
-- =====================================================================
-- Solo lo que está en alerta hoy:
--   SELECT * FROM co_sandbox_datos.vw_alertas_primas
--   WHERE estado IN ('Advertencia','Crítica') ORDER BY ambito, fecha DESC, estado;
--
-- Alertas de saldo del último día por ramo:
--   SELECT clave, fecha, valor, valor_referencia, variacion_pct, estado
--   FROM co_sandbox_datos.vw_alertas_primas
--   WHERE ambito = 'saldo_ramo'
--     AND fecha = (SELECT MAX(fecha) FROM co_sandbox_datos.vw_alertas_primas WHERE ambito='saldo_ramo')
--   ORDER BY estado, ABS(variacion_pct) DESC;
--
-- Semáforo de dimensiones del último periodo:
--   SELECT clave_natural, periodo_contable, valor, estado
--   FROM co_sandbox_datos.vw_alertas_primas
--   WHERE ambito IN ('dimension','disponibilidad')
--     AND periodo_contable = (SELECT MAX(periodo_contable) FROM co_sandbox_datos.vw_alertas_primas WHERE ambito='dimension')
--   ORDER BY ambito, clave;
