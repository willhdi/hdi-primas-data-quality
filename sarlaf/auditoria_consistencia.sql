/* ============================================================================
   AUDITORÍA DE LA REGLA DE CONSISTENCIA (ingresos / egresos)
   Motivo: pct_consistencia = 0.00 para persona jurídica en el periodo 202606.

   Requisito: haber ejecutado antes los BLOQUES A y B de sarlaf.sql en la misma
   sesión (crean tmp_reporte_base y tmp_reglas_reporte_base). El notebook
   sarlaf_runner.ipynb los ejecuta parametrizados.

   Todas las consultas son agregadas: no exponen datos personales.

   La regla auditada (bloque C de sarlaf.sql):

     LEAST(100, GREATEST(0,
         (1 - ( ABS(SUM(COALESCE(total_ingresos,0)) - SUM(COALESCE(ingresos_pirani,0)))
                / NULLIF(SUM(COALESCE(ingresos_pirani,0)), 0) )) * 100))
     FROM tmp_reglas_reporte_base
     WHERE tipo_persona IN (1,2) AND declara_sarlaft = 1 AND ingresos_pirani IS NOT NULL
     GROUP BY tipo_persona

   No es un "% de clientes consistentes": es 100 menos la desviación relativa
   entre DOS SUMAS del portafolio. Si esa desviación supera el 100 %, el
   GREATEST(0, ...) la trunca a 0 — que es exactamente lo que está pasando.

   ----------------------------------------------------------------------------
   CONCLUSIÓN DE LA AUDITORÍA (periodo 202606, corrida del 2026-07-24)
   ----------------------------------------------------------------------------
   El 0.00 de persona jurídica NO indica un problema de calidad de las cifras.
   Es un artefacto de comparar contra ceros:

   * El universo jurídico son 522 clientes. De ellos, 512 tienen
     ingresos_pirani = 0 y solo 10 tienen un valor > 0 (Q2).
   * Esos 512 aportan $2.739.303.453.422 al NUMERADOR y $0 al DENOMINADOR.
     Solo 3 empresas (ingresos > 100.000 M) aportan $2.599.193.472.950, el 87 %
     del "error" (Q5).
   * Donde Pirani sí tiene dato, la cifra coincide EXACTAMENTE: las 10 empresas
     comparables dan razón reporte/Pirani = 1.0000 (mín = mediana = máx) y 10 de
     10 son iguales al peso (Q4). La fórmula sobre ese subconjunto da 100.00 (Q3).
   * Egresos es aún más extremo: 519 de 522 con egresos_pirani = 0, desviación
     129,42 -> 0.00 (Q7).

   CAUSA DE FONDO: el filtro del universo es `ingresos_pirani IS NOT NULL`, pero
   en Pirani el "sin dato" viene como la cadena '0', no como NULL (230.452 de
   357.140 registros). El IS NOT NULL nunca los excluye, así que la regla lee
   "Pirani afirma que esta empresa tiene ingresos de $0" cuando en realidad
   significa "Pirani no capturó el dato". El mismo defecto tiene la regla fila a
   fila rg_consistencia_* del bloque B (Q6): marca 0 = inconsistente cuando la
   comparación era imposible.

   CORRECCIÓN SUGERIDA (decisión de negocio, no aplicada aquí): cambiar el
   universo de `ingresos_pirani IS NOT NULL` a `ingresos_pirani > 0` y reportar
   siempre la COBERTURA junto al porcentaje. Con ese cambio el indicador daría
   100.00 en jurídica y 99.65 en natural (Q3) — pero sobre 10 y 82.723 clientes
   respectivamente, es decir 0,03 % de las empresas. Publicar ese 100 sin declarar
   la cobertura sería tan engañoso como el 0.00 actual.
   ============================================================================ */


