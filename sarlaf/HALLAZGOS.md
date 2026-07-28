# Hallazgos sobre `sarlaf.sql`

Documentados, sin modificar el SQL original. Números de la corrida del periodo **202606** con
`clientes_pirani_202606` (los mismos valores que están quemados en `sarlaf.sql`), ejecutada el
2026-07-24 desde `sarlaf_runner.ipynb` y `auditoria_consistencia.sql`.

## 1. El `0.00` de consistencia en persona jurídica es un artefacto de comparar contra ceros

No es un problema de calidad de las cifras. La evidencia:

- El universo jurídico son **522 clientes**. De ellos **512 tienen `ingresos_pirani = 0`** y solo
  **10** tienen un valor mayor que cero.
- Esos 512 aportan **$2.739.303.453.422 al numerador** y **$0 al denominador**. Solo 3 empresas
  (ingresos > 100.000 M) aportan $2.599.193.472.950, el **87 % del "error"**.
- Donde Pirani sí tiene dato, la cifra **coincide exactamente**: las 10 empresas comparables dan
  razón reporte/Pirani = 1.0000 (mínimo = mediana = máximo) y las 10 son iguales al peso.
  La fórmula aplicada solo a ese subconjunto da **100.00**.
- Egresos es más extremo aún: 519 de 522 con `egresos_pirani = 0`, desviación 129,42 → `0.00`.

**Causa de fondo:** el universo se filtra con `ingresos_pirani IS NOT NULL`, pero en Pirani el
"sin dato" llega como la cadena `'0'`, no como `NULL` (230.452 de 357.140 registros). El
`IS NOT NULL` nunca los excluye, así que la regla interpreta "Pirani afirma que esta empresa
tiene ingresos de $0" cuando en realidad significa "Pirani no capturó el dato".

**Corrección sugerida** (decisión de negocio, no aplicada): cambiar el universo a
`ingresos_pirani > 0` y reportar siempre la **cobertura** junto al porcentaje. Con ese cambio el
indicador daría 100.00 en jurídica y ~99,7 en natural — pero sobre 10 y ~82.800 clientes, es decir
el 0,03 % de las empresas. Publicar ese 100 sin declarar la cobertura sería tan engañoso como el
`0.00` actual.

## 2. La fórmula no tiene resolución fuera del rango 0–100 % de desviación

`LEAST(100, GREATEST(0, (1 − desviación_relativa) × 100))` aplasta a 0 cualquier desviación mayor
al 100 %: un −20 % y un −1090 % se ven idénticos. Además no es un "% de clientes que cumplen" como
las demás dimensiones, sino una razón entre **dos sumas** del portafolio, que se la puede llevar un
solo cliente grande (aquí, 3 empresas hacen el 87 %).

Detalle de fragilidad: si esas columnas dejaran de ser `NUMERIC` y fueran enteras, la división
pasaría a ser **entera** (ratio 11 en vez de 11,903787) y el indicador cambiaría de valor en
silencio. Hoy son `NUMERIC(18,2)` por los `TRY_CAST` del bloque A.

### Variantes evaluadas para acotar el rango sin `GREATEST` (Q8)

Poner más `ABS` no sirve: el `ABS` ya está en el numerador y lo que se dispara es el **cociente**,
que no tiene cota superior. Lo que sí acota por construcción es cambiar el **denominador**.

| variante | fórmula | ingresos natural (97.178) | ingresos jurídica (522) | egresos jurídica (522) |
|---|---|---|---|---|
| V0 actual | `1 − \|a−b\|/b`, truncada | 98,28 | **0,00** (crudo −1.090,37) | **0,00** (crudo −12.842,11) |
| V1 simétrica | `1 − \|a−b\|/(a+b)` | 99,15 | 14,39 | 1,53 |
| V2 min/max | `min(a,b)/max(a,b)` | 98,30 | 7,74 | 0,76 |

Como `a, b ≥ 0`, siempre se cumple `|a−b| ≤ a+b`, así que **V1 está en [0,100] por construcción**,
sin `GREATEST` ni `LEAST`. V2 también está acotada pero usa esas mismas funciones. V2 es casi
idéntica a V0 en el rango sano (98,30 vs 98,28), así que preserva la comparabilidad con lo ya
reportado; V1 sube todo ~0,9 pp.

