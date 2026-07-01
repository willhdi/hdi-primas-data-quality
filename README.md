# Contexto y Plan de Apoyo — Proceso de Calidad de Cifras (Primas)

## 1. Resumen de la reunión

La reunión tuvo como objetivo hacer traspaso de conocimiento sobre el tablero de calidad de cifras de **primas**, construido inicialmente por Juan Rojas (Data QA - Outsourcing Kibernum), con participación de Paula Torres, Viviana Cañas y Wilson (tú).

Puntos clave discutidos:

- **Origen del tablero**: Juan desarrolló un Power BI que mide KPIs de calidad de datos sobre la fuente de primas, apoyado en un catálogo de campos donde se definían las reglas de negocio por indicador.
- **KPIs cubiertos inicialmente**: completitud, unicidad, validez y exactitud. Quedó pendiente el KPI de **disponibilidad**, que Juan no alcanzó a desarrollar.
- **Método de trabajo de Juan**: creaba querys independientes por cada KPI y las integraba manualmente al tablero. Los periodos contables estaban **quemados** (insertados a mano), cubriendo un rango tentativo de 6 meses hacia atrás.
- **Observación de Paula**: el tablero no debe tener periodos quemados; debe actualizarse automáticamente a medida que aparecen nuevos datos en las tablas fuente (ej. si cierra junio, el tablero debe reflejar junio sin intervención manual).
- **Limitación técnica identificada**: en el momento de construcción no existía un pase automatizado (Glue u otra plataforma), por lo que la actualización era manual.
- **Rol de Viviana**: tomó el tablero de Juan para mejorarlo visualmente — ajustó filtros y variables adicionales para dejarlo en un nivel de visualización más robusto y monitoreable.

## 2. Contexto del proceso (según el correo de Viviana Cañas)

- **Fuente a evaluar**: `gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement`
- **Indicadores a evaluar sobre esa vista**:
  1. Completitud
  2. Unicidad
  3. Exactitud
  4. Validez
  5. Integridad
  6. Disponibilidad
- **Requisito de granularidad**: la lógica (desde la fuente hasta la visualización) debe permitir evaluar los indicadores tanto a **nivel de campo** como a **nivel de periodo**.
- **Documentación de referencia**: las fórmulas/definiciones de cada indicador están en la *Política de Poblamiento y Calidad de Datos* (disponible con Paula).
- **Insumos que te comparten/compartirán**:
  - Archivo PBIX del tablero actual de primas (Juan Rojas).
  - Excel con las reglas definidas por indicador.
  - Excel adicional con especificaciones de construcción del tablero.
  - Queries de las tablas fuente usadas en el modelo actual.
- **Punto de contacto técnico**: Juan Rojas Amaya, quien conoce el desarrollo previo y puede dar accesos a las vistas.

## 3. Qué debes hacer / en qué debes apoyar

Como perfil de **Gobierno de Datos**, tu rol frente a este proceso es:

1. **Apropiarte de la lógica existente**
   - Revisar el PBIX de Juan y el Excel de reglas de negocio para entender cómo está calculado cada KPI actualmente.
   - Entender las querys que alimentan el tablero (te las compartirá Juan).

2. **Completar el indicador faltante**
   - Definir y construir la lógica del KPI de **disponibilidad**, que no fue desarrollado en la primera versión.

3. **Resolver el problema de automatización**
   - Diseñar/gestionar que los periodos contables dejen de estar quemados y se actualicen automáticamente a medida que llegan nuevos datos.
   - Esto probablemente implica coordinar con el equipo de datos la construcción de un pipeline (ej. Glue u otra herramienta) que refresque las tablas fuente sin intervención manual — un tema natural para gobierno de datos, ya que estandariza y da trazabilidad al proceso.

4. **Asegurar la granularidad requerida**
   - Validar que la solución permita ver los indicadores tanto por **campo** como por **periodo contable**, tal como lo pide el correo de Viviana.

5. **Alinear con la documentación oficial**
   - Contrastar la lógica implementada por Juan contra la Política de Poblamiento y Calidad de Datos (con Paula), para asegurar consistencia normativa/gobierno.

6. **Coordinación de stakeholders**
   - Juan Rojas → conocimiento técnico del desarrollo previo y accesos a las vistas.
   - Paula Torres → dueña del proceso / define reglas de negocio y política de calidad.
   - Viviana Cañas → encargada de la capa de visualización (Power BI) y de compartir los archivos oficiales.

## 4. Próximos pasos sugeridos

- [ ] Solicitar y revisar: PBIX, Excel de reglas, Excel de especificaciones y las queries fuente.
- [ ] Agendar sesión técnica con Juan para entender el detalle de cada query/KPI.
- [ ] Revisar la Política de Poblamiento y Calidad de Datos con Paula.
- [ ] Evaluar opciones de automatización de la carga de periodos (Glue u otra alternativa disponible en tu stack actual).
- [ ] Diseñar la lógica del KPI de disponibilidad.
- [ ] Validar con Viviana el estado actual de la visualización mejorada.
