#!/usr/bin/env python3
"""Evict clean page cache that the kernel parked in GPU HBM (GB200 exposes each GPU's HBM as a
NUMA node).  nvidia-smi shows it as used memory with no process, and CUDA cannot reclaim it.

No root needed: for each GPU NUMA node, a child bound to that node (numactl --membind) touches
anonymous memory in chunks; the kernel must reclaim that node's clean file pages to satisfy it.
The child then exits and the memory returns to the free pool.

Safe to run while other work shares the node:
  - a GPU that has any compute process is skipped (its HBM is also that node's memory, and
    touching past what is free would invite the OOM killer onto someone's job);
  - the child never touches more than MemFree + FilePages - 4 GiB of the node;
  - nodes with < 8 GiB of file pages are skipped (~2 GiB per node is not reclaimable anyway);
  - the child stops once file pages are < 4 GiB, or when, already past the node's free memory,
    4 more chunks brought no reduction.
GPU index i <-> the i-th CPU-less NUMA node in numeric order (2/10/18/26 on a 4-GPU node).

    python3 reclaim_hbm_pagecache.py        # needs the GPUs visible to nvidia-smi for the skip check
"""
import ctypes
import os
import subprocess
import sys
import time

CHUNK = 2 << 30               # 2 GiB per step
MARGIN_KB = 4 << 20           # keep 4 GiB of the node untouched
MIN_FILE_KB = 8 << 20         # below 8 GiB of page cache: nothing worth doing
STOP_FILE_KB = 4 << 20        # the child stops below 4 GiB


def meminfo(node):
    out = {}
    with open(f"/sys/devices/system/node/node{node}/meminfo") as f:
        for line in f:
            parts = line.split()
            out[parts[2].rstrip(":")] = int(parts[3])
    return out


def child(node, budget_kb):
    held = []
    free0 = meminfo(node)["MemFree"]
    history = []
    while True:
        fp = meminfo(node)["FilePages"]
        if fp < STOP_FILE_KB:
            break
        if (len(held) + 1) * CHUNK // 1024 > budget_kb:
            break
        touched_kb = len(held) * CHUNK // 1024
        history.append(fp)
        if touched_kb > free0 and len(history) > 4 and history[-5] - fp < (CHUNK // 1024) // 2:
            break   # under pressure and no longer reclaiming: what is left is not reclaimable
        b = bytearray(CHUNK)
        ctypes.memset((ctypes.c_char * CHUNK).from_buffer(b), 1, CHUNK)
        held.append(b)
    print(f"node{node}: touched {len(held) * CHUNK >> 30} GiB, FilePages now {meminfo(node)['FilePages'] >> 20} GiB",
          flush=True)


def gpu_nodes():
    nodes = []
    for d in os.listdir("/sys/devices/system/node"):
        if not d.startswith("node") or not d[4:].isdigit():
            continue
        n = int(d[4:])
        with open(f"/sys/devices/system/node/{d}/cpulist") as f:
            has_cpu = f.read().strip() != ""
        if not has_cpu and meminfo(n)["MemTotal"] > 0:
            nodes.append(n)
    return sorted(nodes)


def busy_gpus():
    """Indices of GPUs with at least one compute process; None if nvidia-smi cannot tell."""
    try:
        idx = subprocess.run(["nvidia-smi", "--query-gpu=index,pci.bus_id", "--format=csv,noheader"],
                             capture_output=True, text=True, timeout=60).stdout
        apps = subprocess.run(["nvidia-smi", "--query-compute-apps=gpu_bus_id", "--format=csv,noheader"],
                              capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return None
    bus = {}
    for line in idx.strip().splitlines():
        if "," in line:
            i, b = [x.strip() for x in line.split(",", 1)]
            bus[b.lower()] = int(i)
    if not bus:
        return None
    return {bus[a.strip().lower()] for a in apps.strip().splitlines() if a.strip().lower() in bus}


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--child":
        child(int(sys.argv[2]), int(sys.argv[3]))
        sys.exit(0)
    nodes = gpu_nodes()
    busy = busy_gpus()
    if busy is None:
        print("reclaim: nvidia-smi cannot see the GPUs; not touching any node (run with the GPUs visible)")
        sys.exit(0)
    for gpu, n in enumerate(nodes):
        m = meminfo(n)
        if m["FilePages"] < MIN_FILE_KB:
            print(f"node{n} (GPU{gpu}): FilePages {m['FilePages'] >> 20} GiB, skip")
            continue
        if gpu in busy:
            print(f"node{n} (GPU{gpu}): compute process present, skip ({m['FilePages'] >> 20} GiB page cache left)")
            continue
        budget = m["MemFree"] + m["FilePages"] - MARGIN_KB
        t = time.time()
        subprocess.run(["numactl", f"--membind={n}", sys.executable, __file__, "--child", str(n), str(budget)],
                       check=False)
        print(f"node{n} (GPU{gpu}): {time.time() - t:.1f}s, FilePages after {meminfo(n)['FilePages'] >> 20} GiB")
