#!/bin/bash
# ============================================================
# Run K6 Q7 Skip Scan Benchmark
# For Experiment 3: RDS 17.7 vs RDS 18.1 comparison
#
# Tests Q7 skip scan endpoints via Go API
# Run this AFTER run_k6_suite.sh for skip scan comparison
#
# Run from: EC2 Load Generator (m8g.medium)
# Target:   EC2 App Server (m8g.xlarge)
#
# Usage: ./run_k6_q7.sh <base_url> <dataset> <scenario> <label>
#
# Scenarios: steady_1 | steady_10 | steady_100 | steady_1000 | ramp
#
# Example:
#   ./run_k6_q7.sh http://<ec2-app-private-ip>:8080 1m steady_100 rds_18.1
# ============================================================

set -euo pipefail

BASE_URL=${1:?"Usage: $0 <base_url> <dataset> <scenario> <label>"}
DATASET=${2:?"Usage: $0 <base_url> <dataset> <scenario> <label>"}
SCENARIO=${3:?"Usage: $0 <base_url> <dataset> <scenario> <label>"}
LABEL=${4:?"Usage: $0 <base_url> <dataset> <scenario> <label>"}

# Validate scenario
VALID_SCENARIOS=("steady_1" "steady_10" "steady_100" "steady_1000" "ramp")
VALID=false
for s in "${VALID_SCENARIOS[@]}"; do
    if [ "$SCENARIO" == "$s" ]; then
        VALID=true
        break
    fi
done

if [ "$VALID" != "true" ]; then
    echo "Invalid scenario: $SCENARIO"
    echo "Valid scenarios: ${VALID_SCENARIOS[*]}"
    exit 1
fi

RESULTS_DIR="results/${LABEL}/${DATASET}"
mkdir -p "$RESULTS_DIR"

echo "============================================================"
echo "K6 Q7 Skip Scan Benchmark (Experiment 2)"
echo "============================================================"
echo "URL:      $BASE_URL"
echo "Dataset:  $DATASET"
echo "Scenario: $SCENARIO"
echo "Label:    $LABEL"
echo "Output:   $RESULTS_DIR/"
echo "============================================================"

# Health check
echo ""
echo "--- Health Check ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health")
if [ "$HTTP_CODE" != "200" ]; then
    echo "FAILED: API health check returned $HTTP_CODE"
    echo "Make sure the Go API is running at $BASE_URL"
    exit 1
fi
echo "API is healthy"

# Test skip scan endpoints are available
echo ""
echo "--- Checking Q7 Endpoints ---"
for endpoint in "recent-corporates" "distinct-corporates" "active-corporates"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/skip-scan/${endpoint}")
    if [ "$HTTP_CODE" != "200" ]; then
        echo "WARNING: /api/skip-scan/${endpoint} returned $HTTP_CODE"
    else
        echo "OK: /api/skip-scan/${endpoint}"
    fi
done

# Run K6 with Q7 only function
echo ""
echo "============================================================"
echo "Running: Q7 Skip Scan - $SCENARIO"
echo "============================================================"

OUTPUT_FILE="${RESULTS_DIR}/q7_k6_${SCENARIO}.json"
SUMMARY_FILE="${RESULTS_DIR}/q7_k6_${SCENARIO}_summary.txt"

k6 run \
    --env BASE_URL="$BASE_URL" \
    --env DATASET="$DATASET" \
    --env SCENARIO="$SCENARIO" \
    --out json="$OUTPUT_FILE" \
    --summary-export="${RESULTS_DIR}/q7_k6_${SCENARIO}_export.json" \
    -e QUERY_FUNC=q7Only \
    k6_q7.js \
    2>&1 | tee "$SUMMARY_FILE"

echo ""
echo "============================================================"
echo "Q7 K6 BENCHMARK COMPLETE"
echo "============================================================"
echo ""
echo "Results saved:"
echo "  Summary: $SUMMARY_FILE"
echo "  Raw data: $OUTPUT_FILE"
echo "  Export: ${RESULTS_DIR}/q7_k6_${SCENARIO}_export.json"
echo ""
echo "Compare between RDS 17.7 and RDS 18.1:"
echo "  - q7_skip_scan_ms p(95) — PG 18 should be faster"
echo "  - success_rate — should be > 99%"
