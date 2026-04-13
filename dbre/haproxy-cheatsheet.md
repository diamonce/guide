# HAProxy Commands Cheat Sheet

[← DBRE Home](README.md)

---

## Connect & Inspect

```bash
# Stats web UI (read-only)
open http://localhost:8404/stats

# Runtime API via socket (read-write — requires stats socket in global config)
# In the lab:
docker exec haproxy socat stdio /var/run/haproxy/admin.sock <<< "show info"

# Shorthand alias for the rest of this doc:
alias hap='docker exec haproxy socat stdio /var/run/haproxy/admin.sock'

# Show all backends and their servers
hap <<< "show servers state"

# Show stat summary (CSV — pipe to column for readability)
hap <<< "show stat" | cut -d',' -f1,2,5,6,7,8,18,19 | column -t -s','

# Show backend list
hap <<< "show backend"

# HAProxy version and uptime
hap <<< "show info" | grep -E "^(Version|Uptime|Maxconn|CurrConns)"
```

---

## Server States

| State | New connections | Existing connections | Use case |
|-------|----------------|---------------------|----------|
| `ready` | Yes | Kept | Normal operation |
| `drain` | No | Kept until done | Graceful removal — patch/upgrade |
| `maint` | No | Dropped immediately | Emergency removal |

```bash
# Set a server to drain (new traffic stops; existing sessions finish)
hap <<< "set server proxysql-nodes/proxysql2 state drain"

# Hard remove (drops all active connections immediately)
hap <<< "set server proxysql-nodes/proxysql2 state maint"

# Bring back online
hap <<< "set server proxysql-nodes/proxysql2 state ready"

# Disable / enable shorthand (equivalent to maint / ready)
hap <<< "disable server proxysql-nodes/proxysql2"
hap <<< "enable server proxysql-nodes/proxysql2"
```

---

## Patch One ProxySQL Node — Zero Downtime

The lab HAProxy backend `proxysql-nodes` has two servers: `proxysql1` and `proxysql2`.
Traffic always flows through the surviving node while the other is being patched.

```
HAProxy :6033
    ├── proxysql1 (proxysql:6033)   ← node-1
    └── proxysql2 (proxysql2:6033)  ← node-2
```

### Step 1 — Verify both nodes are UP

```bash
hap <<< "show servers state proxysql-nodes"
# Both should show state=2 (READY), check=7 (passing)
# scur = current sessions on each server
```

### Step 2 — Drain the node to patch (proxysql2 in this example)

```bash
hap <<< "set server proxysql-nodes/proxysql2 state drain"
```

HAProxy immediately stops routing new connections to `proxysql2`. Existing connections
finish naturally. All new app connections go to `proxysql1`.

### Step 3 — Wait for active sessions to reach zero

```bash
# Watch scur (current sessions) drop — safe to proceed when it hits 0
watch -n1 "docker exec haproxy socat stdio /var/run/haproxy/admin.sock \
  <<< 'show stat' | awk -F, '\$1==\"proxysql-nodes\" && \$2==\"proxysql2\" {print \"scur=\"\$5}'"
```

### Step 4 — Patch the ProxySQL node

```bash
# Restart the container (upgrade image, apply config changes, etc.)
docker restart proxysql2

# Or upgrade to a specific version:
# docker compose up -d --no-deps proxysql2

# Verify the node recovered and its cluster peer synced config
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass \
  -e "SELECT hostname, port FROM proxysql_servers" 2>/dev/null
```

### Step 5 — Restore the node

```bash
hap <<< "set server proxysql-nodes/proxysql2 state ready"
```

### Step 6 — Verify traffic is flowing to both nodes again

```bash
hap <<< "show servers state proxysql-nodes"
# Both state=2 (READY), sessions distributing across both
```

### Repeat for the other node

```bash
# Now drain node-1 and patch it the same way
hap <<< "set server proxysql-nodes/proxysql1 state drain"
# ... wait for scur=0, patch, restore
hap <<< "set server proxysql-nodes/proxysql1 state ready"
```

---

## Graceful HAProxy Config Reload

No connection drops — HAProxy forks a new process, drains old one.

```bash
# In the lab (send SIGUSR2 for graceful reload in HAProxy 2.4+)
docker kill -s USR2 haproxy

# Or reload via haproxy binary (old-style, works on all versions)
docker exec haproxy sh -c \
  'haproxy -f /usr/local/etc/haproxy/haproxy.cfg -p /var/run/haproxy.pid \
   -sf $(cat /var/run/haproxy.pid) 2>/dev/null'

# Verify config before applying
docker exec haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

---

## Weight Adjustment (Traffic Shifting)

Use weight to shift load gradually instead of hard on/off.

```bash
# Route only 10% of new connections to proxysql2 (default weight = 1 = 100%)
hap <<< "set server proxysql-nodes/proxysql2 weight 10%"

# Restore full weight
hap <<< "set server proxysql-nodes/proxysql2 weight 100%"

# View current weights
hap <<< "show servers state proxysql-nodes"
```

---

## Health Check Status

```bash
# Show last health check result per server
hap <<< "show servers state" | column -t

# State field values:
#   0 = STOPPED
#   1 = STARTING
#   2 = RUNNING (READY)
#   3 = STOPPING (drain/maint)
#   6 = DRAIN
#   9 = MAINT (maintenance)

# Check field values (health check result):
#   0 = unknown
#   1 = failed
#   2 = passed with checks disabled
#   3 = passed
#   4 = agent check passed
#   6 = passed (check + agent)
#   7 = all checks passing
```

---

## Useful Stats Fields

```bash
# Show key fields for all backends (scur=current sessions, stot=total, econ=errors)
hap <<< "show stat" | awk -F, 'NR==1 || $1 ~ /proxysql/ {
  printf "%-20s %-15s scur=%-5s stot=%-8s econ=%-5s\n", $1, $2, $5, $8, $14
}'

# Show only the proxysql-nodes backend
hap <<< "show stat" | grep proxysql-nodes | cut -d',' -f1,2,5,6,7,8,13,14,18,19 | column -t -s','
```

CSV column index reference (HAProxy 2.x):

| Col | Field | Meaning |
|-----|-------|---------|
| 1 | `pxname` | Proxy (backend) name |
| 2 | `svname` | Server name (or FRONTEND/BACKEND) |
| 5 | `scur` | Current sessions |
| 6 | `smax` | Max sessions ever |
| 8 | `stot` | Total sessions |
| 14 | `econ` | Connection errors |
| 18 | `chkfail` | Health check failures |
| 19 | `chkdown` | Transitions to DOWN |

---

## Lab Quick Reference

```bash
# Backends and ports
# proxysql-nodes  :6033  leastconn — proxysql1 + proxysql2
# mysql-primary   :3306  writes     — mysql-primary only
# mysql-replicas  :3307  reads      — replica1 + replica2 round-robin
# valkey-primary  :6379  writes     — valkey
# valkey-replicas :6380  reads      — valkey-replica

# Stats socket (add to haproxy.cfg global section to enable):
# stats socket /var/run/haproxy/admin.sock mode 660 level admin expose-fd listeners
# stats timeout 30s

# Stats page (always available, no socket needed)
open http://localhost:8404/stats
```

---

[← DBRE Home](README.md) | [ProxySQL Cheat Sheet](proxysql-cheatsheet.md)
