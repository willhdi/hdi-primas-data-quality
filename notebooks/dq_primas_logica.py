# -*- coding: utf-8 -*-
"""
dq_primas_logica — Fuente única de la lógica de negocio del workstream Primas.

Este módulo NO toca la base de datos ni pandas: solo define las reglas
(campos, dominios, formatos), los mapeos legibles y los *constructores* de los
SELECT. El notebook `cubo_unificado_runner.ipynb` lo importa
(`from dq_primas_logica import *`) y ejecuta el SQL en modo solo-lectura; así,
si cambias una regla aquí, el notebook (y sus tooltips) la reflejan sin duplicar.

Alineación con el warehouse: el equivalente desplegable es `sql/06_KPI_Cubo
Unificado.sql` (cubo) y `sql/07_primas_monto_mensual.sql` (serie de primas).
Ese SQL es un artefacto aparte (DDL/DML) — cuando cambies una regla acá,
replícala allá. `NOMBRE_NATURAL` refleja el CASE de `nombre_natural` de sql/06
y `CATEGORIA_RAMO` el CASE de `categoria_ramo` de sql/07.
"""

# =====================================================================
# Fuente de datos
# =====================================================================
VISTA_FUENTE = 'gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement'


# =====================================================================
# Filtro base compartido (Completitud / Exactitud / Unicidad / Validez)
# Disponibilidad NO lo aplica a propósito (ver CLAUDE.md).
# =====================================================================
def filtro_base(periodos_sql):
    """WHERE del universo DQ compartido para una lista de periodos (str '202601, 202602')."""
    return f'''accountable_period IN ({periodos_sql})
  AND current_record_flag = 1
  AND coverage_code <> 8888
  AND transaction_delta_billed_premium_amount <> 0
  AND (
        (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
        OR source_system = 'CO_as400'
      )'''


# Versión "documentada" (con placeholder legible) para el modal del tablero.
FILTRO_BASE_DOC = '''-- Universo DQ compartido (Completitud / Exactitud / Unicidad / Validez):
accountable_period IN (<periodos del tablero>)
  AND current_record_flag = 1
  AND coverage_code <> 8888
  AND transaction_delta_billed_premium_amount <> 0
  AND (
        (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
        OR source_system = 'CO_as400'
      )'''


# =====================================================================
# COMPLETITUD: % de no-nulos por campo (19 obligatorios + 3 con excepción por fuente)
# =====================================================================
CAMPOS_OBLIGATORIOS = [
    'source_system', 'accountable_period', 'coverage_code', 'branch_sk', 'product_code',
    'transaction_date_sk', 'policy_effective_date_sk', 'policy_expiration_date_sk',
    'inception_date_sk', 'transaction_type', 'transaction_effective_date_sk',
    'transaction_type_description', 'current_record_flag',
    'transaction_delta_billed_premium_amount', 'transaction_delta_commission_amount',
    'risk_number', 'policy_number', 'transaction_delta_billed_premium_amount_raw',
    'policy_transaction_movement_sk',
]


def sql_completitud(fb):
    nulls_simples = ',\n    '.join(
        f'SUM(CASE WHEN {c} IS NULL THEN 1 ELSE 0 END) AS {c}' for c in CAMPOS_OBLIGATORIOS
    )
    return f'''
select
    accountable_period as periodo_contable,
    count(*) as total_registros,
    {nulls_simples},
    -- Campos con excepciones por fuente (CO_as400 no los puebla):
    SUM(CASE WHEN sseguro IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS sseguro,
    SUM(CASE WHEN receipt_type IS NULL AND source_system <> 'CO_as400' THEN 1 ELSE 0 END) AS receipt_type,
    SUM(CASE
            WHEN (receipt_number IS NULL AND source_system <> 'CO_as400' AND receipt_type <> 'not-unificado')
              OR (receipt_type = 'not-unificado' AND receipt_number IS NOT NULL)
            THEN 1 ELSE 0
        END) AS receipt_number
from {VISTA_FUENTE}
where {fb}
group by 1
order by 1;
'''


# =====================================================================
# EXACTITUD: valores dentro del dominio permitido (3 reglas implementadas)
# =====================================================================
def sql_exactitud(fb):
    return f'''
select
    accountable_period as periodo_contable,
    count(*) as total_registros,
    SUM(CASE WHEN source_system IS NULL OR source_system NOT IN ('CO_iaxis', 'CO_as400') THEN 1 ELSE 0 END) AS source_system,
    SUM(CASE WHEN current_record_flag IS NULL OR current_record_flag NOT IN (0, 1) THEN 1 ELSE 0 END) AS current_record_flag,
    SUM(CASE WHEN receipt_type IS NULL OR receipt_type NOT IN ('not-unificado', 'unificado-detail', 'unificado-total') THEN 1 ELSE 0 END) AS receipt_type
from {VISTA_FUENTE}
where {fb}
group by 1
order by 1;
'''


