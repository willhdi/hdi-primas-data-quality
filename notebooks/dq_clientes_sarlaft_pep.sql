​
   ------BLOQUE A -- REPORTE BASE---------------
   
DROP TABLE IF EXISTS tmp_reporte_base;

CREATE TEMP TABLE tmp_reporte_base AS
WITH vigentes_base AS (
    SELECT
        v.policy_holder,
        v.accountable_period,
        ROW_NUMBER() OVER (
            PARTITION BY v.policy_holder
            ORDER BY v.certificate_start_date DESC
        ) AS rn
    FROM co_sandbox_datos.fact_vigentes_total_historico v
    WHERE v.accountable_period = '202606'
),
vigentes_filtrado AS (
    SELECT
        policy_holder
    FROM vigentes_base
    WHERE rn = 1
),
per_personas_base AS (
    SELECT
        p.sperson,
        p.ctipide,
        CAST(p.nnumide AS VARCHAR(50)) AS nnumide,
        p.falta,
        TO_DATE(p.fnacimi, 'YYYY-MM-DD') AS fecha_nacimiento,
        CAST(p.fmovimi AS DATE) AS fmovimi_persona,
        ROW_NUMBER() OVER (
            PARTITION BY p.sperson
            ORDER BY
                (
                    CASE WHEN NULLIF(TRIM(CAST(p.nnumide AS VARCHAR(50))), '') IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN p.ctipide IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN p.falta IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN p.fnacimi IS NOT NULL THEN 1 ELSE 0 END
                ) DESC,
                p.fmovimi DESC
        ) AS rn
    FROM gde_adp_ods.axis_per_personas p
),
per_personas_filtrado AS (
    SELECT
        sperson,
        ctipide,
        nnumide,
        falta,
        fecha_nacimiento,
        fmovimi_persona
    FROM per_personas_base
    WHERE rn = 1
),
detper_base AS (
    SELECT
        d.sperson,
        TRIM(
            COALESCE(NULLIF(TRIM(d.tnombre1), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(d.tnombre2), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(d.tapelli1), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(d.tapelli2), ''), '')
        ) AS nombre_completo,
        TRY_CAST(d.ingresos AS NUMERIC(18,2)) AS ingresos,
        TRY_CAST(d.egresos AS NUMERIC(18,2)) AS egresos,
        CAST(d.fmovimi AS DATE) AS fmovimi_financiera,
        ROW_NUMBER() OVER (
            PARTITION BY d.sperson
            ORDER BY d.fmovimi DESC
        ) AS rn
    FROM gde_adp_ods.axis_per_detper d
),
detper_filtrado AS (
    SELECT
        sperson,
        nombre_completo,
        ingresos,
        egresos,
        fmovimi_financiera
    FROM detper_base
    WHERE rn = 1
),
correo_base AS (
    SELECT
        c.sperson,
        TRIM(CAST(c.tvalcon AS VARCHAR(200))) AS correo,
        CAST(c.fmovimi AS DATE) AS fmovimi_email,
        ROW_NUMBER() OVER (
            PARTITION BY c.sperson
            ORDER BY c.fmovimi DESC
        ) AS rn
    FROM gde_adp_ods.axis_per_contactos c
    WHERE c.ctipcon = 3
      AND NULLIF(TRIM(CAST(c.tvalcon AS VARCHAR(200))), '') IS NOT NULL
      AND POSITION('@' IN CAST(c.tvalcon AS VARCHAR(200))) > 1
),
correo_filtrado AS (
    SELECT
        sperson,
        correo,
        fmovimi_email
    FROM correo_base
    WHERE rn = 1
),
celular_base AS (
    SELECT
        c.sperson,
        TRIM(CAST(c.tvalcon AS VARCHAR(30))) AS celular,
        CAST(c.fmovimi AS DATE) AS fmovimi_celular,
        ROW_NUMBER() OVER (
            PARTITION BY c.sperson
            ORDER BY c.fmovimi DESC
        ) AS rn
    FROM gde_adp_ods.axis_per_contactos c
    WHERE c.ctipcon IN (5, 6)
      AND NULLIF(TRIM(CAST(c.tvalcon AS VARCHAR(30))), '') IS NOT NULL
      AND LENGTH(TRIM(CAST(c.tvalcon AS VARCHAR(30)))) >= 7
),
celular_filtrado AS (
    SELECT
        sperson,
        celular,
        fmovimi_celular
    FROM celular_base
    WHERE rn = 1
),
per_contactos_filtrado AS (
    SELECT
        COALESCE(cr.sperson, ce.sperson) AS sperson,
        cr.correo,
        cr.fmovimi_email,
        ce.celular,
        ce.fmovimi_celular
    FROM correo_filtrado cr
    FULL OUTER JOIN celular_filtrado ce
        ON cr.sperson = ce.sperson
),
as400_base AS (
    SELECT
        CASE
            WHEN a.tipo_identifi_clie = 'E' THEN 33
            WHEN a.tipo_identifi_clie = 'T' THEN 34
            WHEN a.tipo_identifi_clie = 'R' THEN 35
            WHEN a.tipo_identifi_clie = 'C' THEN 36
            WHEN a.tipo_identifi_clie = 'N' THEN 37
            WHEN a.tipo_identifi_clie = 'U' THEN 38
            WHEN a.tipo_identifi_clie = 'P' THEN 40
            WHEN a.tipo_identifi_clie = 'D' THEN 44
            ELSE 0
        END AS tipo_id,
        CAST(a.nro_identifi_clie AS VARCHAR(50)) AS nro_identifi_clie,
        TRIM(
            COALESCE(NULLIF(TRIM(a.nombre_1), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(a.nombre_2), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(a.apellido_1), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(a.apellido_2), ''), '')
        ) AS nombre_completo,
        CAST(a.telefono AS VARCHAR(30)) AS telefono,
        CAST(a.email AS VARCHAR(200)) AS email,
        TO_DATE(a.fecha_nacimiento, 'YYYY-MM-DD') AS fecha_nacimiento,
        CAST(a.fecha_ejecucion_dwh AS DATE) AS fecha_ejecucion_dwh,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(a.nro_identifi_clie AS VARCHAR(50))
            ORDER BY a.fecha_ejecucion_dwh DESC
        ) AS rn
    FROM gde_adp_ods.as400_dwh_clientes a
),
as400_filtrado AS (
    SELECT
        tipo_id,
        nro_identifi_clie,
        nombre_completo,
        telefono,
        email,
        fecha_nacimiento,
        fecha_ejecucion_dwh
    FROM as400_base
    WHERE rn = 1
),
sarlaft_base AS (
    SELECT
        CAST(s.num_identificacion AS VARCHAR(50)) AS num_identificacion,
        s.par_tipo_id,
        TRIM(
            COALESCE(NULLIF(TRIM(s.nombre1_basico), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(s.nombre2_basico), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(s.apellido1_basico), ''), '') || ' ' ||
            COALESCE(NULLIF(TRIM(s.apellido2_basico), ''), '')
        ) AS nombre_completo,
        TO_DATE(s.fecha_nacimiento, 'YYYY-MM-DD') AS fecha_nacimiento,
        CAST(s.email AS VARCHAR(200)) AS email,
        CAST(s.celular AS VARCHAR(30)) AS celular,
        TRY_CAST(s.total_activos AS NUMERIC(18,2)) AS total_activos,
        TRY_CAST(s.total_pasivos AS NUMERIC(18,2)) AS total_pasivos,
        TRY_CAST(s.ingreso_laboral AS NUMERIC(18,2)) AS ingreso_laboral,
        TRY_CAST(s.gasto_financiero AS NUMERIC(18,2)) AS total_egresos,
        CAST(s.fecha_diligenciamiento AS DATE) AS fecha_diligenciamiento,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(s.num_identificacion AS VARCHAR(50))
            ORDER BY s.fecha_diligenciamiento DESC
        ) AS rn
    FROM dp_dm_compliance.vm_formulario_sarlaft s
),
sarlaft_filtrado AS (
    SELECT
        num_identificacion,
        par_tipo_id,
        nombre_completo,
        fecha_nacimiento,
        email,
        celular,
        total_activos,
        total_pasivos,
        ingreso_laboral,
        total_egresos,
        fecha_diligenciamiento
    FROM sarlaft_base
    WHERE rn = 1
),
compra_datos_base AS (
    SELECT
        CAST(sct.numero_id AS VARCHAR(50)) AS numero_id,
        sct.tipo_id,
        sct.nombre_completo,
        CAST(sct.email AS VARCHAR(200)) AS email,
        CAST(sct.celular AS VARCHAR(30)) AS celular,
        TRY_CAST(sct.total_activos_sct AS NUMERIC(18,2)) AS total_activos_sct,
        TRY_CAST(sct.total_pasivos_sct AS NUMERIC(18,2)) AS total_pasivos_sct,
        TRY_CAST(sct.total_ingresos_sct AS NUMERIC(18,2)) AS total_ingresos_sct,
        TRY_CAST(sct.total_egresos_scs AS NUMERIC(18,2)) AS total_egresos_scs,
        CAST(sct.fecha_modificacion AS DATE) AS fecha_modificacion,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(sct.numero_id AS VARCHAR(50))
            ORDER BY sct.fecha_modificacion DESC
        ) AS rn
    FROM co_sandbox_datos.vw_compra_sct_unificada sct
),
compra_datos_filtrado AS (
    SELECT
        numero_id,
        tipo_id,
        nombre_completo,
        email,
        celular,
        total_activos_sct,
        total_pasivos_sct,
        total_ingresos_sct,
        total_egresos_scs,
        fecha_modificacion
    FROM compra_datos_base
    WHERE rn = 1
),
pep_base AS (
    SELECT
        CAST(pep.identificationnumber AS VARCHAR(50)) AS identificationnumber,
        pep."politicamente expuesto" AS politicamente_expuesto,
        CAST(pep."fecha de actualizacion" AS DATE) AS fecha_actualizacion_pep,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(pep.identificationnumber AS VARCHAR(50))
            ORDER BY CAST(pep."fecha de actualizacion" AS DATE) DESC
        ) AS rn
    FROM co_sandbox_datos.clientes_pirani_202606 pep
),
pep_filtrado AS (
    SELECT
        identificationnumber,
        politicamente_expuesto,
        fecha_actualizacion_pep
    FROM pep_base
    WHERE rn = 1
),
reporte_base AS (
    SELECT
        CASE
            WHEN COALESCE(sct.tipo_id, s.par_tipo_id, p.ctipide, a.tipo_id) IN (24, 33, 34, 35, 36, 38, 40, 44, 46, 48) THEN 1
            WHEN COALESCE(sct.tipo_id, s.par_tipo_id, p.ctipide, a.tipo_id) = 37 THEN 2
            ELSE NULL
        END AS tipo_persona,
        v.policy_holder,
        COALESCE(sct.tipo_id, s.par_tipo_id, p.ctipide, a.tipo_id) AS tipo_id,
        COALESCE(sct.numero_id, s.num_identificacion, p.nnumide, a.nro_identifi_clie) AS numero_documento,
        COALESCE(
            NULLIF(TRIM(sct.nombre_completo), ''),
            NULLIF(TRIM(s.nombre_completo), ''),
            NULLIF(TRIM(d.nombre_completo), ''),
            NULLIF(TRIM(a.nombre_completo), '')
        ) AS nombres_completos,
        COALESCE(s.fecha_nacimiento, p.fecha_nacimiento, a.fecha_nacimiento) AS fecha_nacimiento,
        p.falta AS fecha_vinculacion,
        COALESCE(
            NULLIF(TRIM(sct.celular), ''),
            NULLIF(TRIM(s.celular), ''),
            NULLIF(TRIM(c.celular), ''),
            NULLIF(TRIM(a.telefono), '')
        ) AS celular,
        COALESCE(
            NULLIF(TRIM(sct.email), ''),
            NULLIF(TRIM(s.email), ''),
            NULLIF(TRIM(c.correo), ''),
            NULLIF(TRIM(a.email), '')
        ) AS correo_electronico,
        COALESCE(sct.total_activos_sct, s.total_activos) AS total_activos,
        COALESCE(sct.total_pasivos_sct, s.total_pasivos) AS total_pasivos,
        COALESCE(sct.total_ingresos_sct, s.ingreso_laboral, d.ingresos) AS total_ingresos,
        COALESCE(sct.total_egresos_scs, s.total_egresos, d.egresos) AS total_egresos,
        CASE
            WHEN s.num_identificacion IS NOT NULL THEN 1
            ELSE 0
        END AS declara_sarlaft,
        CASE
            WHEN pep.identificationnumber IS NOT NULL THEN 'Intensificado'
            WHEN s.fecha_diligenciamiento IS NOT NULL THEN 'Obligado'
            ELSE 'Ordinario'
        END AS clasificacion,
        CAST(
            CASE
                WHEN pep.identificationnumber IS NOT NULL THEN 365
                WHEN s.fecha_diligenciamiento IS NOT NULL THEN 1095
                ELSE 1095
            END AS NUMERIC(10,0)
        ) AS perfil_riesgo,
        pep.politicamente_expuesto AS clientes_pep,
        /* Fechas de actualización por atributo */
        CASE
            WHEN sct.numero_id IS NOT NULL THEN sct.fecha_modificacion
            WHEN s.num_identificacion IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN p.nnumide IS NOT NULL THEN p.fmovimi_persona
            WHEN a.nro_identifi_clie IS NOT NULL THEN a.fecha_ejecucion_dwh
            ELSE NULL
        END AS fecha_actualizacion_numero_documento,
        CASE
            WHEN NULLIF(TRIM(sct.nombre_completo), '') IS NOT NULL THEN sct.fecha_modificacion
            WHEN NULLIF(TRIM(s.nombre_completo), '') IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN NULLIF(TRIM(d.nombre_completo), '') IS NOT NULL THEN d.fmovimi_financiera
            WHEN NULLIF(TRIM(a.nombre_completo), '') IS NOT NULL THEN a.fecha_ejecucion_dwh
            ELSE NULL
        END AS fecha_actualizacion_nombres,
        CASE
            WHEN s.fecha_nacimiento IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN p.fecha_nacimiento IS NOT NULL THEN p.fmovimi_persona
            WHEN a.fecha_nacimiento IS NOT NULL THEN a.fecha_ejecucion_dwh
            ELSE NULL
        END AS fecha_actualizacion_fecha_nacimiento,
        p.fmovimi_persona AS fecha_actualizacion_fecha_vinculacion,
        CASE
            WHEN NULLIF(TRIM(sct.celular), '') IS NOT NULL THEN sct.fecha_modificacion
            WHEN NULLIF(TRIM(s.celular), '') IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN NULLIF(TRIM(c.celular), '') IS NOT NULL THEN c.fmovimi_celular
            WHEN NULLIF(TRIM(a.telefono), '') IS NOT NULL THEN a.fecha_ejecucion_dwh
            ELSE NULL
        END AS fecha_actualizacion_celular,
        CASE
            WHEN NULLIF(TRIM(sct.email), '') IS NOT NULL THEN sct.fecha_modificacion
            WHEN NULLIF(TRIM(s.email), '') IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN NULLIF(TRIM(c.correo), '') IS NOT NULL THEN c.fmovimi_email
            WHEN NULLIF(TRIM(a.email), '') IS NOT NULL THEN a.fecha_ejecucion_dwh
            ELSE NULL
        END AS fecha_actualizacion_correo,
        CASE
            WHEN sct.total_activos_sct IS NOT NULL THEN sct.fecha_modificacion
            WHEN s.total_activos IS NOT NULL THEN s.fecha_diligenciamiento
            ELSE p.fmovimi_persona
        END AS fecha_actualizacion_activos,
        CASE
            WHEN sct.total_pasivos_sct IS NOT NULL THEN sct.fecha_modificacion
            WHEN s.total_pasivos IS NOT NULL THEN s.fecha_diligenciamiento
            ELSE p.fmovimi_persona
        END AS fecha_actualizacion_pasivos,
        CASE
            WHEN sct.total_ingresos_sct IS NOT NULL THEN sct.fecha_modificacion
            WHEN s.ingreso_laboral IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN d.ingresos IS NOT NULL THEN d.fmovimi_financiera
            ELSE p.fmovimi_persona
        END AS fecha_actualizacion_ingresos,
        CASE
            WHEN sct.total_egresos_scs IS NOT NULL THEN sct.fecha_modificacion
            WHEN s.total_egresos IS NOT NULL THEN s.fecha_diligenciamiento
            WHEN d.egresos IS NOT NULL THEN d.fmovimi_financiera
            ELSE p.fmovimi_persona
        END AS fecha_actualizacion_egresos
    FROM vigentes_filtrado v
    LEFT JOIN per_personas_filtrado p
        ON v.policy_holder = p.sperson
    LEFT JOIN detper_filtrado d
        ON p.sperson = d.sperson
    LEFT JOIN per_contactos_filtrado c
        ON p.sperson = c.sperson
    LEFT JOIN sarlaft_filtrado s
        ON p.nnumide = s.num_identificacion
    LEFT JOIN compra_datos_filtrado sct
        ON p.nnumide = sct.numero_id
    LEFT JOIN as400_filtrado a
        ON p.nnumide = a.nro_identifi_clie
    LEFT JOIN pep_filtrado pep
        ON COALESCE(sct.numero_id, s.num_identificacion, p.nnumide, a.nro_identifi_clie) = pep.identificationnumber
)
SELECT *
FROM reporte_base;


