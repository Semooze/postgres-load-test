-- ============================================================
-- QUERY 3: Read — Join 3 Tables (Corporate + User + Transaction)
-- Purpose: Full 3-table join with aggregation
-- ============================================================

-- 3a: Transaction summary per user for a corporate
\set corp_id random(1, :max_corp_id)
SELECT
    c.name AS corporate_name,
    c.industry,
    u.full_name,
    u.department,
    COUNT(t.id) AS tx_count,
    SUM(t.amount) AS total_amount,
    AVG(t.amount) AS avg_amount,
    MAX(t.created_at) AS last_tx_date
FROM corporate c
INNER JOIN app_user u ON u.corporate_id = c.id
INNER JOIN transaction_record t ON t.user_id = u.id AND t.corporate_id = c.id
WHERE c.id = :corp_id
  AND t.status = 'completed'
GROUP BY c.name, c.industry, u.full_name, u.department
HAVING COUNT(t.id) > 1
ORDER BY total_amount DESC
LIMIT 20;

-- 3b: Corporate-level report with user and transaction metrics
\set industry_idx random(0, 7)
SELECT
    c.id AS corporate_id,
    c.name,
    COUNT(DISTINCT u.id) AS user_count,
    COUNT(t.id) AS tx_count,
    SUM(t.amount) AS total_amount,
    SUM(t.amount) FILTER (WHERE t.tx_type = 'payment') AS payment_total,
    SUM(t.amount) FILTER (WHERE t.tx_type = 'refund') AS refund_total,
    ROUND(AVG(t.amount), 2) AS avg_tx_amount
FROM corporate c
INNER JOIN app_user u ON u.corporate_id = c.id
INNER JOIN transaction_record t ON t.user_id = u.id AND t.corporate_id = c.id
WHERE c.industry = (ARRAY['Technology','Healthcare','Finance','Manufacturing','Retail','Energy','Education','Logistics'])[1 + :industry_idx]
  AND t.created_at >= NOW() - INTERVAL '6 months'
GROUP BY c.id, c.name
ORDER BY total_amount DESC
LIMIT 10;
