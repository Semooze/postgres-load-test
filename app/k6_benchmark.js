// ============================================================
// K6 Load Test for PostgreSQL Benchmark Go API
//
// Usage:
//   # Set environment variables
//   export BASE_URL=http://localhost:8080
//   export DATASET=1m
//   export SCENARIO=ramp        # or: steady_10, steady_100, steady_1000
//
//   # Run specific scenario
//   k6 run --env BASE_URL=$BASE_URL --env DATASET=$DATASET --env SCENARIO=ramp k6_benchmark.js
//
//   # Run steady load at 100 req/s
//   k6 run --env BASE_URL=$BASE_URL --env DATASET=$DATASET --env SCENARIO=steady_100 k6_benchmark.js
// ============================================================

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ============================================================
// Custom Metrics
// ============================================================
const slaBreaches = new Counter('sla_breaches_3s');
const successRate = new Rate('success_rate');

// Per-query latency tracking
const q1Latency = new Trend('q1_read_single_ms', true);
const q2Latency = new Trend('q2_read_join2_ms', true);
const q3Latency = new Trend('q3_read_join3_ms', true);
const q4Latency = new Trend('q4_write_single_ms', true);
const q5Latency = new Trend('q5_acid_2table_ms', true);
const q6Latency = new Trend('q6_acid_3table_ms', true);
const q7Latency = new Trend('q7_skip_scan_ms', true);

// ============================================================
// Configuration
// ============================================================
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATASET = __ENV.DATASET || '1m';
const SCENARIO = __ENV.SCENARIO || 'ramp';

const MAX_IDS = {
    '100k': { corp: 10000, user: 20000, tx: 70000 },
    '1m':   { corp: 100000, user: 200000, tx: 700000 },
    '10m':  { corp: 1000000, user: 2000000, tx: 7000000 },
};

const ids = MAX_IDS[DATASET];
if (!ids) {
    throw new Error(`Invalid DATASET: ${DATASET}. Use 100k, 1m, or 10m`);
}

// ============================================================
// Scenarios
// ============================================================
const scenarios = {
    // Ramp through concurrency levels
    ramp: {
        ramp: {
            executor: 'ramping-arrival-rate',
            startRate: 1,
            timeUnit: '1s',
            preAllocatedVUs: 200,
            maxVUs: 2000,
            stages: [
                { duration: '1m',  target: 1 },       // warmup
                { duration: '3m',  target: 10 },      // 10 req/s
                { duration: '3m',  target: 100 },     // 100 req/s
                { duration: '3m',  target: 1000 },    // 1000 req/s
                { duration: '1m',  target: 1 },       // cooldown
            ],
        },
    },
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
};

export const options = {
    scenarios: scenarios[SCENARIO] || scenarios['ramp'],
    thresholds: {
        // Global SLA
        'http_req_duration': ['p(95)<3000'],       // 95th percentile under 3s
        'success_rate': ['rate>0.99'],              // 99% success rate

        // Per-query thresholds
        'q1_read_single_ms': ['p(95)<500'],        // single table: fast
        'q2_read_join2_ms': ['p(95)<1000'],        // 2-table join
        'q3_read_join3_ms': ['p(95)<2000'],        // 3-table join
        'q4_write_single_ms': ['p(95)<500'],       // single write
        'q5_acid_2table_ms': ['p(95)<1000'],       // ACID 2-table
        'q6_acid_3table_ms': ['p(95)<1500'],       // ACID 3-table
        'q7_skip_scan_ms': ['p(95)<2000'],         // skip scan
    },
};

// ============================================================
// Helpers
// ============================================================
function randInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}

function trackResponse(res, queryTrend) {
    const ok = res.status >= 200 && res.status < 300;
    successRate.add(ok);
    queryTrend.add(res.timings.duration);

    if (res.timings.duration >= 3000) {
        slaBreaches.add(1);
    }

    check(res, {
        'status 2xx': (r) => r.status >= 200 && r.status < 300,
        'under 3s SLA': (r) => r.timings.duration < 3000,
    });
}

const jsonHeaders = { headers: { 'Content-Type': 'application/json' } };