--PRUEBA PARA BLOQUE A---

SELECT count(policy_holder)
FROM tmp_reporte_base --where tipo_persona = 0 --is null
;

SELECT *
FROM tmp_reporte_base --where tipo_persona = 0 --is null
limit 100;

LIMIT 100;

select distinct count(policy_holder) from co_sandbox_datos.fact_vigentes_total_historico where accountable_period = '202605';

select distinct count(policy_holder) from vigentes_filtrado where accountable_period = '202605';


   
   
   
   WITH vigentes_base AS (
    SELECT
        v.policy_holder,
        ROW_NUMBER() OVER (
            PARTITION BY v.policy_holder
            ORDER BY v.certificate_start_date DESC
        ) AS rn
    FROM co_sandbox_datos.fact_vigentes_total_historico v
    WHERE v.accountable_period = '202605'
),
vigentes_filtrado AS (
    SELECT policy_holder
    FROM vigentes_base
    WHERE rn = 1
)
SELECT COUNT(*) AS total_registros_rn_1
FROM vigentes_filtrado;


WITH vigentes_base AS (
    SELECT
        v.policy_holder,
        ROW_NUMBER() OVER (
            PARTITION BY v.policy_holder
            ORDER BY v.certificate_start_date DESC
        ) AS rn
    FROM co_sandbox_datos.fact_vigentes_total_historico v
    WHERE v.accountable_period = '202605'
),
vigentes_filtrado AS (
    SELECT policy_holder
    FROM vigentes_base
    WHERE rn = 1
)
SELECT
    (SELECT COUNT(*) FROM vigentes_base) AS total_registros_base,
    (SELECT COUNT(*) FROM vigentes_filtrado) AS total_registros_rn_1;
   
   
   SELECT
    policy_holder,
    COUNT(*) AS cantidad_registros
