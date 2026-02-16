# Aurora vs RDS PostgreSQL — Cost Comparison by Organization Scale

> **Exchange Rate:** 1 USD = 31.10 THB (14 Feb 2026)
>
> **Region:** Asia Pacific (Singapore) `ap-southeast-1` — On-Demand pricing
>
> **Engine:** PostgreSQL
>
> **Note:** ราคาเป็นการประมาณจาก AWS published pricing อาจมีการเปลี่ยนแปลง ควรตรวจสอบกับ AWS Pricing Calculator อีกครั้ง

---

## Important: Aurora vs RDS Architecture Differences

| Feature | Aurora | RDS |
|---|---|---|
| **Multi-AZ Storage** | ✅ Built-in (6 copies, 3 AZs) — ไม่มีค่าใช้จ่ายเพิ่ม | ❌ ต้องเปิด Multi-AZ เอง — compute + storage x2 |
| **Multi-AZ Compute** | ❌ ต้องสร้าง Reader instance แยก (จ่ายเพิ่ม) | ✅ Multi-AZ มี standby instance (จ่าย x2) |
| **Minimum Instance (PostgreSQL)** | db.t3.medium (2 vCPU, 4 GB) | db.t3.small (2 vCPU, 2 GB) |
| **Read Replicas** | สูงสุด 15 ตัว | สูงสุด 5 ตัว (15 สำหรับ Multi-AZ cluster) |
| **Failover Time** | ~30 วินาที | 1-2 นาที (Multi-AZ) |
| **Storage Auto-scaling** | ✅ อัตโนมัติ สูงสุด 128 TiB | ❌ ต้อง provision ล่วงหน้า (สูงสุด 64 TiB) |
| **Global Database** | ✅ รองรับ cross-region replication | ❌ ใช้ read replica cross-region แทน |

---

## Instance Pricing Reference (Singapore Region, On-Demand, PostgreSQL)

| Instance | vCPU | RAM | RDS Single-AZ | RDS Multi-AZ | Aurora Std | Aurora I/O-Opt |
|---|---|---|---|---|---|---|
| db.t3.small | 2 | 2 GB | $0.044/hr | $0.088/hr | ❌ ไม่รองรับ | ❌ ไม่รองรับ |
| db.t3.medium | 2 | 4 GB | $0.104/hr | $0.208/hr | $0.112/hr | $0.146/hr |
| db.r6g.large | 2 | 16 GB | $0.290/hr | $0.580/hr | $0.348/hr | $0.452/hr |
| db.r6g.xlarge | 4 | 32 GB | $0.580/hr | $1.160/hr | $0.696/hr | $0.905/hr |
| db.r6g.2xlarge | 8 | 64 GB | $1.160/hr | $2.320/hr | $1.392/hr | $1.810/hr |
| db.r6g.4xlarge | 16 | 128 GB | $2.320/hr | $4.640/hr | $2.784/hr | $3.619/hr |

> **หมายเหตุ:** Aurora ราคา instance สูงกว่า RDS Single-AZ ~20% แต่ storage เป็น Multi-AZ by default แล้ว
> เมื่อเทียบ Aurora กับ RDS Multi-AZ → Aurora compute ถูกกว่า ~40% เพราะ RDS ต้องจ่าย standby instance x2

### Storage Pricing (Singapore Region)

| Component | Aurora Standard | Aurora I/O-Opt | RDS gp3 | RDS io2 |
|---|---|---|---|---|
| Storage | $0.120/GB-mo | $0.270/GB-mo | $0.138/GB-mo | $0.150/GB-mo |
| IOPS | $0.24/1M I/O req | Included | 3,000 free (+$0.024/IOPS-mo) | $0.120/IOPS-mo |
| Throughput | N/A | N/A | 125 MB/s free (+$0.096/MBps-mo) | N/A |

