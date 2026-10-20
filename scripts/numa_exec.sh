#!/bin/bash
# Keep page cache out of GPU HBM on GB200 (each GPU's HBM is a CPU-less NUMA node): bind memory
# to the NUMA nodes that have CPUs, then exec the command.  No-op when numactl is missing.
if command -v numactl >/dev/null 2>&1; then
  N=$(numactl -H 2>/dev/null | awk '/^node [0-9]+ cpus: [0-9]/{print $2}' | paste -sd, -)
  [ -n "$N" ] && exec numactl --membind="$N" --cpunodebind="$N" "$@"
fi
exec "$@"