FROM co_sandbox_datos.fact_vigentes_total_historico
WHERE accountable_period = '202604'
GROUP BY policy_holder
HAVING COUNT(*) >= 1
ORDER BY cantidad_registros DESC;

---BLOQUE B -- REGLAS CALIDAD REPORTE BASE ---------------

DROP TABLE IF EXISTS tmp_reglas_reporte_base;

CREATE TEMP TABLE tmp_reglas_reporte_base AS
SELECT
    rb.*,
    /* =========================
       COMPLETITUD
       ========================= */
    CASE WHEN rb.numero_documento IS NOT NULL AND BTRIM(rb.numero_documento) <> '' THEN 1 ELSE 0 END AS rg_completitud_numero_documento,
    CASE WHEN rb.nombres_completos IS NOT NULL AND BTRIM(rb.nombres_completos) <> '' THEN 1 ELSE 0 END AS rg_completitud_nombres,
    CASE WHEN rb.fecha_nacimiento IS NOT NULL THEN 1 ELSE 0 END AS rg_completitud_fecha_nacimiento,
    CASE WHEN rb.fecha_vinculacion IS NOT NULL THEN 1 ELSE 0 END AS rg_completitud_fecha_vinculacion,
    CASE WHEN rb.celular IS NOT NULL AND BTRIM(rb.celular) <> '' THEN 1 ELSE 0 END AS rg_completitud_celular,
    CASE WHEN rb.correo_electronico IS NOT NULL AND BTRIM(rb.correo_electronico) <> '' THEN 1 ELSE 0 END AS rg_completitud_correo,
    CASE WHEN rb.total_activos IS NOT NULL THEN 1 ELSE 0 END AS rg_completitud_activos,
    CASE WHEN rb.total_pasivos IS NOT NULL THEN 1 ELSE 0 END AS rg_completitud_pasivos,
    CASE WHEN rb.total_ingresos IS NOT NULL THEN 1 ELSE 0 END AS rg_completitud_ingresos,
    CASE WHEN rb.total_egresos IS NOT NULL THEN 1 ELSE 0 END AS rg_completitud_egresos,
    /* =========================
       VALIDEZ
       ========================= */
    CASE
        WHEN rb.numero_documento IS NOT NULL
         AND BTRIM(rb.numero_documento) <> ''
         AND POSITION(' ' IN rb.numero_documento) = 0
        THEN 1 ELSE 0
    END AS rg_validez_numero_documento,
    CASE
        WHEN rb.nombres_completos IS NOT NULL
         AND BTRIM(rb.nombres_completos) <> ''
         AND REGEXP_INSTR(rb.nombres_completos, '^[A-Za-zÁÉÍÓÚáéíóúÑñ ]+$') = 1
        THEN 1 ELSE 0
    END AS rg_validez_nombres,
    CASE
        WHEN rb.fecha_nacimiento IS NULL THEN 0
        WHEN rb.fecha_nacimiento > CURRENT_DATE THEN 0
        WHEN rb.fecha_nacimiento < DATE '1940-01-01' THEN 0
        ELSE 1
    END AS rg_validez_fecha_nacimiento,
    CASE
        WHEN rb.fecha_vinculacion IS NULL THEN 0
        WHEN rb.fecha_vinculacion > CURRENT_DATE THEN 0
        WHEN rb.fecha_nacimiento IS NOT NULL AND rb.fecha_vinculacion < rb.fecha_nacimiento THEN 0
        ELSE 1
    END AS rg_validez_fecha_vinculacion,
    CASE
        WHEN rb.celular IS NOT NULL
         AND REGEXP_INSTR(REGEXP_REPLACE(rb.celular, '[^0-9]', ''), '^[0-9]{10}$') = 1
        THEN 1 ELSE 0
    END AS rg_validez_celular,
    CASE
        WHEN rb.correo_electronico IS NOT NULL
         AND REGEXP_INSTR(
                LOWER(BTRIM(rb.correo_electronico)),
                '^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$'
             ) = 1
        THEN 1 ELSE 0
    END AS rg_validez_correo,
    CASE WHEN rb.total_activos IS NOT NULL AND rb.total_activos >= 0 THEN 1 ELSE 0 END AS rg_validez_activos,
    CASE WHEN rb.total_pasivos IS NOT NULL AND rb.total_pasivos >= 0 THEN 1 ELSE 0 END AS rg_validez_pasivos,
    CASE WHEN rb.total_ingresos IS NOT NULL AND rb.total_ingresos >= 0 THEN 1 ELSE 0 END AS rg_validez_ingresos,
    CASE WHEN rb.total_egresos IS NOT NULL AND rb.total_egresos >= 0 THEN 1 ELSE 0 END AS rg_validez_egresos,
    /* =========================
       UNICIDAD
       ========================= */
    CASE
        WHEN COUNT(*) OVER (PARTITION BY rb.tipo_id, rb.numero_documento) = 1
        THEN 1 ELSE 0
    END AS rg_unicidad_numero_documento,
    /* =========================
       PRECISION
       ========================= */
    CASE
        WHEN rb.total_ingresos IS NOT NULL
         AND rb.total_ingresos > 0
         AND rb.total_egresos IS NOT NULL
         AND rb.total_ingresos >= rb.total_egresos
        THEN 1 ELSE 0
    END AS rg_precision_ingresos,
    CASE
        WHEN rb.total_egresos IS NOT NULL
         AND rb.total_egresos > 0
         AND rb.total_ingresos IS NOT NULL
         AND rb.total_ingresos >= rb.total_egresos
        THEN 1 ELSE 0
    END AS rg_precision_egresos,
    /* =========================
       OPORTUNIDAD
       Se calcula sin excluir globalmente PJ.
       La aplicabilidad por tipo de persona se controla en métricas.
       ========================= */
    CASE
        WHEN rb.fecha_actualizacion_numero_documento IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_numero_documento, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_numero_documento,
    CASE
        WHEN rb.fecha_actualizacion_nombres IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_nombres, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_nombres,
    CASE
        WHEN rb.fecha_actualizacion_fecha_nacimiento IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_fecha_nacimiento, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_fecha_nacimiento,
    CASE
        WHEN rb.fecha_actualizacion_fecha_vinculacion IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_fecha_vinculacion, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_fecha_vinculacion,
    CASE
        WHEN rb.fecha_actualizacion_celular IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_celular, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_celular,
    CASE
        WHEN rb.fecha_actualizacion_correo IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_correo, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_correo,
    CASE
        WHEN rb.fecha_actualizacion_activos IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_activos, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_activos,
    CASE
        WHEN rb.fecha_actualizacion_pasivos IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_pasivos, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_pasivos,
    CASE
        WHEN rb.fecha_actualizacion_ingresos IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_ingresos, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_ingresos,
    CASE
        WHEN rb.fecha_actualizacion_egresos IS NOT NULL
         AND (DATEDIFF(day, rb.fecha_actualizacion_egresos, CURRENT_DATE) + 30) <= rb.perfil_riesgo
        THEN 1 ELSE 0
    END AS rg_oportunidad_egresos