-- @@Q0: Demostración del truncamiento, sin depender de ninguna tabla
-- Reproduce la fórmula con las dos sumas observadas en el periodo 202606 para
-- persona jurídica. Se puede pegar en cualquier editor SQL y da 0 siempre.
-- Resultado: ratio 11.903787 -> (1 - 11.903787) * 100 = -1090.3787 -> GREATEST -> 0.
WITH s AS (
    SELECT 2973929676533.00::NUMERIC(38,2) AS suma_reporte,   -- SUM(total_ingresos)  de 522 empresas
            230469534390.00::NUMERIC(38,2) AS suma_pirani     -- SUM(ingresos_pirani) de las mismas 522
)
SELECT
    suma_reporte,
    suma_pirani,
    ABS(suma_reporte - suma_pirani)                                              AS paso3_diferencia_abs,
    ROUND(ABS(suma_reporte - suma_pirani) / NULLIF(suma_pirani, 0), 6)           AS paso4_ratio_desviacion,
    ROUND((1 - ABS(suma_reporte - suma_pirani) / NULLIF(suma_pirani, 0)) * 100, 4) AS paso5_pct_sin_truncar,
    GREATEST(0, (1 - ABS(suma_reporte - suma_pirani) / NULLIF(suma_pirani, 0)) * 100) AS paso6_tras_greatest,
    LEAST(100, GREATEST(0, (1 - ABS(suma_reporte - suma_pirani) / NULLIF(suma_pirani, 0)) * 100)) AS paso7_valor_final
FROM s;
-- OJO: si algún día esas columnas dejaran de ser NUMERIC y fueran enteras, la
-- división pasaría a ser ENTERA (11 en vez de 11.903787) y el indicador cambiaría
-- de valor en silencio. Hoy son NUMERIC(18,2) por los TRY_CAST del bloque A.


-- @@Q1: Descomposición aritmética de la fórmula, paso a paso, por tipo de persona
-- Muestra que el 0.00 NO viene de falta de datos sino del truncamiento.
SELECT
    tipo_persona,
    COUNT(*)                                                              AS filas_universo,
    SUM(COALESCE(total_ingresos, 0))                                      AS paso1_suma_reporte,
    SUM(COALESCE(ingresos_pirani, 0))                                     AS paso2_suma_pirani,
    ABS(SUM(COALESCE(total_ingresos, 0)) - SUM(COALESCE(ingresos_pirani, 0)))
                                                                          AS paso3_diferencia_abs,
    ROUND(ABS(SUM(COALESCE(total_ingresos, 0)) - SUM(COALESCE(ingresos_pirani, 0)))
          / NULLIF(SUM(COALESCE(ingresos_pirani, 0)), 0), 6)              AS paso4_ratio_desviacion,
    ROUND((1 - ABS(SUM(COALESCE(total_ingresos, 0)) - SUM(COALESCE(ingresos_pirani, 0)))
               / NULLIF(SUM(COALESCE(ingresos_pirani, 0)), 0)) * 100, 4)  AS paso5_pct_sin_truncar,
    GREATEST(0, (1 - ABS(SUM(COALESCE(total_ingresos, 0)) - SUM(COALESCE(ingresos_pirani, 0)))
                     / NULLIF(SUM(COALESCE(ingresos_pirani, 0)), 0)) * 100)
                                                                          AS paso6_tras_greatest,
    LEAST(100, GREATEST(0, (1 - ABS(SUM(COALESCE(total_ingresos, 0)) - SUM(COALESCE(ingresos_pirani, 0)))
                                / NULLIF(SUM(COALESCE(ingresos_pirani, 0)), 0)) * 100))
                                                                          AS paso7_valor_final
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND declara_sarlaft = 1
  AND ingresos_pirani IS NOT NULL
GROUP BY tipo_persona
ORDER BY tipo_persona;


-- @@Q2: ¿De qué está hecho el universo? Cuántos aportan 0 al denominador
-- Si casi todos los ingresos de Pirani son 0, el denominador queda diminuto
-- frente al numerador y la desviación relativa se dispara.
SELECT
    tipo_persona,
    CASE WHEN COALESCE(ingresos_pirani, 0) = 0 THEN 'pirani = 0' ELSE 'pirani > 0' END AS grupo_pirani,
    COUNT(*)                                          AS clientes,
    SUM(COALESCE(total_ingresos, 0))                  AS suma_reporte,
    SUM(COALESCE(ingresos_pirani, 0))                 AS suma_pirani,
    SUM(CASE WHEN COALESCE(total_ingresos, 0) = 0 THEN 1 ELSE 0 END) AS reporte_en_cero
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND declara_sarlaft = 1
  AND ingresos_pirani IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;


