#!/bin/bash
# ============================================================
# Run K6 Benchmark Suite
# Runs all scenarios for a given experiment configuration
#
# Usage: ./run_k6_suite.sh <base_url> <dataset> <label>
# Example: ./run_k6_suite.sh http://localhost:8080 1m aurora_17.7_run1
#
# Results are saved to: results/<label>/
# ============================================================

set -euo pipefail

BASE_URL=${1:?"Usage: $0 <base_url> <dataset> <label>"}
DATASET=${2:?"Usage: $0 <base_url> <dataset> <label>"}
LABEL=${3:?"Usage: $0 <base_url> <dataset> <label>"}

RESULTS_DIR="results/${LABEL}/${DATASET}"
mkdir -p "$RESULTS_DIR"

echo "============================================================"
echo "K6 Benchmark Suite"
echo "URL:     $BASE_URL"
echo "Dataset: $DATASET"
echo "Label:   $LABEL"
echo "Output:  $RESULTS_DIR/"
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
curl -s "${BASE_URL}/health" | python3 -m json.tool 2>/dev/null || curl -s "${BASE_URL}/health"
echo ""

# ============================================================
# Run scenarios: steady load at each concurrency level
# ============================================================
SCENARIOS=("steady_1" "steady_10" "steady_100" "steady_1000")

for scenario in "${SCENARIOS[@]}"; do
    echo ""
    echo "============================================================"
    echo "SCENARIO: $scenario"
    echo "============================================================"
    
    OUTPUT_FILE="${RESULTS_DIR}/${scenario}.json"
    SUMMARY_FILE="${RESULTS_DIR}/${scenario}_summary.txt"
    
    k6 run \
        --env BASE_URL="$BASE_URL" \
        --env DATASET="$DATASET" \
        --env SCENARIO="$scenario" \
        --out json="$OUTPUT_FILE" \
        --summary-export="${RESULTS_DIR}/${scenario}_export.json" \
        k6_benchmark.js \
        2>&1 | tee "$SUMMARY_FILE"
    
    echo ""
    echo "Results saved:"
    echo "  Summary: $SUMMARY_FILE"
    echo "  Raw data: $OUTPUT_FILE"
    echo "  Export: ${RESULTS_DIR}/${scenario}_export.json"
    
    # Pause between scenarios
    echo ""
    echo "Cooling down for 30 seconds..."
    sleep 30
done

# ============================================================
# Run ramp test (all concurrency levels in one run)
# ============================================================
echo ""
echo "============================================================"
echo "SCENARIO: ramp (1 → 10 → 100 → 1000 req/s)"
echo "============================================================"

k6 run \
    --env BASE_URL="$BASE_URL" \
    --env DATASET="$DATASET" \
    --env SCENARIO="ramp" \
    --out json="${RESULTS_DIR}/ramp.json" \
    --summary-export="${RESULTS_DIR}/ramp_export.json" \
    k6_benchmark.js \
    2>&1 | tee "${RESULTS_DIR}/ramp_summary.txt"

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================================"
echo "ALL K6 SCENARIOS COMPLETE"
echo "============================================================"
echo ""
echo "Results directory: $RESULTS_DIR/"
ls -la "$RESULTS_DIR/"
echo ""
echo "To view a summary:"
echo "  cat ${RESULTS_DIR}/steady_100_summary.txt"
echo ""
echo "Key metrics to compare:"
echo "  - http_req_duration p(95) — should be < 3000ms"
echo "  - q1_read_single_ms p(95)"
echo "  - q2_read_join2_ms p(95)"
echo "  - q3_read_join3_ms p(95)"
echo "  - q4_write_single_ms p(95)"
echo "  - q5_acid_2table_ms p(95)"
echo "  - q6_acid_3table_ms p(95)"
echo "  - sla_breaches_3s — should be 0 or near 0"
echo "  - success_rate — should be > 99%"
