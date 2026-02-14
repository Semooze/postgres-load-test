-- ============================================================
-- QUERY 7: Skip Scan Test (Experiment 2 only: RDS 18.1 vs RDS 17.7)
-- Purpose: Demonstrate PG 18 skip scan on composite index
-- 
-- Index: idx_tx_corp_created ON transaction_record(corporate_id, created_at)
--
-- PG 17: Cannot use this index without corporate_id in WHERE
--         → Falls back to idx_tx_created or seq scan
-- PG 18: Can "skip scan" through distinct corporate_id values
--         → Uses the composite index even without corporate_id filter
--
-- IMPORTANT: Run EXPLAIN (ANALYZE, BUFFERS) on both versions to confirm
-- skip scan is actually being used in PG 18
-- ============================================================

-- 7a: Range query on second column of composite index (no leading column filter)
-- This is the classic skip scan scenario
SELECT 
    corporate_id,
    COUNT(*) AS tx_count,
    SUM(amount) AS total_amount
FROM transaction_record
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
GROUP BY corporate_id
ORDER BY total_amount DESC
LIMIT 20;

-- 7b: DISTINCT on leading column using skip scan
-- PG 18 can skip through the index instead of scanning all rows
SELECT DISTINCT corporate_id
FROM transaction_record
WHERE created_at >= NOW() - INTERVAL '30 days';

-- 7c: EXISTS-style pattern — find corporates with recent transactions
-- Another pattern that benefits from skip scan
SELECT c.id, c.name
FROM corporate c
WHERE EXISTS (
    SELECT 1 
    FROM transaction_record t 
    WHERE t.corporate_id = c.id 
      AND t.created_at >= NOW() - INTERVAL '7 days'
)
ORDER BY c.id
LIMIT 50;

-- ============================================================
-- Verification: Run this on both PG 17 and PG 18 to compare plans
-- ============================================================
-- EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
-- SELECT corporate_id, COUNT(*) AS tx_count, SUM(amount) AS total_amount
-- FROM transaction_record
-- WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
-- GROUP BY corporate_id
-- ORDER BY total_amount DESC
-- LIMIT 20;
--
-- Expected PG 17: Index Scan on idx_tx_created or Seq Scan
-- Expected PG 18: Index Skip Scan on idx_tx_corp_created
-- ============================================================
