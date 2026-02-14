-- ============================================================
-- QUERY 2: Read — Join 2 Tables (Corporate + User)
-- Purpose: Measure join performance with filter
-- ============================================================

-- 2a: Inner join with filter — find users for a corporate
\set corp_id random(1, :max_corp_id)
SELECT 
    c.name AS corporate_name,
    c.industry,
    u.id AS user_id,
    u.full_name,
    u.role,
    u.department,
    u.last_login_at
FROM corporate c
INNER JOIN app_user u ON u.corporate_id = c.id
WHERE c.id = :corp_id
  AND u.is_active = TRUE
ORDER BY u.last_login_at DESC NULLS LAST
LIMIT 50;

-- 2b: Aggregation join — user count per department for a corporate
\set corp_id random(1, :max_corp_id)
SELECT
    c.name AS corporate_name,
    u.department,
    COUNT(*) AS user_count,
    COUNT(*) FILTER (WHERE u.last_login_at > NOW() - INTERVAL '30 days') AS active_last_30d
FROM corporate c
INNER JOIN app_user u ON u.corporate_id = c.id
WHERE c.id = :corp_id
GROUP BY c.name, u.department
ORDER BY user_count DESC;
