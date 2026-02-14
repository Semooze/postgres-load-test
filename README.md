# PostgreSQL Benchmark Suite

## 📋 Overview

A comprehensive benchmark suite to evaluate PostgreSQL performance for production deployment with a **3-second response time SLA**. This includes four experiments comparing different PostgreSQL configurations, versions, and deployment strategies.

---

## Infrastructure Environment

| Component | Instance Type | Specs | Storage | Purpose |
|-----------|---------------|-------|---------|---------|
| RDS PostgreSQL | db.r7i.xlarge | 4 vCPU, 32 GB RAM | gp3 (100GB, 3000 IOPS) | Experiments 1, 2, 3 |
| Aurora PostgreSQL | db.r7i.xlarge | 4 vCPU, 32 GB RAM | Aurora Storage (auto) | Experiments 1, 2 |
| Application | t3.medium | 2 vCPU, 4 GB RAM | - | Go API server, K6 load testing |

**Storage Notes:**

- **RDS:** Uses EBS gp3 storage. You specify type and size when creating the instance.
- **Aurora:** Uses Aurora's distributed storage (AWS-managed, auto-scales up to 128TB). No storage type selection needed.

**Network:** All instances deployed in the same Availability Zone (AZ) to minimize network latency.

---

## Experiments

### Experiment 1: Aurora 17.7 vs RDS 18.1 (Production Decision)

**Objective:** Determine the best managed PostgreSQL service for production workloads.

| Configuration | Engine | Version | State |
|---------------|--------|---------|-------|
| Aurora PostgreSQL | Aurora | 17.7 | Tuned (if supported) |
| RDS PostgreSQL | Standard RDS | 18.1 | Tuned |

**Evaluation Criteria:**
- Performance: TPS, response time (p95/p99), SLA compliance
- Cost: Instance pricing, storage costs, I/O costs

**Note:** RDS supports parameter group tuning. Aurora tuning support is TBD - some parameters may be AWS-managed.

---

### Experiment 2: Aurora 17.7 vs RDS 17.7 (Same Version Comparison)

**Objective:** Compare Aurora vs RDS performance overhead on the same PostgreSQL version.

| Configuration | Engine | Version | State |
|---------------|--------|---------|-------|
| Aurora PostgreSQL | Aurora | 17.7 | Tuned (if supported) |
| RDS PostgreSQL | Standard RDS | 17.7 | Tuned |

**Note:** Uses data from Experiments 1 & 3. Isolates Aurora vs RDS differences without version upgrade impact.

---

### Experiment 3: RDS 18.1 vs RDS 17.7 (Version Comparison)

**Objective:** Measure performance improvements from PostgreSQL 17.7 to 18.1.

| Configuration | Version | State | Queries |
|---------------|---------|-------|---------|
| RDS PostgreSQL | 17.7 | Tuned | Q1-Q7 |
| RDS PostgreSQL | 18.1 | Tuned | Q1-Q7 |

**Note:** Both instances tuned identically via RDS parameter groups. Includes Query 7 (Skip Scan) to test PG 18's new skip scan optimization.

---

### Experiment 4: Tuning & Containerization Impact (EC2)

**Objective:** Evaluate the impact of configuration tuning, containerization overhead, and storage types on performance.

| Configuration | Tuning | Storage |
|---------------|--------|---------|
| EC2 Docker PostgreSQL 18.1 | Untuned | gp3 EBS |
| EC2 Docker PostgreSQL 18.1 | Tuned | gp3 EBS |
| EC2 Host PostgreSQL 18.1 | Tuned | gp3 EBS |
| EC2 Host PostgreSQL 18.1 | Tuned | Local NVMe |

**Note:** Compares Docker untuned vs Docker tuned vs Host tuned (gp3 vs NVMe) to measure tuning impact, Docker overhead, and storage performance.

---

## Tuning Configuration

| Environment | Method | Config File | Experiments |
|-------------|--------|-------------|-------------|
| RDS PostgreSQL | AWS Parameter Groups | `03_tuning_rds.md` | 1, 2, 3 |
| Aurora PostgreSQL | AWS Cluster Parameter Groups | `03_tuning_rds.md` | 1, 2 |
| EC2 Host/Docker | `ALTER SYSTEM` / postgresql.conf | `03_tuning_ec2.sql` | 4 |

