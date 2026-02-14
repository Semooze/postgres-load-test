## Test Execution Steps

Complete workflow for Experiments 1 & 2. Both experiments will run with tuned configurations where possible.

- **RDS:** Tuning applied via parameter groups
- **Aurora:** Tuning applied if supported (some parameters may be AWS-managed)

### Execution Environment

Commands are annotated with where they should be run:
- `[LOCAL]` - Run from your local machine
- `[EC2]` - Run on the EC2 app server (t3.medium)

### Enable T3 Unlimited Mode (Before Testing)

Enable unlimited CPU burst mode on the app server to prevent throttling during high-concurrency tests:

```bash
# [LOCAL] Check current credit specification
aws ec2 describe-instance-credit-specifications --instance-ids <instance-id>

# [LOCAL] Enable unlimited mode
aws ec2 modify-instance-credit-specification \
    --instance-credit-specification "InstanceId=<instance-id>,CpuCredits=unlimited"
```

**Note:** Unlimited mode incurs additional charges when CPU usage exceeds baseline (20% for t3.medium).

### Test Order (Consolidated)

| Order | Subject | Queries | Purpose |
| ----- | ------- | ------- | ------- |
| 1 | RDS 17.7 | Q1-Q7 (7 queries) | Version baseline + skip scan absent |
| 2 | RDS 18.1 | Q1-Q7 (7 queries) | Version comparison + skip scan optimization |
| 3 | Aurora 17.7 | Q1-Q6 (6 queries) | Managed service comparison (no Q7 - same PG version) |

**Rationale:** RDS 17.7 and 18.1 are tested back-to-back with Q7 to directly compare PG 18's skip scan optimization. Aurora 17.7 skips Q7 since it's also PG 17.

---

### Script Usage

```bash
./run_benchmark.sh <host> <db_name> <db_user> <db_pass> <dataset_size> <label>
```

**Parameters:**

- `<dataset_size>`: `100k` | `1m` | `10m` (dataset scale, NOT duration)
- `<label>`: Database engine/version identifier (e.g., `rds_17.7`, `rds_18.1`, `aurora_17.7`)

**Note:** The script includes a built-in 60-second warmup phase.

---

### Pre-Test Checklist

```bash
# [EC2] Check autovacuum status (should show no running autovacuum jobs)
psql -h <host> -U <user> -d <db> -c "SELECT pid, usename, query FROM pg_stat_activity WHERE query LIKE '%autovacuum%';"

# [EC2] Monitor WAL/checkpoint activity
psql -h <host> -U <user> -d <db> -c "SELECT * FROM pg_stat_bgwriter;"
```

**For RDS/Aurora:** Cannot disable autovacuum, but run `VACUUM ANALYZE` manually before tests so autovacuum has minimal work.

---

### Initialization (Once Per Subject)

```bash
# [LOCAL] 1. SSH into EC2 app server
ssh ubuntu@<ec2-ip>

# [EC2] 2. Setup EC2 + install tools
cd ~/pg-benchmark/app
chmod +x setup_ec2.sh
./setup_ec2.sh

# [EC2] 3. Create database on target instance
psql -h <host> -U postgres -c "CREATE DATABASE benchdb;"
```

---

## Subject 1: RDS 17.7 (7 Queries, Tuned)

Tests Q1-Q7 including skip scan to establish PG 17 baseline. Tuning applied via RDS parameter group.

### Scale 1: 100K Rows

```bash
# [EC2] Initialize schema and seed data
psql -h <rds17-host> -U postgres -d benchdb -f 01_schema.sql
psql -h <rds17-host> -U postgres -d benchdb -v scale=1 -f 02_seed_data.sql
psql -h <rds17-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark (Q1-Q6)
./run_benchmark.sh <rds17-host> benchdb postgres <pass> 100k rds_17.7

# [EC2] Run Q7 skip scan benchmark
./run_benchmark_q7.sh <rds17-host> benchdb postgres <pass> 100k rds_17.7
```

### Scale 2: 1M Rows

```bash
# [EC2] Scale transition
psql -h <rds17-host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <rds17-host> -U postgres -d benchdb -v scale=10 -f 02_seed_data.sql
psql -h <rds17-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark (Q1-Q6)
./run_benchmark.sh <rds17-host> benchdb postgres <pass> 1m rds_17.7

# [EC2] Run Q7 skip scan benchmark
./run_benchmark_q7.sh <rds17-host> benchdb postgres <pass> 1m rds_17.7
```

