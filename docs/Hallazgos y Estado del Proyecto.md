# Estado del proyecto — Calidad de Datos Primas

## Resumen simple (para el daily)

**Qué se hizo:**
- Se revisó todo el repositorio: los 5 KPIs (Completitud, Exactitud, Unicidad, Validez, Disponibilidad) y el catálogo oficial de reglas de negocio (Excel + CSV).
- Se organizó el repo en carpetas (`sql/` y `docs/`) para que sea más fácil de navegar — sin borrar ni modificar ningún archivo original.
- Se construyó **un solo procedimiento nuevo e independiente** (`sql/KPI Cubo Unificado.sql` → `sp_kpi_cubo_mensual` + `sp_kpi_cubo_auto`) que calcula los 5 indicadores en una sola tabla ("cubo", formato largo por `tipo_indicador` + `campo` + `periodo`), sin depender de que los 5 procedimientos/tablas originales existan o se ejecuten. Esta es la dirección hacia la que se quiere migrar: reemplazar los 5 por uno solo, una vez se valide que el cubo entrega lo mismo (o mejor) que el tablero actual.
- Ese mismo procedimiento único ya resuelve la detección automática de periodos pendientes (`sp_kpi_cubo_auto`), para dejar de tener que "quemar" el periodo a mano cada vez que cierra un mes.
- Se encontraron 3 pendientes/inconsistencias (detalle abajo) que requieren una decisión de negocio antes de tocar los archivos originales.

**Cómo se piensa solucionar:**
- El cubo único ya tiene la lógica lista en SQL; falta (a) validar que sus cifras cuadran contra el tablero actual, y (b) coordinar con el equipo de datos un disparador externo (Glue, cron, etc.) que ejecute `sp_kpi_cubo_auto()` solo cada mes — ese es el siguiente paso técnico fuera de este repo.
- El hallazgo #1 (filtro de Exactitud) ya quedó corregido *dentro del cubo nuevo* (ahí sí aplica `current_record_flag = 1` en Exactitud, igual que los demás); el archivo original `KPI Exactitud.sql` se deja intacto como respaldo, con la inconsistencia sin tocar.
- Los hallazgos #2 y #3 siguen sin resolver a propósito: necesitan validación de negocio (Paula Torres / Política de Poblamiento) antes de escribir cualquier lógica nueva.
- El KPI de Integridad sigue bloqueado hasta tener las reglas oficiales — no se puede inventar la lógica.

**Bloqueos actuales:**
- Falta la Política de Poblamiento y Calidad de Datos para poder definir el KPI de Integridad.
- Falta identificar cuál es la tabla ODS que se debe usar para completar las reglas de Exactitud sobre los campos `transaction_delta_*`.

---

## Hallazgos técnicos

### 1. `KPI Exactitud.sql` usa un universo base distinto al resto (corregido en el cubo nuevo, no en el original)
El CTE base de Exactitud no incluye el filtro `current_record_flag = 1`, a diferencia de Completitud, Unicidad y Validez (que sí lo tienen, y que es el filtro documentado como compartido entre los 4 KPIs). Esto significa que el archivo original de Exactitud calcula sobre un universo un poco más amplio (incluye registros no vigentes) que los demás KPIs.
- **Impacto:** los porcentajes de exactitud del archivo original podrían no ser directamente comparables con los de completitud/unicidad/validez para el mismo periodo.
- **Estado:** el archivo original `sql/KPI Exactitud.sql` se dejó intacto (no se modifica, por instrucción del usuario). En `sql/KPI Cubo Unificado.sql` (código nuevo) sí se aplicó el filtro completo, por lo que las cifras de exactitud del cubo pueden diferir levemente de las del archivo original para el mismo periodo — es esperado, no un error.

### 2. Reglas de Exactitud contra tabla ODS no implementadas
El catálogo de reglas (`docs/KPIs - REGLAS CALIDAD CDP Primas(Reglas KPIs Calidad).csv`) define reglas de exactitud para `transaction_delta_billed_premium_amount`, `transaction_delta_base_premium_amount` y `transaction_delta_commission_amount`, basadas en "Comparación con tabla ODS, deben contener el mismo valor". Ninguna de estas 3 reglas está implementada en `KPI Exactitud.sql` (que hoy solo valida `source_system`, `current_record_flag` y `receipt_type`).
- **Por qué no se implementó:** no está identificada en el repo cuál es la tabla ODS ni cómo se relaciona (llaves de cruce) con la vista de primas.

### 3. KPI de Integridad — bloqueado
No existe archivo para este indicador, y el catálogo de reglas tampoco tiene ninguna lógica definida en su columna de Integridad (está vacía para todos los campos). Es el sexto indicador mencionado en el alcance original (ver [README.md](../README.md)) pero nunca se llegó a definir.
- **Qué se necesita:** la Política de Poblamiento y Calidad de Datos (la tiene Paula Torres) para poder definir qué significa "integridad" para este dataset antes de escribir cualquier SQL.

---

## Avance 2026-08-12 — Alertas y disponibilidad por hora de carga

**Tarea 1 — Alertas de saldos + dimensiones (hecho).** Se creó `sql/vistas/03_vw_alertas_primas.sql` → vista única `co_sandbox_datos.vw_alertas_primas` (formato largo, semáforo Normal/Advertencia/Crítica) que reúne cuatro ámbitos: `saldo_ramo` (saldo diario de prima por ramo vs. día anterior, umbrales ±15%/±30% como el MoM), `dimension` (% de cumplimiento por dimensión desde el cubo, <95%/<90%), `disponibilidad` (regla 4, banda laxa propia) y `hora_carga`. **Integridad** aparece como fila con estado `Pendiente` (no se inventa cálculo). La lógica se replicó en `dq_primas_logica.py` y el notebook exporta `reports/alertas_primas.csv` + el panel `reports/alertas_primas.html`.

**Tarea 2 — Disponibilidad por hora de carga (hecho, verificado con diagnóstico).** Se creó `sql/vistas/02_vw_disponibilidad_hora_carga.sql` → `vw_disponibilidad_hora_carga`. Hallazgo al verificar la vista: existe la columna `load_ts` (timestamp con hora real); `transaction_accounting_ts` es contable y no sirve. **Decisión clave:** el indicador usa `MIN(load_ts)` por día, no `MAX` — el `MAX` se corre a "hoy" porque los registros viejos se reescriben en cargas posteriores (SCD/reprocesos), así que no refleja el arribo real. Con las cargas actuales de madrugada (~04:00–09:00), el SLA de las 11:00 am se cumple normalmente.

**Notas de diseño (no son bugs):**
- La banda de `disponibilidad` en `vw_alertas_primas` NO usa el 90/95 de las demás dimensiones a propósito: en regla 4 un solo día faltante condena un ramo, así que los % bajos son normales (si se aplicara 90/95 saldría casi siempre en Crítica).
- El panel de alertas del notebook (`alertas_primas.html`) es un artefacto aparte, autocontenido; las alertas también quedan embebidas en el payload del tablero principal para futura integración a una pestaña. La integración visual dentro de la SPA de 54KB se dejó pendiente por no poder ejecutar el notebook contra Redshift en esa sesión.

**Envío de alertas (Power Automate u otro canal): fuera de alcance por ahora** — `vw_alertas_primas` queda como capa base para conectarlo después.
