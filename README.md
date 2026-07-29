# Linux Kernel Isolation Primitives

Hands-on demonstrations of the two kernel mechanisms that every container
runtime — Docker, Kubernetes, Podman, containerd — is built on top of:
**cgroups** (resource limiting) and **namespaces** (visibility isolation).

Every script here talks directly to the raw kernel interfaces
(`/sys/fs/cgroup`, `ip netns`, `unshare`) with no container runtime, no
systemd unit files, and no external dependencies beyond standard Linux
tooling. The goal is to make the mechanism transparent: a container is not
a special kind of process — it's a regular process wrapped in namespaces
(controlling what it can see) and constrained by a cgroup (controlling how
much it can use).

All commands in this repo were run and verified live on a production Ubuntu
server (kernel 6.14, cgroups v2 unified hierarchy) as part of a structured
Linux systems engineering learning path — not copied from documentation
without verification.

## Contents

### [`01-cgroups-v2/`](./01-cgroups-v2/)
- **`memory-hard-limit-demo.sh`** — sets `memory.max`, proves the kernel
  OOM-kills a process the instant it crosses the limit.
- **`memory-soft-limit-demo.sh`** — sets `memory.high` below `memory.max`,
  proves the kernel throttles (rather than kills) a process crossing the
  soft line, using it as a buffer zone against temporary memory spikes.

### [`02-namespaces/`](./02-namespaces/)
- **`pid-namespace-demo.sh`** — proves a process inside a new PID namespace
  believes it is PID 1 and can only see itself in its process list.
- **`network-namespace-demo.sh`** — proves a fresh network namespace has
  zero connectivity, then builds a veth pair by hand to bridge it back to
  the host — the same mechanism Docker uses for every container's network.

## Why this exists

Most engineers interact with these mechanisms only through high-level
wrappers (`docker run --memory=`, Kubernetes resource `limits:`, `.service`
file `MemoryMax=`). This repo strips those wrappers away to show the
underlying kernel behavior directly — the same primitives Google's Borg,
Meta's internal container system, and every `docker run` invocation
ultimately reduce to.

## Requirements

- Linux with cgroups v2 (check: `cat /sys/fs/cgroup/cgroup.controllers`)
- `iproute2` (`ip` command) and `util-linux` (`unshare` command)
- Root privileges
- Python 3 (for test workloads only)

## Usage

Each script is self-contained and includes a `cleanup` argument to tear
down anything it created:

```bash
sudo ./01-cgroups-v2/memory-hard-limit-demo.sh
sudo ./01-cgroups-v2/memory-hard-limit-demo.sh cleanup

sudo ./02-namespaces/network-namespace-demo.sh
sudo ./02-namespaces/network-namespace-demo.sh cleanup
```

## License

MIT