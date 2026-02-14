-- ============================================================
-- QUERY 4: Write — Single Table
-- Purpose: Baseline write performance (INSERT + UPDATE)
-- ============================================================

-- 4a: Insert a new transaction
\set user_id random(1, :max_user_id)
\set corp_id random(1, :max_corp_id)
\set amount random(100, 100000)
INSERT INTO transaction_record (user_id, corporate_id, amount, currency, tx_type, status, description, created_at, reference_code)
VALUES (
    :user_id,
    :corp_id,
    :amount / 100.0,
    (ARRAY['THB','USD','JPY','SGD'])[1 + (random() * 3)::INT],
    (ARRAY['payment','refund','transfer','fee'])[1 + (random() * 3)::INT],
    'pending',
    'Benchmark transaction',
    NOW(),
    'BENCH' || LPAD((random() * 999999999)::BIGINT::TEXT, 12, '0')
);

-- 4b: Update transaction status (simulate completion)
\set tx_id random(1, :max_tx_id)
UPDATE transaction_record 
SET status = 'completed', 
    completed_at = NOW(),
    updated_at = NOW()
WHERE id = :tx_id 
  AND status = 'pending';
