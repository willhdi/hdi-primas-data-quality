SELECT
    TO_DATE(m.accountable_period::VARCHAR, 'YYYYMM') AS periodo_fecha,
    CASE TRIM(m.product_code)
        -- >>> AUTOGEN:categoria_ramo (generado por notebooks/generar_sql.py desde dq_primas_logica.CATEGORIA_RAMO — no editar a mano) <<<
        -- Autos
        WHEN '6031' THEN 'Autos' WHEN '6033' THEN 'Autos' WHEN '6034' THEN 'Autos'
        WHEN '6035' THEN 'Autos' WHEN '6036' THEN 'Autos' WHEN '6038' THEN 'Autos'
        WHEN '6039' THEN 'Autos' WHEN '6041' THEN 'Autos' WHEN '6042' THEN 'Autos'
        WHEN '6043' THEN 'Autos' WHEN '6045' THEN 'Autos' WHEN '6046' THEN 'Autos'
        WHEN '6047' THEN 'Autos' WHEN '6048' THEN 'Autos' WHEN '6049' THEN 'Autos'
        WHEN '6060' THEN 'Autos' WHEN '6061' THEN 'Autos' WHEN '800004' THEN 'Autos'
        WHEN '900731' THEN 'Autos' WHEN '900753' THEN 'Autos' WHEN '900792' THEN 'Autos'
        WHEN '900795' THEN 'Autos'
        -- Responsabilidad Civil
        WHEN '10005' THEN 'Responsabilidad Civil' WHEN '111715' THEN 'Responsabilidad Civil' WHEN '12' THEN 'Responsabilidad Civil'
        WHEN '800007' THEN 'Responsabilidad Civil' WHEN '900752' THEN 'Responsabilidad Civil' WHEN '900775' THEN 'Responsabilidad Civil'
        WHEN 'DO1' THEN 'Responsabilidad Civil' WHEN 'LA1' THEN 'Responsabilidad Civil' WHEN 'LB' THEN 'Responsabilidad Civil'
        WHEN 'RC' THEN 'Responsabilidad Civil' WHEN 'RCL' THEN 'Responsabilidad Civil' WHEN 'RCM' THEN 'Responsabilidad Civil'
        WHEN 'RCP' THEN 'Responsabilidad Civil' WHEN 'RCT' THEN 'Responsabilidad Civil' WHEN 'REO' THEN 'Responsabilidad Civil'
        -- Vida
        WHEN '462' THEN 'Vida' WHEN '463' THEN 'Vida' WHEN '6023' THEN 'Vida'
        WHEN '6024' THEN 'Vida' WHEN '6025' THEN 'Vida' WHEN '6026' THEN 'Vida'
        WHEN '6028' THEN 'Vida' WHEN '6029' THEN 'Vida' WHEN '6052' THEN 'Vida'
        WHEN '900762' THEN 'Vida' WHEN '900771' THEN 'Vida' WHEN 'GC' THEN 'Vida'
        WHEN 'IF' THEN 'Vida'
        -- Hogar
        WHEN '10000' THEN 'Hogar' WHEN '10001' THEN 'Hogar' WHEN '10003' THEN 'Hogar'
        WHEN '410' THEN 'Hogar' WHEN '411' THEN 'Hogar' WHEN '6071' THEN 'Hogar'
        WHEN '900748' THEN 'Hogar' WHEN '900754' THEN 'Hogar' WHEN '900758' THEN 'Hogar'
        -- Transporte / Navegación
        WHEN '10' THEN 'Transporte / Navegación' WHEN '70107' THEN 'Transporte / Navegación' WHEN '70108' THEN 'Transporte / Navegación'
        WHEN '8092' THEN 'Transporte / Navegación' WHEN '900777' THEN 'Transporte / Navegación' WHEN '900778' THEN 'Transporte / Navegación'
        WHEN 'TRM' THEN 'Transporte / Navegación'
        -- Daños Materiales
        WHEN '19' THEN 'Daños Materiales' WHEN '900744' THEN 'Daños Materiales' WHEN '900746' THEN 'Daños Materiales'
        WHEN '900747' THEN 'Daños Materiales' WHEN '900774' THEN 'Daños Materiales' WHEN 'IN' THEN 'Daños Materiales'
        WHEN 'ST' THEN 'Daños Materiales'
        -- Ingeniería
        WHEN '11' THEN 'Ingeniería' WHEN '17' THEN 'Ingeniería' WHEN '18' THEN 'Ingeniería'
        WHEN '800008' THEN 'Ingeniería' WHEN '900745' THEN 'Ingeniería' WHEN '900779' THEN 'Ingeniería'
        -- Salud
        WHEN 'E1' THEN 'Salud' WHEN 'H1' THEN 'Salud' WHEN 'RDH' THEN 'Salud'
        WHEN 'SE' THEN 'Salud' WHEN 'Z1' THEN 'Salud'
        -- Cumplimiento
        WHEN '01' THEN 'Cumplimiento' WHEN '10004' THEN 'Cumplimiento' WHEN 'BO' THEN 'Cumplimiento'
        WHEN 'JU' THEN 'Cumplimiento'
        -- Manejo / Riesgos Financieros
        WHEN '02' THEN 'Manejo / Riesgos Financieros' WHEN '22' THEN 'Manejo / Riesgos Financieros' WHEN '900751' THEN 'Manejo / Riesgos Financieros'
        WHEN '900776' THEN 'Manejo / Riesgos Financieros'
        -- Exequias
        WHEN '396' THEN 'Exequias' WHEN '900719' THEN 'Exequias' WHEN '900720' THEN 'Exequias'
        WHEN '900721' THEN 'Exequias'
        -- PYME / Multiriesgo
        WHEN '10024' THEN 'PYME / Multiriesgo' WHEN '900742' THEN 'PYME / Multiriesgo' WHEN 'PY' THEN 'PYME / Multiriesgo'
        -- Accidentes Personales
        WHEN '7467' THEN 'Accidentes Personales' WHEN '7468' THEN 'Accidentes Personales' WHEN '7469' THEN 'Accidentes Personales'
        -- SOAT
        WHEN '368' THEN 'SOAT' WHEN '900730' THEN 'SOAT'
        -- Asistencias
        WHEN 'ADU' THEN 'Asistencias' WHEN 'T1' THEN 'Asistencias'
        -- Agropecuario
        WHEN '900793' THEN 'Agropecuario'
        -- Aviación
        WHEN '900794' THEN 'Aviación'
        -- Otros
        WHEN '800020' THEN 'Otros' WHEN '900765' THEN 'Otros' WHEN '900780' THEN 'Otros'
        WHEN 'LGP' THEN 'Otros'
        ELSE 'Sin clasificar'
        -- >>> END:categoria_ramo <<<
    END AS categoria_ramo,
    SUM(m.transaction_delta_billed_premium_amount) AS prima_neta
FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement m
WHERE m.current_record_flag = 1
  AND m.coverage_code <> 8888
  AND m.transaction_delta_billed_premium_amount <> 0
  AND m.accountable_period >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '3 years', 'YYYYMM') AS INTEGER)
  AND (
        (m.source_system = 'CO_iaxis' AND m.receipt_type NOT IN ('unificado-total'))
        OR m.source_system = 'CO_as400'
      )
GROUP BY 1, 2
ORDER BY periodo_fecha DESC;