> Singapore region ราคาสูงกว่า US East ~20%
> gp3 ≥ 400 GB: baseline เพิ่มเป็น 12,000 IOPS + 500 MB/s (included)

---

## Scenario 1: Small Organization — 50 Users

> **ลักษณะงาน:** ระบบภายในองค์กรขนาดเล็ก, ใช้งาน 9:00-18:00 วันจันทร์-ศุกร์
>
> **Deployment:** Single-AZ (RDS) / Default (Aurora — storage Multi-AZ อยู่แล้ว)
>
> **ไม่ต้องการ HA ระดับสูง** — downtime ได้บ้าง

| Parameter | Value |
|---|---|
| Instance | RDS: db.t3.small / Aurora: db.t3.medium (minimum) |
| Storage | 20 GB |
| IOPS | 3,000 (baseline) |
| Aurora I/O | 10M requests/mo |
| Read Replicas | 0 |

| Cost Component | Aurora Std | Aurora I/O-Opt | RDS gp3 (Single-AZ) | RDS io2 (Single-AZ) |
|---|---|---|---|---|
| Compute | $81.76 | $106.58 | $32.12 | $32.12 |
| Storage | $2.40 | $5.40 | $2.76 | $3.00 |
| IOPS / I/O | $2.40 | $0.00 | $0.00 | $360.00 |
| **Total (USD)** | **$86.56** | **$111.98** | **$34.88** | **$395.12** |
| **Total (THB)** | **฿2,692** | **฿3,483** | **฿1,085** | **฿12,288** |

### สรุป Scenario 1

| Option | ฿/เดือน | เทียบ |
|---|---|---|
| ✅ **RDS gp3 Single-AZ** | **฿1,085** | ถูกสุด — db.t3.small ถูกกว่า Aurora minimum |
| Aurora Standard | ฿2,692 | แพงกว่า 2.5x (ต้องใช้ db.t3.medium ขั้นต่ำ) |
| Aurora I/O-Opt | ฿3,483 | แพงกว่า 3.2x |
| ❌ RDS io2 | ฿12,288 | แพงเกินจำเป็น (3,000 IOPS × $0.12) |

> **แนะนำ: RDS gp3 Single-AZ with db.t3.small** — ประหยัดที่สุดสำหรับองค์กรเล็ก

---

## Scenario 2: Enterprise — 200+ Users

> **ลักษณะงาน:** ระบบ ERP, Healthcare, Business Critical
>
> **Deployment:** Multi-AZ (ทั้ง RDS และ Aurora) — ต้องการ HA
>
> **ต้องการ failover อัตโนมัติ**

| Parameter | Value |
|---|---|
| Instance | db.r6g.large (2 vCPU, 16 GB) |
| Storage | 200 GB |
| IOPS | 5,000 |
| Aurora I/O | 50M requests/mo |
| Read Replicas | Aurora: 1 reader (HA) / RDS: Multi-AZ standby |

| Cost Component | Aurora Std (writer+reader) | Aurora I/O-Opt (writer+reader) | RDS gp3 Multi-AZ | RDS io2 Multi-AZ |
|---|---|---|---|---|
| Compute (primary) | $254.04 | $330.06 | $423.40 | $423.40 |
| Compute (reader/standby) | $254.04 | $330.06 | (included in Multi-AZ) | (included in Multi-AZ) |
| Storage | $24.00 | $54.00 | $27.60 × 2 = $55.20 | $30.00 × 2 = $60.00 |
| IOPS / I/O | $12.00 | $0.00 | $48.00 | $600.00 × 2 = $1,200.00 |
| **Total (USD)** | **$544.08** | **$714.12** | **$526.60** | **$1,683.40** |
| **Total (THB)** | **฿16,921** | **฿22,209** | **฿16,377** | **฿52,354** |

### IOPS Breakdown