Ninguna de las dos arregla el problema de los ceros del punto 1: solo cambia la escala con que se
reporta el artefacto.

**V3 — % de clientes que coinciden** (universo `pirani > 0`, tolerancia ±1):

| | clientes | % coinciden |
|---|---|---|
| Ingresos natural | 82.775 | 95,65 |
| Ingresos jurídica | 10 | 100,00 |
| Egresos natural | 70.385 | 77,61 |
| Egresos jurídica | 3 | 66,67 |

Es un `AVG` de 0/1: acotado por construcción, sin división que se dispare, sin que un cliente grande
domine, y comparable con completitud/validez/unicidad. La brecha con la razón de sumas es
reveladora: en egresos de natural, las **sumas** cuadran al 99,82 % pero solo el **77,61 % de los
clientes** tiene la cifra correcta — los errores en un sentido cancelan los del otro y el agregado
los esconde.

> Trampa de Redshift al implementarlo: `AVG(CASE WHEN ... THEN 1.0 ELSE 0.0 END)` trunca el
> resultado a **un decimal** (la escala de `1.0`). Hay que castear a `DECIMAL(18,6)` como ya hace el
> bloque C original. Con `1.0` el % de ingresos natural sale 90,0 en vez de 95,65.

## 3. Dónde el `NULL` de `pct_consistencia` sí es normal

La dimensión consistencia solo está definida para `total_ingresos` y `total_egresos`. En los otros
8 atributos (`numero_documento`, `celular`, …) `pct_consistencia` sale `NULL` para ambos tipos de
persona, y es correcto.

## 4. El NIT del formulario SARLAFT no cruza con el de iAxis

El formulario guarda el NIT **sin dígito de verificación** (9 dígitos: 159.681 de 176.821) e iAxis
**con** DV (10 dígitos: 260.948). El join `p.nnumide = s.num_identificacion` cruza solo **3.349**
NIT; quitándole el DV al lado de iAxis cruzan **154.127** — 46 veces más.

Consecuencia: solo **525 de 28.623** tomadores jurídicos (1,8 %) quedan con `declara_sarlaft = 1`,
contra 42,9 % en personas naturales. Afecta a `clasificacion`, `perfil_riesgo` y a los cuatro
atributos financieros (activos/pasivos/ingresos/egresos), que salen del formulario: toda la
medición de personas jurídicas de esos campos queda sesgada.

*Pirani sí cruza bien* (28.456 de 28.623) porque trae el NIT con DV, igual que iAxis.

**Alcance medido — este bug NO es lo que limita la cobertura de consistencia.** Se comprobó
quitando el filtro `declara_sarlaft = 1` del universo: la cobertura queda **idéntica** (10 clientes
en jurídica, 82.837 en natural) y el porcentaje no se mueve. La razón es que quien tiene cifra en
Pirani ya tiene formulario, así que el filtro no está descartando a nadie. El limitante de
consistencia es el punto 12, no este.

## 12. El techo de cobertura de consistencia lo pone Pirani, no el join

En la tabla `clientes_pirani_202606` (357.140 registros):

| tipo persona en Pirani | filas | con `ingresos > 0` | con `egresos > 0` |
|---|---|---|---|
| J (empresas) | 39.878 | **156** (0,4 %) | **54** (0,1 %) |
| N (naturales) | 317.262 | 125.363 (39,5 %) | 103.488 (32,6 %) |

Pirani prácticamente no trae cifras financieras de empresas. Embudo sobre los tomadores vigentes:

| paso | natural | jurídica |
|---|---|---|
| 1. clientes vigentes | 228.603 | 28.623 |
| 2. cruzan con Pirani | 226.953 | 28.456 |
| 3. Pirani trae ingresos > 0 | 82.837 | **10** |
| 4. (además) con formulario SARLAFT | 98.034 | 525 |
| 5. universo de consistencia v2 | 82.837 | **10** |

El paso 3 es el que manda: el paso 4 no resta nada. Por eso la cobertura de consistencia en
jurídica no puede subir arreglando joins — no existe el dato de contraste. Solo subiría si Pirani
empezara a entregar ingresos/egresos de empresas.

