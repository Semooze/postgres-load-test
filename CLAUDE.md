# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PostgreSQL benchmark suite for evaluating production deployment with a 3-second response time SLA. Compares Aurora vs RDS, PostgreSQL versions (17.7 vs 18.1), and infrastructure configurations (tuning, Docker vs host, storage types).

## Prerequisites

- **PostgreSQL client tools** - `psql`, `pgbench`
- **K6** - Load testing tool
- **Go 1.22+** - For building the API server
- **Access to target PostgreSQL instance** - RDS, Aurora, or EC2-hosted

## Build Commands

### Go API Server

```bash
cd app
go build -o benchmark-api .
```

### EC2 Environment Setup

```bash
cd app && chmod +x setup_ec2.sh && ./setup_ec2.sh
```

## Test Execution Steps

### Step 1: Initialize Database

```bash
psql -h <host> -U postgres -c "CREATE DATABASE benchdb;"
psql -h <host> -U postgres -d benchdb -f 01_schema.sql
```

### Step 2: Seed Data

```bash
# scale: 1=100K, 10=1M, 100=10M rows
psql -h <host> -U postgres -d benchdb -v scale=10 -f 02_seed_data.sql
```

### Step 3: Pre-Test Checklist

```bash
# Run VACUUM ANALYZE before tests (minimizes autovacuum interference)
psql -h <host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# Check no autovacuum running
psql -h <host> -U postgres -d benchdb -c "SELECT pid, usename, query FROM pg_stat_activity WHERE query LIKE '%autovacuum%';"

# Clear filesystem cache on EC2 app host
ssh ubuntu@<ec2-ip> "echo 3 | sudo tee /proc/sys/vm/drop_caches"
```

### Step 4: Run pgbench (Database-Level)

```bash
chmod +x run_benchmark.sh
./run_benchmark.sh <host> <db_name> <db_user> <db_pass> <dataset_size> <label>
# dataset_size: 100k | 1m | 10m
# label: aurora_17.7, rds_18.1, rds_17.7_tuned, etc.
# Includes automatic 60s warmup phase
```

### Step 5: Run K6 (Application-Level)

```bash
# Start API server
export DATABASE_URL='postgresql://postgres:<password>@<host>:5432/benchdb?sslmode=require'
cd app && ./benchmark-api &

# Run full K6 suite (in separate terminal)
./run_k6_suite.sh http://localhost:8080 1m aurora_17.7_run1

# Or run single scenario
k6 run --env BASE_URL=http://localhost:8080 --env DATASET=1m --env SCENARIO=steady_100 k6_benchmark.js
```

### Step 6: Scale Transition (Between Dataset Sizes)

```bash
# Truncate and re-seed for next scale
psql -h <host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <host> -U postgres -d benchdb -v scale=100 -f 02_seed_data.sql
psql -h <host> -U postgres -d benchdb -c "VACUUM ANALYZE;"
```

### Step 7: Cleanup

```bash
psql -h <host> -U postgres -c "DROP DATABASE benchdb;"
```

## Key Metrics to Monitor

- `http_req_duration p(95)` - Should be < 3000ms (SLA target)
- `sla_breaches_3s` - Should be 0 or near 0
- `success_rate` - Should be > 99%
- Per-query p95: `q1_read_single_ms`, `q2_read_join2_ms`, `q3_read_join3_ms`, `q4_write_single_ms`, `q5_acid_2table_ms`, `q6_acid_3table_ms`, `q7_skip_scan_ms`

## Monitoring During Tests

```bash
# WAL/checkpoint activity (p99 spikes often correlate with checkpoints)
psql -h <host> -U postgres -d benchdb -c "SELECT * FROM pg_stat_bgwriter;"
```

## Architecture

### Database Schema

Three tables with 10%/20%/70% row distribution:

- `corporate` - Business entities with credit limits
- `app_user` - Users belonging to corporates
- `transaction_record` - Financial transactions

### Go API (app/)

Echo framework with pgx connection pool. Endpoints map to benchmark query types:

- `main.go` - Server setup, connection pool config (100 max, 10 min connections)
- `handlers.go` - Query implementations (Q1-Q7)

### Query Types (queries/)

| Query | Type        | Tables | Endpoint                                                             |
| ----- | ----------- | ------ | -------------------------------------------------------------------- |
| Q1    | Read single | 1      | `/api/transactions/:id`, `/api/transactions/summary/:corporate_id`   |
| Q2    | Read join   | 2      | `/api/corporates/:id/users`                                          |
| Q3    | Read join   | 3      | `/api/corporates/:id/report`                                         |
| Q4    | Write       | 1      | `POST /api/transactions`                                             |
| Q5    | ACID        | 2      | `POST /api/transactions/with-activity`                               |
| Q6    | ACID        | 3      | `POST /api/transactions/full-process`                                |
| Q7    | Skip Scan   | 1-2    | `/api/skip-scan/recent-corporates`, `/api/skip-scan/distinct-corporates`, `/api/skip-scan/active-corporates` |

### K6 Test Script (app/k6_benchmark.js)

Scenarios: `ramp`, `steady_1`, `steady_10`, `steady_100`, `steady_1000`

- Tracks per-query latency metrics (q1_read_single_ms, etc.)
- SLA breach counter (3s threshold)
- 60/40 read/write distribution

### Benchmark Scripts

- `run_benchmark.sh` - pgbench automation with 60s warmup, tests Q1-Q6 at concurrency 1/10/100/1000
- `run_benchmark_q7.sh` - pgbench Q7 skip scan benchmark (Experiment 3 only)
- `app/run_k6_suite.sh` - Runs all K6 scenarios with health checks and cooldown periods (Q1-Q6)
- `app/run_k6_q7.sh` - K6 Q7 skip scan benchmark (Experiment 3 only)

## Dataset Scale Values

| Scale | Rows | Corporate | User      | Transaction |
| ----- | ---- | --------- | --------- | ----------- |
| 1     | 100K | 10,000    | 20,000    | 70,000      |
| 10    | 1M   | 100,000   | 200,000   | 700,000     |
| 100   | 10M  | 1,000,000 | 2,000,000 | 7,000,000   |