- **RDS gp3:** storage < 400 GB → baseline 3,000 IOPS → extra 2,000 × $0.024 = $48.00
- **RDS io2 Multi-AZ:** 5,000 IOPS × $0.120 × 2 instances = $1,200.00
- **Aurora:** 50M × $0.24/1M = $12.00 (storage is shared, no duplicate)

### สรุป Scenario 2

| Option | ฿/เดือน | เทียบ |
|---|---|---|
| ✅ **RDS gp3 Multi-AZ** | **฿16,377** | ถูกสุดเล็กน้อย |
| Aurora Standard (w+r) | ฿16,921 | แพงกว่าแค่ ~3% แต่ได้ storage HA ดีกว่า |
| Aurora I/O-Opt (w+r) | ฿22,209 | แพงกว่า ~36% |
| ❌ RDS io2 Multi-AZ | ฿52,354 | แพงมาก — IOPS ถูก provision ทั้ง 2 AZ |

> **แนะนำ: Aurora Standard** ถ้าต้องการ fast failover (<30s) และ storage HA built-in
> **แนะนำ: RDS gp3 Multi-AZ** ถ้าต้องการประหยัดที่สุดและ failover 1-2 นาทีรับได้

---

## Scenario 2B: Enterprise 200+ Users — Single-AZ (Lower HA Requirements)

> **ลักษณะงาน:** ระบบ ERP, Internal Tools ที่ไม่ใช่ mission-critical
>
> **Deployment:** Single-AZ — ยอมรับ downtime ได้บ้าง, ยอมรับ data loss เล็กน้อยได้ (RPO > 0)
>
> **Use Case:** Dev/Staging environments, Non-critical internal systems, Cost-sensitive deployments

| Parameter | Value |
|---|---|
| Instance | db.r6g.large (2 vCPU, 16 GB) |
| Storage | 200 GB |
| IOPS | 5,000 |

### Single-AZ vs Multi-AZ Comparison

| Cost Component | RDS gp3 Single-AZ | RDS gp3 Multi-AZ | RDS io2 Single-AZ | RDS io2 Multi-AZ |
|---|---|---|---|---|
| Compute | $211.70 | $423.40 | $211.70 | $423.40 |
| Storage | $27.60 | $27.60 × 2 = $55.20 | $30.00 | $30.00 × 2 = $60.00 |
| IOPS | $48.00 | $48.00 | $600.00 | $600.00 × 2 = $1,200.00 |
| **Total (USD)** | **$287.30** | **$526.60** | **$841.70** | **$1,683.40** |
| **Total (THB)** | **฿8,935** | **฿16,377** | **฿26,177** | **฿52,354** |
| ส่วนต่าง | — | +฿7,442 (+83%) | — | +฿26,177 (+100%) |

### สรุป Scenario 2B

| Option | ฿/เดือน | ประหยัด vs Multi-AZ | Trade-off |
|---|---|---|---|
| ✅ **RDS gp3 Single-AZ** | **฿8,935** | ประหยัด ฿7,442 (45%) | No automatic failover, potential data loss |
| RDS gp3 Multi-AZ | ฿16,377 | — | Full HA |
| RDS io2 Single-AZ | ฿26,177 | ประหยัด ฿26,177 (50%) | High IOPS แต่ไม่มี HA |
| ❌ RDS io2 Multi-AZ | ฿52,354 | — | แพงเกินจำเป็นสำหรับ use case นี้ |

> **เมื่อไหร่ควรใช้ Single-AZ:**
> - Dev/Test/Staging environments
> - Internal tools ที่ downtime ไม่กระทบ business
> - มี backup strategy อื่น (เช่น automated snapshots ทุก 1 ชม.)
> - งบจำกัดและยอมรับ RPO > 0 ได้
>
> **เมื่อไหร่ไม่ควรใช้ Single-AZ:**
> - Production systems ที่ user-facing
> - ระบบที่ downtime มีค่าเสียหาย > ฿7,442/เดือน
> - ต้องการ SLA 99.95%+

---

## Scenario 3: Provincial Scale — 1M Users

