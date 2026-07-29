# Cgroups v2 — Built From Scratch, No systemd, No Docker

This section demonstrates Linux control groups (cgroups) — the kernel
mechanism that limits *how much* CPU, memory, and other resources a process
(or group of processes) can consume. This is the other half of container
isolation, alongside namespaces (see `../02-namespaces/`), which control
*what* a process can see rather than *how much* it can use.

Everything here is done directly against the raw `/sys/fs/cgroup`
filesystem — the same interface that systemd's `MemoryMax=`/`CPUQuota=`
directives and Docker's `--memory`/`--cpus` flags both write to under the
hood. Understanding this layer directly makes both of those tools
transparent rather than magic.

## Core concept

A cgroup is just a directory under `/sys/fs/cgroup/`. Creating one is
literally `mkdir` — the kernel automatically populates it with control
files (`memory.max`, `memory.current`, `cgroup.procs`, `cpu.max`, etc.).
Writing a process's PID into `cgroup.procs` puts that process "in the
bucket," and every limit written into that bucket's files applies to it
from that moment on.

## Demo 1 — Hard limit (`memory-hard-limit-demo.sh`)

Sets `memory.max` (a hard ceiling) and proves the kernel enforces it with
an immediate, unconditional OOM (Out-Of-Memory) kill the instant a process
crosses the line — verified via the kernel's own `memory.events` counters,
not just process exit codes (which can be misleading — some tools report
"success" even after being OOM-killed).

```bash
sudo ./memory-hard-limit-demo.sh
sudo ./memory-hard-limit-demo.sh cleanup
```

Expected tail of output:
```
Allocated 99 MB
Allocated 100 MB
low 0
high 0
max 35
oom 1
oom_kill 1
oom_group_kill 0
```

## Demo 2 — Soft limit (`memory-soft-limit-demo.sh`)

Sets **both** `memory.high` (soft throttle line) and `memory.max` (hard
kill line, set well above the soft line) to create a buffer zone. Proves
that crossing `memory.high` does **not** kill the process — instead the
kernel throttles it (scheduling penalty + aggressive reclaim of caches/
buffers) and the process survives, visibly slowed down, as long as it
doesn't reach `memory.max`.

```bash
sudo ./memory-soft-limit-demo.sh
sudo ./memory-soft-limit-demo.sh cleanup
```

Expected output includes:
```
Process <pid> is still alive (not OOM-killed).
low 0
high 3472
max 0
oom 0
oom_kill 0
```

`high` climbing into the thousands shows the kernel repeatedly intervening
to slow the process down; `oom_kill: 0` confirms it was never killed.

## Why two separate limits matter in production

A hard limit alone (`memory.max` with no `memory.high`) means any process
that spikes even briefly gets killed outright — abrupt, with dropped
connections and lost in-flight work. Setting `memory.high` below
`memory.max` gives the kernel a chance to reclaim memory and let a
temporary spike (a traffic burst, a large batch job) settle back down on
its own, reserving the hard kill for genuine runaway growth (e.g. an actual
memory leak) that throttling alone can't fix.

## Requirements

- Linux with cgroups v2 (unified hierarchy) mounted at `/sys/fs/cgroup`
  — verify with `cat /sys/fs/cgroup/cgroup.controllers` (should list
  `memory` among the controllers)
- Root privileges
- Python 3 (used only for the test workload, not required for cgroups
  themselves)

## Related

See `../02-namespaces/` for the isolation half of this picture — manually
creating a PID namespace (a process believing it's PID 1) and a network
namespace bridged back to the host via a veth pair.