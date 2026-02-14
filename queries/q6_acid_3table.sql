-- ============================================================
-- QUERY 6: ACID Write — 3 Tables (Corporate + User + Transaction)
-- Purpose: Full 3-table transaction with business logic
-- Scenario: Process payment → insert tx, update user, update corporate credit
-- ============================================================

\set user_id random(1, :max_user_id)
\set corp_id random(1, :max_corp_id)
\set amount random(100, 50000)

BEGIN;

-- Step 1: Check corporate credit limit (SELECT FOR UPDATE to lock row)
SELECT id, credit_limit 
FROM corporate 
WHERE id = :corp_id 
FOR UPDATE;

-- Step 2: Insert transaction record
INSERT INTO transaction_record (user_id, corporate_id, amount, currency, tx_type, status, description, created_at, reference_code)
VALUES (
    :user_id,
    :corp_id,
    :amount / 100.0,
    'THB',
    'payment',
    'completed',
    'ACID 3-table benchmark',
    NOW(),
    'ACID3' || LPAD((random() * 999999999)::BIGINT::TEXT, 12, '0')
);

-- Step 3: Update user activity
UPDATE app_user 
SET last_login_at = NOW()
WHERE id = :user_id;

-- Step 4: Deduct from corporate credit limit
UPDATE corporate 
SET credit_limit = credit_limit - (:amount / 100.0),
    updated_at = NOW()
WHERE id = :corp_id;

COMMIT;
