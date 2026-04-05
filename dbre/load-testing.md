# MySQL Load Testing & VM Optimization

[← DBRE Home](README.md) | [← Main](../README.md)

---

## Why Load Test `[B]`

Load testing answers questions that can't be answered by looking at production:

- What is the breaking point of this MySQL instance?
- Will this schema change hold up under production traffic?
- What is the baseline TPS/latency before and after a config change?
- Can this instance survive a traffic spike 3× normal?
- Does this VM size actually fit our workload?

**Rule:** always establish a baseline before changing anything — config, schema, VM size, or storage.

---

## Tools `[B]`

| Tool | Best for | Built-in? |
|------|----------|-----------|
| `sysbench` | Standard OLTP benchmark, scriptable, realistic | No — install |
| `mysqlslap` | Quick multi-threaded query load, simple | Yes — ships with MySQL |
| `tpcc-mysql` | TPC-C standard (order-entry workload), most realistic | No |
| `pt-query-digest` | Replay real production traffic from slow log | Percona Toolkit |
| `Percona Playback` | Replay exact production query stream | No |

**Start with `sysbench`** for most purposes — it is the most widely used and results are comparable across teams.

---

## sysbench `[I]`

### Install

```bash
# Ubuntu / Debian
apt-get install sysbench

# RHEL / CentOS
yum install sysbench

# macOS
brew install sysbench
```

### Prepare test schema

```bash
sysbench \
  --db-driver=mysql \
  --mysql-host=127.0.0.1 \
  --mysql-port=3306 \
  --mysql-user=bench \
  --mysql-password=bench \
  --mysql-db=sbtest \
  --tables=10 \
  --table-size=1000000 \
  oltp_read_write prepare
```

```sql
-- Create benchmark user and database first
CREATE DATABASE sbtest;
CREATE USER 'bench'@'%' IDENTIFIED BY 'bench';
GRANT ALL ON sbtest.* TO 'bench'@'%';
```

### Run benchmarks

```bash
# --- Read/Write OLTP (most realistic: 70% read, 30% write) ---
sysbench \
  --db-driver=mysql \
  --mysql-host=127.0.0.1 \
  --mysql-user=bench --mysql-password=bench \
  --mysql-db=sbtest \
  --tables=10 --table-size=1000000 \
  --threads=32 \
  --time=300 \
  --report-interval=10 \
  oltp_read_write run

# --- Read-only (replicas, analytics) ---
sysbench ... --threads=64 oltp_read_only run

# --- Write-heavy (insert throughput) ---
sysbench ... --threads=16 oltp_write_only run

# --- Point select (cache hit testing) ---
sysbench ... --threads=128 oltp_point_select run

# Cleanup after tests
sysbench ... oltp_read_write cleanup
```

### Reading sysbench output

```
SQL statistics:
    queries performed:
        read:   2,801,420    ← SELECT count
        write:    800,406    ← INSERT/UPDATE/DELETE
        total:  3,601,826
    transactions:   200,101  (667.00 per sec)  ← TPS — primary metric
    queries:      3,601,826  (12,006.09 per sec)
    ignored errors:       0
    reconnects:           0

Latency (ms):
    min:    2.34
    avg:   47.96
    max:  892.10
    95th percentile:  99.33   ← watch this — your SLO boundary
    99th percentile: 147.00   ← should not spike after config/schema change

Threads fairness:
    events (avg/stddev): 6253.2/45.3
```

**Key numbers to track:**
- **TPS** (transactions per second) — primary throughput metric
- **p95 latency** — your application's experienced latency under load
- **p99 latency** — tail latency, indicates lock contention or IO bottleneck
- **Errors / reconnects** — should be zero; any value indicates a problem

### Thread count ramp test

Find the saturation point — the thread count where TPS stops growing and latency spikes:

```bash
for THREADS in 1 2 4 8 16 32 64 128 256; do
  echo -n "Threads: $THREADS  "
  sysbench \
    --db-driver=mysql \
    --mysql-host=127.0.0.1 \
    --mysql-user=bench --mysql-password=bench \
    --mysql-db=sbtest \
    --tables=10 --table-size=1000000 \
    --threads=$THREADS \
    --time=60 \
    oltp_read_write run 2>&1 \
    | grep -E "transactions:|95th percentile"
done
```