-- @@Q3: La misma fórmula, pero comparando solo donde AMBOS lados tienen valor > 0
-- Es la comparación "limpia": mide si hay un problema real de cifras o solo de ceros.
SELECT
    tipo_persona,
    COUNT(*)                                                             AS filas_comparables,
    SUM(total_ingresos)                                                  AS suma_reporte,
    SUM(ingresos_pirani)                                                 AS suma_pirani,
    ROUND(ABS(SUM(total_ingresos) - SUM(ingresos_pirani))
          / NULLIF(SUM(ingresos_pirani), 0), 6)                          AS ratio_desviacion,
    LEAST(100, GREATEST(0, (1 - ABS(SUM(total_ingresos) - SUM(ingresos_pirani))
                                / NULLIF(SUM(ingresos_pirani), 0)) * 100)) AS pct_consistencia_limpio
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND declara_sarlaft = 1
  AND ingresos_pirani > 0
  AND total_ingresos  > 0
GROUP BY tipo_persona
ORDER BY tipo_persona;


-- @@Q4: ¿Hay diferencia de ESCALA entre las dos fuentes? (mensual vs anual, miles vs pesos)
-- Se mira la razón fila a fila reporte/pirani donde ambos son > 0.
SELECT
    tipo_persona,
    COUNT(*)                                                                     AS filas,
    ROUND(MIN(total_ingresos / ingresos_pirani), 4)                              AS razon_min,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_ingresos / ingresos_pirani), 4) AS razon_p25,
    ROUND(MEDIAN(total_ingresos / ingresos_pirani), 4)                           AS razon_mediana,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_ingresos / ingresos_pirani), 4) AS razon_p75,
    ROUND(MAX(total_ingresos / ingresos_pirani), 4)                              AS razon_max,
    SUM(CASE WHEN total_ingresos = ingresos_pirani THEN 1 ELSE 0 END)            AS iguales_exactos
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND declara_sarlaft = 1
  AND ingresos_pirani > 0
  AND total_ingresos  > 0
GROUP BY tipo_persona
ORDER BY tipo_persona;


-- @@Q5: Concentración — ¿el resultado lo decide un puñado de clientes?
-- Reparte el universo jurídico en rangos de magnitud (sin identificar a nadie)
-- y muestra cuánto aporta cada rango a la suma del reporte.
SELECT
    tipo_persona,
    CASE
        WHEN COALESCE(total_ingresos, 0) = 0                     THEN '0'
        WHEN total_ingresos <          1000000                   THEN '1) < 1 M'
        WHEN total_ingresos <         10000000                   THEN '2) 1 M - 10 M'
        WHEN total_ingresos <        100000000                   THEN '3) 10 M - 100 M'
        WHEN total_ingresos <       1000000000                   THEN '4) 100 M - 1.000 M'
        WHEN total_ingresos <      10000000000                   THEN '5) 1.000 M - 10.000 M'
        WHEN total_ingresos <     100000000000                   THEN '6) 10.000 M - 100.000 M'
        ELSE                                                          '7) > 100.000 M'
    END                                              AS rango_ingresos_reporte,
    COUNT(*)                                         AS clientes,
    SUM(COALESCE(total_ingresos, 0))                 AS aporte_a_suma_reporte,
    SUM(COALESCE(ingresos_pirani, 0))                AS aporte_a_suma_pirani
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND declara_sarlaft = 1
  AND ingresos_pirani IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;


