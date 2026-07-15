# Guía: tablero de Calidad de Datos en Power BI (réplica del tablero HTML)

Guía paso a paso para consumir el Cubo Unificado (`co_sandbox_datos.vw_kpi_cubo_mensual_pbi`)
y reconstruir en Power BI Desktop el mismo tablero que hoy existe en
`reports/tablero_calidad_primas.html`. No reemplaza el HTML — es la versión Power BI del mismo reporte.

**Restricción de diseño:** solo visuales nativos (sin AppSource). El radar del HTML se reemplaza por
barras agrupadas y el Pareto se arma con el gráfico combinado nativo.

## Mapa: tablero HTML → Power BI

| Pestaña del HTML | Página de Power BI | Visuales |
|---|---|---|
| Resumen ejecutivo | 1. Resumen ejecutivo | 5 Medidores + tarjetas Δ, 2 tarjetas Disponibilidad, línea DQ Score, barras vs Target (reemplaza al radar), tabla semáforo |
| Detalle por variable | 2. Detalle por variable | 3 tablas por dimensión, tarjeta hero Unicidad, tabla combinada |
| Tendencia e historia | 3. Tendencia e historia | Líneas multi-serie + línea Target, tabla de variación |
| Análisis de errores | 4. Análisis de errores | Anillo por dimensión, tabla Top 10, Pareto nativo |
| Información | 5. Información | Cuadros de texto |
| Modal drill-down (clic en anillo) | 6. Detalle dimensión (obtención de detalles) | Tabla por campo, se llega con clic derecho |

---

## 0. Requisitos previos

1. **El cubo debe estar poblado.** Si aún no existe, ejecuta completo `sql/06_KPI_Cubo Unificado.sql`
   (crea tabla, SPs y vista) y luego, en el editor SQL del warehouse:
   ```sql
   CALL co_sandbox_datos.sp_kpi_cubo_auto();
   SELECT * FROM co_sandbox_datos.vw_kpi_cubo_mensual_pbi LIMIT 20; -- verificación
   ```
2. Power BI Desktop instalado y conexión al CDP (Redshift) ya probada.
3. Archivos del repo a mano: `reports/tema_hdi_powerbi.json` (tema) y `HDI_Seguros.png` (logo).
4. Plan B sin conexión: `reports/cubo_unificado.csv` tiene las mismas columnas (menos `fecha_calculo`)
   y sirve para maquetar el tablero offline; luego se cambia el origen a la vista.

## 1. Conectar los datos

1. **Obtener datos → PostgreSQL** (Redshift usa el conector PostgreSQL). Servidor/puerto/base del
   warehouse de siempre; modo **Import** (la vista es un agregado mensual pequeño).
2. Selecciona `co_sandbox_datos.vw_kpi_cubo_mensual_pbi` → **Transformar datos** (no cargues aún).
3. En Power Query, renombra la consulta a **`KPI_Cubo`** y confirma tipos:
   - `periodo_contable` → **Número entero** (YYYYMM; se usa para ordenar),
   - `porcentaje` → **Número decimal**, `total_registros` y `cantidad_mala` → **Número entero**,
   - `es_total` → **Número entero**, `fecha_calculo` → **Fecha/Hora**.

### 1.1 Columnas auxiliares (Agregar columna → Columna personalizada)

**`Periodo (texto)`** (tipo Texto) — etiqueta del slicer, con "(en curso)" para el mes actual,
calculado dinámicamente (sin periodos quemados, alineado al mandato del proyecto):

```
Text.From([periodo_contable]) &
(if [periodo_contable] = Date.Year(DateTime.LocalNow()) * 100 + Date.Month(DateTime.LocalNow())
 then " (en curso)" else "")
```

**`Dimensión`** (tipo Texto) — etiqueta legible para leyendas y tablas:

```
if [tipo_indicador] = "completitud" then "Completitud"
else if [tipo_indicador] = "exactitud" then "Exactitud"
else if [tipo_indicador] = "unicidad" then "Unicidad"
else if [tipo_indicador] = "validez" then "Validez"
else "Disponibilidad"
```

**`es_fila_error`** (tipo Número entero) — marca las filas que cuentan errores sin duplicar
(las filas TOTAL repetirían la suma del detalle; Unicidad solo tiene su fila total; Disponibilidad
queda fuera del análisis de errores). La usan el anillo, el Top 10 y el Pareto de la página 4:

```
if [tipo_indicador] = "disponibilidad" then 0
else if [es_total] = 0 then 1
else if [tipo_indicador] = "unicidad" then 1
else 0
```

4. **Cerrar y aplicar.** En la vista de datos, selecciona `Periodo (texto)` →
   **Ordenar por columna → `periodo_contable`** (para que los ejes y el slicer ordenen cronológicamente).

### 1.2 Etiquetas agregadas del cubo (importante para no equivocarse)

Cada dimensión tiene UNA fila `es_total = 1` por periodo, pero la etiqueta varía:

| tipo_indicador | nombre_campo de la fila total |
|---|---|
| completitud | `TOTAL_PERIODO` |
| validez | `TOTAL_PERIODO` |
| exactitud | `TOTAL` |
| unicidad | `policy_transaction_movement_sk` (fila única, no tiene detalle) |
| disponibilidad | `disponibilidad_sync` y `disponibilidad_regla4` (DOS filas, no comparables entre sí) |

Por eso las medidas filtran por `es_total = 1`, nunca por el texto `TOTAL`.

## 2. Medidas DAX

Crea estas medidas en la tabla `KPI_Cubo` (Modelado → Nueva medida). `porcentaje` ya viene en
escala 0–100 (99.5 = 99.5 %), por eso los formatos concatenan el símbolo `%` en vez de usar el
formato porcentaje de Power BI (que multiplicaría ×100).

```dax
% Calidad = AVERAGE(KPI_Cubo[porcentaje])

% Dimensión =
CALCULATE(AVERAGE(KPI_Cubo[porcentaje]), KPI_Cubo[es_total] = 1)

DQ Score =
CALCULATE(
    AVERAGE(KPI_Cubo[porcentaje]),
    KPI_Cubo[es_total] = 1,
    KPI_Cubo[tipo_indicador] <> "disponibilidad"
)

Registros Malos = SUM(KPI_Cubo[cantidad_mala])

Registros Evaluados = SUM(KPI_Cubo[total_registros])

Campos Evaluados =
COALESCE(
    CALCULATE(DISTINCTCOUNT(KPI_Cubo[nombre_campo]), KPI_Cubo[es_total] = 0),
    1   -- Unicidad no tiene filas de detalle: cuenta como 1 campo
)

Fecha de Cálculo = MAX(KPI_Cubo[fecha_calculo])
```

**`DQ Score`** replica exactamente el "Comportamiento general" del HTML: promedio simple de las 4
dimensiones comparables (Completitud, Exactitud, Unicidad, Validez), **excluyendo Disponibilidad**,
que es informativa.

### 2.1 Variación vs. periodo anterior (las flechas ▲/▼ de los anillos)

El periodo anterior se busca por orden, no restando 1 (202601 − 1 no es 202512):

```dax
Periodo Anterior =
VAR p = MAX(KPI_Cubo[periodo_contable])
RETURN
CALCULATE(
    MAX(KPI_Cubo[periodo_contable]),
    REMOVEFILTERS(KPI_Cubo[periodo_contable], KPI_Cubo[Periodo (texto)]),
    KPI_Cubo[periodo_contable] < p
)

% Dimensión Anterior =
VAR pa = [Periodo Anterior]
RETURN
CALCULATE(
    [% Dimensión],
    REMOVEFILTERS(KPI_Cubo[periodo_contable], KPI_Cubo[Periodo (texto)]),
    KPI_Cubo[periodo_contable] = pa
)

Δ vs Anterior =
VAR ant = [% Dimensión Anterior]
RETURN IF(NOT ISBLANK(ant), [% Dimensión] - ant)

Δ Texto =
VAR d = [Δ vs Anterior]
RETURN
IF(ISBLANK(d), "—",
   IF(d >= 0, "▲ +" & FORMAT(d, "0.00"), "▼ " & FORMAT(d, "0.00"))
   & " pp vs " & FORMAT([Periodo Anterior], "0"))

Color Delta = IF([Δ vs Anterior] >= 0, "#006300", "#d03b3b")
```

Para el DQ Score, el mismo patrón cambiando la medida base:

```dax
Δ DQ Texto =
VAR pa = [Periodo Anterior]
VAR ant = CALCULATE([DQ Score],
              REMOVEFILTERS(KPI_Cubo[periodo_contable], KPI_Cubo[Periodo (texto)]),
              KPI_Cubo[periodo_contable] = pa)
VAR d = [DQ Score] - ant
RETURN
IF(ISBLANK(ant), "—",
   IF(d >= 0, "▲ +" & FORMAT(d, "0.00"), "▼ " & FORMAT(d, "0.00"))
   & " pp vs " & FORMAT(pa, "0"))
```

### 2.2 Semáforo de 4 bandas

El HTML usa 4 estados con umbrales distintos para los dos chequeos de Disponibilidad. El tema JSON
solo trae 3 colores, así que la 4.ª banda (GRAVE, `#ec835a`) se aplica con estas medidas vía
formato condicional:

```dax
Estado =
VAR v = [% Calidad]
VAR clave = SELECTEDVALUE(KPI_Cubo[nombre_campo])
VAR uB = SWITCH(clave, "disponibilidad_sync", 97, "disponibilidad_regla4", 80, 99)
VAR uA = SWITCH(clave, "disponibilidad_sync", 90, "disponibilidad_regla4", 60, 97)
VAR uG = SWITCH(clave, "disponibilidad_sync", 80, "disponibilidad_regla4", 40, 90)
RETURN
SWITCH(TRUE(),
    ISBLANK(v), BLANK(),
    v >= uB, "BUENO",
    v >= uA, "ALERTA",
    v >= uG, "GRAVE",
    "CRÍTICO")

Color Semáforo =
SWITCH([Estado],
    "BUENO",   "#0ca30c",
    "ALERTA",  "#fab219",
    "GRAVE",   "#ec835a",
    "CRÍTICO", "#d03b3b",
    "#898781")
```

Umbrales (idénticos al HTML): generales BUENO ≥ 99 · ALERTA ≥ 97 · GRAVE ≥ 90 · CRÍTICO < 90;
`disponibilidad_sync` 97/90/80; `disponibilidad_regla4` 80/60/40. Target de referencia: **95**.

### 2.3 Errores y Pareto (página 4)

```dax
% del Total Errores =
100 * DIVIDE([Registros Malos],
             CALCULATE([Registros Malos], ALLSELECTED(KPI_Cubo)))

% Errores Acumulado =
VAR errActual = [Registros Malos]
VAR total = CALCULATE([Registros Malos], ALLSELECTED(KPI_Cubo[nombre_campo]))
VAR acum =
    CALCULATE([Registros Malos],
        FILTER(ALLSELECTED(KPI_Cubo[nombre_campo]),
               CALCULATE([Registros Malos]) >= errActual))
RETURN 100 * DIVIDE(acum, total)
```

### 2.4 Tendencia (página 3)

```dax
Tendencia Estado =
VAR d = [Δ vs Anterior]
RETURN
SWITCH(TRUE(),
    ISBLANK(d), "— sin anterior",
    ABS(d) < 0.005, "● Estable",
    d > 0, "▲ Mejora",
    "▼ Baja")
```

## 3. Tema y marca (hazlo antes de armar visuales)

1. **Vista → Temas → Buscar temas** → `reports/tema_hdi_powerbi.json`
   (verde marca `#0f7a3c`/`#8dc63f`, semáforo, series categóricas, fondos claros).
2. Fondo de página: `#f4f4f1` (Formato de página → Lienzo).
3. **Encabezado** en cada página: imagen `HDI_Seguros.png` (Insertar → Imagen) a la izquierda +
   cuadro de texto centrado "**KPIs Calidad de Datos — CDP Primas**" en verde `#0f7a3c`.
4. Colores fijos por serie (en cada visual con leyenda `Dimensión`):
   Completitud `#2a78d6` · Exactitud `#eda100` · Unicidad `#4a3aa7` · Validez `#eb6834` ·
   Target/rojo `#d03b3b`.

## 4. Slicer de periodo (común a todas las páginas)

1. **Segmentación de datos** con `Periodo (texto)`; estilo **Lista desplegable**; Configuración →
   Selección → **Selección única**. Gracias a "Ordenar por columna" queda en orden cronológico y el
   mes actual aparece como "202607 (en curso)".
