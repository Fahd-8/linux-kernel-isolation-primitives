# Linux Namespaces — Built From Scratch, No Docker

This section demonstrates the kernel-level isolation mechanism that every
container runtime (Docker, Kubernetes, Podman, containerd) is built on top
of — without using any of that tooling. Just raw `ip` and `unshare` commands
from `iproute2` and `util-linux`.

## The core idea

A container is not a special kind of process. It's a regular Linux process
that has been given a restricted view of the system using **namespaces**.
Namespaces control *what a process can see* — as opposed to **cgroups**
(covered in `../01-cgroups-v2/`), which control *how much of a resource a
process can use*.

There are 8 namespace types in modern Linux:

| Namespace | Isolates |
|---|---|
| PID       | Other processes |
| Network   | The network stack (interfaces, IPs, routes) |
| Mount     | The filesystem view |
| UTS       | Hostname |
| User      | User/group ID mapping |
| IPC       | Shared memory & message queues between processes |
| Cgroup    | The cgroup hierarchy a process can see |
| Time      | System clock / boot time (added in kernel 5.6) |

This repo demonstrates the two most illustrative ones hands-on: **PID** and
**Network**.

## Demo 1 — PID namespace (`pid-namespace-demo.sh`)

Proves that a process inside a new PID namespace believes it is `PID 1`
(the number normally reserved for `init`/`systemd`), and can only see itself
in its own process list — even though on the real host it has a completely
ordinary, high-numbered PID.

```bash
sudo ./pid-namespace-demo.sh
```

Inside the namespace:
```
$ echo $$
1
$ ps aux
USER   PID  ... COMMAND
root   1    ... bash
root   15   ... ps aux
```

Exit with `exit` — the shell's real PID on the host reappears, unchanged.

## Demo 2 — Network namespace (`network-namespace-demo.sh`)

Proves two things in sequence:

1. **A freshly created network namespace has zero connectivity** — not even
   to the host it's running on. This is real isolation, not a display trick.
2. **A veth (virtual ethernet) pair can bridge the namespace back to the
   host** — one end of the pair lives in the namespace, the other stays on
   the host. This is exactly the mechanism Docker uses for every container's
   networking (visible on any Docker host via `ip link show`, where you'll
   see veth interfaces attached to `docker0` or a custom bridge).

```bash
sudo ./network-namespace-demo.sh          # run the full demo
sudo ./network-namespace-demo.sh cleanup  # tear down everything it created
```

Expected output includes:
```
[*] Attempting to reach 8.8.8.8 from inside the namespace (expected: FAIL)
ping: connect: Network is unreachable
[+] Confirmed: namespace has zero network connectivity.
...
[*] Ping from namespace -> host:
64 bytes from 10.200.1.1: icmp_seq=1 ttl=64 time=0.18 ms
```

## Why this matters

Every container platform — Docker, Kubernetes, AWS Fargate, Google's
internal Borg — ultimately reduces to this same primitive: a process,
wrapped in one or more namespaces, with a cgroup limiting its resource
consumption. Understanding these two mechanisms directly (rather than only
through `docker run` flags) makes debugging container networking, resource
limits, and process visibility issues far more tractable — you're reasoning
about the actual kernel behavior, not a black box.

## Requirements

- Linux with cgroups v2 and namespace support (kernel 4.6+, verified on
  Ubuntu with kernel 6.14)
- `iproute2` (`ip` command)
- `util-linux` (`unshare` command)
- Root privileges

## Related

See `../01-cgroups-v2/` for the resource-limiting half of this picture —
manually creating a cgroup, setting `memory.max` (hard limit) and
`memory.high` (soft throttle), and proving enforcement via a live OOM kill.