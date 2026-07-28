SELECT
    accountable_period,
    SUM(transaction_delta_billed_premium_amount) AS prima_neta
FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
WHERE current_record_flag = 1
  AND coverage_code <> 8888
  AND transaction_delta_billed_premium_amount <> 0
  AND accountable_period >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '3 years', 'YYYYMM') AS INTEGER)
  AND (
        (source_system = 'CO_iaxis' AND receipt_type NOT IN ('unificado-total'))
        OR source_system = 'CO_as400'
      )
GROUP BY accountable_period
ORDER BY accountable_period;