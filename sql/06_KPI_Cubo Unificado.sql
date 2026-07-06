-- ///////////////////////////////////////////////////////////////////////////// --
-- CUBO UNIFICADO DE CALIDAD DE DATOS (PRIMAS)                                    --
-- ///////////////////////////////////////////////////////////////////////////// --
--
-- ¿QUÉ ES? (negocio)
--   Una sola tabla mensual con los 5 indicadores de calidad de datos del hecho
--   de primas (vw_fact_policy_transaction_movement), lista para Power BI:
--     · Completitud   -> ¿los campos obligatorios vienen diligenciados (no nulos)?
--     · Exactitud     -> ¿los valores caen dentro del dominio permitido?
--     · Unicidad      -> ¿hay registros duplicados (misma llave)?
--     · Validez       -> ¿el formato/forma del dato es correcto (longitudes, fechas)?
--     · Disponibilidad-> ¿la información está llegando y sincronizada a tiempo?
--
-- ¿QUÉ ES? (técnico)
--   No llama a sp_kpi_completitud_mensual, sp_kpi_exactitud_mensual,
--   sp_kpi_unicidad_mensual, sp_kpi_validez_mensual ni sp_kpi_disponibilidad_mensual:
--   toda la lógica de cada indicador está reescrita aquí mismo, así que este
--   archivo funciona solo (no depende de que los otros 5 se hayan ejecutado
--   antes ni de que sigan existiendo).
--
--   Los 5 archivos originales NO se tocan ni se borran — se dejan como
--   respaldo/referencia hasta que se confirme que este cubo los reemplaza
--   en Power BI (regla del repositorio, ver CLAUDE.md).
--
-- PARIDAD CON EL NOTEBOOK (notebooks/cubo_unificado_runner.ipynb)
--   Este archivo y el notebook implementan LAS MISMAS reglas de negocio y deben
--   producir el mismo cubo (mismo grano, mismos campos, mismos porcentajes):
--     · Mismos 22 campos de Completitud (19 obligatorios + 3 con excepción por fuente).
--     · Mismas 3 reglas implementadas de Exactitud.
--     · Misma llave de Unicidad (policy_transaction_movement_sk).
--     · Mismas 12 reglas de Validez (movement_type excluido a propósito, igual
--       que en el sql/05 original, donde está comentado).
--     · Mismos 2 chequeos de Disponibilidad (sync y regla4).
--     · Mismas filas de total: MAX(total_registros), SUM(cantidad_mala),
--       AVG(porcentaje) redondeado a 2 decimales.
--     · Igual manejo del MES EN CURSO: se calcula con datos parciales y se
--       recalcula en cada corrida de sp_kpi_cubo_auto() para ver su evolución;
--       disponibilidad_regla4 solo le exige los días ya transcurridos.
--   Si cambias una regla aquí, cámbiala también en el notebook (y viceversa).
--
-- CAMBIO DE COMPORTAMIENTO A PROPÓSITO vs. el archivo original de Exactitud:
--   aquí Exactitud SÍ aplica el filtro compartido completo (incluye
--   current_record_flag = 1), igual que Completitud/Unicidad/Validez. El
--   archivo original de Exactitud no lo tenía (hallazgo #1 en
--   "docs/Hallazgos y Estado del Proyecto.md") — se corrige aquí porque es
--   código nuevo, no una modificación del original. Las reglas de Exactitud
--   que comparan contra la tabla ODS (transaction_delta_*) siguen sin
--   implementar (hallazgo #2): requieren acceso/definición de la fuente ODS.
--
-- FILTRO BASE COMPARTIDO (negocio)
--   Completitud, Exactitud, Unicidad y Validez miden calidad SOLO sobre el
--   "universo de negocio válido" del periodo:
--     · current_record_flag = 1                     -> solo la foto vigente del registro
--                                                      (la vista guarda historia de versiones).
--     · coverage_code <> 8888                       -> excluye la cobertura técnica/ficticia 8888.
--     · transaction_delta_billed_premium_amount<>0  -> excluye movimientos sin efecto en prima
--                                                      (no aportan al negocio ni a los KPIs).
--     · receipt_type <> 'unificado-total' en iaxis  -> el recibo "unificado-total" es un
--                                                      consolidado que DUPLICARÍA lo que ya
--                                                      está en sus recibos de detalle.
--   Disponibilidad NO usa este filtro a propósito: compara tabla base vs. vista
--   COMPLETAS; cualquier filtro escondería brechas de sincronización.
--
-- ///////////////////////////////////////////////////////////////////////////// --


-- //////////////////////// TABLA CUBO //////////////////////// --
-- Formato largo: UNA fila por (periodo_contable, tipo_indicador, nombre_campo).
-- Ese grano permite a Power BI filtrar/cruzar por campo Y por periodo con una
-- sola tabla, sin uniones entre 5 tablas distintas.
--
-- Lectura de columnas:
--   total_registros -> tamaño del universo evaluado (filas del filtro base;
--                      en disponibilidad_regla4 son RAMOS, no filas).
--   cantidad_mala   -> nulos / inexactos / duplicados / inválidos / faltantes,
--                      según tipo_indicador.
--   porcentaje      -> % de calidad = 100 * (total - malas) / total. Más alto = mejor.
--   es_total        -> 1 = fila agregada del indicador (TOTAL_PERIODO / TOTAL /
--                      las de disponibilidad); 0 = fila de detalle por campo.
--                      En Power BI: usar es_total=1 para los medidores del resumen
--                      y es_total=0 para el detalle por variable.
--   fecha_calculo   -> cuándo se calculó la fila. Para el MES EN CURSO indica
--                      "corte" de los datos parciales (se recalcula cada corrida).
create table if not exists co_sandbox_datos.kpi_cubo_mensual (
    periodo_contable INTEGER,         -- YYYYMM entero (ej. 202607), NO es fecha
    tipo_indicador VARCHAR(20),       -- completitud | exactitud | unicidad | validez | disponibilidad
    nombre_campo VARCHAR(100),        -- campo evaluado, o TOTAL_PERIODO/TOTAL/disponibilidad_*
    total_registros BIGINT,
    cantidad_mala BIGINT,
    porcentaje DECIMAL(6,2),
    es_total INTEGER,
    fecha_calculo TIMESTAMP default GETDATE()
);

-- //////////////////////// SP CUBO (un periodo) //////////////////////// --
-- Calcula los 5 indicadores para UN periodo. Idempotente: DELETE + INSERT,
-- por lo que se puede re-ejecutar sin duplicar filas (uso típico: re-correr
-- un periodo tras una corrección en la fuente, o refrescar el mes en curso).
CREATE OR REPLACE PROCEDURE co_sandbox_datos.sp_kpi_cubo_mensual(p_periodo INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Soporte para el MES EN CURSO (datos parciales):
    --   v_periodo_actual: el YYYYMM de hoy, para detectar si p_periodo está abierto.
    --   v_dias_exigidos : días 1-15 que la regla 4 de Disponibilidad puede exigir.
    --     · Mes cerrado  -> exige los 15 días completos.
    --     · Mes en curso -> exige solo los días ya transcurridos (hasta AYER,
    --       máximo 15). Sin esto, la regla castigaría días que aún no ocurren:
    --       p. ej. el día 6 del mes ningún ramo podría tener datos del día 7 al 15
    --       y el indicador daría 0% de forma artificial. Se usa "ayer" y no "hoy"
    --       porque el día corriente puede no haber cargado todavía.
    v_periodo_actual INTEGER;
    v_dias_exigidos  INTEGER;
BEGIN

v_periodo_actual := CAST(TO_CHAR(GETDATE(), 'YYYYMM') AS INTEGER);

IF p_periodo = v_periodo_actual THEN
    v_dias_exigidos := LEAST(15, GREATEST(CAST(DATE_PART('day', GETDATE()) AS INTEGER) - 1, 0));
ELSE
    v_dias_exigidos := 15;
END IF;

-- Idempotencia: borra el periodo completo (los 5 indicadores) antes de recalcular.
DELETE FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable = p_periodo;

-- ============================================================
-- 1) COMPLETITUD
-- ------------------------------------------------------------
-- Negocio: ¿qué tan diligenciados vienen los campos obligatorios?
--   Un nulo aquí significa que la fuente NO entregó el dato, lo que rompe
--   reportes y cruces aguas abajo (p. ej. sin product_code no se puede
--   asignar el ramo).
-- Técnico: 19 campos con regla simple "IS NULL" + 3 campos con excepción
--   por sistema fuente:
--     · sseguro y receipt_type: CO_as400 NO los puebla por diseño, así que a
--       esa fuente no se le cuenta el nulo como falta.
--     · receipt_number: doble condición — debe existir cuando el recibo lo
--       requiere (fuera de as400 y fuera de 'not-unificado'), y NO debe
--       existir cuando receipt_type = 'not-unificado' (allí un valor es
--       tan anómalo como un faltante).
--   Un solo escaneo de la vista calcula los 22 conteos (SUM(CASE...)),
--   y luego se "despivotea" a formato largo con UNION ALL.
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
        -- Excepciones por fuente: CO_as400 no puebla sseguro ni receipt_type por diseño.
        SUM(CASE WHEN sseguro IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS n_sseguro,
        SUM(CASE WHEN receipt_type IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS n_receipt_type,
        -- receipt_number: falta cuando debería existir, o existe cuando NO debería.
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
    0,                                -- es_total = 0: fila de detalle por campo
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

-- Fila TOTAL_PERIODO de Completitud: resumen del indicador para los medidores
-- del tablero. Promedio SIMPLE de los porcentajes por campo (cada campo pesa
-- igual, sin ponderar por registros) + suma de todos los nulos del periodo.
-- Misma agregación que usa el notebook (max/sum/avg).
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
SELECT
    p_periodo,
    'completitud',
    'TOTAL_PERIODO',
    MAX(total_registros),
    SUM(cantidad_mala),
    ROUND(AVG(porcentaje), 2),
    1,                                -- es_total = 1: fila agregada
    GETDATE()
FROM co_sandbox_datos.kpi_cubo_mensual
WHERE periodo_contable = p_periodo
  AND tipo_indicador = 'completitud';

-- ============================================================
-- 2) EXACTITUD
-- ------------------------------------------------------------
-- Negocio: el dato puede venir diligenciado (completitud OK) pero con un
--   valor FUERA del dominio permitido — p. ej. un sistema fuente distinto
--   de los 2 oficiales, o un tipo de recibo desconocido. Eso es inexactitud.
-- Técnico: 3 reglas de dominio implementadas (las del catálogo de reglas que
--   solo requieren la vista):
--     · source_system      IN ('CO_iaxis','CO_as400')
--     · current_record_flag IN (0,1)
--     · receipt_type       IN ('not-unificado','unificado-detail','unificado-total')
--   Usa el filtro compartido COMPLETO, incluyendo current_record_flag = 1
--   (corrección deliberada vs. el sql/03 original — hallazgo #1). Las reglas
--   contra la tabla ODS (transaction_delta_*) siguen pendientes (hallazgo #2).
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

-- Fila TOTAL de Exactitud (nombre 'TOTAL' por consistencia con el sql/03
-- original, que usaba 'TOTAL' y no 'TOTAL_PERIODO').
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
-- ------------------------------------------------------------
-- Negocio: cada movimiento de prima debe existir UNA sola vez. Un duplicado
--   infla primas y comisiones en los reportes financieros.
-- Técnico: la llave evaluada es policy_transaction_movement_sk (llave
--   subrogada del movimiento). cantidad_mala cuenta TODAS las filas que
--   participan en un duplicado (si una llave aparece 3 veces, suma 3, no 2),
--   igual que el notebook. Es el único indicador con una sola fila por
--   periodo (es_total = 1 directamente, no hay detalle por campo).
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
-- ------------------------------------------------------------
-- Negocio: el dato puede estar diligenciado y "existir", pero con una FORMA
--   incorrecta: una fecha que no es YYYYMMDD, un código con caracteres raros,
--   el comodín 'Unknown' que la capa de integración usa cuando no supo mapear
--   el valor real. Todo eso invalida el dato para análisis.
-- Técnico: 12 reglas de formato/dominio por campo:
--     · 'Unknown' cuenta como inválido (source_system, coverage_code,
--       risk_number, policy_number, transaction_type, product_code).
--     · Fechas *_sk deben tener forma de 8 dígitos (YYYYMMDD):
--       transaction_date_sk con regex '^[0-9]{8}$'; las demás por LENGTH = 8.
--     · accountable_period debe tener 6 dígitos (YYYYMM).
--     · product_code: máx. 6 caracteres, sin espacios ni caracteres
--       especiales; y regla por fuente: en CO_iaxis el código de producto es
--       numérico, así que LETRAS solo son válidas en CO_as400.
--     · transaction_type: máx. 2 caracteres.
--   movement_type está EXCLUIDO a propósito (también está comentado en el
--   sql/05 original) — exclusión conocida, no un olvido; no reactivar sin
--   confirmarlo contra el catálogo de reglas (docs/*.xlsx).
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

-- Fila TOTAL_PERIODO de Validez (misma agregación que Completitud).
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
-- ------------------------------------------------------------
-- Dos chequeos que NO son comparables entre sí (no promediarlos):
--
-- (a) disponibilidad_sync — ¿la vista está sincronizada con la tabla base?
--     Negocio: si la vista (lo que consume Power BI) va retrasada frente a la
--       tabla base, el tablero muestra información incompleta sin que nadie
--       lo note. Este chequeo lo hace visible.
--     Técnico: cuenta las llaves de la tabla base gde_adp_dwh.fact_... que
--       aún NO aparecen en la vista vw_fact_... para el periodo. ~98% es
--       esperado y NORMAL (desfase de refresco de la vista materializada),
--       no una falla. Requiere permiso SELECT sobre el esquema gde_adp_dwh.
--     Sin el filtro compartido A PROPÓSITO: se comparan tabla y vista
--       COMPLETAS; cualquier filtro escondería brechas de sincronización.
--     El periodo se deriva de transaction_accounting_ts (TO_CHAR 'YYYYMM')
--       y no de accountable_period, para no depender de un campo que podría
--       venir mal poblado — precisamente lo que se quiere detectar.
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
    -- Llaves presentes en la tabla base pero ausentes en la vista (anti-join).
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

-- ============================================================
-- (b) disponibilidad_regla4 — ¿cada ramo recibió datos todos los días 1-15?
--     Negocio: la "regla 4" del catálogo exige que cada ramo (product_code)
--       registre movimientos TODOS los días del 1 al 15 del mes. El
--       porcentaje = ramos sin ningún día faltante / total de ramos.
--       Porcentajes BAJOS son comunes y esperables: basta UN día faltante
--       (un festivo sin emisión en un ramo pequeño, por ejemplo) para
--       castigar el ramo completo. Leerlo como señal de patrón, no de caída.
--     Técnico: se cuenta cuántos días DISTINTOS del rango 1-15 tiene cada
--       ramo (dias_presentes) y se compara contra v_dias_exigidos:
--         · mes cerrado  -> 15 (equivale a exigir todos los días 1-15);
--         · mes EN CURSO -> solo los días ya transcurridos (ver DECLARE),
--           para no castigar días que aún no ocurren.
--       El día se extrae de transaction_date_sk (YYYYMMDD): posiciones 7-8.
--       Misma lógica de conteo del notebook, por lo que ambos coinciden
--       también en meses parciales.
--     total_registros aquí = número de RAMOS del periodo, no de filas.
-- ============================================================
INSERT INTO co_sandbox_datos.kpi_cubo_mensual
WITH base AS (
    SELECT
        product_code,
        CAST(SUBSTRING(CAST(transaction_date_sk AS VARCHAR), 7, 2) AS INTEGER) AS dia
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE CAST(TO_CHAR(transaction_accounting_ts, 'YYYYMM') AS INTEGER) = p_periodo
),
ramos AS (
    SELECT
        product_code,
        COUNT(DISTINCT CASE WHEN dia BETWEEN 1 AND 15 THEN dia END) AS dias_presentes
    FROM base
    GROUP BY product_code
)
SELECT
    p_periodo,
    'disponibilidad',
    'disponibilidad_regla4',
    COUNT(*),                                                              -- total de ramos
    SUM(CASE WHEN dias_presentes >= v_dias_exigidos THEN 0 ELSE 1 END),   -- ramos con algún día exigido faltante
    CASE
        WHEN COUNT(*) = 0 THEN 0
        ELSE ROUND(SUM(CASE WHEN dias_presentes >= v_dias_exigidos THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
    END,
    1,
    GETDATE()
FROM ramos;

END;
$$;

-- //////////////////////// SP AUTO (detección de periodos pendientes) //////////////////////// --
-- Elimina los periodos "quemados": en vez de editar este archivo cada mes,
-- este SP descubre solo qué calcular. Procesa:
--   1) Todo periodo presente en la fuente que aún no exista en el cubo
--      (periodos nuevos que van cerrando, o backfill inicial de la historia).
--   2) SIEMPRE el MES EN CURSO (si ya tiene datos en la fuente): así el cubo
--      evoluciona día a día igual que el notebook/tablero — cada corrida
--      recalcula el mes abierto con los datos acumulados hasta ese momento.
--      Es seguro porque sp_kpi_cubo_mensual es idempotente (DELETE + INSERT);
--      fecha_calculo queda como marca del "corte" de esos datos parciales.
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
          AND (
                -- periodos que faltan en el cubo…
                accountable_period NOT IN (
                    SELECT DISTINCT periodo_contable
                    FROM co_sandbox_datos.kpi_cubo_mensual
                )
                -- …más el mes en curso, que se refresca en CADA corrida
                OR accountable_period = CAST(TO_CHAR(GETDATE(), 'YYYYMM') AS INTEGER)
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
-- Con una invocación DIARIA, el mes en curso se refresca cada día y el
-- tablero muestra su evolución, igual que al re-ejecutar el notebook.
-- Ese disparador no existe hoy en el stack (ver README.md) y su
-- construcción/gestión está fuera del alcance de este repositorio de SQL.

-- //////////////////////// VISTA PARA POWER BI //////////////////////// --
-- Passthrough 1:1 sobre la tabla. Existe para desacoplar a Power BI del
-- objeto físico: si mañana la tabla cambia de nombre/esquema o se le agrega
-- lógica (p. ej. marcar el mes en curso), solo se ajusta la vista y el
-- reporte no se toca.
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
-- Consultas de uso y verificación (ejecutar a mano, no son parte del deploy).

-- Backfill/recálculo de un periodo puntual (idempotente, se puede repetir):
-- call co_sandbox_datos.sp_kpi_cubo_mensual(202602);

-- Procesar todos los periodos pendientes + refrescar el mes en curso:
-- call co_sandbox_datos.sp_kpi_cubo_auto();

-- Inspeccionar el cubo de un periodo (detalle + totales):
select *
from co_sandbox_datos.kpi_cubo_mensual
where periodo_contable = 202602
order by tipo_indicador, nombre_campo;

-- Ver la evolución del mes en curso (fecha_calculo = corte de los datos parciales):
select *
from co_sandbox_datos.kpi_cubo_mensual


-- Periodos ya calculados vs. periodos disponibles en la fuente
-- (si un periodo aparece en la fuente y no en el cubo, sp_kpi_cubo_auto lo procesará):
select distinct accountable_period as periodo_disponible
from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
where current_record_flag = 1
order by 1;

select distinct periodo_contable as periodo_calculado
from co_sandbox_datos.kpi_cubo_mensual
order by 1;