> **ลักษณะงาน:** ระบบสาธารณสุขจังหวัด, e-Government, ระบบที่ประชาชน 1 ล้านคนใช้
>
> **Deployment:** Multi-AZ (mandatory) + Read Replicas
>
> **ต้องการ HA สูง** — downtime ส่งผลกระทบวงกว้าง

| Parameter | Value |
|---|---|
| Instance (Writer) | db.r6g.2xlarge (8 vCPU, 64 GB) |
| Instance (Readers) | db.r6g.xlarge × 2 |
| Storage | 1,000 GB (1 TB) |
| IOPS | 20,000 |
| Aurora I/O | 300M requests/mo |
| Read Replicas | 2 |

| Cost Component | Aurora Std | Aurora I/O-Opt | RDS gp3 Multi-AZ | RDS io2 Multi-AZ |
|---|---|---|---|---|
| Writer compute | $1,016.16 | $1,321.30 | $1,693.60 | $1,693.60 |
| 2× Reader compute | $1,016.16 | $1,321.30 | $1,693.60 | $1,693.60 |
| Storage | $120.00 | $270.00 | $138.00 × 2 = $276.00 | $150.00 × 2 = $300.00 |
| Reader storage | (shared) | (shared) | $138.00 × 2 = $276.00 | $150.00 × 2 = $300.00 |
| IOPS / I/O | $72.00 | $0.00 | $192.00 (writer) | $2,400.00 × 2 = $4,800.00 |
| Reader IOPS | (shared I/O) | $0.00 | $192.00 × 2 = $384.00 | $2,400.00 × 2 = $4,800.00 |
| **Total (USD)** | **$2,224.32** | **$2,912.60** | **$4,515.20** | **$13,587.20** |
| **Total (THB)** | **฿69,176** | **฿90,562** | **฿140,373** | **฿422,562** |

### ทำไม Aurora ถูกกว่ามากในระดับนี้

1. **Storage shared** — Aurora writer + readers ใช้ storage layer เดียวกัน ไม่ต้องจ่ายซ้ำ
2. **RDS Multi-AZ ทุก instance** ต้องจ่าย storage + IOPS ซ้ำทุก AZ
3. **RDS reader replicas** แต่ละตัวมี EBS storage แยก → storage × จำนวน instances

### สรุป Scenario 3

| Option | ฿/เดือน | เทียบ |
|---|---|---|
| ✅ **Aurora Standard** | **฿69,176** | ถูกสุด — shared storage ได้เปรียบมาก |
| Aurora I/O-Opt | ฿90,562 | แพงกว่า ~31% แต่ predictable cost |
| RDS gp3 Multi-AZ | ฿140,373 | แพงกว่า 2x — storage/IOPS ซ้ำทุก instance |
| ❌ RDS io2 Multi-AZ | ฿422,562 | แพงมาก — ไม่คุ้มค่า |

> **แนะนำ: Aurora Standard** — ชัดเจนว่า Aurora ชนะเมื่อมี read replicas เพราะ shared storage

---

## Scenario 4: Country Scale — 10M+ Users (Multi-AZ mandatory)

> **ลักษณะงาน:** ระบบระดับประเทศ เช่น ระบบประกันสุขภาพ, National Health Platform
>
> **Deployment:** Multi-AZ (mandatory) + Multiple Read Replicas + พิจารณา Multi-Region DR
>
> **ต้องการ HA สูงสุด** — SLA 99.99%

| Parameter | Value |
|---|---|
| Instance (Writer) | db.r6g.4xlarge (16 vCPU, 128 GB) |
| Instance (Readers) | db.r6g.2xlarge × 4 |
| Storage | 5,000 GB (5 TB) |
| IOPS | 40,000 |
| Aurora I/O | 1,000M (1B) requests/mo |
| Read Replicas | 4 |

