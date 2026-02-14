-- ============================================================
-- Data Seeding Script
-- Usage: Set :scale before running
--   100K total  → :scale = 1    (10K corp, 20K user, 70K tx)
--   1M total    → :scale = 10   (100K corp, 200K user, 700K tx)
--   10M total   → :scale = 100  (1M corp, 2M user, 7M tx)
--
-- Run: psql -v scale=10 -f 02_seed_data.sql
-- ============================================================

-- Seed Corporate (10% of total = 10,000 × :scale)
INSERT INTO corporate (name, tax_id, industry, country, created_at, is_active, credit_limit, metadata)
SELECT
    'Corp_' || i,
    'TAX' || LPAD(i::TEXT, 10, '0'),
    (ARRAY['Technology','Healthcare','Finance','Manufacturing','Retail','Energy','Education','Logistics'])[1 + (i % 8)],
    (ARRAY['TH','US','JP','SG','DE','GB','AU','KR'])[1 + (i % 8)],
    NOW() - (random() * INTERVAL '5 years'),
    (random() > 0.1),
    ROUND((random() * 10000000)::NUMERIC, 2),
    jsonb_build_object('tier', (ARRAY['bronze','silver','gold','platinum'])[1 + (i % 4)], 'region', 'APAC')
FROM generate_series(1, 10000 * :scale) AS s(i);

-- Seed Users (20% of total = 20,000 × :scale)
INSERT INTO app_user (corporate_id, email, full_name, role, department, created_at, last_login_at, is_active, profile)
SELECT
    1 + (i % (10000 * :scale)),  -- distributed across corporates
    'user' || i || '@example.com',
    'User Name ' || i,
    (ARRAY['admin','manager','staff','viewer'])[1 + (i % 4)],
    (ARRAY['Engineering','Sales','Marketing','Finance','Operations','HR','Legal','Support'])[1 + (i % 8)],
    NOW() - (random() * INTERVAL '3 years'),
    CASE WHEN random() > 0.3 THEN NOW() - (random() * INTERVAL '30 days') ELSE NULL END,
    (random() > 0.05),
    jsonb_build_object('lang', (ARRAY['th','en','ja','zh'])[1 + (i % 4)])
FROM generate_series(1, 20000 * :scale) AS s(i);

-- Seed Transactions (70% of total = 70,000 × :scale)
-- Insert in batches of 100K to avoid memory issues at large scale
DO $$
DECLARE
    total_rows BIGINT := 70000 * :scale;
    batch_size BIGINT := 100000;
    inserted BIGINT := 0;
    remaining BIGINT;
    user_count BIGINT := 20000 * :scale;
    corp_count BIGINT := 10000 * :scale;
BEGIN
    WHILE inserted < total_rows LOOP
        remaining := LEAST(batch_size, total_rows - inserted);
        
        INSERT INTO transaction_record (user_id, corporate_id, amount, currency, tx_type, status, description, created_at, completed_at, reference_code)
        SELECT
            1 + ((inserted + i) % user_count),
            1 + ((inserted + i) % corp_count),
            ROUND((random() * 100000)::NUMERIC, 2),
            (ARRAY['THB','USD','JPY','SGD'])[1 + ((inserted + i) % 4)],
            (ARRAY['payment','refund','transfer','fee'])[1 + ((inserted + i) % 4)],
            (ARRAY['pending','completed','completed','completed','failed','cancelled'])[1 + ((inserted + i) % 6)],
            'Transaction #' || (inserted + i),
            NOW() - (random() * INTERVAL '2 years'),
            CASE WHEN random() > 0.2 THEN NOW() - (random() * INTERVAL '1 year') ELSE NULL END,
            'REF' || LPAD((inserted + i)::TEXT, 12, '0')
        FROM generate_series(1, remaining) AS s(i);
        
        inserted := inserted + remaining;
        RAISE NOTICE 'Inserted % / % transactions', inserted, total_rows;
    END LOOP;
END $$;

-- Update statistics
ANALYZE corporate;
ANALYZE app_user;
ANALYZE transaction_record;

-- Verify counts
SELECT 'corporate' AS table_name, COUNT(*) AS row_count FROM corporate
UNION ALL
SELECT 'app_user', COUNT(*) FROM app_user
UNION ALL
SELECT 'transaction_record', COUNT(*) FROM transaction_record;
