SELECT
    transaction_date_sk,
    COUNT(*) AS cantidad_registros
FROM gde_adp_dwh_vw_general.vw_fact_policy_transaction_movement
WHERE transaction_date_sk >= CAST(TO_CHAR(CURRENT_DATE - INTERVAL '3 months', 'YYYYMMDD') AS INTEGER)
  AND transaction_date_sk IS NOT NULL
GROUP BY transaction_date_sk
ORDER BY transaction_date_sk DESC;