# =====================================================================
# UNICIDAD: duplicados de policy_transaction_movement_sk dentro del universo
# =====================================================================
def sql_unicidad(fb):
    return f'''
with base as (
    select accountable_period as periodo_contable, policy_transaction_movement_sk
    from {VISTA_FUENTE}
    where {fb}
),
duplicados as (
    select periodo_contable, policy_transaction_movement_sk
    from base
    group by 1, 2
    having count(*) > 1
)
select
    b.periodo_contable,
    count(*) as total_registros,
    SUM(CASE WHEN d.policy_transaction_movement_sk IS NOT NULL THEN 1 ELSE 0 END) as cantidad_mala
from base b
left join duplicados d
  on d.periodo_contable = b.periodo_contable
 and d.policy_transaction_movement_sk = b.policy_transaction_movement_sk
group by 1
order by 1;
'''


# =====================================================================
# VALIDEZ: formato/dominio por campo (12 reglas).
# La condición describe al registro INVÁLIDO (si se cumple, suma 1 a cantidad_mala).
# movement_type está excluido a propósito (igual que en el sql/05 original).
# =====================================================================
REGLAS_VALIDEZ = {
    'source_system': "source_system IS NULL OR source_system = 'Unknown'",
    'coverage_code': "coverage_code IS NULL OR coverage_code = 'Unknown'",
    'product_code': (
        "product_code IS NULL OR product_code = 'Unknown' OR LENGTH(product_code) > 6 "
        "OR product_code LIKE '% %' OR product_code ~ '[^A-Za-z0-9]' "
        "OR (source_system = 'CO_iaxis' AND product_code ~ '[A-Za-z]')"
    ),
    'transaction_date_sk': "transaction_date_sk IS NULL OR transaction_date_sk::VARCHAR !~ '^[0-9]{8}$'",
    'transaction_type': "transaction_type IS NULL OR transaction_type = 'Unknown' OR LENGTH(transaction_type) > 2",
    'current_record_flag': "current_record_flag IS NULL OR current_record_flag NOT IN (0, 1)",
    'risk_number': "risk_number IS NULL OR risk_number = 'Unknown'",
    'policy_number': "policy_number IS NULL OR policy_number = 'Unknown'",
    'accountable_period': "accountable_period IS NULL OR LENGTH(accountable_period::VARCHAR) <> 6",
    'policy_effective_date_sk': "policy_effective_date_sk IS NULL OR LENGTH(policy_effective_date_sk::VARCHAR) <> 8",
    'inception_date_sk': "inception_date_sk IS NULL OR LENGTH(inception_date_sk::VARCHAR) <> 8",
    'transaction_effective_date_sk': "transaction_effective_date_sk IS NULL OR LENGTH(transaction_effective_date_sk::VARCHAR) <> 8",
}

# Explicación en lenguaje natural de cada regla de Validez (mismas llaves que REGLAS_VALIDEZ).
VALIDEZ_QUE_HACE = {
    'source_system': "No debe ser nulo ni traer el valor comodín 'Unknown'.",
    'coverage_code': "No debe ser nulo ni traer el valor comodín 'Unknown'.",
    'product_code': ("No nulo ni 'Unknown', máximo 6 caracteres, sin espacios ni caracteres especiales. "
                     "Las letras solo se aceptan en AS400: en iAxis el código de producto debe ser numérico."),
    'transaction_date_sk': 'Debe ser un entero con forma de fecha YYYYMMDD (exactamente 8 dígitos).',
    'transaction_type': "No nulo ni 'Unknown' y con máximo 2 caracteres (es un código corto).",
    'current_record_flag': 'Solo admite 0 (histórico) o 1 (vigente); cualquier otro valor o nulo es inválido.',
    'risk_number': "No debe ser nulo ni traer el valor comodín 'Unknown'.",
    'policy_number': "No debe ser nulo ni traer el valor comodín 'Unknown'.",
    'accountable_period': 'Debe tener exactamente 6 dígitos con forma YYYYMM (p. ej. 202606).',
    'policy_effective_date_sk': 'Debe tener exactamente 8 dígitos con forma YYYYMMDD.',
    'inception_date_sk': 'Debe tener exactamente 8 dígitos con forma YYYYMMDD.',
    'transaction_effective_date_sk': 'Debe tener exactamente 8 dígitos con forma YYYYMMDD.',
}
assert set(VALIDEZ_QUE_HACE) == set(REGLAS_VALIDEZ), 'VALIDEZ_QUE_HACE desalineado con REGLAS_VALIDEZ'