-- @@Q6: El indicador ALTERNATIVO que sí es comparable con las demás dimensiones:
-- % de clientes cuya cifra coincide con Pirani (la regla rg_consistencia_* del
-- bloque B, que hoy está calculada pero NO se usa en el bloque C).
SELECT
    tipo_persona,
    COUNT(*)                                                                  AS clientes_con_base_comparacion,
    SUM(rg_consistencia_ingresos)                                             AS ingresos_consistentes,
    ROUND(100.0 * SUM(rg_consistencia_ingresos) / NULLIF(COUNT(rg_consistencia_ingresos), 0), 2)
                                                                              AS pct_clientes_consistentes_ing,
    SUM(rg_consistencia_egresos)                                              AS egresos_consistentes,
    ROUND(100.0 * SUM(rg_consistencia_egresos) / NULLIF(COUNT(rg_consistencia_egresos), 0), 2)
                                                                              AS pct_clientes_consistentes_egr
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND rg_consistencia_ingresos IS NOT NULL
GROUP BY tipo_persona
ORDER BY tipo_persona;


-- @@Q7: Lo mismo para EGRESOS (la otra celda que da 0.00)
SELECT
    tipo_persona,
    COUNT(*)                                                              AS filas_universo,
    SUM(COALESCE(total_egresos, 0))                                       AS suma_reporte,
    SUM(COALESCE(egresos_pirani, 0))                                      AS suma_pirani,
    ROUND(ABS(SUM(COALESCE(total_egresos, 0)) - SUM(COALESCE(egresos_pirani, 0)))
          / NULLIF(SUM(COALESCE(egresos_pirani, 0)), 0), 6)               AS ratio_desviacion,
    LEAST(100, GREATEST(0, (1 - ABS(SUM(COALESCE(total_egresos, 0)) - SUM(COALESCE(egresos_pirani, 0)))
                                / NULLIF(SUM(COALESCE(egresos_pirani, 0)), 0)) * 100))
                                                                          AS pct_consistencia_final,
    SUM(CASE WHEN COALESCE(egresos_pirani, 0) = 0 THEN 1 ELSE 0 END)      AS pirani_en_cero
FROM tmp_reglas_reporte_base
WHERE tipo_persona IN (1, 2)
  AND declara_sarlaft = 1
  AND egresos_pirani IS NOT NULL
GROUP BY tipo_persona
ORDER BY tipo_persona;


-- @@Q8: Variantes de la fórmula, para decidir cómo acotar el rango sin GREATEST
-- V0 = fórmula actual (necesita GREATEST/LEAST para no salirse de rango)
-- V1 = denominador simétrico (a + b): |a-b| <= a+b siempre => rango [0,100] GARANTIZADO
-- V2 = razón menor/mayor: también acotada, pero usa GREATEST/LEAST
-- V3 = % de CLIENTES que coinciden (AVG de 0/1): acotada por construcción y
--      comparable con las demás dimensiones. OJO con la escala: hay que castear a
--      DECIMAL(18,6) o Redshift trunca el promedio (con 1.0/0.0 devuelve 1 decimal).
WITH base AS (
    SELECT tipo_persona,
           SUM(COALESCE(total_ingresos, 0))::NUMERIC(38,2)  AS a,
           SUM(COALESCE(ingresos_pirani, 0))::NUMERIC(38,2) AS b,
           COUNT(*)                                         AS n
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
      AND ingresos_pirani IS NOT NULL   -- cambiar a `ingresos_pirani > 0` para el universo corregido
    GROUP BY tipo_persona
)
SELECT
    tipo_persona,
    n                                                                       AS clientes,
    ROUND(LEAST(100, GREATEST(0, (1 - ABS(a - b) / NULLIF(b, 0)) * 100)), 2) AS v0_actual,
    ROUND((1 - ABS(a - b) / NULLIF(b, 0)) * 100, 2)                          AS v0_sin_truncar,
    ROUND((1 - ABS(a - b) / NULLIF(a + b, 0)) * 100, 2)                      AS v1_simetrico,
    ROUND(LEAST(a, b) / NULLIF(GREATEST(a, b), 0) * 100, 2)                  AS v2_min_sobre_max
FROM base
ORDER BY tipo_persona;
