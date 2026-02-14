// ============================================================
// K6 Load Test for Q7 Skip Scan (Experiment 2)
// Tests PG 18 skip scan optimization via Go API
//
// Usage:
//   ./run_k6_q7.sh http://localhost:8080 1m steady_100 rds_18.1
//
// Or manually:
//   k6 run --env BASE_URL=http://localhost:8080 --env SCENARIO=steady_100 k6_q7.js
// ============================================================

import http from 'k6/http';
import { check } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ============================================================
// Custom Metrics
// ============================================================
const slaBreaches = new Counter('sla_breaches_3s');
const successRate = new Rate('success_rate');

// Q7 sub-query latency tracking
const q7aLatency = new Trend('q7a_recent_corporates_ms', true);
const q7bLatency = new Trend('q7b_distinct_corporates_ms', true);
const q7cLatency = new Trend('q7c_active_corporates_ms', true);
const q7Latency = new Trend('q7_skip_scan_ms', true);

// ============================================================
// Configuration
// ============================================================
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const SCENARIO = __ENV.SCENARIO || 'steady_100';

// ============================================================
// Scenarios
// ============================================================
const scenarios = {
    // Steady 1 req/s (baseline)
    steady_1: {
        steady: {
            executor: 'constant-arrival-rate',
            rate: 1,
            timeUnit: '1s',
            duration: '5m',
            preAllocatedVUs: 5,
            maxVUs: 10,
        },
    },
    // Steady 10 req/s
    steady_10: {
        steady: {
            executor: 'constant-arrival-rate',
            rate: 10,
            timeUnit: '1s',
            duration: '5m',
            preAllocatedVUs: 20,
            maxVUs: 50,
        },
    },
    // Steady 100 req/s
    steady_100: {
        steady: {
            executor: 'constant-arrival-rate',
            rate: 100,
            timeUnit: '1s',
            duration: '5m',
            preAllocatedVUs: 150,
            maxVUs: 300,
        },
    },
    // Steady 1000 req/s
    steady_1000: {
        steady: {
            executor: 'constant-arrival-rate',
            rate: 1000,
            timeUnit: '1s',
            duration: '5m',
            preAllocatedVUs: 1500,
            maxVUs: 2500,
        },
    },
    // Ramp through concurrency levels
    ramp: {
        ramp: {
            executor: 'ramping-arrival-rate',
            startRate: 1,
            timeUnit: '1s',
            preAllocatedVUs: 200,
            maxVUs: 2000,
            stages: [
                { duration: '1m', target: 1 },      // warmup
                { duration: '3m', target: 10 },     // 10 req/s
                { duration: '3m', target: 100 },    // 100 req/s
                { duration: '3m', target: 1000 },   // 1000 req/s
                { duration: '1m', target: 1 },      // cooldown
            ],
        },
    },
};

export const options = {
    scenarios: scenarios[SCENARIO] || scenarios['steady_100'],
    thresholds: {
        'http_req_duration': ['p(95)<3000'],
        'success_rate': ['rate>0.99'],
        'q7_skip_scan_ms': ['p(95)<2000'],
        'q7a_recent_corporates_ms': ['p(95)<2000'],
        'q7b_distinct_corporates_ms': ['p(95)<2000'],
        'q7c_active_corporates_ms': ['p(95)<2000'],
    },
};

// ============================================================
// Helpers
// ============================================================
function trackResponse(res, queryTrend) {
    const ok = res.status >= 200 && res.status < 300;
    successRate.add(ok);
    queryTrend.add(res.timings.duration);
    q7Latency.add(res.timings.duration);

    if (res.timings.duration >= 3000) {
        slaBreaches.add(1);
    }

    check(res, {
        'status 2xx': (r) => r.status >= 200 && r.status < 300,
        'under 3s SLA': (r) => r.timings.duration < 3000,
    });
}

// ============================================================
// Main test function — randomly picks Q7 sub-query
//
// Distribution:
//   Q7a: Recent corporates aggregation (40%)
//   Q7b: Distinct corporates (30%)
//   Q7c: Active corporates EXISTS (30%)
// ============================================================
export default function () {
    const roll = Math.random() * 100;

    if (roll < 40) {
        // Q7a: Recent corporates aggregation (40%)
        const res = http.get(`${BASE_URL}/api/skip-scan/recent-corporates`, {
            tags: { query: 'q7a_recent' },
        });
        trackResponse(res, q7aLatency);

    } else if (roll < 70) {
        // Q7b: Distinct corporates (30%)
        const res = http.get(`${BASE_URL}/api/skip-scan/distinct-corporates`, {
            tags: { query: 'q7b_distinct' },
        });
        trackResponse(res, q7bLatency);

    } else {
        // Q7c: Active corporates with EXISTS (30%)
        const res = http.get(`${BASE_URL}/api/skip-scan/active-corporates`, {
            tags: { query: 'q7c_active' },
        });
        trackResponse(res, q7cLatency);
    }
}
