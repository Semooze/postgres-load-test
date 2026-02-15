-- ============================================================
-- PostgreSQL Tuning Configuration (EC2 Self-Managed)
-- For Experiment 4: Docker/Host tuned vs untuned comparison
--
-- THIS FILE IS FOR EC2 ONLY (Docker or Host PostgreSQL)
-- For RDS/Aurora (Exp 1-3), use 03_tuning_rds.md (AWS Parameter Groups)
--
-- Apply these to the "tuned" instances only
-- Configured for: r8g.xlarge (4 vCPU, 32 GB RAM, Graviton3, memory optimized)
-- ============================================================

-- ============================================================
-- MEMORY (adjust to actual RAM)
-- ============================================================
-- shared_buffers: 25% of RAM
ALTER SYSTEM SET shared_buffers = '8GB';

-- effective_cache_size: 75% of RAM (tells planner how much OS cache to expect)
ALTER SYSTEM SET effective_cache_size = '24GB';

-- work_mem: RAM / max_connections / 4 (used per sort/hash operation)
ALTER SYSTEM SET work_mem = '64MB';

-- maintenance_work_mem: for VACUUM, CREATE INDEX
ALTER SYSTEM SET maintenance_work_mem = '2GB';

-- ============================================================
-- WAL / WRITE PERFORMANCE
-- ============================================================
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_size = '16GB';
ALTER SYSTEM SET min_wal_size = '2GB';
ALTER SYSTEM SET wal_buffers = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- ============================================================
-- QUERY PLANNER
-- ============================================================
-- random_page_cost: 1.1 for SSD/NVMe, 1.5 for gp3, 4.0 for HDD
ALTER SYSTEM SET random_page_cost = 1.1;          -- SSD/NVMe
-- ALTER SYSTEM SET random_page_cost = 1.5;        -- gp3 EBS

-- Tells planner how many concurrent I/O requests the disk can handle
ALTER SYSTEM SET effective_io_concurrency = 200;   -- SSD/NVMe
-- ALTER SYSTEM SET effective_io_concurrency = 50;  -- gp3 EBS

ALTER SYSTEM SET default_statistics_target = 200;

-- ============================================================
-- PARALLELISM
-- ============================================================
ALTER SYSTEM SET max_worker_processes = 8;
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET max_parallel_workers = 8;
ALTER SYSTEM SET max_parallel_maintenance_workers = 4;

-- ============================================================
-- CONNECTION MANAGEMENT
-- ============================================================
ALTER SYSTEM SET max_connections = 200;
-- NOTE: For 1000+ concurrent, use PgBouncer in front
-- PgBouncer config example:
--   pool_mode = transaction
--   default_pool_size = 100
--   max_client_conn = 10000

-- ============================================================
-- BACKGROUND WRITER
-- ============================================================
ALTER SYSTEM SET bgwriter_delay = '200ms';
ALTER SYSTEM SET bgwriter_lru_maxpages = 100;
ALTER SYSTEM SET bgwriter_lru_multiplier = 2.0;

-- ============================================================
-- AUTOVACUUM (important for write-heavy benchmarks)
-- ============================================================
ALTER SYSTEM SET autovacuum = on;
ALTER SYSTEM SET autovacuum_max_workers = 4;
ALTER SYSTEM SET autovacuum_naptime = '10s';
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.05;
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.025;

-- ============================================================
-- MONITORING (for benchmark analysis)
-- ============================================================
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET track_io_timing = on;
ALTER SYSTEM SET track_activity_query_size = 2048;
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- log queries > 1s

-- ============================================================
-- JIT (can help CPU-bound queries, may hurt short queries)
-- ============================================================
ALTER SYSTEM SET jit = on;

-- ============================================================
-- PG 18 SPECIFIC: io_method (Experiment 2 only)
-- ============================================================
-- Default in PG 18 is 'worker' (recommended)
-- ALTER SYSTEM SET io_method = 'worker';
-- ALTER SYSTEM SET io_method = 'io_uring';   -- test separately
-- ALTER SYSTEM SET io_method = 'sync';        -- same as PG 17 behavior

-- ============================================================
-- APPLY: Requires restart for some settings
-- ============================================================
-- SELECT pg_reload_conf();  -- for runtime-changeable settings
-- sudo systemctl restart postgresql  -- for shared_buffers, etc.


-- ============================================================
-- OS-LEVEL TUNING (run as root on EC2)
-- ============================================================
-- Save as /etc/sysctl.d/99-postgres.conf and run: sysctl -p

/*
# Huge pages (reduces TLB misses for large shared_buffers)
# First check: grep Huge /proc/meminfo
# Calculate: shared_buffers / 2MB hugepage size = number needed
vm.nr_hugepages = 4096          # For 8GB shared_buffers

# Dirty page writeback tuning
vm.dirty_ratio = 40             # % of RAM before forced writeback
vm.dirty_background_ratio = 10  # % of RAM before background writeback
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100

# Swappiness: minimize swap usage
vm.swappiness = 1

# Shared memory
kernel.shmmax = 8589934592      # Match shared_buffers in bytes
kernel.shmall = 2097152

# Network (if DB and app are on different machines)
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
*/

-- ============================================================
-- I/O SCHEDULER (run as root)
-- ============================================================
/*
# For NVMe/SSD: use 'none' (noop)
echo none > /sys/block/nvme0n1/queue/scheduler

# For EBS gp3: use 'mq-deadline'
echo mq-deadline > /sys/block/xvda/queue/scheduler

# Increase readahead for sequential scans
blockdev --setra 4096 /dev/nvme0n1
*/