### Scale 3: 10M Rows

```bash
# [EC2] Scale transition
psql -h <rds17-host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <rds17-host> -U postgres -d benchdb -v scale=100 -f 02_seed_data.sql
psql -h <rds17-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark (Q1-Q6)
./run_benchmark.sh <rds17-host> benchdb postgres <pass> 10m rds_17.7

# [EC2] Run Q7 skip scan benchmark
./run_benchmark_q7.sh <rds17-host> benchdb postgres <pass> 10m rds_17.7
```

### Cleanup RDS 17.7

```bash
# [EC2] Drop database
psql -h <rds17-host> -U postgres -c "DROP DATABASE benchdb;"
# Optionally terminate instance after all tests complete
```

---

## Subject 2: RDS 18.1 (7 Queries, Tuned)

Tests Q1-Q7 including skip scan to demonstrate PG 18 optimization. Tuning applied via RDS parameter group.

### Scale 1: 100K Rows

```bash
# [EC2] Initialize schema and seed data
psql -h <rds18-host> -U postgres -d benchdb -f 01_schema.sql
psql -h <rds18-host> -U postgres -d benchdb -v scale=1 -f 02_seed_data.sql
psql -h <rds18-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark (Q1-Q6)
./run_benchmark.sh <rds18-host> benchdb postgres <pass> 100k rds_18.1

# [EC2] Run Q7 skip scan benchmark
./run_benchmark_q7.sh <rds18-host> benchdb postgres <pass> 100k rds_18.1
```

### Scale 2: 1M Rows

```bash
# [EC2] Scale transition
psql -h <rds18-host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <rds18-host> -U postgres -d benchdb -v scale=10 -f 02_seed_data.sql
psql -h <rds18-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark (Q1-Q6)
./run_benchmark.sh <rds18-host> benchdb postgres <pass> 1m rds_18.1

# [EC2] Run Q7 skip scan benchmark
./run_benchmark_q7.sh <rds18-host> benchdb postgres <pass> 1m rds_18.1
```

### Scale 3: 10M Rows

```bash
# [EC2] Scale transition
psql -h <rds18-host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <rds18-host> -U postgres -d benchdb -v scale=100 -f 02_seed_data.sql
psql -h <rds18-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark (Q1-Q6)
./run_benchmark.sh <rds18-host> benchdb postgres <pass> 10m rds_18.1

# [EC2] Run Q7 skip scan benchmark
./run_benchmark_q7.sh <rds18-host> benchdb postgres <pass> 10m rds_18.1
```

### Skip Scan Comparison (After Both RDS Tests)

Compare Q7 results between RDS 17.7 and 18.1:

```bash
# [LOCAL] Compare TPS and latency
diff results/rds_17.7/1m/q7_skip_scan_c100.txt results/rds_18.1/1m/q7_skip_scan_c100.txt

# [LOCAL] Compare execution plans (captured by run_benchmark_q7.sh)
diff results/rds_17.7/1m/q7_explain_analyze.txt results/rds_18.1/1m/q7_explain_analyze.txt
```

**Expected results:**
- RDS 17.7: Sequential/Index Scan (no skip scan support)
- RDS 18.1: Index Skip Scan on `idx_tx_corp_created`

### Cleanup RDS 18.1

```bash
# [EC2] Drop database
psql -h <rds18-host> -U postgres -c "DROP DATABASE benchdb;"
```

---

## Subject 3: Aurora 17.7 (6 Queries, Tuned if supported)

Tests Q1-Q6 only. Skips Q7 since Aurora is also PG 17 (no skip scan feature). Tuning applied via Aurora parameter group if supported - some parameters may be AWS-managed.

### Scale 1: 100K Rows

```bash
# [EC2] Initialize schema and seed data
psql -h <aurora-host> -U postgres -d benchdb -f 01_schema.sql
psql -h <aurora-host> -U postgres -d benchdb -v scale=1 -f 02_seed_data.sql
psql -h <aurora-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark
./run_benchmark.sh <aurora-host> benchdb postgres <pass> 100k aurora_17.7
```

### Scale 2: 1M Rows

```bash
# [EC2] Scale transition
psql -h <aurora-host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <aurora-host> -U postgres -d benchdb -v scale=10 -f 02_seed_data.sql
psql -h <aurora-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark
./run_benchmark.sh <aurora-host> benchdb postgres <pass> 1m aurora_17.7
```

### Scale 3: 10M Rows