2. **Ver → Sincronizar segmentaciones** → activa el slicer en las páginas 1–4 (la 5 no lo necesita).
3. **Clave — editar interacciones:** los gráficos de tendencia muestran TODOS los periodos aunque el
   slicer tenga uno seleccionado (igual que el HTML). Con el slicer seleccionado:
   **Formato → Editar interacciones** → en el gráfico "Tendencia DQ Score" (página 1) y en
   "Evolución por dimensión" (página 3) marca **Ninguna** (⊘). Todo lo demás sí se filtra.

## 5. Página 1 — Resumen ejecutivo

**a) Cinco medidores (visual Medidor / Gauge).** Para cada dimensión:
- Campo Valor = `% Dimensión`; Mín 0, Máx 100; Destino 95.
- Filtros del visual: `tipo_indicador` = (completitud / exactitud / unicidad / validez) **y** `es_total` = 1.
- Color de relleno: Formato → Colores → fx → **Valor de campo** → `Color Semáforo`
  (así el anillo se pinta según el semáforo, como en el HTML).
- El 5.º medidor es el **DQ Score**: Valor = `DQ Score` (sin filtro de tipo_indicador), un poco más
  grande, relleno fijo verde marca `#0f7a3c`, y detrás un rectángulo (Insertar → Formas) con fondo
  verde suave para destacarlo, como el HTML.

**b) Deltas bajo cada medidor:** una **Tarjeta** por medidor con `Δ Texto` (la del DQ Score con
`Δ DQ Texto`), mismos filtros que su medidor, y color de fuente condicional fx → Valor de campo →
`Color Delta`. Otra tarjeta pequeña opcional con `Estado` y fondo `Color Semáforo` hace de "chip".

**c) Disponibilidad (informativa — no entra al DQ Score):** dos **Tarjetas** con `% Calidad`:
- una filtrada `nombre_campo = disponibilidad_sync` — subtítulo: "Sincronización tabla base vs.
  vista; ~98 % es esperado y normal, no una falla".
- otra filtrada `nombre_campo = disponibilidad_regla4` — subtítulo: "% de ramos con datos todos los
  días 1–15; porcentajes bajos son comunes (1 día faltante castiga el ramo)".
- A cada una, una tarjeta `Estado` al lado (recuerda: sus umbrales especiales ya están dentro de la
  medida). Enmárcalas con borde punteado (Formato → Efectos → Borde) para replicar el HTML.

**d) Tendencia del DQ Score:** **Gráfico de líneas**; eje X = `Periodo (texto)`, eje Y = `DQ Score`;
sin filtro de periodo (interacción en Ninguna, ver §4). Panel **Analítica** (lupa) → **Línea
constante Y = 95**, color `#d03b3b`, estilo discontinuo, etiqueta "Target 95". Eje Y acotado
(p. ej. 90–100) para que se lea la variación.

**e) Dimensiones vs. Target (reemplaza al radar):** **Gráfico de barras agrupadas** (horizontal);
eje Y = `Dimensión`, eje X = `% Dimensión`; filtros del visual: `es_total = 1` y
`tipo_indicador` ≠ disponibilidad. Analítica → línea constante X = 95 (Target, `#d03b3b`
discontinua). Rango del eje X 75–100 para imitar la escala del radar del HTML (anota en el
subtítulo "escala 75–100"). Colores de datos por dimensión (§3.4).

**f) Tabla semáforo:** visual **Tabla** con `Dimensión`, `% Dimensión`, `Campos Evaluados`,
`Registros Evaluados`, `% Calidad` (con **Barras de datos** en formato condicional) y `Estado`;
filtros `es_total = 1` y `tipo_indicador` ≠ disponibilidad. Formato condicional del fondo de la
columna `Estado`: fx → Valor de campo → `Color Semáforo`. Encabezado de tabla en verde `#0f7a3c`
con texto blanco (estilo del HTML).

## 6. Página 2 — Detalle por variable

**a) Tres tablas por dimensión** (Completitud, Validez, Exactitud — el mismo orden del HTML). Cada
una es un visual **Tabla** filtrado `tipo_indicador` = X y `es_total = 0`, ordenado por `porcentaje`
**ascendente** (peor primero), con columnas:
- `nombre_campo`, `% Calidad` con **Barras de datos**, `Registros Malos` (renombra el encabezado
  según la dimensión: Nulos / Inválidos / Inexactos, doble clic en el campo del visual) y `Estado`
  con fondo `Color Semáforo`.

