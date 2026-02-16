# Key Factors: Aurora vs RDS Multi-AZ

## Multi-AZ Architecture Comparison

### RDS Multi-AZ

```
┌─────────────────┐         Synchronous          ┌─────────────────┐
│   Primary       │ ──────── Replication ──────▶ │   Standby       │
│   (AZ-a)        │         (every write)        │   (AZ-b)        │
│   Read/Write    │                              │   NOT readable  │
└─────────────────┘                              └─────────────────┘
        │
        │  (Optional) Async Replication
        ▼
┌─────────────────┐
│  Read Replica   │  ◀── Separate storage, has replication lag
│  (AZ-c)         │
│  Read only      │
└─────────────────┘
```

**Characteristics:**
- Standby is for **failover only** - cannot serve read traffic
- Synchronous replication adds **write latency** (~2-5ms penalty)
- Read Replicas are **separate** from Multi-AZ (async, have lag, extra cost)
- Up to 5 Read Replicas for PostgreSQL
- Failover time: **60-120 seconds**

### Aurora Multi-AZ

```
┌─────────────────┐                              ┌─────────────────┐
│   Primary       │ ────────────┬──────────────▶ │  Read Replica   │
│   (AZ-a)        │             │                │  (AZ-b)         │
│   Read/Write    │             │                │  Read only      │
└─────────────────┘             │                └─────────────────┘
                                │
                                ▼
              ┌─────────────────────────────────────┐
              │     Shared Distributed Storage      │
              │     6 copies across 3 AZs           │
              │     (automatic, no extra config)    │
              └─────────────────────────────────────┘
                                │
                                │
                                ▼
                        ┌─────────────────┐
                        │  Read Replica   │
                        │  (AZ-c)         │
                        │  Read only      │
                        └─────────────────┘
```

**Characteristics:**
- Storage replication is **built-in** (6 copies, 3 AZs)
- Write latency is **lower** than RDS Multi-AZ (4/6 quorum write)
- Read Replicas **share storage** - minimal replication lag (~10-20ms)
- Up to 15 Read Replicas
- Failover time: **~30 seconds**

---

## Performance Comparison

| Factor | RDS Single-AZ | RDS Multi-AZ | Aurora |
|--------|---------------|--------------|--------|
| Write Latency | Baseline | +2-5ms (sync replication) | +1-2ms (storage quorum) |
| Write TPS | Highest | Lower (sync overhead) | Medium-High |
| Read Scaling | No (or async replicas) | No (standby not readable) | Yes (up to 15 replicas) |
| Read Replica Lag | 1-60 seconds | 1-60 seconds | 10-20ms |
| Failover Time | Manual | 60-120s | ~30s |

**Key Insight:** RDS Multi-AZ does **NOT** improve read performance - the standby cannot serve reads. For read scaling with RDS, you need separate Read Replicas (with async replication lag).

---

## RDS Proxy

### What It Does

```
┌─────────┐     ┌───────────┐     ┌─────────────┐
│   App   │────▶│ RDS Proxy │────▶│  RDS/Aurora │
│ Server  │     │           │     │  Database   │
└─────────┘     └───────────┘     └─────────────┘
```

**Benefits:**
1. **Connection Pooling** - Reduces database connection overhead
2. **Faster Failover** - Maintains app connections during failover (reduces downtime perception)
3. **Connection Multiplexing** - Many app connections → fewer DB connections

### Does RDS Proxy Help Multi-AZ?

| Aspect | Without Proxy | With Proxy |
|--------|---------------|------------|
| Failover time (DB) | 60-120s (RDS) / 30s (Aurora) | Same |
| App reconnection | Apps must reconnect | Proxy handles reconnection |
| Perceived downtime | Full failover time | Reduced (proxy buffers) |
| Write performance | Baseline | No improvement |
| Connection efficiency | App manages | Proxy pools connections |

**RDS Proxy does NOT:**
- Improve write replication performance
- Reduce synchronous replication latency
- Add read scaling capability

**RDS Proxy DOES:**
- Make failover more transparent to applications
- Reduce connection overhead (useful for serverless/Lambda)
- Help with connection limits at high concurrency