## 13. Los tres números que conviene publicar por campo

Consistencia se diferencia de completitud/validez/unicidad en que necesita una **segunda fuente**.
Por eso un solo porcentaje no alcanza: hay que decir también sobre cuánta población se calculó.

Ya implementado en el bloque C de `sarlaf_v2.sql`. Salida real del periodo 202606:

| tipo | atributo | `pct_consistencia` | `pct_cobertura_consistencia` | `pct_consistencia_ponderada` | `cumple_90` | `alerta_cobertura_baja` |
|---|---|---|---|---|---|---|
| Natural | total_ingresos | 95,78 | 36,24 | 34,71 | 1 | 0 |
| Natural | total_egresos | 78,08 | 30,81 | 24,05 | 0 | 0 |
| Jurídica | total_ingresos | **100,00** | **0,03** | **0,03** | **1** | **1** |
| Jurídica | total_egresos | 66,67 | 0,01 | 0,01 | 0 | **1** |

- **Cobertura** = comparables / total de clientes → qué tan verificable es el campo.
- **Consistencia** = coinciden / comparables → de lo verificable, cuánto cuadra (es lo que hoy
  entrega `sarlaf_v2.sql`).
- **Ponderada** = coinciden / total de clientes → el número sobre el 100 % de la población;
  equivale a consistencia × cobertura y cuenta a los no comparables como "no verificados".

Publicar solo el 100,00 de jurídica es tan engañoso como el `0.00` original: está calculado sobre
10 clientes de 28.623. Con los tres números juntos queda claro de inmediato que el problema es la
fuente, no los datos de HDI.

## 5. `rg_consistencia_ingresos` / `rg_consistencia_egresos` son código muerto

El bloque B las calcula fila a fila (tolerancia ±1), pero los bloques C y SFC no las usan: usan la
razón de sumas. Dan resultados incompatibles — la regla fila a fila da **0,04 %** en jurídica y
**36,23 %** en natural, frente al 98,28 % de la razón de sumas.

Además arrastra el mismo defecto del punto 1: marca `0 = inconsistente` cuando `ingresos_pirani = 0`,
o sea cuando la comparación era imposible.

## 6. El bloque SFC usa `CREATE TABLE` (permanente), no `CREATE TEMP TABLE`

Deja `tmp_reporte_sfc_calidad_datos` en el esquema por defecto y hace fallar la segunda ejecución
("table already exists"). El notebook lo ejecuta como TEMP.

## 7. El bloque C y el bloque SFC no reportan lo mismo

En el SFC están comentadas las filas de oportunidad de `numero_documento`, `nombres_completos`,
`fecha_nacimiento` y `fecha_vinculacion`; en el bloque C sí están. Los dos entregables difieren en
esas 4 celdas.

## 8. `fecha_actualizacion_*` financieras caen a `p.fmovimi_persona` aunque el valor no exista

(`ELSE p.fmovimi_persona` en activos/pasivos/ingresos/egresos.) Un cliente sin ingresos puede
puntuar "oportuno" en ingresos: la oportunidad queda inflada.

## 9. `total_ingresos` para jurídica sale de `s.ingreso_laboral`

En la cascada `COALESCE(sct.total_ingresos_sct, s.ingreso_laboral, d.ingresos)`. "Ingreso laboral"
es un concepto de persona natural; conviene confirmar con negocio qué campo del formulario aplica a
una empresa.

## 10. El parseo de Pirani no está fallando hoy, pero es frágil

`REGEXP_REPLACE(..., '[^0-9.-]', '')` sobre un formato colombiano `1.234.567,89` produciría
`1.234.567.89` y `TRY_CAST` devolvería `NULL` sin error. En `clientes_pirani_202606` los 357.140
registros parsean bien, pero basta un cambio de formato en el cargue para perder valores en silencio.

## 11. El reporte no es reproducible bit a bit entre corridas

Varios `ROW_NUMBER() OVER (... ORDER BY fmovimi DESC)` no tienen desempate determinista: con dos
registros del mismo `sperson` y misma fecha, cada corrida puede elegir uno distinto. Entre dos
ejecuciones seguidas, la consistencia de ingresos de persona natural se movió de 98,28 a 98,29.