**b) Tarjeta hero de Unicidad:** **Tarjeta** grande con `% Dimensión` filtrada
`tipo_indicador = unicidad`, subtítulo "policy_transaction_movement_sk sin duplicados", y al lado
`Registros Malos` (duplicados) y `Registros Evaluados`.

**c) Tabla combinada "Calidad por campo (todas las dimensiones)":** **Tabla** con `nombre_campo`,
`Dimensión`, `% Calidad`, `Registros Malos` y `Estado` (fondo `Color Semáforo`); filtro
`es_fila_error = 1`; ordenada por `% Calidad` ascendente. Es la lista de priorización de
remediación: lo primero de la lista es lo primero a remediar.

Alternativa compacta: una **Matriz** (filas `nombre_campo`, columnas `Dimensión`, valores
`% Calidad`, fondo condicional `Color Semáforo`) muestra todo el cruce campo × dimensión de una vez.

## 7. Página 3 — Tendencia e historia

**a) Evolución por dimensión:** **Gráfico de líneas**; eje X = `Periodo (texto)`, eje Y =
`% Dimensión`, **Leyenda** = `Dimensión`; filtros `es_total = 1` y `tipo_indicador` ≠ disponibilidad;
interacción del slicer en **Ninguna** (§4); Analítica → línea constante Y = 95 "Target"
(`#d03b3b`, discontinua); colores por serie (§3.4); eje Y acotado (p. ej. 95–100 o según tus datos).

**b) Variación periodo a periodo:** **Tabla** con `Dimensión`, `% Dimensión` (periodo actual),
`% Dimensión Anterior`, `Δ vs Anterior` y `Tendencia Estado`; filtros `es_total = 1` y
`tipo_indicador` ≠ disponibilidad. Esta tabla SÍ responde al slicer (compara el periodo
seleccionado contra el anterior).

## 8. Página 4 — Análisis de errores

Los tres visuales llevan el filtro **`es_fila_error = 1`** (evita el doble conteo de las filas
TOTAL, incluye la fila única de Unicidad y excluye Disponibilidad — misma lógica del HTML).

**a) Distribución por dimensión:** **Gráfico de anillos**; Valores = `Registros Malos`,
Leyenda = `Dimensión`; etiquetas de detalle con valor y porcentaje; colores por dimensión (§3.4).

**b) Top 10 de campos:** **Tabla** con `nombre_campo`, `Registros Malos` (con **Barras de datos**)
y `% del Total Errores`; filtro del visual sobre `nombre_campo` → tipo **N superior**, Mostrar 10,
Por valor `Registros Malos`; ordenada descendente.

**c) Pareto 80/20 (nativo):** **Gráfico de columnas agrupadas y líneas**;
- Eje X = `nombre_campo` (mismo filtro N superior = 10 por `Registros Malos`),
- Columnas (eje Y) = `% del Total Errores`,
- Línea (eje Y secundario) = `% Errores Acumulado`,
- Ordena por `Registros Malos` descendente; fija ambos ejes 0–100 y apaga el eje secundario
  ("un solo eje 0–100 %", como el HTML); etiquetas de datos encendidas en las columnas.

## 9. Página 5 — Información

Cuadros de texto en dos columnas (copiar/adaptar del HTML):

- **Nombre del reporte:** KPIs Calidad de Datos — CDP Primas.
  **Data Steward:** Karen Carvajal — Directora de Gobierno de Datos.
  **Data Owner:** Javier Gualdron — Director de Ingeniería de Datos.
  **Desarrollador:** Wilson Jerez — Analista Senior de Gobierno de Datos.
- **Esta versión (diferencia clave con el HTML):** lee el **cubo persistido** vía
  `co_sandbox_datos.vw_kpi_cubo_mensual_pbi`, poblado por `sp_kpi_cubo_mensual` /
  `sp_kpi_cubo_auto` (el HTML calcula al vuelo desde un notebook). Agrega una **Tarjeta** con
  `Fecha de Cálculo` — "Datos calculados el …" — que además indica el corte parcial del mes en curso.