```
# Example output — TPS grows until 32 threads, then plateaus
Threads: 1    transactions: 120/s   p95: 9ms
Threads: 4    transactions: 450/s   p95: 11ms
Threads: 16   transactions: 1,400/s p95: 15ms
Threads: 32   transactions: 2,100/s p95: 22ms   ← sweet spot
Threads: 64   transactions: 2,050/s p95: 48ms   ← saturating
Threads: 128  transactions: 1,900/s p95: 120ms  ← past saturation, latency blowing up
```

The saturation point tells you the optimal `max_connections` and thread pool size for this instance.

---

## mysqlslap `[B]`

Simpler than sysbench — built into MySQL. Good for quick tests against your actual schema.

```bash
# Auto-generate a test schema and hammer it with 50 concurrent clients
mysqlslap \
  --host=127.0.0.1 \
  --user=root \
  --concurrency=50 \
  --iterations=3 \
  --auto-generate-sql \
  --auto-generate-sql-load-type=mixed \
  --number-of-queries=10000 \
  --verbose

# Test a specific query under load
mysqlslap \
  --host=127.0.0.1 \
  --user=root \
  --concurrency=100 \
  --iterations=5 \
  --query="SELECT * FROM orders WHERE customer_id = FLOOR(1 + RAND() * 100000)" \
  --create-schema=mydb
```

---

## Monitoring During Load Tests `[I]`

Always capture these in parallel while sysbench runs:

```bash
# Terminal 1: watch InnoDB in real time
mysqladmin -u root -p extended-status -i 1 | grep -E \
  "Threads_running|Threads_connected|Slow_queries|Innodb_row_lock_waits|Innodb_buffer_pool_read"

# Terminal 2: watch OS resources
iostat -xm 2        # disk IO — watch %util and await on MySQL disk
vmstat 2            # CPU, memory, swap
```

```sql
-- Terminal 3: watch for lock contention
SELECT
  r.trx_mysql_thread_id AS waiting,
  b.trx_mysql_thread_id AS blocking,
  b.trx_query AS blocking_query,
  r.trx_query AS waiting_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;
```

**What to look for:**

| Signal | Interpretation |
|--------|---------------|
| `%util` on disk > 80% | IO-bound — storage is the bottleneck |
| `await` (disk) > 5ms on SSD | Disk queue backing up |
| CPU iowait > 20% | Waiting on disk, not computing |
| `Threads_running` > 2× vCPU count | CPU-bound or lock contention |
| `Innodb_row_lock_waits` growing | Schema design or query contention issue |
| Swap usage > 0 | `innodb_buffer_pool_size` too large for available RAM |

---

## VM Optimization `[I]`

### Memory — Most Important Setting

`innodb_buffer_pool_size` is the single highest-impact tuning parameter. All hot data and indexes
should fit in it. Buffer pool misses = disk reads = slow queries.

```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf

# Buffer pool: 70-80% of total RAM for a dedicated MySQL VM
# 16GB RAM → innodb_buffer_pool_size = 12G
# 64GB RAM → innodb_buffer_pool_size = 48G
innodb_buffer_pool_size = 48G

# Multiple buffer pool instances — reduces contention on high-core machines
# One instance per 1-2GB of buffer pool, up to number of vCPUs
innodb_buffer_pool_instances = 16

# How long to wait for a row lock before timeout (default 50s — often too long)
innodb_lock_wait_timeout = 10

# Per-thread sort buffer (allocated per connection — don't set too high)
sort_buffer_size = 4M
join_buffer_size = 4M

# Read buffer (used for full table scans)
read_buffer_size = 2M
read_rnd_buffer_size = 8M
```

**Verify buffer pool effectiveness after load test:**