**Notes:**
- RDS/Aurora: Cannot use `ALTER SYSTEM`. Must configure via AWS Console or CLI.
- Aurora: Some parameters are AWS-managed (WAL, checkpoints, I/O).
- EC2: Requires PostgreSQL restart after applying `ALTER SYSTEM` changes.

---

## Test Workload

### Query Types

| # | Type | Description | Tables |
|---|------|-------------|--------|
| 1 | Read Single | Point select + range scan with aggregation | 1 |
| 2 | Read Join 2 | Corporate → User join with filter | 2 |
| 3 | Read Join 3 | Corporate → User → Transaction with aggregation | 3 |
| 4 | Write Single | INSERT + UPDATE operations | 1 |
| 5 | ACID 2-Table | Transaction: insert transaction + update user | 2 |
| 6 | ACID 3-Table | Transaction: insert transaction + update user + update corporate | 3 |
| 7 | Skip Scan* | Composite index skip scan (PG 18 feature) | 1-2 |

*Query 7 is only used in Experiment 3 (RDS version comparison) to demonstrate PG 18 skip scan optimization.

### Dataset Sizes

| Scale | Corporate | User | Transaction | Total |
|-------|-----------|------|-------------|-------|
| 100K | 10,000 | 20,000 | 70,000 | 100K |
| 1M | 100,000 | 200,000 | 700,000 | 1M |
| 10M | 1,000,000 | 2,000,000 | 7,000,000 | 10M |

### Concurrency Levels

| Level | Clients | Scenario |
|-------|---------|----------|
| 1 | 1 | Baseline straight-line performance |
| 2 | 10 | Light load |
| 3 | 100 | Moderate production load |
| 4 | 1,000 | Heavy load (requires PgBouncer) |
| 5 | 10,000 | Stress test (requires PgBouncer) |

---

## 🛠️ Tools & Metrics

### Benchmarking Tools

| Tool | Purpose | Metrics |
|------|---------|---------|
| pgbench | Database-level benchmarking | TPS, latency (avg/stddev) |
| K6 | Application-level (Go API) load testing | p50/p95/p99 latency, QPS, SLA compliance |

### Collected Metrics

| Metric | Source | Purpose |
|--------|--------|---------|
| QPS / TPS | Both | Throughput capacity |
| Avg Latency | Both | General performance indicator |
| p50 Latency | K6 | Median response time |
| p95 Latency | K6 | Tail latency (SLA target) |
| p99 Latency | K6 | Worst-case latency |
| SLA Breach Count | K6 | Requests exceeding 3 seconds |
| Error Rate | K6 | Connection/query failures |

---

## 📁 Project Structure

```
pg-benchmark/
├── 01_schema.sql              # Table definitions and indexes
├── 02_seed_data.sql           # Data generation (configurable scale)
├── 03_tuning_rds.md           # RDS/Aurora tuning (Parameter Groups) - Exp 1-3
├── 03_tuning_ec2.sql          # EC2 tuning (ALTER SYSTEM) - Exp 4
├── README.md                  # This file
├── run_benchmark.sh           # pgbench automation script (Q1-Q6)
├── run_benchmark_q7.sh        # Q7 skip scan benchmark (Experiment 3 only)
├── app/
│   ├── go.mod                 # Go module dependencies
│   ├── main.go                # Go API server
│   ├── handlers.go            # HTTP handlers for benchmark queries (Q1-Q7)
│   ├── k6_benchmark.js        # K6 load test script (Q1-Q6)
│   ├── k6_q7.js               # K6 load test script (Q7 skip scan only)
│   ├── run_k6_suite.sh        # K6 test suite runner (Q1-Q6)
│   ├── run_k6_q7.sh           # K6 Q7 skip scan runner (Experiment 3)
│   └── setup_ec2.sh           # EC2 environment setup script
└── queries/
    ├── q1_read_single.sql     # Query 1: Single table read
    ├── q2_read_join2.sql      # Query 2: 2-table join
    ├── q3_read_join3.sql      # Query 3: 3-table join
    ├── q4_write_single.sql    # Query 4: Single table write
    ├── q5_acid_2table.sql     # Query 5: ACID 2-table transaction
    ├── q6_acid_3table.sql     # Query 6: ACID 3-table transaction
    └── q7_skip_scan.sql       # Query 7: Skip scan (PG 18 feature)
```

