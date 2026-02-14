-- ============================================================
-- QUERY 5: ACID Write — 2 Tables (User + Transaction)
-- Purpose: Multi-table transaction with rollback safety
-- Scenario: User makes a payment → insert tx + update user last_login
-- ============================================================

\set user_id random(1, :max_user_id)
\set corp_id random(1, :max_corp_id)
\set amount random(100, 100000)

BEGIN;

-- Step 1: Insert transaction
INSERT INTO transaction_record (user_id, corporate_id, amount, currency, tx_type, status, description, created_at, reference_code)
VALUES (
    :user_id,
    :corp_id,
    :amount / 100.0,
    'THB',
    'payment',
    'completed',
    'ACID 2-table benchmark',
    NOW(),
    'ACID2' || LPAD((random() * 999999999)::BIGINT::TEXT, 12, '0')
);

-- Step 2: Update user's last login (simulates activity tracking within same tx)
UPDATE app_user 
SET last_login_at = NOW()
WHERE id = :user_id;

COMMIT;