| Cost Component | Aurora Std | Aurora I/O-Opt | RDS gp3 Multi-AZ | RDS io2 Multi-AZ |
|---|---|---|---|---|
| Writer compute | $2,032.32 | $2,641.87 | $3,387.20 | $3,387.20 |
| 4× Reader compute | $4,064.64 | $5,284.40 | $6,774.40 | $6,774.40 |
| Storage (shared/per-inst) | $600.00 | $1,350.00 | $690.00 × 6 = $4,140.00 | $750.00 × 6 = $4,500.00 |
| IOPS / I/O | $240.00 | $0.00 | $672.00 × 2 + $672.00 × 4 = $4,032.00 | $4,800.00 × 6 = $28,800.00 |
| **Total (USD)** | **$6,936.96** | **$9,276.27** | **$18,333.60** | **$43,461.60** |
| **Total (THB)** | **฿215,739** | **฿288,492** | **฿570,175** | **฿1,351,656** |

### IOPS Breakdown

- **RDS gp3:** storage 5 TB ≥ 400 GB → baseline 12,000 IOPS → extra 28,000 × $0.024 = $672/instance
- **RDS io2:** 40,000 IOPS × $0.120 = $4,800/instance
- **Aurora:** 1B × $0.24/1M = $240 (ทุก readers share storage)

### สรุป Scenario 4

| Option | ฿/เดือน | เทียบ |
|---|---|---|
| ✅ **Aurora Standard** | **฿215,739** | ถูกสุดอย่างชัดเจน |
| Aurora I/O-Opt | ฿288,492 | แพงกว่า ~34% แต่ I/O ไม่ต้องกังวล |
| RDS gp3 Multi-AZ | ฿570,175 | แพงกว่า 2.6x |
| ❌ RDS io2 Multi-AZ | ฿1,351,656 | แพงกว่า 6.3x — ไม่สมเหตุสมผล |

> **แนะนำ: Aurora Standard** หรือ **Aurora I/O-Optimized** (ถ้าต้องการ predictable cost)

---

## Scenario 5: Global Scale — 1,000+ Users Multi-Region

> **ลักษณะงาน:** International SaaS, Global Healthcare Platform
>
> **Deployment:** Multi-Region (Singapore primary + US/EU secondary)
>
> **Aurora Global Database vs RDS Cross-Region Read Replicas**

| Parameter | Value |
|---|---|
| Primary Region | Singapore (ap-southeast-1) |
| Secondary Region | US East (us-east-1) |
| Writer Instance | db.r6g.2xlarge |
| Reader per Region | db.r6g.xlarge × 2 |
| Storage | 2,000 GB (2 TB) |
| IOPS | 20,000 |
| Aurora I/O | 500M requests/mo (primary) |
| Cross-Region Replication | Continuous |

| Cost Component | Aurora Global DB (Std) | RDS gp3 + Cross-Region Replica |
|---|---|---|
| **Primary Region (Singapore)** | | |
| Writer compute | $1,016.16 | $1,693.60 (Multi-AZ) |
| 2× Reader compute | $1,016.16 | $1,693.60 |
| Storage (primary) | $240.00 | $276.00 × 4 = $1,104.00 |
| IOPS / I/O (primary) | $120.00 | $192.00 × 4 = $768.00 |
| **Secondary Region (US East)** | | |
| Reader compute (2×) | $696.00 | ~$1,160.00 |
| Storage (secondary) | $200.00 | ~$230.00 × 2 = $460.00 |
| I/O (secondary) | $60.00 | ~$160.00 × 2 = $320.00 |
| **Cross-Region Transfer** | ~$200.00 | ~$200.00 |
| Replicated Write I/O | ~$100.00 | N/A |
| **Total (USD)** | **~$3,448** | **~$5,599** |
| **Total (THB)** | **~฿107,233** | **~฿174,129** |

### สรุป Scenario 5