- **Indicadores:** Completitud (% no nulos por campo obligatorio), Validez (formato/dominio por
  campo), Exactitud (valores dentro del dominio permitido), Unicidad (sin duplicados de
  `policy_transaction_movement_sk`), DQ Score (promedio simple de las 4 anteriores),
  Disponibilidad (informativa, fuera del DQ Score; sus 2 chequeos no son comparables entre sí).
- **Umbrales:** los de §2.2, más Target 95.
- **Notas metodológicas:** universo con filtro base compartido (`current_record_flag = 1`,
  `coverage_code ≠ 8888`, prima ≠ 0, iaxis sin unificado-total + as400); Disponibilidad no lo aplica
  a propósito; el cubo aplica a Exactitud el filtro compartido completo (desviación deliberada del
  SQL original — hallazgo #1 en `docs/Hallazgos y Estado del Proyecto.md`); `movement_type` excluido
  de Validez a propósito; periodos autodetectados, sin fechas quemadas.

## 10. Página 6 — Drill-down (obtención de detalles)

Réplica del modal del HTML ("clic en un anillo → en qué campos falla"):

1. Crea una página **"Detalle dimensión"**. En **Compilación de página → Obtención de detalles**,
   arrastra `Dimensión` (deja "Mantener todos los filtros" activado para conservar el periodo).
2. Contenido: título dinámico (Tarjeta con `SELECTEDVALUE(KPI_Cubo[Dimensión])`), y una **Tabla**
   con `nombre_campo`, `% Calidad`, `Registros Malos`, `Estado` (fondo `Color Semáforo`), filtro
   `es_total = 0`, ordenada por `% Calidad` ascendente. Añade tarjetas de resumen: `Campos
   Evaluados` y `Registros Malos` totales.
3. Uso: en la página 1, **clic derecho** sobre una fila de la tabla semáforo (o del anillo de la
   página 4) → **Obtención de detalles → Detalle dimensión**. Power BI pone solo el botón "←"
   (esquina superior izquierda, se usa con Ctrl+clic en Desktop) para volver.
4. Nota: los Medidores no exponen clic derecho de obtención de detalles de forma fiable; por eso el
   punto de entrada recomendado es la tabla semáforo (misma información que los anillos).

## 11. Publicar y programar la actualización

1. **Publicar** al área de trabajo de Power BI Service.
2. Configurar **puerta de enlace (gateway)** si el warehouse no es accesible desde la nube, y
   credenciales del origen PostgreSQL/Redshift.
3. **Actualización programada** del semantic model, alineada a cuándo corre
   `co_sandbox_datos.sp_kpi_cubo_auto()` en el warehouse (mientras no exista scheduler Glue/cron,
   ejecútalo manualmente y luego refresca el dataset; el SP es idempotente y re-procesa el mes en
   curso en cada corrida).
4. El slicer marcará "(en curso)" automáticamente al mes calendario actual; cuando el mes cierre y
   el SP procese el siguiente, todo se actualiza solo — sin periodos quemados.

## 12. Lista de verificación final (paridad con el HTML)

- [ ] 5 páginas + página de obtención de detalles.
- [ ] Slicer de periodo sincronizado, selección única, "(en curso)" en el mes actual.
- [ ] 4 medidores + DQ Score con color por semáforo y deltas ▲/▼ vs. periodo anterior.
- [ ] DQ Score promedia solo las 4 dimensiones comparables (Disponibilidad fuera).
- [ ] 2 tarjetas de Disponibilidad con sus umbrales especiales (97/90/80 y 80/60/40).
- [ ] Semáforo de 4 bandas (`#0ca30c` / `#fab219` / `#ec835a` / `#d03b3b`) vía `Color Semáforo`.
- [ ] Tendencias con línea Target 95 y sin filtro del slicer (interacciones editadas).
- [ ] Barras "dimensión vs Target" en lugar del radar (sin visuales de AppSource).
- [ ] Página de errores con `es_fila_error = 1`: anillo, Top 10 y Pareto (acumulado en línea).
- [ ] Tema `tema_hdi_powerbi.json` aplicado + logo `HDI_Seguros.png` + colores fijos por serie.
- [ ] Tarjeta `Fecha de Cálculo` (corte de datos del mes en curso).
- [ ] Publicado con refresh programado tras `sp_kpi_cubo_auto()`.