```sql
-- Hit ratio should be > 99%
SELECT
  (1 - (
    variable_value / (
      SELECT variable_value FROM performance_schema.global_status
      WHERE variable_name = 'Innodb_buffer_pool_read_requests'
    )
  )) * 100 AS buffer_pool_hit_pct
FROM performance_schema.global_status
WHERE variable_name = 'Innodb_buffer_pool_reads';
```

### InnoDB IO Settings

```ini
# Disk IO capacity — set to IOPS of your storage
# SSD (gp3 3000 IOPS default): innodb_io_capacity = 2000
# SSD (io2 high IOPS): innodb_io_capacity = 10000
# NVMe local SSD: innodb_io_capacity = 50000
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000       # burst limit during checkpoint flush

# SSD — reduce random page cost (default 4.0 is for spinning disk)
innodb_random_read_ahead = OFF

# Flush method for SSD — O_DIRECT bypasses OS cache (avoids double buffering)
innodb_flush_method = O_DIRECT

# How often InnoDB flushes logs to disk
# 1 = flush on every commit (safest, ACID-compliant)
# 2 = flush once per second (faster, lose up to 1s of data on crash)
innodb_flush_log_at_trx_commit = 1   # keep at 1 for production OLTP
                                      # set to 2 for analytics/staging

# Log file size — larger = fewer checkpoints = better write performance
# Set to 25% of innodb_buffer_pool_size
innodb_log_file_size = 4G
innodb_log_buffer_size = 256M

# Write/read threads — match to storage concurrency
innodb_write_io_threads = 8
innodb_read_io_threads = 8
```

### Connection and Thread Settings

```ini
# Max connections — keep conservative, use ProxySQL for pooling
# Formula: (RAM_GB - buffer_pool_GB) * 150 ≈ safe max
max_connections = 500

# Thread cache — reuse threads instead of creating new ones
thread_cache_size = 64

# Table cache — open table descriptors kept in memory
table_open_cache = 4000
table_definition_cache = 2000

# Temp tables in memory before spilling to disk
tmp_table_size = 256M
max_heap_table_size = 256M
```

### Replication Settings

```ini
# Parallel replication — uses multiple threads on replica (MySQL 5.7+)
slave_parallel_workers = 8
slave_parallel_type = LOGICAL_CLOCK   # better parallelism than DATABASE mode

# Binlog format — ROW is required for Orchestrator and most HA tools
binlog_format = ROW
binlog_row_image = MINIMAL            # only log changed columns, reduces binlog size

# Expire binlogs after N days (don't let disk fill up)
expire_logs_days = 7                  # MySQL 5.7
binlog_expire_logs_seconds = 604800   # MySQL 8.0 (7 days)

# GTID — enables easier failover and replica re-pointing
gtid_mode = ON
enforce_gtid_consistency = ON
```

---

## OS-Level Optimization `[I]`

### Kernel Parameters

```bash
# /etc/sysctl.conf — apply with: sysctl -p
# Sources: https://www.percona.com/blog/mysql-101-linux-tuning-for-mysql/
#          https://www.percona.com/blog/linux-os-tuning-for-mysql-database-performance/

# Reduce swappiness — MySQL manages its own memory (buffer pool)
# 0 = never swap (risky if buffer pool misconfigured)
# 1 = swap only under extreme memory pressure (recommended)
vm.swappiness = 1

# Network — for high connection counts
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# File handles — MySQL opens many files (tables, binlogs, redo logs)
fs.file-max = 2097152
```

```bash
# /etc/security/limits.conf — MySQL process limits
mysql soft nofile 65535
mysql hard nofile 65535
mysql soft nproc  65535
mysql hard nproc  65535
```

### Transparent Huge Pages — Disable