// ============================================================
// Main test function — randomly picks a query type
//
// Distribution:
//   Read queries  (Q1-Q3): 60% of requests
//   Write queries (Q4-Q6): 40% of requests
// ============================================================
export default function () {
    const roll = Math.random() * 100;

    if (roll < 15) {
        // Q1a: Point select (15%)
        const txId = randInt(1, ids.tx);
        const res = http.get(`${BASE_URL}/api/transactions/${txId}`, {
            tags: { query: 'q1_point' },
        });
        trackResponse(res, q1Latency);

    } else if (roll < 25) {
        // Q1b: Aggregation (10%)
        const corpId = randInt(1, ids.corp);
        const res = http.get(`${BASE_URL}/api/transactions/summary/${corpId}`, {
            tags: { query: 'q1_agg' },
        });
        trackResponse(res, q1Latency);

    } else if (roll < 40) {
        // Q2: 2-table join (15%)
        const corpId = randInt(1, ids.corp);
        const res = http.get(`${BASE_URL}/api/corporates/${corpId}/users`, {
            tags: { query: 'q2' },
        });
        trackResponse(res, q2Latency);

    } else if (roll < 60) {
        // Q3: 3-table join (20%)
        const corpId = randInt(1, ids.corp);
        const res = http.get(`${BASE_URL}/api/corporates/${corpId}/report`, {
            tags: { query: 'q3' },
        });
        trackResponse(res, q3Latency);

    } else if (roll < 75) {
        // Q4: Write single (15%)
        const payload = JSON.stringify({
            user_id: randInt(1, ids.user),
            corporate_id: randInt(1, ids.corp),
            amount: parseFloat((randInt(100, 100000) / 100).toFixed(2)),
            currency: ['THB', 'USD', 'JPY', 'SGD'][randInt(0, 3)],
            tx_type: 'payment',
        });
        const res = http.post(`${BASE_URL}/api/transactions`, payload, jsonHeaders);
        trackResponse(res, q4Latency);

    } else if (roll < 88) {
        // Q5: ACID 2-table (13%)
        const payload = JSON.stringify({
            user_id: randInt(1, ids.user),
            corporate_id: randInt(1, ids.corp),
            amount: parseFloat((randInt(100, 100000) / 100).toFixed(2)),
        });
        const res = http.post(`${BASE_URL}/api/transactions/with-activity`, payload, jsonHeaders);
        trackResponse(res, q5Latency);

    } else {
        // Q6: ACID 3-table (12%)
        const payload = JSON.stringify({
            user_id: randInt(1, ids.user),
            corporate_id: randInt(1, ids.corp),
            amount: parseFloat((randInt(100, 50000) / 100).toFixed(2)),
        });
        const res = http.post(`${BASE_URL}/api/transactions/full-process`, payload, jsonHeaders);
        trackResponse(res, q6Latency);
    }
}

// ============================================================
// Separate test functions for testing individual queries
// Run with: k6 run --env QUERY=q1 k6_benchmark.js
// ============================================================

// Export individual query functions for isolated testing
export function q1Only() {
    const txId = randInt(1, ids.tx);
    const res = http.get(`${BASE_URL}/api/transactions/${txId}`);
    trackResponse(res, q1Latency);
}

export function q2Only() {
    const corpId = randInt(1, ids.corp);
    const res = http.get(`${BASE_URL}/api/corporates/${corpId}/users`);
    trackResponse(res, q2Latency);
}

export function q3Only() {
    const corpId = randInt(1, ids.corp);
    const res = http.get(`${BASE_URL}/api/corporates/${corpId}/report`);
    trackResponse(res, q3Latency);
}

export function q4Only() {
    const payload = JSON.stringify({
        user_id: randInt(1, ids.user),
        corporate_id: randInt(1, ids.corp),
        amount: parseFloat((randInt(100, 100000) / 100).toFixed(2)),
        currency: 'THB',
        tx_type: 'payment',
    });
    const res = http.post(`${BASE_URL}/api/transactions`, payload, jsonHeaders);
    trackResponse(res, q4Latency);
}

export function q5Only() {
    const payload = JSON.stringify({
        user_id: randInt(1, ids.user),
        corporate_id: randInt(1, ids.corp),
        amount: parseFloat((randInt(100, 100000) / 100).toFixed(2)),
    });
    const res = http.post(`${BASE_URL}/api/transactions/with-activity`, payload, jsonHeaders);
    trackResponse(res, q5Latency);
}

export function q6Only() {
    const payload = JSON.stringify({
        user_id: randInt(1, ids.user),
        corporate_id: randInt(1, ids.corp),
        amount: parseFloat((randInt(100, 50000) / 100).toFixed(2)),
    });
    const res = http.post(`${BASE_URL}/api/transactions/full-process`, payload, jsonHeaders);
    trackResponse(res, q6Latency);
}

// Q7: Skip scan queries (PG 18 optimization)
export function q7Only() {
    // Randomly pick one of the three skip scan patterns
    const roll = Math.random() * 100;

    if (roll < 40) {
        // Q7a: Recent corporates aggregation (40%)
        const res = http.get(`${BASE_URL}/api/skip-scan/recent-corporates`, {
            tags: { query: 'q7a_recent' },
        });
        trackResponse(res, q7Latency);
    } else if (roll < 70) {
        // Q7b: Distinct corporates (30%)
        const res = http.get(`${BASE_URL}/api/skip-scan/distinct-corporates`, {
            tags: { query: 'q7b_distinct' },
        });
        trackResponse(res, q7Latency);
    } else {
        // Q7c: Active corporates with EXISTS (30%)
        const res = http.get(`${BASE_URL}/api/skip-scan/active-corporates`, {
            tags: { query: 'q7c_active' },
        });
        trackResponse(res, q7Latency);
    }
}