```bash
# [EC2] Scale transition
psql -h <aurora-host> -U postgres -d benchdb -c "TRUNCATE corporate CASCADE;"
psql -h <aurora-host> -U postgres -d benchdb -v scale=100 -f 02_seed_data.sql
psql -h <aurora-host> -U postgres -d benchdb -c "VACUUM ANALYZE;"

# [EC2] Clear filesystem cache
echo 3 | sudo tee /proc/sys/vm/drop_caches

# [EC2] Run benchmark
./run_benchmark.sh <aurora-host> benchdb postgres <pass> 10m aurora_17.7
```

### Cleanup Aurora 17.7

```bash
# [EC2] Drop database
psql -h <aurora-host> -U postgres -c "DROP DATABASE benchdb;"
```

---

## Application-Level Testing (K6)

Run K6 tests after database-level benchmarks for each subject:

```bash
# [EC2] Start Go API server
export DATABASE_URL='postgresql://postgres:<pass>@<host>:5432/benchdb?sslmode=require'
cd app && ./benchmark-api &

# [EC2] Run K6 benchmark suite (Q1-Q6)
./run_k6_suite.sh http://localhost:8080 1m rds_17.7
./run_k6_suite.sh http://localhost:8080 1m rds_18.1
./run_k6_suite.sh http://localhost:8080 1m aurora_17.7

# [EC2] Run K6 Q7 skip scan (Experiment 3: RDS only)
./run_k6_q7.sh http://localhost:8080 1m steady_100 rds_17.7
./run_k6_q7.sh http://localhost:8080 1m steady_100 rds_18.1
```

---

## Monitoring Notes

**WAL/Checkpoint Spikes:** During write-heavy benchmarks, you may observe p99 latency spikes from PostgreSQL's periodic WAL checkpoints. Monitor with:

```bash
# [EC2] Monitor WAL/checkpoint activity
psql -h <host> -U postgres -d benchdb -c "SELECT * FROM pg_stat_bgwriter;"
```

**RDS/Aurora Constraints:**

- Cannot disable autovacuum, but manual `VACUUM ANALYZE` before tests minimizes background work
- Monitor database metrics in AWS Console for unexpected performance degradation

---

## Result Analysis

After running benchmarks, compare results across 4 experiments:

| Experiment | Subjects | Queries | Purpose |
|------------|----------|---------|---------|
| 1 | Aurora 17.7 vs RDS 18.1 | Q1-Q6 | Production decision |
| 2 | Aurora 17.7 vs RDS 17.7 | Q1-Q6 | Aurora vs RDS overhead (same PG version) |
| 3 | RDS 17.7 vs RDS 18.1 | Q1-Q7 | PG 18 improvements, skip scan optimization |
| 4 | EC2 Docker/Host | Q1-Q6 | Tuning & containerization impact |

### Key Metrics to Compare

- **TPS/QPS** - Throughput capacity
- **p95/p99 Latency** - Tail latency (SLA target: < 3000ms)
- **SLA Breach Count** - Requests exceeding 3 seconds
- **Q7 Skip Scan** - Compare TPS and execution plans between RDS 17.7 and 18.1

### Quick Comparison Commands

```bash
# [LOCAL] Experiment 1: Aurora 17.7 vs RDS 18.1 (production decision)
diff results/aurora_17.7/1m/q1_read_single_c100.txt results/rds_18.1/1m/q1_read_single_c100.txt

# [LOCAL] Experiment 2: Aurora 17.7 vs RDS 17.7 (same PG version)
diff results/aurora_17.7/1m/q1_read_single_c100.txt results/rds_17.7/1m/q1_read_single_c100.txt

# [LOCAL] Experiment 3: RDS 17.7 vs RDS 18.1 (version upgrade)
diff results/rds_17.7/1m/q1_read_single_c100.txt results/rds_18.1/1m/q1_read_single_c100.txt

# [LOCAL] Experiment 3: Q7 Skip Scan (pgbench)
diff results/rds_17.7/1m/q7_skip_scan_c100.txt results/rds_18.1/1m/q7_skip_scan_c100.txt

# [LOCAL] Experiment 3: Q7 Skip Scan (K6)
diff results/rds_17.7/1m/q7_k6_steady_100_summary.txt results/rds_18.1/1m/q7_k6_steady_100_summary.txt
```

Review the generated reports for QPS, latency percentiles, and SLA compliance metrics. Document any WAL checkpoint spikes or autovacuum interference in results.
