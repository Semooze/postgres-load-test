#!/bin/bash
# ============================================================
# PostgreSQL Benchmark Runner - Q7 Skip Scan Only
# For Experiment 2: RDS 17.7 vs RDS 18.1 comparison
#
# Run this AFTER run_benchmark.sh to add Q7 results
#
# Usage: ./run_benchmark_q7.sh <db_host> <db_name> <db_user> <db_pass> <dataset_size> <label>
#
# Example:
#   ./run_benchmark_q7.sh mydb.rds.amazonaws.com benchdb postgres mypass 1m rds_18.1
# ============================================================

set -euo pipefail

DB_HOST=$1
DB_NAME=$2
DB_USER=$3
DB_PASS=$4
DATASET_SIZE=$5
LABEL=$6

export PGPASSWORD="$DB_PASS"

# Output directory (same as run_benchmark.sh)
RESULTS_DIR="results/${LABEL}/${DATASET_SIZE}"
mkdir -p "$RESULTS_DIR"

# Determine max IDs based on dataset size
case $DATASET_SIZE in
    100k)
        MAX_CORP_ID=10000
        MAX_USER_ID=20000
        MAX_TX_ID=70000
        ;;
    1m)
        MAX_CORP_ID=100000
        MAX_USER_ID=200000
        MAX_TX_ID=700000
        ;;
    10m)
        MAX_CORP_ID=1000000
        MAX_USER_ID=2000000
        MAX_TX_ID=7000000
        ;;
    *)
        echo "Invalid dataset size: $DATASET_SIZE (use 100k, 1m, 10m)"
        exit 1
        ;;
esac

# Concurrency levels to test
CONCURRENCY_LEVELS=(1 10 100 1000)

# Duration per test in seconds
DURATION=300

echo "============================================================"
echo "Q7 Skip Scan Benchmark (Experiment 2)"
echo "============================================================"
echo "Label: $LABEL | Dataset: $DATASET_SIZE"
echo "Host: $DB_HOST | DB: $DB_NAME"
echo "Duration: ${DURATION}s per test"
echo "Concurrency levels: ${CONCURRENCY_LEVELS[*]}"
echo "============================================================"

# Function to run pgbench
run_pgbench() {
    local clients=$1
    local threads=$((clients < 8 ? clients : 8))
    if [ $threads -lt 1 ]; then threads=1; fi

    local outfile="${RESULTS_DIR}/q7_skip_scan_c${clients}.txt"

    echo ""
    echo "--- Running: q7_skip_scan | Clients: ${clients} | Threads: ${threads} ---"

    pgbench \
        -h "$DB_HOST" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -f queries/q7_skip_scan.sql \
        -c "$clients" \
        -j "$threads" \
        -T "$DURATION" \
        -P 10 \
        --random-seed=42 \
        -D max_corp_id="$MAX_CORP_ID" \
        -D max_user_id="$MAX_USER_ID" \
        -D max_tx_id="$MAX_TX_ID" \
        2>&1 | tee "$outfile"

    echo "Results saved to: $outfile"
}

# ============================================================
# Run Q7 at all concurrency levels
# ============================================================
echo ""
echo "============================================================"
echo "QUERY: q7_skip_scan"
echo "============================================================"

for clients in "${CONCURRENCY_LEVELS[@]}"; do
    run_pgbench "$clients"
    sleep 5
done

# ============================================================
# Capture EXPLAIN ANALYZE for skip scan verification
# ============================================================
echo ""
echo "============================================================"
echo "SKIP SCAN EXPLAIN ANALYZE"
echo "============================================================"

EXPLAIN_FILE="${RESULTS_DIR}/q7_explain_analyze.txt"

echo "Capturing execution plans..." | tee "$EXPLAIN_FILE"
echo "" >> "$EXPLAIN_FILE"
echo "=== Query 7a: Range on second column ===" >> "$EXPLAIN_FILE"

psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    corporate_id,
    COUNT(*) AS tx_count,
    SUM(amount) AS total_amount
FROM transaction_record
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
GROUP BY corporate_id
ORDER BY total_amount DESC
LIMIT 20;
" >> "$EXPLAIN_FILE" 2>&1

echo "" >> "$EXPLAIN_FILE"
echo "=== Query 7b: DISTINCT on leading column ===" >> "$EXPLAIN_FILE"

psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT DISTINCT corporate_id
FROM transaction_record
WHERE created_at >= NOW() - INTERVAL '30 days';
" >> "$EXPLAIN_FILE" 2>&1

echo ""
echo "Execution plans saved to: $EXPLAIN_FILE"
cat "$EXPLAIN_FILE"

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================================"
echo "Q7 BENCHMARK COMPLETE"
echo "Results directory: $RESULTS_DIR"
echo "============================================================"
echo ""
echo "Q7 files generated:"
ls -la "$RESULTS_DIR"/q7_*
echo ""
echo "Compare between RDS 17.7 and RDS 18.1:"
echo "  - TPS/latency: q7_skip_scan_c*.txt"
echo "  - Execution plans: q7_explain_analyze.txt"
echo "  - PG 18 should show 'Index Skip Scan' in the plan"
