# Guía: tablero de Calidad de Datos en Power BI

Réplica del tablero HTML (`reports/tablero_calidad_primas.html`) usando Power BI Desktop.
No reemplaza el HTML — es una vista alternativa que consume la misma fuente (`vw_kpi_cubo_mensual_pbi`).

## 1. Conectar los datos

1. Power BI Desktop → **Obtener datos** → **PostgreSQL** (Redshift usa el conector PostgreSQL).
2. Servidor/puerto/base del warehouse (los de siempre), esquema `co_sandbox_datos`.
3. Modo de datos: **Import** (recomendado — la vista es un agregado mensual pequeño; programa el refresh en el servicio Power BI, p. ej. diario o después de cada corrida de `sp_kpi_cubo_mensual`/`sp_kpi_cubo_auto`).
4. Selecciona la tabla `vw_kpi_cubo_mensual_pbi`. Trae los 5 indicadores en formato largo:
   `periodo_contable`, `tipo_indicador`, `nombre_campo`, `total_registros`, `cantidad_mala`, `porcentaje`, `es_total`, `fecha_calculo`.
5. En Power Query, confirma tipos: `periodo_contable` como **Texto** (es un YYYYMM, no fecha), `porcentaje` como **Decimal**, `es_total` como **Número entero**.

## 2. Medidas DAX (pega en la tabla `KPI_Cubo`)

```dax
Score DQ =
AVERAGEX(FILTER(KPI_Cubo, KPI_Cubo[es_total] = 1), KPI_Cubo[porcentaje])

% por Indicador =
AVERAGE(KPI_Cubo[porcentaje])

Registros Malos =
SUM(KPI_Cubo[cantidad_mala])

% Formateado =
FORMAT([% por Indicador], "0.0%")
```

## 3. Páginas y visuales sugeridos (calcando el HTML)

**Página "Resumen"**
- Slicer de `periodo_contable` arriba (equivalente al selector de periodo del HTML).
- Un visual **Gauge** por cada `tipo_indicador` (Completitud, Exactitud, Unicidad, Validez, Disponibilidad), filtrado con `es_total = 1`.
- Un Gauge adicional para la medida `Score DQ` (equivalente al "DQ Score" combinado del HTML).
- Colores: usa el tema `reports/tema_hdi_powerbi.json` (ver paso 4) — verde `#0ca30c` = bien, ámbar `#fab219` = alerta, rojo `#d03b3b` = crítico, igual que el semáforo del HTML.

**Página "Detalle por campo"**
- **Matriz**: filas `nombre_campo`, columnas `tipo_indicador`, valores `% por Indicador`.
- Formato condicional (reglas de fondo) con los mismos 3 colores de semáforo del HTML.

**Página "Tendencia"**
- **Gráfico de líneas**: eje X `periodo_contable`, valores `% por Indicador`, leyenda `tipo_indicador` (una línea por indicador, como el gráfico SVG del HTML).

## 4. Aplicar el tema de marca HDI

Vista → Temas → Explorar temas → **Examinar temas** → selecciona `reports/tema_hdi_powerbi.json`.
Contiene la misma paleta que el HTML: verde marca `#0f7a3c`/`#8dc63f`, semáforo `#0ca30c`/`#fab219`/`#d03b3b`, series categóricas `#2a78d6`/`#eda100`/`#4a3aa7`/`#eb6834`.

## 5. Publicar y programar refresh

1. Publicar al workspace de Power BI Service.
2. Configurar **gateway** de datos (si el warehouse no es accesible públicamente) y credenciales.
3. Programar actualización (Configuración del dataset → Actualización programada) alineada a cuándo corre `sp_kpi_cubo_auto`.
