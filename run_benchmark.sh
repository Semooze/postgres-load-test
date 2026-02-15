#!/bin/bash
# ============================================================
# PostgreSQL Benchmark Runner (pgbench - Database Level)
# Runs Q1-Q6 queries directly against the database using pgbench
#
# Run from: EC2 App Server (m8g.xlarge)
# Target:   RDS/Aurora database directly (not through Go API)
#
# Usage: ./run_benchmark.sh <db_host> <db_name> <db_user> <db_pass> <dataset_size> <label>
#
# dataset_size: 100k | 1m | 10m
# label: e.g., "aurora_17.7" or "rds_18.1"
#
# Example:
#   ./run_benchmark.sh mydb.cluster.amazonaws.com benchdb postgres mypass 1m aurora_17.7
# ============================================================

set -euo pipefail

DB_HOST=$1
DB_NAME=$2
DB_USER=$3
DB_PASS=$4
DATASET_SIZE=$5
LABEL=$6

export PGPASSWORD="$DB_PASS"

# Output directory
RESULTS_DIR="results/${LABEL}/${DATASET_SIZE}"
mkdir -p "$RESULTS_DIR"

# Determine max IDs based on dataset size
case $DATASET_SIZE in
    100k)
        MAX_CORP_ID=10000
        MAX_USER_ID=20000
        MAX_TX_ID=70000
        SCALE=1
        ;;
    1m)
        MAX_CORP_ID=100000
        MAX_USER_ID=200000
        MAX_TX_ID=700000
        SCALE=10
        ;;
    10m)
        MAX_CORP_ID=1000000
        MAX_USER_ID=2000000
        MAX_TX_ID=7000000
        SCALE=100
        ;;
    *)
        echo "Invalid dataset size: $DATASET_SIZE (use 100k, 1m, 10m)"
        exit 1
        ;;
esac

# Concurrency levels to test
CONCURRENCY_LEVELS=(1 10 100 1000)

# Duration per test in seconds (300 = 5 minutes)
DURATION=300

# Warmup duration in seconds
WARMUP=60

echo "============================================================"
echo "Benchmark: $LABEL | Dataset: $DATASET_SIZE"
echo "Host: $DB_HOST | DB: $DB_NAME"
echo "Max IDs → Corp: $MAX_CORP_ID, User: $MAX_USER_ID, Tx: $MAX_TX_ID"
echo "Duration: ${DURATION}s per test, Warmup: ${WARMUP}s"
echo "Concurrency levels: ${CONCURRENCY_LEVELS[*]}"
echo "============================================================"

# Function to run a single pgbench test
run_pgbench() {
    local query_name=$1
    local query_file=$2
    local clients=$3
    local threads=$((clients < 8 ? clients : 8))  # max 8 threads
    
    if [ $threads -lt 1 ]; then threads=1; fi
    
    local outfile="${RESULTS_DIR}/${query_name}_c${clients}.txt"
    
    echo ""
    echo "--- Running: ${query_name} | Clients: ${clients} | Threads: ${threads} ---"
    
    pgbench \
        -h "$DB_HOST" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -f "$query_file" \
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
# Warmup phase
# ============================================================
echo ""
echo "============================================================"
echo "WARMUP PHASE (${WARMUP}s)"
echo "============================================================"
pgbench \
    -h "$DB_HOST" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -f queries/q1_read_single.sql \
    -c 10 -j 4 -T "$WARMUP" \
    -D max_corp_id="$MAX_CORP_ID" \
    -D max_user_id="$MAX_USER_ID" \
    -D max_tx_id="$MAX_TX_ID" \
    > /dev/null 2>&1
echo "Warmup complete."

# ============================================================
# Run all queries at all concurrency levels
# ============================================================
QUERIES=(
    "q1_read_single:queries/q1_read_single.sql"
    "q2_read_join2:queries/q2_read_join2.sql"
    "q3_read_join3:queries/q3_read_join3.sql"
    "q4_write_single:queries/q4_write_single.sql"
    "q5_acid_2table:queries/q5_acid_2table.sql"
    "q6_acid_3table:queries/q6_acid_3table.sql"
)

for query_entry in "${QUERIES[@]}"; do
    IFS=':' read -r query_name query_file <<< "$query_entry"
    
    echo ""
    echo "============================================================"
    echo "QUERY: $query_name"
    echo "============================================================"
    
    for clients in "${CONCURRENCY_LEVELS[@]}"; do
        run_pgbench "$query_name" "$query_file" "$clients"
        
        # Brief pause between tests to let the DB settle
        sleep 5
    done
done

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================================"
echo "ALL BENCHMARKS COMPLETE"
echo "Results directory: $RESULTS_DIR"
echo "============================================================"
echo ""
echo "Files generated:"
ls -la "$RESULTS_DIR/"
