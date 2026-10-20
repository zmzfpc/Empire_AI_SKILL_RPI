---
name: empireai
description: >-
  Run and manage work on the Empire AI clusters as an RPI user: Alpha
  (alpha1.empire-ai.org; x86 H100/H200/RTX PRO 6000, plus the Arm `grace` CPU
  partition) and Beta (beta.empireai.edu; Arm GB200 NVL72, NGC containers via
  Pyxis). Covers finding the `rp_<pi>_<project>` account, writing and submitting
  sbatch/srun jobs, choosing a partition and QoS (test/standard/long/priority/burst),
  estimating and checking Service Units (SU, ColdFront, `checksu`), storage paths
  and what they cost, job priority and fairshare (`sprio`, `sshare`), and decoding
  pending reasons and submission errors. Use whenever the user mentions Empire AI
  or EmpireAI, alpha1 or beta.empireai.edu, B200/GB200 or H100 Slurm jobs on these
  hosts, `beta_test`, ColdFront, `checksu` or SU, or asks why a job there is
  pending, failed, or cost what it did.
---

# Empire AI: Alpha, Grace and Beta

The facts below were verified live on 2026-10-19. QoS limits, node counts and site policy change.
When a live command disagrees with this file, trust the live output and tell the user what changed.

Placeholders: `rp_<pi>_<project>` is the user's project account, `<user>` their Empire AI username.

## 1. Orient first

These are cheap and read-only. Run them before writing or submitting anything.

```bash
hostname; uname -m      # aarch64 + b*-mgmt-* = beta login node; x86_64 + alpha1 = alpha login node
sinfo -s                # beta lists beta/beta_test/cdmm; alpha lists alpha/grace/cpu
sacctmgr show assoc where user=$USER format=Account%24,User%8,QOS%46,DefaultQOS%8
id -Gn | tr ' ' '\n' | grep '^rp_'     # each project account is also a Unix group
```

- **Two separate Slurm clusters.** Alpha (Slurm 23.02, also schedules `grace`) and beta (Slurm 25.05) have separate
  controllers, queues, fairshare trees and QoS limits. `squeue` on beta never shows alpha jobs. Both report
  `ClusterName=slurm`, so tell them apart by host, `uname -m` and partition names.
- **Shared between them:** `/mnt/home/$USER` (same directory), `/projects`, SSH keys, ColdFront SU, account names.
- **The account is the user's decision**, because it decides whose SU are spent. One `rp_` account: use it. Several:
  ask which project pays. None: the PI has not added them to a project in ColdFront yet, and nothing can be charged
  until they do. Two other accounts may appear: `rpi_beta_test` (beta early access, some users only) and bare `rpi`
  on alpha (free `burst` QoS only).
- If the user's project already has sbatch scripts, read them and follow their conventions before writing new ones.

## 2. Hard rules

1. **Always pass `-A rp_<pi>_<project>`.** Alpha rejects jobs without it ("Account must be specified"). Beta silently
   uses the default account (`sacctmgr show user $USER`), which can charge the wrong project.
2. **Always pass `--time`.** The default on partitions `alpha` and `beta` is 1 h, and jobs without `--time` are killed
   at exactly 1:00:00. Ask for a realistic time, not the maximum: backfill starts short jobs sooner.
3. **Beta is aarch64 and has no CUDA or PyTorch modules.** Run GPU work inside an NGC container
   (`--container-image='nvcr.io#nvidia/pytorch:26.02-py3'`). Use NGC tags from 2025 or later, since `24.12` and older
   lack Blackwell support. On `26.02`, a warning that `sm_100` is not compatible is expected and harmless. Python
   environments built on alpha (x86) do not run on beta, so keep one environment per architecture.
4. **Partition `beta` gives whole 4-GPU nodes, takes batch jobs only, and every QoS there needs at least 4 GPUs.**
   `salloc` and bare `srun` on `beta` are rejected. Anything with 1 to 3 GPUs, anything interactive, and debugging
   goes to `-p beta_test --qos=test` (at most 2 h, 1 to 8 GPUs, shared nodes, half price). `--qos=test` is not
   allowed on `-p beta`.