FROM tmp_reporte_base rb;


---PRUEBA BLOQUE B---

SELECT *
FROM tmp_reglas_reporte_base
LIMIT 100;




-----BLOQUE C --- METRICAS DE REGLAS DE CALIDAD----------------

WITH metricas AS (
    /* =========================
       COMPLETITUD
       ========================= */
    SELECT
        tipo_persona,
        'numero_documento' AS atributo,
        'completitud' AS dimension,
        AVG(rg_completitud_numero_documento::DECIMAL(18,6)) * 100 AS porcentaje
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'nombres_completos',
        'completitud',
        AVG(rg_completitud_nombres::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'fecha_nacimiento',
        'completitud',
        AVG(rg_completitud_fecha_nacimiento::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'fecha_vinculacion',
        'completitud',
        AVG(rg_completitud_fecha_vinculacion::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'celular',
        'completitud',
        AVG(rg_completitud_celular::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'correo_electronico',
        'completitud',
        AVG(rg_completitud_correo::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_activos',
        'completitud',
        AVG(rg_completitud_activos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_pasivos',
        'completitud',
        AVG(rg_completitud_pasivos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_ingresos',
        'completitud',
        AVG(rg_completitud_ingresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_egresos',
        'completitud',
        AVG(rg_completitud_egresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    /* =========================
       VALIDEZ
       ========================= */
    UNION ALL
    SELECT
        tipo_persona,
        'numero_documento',
        'validez',
        AVG(rg_validez_numero_documento::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'nombres_completos',
        'validez',
        AVG(rg_validez_nombres::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'fecha_nacimiento',
        'validez',
        AVG(rg_validez_fecha_nacimiento::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'fecha_vinculacion',
        'validez',
        AVG(rg_validez_fecha_vinculacion::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'celular',
        'validez',
        AVG(rg_validez_celular::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'correo_electronico',
        'validez',
        AVG(rg_validez_correo::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_activos',
        'validez',
        AVG(rg_validez_activos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_pasivos',
        'validez',
        AVG(rg_validez_pasivos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_ingresos',
        'validez',
        AVG(rg_validez_ingresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_egresos',
        'validez',
        AVG(rg_validez_egresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    /* =========================
       UNICIDAD
       ========================= */
    UNION ALL
    SELECT
        tipo_persona,
        'numero_documento',
        'unicidad',
        AVG(rg_unicidad_numero_documento::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    /* =========================
       PRECISION
       ========================= */
    UNION ALL
    SELECT
        tipo_persona,
        'total_ingresos',
        'precision',
        AVG(rg_precision_ingresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_egresos',
        'precision',
        AVG(rg_precision_egresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    /* =========================
       OPORTUNIDAD
       ========================= */
    UNION ALL
    SELECT
        tipo_persona,
        'numero_documento',
        'oportunidad',
        AVG(rg_oportunidad_numero_documento::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'nombres_completos',
        'oportunidad',
        AVG(rg_oportunidad_nombres::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'fecha_nacimiento',
        'oportunidad',
        AVG(rg_oportunidad_fecha_nacimiento::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'fecha_vinculacion',
        'oportunidad',
        AVG(rg_oportunidad_fecha_vinculacion::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'celular',
        'oportunidad',
        AVG(rg_oportunidad_celular::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'correo_electronico',
        'oportunidad',
        AVG(rg_oportunidad_correo::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_activos',
        'oportunidad',
        AVG(rg_oportunidad_activos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_pasivos',
        'oportunidad',
        AVG(rg_oportunidad_pasivos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_ingresos',
        'oportunidad',
        AVG(rg_oportunidad_ingresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
    UNION ALL
    SELECT
        tipo_persona,
        'total_egresos',
        'oportunidad',
        AVG(rg_oportunidad_egresos::DECIMAL(18,6)) * 100
    FROM tmp_reglas_reporte_base
    WHERE tipo_persona IN (1,2)
      AND declara_sarlaft = 1
    GROUP BY tipo_persona
)
SELECT
    tipo_persona,
    CASE
        WHEN tipo_persona = 1 THEN 'Persona natural'
        WHEN tipo_persona = 2 THEN 'Persona juridica'
        ELSE 'No clasificada'
    END AS desc_tipo_persona,
    atributo,
    ROUND(MAX(CASE WHEN dimension = 'completitud' THEN porcentaje END), 2) AS pct_completitud,
    ROUND(MAX(CASE WHEN dimension = 'validez' THEN porcentaje END), 2) AS pct_validez,
    ROUND(MAX(CASE WHEN dimension = 'unicidad' THEN porcentaje END), 2) AS pct_unicidad,
    ROUND(MAX(CASE WHEN dimension = 'precision' THEN porcentaje END), 2) AS pct_precision,
    ROUND(MAX(CASE WHEN dimension = 'oportunidad' THEN porcentaje END), 2) AS pct_oportunidad,
    CASE WHEN ROUND(MAX(CASE WHEN dimension = 'completitud' THEN porcentaje END), 2) >= 90 THEN 1 ELSE 0 END AS cumple_completitud_90,
    CASE WHEN ROUND(MAX(CASE WHEN dimension = 'validez' THEN porcentaje END), 2) >= 90 THEN 1 ELSE 0 END AS cumple_validez_90,
    CASE WHEN ROUND(MAX(CASE WHEN dimension = 'unicidad' THEN porcentaje END), 2) >= 90 THEN 1 ELSE 0 END AS cumple_unicidad_90,
    CASE WHEN ROUND(MAX(CASE WHEN dimension = 'precision' THEN porcentaje END), 2) >= 90 THEN 1 ELSE 0 END AS cumple_precision_90,
    CASE WHEN ROUND(MAX(CASE WHEN dimension = 'oportunidad' THEN porcentaje END), 2) >= 90 THEN 1 ELSE 0 END AS cumple_oportunidad_90
FROM metricas
GROUP BY tipo_persona, atributo
ORDER BY tipo_persona, atributo;