def sql_validez(fb):
    casos_validez = ',\n    '.join(
        f'SUM(CASE WHEN {regla} THEN 1 ELSE 0 END) AS {campo}'
        for campo, regla in REGLAS_VALIDEZ.items()
    )
    return f'''
select
    accountable_period as periodo_contable,
    count(*) as total_registros,
    {casos_validez}
from {VISTA_FUENTE}
where {fb}
group by 1
order by 1;
'''


# =====================================================================
# DISPONIBILIDAD: dos chequeos NO comparables entre sí (ver CLAUDE.md, sql/06 y sql/08).
# A propósito SIN el filtro base compartido; ambos usan SOLO la vista general.
# =====================================================================
def sql_disponibilidad_mes(periodos_sql, periodo_en_curso=None, dias_transcurridos=0):
    """(a) Cobertura de días del mes con movimientos, usando transaction_date_sk."""
    dias_mes = "EXTRACT(DAY FROM LAST_DAY(TO_DATE(CAST(periodo_contable AS VARCHAR), 'YYYYMM')))::INTEGER"
    dias_exig_expr = (
        f"CASE WHEN periodo_contable = {periodo_en_curso} THEN LEAST({dias_transcurridos}, {dias_mes}) ELSE {dias_mes} END"
        if periodo_en_curso else dias_mes
    )
    return f'''
with base as (
    select
        accountable_period            as periodo_contable,
        MOD(transaction_date_sk, 100) as dia
    from {VISTA_FUENTE}
    where accountable_period in ({periodos_sql})
      and transaction_date_sk is not null
      and transaction_date_sk / 100 = accountable_period   -- el movimiento pertenece al mes del periodo
),
esperados as (
    select periodo_contable, {dias_exig_expr} as dias_exigidos
    from (select distinct periodo_contable from base)
),
presentes as (
    select b.periodo_contable,
           count(distinct case when b.dia between 1 and e.dias_exigidos then b.dia end) as dias_con_datos
    from base b
    join esperados e on e.periodo_contable = b.periodo_contable
    group by b.periodo_contable
)
select
    e.periodo_contable,
    e.dias_exigidos                                   as total_registros,   -- dias exigidos del mes
    e.dias_exigidos - coalesce(pr.dias_con_datos, 0)  as cantidad_mala      -- dias sin movimientos
from esperados e
left join presentes pr on pr.periodo_contable = e.periodo_contable
order by 1;
'''


def sql_disponibilidad_regla4(periodos_sql, periodo_en_curso=None, dias_regla4_en_curso=15):
    """(b) % de ramos (product_code) con datos TODOS los días 1-15 del mes."""
    dias_exigidos_sql = (
        f'CASE WHEN periodo_contable = {periodo_en_curso} THEN {dias_regla4_en_curso} ELSE 15 END'
        if periodo_en_curso else '15'
    )
    return f'''
with base as (
    select cast(to_char(transaction_accounting_ts, 'YYYYMM') as integer) as periodo_contable,
           product_code,
           cast(substring(cast(transaction_date_sk as varchar), 7, 2) as integer) as dia
    from {VISTA_FUENTE}
    where cast(to_char(transaction_accounting_ts, 'YYYYMM') as integer) in ({periodos_sql})
),
ramos as (
    select periodo_contable, product_code,
           count(distinct case when dia between 1 and 15 then dia end) as dias_presentes
    from base
    group by 1, 2
)
select
    periodo_contable,
    count(*) as total_registros,                                        -- total de ramos
    SUM(CASE WHEN dias_presentes >= {dias_exigidos_sql} THEN 0 ELSE 1 END) as cantidad_mala  -- ramos con algun dia exigido faltante
from ramos
group by 1
order by 1;
'''


# =====================================================================
# SERIE DE PRIMAS: monto mensual (mismo universo que los KPIs).
# Equivalente read-only de sql/07_primas_monto_mensual.sql.
# =====================================================================
def sql_primas(fb):
    return f'''
select
    accountable_period as periodo_contable,
    source_system,
    count(*)                                                          as movimientos,
    count(distinct policy_number)                                    as polizas,
    sum(transaction_delta_billed_premium_amount)                     as prima_neta,
    sum(case when transaction_delta_billed_premium_amount > 0
             then transaction_delta_billed_premium_amount else 0 end) as prima_emitida,
    sum(case when transaction_delta_billed_premium_amount < 0
             then transaction_delta_billed_premium_amount else 0 end) as prima_anulada,
    sum(transaction_delta_commission_amount)                         as comision
from {VISTA_FUENTE}
where {fb}
group by 1, 2
order by 1, 2;
'''