THP causes latency spikes with MySQL (memory allocation stalls during page compaction) — source: [Percona: Transparent Huge Pages refresher](https://www.percona.com/blog/transparent-huge-pages-refresher/):

```bash
# Disable immediately
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent — add to /etc/rc.local or a systemd unit
cat >> /etc/rc.local << 'EOF'
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF
```

### IO Scheduler

```bash
# Check current scheduler
cat /sys/block/sda/queue/scheduler

# For NVMe / SSD — use 'none' or 'mq-deadline' (not 'cfq' which is for spinning disk)
echo none > /sys/block/nvme0n1/queue/scheduler
echo mq-deadline > /sys/block/sda/queue/scheduler

# Make persistent via udev rule
cat > /etc/udev/rules.d/60-mysql-io-scheduler.rules << 'EOF'
ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd*", ATTR{queue/scheduler}="mq-deadline"
EOF
```

### Filesystem

```bash
# Mount MySQL data directory with noatime (skip access time writes)
# /etc/fstab
UUID=<uuid>  /var/lib/mysql  ext4  defaults,noatime,nodiratime  0  2

# XFS is preferred over ext4 for large MySQL deployments
# Better write performance and online resize support
mkfs.xfs /dev/sdc
mount -o noatime,nodiratime /dev/sdc /var/lib/mysql
```

---

## GCP VM Optimization for MySQL `[I]`

### Machine Family Selection

| Workload | Machine type | RAM | Why |
|----------|-------------|-----|-----|
| Dev / staging | `n2-standard-4` | 16 GB | Cheap baseline |
| OLTP primary (small) | `n2-highmem-8` | 64 GB | Memory > CPU for MySQL |
| OLTP primary (prod) | `n2-highmem-16` | 128 GB | Fit full working set in buffer pool |
| Write-heavy primary | `c3-standard-22` | 88 GB | Higher memory bandwidth, latest CPU |
| Analytics replica | `n2-highmem-32` | 256 GB | Large buffer pool for full-scan workloads |
| Cost-sensitive | `n2d-highmem-8` | 64 GB | AMD EPYC — ~20% cheaper, similar perf |

**Rules:**
- Always prefer **highmem** over standard for MySQL — buffer pool fit is worth more than extra vCPUs
- `n2` (Intel Cascade/Ice Lake) has better single-thread performance than `n2d` (AMD) — matters for high-concurrency OLTP
- `c3` machines have higher memory bandwidth — better for buffer pool throughput on very large instances
- Never use `e2` (shared-core) for production MySQL — inconsistent CPU scheduling causes latency spikes

---

### Storage: Disk Types and Layout

**Disk type comparison** — source: [GCP Persistent Disk performance overview](https://cloud.google.com/compute/docs/disks/performance) · [Hyperdisk overview](https://cloud.google.com/compute/docs/disks/hyperdisks):

| Type | Max IOPS | Max throughput | IOPS/GB | Use for |
|------|----------|---------------|---------|---------|
| `pd-standard` | 7,500 | 400 MB/s | 0.75 | Never for MySQL primary |
| `pd-balanced` | 80,000 | 1,200 MB/s | 6 | Dev, replicas, low-write workloads |
| `pd-ssd` | 100,000 | 1,200 MB/s | 30 | Production primary — most common choice |
| `pd-extreme` | 120,000 | 2,400 MB/s | 120 | High-write primary, must be explicitly provisioned |
| `hyperdisk-balanced` | 160,000 | 2,400 MB/s | independent | IOPS and throughput independent of disk size |
| `hyperdisk-extreme` | 350,000 | 5,000 MB/s | independent | Extreme write workloads |
| `local-ssd` (NVMe) | 680,000+ | 5,400 MB/s | — | tmpdir, temp tables — **ephemeral, lost on VM stop** |

**`pd-ssd` IOPS scale with disk size** — up to the per-disk max ([GCP docs](https://cloud.google.com/compute/docs/disks/performance)):
```
100 GB pd-ssd  →  3,000 IOPS   (too low for prod)
500 GB pd-ssd  → 15,000 IOPS
1 TB  pd-ssd  → 30,000 IOPS
3 TB  pd-ssd  → 90,000 IOPS    (near maximum)
```
Provision disk larger than your data needs if you need the IOPS — disk is cheap, performance matters.

**`hyperdisk-balanced`** decouples IOPS from size — provision exactly what you need:
```hcl
resource "google_compute_disk" "mysql_data" {
  type                    = "hyperdisk-balanced"
  size                    = 500   # GB
  provisioned_iops        = 20000
  provisioned_throughput  = 500   # MB/s
}
```

---

### Disk Layout: Separate Disks per Function

Never put everything on one disk. Separate IO patterns reduce contention and let each disk be sized for its workload:

```
/var/lib/mysql/data    → pd-ssd or hyperdisk-balanced (data files, indexes)
/var/lib/mysql/binlog  → pd-ssd (sequential writes — smaller, fast)
/var/lib/mysql/redo    → local-ssd if available (high IOPS, InnoDB redo log)
/tmp / tmpdir          → local-ssd (temp tables, sort buffers spilling to disk)
```

```hcl
# Terraform — separate disks for MySQL node
resource "google_compute_disk" "data" {
  name = "mysql-data"
  type = "pd-ssd"
  size = 1000   # 1TB → 30,000 IOPS on pd-ssd
  zone = var.zone
}

resource "google_compute_disk" "binlog" {
  name = "mysql-binlog"
  type = "pd-ssd"
  size = 200
  zone = var.zone
}

resource "google_compute_instance" "mysql" {
  name         = "mysql-primary"
  machine_type = "n2-highmem-16"

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "mysql-data"
  }
  attached_disk {
    source      = google_compute_disk.binlog.id
    device_name = "mysql-binlog"
  }

  # Local SSD for tmpdir (ephemeral — only temp tables, not data)
  scratch_disk {
    interface = "NVME"
  }

  # Premium network tier for low-latency replication between nodes
  network_interface {
    network    = var.network
    nic_type   = "VIRTIO_NET"   # or GVNIC for >100Gbps
    access_config {}
  }

  # Ensure VM doesn't live-migrate during maintenance — causes MySQL stalls
  # source: https://cloud.google.com/compute/docs/instances/setting-vm-host-options
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }
}
```

Mount configuration:

```bash
# /etc/fstab — use UUID, noatime, XFS for data disk
UUID=$(blkid -s UUID -o value /dev/disk/by-id/google-mysql-data)
echo "UUID=$UUID /var/lib/mysql xfs defaults,noatime,nodiratime 0 2" >> /etc/fstab

UUID=$(blkid -s UUID -o value /dev/disk/by-id/google-mysql-binlog)
echo "UUID=$UUID /var/log/mysql/binlog xfs defaults,noatime,nodiratime 0 2" >> /etc/fstab

# Local SSD — format and mount for tmpdir
mkfs.xfs /dev/nvme0n1
echo "/dev/nvme0n1 /var/tmp/mysql xfs defaults,noatime 0 0" >> /etc/fstab
```

```ini
# my.cnf — point tmpdir and binlog to separate disks
[mysqld]
datadir   = /var/lib/mysql
tmpdir    = /var/tmp/mysql        # local SSD
log_bin   = /var/log/mysql/binlog/mysql-bin
```

---

### innodb_io_capacity per Disk Type

```ini
# pd-balanced (6 IOPS/GB, 500GB disk = ~3000 IOPS)
innodb_io_capacity     = 2000
innodb_io_capacity_max = 3000

# pd-ssd (1TB = 30,000 IOPS)
innodb_io_capacity     = 20000
innodb_io_capacity_max = 30000

# pd-extreme (provisioned 60,000 IOPS)
innodb_io_capacity     = 40000
innodb_io_capacity_max = 60000

# hyperdisk-balanced (provisioned 20,000 IOPS)
innodb_io_capacity     = 14000
innodb_io_capacity_max = 20000

# local-ssd NVMe (if data disk — very high)
innodb_io_capacity     = 100000
innodb_io_capacity_max = 200000
```

Set `innodb_io_capacity` to ~70% of measured write IOPS — source: [Percona InnoDB optimization](https://www.percona.com/blog/innodb-performance-optimization-basics-updated/).

Measure actual disk IOPS before setting — provisioned != delivered:

```bash
fio --name=mysql-randrw \
    --filename=/var/lib/mysql/fio-test \
    --rw=randrw --rwmixread=70 \
    --bs=16k --ioengine=libaio \
    --iodepth=64 --numjobs=4 \
    --size=4G --runtime=60 \
    --group_reporting \
    --output-format=normal \
  | grep -E "IOPS|BW|lat"

# Set innodb_io_capacity = measured_write_IOPS * 0.7
```

---

### CPU and NUMA Tuning

**Source:** [MySQL 8.0 InnoDB startup options — innodb_numa_interleave](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_numa_interleave)

```ini
# my.cnf — for VMs with >= 16 vCPU
[mysqld]

# NUMA interleaving: allocates buffer pool across all NUMA nodes
# Prevents buffer pool allocation from being pinned to one NUMA node
# Significant on n2-highmem-32+ (multi-NUMA boundary)
innodb_numa_interleave = ON

# Thread concurrency: 0 = unlimited (GCP VMs are single-socket, 0 is fine up to 16 vCPU)
# For >16 vCPU set to 2x vCPU count to limit context switching
innodb_thread_concurrency = 0

# Parallel read threads for full scans (analytics replica)
innodb_parallel_read_threads = 4
```

```bash
# Check NUMA topology on your GCP VM
numactl --hardware

# For VMs with >1 NUMA node, start MySQL with NUMA interleave
numactl --interleave=all mysqld &
# Or set in systemd unit:
# ExecStart=/usr/bin/numactl --interleave=all /usr/sbin/mysqld
```

---

### CPU Governor

GCP VMs sometimes boot with `powersave` governor, causing CPU frequency scaling that hurts latency — source: [Percona: CPU governor and MySQL performance](https://www.percona.com/blog/cpu-governor-performance/):

```bash
# Check current governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Set to performance
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo performance > $cpu
done

# Verify
grep -r . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | head -5
```

---

### Network: Placement Policy for Replication

Primary and replicas should be in the same zone for lowest replication lag, and in a compact placement policy to minimize physical distance — source: [GCP: compact placement policies](https://cloud.google.com/compute/docs/instances/use-compact-placement-policies):

```hcl
resource "google_compute_resource_policy" "mysql_cluster" {
  name   = "mysql-cluster-placement"
  region = var.region

  group_placement_policy {
    collocation = "COLLOCATED"   # pack VMs physically close — < 1ms network latency
  }
}

resource "google_compute_instance" "mysql_primary" {
  resource_policies = [google_compute_resource_policy.mysql_cluster.id]
  # ...
}

resource "google_compute_instance" "mysql_replica" {
  resource_policies = [google_compute_resource_policy.mysql_cluster.id]
  # ...
}
```

Enable **GVNIC** (Google Virtual NIC) on n2/c3 for higher network throughput (relevant for large replica lag catch-up or xtrabackup transfers):

```hcl
network_interface {
  nic_type = "GVNIC"   # up to 100 Gbps vs 32 Gbps for VIRTIO_NET on n2
}
```

---

### GCP Startup Script: Persist All OS Tuning

GCP startup scripts run on every boot — use them to apply OS settings that don't survive reboot:

```bash
# /etc/google-cloud/startup-scripts/mysql-tuning.sh
# Register: gcloud compute instances add-metadata mysql-primary \
#   --metadata-from-file startup-script=/etc/google-cloud/startup-scripts/mysql-tuning.sh

#!/bin/bash
set -e

# Disable transparent huge pages
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Set CPU governor to performance
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo performance > $cpu 2>/dev/null || true
done

# IO scheduler: none for NVMe (local SSD), mq-deadline for pd-ssd
for dev in /sys/block/nvme*/queue/scheduler; do
  echo none > $dev 2>/dev/null || true
done
for dev in /sys/block/sd*/queue/scheduler; do
  echo mq-deadline > $dev 2>/dev/null || true
done

# Kernel tuning
sysctl -w vm.swappiness=1
sysctl -w vm.dirty_ratio=15
sysctl -w vm.dirty_background_ratio=5
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535

echo "MySQL OS tuning applied"
```

---

### Checklist: GCP MySQL Node

- [ ] Machine type is `n2-highmem` or `c3` — not `e2`, not `n1`
- [ ] `on_host_maintenance = TERMINATE` — prevents live migration stalls
- [ ] Data disk: `pd-ssd` ≥ 500 GB or `hyperdisk-balanced` with explicit IOPS
- [ ] Binlog on separate disk from data
- [ ] Local SSD attached and mounted as `tmpdir`
- [ ] `/etc/fstab` uses UUID, `noatime`, XFS
- [ ] `innodb_io_capacity` set to 70% of measured disk IOPS
- [ ] `innodb_buffer_pool_size` = 70–80% of RAM
- [ ] `innodb_numa_interleave = ON` on ≥ 16 vCPU VMs
- [ ] THP disabled (startup script)
- [ ] CPU governor set to `performance` (startup script)
- [ ] IO scheduler `none` for NVMe, `mq-deadline` for pd-* (startup script)
- [ ] Primary and replicas in same zone, compact placement policy
- [ ] GVNIC enabled for high-throughput replication

---

### References

| Recommendation | Source |
|---------------|--------|
| Disk types, IOPS/throughput specs | [GCP Persistent Disk performance overview](https://cloud.google.com/compute/docs/disks/performance) |
| Hyperdisk provisioned IOPS | [GCP Hyperdisk overview](https://cloud.google.com/compute/docs/disks/hyperdisks) |
| Optimizing PD performance | [GCP: Optimizing Persistent Disk performance](https://cloud.google.com/compute/docs/disks/optimizing-pd-performance) |
| `on_host_maintenance = TERMINATE` | [GCP: VM host options](https://cloud.google.com/compute/docs/instances/setting-vm-host-options) |
| Compact placement policy | [GCP: Compact placement policies](https://cloud.google.com/compute/docs/instances/use-compact-placement-policies) |
| `innodb_numa_interleave` | [MySQL 8.0 Reference: InnoDB startup options](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_numa_interleave) |
| `innodb_io_capacity` tuning | [Percona: InnoDB performance optimization basics](https://www.percona.com/blog/innodb-performance-optimization-basics-updated/) |
| CPU governor impact | [Percona: CPU governor and MySQL performance](https://www.percona.com/blog/cpu-governor-performance/) |
| Transparent Huge Pages | [Percona: Transparent Huge Pages refresher](https://www.percona.com/blog/transparent-huge-pages-refresher/) |
| `vm.swappiness` + Linux tuning | [Percona: MySQL 101 Linux tuning](https://www.percona.com/blog/mysql-101-linux-tuning-for-mysql/) · [Percona: Linux OS tuning](https://www.percona.com/blog/linux-os-tuning-for-mysql-database-performance/) |

---

### AWS

| Workload | Instance | Storage |
|----------|----------|---------|
| Dev / staging | `db.t3.large` | gp3 |
| OLTP primary | `db.r6g.2xlarge` (8 vCPU, 64GB) | gp3 (3000 IOPS base) or io2 |
| Write-heavy | `db.r6g.4xlarge` | io2 (provision IOPS explicitly) |
| Analytics | `db.r6g.8xlarge` | gp3 |

```
gp3: 3000 IOPS baseline, up to 16000 IOPS provisioned separately from storage size
     → set innodb_io_capacity = 2500 for baseline, higher if provisioned
io2: up to 64000 IOPS, expensive — only for write-intensive workloads
```

---

## Before/After Benchmark Workflow `[B]`

Use this pattern any time you change MySQL config, VM size, or storage:

```bash
# 1. Establish baseline (before change)
sysbench ... --threads=32 --time=300 oltp_read_write run > before.txt

# 2. Make the change (resize VM, update my.cnf, upgrade storage)

# 3. Run identical test after
sysbench ... --threads=32 --time=300 oltp_read_write run > after.txt

# 4. Compare key metrics
grep -E "transactions:|95th percentile|99th percentile" before.txt after.txt
```

**Never tune blind.** If TPS decreased or p99 increased after a change, revert it.

---

## Related Topics

- [Performance Tuning](performance.md) — query optimization, indexes, EXPLAIN
- [Observability](observability.md) — monitoring InnoDB metrics during load tests
- [HA & Failover](ha-failover.md) — testing failover under load
- [Scaling Databases](scaling.md) — when load testing reveals you need to scale out
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-query-digest to analyze load test queries
