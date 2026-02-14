-- ============================================================
-- PostgreSQL Benchmark Schema
-- Distribution: Corporate 10%, User 20%, Transaction 70%
-- Dataset sizes: 100K, 1M, 10M total rows
-- ============================================================

-- Corporate table (10% of total rows)
CREATE TABLE corporate (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    tax_id          VARCHAR(20) NOT NULL,
    industry        VARCHAR(50) NOT NULL,
    country         VARCHAR(3) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    credit_limit    NUMERIC(15,2) NOT NULL DEFAULT 0,
    metadata        JSONB
);

-- User table (20% of total rows)
CREATE TABLE app_user (
    id              BIGSERIAL PRIMARY KEY,
    corporate_id    BIGINT NOT NULL REFERENCES corporate(id),
    email           VARCHAR(255) NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    role            VARCHAR(30) NOT NULL,       -- 'admin', 'manager', 'staff', 'viewer'
    department      VARCHAR(50) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    profile         JSONB
);

-- Transaction table (70% of total rows)
CREATE TABLE transaction_record (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES app_user(id),
    corporate_id    BIGINT NOT NULL REFERENCES corporate(id),
    amount          NUMERIC(15,2) NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'THB',
    tx_type         VARCHAR(20) NOT NULL,       -- 'payment', 'refund', 'transfer', 'fee'
    status          VARCHAR(20) NOT NULL,       -- 'pending', 'completed', 'failed', 'cancelled'
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    reference_code  VARCHAR(50) NOT NULL
);

-- ============================================================
-- Indexes (realistic production indexes)
-- ============================================================

-- Corporate
CREATE INDEX idx_corporate_industry ON corporate(industry);
CREATE INDEX idx_corporate_country ON corporate(country);
CREATE INDEX idx_corporate_active ON corporate(is_active) WHERE is_active = TRUE;

-- User
CREATE INDEX idx_user_corporate ON app_user(corporate_id);
CREATE INDEX idx_user_email ON app_user(email);
CREATE INDEX idx_user_role ON app_user(role);
CREATE INDEX idx_user_department ON app_user(department);
CREATE INDEX idx_user_active ON app_user(is_active) WHERE is_active = TRUE;

-- Transaction
CREATE INDEX idx_tx_user ON transaction_record(user_id);
CREATE INDEX idx_tx_corporate ON transaction_record(corporate_id);
CREATE INDEX idx_tx_status ON transaction_record(status);
CREATE INDEX idx_tx_type ON transaction_record(tx_type);
CREATE INDEX idx_tx_created ON transaction_record(created_at);
CREATE INDEX idx_tx_reference ON transaction_record(reference_code);

-- Composite index for skip scan test (Experiment 2, Query 7)
-- PG 18 can skip scan on this when querying by created_at without corporate_id
CREATE INDEX idx_tx_corp_created ON transaction_record(corporate_id, created_at);

-- ============================================================
-- ANALYZE after data load
-- ============================================================
-- Run after seeding: ANALYZE corporate; ANALYZE app_user; ANALYZE transaction_record;