# =====================================================================
# nombre_natural: resumen legible por nombre_campo (refleja el CASE de sql/06).
# =====================================================================
NOMBRE_NATURAL = {
    'source_system': 'Sistema fuente',
    'accountable_period': 'Periodo contable',
    'coverage_code': 'Código de cobertura',
    'branch_sk': 'Sucursal / comercial',
    'product_code': 'Código de producto (ramo)',
    'transaction_date_sk': 'Fecha del movimiento',
    'policy_effective_date_sk': 'Fecha de efectividad de póliza',
    'policy_expiration_date_sk': 'Fecha de vencimiento de póliza',
    'inception_date_sk': 'Fecha de inicio del contrato',
    'transaction_type': 'Tipo de transacción',
    'transaction_effective_date_sk': 'Fecha efectiva del movimiento',
    'transaction_type_description': 'Descripción del tipo de transacción',
    'current_record_flag': 'Marca de vigencia del registro',
    'transaction_delta_billed_premium_amount': 'Prima facturada (monto neto)',
    'transaction_delta_billed_premium_amount_raw': 'Prima facturada (valor bruto)',
    'transaction_delta_commission_amount': 'Comisión del movimiento',
    'risk_number': 'Número de riesgo',
    'policy_number': 'Número de póliza',
    'policy_transaction_movement_sk': 'Identificador del movimiento',
    'sseguro': 'Identificador de seguro (derivado del riesgo)',
    'receipt_type': 'Tipo de recibo',
    'receipt_number': 'Número de recibo',
    # Filas agregadas / de resumen
    'TOTAL_PERIODO': 'Total del periodo',
    'TOTAL': 'Total del periodo',
    'disponibilidad_mes': 'Disponibilidad del mes (días con datos)',
    'disponibilidad_regla4': 'Disponibilidad por ramo (días 1–15)',
}


def nombre_natural(campo):
    """Resumen legible del campo; si no está mapeado, devuelve el nombre técnico."""
    return NOMBRE_NATURAL.get(campo, campo)


# =====================================================================
# CATEGORIA_RAMO: agrupación de product_code en líneas de negocio
# (refleja el CASE de categoria_ramo de sql/07). Ver reports/ramos_product_description.csv.
# =====================================================================
CATEGORIA_RAMO = {
    # Autos
    **{c: 'Autos' for c in ['6031', '6033', '6034', '6035', '6036', '6038', '6039', '6041',
                            '6042', '6043', '6045', '6046', '6047', '6048', '6049', '6060',
                            '6061', '800004', '900731', '900753', '900792', '900795']},
    # Responsabilidad Civil
    **{c: 'Responsabilidad Civil' for c in ['10005', '111715', '12', '800007', '900752',
                                            '900775', 'DO1', 'LA1', 'LB', 'RC', 'RCL', 'RCM',
                                            'RCP', 'RCT', 'REO']},
    # Vida
    **{c: 'Vida' for c in ['462', '463', '6023', '6024', '6025', '6026', '6028', '6029',
                           '6052', '900762', '900771', 'GC', 'IF']},
    # Hogar
    **{c: 'Hogar' for c in ['10000', '10001', '10003', '410', '411', '6071', '900748',
                            '900754', '900758']},
    # Transporte / Navegación
    **{c: 'Transporte / Navegación' for c in ['10', '70107', '70108', '8092', '900777',
                                              '900778', 'TRM']},
    # Daños Materiales
    **{c: 'Daños Materiales' for c in ['19', '900744', '900746', '900747', '900774', 'IN', 'ST']},
    # Ingeniería
    **{c: 'Ingeniería' for c in ['11', '17', '18', '800008', '900745', '900779']},
    # Salud
    **{c: 'Salud' for c in ['E1', 'H1', 'RDH', 'SE', 'Z1']},
    # Cumplimiento
    **{c: 'Cumplimiento' for c in ['01', '10004', 'BO', 'JU']},
    # Manejo / Riesgos Financieros
    **{c: 'Manejo / Riesgos Financieros' for c in ['02', '22', '900751', '900776']},
    # Exequias
    **{c: 'Exequias' for c in ['396', '900719', '900720', '900721']},
    # PYME / Multiriesgo
    **{c: 'PYME / Multiriesgo' for c in ['10024', '900742', 'PY']},
    # Accidentes Personales
    **{c: 'Accidentes Personales' for c in ['7467', '7468', '7469']},
    # SOAT
    **{c: 'SOAT' for c in ['368', '900730']},
    # Asistencias
    **{c: 'Asistencias' for c in ['ADU', 'T1']},
    # Agropecuario / Aviación
    '900793': 'Agropecuario',
    '900794': 'Aviación',
    # Otros (desempleo, coaseguro aceptado, global protection)
    **{c: 'Otros' for c in ['800020', '900765', '900780', 'LGP']},
}


def categoria_ramo(product_code):
    """Categoría de negocio del ramo; 'Sin clasificar' si no está mapeado."""
    return CATEGORIA_RAMO.get(str(product_code).strip(), 'Sin clasificar')