---

## 🚀 Quick Start

### Prerequisites
- PostgreSQL client tools (`psql`)
- K6 installed
- Go 1.19+ (for the API server)
- Access to target PostgreSQL instance

### Step 1: Initialize Database Schema

```bash
psql -h <host> -U <user> -d <db> -f 01_schema.sql
```

### Step 2: Seed Test Data

```bash
# Load 1M rows (adjust scale value as needed)
psql -h <host> -U <user> -d <db> -v scale=10 -f 02_seed_data.sql
```

### Step 3: Apply Tuning Parameters (Optional)

For tuned configurations:

```bash
# RDS/Aurora (Exp 1-3): Use AWS Parameter Groups
# See 03_tuning_rds.md for AWS CLI commands

# EC2 Self-Managed (Exp 4): Use ALTER SYSTEM
psql -h <host> -U <user> -d <db> -f 03_tuning_ec2.sql
sudo systemctl restart postgresql  # Apply changes
```

### Step 4: Run Database-Level Benchmarks

```bash
chmod +x run_benchmark.sh

# Run pgbench tests (1 minute duration)
./run_benchmark.sh <host> <db> <user> <password> 1m aurora_17.7
./run_benchmark.sh <host> <db> <user> <password> 1m rds_18.1
```

### Step 5: Run Application-Level Load Tests with K6

```bash
k6 run --env BASE_URL=http://your-go-api:8080 --env DATASET=1m app/k6_benchmark.js
```

### Step 6: Compare Query Execution Plans

For Experiment 3, compare the execution plans to observe PG 18's skip scan optimization:

```bash
# Test on RDS 17.7
psql -h rds17 -U <user> -d <db> -c "EXPLAIN (ANALYZE, BUFFERS) SELECT corporate_id, COUNT(*) FROM transactions GROUP BY corporate_id;"

# Test on RDS 18.1
psql -h rds18 -U <user> -d <db> -c "EXPLAIN (ANALYZE, BUFFERS) SELECT corporate_id, COUNT(*) FROM transactions GROUP BY corporate_id;"
```

---

## EC2 Deployment Setup

Commands are annotated with where they should be run:
- `[LOCAL]` - Run from your local machine
- `[EC2]` - Run on the EC2 app server (t3.medium)

### Enable T3 Unlimited Mode

Enable unlimited CPU burst mode on the app server to prevent throttling during high-concurrency tests:

```bash
# [LOCAL] Check current credit specification
aws ec2 describe-instance-credit-specifications --instance-ids <instance-id>

# [LOCAL] Enable unlimited mode
aws ec2 modify-instance-credit-specification \
    --instance-credit-specification "InstanceId=<instance-id>,CpuCredits=unlimited"
```

**Note:** Unlimited mode incurs additional charges when CPU usage exceeds baseline (20% for t3.medium). Monitor costs in AWS Cost Explorer.

### Upload and Initialize

```bash
# [LOCAL] 1. Upload benchmark folder to EC2
scp -r . ubuntu@<ec2-ip>:~/pg-benchmark/

# [LOCAL] 2. Connect to EC2
ssh ubuntu@<ec2-ip>

# [EC2] 3. Run setup script
cd ~/pg-benchmark/app
chmod +x setup_ec2.sh
./setup_ec2.sh
```

### Database Initialization

```bash
# [EC2] 4. Initialize database schema and seed data
psql -h <rds-endpoint> -U postgres -d benchdb -f ../01_schema.sql
psql -h <rds-endpoint> -U postgres -d benchdb -v scale=10 -f ../02_seed_data.sql
```

### Start API and Run Tests

```bash
# [EC2] 5. Start the Go API server
export DATABASE_URL='postgresql://postgres:<password>@<rds-endpoint>:5432/benchdb?sslmode=require'
./benchmark-api

# [EC2] 6. In another terminal, run K6 benchmark suite
./run_k6_suite.sh http://localhost:8080 1m aurora_17.7_run1
```

---
