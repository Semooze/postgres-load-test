-- ============================================================
-- QUERY 1: Read — Single Table
-- Purpose: Baseline single-table performance
-- At 100K: CPU-bound (fits in shared_buffers)
-- At 10M:  I/O-bound (spills to disk)
-- ============================================================

-- 1a: Point select by PK (index lookup)
-- pgbench variable: random id within range
\set tx_id random(1, :max_tx_id)
SELECT id, user_id, amount, status, created_at
FROM transaction_record
WHERE id = :tx_id;

-- 1b: Range scan with aggregation (heavier I/O + CPU)
\set corp_id random(1, :max_corp_id)
SELECT 
    status,
    COUNT(*) AS tx_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MIN(created_at) AS earliest,
    MAX(created_at) AS latest
FROM transaction_record
WHERE corporate_id = :corp_id
GROUP BY status
ORDER BY total_amount DESC;