5. **On alpha, a 1-GPU job always lands on an RTX PRO 6000.** For H100 or H200, request `--gres=gpu:2` or more plus
   `--constraint=h100` (or `h200`). Alpha nodes are shared, so set `--cpus-per-task` and `--mem` (default
   19,800 MB per CPU).
6. **Login nodes are for editing, building and submitting.** No training or inference there (they have no GPUs).
   A login node's `/tmp` is invisible to compute nodes, and beta has several login nodes behind one hostname, so
   stage job inputs under `/mnt/home` or `/projects`.
7. **Submitting spends the user's money.** Before submitting, state the partition, QoS, GPUs, time limit and the
   worst-case SU (section 4), validate with `sbatch --test-only`, and get the user's go-ahead unless they already
   gave it. Do not pick `priority` unless the user asks or a deadline needs it. Never request `burst`: the system
   assigns it.
8. **End batch scripts with `exit $rc` of the payload**, so `--dependency=afterok:<id>` chains mean something.
9. **Do not edit a payload script while a job runs it.** `sbatch` snapshots the batch script at submission, but a
   script it calls (`bash run.sh`) is read by bash incrementally, so editing it mid-run breaks the running job.
   Write a new copy instead.
10. **Cancel only jobs you were asked to cancel**, by job ID. Confirm before anything broad such as
    `scancel -u $USER`.

## 3. Choosing cluster, partition and QoS

| Job | Where | QoS |
|---|---|---|
| smoke test, debugging, eval that fits in 2 h, 1-8 B200 | beta, `-p beta_test` | `test` (0.5x) |
| interactive GPU shell on beta | beta, `-p beta_test` | `test` |
| production, at most 48 h, whole nodes | beta, `-p beta` | `standard` (1x, the default for `rp_` accounts) |
| long and not urgent, at most 7 days | beta `-p beta`, or alpha | `long` (0.5x, lowest paid priority, starts mostly by backfill) |
| hard deadline | either | `priority` (2x SU, and it burns fairshare twice as fast) |
| H100/H200 work or x86-only software | alpha, `-p alpha --gres=gpu:>=2 --constraint=h100` | `test`/`standard`/`long`/`priority` |
| interactive shell on alpha | alpha, `-p alpha` | `interactive` (1 session, 2 h) |
| Arm CPU-only work | alpha, `-p grace` (billed 0.5 SU per node-hour) | as above |

Key limits. Beta caps GPUs **per job**; alpha caps GPUs **per user**, summed over the user's running jobs.

| QoS | Beta: max wall · GPUs per job · running/submitted per user | Alpha: max wall · per-user GPU cap · running/submitted | SU multiplier |
|---|---|---|---|
| `priority` | 24 h · 4-72 · 30/50 | 24 h · 64 · 30/50 | 2.0 |
| `test` | 2 h · 1-8 · 5/10 (partition `beta_test` only) | 2 h · 8 · 10/20 | 0.5 |
| `standard` | 48 h · 4-36 · 30/50 | 48 h · 32 · 30/50 | 1.0 |
| `long` | 7 d · 4-36 · 20/30 | 7 d · 32 · 20/30 | 0.5 |
| `interactive` | accepted by no beta partition | 2 h · 4 · 1 | 1.0 |
| `burst` | system-assigned when a project is out of SU; free, lowest priority, preemptable | same | 0 |

Re-check before planning around a number:
`sacctmgr show qos format=Name%12,Priority,MaxWall,MinTRES%14,MaxTRES%14,MaxTRESPU%32,MaxJobsPU,MaxSubmitPU,UsageFactor`.
Partitions, preemption and the raw snapshot: [references/qos-and-limits.md](references/qos-and-limits.md).

## 4. Cost in Service Units

