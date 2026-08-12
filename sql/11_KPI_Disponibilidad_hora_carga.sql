-- 11_KPI_Disponibilidad_hora_carga.sql  (nuevo, aditivo — BORRADOR)
--
-- Disponibilidad por HORA DE CARGA (corte 11:00 am).
--
-- Objetivo: además de "¿llegó data del mes?" (sql/08, que solo cuenta DÍAS), medir
-- si la carga de cada día quedó lista ANTES o DESPUÉS de las 11:00 am.
--
-- ⚠ BLOQUEO / VERIFICAR PRIMERO ⚠
-- transaction_date_sk es un entero YYYYMMDD: NO tiene hora. Para el corte 11am hace
-- falta un TIMESTAMP TÉCNICO REAL de fin de carga. Candidatos:
--   • load_ts                  — documentado como "hora en que el registro se cargó al
--                                DWH". Es el correcto SI existe en la vista con hora real.
--   • transaction_accounting_ts — timestamp CONTABLE (de negocio). NO sirve para hora de
--                                carga: refleja cuándo ocurrió el movimiento, no cuándo se cargó.
-- Por eso este archivo tiene dos partes: PASO 1 (diagnóstico, correr y pegarme el
-- resultado) y PASO 2 (indicador borrador, ya escrito, que se activa al confirmar).

-- =====================================================================
-- PASO 1 — DIAGNÓSTICO (correr en Redshift y compartir el resultado)
-- =====================================================================

-- 1a) ¿Qué columnas de tipo timestamp / carga expone la vista?
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gde_adp_dwh_vw_general'
  AND table_name   = 'vw_fact_policy_transaction_movement'
  AND (   data_type ILIKE '%timestamp%'
       OR column_name ILIKE '%ts%'
       OR column_name ILIKE '%load%'
       OR column_name ILIKE '%carga%'
       OR column_name ILIKE '%fecha%' )
ORDER BY column_name;

-- 1b) Si aparece load_ts (o equivalente): ¿trae hora real y cómo se ve un día típico?
--     (Confirma que MIN/MAX difieren en horas — si todo cae a las 00:00:00, NO hay hora.)
-- SELECT
--     transaction_date_sk,
--     COUNT(*)        AS registros,
--     MIN(load_ts)    AS primera_carga,
--     MAX(load_ts)    AS ultima_carga
-- FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
-- WHERE transaction_date_sk >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '10 days', 'YYYYMMDD') AS INTEGER)
--   AND load_ts IS NOT NULL
-- GROUP BY transaction_date_sk
-- ORDER BY transaction_date_sk DESC;

-- Si NO existe ninguna columna de carga en la vista, necesito de tu lado UNA de estas:
--   (A) Una tabla de control/log del ETL con: fecha de datos + timestamp de fin de carga
--       (y a poder ser el estado del job). Me pasas esquema.tabla y nombres de columna.
--   (B) O confirmar que se expone load_ts en la vista base para poder derivarlo.
-- Sin (A) ni (B) el corte de 11am no se puede calcular (no hay hora que comparar).


-- =====================================================================
-- PASO 2 — INDICADOR (ACTIVO — confirmado con el diagnóstico del PASO 1)
--
-- Confirmado en la vista:
--   • load_ts existe y es TIMESTAMP con hora real (cargas ~04:00–09:00 am).
--   • transaction_accounting_ts se descarta (es contable, no de carga).
--
-- DECISIÓN CLAVE — usar MIN(load_ts), NO MAX(load_ts):
--   El diagnóstico mostró que MAX(load_ts) de casi todos los días se corre al timestamp
--   de HOY, porque los registros viejos se REESCRIBEN en cargas posteriores (versionado
--   SCD / reprocesos). Por eso MAX no mide el arribo del día. MIN(load_ts) sí: es cuándo
--   la data de ese día aterrizó POR PRIMERA VEZ (la madrugada del día siguiente).
--
--   Grano: un renglón por día de datos (transaction_date_sk). Ventana: últimos ~60 días.
--   "A tiempo" = el arribo (MIN load_ts) ocurrió a las 11:00 am o antes de su día.
-- =====================================================================

CREATE OR REPLACE VIEW co_sandbox_datos.vw_disponibilidad_hora_carga AS
WITH arribo AS (
    SELECT
        transaction_date_sk,
        TO_DATE(transaction_date_sk::VARCHAR, 'YYYYMMDD')       AS fecha_datos,
        MIN(load_ts)                                            AS arribo_datos,      -- primer aterrizaje = arribo real del día
        MAX(load_ts)                                            AS ultima_escritura,  -- referencia: última reescritura (SCD/reproceso), NO es el arribo
        COUNT(*)                                                AS registros
    FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    WHERE load_ts IS NOT NULL
      AND transaction_date_sk IS NOT NULL
      AND transaction_date_sk::VARCHAR ~ '^[0-9]{8}$'
      AND transaction_date_sk >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '60 days', 'YYYYMMDD') AS INTEGER)
    GROUP BY 1, 2
)
SELECT
    fecha_datos,
    transaction_date_sk,
    CAST(TO_CHAR(fecha_datos, 'YYYYMM') AS INTEGER)             AS periodo_contable,
    'disponibilidad'                                           AS tipo_indicador,
    'hora_carga_11am'                                          AS nombre_campo,
    arribo_datos,                                                                    -- cuándo llegó la data del día
    CAST(arribo_datos AS TIME)                                 AS hora_arribo,
    ultima_escritura,
    registros,
    -- Minutos respecto al corte de las 11:00 am del día del arribo (negativo = antes de las 11 = a tiempo).
    DATEDIFF(minute, DATE_TRUNC('day', arribo_datos) + INTERVAL '11 hours', arribo_datos) AS minutos_vs_corte,
    CASE
        WHEN CAST(arribo_datos AS TIME) <= TIME '11:00:00' THEN 'A tiempo'
        ELSE 'Tarde'
    END                                                        AS estado,
    GETDATE()                                                  AS fecha_calculo
FROM arribo
ORDER BY fecha_datos DESC;

-- Validación:
--   SELECT * FROM co_sandbox_datos.vw_disponibilidad_hora_carga;
--   -- ¿algún día llegó tarde (después de las 11)?
--   SELECT * FROM co_sandbox_datos.vw_disponibilidad_hora_carga WHERE estado = 'Tarde';

-- Nota: si en el futuro la carga pasa a correr en varios lotes durante el día y quieres
-- medir el FIN del batch matutino (no el primer arribo), la fuente correcta sería una tabla
-- de control/log del ETL con el timestamp de fin de proceso. Hoy, con carga única de
-- madrugada, MIN(load_ts) es el arribo correcto.
