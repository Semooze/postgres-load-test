# RDS/Aurora Parameter Group Tuning

For Experiments 1-3 (RDS and Aurora managed services).

**Note:** RDS/Aurora cannot use `ALTER SYSTEM`. Configure via AWS Parameter Groups.

## Create Custom Parameter Group

```bash
# [LOCAL] Create parameter group for RDS PostgreSQL 17/18
aws rds create-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --db-parameter-group-family postgres17 \
    --description "Tuned parameters for benchmark"

# For Aurora PostgreSQL
aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name aurora-pg-benchmark-tuned \
    --db-parameter-group-family aurora-postgresql17 \
    --description "Tuned parameters for Aurora benchmark"
```

## Apply Parameters (RDS)

```bash
# Memory settings (r7i.xlarge: 32GB RAM)
aws rds modify-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --parameters \
        "ParameterName=shared_buffers,ParameterValue={DBInstanceClassMemory/4},ApplyMethod=pending-reboot" \
        "ParameterName=effective_cache_size,ParameterValue={DBInstanceClassMemory*3/4},ApplyMethod=immediate" \
        "ParameterName=work_mem,ParameterValue=65536,ApplyMethod=immediate" \
        "ParameterName=maintenance_work_mem,ParameterValue=2097152,ApplyMethod=immediate"

# WAL settings
aws rds modify-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --parameters \
        "ParameterName=max_wal_size,ParameterValue=16384,ApplyMethod=immediate" \
        "ParameterName=min_wal_size,ParameterValue=2048,ApplyMethod=immediate" \
        "ParameterName=checkpoint_completion_target,ParameterValue=0.9,ApplyMethod=immediate"

# Query planner (gp3 EBS)
aws rds modify-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --parameters \
        "ParameterName=random_page_cost,ParameterValue=1.5,ApplyMethod=immediate" \
        "ParameterName=effective_io_concurrency,ParameterValue=50,ApplyMethod=immediate" \
        "ParameterName=default_statistics_target,ParameterValue=200,ApplyMethod=immediate"

# Parallelism
aws rds modify-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --parameters \
        "ParameterName=max_parallel_workers_per_gather,ParameterValue=4,ApplyMethod=immediate" \
        "ParameterName=max_parallel_workers,ParameterValue=8,ApplyMethod=immediate"

# Autovacuum
aws rds modify-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --parameters \
        "ParameterName=autovacuum_max_workers,ParameterValue=4,ApplyMethod=immediate" \
        "ParameterName=autovacuum_naptime,ParameterValue=10,ApplyMethod=immediate" \
        "ParameterName=autovacuum_vacuum_scale_factor,ParameterValue=0.05,ApplyMethod=immediate"

# Monitoring
aws rds modify-db-parameter-group \
    --db-parameter-group-name pg-benchmark-tuned \
    --parameters \
        "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
        "ParameterName=track_io_timing,ParameterValue=1,ApplyMethod=immediate" \
        "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

## Apply Parameters (Aurora)

Aurora has some different/restricted parameters:

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name aurora-pg-benchmark-tuned \
    --parameters \
        "ParameterName=shared_buffers,ParameterValue={DBInstanceClassMemory/4},ApplyMethod=pending-reboot" \
        "ParameterName=work_mem,ParameterValue=65536,ApplyMethod=immediate" \
        "ParameterName=default_statistics_target,ParameterValue=200,ApplyMethod=immediate" \
        "ParameterName=random_page_cost,ParameterValue=1.1,ApplyMethod=immediate"
```

**Note:** Aurora manages many parameters automatically (WAL, checkpoints, etc.). Not all RDS parameters are available.

## Attach Parameter Group to Instance

```bash
# RDS
aws rds modify-db-instance \
    --db-instance-identifier your-rds-instance \
    --db-parameter-group-name pg-benchmark-tuned \
    --apply-immediately

# Aurora (apply to cluster)
aws rds modify-db-cluster \
    --db-cluster-identifier your-aurora-cluster \
    --db-cluster-parameter-group-name aurora-pg-benchmark-tuned \
    --apply-immediately
```

## Reboot to Apply Changes

Some parameters require reboot (marked `pending-reboot`):

```bash
# RDS
aws rds reboot-db-instance --db-instance-identifier your-rds-instance

# Aurora
aws rds reboot-db-instance --db-instance-identifier your-aurora-instance
```

## Verify Parameters

```bash
# Check current parameter values
psql -h <host> -U postgres -d benchdb -c "SHOW shared_buffers;"
psql -h <host> -U postgres -d benchdb -c "SHOW work_mem;"
psql -h <host> -U postgres -d benchdb -c "SHOW random_page_cost;"
```

## Parameter Reference

| Parameter | Value | Unit | Notes |
|-----------|-------|------|-------|
| shared_buffers | {DBInstanceClassMemory/4} | bytes | ~25% of RAM |
| effective_cache_size | {DBInstanceClassMemory*3/4} | bytes | ~75% of RAM |
| work_mem | 65536 | KB | 64MB |
| maintenance_work_mem | 2097152 | KB | 2GB |
| max_wal_size | 16384 | MB | 16GB |
| checkpoint_completion_target | 0.9 | ratio | |
| random_page_cost | 1.5 | | gp3 EBS |
| effective_io_concurrency | 50 | | gp3 EBS |
| max_parallel_workers_per_gather | 4 | | |
| autovacuum_vacuum_scale_factor | 0.05 | ratio | 5% |

## Aurora-Specific Notes

Aurora manages these automatically (not configurable):
- WAL settings (max_wal_size, wal_buffers)
- Checkpoint settings
- Some I/O settings

Aurora uses its own storage layer with different I/O characteristics than RDS gp3.