# =====================================================================
# Documentación de campos y participación en reglas DQ (para tooltips del tablero).
# =====================================================================
DICCIONARIO_CAMPOS = {
    # ---- Identificadores / llaves surrogate (las *_sk apuntan a dimensiones; -1 = no aplica / no informado) ----
    'policy_transaction_movement_sk': 'Llave única (surrogate) del movimiento de prima. Es la llave que Unicidad valida contra duplicados.',
    'source_system': "Sistema origen del registro: 'CO_iaxis' (iAxis) o 'CO_as400' (AS/400).",
    'audit_transaction_id': 'Identificador de auditoría de la transacción en el sistema origen (trazabilidad).',
    'customer_sk': 'Llave surrogate del cliente (tomador).',
    'quote_sk': 'Llave surrogate de la cotización; -1 = no aplica / no informado.',
    'policy_sk': 'Llave surrogate de la póliza.',
    'risk_sk': 'Llave surrogate del riesgo asegurado.',
    'policy_item_sk': 'Llave surrogate del ítem/objeto asegurado dentro de la póliza.',
    'insured_sk': 'Llave surrogate del asegurado.',
    'vehicle_sk': 'Llave surrogate del vehículo (ramos de autos); -1 = no aplica.',
    'coverage_sk': 'Llave surrogate de la cobertura.',
    'producer_sk': 'Llave surrogate del intermediario / productor.',
    'branch_sk': 'Llave surrogate de la sucursal.',
    'product_sk': 'Llave surrogate del producto.',
    'lob_sk': 'Llave surrogate de la línea de negocio (Line of Business).',
    # ---- Identificadores de negocio ----
    'risk_id': 'Identificador del riesgo en el sistema origen.',
    'sseguro': 'Identificador interno del seguro en iAxis. CO_as400 no lo puebla (excepción por fuente en Completitud).',
    'risk_number': 'Número del riesgo dentro de la póliza.',
    'policy_number': 'Número de la póliza.',
    'coverage_code': 'Código de la cobertura. El código 8888 se excluye del universo DQ (filtro base).',
    'product_code': 'Código del producto/ramo. En CO_iaxis debe ser numérico; letras solo se aceptan en CO_as400 (regla de Validez). Es el "ramo" de Disponibilidad regla 4.',
    # ---- Fechas como enteros YYYYMMDD / YYYYMM ----
    'transaction_date_sk': 'Fecha de la transacción, entero con forma YYYYMMDD.',
    'policy_effective_date_sk': 'Inicio de vigencia de la póliza (YYYYMMDD).',
    'policy_expiration_date_sk': 'Fin de vigencia de la póliza (YYYYMMDD).',
    'inception_date_sk': 'Fecha de inicio original (incepción) de la relación/póliza (YYYYMMDD).',
    'transaction_effective_date_sk': 'Inicio de vigencia del movimiento (YYYYMMDD).',
    'transaction_expiration_date_sk': 'Fin de vigencia del movimiento (YYYYMMDD).',
    'accountable_period': 'Periodo contable del movimiento, entero YYYYMM (p. ej. 202606). Es el periodo_contable por el que se cortan todos los KPIs.',
    # ---- Transacción / movimiento ----
    'transaction_type': 'Código del tipo de transacción (emisión, endoso, cancelación, …).',
    'transaction_type_description': 'Descripción legible del tipo de transacción.',
    'movement_type': 'Tipo de movimiento contable. Excluido de Validez a propósito (igual que en el SQL original).',
    'receipt_type': "Tipo de recibo: 'not-unificado', 'unificado-detail' o 'unificado-total'. Los 'unificado-total' de iAxis se excluyen del universo para no duplicar prima.",
    'receipt_number': 'Número del recibo. Completitud le aplica reglas por fuente (CO_as400 y los not-unificado no lo llevan).',
    'transaction_accounting_ts': 'Fecha/hora contable de la transacción (timestamp).',
    'load_ts': 'Fecha/hora en que el registro se cargó al DWH.',
    'performer_login': 'Usuario/proceso que ejecutó la transacción en el origen.',
    'creator_login': 'Usuario/proceso que creó el registro en el origen.',
    'current_record_flag': 'Bandera de vigencia (SCD): 1 = versión vigente del registro, 0 = histórica. Todo el DQ filtra por 1.',
    # ---- Montos de prima ("delta" = lo que aporta ESTE movimiento; "_raw" = valor crudo del origen) ----
    'transaction_delta_billed_premium_amount': 'Delta de prima facturada del movimiento. El universo DQ exige que sea ≠ 0 (filtro base).',
    'transaction_delta_billed_premium_amount_raw': 'Prima facturada del movimiento sin transformar, tal como llegó del origen.',
    'transaction_delta_net_written_premium_amount': 'Delta de prima neta emitida.',
    'transaction_delta_net_written_premium_amount_raw': 'Prima neta emitida sin transformar (valor crudo del origen).',
    'transaction_delta_base_premium_amount': 'Delta de prima base (sin impuestos ni recargos).',
    'transaction_delta_base_annual_premium_amount': 'Delta de prima base anualizada.',
    'transaction_delta_commission_amount': 'Delta de comisión del intermediario.',
    'transaction_delta_commission_amount_raw': 'Comisión sin transformar (valor crudo del origen).',
    'annual_premium': 'Prima anual asociada a la póliza/riesgo.',
    # ---- Impuestos y contribuciones ----
    'transaction_delta_total_tax_amount': 'Delta del total de impuestos del movimiento (suma de los componentes).',
    'transaction_delta_concierge_tax_amount': 'Delta de impuesto/tasa "concierge" (componente específico por país/producto).',
    'transaction_delta_clea_tax_amount': 'Delta de impuesto/tasa CLEA (componente específico por país/producto).',
    'transaction_delta_fng_tax_amount': 'Delta de contribución FNG (componente específico por país/producto).',
    'transaction_delta_ips_tax_amount': 'Delta de impuesto/tasa IPS (componente específico por país/producto).',
    'transaction_delta_ie_tax_amount': 'Delta de impuesto/tasa IE (componente específico por país/producto).',
    'transaction_delta_ipt_tax_amount': 'Delta de impuesto sobre la prima (IPT — Insurance Premium Tax).',
    'transaction_delta_miicf_tax_amount': 'Delta de impuesto/tasa MIICF (componente específico por país/producto).',
    'transaction_delta_compens_fund_tax_amount': 'Delta de contribución a fondo de compensación.',
    'transaction_delta_statutory_tax_amount': 'Delta de impuesto/contribución estatutaria.',
    'transaction_delta_statutory_ie_tax_amount': 'Delta de impuesto/contribución estatutaria IE.',
    'transaction_delta_consorcio_occupant_tax_amount': 'Delta de tasa de consorcio / ocupantes (componente específico por país/producto).',
    'transaction_delta_selo_tax_amount': 'Delta de impuesto de estampilla ("selo").',
    'transaction_delta_selo_dac_tax_amount': 'Delta de impuesto de estampilla DAC ("selo DAC").',
    # ---- Tasas / fees ----
    'transaction_delta_uninsured_auto_fund_fee_amount': 'Delta de contribución al fondo de vehículos no asegurados.',
    'transaction_delta_road_safety_fee_amount': 'Delta de tasa de seguridad vial.',
    'transaction_delta_medical_emergency_fund_fee_amount': 'Delta de contribución al fondo de emergencias médicas.',
    'transaction_delta_green_card_fee_amount': 'Delta de tasa de carta verde (cobertura fronteriza).',
}