```
SU = GPU-hours x rate x QoS multiplier        1 SU = $0.50 (RPI FOCI)
rate:  beta B200 2 SU/GPU-h · alpha GPU 1 SU/GPU-h · grace 0.5 SU/node-hour
QoS:   priority 2 · standard, interactive 1 · test, long 0.5 · burst 0
storage (home, projects, scratch alike): 8.333 SU per TB-month, no quota, no purge
```

- On partition `beta` the whole node (4 GPUs) is billed, whatever the job uses.
- Worst case for a job = its `--time`. Examples: one beta node for 12 h costs 192 SU on `priority`, 96 on `standard`,
  48 on `long`; 4 GPUs for 2 h on `test` cost 8; 1 GPU for 15 min on `test` costs 0.25; 8 H100 for 24 h on alpha
  `standard` cost 192.
- **Slurm does not know SU.** `sshare`'s `RawUsage` is decayed fairshare usage and `sreport` gives raw GPU-hours;
  neither is the balance. The ledger is ColdFront (<https://coldfront.empireai.edu/>). `checksu` on either login node
  prints ColdFront's numbers, at most about 15 minutes old.
- A project that runs out of SU is restricted to `burst`; running jobs are not killed, and the PI requests more SU.
- Per-QoS estimate of the user's own spend from `sacct`: `scripts/su_estimate.sh <account> [start-date]`.

`checksu` forms, the formula table and a worked bill: [references/su-and-coldfront.md](references/su-and-coldfront.md).

## 5. Writing and submitting jobs

Templates (copy into the user's project, replace `rp_<pi>_<project>`, then `sbatch --test-only` before the real
submit):

| File | Use it for |
|---|---|
| [templates/beta_test_1gpu.sbatch](templates/beta_test_1gpu.sbatch) | a first beta job: 1 B200 on `beta_test`, PyTorch container, prints arch and GPU name |
| [templates/beta_node.sbatch](templates/beta_node.sbatch) | full-node production job on `beta` (`torchrun`, 4 GPUs) |
| [templates/beta_lane.sbatch](templates/beta_lane.sbatch) | a reusable 4-GPU runner for any payload script, with the GB200 fixes from section 7 built in; one script for both lanes |
| [templates/alpha_h100.sbatch](templates/alpha_h100.sbatch) | an alpha job on 2 H100 |
| [scripts/numa_exec.sh](scripts/numa_exec.sh), [scripts/reclaim_hbm_pagecache.py](scripts/reclaim_hbm_pagecache.py) | helpers that `beta_lane.sbatch` calls; copy them into the project's `tools/` |

Options on the `sbatch` command line override the `#SBATCH` lines, so one script serves both beta lanes:

```bash
sbatch -A rp_<pi>_<project> --job-name=smoke beta_lane.sbatch runs/eval.sh                       # test lane (script defaults)
sbatch -A rp_<pi>_<project> -p beta --qos=standard --time=12:00:00 --job-name=full \
       --export=ALL,MODE=full beta_lane.sbatch runs/eval.sh                                      # whole node on beta
```

Container mounts: `--container-mounts=/mnt/home/$USER:/mnt/home/$USER,/projects:/projects` and
`--container-workdir="$PWD"`. The first pull of an image (about 15 GB) takes a few minutes.

Interactive work:

```bash
# beta: only on beta_test with the test QoS; start it inside tmux, the session dies with the SSH connection
srun -A rp_<pi>_<project> -p beta_test --qos=test --gres=gpu:1 -c 16 --mem=160G -t 01:00:00 \
     --container-image='nvcr.io#nvidia/pytorch:26.02-py3' \
     --container-mounts=/mnt/home/$USER:/mnt/home/$USER --pty bash
# alpha (a 1-GPU session lands on an RTX PRO 6000)
srun -A rp_<pi>_<project> -p alpha --qos=interactive --gres=gpu:1 -c 8 --mem=64G -t 01:00:00 --pty bash
# a shell inside a job that is already running (the only way onto a compute node)
srun --jobid=<jobid> --overlap --pty bash
```

Other options worth reaching for: `--array=0-99%10` (100 tasks, at most 10 at once, each reads
`$SLURM_ARRAY_TASK_ID`), `--dependency=afterok:<id>`, `--export=ALL,VAR=value`, `--output=%x_%j.out`.

**Runs longer than the wall limit.** Save checkpoints regularly, then either
- chain jobs: `sbatch --dependency=afterok:<previous id> ...`, each resuming from the latest checkpoint (simplest), or
- self-requeue: submit with `--requeue --signal=B:USR1@900`. The batch shell gets USR1 15 minutes before the limit;
  it must run the payload in the background and `wait`, so a `trap '... ; scontrol requeue $SLURM_JOB_ID' USR1` can
  fire. The requeued job reruns the script from the top and must resume from the latest checkpoint. Without `B:`,
  the signal goes to the job steps (the program itself) instead of the batch shell. A requeued job queues again.

Multi-node: `--nodes=N --gres=gpu:4` gives 4N GPUs; the code handles distribution (DDP, FSDP, DeepSpeed, ...).
Beta's 72 nodes are 4 NVL72 racks of 18 (`TopologyPlugin=topology/block`), so a job of up to 18 nodes can stay
inside one NVLink domain. Node names encode the rack: `b2-37-s1-dgx-02-c18` is rack 2, compute tray 18.

## 6. Watching and changing jobs

```bash
squeue --me                                     # state + pending reason (last column)
squeue --me --start                             # scheduler's estimated start times
scontrol show job <id>                          # everything about one job
sacct -j <id> -o JobID,State,ExitCode,Elapsed,MaxRSS
sacct -j <id> -o JobID,Account,QOS,SubmitLine%120   # what it was really submitted with
seff <id>                                       # CPU/memory efficiency after the end (no GPU numbers)
scontrol update JobId=<id> TimeLimit=04:00:00   # users can lower a limit, not raise it
scontrol update JobId=<id> Partition=beta_test  # move a pending job
scontrol hold <id> / scontrol release <id>
```

**`scontrol update JobId=<id> QOS=<new>` resets the time limit to the new QoS's maximum.** Run
`scontrol update JobId=<id> TimeLimit=<needed>` right after, or the job can wait with `QOSMaxWallDurationPerJobLimit`.

Full command list: [references/commands.md](references/commands.md).

## 7. GB200 node hygiene (beta)

- Plan for about 185 GB usable per B200 (189 GB reported). Each node: 4 B200, 2 Grace CPUs (144 Arm cores),
  about 1.5 TB memory.
- **GPU memory "in use" with no process is usually page cache.** Each GPU's HBM is a CPU-less NUMA node, so the
  kernel can park file page cache there (for example model weights an earlier job read). CUDA cannot reclaim it.
  Fix: at job start run `srun -n1 --cpus-per-task="$SLURM_CPUS_PER_TASK" python3 tools/reclaim_hbm_pagecache.py || true`
  on the host (needs the GPUs visible; skips GPUs that run a process; no root), then launch the payload through
  `tools/numa_exec.sh`, which binds memory to the CPU NUMA nodes so new page cache stays out of HBM. `numa_exec.sh`
  silently does nothing if the container has no `numactl`; check with `command -v numactl` inside the image.
- **`beta_test` caps memory at 10,834 MB per CPU.** If `--mem` exceeds `cpus-per-task x 10,834 MB`, Slurm silently
  raises the CPU count (`--mem=768G` with 64 CPUs becomes 73), and every inner `srun` then exits within a second with
  "cpus-per-task set by two different environment variables". Either keep `--mem` under the cap (16 CPUs: 160G;
  64 CPUs: 640G) or `unset SLURM_TRES_PER_TASK` and pass `srun --cpus-per-task="$SLURM_CPUS_PER_TASK"`.
  `beta_lane.sbatch` does both.
- If the user's home is mounted into the container, pip packages in `~/.local` built for another Python or
  architecture can shadow the container's. Set `PYTHONNOUSERSITE=1` when that bites.

## 8. Why is it pending, why did it fail

| Symptom | Cause | Fix |
|---|---|---|
| pending `Priority` | higher-priority jobs ahead | wait, or shorten `--time` to fit a backfill gap |
| pending `Resources` | next in line, nodes still freeing | wait |
| pending `QOSMaxJobsPerUserLimit` | running-job cap of the QoS (`test`: 5 on beta, 10 on alpha) | wait for one to finish |
| pending `QOSMaxGRESPerUser` (alpha) | running jobs already use the per-user GPU cap | wait, or another QoS |
| pending `QOSMaxWallDurationPerJobLimit` | `--time` above the QoS maximum, often after `scontrol update QOS=` | `scontrol update JobId=<id> TimeLimit=...` |
| `Job's QOS not permitted to use this partition` | e.g. `--qos=test` on `-p beta` | `scontrol update JobId=<id> Partition=beta_test` |
| pending `Dependency` / `DependencyNeverSatisfied` | upstream still running / upstream failed | fix it, or `scancel` and resubmit |
| pending `JobHeldUser` | held | `scontrol release <id>` |
| `ReqNodeNotAvail, Reserved for maintenance` | maintenance reservation | wait; `scontrol show res` |
| submit fails: `Job violates accounting/QOS policy`, `QOSMinGRES` (beta) | fewer than 4 GPUs on `beta`, or `--time` over the QoS maximum | 4 GPUs, or `-p beta_test --qos=test` |
| "no interactive jobs allowed in the 'beta' partition" | `salloc` or bare `srun` on `beta` | `-p beta_test --qos=test` |
| "Account must be specified" (alpha) | no `-A` | add `-A rp_<pi>_<project>` |
| killed at exactly 1:00:00 | no `--time` | set `--time` |
| asked for 1 H100 on alpha, got an RTX PRO 6000 | site routing of 1-GPU jobs | 2+ GPUs with `--constraint=h100` |
| inner `srun` dies at once on `beta_test`, two CPU-count variables | `--mem` over the 10,834 MB-per-CPU cap | section 7 |
| `nvidia-smi` shows memory used, no process (beta) | page cache in HBM | section 7 |
| environment works on alpha, crashes on beta | x86 build on Arm | per-arch environment, or an NGC container |
| `module load cuda` / `pytorch` fails on beta | beta modules cover system tools only | NGC container |
| job cannot find a file in `/tmp` | login node `/tmp` is local to that login node | stage under `/mnt/home` or `/projects` |
| job ran under the wrong account | no `-A` on beta | `sacct -j <id> -o Account`; always pass `-A` |
| `burst` job put back in the queue | preempted by a paid QoS (after its first 15 min) | expected for `burst`; checkpoint |

Priority mechanics (QoS dominates; fairshare decides within a QoS; age matters only after days):
[references/priority-fairshare.md](references/priority-fairshare.md).

## 9. Storage

| Path | Visible on | Notes |
|---|---|---|
| `/mnt/home/$USER` | alpha and beta (same directory) | VAST, 15 PB pool; code, configs, environments, data |
| `/projects/rp/<pi>/<project>` | alpha and beta | group `rp_<pi>_<project>`, setgid; data and checkpoints the group shares |
| `/ddn/scratch/rpi/$USER` | beta only | DDN Lustre, 5 TB hard limit per user (`lfs quota -h -u $USER /ddn`); good for big files, bad for millions of small ones |
| `/mnt/lustre/<inst>/$USER` | alpha only | legacy link into `/mnt/home/DDN_Copy/<inst>` |
| `/tmp` | each node separately | job-local scratch only |

No quotas on home or projects and no purge anywhere: everything kept is billed at 8.333 SU per TB-month (1 TB for a
year = 100 SU = $50). Point the user at stale checkpoints and duplicate datasets when cost comes up; `du -sh <dir>`
measures, and the `VAST` row of `checksu` shows what storage has cost. Copy data in with
`rsync -avP ./data/ <user>@beta.empireai.edu:/projects/rp/<pi>/<project>/data/` (visible on both clusters).

## 10. Help

Empire AI help desk: `empireai.freshdesk.com` (UB CCR's page lists `help@empire-ai.org`). Include the job ID and the
exact error text.
