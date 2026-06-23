-- =============================================================================
-- Showback query — monthly cost per team x service x environment.
--
-- Runs in Amazon Athena over the Cost & Usage Report (CUR) — the authoritative,
-- line-item billing data. Powers the per-team showback dashboards in 4b. Swap
-- the table name for your CUR database/table.
--
-- Notes:
--  - amortized cost spreads upfront SP/RI fees over the period (true unit cost).
--  - resource_tags_user_<key> columns appear once tags are activated as
--    cost-allocation tags.
--  - untagged spend surfaces as '(untagged)' so it can't hide (FinOps SLI).
-- =============================================================================

WITH line_items AS (
  SELECT
    date_trunc('month', line_item_usage_start_date)         AS usage_month,
    COALESCE(NULLIF(resource_tags_user_team, ''), '(untagged)')        AS team,
    COALESCE(NULLIF(resource_tags_user_service, ''), '(untagged)')     AS service,
    COALESCE(NULLIF(resource_tags_user_environment, ''), '(untagged)') AS environment,
    product_product_name                                    AS aws_service,
    -- Amortized cost = the "fair" cost incl. spread SP/RI upfront fees.
    CAST(reservation_effective_cost AS double)
      + CAST(savings_plan_savings_plan_effective_cost AS double)
      + CASE
          WHEN line_item_line_item_type = 'Usage'
          THEN CAST(line_item_unblended_cost AS double)
          ELSE 0
        END                                                 AS amortized_cost
  FROM cur_database.cur_table
  WHERE line_item_usage_start_date >= date_add('month', -3, current_date)
)

SELECT
  usage_month,
  team,
  service,
  environment,
  aws_service,
  ROUND(SUM(amortized_cost), 2)                             AS cost_usd
FROM line_items
GROUP BY usage_month, team, service, environment, aws_service
HAVING SUM(amortized_cost) > 0
ORDER BY usage_month DESC, cost_usd DESC;

-- ---------------------------------------------------------------------------
-- Companion: untagged-spend ratio (a FinOps program SLI; target < 5%).
-- ---------------------------------------------------------------------------
-- SELECT
--   date_trunc('month', line_item_usage_start_date) AS usage_month,
--   ROUND(
--     SUM(CASE WHEN resource_tags_user_team = '' OR resource_tags_user_team IS NULL
--              THEN CAST(line_item_unblended_cost AS double) ELSE 0 END)
--     / NULLIF(SUM(CAST(line_item_unblended_cost AS double)), 0) * 100, 2
--   ) AS untagged_pct
-- FROM cur_database.cur_table
-- GROUP BY 1
-- ORDER BY 1 DESC;