# En qué reglas DQ participa cada campo (espejo de la sección de cálculo).
USO_DQ = {
    'completitud': [
        'source_system', 'accountable_period', 'coverage_code', 'branch_sk', 'product_code',
        'transaction_date_sk', 'policy_effective_date_sk', 'policy_expiration_date_sk',
        'inception_date_sk', 'transaction_type', 'transaction_effective_date_sk',
        'transaction_type_description', 'current_record_flag',
        'transaction_delta_billed_premium_amount', 'transaction_delta_commission_amount',
        'risk_number', 'policy_number', 'transaction_delta_billed_premium_amount_raw',
        'policy_transaction_movement_sk', 'sseguro', 'receipt_type', 'receipt_number',
    ],
    'exactitud': ['source_system', 'current_record_flag', 'receipt_type'],
    'validez': list(REGLAS_VALIDEZ.keys()),
    'unicidad': ['policy_transaction_movement_sk'],
    'disponibilidad (regla 4)': ['product_code', 'transaction_date_sk'],
}
EN_FILTRO_BASE = ['accountable_period', 'current_record_flag', 'coverage_code',
                  'transaction_delta_billed_premium_amount', 'source_system', 'receipt_type']


# =====================================================================
# REGLAS_DQ: documentación por dimensión para el modal del tablero.
# Se arma desde las MISMAS variables que generan los SELECT, así el SQL que se
# muestra nunca se desalinea del que se ejecuta.
# =====================================================================
_UNIVERSO_DOC = ('Movimientos del periodo con current_record_flag = 1 (versión vigente), cobertura '
                 'distinta de 8888, prima facturada distinta de 0, y recibos de iAxis que no sean '
                 '«unificado-total» (para no duplicar prima); AS400 entra completo.')