### RDS Proxy vs PgBouncer

| Aspect | RDS Proxy | PgBouncer |
|--------|-----------|-----------|
| Connection pooling | Yes | Yes |
| Managed by | AWS | Self-hosted (on EC2) |
| Cost | ~$0.015/vCPU-hour | Free (open source) |
| Failover handling | Built-in (maintains connections) | Manual configuration |
| IAM authentication | Yes | No |
| Secrets Manager | Integrated | No |
| Works with | RDS/Aurora only | Any PostgreSQL |
| Setup complexity | Easy (AWS Console) | Medium (config files) |

**Summary:** RDS Proxy ≈ Managed PgBouncer + failover handling + AWS integrations

If you're already running PgBouncer on EC2, it does the same connection pooling job for free. RDS Proxy adds value mainly for:
- Serverless/Lambda (no EC2 to run PgBouncer)
- Simplified failover handling
- IAM-based authentication

---

## Cost Comparison (Detailed)

### RDS Multi-AZ Cost Breakdown

**Yes, Multi-AZ roughly doubles instance cost:**

| Component | Single-AZ | Multi-AZ | Multiplier |
|-----------|-----------|----------|------------|
| Instance | 1x | 2x (primary + standby) | **2x** |
| Storage | 1x | ~2x (replicated to standby) | **~2x** |
| I/O | 1x | ~1.5-2x (sync writes) | **~1.5x** |

**Example pricing (db.r8g.xlarge, ap-southeast-1):**

| Configuration | Instance/hour | Monthly (730h) |
|---------------|---------------|----------------|
| RDS Single-AZ | ~$0.48 | ~$350 |
| RDS Multi-AZ | ~$0.96 | ~$700 |
| Aurora (single writer) | ~$0.52 | ~$380 + I/O costs |

### RDS Cost Formula
```
Single-AZ:  Instance + Storage + I/O
Multi-AZ:   Instance × 2 + Storage × 2 + I/O × 1.5
```

### Aurora Cost Formula
```
Aurora:     Instance + Storage (usage-based) + I/O (per million)
+ Replica:  Instance × N (replicas share storage, no extra storage cost)
```

### Cost Considerations

| Factor | RDS Multi-AZ | Aurora |
|--------|--------------|--------|
| HA cost | 2x instance (standby) | Included (no extra instance) |
| Read scaling | Extra replicas + storage each | Extra replicas only (shared storage) |
| Storage | Provisioned (may over-provision) | Usage-based (auto-scales) |
| I/O | Included | Pay per million requests |
| Predictability | More predictable | Variable (I/O dependent) |

**When RDS Multi-AZ is cheaper:**
- Write-heavy workloads (Aurora I/O costs add up)
- Predictable, steady workloads
- Don't need read scaling

**When Aurora is cheaper:**
- Read-heavy workloads (read replicas share storage)
- Bursty workloads (pay for what you use)
- Need multiple read replicas

---

## Decision Matrix

| If You Need... | Recommendation |
|----------------|----------------|
| Lowest cost, no HA | RDS Single-AZ |
| HA with predictable cost | RDS Multi-AZ |
| HA + read scaling | Aurora |
| Fastest failover | Aurora |
| Write-heavy, cost-sensitive | RDS Multi-AZ (avoid Aurora I/O costs) |
| Read-heavy, need scaling | Aurora (read replicas share storage) |
| Serverless/Lambda backend | Aurora + RDS Proxy |
| PG 18 features (skip scan) | RDS 18.1 (Aurora still on 17.x) |

---

## Recommendation for This Benchmark

Since cost and HA are key factors:

1. **Skip Aurora vs RDS performance benchmarks** - Architecture differences matter more than raw query speed
2. **Decision should be based on:**
   - Expected read/write ratio
   - I/O cost estimation for Aurora
   - HA requirements (failover time tolerance)
   - Read scaling needs
3. **Focus benchmarks on:**
   - RDS 17.7 vs 18.1 (version upgrade benefits)
   - EC2 tuning impact (Experiment 4)