| Option | ฿/เดือน | เทียบ |
|---|---|---|
| ✅ **Aurora Global Database** | **~฿107,233** | ถูกกว่า + Global Database feature built-in |
| RDS gp3 Cross-Region | ~฿174,129 | แพงกว่า ~62% + ต้อง manage replication เอง |

> **แนะนำ: Aurora Global Database** — ไม่มีทางเลือกอื่นที่ดีกว่าสำหรับ multi-region
> RDS ไม่มี Global Database feature ต้องใช้ cross-region read replicas ซึ่งซับซ้อนกว่ามาก

---

## Overall Comparison (THB/month)

| Scenario | Users | Aurora Std | Aurora I/O-Opt | RDS gp3 | RDS io2 | Winner |
|---|---|---|---|---|---|---|
| 1. Small Org | 50 | ฿2,692 | ฿3,483 | **฿1,085** | ฿12,288 | **RDS gp3** |
| 2. Enterprise | 200+ | ฿16,921 | ฿22,209 | **฿16,377** | ฿52,354 | **RDS gp3 ≈ Aurora** |
| 3. Province | 1M | **฿69,176** | ฿90,562 | ฿140,373 | ฿422,562 | **Aurora Std** |
| 4. Country | 10M+ | **฿215,739** | ฿288,492 | ฿570,175 | ฿1,351,656 | **Aurora Std** |
| 5. Global | 1K+ MR | **~฿107,233** | — | ~฿174,129 | — | **Aurora Global** |

---

## Decision Guide

```
ผู้ใช้ < 50 คน, งบจำกัด
  └─→ RDS gp3 Single-AZ (db.t3.small)     ~฿1,085/mo

ผู้ใช้ 200+ คน, ต้องการ HA
  ├─→ RDS gp3 Multi-AZ                     ~฿16,377/mo (ถูกสุด)
  └─→ Aurora Standard (writer+reader)       ~฿16,921/mo (fast failover, better HA)

ผู้ใช้ 1M+ คน, ต้องการ Read Replicas
  └─→ Aurora Standard                      ~฿69,176/mo (shared storage ชนะ)

ผู้ใช้ 10M+ คน, ระดับประเทศ
  └─→ Aurora Standard/I/O-Opt              ~฿215K-288K/mo

Multi-Region / Global
  └─→ Aurora Global Database               ทางเลือกเดียวที่สมเหตุสมผล
```

## Key Takeaways

1. **RDS gp3 ชนะสำหรับองค์กรเล็ก-กลาง (< 200 users)** — db.t3.small ถูกกว่า Aurora minimum (db.t3.medium) + Single-AZ ลดค่าใช้จ่ายครึ่งหนึ่ง

2. **Aurora ชนะเมื่อมี Read Replicas** — shared storage layer ทำให้ไม่ต้องจ่าย storage ซ้ำทุก instance ในขณะที่ RDS ทุก instance มี EBS แยกกัน

3. **RDS Multi-AZ จ่าย storage+IOPS ซ้ำ 2 เท่า** — นี่คือจุดที่ Aurora ได้เปรียบมากที่สุด เพราะ Aurora storage เป็น Multi-AZ by default โดยไม่ต้องจ่ายเพิ่ม

4. **RDS io2 แพงเกินไปในแทบทุกกรณี** — ใช้เฉพาะเมื่อต้องการ 99.999% durability guarantee จริงๆ

5. **Aurora Global Database เป็นทางเลือกเดียวสำหรับ Multi-Region** — RDS ทำ cross-region ได้แต่ซับซ้อนและแพงกว่า

6. **จุดตัด (Crossover Point):** เมื่อ instance count ≥ 3 (writer + 2 readers) Aurora มักถูกกว่า RDS Multi-AZ เสมอ

---

*Last updated: 14 Feb 2026 | Exchange rate: 1 USD = 31.10 THB | Region: ap-southeast-1 (Singapore)*
*Pricing source: AWS official pricing pages, dbcost.com, cloudprice.net*