def construir_reglas_dq():
    """Estructura de documentación (dict) que alimenta el modal del tablero HTML."""
    return {
        'completitud': {
            'explicacion': ('Por cada campo obligatorio se cuentan los registros del universo filtrado donde el '
                            'campo viene nulo (cantidad_mala = «Nulos»). El % del campo es 100 × (1 − nulos / '
                            'total_registros) y el anillo muestra el promedio simple de todos los campos '
                            '(fila TOTAL_PERIODO). Tres campos tienen excepciones por fuente porque AS400 no los '
                            'puebla: sseguro, receipt_type y receipt_number.'),
            'universo': _UNIVERSO_DOC,
            'universo_sql': FILTRO_BASE_DOC,
            'reglas': {
                **{
                    c: {
                        'que_hace': 'El campo no debe venir nulo en ningún movimiento del universo filtrado.',
                        'sql': f'SUM(CASE WHEN {c} IS NULL THEN 1 ELSE 0 END) AS {c}',
                    }
                    for c in CAMPOS_OBLIGATORIOS
                },
                'sseguro': {
                    'que_hace': ('Solo se exige en iAxis: AS400 no maneja el identificador interno sseguro, '
                                 'así que sus nulos no se castigan.'),
                    'sql': ("SUM(CASE WHEN sseguro IS NULL AND source_system <> 'CO_as400' "
                            'THEN 1 ELSE 0 END) AS sseguro'),
                },
                'receipt_type': {
                    'que_hace': 'Solo se exige en iAxis: AS400 no puebla el tipo de recibo.',
                    'sql': ("SUM(CASE WHEN receipt_type IS NULL AND source_system <> 'CO_as400' "
                            'THEN 1 ELSE 0 END) AS receipt_type'),
                },
                'receipt_number': {
                    'que_hace': ('Regla doble: (a) en iAxis, los recibos que no son «not-unificado» deben traer '
                                 'número de recibo; (b) al revés, un recibo «not-unificado» NO debe traer número '
                                 '(si lo trae, también cuenta como error).'),
                    'sql': """SUM(CASE
        WHEN (receipt_number IS NULL AND source_system <> 'CO_as400' AND receipt_type <> 'not-unificado')
          OR (receipt_type = 'not-unificado' AND receipt_number IS NOT NULL)
        THEN 1 ELSE 0
    END) AS receipt_number""",
                },
            },
        },
        'exactitud': {
            'explicacion': ('Cada campo debe traer valores dentro de su dominio permitido (lista cerrada de '
                            'valores válidos), no solo venir informado. Hay 3 reglas implementadas; las reglas '
                            'del original que comparan montos contra la tabla ODS siguen sin implementar '
                            '(hallazgo #2 del doc de hallazgos). A diferencia del sql/03 original, aquí SÍ se '
                            'aplica el filtro compartido completo con current_record_flag = 1 — desviación '
                            'deliberada documentada como hallazgo #1.'),
            'universo': _UNIVERSO_DOC,
            'universo_sql': FILTRO_BASE_DOC,
            'reglas': {
                'source_system': {
                    'que_hace': "El sistema origen solo puede ser 'CO_iaxis' o 'CO_as400'; nulo u otro valor es inexacto.",
                    'sql': ("SUM(CASE WHEN source_system IS NULL OR source_system NOT IN ('CO_iaxis', 'CO_as400') "
                            'THEN 1 ELSE 0 END) AS source_system'),
                },
                'current_record_flag': {
                    'que_hace': 'La bandera de vigencia solo puede ser 0 o 1; nulo u otro valor es inexacto.',
                    'sql': ('SUM(CASE WHEN current_record_flag IS NULL OR current_record_flag NOT IN (0, 1) '
                            'THEN 1 ELSE 0 END) AS current_record_flag'),
                },
                'receipt_type': {
                    'que_hace': ("El tipo de recibo solo puede ser 'not-unificado', 'unificado-detail' o "
                                 "'unificado-total'; nulo u otro valor es inexacto."),
                    'sql': ("SUM(CASE WHEN receipt_type IS NULL OR receipt_type NOT IN "
                            "('not-unificado', 'unificado-detail', 'unificado-total') "
                            'THEN 1 ELSE 0 END) AS receipt_type'),
                },
            },
        },
        'unicidad': {
            'explicacion': ('La llave del movimiento (policy_transaction_movement_sk) no debe repetirse dentro '
                            'del periodo en el universo filtrado. cantidad_mala («Duplicados») cuenta TODOS los '
                            'registros que participan en un duplicado (si una llave aparece 2 veces, suma 2). '
                            '% = 100 × (1 − duplicados / total_registros); es una sola regla por periodo.'),
            'universo': _UNIVERSO_DOC,
            'universo_sql': FILTRO_BASE_DOC,
            'reglas': {
                'policy_transaction_movement_sk': {
                    'que_hace': ('Se agrupa por periodo + llave; las llaves con más de una fila son duplicados '
                                 'y todos sus registros cuentan como malos.'),
                    'sql': """with base as (
    select accountable_period as periodo_contable, policy_transaction_movement_sk
    from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    where <FILTRO_BASE>
),
duplicados as (
    select periodo_contable, policy_transaction_movement_sk
    from base
    group by 1, 2
    having count(*) > 1
)
select
    b.periodo_contable,
    count(*) as total_registros,
    SUM(CASE WHEN d.policy_transaction_movement_sk IS NOT NULL THEN 1 ELSE 0 END) as cantidad_mala
from base b
left join duplicados d
  on d.periodo_contable = b.periodo_contable
 and d.policy_transaction_movement_sk = b.policy_transaction_movement_sk
group by 1""",
                },
            },
        },
        'validez': {
            'explicacion': ('Cada campo debe cumplir su formato o dominio (longitudes, formas YYYYMMDD/YYYYMM, '
                            'caracteres permitidos, valores comodín prohibidos). La condición del CASE describe '
                            'al registro INVÁLIDO: si se cumple, suma 1 a cantidad_mala («Inválidos»). '
                            'movement_type está excluido a propósito, igual que en el sql/05 original.'),
            'universo': _UNIVERSO_DOC,
            'universo_sql': FILTRO_BASE_DOC,
            'reglas': {
                campo: {
                    'que_hace': VALIDEZ_QUE_HACE[campo],
                    'sql': f'SUM(CASE WHEN {regla} THEN 1 ELSE 0 END) AS {campo}',
                }
                for campo, regla in REGLAS_VALIDEZ.items()
            },
        },
        'dq': {
            'explicacion': ('Promedio simple de las 4 dimensiones comparables (Completitud, Exactitud, Unicidad '
                            'y Validez), tomando la fila TOTAL de cada una en el periodo seleccionado. '
                            'Disponibilidad no entra al DQ Score porque sus dos chequeos no son comparables '
                            'con el resto (miden sincronización y llegada de datos, no calidad campo a campo).'),
        },
        'disponibilidad_mes': {
            'que_hace': ('Usando transaction_date_sk (fecha del movimiento) sobre la MISMA vista, verifica '
                         'que haya llegado data del mes: cuenta cuantos dias del mes tuvieron al menos un '
                         'movimiento. cantidad_mala son los dias del mes SIN movimientos. Para el mes anterior '
                         '(ultimo cerrado) confirma directamente que si hay data del mes. No usa la tabla base '
                         'gde_adp_dwh: solo la vista general. Al mes en curso solo se le exigen los dias ya '
                         'transcurridos; fines de semana/festivos sin movimientos hacen que <100% sea normal.'),
            'sql': """with base as (
    select accountable_period as periodo_contable,
           MOD(transaction_date_sk, 100) as dia
    from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    where accountable_period in (<periodos>)
      and transaction_date_sk is not null
      and transaction_date_sk / 100 = accountable_period   -- el movimiento pertenece al mes
),
esperados as (   -- dias exigidos: dias del mes (cerrado) o transcurridos (mes en curso)
    select periodo_contable,
           extract(day from last_day(to_date(cast(periodo_contable as varchar),'YYYYMM'))) as dias_exigidos
    from (select distinct periodo_contable from base)
),
presentes as (
    select b.periodo_contable,
           count(distinct case when b.dia between 1 and e.dias_exigidos then b.dia end) as dias_con_datos
    from base b join esperados e on e.periodo_contable = b.periodo_contable
    group by b.periodo_contable
)
select e.periodo_contable,
       e.dias_exigidos as total_registros,
       e.dias_exigidos - coalesce(pr.dias_con_datos,0) as cantidad_mala
from esperados e left join presentes pr on pr.periodo_contable = e.periodo_contable""",
        },
        'disponibilidad_regla4': {
            'que_hace': ('Por cada ramo (product_code) verifica que hayan llegado datos TODOS los días 1 a 15 '
                         'del mes (día = posición 7-8 de transaction_date_sk). Un ramo con un solo día faltante '
                         'ya cuenta como malo, por eso los porcentajes bajos son comunes y no significan que '
                         'falte la mayoría de los datos. Al mes en curso solo se le exigen los días ya '
                         'transcurridos; a los meses cerrados, los 15 completos. También va SIN el filtro base.'),
            'sql': """with base as (
    select cast(to_char(transaction_accounting_ts, 'YYYYMM') as integer) as periodo_contable,
           product_code,
           cast(substring(cast(transaction_date_sk as varchar), 7, 2) as integer) as dia
    from gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
    where cast(to_char(transaction_accounting_ts, 'YYYYMM') as integer) in (<periodos>)
),
ramos as (
    select periodo_contable, product_code,
           count(distinct case when dia between 1 and 15 then dia end) as dias_presentes
    from base
    group by 1, 2
)
select
    periodo_contable,
    count(*) as total_registros,   -- total de ramos
    SUM(CASE WHEN dias_presentes >= <dias exigidos: 15, o los transcurridos si el mes está en curso>
        THEN 0 ELSE 1 END) as cantidad_mala
from ramos
group by 1""",
        },
    }
